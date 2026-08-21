#!/usr/bin/env python3
"""Compare coverage for non-main core sibling repositories with origin/main.

Usage: ./scripts/repo/compare-test-coverage.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from dataclasses import dataclass
import xml.etree.ElementTree as ET


REPOSITORIES = (
    "service-common",
    "transaction-service",
    "currency-service",
    "permission-service",
    "session-gateway",
    "budget-analyzer-web",
    "ext-authz",
)
BASE_REF = "origin/main"


@dataclass(frozen=True)
class Metric:
    covered: int
    total: int

    @property
    def percent(self) -> float | None:
        if self.total == 0:
            return None
        return self.covered * 100 / self.total


@dataclass(frozen=True)
class Coverage:
    line_label: str
    lines: Metric
    branches: Metric | None


@dataclass(frozen=True)
class Comparison:
    repository: str
    branch: str
    base: Coverage
    candidate: Coverage


def git(repo: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ("git", "-C", str(repo), *arguments),
        check=False,
        capture_output=True,
        text=True,
    )


def extract_revision(repo: Path, revision: str, destination: Path) -> None:
    destination.mkdir(parents=True)
    archive = subprocess.Popen(
        ("git", "-C", str(repo), "archive", "--format=tar", revision),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert archive.stdout is not None
    extract = subprocess.run(
        ("tar", "-xf", "-", "-C", str(destination)),
        check=False,
        stdin=archive.stdout,
        capture_output=True,
        text=False,
    )
    archive.stdout.close()
    archive_stderr = b""
    if archive.stderr is not None:
        archive_stderr = archive.stderr.read()
    archive_status = archive.wait()

    if archive_status != 0:
        message = archive_stderr.decode(errors="replace").strip()
        raise RuntimeError(f"git archive failed: {message}")
    if extract.returncode != 0:
        message = extract.stderr.decode(errors="replace").strip()
        raise RuntimeError(f"tar extraction failed: {message}")


def run_logged(command: tuple[str, ...], directory: Path, log_path: Path) -> int:
    environment = os.environ.copy()
    environment["CI"] = "true"
    with log_path.open("a", encoding="utf-8") as log:
        log.write(f"$ {' '.join(command)}\n")
        log.flush()
        result = subprocess.run(
            command,
            cwd=directory,
            check=False,
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )
    return result.returncode


def show_log_tail(log_path: Path, lines: int = 30) -> None:
    try:
        content = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return
    for line in content[-lines:]:
        print(f"    {line}", file=sys.stderr)


def sum_jacoco_reports(directory: Path) -> Coverage | None:
    reports = sorted(
        directory.glob("**/build/reports/jacoco/test/jacocoTestReport.xml")
    )
    if not reports:
        return None

    totals = {"LINE": [0, 0], "BRANCH": [0, 0]}
    for report in reports:
        root = ET.parse(report).getroot()
        counters = {counter.attrib["type"]: counter for counter in root.findall("counter")}
        for counter_type in totals:
            counter = counters.get(counter_type)
            if counter is None:
                continue
            missed = int(counter.attrib["missed"])
            covered = int(counter.attrib["covered"])
            totals[counter_type][0] += covered
            totals[counter_type][1] += missed + covered

    return Coverage(
        line_label="lines",
        lines=Metric(*totals["LINE"]),
        branches=Metric(*totals["BRANCH"]),
    )


def read_vitest_report(directory: Path) -> Coverage | None:
    report = directory / "coverage" / "coverage-summary.json"
    if not report.is_file():
        return None

    summary = json.loads(report.read_text(encoding="utf-8"))["total"]
    lines = summary["lines"]
    branches = summary["branches"]
    return Coverage(
        line_label="lines",
        lines=Metric(covered=int(lines["covered"]), total=int(lines["total"])),
        branches=Metric(
            covered=int(branches["covered"]), total=int(branches["total"])
        ),
    )


def read_go_report(directory: Path) -> Coverage | None:
    report = directory / "coverage.out"
    if not report.is_file():
        return None

    covered = 0
    total = 0
    for line in report.read_text(encoding="utf-8").splitlines()[1:]:
        fields = line.split()
        if len(fields) != 3:
            continue
        statements = int(fields[1])
        count = int(fields[2])
        total += statements
        if count > 0:
            covered += statements
    return Coverage(
        line_label="statements",
        lines=Metric(covered=covered, total=total),
        branches=None,
    )


def build_coverage(directory: Path, log_path: Path) -> tuple[Coverage | None, int]:
    if (directory / "gradlew").is_file():
        status = run_logged(
            ("./gradlew", "test", "jacocoTestReport", "--console=plain"),
            directory,
            log_path,
        )
        return sum_jacoco_reports(directory), status

    if (directory / "package.json").is_file():
        install_status = run_logged(
            ("npm", "ci", "--no-audit", "--no-fund"), directory, log_path
        )
        if install_status != 0:
            return None, install_status
        status = run_logged(("npm", "run", "test:coverage"), directory, log_path)
        return read_vitest_report(directory), status

    if (directory / "go.mod").is_file():
        status = run_logged(
            ("go", "test", "-coverprofile=coverage.out", "./..."),
            directory,
            log_path,
        )
        return read_go_report(directory), status

    return None, 2


def format_metric(metric: Metric | None) -> str:
    if metric is None or metric.percent is None:
        return "n/a"
    return f"{metric.covered}/{metric.total} ({metric.percent:.2f}%)"


def format_percent_delta(base: Metric | None, candidate: Metric | None) -> str:
    if (
        base is None
        or candidate is None
        or base.percent is None
        or candidate.percent is None
    ):
        return "n/a"
    return f"{candidate.percent - base.percent:+.2f}"


def format_count_delta(base: Metric | None, candidate: Metric | None) -> str:
    if base is None or candidate is None:
        return "n/a"
    return f"{candidate.covered - base.covered:+d}"


def format_total_delta(base: Metric | None, candidate: Metric | None) -> str:
    if base is None or candidate is None:
        return "n/a"
    return f"{candidate.total - base.total:+d}"


def print_metric_table(
    title: str,
    comparisons: list[Comparison],
    metric_name: str,
) -> None:
    print(f"\n{title}")
    print(
        f"{'Repository':<22} {'Branch':<22} {'origin/main':>22} {'HEAD':>22} "
        f"{'delta pp':>9} {'covered':>9} {'total':>8}"
    )
    print("-" * 120)
    for comparison in comparisons:
        base_metric = getattr(comparison.base, metric_name)
        candidate_metric = getattr(comparison.candidate, metric_name)
        print(
            f"{comparison.repository:<22} {comparison.branch:<22} "
            f"{format_metric(base_metric):>22} {format_metric(candidate_metric):>22} "
            f"{format_percent_delta(base_metric, candidate_metric):>9} "
            f"{format_count_delta(base_metric, candidate_metric):>9} "
            f"{format_total_delta(base_metric, candidate_metric):>8}"
        )


def main() -> int:
    if len(sys.argv) != 1:
        print("error: compare-test-coverage.py does not accept arguments", file=sys.stderr)
        return 2

    repository_root = Path(__file__).resolve().parents[2]
    workspace_root = repository_root.parent
    comparisons: list[Comparison] = []
    failures: list[str] = []
    selected = 0

    print(f"Comparing non-main repositories with the local {BASE_REF} ref.")
    print("No repositories will be fetched, checked out, or modified.\n")

    with tempfile.TemporaryDirectory(prefix="budget-analyzer-coverage-") as temp:
        temporary_root = Path(temp)
        for repository_name in REPOSITORIES:
            repo = workspace_root / repository_name
            if not repo.is_dir() or git(repo, "rev-parse", "--git-dir").returncode != 0:
                continue

            branch_result = git(repo, "symbolic-ref", "--quiet", "--short", "HEAD")
            if branch_result.returncode != 0:
                continue
            branch = branch_result.stdout.strip()
            if branch in {"main", "master"}:
                continue

            selected += 1
            dirty = git(repo, "status", "--porcelain", "--untracked-files=normal")
            if dirty.returncode != 0 or dirty.stdout.strip():
                message = f"{repository_name}: working tree is not clean"
                print(f"ERROR: {message}", file=sys.stderr)
                failures.append(message)
                continue

            base_result = git(repo, "rev-parse", "--verify", f"{BASE_REF}^{{commit}}")
            head_result = git(repo, "rev-parse", "--verify", "HEAD^{commit}")
            if base_result.returncode != 0 or head_result.returncode != 0:
                message = f"{repository_name}: cannot resolve {BASE_REF} or HEAD"
                print(f"ERROR: {message}", file=sys.stderr)
                failures.append(message)
                continue

            base_sha = base_result.stdout.strip()
            head_sha = head_result.stdout.strip()
            print(
                f"[{repository_name}] {branch}: "
                f"{BASE_REF} {base_sha[:8]} -> HEAD {head_sha[:8]}"
            )

            repository_temp = temporary_root / repository_name
            base_directory = repository_temp / "base"
            candidate_directory = repository_temp / "candidate"
            try:
                extract_revision(repo, base_sha, base_directory)
                extract_revision(repo, head_sha, candidate_directory)
            except RuntimeError as error:
                message = f"{repository_name}: {error}"
                print(f"ERROR: {message}", file=sys.stderr)
                failures.append(message)
                continue

            print("  building origin/main coverage...")
            base_log = repository_temp / "base.log"
            base_coverage, base_status = build_coverage(base_directory, base_log)
            if base_status != 0 or base_coverage is None:
                message = f"{repository_name}: origin/main coverage build failed"
                print(f"ERROR: {message}", file=sys.stderr)
                show_log_tail(base_log)
                failures.append(message)
                continue

            print("  building HEAD coverage...")
            candidate_log = repository_temp / "candidate.log"
            candidate_coverage, candidate_status = build_coverage(
                candidate_directory, candidate_log
            )
            if candidate_status != 0 or candidate_coverage is None:
                message = f"{repository_name}: HEAD coverage build failed"
                print(f"ERROR: {message}", file=sys.stderr)
                show_log_tail(candidate_log)
                failures.append(message)
                continue

            comparisons.append(
                Comparison(
                    repository=repository_name,
                    branch=branch,
                    base=base_coverage,
                    candidate=candidate_coverage,
                )
            )

    if selected == 0:
        print("No core sibling repositories are currently on a non-main branch.")
        return 0

    if comparisons:
        line_label = (
            "Line / statement coverage"
            if any(item.base.line_label == "statements" for item in comparisons)
            else "Line coverage"
        )
        print_metric_table(line_label, comparisons, "lines")
        print_metric_table("Branch coverage", comparisons, "branches")
        print("\nDeltas are HEAD minus origin/main; 'delta pp' is percentage points.")

    if failures:
        print("\nFailures:", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
