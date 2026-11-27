#!/usr/bin/env python3
"""Roadstorm scenario/reference contract validator.

Ownership: fixtures/scenario/** together with schemas/scenario/** (PLAN.md
M0.9, job 847d8664-1028-4233-a67c-39f1465b4964).

This module is the executable form of the three text contracts in
``schemas/scenario/``:

* ``scenario.schema.json`` - the versioned scenario configuration contract
  (course and dependency revisions, participants and drivers, initial state,
  capture/comparison protocol, seeds, required telemetry) from
  docs/BENCHMARKS.md and docs/TECHNICAL_DESIGN.md;
* ``reference_run.schema.json`` - the versioned benchmark reference record
  contract (the measured-evidence half: capture protocol, retained lap
  statistics, sector splits, speed samples, hashes, derived medal
  thresholds) from docs/BENCHMARKS.md 'Reference driver and records';
* ``scenario_fixture.schema.json`` - the fixture wrapper that bundles one
  scenario with the reference records it depends on.

It does three jobs a plain JSON syntax check cannot:

1. Validates every ``fixtures/scenario/positive/*.json`` fixture against the
   fixture schema (which pulls in the scenario and record schemas by
   ``$ref``) with a small standard-library JSON Schema evaluator - no
   third-party packages, no installs, no network.
2. Runs the semantic checks that make the contract meaningful rather than
   merely well-formed: fixture/scenario family agreement, the tactical
   window protocol (2 s warm-up, 3 s window), the per-family required
   telemetry, reference linkage (match by car, loadout, assists, course and
   reference revision), the evidence-status honesty rule (a fixture may only
   carry planned records, and a planned record may carry no results), the
   clean-lap accounting and medal arithmetic a measured record must satisfy,
   rejection-criteria completeness, dependency completeness, the retained
   evidence a measured record must keep (speed samples, car/loadout/assist/
   track/handling hashes, per-clean-lap sector splits), the initial-state
   agreement rules (per-participant slots, matched-state coverage and scalar
   agreement, history source, command-schedule completeness), the comparison
   structure (one evaluated slot plus alternative producer arms that are
   separate runs, never simultaneous cars), comparison-arm producer identity
   and style coherence, the fixed context car a tactical family requires,
   participant-slot and record-id uniqueness, the reference-capture subject
   and traffic-free shape, participant-pose distinctness inside one execution,
   the driver-revision pinning rule for cloning-only
   producers, the metric vocabulary and shape (comparator/value/bounds),
   the null/unknowns pairing rule in both directions, and the canonical
   content hash.
3. Runs every ``fixtures/scenario/negative/*.json`` fixture and requires it
   to fail with exactly the failure set declared in its ``.expected.json``
   sidecar, so each documented rejection stays rejected.

Constants (60 Hz, 2 s warm-up, 3 s window, 0.10 m / 0.10 m/s handover, five
clean laps, medal factors 1.25/1.12/1.05, the five rejection criteria, the
per-family telemetry minimums) are read from the schemas' ``$defs.constants``
instead of being restated here, so the schemas are the single source of
truth.

Deliberate limitations, mirroring fixtures/intent/validate_intent_contract.py:

* Standard library only, standalone. It does not run Godot, execute a
  scenario, capture a lap, or measure anything; fixtures carry authored
  targets, never measurements.
* It cannot make unknown facts known. Unratified revisions and unmeasured
  results stay null with an unknowns entry; the validator enforces the
  pairing, never fills values in.
* It validates fixture documents, not a runtime implementation. A green run
  means the contract and its fixtures agree, not that any benchmark has been
  run. No fixture contains a lap time, a median, a contact rate or any other
  measured value.
* It implements the contract's rules in Python rather than evaluating the
  full JSON Schema semantics; the schema files remain the text contracts of
  record. No ``jsonschema`` dependency is introduced.
* The validator treats every non-capture family as a tactical family for the
  window-protocol and telemetry checks; a capture-flavored 'regression'
  fixture would need that check extended.

Usage::

    python3 validate_scenario_contract.py                 # validate everything
    python3 validate_scenario_contract.py --update-hashes  # (re)write content_hash
    python3 validate_scenario_contract.py --schemas DIR --positive DIR --negative DIR

Exit codes: 0 = all fixtures valid and all negative fixtures rejected as
expected; 1 = validation failures; 2 = a file could not be read/parsed or the
command line was wrong.

Original project code under the Unlicense.
"""

from __future__ import annotations

import argparse
import dataclasses
import hashlib
import json
import re
import sys
from pathlib import Path
from statistics import median as _median
from typing import Any, Iterator, Mapping, Sequence

# ---------------------------------------------------------------------------
# Contract constants
# ---------------------------------------------------------------------------

SCENARIO_SCHEMA_NAME = "scenario.schema.json"
REFERENCE_SCHEMA_NAME = "reference_run.schema.json"
FIXTURE_SCHEMA_NAME = "scenario_fixture.schema.json"

# Semantic checks implemented here; scenario_fixture.schema.json's expectation
# enum must stay equal to this set.
IMPLEMENTED_CHECKS = frozenset(
    {
        "family_agreement",
        "reference_linkage",
        "evidence_status",
        "clean_lap_accounting",
        "medal_threshold_arithmetic",
        "rejection_criteria_complete",
        "dependency_completeness",
        "measured_evidence_completeness",
        "window_protocol",
        "telemetry_required",
        "initial_state_agreement",
        "comparison_arms",
        "comparison_arm_identity",
        "tactical_context_required",
        "participant_slot_uniqueness",
        "participant_pose_distinctness",
        "driver_revision_pinning",
        "reference_capture_structure",
        "reference_record_id_uniqueness",
        "null_unknown_pairing",
        "content_hash",
        "metric_status_honesty",
        "metric_shape",
    }
)

CAPTURE_FAMILY = "reference_lap_capture"

# The six BENCHMARKS 'Tactical comparison' families. Each compares producers
# from matched initial states and histories, so each carries a comparison
# structure; 'regression' is reserved for later single-concern fixtures and
# is not forced into that shape here.
TACTICAL_COMPARISON_FAMILIES = frozenset(
    {
        "slower_lead_straight_pass",
        "open_two_lane_corner_entry",
        "narrow_section_patience",
        "legal_defended_line_cutback",
        "multi_car_merge",
        "noisy_human_proxy",
    }
)

EVALUATED_ROLE = "evaluated"
REFERENCE_SUBJECT_ROLE = "reference_subject"
CALIBRATION_DRIVER_KIND = "calibration_driver"

# The producers BENCHMARKS 'Tactical comparison' compares. A comparison arm
# is a run of one of these; human_proxy and scripted drivers are fixed context
# participants (the noisy_human_proxy family), never compared producers.
PRODUCER_ARM_KINDS = frozenset(
    {"classic_planner", "cloning_only_policy", "learned_policy"}
)

# The explicit style input each producer kind requires: Classic and
# cloning-only use the Classic 0/0 pair ('none'); a Roadstormer is one of the
# two learned styles. Absent means the arm does not say which producer ran.
ARM_STYLE_RULES = {
    "classic_planner": frozenset({"none"}),
    "cloning_only_policy": frozenset({"none"}),
    "learned_policy": frozenset({"surge", "switch"}),
}

# The initial-state members that locate a participant on the road. Two
# simultaneous participants of one execution must not declare the same values
# for all of them.
POSE_MEMBERS = ("forward_gap_m", "lateral_offset_m", "speed_m_s", "heading_offset_deg")

# Metric vocabulary, mirroring schemas/handling/validate_fixtures.py so the
# scenario and handling contracts check comparison metrics identically.
COMPARATORS = ("eq", "lte", "gte", "lt", "gt", "range", "ratio_range", "report")
THRESHOLD_COMPARATORS = ("eq", "lte", "gte", "lt", "gt")
RANGE_COMPARATORS = ("range", "ratio_range")
# A fixture carries documented targets and reporting requirements only.
METRIC_STATUSES = ("documented_initial_target", "undecided")

CONTENT_HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

TOLERANCE = 1e-9

# Sentinel for "this dotted path does not exist" (distinct from JSON null).
MISSING = object()


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class Failure:
    """One validation finding.

    ``code`` is the JSON Schema keyword for schema failures, ``"semantic"``
    for contract checks (with ``check`` naming the check), or an I/O code.
    ``path`` is the dotted path inside the fixture document.
    """

    code: str
    path: str
    message: str
    check: str | None = None

    def key(self) -> tuple[str, str, str | None]:
        return (self.code, self.path, self.check)


# ---------------------------------------------------------------------------
# Document loading
# ---------------------------------------------------------------------------


class DocumentError(Exception):
    """The bytes on disk are not a usable JSON record."""


def _reject_duplicate_members(pairs: Sequence[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DocumentError(f"duplicate JSON member {key!r}")
        result[key] = value
    return result


def load_json(path: Path) -> Any:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise DocumentError(f"cannot read {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        raise DocumentError(f"{path} is not valid UTF-8: {exc}") from exc
    try:
        return json.loads(text, object_pairs_hook=_reject_duplicate_members)
    except json.JSONDecodeError as exc:
        raise DocumentError(f"{path} is not valid JSON: {exc}") from exc
    except DocumentError as exc:
        raise DocumentError(f"{path}: {exc}") from exc


def canonical_hash(document: Mapping[str, Any]) -> str:
    """SHA-256 over canonical JSON with the content_hash member removed.

    Canonical form per schemas/common.schema.json ($defs.content_hash):
    sorted keys, compact separators, UTF-8.
    """
    body = {key: value for key, value in document.items() if key != "content_hash"}
    canonical = json.dumps(body, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def iter_null_paths(value: Any, prefix: str = "") -> Iterator[str]:
    """Yield the dotted path of every JSON null in ``value``.

    Array members are addressed by index, e.g.
    ``reference_records.0.results.statistics.median_s``.
    """
    if value is None:
        yield prefix
        return
    if isinstance(value, Mapping):
        for key, child in value.items():
            child_prefix = f"{prefix}.{key}" if prefix else str(key)
            yield from iter_null_paths(child, child_prefix)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from iter_null_paths(child, f"{prefix}.{index}")


def resolve_dotted(document: Any, path: str) -> Any:
    """Resolve a dotted path; return MISSING when it does not exist.

    A path that exists and holds JSON null returns None, which is how the
    null/unknowns pairing rule distinguishes the two cases.
    """
    node = document
    for token in path.split("."):
        if isinstance(node, Mapping) and token in node:
            node = node[token]
        elif isinstance(node, list) and token.isdigit() and int(token) < len(node):
            node = node[int(token)]
        else:
            return MISSING
    return node


# ---------------------------------------------------------------------------
# Minimal JSON Schema evaluator (draft 2020-12 subset)
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class DocumentContext:
    """The document a schema node lives in, for resolving its $ref strings."""

    root: Mapping[str, Any]
    base_dir: Path


class SchemaCache:
    def __init__(self) -> None:
        self.documents: dict[Path, Mapping[str, Any]] = {}
        self.patterns: dict[str, re.Pattern[str]] = {}

    def document(self, path: Path) -> Mapping[str, Any]:
        resolved = path.resolve()
        if resolved not in self.documents:
            self.documents[resolved] = load_json(resolved)
        return self.documents[resolved]

    def pattern(self, expression: str) -> re.Pattern[str]:
        if expression not in self.patterns:
            self.patterns[expression] = re.compile(expression)
        return self.patterns[expression]


def _json_type(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "unknown"


def _is_number(value: Any) -> bool:
    """True for a JSON number; JSON booleans are not numbers."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _matches_type(value: Any, expected: str) -> bool:
    actual = _json_type(value)
    if expected == "number":
        return actual in ("integer", "number")
    return actual == expected


def _json_equal(left: Any, right: Any) -> bool:
    # bool is a subclass of int in Python; JSON treats true != 1.
    if isinstance(left, bool) != isinstance(right, bool):
        return False
    return bool(left == right)


def resolve_ref(ref: str, context: DocumentContext, cache: SchemaCache):
    if ref.startswith("#"):
        pointer = ref[1:]
        new_context = context
        document = context.root
    else:
        file_part, _, pointer = ref.partition("#")
        target = (context.base_dir / file_part).resolve()
        document = cache.document(target)
        new_context = DocumentContext(root=document, base_dir=target.parent)
    node: Any = document
    for token in pointer.split("/"):
        if not token:
            continue
        token = token.replace("~1", "/").replace("~0", "~")
        if not isinstance(node, Mapping) or token not in node:
            raise DocumentError(f"unresolvable $ref {ref!r} (missing {token!r})")
        node = node[token]
    return node, new_context


def validate_node(
    schema: Any,
    instance: Any,
    path: str,
    context: DocumentContext,
    failures: list[Failure],
    cache: SchemaCache,
) -> None:
    """Validate ``instance`` against ``schema``; append findings to ``failures``.

    Supported keywords: $ref, type, const, enum, required,
    additionalProperties, properties, items, minItems, maxItems, minimum,
    maximum, exclusiveMinimum, pattern, minLength. Annotation keywords
    (title, description, examples, default, $schema, $defs, $comment) are
    ignored.
    """
    if isinstance(schema, bool):
        if not schema:
            failures.append(Failure("false-schema", path, "schema is false; nothing validates"))
        return
    if not isinstance(schema, Mapping):
        raise DocumentError(f"schema node at {path!r} is not an object")

    if "$ref" in schema:
        try:
            target, new_context = resolve_ref(str(schema["$ref"]), context, cache)
        except DocumentError as exc:
            failures.append(Failure("ref", path, str(exc)))
            return
        validate_node(target, instance, path, new_context, failures, cache)
        return

    if "type" in schema:
        expected = schema["type"]
        allowed = expected if isinstance(expected, list) else [expected]
        if not any(_matches_type(instance, item) for item in allowed):
            failures.append(
                Failure(
                    "type",
                    path,
                    f"expected type {expected}, found {_json_type(instance)}",
                )
            )
            return

    if "const" in schema and not _json_equal(instance, schema["const"]):
        failures.append(
            Failure("const", path, f"must be {schema['const']!r}, found {instance!r}")
        )

    if "enum" in schema:
        options = schema["enum"]
        if not any(_json_equal(instance, option) for option in options):
            failures.append(
                Failure("enum", path, f"must be one of {options!r}, found {instance!r}")
            )

    if isinstance(instance, Mapping):
        properties = schema.get("properties", {})
        for member in schema.get("required", []):
            if member not in instance:
                failures.append(
                    Failure("required", f"{path}.{member}" if path else member,
                            f"missing required member {member!r}")
                )
        if schema.get("additionalProperties") is False:
            for key in instance:
                if key not in properties:
                    failures.append(
                        Failure(
                            "additionalProperties",
                            f"{path}.{key}" if path else key,
                            f"member {key!r} is not allowed",
                        )
                    )
        for key, subschema in properties.items():
            if key in instance:
                child = f"{path}.{key}" if path else key
                validate_node(subschema, instance[key], child, context, failures, cache)

    if isinstance(instance, list):
        item_schema = schema.get("items")
        if item_schema is not None:
            for index, element in enumerate(instance):
                validate_node(
                    item_schema, element, f"{path}.{index}", context, failures, cache
                )
        if "minItems" in schema and len(instance) < schema["minItems"]:
            failures.append(
                Failure("minItems", path, f"needs at least {schema['minItems']} items")
            )
        if "maxItems" in schema and len(instance) > schema["maxItems"]:
            failures.append(
                Failure("maxItems", path, f"needs at most {schema['maxItems']} items")
            )

    if isinstance(instance, str):
        if "minLength" in schema and len(instance) < schema["minLength"]:
            failures.append(
                Failure("minLength", path, f"shorter than {schema['minLength']} characters")
            )
        if "pattern" in schema and not cache.pattern(schema["pattern"]).search(instance):
            failures.append(
                Failure("pattern", path, f"does not match {schema['pattern']!r}")
            )

    if isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if "minimum" in schema and instance < schema["minimum"]:
            failures.append(Failure("minimum", path, f"below minimum {schema['minimum']}"))
        if "maximum" in schema and instance > schema["maximum"]:
            failures.append(Failure("maximum", path, f"above maximum {schema['maximum']}"))
        if "exclusiveMinimum" in schema and instance <= schema["exclusiveMinimum"]:
            failures.append(
                Failure(
                    "exclusiveMinimum",
                    path,
                    f"not above exclusive minimum {schema['exclusiveMinimum']}",
                )
            )


# ---------------------------------------------------------------------------
# Contract constants, read from the schemas
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class ContractConstants:
    tick_rate_hz: int
    history_warmup_s: float
    opportunity_window_s: float
    handover_max_position_m: float
    handover_max_speed_m_s: float
    required_telemetry_by_family: Mapping[str, tuple[str, ...]]
    required_clean_laps: int
    sector_count: int
    medal_multipliers: Mapping[str, float]
    rejection_criteria: tuple[str, ...]
    arcade_rush_factors: Mapping[str, float]


def load_constants(
    scenario_schema: Mapping[str, Any], reference_schema: Mapping[str, Any]
) -> ContractConstants:
    scenario_props = scenario_schema["$defs"]["constants"]["properties"]
    reference_props = reference_schema["$defs"]["constants"]["properties"]
    telemetry = {
        family: tuple(entry["const"])
        for family, entry in scenario_props["required_telemetry_by_family"]["properties"].items()
    }
    multipliers = {
        name: float(entry["const"])
        for name, entry in reference_props["medal_multipliers"]["properties"].items()
    }
    factors = {
        difficulty: float(entry["const"])
        for difficulty, entry in reference_props["arcade_rush_factors"]["properties"].items()
    }
    return ContractConstants(
        tick_rate_hz=int(scenario_props["tick_rate_hz"]["const"]),
        history_warmup_s=float(scenario_props["history_warmup_s"]["const"]),
        opportunity_window_s=float(scenario_props["opportunity_window_s"]["const"]),
        handover_max_position_m=float(scenario_props["handover_max_position_m"]["const"]),
        handover_max_speed_m_s=float(scenario_props["handover_max_speed_m_s"]["const"]),
        required_telemetry_by_family=telemetry,
        required_clean_laps=int(reference_props["required_clean_laps"]["const"]),
        sector_count=int(reference_props["sector_count"]["const"]),
        medal_multipliers=multipliers,
        rejection_criteria=tuple(reference_props["rejection_criteria"]["const"]),
        arcade_rush_factors=factors,
    )


# ---------------------------------------------------------------------------
# Semantic checks
# ---------------------------------------------------------------------------


def check_family_agreement(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """The fixture family and the enclosed scenario family must agree."""
    failures: list[Failure] = []
    fixture_family = document["fixture_family"]
    scenario_family = document["scenario"]["scenario_family"]
    if fixture_family != scenario_family:
        failures.append(
            Failure(
                "semantic",
                "fixture_family",
                f"fixture_family is {fixture_family!r} but the enclosed scenario "
                f"declares {scenario_family!r}",
                check="family_agreement",
            )
        )
    return failures


def check_window_protocol(
    document: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Tactical families carry the 2 s warm-up and 3 s window; captures do not."""
    failures: list[Failure] = []
    scenario = document["scenario"]
    protocol = scenario["protocol"]
    family = scenario["scenario_family"]
    if family == CAPTURE_FAMILY:
        for member in ("history_warmup_s", "opportunity_window_s"):
            if member in protocol:
                failures.append(
                    Failure(
                        "semantic",
                        f"scenario.protocol.{member}",
                        f"{member} belongs to the tactical opportunity-window protocol; "
                        "a reference_lap_capture scenario must omit it",
                        check="window_protocol",
                    )
                )
        return failures
    expected = (
        ("history_warmup_s", constants.history_warmup_s),
        ("opportunity_window_s", constants.opportunity_window_s),
    )
    for member, value in expected:
        if member not in protocol:
            failures.append(
                Failure(
                    "semantic",
                    "scenario.protocol",
                    f"tactical family {family!r} requires protocol.{member} = {value} s",
                    check="window_protocol",
                )
            )
        elif abs(float(protocol[member]) - value) > TOLERANCE:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.protocol.{member}",
                    f"protocol.{member} is {protocol[member]} but BENCHMARKS fixes "
                    f"{value} s for an opportunity window",
                    check="window_protocol",
                )
            )
    return failures


def check_telemetry_required(
    document: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """The declared telemetry must cover the per-family minimum."""
    failures: list[Failure] = []
    scenario = document["scenario"]
    family = scenario["scenario_family"]
    key = CAPTURE_FAMILY if family == CAPTURE_FAMILY else "tactical_families"
    minimum = set(constants.required_telemetry_by_family[key])
    declared = set(scenario["required_telemetry"])
    missing = sorted(minimum - declared)
    if missing:
        failures.append(
            Failure(
                "semantic",
                "scenario.required_telemetry",
                f"family {family!r} requires telemetry channels {missing} that the "
                "scenario does not declare",
                check="telemetry_required",
            )
        )
    return failures


def check_reference_linkage(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """A scenario's reference must resolve and match the compared participants.

    BENCHMARKS: match an evaluated Roadstormer and Classic by car, loadout,
    difficulty, assists, initial scenario and reference revision.
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    if "reference" not in scenario:
        return failures
    reference = scenario["reference"]
    records = document.get("reference_records", [])
    matches = [record for record in records if record["record_id"] == reference["record_id"]]
    if not matches:
        failures.append(
            Failure(
                "semantic",
                "scenario.reference",
                f"no embedded reference record with id {reference['record_id']!r}",
                check="reference_linkage",
            )
        )
        return failures
    record = matches[0]
    if record["revision"] != reference["revision"]:
        failures.append(
            Failure(
                "semantic",
                "scenario.reference.revision",
                f"reference revision {reference['revision']!r} does not match the "
                f"embedded record's revision {record['revision']!r}",
                check="reference_linkage",
            )
        )
    if record["kind"] != reference["kind"]:
        failures.append(
            Failure(
                "semantic",
                "scenario.reference.kind",
                f"reference kind {reference['kind']!r} does not match the embedded "
                f"record's kind {record['kind']!r}",
                check="reference_linkage",
            )
        )
    if record["course"]["course_id"] != scenario["course"]["course_id"]:
        failures.append(
            Failure(
                "semantic",
                "scenario.course.course_id",
                f"scenario course {scenario['course']['course_id']!r} does not match "
                f"the referenced record's course {record['course']['course_id']!r}",
                check="reference_linkage",
            )
        )
    scenario_course_revision = scenario["course"].get("course_revision")
    record_course_revision = record["course"].get("course_revision")
    if scenario_course_revision != record_course_revision:
        failures.append(
            Failure(
                "semantic",
                "scenario.course.course_revision",
                f"scenario course revision {scenario_course_revision!r} does not "
                f"match the referenced record's course revision "
                f"{record_course_revision!r}; BENCHMARKS matching assumes the "
                "same initial scenario and course dependencies (nulls may agree "
                "while course content is unratified)",
                check="reference_linkage",
            )
        )
    subject = record["subject"]
    for index, participant in enumerate(scenario["participants"]):
        if participant["role"] != EVALUATED_ROLE:
            continue
        for field in ("car_id", "loadout", "assists"):
            if participant[field] != subject[field]:
                failures.append(
                    Failure(
                        "semantic",
                        f"scenario.participants.{index}.{field}",
                        f"matched participant {participant['slot']!r} has {field} "
                        f"{participant[field]!r} but the referenced record captured "
                        f"{subject[field]!r}; matched comparisons must agree on car, "
                        "loadout and assists",
                        check="reference_linkage",
                    )
                )
    return failures


def check_reference_capture_structure(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """A reference capture declares exactly one calibration-driver subject.

    BENCHMARKS 'Reference driver and records': the CalibrationDriver is the
    fixed, versioned, traffic-free follower, and using an evaluated AI
    difficulty as its own reference is not allowed. The scenario schema fixes
    ``reference_subject`` as the single calibration-driver subject of a
    reference capture; this check makes that text executable, so a capture
    cannot establish references from a learned or evaluated driver and no
    traffic can share a traffic-free capture run.
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    if scenario["scenario_family"] != CAPTURE_FAMILY:
        return failures
    participants = scenario["participants"]
    subjects = [
        (index, participant)
        for index, participant in enumerate(participants)
        if participant.get("role") == REFERENCE_SUBJECT_ROLE
    ]
    if len(participants) != 1 or len(subjects) != 1:
        roles = ", ".join(
            f"{participant.get('slot')!r}:{participant.get('role')!r}"
            for participant in participants
        )
        failures.append(
            Failure(
                "semantic",
                "scenario.participants",
                "a reference_lap_capture scenario must declare exactly one "
                f"participant with role {REFERENCE_SUBJECT_ROLE!r} (found: {roles}); "
                "the reference subject runs alone on a traffic-free capture",
                check="reference_capture_structure",
            )
        )
        return failures
    index, subject = subjects[0]
    driver = subject.get("driver")
    if not isinstance(driver, Mapping) or driver.get("kind") != CALIBRATION_DRIVER_KIND:
        found = None if not isinstance(driver, Mapping) else driver.get("kind")
        failures.append(
            Failure(
                "semantic",
                f"scenario.participants.{index}.driver.kind",
                f"the reference_subject must be driven by kind "
                f"{CALIBRATION_DRIVER_KIND!r}; found {found!r}. BENCHMARKS "
                "forbids using an evaluated AI difficulty as its own reference",
                check="reference_capture_structure",
            )
        )
    return failures


def check_evidence_status(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """An authored fixture may only carry planned records, without results.

    Measured and superseded records are evidence produced by M1/M4 capture
    tooling as separate artifacts; a planned record must not pre-fill any
    result, so an authored file cannot impersonate a record.
    """
    failures: list[Failure] = []
    for index, record in enumerate(document.get("reference_records", [])):
        prefix = f"reference_records.{index}"
        status = record["status"]
        if status != "planned":
            failures.append(
                Failure(
                    "semantic",
                    f"{prefix}.status",
                    f"status {status!r} is measured evidence produced by capture "
                    "tooling; an authored fixture may only carry 'planned' records",
                    check="evidence_status",
                )
            )
            continue
        results = record["results"]
        populated = []
        if results["laps"]:
            populated.append("laps")
        if results["speed_samples"]:
            populated.append("speed_samples")
        if any(value is not None for value in results["statistics"].values()):
            populated.append("statistics")
        if any(value is not None for value in results["hashes"].values()):
            populated.append("hashes")
        thresholds = record["derived_thresholds"]
        if any(thresholds[key] is not None for key in ("bronze_s", "silver_s", "gold_s")):
            populated.append("derived_thresholds")
        if populated:
            failures.append(
                Failure(
                    "semantic",
                    f"{prefix}.results",
                    f"a planned record must carry no results; found values in "
                    f"{populated}",
                    check="evidence_status",
                )
            )
    return failures


def check_rejection_criteria_complete(
    document: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Every record's rejection criteria must be exactly the five specified."""
    failures: list[Failure] = []
    required = list(constants.rejection_criteria)
    for index, record in enumerate(document.get("reference_records", [])):
        declared = record["capture_protocol"]["rejection_criteria"]
        prefix = f"reference_records.{index}.capture_protocol.rejection_criteria"
        if len(set(declared)) != len(declared):
            failures.append(
                Failure(
                    "semantic",
                    prefix,
                    "rejection criteria must not repeat an entry",
                    check="rejection_criteria_complete",
                )
            )
        missing = [criterion for criterion in required if criterion not in declared]
        if missing:
            failures.append(
                Failure(
                    "semantic",
                    prefix,
                    f"BENCHMARKS rejects runs with {required}; missing {missing}",
                    check="rejection_criteria_complete",
                )
            )
    return failures


def check_reference_record_id_uniqueness(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Embedded reference records have unique record_id values.

    A scenario's ``reference`` member resolves by ``record_id``. Two embedded
    records under one ID make linkage silently read the first and leave
    conflicting evidence under a single identity; capture tooling addresses
    records by ID, so duplicates cannot be resolved downstream either.
    """
    failures: list[Failure] = []
    seen: dict[str, int] = {}
    for index, record in enumerate(document.get("reference_records", [])):
        record_id = record["record_id"]
        if record_id in seen:
            failures.append(
                Failure(
                    "semantic",
                    f"reference_records.{index}.record_id",
                    f"record_id {record_id!r} is already declared by "
                    f"reference_records.{seen[record_id]}; embedded records must "
                    "have distinct IDs so reference linkage and capture "
                    "tooling address one record per ID",
                    check="reference_record_id_uniqueness",
                )
            )
        else:
            seen[record_id] = index
    return failures


def check_clean_lap_accounting(
    document: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """A measured record must retain enough clean laps and consistent statistics.

    No measured record is authored at M0.9 (see evidence_status); this check
    defines the rule the capture tooling must satisfy, and the unit suite
    exercises it with synthetic arithmetic data.
    """
    failures: list[Failure] = []
    for index, record in enumerate(document.get("reference_records", [])):
        if record["status"] != "measured":
            continue
        prefix = f"reference_records.{index}"
        laps = record["results"]["laps"]
        clean = [lap for lap in laps if lap.get("clean") is True]
        if len(clean) < constants.required_clean_laps:
            failures.append(
                Failure(
                    "semantic",
                    f"{prefix}.results.laps",
                    f"a measured record must retain at least {constants.required_clean_laps} "
                    f"clean laps; found {len(clean)}",
                    check="clean_lap_accounting",
                )
            )
        for position, lap in enumerate(laps):
            if lap.get("clean") is False and lap.get("invalid_reason") not in constants.rejection_criteria:
                failures.append(
                    Failure(
                        "semantic",
                        f"{prefix}.results.laps.{position}",
                        "an unclean lap must carry an invalid_reason from the capture "
                        "protocol's rejection criteria",
                        check="clean_lap_accounting",
                    )
                )
            if lap.get("clean") is True and lap.get("time_s") is None:
                failures.append(
                    Failure(
                        "semantic",
                        f"{prefix}.results.laps.{position}",
                        "a clean lap must retain its time_s",
                        check="clean_lap_accounting",
                    )
                )
            splits = lap.get("sector_splits_s")
            if splits is not None and len(splits) != constants.sector_count:
                failures.append(
                    Failure(
                        "semantic",
                        f"{prefix}.results.laps.{position}",
                        f"sector_splits_s must hold {constants.sector_count} sector times",
                        check="clean_lap_accounting",
                    )
                )
        statistics = record["results"]["statistics"]
        if any(value is None for value in statistics.values()):
            failures.append(
                Failure(
                    "semantic",
                    f"{prefix}.results.statistics",
                    "a measured record must retain median, min and max over the clean laps",
                    check="clean_lap_accounting",
                )
            )
            continue
        times = [float(lap["time_s"]) for lap in clean if lap.get("time_s") is not None]
        if not times:
            continue
        expected = {
            "median_s": _median(times),
            "min_s": min(times),
            "max_s": max(times),
        }
        for key, value in expected.items():
            if abs(float(statistics[key]) - value) > TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        f"{prefix}.results.statistics.{key}",
                        f"{key} is {statistics[key]} but the clean laps give {value}",
                        check="clean_lap_accounting",
                    )
                )
    return failures


def check_medal_threshold_arithmetic(
    document: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Medal thresholds are the documented factors times the measured median."""
    failures: list[Failure] = []
    for index, record in enumerate(document.get("reference_records", [])):
        if record["status"] != "measured":
            continue
        # Medal thresholds derive from the flying-lap median; on a
        # standing_start_lap_set they do not apply (reference_run.schema.json
        # permits null there) and Arcade Rush uses that record's sector times.
        if record["kind"] == "standing_start_lap_set":
            continue
        prefix = f"reference_records.{index}"
        thresholds = record["derived_thresholds"]
        if any(thresholds[key] is None for key in ("bronze_s", "silver_s", "gold_s")):
            failures.append(
                Failure(
                    "semantic",
                    f"{prefix}.derived_thresholds",
                    "a measured record must retain the derived medal thresholds",
                    check="medal_threshold_arithmetic",
                )
            )
            continue
        median_s = record["results"]["statistics"]["median_s"]
        if median_s is None:
            continue  # already reported by clean_lap_accounting
        pairs = (
            ("bronze_s", "bronze"),
            ("silver_s", "silver"),
            ("gold_s", "gold"),
        )
        for field, multiplier_name in pairs:
            multiplier = constants.medal_multipliers[multiplier_name]
            expected = multiplier * float(median_s)
            if abs(float(thresholds[field]) - expected) > TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        f"{prefix}.derived_thresholds.{field}",
                        f"{field} is {thresholds[field]} but {multiplier} x the measured "
                        f"median {median_s} = {expected}",
                        check="medal_threshold_arithmetic",
                    )
                )
    return failures


def check_dependency_completeness(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """A measured record must name every dependency it was captured against."""
    failures: list[Failure] = []
    paths = (
        "course.course_revision",
        "driver.driver_revision",
        "driver.reference_line_revision",
        "dependencies.engine_revision",
        "dependencies.handling_revision",
        "dependencies.platform",
    )
    for index, record in enumerate(document.get("reference_records", [])):
        if record["status"] != "measured":
            continue
        undetermined = [path for path in paths if resolve_dotted(record, path) is None]
        if undetermined:
            failures.append(
                Failure(
                    "semantic",
                    f"reference_records.{index}",
                    "a measured record must name every dependency it was captured "
                    f"against; undetermined: {undetermined}",
                    check="dependency_completeness",
                )
            )
    return failures


def check_measured_evidence_completeness(
    document: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """A measured record must retain the evidence BENCHMARKS requires.

    BENCHMARKS 'Reference driver and records': retain median, min/max,
    individual times, sector splits, speed samples, car/loadout/assist hashes,
    line/controller version, engine/backend/handling/course revisions,
    platform and seeds. dependency_completeness covers the revisions and the
    platform; this check covers the retained evidence itself, which the
    dependency check cannot see: a measured standing_start_lap_set whose laps
    omit sector splits cannot build the Arcade Rush budgets, and a measured
    record without speed samples or the car/loadout/assist/track/handling
    hashes has lost evidence the contract promises to keep.
    """
    failures: list[Failure] = []
    for index, record in enumerate(document.get("reference_records", [])):
        if record["status"] != "measured":
            continue
        prefix = f"reference_records.{index}"
        results = record["results"]
        if not results["speed_samples"]:
            failures.append(
                Failure(
                    "semantic",
                    f"{prefix}.results.speed_samples",
                    "BENCHMARKS retains speed samples with each record; a measured "
                    "record must retain at least one speed sample",
                    check="measured_evidence_completeness",
                )
            )
        null_hashes = sorted(
            name for name, value in results["hashes"].items() if value is None
        )
        if null_hashes:
            failures.append(
                Failure(
                    "semantic",
                    f"{prefix}.results.hashes",
                    "BENCHMARKS retains the car/loadout/assist hashes and "
                    "TECHNICAL_DESIGN 'Content contracts' additionally retains "
                    f"the track/handling hashes with each record; undetermined: "
                    f"{null_hashes}",
                    check="measured_evidence_completeness",
                )
            )
        for position, lap in enumerate(results["laps"]):
            if lap.get("clean") is not True:
                continue
            splits = lap.get("sector_splits_s")
            if splits is None or len(splits) != constants.sector_count:
                failures.append(
                    Failure(
                        "semantic",
                        f"{prefix}.results.laps.{position}.sector_splits_s",
                        f"a measured record must retain {constants.sector_count} "
                        "sector splits per clean lap (BENCHMARKS retains sector "
                        "splits; Arcade Rush budgets are built from the "
                        "standing-start record's sector times)",
                        check="measured_evidence_completeness",
                    )
                )
    return failures


def check_initial_state_agreement(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Initial state, commands and history must pin the scenario consistently.

    Implements the initial state/commands/history half of the TECHNICAL_DESIGN
    'Content contracts' row: per-participant entries name real slots without
    duplicates, a tactical comparison fixes the matched initial state of its
    single evaluated slot - the state every comparison arm starts from - and a
    matched history, the single-participant members agree with that entry, a
    stored-snapshot history names its snapshot, and an authored command
    schedule is actually present.
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    initial = scenario["initial_state"]
    family = scenario["scenario_family"]
    tactical = family != CAPTURE_FAMILY
    participants = scenario["participants"]
    slots = {participant["slot"] for participant in participants}
    matched = [
        participant["slot"]
        for participant in participants
        if participant["role"] == EVALUATED_ROLE
    ]

    entries = initial.get("per_participant_state")
    if entries is None:
        if tactical and matched:
            failures.append(
                Failure(
                    "semantic",
                    "scenario.initial_state",
                    "a tactical comparison runs from matched initial states; add "
                    "initial_state.per_participant_state with an entry for the "
                    f"evaluated slot ({sorted(matched)})",
                    check="initial_state_agreement",
                )
            )
    else:
        seen: set[str] = set()
        for position, entry in enumerate(entries):
            slot = entry.get("slot")
            if slot not in slots:
                failures.append(
                    Failure(
                        "semantic",
                        f"scenario.initial_state.per_participant_state.{position}.slot",
                        f"slot {slot!r} is not a participant of this scenario "
                        f"(participants: {sorted(slots)})",
                        check="initial_state_agreement",
                    )
                )
                continue
            if slot in seen:
                failures.append(
                    Failure(
                        "semantic",
                        f"scenario.initial_state.per_participant_state.{position}.slot",
                        f"slot {slot!r} declares its initial state twice",
                        check="initial_state_agreement",
                    )
                )
                continue
            seen.add(slot)
        missing = [slot for slot in matched if slot not in seen]
        if missing and tactical:
            failures.append(
                Failure(
                    "semantic",
                    "scenario.initial_state.per_participant_state",
                    "a tactical comparison fixes matched initial states; no entry "
                    f"for the evaluated slot {missing}",
                    check="initial_state_agreement",
                )
            )
        for position, entry in enumerate(entries):
            if entry.get("slot") not in matched:
                continue
            for member, summary in (
                ("forward_gap_m", "forward_gap_m"),
                ("lateral_offset_m", "lateral_offset_m"),
                ("speed_m_s", "entry_speed_m_s"),
            ):
                entry_value = entry.get(member)
                summary_value = initial.get(summary)
                if entry_value is None or summary_value is None:
                    continue
                if abs(float(entry_value) - float(summary_value)) > TOLERANCE:
                    failures.append(
                        Failure(
                            "semantic",
                            f"scenario.initial_state.per_participant_state.{position}.{member}",
                            f"the evaluated slot {entry['slot']!r} declares "
                            f"{member} {entry_value} but initial_state.{summary} is "
                            f"{summary_value}; matched initial states must agree",
                            check="initial_state_agreement",
                        )
                    )

    history = initial.get("history")
    if history is None:
        if tactical:
            failures.append(
                Failure(
                    "semantic",
                    "scenario.initial_state",
                    "a tactical comparison runs from matched histories; add "
                    "initial_state.history naming how the shared pre-window "
                    "history is established",
                    check="initial_state_agreement",
                )
            )
    else:
        if history.get("source") == "stored_scenario_snapshot":
            for member in ("snapshot_id", "snapshot_revision"):
                if history.get(member) is None:
                    failures.append(
                        Failure(
                            "semantic",
                            f"scenario.initial_state.history.{member}",
                            f"history source 'stored_scenario_snapshot' requires "
                            f"{member}",
                            check="initial_state_agreement",
                        )
                    )
        warmup = history.get("warmup_s")
        protocol_warmup = scenario["protocol"].get("history_warmup_s")
        if (
            warmup is not None
            and protocol_warmup is not None
            and abs(float(warmup) - float(protocol_warmup)) > TOLERANCE
        ):
            failures.append(
                Failure(
                    "semantic",
                    "scenario.initial_state.history.warmup_s",
                    f"history warmup_s is {warmup} but protocol.history_warmup_s "
                    f"is {protocol_warmup}; BENCHMARKS fixes the two-second warm-up",
                    check="initial_state_agreement",
                )
            )

    commands = initial.get("initial_commands")
    if commands is not None and commands.get("source") == "authored_schedule":
        if not commands.get("schedule"):
            failures.append(
                Failure(
                    "semantic",
                    "scenario.initial_state.initial_commands.schedule",
                    "initial_commands source 'authored_schedule' requires a "
                    "non-empty command schedule",
                    check="initial_state_agreement",
                )
            )
    return failures


def check_driver_revision_pinning(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Every cloning-only driver - participant or comparison arm - pins its producer.

    No dependencies member pins the behavioral-cloning-only producer, and
    BENCHMARKS/OPPONENT_AI evaluate it separately from the PPO-trained
    policy; without a producer_revision the two could only be told apart
    by an undocumented convention.
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    for index, participant in enumerate(scenario["participants"]):
        driver = participant.get("driver")
        if driver is None:
            continue  # the evaluated slot's producers are its arms
        if driver.get("kind") == "cloning_only_policy" and "producer_revision" not in driver:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.participants.{index}.driver",
                    f"cloning_only_policy participant {participant['slot']!r} must "
                    "carry driver.producer_revision; nothing else pins that "
                    "producer, and OPPONENT_AI evaluates cloning-only separately "
                    "from the PPO-trained policy",
                    check="driver_revision_pinning",
                )
            )
    comparison = scenario.get("comparison")
    if comparison is None:
        return failures
    for index, arm in enumerate(comparison.get("arms", [])):
        driver = arm.get("driver", {})
        if driver.get("kind") == "cloning_only_policy" and "producer_revision" not in driver:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.comparison.arms.{index}.driver",
                    f"cloning_only_policy arm {arm.get('arm_id')!r} must carry "
                    "driver.producer_revision; nothing else pins that producer, "
                    "and OPPONENT_AI evaluates cloning-only separately from the "
                    "PPO-trained policy",
                    check="driver_revision_pinning",
                )
            )
    return failures


def check_comparison_arms(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """A matched comparison is one evaluated slot plus alternative producer runs.

    BENCHMARKS 'Tactical comparison' compares Classic, cloning-only, Surge and
    Switch from matched initial states and histories. Those producers are
    separate executions of the same scenario driving one evaluated slot, not
    simultaneous participants: co-located compared cars would each be traffic
    for the others, so their histories could not match and the window would
    start in contact. The scenario therefore declares exactly one 'evaluated'
    participant, fixes its matched initial state and shared history once, and
    lists the compared producers as comparison.arms (at least two for the six
    tactical families).
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    family = scenario["scenario_family"]
    participants = scenario["participants"]
    tactical_comparison = family in TACTICAL_COMPARISON_FAMILIES
    comparison = scenario.get("comparison")

    evaluated = [
        (index, participant)
        for index, participant in enumerate(participants)
        if participant["role"] == EVALUATED_ROLE
    ]
    if len(evaluated) > 1:
        slots = ", ".join(sorted(participant["slot"] for _i, participant in evaluated))
        failures.append(
            Failure(
                "semantic",
                "scenario.participants",
                f"participants {slots} all carry role 'evaluated'; a matched "
                "comparison evaluates one slot, and the compared producers are "
                "alternative runs of it declared in comparison.arms - never "
                "simultaneous participants",
                check="comparison_arms",
            )
        )

    for index, participant in enumerate(participants):
        if participant["role"] == EVALUATED_ROLE:
            if "driver" in participant:
                failures.append(
                    Failure(
                        "semantic",
                        f"scenario.participants.{index}.driver",
                        f"the evaluated slot {participant['slot']!r} carries its own "
                        "driver; its producers are comparison.arms, and a second "
                        "driver here could disagree with them",
                        check="comparison_arms",
                    )
                )
        elif "driver" not in participant:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.participants.{index}",
                    f"participant {participant['slot']!r} has role "
                    f"{participant['role']!r} and must declare its driver; only the "
                    "evaluated slot leaves its drivers to comparison.arms",
                    check="comparison_arms",
                )
            )

    if comparison is None:
        if tactical_comparison:
            failures.append(
                Failure(
                    "semantic",
                    "scenario.comparison",
                    f"tactical family {family!r} compares producers from matched "
                    "initial states and histories; add scenario.comparison naming "
                    "the evaluated slot and the compared arms",
                    check="comparison_arms",
                )
            )
        elif evaluated:
            failures.append(
                Failure(
                    "semantic",
                    "scenario.comparison",
                    "the scenario declares an evaluated participant but no "
                    "comparison.arms naming the producers that run it",
                    check="comparison_arms",
                )
            )
        return failures

    evaluated_slot = comparison.get("evaluated_slot")
    by_slot = {participant["slot"]: participant for participant in participants}
    if evaluated_slot not in by_slot:
        failures.append(
            Failure(
                "semantic",
                "scenario.comparison.evaluated_slot",
                f"evaluated_slot {evaluated_slot!r} is not a participant of this "
                f"scenario (participants: {sorted(by_slot)})",
                check="comparison_arms",
            )
        )
    elif by_slot[evaluated_slot]["role"] != EVALUATED_ROLE:
        failures.append(
            Failure(
                "semantic",
                "scenario.comparison.evaluated_slot",
                f"evaluated_slot {evaluated_slot!r} names a participant with role "
                f"{by_slot[evaluated_slot]['role']!r}; it must name the single "
                "participant with role 'evaluated'",
                check="comparison_arms",
            )
        )

    arms = comparison.get("arms", [])
    if tactical_comparison and len(arms) < 2:
        failures.append(
            Failure(
                "semantic",
                "scenario.comparison.arms",
                f"tactical family {family!r} compares producers, so it needs at "
                f"least two arms; found {len(arms)}",
                check="comparison_arms",
            )
        )
    seen: set[str] = set()
    for index, arm in enumerate(arms):
        arm_id = arm.get("arm_id")
        if arm_id in seen:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.comparison.arms.{index}.arm_id",
                    f"arm_id {arm_id!r} is declared twice; results are reported "
                    "per arm, so the compared producers must be distinguishable",
                    check="comparison_arms",
                )
            )
        seen.add(arm_id)
    return failures


def _arm_spec_key(driver: Mapping[str, Any]) -> tuple[Any, ...]:
    """Identity of a compared producer: kind, difficulty, style and revision."""
    return (
        driver.get("kind"),
        driver.get("difficulty"),
        driver.get("style"),
        driver.get("producer_revision"),
    )


def check_comparison_arm_identity(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Comparison arms name distinct BENCHMARKS producers with coherent styles.

    Each arm is a separate execution of one evaluated slot and results are
    reported per arm. Two arms carrying the same driver spec would attribute
    results to a producer that never ran, and a mislabelled style would claim
    a Classic run as Surge or hide which learned style ran. BENCHMARKS
    'Tactical comparison' compares Classic, cloning-only, Surge and Switch:
    those producers are classic_planner, cloning_only_policy and
    learned_policy (Surge/Switch are learned styles); human_proxy and scripted
    drivers are fixed context participants, not compared producers. This
    binds the six preregistered tactical families; a scenario may instantiate
    any subset of at least two producers - covering all four is a
    benchmark-level requirement across the six families, not a per-scenario
    one (see schemas/scenario/README.md).
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    if scenario["scenario_family"] not in TACTICAL_COMPARISON_FAMILIES:
        return failures
    comparison = scenario.get("comparison")
    if comparison is None:
        return failures
    seen: dict[tuple[Any, ...], str] = {}
    for index, arm in enumerate(comparison.get("arms", [])):
        driver = arm.get("driver", {})
        arm_id = arm.get("arm_id")
        kind = driver.get("kind")
        if kind not in PRODUCER_ARM_KINDS:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.comparison.arms.{index}.driver.kind",
                    f"comparison arm {arm_id!r} declares driver kind {kind!r}; the "
                    f"compared producers are {sorted(PRODUCER_ARM_KINDS)} - human "
                    "proxies and scripted drivers are fixed context participants, "
                    "not compared producers",
                    check="comparison_arm_identity",
                )
            )
            continue
        allowed_styles = ARM_STYLE_RULES[kind]
        style = driver.get("style")
        if style not in allowed_styles:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.comparison.arms.{index}.driver.style",
                    f"producer {kind!r} requires style {sorted(allowed_styles)} "
                    "(Classic uses the 0/0 style pair; a Roadstormer is Surge or "
                    f"Switch); found {style!r}",
                    check="comparison_arm_identity",
                )
            )
        key = _arm_spec_key(driver)
        if key in seen:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.comparison.arms.{index}.driver",
                    f"arm {arm_id!r} repeats the producer already declared by arm "
                    f"{seen[key]!r} (kind, difficulty, style and producer_revision "
                    "are equal); two runs of one producer cannot be told apart in "
                    "results reported per arm",
                    check="comparison_arm_identity",
                )
            )
        else:
            seen[key] = str(arm_id)
    return failures


def check_tactical_context_required(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """A tactical opportunity window needs at least one fixed context car.

    All six BENCHMARKS 'Tactical comparison' families define an encounter with
    other cars (a slower lead, a second car, merge traffic or a proxy). A
    scenario whose only participant is the evaluated slot leaves
    ``initial_state.forward_gap_m`` pointing at nothing and cannot realise an
    opportunity window.
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    if scenario["scenario_family"] not in TACTICAL_COMPARISON_FAMILIES:
        return failures
    context = [
        participant
        for participant in scenario["participants"]
        if participant["role"] != EVALUATED_ROLE
    ]
    if not context:
        slots = ", ".join(
            sorted(participant["slot"] for participant in scenario["participants"])
        )
        failures.append(
            Failure(
                "semantic",
                "scenario.participants",
                "a tactical comparison needs at least one fixed context participant "
                f"besides the evaluated slot (found only: {slots}); every BENCHMARKS "
                "tactical family is an encounter with another car, and a solo "
                "evaluated slot leaves forward_gap_m pointing at nothing",
                check="tactical_context_required",
            )
        )
    return failures


def check_participant_pose_distinctness(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """No two simultaneous participants of one execution may declare the same pose.

    Participants of a scenario are the cars present in one execution, so two
    of them must be distinguishable on the road. A pair whose authored
    per-participant states agree on every pose member (forward gap, lateral
    offset, speed, heading offset) are co-located cars: the window would start
    in contact and each car would be traffic for the other. Entries that
    author no pose member at all are not compared - an unauthored pose is
    simply not configuration.
    """
    failures: list[Failure] = []
    scenario = document["scenario"]
    initial = scenario.get("initial_state", {})
    entries = initial.get("per_participant_state") or []
    authored: list[tuple[str, int, tuple[Any, ...]]] = []
    for position, entry in enumerate(entries):
        slot = entry.get("slot")
        if slot is None:
            continue
        signature = tuple(entry.get(member) for member in POSE_MEMBERS)
        if all(value is None for value in signature):
            continue
        authored.append((slot, position, signature))
    for first in range(len(authored)):
        slot_a, position_a, signature_a = authored[first]
        for second in range(first + 1, len(authored)):
            slot_b, position_b, signature_b = authored[second]
            if signature_a != signature_b:
                continue
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.initial_state.per_participant_state.{position_b}.slot",
                    f"participants {slot_a!r} and {slot_b!r} declare the same "
                    "initial pose (forward gap, lateral offset, speed and heading "
                    "offset all equal); simultaneous participants must be "
                    "distinguishable on the road",
                    check="participant_pose_distinctness",
                )
            )
    return failures


def check_participant_slot_uniqueness(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Participant slots are unique identities inside one execution.

    ``per_participant_state`` entries and ``comparison.evaluated_slot`` name
    participants by slot, so two participants sharing a slot make those
    references ambiguous; the pose-distinctness rule compares authored poses,
    not identity.
    """
    failures: list[Failure] = []
    seen: dict[str, int] = {}
    for index, participant in enumerate(document["scenario"]["participants"]):
        slot = participant["slot"]
        if slot in seen:
            failures.append(
                Failure(
                    "semantic",
                    f"scenario.participants.{index}.slot",
                    f"slot {slot!r} is already declared by participant "
                    f"{seen[slot]}; slots are identities for per_participant_state "
                    "and evaluated_slot, so participants must be distinguishable "
                    "by name",
                    check="participant_slot_uniqueness",
                )
            )
        else:
            seen[slot] = index
    return failures


def check_null_unknown_pairing(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Every null has an unknowns entry, and every entry points at a null."""
    failures: list[Failure] = []
    null_paths = set(iter_null_paths(document))
    unknown_entries = document.get("unknowns", [])
    unknown_paths = [str(entry["path"]) for entry in unknown_entries]
    unknown_set = set(unknown_paths)
    # One null gets one explanation. A repeated path is ambiguous evidence
    # about why the value is undetermined even when both entries agree.
    for path in sorted(unknown_set):
        if unknown_paths.count(path) > 1:
            failures.append(
                Failure(
                    "semantic",
                    path,
                    f"unknowns declares this path {unknown_paths.count(path)} times; "
                    "one undetermined value takes exactly one explanation",
                    check="null_unknown_pairing",
                )
            )
    for path in sorted(null_paths):
        if path not in unknown_set:
            failures.append(
                Failure(
                    "semantic",
                    path,
                    "null means 'not yet determined' but has no unknowns entry",
                    check="null_unknown_pairing",
                )
            )
    for path in unknown_paths:
        resolved = resolve_dotted(document, path)
        if resolved is MISSING:
            failures.append(
                Failure(
                    "semantic",
                    path,
                    "unknowns entry does not resolve to a value in this document",
                    check="null_unknown_pairing",
                )
            )
        elif resolved is not None:
            failures.append(
                Failure(
                    "semantic",
                    path,
                    "has an unknowns entry but carries a determined value",
                    check="null_unknown_pairing",
                )
            )
    return failures


def check_metric_status_honesty(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """A fixture metric may not claim measured status or an unknown status."""
    failures: list[Failure] = []
    for index, metric in enumerate(document["comparison"]["metrics"]):
        status = metric.get("status")
        if status == "measured":
            failures.append(
                Failure(
                    "semantic",
                    f"comparison.metrics.{index}.status",
                    "a fixture metric carries status 'measured'; measured values "
                    "belong to reference records and evaluation reports",
                    check="metric_status_honesty",
                )
            )
        elif status is not None and status not in METRIC_STATUSES:
            failures.append(
                Failure(
                    "semantic",
                    f"comparison.metrics.{index}.status",
                    f"metric status must be one of {list(METRIC_STATUSES)}, found "
                    f"{status!r}; a fixture carries documented targets and "
                    "reporting requirements, never measured values",
                    check="metric_status_honesty",
                )
            )
    return failures


def check_metric_shape(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Comparison metrics must use the documented comparator/value vocabulary.

    Mirrors the handling validator's metric rules so both contracts check the
    shared acceptance_metric vocabulary identically: threshold comparators
    carry a numeric ``value`` and no bounds, range comparators carry ordered
    numeric ``value_min``/``value_max`` and no point ``value``, and a
    ``report`` metric carries no pass/fail bound at all.
    """
    failures: list[Failure] = []
    for index, metric in enumerate(document["comparison"]["metrics"]):
        metric_path = f"comparison.metrics.{index}"
        comparator = metric.get("comparator")
        if comparator not in COMPARATORS:
            # The schema enum already rejects this; keep the check defensive.
            failures.append(
                Failure(
                    "semantic",
                    f"{metric_path}.comparator",
                    f"comparator must be one of {list(COMPARATORS)}, found {comparator!r}",
                    check="metric_shape",
                )
            )
            continue
        value = metric.get("value")
        value_min = metric.get("value_min")
        value_max = metric.get("value_max")
        if comparator in THRESHOLD_COMPARATORS:
            if not _is_number(value):
                failures.append(
                    Failure(
                        "semantic",
                        f"{metric_path}.value",
                        f"comparator {comparator!r} requires a numeric value",
                        check="metric_shape",
                    )
                )
            if value_min is not None or value_max is not None:
                failures.append(
                    Failure(
                        "semantic",
                        f"{metric_path}.value_min",
                        "threshold comparators use value, not value_min/value_max",
                        check="metric_shape",
                    )
                )
        elif comparator in RANGE_COMPARATORS:
            if not _is_number(value_min) or not _is_number(value_max):
                failures.append(
                    Failure(
                        "semantic",
                        metric_path,
                        f"comparator {comparator!r} requires numeric value_min and value_max",
                        check="metric_shape",
                    )
                )
            elif float(value_min) >= float(value_max):
                failures.append(
                    Failure(
                        "semantic",
                        metric_path,
                        "value_min must be smaller than value_max",
                        check="metric_shape",
                    )
                )
            if value is not None:
                failures.append(
                    Failure(
                        "semantic",
                        f"{metric_path}.value",
                        "range comparators use value_min/value_max, not value",
                        check="metric_shape",
                    )
                )
        else:  # report
            if value is not None or value_min is not None or value_max is not None:
                failures.append(
                    Failure(
                        "semantic",
                        metric_path,
                        "comparator 'report' records without declaring a pass/fail "
                        "threshold; remove value/value_min/value_max",
                        check="metric_shape",
                    )
                )
    return failures


def check_content_hash(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    recorded = document.get("content_hash")
    if not isinstance(recorded, str) or not CONTENT_HASH_RE.match(recorded):
        return [
            Failure(
                "semantic",
                "content_hash",
                f"must look like 'sha256:<64 lowercase hex>', found {recorded!r}",
                check="content_hash",
            )
        ]
    actual = canonical_hash(document)
    if actual != recorded:
        return [
            Failure(
                "semantic",
                "content_hash",
                f"recorded {recorded} but the file hashes to {actual}",
                check="content_hash",
            )
        ]
    return []


def check_expectations_declared(
    document: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Expectations must name implemented checks and existing fixture parts."""
    failures: list[Failure] = []
    record_count = len(document.get("reference_records", []))
    for index, expectation in enumerate(document.get("expectations", [])):
        check = expectation.get("check")
        if check not in IMPLEMENTED_CHECKS:
            failures.append(
                Failure(
                    "semantic",
                    f"expectations.{index}.check",
                    f"check {check!r} is not implemented by this validator "
                    f"(implemented: {sorted(IMPLEMENTED_CHECKS)})",
                    check="expectation_implemented",
                )
            )
        path = expectation.get("path", "")
        if path in ("", "scenario"):
            continue
        match = re.fullmatch(r"reference_records\.(\d+)", path)
        if not match or int(match.group(1)) >= record_count:
            failures.append(
                Failure(
                    "semantic",
                    f"expectations.{index}.path",
                    f"path {path!r} does not reference a part of this fixture",
                    check="expectation_implemented",
                )
            )
    return failures


SEMANTIC_CHECKS = (
    check_expectations_declared,
    check_family_agreement,
    check_window_protocol,
    check_telemetry_required,
    check_reference_linkage,
    check_reference_capture_structure,
    check_evidence_status,
    check_rejection_criteria_complete,
    check_reference_record_id_uniqueness,
    check_clean_lap_accounting,
    check_medal_threshold_arithmetic,
    check_dependency_completeness,
    check_measured_evidence_completeness,
    check_initial_state_agreement,
    check_comparison_arms,
    check_comparison_arm_identity,
    check_tactical_context_required,
    check_participant_pose_distinctness,
    check_participant_slot_uniqueness,
    check_driver_revision_pinning,
    check_null_unknown_pairing,
    check_metric_status_honesty,
    check_metric_shape,
    check_content_hash,
)


# ---------------------------------------------------------------------------
# Fixture pipelines
# ---------------------------------------------------------------------------


@dataclasses.dataclass
class Contracts:
    fixture_schema: Mapping[str, Any]
    scenario_schema: Mapping[str, Any]
    reference_schema: Mapping[str, Any]
    constants: ContractConstants
    schemas_dir: Path


def load_contracts(schemas_dir: Path) -> Contracts:
    cache = SchemaCache()
    fixture_schema = cache.document(schemas_dir / FIXTURE_SCHEMA_NAME)
    scenario_schema = cache.document(schemas_dir / SCENARIO_SCHEMA_NAME)
    reference_schema = cache.document(schemas_dir / REFERENCE_SCHEMA_NAME)
    if not isinstance(fixture_schema, Mapping):
        raise DocumentError("fixture schema document must be a JSON object")
    return Contracts(
        fixture_schema=fixture_schema,
        scenario_schema=scenario_schema,
        reference_schema=reference_schema,
        constants=load_constants(scenario_schema, reference_schema),
        schemas_dir=schemas_dir,
    )


def validate_positive(path: Path, contracts: Contracts) -> list[Failure]:
    """Full pipeline for a positive fixture: schema, then semantics, then hash."""
    try:
        document = load_json(path)
    except DocumentError as exc:
        return [Failure("invalid-json", "", str(exc))]
    if not isinstance(document, Mapping):
        return [Failure("invalid-json", "", "fixture document must be a JSON object")]

    failures: list[Failure] = []
    cache = SchemaCache()
    context = DocumentContext(root=contracts.fixture_schema, base_dir=contracts.schemas_dir)
    validate_node(contracts.fixture_schema, document, "", context, failures, cache)
    if failures:
        return failures

    for check in SEMANTIC_CHECKS:
        failures.extend(check(document, contracts.constants))
    return failures


def validate_negative(path: Path, contracts: Contracts) -> tuple[list[Failure], list[Failure]]:
    """Run a negative fixture and compare against its .expected.json sidecar.

    Returns (actual_failures, report_failures). ``report_failures`` is non-empty
    when the fixture did not fail exactly as declared (including a missing or
    unreadable sidecar, or a fixture that unexpectedly validates).
    """
    actual = validate_positive(path, contracts)
    sidecar = path.with_suffix("").with_suffix(".expected.json")
    if not sidecar.exists():
        return actual, [
            Failure(
                "missing-expectation",
                "",
                f"no expectation sidecar next to {path.name}",
            )
        ]
    try:
        expected_document = load_json(sidecar)
    except DocumentError as exc:
        return actual, [Failure("invalid-json", sidecar.name, str(exc))]
    expected_entries = expected_document.get("expected_failures")
    if not isinstance(expected_entries, list):
        return actual, [
            Failure("invalid-json", sidecar.name, "sidecar needs an 'expected_failures' array")
        ]
    expected_keys = set()
    for entry in expected_entries:
        if not isinstance(entry, Mapping) or "code" not in entry or "path" not in entry:
            return actual, [
                Failure(
                    "invalid-json",
                    sidecar.name,
                    "each expected failure needs at least 'code' and 'path'",
                )
            ]
        expected_keys.add((str(entry["code"]), str(entry["path"]), entry.get("check")))

    report: list[Failure] = []
    if not actual:
        report.append(
            Failure(
                "unexpectedly-valid",
                path.name,
                "negative fixture validates but is expected to fail",
            )
        )
        return actual, report
    actual_keys = {failure.key() for failure in actual}
    for missing in sorted(expected_keys - actual_keys):
        report.append(
            Failure(
                "missing-failure",
                path.name,
                f"expected failure {missing} did not occur",
            )
        )
    for extra in sorted(actual_keys - expected_keys):
        report.append(
            Failure(
                "extra-failure",
                path.name,
                f"unexpected failure {extra} occurred",
            )
        )
    return actual, report


def update_hashes(directory: Path) -> int:
    """Recompute and write content_hash for every fixture in ``directory``."""
    updated = 0
    for path in sorted(directory.glob("*.json")):
        try:
            document = load_json(path)
        except DocumentError as exc:
            print(f"error: {exc}", file=sys.stderr)
            updated += 1
            continue
        if not isinstance(document, dict):
            print(f"error: {path.name} is not a JSON object", file=sys.stderr)
            updated += 1
            continue
        digest = canonical_hash(document)
        if document.get("content_hash") == digest:
            continue
        document["content_hash"] = digest
        path.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"updated {path.name}: {digest}")
        updated += 1
    return updated


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _iter_fixtures(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(path for path in directory.glob("*.json") if not path.name.endswith(".expected.json"))


def main(argv: Sequence[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Validate Roadstorm scenario/reference fixtures against schemas/scenario."
    )
    parser.add_argument(
        "--schemas",
        type=Path,
        default=here.parents[1] / "schemas" / "scenario",
        help="directory holding the three scenario contract schemas",
    )
    parser.add_argument(
        "--positive", type=Path, default=here / "positive", help="directory of valid fixtures"
    )
    parser.add_argument(
        "--negative", type=Path, default=here / "negative", help="directory of invalid fixtures"
    )
    parser.add_argument(
        "--update-hashes",
        action="store_true",
        help="recompute and write content_hash for the fixtures in --positive, then exit",
    )
    args = parser.parse_args(argv)

    if args.update_hashes:
        changed = update_hashes(args.positive)
        print(f"content_hash update complete ({changed} file(s) written)")
        return 0

    try:
        contracts = load_contracts(args.schemas)
    except DocumentError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    problems = 0

    positive = _iter_fixtures(args.positive)
    if not positive:
        print(f"error: no positive fixtures found in {args.positive}", file=sys.stderr)
        return 2
    for path in positive:
        failures = validate_positive(path, contracts)
        if failures:
            problems += 1
            print(f"FAIL {path.name}")
            for failure in failures:
                print(f"  - [{failure.code}] {failure.path}: {failure.message}")
        else:
            print(f"ok   {path.name}")

    negative = _iter_fixtures(args.negative)
    if not negative:
        print(f"error: no negative fixtures found in {args.negative}", file=sys.stderr)
        return 2
    for path in negative:
        _actual, report = validate_negative(path, contracts)
        if report:
            problems += 1
            print(f"FAIL {path.name} (negative expectations)")
            for failure in report:
                print(f"  - [{failure.code}] {failure.path}: {failure.message}")
        else:
            print(f"ok   {path.name} (rejected as expected)")

    total = len(positive) + len(negative)
    if problems:
        print(f"{problems} of {total} fixtures have problems")
        return 1
    print(f"all {total} fixtures behave as contracted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
