#!/usr/bin/env python3
"""Tests for fixtures/observation/validate_observation_contract.py.

Ownership: fixtures/observation/** (PLAN.md M0.9, job
8667d71d-5817-4955-b069-aed859c8d8f8).

Run from the repository root with::

    python3 -m unittest discover -s fixtures/observation/tests -t .

or via fixtures/observation/run_tests.sh. Standard library only.

The suite pins five things:

* every positive fixture validates cleanly against schemas/observation;
* every negative fixture is rejected with exactly the failure set its
  .expected.json sidecar declares;
* the record schema's ordered feature layout and constants load as the single
  source of truth (64 features, 18/12/7 traffic ages, the 70/35 m neighbor
  window, the normalization scales);
* the validator's own machinery behaves: duplicate JSON members are rejected,
  the content hash is canonical and order-independent, --update-hashes rewrites
  a stale hash, schema failures short-circuit semantic checks, $ref resolves
  the stable_id pattern, and an unimplemented expectation check is reported;
* the audit remediations stay remediated: non-finite JSON is rejected (at
  parse and in the evaluator), schema-form additionalProperties is applied,
  declared per-feature kinds/ranges and the neighbor window are enforced, an
  omitted optional field fails gracefully instead of crashing, empty or
  bogus reset defaults are rejected, and 'measured' metrics cannot ride in a
  fixture file.
"""

from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve()
FIXTURES_DIR = HERE.parents[1]
REPO_ROOT = HERE.parents[3]
sys.path.insert(0, str(FIXTURES_DIR))

import validate_observation_contract as voc  # noqa: E402

POSITIVE_DIR = FIXTURES_DIR / "positive"
NEGATIVE_DIR = FIXTURES_DIR / "negative"
SCHEMAS_DIR = REPO_ROOT / "schemas" / "observation"


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
        cls.contracts = voc.load_contracts(SCHEMAS_DIR)

    def test_positive_fixtures_exist(self) -> None:
        self.assertGreaterEqual(len(positive_paths()), 1)

    def test_each_positive_fixture_validates(self) -> None:
        for path in positive_paths():
            with self.subTest(fixture=path.name):
                self.assertEqual(voc.validate_positive(path, self.contracts), [])


class NegativeFixtureTests(unittest.TestCase):
    """Every negative fixture must fail exactly as its sidecar declares."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = voc.load_contracts(SCHEMAS_DIR)

    def test_negative_fixtures_exist(self) -> None:
        self.assertGreaterEqual(len(negative_paths()), 1)

    def test_each_negative_fixture_rejected_as_declared(self) -> None:
        for path in negative_paths():
            with self.subTest(fixture=path.name):
                _actual, report = voc.validate_negative(path, self.contracts)
                self.assertEqual(report, [], msg=f"{path.name} deviated from its sidecar")

    def test_negative_fixture_without_sidecar_is_reported(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            stray = Path(tmp) / "stray.json"
            stray.write_text(json.dumps({"schema_version": "1.0.0"}), encoding="utf-8")
            _actual, report = voc.validate_negative(stray, self.contracts)
            self.assertTrue(any(f.code == "missing-expectation" for f in report))


class FeatureLayoutTests(unittest.TestCase):
    """The record schema's ordered 64-feature layout is the source of truth."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = voc.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants

    def test_constants_match_the_specified_contract(self) -> None:
        self.assertEqual(self.constants.feature_count, 64)
        self.assertEqual(self.constants.neighbor_slot_count, 4)
        self.assertEqual(self.constants.clip_min, -1.0)
        self.assertEqual(self.constants.clip_max, 1.0)
        self.assertEqual(
            dict(self.constants.traffic_age_ticks), {"rookie": 18, "racer": 12, "expert": 7}
        )

    def test_group_index_spans_are_derived_from_the_layout(self) -> None:
        self.assertEqual(self.constants.presence_indices, (32, 38, 44, 50))
        self.assertEqual(self.constants.route_gap_indices, (27, 33, 39, 45))
        self.assertEqual(self.constants.history_indices, (51, 52, 53, 54, 55, 56))
        self.assertEqual(
            self.constants.difficulty_hot, {"rookie": 57, "racer": 58, "expert": 59}
        )
        self.assertEqual(self.constants.style_hot, {"surge": 60, "switch": 61})

    def test_feature_layout_is_ordered_and_complete(self) -> None:
        features = self.constants.features
        self.assertEqual(len(features), 64)
        self.assertEqual([f["index"] for f in features], list(range(64)))

    def test_normalization_scales_match_opponent_ai(self) -> None:
        scales = self.constants.normalization_scales
        self.assertEqual(scales["lateral_speed_scale_m_s"], 20.0)
        self.assertEqual(scales["road_curvature_scale_m"], 100.0)
        self.assertEqual(scales["road_grade_scale"], 0.12)
        self.assertEqual(scales["road_bank_scale_rad"], 0.21)
        self.assertEqual(scales["neighbor_gap_scale_m"], 70.0)
        self.assertEqual(scales["history_forward_distance_scale_m"], 195.0)

    def test_neighbor_window_constants_are_loaded(self) -> None:
        self.assertEqual(self.constants.neighbor_ahead_m, 70.0)
        self.assertEqual(self.constants.neighbor_behind_m, 35.0)

    def test_neighbor_slot_size_is_derived_from_the_layout(self) -> None:
        # 24 neighbor features / 4 slots, read from the layout rather than
        # restated in the validator.
        self.assertEqual(self.constants.neighbor_slot_size, 6)
        self.assertIn("neighbor", self.constants.group_names)
        self.assertIn("history_lane_target_0p2s", self.constants.feature_names)
        self.assertNotIn("history_lane_targett_0p2s", self.constants.feature_names)


class RemediationRegressionTests(unittest.TestCase):
    """Each audit finding stays fixed (job 74b35657-1cb2-47c1-8753-ed569921f41f)."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = voc.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants

    def _fixture(self) -> dict:
        return json.loads(
            (POSITIVE_DIR / "fixture.observation.surge_full_vector.json").read_text(encoding="utf-8")
        )

    def _validate(self, document: dict) -> list[voc.Failure]:
        import tempfile

        document["content_hash"] = voc.canonical_hash(document)
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "probe.json"
            target.write_text(json.dumps(document), encoding="utf-8")
            return voc.validate_positive(target, self.contracts)

    # B2: NaN / non-finite JSON
    def test_non_finite_json_is_rejected_at_parse(self) -> None:
        import tempfile

        for literal in ("NaN", "Infinity", "-Infinity"):
            with tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "nonfinite.json"
                path.write_text('{"a": %s}' % literal, encoding="utf-8")
                with self.assertRaises(voc.DocumentError, msg=literal):
                    voc.load_json(path)

    def test_evaluator_refuses_non_finite_numbers_in_memory(self) -> None:
        failures: list[voc.Failure] = []
        cache = voc.SchemaCache()
        context = voc.DocumentContext(
            root=self.contracts.record_schema, base_dir=self.contracts.schemas_dir
        )
        record = self._fixture()["records"][0]
        record["feature_vector"][62] = float("nan")
        voc.validate_node(
            self.contracts.record_schema, record, "records.0", context, failures, cache
        )
        self.assertTrue(
            any(f.code == "finite" and f.path == "records.0.feature_vector.62" for f in failures),
            msg=str(failures),
        )

    # B3: declared per-feature kinds and ranges
    def test_declared_kinds_and_ranges_are_enforced(self) -> None:
        probes = {
            6: (0.5, "boolean"),
            31: (-0.5, "neighbor width"),
            63: (-0.5, "occupancy fraction"),
            53: (0.5, "signed enum"),
        }
        for index, (value, label) in probes.items():
            with self.subTest(feature=index):
                document = self._fixture()
                document["records"][0]["feature_vector"][index] = value
                failures = self._validate(document)
                self.assertTrue(
                    any(
                        f.check == "feature_declared_ranges"
                        and f.path == "records.0.feature_vector"
                        for f in failures
                    ),
                    msg=f"{label} at {index} was accepted: {failures}",
                )

    # B4: the 70 m ahead / 35 m behind neighbor window
    def test_neighbor_window_rejects_outside_gaps(self) -> None:
        for raw, label in ((-42, "42 m behind"), (80, "80 m ahead")):
            with self.subTest(gap=label):
                document = self._fixture()
                record = document["records"][0]
                record["feature_vector"][27] = voc._clip(raw / 70.0, -1.0, 1.0)
                record["raw_inputs"]["27"] = raw
                del record["raw_inputs"]["28"]
                for i in range(33, 39):
                    record["feature_vector"][i] = 0
                record["masks"]["neighbor_slots"] = [1, 0, 0, 0]
                failures = self._validate(document)
                self.assertTrue(
                    any(f.check == "neighbor_window" for f in failures),
                    msg=f"{label} was accepted: {failures}",
                )

    def test_neighbor_window_accepts_the_inclusive_edges(self) -> None:
        # 35 m behind (-0.5) and 70 m ahead (1.0) are inside the window.
        fixture = {
            "records": [
                {
                    "feature_vector": [0.0] * 64,
                    "raw_inputs": {"27": -35, "33": 70},
                }
            ]
        }
        fixture["records"][0]["feature_vector"][27] = -0.5
        fixture["records"][0]["feature_vector"][32] = 1
        fixture["records"][0]["feature_vector"][33] = 1.0
        fixture["records"][0]["feature_vector"][38] = 1
        self.assertEqual(voc.check_neighbor_window(fixture, self.constants), [])

    # B6: reset defaults must be listed and name real layout entries
    def test_reset_defaults_must_be_listed_and_named(self) -> None:
        def masked_reset(defaults: list[str]) -> dict:
            document = self._fixture()
            record = document["records"][0]
            record["masks"]["history_valid"] = 0
            record["reset"]["post_reset_defaults_applied"] = True
            record["reset"]["reset_generation"] = 1
            record["reset"]["defaults_applied"] = defaults
            for i in range(51, 57):
                record["feature_vector"][i] = 0
            del record["raw_inputs"]["54"]
            del record["raw_inputs"]["55"]
            return document

        for defaults, label in (([], "empty"), (["history_lane_targett_0p2s"], "bogus name")):
            with self.subTest(defaults=label):
                failures = self._validate(masked_reset(defaults))
                self.assertTrue(
                    any(
                        f.check == "history_mask"
                        and f.path == "records.0.reset.defaults_applied"
                        for f in failures
                    ),
                    msg=f"{label} defaults were accepted: {failures}",
                )
        # The shipped post-reset fixture names real layout features and passes.
        shipped = json.loads(
            (POSITIVE_DIR / "fixture.observation.post_reset_masked.json").read_text(encoding="utf-8")
        )
        self.assertEqual(voc.validate_positive(
            POSITIVE_DIR / "fixture.observation.post_reset_masked.json", self.contracts), [])
        self.assertTrue(
            all(name in self.constants.feature_names for name in shipped["records"][0]["reset"]["defaults_applied"])
        )

    # B7: 'measured' metrics cannot ride in a fixture file
    def test_measured_metric_is_rejected(self) -> None:
        fixture = {
            "comparison": {
                "metrics": [{"name": "probe", "status": "measured"}]
            }
        }
        failures = voc.check_comparison_metrics(fixture)
        self.assertTrue(
            any(f.check == "comparison_metrics" and f.path == "comparison.metrics.0" for f in failures),
            msg=str(failures),
        )
        clean = {"comparison": {"metrics": [{"name": "probe", "status": "documented_initial_target"}]}}
        self.assertEqual(voc.check_comparison_metrics(clean), [])

    # B8: schema-form additionalProperties is applied by the evaluator
    def test_additional_properties_schema_form_is_applied(self) -> None:
        failures: list[voc.Failure] = []
        cache = voc.SchemaCache()
        context = voc.DocumentContext(
            root=self.contracts.record_schema, base_dir=self.contracts.schemas_dir
        )
        record = self._fixture()["records"][0]
        record["raw_inputs"]["0"] = "fast"
        voc.validate_node(
            self.contracts.record_schema, record, "records.0", context, failures, cache
        )
        self.assertTrue(
            any(f.code == "type" and f.path == "records.0.raw_inputs.0" for f in failures),
            msg=str(failures),
        )

    # B1: an omitted optional field fails gracefully, never crashes
    def test_omitted_optional_field_fails_without_crashing(self) -> None:
        document = self._fixture()
        del document["records"][0]["occupancy_encounter_gap_m"]
        document["unknowns"] = [
            u for u in document["unknowns"] if u["path"] != "records.0.occupancy_encounter_gap_m"
        ]
        failures = self._validate(document)
        self.assertTrue(
            any(
                f.check == "unknown_pairing"
                and f.path == "records.0.occupancy_encounter_gap_m"
                for f in failures
            ),
            msg=str(failures),
        )

    def test_cli_reports_the_omitted_field_as_a_failure_not_a_crash(self) -> None:
        # The documented exit-code contract: 1 = validation failures, and no
        # traceback on stderr (the pre-fix behavior was exit 1 + KeyError).
        import subprocess
        import tempfile

        document = self._fixture()
        del document["records"][0]["occupancy_encounter_gap_m"]
        document["unknowns"] = [
            u for u in document["unknowns"] if u["path"] != "records.0.occupancy_encounter_gap_m"
        ]
        document["content_hash"] = voc.canonical_hash(document)
        with tempfile.TemporaryDirectory() as tmp:
            positive = Path(tmp) / "positive"
            positive.mkdir()
            (positive / "probe.json").write_text(json.dumps(document), encoding="utf-8")
            negative = Path(tmp) / "negative"
            negative.mkdir()
            (negative / "bad_schema_version.json").write_text(
                (NEGATIVE_DIR / "bad_schema_version.json").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            (negative / "bad_schema_version.expected.json").write_text(
                (NEGATIVE_DIR / "bad_schema_version.expected.json").read_text(encoding="utf-8"),
                encoding="utf-8",
            )
            proc = subprocess.run(
                [
                    sys.executable,
                    str(FIXTURES_DIR / "validate_observation_contract.py"),
                    "--schemas",
                    str(SCHEMAS_DIR),
                    "--positive",
                    str(positive),
                    "--negative",
                    str(negative),
                ],
                capture_output=True,
                text=True,
            )
        self.assertEqual(proc.returncode, 1)
        self.assertNotIn("Traceback", proc.stderr)
        self.assertIn("occupancy_encounter_gap_m", proc.stdout)


class ValidatorMachineryTests(unittest.TestCase):
    """Unit tests for the pieces the fixture suites rely on."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.contracts = voc.load_contracts(SCHEMAS_DIR)
        cls.constants = cls.contracts.constants

    def test_duplicate_json_members_are_rejected(self) -> None:
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "duplicate.json"
            path.write_text('{"a": 1, "a": 2}', encoding="utf-8")
            with self.assertRaises(voc.DocumentError):
                voc.load_json(path)

    def test_content_hash_is_canonical_and_order_independent(self) -> None:
        first = {"b": 2, "a": 1, "content_hash": "sha256:" + "0" * 64}
        second = {"content_hash": "sha256:" + "0" * 64, "a": 1, "b": 2}
        self.assertEqual(voc.canonical_hash(first), voc.canonical_hash(second))
        changed = {"a": 1, "b": 3, "content_hash": "sha256:" + "0" * 64}
        self.assertNotEqual(voc.canonical_hash(first), voc.canonical_hash(changed))

    def test_schema_failure_short_circuits_semantics(self) -> None:
        # bad_feature_range is out of bounds for the schema; the semantic
        # normalization check must not also fire, so a negative fixture's
        # sidecar can pin the single intended rejection.
        path = NEGATIVE_DIR / "bad_feature_range.json"
        failures = voc.validate_positive(path, self.contracts)
        self.assertEqual([f.code for f in failures], ["maximum"])
        self.assertTrue(all(f.check is None for f in failures))

    def test_record_schema_rejects_bad_stable_id_via_ref(self) -> None:
        # Exercises $ref resolution into ../common.schema.json from the record
        # schema: a participant_id that is not a stable_id must fail 'pattern'.
        fixture = json.loads(
            (POSITIVE_DIR / "fixture.observation.surge_full_vector.json").read_text()
        )
        fixture["records"][0]["participant_id"] = "Not A Stable ID"
        failures: list[voc.Failure] = []
        cache = voc.SchemaCache()
        context = voc.DocumentContext(
            root=self.contracts.record_schema, base_dir=self.contracts.schemas_dir
        )
        voc.validate_node(
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

        source = POSITIVE_DIR / "fixture.observation.surge_full_vector.json"
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / source.name
            document = json.loads(source.read_text(encoding="utf-8"))
            document["content_hash"] = "sha256:" + "0" * 64
            target.write_text(json.dumps(document, indent=2), encoding="utf-8")
            voc.update_hashes(Path(tmp))
            self.assertEqual(voc.validate_positive(target, self.contracts), [])

    def test_unimplemented_expectation_check_is_reported(self) -> None:
        document = {
            "records": [{"observation_id": "x"}],
            "expectations": [
                {
                    "expectation_id": "expect.future",
                    "check": "not_a_real_check",
                    "path": "records.0",
                    "statement": "defense in depth",
                }
            ],
        }
        failures = voc.check_expectations_declared(document)
        self.assertTrue(any(f.check == "expectation_implemented" for f in failures))


if __name__ == "__main__":
    unittest.main()
