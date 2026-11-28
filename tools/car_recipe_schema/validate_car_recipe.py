#!/usr/bin/env python3
"""Roadstorm Racer! car handling source-recipe checker (contracts 1.0.0/1.1.0).

Ownership: tools/car_recipe_schema/** and fixtures/car_recipe/** (M0.2
versioned handling-source contract job). Standard library only.

This module is the executable form of the two source-recipe contracts:

* ``schemas/handling_config.schema.json`` (``schema_version`` ``1.0.0``), and
* ``schemas/handling_config_v1_1.schema.json`` (``schema_version`` ``1.1.0``).

It validates a complete recipe document: required members, closed objects,
types, ranges, the null/``unknowns`` honesty rule in both directions, strict
JSON parsing (duplicate members and ``Infinity``/``NaN`` literals rejected),
and the canonical ``content_hash``. For ``1.1.0`` it additionally enforces
the five added motor inputs and their cross-field rule.

Version dispatch is exact: ``1.0.0`` and ``1.1.0`` are accepted, anything else
is refused. There is no migration between versions.

Modes:

* ``schema`` checks historical schema validity only. A valid ``1.0.0`` recipe
  passes even though it cannot supply the five motor inputs.
* ``motor-ready`` (default) additionally refuses a recipe whose required motor
  inputs are missing, ``null`` or listed in ``unknowns``, naming their dotted
  paths. A ``1.0.0`` recipe is always refused here.

Deliberate limitations (documented in README.md):

* Standard library only. It does not run the engine, execute a recipe or check
  physics outcomes; those are later motor and benchmark gates.
* It implements the recipe contracts in plain Python, not the full JSON Schema
  draft 2020-12 vocabulary. The schema documents remain the text contracts.
  Finiteness, the null/``unknowns`` pairing and the reverse cross-field rule
  are semantic checks the schema cannot fully express.
* It cannot make unknown facts known. Missing or null values are reported,
  never filled in and never guessed.

Usage as a library::

    from validate_car_recipe import validate_recipe_file, validate_recipe_document

Exit codes for the CLI wrapper: 0 = no errors, 1 = validation/content errors,
2 = a path could not be read or the command line was wrong.

Original project code under the Unlicense.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

# ---------------------------------------------------------------------------
# Contract constants
# ---------------------------------------------------------------------------

SUPPORTED_VERSIONS = ("1.0.0", "1.1.0")
DEFAULT_MODE = "motor-ready"
MODES = ("schema", "motor-ready")

RECIPE_SCHEMA_V1_0_0 = "handling_config.schema.json"
RECIPE_SCHEMA_V1_1_0 = "handling_config_v1_1.schema.json"

# Reused verbatim from schemas/common.schema.json.
STABLE_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_-]+)*$")
CONTENT_HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
REVISION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
UNKNOWN_PATH_RE = re.compile(
    r"^[a-z_][a-z0-9_]*(?:\[[0-9]+\])?(?:\.[a-z_][a-z0-9_]*(?:\[[0-9]+\])?)*$"
)

STATUSES = ("provisional", "measured", "frozen", "superseded", "example")
PROVENANCE_FIELDS = (
    "source_contract",
    "author",
    "model",
    "provider",
    "date_utc",
    "note",
)
UNKNOWN_ENTRY_MEMBERS = frozenset({"path", "reason", "blocking", "until"})
NOTE_KEYS = frozenset({"note", "notes"})
NULL_EXEMPT_SUBTREES = frozenset({"provenance", "unknowns", "content_hash"})

# Keys whose null values are documentation, not undetermined data.
ROOT_REQUIRED = (
    "schema_version",
    "car_id",
    "display_name",
    "revision",
    "status",
    "units",
    "coordinate_frame",
    "dimensions",
    "mass_kg",
    "contact_proxy",
    "engine",
    "handling",
    "upgrades",
    "detachable_parts",
    "unknowns",
    "content_hash",
    "provenance",
)
ROOT_MEMBERS = frozenset(ROOT_REQUIRED) | {"presentation"}

UNITS_MEMBERS = frozenset({"length", "mass", "time", "angle"})
COORDINATE_FRAME_MEMBERS = frozenset({"forward", "up", "origin"})
DIMENSIONS_MEMBERS = frozenset({
    "length_m", "width_m", "height_m", "wheelbase_m", "ground_clearance_m",
    "jump_envelope_m",
})
CONTACT_PROXY_MEMBERS = frozenset({"shape", "derived_from", "roof", "underside"})
ENGINE_MEMBERS = frozenset({"top_speed_kmh", "acceleration_curve"})
DRAG_MEMBERS = frozenset({"aerodynamic", "rolling"})
YAW_GAIN_MEMBERS = frozenset({"grip", "drift"})
LATERAL_DAMPING_MEMBERS = frozenset({"grip_per_s", "drift_per_s"})
DRIFT_MEMBERS = frozenset({
    "entry_min_speed_m_s", "entry_blend_s", "target_slip_deg_min",
    "target_slip_deg_max", "recovery_blend_s", "stability_assist_max_slip_deg",
})
SURGE_MEMBERS = frozenset({
    "candidate_deltas_m_s", "duration_s", "cooldown_s", "stackable",
    "selected_delta_m_s",
})
DRAFTING_MEMBERS = frozenset({
    "min_gap_m", "max_gap_m", "cone_deg", "lateral_separation_m", "eligible_s",
    "fade_s", "max_drag_reduction", "stackable",
})
AIRBORNE_MEMBERS = frozenset({"gravity_m_s2", "adhesion_bounds"})
CONTACT_CAPS_MEMBERS = frozenset({
    "solver_iterations", "overlap_passes", "max_single_correction_m",
    "max_total_correction_m",
})
SURFACE_MODIFIER_MEMBERS = frozenset({
    "surface_id", "lateral_grip_scale", "drag_scale", "notes",
})
SPEED_ACCELERATION_POINT_MEMBERS = frozenset({"speed_m_s", "acceleration_m_s2"})
DETACHABLE_PART_MEMBERS = frozenset({
    "slot", "mesh_id", "lod_ids", "attachment_transform", "impact_region",
    "thresholds",
})
THRESHOLD_MEMBERS = frozenset({
    "loosen_m_s", "detach_single_m_s", "detach_accumulated_m_s",
})
UPGRADES_MEMBERS = frozenset({
    "levels", "engine", "tires", "chassis", "max_increase_percent",
})
UPGRADE_ENGINE_MEMBERS = frozenset({"acceleration_factors", "top_speed_factors"})
UPGRADE_TIRES_MEMBERS = frozenset({
    "grip_lateral_damping_factors", "drift_exit_blend_divisors",
})
UPGRADE_CHASSIS_MEMBERS = frozenset({
    "yaw_gain_factors", "impact_speed_loss_factors",
})
UPGRADE_MAX_INCREASE_MEMBERS = frozenset({"acceleration", "top_speed"})

HANDLING_V1_0_0_REQUIRED = (
    "acceleration_curve",
    "braking_acceleration_m_s2",
    "drag",
    "yaw_gain",
    "lateral_damping",
    "drift",
    "surge",
    "drafting",
    "airborne",
    "contact_caps",
    "surfaces",
)

FIVE_FIELDS = (
    "max_yaw_rate_rad_s",
    "reverse_trigger_speed_m_s",
    "reverse_hold_time_s",
    "reverse_acceleration_m_s2",
    "reverse_top_speed_m_s",
)

HANDLING_V1_1_0_REQUIRED = HANDLING_V1_0_0_REQUIRED + FIVE_FIELDS

# Required typed-runtime motor inputs, as dotted source paths. The first six
# come from HandlingDefinition's core physical subset; the last five are the
# 1.1.0 additions. A motor-ready recipe must supply every one of them.
MOTOR_CORE_INPUTS = (
    "handling.acceleration_curve",
    "handling.braking_acceleration_m_s2",
    "handling.drag.aerodynamic",
    "handling.drag.rolling",
    "handling.yaw_gain.grip",
    "handling.lateral_damping.grip_per_s",
)
MOTOR_INPUTS = MOTOR_CORE_INPUTS + tuple(f"handling.{field}" for field in FIVE_FIELDS)

# Design bounds mirrored from src/data/handling_definition.gd.
REVERSE_TRIGGER_MAX_M_S = 1.0
REVERSE_HOLD_MIN_S = 0.3


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------


class Finding:
    """One validation result. ``path`` is '' for document-level findings."""

    __slots__ = ("path", "code", "message", "is_error")

    def __init__(self, path: str, code: str, message: str, is_error: bool = True) -> None:
        self.path = path
        self.code = code
        self.message = message
        self.is_error = is_error

    def __str__(self) -> str:
        location = self.path or "<document>"
        severity = "ERROR" if self.is_error else "warn"
        return f"{severity} {location}: {self.code}: {self.message}"

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"Finding({self.path!r}, {self.code!r}, {self.message!r}, {self.is_error!r})"


# ---------------------------------------------------------------------------
# Strict JSON loading
# ---------------------------------------------------------------------------


def _reject_duplicate_keys(pairs: Sequence[tuple[str, Any]]) -> dict[str, Any]:
    seen: dict[str, Any] = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f"duplicate JSON member {key!r}")
        seen[key] = value
    return seen


def _reject_constant(token: str) -> Any:
    raise ValueError(f"non-JSON literal {token!r}")


def load_json_document(path: Path) -> tuple[dict[str, Any] | None, list[Finding]]:
    """Load a JSON object, reporting unreadable/invalid files as findings."""
    findings: list[Finding] = []
    try:
        raw = path.read_bytes()
    except OSError as exc:
        findings.append(Finding("", "unreadable-file", str(exc)))
        return None, findings
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        findings.append(Finding("", "invalid-encoding", f"not valid UTF-8: {exc}"))
        return None, findings
    try:
        document = json.loads(
            text,
            object_pairs_hook=_reject_duplicate_keys,
            parse_constant=_reject_constant,
        )
    except ValueError as exc:
        findings.append(Finding("", "invalid-json", f"not a strict JSON document: {exc}"))
        return None, findings
    if not isinstance(document, dict):
        findings.append(Finding("", "not-an-object", "top-level JSON value is not an object"))
        return None, findings
    return document, findings


# ---------------------------------------------------------------------------
# Canonical hashing (schemas/common.schema.json "content_hash")
# ---------------------------------------------------------------------------


def canonical_json(document: Mapping[str, Any]) -> str:
    """Canonical JSON: recursively sorted keys, compact separators, UTF-8 text."""
    return json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def content_hash_of(document: Mapping[str, Any]) -> str:
    """SHA-256 over canonical JSON of the file with content_hash removed."""
    payload = {key: value for key, value in document.items() if key != "content_hash"}
    return "sha256:" + hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _is_finite_number(value: Any) -> bool:
    return _is_number(value) and math.isfinite(value)


def _is_integer(value: Any) -> bool:
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return True
    return _is_finite_number(value) and float(value).is_integer()


def _child(path: str, key: str) -> str:
    return f"{path}.{key}" if path else key


def _index(path: str, index: int) -> str:
    return f"{path}[{index}]"


def _check_closed(
    mapping: Any,
    path: str,
    allowed: frozenset,
    findings: list[Finding],
    contract: str,
) -> None:
    if not isinstance(mapping, dict):
        return
    for key in mapping:
        if key not in allowed:
            findings.append(
                Finding(
                    _child(path, key),
                    "unknown-member",
                    f"member {key!r} is not declared by {contract} (additionalProperties: false)",
                )
            )


def _check_number(
    value: Any,
    path: str,
    findings: list[Finding],
    *,
    minimum: float | None = None,
    maximum: float | None = None,
    exclusive_minimum: float | None = None,
    nullable: bool = False,
    code: str = "bad-number",
) -> bool:
    """Check one numeric property; append a finding and return False on defect."""
    if value is None:
        if nullable:
            return True
        findings.append(Finding(path, code, "null is not allowed here; expected a number"))
        return False
    if not _is_number(value):
        findings.append(Finding(path, code, f"expected a number, got {type(value).__name__}"))
        return False
    if not math.isfinite(value):
        findings.append(Finding(path, code, f"non-finite number {value!r}"))
        return False
    if exclusive_minimum is not None and value <= exclusive_minimum:
        findings.append(
            Finding(path, code, f"{value!r} must be greater than {exclusive_minimum!r}")
        )
        return False
    if minimum is not None and value < minimum:
        findings.append(Finding(path, code, f"{value!r} is below the minimum {minimum!r}"))
        return False
    if maximum is not None and value > maximum:
        findings.append(Finding(path, code, f"{value!r} is above the maximum {maximum!r}"))
        return False
    return True


def _check_number_array(
    value: Any,
    path: str,
    findings: list[Finding],
    *,
    minimum: float | None = None,
    maximum: float | None = None,
    min_items: int | None = None,
    max_items: int | None = None,
    unique: bool = False,
    integer: bool = False,
    code: str = "bad-array",
) -> bool:
    if not isinstance(value, list):
        findings.append(Finding(path, code, f"expected an array, got {type(value).__name__}"))
        return False
    ok = True
    if min_items is not None and len(value) < min_items:
        findings.append(Finding(path, code, f"needs at least {min_items} item(s)"))
        ok = False
    if max_items is not None and len(value) > max_items:
        findings.append(Finding(path, code, f"allows at most {max_items} item(s)"))
        ok = False
    seen: list[Any] = []
    for index, item in enumerate(value):
        item_path = _index(path, index)
        if integer:
            if not _is_integer(item):
                findings.append(Finding(item_path, code, "expected an integer"))
                ok = False
                continue
        elif not _is_finite_number(item):
            findings.append(Finding(item_path, code, "expected a finite number"))
            ok = False
            continue
        if minimum is not None and item < minimum:
            findings.append(Finding(item_path, code, f"{item!r} is below the minimum {minimum!r}"))
            ok = False
        if maximum is not None and item > maximum:
            findings.append(Finding(item_path, code, f"{item!r} is above the maximum {maximum!r}"))
            ok = False
        if unique:
            if item in seen:
                findings.append(Finding(item_path, code, f"duplicate entry {item!r}"))
                ok = False
            else:
                seen.append(item)
    return ok


def _check_string(
    value: Any,
    path: str,
    findings: list[Finding],
    *,
    nullable: bool = False,
    min_length: int = 1,
    code: str = "bad-string",
) -> bool:
    if value is None:
        if nullable:
            return True
        findings.append(Finding(path, code, "null is not allowed here; expected a string"))
        return False
    if not isinstance(value, str):
        findings.append(Finding(path, code, f"expected a string, got {type(value).__name__}"))
        return False
    if len(value) < min_length:
        findings.append(Finding(path, code, f"must be at least {min_length} character(s)"))
        return False
    return True


def _check_boolean(value: Any, path: str, findings: list[Finding], code: str = "bad-boolean") -> bool:
    if not isinstance(value, bool):
        findings.append(Finding(path, code, f"expected a boolean, got {type(value).__name__}"))
        return False
    return True


def _resolve_path(document: Mapping[str, Any], path: str) -> tuple[Any, bool]:
    """Resolve a dotted path with optional [index] segments; return (value, found)."""
    node: Any = document
    for token in path.split("."):
        name, index = token, None
        if "[" in token:
            name, _, rest = token.partition("[")
            index = int(rest.rstrip("]"))
        if isinstance(node, Mapping) and name in node:
            node = node[name]
        elif isinstance(node, list) and name.isdigit() and int(name) < len(node):
            node = node[int(name)]
        else:
            return None, False
        if index is not None:
            if not isinstance(node, list) or index >= len(node):
                return None, False
            node = node[index]
    return node, True


def _collect_null_paths(value: Any, path: str, out: list[str]) -> None:
    """Collect dotted paths of JSON null values, skipping documentation-only keys."""
    if value is None:
        out.append(path)
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if key in NOTE_KEYS or key in NULL_EXEMPT_SUBTREES:
                continue
            _collect_null_paths(item, _child(path, key), out)
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            _collect_null_paths(item, _index(path, index), out)


# ---------------------------------------------------------------------------
# Section validators
# ---------------------------------------------------------------------------


def _validate_units(document: Mapping[str, Any], findings: list[Finding]) -> None:
    units = document.get("units")
    if not isinstance(units, dict):
        findings.append(Finding("units", "bad-units", "units must be an object"))
        return
    expected = {"length": "m", "mass": "kg", "time": "s", "angle": "deg"}
    for key, want in expected.items():
        if units.get(key) != want:
            findings.append(
                Finding(_child("units", key), "bad-unit", f"must be {want!r} (got {units.get(key)!r})")
            )
    _check_closed(units, "units", UNITS_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)


def _validate_coordinate_frame(document: Mapping[str, Any], findings: list[Finding]) -> None:
    frame = document.get("coordinate_frame")
    if not isinstance(frame, dict):
        findings.append(Finding("coordinate_frame", "bad-frame", "coordinate_frame must be an object"))
        return
    expected = {
        "forward": "-Z",
        "up": "+Y",
        "origin": "ground_projection_of_axle_midpoint",
    }
    for key, want in expected.items():
        if frame.get(key) != want:
            findings.append(
                Finding(
                    _child("coordinate_frame", key),
                    "bad-frame-axis",
                    f"must be {want!r} (got {frame.get(key)!r})",
                )
            )
    _check_closed(frame, "coordinate_frame", COORDINATE_FRAME_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)


def _validate_dimensions(document: Mapping[str, Any], findings: list[Finding]) -> None:
    dimensions = document.get("dimensions")
    if not isinstance(dimensions, dict):
        findings.append(Finding("dimensions", "bad-dimensions", "dimensions must be an object"))
        return
    _check_closed(dimensions, "dimensions", DIMENSIONS_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
    bounds = {
        "length_m": (3.6, 4.8, False),
        "width_m": (1.7, 2.2, False),
        "height_m": (1.0, 1.8, False),
        "wheelbase_m": (None, None, True),
        "ground_clearance_m": (None, None, True),
        "jump_envelope_m": (None, None, True),
    }
    for key, (low, high, nullable) in bounds.items():
        if key not in dimensions:
            findings.append(
                Finding(_child("dimensions", key), "missing-field", "required member is absent")
            )
            continue
        value = dimensions[key]
        kwargs: dict[str, Any] = {"nullable": nullable}
        if low is not None:
            kwargs["minimum"] = low
        if high is not None:
            kwargs["maximum"] = high
        if key == "wheelbase_m":
            kwargs["exclusive_minimum"] = 0.0
            kwargs.pop("minimum", None)
            kwargs.pop("maximum", None)
        elif key in ("ground_clearance_m", "jump_envelope_m"):
            kwargs["minimum"] = 0.0
        _check_number(value, _child("dimensions", key), findings, **kwargs)


def _validate_contact_proxy(document: Mapping[str, Any], findings: list[Finding]) -> None:
    proxy = document.get("contact_proxy")
    if not isinstance(proxy, dict):
        findings.append(Finding("contact_proxy", "bad-contact-proxy", "contact_proxy must be an object"))
        return
    _check_closed(proxy, "contact_proxy", CONTACT_PROXY_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
    if proxy.get("shape") not in ("rounded_box", "convex_hull"):
        findings.append(
            Finding(
                "contact_proxy.shape",
                "bad-shape",
                f"must be 'rounded_box' or 'convex_hull' (got {proxy.get('shape')!r})",
            )
        )
    if proxy.get("derived_from") != "declared_dimensions":
        findings.append(
            Finding(
                "contact_proxy.derived_from",
                "bad-derived-from",
                f"must be 'declared_dimensions' (got {proxy.get('derived_from')!r})",
            )
        )
    for key in ("roof", "underside"):
        child = _child("contact_proxy", key)
        if key not in proxy:
            findings.append(Finding(child, "missing-field", "required member is absent"))
        else:
            _check_string(proxy[key], child, findings, nullable=True, min_length=0)


def _validate_speed_acceleration_point(point: Any, path: str, findings: list[Finding]) -> None:
    if not isinstance(point, dict):
        findings.append(Finding(path, "bad-acceleration-point", "point must be an object"))
        return
    _check_closed(point, path, SPEED_ACCELERATION_POINT_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
    for key in ("speed_m_s", "acceleration_m_s2"):
        if key not in point:
            findings.append(Finding(_child(path, key), "missing-field", "required member is absent"))
        else:
            _check_number(point[key], _child(path, key), findings, minimum=0.0)


def _validate_acceleration_curve(value: Any, path: str, findings: list[Finding]) -> None:
    if value is None:
        return
    if not isinstance(value, list):
        findings.append(Finding(path, "bad-acceleration-curve", "must be an array or null"))
        return
    for index, point in enumerate(value):
        _validate_speed_acceleration_point(point, _index(path, index), findings)


def _validate_engine(document: Mapping[str, Any], findings: list[Finding]) -> None:
    engine = document.get("engine")
    if not isinstance(engine, dict):
        findings.append(Finding("engine", "bad-engine", "engine must be an object"))
        return
    _check_closed(engine, "engine", ENGINE_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
    for key in ("top_speed_kmh", "acceleration_curve"):
        if key not in engine:
            findings.append(Finding(_child("engine", key), "missing-field", "required member is absent"))
    if "top_speed_kmh" in engine:
        _check_number(
            engine["top_speed_kmh"],
            "engine.top_speed_kmh",
            findings,
            minimum=205.0,
            maximum=235.0,
            nullable=True,
        )
    if "acceleration_curve" in engine:
        _validate_acceleration_curve(engine["acceleration_curve"], "engine.acceleration_curve", findings)


def _validate_surface_modifier(item: Any, path: str, findings: list[Finding]) -> None:
    if not isinstance(item, dict):
        findings.append(Finding(path, "bad-surface-modifier", "surface modifier must be an object"))
        return
    _check_closed(item, path, SURFACE_MODIFIER_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
    for key in ("surface_id", "lateral_grip_scale", "drag_scale"):
        if key not in item:
            findings.append(Finding(_child(path, key), "missing-field", "required member is absent"))
    if "surface_id" in item:
        _check_string(item["surface_id"], _child(path, "surface_id"), findings)
    for key in ("lateral_grip_scale", "drag_scale"):
        if key in item:
            _check_number(item[key], _child(path, key), findings, minimum=0.0, nullable=True)
    if "notes" in item:
        _check_string(item["notes"], _child(path, "notes"), findings, nullable=True, min_length=0)


def _validate_two_member_numbers(
    obj: Any,
    path: str,
    members: Sequence[str],
    allowed: frozenset,
    findings: list[Finding],
) -> None:
    if not isinstance(obj, dict):
        findings.append(Finding(path, "bad-object", f"{path} must be an object"))
        return
    _check_closed(obj, path, allowed, findings, RECIPE_SCHEMA_V1_0_0)
    for key in members:
        if key not in obj:
            findings.append(Finding(_child(path, key), "missing-field", "required member is absent"))
        else:
            _check_number(obj[key], _child(path, key), findings, minimum=0.0, nullable=True)


def _validate_handling_common(handling: Mapping[str, Any], findings: list[Finding]) -> None:
    """Validate the handling members shared by 1.0.0 and 1.1.0."""
    for key in ("acceleration_curve", "braking_acceleration_m_s2"):
        if key not in handling:
            findings.append(Finding(_child("handling", key), "missing-field", "required member is absent"))
    if "acceleration_curve" in handling:
        _validate_acceleration_curve(handling["acceleration_curve"], "handling.acceleration_curve", findings)
    if "braking_acceleration_m_s2" in handling:
        _check_number(
            handling["braking_acceleration_m_s2"],
            "handling.braking_acceleration_m_s2",
            findings,
            minimum=0.0,
            nullable=True,
        )

    _validate_two_member_numbers(
        handling.get("drag"), "handling.drag", ("aerodynamic", "rolling"), DRAG_MEMBERS, findings
    )
    _validate_two_member_numbers(
        handling.get("yaw_gain"), "handling.yaw_gain", ("grip", "drift"), YAW_GAIN_MEMBERS, findings
    )
    _validate_two_member_numbers(
        handling.get("lateral_damping"),
        "handling.lateral_damping",
        ("grip_per_s", "drift_per_s"),
        LATERAL_DAMPING_MEMBERS,
        findings,
    )

    drift = handling.get("drift")
    if not isinstance(drift, dict):
        findings.append(Finding("handling.drift", "bad-object", "handling.drift must be an object"))
    else:
        _check_closed(drift, "handling.drift", DRIFT_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in (
            "entry_min_speed_m_s",
            "entry_blend_s",
            "target_slip_deg_min",
            "target_slip_deg_max",
            "recovery_blend_s",
        ):
            if key not in drift:
                findings.append(Finding(_child("handling.drift", key), "missing-field", "required member is absent"))
            else:
                _check_number(drift[key], _child("handling.drift", key), findings, minimum=0.0)
        if "stability_assist_max_slip_deg" not in drift:
            findings.append(
                Finding(
                    "handling.drift.stability_assist_max_slip_deg",
                    "missing-field",
                    "required member is absent",
                )
            )
        else:
            _check_number(
                drift["stability_assist_max_slip_deg"],
                "handling.drift.stability_assist_max_slip_deg",
                findings,
                minimum=0.0,
                nullable=True,
            )

    surge = handling.get("surge")
    if not isinstance(surge, dict):
        findings.append(Finding("handling.surge", "bad-object", "handling.surge must be an object"))
    else:
        _check_closed(surge, "handling.surge", SURGE_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in ("candidate_deltas_m_s", "duration_s", "cooldown_s", "stackable", "selected_delta_m_s"):
            if key not in surge:
                findings.append(Finding(_child("handling.surge", key), "missing-field", "required member is absent"))
        if "candidate_deltas_m_s" in surge:
            _check_number_array(
                surge["candidate_deltas_m_s"],
                "handling.surge.candidate_deltas_m_s",
                findings,
                minimum=0.0,
                min_items=1,
            )
        for key in ("duration_s", "cooldown_s"):
            if key in surge:
                _check_number(surge[key], _child("handling.surge", key), findings, minimum=0.0)
        if "stackable" in surge:
            _check_boolean(surge["stackable"], "handling.surge.stackable", findings)
        if "selected_delta_m_s" in surge:
            _check_number(
                surge["selected_delta_m_s"],
                "handling.surge.selected_delta_m_s",
                findings,
                minimum=0.0,
                nullable=True,
            )

    drafting = handling.get("drafting")
    if not isinstance(drafting, dict):
        findings.append(Finding("handling.drafting", "bad-object", "handling.drafting must be an object"))
    else:
        _check_closed(drafting, "handling.drafting", DRAFTING_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in (
            "min_gap_m",
            "max_gap_m",
            "cone_deg",
            "lateral_separation_m",
            "eligible_s",
            "fade_s",
            "max_drag_reduction",
            "stackable",
        ):
            if key not in drafting:
                findings.append(Finding(_child("handling.drafting", key), "missing-field", "required member is absent"))
        for key in (
            "min_gap_m",
            "max_gap_m",
            "cone_deg",
            "lateral_separation_m",
            "eligible_s",
            "fade_s",
        ):
            if key in drafting:
                _check_number(drafting[key], _child("handling.drafting", key), findings, minimum=0.0)
        if "max_drag_reduction" in drafting:
            _check_number(
                drafting["max_drag_reduction"],
                "handling.drafting.max_drag_reduction",
                findings,
                minimum=0.0,
                maximum=1.0,
            )
        if "stackable" in drafting:
            _check_boolean(drafting["stackable"], "handling.drafting.stackable", findings)

    airborne = handling.get("airborne")
    if not isinstance(airborne, dict):
        findings.append(Finding("handling.airborne", "bad-object", "handling.airborne must be an object"))
    else:
        _check_closed(airborne, "handling.airborne", AIRBORNE_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in ("gravity_m_s2", "adhesion_bounds"):
            if key not in airborne:
                findings.append(
                    Finding(_child("handling.airborne", key), "missing-field", "required member is absent")
                )
        if "gravity_m_s2" in airborne:
            _check_number(
                airborne["gravity_m_s2"],
                "handling.airborne.gravity_m_s2",
                findings,
                minimum=0.0,
                nullable=True,
            )
        if "adhesion_bounds" in airborne:
            bounds = airborne["adhesion_bounds"]
            if bounds is not None and not isinstance(bounds, dict):
                findings.append(
                    Finding(
                        "handling.airborne.adhesion_bounds",
                        "bad-adhesion-bounds",
                        "must be an object or null",
                    )
                )

    caps = handling.get("contact_caps")
    if not isinstance(caps, dict):
        findings.append(Finding("handling.contact_caps", "bad-object", "handling.contact_caps must be an object"))
    else:
        _check_closed(caps, "handling.contact_caps", CONTACT_CAPS_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in (
            "solver_iterations",
            "overlap_passes",
            "max_single_correction_m",
            "max_total_correction_m",
        ):
            if key not in caps:
                findings.append(
                    Finding(_child("handling.contact_caps", key), "missing-field", "required member is absent")
                )
        for key in ("solver_iterations", "overlap_passes"):
            if key in caps and not _is_integer(caps[key]):
                findings.append(Finding(_child("handling.contact_caps", key), "bad-integer", "expected an integer"))
            elif key in caps and caps[key] < 0:
                findings.append(
                    Finding(_child("handling.contact_caps", key), "bad-integer", "must be >= 0")
                )
        for key in ("max_single_correction_m", "max_total_correction_m"):
            if key in caps:
                _check_number(caps[key], _child("handling.contact_caps", key), findings, minimum=0.0)

    surfaces = handling.get("surfaces")
    if not isinstance(surfaces, list):
        findings.append(Finding("handling.surfaces", "bad-surfaces", "surfaces must be an array"))
    else:
        for index, item in enumerate(surfaces):
            _validate_surface_modifier(item, _index("handling.surfaces", index), findings)


def _validate_max_yaw_rate(value: Any, path: str, findings: list[Finding]) -> None:
    """Finite positive number, null, or the exact {"unlimited": true} object."""
    if value is None:
        return
    if isinstance(value, bool):
        findings.append(Finding(path, "bad-yaw-rate", "booleans are not numbers"))
        return
    if isinstance(value, dict):
        if set(value) != {"unlimited"}:
            findings.append(
                Finding(
                    path,
                    "bad-unlimited-encoding",
                    f"unlimited encoding must be exactly {{\"unlimited\": true}}; got keys {sorted(value)!r}",
                )
            )
            return
        if value["unlimited"] is not True:
            findings.append(
                Finding(
                    path,
                    "bad-yaw-rate",
                    f"unlimited sentinel must be the JSON boolean true; got {value['unlimited']!r}",
                )
            )
        return
    if not _is_number(value):
        findings.append(Finding(path, "bad-yaw-rate", f"expected a number, null or an unlimited object, got {type(value).__name__}"))
        return
    if not math.isfinite(value):
        findings.append(Finding(path, "bad-yaw-rate", f"non-finite number {value!r}; use {{\"unlimited\": true}} for INF"))
        return
    if value <= 0:
        findings.append(Finding(path, "bad-yaw-rate", f"{value!r} must be positive"))


def _validate_handling(
    document: Mapping[str, Any],
    version: str,
    findings: list[Finding],
) -> None:
    handling = document.get("handling")
    if not isinstance(handling, dict):
        findings.append(Finding("handling", "bad-handling", "handling must be an object"))
        return

    if version == "1.1.0":
        required = HANDLING_V1_1_0_REQUIRED
        allowed = frozenset(HANDLING_V1_1_0_REQUIRED)
        contract = RECIPE_SCHEMA_V1_1_0
    else:
        required = HANDLING_V1_0_0_REQUIRED
        allowed = frozenset(HANDLING_V1_0_0_REQUIRED)
        contract = RECIPE_SCHEMA_V1_0_0

    _check_closed(handling, "handling", allowed, findings, contract)
    for key in required:
        if key not in handling:
            findings.append(Finding(_child("handling", key), "missing-field", "required member is absent"))

    _validate_handling_common(handling, findings)

    if version != "1.1.0":
        return

    # Five added motor inputs.
    for field in FIVE_FIELDS:
        path = _child("handling", field)
        if field not in handling:
            continue  # already reported as a missing required member
        value = handling.get(field)
        if value is None:
            if path not in _unknown_paths(document):
                findings.append(
                    Finding(
                        path,
                        "null-without-unknown",
                        "null means unresolved and requires a resolving unknowns entry at this dotted path",
                    )
                )
            continue
        if path in _unknown_paths(document):
            # Also reported by the general resolved-but-unknown rule.
            findings.append(
                Finding(
                    path,
                    "resolved-but-unknown",
                    "a determined value is listed in unknowns; remove the entry or set the value to null",
                )
            )

    _validate_max_yaw_rate(handling.get("max_yaw_rate_rad_s"), "handling.max_yaw_rate_rad_s", findings)

    trigger = handling.get("reverse_trigger_speed_m_s")
    if trigger is not None:
        _check_number(
            trigger,
            "handling.reverse_trigger_speed_m_s",
            findings,
            minimum=0.0,
            maximum=REVERSE_TRIGGER_MAX_M_S,
        )

    hold = handling.get("reverse_hold_time_s")
    if hold is not None:
        _check_number(
            hold,
            "handling.reverse_hold_time_s",
            findings,
            minimum=REVERSE_HOLD_MIN_S,
        )

    acceleration = handling.get("reverse_acceleration_m_s2")
    top_speed = handling.get("reverse_top_speed_m_s")
    if acceleration is not None:
        _check_number(
            acceleration,
            "handling.reverse_acceleration_m_s2",
            findings,
            minimum=0.0,
        )
    if top_speed is not None:
        _check_number(
            top_speed,
            "handling.reverse_top_speed_m_s",
            findings,
            minimum=0.0,
        )

    # Cross-field rule, duplicated from properties.handling.allOf because this
    # stdlib checker does not evaluate allOf/if/then.
    if _is_finite_number(acceleration) and acceleration > 0:
        if top_speed is None:
            findings.append(
                Finding(
                    "handling.reverse_top_speed_m_s",
                    "reverse-cross-field",
                    f"reverse acceleration {acceleration!r} > 0 requires a present, positive reverse_top_speed_m_s (null is unresolved)",
                )
            )
        elif not _is_finite_number(top_speed) or top_speed <= 0:
            findings.append(
                Finding(
                    "handling.reverse_top_speed_m_s",
                    "reverse-cross-field",
                    f"reverse acceleration {acceleration!r} > 0 requires a positive reverse_top_speed_m_s (got {top_speed!r})",
                )
            )


def _validate_upgrades(document: Mapping[str, Any], findings: list[Finding]) -> None:
    upgrades = document.get("upgrades")
    if not isinstance(upgrades, dict):
        findings.append(Finding("upgrades", "bad-upgrades", "upgrades must be an object"))
        return
    _check_closed(upgrades, "upgrades", UPGRADES_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
    for key in ("levels", "engine", "tires", "chassis", "max_increase_percent"):
        if key not in upgrades:
            findings.append(Finding(_child("upgrades", key), "missing-field", "required member is absent"))
    if "levels" in upgrades:
        _check_number_array(
            upgrades["levels"],
            "upgrades.levels",
            findings,
            minimum=0,
            maximum=2,
            min_items=3,
            max_items=3,
            unique=True,
            integer=True,
        )

    engine = upgrades.get("engine")
    if "engine" in upgrades and not isinstance(engine, dict):
        findings.append(Finding("upgrades.engine", "bad-upgrades-engine", "must be an object"))
    elif isinstance(engine, dict):
        _check_closed(engine, "upgrades.engine", UPGRADE_ENGINE_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in ("acceleration_factors", "top_speed_factors"):
            if key not in engine:
                findings.append(Finding(_child("upgrades.engine", key), "missing-field", "required member is absent"))
            else:
                _check_number_array(
                    engine[key],
                    _child("upgrades.engine", key),
                    findings,
                    minimum=1.0,
                    min_items=3,
                    max_items=3,
                )

    tires = upgrades.get("tires")
    if "tires" in upgrades and not isinstance(tires, dict):
        findings.append(Finding("upgrades.tires", "bad-upgrades-tires", "must be an object"))
    elif isinstance(tires, dict):
        _check_closed(tires, "upgrades.tires", UPGRADE_TIRES_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in ("grip_lateral_damping_factors", "drift_exit_blend_divisors"):
            if key not in tires:
                findings.append(Finding(_child("upgrades.tires", key), "missing-field", "required member is absent"))
            else:
                _check_number_array(
                    tires[key],
                    _child("upgrades.tires", key),
                    findings,
                    minimum=1.0,
                    min_items=3,
                    max_items=3,
                )

    chassis = upgrades.get("chassis")
    if "chassis" in upgrades and not isinstance(chassis, dict):
        findings.append(Finding("upgrades.chassis", "bad-upgrades-chassis", "must be an object"))
    elif isinstance(chassis, dict):
        _check_closed(chassis, "upgrades.chassis", UPGRADE_CHASSIS_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in ("yaw_gain_factors", "impact_speed_loss_factors"):
            if key not in chassis:
                findings.append(Finding(_child("upgrades.chassis", key), "missing-field", "required member is absent"))
            elif key == "yaw_gain_factors":
                _check_number_array(
                    chassis[key],
                    _child("upgrades.chassis", key),
                    findings,
                    minimum=1.0,
                    min_items=3,
                    max_items=3,
                )
            else:
                _check_number_array(
                    chassis[key],
                    _child("upgrades.chassis", key),
                    findings,
                    minimum=0.0,
                    maximum=1.0,
                    min_items=3,
                    max_items=3,
                )

    max_increase = upgrades.get("max_increase_percent")
    if "max_increase_percent" in upgrades and not isinstance(max_increase, dict):
        findings.append(
            Finding("upgrades.max_increase_percent", "bad-upgrades-max-increase", "must be an object")
        )
    elif isinstance(max_increase, dict):
        _check_closed(
            max_increase, "upgrades.max_increase_percent", UPGRADE_MAX_INCREASE_MEMBERS, findings,
            RECIPE_SCHEMA_V1_0_0,
        )
        for key in ("acceleration", "top_speed"):
            if key not in max_increase:
                findings.append(
                    Finding(_child("upgrades.max_increase_percent", key), "missing-field", "required member is absent")
                )
            else:
                _check_number(
                    max_increase[key],
                    _child("upgrades.max_increase_percent", key),
                    findings,
                    minimum=0.0,
                )


def _validate_detachable_parts(document: Mapping[str, Any], findings: list[Finding]) -> None:
    parts = document.get("detachable_parts")
    if not isinstance(parts, list):
        findings.append(Finding("detachable_parts", "bad-detachable-parts", "detachable_parts must be an array"))
        return
    if len(parts) > 3:
        findings.append(Finding("detachable_parts", "too-many-parts", "at most 3 detachable parts"))
    for index, part in enumerate(parts):
        path = _index("detachable_parts", index)
        if not isinstance(part, dict):
            findings.append(Finding(path, "bad-detachable-part", "part must be an object"))
            continue
        _check_closed(part, path, DETACHABLE_PART_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        for key in ("slot", "mesh_id", "lod_ids", "attachment_transform", "impact_region", "thresholds"):
            if key not in part:
                findings.append(Finding(_child(path, key), "missing-field", "required member is absent"))
        if part.get("slot") not in ("front_bumper", "rear_bumper", "rear_wing"):
            findings.append(
                Finding(
                    _child(path, "slot"),
                    "bad-slot",
                    f"must be 'front_bumper', 'rear_bumper' or 'rear_wing' (got {part.get('slot')!r})",
                )
            )
        if "mesh_id" in part:
            _check_string(part["mesh_id"], _child(path, "mesh_id"), findings, nullable=True, min_length=0)
        if "lod_ids" in part:
            lods = part["lod_ids"]
            if not isinstance(lods, list):
                findings.append(Finding(_child(path, "lod_ids"), "bad-lod-ids", "must be an array of strings"))
            else:
                for lod_index, lod in enumerate(lods):
                    if not isinstance(lod, str):
                        findings.append(
                            Finding(_index(_child(path, "lod_ids"), lod_index), "bad-lod-id", "must be a string")
                        )
        for key in ("attachment_transform", "impact_region"):
            if key in part and part[key] is not None and not isinstance(part[key], dict):
                findings.append(Finding(_child(path, key), f"bad-{key}", "must be an object or null"))
        if "thresholds" in part:
            thresholds = part["thresholds"]
            if not isinstance(thresholds, dict):
                findings.append(
                    Finding(_child(path, "thresholds"), "bad-thresholds", "thresholds must be an object")
                )
            else:
                _check_closed(thresholds, _child(path, "thresholds"), THRESHOLD_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
                for key in ("loosen_m_s", "detach_single_m_s", "detach_accumulated_m_s"):
                    if key not in thresholds:
                        findings.append(
                            Finding(_child(_child(path, "thresholds"), key), "missing-field", "required member is absent")
                        )
                    else:
                        _check_number(
                            thresholds[key],
                            _child(_child(path, "thresholds"), key),
                            findings,
                            minimum=0.0,
                        )


def _unknown_paths(document: Mapping[str, Any]) -> list[str]:
    """Dotted paths declared in the document's unknowns list (valid entries only)."""
    paths: list[str] = []
    unknowns = document.get("unknowns")
    if not isinstance(unknowns, list):
        return paths
    for entry in unknowns:
        if isinstance(entry, dict):
            candidate = entry.get("path")
            if isinstance(candidate, str):
                paths.append(candidate)
    return paths


def _validate_unknowns(document: Mapping[str, Any], findings: list[Finding]) -> None:
    unknowns = document.get("unknowns")
    if not isinstance(unknowns, list):
        findings.append(Finding("unknowns", "bad-unknowns", "unknowns must be an array"))
        return
    paths: list[str] = []
    for index, entry in enumerate(unknowns):
        path = _index("unknowns", index)
        if not isinstance(entry, dict):
            findings.append(Finding(path, "bad-unknown", "unknown entry must be an object"))
            continue
        _check_closed(entry, path, UNKNOWN_ENTRY_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0)
        unknown_path = entry.get("path")
        if not isinstance(unknown_path, str) or not UNKNOWN_PATH_RE.match(unknown_path):
            findings.append(
                Finding(_child(path, "path"), "bad-unknown-path", "path must be a dotted path with optional [index] segments")
            )
        else:
            paths.append(unknown_path)
        if not isinstance(entry.get("reason"), str) or not entry.get("reason"):
            findings.append(Finding(_child(path, "reason"), "bad-unknown-reason", "reason must be a non-empty string"))
        if "blocking" in entry and not isinstance(entry["blocking"], bool):
            findings.append(Finding(_child(path, "blocking"), "bad-unknown-blocking", "blocking must be a boolean"))
        if "until" in entry and entry["until"] is not None and not isinstance(entry["until"], str):
            findings.append(Finding(_child(path, "until"), "bad-unknown-until", "until must be a string or null"))

    for candidate in paths:
        value, found = _resolve_path(document, candidate)
        if not found:
            findings.append(
                Finding(
                    "unknowns",
                    "unresolved-unknown",
                    f"unknown path {candidate!r} does not resolve to any member of this document",
                )
            )
        elif value is not None:
            findings.append(
                Finding(
                    "unknowns",
                    "resolved-but-unknown",
                    f"unknown path {candidate!r} resolves to a determined value; an unknown must resolve to null",
                )
            )

    null_paths: list[str] = []
    _collect_null_paths(document, "", null_paths)
    for null_path in null_paths:
        explained = any(
            null_path == candidate
            or null_path.startswith(candidate + ".")
            or null_path.startswith(candidate + "[")
            for candidate in paths
        )
        if not explained:
            findings.append(
                Finding(
                    null_path,
                    "unlisted-null",
                    "null value must be listed in unknowns with a reason; do not leave an undetermined value unexplained",
                )
            )


def _validate_provenance(document: Mapping[str, Any], findings: list[Finding]) -> None:
    provenance = document.get("provenance")
    if not isinstance(provenance, dict):
        findings.append(Finding("provenance", "bad-provenance", "provenance must be an object"))
        return
    _check_closed(provenance, "provenance", frozenset(PROVENANCE_FIELDS), findings, RECIPE_SCHEMA_V1_0_0)
    for key in PROVENANCE_FIELDS:
        value = provenance.get(key)
        if value is not None and not isinstance(value, str):
            findings.append(Finding(_child("provenance", key), "bad-provenance-field", "must be a string or null"))


def _validate_content_hash(document: Mapping[str, Any], findings: list[Finding]) -> None:
    recorded = document.get("content_hash")
    if not isinstance(recorded, str) or not CONTENT_HASH_RE.match(recorded):
        findings.append(Finding("content_hash", "bad-content-hash", "must look like 'sha256:<64 lowercase hex>'"))
        return
    actual = content_hash_of(document)
    if recorded != actual:
        findings.append(
            Finding(
                "content_hash",
                "content-hash-mismatch",
                f"recorded hash is {recorded} but the file hashes to {actual}; recompute over canonical JSON with the content_hash member removed",
            )
        )


def _validate_presentation(document: Mapping[str, Any], findings: list[Finding]) -> None:
    if "presentation" not in document:
        return
    if not isinstance(document["presentation"], dict):
        findings.append(Finding("presentation", "bad-presentation", "presentation must be an object"))


# ---------------------------------------------------------------------------
# Motor-ready mode
# ---------------------------------------------------------------------------


def _validate_motor_ready(document: Mapping[str, Any], findings: list[Finding]) -> None:
    unknown_paths = set(_unknown_paths(document))
    for path in MOTOR_INPUTS:
        value, found = _resolve_path(document, path)
        if not found:
            findings.append(
                Finding(
                    path,
                    "motor-input-missing",
                    "required typed motor input has no source property in this recipe",
                )
            )
            continue
        if value is None:
            findings.append(
                Finding(
                    path,
                    "motor-input-unresolved",
                    "required typed motor input is null/unresolved; a baker must refuse rather than substitute a typed default",
                )
            )
            continue
        if path in unknown_paths:
            findings.append(
                Finding(path, "motor-input-unknown", "required typed motor input is listed in unknowns")
            )
            continue
        if path != "handling.acceleration_curve" or not isinstance(value, list):
            continue
        if not value:
            findings.append(
                Finding(path, "motor-input-empty", "acceleration curve needs at least one authored point")
            )
            continue
        previous_speed: float | None = None
        for index, point in enumerate(value):
            speed = point.get("speed_m_s") if isinstance(point, dict) else None
            if not _is_finite_number(speed):
                # Malformed points are already reported by schema validation;
                # ordering compares the authored finite speeds only.
                continue
            if previous_speed is not None and speed <= previous_speed:
                findings.append(
                    Finding(
                        f"{_index(path, index)}.speed_m_s",
                        "motor-input-order",
                        f"speed {speed!r} does not strictly exceed previous speed {previous_speed!r}",
                    )
                )
            previous_speed = speed


# ---------------------------------------------------------------------------
# Document-level validation
# ---------------------------------------------------------------------------


def validate_recipe_document(
    document: Mapping[str, Any],
    *,
    mode: str = DEFAULT_MODE,
) -> list[Finding]:
    """Validate a parsed recipe document and return findings (empty = valid)."""
    findings: list[Finding] = []

    for field in ROOT_REQUIRED:
        if field not in document:
            findings.append(Finding(field, "missing-field", "required member is absent"))

    version = document.get("schema_version")
    if version not in SUPPORTED_VERSIONS:
        findings.append(
            Finding(
                "schema_version",
                "unsupported-schema-version",
                f"must be one of {list(SUPPORTED_VERSIONS)} (got {version!r}); versions are never migrated",
            )
        )
        return findings

    _check_closed(document, "", ROOT_MEMBERS, findings, RECIPE_SCHEMA_V1_0_0 if version == "1.0.0" else RECIPE_SCHEMA_V1_1_0)

    if "car_id" in document:
        car_id = document["car_id"]
        if not isinstance(car_id, str) or not STABLE_ID_RE.match(car_id):
            findings.append(Finding("car_id", "bad-car-id", "must be a stable semantic ID matching the common schema pattern"))
    if "display_name" in document:
        _check_string(document["display_name"], "display_name", findings)
    if "revision" in document:
        _check_string(document["revision"], "revision", findings)
    if "status" in document and document["status"] not in STATUSES:
        findings.append(
            Finding("status", "bad-status", f"must be one of {list(STATUSES)} (got {document['status']!r})")
        )

    _validate_presentation(document, findings)
    _validate_units(document, findings)
    _validate_coordinate_frame(document, findings)
    _validate_dimensions(document, findings)
    if "mass_kg" in document:
        _check_number(document["mass_kg"], "mass_kg", findings, exclusive_minimum=0.0)
    _validate_contact_proxy(document, findings)
    _validate_engine(document, findings)
    _validate_handling(document, version, findings)
    _validate_upgrades(document, findings)
    _validate_detachable_parts(document, findings)
    _validate_unknowns(document, findings)
    _validate_provenance(document, findings)
    _validate_content_hash(document, findings)

    if mode == "motor-ready":
        _validate_motor_ready(document, findings)

    return findings


def validate_recipe_file(path: Path, *, mode: str = DEFAULT_MODE) -> list[Finding]:
    """Load and validate one recipe file."""
    document, findings = load_json_document(path)
    if document is None:
        return findings
    findings.extend(validate_recipe_document(document, mode=mode))
    return findings


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------


def _default_root() -> Path:
    # tools/car_recipe_schema/validate_car_recipe.py -> repository root
    return Path(__file__).resolve().parents[2]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Validate Roadstorm car handling source recipes against "
            "schemas/handling_config.schema.json (1.0.0) or "
            "schemas/handling_config_v1_1.schema.json (1.1.0)."
        ),
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="recipe files or directories (default: fixtures/car_recipe/positive under the repository root)",
    )
    parser.add_argument(
        "--mode",
        choices=MODES,
        default=DEFAULT_MODE,
        help="schema = historical validity only; motor-ready = also refuse missing/unresolved motor inputs (default)",
    )
    parser.add_argument("--root", type=Path, default=None, help="repository root (default: inferred from this script)")
    args = parser.parse_args(argv)

    root = args.root.resolve() if args.root else _default_root()
    if not root.is_dir():
        print(f"error: root {root} is not a directory", file=sys.stderr)
        return 2

    targets = args.paths or [root / "fixtures" / "car_recipe" / "positive"]

    findings: list[Finding] = []
    checked = 0
    unreadable = False
    for target in targets:
        resolved = target if target.is_absolute() else root / target
        if resolved.is_dir():
            files = sorted(resolved.rglob("*.json"))
            if not files:
                print(f"error: no recipe files in {resolved}", file=sys.stderr)
                return 2
            for path in files:
                file_findings = validate_recipe_file(path, mode=args.mode)
                findings.extend(file_findings)
                if any(f.code == "unreadable-file" for f in file_findings):
                    unreadable = True
                checked += 1
        elif resolved.is_file():
            file_findings = validate_recipe_file(resolved, mode=args.mode)
            findings.extend(file_findings)
            if any(f.code == "unreadable-file" for f in file_findings):
                unreadable = True
            checked += 1
        else:
            print(f"error: {resolved} is not a readable file or directory", file=sys.stderr)
            return 2

    errors = [finding for finding in findings if finding.is_error]
    warnings = [finding for finding in findings if not finding.is_error]
    for finding in findings:
        print(finding)
    print(
        f"checked {checked} recipe file(s) in mode {args.mode!r}: "
        f"{len(errors)} error(s), {len(warnings)} warning(s)"
    )
    if unreadable:
        return 2
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
