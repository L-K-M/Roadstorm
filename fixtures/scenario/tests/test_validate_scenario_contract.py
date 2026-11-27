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
  splits, speed samples, car/loadout/assist/track/handling hashes);
* the 2026-11-27 second-pass remediation: matched comparisons are one
  evaluated slot plus alternative producer arms that are separate runs, not
  simultaneous co-located cars (comparison_arms and
  participant_pose_distinctness), the tick-level safety_interventions
  telemetry channel, and the track/handling hashes TECHNICAL_DESIGN requires
  alongside the car/loadout/assist hashes;
* the 2026-11-27 correction pass for review findings R1-R10: a reference
  capture declares exactly one calibration-driver subject, comparison arms are
  distinct BENCHMARKS producers with coherent style inputs, a tactical family
  needs a fixed context car, scenario and record course revisions agree,
  participant slots and record IDs are unique, duplicate unknowns entries are
  rejected, and standing-start records are exempt from medal arithmetic.
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
        "track_hash": FAKE_HASH,
        "handling_hash": FAKE_HASH,
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
                "safety_interventions",
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

    def test_sector_splits_must_sum_to_the_clean_lap_time(self) -> None:
        document = build_measured_record()
        lap = document["reference_records"][0]["results"]["laps"][0]
        lap["sector_splits_s"] = [100.0] * 4
        failures = run_record_checks(document, self.contracts)
        self.assertTrue(
            any(
                f.check == "clean_lap_accounting"
                and f.path == "reference_records.0.results.laps.0"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_sector_split_sum_within_rounding_bound_passes(self) -> None:
        # GAME_DESIGN stores interpolated crossings as integer microseconds and
        # rounds Arcade Rush budgets to milliseconds; with the coarser
        # documented millisecond granularity, four independent splits plus the
        # lap total can disagree by up to (4 + 1) x 0.5 ms = 2.5 ms. These
        # whole-millisecond splits sum to 40.002 s against a 40 s lap (2 ms),
        # inside the derived envelope.
        document = build_measured_record()
        lap = document["reference_records"][0]["results"]["laps"][0]
        lap["sector_splits_s"] = [10.001, 10.001, 10.001, 9.999]
        self.assertEqual(run_record_checks(document, self.contracts), [])

    def test_sector_split_sum_beyond_rounding_bound_is_rejected(self) -> None:
        # A systematic error above the derived rounding envelope - including a
        # full one-tick sector mistake - is rejected.
        for first_sector in (10.003, 10.017):
            document = build_measured_record()
            lap = document["reference_records"][0]["results"]["laps"][0]
            lap["sector_splits_s"] = [first_sector, 10.0, 10.0, 10.0]
            failures = run_record_checks(document, self.contracts)
            self.assertTrue(
                any(
                    f.check == "clean_lap_accounting"
                    and f.path == "reference_records.0.results.laps.0"
                    for f in failures
                ),
                msg=f"first_sector={first_sector}: {failures}",
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
    samples and car/loadout/assist hashes with each record, and
    TECHNICAL_DESIGN 'Content contracts' additionally retains track/handling
    hashes; the numbers stay synthetic arithmetic data from
    build_measured_record.
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

    def test_measured_record_needs_the_track_and_handling_hashes(self) -> None:
        # TECHNICAL_DESIGN 'Content contracts' lists track/handling hashes
        # alongside the car/loadout/assist ones; a measured record that loses
        # them has lost evidence the contract promises to keep.
        for name in ("track_hash", "handling_hash"):
            document = build_measured_record()
            document["reference_records"][0]["results"]["hashes"][name] = None
            failures = vsc.check_measured_evidence_completeness(document, self.constants)
            self.assertTrue(
                any(
                    f.check == "measured_evidence_completeness"
                    and f.path == "reference_records.0.results.hashes"
                    and name in f.message
                    for f in failures
                ),
                msg=f"{name}: {failures}",
            )

    def test_planned_records_carry_the_five_hashes_as_nulls_with_unknowns(self) -> None:
        # The shipped planned records represent both cited documents: revisions
        # in course/dependencies and all five content hashes in results.hashes,
        # null until capture tooling computes them.
        for name in (
            "fixture.scenario.reference_capture_flying.json",
            "fixture.scenario.arcade_rush_standing_start.json",
            "fixture.scenario.tactical_window_slower_lead.json",
        ):
            document = json.loads((POSITIVE_DIR / name).read_text(encoding="utf-8"
            ))
            for index, record in enumerate(document["reference_records"]):
                hashes = record["results"]["hashes"]
                self.assertEqual(
                    sorted(hashes),
                    [
                        "assist_hash",
                        "car_hash",
                        "handling_hash",
                        "loadout_hash",
                        "track_hash",
                    ],
                )
                for hash_name, value in hashes.items():
                    self.assertIsNone(value)
                    dotted = f"reference_records.{index}.results.hashes.{hash_name}"
                    self.assertIn(
                        dotted,
                        [entry["path"] for entry in document["unknowns"]],
                    )

    def test_tactical_fixture_declares_the_safety_intervention_channel(self) -> None:
        document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.tactical_window_slower_lead.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertIn(
            "safety_interventions",
            document["scenario"]["required_telemetry"],
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
                and f.path.endswith(".per_participant_state.2.slot")
                for f in failures
            ),
            msg=str(failures),
        )

    def test_ahead_slot_must_not_name_the_same_participant(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["participants"].append(
            {
                "slot": "traffic_1",
                "role": "traffic",
                "car_id": "car.balanced_starter",
                "loadout": "stock",
                "assists": "standard",
                "driver": {"kind": "scripted"},
            }
        )
        document["scenario"]["initial_state"]["per_participant_state"].append(
            {
                "slot": "traffic_1",
                "ahead_slot": "traffic_1",
                "forward_gap_m": 10,
                "lateral_offset_m": 2.0,
                "speed_m_s": 28.0,
                "heading_offset_deg": 0,
            }
        )
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and f.path.endswith(".per_participant_state.2.ahead_slot")
                and "itself" in f.message
                for f in failures
            ),
            msg=str(failures),
        )

    def test_equal_gap_convoy_with_distinct_named_predecessors_passes(self) -> None:
        # Both cars declare the same relative tuple, but each follows a
        # different named car: a legal evenly spaced convoy, not co-location.
        document = json.loads(json.dumps(self.document))
        for slot, ahead in (("merge_a", "lead"), ("merge_b", "evaluated")):
            document["scenario"]["participants"].append(
                {
                    "slot": slot,
                    "role": "traffic",
                    "car_id": "car.balanced_starter",
                    "loadout": "stock",
                    "assists": "standard",
                    "driver": {"kind": "scripted"},
                }
            )
            document["scenario"]["initial_state"]["per_participant_state"].append(
                {
                    "slot": slot,
                    "ahead_slot": ahead,
                    "forward_gap_m": 20,
                    "lateral_offset_m": 3.0,
                    "speed_m_s": 25.0,
                    "heading_offset_deg": 0,
                }
            )
        self.assertEqual(self._check(document), [])
        self.assertEqual(vsc.check_participant_pose_distinctness(document), [])

    def test_mutual_predecessor_references_are_not_banned(self) -> None:
        # A closed course has no absolute predecessor ordering, so mutual
        # names between distinct cars are not rejected here.
        document = json.loads(json.dumps(self.document))
        for slot, ahead in (("merge_a", "merge_b"), ("merge_b", "merge_a")):
            document["scenario"]["participants"].append(
                {
                    "slot": slot,
                    "role": "traffic",
                    "car_id": "car.balanced_starter",
                    "loadout": "stock",
                    "assists": "standard",
                    "driver": {"kind": "scripted"},
                }
            )
            document["scenario"]["initial_state"]["per_participant_state"].append(
                {
                    "slot": slot,
                    "ahead_slot": ahead,
                    "forward_gap_m": 10,
                    "lateral_offset_m": 0,
                    "speed_m_s": 30,
                    "heading_offset_deg": 0,
                }
            )
        self.assertEqual(
            [f for f in self._check(document) if f.path.endswith("ahead_slot")], []
        )

    def test_per_participant_slot_must_not_repeat(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["initial_state"]["per_participant_state"].append(
            {"slot": "evaluated", "speed_m_s": 30}
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

    def test_the_evaluated_slot_needs_an_entry(self) -> None:
        document = json.loads(json.dumps(self.document))
        entries = document["scenario"]["initial_state"]["per_participant_state"]
        entries[:] = [entry for entry in entries if entry["slot"] != "evaluated"]
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "initial_state_agreement"
                and f.path == "scenario.initial_state.per_participant_state"
                and "evaluated" in f.message
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
    """Every cloning-only driver - participant or comparison arm - pins its producer."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.tactical_window_slower_lead.json").read_text(
                encoding="utf-8"
            )
        )

    def test_shipped_tactical_fixture_pins_the_producer(self) -> None:
        self.assertEqual(vsc.check_driver_revision_pinning(self.document), [])

    def test_cloning_only_arm_requires_producer_revision(self) -> None:
        document = json.loads(json.dumps(self.document))
        arm = document["scenario"]["comparison"]["arms"][1]
        self.assertEqual(arm["arm_id"], "cloning_only")
        arm["driver"].pop("producer_revision")
        failures = vsc.check_driver_revision_pinning(document)
        self.assertTrue(
            any(
                f.check == "driver_revision_pinning"
                and f.path == "scenario.comparison.arms.1.driver"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_cloning_only_participant_requires_producer_revision(self) -> None:
        # A non-evaluated participant (fixed context traffic, say) driven by the
        # cloning-only producer is pinned the same way.
        document = json.loads(json.dumps(self.document))
        document["scenario"]["participants"].append(
            {
                "slot": "traffic_cloning",
                "role": "traffic",
                "car_id": "car.balanced_starter",
                "loadout": "stock",
                "assists": "standard",
                "driver": {"kind": "cloning_only_policy", "difficulty": "racer"},
            }
        )
        failures = vsc.check_driver_revision_pinning(document)
        self.assertTrue(
            any(
                f.check == "driver_revision_pinning"
                and f.path == "scenario.participants.2.driver"
                for f in failures
            ),
            msg=str(failures),
        )


class ComparisonArmsTests(unittest.TestCase):
    """A matched comparison is one evaluated slot plus alternative producer runs.

    BENCHMARKS 'Tactical comparison' compares Classic, cloning-only, Surge and
    Switch from matched initial states and histories. The compared producers
    are separate executions of the same scenario driving one evaluated slot;
    modeling them as simultaneous participants would co-locate the compared
    cars and break the matched histories.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.tactical_window_slower_lead.json").read_text(
                encoding="utf-8"
            )
        )

    def _check(self, document: dict | None = None) -> list[vsc.Failure]:
        return vsc.check_comparison_arms(document or self.document)

    def test_shipped_tactical_fixture_declares_one_slot_and_four_arms(self) -> None:
        scenario = self.document["scenario"]
        evaluated = [
            participant
            for participant in scenario["participants"]
            if participant["role"] == "evaluated"
        ]
        self.assertEqual([participant["slot"] for participant in evaluated], ["evaluated"])
        self.assertEqual(
            [arm["arm_id"] for arm in scenario["comparison"]["arms"]],
            ["classic", "cloning_only", "surge", "switch"],
        )
        self.assertEqual(scenario["comparison"]["evaluated_slot"], "evaluated")
        self.assertEqual(self._check(), [])

    def test_shipped_capture_fixture_needs_no_comparison(self) -> None:
        document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.reference_capture_flying.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(vsc.check_comparison_arms(document), [])

    def test_tactical_family_requires_a_comparison(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"].pop("comparison")
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "comparison_arms"
                and f.path == "scenario.comparison"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_evaluated_slot_must_name_the_evaluated_participant(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["comparison"]["evaluated_slot"] = "lead"
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "comparison_arms"
                and f.path == "scenario.comparison.evaluated_slot"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_only_one_participant_may_be_evaluated(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["participants"].append(
            {
                "slot": "evaluated_2",
                "role": "evaluated",
                "car_id": "car.balanced_starter",
                "loadout": "stock",
                "assists": "standard",
            }
        )
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "comparison_arms" and f.path == "scenario.participants"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_the_evaluated_slot_carries_no_driver_of_its_own(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["participants"][1]["driver"] = {
            "kind": "classic_planner",
            "difficulty": "racer",
            "style": "none",
        }
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "comparison_arms"
                and f.path == "scenario.participants.1.driver"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_context_participants_must_declare_their_driver(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["participants"][0].pop("driver")
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "comparison_arms"
                and f.path == "scenario.participants.0"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_arm_ids_must_be_distinguishable(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["comparison"]["arms"][3]["arm_id"] = "surge"
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "comparison_arms"
                and f.path == "scenario.comparison.arms.3.arm_id"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_a_tactical_comparison_needs_at_least_two_arms(self) -> None:
        document = json.loads(json.dumps(self.document))
        document["scenario"]["comparison"]["arms"] = document["scenario"]["comparison"][
            "arms"
        ][:1]
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "comparison_arms"
                and f.path == "scenario.comparison.arms"
                and "at least two" in f.message
                for f in failures
            ),
            msg=str(failures),
        )


class ParticipantPoseDistinctnessTests(unittest.TestCase):
    """Two entries sharing one named car ahead may not declare one relative pose."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.document = json.loads(
            (POSITIVE_DIR / "fixture.scenario.tactical_window_slower_lead.json").read_text(
                encoding="utf-8"
            )
        )

    def _check(self, document: dict | None = None) -> list[vsc.Failure]:
        return vsc.check_participant_pose_distinctness(document or self.document)

    def test_shipped_fixture_has_distinguishable_participants(self) -> None:
        self.assertEqual(self._check(), [])

    def _add_traffic(self, document, **pose):
        document["scenario"]["participants"].append(
            {
                "slot": "traffic_1",
                "role": "traffic",
                "car_id": "car.balanced_starter",
                "loadout": "stock",
                "assists": "standard",
                "driver": {"kind": "scripted"},
            }
        )
        entry = {
            "slot": "traffic_1",
            "forward_gap_m": 10,
            "lateral_offset_m": 0,
            "speed_m_s": 30,
            "heading_offset_deg": 0,
        }
        entry.update(pose)
        document["scenario"]["initial_state"]["per_participant_state"].append(entry)
        return document

    def test_identical_relative_poses_without_shared_reference_are_a_legal_convoy(self) -> None:
        # Each participant's forward_gap_m is measured against its own
        # predecessor, so identical tuples can be an evenly spaced convoy;
        # without a shared named ahead_slot they are not comparable.
        document = self._add_traffic(json.loads(json.dumps(self.document)))
        self.assertEqual(self._check(document), [])

    def test_identical_relative_poses_behind_the_same_car_are_rejected(self) -> None:
        document = self._add_traffic(json.loads(json.dumps(self.document)), ahead_slot="lead")
        failures = self._check(document)
        self.assertTrue(
            any(
                f.check == "participant_pose_distinctness"
                and f.path == "scenario.initial_state.per_participant_state.2.slot"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_different_named_predecessors_are_not_compared(self) -> None:
        document = self._add_traffic(
            json.loads(json.dumps(self.document)), ahead_slot="evaluated"
        )
        self.assertEqual(self._check(document), [])

    def test_entries_without_an_authored_pose_are_not_compared(self) -> None:
        document = json.loads(json.dumps(self.document))
        entries = document["scenario"]["initial_state"]["per_participant_state"]
        entries.append({"slot": "traffic_1", "note": "pose not authored"})
        entries.append({"slot": "traffic_2", "note": "pose not authored"})
        self.assertEqual(self._check(document), [])

    def test_shared_reference_with_equal_position_but_different_motion_is_rejected(self) -> None:
        # Position at t0 is fixed by the named predecessor, forward gap and
        # lateral offset. Speed and heading do not move a car, so they cannot
        # make a same-position pair distinguishable.
        for overridden in (
            {"speed_m_s": 29.0},
            {"heading_offset_deg": 5.0},
            {"speed_m_s": 29.0, "heading_offset_deg": 5.0},
        ):
            document = self._add_traffic(
                json.loads(json.dumps(self.document)), ahead_slot="lead", **overridden
            )
            failures = self._check(document)
            self.assertTrue(
                any(
                    f.check == "participant_pose_distinctness"
                    and f.path == "scenario.initial_state.per_participant_state.2.slot"
                    for f in failures
                ),
                msg=f"{overridden}: {failures}",
            )

    def test_same_position_without_shared_reference_is_not_compared(self) -> None:
        # Different predecessors mean the two equal positions are not one
        # place; this remains a legal convoy authoring.
        document = self._add_traffic(
            json.loads(json.dumps(self.document)), ahead_slot="evaluated"
        )
        self.assertEqual(self._check(document), [])

    def test_undetermined_gap_is_not_treated_as_equal(self) -> None:
        # A null/absent gap means the relative position is unknown, so it
        # must not be assumed equal to another undetermined entry.
        document = json.loads(json.dumps(self.document))
        for slot in ("traffic_1", "traffic_2"):
            document["scenario"]["participants"].append(
                {
                    "slot": slot,
                    "role": "traffic",
                    "car_id": "car.balanced_starter",
                    "loadout": "stock",
                    "assists": "standard",
                    "driver": {"kind": "scripted"},
                }
            )
            document["scenario"]["initial_state"]["per_participant_state"].append(
                {
                    "slot": slot,
                    "ahead_slot": "lead",
                    "lateral_offset_m": 3.5,
                    "speed_m_s": 25,
                    "heading_offset_deg": 0,
                }
            )
        self.assertEqual(self._check(document), [])


class ContractCorrectionTests(unittest.TestCase):
    """The 2026-11-27 correction pass rules (review findings R1-R10).

    These exercise the semantic checks added or tightened after the independent
    review of the b8c76b03 remediation: the reference-capture subject, producer
    arm identity/style coherence, the tactical context car, course-revision
    linkage, participant-slot and record-id uniqueness, duplicate unknowns
    entries, and the standing-start medal exemption.
    """

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vsc.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants
        cls.tactical = json.loads(
            (POSITIVE_DIR / "fixture.scenario.tactical_window_slower_lead.json").read_text(
                encoding="utf-8"
            )
        )
        cls.capture = json.loads(
            (POSITIVE_DIR / "fixture.scenario.reference_capture_flying.json").read_text(
                encoding="utf-8"
            )
        )

    def test_shipped_fixtures_satisfy_the_new_rules(self) -> None:
        for path in positive_paths():
            document = json.loads(path.read_text(encoding="utf-8"))
            with self.subTest(fixture=path.name):
                self.assertEqual(vsc.check_reference_capture_structure(document), [])
                self.assertEqual(vsc.check_comparison_arm_identity(document), [])
                self.assertEqual(vsc.check_tactical_context_required(document), [])
                self.assertEqual(vsc.check_participant_slot_uniqueness(document), [])
                self.assertEqual(vsc.check_reference_record_id_uniqueness(document), [])

    def test_learned_reference_subject_is_rejected(self) -> None:
        document = json.loads(json.dumps(self.capture))
        document["scenario"]["participants"][0]["driver"] = {
            "kind": "learned_policy",
            "difficulty": "racer",
            "style": "surge",
        }
        failures = vsc.check_reference_capture_structure(document)
        self.assertTrue(
            any(
                f.check == "reference_capture_structure"
                and f.path == "scenario.participants.0.driver.kind"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_two_subjects_or_traffic_are_rejected(self) -> None:
        extra = {
            "slot": "traffic_1",
            "role": "traffic",
            "car_id": "car.balanced_starter",
            "loadout": "stock",
            "assists": "standard",
            "driver": {"kind": "scripted"},
        }
        document = json.loads(json.dumps(self.capture))
        document["scenario"]["participants"].append(extra)
        failures = vsc.check_reference_capture_structure(document)
        self.assertTrue(
            any(
                f.check == "reference_capture_structure"
                and f.path == "scenario.participants"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_duplicate_producer_arm_is_rejected(self) -> None:
        document = json.loads(json.dumps(self.tactical))
        arms = document["scenario"]["comparison"]["arms"]
        arms[3]["driver"] = copy.deepcopy(arms[0]["driver"])
        failures = vsc.check_comparison_arm_identity(document)
        self.assertTrue(
            any(
                f.check == "comparison_arm_identity"
                and f.path == "scenario.comparison.arms.3.driver"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_arms_must_share_one_declared_difficulty(self) -> None:
        mixed = json.loads(json.dumps(self.tactical))
        mixed["scenario"]["comparison"]["arms"][0]["driver"]["difficulty"] = "expert"
        failures = vsc.check_comparison_arm_identity(mixed)
        self.assertTrue(
            any(
                f.check == "comparison_arm_identity"
                and f.path == "scenario.comparison.arms.1.driver.difficulty"
                for f in failures
            ),
            msg=str(failures),
        )

        missing = json.loads(json.dumps(self.tactical))
        missing["scenario"]["comparison"]["arms"][0]["driver"].pop("difficulty")
        failures = vsc.check_comparison_arm_identity(missing)
        self.assertTrue(
            any(
                f.check == "comparison_arm_identity"
                and f.path == "scenario.comparison.arms.0.driver.difficulty"
                for f in failures
            ),
            msg=str(failures),
        )

        # Two classic arms differing only by difficulty are the same producer
        # under unmatched conditions, not two distinct compared producers.
        duplicate = json.loads(json.dumps(self.tactical))
        duplicate["scenario"]["comparison"]["arms"] = [
            {
                "arm_id": "classic_a",
                "driver": {
                    "kind": "classic_planner",
                    "difficulty": "rookie",
                    "style": "none",
                },
            },
            {
                "arm_id": "classic_b",
                "driver": {
                    "kind": "classic_planner",
                    "difficulty": "expert",
                    "style": "none",
                },
            },
        ]
        failures = vsc.check_comparison_arm_identity(duplicate)
        self.assertTrue(
            any(
                f.check == "comparison_arm_identity"
                and f.path == "scenario.comparison.arms.1.driver.difficulty"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_classic_style_must_be_none_and_learned_style_required(self) -> None:
        classic = json.loads(json.dumps(self.tactical))
        classic["scenario"]["comparison"]["arms"][0]["driver"]["style"] = "surge"
        self.assertTrue(
            any(
                f.check == "comparison_arm_identity"
                and f.path == "scenario.comparison.arms.0.driver.style"
                for f in vsc.check_comparison_arm_identity(classic)
            )
        )
        learned = json.loads(json.dumps(self.tactical))
        learned["scenario"]["comparison"]["arms"][2]["driver"].pop("style")
        self.assertTrue(
            any(
                f.check == "comparison_arm_identity"
                and f.path == "scenario.comparison.arms.2.driver.style"
                for f in vsc.check_comparison_arm_identity(learned)
            )
        )

    def test_non_producer_arm_kind_is_rejected(self) -> None:
        document = json.loads(json.dumps(self.tactical))
        document["scenario"]["comparison"]["arms"][0]["driver"] = {"kind": "human_proxy"}
        failures = vsc.check_comparison_arm_identity(document)
        self.assertTrue(
            any(
                f.check == "comparison_arm_identity"
                and f.path == "scenario.comparison.arms.0.driver.kind"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_three_distinct_producers_still_pass(self) -> None:
        # The full four-producer set is a benchmark-level requirement across the
        # six families; one scenario may instantiate any subset of >= 2.
        document = json.loads(json.dumps(self.tactical))
        document["scenario"]["comparison"]["arms"] = [
            arm
            for arm in document["scenario"]["comparison"]["arms"]
            if arm["arm_id"] != "cloning_only"
        ]
        self.assertEqual(vsc.check_comparison_arm_identity(document), [])

    def test_tactical_family_needs_a_context_car(self) -> None:
        document = json.loads(json.dumps(self.tactical))
        document["scenario"]["participants"] = [
            p
            for p in document["scenario"]["participants"]
            if p["role"] == "evaluated"
        ]
        document["scenario"]["initial_state"]["per_participant_state"] = [
            e
            for e in document["scenario"]["initial_state"]["per_participant_state"]
            if e["slot"] == "evaluated"
        ]
        failures = vsc.check_tactical_context_required(document)
        self.assertTrue(
            any(
                f.check == "tactical_context_required"
                and f.path == "scenario.participants"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_course_revision_must_match_the_referenced_record(self) -> None:
        document = json.loads(json.dumps(self.tactical))
        document["scenario"]["course"]["course_revision"] = "course_rev_9"
        document["reference_records"][0]["course"]["course_revision"] = "course_rev_1"
        failures = vsc.check_reference_linkage(document)
        self.assertTrue(
            any(
                f.check == "reference_linkage"
                and f.path == "scenario.course.course_revision"
                for f in failures
            ),
            msg=str(failures),
        )
        document["scenario"]["course"]["course_revision"] = None
        document["reference_records"][0]["course"]["course_revision"] = None
        failures = vsc.check_reference_linkage(document)
        self.assertFalse(
            any(f.path == "scenario.course.course_revision" for f in failures)
        )

    def test_duplicate_participant_slot_is_rejected(self) -> None:
        document = json.loads(json.dumps(self.tactical))
        document["scenario"]["participants"].append(
            {
                "slot": "lead",
                "role": "traffic",
                "car_id": "car.balanced_starter",
                "loadout": "stock",
                "assists": "standard",
                "driver": {"kind": "scripted"},
            }
        )
        failures = vsc.check_participant_slot_uniqueness(document)
        self.assertTrue(
            any(
                f.check == "participant_slot_uniqueness"
                and f.path == "scenario.participants.2.slot"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_duplicate_record_id_is_rejected(self) -> None:
        document = json.loads(json.dumps(self.tactical))
        document["reference_records"].append(copy.deepcopy(document["reference_records"][0]))
        failures = vsc.check_reference_record_id_uniqueness(document)
        self.assertTrue(
            any(
                f.check == "reference_record_id_uniqueness"
                and f.path == "reference_records.1.record_id"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_duplicate_unknowns_path_is_rejected(self) -> None:
        document = json.loads(json.dumps(self.tactical))
        document["unknowns"].append(
            {"path": document["unknowns"][0]["path"], "reason": "conflicting reason"}
        )
        failures = vsc.check_null_unknown_pairing(document)
        self.assertTrue(
            any(
                f.check == "null_unknown_pairing"
                and f.path == document["unknowns"][0]["path"]
                and "2 times" in f.message
                for f in failures
            ),
            msg=str(failures),
        )

    def test_standing_start_medal_thresholds_do_not_apply(self) -> None:
        document = build_measured_record()
        record = document["reference_records"][0]
        record["kind"] = "standing_start_lap_set"
        for field in ("bronze_s", "silver_s", "gold_s"):
            record["derived_thresholds"][field] = None
            document["unknowns"].append(
                {
                    "path": f"reference_records.0.derived_thresholds.{field}",
                    "reason": "medal thresholds derive from the flying-lap median",
                }
            )
        failures = run_record_checks(document, self.contracts)
        self.assertFalse(
            any(f.check == "medal_threshold_arithmetic" for f in failures),
            msg=str(failures),
        )


if __name__ == "__main__":
    unittest.main()
