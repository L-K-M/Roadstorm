#!/usr/bin/env python3
"""Tests for fixtures/scenario/validate_scenario_contract.py.

Ownership: fixtures/scenario/** (PLAN.md M0.9, job
847d8664-1028-4233-a67c-39f1465b4964).

Run from the repository root with::

    python3 -m unittest discover -s fixtures/scenario/tests -t .

or via fixtures/scenario/run_tests.sh. Standard library only.

The suite pins four things:

* every positive fixture validates cleanly against schemas/scenario;
* every negative fixture is rejected with exactly the failure set its
  .expected.json sidecar declares;
* the validator's own machinery behaves: constants come from the schemas,
  duplicate JSON members are rejected, the content hash is canonical and
  order-independent, --update-hashes rewrites a stale hash, and schema
  failures short-circuit semantic checks;
* the measured-record accounting rules (clean-lap counts, median/min/max,
  medal arithmetic, dependency completeness) hold for a synthetic measured
  record built in the test. Those numbers are arithmetic test data inside
  this file, not measurements: no shipped fixture contains a lap time;
* the remediation rules added for the 2026-11-27 contract review: the metric
  vocabulary and shape (comparator/value/bounds, mirroring the handling
  validator), initial-state/commands/history agreement, cloning-only producer
  pinning, and the retained evidence a measured record must keep (sector
  splits, speed samples, car/loadout/assist hashes).
"""

from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
FIXTURES_DIR = HERE.parents[1]
REPO_ROOT = HERE.parents[3]
sys.path.insert(0, str(FIXTURES_DIR))

import validate_scenario_contract as vsc  # noqa: E402

POSITIVE_DIR = FIXTURES_DIR / "positive"
NEGATIVE_DIR = FIXTURES_DIR / "negative"
SCHEMAS_DIR = REPO_ROOT / "schemas" / "scenario"

FAKE_HASH = "sha256:" + "a" * 64


def positive_paths() -> list[Path]:
    return sorted(POSITIVE_DIR.glob("*.json"))


def negative_paths() -> list[Path]:
    return sorted(
        path
        for path in NEGATIVE_DIR.glob("*.json")
        if not path.name.endswith(".expected.json")
    )


def build_measured_record() -> dict:
    """Turn the planned flying record into a consistent synthetic measured one.

    Lap times are round test numbers chosen so the arithmetic is exact; they
    are not measurements and never leave this function.
    """
    document = json.loads(
        (POSITIVE_DIR / "fixture.scenario.reference_capture_flying.json").read_text(encoding="utf-8")
    )
    record = document["reference_records"][0]
    record["status"] = "measured"
    record["course"]["course_revision"] = "course_rev_1"
    record["driver"]["driver_revision"] = "calibration_driver_v1"
    record["driver"]["reference_line_revision"] = "reference_line_v1"
    record["dependencies"]["handling_revision"] = "handling_rev_1"
    record["dependencies"]["platform"] = {"os": "macOS", "cpu": "Apple M1", "gpu": "integrated"}
    times = [40.0, 41.0, 42.0, 43.0, 44.0]
    laps = [
        {
            "lap_index": index,
            "time_s": time,
            "clean": True,
            "sector_splits_s": [time / 4.0] * 4,
        }
        for index, time in enumerate(times)
    ]
    laps.append(
        {
            "lap_index": 5,
            "time_s": 45.0,
            "clean": False,
            "invalid_reason": "contact",
        }
    )
    record["results"]["laps"] = laps
    record["results"]["speed_samples"] = [
        {"route_distance_m": distance, "speed_m_s": 30.0 + distance / 10.0}
        for distance in (0.0, 50.0, 100.0)
    ]
    record["results"]["statistics"] = {"median_s": 42.0, "min_s": 40.0, "max_s": 44.0}
    record["results"]["hashes"] = {
        "car_hash": FAKE_HASH,
        "loadout_hash": FAKE_HASH,
        "assist_hash": FAKE_HASH,
    }
    record["derived_thresholds"]["bronze_s"] = 1.25 * 42.0
    record["derived_thresholds"]["silver_s"] = 1.12 * 42.0
    record["derived_thresholds"]["gold_s"] = 1.05 * 42.0
    # Drop the unknowns entries whose values are now determined, exactly as an
    # author filling in a measured record would.
    document["unknowns"] = [
        entry
        for entry in document["unknowns"]
        if vsc.resolve_dotted(document, entry["path"]) is None
    ]
    return document


def run_record_checks(document: dict, contracts: vsc.Contracts) -> list[vsc.Failure]:
    """Run the record-level accounting checks directly.

    A fixture file may never carry a measured record (evidence_status), so the
    accounting rules are exercised here on a synthetic document rather than
    through validate_positive.
    """
    constants = contracts.constants
    failures: list[vsc.Failure] = []
    failures.extend(vsc.check_clean_lap_accounting(document, constants))
    failures.extend(vsc.check_medal_threshold_arithmetic(document, constants))
    failures.extend(vsc.check_dependency_completeness(document, constants))
    failures.extend(vsc.check_measured_evidence_completeness(document, constants))
    failures.extend(vsc.check_null_unknown_pairing(document, constants))
    return failures


class PositiveFixtureTests(unittest.TestCase):
    """Every authored-valid fixture must pass schema, semantics and hash."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)

    def test_positive_fixtures_exist(self) -> None:
        self.assertGreaterEqual(len(positive_paths()), 1)

    def test_each_positive_fixture_validates(self) -> None:
        for path in positive_paths():
            with self.subTest(fixture=path.name):
                self.assertEqual(vsc.validate_positive(path, self.contracts), [])


class NegativeFixtureTests(unittest.TestCase):
    """Every negative fixture must fail exactly as its sidecar declares."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)

    def test_negative_fixtures_exist(self) -> None:
        self.assertGreaterEqual(len(negative_paths()), 1)

    def test_each_negative_fixture_rejected_as_declared(self) -> None:
        for path in negative_paths():
            with self.subTest(fixture=path.name):
                _actual, report = vsc.validate_negative(path, self.contracts)
                self.assertEqual(report, [], msg=f"{path.name} deviated from its sidecar")

    def test_negative_fixture_without_sidecar_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stray = Path(tmp) / "stray.json"
            stray.write_text(json.dumps({"schema_version": "1.0.0"}), encoding="utf-8")
            _actual, report = vsc.validate_negative(stray, self.contracts)
            self.assertTrue(any(f.code == "missing-expectation" for f in report))


class ValidatorMachineryTests(unittest.TestCase):
    """Unit tests for the pieces the fixture suites rely on."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants

    def test_constants_match_the_specified_contract(self) -> None:
        self.assertEqual(self.constants.tick_rate_hz, 60)
        self.assertEqual(self.constants.history_warmup_s, 2.0)
        self.assertEqual(self.constants.opportunity_window_s, 3.0)
        self.assertEqual(self.constants.handover_max_position_m, 0.1)
        self.assertEqual(self.constants.handover_max_speed_m_s, 0.1)
        self.assertEqual(self.constants.required_clean_laps, 5)
        self.assertEqual(self.constants.sector_count, 4)
        self.assertEqual(
            dict(self.constants.medal_multipliers),
            {"bronze": 1.25, "silver": 1.12, "gold": 1.05},
        )
        self.assertEqual(
            set(self.constants.rejection_criteria),
            {"contact", "reset", "missed_gate", "invalid_progress", "numerical_error"},
        )
        self.assertEqual(
            dict(self.constants.arcade_rush_factors),
            {"rookie": 1.2, "racer": 1.1, "expert": 1.02},
        )
        self.assertEqual(
            set(self.constants.required_telemetry_by_family["reference_lap_capture"]),
            {
                "gate_crossings",
                "lap_times",
                "sector_splits",
                "speed_samples",
                "contacts",
                "resets",
                "progress_corrections",
                "validity_flags",
            },
        )
        self.assertEqual(
            set(self.constants.required_telemetry_by_family["tactical_families"]),
            {
                "driver_commands",
                "tactical_intents",
                "safety_corrections",
                "contacts",
                "participant_poses",
                "gate_crossings",
                "race_rng_state",
            },
        )

    def test_duplicate_json_members_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "duplicate.json"
            path.write_text('{"a": 1, "a": 2}', encoding="utf-8")
            with self.assertRaises(vsc.DocumentError):
                vsc.load_json(path)

    def test_content_hash_is_canonical_and_order_independent(self) -> None:
        first = {"b": 2, "a": 1, "content_hash": "sha256:" + "0" * 64}
        second = {"content_hash": "sha256:" + "0" * 64, "a": 1, "b": 2}
        self.assertEqual(vsc.canonical_hash(first), vsc.canonical_hash(second))
        changed = {"a": 1, "b": 3, "content_hash": "sha256:" + "0" * 64}
        self.assertNotEqual(vsc.canonical_hash(first), vsc.canonical_hash(changed))

    def test_schema_failure_short_circuits_semantics(self) -> None:
        # bad_schema_version fails the const check; no semantic check may also
        # fire, so a negative fixture's sidecar can pin the intended rejection.
        path = NEGATIVE_DIR / "bad_schema_version.json"
        failures = vsc.validate_positive(path, self.contracts)
        self.assertEqual([f.code for f in failures], ["const"])
        self.assertTrue(all(f.check is None for f in failures))

    def test_iter_null_paths_and_resolve_dotted(self) -> None:
        document = {"a": {"b": None}, "c": [1, None, {"d": None}]}
        self.assertEqual(
            sorted(vsc.iter_null_paths(document)), ["a.b", "c.1", "c.2.d"]
        )
        self.assertIsNone(vsc.resolve_dotted(document, "a.b"))
        self.assertIs(vsc.resolve_dotted(document, "a.missing"), vsc.MISSING)
        self.assertIs(vsc.resolve_dotted(document, "c.9"), vsc.MISSING)

    def test_update_hashes_repairs_a_stale_hash(self) -> None:
        source = POSITIVE_DIR / "fixture.scenario.reference_capture_flying.json"
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / source.name
            document = json.loads(source.read_text(encoding="utf-8"))
            document["content_hash"] = "sha256:" + "0" * 64
            target.write_text(json.dumps(document, indent=2), encoding="utf-8")
            vsc.update_hashes(Path(tmp))
            self.assertEqual(vsc.validate_positive(target, self.contracts), [])

    def test_unimplemented_expectation_check_is_reported(self) -> None:
        document = {
            "reference_records": [],
            "expectations": [
                {
                    "expectation_id": "expect.future",
                    "check": "not_a_real_check",
                    "path": "",
                    "statement": "defense in depth",
                }
            ],
        }
        failures = vsc.check_expectations_declared(document)
        self.assertTrue(any(f.check == "expectation_implemented" for f in failures))

    def test_expectation_enum_matches_implemented_checks(self) -> None:
        # The fixture schema's expectation enum and the validator's implemented
        # set must not drift: an implemented check missing from the enum could
        # not be declared, and an enum entry without an implementation would be
        # accepted as a declaration that nothing checks.
        enum = set(
            self.contracts.fixture_schema["$defs"]["expectation"]["properties"]["check"][
                "enum"
            ]
        )
        self.assertEqual(enum, set(vsc.IMPLEMENTED_CHECKS))


class MeasuredRecordAccountingTests(unittest.TestCase):
    """The accounting rules a measured reference record must satisfy.

    The numbers are arithmetic test data constructed in build_measured_record;
    they are not measurements and no shipped fixture contains them.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants

    def test_consistent_measured_record_passes(self) -> None:
        document = build_measured_record()
        self.assertEqual(run_record_checks(document, self.contracts), [])

    def test_median_must_match_the_clean_laps(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["results"]["statistics"]["median_s"] = 41.0
        failures = run_record_checks(document, self.contracts)
        self.assertTrue(
            any(
                f.check == "clean_lap_accounting"
                and f.path == "reference_records.0.results.statistics.median_s"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_min_and_max_must_match_the_clean_laps(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["results"]["statistics"]["max_s"] = 40.0
        failures = run_record_checks(document, self.contracts)
        self.assertTrue(
            any(
                f.check == "clean_lap_accounting"
                and f.path == "reference_records.0.results.statistics.max_s"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_medal_thresholds_are_the_factors_times_the_median(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["derived_thresholds"]["bronze_s"] = 60.0
        failures = run_record_checks(document, self.contracts)
        self.assertTrue(
            any(
                f.check == "medal_threshold_arithmetic"
                and f.path == "reference_records.0.derived_thresholds.bronze_s"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_fewer_than_five_clean_laps_fails(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["results"]["laps"] = document["reference_records"][0][
            "results"
        ]["laps"][:4]
        failures = run_record_checks(document, self.contracts)
        self.assertTrue(
            any(
                f.check == "clean_lap_accounting" and f.path == "reference_records.0.results.laps"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_unclean_lap_needs_an_invalid_reason(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["results"]["laps"][5].pop("invalid_reason")
        failures = run_record_checks(document, self.contracts)
        self.assertTrue(
            any(
                f.check == "clean_lap_accounting"
                and f.path == "reference_records.0.results.laps.5"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_measured_record_needs_complete_dependencies(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["dependencies"]["handling_revision"] = None
        document["unknowns"].append(
            {
                "path": "reference_records.0.dependencies.handling_revision",
                "reason": "synthetic regression",
            }
        )
        failures = run_record_checks(document, self.contracts)
        self.assertTrue(
            any(f.check == "dependency_completeness" for f in failures), msg=str(failures)
        )

    def test_demoting_back_to_planned_with_results_fails(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["status"] = "planned"
        failures = vsc.check_evidence_status(document)
        self.assertTrue(any(f.check == "evidence_status" for f in failures), msg=str(failures))

    def test_planned_positive_record_still_passes(self) -> None:
        # The shipped planned fixture must not be affected by the measured path.
        path = POSITIVE_DIR / "fixture.scenario.reference_capture_flying.json"
        self.assertEqual(vsc.validate_positive(path, self.contracts), [])


class MeasuredEvidenceCompletenessTests(unittest.TestCase):
    """A measured record retains the evidence BENCHMARKS requires.

    BENCHMARKS 'Reference driver and records' retains sector splits, speed
    samples and car/loadout/assist hashes with each record; the numbers stay
    synthetic arithmetic data from build_measured_record.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants

    def test_consistent_measured_record_retains_evidence(self) -> None:
        document = build_measured_record()
        self.assertEqual(
            vsc.check_measured_evidence_completeness(document, self.constants), []
        )

    def test_measured_record_needs_speed_samples(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["results"]["speed_samples"] = []
        failures = vsc.check_measured_evidence_completeness(document, self.constants)
        self.assertTrue(
            any(
                f.check == "measured_evidence_completeness"
                and f.path == "reference_records.0.results.speed_samples"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_measured_record_needs_the_hashes(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["results"]["hashes"]["car_hash"] = None
        failures = vsc.check_measured_evidence_completeness(document, self.constants)
        self.assertTrue(
            any(
                f.check == "measured_evidence_completeness"
                and f.path == "reference_records.0.results.hashes"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_measured_record_needs_sector_splits_per_clean_lap(self) -> None:
        document = build_measured_record()
        document["reference_records"][0]["results"]["laps"][0].pop("sector_splits_s")
        failures = vsc.check_measured_evidence_completeness(document, self.constants)
        self.assertTrue(
            any(
                f.check == "measured_evidence_completeness"
                and f.path == "reference_records.0.results.laps.0.sector_splits_s"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_planned_record_needs_no_evidence_yet(self) -> None:
        # The shipped planned records carry no results; the rule only binds a
        # measured record.
        path = POSITIVE_DIR / "fixture.scenario.arcade_rush_standing_start.json"
        document = json.loads(path.read_text(encoding="utf-8"))
        self.assertEqual(
            vsc.check_measured_evidence_completeness(document, self.constants), []
        )


class MetricShapeTests(unittest.TestCase):
    """The scenario metric vocabulary mirrors the handling validator's rules."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)

    @staticmethod
    def _failures(metric: dict) -> list[vsc.Failure]:
        return vsc.check_metric_shape({"comparison": {"metrics": [metric]}})

    def test_threshold_metric_with_a_numeric_value_passes(self) -> None:
        self.assertEqual(self._failures({"name": "m", "comparator": "gte", "value": 5}), [])

    def test_threshold_metric_requires_a_numeric_value(self) -> None:
        failures = self._failures({"name": "m", "comparator": "gte"})
        self.assertTrue(
            any(
                f.check == "metric_shape" and f.path == "comparison.metrics.0.value"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_threshold_metric_rejects_range_bounds(self) -> None:
        failures = self._failures(
            {"name": "m", "comparator": "lte", "value": 1, "value_max": 2}
        )
        self.assertTrue(
            any(
                f.check == "metric_shape" and f.path == "comparison.metrics.0.value_min"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_range_metric_requires_ordered_bounds(self) -> None:
        failures = self._failures(
            {"name": "m", "comparator": "ratio_range", "value_min": 1.1, "value_max": 0.9}
        )
        self.assertTrue(
            any(
                f.check == "metric_shape" and f.path == "comparison.metrics.0"
                and "smaller" in f.message
                for f in failures
            ),
            msg=str(failures),
        )

    def test_range_metric_requires_bounds_at_all(self) -> None:
        failures = self._failures({"name": "m", "comparator": "range"})
        self.assertTrue(
            any(
                f.check == "metric_shape" and f.path == "comparison.metrics.0"
                and "requires numeric value_min and value_max" in f.message
                for f in failures
            ),
            msg=str(failures),
        )

    def test_range_metric_rejects_a_point_value(self) -> None:
        failures = self._failures(
            {
                "name": "m",
                "comparator": "ratio_range",
                "value": 1.0,
                "value_min": 0.9,
                "value_max": 1.1,
            }
        )
        self.assertTrue(
            any(
                f.check == "metric_shape" and f.path == "comparison.metrics.0.value"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_report_metric_rejects_a_threshold(self) -> None:
        failures = self._failures({"name": "m", "comparator": "report", "value": 1})
        self.assertTrue(
            any(
                f.check == "metric_shape" and f.path == "comparison.metrics.0"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_shipped_fixture_metrics_pass_the_shape_rules(self) -> None:
        for path in positive_paths():
            document = json.loads(path.read_text(encoding="utf-8"))
            with self.subTest(fixture=path.name):
                self.assertEqual(vsc.check_metric_shape(document), [])

    def test_metric_status_vocabulary(self) -> None:
        for status in ("documented_initial_target", "undecided", None):
            metric = {"name": "m", "comparator": "gte", "value": 1}
            if status is not None:
                metric["status"] = status
            self.assertEqual(
                vsc.check_metric_status_honesty({"comparison": {"metrics": [metric]}}), []
            )
        failures = vsc.check_metric_status_honesty(
            {
                "comparison": {
                    "metrics": [
                        {"name": "m", "comparator": "gte", "value": 1, "status": "bogus"}
                    ]
                }
            }
        )
        self.assertTrue(
            any(f.check == "metric_status_honesty" for f in failures), msg=str(failures)
        )


class InitialStateAgreementTests(unittest.TestCase):
    """Initial state, commands and history must pin the scenario consistently."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)
        cls.document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.tactical_window_slower_lead.json").read_text(
                encoding="utf-8"
            )
        )

    def _check(self, document: dict | None = None) -> list[vsc.Failure]:
        return vsc.check_initial_state_agreement(document or self.document)

    def test_shipped_tactical_fixture_agrees(self) -> None:
        self.assertEqual(self._check(), [])

    def test_shipped_capture_fixture_needs_no_matched_state(self) -> None:
        document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.reference_capture_flying.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(vsc.check_initial_state_agreement(document), [])

    def test_tactical_scenario_requires_matched_state_and_history(self) -> None:
        document = json.loads(json.dumps(self.document))
        initial = document["scenario"]["initial_state"]
        initial.pop("per_participant_state")
        initial.pop("history")
        failures = self._check(document)
        self.assertEqual(
            sorted(f.path for f in failures),
            ["scenario.initial_state", "scenario.initial_state"],
        )
        self.assertTrue(all(f.check == "initial_state_agreement" for f in failures))

    def test_per_participant_slot_must_name_a_participant(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["initial_state"]["per_participant_state"].append(
            {"slot": "nobody", "speed_m_s": 30}
        )
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and f.path.endswith(".per_participant_state.5.slot")
                for f in failures
            ),
            msg=str(failures),
        )

    def test_per_participant_slot_must_not_repeat(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["initial_state"]["per_participant_state"].append(
            {"slot": "surge", "speed_m_s": 30}
        )
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and "twice" in f.message
                for f in failures
            ),
            msg=str(failures),
        )

    def test_every_matched_participant_needs_an_entry(self) -> None:
        document = json.loads(json.dumps(self.document))
        entries = document["scenario"]["initial_state"]["per_participant_state"]
        entries[:] = [entry for entry in entries if entry["slot"] != "surge"]
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and f.path == "scenario.initial_state.per_participant_state"
                and "surge" in f.message
                for f in failures
            ),
            msg=str(failures),
        )

    def test_per_participant_state_must_agree_with_the_summary(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["initial_state"]["per_participant_state"][1][
            "speed_m_s"
        ] = 31.0
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and f.path.endswith(".per_participant_state.1.speed_m_s")
                for f in failures
            ),
            msg=str(failures),
        )

    def test_stored_snapshot_history_names_its_snapshot(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["initial_state"]["history"]["source"] = (
            "stored_scenario_snapshot"
        )
        failures = self._check(document)
        self.assertEqual(
            sorted(f.path for f in failures),
            [
                "scenario.initial_state.history.snapshot_id",
                "scenario.initial_state.history.snapshot_revision",
            ],
        )

    def test_history_warmup_must_match_the_protocol(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["initial_state"]["history"]["warmup_s"] = 1.5
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and f.path == "scenario.initial_state.history.warmup_s"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_authored_schedule_requires_a_schedule(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["initial_state"]["initial_commands"] = {
            "source": "authored_schedule"
        }
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and f.path == "scenario.initial_state.initial_commands.schedule"
                for f in failures
            ),
            msg=str(failures),
        )


class DriverRevisionPinningTests(unittest.TestCase):
    """A cloning-only participant pins its producer by revision."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.tactical_window_slower_lead.json").read_text(
                encoding="utf-8"
            )
        )

    def test_shipped_tactical_fixture_pins_the_producer(self) -> None:
        self.assertEqual(vsc.check_driver_revision_pinning(self.document), [])

    def test_cloning_only_participant_requires_producer_revision(self) -> None:
        document = json.loads(json.dumps(self.document))
        for participant in document["scenario"]["participants"]:
            if participant["driver"]["kind"] == "cloning_only_policy":
                participant["driver"].pop("producer_revision")
        failures = vsc.check_driver_revision_pinning(document)
        self.assertTrue(
            any(
                f.check == "driver_revision_pinning"
                and f.path == "scenario.participants.2.driver"
                for f in failures
            ),
            msg=str(failures),
        )


if __name__ == "__main__":
    unittest.main()
