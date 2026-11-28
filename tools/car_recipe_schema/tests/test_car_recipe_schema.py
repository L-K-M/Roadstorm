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
import re
import subprocess
import sys
import tempfile
import unittest
from decimal import Decimal
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


BASE_FIXTURE_TEXT = (FIXTURES / "positive" / "example_rookie_finite.json").read_text(
    encoding="utf-8"
)


def write_recipe(directory: str, name: str, text: str) -> Path:
    path = Path(directory) / name
    path.write_text(text, encoding="utf-8")
    return path


def replace_number(text: str, key: str, literal: str) -> str:
    """Replace one numeric member's literal in a recipe text, keeping the text."""
    pattern = re.compile(rf"(\"{key}\":\s*)[^,\n]+")
    updated, count = pattern.subn(rf"\g<1>{literal}", text, count=1)
    assert count == 1, f"no numeric member {key!r} to replace"
    return updated


def insert_member(text: str, member_text: str) -> str:
    """Insert a root member before content_hash in a recipe text."""
    anchor = '  "content_hash"'
    assert anchor in text
    return text.replace(anchor, member_text + "\n" + anchor, 1)


def load_text(text: str) -> dict[str, Any]:
    """Parse a recipe text through the checker's strict loader."""
    with tempfile.TemporaryDirectory() as tmp:
        path = write_recipe(tmp, "recipe.json", text)
        document, findings = vcr.load_json_document(path)
    assert document is not None and findings == [], findings
    return document


def validate_text(text: str, mode: str = "schema") -> list[Any]:
    """Validate a recipe text through the file entry point."""
    with tempfile.TemporaryDirectory() as tmp:
        path = write_recipe(tmp, "recipe.json", text)
        return vcr.validate_recipe_file(path, mode=mode)


def validate_bytes(payload: bytes, mode: str = "motor-ready") -> list[Any]:
    """Validate raw recipe bytes through the file entry point."""
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "recipe.json"
        path.write_bytes(payload)
        return vcr.validate_recipe_file(path, mode=mode)


def rehash(text: str) -> str:
    """Rewrite a recipe text with a recomputed content_hash.

    Leaves only the defect under test: every other difference, including a stale
    hash, is removed.
    """
    document = load_text(text)
    document["content_hash"] = vcr.content_hash_of(document)
    return json.dumps(vcr.to_binary64(document), indent=2, ensure_ascii=False)


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


def pairs(findings: list[Any]) -> set[tuple[str, str]]:
    """Every (code, path) pair in a finding list."""
    return {(finding.code, finding.path) for finding in findings}


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


# (fixture file, expected code, expected path) for every negative fixture. The
# fixture loop asserts the declared defect rather than accepting any finding,
# so a fixture that starts failing for an unrelated reason is caught.
NEGATIVE_FIXTURE_EXPECTATIONS = {
    "accel_positive_top_null.json": (
        "reverse-cross-field",
        "handling.reverse_top_speed_m_s",
    ),
    "accel_positive_top_zero.json": (
        "reverse-cross-field",
        "handling.reverse_top_speed_m_s",
    ),
    "boolean_as_number.json": ("bad-number", "handling.braking_acceleration_m_s2"),
    "duplicate_key.json": ("invalid-json", ""),
    "extra_handling_member.json": ("unknown-member", "handling.extra_field"),
    "hold_below_minimum.json": ("bad-number", "handling.reverse_hold_time_s"),
    "missing_max_yaw_rate_rad_s.json": (
        "missing-field",
        "handling.max_yaw_rate_rad_s",
    ),
    "missing_reverse_acceleration_m_s2.json": (
        "missing-field",
        "handling.reverse_acceleration_m_s2",
    ),
    "missing_reverse_hold_time_s.json": (
        "missing-field",
        "handling.reverse_hold_time_s",
    ),
    "missing_reverse_top_speed_m_s.json": (
        "missing-field",
        "handling.reverse_top_speed_m_s",
    ),
    "missing_reverse_trigger_speed_m_s.json": (
        "missing-field",
        "handling.reverse_trigger_speed_m_s",
    ),
    "null_field_without_unknowns.json": (
        "null-without-unknown",
        "handling.max_yaw_rate_rad_s",
    ),
    "resolved_value_listed_unknown.json": (
        "resolved-but-unknown",
        "handling.max_yaw_rate_rad_s",
    ),
    "reverse_acceleration_negative.json": (
        "bad-number",
        "handling.reverse_acceleration_m_s2",
    ),
    "reverse_top_speed_negative.json": ("bad-number", "handling.reverse_top_speed_m_s"),
    "stale_content_hash.json": ("content-hash-mismatch", "content_hash"),
    "top_null_without_unknowns.json": (
        "reverse-cross-field",
        "handling.reverse_top_speed_m_s",
    ),
    "trigger_above_one.json": ("bad-number", "handling.reverse_trigger_speed_m_s"),
    "unsupported_version.json": ("unsupported-schema-version", "schema_version"),
    "version_trailing_newline.json": (
        "unsupported-schema-version",
        "schema_version",
    ),
    "yaw_boolean.json": ("bad-yaw-rate", "handling.max_yaw_rate_rad_s"),
    "yaw_infinity_literal.json": ("invalid-json", ""),
    "yaw_negative.json": ("bad-yaw-rate", "handling.max_yaw_rate_rad_s"),
    "yaw_numeric_string.json": ("bad-yaw-rate", "handling.max_yaw_rate_rad_s"),
    "yaw_unlimited_extra_key.json": (
        "bad-unlimited-encoding",
        "handling.max_yaw_rate_rad_s",
    ),
    "yaw_unlimited_false.json": ("bad-yaw-rate", "handling.max_yaw_rate_rad_s"),
    "yaw_zero.json": ("bad-yaw-rate", "handling.max_yaw_rate_rad_s"),
}


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
        self.assertEqual(
            sorted(path.name for path in (FIXTURES / "negative").glob("*.json")),
            sorted(NEGATIVE_FIXTURE_EXPECTATIONS),
            "every negative fixture must declare its expected code and path",
        )
        for path in sorted((FIXTURES / "negative").glob("*.json")):
            with self.subTest(path=path.name):
                document, load_findings = vcr.load_json_document(path)
                findings = load_findings if document is None else findings_for(document)
                self.assertIn(
                    NEGATIVE_FIXTURE_EXPECTATIONS[path.name],
                    pairs(findings),
                    f"{path.name} was not rejected for its declared reason",
                )

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

    def test_acceleration_curve_order_compares_binary64_values(self) -> None:
        # The reviewer's exact counterexample: two distinct authored integers
        # that both round to 9007199254740992.0. Schema mode stays shape-only;
        # motor-ready mode compares the runtime floats and names the point.
        head, separator, tail = BASE_FIXTURE_TEXT.partition('"handling"')
        tail = tail.replace('"speed_m_s": 0', '"speed_m_s": 9007199254740992', 1)
        tail = tail.replace('"speed_m_s": 30', '"speed_m_s": 9007199254740993', 1)
        text = rehash(head + separator + tail)
        schema_findings = validate_text(text, mode="schema")
        self.assertNotIn("motor-input-order", codes(schema_findings))
        self.assertIn(
            ("number-not-representable", "handling.acceleration_curve[1].speed_m_s"),
            pairs(schema_findings),
        )
        findings = validate_text(text, mode="motor-ready")
        self.assertIn(
            ("motor-input-order", "handling.acceleration_curve[1].speed_m_s"),
            pairs(findings),
        )

    def test_acceleration_curve_order_collapses_stable_decimal_literals(self) -> None:
        # Two distinct round-trip-stable decimals that share one binary64
        # value: the mapper publishes a duplicate speed, so order must refuse.
        head, separator, tail = BASE_FIXTURE_TEXT.partition('"handling"')
        tail = tail.replace('"speed_m_s": 0', '"speed_m_s": 0.1', 1)
        tail = tail.replace(
            '"speed_m_s": 30',
            '"speed_m_s": 0.1000000000000000055511151231257827021181583404541015625',
            1,
        )
        text = rehash(head + separator + tail)
        self.assertEqual(validate_text(text, mode="schema"), [])
        findings = validate_text(text, mode="motor-ready")
        self.assertIn(
            ("motor-input-order", "handling.acceleration_curve[1].speed_m_s"),
            pairs(findings),
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


class NumberBoundaryTests(unittest.TestCase):
    """The source decimal to binary64 boundary.

    Every case goes through the file entry point so the authored literal, not a
    pre-rounded Python float, is what the checker sees.
    """

    OUT_OF_RANGE = "1" + "0" * 400
    OUT_OF_RANGE_309 = "9" * 309
    IN_RANGE_309 = "1" + "0" * 308
    PRECISION_LOSING = "1.00000000000000001"
    UNDERFLOWING = "1e-400"

    def test_out_of_range_integers_are_refused_at_their_path(self) -> None:
        cases = [
            ("handling.max_yaw_rate_rad_s", self.OUT_OF_RANGE),
            ("handling.reverse_hold_time_s", self.OUT_OF_RANGE),
            ("mass_kg", self.OUT_OF_RANGE_309),
        ]
        for field, literal in cases:
            for mode in ("schema", "motor-ready"):
                with self.subTest(field=field, literal_length=len(literal), mode=mode):
                    text = replace_number(BASE_FIXTURE_TEXT, field.removeprefix("handling."), literal)
                    findings = validate_text(text, mode)
                    self.assertIn(("non-finite-number", field), pairs(findings))

    def test_long_integer_range_and_exactness_are_distinct(self) -> None:
        # 10**308 fits binary64 but does not convert back exactly, so the typed
        # runtime would silently lose source precision. Digit count alone is
        # not the refusal reason; recoverability is.
        text = rehash(replace_number(BASE_FIXTURE_TEXT, "mass_kg", self.IN_RANGE_309))
        findings = validate_text(text)
        self.assertIn(("number-not-representable", "mass_kg"), pairs(findings))

        # 2**300 has 91 digits and is exactly representable, so it is accepted.
        exact = str(2**300)
        text = rehash(replace_number(BASE_FIXTURE_TEXT, "mass_kg", exact))
        self.assertEqual(validate_text(text), [])

    def test_integer_policy_at_the_api_boundary(self) -> None:
        document = base_document()
        document["mass_kg"] = 10**308
        self.assertIn(("number-not-representable", "mass_kg"), pairs(findings_for(document)))

        document["mass_kg"] = 2**300
        document["content_hash"] = vcr.content_hash_of(document)
        self.assertEqual(findings_for(document), [])

    def test_precision_losing_literal_is_refused(self) -> None:
        text = replace_number(
            BASE_FIXTURE_TEXT, "reverse_trigger_speed_m_s", self.PRECISION_LOSING
        )
        for mode in ("schema", "motor-ready"):
            with self.subTest(mode=mode):
                findings = validate_text(text, mode)
                self.assertIn(
                    ("number-not-representable", "handling.reverse_trigger_speed_m_s"),
                    pairs(findings),
                )
                # It is also above the declared maximum once compared exactly.
                self.assertIn(("bad-number", "handling.reverse_trigger_speed_m_s"), pairs(findings))

    def test_underflowing_literal_is_refused(self) -> None:
        text = insert_member(
            BASE_FIXTURE_TEXT, f'  "presentation": {{"scale": {self.UNDERFLOWING}}},'
        )
        self.assertIn(("number-not-representable", "presentation.scale"), pairs(validate_text(text)))

    def test_round_trip_stable_literals_are_accepted(self) -> None:
        presentation = (
            '  "presentation": {\n'
            '    "paint.color": "sunset",\n'
            '    "scale": 0.1,\n'
            '    "tiny": 1e-07,\n'
            '    "subnormal": 1e-300,\n'
            '    "count": 30,\n'
            '    "ratio": 1.05\n'
            '  },'
        )
        text = rehash(insert_member(BASE_FIXTURE_TEXT, presentation))
        for mode in ("schema", "motor-ready"):
            with self.subTest(mode=mode):
                self.assertEqual(validate_text(text, mode), [])

    def test_exact_boundaries_are_compared_in_decimal_space(self) -> None:
        stable = rehash(replace_number(BASE_FIXTURE_TEXT, "reverse_trigger_speed_m_s", "0.9999999999999999"))
        self.assertEqual(validate_text(stable), [])

        # The exact decimal expansion of binary64 0.3 is round-trip stable,
        # but is still strictly below the authored source minimum 0.3.
        below_hold = str(Decimal(0.3))
        text = replace_number(BASE_FIXTURE_TEXT, "reverse_hold_time_s", below_hold)
        findings = validate_text(text)
        self.assertIn(("bad-number", "handling.reverse_hold_time_s"), pairs(findings))
        self.assertNotIn("number-not-representable", codes(findings))

    def test_direct_api_refuses_non_finite_and_huge_numbers(self) -> None:
        document = base_document()
        document["handling"]["max_yaw_rate_rad_s"] = float("inf")
        document["mass_kg"] = 10**400
        findings = findings_for(document)
        self.assertIn(("non-finite-number", "handling.max_yaw_rate_rad_s"), pairs(findings))
        self.assertIn(("non-finite-number", "mass_kg"), pairs(findings))
        self.assertIn("bad-yaw-rate", codes(findings))

    def test_direct_api_compares_decimal_values_exactly(self) -> None:
        document = base_document()
        document["handling"]["reverse_trigger_speed_m_s"] = Decimal("1.0")
        self.assertEqual(findings_for(document), [])

        document["handling"]["reverse_trigger_speed_m_s"] = Decimal("1.00000000000000001")
        findings = findings_for(document)
        self.assertIn(("number-not-representable", "handling.reverse_trigger_speed_m_s"), pairs(findings))
        self.assertIn(("bad-number", "handling.reverse_trigger_speed_m_s"), pairs(findings))

    def test_non_finite_literal_in_freeform_presentation_is_refused(self) -> None:
        text = insert_member(BASE_FIXTURE_TEXT, '  "presentation": {"icon": 1e999},')
        findings = validate_text(text)
        self.assertIn(("non-finite-number", "presentation.icon"), pairs(findings))
        self.assertIn("content-hash-uncomputable", codes(findings))

    def test_canonical_json_never_emits_non_finite_tokens(self) -> None:
        for value in (float("inf"), float("-inf"), float("nan")):
            with self.subTest(value=value):
                with self.assertRaises(vcr.CanonicalizationError):
                    vcr.canonical_json({"a": value})
        text = vcr.canonical_json(vcr.to_binary64(base_document()))
        self.assertNotIn("NaN", text)
        self.assertNotIn("Infinity", text)

    def test_content_hash_of_a_non_representable_document_raises(self) -> None:
        document = base_document()
        document["presentation"] = {"icon": Decimal("1e999")}
        with self.assertRaises(vcr.CanonicalizationError):
            vcr.content_hash_of(document)
        document["presentation"] = {"icon": Decimal("1.00000000000000001")}
        with self.assertRaises(vcr.CanonicalizationError):
            vcr.content_hash_of(document)


class SurrogateTests(unittest.TestCase):
    """Escaped lone surrogates cannot be encoded as UTF-8 or hashed."""

    def test_lone_surrogate_in_a_string_is_refused(self) -> None:
        text = BASE_FIXTURE_TEXT.replace(
            '"display_name": "Example Rookie"', '"display_name": "Bad \\ud800 Name"'
        )
        findings = validate_text(text)
        self.assertIn(("unpaired-surrogate", "display_name"), pairs(findings))
        self.assertIn("content-hash-uncomputable", codes(findings))

    def test_lone_surrogate_in_a_member_name_is_refused(self) -> None:
        text = BASE_FIXTURE_TEXT.replace('"mass_kg": 1200', '"ma\\ud800ss_kg": 1200')
        findings = validate_text(text)
        surrogate_paths = {
            path for code, path in pairs(findings) if code == "unpaired-surrogate"
        }
        self.assertEqual(surrogate_paths, {'ma\\ud800ss_kg'})
        self.assertIn("content-hash-uncomputable", codes(findings))

    def test_lone_surrogate_in_the_open_presentation_subtree_is_refused(self) -> None:
        text = insert_member(
            BASE_FIXTURE_TEXT, '  "presentation": {"pa\\ud800int": null},'
        )
        findings = validate_text(text)
        self.assertIn(("unpaired-surrogate", 'presentation.pa\\ud800int'), pairs(findings))

    def test_paired_surrogate_escape_is_combined_and_accepted(self) -> None:
        text = rehash(
            BASE_FIXTURE_TEXT.replace(
                '"display_name": "Example Rookie"',
                '"display_name": "R\\u00e9sum\\u00e9 \\ud83d\\ude00"',
            )
        )
        self.assertEqual(validate_text(text), [])


class CanonicalHashGoldenTests(unittest.TestCase):
    """A pinned digest for the canonical hash rule."""

    # sha256 over canonical JSON (sorted keys, compact separators, UTF-8) of the
    # positive example with a non-ASCII display name and a presentation object
    # holding float notation, integer notation, a dotted key and nesting, with
    # the content_hash member removed.
    GOLDEN_DIGEST = "sha256:6d28c6e67fdac14d57399f066c277cd864f28e3679a169a941e45794cf05158a"

    def golden_document(self) -> dict[str, Any]:
        document = base_document()
        document["display_name"] = "Résumé 😀 Racer"
        document["presentation"] = {
            "paint.color": "sunset",
            "scale": 0.1,
            "count": 30,
            "nested": {"deep": {"value": 1e-07}},
        }
        return document

    def test_golden_digest_is_stable(self) -> None:
        self.assertEqual(vcr.content_hash_of(self.golden_document()), self.GOLDEN_DIGEST)

    def test_key_order_and_whitespace_do_not_change_the_digest(self) -> None:
        document = self.golden_document()
        shuffled = dict(reversed(list(document.items())))
        self.assertEqual(vcr.content_hash_of(shuffled), self.GOLDEN_DIGEST)

    def test_float_and_integer_notation_change_the_digest(self) -> None:
        document = self.golden_document()
        integer_notation = copy.deepcopy(document)
        integer_notation["presentation"]["count"] = 30.0
        self.assertNotEqual(
            vcr.content_hash_of(integer_notation), self.GOLDEN_DIGEST
        )

    def test_integer_and_float_literals_hash_differently(self) -> None:
        self.assertNotEqual(vcr.content_hash_of({"a": 30}), vcr.content_hash_of({"a": 30.0}))
        # Exponent and plain fraction notation for one binary64 value agree.
        self.assertEqual(
            vcr.content_hash_of({"a": Decimal("1e2")}),
            vcr.content_hash_of({"a": 100.0}),
        )

    def test_differently_formatted_files_with_the_golden_hash_validate(self) -> None:
        document = self.golden_document()
        document["content_hash"] = self.GOLDEN_DIGEST
        plain = vcr.to_binary64(document)
        variants = {
            "compact_ascii": json.dumps(plain, separators=(",", ":")),
            "pretty_unicode": json.dumps(plain, indent=4, ensure_ascii=False),
        }
        for label, text in variants.items():
            with self.subTest(variant=label):
                self.assertEqual(validate_text(text), [])


class MotorReadyPreflightTests(unittest.TestCase):
    """Motor-ready mode runs the typed-resource checks a baker will make."""

    NON_TRIPLETS = ("draft-A", "0.1", "01.2.3", "0.1.0\n", "1.2.3.4", "v1.2.3")

    def test_non_triplet_revision_is_schema_valid_but_not_motor_ready(self) -> None:
        for revision in self.NON_TRIPLETS:
            with self.subTest(revision=revision):
                document = mutate(lambda d, r=revision: d.__setitem__("revision", r))
                self.assertEqual(findings_for(document), [])
                findings = findings_for(document, mode="motor-ready")
                self.assertIn(("bad-revision-format", "revision"), pairs(findings))

    def test_triplet_revision_is_motor_ready(self) -> None:
        for revision in ("0.1.0", "1.2.3", "10.20.30"):
            with self.subTest(revision=revision):
                document = mutate(lambda d, r=revision: d.__setitem__("revision", r))
                self.assertEqual(findings_for(document, mode="motor-ready"), [])

    def test_car_id_that_would_fail_definition_identity_is_refused(self) -> None:
        text = BASE_FIXTURE_TEXT.replace(
            '"car_id": "car.example_rookie"', '"car_id": "car.example_rookie\\n"'
        )
        # Schema mode keeps the historical source rule, which the JSON-Schema
        # style match accepts.
        schema_findings = validate_text(text, mode="schema")
        self.assertNotIn("bad-handling-id", codes(schema_findings))
        self.assertNotIn("bad-car-id", codes(schema_findings))

        motor_findings = validate_text(text, mode="motor-ready")
        self.assertIn(("bad-handling-id", "car_id"), pairs(motor_findings))

    def test_well_formed_car_id_is_motor_ready(self) -> None:
        document = mutate(lambda d: d.__setitem__("car_id", "car.comet"))
        self.assertEqual(findings_for(document, mode="motor-ready"), [])


class MotorReadySourceContractTests(unittest.TestCase):
    """Motor-ready mode ties authored provenance to the accepted contract."""

    PATH = "provenance.source_contract"
    TOKEN = "roadstorm.handling_config.1.1.0"

    def _document_with(self, value: Any) -> dict[str, Any]:
        def apply(d: dict[str, Any]) -> None:
            d["provenance"]["source_contract"] = value
        return mutate(apply)

    def test_exact_token_passes_both_modes(self) -> None:
        self.assertEqual(base_document()["provenance"]["source_contract"], self.TOKEN)
        self.assertEqual(findings_for(base_document()), [])
        self.assertEqual(findings_for(base_document(), mode="motor-ready"), [])

    def test_null_is_honest_in_schema_mode_only(self) -> None:
        document = self._document_with(None)
        self.assertEqual(findings_for(document), [])
        self.assertIn(
            ("source-contract-missing", self.PATH),
            pairs(findings_for(document, mode="motor-ready")),
        )

    def test_absent_member_is_reported_as_missing(self) -> None:
        def drop(d: dict[str, Any]) -> None:
            del d["provenance"]["source_contract"]

        document = mutate(drop)
        self.assertEqual(findings_for(document), [])
        self.assertIn(
            ("source-contract-missing", self.PATH),
            pairs(findings_for(document, mode="motor-ready")),
        )

    def test_historical_wrong_and_malformed_tokens_are_refused(self) -> None:
        values = (
            "roadstorm.handling_config.1.0.0",
            "roadstorm.handling_config.1.1.1",
            "roadstorm.handling_config.2.0.0",
            "roadstorm.handling_config.1.1",
            "roadstorm.handling_config.1.1.0\n",
            "ROADSTORM.handling_config.1.1.0",
        )
        for value in values:
            with self.subTest(value=value):
                document = self._document_with(value)
                self.assertEqual(findings_for(document), [])
                self.assertIn(
                    ("source-contract-mismatch", self.PATH),
                    pairs(findings_for(document, mode="motor-ready")),
                )

    def test_non_string_value_keeps_type_diagnostic(self) -> None:
        findings = findings_for(self._document_with(1.1), mode="motor-ready")
        self.assertIn(("bad-provenance-field", self.PATH), pairs(findings))
        self.assertIn(("source-contract-mismatch", self.PATH), pairs(findings))

    def test_rehashed_file_finding_is_independent_of_content_hash(self) -> None:
        for value in (None, "roadstorm.handling_config.1.0.0"):
            with self.subTest(value=value):
                document = self._document_with(value)
                with tempfile.TemporaryDirectory() as tmp:
                    path = Path(tmp) / "recipe.json"
                    path.write_text(json.dumps(document), encoding="utf-8")
                    findings = vcr.validate_recipe_file(path, mode="motor-ready")
                self.assertNotIn("content-hash-mismatch", codes(findings))
                expected = (
                    "source-contract-missing" if value is None else "source-contract-mismatch"
                )
                self.assertIn((expected, self.PATH), pairs(findings))

    def test_rehashed_correct_token_file_passes(self) -> None:
        document = base_document()
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "recipe.json"
            path.write_text(json.dumps(document), encoding="utf-8")
            self.assertEqual(vcr.validate_recipe_file(path, mode="motor-ready"), [])

    def test_v1_0_0_null_draft_stays_historical_and_unaffected_by_this_rule(self) -> None:
        document = base_document("1.0.0")
        document["provenance"]["source_contract"] = None
        document["content_hash"] = vcr.content_hash_of(document)
        self.assertEqual(findings_for(document), [])
        findings = findings_for(document, mode="motor-ready")
        self.assertIn("motor-input-missing", codes(findings))
        self.assertNotIn("source-contract-missing", codes(findings))


class PresentationNullPathTests(unittest.TestCase):
    """The open presentation subtree and the null/unknowns path policy."""

    COSMETIC = (
        '  "presentation": {\n'
        '    "paint.color": null,\n'
        '    "paint-id": null,\n'
        '    "paint": {"color": null},\n'
        '    "count": 3\n'
        '  },'
    )

    def test_open_presentation_subtree_is_exempt_from_the_unknowns_rule(self) -> None:
        text = rehash(insert_member(BASE_FIXTURE_TEXT, self.COSMETIC))
        for mode in ("schema", "motor-ready"):
            with self.subTest(mode=mode):
                findings = validate_text(text, mode)
                self.assertNotIn("unlisted-null", codes(findings))
                self.assertEqual(findings, [])

    def test_presentation_is_still_checked_for_representability(self) -> None:
        text = insert_member(BASE_FIXTURE_TEXT, '  "presentation": {"icon": 1e999},')
        findings = validate_text(text)
        self.assertIn(("non-finite-number", "presentation.icon"), pairs(findings))

    def test_unknowns_path_cannot_name_a_dotted_literal_key(self) -> None:
        text = rehash(
            insert_member(BASE_FIXTURE_TEXT, '  "presentation": {"paint.color": null},')
        )
        document = load_text(text)
        document["unknowns"].append(
            {"path": "presentation.paint.color", "reason": "literal key, not a member"}
        )
        findings = findings_for(document)
        self.assertIn(("unresolved-unknown", "unknowns"), pairs(findings))

    def test_declared_path_covers_only_structural_segments(self) -> None:
        covers = vcr._declared_path_covers
        self.assertTrue(covers("a.b", "a.b"))
        self.assertTrue(covers("a.b", "a.b.c"))
        self.assertTrue(covers("a.b", "a.b[0].c"))
        self.assertTrue(covers("a.b", "a.b[12]"))
        self.assertFalse(covers("a.b", 'a.b["c.d"]'))
        self.assertFalse(covers("a", 'a["b.c"]'))
        self.assertFalse(covers("a.b", "a.bc"))

    def test_closed_subtree_null_still_requires_its_exact_entry(self) -> None:
        document = mutate(
            lambda d: (
                d["handling"]["surge"].__setitem__("selected_delta_m_s", None),
                drop_unknown_entry(d, "handling.surge.selected_delta_m_s"),
            )
        )
        self.assertIn(
            ("unlisted-null", "handling.surge.selected_delta_m_s"),
            pairs(findings_for(document)),
        )

    def test_closed_subtree_null_with_its_entry_is_accepted(self) -> None:
        self.assertEqual(findings_for(base_document()), [])


class RobustnessBoundaryTests(unittest.TestCase):
    """Malformed boundary input must produce findings, never exceptions."""

    def _write_rehashed(self, tmp: str, mutate_fn: Callable[[dict[str, Any]], None]) -> Path:
        document = base_document()
        mutate_fn(document)
        document["content_hash"] = vcr.content_hash_of(document)
        return write_recipe(tmp, "recipe.json", json.dumps(document))

    def test_unknown_path_trailing_newline_is_a_structured_finding(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_rehashed(
                tmp,
                lambda d: d["unknowns"].append(
                    {"path": "detachable_parts[1]\n", "reason": "trailing newline"}
                ),
            )
            findings = vcr.validate_recipe_file(path, mode="motor-ready")
        self.assertIn(("bad-unknown-path", "unknowns[6].path"), pairs(findings))

    def test_unknown_path_huge_index_is_bounded_and_structured(self) -> None:
        huge = "detachable_parts[" + "1" * 4400 + "].mesh_id"
        with tempfile.TemporaryDirectory() as tmp:
            path = self._write_rehashed(
                tmp, lambda d: d["unknowns"].append({"path": huge, "reason": "huge index"})
            )
            findings = vcr.validate_recipe_file(path, mode="motor-ready")
        self.assertIn(("bad-unknown-path", "unknowns[6].path"), pairs(findings))
        self.assertLessEqual(len(findings), 2)

    def test_extreme_decimal_exponent_is_a_controlled_finding(self) -> None:
        payload = b'{"presentation":{"probe":1e99999999999999999999999999}}'
        findings = validate_bytes(payload)
        self.assertIn(("invalid-number", ""), pairs(findings))

    def test_deep_presentation_nesting_is_refused_at_the_file_boundary(self) -> None:
        deep = "[" * 3000 + "null" + "]" * 3000
        text = insert_member(BASE_FIXTURE_TEXT, f'  "presentation": {{"probe": {deep}}},')
        findings = validate_text(text)
        self.assertIn(("nesting-too-deep", "presentation"), pairs(findings))

    def test_deep_api_document_is_refused_without_recursion(self) -> None:
        node: Any = None
        for _ in range(3000):
            node = [node]
        findings = findings_for(node)
        self.assertIn("nesting-too-deep", codes(findings))

    def test_nesting_at_the_supported_limit_is_still_processed(self) -> None:
        node: Any = {}
        for _ in range(vcr.MAX_NESTING_DEPTH - 2):
            node = [node]
        document = base_document()
        document["presentation"] = {"probe": node}
        document["content_hash"] = vcr.content_hash_of(document)
        self.assertEqual(findings_for(document), [])

    def test_canonical_hash_of_deep_document_is_a_controlled_error(self) -> None:
        node: Any = None
        for _ in range(3000):
            node = [node]
        with self.assertRaises(vcr.CanonicalizationError):
            vcr.content_hash_of({"presentation": node})


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

    def test_motor_ready_positive_files_exit_zero(self) -> None:
        result = self._run(
            "--mode",
            "motor-ready",
            str(FIXTURES / "positive" / "example_rookie_finite.json"),
            str(FIXTURES / "positive" / "example_rookie_unlimited.json"),
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 error(s)", result.stdout)

    def test_missing_path_exits_two(self) -> None:
        result = self._run(str(ROOT / "does" / "not" / "exist.json"))
        self.assertEqual(result.returncode, 2)

    def test_bad_usage_exits_two(self) -> None:
        result = self._run("--mode", "nonsense")
        self.assertEqual(result.returncode, 2)

    def test_boundary_defects_exit_one_without_traceback(self) -> None:
        cases = [
            (
                b'{"presentation":{"probe":1e99999999999999999999999999}}',
                "invalid-number",
            ),
            (
                b'{"presentation":{"probe":'
                + b"[" * 3000
                + b"null"
                + b"]" * 3000
                + b"}}",
                "nesting-too-deep",
            ),
        ]
        for payload, expected in cases:
            with self.subTest(expected=expected):
                with tempfile.TemporaryDirectory() as tmp:
                    path = Path(tmp) / "boundary.json"
                    path.write_bytes(payload)
                    result = self._run("--mode", "motor-ready", str(path))
                self.assertEqual(result.returncode, 1)
                combined = result.stdout + result.stderr
                self.assertIn(expected, combined)
                self.assertNotIn("Traceback", result.stderr)

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
