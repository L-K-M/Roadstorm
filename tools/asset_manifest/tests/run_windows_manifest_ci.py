#!/usr/bin/env python3
"""Windows-host CI runner for the asset manifest validator.

Ownership: tools/asset_manifest/** (PLAN.md M0 provenance manifest tooling).

This exists so a Windows job cannot report acceptance while the native
guarded-open tests silently skip. It runs, in order:

1. the complete ``tools/asset_manifest`` unittest suite, recording which
   individual tests passed, failed, errored or were skipped;
2. the shipped empty registry through ``validate_manifest.py --check-hashes``.

It fails (exit 1) when any test from ``WindowsNativeGuardTestCase`` was
skipped, is missing, failed or errored, when the suite did not run at all, or
when the CLI check does not pass. Exit 0 means every native guarded-open test
executed and passed on the host, including the regular output/hash control and
the junction-parent refusal test.

On a non-Windows host the native tests are skipped by design, so this runner
reports that and exits 1 rather than claiming anything about Windows.

Standard library only; no network, credentials or writes outside the
repository checkout and the interpreter's temporary files.

Original project code under the Unlicense.
"""

from __future__ import annotations

import subprocess
import sys
import unittest
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

    native_class = getattr(module, _NATIVE_CLASS, None)
    expected = (
        {name for name in vars(native_class) if name.startswith("test_")}
        if native_class is not None
        else set()
    )
    succeeded = _method_names(result.succeeded)
    skipped = [name for name, _reason in result.skipped_tests]
    failed = _method_names(result.failed_ids + result.error_ids)
    native_ran = {
        name
        for name in succeeded
        if name in expected
    }

    problems: list[str] = []
    if not expected:
        problems.append(
            "no {} tests were found; the native guarded-open coverage is missing".format(
                _NATIVE_CLASS
            )
        )
    if result.skipped_tests:
        problems.append(
            "{} test(s) skipped (Windows acceptance requires them to run):\n  - {}".format(
                len(result.skipped_tests),
                "\n  - ".join(
                    "{} ({})".format(name, reason)
                    for name, reason in result.skipped_tests
                ),
            )
        )
    if result.failed_ids or result.error_ids:
        problems.append(
            "{} test(s) failed or errored:\n  - {}".format(
                len(result.failed_ids) + len(result.error_ids),
                "\n  - ".join(result.failed_ids + result.error_ids),
            )
        )
    missing = sorted(expected - succeeded)
    if missing:
        problems.append("native guarded-open test(s) did not run: {}".format(", ".join(missing)))
    lost_critical = [name for name in _CRITICAL_TESTS if name in missing]
    if lost_critical:
        problems.append(
            "critical Windows controls did not run: {}".format(", ".join(lost_critical))
        )

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
    print("native guarded-open tests expected: {}".format(len(expected)))
    print("native guarded-open tests executed and passed: {}".format(len(native_ran)))

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
