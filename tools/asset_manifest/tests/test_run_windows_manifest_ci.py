#!/usr/bin/env python3
"""Self-tests for the Windows CI runner's skip and diagnostic policy.

Ownership: tools/asset_manifest/**.

These are focused fake-result controls: they fabricate recorded suite outcomes
and check the policy the hosted job relies on, without running the manifest
suite twice or touching a Windows host:

* a skip inside ``WindowsNativeGuardTestCase`` is a hard failure;
* skips outside it (the documented FIFO/platform cases) are allowed and listed;
* any whole-suite failure or error is a hard failure even outside the native
  class;
* missing or failed critical controls are flagged;
* full FAIL/ERROR details (traceback and assertion diff) are printed.

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

_EXPECTED = {
    "test_native_regular_outputs_hash_and_anchors_resolve",
    "test_native_junction_parent_is_refused",
}


def _record(stream=None) -> runner._RecordingResult:
    return runner._RecordingResult(
        runner._WritelnStream(stream if stream is not None else io.StringIO()),
        descriptions=True,
        verbosity=2,
    )


class RunnerSkipPolicyTestCase(unittest.TestCase):
    """The runner must fail closed on native skips but allow other platform skips."""

    def test_native_skip_is_a_hard_failure(self):
        result = _record()
        result.testsRun = 2
        result.succeeded = [
            "tests.test_manifest_validator.WindowsNativeGuardTestCase."
            "test_native_regular_outputs_hash_and_anchors_resolve"
        ]
        result.skipped_tests = [
            (
                "tests.test_manifest_validator.WindowsNativeGuardTestCase."
                "test_native_junction_parent_is_refused",
                "native Win32 acceptance requires a Windows host",
            )
        ]
        assessment = runner.assess(result, _EXPECTED)
        problems = "\n".join(assessment.problems)
        self.assertEqual(len(assessment.native_skips), 1)
        self.assertIn("skipped", problems)
        self.assertIn("test_native_junction_parent_is_refused", problems)
        self.assertIn("critical Windows controls did not run", problems)

    def test_non_native_platform_skip_is_allowed(self):
        result = _record()
        result.testsRun = 3
        result.succeeded = [
            "tests.test_manifest_validator.WindowsNativeGuardTestCase." + name
            for name in sorted(_EXPECTED)
        ]
        result.skipped_tests = [
            (
                "tests.test_manifest_validator.RegisterReadGuardTestCase."
                "test_refuses_a_fifo_in_place_of_the_register",
                "this platform has no FIFOs",
            )
        ]
        assessment = runner.assess(result, _EXPECTED)
        self.assertEqual(assessment.problems, [])
        self.assertEqual(assessment.native_skips, [])
        self.assertEqual(len(assessment.allowed_skips), 1)
        self.assertEqual(
            assessment.native_ran,
            _EXPECTED,
            "passing native tests must be recognised as executed",
        )

    def test_missing_native_class_is_a_hard_failure(self):
        result = _record()
        result.testsRun = 1
        result.succeeded = ["tests.test_manifest_validator.ManifestValidatorTestCase.test_x"]
        assessment = runner.assess(result, set())
        self.assertTrue(
            any("coverage is missing" in problem for problem in assessment.problems),
            assessment.problems,
        )


class RunnerFailurePolicyTestCase(unittest.TestCase):
    """Failures anywhere stay fatal, and diagnostics carry real detail."""

    def test_whole_suite_failure_is_fatal_outside_the_native_class(self):
        result = _record()
        result.testsRun = 2
        result.succeeded = [
            "tests.test_manifest_validator.WindowsNativeGuardTestCase." + name
            for name in sorted(_EXPECTED)
        ]
        result.failed_ids = ["tests.test_manifest_validator.ManifestValidatorTestCase.test_fifo"]
        assessment = runner.assess(result, _EXPECTED)
        joined = "\n".join(assessment.problems)
        self.assertIn("failed or errored", joined)
        self.assertIn("ManifestValidatorTestCase.test_fifo", joined)

    def test_error_outside_the_native_class_is_fatal(self):
        result = _record()
        result.testsRun = 2
        result.succeeded = [
            "tests.test_manifest_validator.WindowsNativeGuardTestCase." + name
            for name in sorted(_EXPECTED)
        ]
        result.error_ids = ["tests.test_manifest_validator.JunctionComponentTestCase.test_y"]
        assessment = runner.assess(result, _EXPECTED)
        self.assertTrue(
            any("failed or errored" in problem for problem in assessment.problems),
            assessment.problems,
        )

    def test_missing_critical_control_is_reported_separately(self):
        result = _record()
        result.testsRun = 1
        result.succeeded = [
            "tests.test_manifest_validator.WindowsNativeGuardTestCase."
            "test_native_regular_outputs_hash_and_anchors_resolve"
        ]
        assessment = runner.assess(result, _EXPECTED)
        joined = "\n".join(assessment.problems)
        self.assertIn("did not run: test_native_junction_parent_is_refused", joined)
        self.assertIn("critical Windows controls did not run", joined)

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
        self.assertIn("FAIL", text)
        self.assertIn("test_boom", text)
        self.assertIn("1 != 2", text)


if __name__ == "__main__":
    unittest.main()
