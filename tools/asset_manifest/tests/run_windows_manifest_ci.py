#!/usr/bin/env python3
"""Windows-host CI runner for the asset manifest validator.

Ownership: tools/asset_manifest/** (PLAN.md M0 provenance manifest tooling).

This exists so a Windows job cannot report acceptance while the native
guarded-open tests silently skip or are misattributed. It runs, in order:

1. the complete ``tools/asset_manifest`` unittest suite with a recording
   result;
2. every FAIL/ERROR detail (traceback and assertion diff) from that suite,
   printed before the verdict;
3. the shipped empty registry through ``validate_manifest.py --check-hashes``.

Policy:

* any test failure or error anywhere in the suite is a hard failure;
* a skipped test *inside* ``WindowsNativeGuardTestCase`` is a hard failure -
  a skipped native guarded-open test certifies nothing about Windows;
* native controls are identified by their fully qualified test ID
  (``<module>.<class>.<method>``) in the module namespace unittest discovery
  reports (``tests.test_manifest_validator``). The two named critical controls
  must appear in the passed set under the native class itself, independently
  of what the class happens to contain at runtime;
* a non-native skip is allowed only when its class/method pair is in the
  reviewed allowlist below - on Windows exactly 13 cases: 6 FIFO controls with
  no Windows equivalent, 5 Unix mode-000 controls with native ACL
  counterparts, and 2 POSIX-flag-only controls. Any other non-native skip is
  unreviewed coverage loss and fails the job;
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
# They are required by full test ID, independent of runtime discovery.
_CRITICAL_TESTS = (
    "test_native_regular_outputs_hash_and_anchors_resolve",
    "test_native_junction_parent_is_refused",
)

# Reviewed non-native Windows skips, as (class, method). Six FIFO controls have
# no Windows equivalent; five Unix mode-000 controls have native ACL
# counterparts; two flag controls are POSIX-only.
_ALLOWED_NONNATIVE_SKIPS = frozenset(
    {
        # FIFO controls (no Windows equivalent).
        ("ManifestValidatorTestCase", "test_digest_refuses_a_fifo_swapped_in_at_the_open_boundary"),
        ("ManifestValidatorTestCase", "test_register_swapped_for_a_fifo_after_the_check_does_not_block"),
        ("ManifestValidatorTestCase", "test_register_that_is_a_fifo_is_refused_without_being_opened"),
        ("RegisterReadGuardTestCase", "test_guarded_open_refuses_a_fifo_without_blocking"),
        ("RegisterReadGuardTestCase", "test_refuses_a_fifo_in_place_of_the_register"),
        ("RegisterReadGuardTestCase", "test_refuses_a_fifo_swapped_in_after_the_pre_check"),
        # Unix mode-000 controls (native ACL counterparts exist).
        ("ManifestValidatorTestCase", "test_cli_unreadable_manifest_exits_2"),
        ("ManifestValidatorTestCase", "test_unreadable_output_cli_emits_json_instead_of_a_traceback"),
        ("ManifestValidatorTestCase", "test_unreadable_output_is_a_structured_finding_not_a_traceback"),
        ("ManifestValidatorTestCase", "test_unreadable_register_is_rejected_before_any_read"),
        ("RegisterReadGuardTestCase", "test_refuses_an_unreadable_register"),
        # POSIX-only guarded-open flag controls.
        ("ManifestValidatorTestCase", "test_guarded_open_fails_closed_without_fd_protections"),
        ("RegisterReadGuardTestCase", "test_guarded_open_fails_closed_where_flags_are_unavailable"),
    }
)

# Outcome of the suite plus the derived policy verdict. ``problems`` is the
# list of hard failures; ``allowed_skips``/``drift_skips``/``native_skips``
# carry the skip split for reporting.
Assessment = namedtuple(
    "Assessment",
    (
        "problems",
        "failed_ids",
        "error_ids",
        "native_skips",
        "allowed_skips",
        "drift_skips",
        "expected_native",
        "critical_native",
        "native_ran",
        "succeeded_ids",
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


def _class_and_method(test_id: str) -> tuple[str, str]:
    """Split a unittest test ID into its trailing class and method names."""
    parts = test_id.split(".")
    return parts[-2], parts[-1]


def native_control_ids(native_class):
    """Fully qualified native test IDs, including the critical controls.

    ``expected`` covers every ``test_*`` attribute found on the class.
    ``critical`` always uses the two named control methods under this class,
    whether or not the class currently defines them - a renamed or deleted
    control is therefore reported instead of silently dropping out of the
    requirement.
    """
    prefix = "{}.{}.".format(native_class.__module__, native_class.__qualname__)
    expected = {
        prefix + name for name in vars(native_class) if name.startswith("test_")
    }
    critical = {prefix + name for name in _CRITICAL_TESTS}
    return expected, critical


def load_test_module():
    """Import the test module in the namespace unittest discovery reports.

    Discovery runs with ``tools/asset_manifest`` as the top-level directory
    and its ``tests`` package as the start directory, so it imports
    ``tests.test_manifest_validator`` and reports IDs under that namespace.
    Importing the module directly from ``tests/`` instead creates a second
    module object whose ``__module__`` is the bare ``test_manifest_validator``.
    Expected native IDs built from the bare name can never match the prefixed
    IDs the suite reports, which fails the job even when every native control
    passed. Import the same dotted name discovery uses.
    """
    if str(_TOOL_DIR) not in sys.path:
        sys.path.insert(0, str(_TOOL_DIR))
    import importlib

    return importlib.import_module("{}.test_manifest_validator".format(_TESTS_DIR.name))


def discover_suite() -> unittest.TestSuite:
    """Discover the suite with the same layout as run_tests.sh.

    ``tools/asset_manifest`` is the top-level directory and its ``tests``
    package is the start directory, so unittest imports the tests as
    ``tests.test_manifest_validator`` and reports IDs under that namespace.
    """
    loader = unittest.TestLoader()
    return loader.discover(start_dir=str(_TESTS_DIR), top_level_dir=str(_TOOL_DIR))


def run_suite(suite=None) -> _RecordingResult:
    """Run the complete suite and return the recorded outcomes."""
    if suite is None:
        suite = discover_suite()
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
        stream = getattr(result, "stream", None)
        if stream is None:
            print("")
            print("full unittest failure and error details:")
        else:
            stream.writeln("")
            stream.writeln("full unittest failure and error details:")
        result.printErrors()


def assess(
    result: _RecordingResult,
    expected_native,
    critical_native=frozenset(),
) -> Assessment:
    """Apply the skip/failure policy to a recorded suite result.

    Hard failures: any failure or error anywhere; any skip inside the native
    class; no native tests found; a discovered native test missing from the
    passed set; either critical control missing from the passed set; any
    failure/error among native IDs; an unreviewed non-native skip. Allowlisted
    non-native skips are returned for reporting only.
    """
    expected_native = set(expected_native)
    critical_native = set(critical_native)

    native_skips = [
        (test_id, reason)
        for test_id, reason in result.skipped_tests
        if _class_and_method(test_id)[0] == _NATIVE_CLASS
    ]
    other_skips = [
        (test_id, reason)
        for test_id, reason in result.skipped_tests
        if _class_and_method(test_id)[0] != _NATIVE_CLASS
    ]
    allowed_skips = []
    drift_skips = []
    for test_id, reason in other_skips:
        if _class_and_method(test_id) in _ALLOWED_NONNATIVE_SKIPS:
            allowed_skips.append((test_id, reason))
        else:
            drift_skips.append((test_id, reason))

    succeeded_ids = set(result.succeeded)
    native_failed = sorted(
        (set(result.failed_ids) | set(result.error_ids))
        & (expected_native | critical_native)
    )

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
    if native_failed:
        problems.append(
            "{} native guarded-open test(s) failed or errored:\n  - {}".format(
                len(native_failed), "\n  - ".join(native_failed)
            )
        )
    if drift_skips:
        problems.append(
            "{} unreviewed non-native skip(s) would silently reduce coverage; "
            "add them to the reviewed allowlist or make them run:\n  - {}".format(
                len(drift_skips),
                "\n  - ".join(
                    "{} ({})".format(name, reason) for name, reason in drift_skips
                ),
            )
        )
    if not expected_native and not critical_native:
        problems.append(
            "no {} tests were found; the native guarded-open coverage is missing".format(
                _NATIVE_CLASS
            )
        )

    missing = sorted(expected_native - succeeded_ids)
    if missing:
        problems.append("native guarded-open test(s) did not run: {}".format(", ".join(missing)))
    critical_missing = sorted(critical_native - succeeded_ids)
    if critical_missing:
        problems.append(
            "critical Windows controls did not run: {}".format(", ".join(critical_missing))
        )

    return Assessment(
        problems=problems,
        failed_ids=list(result.failed_ids),
        error_ids=list(result.error_ids),
        native_skips=native_skips,
        allowed_skips=allowed_skips,
        drift_skips=drift_skips,
        expected_native=expected_native,
        critical_native=critical_native,
        native_ran=expected_native & succeeded_ids,
        succeeded_ids=succeeded_ids,
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

    result = run_suite()
    print_diagnostics(result)

    native_class = getattr(module, _NATIVE_CLASS, None)
    if native_class is None:
        expected_native: set[str] = set()
        critical_native: set[str] = set()
    else:
        expected_native, critical_native = native_control_ids(native_class)
    assessment = assess(result, expected_native, critical_native)

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
        "non-native skips (reviewed allowlist): {} allowed, {} unreviewed".format(
            len(assessment.allowed_skips), len(assessment.drift_skips)
        )
    )
    for name, reason in assessment.allowed_skips:
        print("  - [allowed] {} ({})".format(name, reason))
    for name, reason in assessment.drift_skips:
        print("  - [unreviewed] {} ({})".format(name, reason))
    print("native guarded-open tests expected: {}".format(len(assessment.expected_native)))
    print("native critical controls required: {}".format(len(assessment.critical_native)))
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
