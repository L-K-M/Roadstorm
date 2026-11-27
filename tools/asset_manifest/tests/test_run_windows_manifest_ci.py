#!/usr/bin/env python3
"""Self-tests for the Windows CI runner's identity, skip and diagnostic policy.

Ownership: tools/asset_manifest/**.

These are focused fake-result controls: they fabricate recorded suite outcomes
and check the policy the hosted job relies on, without running the manifest
suite twice or touching a Windows host.

Covered regressions include both constructions the review demonstrated:

* a native class that contains only the oversized-integer control must still
  fail because the two critical controls are required independently;
* critical method names passing under a *different* class must not satisfy the
  critical IDs;
* a non-native skip outside the reviewed allowlist must fail instead of
  silently reducing coverage.

Original project code under the Unlicense.
"""

from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path

_TESTS_DIR = Path(__file__).resolve().parent
if str(_TESTS_DIR) not in sys.path:
    sys.path.insert(0, str(_TESTS_DIR))

import run_windows_manifest_ci as runner  # noqa: E402  (path set up above)

_MODULE = "tests.test_manifest_validator"


class _FakeNative(unittest.TestCase):
    """Stands in for ``WindowsNativeGuardTestCase``."""

    def test_native_regular_outputs_hash_and_anchors_resolve(self):
        pass

    def test_native_junction_parent_is_refused(self):
        pass


_FakeNative.__module__ = _MODULE
_FakeNative.__qualname__ = runner._NATIVE_CLASS


def _record(stream=None) -> runner._RecordingResult:
    return runner._RecordingResult(
        runner._WritelnStream(stream if stream is not None else io.StringIO()),
        descriptions=True,
        verbosity=2,
    )


class RunnerIdentityPolicyTestCase(unittest.TestCase):
    """Native controls are identified by full ID, never by bare method name."""

    def test_critical_controls_are_required_independently_of_discovery(self):
        """A class holding only the oversized control must still fail."""

        class OnlyOversized(unittest.TestCase):
            def test_native_oversized_integer_cli_exits_2_with_json(self):
                pass

        OnlyOversized.__module__ = _MODULE
        OnlyOversized.__qualname__ = runner._NATIVE_CLASS
        expected, critical = runner.native_control_ids(OnlyOversized)
        self.assertEqual(len(expected), 1, "fixture class should hold one test")
        self.assertEqual(len(critical), len(runner._CRITICAL_TESTS))
        result = _record()
        result.testsRun = 1
        result.succeeded = list(expected)
        assessment = runner.assess(result, expected, critical)
        joined = "\n".join(assessment.problems)
        self.assertIn("critical Windows controls did not run", joined)
        self.assertTrue(
            any(item.endswith("test_native_junction_parent_is_refused") for item in critical),
            critical,
        )

    def test_critical_names_under_another_class_do_not_count(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 2
        result.succeeded = [
            "{}.{}.{}".format(
                _MODULE, runner._NATIVE_CLASS, "test_native_regular_outputs_hash_and_anchors_resolve"
            ),
            # The critical method name, but under the wrong class.
            "{}.{}.{}".format(
                _MODULE, "ManifestValidatorTestCase", "test_native_junction_parent_is_refused"
            ),
        ]
        assessment = runner.assess(result, expected, critical)
        joined = "\n".join(assessment.problems)
        self.assertIn("critical Windows controls did not run", joined)
        self.assertIn(
            "{}.{}.{}".format(_MODULE, runner._NATIVE_CLASS, "test_native_junction_parent_is_refused"),
            joined,
        )

    def test_discovered_native_test_missing_from_passes_fails(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 1
        result.succeeded = [
            "{}.{}.{}".format(
                _MODULE, runner._NATIVE_CLASS, "test_native_regular_outputs_hash_and_anchors_resolve"
            )
        ]
        assessment = runner.assess(result, expected, critical)
        self.assertTrue(any("did not run" in p for p in assessment.problems), assessment.problems)
        self.assertEqual(
            assessment.native_ran,
            {
                "{}.{}.{}".format(
                    _MODULE, runner._NATIVE_CLASS, "test_native_regular_outputs_hash_and_anchors_resolve"
                )
            },
        )

    def test_missing_native_class_is_reported(self):
        result = _record()
        result.testsRun = 1
        result.succeeded = ["tests.test_manifest_validator.ManifestValidatorTestCase.test_x"]
        assessment = runner.assess(result, set(), set())
        self.assertTrue(
            any("coverage is missing" in p for p in assessment.problems),
            assessment.problems,
        )

    def test_native_failure_is_named(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 2
        result.succeeded = [
            "{}.{}.{}".format(
                _MODULE, runner._NATIVE_CLASS, "test_native_regular_outputs_hash_and_anchors_resolve"
            )
        ]
        result.failed_ids = [
            "{}.{}.{}".format(
                _MODULE, runner._NATIVE_CLASS, "test_native_junction_parent_is_refused"
            )
        ]
        assessment = runner.assess(result, expected, critical)
        self.assertTrue(
            any("native guarded-open test(s) failed or errored" in p for p in assessment.problems),
            assessment.problems,
        )


class RunnerSkipPolicyTestCase(unittest.TestCase):
    """Skips inside the native class fail; outside they need review."""

    def test_native_skip_is_a_hard_failure(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 2
        result.succeeded = [
            "{}.{}.{}".format(
                _MODULE, runner._NATIVE_CLASS, "test_native_regular_outputs_hash_and_anchors_resolve"
            )
        ]
        result.skipped_tests = [
            (
                "{}.{}.{}".format(
                    _MODULE, runner._NATIVE_CLASS, "test_native_junction_parent_is_refused"
                ),
                "native Win32 acceptance requires a Windows host",
            )
        ]
        assessment = runner.assess(result, expected, critical)
        self.assertEqual(len(assessment.native_skips), 1)
        joined = "\n".join(assessment.problems)
        self.assertIn("skipped", joined)
        self.assertIn("critical Windows controls did not run", joined)

    def test_reviewed_non_native_skip_is_allowed(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 3
        result.succeeded = sorted(expected)
        result.skipped_tests = [
            (
                "{}.{}.{}".format(
                    _MODULE,
                    "RegisterReadGuardTestCase",
                    "test_refuses_a_fifo_in_place_of_the_register",
                ),
                "this platform has no FIFOs",
            )
        ]
        assessment = runner.assess(result, expected, critical)
        self.assertEqual(assessment.problems, [])
        self.assertEqual(assessment.drift_skips, [])
        self.assertEqual(len(assessment.allowed_skips), 1)
        self.assertEqual(assessment.native_ran, expected)

    def test_unreviewed_non_native_skip_fails_as_drift(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 3
        result.succeeded = sorted(expected)
        result.skipped_tests = [
            (
                "{}.{}.{}".format(
                    _MODULE,
                    "ManifestValidatorTestCase",
                    "test_some_new_security_control",
                ),
                "not yet reviewed on Windows",
            )
        ]
        assessment = runner.assess(result, expected, critical)
        self.assertEqual(len(assessment.drift_skips), 1)
        joined = "\n".join(assessment.problems)
        self.assertIn("unreviewed non-native skip(s)", joined)
        self.assertIn("test_some_new_security_control", joined)


class RunnerFailurePolicyTestCase(unittest.TestCase):
    """Failures anywhere stay fatal, and diagnostics carry real detail."""

    def test_whole_suite_failure_is_fatal_outside_the_native_class(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 2
        result.succeeded = sorted(expected)
        result.failed_ids = [
            "{}.{}.{}".format(_MODULE, "ManifestValidatorTestCase", "test_fifo")
        ]
        assessment = runner.assess(result, expected, critical)
        joined = "\n".join(assessment.problems)
        self.assertIn("failed or errored", joined)
        self.assertIn("ManifestValidatorTestCase.test_fifo", joined)

    def test_error_outside_the_native_class_is_fatal(self):
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = 2
        result.succeeded = sorted(expected)
        result.error_ids = [
            "{}.{}.{}".format(_MODULE, "JunctionComponentTestCase", "test_y")
        ]
        assessment = runner.assess(result, expected, critical)
        self.assertTrue(
            any("failed or errored" in p for p in assessment.problems),
            assessment.problems,
        )

    def test_diagnostics_print_traceback_and_assertion_diff(self):
        class _Failing(unittest.TestCase):
            def test_boom(self):
                self.assertEqual(1, 2, "values differ")

        stream = io.StringIO()
        result = _record(stream)
        _Failing("test_boom").run(result)
        self.assertEqual(result.failed_ids, [_Failing("test_boom").id()])
        runner.print_diagnostics(result)
        text = stream.getvalue()
        self.assertIn("full unittest failure and error details:", text)
        self.assertIn("FAIL", text)
        self.assertIn("test_boom", text)
        self.assertIn("1 != 2", text)


class RunnerAllowlistTestCase(unittest.TestCase):
    """The reviewed skip allowlist must match real tests in the suite."""

    def test_allowlisted_skips_exist_and_number_thirteen(self):
        import test_manifest_validator as module

        self.assertEqual(len(runner._ALLOWED_NONNATIVE_SKIPS), 13)
        for class_name, method in sorted(runner._ALLOWED_NONNATIVE_SKIPS):
            test_class = getattr(module, class_name, None)
            self.assertIsNotNone(test_class, class_name)
            self.assertTrue(
                callable(getattr(test_class, method, None)),
                "{}.{} is not a test method".format(class_name, method),
            )

    def test_allowlisted_windows_run_has_no_drift(self):
        """All 13 known Windows platform skips together are not drift."""
        expected, critical = runner.native_control_ids(_FakeNative)
        result = _record()
        result.testsRun = len(expected) + len(runner._ALLOWED_NONNATIVE_SKIPS)
        result.succeeded = sorted(expected)
        result.skipped_tests = [
            (
                "{}.{}.{}".format(_MODULE, class_name, method),
                "documented Windows platform case",
            )
            for class_name, method in sorted(runner._ALLOWED_NONNATIVE_SKIPS)
        ]
        assessment = runner.assess(result, expected, critical)
        self.assertEqual(assessment.problems, [])
        self.assertEqual(len(assessment.allowed_skips), 13)
        self.assertEqual(assessment.drift_skips, [])


if __name__ == "__main__":
    unittest.main()
