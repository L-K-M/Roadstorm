#!/usr/bin/env python3
"""Roadstorm Racer! handling benchmark fixture validator.

Ownership: schemas/handling/** (PLAN.md M0.9 handling-contract slice, job
b20cb153-94a8-4997-be00-1f8335daa1a0). Companion fixtures live in
fixtures/handling/ and the contract itself in handling_fixture.schema.json.

This module is the executable form of the handling-fixture contract in
``handling_fixture.schema.json``, which was derived from
``docs/BENCHMARKS.md`` ("Handling fixtures"), ``docs/TECHNICAL_DESIGN.md``
("Content contracts", ReferenceRun/Scenario) and ``docs/GAME_DESIGN.md``
("Handling and drift", "Drafting"). For every fixture file it checks:

* required fields, closed vocabularies (families, roles, events, gates) and
  closed objects (undeclared members are rejected, matching the schema's
  additionalProperties: false);
* numeric ranges (geometry, commands, gates and barriers inside their
  authored length, metric comparators) and the draft fixture's wake-window
  expectations correlated with the GAME_DESIGN documented 5-20 m window;
* revision identifiers: the contract ``schema_version``, the fixture
  ``revision``, the ``content_hash`` recomputed over canonical JSON, and
  controller and handling revision identifiers;
* the honesty rule in both directions: every JSON null must be listed in
  ``unknowns`` with a reason, every ``unknowns`` entry must resolve to a
  member of the document, and no fixture may carry a metric whose status
  claims a measurement. Authored initial values and documented design targets
  are fine; invented measurements are not.

Deliberate limitations (documented in README.md):

* Standard library only, standalone. It does not run the engine, execute a
  fixture, or check physics outcomes; those are M1 motor and reference-run
  gates. A valid fixture is a well-formed contract, not a passing test.
* It validates fixture files, not the schema's full JSON Schema semantics.
  The schema document remains the text contract; this checker implements the
  same rules in plain Python so no schema dependency is required.
* It cannot make unknown facts known. Missing or null values are reported,
  never filled in and never guessed.

Usage as a library::

    from validate_fixtures import validate_fixture, validate_fixture_directory
    findings = validate_fixture(Path("fixtures/handling/sweeper.json"))
    findings += validate_fixture_directory(Path("fixtures/handling"))

Exit codes for the CLI wrapper: 0 = no errors, 1 = validation errors,
2 = a path could not be read or the command line was wrong. A file that is
not JSON or not UTF-8 is a content defect (exit 1); a missing or unreadable
path is an environment problem (exit 2).

Original project code under the Unlicense.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

# ---------------------------------------------------------------------------
# Contract constants (kept in step with handling_fixture.schema.json)
# ---------------------------------------------------------------------------

FIXTURE_SCHEMA_VERSION = "1.0.0"
SCHEMA_DOCUMENT_NAME = "handling_fixture.schema.json"

# Stable semantic ID pattern, reused verbatim from schemas/common.schema.json
# ("stable_id") so fixture and car IDs share one vocabulary.
STABLE_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_-]+)*$")

# Hash spelling, reused from schemas/common.schema.json ("content_hash").
CONTENT_HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

# Revision identifier pattern, reused from schemas/common.schema.json
# ("schema_version").
REVISION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")

FIXTURE_ID_RE = re.compile(r"^fixture\.handling\.[a-z][a-z0-9_]*$")
RUN_ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")

# Dotted path with optional [index] segments, used by unknowns entries.
UNKNOWN_PATH_RE = re.compile(
    r"^[a-z_][a-z0-9_]*(?:\[[0-9]+\])?(?:\.[a-z_][a-z0-9_]*(?:\[[0-9]+\])?)*$"
)

REQUIRED_TOP_LEVEL = (
    "schema_version",
    "fixture_id",
    "fixture_family",
    "title",
    "description",
    "revision",
    "status",
    "units",
    "coordinate_frame",
    "geometry",
    "surfaces",
    "runs",
    "timing_gates",
    "expected_events",
    "comparison",
    "cars",
    "unknowns",
    "content_hash",
    "provenance",
)

FIXTURE_FAMILIES = (
    "straight",
    "sweeper",
    "hairpin",
    "esses",
    "gravel",
    "grounding",
    "contact",
    "draft",
    "regression",
)
# BENCHMARKS asks for at least ten clean paired runs per relevant corner
# fixture; these families are the relevant corner fixtures.
CORNER_FAMILIES = ("sweeper", "hairpin", "esses", "gravel")
MIN_PAIRED_RUNS = 10

FIXTURE_STATUSES = ("provisional", "measured", "frozen", "superseded", "example")
SEGMENT_TYPES = ("straight", "arc")
SEGMENT_DIRECTIONS = ("left", "right")
BARRIER_KINDS = ("wall", "barrier", "guardrail")
FEATURE_TYPES = ("crest", "compression", "jump")
RUN_ROLES = ("primary", "control", "comparison")
START_MODES = ("standing", "rolling")
DRIVER_KINDS = ("controller", "scripted_commands")
CONTROLLER_IDS = ("calibration_driver", "scripted_grip", "scripted_drift")
GATE_KINDS = ("start", "intermediate", "finish")
LOADOUTS = ("stock", "max_upgrade")
EVENT_TYPES = (
    "acceleration_phase_complete",
    "braking_phase_complete",
    "top_speed_reached",
    "reverse_engaged",
    "drift_entry",
    "drift_sustained",
    "drift_exit",
    "drift_recovery",
    "surge_granted",
    "surface_transition",
    "airborne_takeoff",
    "airborne_landing",
    "stable_landing",
    "wall_contact",
    "car_contact",
    "reset_requested",
    "reset_blocked_anchor",
    "overlap_correction",
    "correction_limit_saturated",
    "drafting_eligible",
    "drafting_fade",
)
COMPARATORS = ("eq", "lte", "gte", "lt", "gt", "range", "ratio_range", "report")
THRESHOLD_COMPARATORS = ("eq", "lte", "gte", "lt", "gt")
RANGE_COMPARATORS = ("range", "ratio_range")
# A fixture carries documented targets and reporting requirements only.
METRIC_STATUSES = ("documented_initial_target", "undecided")
PROVENANCE_FIELDS = (
    "source_contract",
    "author",
    "model",
    "provider",
    "date_utc",
    "note",
)

# Documented design bounds enforced as invalid ranges.
MAX_ABS_GRADE_PERCENT = 12.0
MAX_ABS_BANKING_DEG = 12.0
MAX_ARC_ANGLE_DEG = 360.0
MAX_OTHER_PARTICIPANTS = 7

# Keys whose null values are documentation, not undetermined data: they are
# excluded from the null-requires-unknown rule.
NOTE_KEYS = ("note",)
NULL_EXEMPT_SUBTREES = ("provenance", "unknowns", "content_hash")

# Gate positions may sit at most this far past a segment end (authoring
# rounding of arc lengths such as 188.4956 m).
GATE_LENGTH_TOLERANCE_M = 1e-3

# Closed-object vocabularies. handling_fixture.schema.json sets
# additionalProperties: false at the root and in every $defs object, so the
# validator rejects undeclared members instead of ignoring them.
TOP_LEVEL_MEMBERS = frozenset(REQUIRED_TOP_LEVEL) | {"barriers", "features"}
UNITS_MEMBERS = frozenset({"length", "mass", "time", "angle", "speed"})
COORDINATE_FRAME_MEMBERS = frozenset({"forward", "up", "right"})
GEOMETRY_MEMBERS = frozenset({"start_reference", "closed_loop", "segments"})
SEGMENT_MEMBERS = frozenset({
    "type", "length_m", "radius_m", "angle_deg", "direction", "grade_percent",
    "banking_deg", "width_m", "surface_id", "note",
})
SURFACE_MEMBERS = frozenset({"surface_id", "description", "handling_modifiers", "note"})
BARRIER_MEMBERS = frozenset({
    "barrier_id", "kind", "segment_index", "arc_length_m", "lateral_offset_m",
    "angle_deg", "length_m", "height_m", "thickness_m", "note",
})
FEATURE_MEMBERS = frozenset({
    "type", "segment_index", "arc_length_m", "description",
    "takeoff_grade_percent", "airborne_gap_m", "landing_run_m", "note",
})
RUN_MEMBERS = frozenset({
    "run_id", "role", "description", "initial_state", "other_participants",
    "surface_overrides", "driver",
})
INITIAL_STATE_MEMBERS = frozenset({
    "start_mode", "velocity_m_s", "heading_deg", "position_m", "grounded", "note",
})
PARTICIPANT_MEMBERS = frozenset({"slot", "car_id", "pose", "velocity_m_s", "driver", "note"})
POSE_MEMBERS = frozenset({"position_m", "heading_deg"})
DRIVER_MEMBERS = frozenset({
    "kind", "controller_id", "controller_revision", "command_schedule", "assists", "note",
})
COMMAND_MEMBERS = frozenset({"t_s", "steer", "throttle", "brake", "handbrake", "reset"})
SURFACE_OVERRIDE_MEMBERS = frozenset({"segment_index", "surface_id"})
TIMING_GATE_MEMBERS = frozenset({"gate_id", "kind", "segment_index", "arc_length_m", "purpose"})
EXPECTED_EVENT_MEMBERS = frozenset({"event", "required", "applies_to_runs", "note"})
COMPARISON_MEMBERS = frozenset({"purpose", "paired_runs_required", "metrics", "note"})
METRIC_MEMBERS = frozenset({
    "name", "description", "comparator", "value", "value_min", "value_max", "unit", "status",
})
CAR_SET_MEMBERS = frozenset({"car_ids", "loadouts", "handling_revision", "note"})
UNKNOWN_ENTRY_MEMBERS = frozenset({"path", "reason", "blocking", "until"})

# GAME_DESIGN "Drafting": following a rival within approximately 5-20 m and a
# narrow forward cone gives the wake benefit. BENCHMARKS "Handling fixtures"
# brackets the window with 4 m and 21 m initial gaps, so a draft fixture must
# not expect wake eligibility at a gap outside the documented window.
WAKE_WINDOW_M = (5.0, 20.0)
WAKE_CONE_HALF_ANGLE_DEG = 10.0
WAKE_LATERAL_LIMIT_M = 1.5
WAKE_WINDOW_METRIC_NAME = "wake_gap_window_m"
GAP_TOLERANCE_M = 1e-9


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
# JSON loading with duplicate-member and encoding detection
# ---------------------------------------------------------------------------


def _reject_duplicate_keys(pairs: Sequence[tuple[str, Any]]) -> dict[str, Any]:
    seen: dict[str, Any] = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f"duplicate JSON member {key!r}")
        seen[key] = value
    return seen


def load_json_document(path: Path) -> tuple[dict[str, Any] | None, list[Finding]]:
    """Load a JSON object, reporting unreadable/invalid files as findings.

    Returns (document, findings). The document is None when the bytes could
    not be decoded into a JSON object at all; the caller decides the exit
    code from the findings.
    """
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
        document = json.loads(text, object_pairs_hook=_reject_duplicate_keys)
    except ValueError as exc:
        findings.append(Finding("", "invalid-json", f"not a JSON document: {exc}"))
        return None, findings
    if not isinstance(document, dict):
        findings.append(Finding("", "not-an-object", "top-level JSON value is not an object"))
        return None, findings
    return document, findings


# ---------------------------------------------------------------------------
# Canonical hashing (schemas/common.schema.json "content_hash")
# ---------------------------------------------------------------------------


def canonical_json(document: Mapping[str, Any]) -> str:
    """Canonical JSON: sorted keys, compact separators, UTF-8 text."""
    return json.dumps(document, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def content_hash_of(document: Mapping[str, Any]) -> str:
    """SHA-256 over canonical JSON of the file with content_hash removed."""
    payload = {key: value for key, value in document.items() if key != "content_hash"}
    return "sha256:" + hashlib.sha256(canonical_json(payload).encode("utf-8")).hexdigest()


# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def _child_path(path: str, key: str) -> str:
    return f"{path}.{key}" if path else key


def _index_path(path: str, index: int) -> str:
    return f"{path}[{index}]"


def _check_closed(mapping: Any, path: str, allowed: frozenset, findings: list[Finding]) -> None:
    """Reject members a closed schema object does not declare.

    handling_fixture.schema.json sets additionalProperties: false at the root
    and in every $defs object; silently ignoring undeclared members would let
    a fixture drift away from the text contract.
    """
    if not isinstance(mapping, dict):
        return
    for key in mapping:
        if key not in allowed:
            findings.append(
                Finding(
                    _child_path(path, key),
                    "unknown-member",
                    f"member {key!r} is not declared by handling_fixture.schema.json (additionalProperties: false)",
                )
            )


def _resolve_unknown_path(document: Mapping[str, Any], path: str) -> tuple[Any, bool]:
    """Resolve an unknowns dotted path; return (value, found).

    Accepts bracket indices (runs[0].initial_state) and bare numeric tokens.
    A path that exists and holds JSON null resolves to (None, True).
    """
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


def _run_wake_geometry(run: Mapping[str, Any]) -> tuple[float, float] | None:
    """Longitudinal gap and lateral separation from a run to its single leader.

    Returns None when the run has no exactly-one-participant layout or the
    headings are not aligned with the segment tangent, where a plain axis
    decomposition of the authored positions would be wrong.
    """
    initial = run.get("initial_state")
    participants = run.get("other_participants")
    if not isinstance(initial, dict) or not isinstance(participants, list) or len(participants) != 1:
        return None
    participant = participants[0]
    if not isinstance(participant, dict) or not isinstance(participant.get("pose"), dict):
        return None
    ego_position = initial.get("position_m")
    leader_position = participant["pose"].get("position_m")
    if not (isinstance(ego_position, list) and isinstance(leader_position, list)):
        return None
    if len(ego_position) != 3 or len(leader_position) != 3:
        return None
    if not all(_is_number(v) for v in ego_position) or not all(_is_number(v) for v in leader_position):
        return None
    if initial.get("heading_deg") != 0 or participant["pose"].get("heading_deg") != 0:
        return None
    gap = abs(float(ego_position[2]) - float(leader_position[2]))
    lateral = abs(float(ego_position[0]) - float(leader_position[0]))
    return gap, lateral



def _collect_null_paths(value: Any, path: str, out: list[str]) -> None:
    """Collect dotted paths of JSON null values, skipping documentation-only keys."""
    if value is None:
        out.append(path)
        return
    if isinstance(value, dict):
        for key, item in value.items():
            if key in NOTE_KEYS or key in NULL_EXEMPT_SUBTREES:
                continue
            _collect_null_paths(item, _child_path(path, key), out)
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            _collect_null_paths(item, _index_path(path, index), out)


def _segment_length_m(segment: Mapping[str, Any]) -> float | None:
    if segment.get("type") == "straight":
        length = segment.get("length_m")
        return float(length) if _is_number(length) else None
    radius = segment.get("radius_m")
    angle = segment.get("angle_deg")
    if _is_number(radius) and _is_number(angle):
        return float(radius) * math.radians(float(angle))
    return None


# ---------------------------------------------------------------------------
# Section validators
# ---------------------------------------------------------------------------


def _validate_units(document: Mapping[str, Any], findings: list[Finding]) -> None:
    units = document.get("units")
    if not isinstance(units, dict):
        findings.append(Finding("units", "bad-units", "units must be an object"))
        return
    expected = {"length": "m", "mass": "kg", "time": "s", "angle": "deg", "speed": "m/s"}
    for key, want in expected.items():
        if units.get(key) != want:
            findings.append(
                Finding(
                    _child_path("units", key),
                    "bad-unit",
                    f"must be {want!r} (got {units.get(key)!r})",
                )
            )
    for key in units:
        if key not in expected:
            findings.append(Finding(_child_path("units", key), "unknown-unit", "unknown unit member"))


def _validate_coordinate_frame(document: Mapping[str, Any], findings: list[Finding]) -> None:
    frame = document.get("coordinate_frame")
    if not isinstance(frame, dict):
        findings.append(Finding("coordinate_frame", "bad-frame", "coordinate_frame must be an object"))
        return
    expected = {"forward": "-Z", "up": "+Y", "right": "+X"}
    for key, want in expected.items():
        if frame.get(key) != want:
            findings.append(
                Finding(
                    _child_path("coordinate_frame", key),
                    "bad-frame-axis",
                    f"must be {want!r} (got {frame.get(key)!r})",
                )
            )
    _check_closed(frame, "coordinate_frame", COORDINATE_FRAME_MEMBERS, findings)


def _validate_surfaces(document: Mapping[str, Any], findings: list[Finding]) -> set[str]:
    declared: set[str] = set()
    surfaces = document.get("surfaces")
    if not isinstance(surfaces, list) or not surfaces:
        findings.append(Finding("surfaces", "no-surfaces", "surfaces must be a non-empty array"))
        return declared
    for index, surface in enumerate(surfaces):
        path = _index_path("surfaces", index)
        if not isinstance(surface, dict):
            findings.append(Finding(path, "bad-surface", "surface must be an object"))
            continue
        surface_id = surface.get("surface_id")
        if not isinstance(surface_id, str) or not surface_id:
            findings.append(Finding(_child_path(path, "surface_id"), "bad-surface-id", "must be a non-empty string"))
            continue
        if surface_id in declared:
            findings.append(Finding(_child_path(path, "surface_id"), "duplicate-surface", f"surface {surface_id!r} declared twice"))
        declared.add(surface_id)
        if not isinstance(surface.get("description"), str) or not surface.get("description"):
            findings.append(Finding(_child_path(path, "description"), "bad-surface-description", "must be a non-empty string"))
        _check_closed(surface, path, SURFACE_MEMBERS, findings)
        if "handling_modifiers" in surface and surface["handling_modifiers"] is not None and not isinstance(surface["handling_modifiers"], dict):
            findings.append(Finding(_child_path(path, "handling_modifiers"), "bad-handling-modifiers", "must be an object or null (null means the per-car handling resource owns the modifiers and requires an unknowns entry)"))
        if "note" in surface and surface["note"] is not None and not isinstance(surface["note"], str):
            findings.append(Finding(_child_path(path, "note"), "bad-note", "note must be a string or null"))
    return declared


def _validate_segment(segment: Any, path: str, declared_surfaces: set[str], findings: list[Finding]) -> None:
    if not isinstance(segment, dict):
        findings.append(Finding(path, "bad-segment", "segment must be an object"))
        return
    kind = segment.get("type")
    if kind not in SEGMENT_TYPES:
        findings.append(Finding(_child_path(path, "type"), "bad-segment-type", f"must be one of {list(SEGMENT_TYPES)}"))
        return
    _check_closed(segment, path, SEGMENT_MEMBERS, findings)
    if kind == "straight":
        length = segment.get("length_m")
        if not _is_number(length) or length <= 0:
            findings.append(Finding(_child_path(path, "length_m"), "bad-segment-length", "straight length_m must be a number > 0"))
    else:
        radius = segment.get("radius_m")
        if not _is_number(radius) or radius <= 0:
            findings.append(Finding(_child_path(path, "radius_m"), "bad-arc-radius", "arc radius_m must be a number > 0"))
        angle = segment.get("angle_deg")
        if not _is_number(angle) or not (0 < angle <= MAX_ARC_ANGLE_DEG):
            findings.append(
                Finding(
                    _child_path(path, "angle_deg"),
                    "bad-arc-angle",
                    f"arc angle_deg must be a number in (0, {MAX_ARC_ANGLE_DEG:g}]",
                )
            )
        direction = segment.get("direction")
        if direction not in SEGMENT_DIRECTIONS:
            findings.append(Finding(_child_path(path, "direction"), "bad-direction", f"must be one of {list(SEGMENT_DIRECTIONS)}"))
    width = segment.get("width_m")
    if not _is_number(width) or width <= 0:
        findings.append(Finding(_child_path(path, "width_m"), "bad-width", "width_m must be a number > 0"))
    grade = segment.get("grade_percent")
    if grade is not None and (not _is_number(grade) or abs(grade) > MAX_ABS_GRADE_PERCENT):
        findings.append(
            Finding(
                _child_path(path, "grade_percent"),
                "bad-grade",
                f"grade_percent must be within +/-{MAX_ABS_GRADE_PERCENT:g} (TECHNICAL_DESIGN initial grade target)",
            )
        )
    bank = segment.get("banking_deg")
    if bank is not None and (not _is_number(bank) or abs(bank) > MAX_ABS_BANKING_DEG):
        findings.append(
            Finding(
                _child_path(path, "banking_deg"),
                "bad-banking",
                f"banking_deg must be within +/-{MAX_ABS_BANKING_DEG:g} (TECHNICAL_DESIGN initial banking target)",
            )
        )
    surface_id = segment.get("surface_id")
    if not isinstance(surface_id, str) or surface_id not in declared_surfaces:
        findings.append(Finding(_child_path(path, "surface_id"), "unknown-surface", f"surface {surface_id!r} is not declared in surfaces"))


def _validate_geometry(document: Mapping[str, Any], findings: list[Finding]) -> int:
    geometry = document.get("geometry")
    if not isinstance(geometry, dict):
        findings.append(Finding("geometry", "bad-geometry", "geometry must be an object"))
        return 0
    start_reference = geometry.get("start_reference")
    if not isinstance(start_reference, str) or not start_reference:
        findings.append(Finding("geometry.start_reference", "missing-start-reference", "must be a non-empty string"))
    if geometry.get("closed_loop") is not False:
        findings.append(Finding("geometry.closed_loop", "not-open-section", "handling fixtures are open sections; closed_loop must be false"))
    _check_closed(geometry, "geometry", GEOMETRY_MEMBERS, findings)
    segments = geometry.get("segments")
    if not isinstance(segments, list) or not segments:
        findings.append(Finding("geometry.segments", "no-segments", "segments must be a non-empty array"))
        return 0
    declared = _validate_surfaces(document, findings)
    for index, segment in enumerate(segments):
        _validate_segment(segment, _index_path("geometry.segments", index), declared, findings)
    return len(segments)


def _validate_barriers(document: Mapping[str, Any], segment_count: int, findings: list[Finding]) -> None:
    barriers = document.get("barriers")
    if barriers is None:
        return
    if not isinstance(barriers, list):
        findings.append(Finding("barriers", "bad-barriers", "barriers must be an array when present"))
        return
    seen: set[str] = set()
    for index, barrier in enumerate(barriers):
        path = _index_path("barriers", index)
        if not isinstance(barrier, dict):
            findings.append(Finding(path, "bad-barrier", "barrier must be an object"))
            continue
        barrier_id = barrier.get("barrier_id")
        if not isinstance(barrier_id, str) or not barrier_id:
            findings.append(Finding(_child_path(path, "barrier_id"), "bad-barrier-id", "must be a non-empty string"))
        elif barrier_id in seen:
            findings.append(Finding(_child_path(path, "barrier_id"), "duplicate-barrier", f"barrier {barrier_id!r} declared twice"))
        else:
            seen.add(barrier_id)
        if barrier.get("kind") not in BARRIER_KINDS:
            findings.append(Finding(_child_path(path, "kind"), "bad-barrier-kind", f"must be one of {list(BARRIER_KINDS)}"))
        segment_index = barrier.get("segment_index")
        if not isinstance(segment_index, int) or isinstance(segment_index, bool) or not (0 <= segment_index < segment_count):
            findings.append(Finding(_child_path(path, "segment_index"), "bad-segment-index", f"must reference a segment in [0, {segment_count})"))
        arc_length = barrier.get("arc_length_m")
        if not _is_number(arc_length) or arc_length < 0:
            findings.append(Finding(_child_path(path, "arc_length_m"), "bad-arc-length", "must be a number >= 0"))
        offset = barrier.get("lateral_offset_m")
        if not _is_number(offset):
            findings.append(Finding(_child_path(path, "lateral_offset_m"), "bad-lateral-offset", "must be a finite number"))
        thickness = barrier.get("thickness_m")
        if not _is_number(thickness) or thickness <= 0:
            findings.append(Finding(_child_path(path, "thickness_m"), "bad-thickness", "must be a number > 0"))
        angle = barrier.get("angle_deg")
        if angle is not None and not _is_number(angle):
            findings.append(Finding(_child_path(path, "angle_deg"), "bad-barrier-angle", "must be a finite number or null"))
        for key in ("length_m", "height_m"):
            if key in barrier and barrier[key] is not None and (not _is_number(barrier[key]) or barrier[key] <= 0):
                findings.append(Finding(_child_path(path, key), f"bad-barrier-{key.rstrip('_m')}", f"must be a number > 0 or null (null requires an unknowns entry)"))
        _check_closed(barrier, path, BARRIER_MEMBERS, findings)
        if isinstance(segment_index, int) and not isinstance(segment_index, bool) and 0 <= segment_index < segment_count:
            segments = document.get("geometry", {}).get("segments", []) if isinstance(document.get("geometry"), dict) else []
            segment = segments[segment_index]
            length = _segment_length_m(segment) if isinstance(segment, dict) else None
            if length is not None and _is_number(arc_length) and arc_length > length + GATE_LENGTH_TOLERANCE_M:
                findings.append(
                    Finding(
                        _child_path(path, "arc_length_m"),
                        "barrier-beyond-segment",
                        f"barrier at {arc_length} m is past the {length:.4f} m segment length",
                    )
                )


def _validate_features(document: Mapping[str, Any], segment_count: int, findings: list[Finding]) -> None:
    features = document.get("features")
    if features is None:
        return
    if not isinstance(features, list):
        findings.append(Finding("features", "bad-features", "features must be an array when present"))
        return
    for index, feature in enumerate(features):
        path = _index_path("features", index)
        if not isinstance(feature, dict):
            findings.append(Finding(path, "bad-feature", "feature must be an object"))
            continue
        if feature.get("type") not in FEATURE_TYPES:
            findings.append(Finding(_child_path(path, "type"), "bad-feature-type", f"must be one of {list(FEATURE_TYPES)}"))
        segment_index = feature.get("segment_index")
        if not isinstance(segment_index, int) or isinstance(segment_index, bool) or not (0 <= segment_index < segment_count):
            findings.append(Finding(_child_path(path, "segment_index"), "bad-segment-index", f"must reference a segment in [0, {segment_count})"))
        if not isinstance(feature.get("description"), str) or not feature.get("description"):
            findings.append(Finding(_child_path(path, "description"), "bad-feature-description", "must be a non-empty string"))
        for key in ("takeoff_grade_percent", "airborne_gap_m", "landing_run_m"):
            if key in feature and feature[key] is not None and not _is_number(feature[key]):
                findings.append(Finding(_child_path(path, key), "bad-feature-parameter", "must be a finite number or null (null requires an unknowns entry)"))
        _check_closed(feature, path, FEATURE_MEMBERS, findings)


def _validate_commands(schedule: Any, path: str, findings: list[Finding]) -> None:
    if not isinstance(schedule, list) or not schedule:
        findings.append(Finding(path, "empty-schedule", "command_schedule must be a non-empty array"))
        return
    previous_t = None
    for index, command in enumerate(schedule):
        command_path = _index_path(path, index)
        if not isinstance(command, dict):
            findings.append(Finding(command_path, "bad-command", "command must be an object"))
            continue
        _check_closed(command, command_path, COMMAND_MEMBERS, findings)
        t_s = command.get("t_s")
        if not _is_number(t_s) or t_s < 0:
            findings.append(Finding(_child_path(command_path, "t_s"), "bad-command-time", "t_s must be a number >= 0"))
        elif previous_t is not None and t_s < previous_t:
            findings.append(Finding(_child_path(command_path, "t_s"), "out-of-order-schedule", "command times must be non-decreasing"))
        else:
            previous_t = t_s
        if "steer" in command and not (_is_number(command["steer"]) and -1 <= command["steer"] <= 1):
            findings.append(Finding(_child_path(command_path, "steer"), "bad-steer", "steer must be within [-1, 1]"))
        for key in ("throttle", "brake", "handbrake"):
            if key in command and not (_is_number(command[key]) and 0 <= command[key] <= 1):
                findings.append(Finding(_child_path(command_path, key), f"bad-{key}", f"{key} must be within [0, 1]"))
        if "reset" in command and not isinstance(command["reset"], bool):
            findings.append(Finding(_child_path(command_path, "reset"), "bad-reset", "reset must be a boolean"))


def _validate_driver(driver: Any, path: str, findings: list[Finding]) -> None:
    if not isinstance(driver, dict):
        findings.append(Finding(path, "bad-driver", "driver must be an object"))
        return
    kind = driver.get("kind")
    if kind not in DRIVER_KINDS:
        findings.append(Finding(_child_path(path, "kind"), "bad-driver-kind", f"must be one of {list(DRIVER_KINDS)}"))
        return
    _check_closed(driver, path, DRIVER_MEMBERS, findings)
    if kind == "controller":
        if driver.get("controller_id") not in CONTROLLER_IDS:
            findings.append(Finding(_child_path(path, "controller_id"), "bad-controller-id", f"must be one of {list(CONTROLLER_IDS)}"))
        revision = driver.get("controller_revision")
        if revision is not None and (not isinstance(revision, str) or not revision):
            findings.append(Finding(_child_path(path, "controller_revision"), "bad-controller-revision", "must be a non-empty revision string or null (null requires an unknowns entry)"))
    else:
        _validate_commands(driver.get("command_schedule"), _child_path(path, "command_schedule"), findings)
    assists = driver.get("assists")
    if assists is not None and assists != "standard":
        findings.append(Finding(_child_path(path, "assists"), "bad-assists", "assists must be 'standard' when present"))


def _validate_participants(participants: Any, path: str, run_id: str, findings: list[Finding]) -> None:
    if participants is None:
        return
    if not isinstance(participants, list):
        findings.append(Finding(path, "bad-participants", "other_participants must be an array when present"))
        return
    if len(participants) > MAX_OTHER_PARTICIPANTS:
        findings.append(Finding(path, "too-many-participants", f"at most {MAX_OTHER_PARTICIPANTS} other participants (eight cars total)"))
    slots: set[str] = set()
    for index, participant in enumerate(participants):
        participant_path = _index_path(path, index)
        if not isinstance(participant, dict):
            findings.append(Finding(participant_path, "bad-participant", "participant must be an object"))
            continue
        _check_closed(participant, participant_path, PARTICIPANT_MEMBERS, findings)
        slot = participant.get("slot")
        if not isinstance(slot, str) or not slot:
            findings.append(Finding(_child_path(participant_path, "slot"), "bad-slot", "must be a non-empty string"))
        elif slot in slots:
            findings.append(Finding(_child_path(participant_path, "slot"), "duplicate-slot", f"slot {slot!r} used twice in run {run_id!r}"))
        else:
            slots.add(slot)
        car_id = participant.get("car_id")
        if not isinstance(car_id, str) or not STABLE_ID_RE.match(car_id):
            findings.append(Finding(_child_path(participant_path, "car_id"), "bad-car-id", "must be a stable semantic ID"))
        pose = participant.get("pose")
        if not isinstance(pose, dict):
            findings.append(Finding(_child_path(participant_path, "pose"), "bad-pose", "pose must be an object"))
        else:
            _check_closed(pose, _child_path(participant_path, "pose"), POSE_MEMBERS, findings)
            position = pose.get("position_m")
            if not isinstance(position, list) or len(position) != 3 or not all(_is_number(v) for v in position):
                findings.append(Finding(_child_path(participant_path, "pose.position_m"), "bad-position", "position_m must be three finite numbers"))
            if not _is_number(pose.get("heading_deg")):
                findings.append(Finding(_child_path(participant_path, "pose.heading_deg"), "bad-heading", "heading_deg must be a finite number"))
        velocity = participant.get("velocity_m_s")
        if velocity is not None and (not _is_number(velocity) or velocity < 0):
            findings.append(Finding(_child_path(participant_path, "velocity_m_s"), "bad-velocity", "velocity_m_s must be a number >= 0 or null (null requires an unknowns entry)"))
        if "driver" in participant:
            _validate_driver(participant["driver"], _child_path(participant_path, "driver"), findings)


def _validate_runs(document: Mapping[str, Any], declared_surfaces: set[str], segment_count: int, findings: list[Finding]) -> list[str]:
    runs = document.get("runs")
    if not isinstance(runs, list) or not runs:
        findings.append(Finding("runs", "no-runs", "runs must be a non-empty array"))
        return []
    run_ids: list[str] = []
    for index, run in enumerate(runs):
        path = _index_path("runs", index)
        if not isinstance(run, dict):
            findings.append(Finding(path, "bad-run", "run must be an object"))
            continue
        _check_closed(run, path, RUN_MEMBERS, findings)
        run_id = run.get("run_id")
        if not isinstance(run_id, str) or not RUN_ID_RE.match(run_id):
            findings.append(Finding(_child_path(path, "run_id"), "bad-run-id", "must match ^[a-z][a-z0-9_]*$"))
        elif run_id in run_ids:
            findings.append(Finding(_child_path(path, "run_id"), "duplicate-run", f"run {run_id!r} declared twice"))
        else:
            run_ids.append(run_id)
        if run.get("role") not in RUN_ROLES:
            findings.append(Finding(_child_path(path, "role"), "bad-role", f"must be one of {list(RUN_ROLES)}"))
        if not isinstance(run.get("description"), str) or not run.get("description"):
            findings.append(Finding(_child_path(path, "description"), "bad-run-description", "must be a non-empty string"))

        initial = run.get("initial_state")
        if not isinstance(initial, dict):
            findings.append(Finding(_child_path(path, "initial_state"), "bad-initial-state", "initial_state must be an object"))
        else:
            _check_closed(initial, _child_path(path, "initial_state"), INITIAL_STATE_MEMBERS, findings)
            start_mode = initial.get("start_mode")
            if start_mode not in START_MODES:
                findings.append(Finding(_child_path(path, "initial_state.start_mode"), "bad-start-mode", f"must be one of {list(START_MODES)}"))
            velocity = initial.get("velocity_m_s")
            if start_mode == "standing":
                if not _is_number(velocity) or velocity != 0:
                    findings.append(Finding(_child_path(path, "initial_state.velocity_m_s"), "standing-start-velocity", "a standing start must declare velocity_m_s 0"))
            elif velocity is not None and (not _is_number(velocity) or velocity <= 0):
                findings.append(Finding(_child_path(path, "initial_state.velocity_m_s"), "bad-velocity", "a rolling start needs velocity_m_s > 0 or null (null requires an unknowns entry)"))
            if not isinstance(initial.get("grounded"), bool):
                findings.append(Finding(_child_path(path, "initial_state.grounded"), "bad-grounded", "grounded must be a boolean"))
            if "heading_deg" in initial and not _is_number(initial["heading_deg"]):
                findings.append(Finding(_child_path(path, "initial_state.heading_deg"), "bad-heading", "heading_deg must be a finite number"))
            position = initial.get("position_m")
            if position is not None and (not isinstance(position, list) or len(position) != 3 or not all(_is_number(v) for v in position)):
                findings.append(Finding(_child_path(path, "initial_state.position_m"), "bad-position", "position_m must be three finite numbers"))

        _validate_participants(run.get("other_participants"), _child_path(path, "other_participants"), run_id or "", findings)

        overrides = run.get("surface_overrides")
        if overrides is not None:
            if not isinstance(overrides, list):
                findings.append(Finding(_child_path(path, "surface_overrides"), "bad-overrides", "surface_overrides must be an array when present"))
            else:
                for override_index, override in enumerate(overrides):
                    override_path = _index_path(_child_path(path, "surface_overrides"), override_index)
                    if not isinstance(override, dict):
                        findings.append(Finding(override_path, "bad-override", "override must be an object"))
                        continue
                    _check_closed(override, override_path, SURFACE_OVERRIDE_MEMBERS, findings)
                    segment_index = override.get("segment_index")
                    if not isinstance(segment_index, int) or isinstance(segment_index, bool) or not (0 <= segment_index < segment_count):
                        findings.append(Finding(_child_path(override_path, "segment_index"), "bad-segment-index", f"must reference a segment in [0, {segment_count})"))
                    surface_id = override.get("surface_id")
                    if not isinstance(surface_id, str) or surface_id not in declared_surfaces:
                        findings.append(Finding(_child_path(override_path, "surface_id"), "unknown-surface", f"surface {surface_id!r} is not declared in surfaces"))

        _validate_driver(run.get("driver"), _child_path(path, "driver"), findings)
    return run_ids


def _validate_timing_gates(document: Mapping[str, Any], segment_count: int, findings: list[Finding]) -> None:
    gates = document.get("timing_gates")
    if not isinstance(gates, list) or len(gates) < 2:
        findings.append(Finding("timing_gates", "too-few-gates", "timing_gates must contain at least a start and a finish gate"))
        return
    segments = document.get("geometry", {}).get("segments", []) if isinstance(document.get("geometry"), dict) else []
    seen: set[str] = set()
    kinds: list[str] = []
    for index, gate in enumerate(gates):
        path = _index_path("timing_gates", index)
        if not isinstance(gate, dict):
            findings.append(Finding(path, "bad-gate", "gate must be an object"))
            continue
        _check_closed(gate, path, TIMING_GATE_MEMBERS, findings)
        gate_id = gate.get("gate_id")
        if not isinstance(gate_id, str) or not gate_id:
            findings.append(Finding(_child_path(path, "gate_id"), "bad-gate-id", "must be a non-empty string"))
        elif gate_id in seen:
            findings.append(Finding(_child_path(path, "gate_id"), "duplicate-gate", f"gate {gate_id!r} declared twice"))
        else:
            seen.add(gate_id)
        kind = gate.get("kind")
        if kind not in GATE_KINDS:
            findings.append(Finding(_child_path(path, "kind"), "bad-gate-kind", f"must be one of {list(GATE_KINDS)}"))
        else:
            kinds.append(kind)
        if not isinstance(gate.get("purpose"), str) or not gate.get("purpose"):
            findings.append(Finding(_child_path(path, "purpose"), "bad-gate-purpose", "must be a non-empty string"))
        segment_index = gate.get("segment_index")
        if not isinstance(segment_index, int) or isinstance(segment_index, bool) or not (0 <= segment_index < segment_count):
            findings.append(Finding(_child_path(path, "segment_index"), "bad-segment-index", f"must reference a segment in [0, {segment_count})"))
            continue
        arc_length = gate.get("arc_length_m")
        if not _is_number(arc_length) or arc_length < 0:
            findings.append(Finding(_child_path(path, "arc_length_m"), "bad-arc-length", "must be a number >= 0"))
            continue
        segment = segments[segment_index] if isinstance(segments[segment_index], dict) else None
        length = _segment_length_m(segment) if segment else None
        if length is not None and arc_length > length + GATE_LENGTH_TOLERANCE_M:
            findings.append(
                Finding(
                    _child_path(path, "arc_length_m"),
                    "gate-beyond-segment",
                    f"gate at {arc_length} m is past the {length:.4f} m segment length",
                )
            )
    if kinds.count("start") != 1:
        findings.append(Finding("timing_gates", "gate-start-count", f"exactly one start gate is required (found {kinds.count('start')})"))
    if kinds.count("finish") != 1:
        findings.append(Finding("timing_gates", "gate-finish-count", f"exactly one finish gate is required (found {kinds.count('finish')})"))


def _validate_expected_events(document: Mapping[str, Any], run_ids: Sequence[str], findings: list[Finding]) -> None:
    events = document.get("expected_events")
    if not isinstance(events, list) or not events:
        findings.append(Finding("expected_events", "no-events", "expected_events must be a non-empty array"))
        return
    for index, event in enumerate(events):
        path = _index_path("expected_events", index)
        if not isinstance(event, dict):
            findings.append(Finding(path, "bad-event", "expected event must be an object"))
            continue
        _check_closed(event, path, EXPECTED_EVENT_MEMBERS, findings)
        if event.get("event") not in EVENT_TYPES:
            findings.append(Finding(_child_path(path, "event"), "bad-event-type", "unknown expected event"))
        if not isinstance(event.get("required"), bool):
            findings.append(Finding(_child_path(path, "required"), "bad-required", "required must be a boolean"))
        applies = event.get("applies_to_runs")
        if applies is not None:
            if not isinstance(applies, list) or not applies:
                findings.append(Finding(_child_path(path, "applies_to_runs"), "bad-applies", "applies_to_runs must be a non-empty array when present"))
            else:
                for run_id in applies:
                    if run_id not in run_ids:
                        findings.append(Finding(_child_path(path, "applies_to_runs"), "unknown-run-reference", f"run {run_id!r} is not declared in runs"))


def _validate_metrics(metrics: Any, path: str, findings: list[Finding]) -> None:
    if not isinstance(metrics, list) or not metrics:
        findings.append(Finding(path, "no-metrics", "comparison.metrics must be a non-empty array"))
        return
    for index, metric in enumerate(metrics):
        metric_path = _index_path(path, index)
        if not isinstance(metric, dict):
            findings.append(Finding(metric_path, "bad-metric", "metric must be an object"))
            continue
        _check_closed(metric, metric_path, METRIC_MEMBERS, findings)
        name = metric.get("name")
        if not isinstance(name, str) or not name:
            findings.append(Finding(_child_path(metric_path, "name"), "bad-metric-name", "must be a non-empty string"))
        if not isinstance(metric.get("description"), str) or not metric.get("description"):
            findings.append(Finding(_child_path(metric_path, "description"), "bad-metric-description", "must be a non-empty string"))
        comparator = metric.get("comparator")
        if comparator not in COMPARATORS:
            findings.append(Finding(_child_path(metric_path, "comparator"), "bad-comparator", f"must be one of {list(COMPARATORS)}"))
            continue
        status = metric.get("status")
        if status not in METRIC_STATUSES:
            if status == "measured":
                findings.append(
                    Finding(
                        _child_path(metric_path, "status"),
                        "measured-status-in-fixture",
                        "fixtures carry documented targets and reporting requirements, never measured values; measured references are M1/M4 reference-run records",
                    )
                )
            else:
                findings.append(Finding(_child_path(metric_path, "status"), "bad-metric-status", f"must be one of {list(METRIC_STATUSES)}"))
        value = metric.get("value")
        value_min = metric.get("value_min")
        value_max = metric.get("value_max")
        if comparator in THRESHOLD_COMPARATORS:
            if not _is_number(value):
                findings.append(Finding(_child_path(metric_path, "value"), "missing-metric-value", f"comparator {comparator!r} requires a numeric value"))
            if value_min is not None or value_max is not None:
                findings.append(Finding(_child_path(metric_path, "value_min"), "unexpected-metric-bound", "threshold comparators use value, not value_min/value_max"))
        elif comparator in RANGE_COMPARATORS:
            if not _is_number(value_min) or not _is_number(value_max):
                findings.append(Finding(metric_path, "missing-metric-range", f"comparator {comparator!r} requires numeric value_min and value_max"))
            elif value_min >= value_max:
                findings.append(Finding(metric_path, "inverted-metric-range", "value_min must be smaller than value_max"))
            if value is not None:
                findings.append(Finding(_child_path(metric_path, "value"), "unexpected-metric-value", "range comparators use value_min/value_max, not value"))
        else:  # report
            if value is not None or value_min is not None or value_max is not None:
                findings.append(Finding(metric_path, "report-metric-with-threshold", "comparator 'report' records without declaring a pass/fail threshold; remove value/value_min/value_max"))
        if "unit" in metric and metric["unit"] is not None and not isinstance(metric["unit"], str):
            findings.append(Finding(_child_path(metric_path, "unit"), "bad-metric-unit", "unit must be a string or null"))


def _validate_comparison(document: Mapping[str, Any], findings: list[Finding]) -> None:
    comparison = document.get("comparison")
    if not isinstance(comparison, dict):
        findings.append(Finding("comparison", "bad-comparison", "comparison must be an object"))
        return
    _check_closed(comparison, "comparison", COMPARISON_MEMBERS, findings)
    if not isinstance(comparison.get("purpose"), str) or not comparison.get("purpose"):
        findings.append(Finding("comparison.purpose", "bad-purpose", "must be a non-empty string"))
    paired = comparison.get("paired_runs_required")
    if not isinstance(paired, int) or isinstance(paired, bool) or paired < 1:
        findings.append(Finding("comparison.paired_runs_required", "bad-paired-runs", "must be an integer >= 1"))
    elif document.get("fixture_family") in CORNER_FAMILIES and paired < MIN_PAIRED_RUNS:
        findings.append(
            Finding(
                "comparison.paired_runs_required",
                "few-paired-runs",
                f"BENCHMARKS asks for at least {MIN_PAIRED_RUNS} clean paired runs per relevant corner fixture (got {paired})",
                is_error=False,
            )
        )
    _validate_metrics(comparison.get("metrics"), "comparison.metrics", findings)


def _validate_cars(document: Mapping[str, Any], findings: list[Finding]) -> None:
    cars = document.get("cars")
    if not isinstance(cars, dict):
        findings.append(Finding("cars", "bad-cars", "cars must be an object"))
        return
    _check_closed(cars, "cars", CAR_SET_MEMBERS, findings)
    handling_revision = cars.get("handling_revision")
    if handling_revision is not None and (not isinstance(handling_revision, str) or not handling_revision):
        findings.append(Finding("cars.handling_revision", "bad-handling-revision", "must be a non-empty revision string or null (null requires an unknowns entry)"))
    car_ids = cars.get("car_ids")
    if not isinstance(car_ids, list) or not car_ids:
        findings.append(Finding("cars.car_ids", "no-car-ids", "car_ids must be a non-empty array"))
    else:
        for index, car_id in enumerate(car_ids):
            if not isinstance(car_id, str) or not STABLE_ID_RE.match(car_id):
                findings.append(Finding(_index_path("cars.car_ids", index), "bad-car-id", "must be a stable semantic ID"))
    loadouts = cars.get("loadouts")
    if not isinstance(loadouts, list) or not loadouts:
        findings.append(Finding("cars.loadouts", "no-loadouts", "loadouts must be a non-empty array"))
    else:
        seen: set[str] = set()
        for index, loadout in enumerate(loadouts):
            if loadout not in LOADOUTS:
                findings.append(Finding(_index_path("cars.loadouts", index), "bad-loadout", f"must be one of {list(LOADOUTS)}"))
            elif loadout in seen:
                findings.append(Finding(_index_path("cars.loadouts", index), "duplicate-loadout", f"loadout {loadout!r} listed twice"))
            else:
                seen.add(loadout)


def _validate_unknowns(document: Mapping[str, Any], findings: list[Finding]) -> None:
    unknowns = document.get("unknowns")
    if not isinstance(unknowns, list):
        findings.append(Finding("unknowns", "bad-unknowns", "unknowns must be an array"))
        return
    paths: list[str] = []
    for index, unknown in enumerate(unknowns):
        path = _index_path("unknowns", index)
        if not isinstance(unknown, dict):
            findings.append(Finding(path, "bad-unknown", "unknown entry must be an object"))
            continue
        _check_closed(unknown, path, UNKNOWN_ENTRY_MEMBERS, findings)
        unknown_path = unknown.get("path")
        if not isinstance(unknown_path, str) or not UNKNOWN_PATH_RE.match(unknown_path):
            findings.append(Finding(_child_path(path, "path"), "bad-unknown-path", "path must be a dotted path with optional [index] segments"))
        else:
            paths.append(unknown_path)
        if not isinstance(unknown.get("reason"), str) or not unknown.get("reason"):
            findings.append(Finding(_child_path(path, "reason"), "bad-unknown-reason", "reason must be a non-empty string"))
        if "blocking" in unknown and not isinstance(unknown["blocking"], bool):
            findings.append(Finding(_child_path(path, "blocking"), "bad-unknown-blocking", "blocking must be a boolean"))
        if "until" in unknown and unknown["until"] is not None and not isinstance(unknown["until"], str):
            findings.append(Finding(_child_path(path, "until"), "bad-unknown-until", "until must be a string or null"))
    duplicates = {item for item in paths if paths.count(item) > 1}
    for item in sorted(duplicates):
        findings.append(Finding("unknowns", "duplicate-unknown", f"unknown path {item!r} is listed more than once", is_error=False))

    # The honesty rule, reverse direction: every unknowns entry must resolve
    # to a member of this document. An entry that resolves to nothing (a typo,
    # or a section that was never authored) is rejected, so the pairing cannot
    # silently rot; an absent section is declared as an explicit null with an
    # entry rather than pointed at from nowhere. An entry may also mark an
    # unfixed authored value, such as provisional car IDs, per
    # schemas/common.schema.json (unknown_entry: "the unfixed value or absent
    # section"); resolving to a determined value is therefore accepted.
    for candidate in paths:
        _, found = _resolve_unknown_path(document, candidate)
        if not found:
            findings.append(
                Finding(
                    "unknowns",
                    "unresolved-unknown",
                    f"unknown path {candidate!r} does not resolve to any member of this document; declare the section as an explicit null or fix the path",
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
                    "null value must be listed in unknowns with a reason; do not leave an undetermined value unexplained or pretend it is determined",
                )
            )


def _validate_provenance(document: Mapping[str, Any], findings: list[Finding]) -> None:
    provenance = document.get("provenance")
    if not isinstance(provenance, dict):
        findings.append(Finding("provenance", "bad-provenance", "provenance must be an object"))
        return
    for key in provenance:
        if key not in PROVENANCE_FIELDS:
            findings.append(Finding(_child_path("provenance", key), "unknown-provenance-field", "not a provenance member of schemas/common.schema.json", is_error=False))
    for key in PROVENANCE_FIELDS:
        value = provenance.get(key)
        if value is not None and not isinstance(value, str):
            findings.append(Finding(_child_path("provenance", key), "bad-provenance-field", "must be a string or null"))


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


# ---------------------------------------------------------------------------
# Document-level validation
# ---------------------------------------------------------------------------


def _validate_draft_expectations(document: Mapping[str, Any], findings: list[Finding]) -> None:
    """Draft fixtures must not expect wake eligibility outside the documented window.

    GAME_DESIGN "Drafting" places the wake benefit within approximately 5-20 m
    and a narrow forward cone, and BENCHMARKS brackets that window with 4 m and
    21 m initial gaps. A fixture that requires drafting_eligible at a gap
    outside its own declared window contradicts the documented contract, so the
    eligibility expectations are correlated with the authored run geometry
    here. Only required-true expectations are checked: a run that must NOT
    become eligible makes no claim that geometry can contradict.
    """
    if document.get("fixture_family") != "draft":
        return
    comparison = document.get("comparison")
    metrics = comparison.get("metrics") if isinstance(comparison, dict) else None
    declared_window: tuple[float, float] | None = None
    if isinstance(metrics, list):
        for metric in metrics:
            if isinstance(metric, dict) and metric.get("name") == WAKE_WINDOW_METRIC_NAME:
                low, high = metric.get("value_min"), metric.get("value_max")
                if _is_number(low) and _is_number(high):
                    declared_window = (float(low), float(high))
    if declared_window is None:
        findings.append(
            Finding(
                "comparison.metrics",
                "wake-window-metric-missing",
                f"a draft fixture declares its wake window as a range metric named {WAKE_WINDOW_METRIC_NAME!r}",
                is_error=False,
            )
        )
    elif declared_window != WAKE_WINDOW_M:
        findings.append(
            Finding(
                "comparison.metrics",
                "wake-window-mismatch",
                f"fixture declares a {declared_window[0]:g}-{declared_window[1]:g} m wake window but GAME_DESIGN documents approximately 5-20 m",
            )
        )
    events = document.get("expected_events")
    runs = document.get("runs")
    if not isinstance(events, list) or not isinstance(runs, list):
        return
    run_by_id: dict[str, Mapping[str, Any]] = {}
    for run in runs:
        if isinstance(run, dict) and isinstance(run.get("run_id"), str):
            run_by_id[run["run_id"]] = run
    low, high = WAKE_WINDOW_M
    for index, event in enumerate(events):
        if not isinstance(event, dict) or event.get("event") != "drafting_eligible":
            continue
        if event.get("required") is not True:
            continue
        applies = event.get("applies_to_runs")
        targets = applies if isinstance(applies, list) and applies else list(run_by_id)
        for run_id in targets:
            run = run_by_id.get(run_id)
            if run is None:
                continue  # already reported by _validate_expected_events
            geometry = _run_wake_geometry(run)
            if geometry is None:
                continue
            gap, lateral = geometry
            event_path = _index_path("expected_events", index)
            if gap < low - GAP_TOLERANCE_M or gap > high + GAP_TOLERANCE_M:
                findings.append(
                    Finding(
                        event_path,
                        "draft-eligible-outside-window",
                        f"run {run_id!r} requires drafting_eligible at a {gap:g} m gap, outside the documented {low:g}-{high:g} m wake window",
                    )
                )
                continue
            if gap > 0:
                cone_angle = math.degrees(math.atan2(lateral, gap))
                if lateral > WAKE_LATERAL_LIMIT_M + GAP_TOLERANCE_M or cone_angle > WAKE_CONE_HALF_ANGLE_DEG + GAP_TOLERANCE_M:
                    findings.append(
                        Finding(
                            event_path,
                            "draft-eligible-outside-cone",
                            f"run {run_id!r} requires drafting_eligible with {lateral:g} m lateral separation ({cone_angle:g} degrees), outside the documented +/-10 degree cone and 1.5 m lateral limit",
                        )
                    )


def validate_fixture(path: Path) -> list[Finding]:
    """Validate one fixture file and return findings (empty list = valid)."""
    document, findings = load_json_document(path)
    if document is None:
        return findings

    for field in REQUIRED_TOP_LEVEL:
        if field not in document:
            findings.append(Finding(field, "missing-field", "required member is absent"))

    schema_version = document.get("schema_version")
    if schema_version != FIXTURE_SCHEMA_VERSION:
        findings.append(
            Finding(
                "schema_version",
                "bad-schema-version",
                f"must be {FIXTURE_SCHEMA_VERSION!r} (got {schema_version!r}); a different contract revision is rejected, not silently migrated",
            )
        )

    fixture_id = document.get("fixture_id")
    if not isinstance(fixture_id, str) or not FIXTURE_ID_RE.match(fixture_id):
        findings.append(Finding("fixture_id", "bad-fixture-id", "must match ^fixture\\.handling\\.[a-z][a-z0-9_]*$"))
    elif path is not None and fixture_id.rsplit(".", 1)[-1] != path.stem:
        findings.append(
            Finding(
                "fixture_id",
                "id-filename-mismatch",
                f"fixture_id {fixture_id!r} does not match file name {path.name!r}",
                is_error=False,
            )
        )

    if document.get("fixture_family") not in FIXTURE_FAMILIES:
        findings.append(Finding("fixture_family", "bad-family", f"must be one of {list(FIXTURE_FAMILIES)}"))

    for field in ("title", "description"):
        value = document.get(field)
        if not isinstance(value, str) or not value:
            findings.append(Finding(field, "bad-text", f"{field} must be a non-empty string"))

    revision = document.get("revision")
    if not isinstance(revision, str) or not REVISION_RE.match(revision):
        findings.append(Finding("revision", "bad-revision", "revision must be a dotted numeric revision such as '1.0.0'"))

    status = document.get("status")
    if status not in FIXTURE_STATUSES:
        findings.append(Finding("status", "bad-status", f"must be one of {list(FIXTURE_STATUSES)}"))
    elif status == "measured":
        findings.append(
            Finding(
                "status",
                "measured-status-in-fixture",
                "a fixture file must not claim measured status; measured outcomes belong to M1/M4 reference-run records",
            )
        )

    _validate_units(document, findings)
    _validate_coordinate_frame(document, findings)

    declared_surfaces = _validate_surfaces(document, findings)
    segment_count = _validate_geometry(document, findings)
    _validate_barriers(document, segment_count, findings)
    _validate_features(document, segment_count, findings)
    run_ids = _validate_runs(document, declared_surfaces, segment_count, findings)
    _validate_timing_gates(document, segment_count, findings)
    _validate_expected_events(document, run_ids, findings)
    _validate_comparison(document, findings)
    _validate_cars(document, findings)
    _validate_unknowns(document, findings)
    _validate_provenance(document, findings)
    _validate_content_hash(document, findings)
    _check_closed(document, "", TOP_LEVEL_MEMBERS, findings)
    _validate_draft_expectations(document, findings)
    return findings


def validate_fixture_directory(directory: Path) -> list[Finding]:
    """Validate every *.json fixture in a directory (sorted by name)."""
    findings: list[Finding] = []
    for path in sorted(directory.glob("*.json")):
        findings.extend(validate_fixture(path))
    return findings


def validate_schema_document(path: Path) -> list[Finding]:
    """Check the contract document itself parses and declares the right revision."""
    document, findings = load_json_document(path)
    if document is None:
        return findings
    if not isinstance(document.get("title"), str) or not document["title"]:
        findings.append(Finding("title", "bad-title", "schema document must have a non-empty title"))
    declared = document.get("schema_version")
    if declared != FIXTURE_SCHEMA_VERSION:
        findings.append(
            Finding(
                "schema_version",
                "schema-revision-mismatch",
                f"schema document declares {declared!r} but this validator implements {FIXTURE_SCHEMA_VERSION!r}",
            )
        )
    for field in ("type", "required", "properties", "$defs"):
        if field not in document:
            findings.append(Finding(field, "missing-field", f"schema document is missing {field!r}"))
    return findings


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------


def _default_root() -> Path:
    # schemas/handling/validate_fixtures.py -> repository root
    return Path(__file__).resolve().parents[2]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate Roadstorm handling benchmark fixtures against schemas/handling/handling_fixture.schema.json.",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="fixture files or directories (default: fixtures/handling under the repository root)",
    )
    parser.add_argument("--root", type=Path, default=None, help="repository root (default: inferred from this script)")
    args = parser.parse_args(argv)

    root = args.root.resolve() if args.root else _default_root()
    if not root.is_dir():
        print(f"error: root {root} is not a directory", file=sys.stderr)
        return 2

    schema_path = root / "schemas" / "handling" / SCHEMA_DOCUMENT_NAME
    targets = args.paths or [root / "fixtures" / "handling"]

    findings: list[Finding] = []
    checked = 0
    for target in targets:
        resolved = target if target.is_absolute() else root / target
        if resolved.is_dir():
            files = sorted(resolved.glob("*.json"))
            if not files:
                print(f"error: no fixture files in {resolved}", file=sys.stderr)
                return 2
            for path in files:
                findings.extend(validate_fixture(path))
                checked += 1
        elif resolved.is_file():
            findings.extend(validate_fixture(resolved))
            checked += 1
        else:
            print(f"error: {resolved} is not a readable file or directory", file=sys.stderr)
            return 2

    if schema_path.is_file():
        findings.extend(validate_schema_document(schema_path))

    errors = [finding for finding in findings if finding.is_error]
    warnings = [finding for finding in findings if not finding.is_error]
    for finding in findings:
        print(finding)
    print(f"checked {checked} fixture file(s) plus the schema document: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
