#!/usr/bin/env python3
"""Roadstorm Racer! car handling source-recipe checker tests.

Ownership: tools/car_recipe_schema/** and fixtures/car_recipe/**. Standard
library ``unittest`` only; no network, engine or third-party dependency.

Run directly (``python3 tests/test_car_recipe_schema.py -v``) or through
``../run_tests.sh``. The suite writes nothing into the repository; temporary
files live in a system temporary directory.
"""

from __future__ import annotations

import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any, Callable

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve()
ROOT = HERE.parents[3]
TOOL = ROOT / "tools" / "car_recipe_schema" / "validate_car_recipe.py"
FIXTURES = ROOT / "fixtures" / "car_recipe"
SCHEMAS = ROOT / "schemas"

_spec = importlib.util.spec_from_file_location("validate_car_recipe", TOOL)
assert _spec is not None and _spec.loader is not None
vcr = importlib.util.module_from_spec(_spec)
sys.modules["validate_car_recipe"] = vcr
_spec.loader.exec_module(vcr)


FIVE = (
    "max_yaw_rate_rad_s",
    "reverse_trigger_speed_m_s",
    "reverse_hold_time_s",
    "reverse_acceleration_m_s2",
    "reverse_top_speed_m_s",
)

EXPECTED_DIFF_PATHS = {
    "/schema_version",
    "/properties/schema_version/const",
    "/properties/handling/required",
    "/properties/handling/allOf",
} | {f"/properties/handling/properties/{field}" for field in FIVE}


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def base_document(version: str = "1.1.0") -> dict[str, Any]:
    """A complete, valid 1.1.0 recipe (the committed positive base)."""
    path = FIXTURES / "positive" / "example_rookie_finite.json"
    document = load_json(path)
    if version != "1.1.0":
        document = copy.deepcopy(document)
        document["schema_version"] = version
        for field in FIVE:
            document["handling"].pop(field, None)
        document["content_hash"] = vcr.content_hash_of(document)
    return document


def findings_for(document: dict[str, Any], mode: str = "schema") -> list[Any]:
    return vcr.validate_recipe_document(document, mode=mode)


def codes(findings: list[Any]) -> set[str]:
    return {finding.code for finding in findings}


def paths(findings: list[Any]) -> set[str]:
    return {finding.path for finding in findings}


def mutate(fn: Callable[[dict[str, Any]], None], version: str = "1.1.0") -> dict[str, Any]:
    document = base_document(version)
    fn(document)
    # Mutations change the canonical content; refresh the hash so tests assert
    # the intended defect rather than a stale-hash side effect.
    document["content_hash"] = vcr.content_hash_of(document)
    return document


def detachable_part(**overrides: Any) -> dict[str, Any]:
    """A complete detachable part; overrides inject one targeted defect."""
    part: dict[str, Any] = {
        "slot": "front_bumper",
        "mesh_id": "body.front_bumper",
        "lod_ids": ["body.front_bumper.lod0"],
        "attachment_transform": {},
        "impact_region": {},
        "thresholds": {
            "loosen_m_s": 5.0,
            "detach_single_m_s": 8.0,
            "detach_accumulated_m_s": 12.0,
        },
    }
    part.update(overrides)
    return part


def drop_unknown_entry(document: dict[str, Any], path: str) -> None:
    document["unknowns"] = [
        entry for entry in document["unknowns"] if entry.get("path") != path
    ]


# (label, mutation, expected code, expected path) for inherited schema members
# shared verbatim by 1.0.0 and 1.1.0.
INHERITED_DEFECTS = [
    (
        "missing_dimensions_wheelbase_m",
        lambda d: d["dimensions"].pop("wheelbase_m"),
        "missing-field",
        "dimensions.wheelbase_m",
    ),
    (
        "missing_dimensions_ground_clearance_m",
        lambda d: d["dimensions"].pop("ground_clearance_m"),
        "missing-field",
        "dimensions.ground_clearance_m",
    ),
    (
        "missing_dimensions_jump_envelope_m",
        lambda d: d["dimensions"].pop("jump_envelope_m"),
        "missing-field",
        "dimensions.jump_envelope_m",
    ),
    (
        "missing_contact_proxy_roof",
        lambda d: (
            d["contact_proxy"].pop("roof"),
            drop_unknown_entry(d, "contact_proxy.roof"),
        ),
        "missing-field",
        "contact_proxy.roof",
    ),
    (
        "missing_contact_proxy_underside",
        lambda d: (
            d["contact_proxy"].pop("underside"),
            drop_unknown_entry(d, "contact_proxy.underside"),
        ),
        "missing-field",
        "contact_proxy.underside",
    ),
    (
        "wrong_type_upgrades_engine",
        lambda d: d["upgrades"].__setitem__("engine", []),
        "bad-upgrades-engine",
        "upgrades.engine",
    ),
    (
        "wrong_type_upgrades_tires",
        lambda d: d["upgrades"].__setitem__("tires", []),
        "bad-upgrades-tires",
        "upgrades.tires",
    ),
    (
        "wrong_type_upgrades_chassis",
        lambda d: d["upgrades"].__setitem__("chassis", []),
        "bad-upgrades-chassis",
        "upgrades.chassis",
    ),
    (
        "wrong_type_upgrades_max_increase",
        lambda d: d["upgrades"].__setitem__("max_increase_percent", []),
        "bad-upgrades-max-increase",
        "upgrades.max_increase_percent",
    ),
    (
        "wrong_type_detachable_thresholds",
        lambda d: d["detachable_parts"].append(detachable_part(thresholds=[])),
        "bad-thresholds",
        "detachable_parts[0].thresholds",
    ),
]

# (label, mutation, protected paths) for strings the schemas allow to be empty
# because they carry no minLength; the checker must accept those empty strings.
INHERITED_VALID = [
    (
        "empty_contact_proxy_roof",
        lambda d: (
            d["contact_proxy"].__setitem__("roof", ""),
            drop_unknown_entry(d, "contact_proxy.roof"),
        ),
        {"contact_proxy.roof"},
    ),
    (
        "empty_contact_proxy_underside",
        lambda d: (
            d["contact_proxy"].__setitem__("underside", ""),
            drop_unknown_entry(d, "contact_proxy.underside"),
        ),
        {"contact_proxy.underside"},
    ),
    (
        "empty_detachable_mesh_id",
        lambda d: d["detachable_parts"].append(detachable_part(mesh_id="")),
        {"detachable_parts[0].mesh_id"},
    ),
    (
        "empty_surface_notes",
        lambda d: d["handling"]["surfaces"].append(
            {
                "surface_id": "tarmac",
                "lateral_grip_scale": 1.0,
                "drag_scale": 1.0,
                "notes": "",
            }
        ),
        {"handling.surfaces[0].notes"},
    ),
]


class DeepDiff:
    """Recursive structural diff producing shallowest divergence paths."""

    @staticmethod
    def run(left: Any, right: Any, path: str = "") -> set[str]:
        out: set[str] = set()
        if type(left) is not type(right):
            out.add(path)
            return out
        if isinstance(left, dict):
            for key in sorted(set(left) | set(right)):
                child = f"{path}/{key}"
                if key not in left or key not in right:
                    out.add(child)
                else:
                    out |= DeepDiff.run(left[key], right[key], child)
            return out
        if isinstance(left, list):
            if len(left) != len(right):
                out.add(path)
                return out
            for index, (a, b) in enumerate(zip(left, right)):
                out |= DeepDiff.run(a, b, f"{path}[{index}]")
            return out
        if left != right:
            out.add(path)
        return out


class SchemaDriftTests(unittest.TestCase):
    def test_deep_diff_is_limited_to_the_declared_contract_changes(self) -> None:
        old = load_json(SCHEMAS / "handling_config.schema.json")
        new = load_json(SCHEMAS / "handling_config_v1_1.schema.json")
        differences = DeepDiff.run(old, new)
        self.assertEqual(differences, EXPECTED_DIFF_PATHS)
        self.assertIn("/schema_version", differences)

    def test_root_metadata_matches_version_constant(self) -> None:
        new = load_json(SCHEMAS / "handling_config_v1_1.schema.json")
        self.assertEqual(new["schema_version"], "1.1.0")
        self.assertEqual(
            new["schema_version"],
            new["properties"]["schema_version"]["const"],
        )

    def test_root_title_and_description_are_unchanged(self) -> None:
        old = load_json(SCHEMAS / "handling_config.schema.json")
        new = load_json(SCHEMAS / "handling_config_v1_1.schema.json")
        self.assertEqual(old["title"], new["title"])
        self.assertEqual(old["description"], new["description"])

    def test_closed_shapes_are_preserved(self) -> None:
        old = load_json(SCHEMAS / "handling_config.schema.json")
        new = load_json(SCHEMAS / "handling_config_v1_1.schema.json")
        for document in (old, new):
            self.assertFalse(document["additionalProperties"])
            self.assertFalse(document["properties"]["handling"]["additionalProperties"])

    def test_five_schema_annotations(self) -> None:
        new = load_json(SCHEMAS / "handling_config_v1_1.schema.json")
        props = new["properties"]["handling"]["properties"]
        yaw = props["max_yaw_rate_rad_s"]
        self.assertEqual(yaw["unit"], "rad/s")
        self.assertEqual(
            yaw["oneOf"],
            [
                {"type": ["number", "null"], "exclusiveMinimum": 0},
                {
                    "type": "object",
                    "additionalProperties": False,
                    "required": ["unlimited"],
                    "properties": {"unlimited": {"const": True}},
                },
            ],
        )
        self.assertEqual(props["reverse_trigger_speed_m_s"], {"type": ["number", "null"], "minimum": 0, "maximum": 1})
        self.assertEqual(props["reverse_hold_time_s"], {"type": ["number", "null"], "minimum": 0.3})
        self.assertEqual(props["reverse_acceleration_m_s2"], {"type": ["number", "null"], "minimum": 0})
        self.assertEqual(props["reverse_top_speed_m_s"], {"type": ["number", "null"], "minimum": 0})
        required = new["properties"]["handling"]["required"]
        for field in FIVE:
            self.assertIn(field, required)
        self.assertEqual(len(required), 16)

    def test_cross_field_rule_shape(self) -> None:
        new = load_json(SCHEMAS / "handling_config_v1_1.schema.json")
        rules = new["properties"]["handling"]["allOf"]
        self.assertEqual(len(rules), 1)
        rule = rules[0]
        self.assertEqual(rule["if"]["required"], ["reverse_acceleration_m_s2"])
        self.assertEqual(rule["if"]["properties"]["reverse_acceleration_m_s2"], {"type": "number", "exclusiveMinimum": 0})
        self.assertEqual(rule["then"]["required"], ["reverse_top_speed_m_s"])
        self.assertEqual(rule["then"]["properties"]["reverse_top_speed_m_s"], {"type": "number", "exclusiveMinimum": 0})


class FixtureBehaviourTests(unittest.TestCase):
    def test_every_positive_fixture_is_schema_valid(self) -> None:
        for path in sorted((FIXTURES / "positive").glob("*.json")):
            with self.subTest(path=path.name):
                document, findings = vcr.load_json_document(path)
                self.assertIsNotNone(document)
                self.assertEqual(findings_for(document), [])

    def test_positive_content_hashes_recompute(self) -> None:
        for path in sorted((FIXTURES / "positive").glob("*.json")):
            with self.subTest(path=path.name):
                document = load_json(path)
                self.assertEqual(document["content_hash"], vcr.content_hash_of(document))

    def test_every_negative_fixture_is_rejected_in_schema_mode(self) -> None:
        for path in sorted((FIXTURES / "negative").glob("*.json")):
            with self.subTest(path=path.name):
                document, load_findings = vcr.load_json_document(path)
                if document is None:
                    self.assertTrue(load_findings)
                    continue
                self.assertTrue(findings_for(document), f"{path.name} unexpectedly passed")

    def test_finite_and_unlimited_positives_are_motor_ready(self) -> None:
        for name in ("example_rookie_finite.json", "example_rookie_unlimited.json"):
            with self.subTest(name=name):
                document = load_json(FIXTURES / "positive" / name)
                self.assertEqual(findings_for(document, mode="motor-ready"), [])

    def test_null_motor_inputs_are_schema_valid_but_not_motor_ready(self) -> None:
        document = load_json(FIXTURES / "positive" / "example_rookie_null_motor_inputs.json")
        self.assertEqual(findings_for(document), [])
        findings = findings_for(document, mode="motor-ready")
        self.assertIn("motor-input-unresolved", codes(findings))
        self.assertIn("handling.max_yaw_rate_rad_s", paths(findings))
        self.assertIn("handling.reverse_trigger_speed_m_s", paths(findings))

    def test_v1_0_0_motor_ready_names_all_five_missing_paths(self) -> None:
        document = load_json(FIXTURES / "positive" / "example_rookie_v1_0_0.json")
        self.assertEqual(findings_for(document), [])
        findings = findings_for(document, mode="motor-ready")
        self.assertIn("motor-input-missing", codes(findings))
        for field in FIVE:
            self.assertIn(f"handling.{field}", paths(findings))


class VersionDispatchTests(unittest.TestCase):
    def test_supported_versions_are_accepted(self) -> None:
        for version in ("1.0.0", "1.1.0"):
            with self.subTest(version=version):
                document = base_document(version)
                self.assertEqual(
                    [f for f in findings_for(document) if f.code == "unsupported-schema-version"],
                    [],
                )

    def test_unsupported_versions_are_refused(self) -> None:
        for version in ("2.0.0", "1.2", "1.1.0\n", "", None, 1.1):
            with self.subTest(version=version):
                document = base_document()
                document["schema_version"] = version
                findings = findings_for(document)
                self.assertIn("unsupported-schema-version", codes(findings))

    def test_no_migration_adds_five_fields_to_a_v1_0_0_recipe(self) -> None:
        document = base_document("1.0.0")
        self.assertNotIn("max_yaw_rate_rad_s", document["handling"])
        findings = findings_for(document)
        self.assertEqual(findings, [])
        # An injected 1.1.0 member is rejected by the closed 1.0.0 shape.
        document["handling"]["max_yaw_rate_rad_s"] = 2.5
        self.assertIn("unknown-member", codes(findings_for(document)))


class FiveFieldTests(unittest.TestCase):
    def test_missing_each_five_field_is_rejected(self) -> None:
        for field in FIVE:
            with self.subTest(field=field):
                document = mutate(lambda d, f=field: d["handling"].pop(f))
                findings = findings_for(document)
                self.assertIn("missing-field", codes(findings))
                self.assertIn(f"handling.{field}", paths(findings))

    def test_null_field_requires_matching_unknowns_entry(self) -> None:
        document = mutate(lambda d: d["handling"].__setitem__("max_yaw_rate_rad_s", None))
        findings = findings_for(document)
        self.assertIn("null-without-unknown", codes(findings))
        self.assertIn("handling.max_yaw_rate_rad_s", paths(findings))

        def add_entry(d: dict[str, Any]) -> None:
            d["handling"]["max_yaw_rate_rad_s"] = None
            d["unknowns"].append({"path": "handling.max_yaw_rate_rad_s", "reason": "not measured"})
        self.assertEqual(findings_for(mutate(add_entry)), [])

    def test_non_null_value_listed_as_unknown_is_rejected(self) -> None:
        def add_entry(d: dict[str, Any]) -> None:
            d["unknowns"].append({"path": "handling.max_yaw_rate_rad_s", "reason": "wrong"})
        findings = findings_for(mutate(add_entry))
        self.assertIn("resolved-but-unknown", codes(findings))

    def test_unresolved_unknown_path_is_rejected(self) -> None:
        def add_entry(d: dict[str, Any]) -> None:
            d["unknowns"].append({"path": "handling.does_not_exist", "reason": "typo"})
        self.assertIn("unresolved-unknown", codes(findings_for(mutate(add_entry))))

    def test_yaw_forms(self) -> None:
        bad = [
            ("zero", 0.0),
            ("negative", -1.0),
            ("string", "inf"),
            ("boolean", True),
            ("list", [1.0]),
            ("unlimited_false", {"unlimited": False}),
            ("unlimited_numeric_int", {"unlimited": 1}),
            ("unlimited_numeric_float", {"unlimited": 1.0}),
            ("unlimited_string", {"unlimited": "true"}),
            ("unlimited_extra_key", {"unlimited": True, "note": "x"}),
            ("unlimited_empty", {}),
        ]
        for label, value in bad:
            with self.subTest(label=label):
                document = mutate(lambda d, v=value: d["handling"].__setitem__("max_yaw_rate_rad_s", v))
                findings = findings_for(document)
                self.assertTrue(findings, f"{label} unexpectedly passed")

        good = [2.5, {"unlimited": True}, None]
        for value in good:
            with self.subTest(good=repr(value)):
                def set_value(d: dict[str, Any], v: Any = value) -> None:
                    d["handling"]["max_yaw_rate_rad_s"] = v
                    if v is None:
                        d["unknowns"].append(
                            {"path": "handling.max_yaw_rate_rad_s", "reason": "not measured"}
                        )
                self.assertEqual(findings_for(mutate(set_value)), [])

    def test_numeric_unlimited_sentinels_report_the_yaw_path(self) -> None:
        for value in ({"unlimited": 1}, {"unlimited": 1.0}):
            with self.subTest(value=value):
                document = mutate(
                    lambda d, v=value: d["handling"].__setitem__("max_yaw_rate_rad_s", v)
                )
                for mode in ("schema", "motor-ready"):
                    with self.subTest(mode=mode):
                        findings = findings_for(document, mode=mode)
                        yaw_findings = [
                            f for f in findings if f.path == "handling.max_yaw_rate_rad_s"
                        ]
                        self.assertTrue(yaw_findings)
                        self.assertIn("bad-yaw-rate", {f.code for f in yaw_findings})

    def test_numeric_unlimited_sentinels_are_refused_from_rehashed_files(self) -> None:
        for value in (1, 1.0, "true", False):
            for mode in ("schema", "motor-ready"):
                with self.subTest(value=value, mode=mode):
                    document = base_document()
                    document["handling"]["max_yaw_rate_rad_s"] = {"unlimited": value}
                    document["content_hash"] = vcr.content_hash_of(document)
                    with tempfile.TemporaryDirectory() as tmp:
                        path = Path(tmp) / "recipe.json"
                        path.write_text(json.dumps(document), encoding="utf-8")
                        findings = vcr.validate_recipe_file(path, mode=mode)
                    yaw_findings = [
                        f for f in findings if f.path == "handling.max_yaw_rate_rad_s"
                    ]
                    self.assertTrue(yaw_findings)
                    self.assertIn("bad-yaw-rate", {f.code for f in yaw_findings})

    def test_exact_boolean_unlimited_sentinel_is_accepted_from_rehashed_file(self) -> None:
        document = base_document()
        document["handling"]["max_yaw_rate_rad_s"] = {"unlimited": True}
        document["content_hash"] = vcr.content_hash_of(document)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "recipe.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            for mode in ("schema", "motor-ready"):
                with self.subTest(mode=mode):
                    self.assertEqual(vcr.validate_recipe_file(path, mode=mode), [])

    def test_non_finite_overflow_literal_is_rejected(self) -> None:
        document = base_document()
        document["handling"]["max_yaw_rate_rad_s"] = 1e999  # parses to inf
        findings = findings_for(document)
        self.assertIn("bad-yaw-rate", codes(findings))

    def test_reverse_bounds(self) -> None:
        cases = [
            ("reverse_trigger_speed_m_s", 1.0000001, "maximum"),
            ("reverse_hold_time_s", 0.2999999, "minimum"),
            ("reverse_acceleration_m_s2", -0.5, "minimum"),
            ("reverse_top_speed_m_s", -1.0, "minimum"),
        ]
        for field, value, _bound in cases:
            with self.subTest(field=field, value=value):
                document = mutate(lambda d, f=field, v=value: d["handling"].__setitem__(f, v))
                self.assertIn("bad-number", codes(findings_for(document)))

    def test_boundary_values_pass(self) -> None:
        def set_boundaries(d: dict[str, Any]) -> None:
            d["handling"]["reverse_trigger_speed_m_s"] = 1.0
            d["handling"]["reverse_hold_time_s"] = 0.3
            d["handling"]["reverse_acceleration_m_s2"] = 0.0
            d["handling"]["reverse_top_speed_m_s"] = 0.0
        self.assertEqual(findings_for(mutate(set_boundaries)), [])

        def zero_trigger(d: dict[str, Any]) -> None:
            d["handling"]["reverse_trigger_speed_m_s"] = 0.0
        self.assertEqual(findings_for(mutate(zero_trigger)), [])

    def test_cross_field_rule(self) -> None:
        def accel_top_zero(d: dict[str, Any]) -> None:
            d["handling"]["reverse_acceleration_m_s2"] = 2.0
            d["handling"]["reverse_top_speed_m_s"] = 0.0
        self.assertIn("reverse-cross-field", codes(findings_for(mutate(accel_top_zero))))

        def accel_top_null(d: dict[str, Any]) -> None:
            d["handling"]["reverse_acceleration_m_s2"] = 2.0
            d["handling"]["reverse_top_speed_m_s"] = None
            d["unknowns"].append({"path": "handling.reverse_top_speed_m_s", "reason": "not measured"})
        self.assertIn("reverse-cross-field", codes(findings_for(mutate(accel_top_null))))

        def accel_positive_top_positive(d: dict[str, Any]) -> None:
            d["handling"]["reverse_acceleration_m_s2"] = 2.0
            d["handling"]["reverse_top_speed_m_s"] = 5.0
        self.assertEqual(findings_for(mutate(accel_positive_top_positive)), [])

        def accel_zero_top_zero(d: dict[str, Any]) -> None:
            d["handling"]["reverse_acceleration_m_s2"] = 0.0
            d["handling"]["reverse_top_speed_m_s"] = 0.0
        self.assertEqual(findings_for(mutate(accel_zero_top_zero)), [])


class StructuralTests(unittest.TestCase):
    def test_root_extra_member_is_rejected(self) -> None:
        document = mutate(lambda d: d.__setitem__("extra", 1))
        self.assertIn("unknown-member", codes(findings_for(document)))

    def test_handling_extra_member_is_rejected(self) -> None:
        document = mutate(lambda d: d["handling"].__setitem__("extra", 1))
        self.assertIn("unknown-member", codes(findings_for(document)))

    def test_booleans_are_not_numbers(self) -> None:
        for field in ("braking_acceleration_m_s2", "mass_kg"):
            with self.subTest(field=field):
                if field == "mass_kg":
                    document = mutate(lambda d: d.__setitem__("mass_kg", True))
                else:
                    document = mutate(lambda d: d["handling"].__setitem__(field, True))
                self.assertIn("bad-number", codes(findings_for(document)))

    def test_integer_fields_accept_integral_values(self) -> None:
        def set_caps(d: dict[str, Any]) -> None:
            d["handling"]["contact_caps"]["solver_iterations"] = 8
            d["handling"]["contact_caps"]["overlap_passes"] = 2.0
        self.assertEqual(findings_for(mutate(set_caps)), [])

    def test_missing_required_section_is_rejected(self) -> None:
        document = mutate(lambda d: d.pop("upgrades"))
        self.assertIn("missing-field", codes(findings_for(document)))


class StrictParsingTests(unittest.TestCase):
    def _parse(self, text: str) -> list[Any]:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as handle:
            handle.write(text)
            path = Path(handle.name)
        try:
            document, findings = vcr.load_json_document(path)
        finally:
            path.unlink()
        if document is not None:
            return findings_for(document)
        return findings

    def test_duplicate_keys_are_rejected(self) -> None:
        findings = self._parse('{"schema_version": "1.1.0", "schema_version": "1.1.0"}')
        self.assertIn("invalid-json", codes(findings))

    def test_nan_and_infinity_literals_are_rejected(self) -> None:
        for literal in ("NaN", "Infinity", "-Infinity"):
            with self.subTest(literal=literal):
                findings = self._parse('{"x": ' + literal + "}")
                self.assertIn("invalid-json", codes(findings))

    def test_non_object_document_is_rejected(self) -> None:
        findings = self._parse("[1, 2, 3]")
        self.assertIn("not-an-object", codes(findings))


class ContentHashTests(unittest.TestCase):
    def test_tampered_value_without_rehash_is_rejected(self) -> None:
        document = base_document()
        document["mass_kg"] = 1250
        self.assertIn("content-hash-mismatch", codes(findings_for(document)))

    def test_recomputed_hash_is_accepted(self) -> None:
        document = base_document()
        document["content_hash"] = vcr.content_hash_of(document)
        self.assertEqual(findings_for(document), [])

    def test_stale_hash_fixture_is_rejected(self) -> None:
        path = FIXTURES / "negative" / "stale_content_hash.json"
        document, load_findings = vcr.load_json_document(path)
        self.assertIsNotNone(document)
        self.assertEqual(load_findings, [])
        self.assertIn("content-hash-mismatch", codes(findings_for(document)))


class MotorReadyTests(unittest.TestCase):
    def test_null_core_coefficient_is_refused(self) -> None:
        def null_core(d: dict[str, Any]) -> None:
            d["handling"]["drag"]["aerodynamic"] = None
            d["unknowns"].append({"path": "handling.drag.aerodynamic", "reason": "not measured"})
        findings = findings_for(mutate(null_core), mode="motor-ready")
        self.assertIn("motor-input-unresolved", codes(findings))
        self.assertIn("handling.drag.aerodynamic", paths(findings))

    def test_unlimited_yaw_is_motor_ready(self) -> None:
        document = mutate(lambda d: d["handling"].__setitem__("max_yaw_rate_rad_s", {"unlimited": True}))
        self.assertEqual(findings_for(document, mode="motor-ready"), [])

    def test_empty_acceleration_curve_is_not_motor_ready(self) -> None:
        document = mutate(lambda d: d["handling"].__setitem__("acceleration_curve", []))
        findings = findings_for(document, mode="motor-ready")
        self.assertIn("motor-input-empty", codes(findings))

    def test_acceleration_curve_speed_ordering_regressions(self) -> None:
        cases = [
            (
                "duplicate",
                lambda d: d["handling"]["acceleration_curve"][1].__setitem__("speed_m_s", 0.0),
            ),
            (
                "descending",
                lambda d: d["handling"]["acceleration_curve"][0].__setitem__("speed_m_s", 40.0),
            ),
            (
                "reversed",
                lambda d: d["handling"]["acceleration_curve"].reverse(),
            ),
        ]
        for label, apply in cases:
            with self.subTest(case=label):
                document = mutate(apply)
                # Schema mode keeps the historical shape-only acceptance.
                self.assertEqual(findings_for(document), [])
                findings = findings_for(document, mode="motor-ready")
                self.assertIn("motor-input-order", codes(findings))
                self.assertIn(
                    "handling.acceleration_curve[1].speed_m_s", paths(findings)
                )


class InheritedContractParityTests(unittest.TestCase):
    """Both source versions inherit every pre-1.1.0 member constraint unchanged."""

    VERSIONS = ("1.0.0", "1.1.0")
    MODES = ("schema", "motor-ready")

    def test_inherited_defects_are_rejected_in_every_version_and_mode(self) -> None:
        for version in self.VERSIONS:
            for label, apply, expected_code, expected_path in INHERITED_DEFECTS:
                for mode in self.MODES:
                    with self.subTest(version=version, mode=mode, case=label):
                        findings = findings_for(mutate(apply, version), mode=mode)
                        self.assertIn(expected_code, codes(findings))
                        self.assertIn(expected_path, paths(findings))

    def test_schema_consistent_empty_strings_are_valid_in_every_version(self) -> None:
        for version in self.VERSIONS:
            for label, apply, protected in INHERITED_VALID:
                for mode in self.MODES:
                    with self.subTest(version=version, mode=mode, case=label):
                        findings = findings_for(mutate(apply, version), mode=mode)
                        offenders = sorted(
                            finding.path for finding in findings if finding.path in protected
                        )
                        self.assertEqual(offenders, [])
                        if version == "1.1.0" or mode == "schema":
                            self.assertEqual([str(f) for f in findings], [])


class CommandLineTests(unittest.TestCase):
    def _run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(TOOL), *args],
            capture_output=True,
            text=True,
            timeout=60,
        )

    def test_positive_directory_exits_zero(self) -> None:
        result = self._run("--mode", "schema", str(FIXTURES / "positive"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 error(s)", result.stdout)

    def test_missing_path_exits_two(self) -> None:
        result = self._run(str(ROOT / "does" / "not" / "exist.json"))
        self.assertEqual(result.returncode, 2)

    def test_bad_usage_exits_two(self) -> None:
        result = self._run("--mode", "nonsense")
        self.assertEqual(result.returncode, 2)

    def test_failing_control_known_bad_input_exits_nonzero(self) -> None:
        """Deliberate control: a known-bad recipe must exit nonzero with a diagnostic."""
        with tempfile.TemporaryDirectory() as tmp:
            bad = Path(tmp) / "known_bad.json"
            document = base_document()
            document["handling"]["max_yaw_rate_rad_s"] = 0.0
            document["content_hash"] = vcr.content_hash_of(document)
            bad.write_text(json.dumps(document, indent=2), encoding="utf-8")
            result = self._run("--mode", "schema", str(bad))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.returncode, 1)
        combined = (result.stdout + result.stderr)[:4000]
        self.assertIn("bad-yaw-rate", combined)
        self.assertLessEqual(len(combined), 4000)


if __name__ == "__main__":
    unittest.main(verbosity=2)
