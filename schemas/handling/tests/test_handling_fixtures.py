#!/usr/bin/env python3
"""Standard-library unittest suite for the handling fixture validator.

Ownership: schemas/handling/** (PLAN.md M0.9 handling-contract slice, job
b20cb153-94a8-4997-be00-1f8335daa1a0).

The suite has two halves:

* the shipped contract documents and the eight authored fixtures must
  validate with zero errors, and their content hashes must recompute;
* deliberately broken copies of a fixture must be rejected with specific
  finding codes, so the required-field, invalid-range and revision-identifier
  checks are proven to bite rather than merely existing.

Run with run_tests.sh or `python3 -m unittest discover` from this directory.
Original project code under the Unlicense.
"""

from __future__ import annotations

import copy
import json
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from validate_fixtures import (  # noqa: E402
    FIXTURE_SCHEMA_VERSION,
    REQUIRED_TOP_LEVEL,
    SCHEMA_DOCUMENT_NAME,
    Finding,
    content_hash_of,
    load_json_document,
    main,
    validate_fixture,
    validate_fixture_directory,
    validate_schema_document,
)

REPO_ROOT = HERE.parents[2]
FIXTURE_DIR = REPO_ROOT / "fixtures" / "handling"
SCHEMA_PATH = REPO_ROOT / "schemas" / "handling" / SCHEMA_DOCUMENT_NAME
SHIPPED_FIXTURES = sorted(FIXTURE_DIR.glob("*.json"))


def codes(findings: list[Finding]) -> set[str]:
    return {finding.code for finding in findings if finding.is_error}


def warning_codes(findings: list[Finding]) -> set[str]:
    return {finding.code for finding in findings if not finding.is_error}


class ShippedContractTests(unittest.TestCase):
    """The authored artifacts must be internally consistent."""

    def test_schema_document_is_valid(self) -> None:
        findings = validate_schema_document(SCHEMA_PATH)
        self.assertEqual([str(f) for f in findings], [], "schema document must validate cleanly")

    def test_every_shipped_fixture_is_valid(self) -> None:
        self.assertGreaterEqual(len(SHIPPED_FIXTURES), 8, "all eight BENCHMARKS handling fixtures must exist")
        for path in SHIPPED_FIXTURES:
            with self.subTest(fixture=path.name):
                findings = validate_fixture(path)
                self.assertEqual([str(f) for f in findings], [], f"{path.name} must validate with zero findings")

    def test_fixture_directory_is_valid(self) -> None:
        findings = validate_fixture_directory(FIXTURE_DIR)
        self.assertEqual([str(f) for f in findings], [])

    def test_content_hashes_recompute(self) -> None:
        for path in SHIPPED_FIXTURES:
            with self.subTest(fixture=path.name):
                document, findings = load_json_document(path)
                self.assertIsNotNone(document)
                self.assertEqual(findings, [])
                self.assertEqual(document["content_hash"], content_hash_of(document))

    def test_expected_families_are_covered(self) -> None:
        families = set()
        for path in SHIPPED_FIXTURES:
            document, _ = load_json_document(path)
            families.add(document["fixture_family"])
        self.assertEqual(
            families,
            {"straight", "sweeper", "hairpin", "esses", "gravel", "grounding", "contact", "draft"},
            "every BENCHMARKS handling-fixture table row must have a fixture",
        )

    def test_no_fixture_claims_measured_values(self) -> None:
        for path in SHIPPED_FIXTURES:
            with self.subTest(fixture=path.name):
                document, _ = load_json_document(path)
                self.assertNotEqual(document["status"], "measured")
                for metric in document["comparison"]["metrics"]:
                    self.assertNotEqual(metric.get("status"), "measured", f"{path.name}: {metric['name']}")

    def test_every_null_is_explained(self) -> None:
        for path in SHIPPED_FIXTURES:
            with self.subTest(fixture=path.name):
                document, _ = load_json_document(path)
                self.assertIn("unknowns", document)
                for unknown in document["unknowns"]:
                    self.assertTrue(unknown.get("reason"), f"{path.name}: every unknown needs a reason")

    def test_cli_default_run_passes(self) -> None:
        self.assertEqual(main([]), 0)


class MutationTests(unittest.TestCase):
    """Deliberately broken fixtures must be rejected with specific codes."""

    BASE = FIXTURE_DIR / "sweeper.json"

    def setUp(self) -> None:
        document, findings = load_json_document(self.BASE)
        self.assertEqual(findings, [])
        assert document is not None
        self.document = document
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def _validate(self, mutate=None, *, refresh_hash: bool = True) -> list[Finding]:
        document = copy.deepcopy(self.document)
        if mutate is not None:
            mutate(document)
        if refresh_hash and "content_hash" in document:
            document["content_hash"] = content_hash_of(document)
        path = Path(self.tmp.name) / "sweeper.json"
        path.write_text(json.dumps(document, indent=2), encoding="utf-8")
        return validate_fixture(path)

    def _validate_raw(self, text: str, name: str = "raw.json") -> list[Finding]:
        path = Path(self.tmp.name) / name
        path.write_text(text, encoding="utf-8")
        return validate_fixture(path)

    # -- required fields -------------------------------------------------

    def test_missing_required_field_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc.pop("revision"))
        self.assertIn("missing-field", codes(findings))

    def test_missing_geometry_member_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["geometry"].pop("segments"))
        self.assertIn("no-segments", codes(findings))

    def test_missing_finish_gate_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["timing_gates"].remove(next(g for g in doc["timing_gates"] if g["kind"] == "finish"))
        )
        self.assertIn("gate-finish-count", codes(findings))

    # -- revision identifiers --------------------------------------------

    def test_wrong_schema_version_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc.update(schema_version="0.9.0"))
        self.assertIn("bad-schema-version", codes(findings))

    def test_non_numeric_revision_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc.update(revision="1.0"))
        self.assertIn("bad-revision", codes(findings))

    def test_content_hash_tamper_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc.update(description="changed text"), refresh_hash=False)
        self.assertIn("content-hash-mismatch", codes(findings))

    def test_malformed_content_hash_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc.update(content_hash="sha256:abc"), refresh_hash=False)
        self.assertIn("bad-content-hash", codes(findings))

    def test_controller_revision_null_requires_unknown(self) -> None:
        # The shipped fixture already declares null + unknown; dropping the
        # unknown entry must be reported, not silently accepted.
        def mutate(doc: dict) -> None:
            doc["unknowns"] = [
                unknown
                for unknown in doc["unknowns"]
                if "controller_revision" not in unknown["path"]
            ]

        findings = self._validate(mutate)
        self.assertIn("unlisted-null", codes(findings))

    # -- invalid ranges ---------------------------------------------------

    def test_out_of_range_steer_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["runs"][0].update(
                driver={
                    "kind": "scripted_commands",
                    "command_schedule": [{"t_s": 0, "steer": 1.5, "throttle": 1}],
                }
            )
        )
        self.assertIn("bad-steer", codes(findings))

    def test_negative_radius_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["geometry"]["segments"][1].update(radius_m=-5))
        self.assertIn("bad-arc-radius", codes(findings))

    def test_over_360_degree_arc_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["geometry"]["segments"][1].update(angle_deg=400))
        self.assertIn("bad-arc-angle", codes(findings))

    def test_excess_grade_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["geometry"]["segments"][0].update(grade_percent=15))
        self.assertIn("bad-grade", codes(findings))

    def test_gate_beyond_segment_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["timing_gates"][2].update(arc_length_m=99999))
        self.assertIn("gate-beyond-segment", codes(findings))

    def test_unknown_surface_reference_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["geometry"]["segments"][0].update(surface_id="ice"))
        self.assertIn("unknown-surface", codes(findings))

    def test_standing_start_with_speed_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["runs"][0]["initial_state"].update(start_mode="standing", velocity_m_s=30)
        )
        self.assertIn("standing-start-velocity", codes(findings))

    def test_unknown_run_reference_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["expected_events"][0].update(applies_to_runs=["no_such_run"])
        )
        self.assertIn("unknown-run-reference", codes(findings))

    # -- honesty rules ----------------------------------------------------

    def test_unlisted_null_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["runs"][0]["initial_state"].update(velocity_m_s=None))
        self.assertIn("unlisted-null", codes(findings))

    def test_listed_null_is_accepted(self) -> None:
        def mutate(doc: dict) -> None:
            doc["runs"][0]["initial_state"].update(velocity_m_s=None)
            doc["unknowns"].append(
                {
                    "path": "runs[0].initial_state.velocity_m_s",
                    "reason": "test: undetermined until a recorded decision",
                    "blocking": True,
                }
            )

        findings = self._validate(mutate)
        self.assertEqual([str(f) for f in findings], [])

    def test_measured_metric_status_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["comparison"]["metrics"][0].update(status="measured")
        )
        self.assertIn("measured-status-in-fixture", codes(findings))

    def test_report_metric_with_threshold_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["comparison"]["metrics"][1].update(value=1.0)
        )
        self.assertIn("report-metric-with-threshold", codes(findings))

    def test_incomplete_range_metric_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["comparison"]["metrics"][0].pop("value_max"))
        self.assertIn("missing-metric-range", codes(findings))

    def test_inverted_range_metric_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["comparison"]["metrics"][0].update(value_min=2, value_max=1)
        )
        self.assertIn("inverted-metric-range", codes(findings))

    # -- closed objects (additionalProperties: false) ---------------------

    def test_unknown_top_level_member_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc.update(totally_unknown_top_level=1))
        self.assertIn("unknown-member", codes(findings))

    def test_unknown_run_member_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["runs"][0].update(bogus_member=True))
        self.assertIn("unknown-member", codes(findings))

    def test_unknown_metric_member_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["comparison"]["metrics"][0].update(target=1.0))
        self.assertIn("unknown-member", codes(findings))

    def test_unknown_unknown_entry_member_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["unknowns"][0].update(owner="someone"))
        self.assertIn("unknown-member", codes(findings))

    # -- barriers inside the authored length ---------------------------------

    def test_barrier_beyond_segment_is_rejected(self) -> None:
        document, findings = load_json_document(FIXTURE_DIR / "contact.json")
        self.assertEqual(findings, [])
        assert document is not None
        document["barriers"][0]["arc_length_m"] = 600  # segment is 500 m
        document["content_hash"] = content_hash_of(document)
        path = Path(self.tmp.name) / "contact.json"
        path.write_text(json.dumps(document, indent=2), encoding="utf-8")
        findings = validate_fixture(path)
        self.assertIn("barrier-beyond-segment", codes(findings))

    def test_barrier_extent_members_are_validated(self) -> None:
        document, findings = load_json_document(FIXTURE_DIR / "contact.json")
        self.assertEqual(findings, [])
        assert document is not None
        document["barriers"][0]["length_m"] = -1
        document["barriers"][1]["height_m"] = "tall"
        document["content_hash"] = content_hash_of(document)
        path = Path(self.tmp.name) / "contact.json"
        path.write_text(json.dumps(document, indent=2), encoding="utf-8")
        findings = validate_fixture(path)
        self.assertIn("bad-barrier-length", codes(findings))
        self.assertIn("bad-barrier-height", codes(findings))

    # -- metric bound shapes (schemas/common.schema.json acceptance_metric) ---

    def test_range_metric_with_value_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["comparison"]["metrics"][0].update(value=1.0))
        self.assertIn("unexpected-metric-value", codes(findings))

    def test_threshold_metric_with_bounds_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["comparison"]["metrics"][0].update(comparator="lte", value=1.05, value_min=0, value_max=2))
        self.assertIn("unexpected-metric-bound", codes(findings))

    def test_metric_without_description_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["comparison"]["metrics"][0].pop("description"))
        self.assertIn("bad-metric-description", codes(findings))

    def test_metric_without_status_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["comparison"]["metrics"][0].pop("status"))
        self.assertIn("bad-metric-status", codes(findings))

    # -- handling revision dependency -----------------------------------------

    def test_handling_revision_null_requires_unknown(self) -> None:
        def mutate(doc: dict) -> None:
            doc["unknowns"] = [
                unknown for unknown in doc["unknowns"] if unknown["path"] != "cars.handling_revision"
            ]

        findings = self._validate(mutate)
        self.assertIn("unlisted-null", codes(findings))

    def test_bad_handling_revision_is_rejected(self) -> None:
        findings = self._validate(lambda doc: doc["cars"].update(handling_revision=7))
        self.assertIn("bad-handling-revision", codes(findings))

    def test_handling_revision_string_is_accepted(self) -> None:
        def mutate(doc: dict) -> None:
            doc["cars"]["handling_revision"] = "1.0.0"

        findings = self._validate(mutate)
        self.assertEqual([str(f) for f in findings], [])

    # -- unknowns pairing, both directions -------------------------------------

    def test_unresolved_unknown_path_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["unknowns"].append(
                {"path": "surfaces[1].handling_modifiers", "reason": "test: stale path"}
            )
        )
        self.assertIn("unresolved-unknown", codes(findings))

    def test_unknown_entry_pointing_at_absent_section_is_rejected(self) -> None:
        findings = self._validate(
            lambda doc: doc["unknowns"].append(
                {"path": "geometry.segments[9].width_m", "reason": "test: no such segment"}
            )
        )
        self.assertIn("unresolved-unknown", codes(findings))

    # -- document encoding -------------------------------------------------

    def test_duplicate_json_members_are_rejected(self) -> None:
        text = self.BASE.read_text(encoding="utf-8")
        findings = self._validate_raw(text + '\n"revision": "9.9.9"\n')
        self.assertIn("invalid-json", codes(findings))

    def test_non_utf8_is_rejected(self) -> None:
        path = Path(self.tmp.name) / "binary.json"
        path.write_bytes(b'{"schema_version": "1.0.0", "x": "\xff\xfe"}')
        findings = validate_fixture(path)
        self.assertIn("invalid-encoding", codes(findings))

    # -- warnings ----------------------------------------------------------

    def test_few_paired_runs_is_a_warning_not_an_error(self) -> None:
        findings = self._validate(lambda doc: doc["comparison"].update(paired_runs_required=3))
        self.assertEqual(codes(findings), set())
        self.assertIn("few-paired-runs", warning_codes(findings))

    # -- CLI exit codes -----------------------------------------------------

    def test_cli_missing_path_exits_two(self) -> None:
        self.assertEqual(main(["/nonexistent/path/fixtures"]), 2)

    def test_cli_directory_with_errors_exits_one(self) -> None:
        def mutate(doc: dict) -> None:
            doc["schema_version"] = "0.9.0"

        document = copy.deepcopy(self.document)
        mutate(document)
        document["content_hash"] = content_hash_of(document)
        bad_dir = Path(self.tmp.name) / "bad"
        bad_dir.mkdir()
        (bad_dir / "broken.json").write_text(json.dumps(document), encoding="utf-8")
        self.assertEqual(main([str(bad_dir)]), 1)


class DraftConsistencyTests(unittest.TestCase):
    """Draft fixtures must agree with the GAME_DESIGN documented wake window."""

    BASE = FIXTURE_DIR / "draft.json"

    def setUp(self) -> None:
        document, findings = load_json_document(self.BASE)
        self.assertEqual(findings, [])
        assert document is not None
        self.document = document
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def _validate(self, mutate=None) -> list[Finding]:
        document = copy.deepcopy(self.document)
        if mutate is not None:
            mutate(document)
        document["content_hash"] = content_hash_of(document)
        path = Path(self.tmp.name) / "draft.json"
        path.write_text(json.dumps(document, indent=2), encoding="utf-8")
        return validate_fixture(path)

    def test_shipped_draft_fixture_is_consistent(self) -> None:
        # Independent fixture-content control: every run the shipped fixture
        # requires to become drafting-eligible sits inside the documented
        # 5-20 m wake window and cone.
        findings = self._validate()
        self.assertEqual([str(f) for f in findings], [])
        document = self.document
        required_runs: set[str] = set()
        for event in document["expected_events"]:
            if event.get("event") == "drafting_eligible" and event.get("required") is True:
                required_runs.update(event.get("applies_to_runs", []))
        self.assertEqual(required_runs, {"gap_5", "gap_10", "gap_20"})
        for run in document["runs"]:
            if run["run_id"] not in required_runs:
                continue
            leader = run["other_participants"][0]["pose"]["position_m"]
            ego = run["initial_state"]["position_m"]
            gap = abs(ego[2] - leader[2])
            self.assertGreaterEqual(gap, 5.0, f"{run['run_id']} gap {gap} is below the wake window")
            self.assertLessEqual(gap, 20.0, f"{run['run_id']} gap {gap} is above the wake window")

    def test_eligible_below_window_is_rejected(self) -> None:
        # Regression control for the repaired contradiction: the 4 m bracket
        # run must not be required to become drafting-eligible.
        def mutate(doc: dict) -> None:
            for event in doc["expected_events"]:
                if event.get("event") == "drafting_eligible" and event.get("applies_to_runs") == ["gap_4"]:
                    event["required"] = True

        findings = self._validate(mutate)
        self.assertIn("draft-eligible-outside-window", codes(findings))

    def test_eligible_above_window_is_rejected(self) -> None:
        def mutate(doc: dict) -> None:
            for event in doc["expected_events"]:
                if event.get("event") == "drafting_eligible" and event.get("applies_to_runs") == ["gap_21"]:
                    event["required"] = True

        findings = self._validate(mutate)
        self.assertIn("draft-eligible-outside-window", codes(findings))

    def test_eligible_outside_cone_is_rejected(self) -> None:
        # A run inside the window but beyond the documented cone and lateral
        # limit must not be required to become eligible either.
        def mutate(doc: dict) -> None:
            for run in doc["runs"]:
                if run["run_id"] == "gap_10":
                    run["other_participants"][0]["pose"]["position_m"][0] = 3.0

        findings = self._validate(mutate)
        self.assertIn("draft-eligible-outside-cone", codes(findings))

    def test_declared_window_contradicting_docs_is_rejected(self) -> None:
        def mutate(doc: dict) -> None:
            for metric in doc["comparison"]["metrics"]:
                if metric["name"] == "wake_gap_window_m":
                    metric["value_min"] = 4
                    metric["value_max"] = 21

        findings = self._validate(mutate)
        self.assertIn("wake-window-mismatch", codes(findings))

    def test_not_required_eligibility_is_never_flagged(self) -> None:
        # The control runs (4 m bracket, 21 m bracket, outside-cone) declare
        # required: false; no claim means nothing for geometry to contradict.
        findings = self._validate()
        self.assertNotIn("draft-eligible-outside-window", codes(findings))
        self.assertNotIn("draft-eligible-outside-cone", codes(findings))


class SchemaRevisionTests(unittest.TestCase):
    def test_validator_matches_schema_document_revision(self) -> None:
        document, findings = load_json_document(SCHEMA_PATH)
        self.assertEqual(findings, [])
        assert document is not None
        self.assertEqual(document["schema_version"], FIXTURE_SCHEMA_VERSION)
        self.assertEqual(document["properties"]["schema_version"]["const"], FIXTURE_SCHEMA_VERSION)

    def test_schema_requires_the_members_the_validator_requires(self) -> None:
        # Alignment control: members the validator treats as required are also
        # required by the text contract, so neither can silently drop them.
        document, findings = load_json_document(SCHEMA_PATH)
        self.assertEqual(findings, [])
        assert document is not None
        properties = document["properties"]
        self.assertIn("start_reference", properties["geometry"]["required"])
        self.assertIn("closed_loop", properties["geometry"]["required"])
        self.assertIn("purpose", document["$defs"]["timing_gate"]["required"])
        self.assertIn("paired_runs_required", document["$defs"]["comparison"]["required"])
        for field in REQUIRED_TOP_LEVEL:
            self.assertIn(field, document["required"])

    def test_common_schema_metric_bounds_match_validator(self) -> None:
        # Alignment control: the shared acceptance_metric definition encodes
        # the same comparator-dependent bound rules as validate_fixtures.py.
        document, findings = load_json_document(REPO_ROOT / "schemas" / "common.schema.json")
        self.assertEqual(findings, [])
        assert document is not None
        metric = document["$defs"]["acceptance_metric"]
        self.assertEqual(
            sorted(metric["required"]),
            sorted(["name", "description", "comparator", "status"]),
        )
        branches = {tuple(branch["if"]["properties"]["comparator"].get("enum", [branch["if"]["properties"]["comparator"].get("const")])): branch["then"] for branch in metric["allOf"]}
        self.assertEqual(branches[("eq", "lte", "gte", "lt", "gt")]["required"], ["value"])
        self.assertEqual(branches[("range", "ratio_range")]["required"], ["value_min", "value_max"])
        self.assertNotIn("required", branches[("report",)])


if __name__ == "__main__":
    unittest.main()
