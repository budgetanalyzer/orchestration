#!/usr/bin/env python3
"""Prove an unused OAuth callback requires the initiating browser's binding."""

from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import parse_qs, urljoin, urlsplit

import httpx

REPO_ROOT = Path(__file__).resolve().parents[2]
API_TEST_ROOT = REPO_ROOT.parent / "budget-analyzer-api-tests"
sys.path.insert(0, str(API_TEST_ROOT / "src"))

from api_tests.auth import load_existing_browser_credentials  # noqa: E402
from api_tests.browser_login import fill_hosted_login_form, read_session_cookie  # noqa: E402
from api_tests.config import load_environment  # noqa: E402
from api_tests.session_gateway_assertions import assert_logout_redirect  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402

LOCAL_ORIGIN = "https://app.budgetanalyzer.localhost"
INITIATION_PATH = "/oauth2/authorization/idp"
CALLBACK_PATH = "/login/oauth2/code/idp"
BINDING_COOKIE = "__Host-BA_OAUTH_BINDING"


class ProofFailure(RuntimeError):
    """A diagnostic containing only fixed labels and HTTP status codes."""


def require_status(response: httpx.Response, expected: set[int], label: str) -> None:
    if response.status_code not in expected:
        raise ProofFailure(f"{label} returned HTTP {response.status_code}")


def main() -> None:
    config = load_environment("local", base_dir=API_TEST_ROOT / "environments")
    if config.environment_type != "local" or config.origin != LOCAL_ORIGIN:
        raise ProofFailure(
            "browser proof requires the exact supported local application origin"
        )
    credentials = load_existing_browser_credentials(
        config, "primary", credential_path=API_TEST_ROOT / ".env.local"
    )
    timeout_ms = int(config.timeouts.eventually_seconds * 1000)

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            # Keep callback delivery on the page's intercepted network path.
            context = browser.new_context(service_workers="block")
            try:
                page = context.new_page()
                cdp = context.new_cdp_session(page)
                intercepted = 0
                failures: list[Exception] = []

                def intercept_callback(event: dict) -> None:
                    nonlocal intercepted
                    intercepted += 1
                    try:
                        if intercepted != 1:
                            raise ProofFailure("unexpected additional callback")
                        query = parse_qs(urlsplit(event["request"]["url"]).query)
                        if (
                            not query.get("code")
                            or not query.get("state")
                            or "error" in query
                        ):
                            raise ProofFailure(
                                "hosted login did not supply a code and state"
                            )
                        if any(
                            c["name"] == config.session_cookie_name
                            for c in context.cookies()
                        ):
                            raise ProofFailure(
                                "initiating browser already has a session"
                            )

                        # This URL has never reached the gateway. No browser
                        # headers or cookies are copied to this second client.
                        with httpx.Client(
                            base_url=LOCAL_ORIGIN,
                            follow_redirects=False,
                            timeout=config.timeouts.request_seconds,
                        ) as unbound:
                            response = unbound.get(event["request"]["url"])
                            require_status(response, {302}, "unbound callback")
                            failure_url = urlsplit(
                                urljoin(
                                    LOCAL_ORIGIN, response.headers.get("location", "")
                                )
                            )
                            if (
                                f"{failure_url.scheme}://{failure_url.netloc}"
                                != LOCAL_ORIGIN
                                or failure_url.path != "/login"
                                or parse_qs(failure_url.query).get("error")
                                != ["auth_failed"]
                            ):
                                raise ProofFailure(
                                    "unbound callback lacked the controlled login failure"
                                )
                            if any(
                                cookie.name == config.session_cookie_name
                                for cookie in response.cookies.jar
                            ) or any(
                                cookie.name == config.session_cookie_name
                                for cookie in unbound.cookies.jar
                            ):
                                raise ProofFailure(
                                    "unbound callback issued a session cookie"
                                )
                            require_status(
                                unbound.get("/auth/v1/user"),
                                {401},
                                "unbound user read",
                            )
                            require_status(
                                unbound.post("/auth/v1/session"),
                                {401},
                                "unbound heartbeat",
                            )
                        print(
                            "Unused callback without binding: controlled rejection; no session."
                        )
                    except Exception as exc:  # noqa: BLE001 - sanitize all browser/library failures
                        failures.append(exc)
                        cdp.send(
                            "Fetch.failRequest",
                            {"requestId": event["requestId"], "errorReason": "Aborted"},
                        )
                        return

                    # Preserve the original top-level cross-site navigation.
                    # Success now also proves the rejected request did not
                    # consume state/code and that SameSite=Lax reaches the callback.
                    cdp.send("Fetch.continueRequest", {"requestId": event["requestId"]})

                # Playwright route handlers do not intercept subsequent redirect
                # hops. CDP Fetch pauses the actual cross-site callback request.
                cdp.on("Fetch.requestPaused", intercept_callback)
                cdp.send(
                    "Fetch.enable",
                    {
                        "patterns": [
                            {
                                "urlPattern": f"{LOCAL_ORIGIN}{CALLBACK_PATH}?*",
                                "requestStage": "Request",
                            }
                        ]
                    },
                )
                page.goto(
                    f"{LOCAL_ORIGIN}{INITIATION_PATH}?returnUrl=%2F",
                    wait_until="domcontentloaded",
                    timeout=timeout_ms,
                )
                if page.url.startswith(LOCAL_ORIGIN):
                    raise ProofFailure(
                        "login did not reach the hosted identity provider"
                    )
                bindings = [c for c in context.cookies() if c["name"] == BINDING_COOKIE]
                if len(bindings) != 1 or not (
                    bindings[0]["secure"]
                    and bindings[0]["httpOnly"]
                    and bindings[0]["sameSite"] == "Lax"
                    and bindings[0]["path"] == "/"
                    and bindings[0]["domain"] == urlsplit(LOCAL_ORIGIN).hostname
                ):
                    raise ProofFailure(
                        "initiation lacks the expected secure browser binding cookie"
                    )
                try:
                    fill_hosted_login_form(page, credentials, timeout_ms=timeout_ms)
                    page.wait_for_url(
                        f"{LOCAL_ORIGIN}/", wait_until="networkidle", timeout=timeout_ms
                    )
                finally:
                    if failures:
                        raise failures[0]
                if intercepted != 1:
                    raise ProofFailure(
                        "the browser did not traverse the intercepted callback"
                    )
                session = read_session_cookie(context, config.session_cookie_name)
                with httpx.Client(
                    base_url=LOCAL_ORIGIN,
                    cookies={session.cookie_name: session.cookie_value},
                    follow_redirects=False,
                    timeout=config.timeouts.request_seconds,
                ) as authenticated:
                    try:
                        require_status(
                            authenticated.get("/auth/v1/user"), {200}, "user read"
                        )
                        require_status(
                            authenticated.post("/auth/v1/session"), {200}, "heartbeat"
                        )
                    finally:
                        logout = authenticated.post("/logout")
                        require_status(logout, {303}, "logout")
                        assert_logout_redirect(logout, config)
            finally:
                context.close()
        finally:
            browser.close()

    print(
        "OAuth browser binding proof succeeded: the same callback completed in the "
        "initiating browser; user read, heartbeat, and logout passed."
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - sanitize all browser/library failures
        # Library exceptions can contain callback URLs, cookies, or credentials.
        # Never print their messages, tracebacks, browser traces, or screenshots.
        detail = str(exc) if isinstance(exc, ProofFailure) else type(exc).__name__
        print(f"ERROR: OAuth browser binding proof failed: {detail}", file=sys.stderr)
        raise SystemExit(1) from None
