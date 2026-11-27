#!/usr/bin/env python3
"""Tests for fixtures/intent/validate_intent_contract.py.

Ownership: fixtures/intent/** (PLAN.md M0.9, job
8cfeb70f-e5b3-4cac-8b4c-83a933d0970b).

Run from the repository root with::

    python3 -m unittest discover -s fixtures/intent/tests -t .

or via fixtures/intent/run_tests.sh. Standard library only.

The suite pins three things:

* every positive fixture validates cleanly against schemas/intent;
* every negative fixture is rejected with exactly the failure set its
  .expected.json sidecar declares;
* the validator's own machinery behaves: constants come from the schema,
  the fixture schema's expectation enum matches the implemented checks,
  the metric vocabulary comes from the shared common schema, measured
  metric status and mismatched comparator bounds are rejected, duplicate
  JSON members are rejected, the content hash is canonical and
  order-independent, --update-hashes rewrites a stale hash, and schema
  failures short-circuit semantic checks.
"""

from __future__ import annotations

import json
import shutil
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
FIXTURES_DIR = HERE.parents[1]
REPO_ROOT = HERE.parents[3]
sys.path.insert(0, str(FIXTURES_DIR))

import validate_intent_contract as vic  # noqa: E402

POSITIVE_DIR = FIXTURES_DIR / "positive"
NEGATIVE_DIR = FIXTURES_DIR / "negative"
SCHEMAS_DIR = REPO_ROOT / "schemas" / "intent"


def positive_paths() -> list[Path]:
    return sorted(POSITIVE_DIR.glob("*.json"))


def negative_paths() -> list[Path]:
    return sorted(
        path
        for path in NEGATIVE_DIR.glob("*.json")
        if not path.name.endswith(".expected.json")
    )


class PositiveFixtureTests(unittest.TestCase):
    """Every authored-valid fixture must pass schema, semantics and hash."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vic.load_contracts(SCHEMAS_DIR)

    def test_positive_fixtures_exist(self) -> None:
        self.assertGreaterEqual(len(positive_paths()), 1)

    def test_each_positive_fixture_validates(self) -> None:
        for path in positive_paths():
            with self.subTest(fixture=path.name):
                self.assertEqual(vic.validate_positive(path, self.contracts), [])


class NegativeFixtureTests(unittest.TestCase):
    """Every negative fixture must fail exactly as its sidecar declares."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vic.load_contracts(SCHEMAS_DIR)

    def test_negative_fixtures_exist(self) -> None:
        self.assertGreaterEqual(len(negative_paths()), 1)

    def test_each_negative_fixture_rejected_as_declared(self) -> None:
        for path in negative_paths():
            with self.subTest(fixture=path.name):
                _actual, report = vic.validate_negative(path, self.contracts)
                self.assertEqual(report, [], msg=f"{path.name} deviated from its sidecar")

    def test_negative_fixture_without_sidecar_is_reported(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            stray = Path(tmp) / "stray.json"
            stray.write_text(json.dumps({"schema_version": "1.0.0"}), encoding="utf-8")
            _actual, report = vic.validate_negative(stray, self.contracts)
            self.assertTrue(any(f.code == "missing-expectation" for f in report))


class ValidatorMachineryTests(unittest.TestCase):
    """Unit tests for the pieces the fixture suites rely on."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = vic.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants

    def test_constants_match_the_specified_contract(self) -> None:
        self.assertEqual(self.constants.tactical_rate_hz, 5)
        self.assertEqual(self.constants.sampling_period_ticks, 12)
        self.assertEqual(self.constants.sampling_period_s, 0.2)
        self.assertEqual(self.constants.intent_staleness_ticks, 12)
        self.assertEqual(self.constants.commitment_min_s, 0.4)
        self.assertEqual(self.constants.commitment_follow_below, -1.0 / 3.0)
        self.assertEqual(self.constants.commitment_commit_above, 1.0 / 3.0)
        self.assertEqual(self.constants.drift_above, 0.25)
        self.assertEqual(self.constants.drift_below, -0.25)
        self.assertEqual(self.constants.lateral_margin_m, 0.5)
        self.assertEqual(self.constants.material_lane_change_car_widths, 0.1)
        self.assertEqual(self.constants.material_speed_change_fraction, 0.05)
        self.assertEqual(self.constants.commitment_min_ticks, 24)
        self.assertEqual(self.constants.safety_check_period_ticks, 1)
        self.assertEqual(dict(self.constants.traffic_age_ticks), {"rookie": 18, "racer": 12, "expert": 7})

    def test_observation_sources_index_the_shipped_records(self) -> None:
        # The source_observation check resolves against the shipped positive
        # observation fixtures, read-only, and only those.
        sources = self.contracts.observation_sources
        self.assertEqual(self.contracts.unreadable_observations, ())
        for observation_id in (
            "obs.t000500.ai_classic_2",
            "obs.t000800.ai_classic_4",
            "obs.t000996.ai_surge_1",
        ):
            self.assertIn(observation_id, sources)
        # Illustrative IDs the observation slice does not ship stay unresolvable.
        self.assertNotIn("obs.t000512.ai_classic_2", sources)
        self.assertNotIn("obs.t001008.ai_surge_1", sources)
        # Every resolvable link is unique.
        for observation_id, records in sources.items():
            self.assertEqual(len(records), 1, msg=observation_id)

    def test_duplicate_json_members_are_rejected(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "duplicate.json"
            path.write_text('{"a": 1, "a": 2}', encoding="utf-8")
            with self.assertRaises(vic.DocumentError):
                vic.load_json(path)

    def test_non_finite_json_is_rejected_at_parse(self) -> None:
        # NaN/Infinity are Python json extensions, not JSON; an intent record
        # carrying one must be refused instead of passing comparisons that are
        # false for NaN (for example a NaN decoded pace target).
        import tempfile

        for literal in ("NaN", "Infinity", "-Infinity"):
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "nonfinite.json"
                path.write_text('{"a": %s}' % literal, encoding="utf-8")
                with self.assertRaises(vic.DocumentError, msg=literal):
                    vic.load_json(path)

    def test_evaluator_refuses_non_finite_numbers_in_memory(self) -> None:
        failures: list[vic.Failure] = []
        cache = vic.SchemaCache()
        context = vic.DocumentContext(
            root=self.contracts.record_schema, base_dir=self.contracts.schemas_dir
        )
        document = json.loads(
            (POSITIVE_DIR / "fixture.intent.classic_wait_hold.json").read_text()
        )
        document["records"][0]["lateral"]["lateral_target_norm"] = float("nan")
        vic.validate_node(
            self.contracts.record_schema,
            document["records"][0],
            "records.0",
            context,
            failures,
            cache,
        )
        self.assertTrue(
            any(
                f.code == "finite"
                and f.path == "records.0.lateral.lateral_target_norm"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_content_hash_is_canonical_and_order_independent(self) -> None:
        first = {"b": 2, "a": 1, "content_hash": "sha256:" + "0" * 64}
        second = {"content_hash": "sha256:" + "0" * 64, "a": 1, "b": 2}
        self.assertEqual(vic.canonical_hash(first), vic.canonical_hash(second))
        changed = {"a": 1, "b": 3, "content_hash": "sha256:" + "0" * 64}
        self.assertNotEqual(vic.canonical_hash(first), vic.canonical_hash(changed))

    def test_schema_failure_short_circuits_semantics(self) -> None:
        # bad_lateral_range is out of bounds for the schema; the semantic decode
        # check must not also fire, so a negative fixture's sidecar can pin the
        # single intended rejection.
        path = NEGATIVE_DIR / "bad_lateral_range.json"
        failures = vic.validate_positive(path, self.contracts)
        self.assertEqual([f.code for f in failures], ["maximum"])
        self.assertTrue(all(f.check is None for f in failures))

    def test_record_schema_rejects_bad_stable_id_via_ref(self) -> None:
        # Exercises $ref resolution into ../common.schema.json from the record
        # schema: a participant_id that is not a stable_id must fail 'pattern'.
        fixture = json.loads((POSITIVE_DIR / "fixture.intent.classic_wait_hold.json").read_text())
        fixture["records"][0]["participant_id"] = "Not A Stable ID"
        failures: list[vic.Failure] = []
        cache = vic.SchemaCache()
        context = vic.DocumentContext(
            root=self.contracts.record_schema, base_dir=self.contracts.schemas_dir
        )
        vic.validate_node(
            self.contracts.record_schema,
            fixture["records"][0],
            "records.0",
            context,
            failures,
            cache,
        )
        self.assertTrue(
            any(f.code == "pattern" and f.path == "records.0.participant_id" for f in failures),
            msg=str(failures),
        )

    def test_update_hashes_repairs_a_stale_hash(self) -> None:
        import tempfile

        source = POSITIVE_DIR / "fixture.intent.post_reset_defaults.json"
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / source.name
            document = json.loads(source.read_text(encoding="utf-8"))
            document["content_hash"] = "sha256:" + "0" * 64
            target.write_text(json.dumps(document, indent=2), encoding="utf-8")
            vic.update_hashes(Path(tmp))
            self.assertEqual(vic.validate_positive(target, self.contracts), [])

    def test_unimplemented_expectation_check_is_reported(self) -> None:
        document = {
            "records": [{"intent_id": "x"}],
            "expectations": [
                {
                    "expectation_id": "expect.future",
                    "check": "not_a_real_check",
                    "path": "records.0",
                    "statement": "defense in depth",
                }
            ],
        }
        failures = vic.check_expectations_declared(document)
        self.assertTrue(any(f.check == "expectation_implemented" for f in failures))

    def test_expectation_enum_matches_the_implemented_checks(self) -> None:
        # The fixture schema's expectation enum is the declared contract; this
        # set is what actually runs. They must not drift apart in either
        # direction, so an unimplemented check cannot be declared and an
        # implemented check cannot go undeclared.
        schema = json.loads((SCHEMAS_DIR / vic.FIXTURE_SCHEMA_NAME).read_text(encoding="utf-8"))
        declared = set(schema["$defs"]["expectation"]["properties"]["check"]["enum"])
        self.assertEqual(declared, set(vic.IMPLEMENTED_CHECKS))

    def test_metric_vocabulary_comes_from_the_shared_schema(self) -> None:
        common = json.loads(
            (SCHEMAS_DIR.parent / vic.COMMON_SCHEMA_NAME).read_text(encoding="utf-8")
        )
        metric = common["$defs"]["acceptance_metric"]["properties"]
        vocabulary = self.contracts.constants.metric_vocabulary
        self.assertEqual(
            vocabulary.comparators, tuple(metric["comparator"]["enum"])
        )
        self.assertEqual(vocabulary.statuses, tuple(metric["status"]["enum"]))
        # 'measured' stays in the shared vocabulary (reference-run records need
        # it) but is not legal in a fixture file.
        self.assertIn("measured", vocabulary.statuses)
        self.assertNotIn("measured", vocabulary.fixture_statuses)

    def _mutated_positive(self, mutate) -> Path:
        """Copy a positive fixture, apply one mutation, refresh the hash."""
        import tempfile

        source = POSITIVE_DIR / "fixture.intent.classic_wait_hold.json"
        document = json.loads(source.read_text(encoding="utf-8"))
        mutate(document)
        document["content_hash"] = vic.canonical_hash(document)
        tmp = tempfile.mkdtemp()
        target = Path(tmp) / source.name
        target.write_text(json.dumps(document, indent=2), encoding="utf-8")
        self.addCleanup(lambda: shutil.rmtree(tmp, ignore_errors=True))
        return target

    def test_measured_metric_status_is_rejected(self) -> None:
        # intent_fixture.schema.json states that a metric with status 'measured'
        # is invalid in a fixture file; the JSON Schema subset cannot express it,
        # so the semantic check must.
        target = self._mutated_positive(
            lambda d: d["comparison"]["metrics"][0].__setitem__("status", "measured")
        )
        failures = vic.validate_positive(target, self.contracts)
        self.assertEqual(
            [(f.code, f.path, f.check) for f in failures],
            [("semantic", "comparison.metrics.0.status", "metric_status_honesty")],
        )

    def test_metric_comparator_shape_is_enforced(self) -> None:
        cases = {
            "report_with_threshold": (
                lambda d: d["comparison"]["metrics"][0].__setitem__("comparator", "report"),
                ("semantic", "comparison.metrics.0", "metric_shape"),
            ),
            "range_with_point_value": (
                lambda d: (
                    d["comparison"]["metrics"][0].__setitem__("comparator", "range"),
                    d["comparison"]["metrics"][0].__setitem__("value_min", 0.9),
                    d["comparison"]["metrics"][0].__setitem__("value_max", 1.1),
                ),
                ("semantic", "comparison.metrics.0.value", "metric_shape"),
            ),
            "inverted_range": (
                lambda d: (
                    d["comparison"]["metrics"][0].__setitem__("comparator", "ratio_range"),
                    d["comparison"]["metrics"][0].pop("value"),
                    d["comparison"]["metrics"][0].__setitem__("value_min", 1.1),
                    d["comparison"]["metrics"][0].__setitem__("value_max", 0.9),
                ),
                ("semantic", "comparison.metrics.0", "metric_shape"),
            ),
            "threshold_without_value": (
                lambda d: d["comparison"]["metrics"][0].pop("value"),
                ("semantic", "comparison.metrics.0.value", "metric_shape"),
            ),
            "threshold_with_range_bound": (
                lambda d: d["comparison"]["metrics"][0].__setitem__("value_min", 0.9),
                ("semantic", "comparison.metrics.0.value_min", "metric_shape"),
            ),
        }
        for name, (mutate, expected) in cases.items():
            with self.subTest(case=name):
                failures = vic.validate_positive(self._mutated_positive(mutate), self.contracts)
                self.assertEqual([(f.code, f.path, f.check) for f in failures], [expected])

    def _run_check(self, check, base_name: str, mutate):
        """Copy a positive fixture, mutate it, run one semantic check on it."""
        document = json.loads(
            (POSITIVE_DIR / base_name).read_text(encoding="utf-8")
        )
        mutate(document)
        return check(document, self.constants)

    def test_pace_decode_consistency_rules(self) -> None:
        base = "fixture.intent.classic_wait_hold.json"

        def set_interval(document, low, high, target, note=None):
            pace = document["records"][0]["pace"]
            pace["speed_profile_interval_m_s"] = {"min": low, "max": high}
            pace["target_speed_m_s"] = target
            if note is not None:
                pace["note"] = note

        # A determined interval decodes the target: 20 + 0.5 x (60 - 20) = 40.
        failures = self._run_check(
            vic.check_pace_decode_consistency,
            base,
            lambda d: set_interval(d, 20, 60, 40.0),
        )
        self.assertEqual(failures, [])
        # Inverted interval.
        failures = self._run_check(
            vic.check_pace_decode_consistency,
            base,
            lambda d: set_interval(d, 60, 20, 40.0),
        )
        self.assertTrue(
            any("inverted" in f.message for f in failures), msg=str(failures)
        )
        # Wrong decode.
        failures = self._run_check(
            vic.check_pace_decode_consistency,
            base,
            lambda d: set_interval(d, 20, 60, 45.0),
        )
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0].path, "records.0.pace.target_speed_m_s")
        # Correction whose proposed value is not the pre-safety decode.
        def wrong_correction_decode(document):
            set_interval(document, 20, 60, 40.0)
            document["records"][0]["safety"]["corrections"] = [
                {
                    "field": "pace.target_speed_m_s",
                    "category": "physical_capability",
                    "proposed": 45,
                    "applied": 40,
                    "material": True,
                    "note": None,
                }
            ]

        failures = self._run_check(
            vic.check_pace_decode_consistency, base, wrong_correction_decode
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.safety.corrections.0.proposed"]
        )
        # Negative proposed/applied speed.
        def negative_speed(document):
            set_interval(document, 20, 60, 40.0)
            document["records"][0]["safety"]["corrections"] = [
                {
                    "field": "pace.target_speed_m_s",
                    "category": "physical_capability",
                    "proposed": -10,
                    "applied": 40,
                    "material": True,
                    "note": None,
                }
            ]

        failures = self._run_check(
            vic.check_pace_decode_consistency, base, negative_speed
        )
        self.assertTrue(
            any("cannot be negative" in f.message for f in failures), msg=str(failures)
        )
        # A determined target without a ratified interval.
        failures = self._run_check(
            vic.check_pace_decode_consistency,
            base,
            lambda d: d["records"][0]["pace"].__setitem__("target_speed_m_s", 30.0),
        )
        self.assertEqual(len(failures), 1)
        # A pace correction without a ratified interval.
        failures = self._run_check(
            vic.check_pace_decode_consistency,
            base,
            lambda d: d["records"][0]["safety"]["corrections"].append(
                {
                    "field": "pace.target_speed_m_s",
                    "category": "road",
                    "proposed": 30,
                    "applied": 25,
                    "material": True,
                    "note": None,
                }
            ),
        )
        self.assertEqual(len(failures), 1)

    def test_commitment_hold_rules(self) -> None:
        base = "fixture.intent.classic_wait_hold.json"

        def commit_then_hold(document):
            first = document["records"][0]["commitment"]
            first["commitment_raw"] = 0.5
            first["label"] = "commit_pass"
            first["executed_label"] = "commit_pass"
            first["commit_started_tick"] = 500
            second = document["records"][1]["commitment"]
            second["commitment_raw"] = 0.0
            second["label"] = "wait"
            second["executed_label"] = "commit_pass"
            second["commit_started_tick"] = 500

        # The proposed decode moved to wait but the 0.4 s minimum holds.
        failures = self._run_check(vic.check_commitment_hold, base, commit_then_hold)
        self.assertEqual(failures, [])

        # Early lapse without a hazard interruption.
        def commit_then_lapse(document):
            commit_then_hold(document)
            second = document["records"][1]["commitment"]
            second["executed_label"] = "wait"
            second["commit_started_tick"] = None

        failures = self._run_check(vic.check_commitment_hold, base, commit_then_lapse)
        self.assertEqual(
            [(f.path, f.check) for f in failures],
            [("records.1.commitment", "commitment_hold")],
        )

        # The same early release is legal when a hazard interrupted it.
        def commit_then_interrupted_release(document):
            commit_then_lapse(document)
            second = document["records"][1]["commitment"]
            second["interrupted"] = True
            second["interruption_reason"] = "lead car moved left into the passing room"

        failures = self._run_check(
            vic.check_commitment_hold, base, commit_then_interrupted_release
        )
        self.assertEqual(failures, [])

        # A commitment may only start from its own threshold decode.
        failures = self._run_check(
            vic.check_commitment_hold,
            "fixture.intent.post_reset_defaults.json",
            lambda d: d["records"][0]["commitment"].update(
                {
                    "commitment_raw": 0.0,
                    "label": "wait",
                    "executed_label": "commit_pass",
                    "commit_started_tick": 800,
                }
            ),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.commitment.executed_label"]
        )

        # A restart inside the minimum is an early lapse of the old commitment.
        def commit_then_restart(document):
            commit_then_hold(document)
            second = document["records"][1]["commitment"]
            second["commitment_raw"] = 0.5
            second["label"] = "commit_pass"
            second["commit_started_tick"] = 512

        failures = self._run_check(vic.check_commitment_hold, base, commit_then_restart)
        self.assertEqual(
            [f.path for f in failures], ["records.1.commitment"]
        )

        # Interruption and reason must agree in both directions.
        for interrupted, reason in ((True, None), (False, "a hazard")):
            failures = self._run_check(
                vic.check_commitment_hold,
                base,
                lambda d, i=interrupted, r=reason: d["records"][0]["commitment"].update(
                    {"interrupted": i, "interruption_reason": r}
                ),
            )
            self.assertEqual(
                [f.path for f in failures],
                ["records.0.commitment.interruption_reason"],
                msg=f"interrupted={interrupted} reason={reason}",
            )

    def test_executed_drift_preference_rules(self) -> None:
        base = "fixture.intent.classic_wait_hold.json"
        # Outside the retain band the executed preference must match the label.
        failures = self._run_check(
            vic.check_executed_drift_preference,
            base,
            lambda d: d["records"][0]["drift"].__setitem__("executed_preference", "drift"),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.drift.executed_preference"]
        )
        # Retain with masked post-reset history resolves to 'none'.
        failures = self._run_check(
            vic.check_executed_drift_preference,
            "fixture.intent.post_reset_defaults.json",
            lambda d: d["records"][0]["drift"].__setitem__("executed_preference", "grip"),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.drift.executed_preference"]
        )
        # Retain with valid history keeps a prior drift/grip preference; 'none'
        # is legal only when the reset masked the history.
        failures = self._run_check(
            vic.check_executed_drift_preference,
            "fixture.intent.classic_fallback_substitution.json",
            lambda d: d["records"][0]["drift"].__setitem__("executed_preference", "none"),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.drift.executed_preference"]
        )

    def test_correction_shape_rules(self) -> None:
        base = "fixture.intent.classic_wait_hold.json"

        def duplicate_field(document, field):
            correction = {
                "field": field,
                "category": "physical_capability",
                "proposed": 40.0,
                "applied": 40.0,
                "material": False,
                "note": None,
            }
            document["records"][0]["safety"]["corrections"] = [
                dict(correction),
                dict(correction),
            ]

        # One entry per corrected field: a second pace entry is rejected.
        failures = self._run_check(
            vic.check_correction_shape,
            base,
            lambda d: duplicate_field(d, "pace.target_speed_m_s"),
        )
        self.assertEqual(
            [(f.path, f.check) for f in failures],
            [("records.0.safety.corrections", "correction_shape")],
        )
        # The same rule covers lateral corrections.
        failures = self._run_check(
            vic.check_correction_shape,
            base,
            lambda d: duplicate_field(d, "lateral.decoded_offset_m"),
        )
        self.assertEqual(
            [(f.path, f.check) for f in failures],
            [("records.0.safety.corrections", "correction_shape")],
        )
        # Distinct fields remain legal.
        def distinct_fields(document):
            document["records"][0]["safety"]["corrections"] = [
                {"field": "lateral.decoded_offset_m", "category": "road",
                 "proposed": 3.65, "applied": 3.2, "material": True, "note": None},
                {"field": "pace.target_speed_m_s", "category": "physical_capability",
                 "proposed": 40.0, "applied": 40.0, "material": False, "note": None},
            ]

        failures = self._run_check(
            vic.check_correction_shape, base, distinct_fields
        )
        self.assertEqual(failures, [])

    def test_intervention_window_rules(self) -> None:
        base = "fixture.intent.classic_wait_hold.json"
        failures = self._run_check(
            vic.check_intervention_window,
            base,
            lambda d: d["records"][0]["safety"]["interventions"].__setitem__(
                "ticks", [504, 506]
            ),
        )
        self.assertEqual(failures, [])
        for ticks in ([512], [499], [510, 505]):
            failures = self._run_check(
                vic.check_intervention_window,
                base,
                lambda d, t=ticks: d["records"][0]["safety"]["interventions"].__setitem__(
                    "ticks", t
                ),
            )
            self.assertEqual(
                [f.path for f in failures],
                ["records.0.safety.interventions.ticks"],
                msg=str(ticks),
            )

    def test_emergency_consistency_rules(self) -> None:
        base = "fixture.intent.classic_wait_hold.json"

        def substitute(document, kind, tick, persistent, reason="contact forced a reset"):
            emergency = document["records"][0]["safety"]["emergency"]
            emergency.update(
                {
                    "substituted": True,
                    "kind": kind,
                    "tick": tick,
                    "persistent": persistent,
                    "reason": reason,
                }
            )

        # A fresh emergency_stop substitution is coherent.
        failures = self._run_check(
            vic.check_emergency_consistency,
            base,
            lambda d: substitute(d, "emergency_stop", 502, False),
        )
        self.assertEqual(failures, [])
        # A Classic planner cannot fall back to Classic control.
        failures = self._run_check(
            vic.check_emergency_consistency,
            base,
            lambda d: substitute(d, "classic_fallback", 502, False, "invalid policy output"),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.safety.emergency.kind"]
        )
        # A learned producer may fall back to Classic control.
        failures = self._run_check(
            vic.check_emergency_consistency,
            "fixture.intent.surge_commit_pass.json",
            lambda d: substitute(d, "classic_fallback", 1000, False, "invalid policy output"),
        )
        self.assertEqual(failures, [])
        # A kind without a substitution.
        failures = self._run_check(
            vic.check_emergency_consistency,
            base,
            lambda d: d["records"][0]["safety"]["emergency"].__setitem__(
                "kind", "reset"
            ),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.safety.emergency.kind"]
        )
        # Persistence must agree with the preceding intent.
        def persistent_run(document, second_persistent):
            for index, tick, persistent in ((0, 502, False), (1, 514, second_persistent)):
                emergency = document["records"][index]["safety"]["emergency"]
                emergency.update(
                    {
                        "substituted": True,
                        "kind": "reset",
                        "tick": tick,
                        "persistent": persistent,
                        "reason": "contact forced a reset",
                    }
                )

        failures = self._run_check(
            vic.check_emergency_consistency, base, lambda d: persistent_run(d, True)
        )
        self.assertEqual(failures, [])
        failures = self._run_check(
            vic.check_emergency_consistency, base, lambda d: persistent_run(d, False)
        )
        self.assertEqual(
            [f.path for f in failures], ["records.1.safety.emergency.persistent"]
        )

    def test_source_observation_rules(self) -> None:
        base = "fixture.intent.classic_wait_hold.json"
        # A mismatched traffic age breaks the link.
        failures = self._run_check(
            vic.check_source_observation,
            base,
            lambda d: d["records"][0].__setitem__("traffic_age_ticks", 12),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.0.traffic_age_ticks"]
        )
        # A road width that disagrees with observation feature 14 x 20 m.
        failures = self._run_check(
            vic.check_source_observation,
            base,
            lambda d: d["context"].__setitem__("road_width_m", 11.0),
        )
        self.assertEqual([f.path for f in failures], ["context.road_width_m"])
        # Two records sharing one source observation.
        failures = self._run_check(
            vic.check_source_observation,
            base,
            lambda d: d["records"][1].__setitem__(
                "source_observation_id", "obs.t000500.ai_classic_2"
            ),
        )
        self.assertEqual(
            [f.path for f in failures], ["records.1.source_observation_id"]
        )
        # An unresolvable source passes only when declared illustrative.
        def declare(document):
            document["records"][0]["source_observation_id"] = "obs.t000504.ai_classic_2"
            document["illustrative_sources"] = list(
                document.get("illustrative_sources") or []
            ) + [
                {
                    "observation_id": "obs.t000504.ai_classic_2",
                    "reason": "illustrative only",
                }
            ]

        failures = self._run_check(vic.check_source_observation, base, declare)
        self.assertEqual(failures, [])
        # A source observation captured with the safe diagnostic fallback active
        # carries safe-default features, so its road width is not compared.
        def fallback_source(document):
            record = document["records"][0]
            record["participant_id"] = "ai.switch_3"
            record["source_observation_id"] = "obs.t001200.ai_switch_3"
            record["difficulty"] = "racer"
            record["style"] = "switch"
            record["traffic_age_ticks"] = 12
            record["generated_tick"] = 1200
            record["reset"]["history_valid"] = 0

        failures = self._run_check(vic.check_source_observation, base, fallback_source)
        self.assertEqual(failures, [])

    def test_expectation_path_may_reference_a_metric(self) -> None:
        document = {
            "records": [{"intent_id": "x"}],
            "comparison": {"metrics": [{"name": "m"}]},
            "expectations": [
                {
                    "expectation_id": "expect.shape",
                    "check": "metric_shape",
                    "path": "comparison.metrics.0",
                    "statement": "bounds match the comparator",
                },
                {
                    "expectation_id": "expect.absent",
                    "check": "metric_shape",
                    "path": "comparison.metrics.9",
                    "statement": "no such metric",
                },
            ],
        }
        failures = vic.check_expectations_declared(document)
        paths = [f.path for f in failures if f.check == "expectation_implemented"]
        self.assertEqual(paths, ["expectations.1.path"])


if __name__ == "__main__":
    unittest.main()
