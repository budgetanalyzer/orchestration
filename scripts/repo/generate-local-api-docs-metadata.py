#!/usr/bin/env python3
"""Generate local Tilt /api-docs runtime metadata from sibling checkouts.

Usage: python3 -I scripts/repo/generate-local-api-docs-metadata.py
           [--output PATH] [--repos-parent DIR]

Reads sibling repositories with read-only git commands and file reads only.
The output is written only when its rendered content changes.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ORCHESTRATION_REPOSITORY = "orchestration"
SHARED_LIBRARY_REPOSITORY = "service-common"
REPOSITORIES = (
    "transaction-service",
    "currency-service",
    "permission-service",
    "session-gateway",
    "budget-analyzer-web",
    "ext-authz",
)
GRADLE_VERSION_PATTERN = re.compile(r'^\s*version\s*=\s*"([^"]+)"', re.MULTILINE)


def git(repo: Path, *args: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def parse_describe(output: str | None) -> tuple[str | None, int | None]:
    if not output:
        return None, None
    parts = output.rsplit("-", 2)
    if len(parts) != 3 or not parts[1].isdigit() or not parts[2].startswith("g"):
        return None, None
    return parts[0], int(parts[1])


def format_version(tag: str | None, commits_since_tag: int | None) -> str:
    if tag is None or commits_since_tag is None:
        return "untagged"
    if commits_since_tag == 0:
        return tag
    return f"{tag}+{commits_since_tag}"


def repo_state(repo: Path, repository: str) -> dict:
    if not repo.is_dir() or git(repo, "rev-parse", "--git-dir") is None:
        return {
            "repository": repository,
            "status": "missing-repo",
            "version": None,
            "tag": None,
            "commitsSinceTag": None,
            "commit": None,
            "shortCommit": None,
            "branch": None,
            "commitDate": None,
            "dirty": False,
        }

    tag, commits_since_tag = parse_describe(git(repo, "describe", "--tags", "--long"))
    branch = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
    status_output = git(repo, "status", "--porcelain", "--untracked-files=normal")
    return {
        "repository": repository,
        "status": "ok",
        "version": format_version(tag, commits_since_tag),
        "tag": tag,
        "commitsSinceTag": commits_since_tag,
        "commit": git(repo, "rev-parse", "HEAD") or None,
        "shortCommit": git(repo, "rev-parse", "--short", "HEAD") or None,
        "branch": branch or "detached",
        "commitDate": git(repo, "log", "-1", "--format=%cs") or None,
        "dirty": bool(status_output),
    }


def declared_service_common(repo: Path) -> str | None:
    versions_file = repo / "gradle" / "libs.versions.toml"
    if not versions_file.is_file():
        return None
    with versions_file.open("rb") as handle:
        versions = tomllib.load(handle).get("versions", {})
    value = versions.get("serviceCommon")
    return str(value) if value is not None else None


def local_service_common_version(repo: Path) -> str | None:
    build_file = repo / "build.gradle.kts"
    if not build_file.is_file():
        return None
    match = GRADLE_VERSION_PATTERN.search(build_file.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def build_metadata(repos_parent: Path) -> dict:
    shared_repo = repos_parent / SHARED_LIBRARY_REPOSITORY
    shared_version = local_service_common_version(shared_repo)
    shared_library = repo_state(shared_repo, SHARED_LIBRARY_REPOSITORY)
    shared_library["version"] = shared_version

    repositories = {}
    for name in REPOSITORIES:
        repo = repos_parent / name
        state = repo_state(repo, name)
        declared = declared_service_common(repo) if repo.is_dir() else None
        if declared is not None:
            state["serviceCommon"] = {
                "declared": declared,
                "matchesLocalCheckout": shared_version is not None and declared == shared_version,
            }
        repositories[name] = state

    return {
        "schemaVersion": 3,
        "deployment": {
            "id": "tilt-local-development",
            "environment": "local-development",
            "runtime": "tilt",
        },
        "orchestration": repo_state(ROOT, ORCHESTRATION_REPOSITORY),
        "sharedLibrary": shared_library,
        "repositories": repositories,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / ".tilt" / "api-docs" / "release-metadata.json",
    )
    parser.add_argument("--repos-parent", type=Path, default=ROOT.parent)
    args = parser.parse_args()

    rendered = json.dumps(build_metadata(args.repos_parent.resolve()), indent=2) + "\n"
    output = args.output
    output.parent.mkdir(parents=True, exist_ok=True)
    if not output.exists() or output.read_text(encoding="utf-8") != rendered:
        output.write_text(rendered, encoding="utf-8")


if __name__ == "__main__":
    main()
