#!/usr/bin/env python3
"""Focused browser proof that initiation exhaustion does not consume callback capacity."""

from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import urlsplit

import httpx


REPO_ROOT = Path(__file__).resolve().parents[2]
API_TEST_ROOT = REPO_ROOT.parent / "budget-analyzer-api-tests"
sys.path.insert(0, str(API_TEST_ROOT / "src"))

from api_tests.auth import load_existing_browser_credentials  # noqa: E402
from api_tests.browser_login import (  # noqa: E402
    fill_hosted_login_form,
    read_session_cookie,
)
from api_tests.config import load_environment  # noqa: E402
from api_tests.logging import redact_sensitive_text  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402


LOCAL_ORIGIN = "https://app.budgetanalyzer.localhost"
INITIATION_PATH = "/oauth2/authorization/idp"
CALLBACK_PATH = "/login/oauth2/code/idp"
INITIATION_REQUESTS = 35
INITIATION_POLICY = "login-initiation"


def require_status(response: httpx.Response, expected: set[int], label: str) -> None:
    if response.status_code not in expected:
        raise RuntimeError(f"{label} returned HTTP {response.status_code}")


def main() -> None:
    config = load_environment("local", base_dir=API_TEST_ROOT / "environments")
    if config.environment_type != "local" or config.origin != LOCAL_ORIGIN:
        raise RuntimeError("browser proof requires the exact supported local application origin")

    credentials = load_existing_browser_credentials(
        config,
        "primary",
        credential_path=API_TEST_ROOT / ".env.local",
    )
    timeout_ms = int(config.timeouts.eventually_seconds * 1000)
    callback_statuses: list[int] = []

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True)
        try:
            context = browser.new_context()
            try:
                page = context.new_page()

                def observe_response(response: object) -> None:
                    url = getattr(response, "url", "")
                    status = getattr(response, "status", None)
                    if (
                        isinstance(url, str)
                        and isinstance(status, int)
                        and url.startswith(LOCAL_ORIGIN)
                        and urlsplit(url).path == CALLBACK_PATH
                    ):
                        callback_statuses.append(status)

                page.on("response", observe_response)
                page.goto(
                    f"{LOCAL_ORIGIN}{INITIATION_PATH}?returnUrl=%2F",
                    wait_until="domcontentloaded",
                    timeout=timeout_ms,
                )
                if page.url.startswith(LOCAL_ORIGIN):
                    raise RuntimeError("original login did not reach the hosted identity provider")

                # This client deliberately has a separate cookie jar from the browser.
                # It shares the VM source address but cannot overwrite the original OAuth
                # transaction's cookies or state.
                rejected = 0
                with httpx.Client(
                    base_url=LOCAL_ORIGIN,
                    follow_redirects=False,
                    timeout=config.timeouts.request_seconds,
                ) as extra_initiations:
                    for index in range(INITIATION_REQUESTS):
                        response = extra_initiations.get(
                            INITIATION_PATH,
                            params={"rate_limit_probe": index},
                        )
                        if response.status_code == 429:
                            marker = response.headers.get("x-local-rate-limit-policy")
                            if marker != INITIATION_POLICY:
                                raise RuntimeError(
                                    "browser-client initiation rejection lacked the expected policy marker"
                                )
                            rejected += 1
                        elif response.status_code != 302:
                            raise RuntimeError(
                                "extra browser-client initiation returned an unexpected status"
                            )
                if rejected == 0:
                    raise RuntimeError(
                        "extra browser-client initiations did not exhaust the initiation allowance"
                    )

                fill_hosted_login_form(page, credentials, timeout_ms=timeout_ms)
                page.wait_for_url(
                    f"{LOCAL_ORIGIN}/**",
                    wait_until="networkidle",
                    timeout=timeout_ms,
                )
                if not callback_statuses:
                    raise RuntimeError("OAuth completion did not traverse the application callback")
                if callback_statuses[-1] == 429:
                    raise RuntimeError("OAuth callback consumed the exhausted initiation allowance")

                session = read_session_cookie(context, config.session_cookie_name)
                with httpx.Client(
                    base_url=LOCAL_ORIGIN,
                    cookies={session.cookie_name: session.cookie_value},
                    follow_redirects=False,
                    timeout=config.timeouts.request_seconds,
                ) as authenticated:
                    require_status(
                        authenticated.get("/auth/v1/user"),
                        {200},
                        "authenticated user read",
                    )
                    require_status(
                        authenticated.get("/auth/v1/session"),
                        {200},
                        "authenticated heartbeat",
                    )
                    require_status(
                        authenticated.get("/logout"),
                        {302, 303},
                        "authenticated logout",
                    )
            finally:
                context.close()
        finally:
            browser.close()

    print(
        "Browser callback isolation proof succeeded: initiation exhausted; "
        "original callback, user read, heartbeat, and logout completed."
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # Keep credentials and OAuth values out of diagnostics.
        print(
            f"ERROR: browser callback isolation proof failed: {redact_sensitive_text(str(exc))}",
            file=sys.stderr,
        )
        raise SystemExit(1) from None
