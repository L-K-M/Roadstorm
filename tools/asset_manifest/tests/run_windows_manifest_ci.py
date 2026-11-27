#!/usr/bin/env python3
"""Windows-host CI runner for the asset manifest validator.

Ownership: tools/asset_manifest/** (PLAN.md M0 provenance manifest tooling).

This exists so a Windows job cannot report acceptance while the native
guarded-open tests silently skip. It runs, in order:

1. the complete ``tools/asset_manifest`` unittest suite with a recording
   result;
2. every FAIL/ERROR detail (traceback and assertion diff) from that suite,
   printed before the verdict;
3. the shipped empty registry through ``validate_manifest.py --check-hashes``.

Policy:

* any test failure or error anywhere in the suite is a hard failure;
* a skipped test *inside* ``WindowsNativeGuardTestCase`` is a hard failure -
  a skipped native guarded-open test certifies nothing about Windows;
* a skipped test elsewhere is a documented platform-specific skip (on Windows
  this is the six FIFO cases, which have no Windows equivalent); it is listed
  and allowed, never counted as coverage;
* the two named native controls must have run and passed;
* the shipped empty manifest must pass ``--check-hashes``.

On a non-Windows host every native test is skipped, so the runner fails closed
rather than claiming anything about Windows. Standard library only; no network,
credentials or writes outside the repository checkout.

Original project code under the Unlicense.
"""

from __future__ import annotations

import subprocess
import sys
import unittest
from collections import namedtuple
from pathlib import Path

_TESTS_DIR = Path(__file__).resolve().parent            # tools/asset_manifest/tests
_TOOL_DIR = _TESTS_DIR.parent                          # tools/asset_manifest
_REPO_ROOT = _TOOL_DIR.parents[1]                      # the project checkout
_MANIFEST = _REPO_ROOT / "assets" / "manifest.json"
_CLI = _TOOL_DIR / "validate_manifest.py"
_NATIVE_CLASS = "WindowsNativeGuardTestCase"

# The two controls the CI job must never lose: one proves a valid Windows read
# still hashes, the other proves a static intermediate junction is refused.
_CRITICAL_TESTS = (
    "test_native_regular_outputs_hash_and_anchors_resolve",
    "test_native_junction_parent_is_refused",
)

# Outcome of the suite plus the derived policy verdict. ``problems`` is the
# list of hard failures; ``allowed_skips`` and ``native_skips`` carry the
# platform-skip split for reporting.
Assessment = namedtuple(
    "Assessment",
    (
        "problems",
        "failed_ids",
        "error_ids",
        "native_skips",
        "allowed_skips",
        "expected_native",
        "native_ran",
        "succeeded_names",
    ),
)


class _WritelnStream:
    """Minimal wrapper giving unittest's result the ``writeln`` it expects."""

    def __init__(self, inner) -> None:
        self._inner = inner

    def write(self, text) -> None:
        self._inner.write(text)

    def writeln(self, text="") -> None:
        self._inner.write(text + "\n")

    def flush(self) -> None:
        self._inner.flush()


class _RecordingResult(unittest.TextTestResult):
    """Collects per-test outcomes so skips and omissions can fail the job."""

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.succeeded: list[str] = []
        self.skipped_tests: list[tuple[str, str]] = []
        self.failed_ids: list[str] = []
        self.error_ids: list[str] = []

    def addSuccess(self, test) -> None:
        super().addSuccess(test)
        self.succeeded.append(test.id())

    def addSkip(self, test, reason) -> None:
        super().addSkip(test, reason)
        self.skipped_tests.append((test.id(), reason))

    def addFailure(self, test, err) -> None:
        super().addFailure(test, err)
        self.failed_ids.append(test.id())

    def addError(self, test, err) -> None:
        super().addError(test, err)
        self.error_ids.append(test.id())


def _method_names(test_ids) -> set[str]:
    return {test_id.rsplit(".", 1)[-1] for test_id in test_ids}


def load_test_module():
    """Import the test module once, from its directory, independent of cwd."""
    if str(_TESTS_DIR) not in sys.path:
        sys.path.insert(0, str(_TESTS_DIR))
    import test_manifest_validator

    return test_manifest_validator


def run_suite(module) -> _RecordingResult:
    """Run the complete suite and return the recorded outcomes."""
    loader = unittest.TestLoader()
    suite = loader.discover(start_dir=str(_TESTS_DIR), top_level_dir=str(_TOOL_DIR))
    result = _RecordingResult(_WritelnStream(sys.stdout), descriptions=True, verbosity=2)
    suite.run(result)
    return result


def print_diagnostics(result: _RecordingResult) -> None:
    """Print full FAIL/ERROR details before the verdict.

    Delegates to unittest's own ``printErrors``, so the log gets the separator,
    test description, traceback and assertion diff exactly as a normal
    ``unittest`` run would. A raised exception here is deliberately not caught:
    a diagnostic that cannot be printed must not be turned into a silent
    verdict.
    """
    if result.failed_ids or result.error_ids:
        print("")
        print("full unittest failure and error details:")
        result.printErrors()


def assess(result: _RecordingResult, expected_native) -> Assessment:
    """Apply the skip/failure policy to a recorded suite result.

    Hard failures: any failure or error anywhere; any skip inside the native
    class; no native tests found; native tests missing from the passed set;
    missing critical controls. Skips outside the native class are allowed and
    returned separately for reporting.
    """
    native_skips = [
        (test_id, reason)
        for test_id, reason in result.skipped_tests
        if _NATIVE_CLASS in test_id
    ]
    allowed_skips = [
        (test_id, reason)
        for test_id, reason in result.skipped_tests
        if _NATIVE_CLASS not in test_id
    ]

    problems: list[str] = []
    if result.failed_ids or result.error_ids:
        problems.append(
            "{} test(s) failed or errored:\n  - {}".format(
                len(result.failed_ids) + len(result.error_ids),
                "\n  - ".join(result.failed_ids + result.error_ids),
            )
        )
    if native_skips:
        problems.append(
            "{} native guarded-open test(s) skipped, which certifies nothing "
            "(Windows acceptance requires them to run):\n  - {}".format(
                len(native_skips),
                "\n  - ".join(
                    "{} ({})".format(name, reason) for name, reason in native_skips
                ),
            )
        )
    if not expected_native:
        problems.append(
            "no {} tests were found; the native guarded-open coverage is missing".format(
                _NATIVE_CLASS
            )
        )

    succeeded_names = _method_names(result.succeeded)
    missing = sorted(expected_native - succeeded_names)
    if missing:
        problems.append("native guarded-open test(s) did not run: {}".format(", ".join(missing)))
    lost_critical = [name for name in _CRITICAL_TESTS if name in missing]
    if lost_critical:
        problems.append(
            "critical Windows controls did not run: {}".format(", ".join(lost_critical))
        )

    return Assessment(
        problems=problems,
        failed_ids=list(result.failed_ids),
        error_ids=list(result.error_ids),
        native_skips=native_skips,
        allowed_skips=allowed_skips,
        expected_native=set(expected_native),
        native_ran=set(expected_native) & succeeded_names,
        succeeded_names=succeeded_names,
    )


def run_cli_check() -> tuple[int, str]:
    """Run the shipped empty registry with --check-hashes; return (rc, output)."""
    completed = subprocess.run(
        [
            sys.executable,
            str(_CLI),
            "--root",
            str(_REPO_ROOT),
            str(_MANIFEST),
            "--check-hashes",
        ],
        cwd=str(_REPO_ROOT),
        capture_output=True,
        text=True,
        timeout=300,
    )
    return completed.returncode, (completed.stdout + completed.stderr).strip()


def main(argv=None) -> int:
    print("asset manifest Windows CI runner")
    print("repository root: {}".format(_REPO_ROOT))
    try:
        module = load_test_module()
    except Exception as exc:  # noqa: BLE001 - reported, never hidden
        print("[fail] cannot import the asset manifest test module: {}".format(exc), file=sys.stderr)
        return 1

    result = run_suite(module)
    print_diagnostics(result)

    native_class = getattr(module, _NATIVE_CLASS, None)
    expected_native = (
        {name for name in vars(native_class) if name.startswith("test_")}
        if native_class is not None
        else set()
    )
    assessment = assess(result, expected_native)

    print("")
    print(
        "suite: {} run, {} passed, {} failed, {} errors, {} skipped".format(
            result.testsRun,
            len(result.succeeded),
            len(result.failed_ids),
            len(result.error_ids),
            len(result.skipped_tests),
        )
    )
    print(
        "skips outside the native class (documented platform cases, allowed): {}".format(
            len(assessment.allowed_skips)
        )
    )
    if assessment.allowed_skips:
        for name, reason in assessment.allowed_skips:
            print("  - {} ({})".format(name, reason))
    print("native guarded-open tests expected: {}".format(len(assessment.expected_native)))
    print("native guarded-open tests executed and passed: {}".format(len(assessment.native_ran)))

    problems = list(assessment.problems)
    rc, output = run_cli_check()
    print("shipped manifest --check-hashes: exit {}, {}".format(rc, output.replace("\n", " | ")))
    if rc != 0 or "PASS" not in output:
        problems.append("shipped empty manifest --check-hashes did not pass (exit {})".format(rc))

    if problems:
        print("")
        for problem in problems:
            print("[fail] {}".format(problem), file=sys.stderr)
        print("Windows acceptance NOT established.", file=sys.stderr)
        return 1

    print("[ok] all native guarded-open tests ran and passed; Windows acceptance recorded")
    return 0


if __name__ == "__main__":
    sys.exit(main())
