#!/usr/bin/env python3
"""Roadstorm tactical-intent contract validator.

Ownership: fixtures/intent/** together with schemas/intent/** (PLAN.md M0.9,
job 8cfeb70f-e5b3-4cac-8b4c-83a933d0970b).

This module is the executable form of the two text contracts in
``schemas/intent/``:

* ``tactical_intent.schema.json`` - the versioned TacticalIntent record
  contract (fields, bounds, age and reset semantics) from
  docs/OPPONENT_AI.md and docs/TECHNICAL_DESIGN.md;
* ``intent_fixture.schema.json`` - the fixture wrapper that fixes one
  scenario and declares behavioral expectations.

It does three jobs a plain JSON Syntax check cannot:

1. Validates every ``fixtures/intent/positive/*.json`` fixture against the
   fixture schema (which pulls in the record schema by ``$ref``) with a small
   standard-library JSON Schema evaluator - no third-party packages, no
   installs, no network. Documents are strict JSON: NaN, Infinity and
   -Infinity are refused at parse time (they are Python json extensions, not
   JSON), and the evaluator refuses non-finite numbers in memory. This keeps
   an invalid pace target or decoded value from passing comparisons that are
   false for NaN.
2. Runs the semantic checks that make the contract meaningful rather than
   merely well-formed: lateral decode consistency against the documented
   ``(road_width - car_width)/2 - 0.5 m`` corridor, pace decode consistency
   (ordered interval, decoded target, nonnegative speed corrections checked
   against the pre-safety decode), commitment/drift label thresholds, the
   executed commitment state and its 0.4 s minimum with hazard interruption,
   the executed drift preference, the 5 Hz sampling cadence, intent age
   arithmetic, the difficulty traffic ages, reset masking, zero safety
   deferral, the per-tick intervention window, emergency substitution
   coherence, BENCHMARKS correction materiality, distinct intent IDs,
   the source-observation linkage into the shipped observation fixtures,
   the null/unknowns pairing
   rule, context agreement, metric honesty (no measured status in a fixture
   file), metric comparator shape (threshold vs range vs report bounds) and
   the canonical content hash.
3. Runs every ``fixtures/intent/negative/*.json`` fixture and requires it to
   fail with exactly the failure set declared in its ``.expected.json``
   sidecar, so each documented rejection stays rejected.

Constants (5 Hz, 12-tick period, 0.4 s / 24-tick minimum commitment,
+/-1/3 and +/-0.25 thresholds, 18/12/7 traffic ages, materiality
thresholds) are read from the record schema's ``$defs.constants`` instead of
being restated here, so the schema is the single source of truth. The metric
comparator and status vocabulary is read from
``schemas/common.schema.json``'s ``$defs.acceptance_metric`` for the same
reason; only the threshold/range/report grouping is restated, because it is a
rule (common.schema.json's ``allOf``) rather than vocabulary.

The ``source_observation`` check reads the shipped positive observation
fixtures (``fixtures/observation/positive``) to resolve every
``source_observation_id``. That slice is read-only here: this validator never
writes to it and never assumes an observation record it does not find, so a
later change to the observation slice only changes which references resolve.

Deliberate limitations, mirroring tools/asset_manifest/manifest_validator.py:

* Standard library only, standalone. It does not run Godot, execute any
  intent, or measure anything; fixtures carry authored targets, never
  measurements.
* It cannot make unknown facts known. Unratified values stay null with an
  unknowns entry; the validator enforces the pairing, never fills values in.
* It validates fixture documents, not a runtime implementation. A green run
  means the contract and its fixtures agree, not that AI exists.

Usage::

    python3 validate_intent_contract.py                 # validate everything
    python3 validate_intent_contract.py --update-hashes  # (re)write content_hash
    python3 validate_intent_contract.py --schemas DIR --positive DIR --negative DIR
    python3 validate_intent_contract.py --observations DIR

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
import math
import re
import sys
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

# ---------------------------------------------------------------------------
# Contract constants
# ---------------------------------------------------------------------------

RECORD_SCHEMA_NAME = "tactical_intent.schema.json"
FIXTURE_SCHEMA_NAME = "intent_fixture.schema.json"
COMMON_SCHEMA_NAME = "common.schema.json"

# Record fields whose JSON null means "not yet determined": each null at one
# of these paths requires a matching entry in the fixture's unknowns array.
# Mirrors the descriptions in tactical_intent.schema.json.
NULL_REQUIRES_UNKNOWN = (
    "lateral.legal_corridor_half_width_m",
    "lateral.decoded_offset_m",
    "pace.speed_profile_interval_m_s",
    "pace.target_speed_m_s",
    "commitment.hold_window_s",
    "interpolation.curve",
)

# Semantic checks implemented here; intent_fixture.schema.json's expectation
# enum must stay equal to this set.
IMPLEMENTED_CHECKS = frozenset(
    {
        "decode_consistency",
        "pace_decode_consistency",
        "label_thresholds",
        "commitment_hold",
        "executed_drift_preference",
        "sampling_cadence",
        "age_arithmetic",
        "difficulty_age",
        "context_agreement",
        "reset_mask",
        "safety_deferral",
        "intervention_window",
        "emergency_consistency",
        "correction_materiality",
        "correction_shape",
        "intent_identity",
        "record_sequence",
        "source_observation",
        "min_commitment",
        "metric_status_honesty",
        "metric_shape",
        "unknown_pairing",
    }
)

STABLE_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_-]+)*$")
CONTENT_HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

# Metric comparator grouping, restated from the allOf rules of
# schemas/common.schema.json ($defs.acceptance_metric) and mirrored on
# schemas/handling/validate_fixtures.py so a metric cannot satisfy one
# contract and violate the other. The comparator/status *vocabulary* itself is
# read from that shared schema (see load_metric_vocabulary).
THRESHOLD_COMPARATORS = ("eq", "lte", "gte", "lt", "gt")
RANGE_COMPARATORS = ("range", "ratio_range")
# 'report' is the remaining shared comparator: it records without a threshold.
# common.schema.json also allows 'measured' because reference-run records need
# it; a fixture file never carries a measurement
# (schemas/intent/intent_fixture.schema.json, comparison.metrics).
MEASURED_STATUS = "measured"

TOLERANCE = 1e-9


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


def _reject_non_finite_constant(token: str) -> Any:
    """Refuse NaN/Infinity/-Infinity, which Python's json accepts but JSON does not."""
    raise DocumentError(f"{token} is not valid JSON (numbers must be finite)")


def load_json(path: Path) -> Any:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise DocumentError(f"cannot read {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        raise DocumentError(f"{path} is not valid UTF-8: {exc}") from exc
    try:
        return json.loads(
            text,
            object_pairs_hook=_reject_duplicate_members,
            parse_constant=_reject_non_finite_constant,
        )
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
    maximum, exclusiveMinimum, pattern, minLength. Every number instance must
    be finite: NaN/Infinity are not valid JSON and no comparison against them
    can be trusted (a NaN decoded target would satisfy ``minimum`` and every
    equality tolerance). Annotation keywords (title, description, examples,
    default, $schema, $defs, $comment) are ignored.
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
        if not math.isfinite(instance):
            failures.append(
                Failure(
                    "finite",
                    path,
                    f"{instance!r} is not finite; JSON numbers must be finite "
                    "(NaN/Infinity are not valid JSON)",
                )
            )
        else:
            if "minimum" in schema and instance < schema["minimum"]:
                failures.append(
                    Failure("minimum", path, f"below minimum {schema['minimum']}")
                )
            if "maximum" in schema and instance > schema["maximum"]:
                failures.append(
                    Failure("maximum", path, f"above maximum {schema['maximum']}")
                )
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
    """Contract constants, read from the schemas instead of restated here.

    ``tactical_rate_hz`` through ``traffic_age_ticks`` come from
    ``tactical_intent.schema.json``'s ``$defs.constants``; ``metric_vocabulary``
    comes from the shared ``$defs.acceptance_metric`` in
    ``schemas/common.schema.json``.
    """

    tactical_rate_hz: int
    sampling_period_ticks: int
    sampling_period_s: float
    intent_staleness_ticks: int
    commitment_min_s: float
    commitment_min_ticks: int
    safety_check_period_ticks: int
    commitment_follow_below: float
    commitment_commit_above: float
    drift_above: float
    drift_below: float
    lateral_margin_m: float
    material_lane_change_car_widths: float
    material_speed_change_fraction: float
    traffic_age_ticks: Mapping[str, int]
    metric_vocabulary: MetricVocabulary
    # Not a numeric constant: the shipped positive observation records, keyed
    # by observation_id, that the source_observation check resolves against.
    # Loaded read-only from the observation slice; it is carried here so every
    # semantic check keeps the (fixture, constants) signature.
    observation_sources: Mapping[str, Sequence[Mapping[str, Any]]] = dataclasses.field(
        default_factory=dict
    )


def load_constants(
    record_schema: Mapping[str, Any],
    metric_vocabulary: MetricVocabulary,
    observation_sources: Mapping[str, Sequence[Mapping[str, Any]]] | None = None,
) -> ContractConstants:
    props = record_schema["$defs"]["constants"]["properties"]
    ages = {
        difficulty: int(entry["const"])
        for difficulty, entry in props["traffic_age_ticks_by_difficulty"]["properties"].items()
    }
    return ContractConstants(
        tactical_rate_hz=int(props["tactical_rate_hz"]["const"]),
        sampling_period_ticks=int(props["sampling_period_ticks"]["const"]),
        sampling_period_s=float(props["sampling_period_s"]["const"]),
        intent_staleness_ticks=int(props["intent_staleness_ticks"]["const"]),
        commitment_min_s=float(props["commitment_min_s"]["const"]),
        commitment_min_ticks=int(props["commitment_min_ticks"]["const"]),
        safety_check_period_ticks=int(props["safety_check_period_ticks"]["const"]),
        commitment_follow_below=float(props["commitment_follow_below"]["const"]),
        commitment_commit_above=float(props["commitment_commit_above"]["const"]),
        drift_above=float(props["drift_above"]["const"]),
        drift_below=float(props["drift_below"]["const"]),
        lateral_margin_m=float(props["lateral_margin_m"]["const"]),
        material_lane_change_car_widths=float(props["material_lane_change_car_widths"]["const"]),
        material_speed_change_fraction=float(props["material_speed_change_fraction"]["const"]),
        traffic_age_ticks=ages,
        metric_vocabulary=metric_vocabulary,
        observation_sources=dict(observation_sources or {}),
    )


@dataclasses.dataclass(frozen=True)
class MetricVocabulary:
    """The acceptance-metric vocabulary, read from schemas/common.schema.json."""

    comparators: tuple[str, ...]
    statuses: tuple[str, ...]

    @property
    def fixture_statuses(self) -> tuple[str, ...]:
        """Statuses a fixture file may declare: everything except 'measured'."""
        return tuple(status for status in self.statuses if status != MEASURED_STATUS)


def load_metric_vocabulary(schemas_dir: Path) -> MetricVocabulary:
    """Read the comparator/status vocabulary from the shared schema.

    ``schemas_dir`` is the intent schema directory, so the shared vocabulary
    lives one level up in ``schemas/common.schema.json``. Reading it instead of
    restating it keeps this validator from drifting away from the handling and
    scenario slices that share ``$defs.acceptance_metric``.
    """
    path = schemas_dir.parent / COMMON_SCHEMA_NAME
    cache = SchemaCache()
    document = cache.document(path)
    defs = document.get("$defs")
    metric = defs.get("acceptance_metric") if isinstance(defs, Mapping) else None
    if not isinstance(metric, Mapping):
        raise DocumentError(f"{path} has no $defs.acceptance_metric definition")
    properties = metric.get("properties")
    if not isinstance(properties, Mapping):
        raise DocumentError(f"{path} $defs.acceptance_metric has no properties")

    def enum_of(member: str) -> Any:
        node = properties.get(member)
        return node.get("enum") if isinstance(node, Mapping) else None

    comparators = enum_of("comparator")
    statuses = enum_of("status")
    if not isinstance(comparators, list) or not comparators:
        raise DocumentError(f"{path} acceptance_metric.comparator has no enum")
    if not isinstance(statuses, list) or not statuses:
        raise DocumentError(f"{path} acceptance_metric.status has no enum")
    return MetricVocabulary(
        comparators=tuple(str(item) for item in comparators),
        statuses=tuple(str(item) for item in statuses),
    )


def load_observation_sources(
    observations_dir: Path,
) -> tuple[dict[str, list[Mapping[str, Any]]], list[str]]:
    """Index the shipped positive observation records by observation_id.

    The observation slice is read-only for this validator: only its positive
    fixtures define valid records (its negative fixtures are deliberately
    invalid and must never resolve a reference), and nothing here writes to
    that directory. An unreadable or unparseable positive file is reported by
    name instead of silently resolving to nothing, so a broken observation
    fixture cannot quietly turn every reference to it into a declared gap.
    """
    index: dict[str, list[Mapping[str, Any]]] = {}
    unreadable: list[str] = []
    if not observations_dir.is_dir():
        return index, unreadable
    for path in sorted(observations_dir.glob("*.json")):
        if path.name.endswith(".expected.json"):
            continue
        try:
            document = load_json(path)
        except DocumentError:
            unreadable.append(path.name)
            continue
        if not isinstance(document, Mapping):
            unreadable.append(path.name)
            continue
        records = document.get("records")
        if not isinstance(records, list):
            continue
        for record in records:
            if isinstance(record, Mapping) and isinstance(record.get("observation_id"), str):
                index.setdefault(record["observation_id"], []).append(record)
    return index, unreadable


# ---------------------------------------------------------------------------
# Semantic checks
# ---------------------------------------------------------------------------


def _is_number(value: Any) -> bool:
    """True for a JSON number; JSON booleans are not numbers here."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _record_path(index: int, suffix: str = "") -> str:
    return f"records.{index}" + (f".{suffix}" if suffix else "")


def _metric_path(index: int, suffix: str = "") -> str:
    return f"comparison.metrics.{index}" + (f".{suffix}" if suffix else "")


def _metric_entries(fixture: Mapping[str, Any]) -> list[tuple[int, Mapping[str, Any]]]:
    """The fixture's comparison.metrics entries as (index, metric) pairs."""
    comparison = fixture.get("comparison")
    if not isinstance(comparison, Mapping):
        return []
    metrics = comparison.get("metrics")
    if not isinstance(metrics, list):
        return []
    return [
        (index, metric)
        for index, metric in enumerate(metrics)
        if isinstance(metric, Mapping)
    ]


def check_context_agreement(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    context = fixture["context"]
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        producer = record["producer"]
        pairs = (
            ("difficulty", record["difficulty"], context["difficulty"]),
            ("style", record["style"], context["style"]),
            ("producer.kind", producer["kind"], context["producer_kind"]),
            (
                "producer.producer_revision",
                producer["producer_revision"],
                context["producer_revision"],
            ),
        )
        for field, actual, expected in pairs:
            if actual != expected:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, field),
                        f"{field} is {actual!r} but the fixture context declares {expected!r}",
                        check="context_agreement",
                    )
                )
    return failures


def check_decode_consistency(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    context = fixture["context"]
    road_width = float(context["road_width_m"])
    car_width = float(context["car_width_m"])
    corridor = (road_width - car_width) / 2.0 - constants.lateral_margin_m
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        lateral = record["lateral"]
        raw = float(lateral["lateral_target_norm"])
        proposed = raw * corridor
        declared_corridor = lateral["legal_corridor_half_width_m"]
        if declared_corridor is not None and abs(float(declared_corridor) - corridor) > TOLERANCE:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "lateral.legal_corridor_half_width_m"),
                    f"corridor half-width {declared_corridor} does not match "
                    f"(road_width - car_width)/2 - {constants.lateral_margin_m} m = {corridor}",
                    check="decode_consistency",
                )
            )
        corrections = [
            (position, entry)
            for position, entry in enumerate(record["safety"]["corrections"])
            if entry["field"] == "lateral.decoded_offset_m"
        ]
        decoded = lateral["decoded_offset_m"]
        if corrections:
            for position, entry in corrections:
                if abs(float(entry["proposed"]) - proposed) > TOLERANCE:
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, f"safety.corrections.{position}"),
                            f"proposed {entry['proposed']} is not the raw decode "
                            f"{proposed} of lateral_target_norm {raw}",
                            check="decode_consistency",
                        )
                    )
                if decoded is None:
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "lateral.decoded_offset_m"),
                            "a lateral correction was applied but decoded_offset_m is null",
                            check="decode_consistency",
                        )
                    )
                elif abs(float(entry["applied"]) - float(decoded)) > TOLERANCE:
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "lateral.decoded_offset_m"),
                            f"decoded_offset_m {decoded} does not match the applied "
                            f"correction value {entry['applied']}",
                            check="decode_consistency",
                        )
                    )
                if abs(float(entry["applied"])) > corridor + TOLERANCE:
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, f"safety.corrections.{position}"),
                            f"applied {entry['applied']} leaves the legal corridor "
                            f"+/-{corridor} m",
                            check="decode_consistency",
                        )
                    )
        elif decoded is not None:
            if abs(float(decoded) - proposed) > TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "lateral.decoded_offset_m"),
                        f"decoded_offset_m {decoded} is not the raw decode {proposed} "
                        f"of lateral_target_norm {raw} and no correction explains the difference",
                        check="decode_consistency",
                    )
                )
        if decoded is not None and abs(float(decoded)) > corridor + TOLERANCE:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "lateral.decoded_offset_m"),
                    f"decoded_offset_m {decoded} leaves the legal corridor +/-{corridor} m",
                    check="decode_consistency",
                )
            )
    return failures


def check_pace_decode_consistency(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Ordered pace interval, decoded target speed and speed-correction rules.

    OPPONENT_AI.md action 1 maps ``(a+1)/2`` into the selected difficulty's
    desired speed-profile interval, and action 2-style separation of proposed
    and executed values applies to pace as well. The per-difficulty intervals
    are tuned at M4.3, so every shipped fixture leaves them null; a record
    that does fix an interval must then be internally consistent:

    * the interval is ordered (min <= max);
    * the uncorrected ``target_speed_m_s`` is ``min + pace_norm*(max-min)``;
    * a pace correction's ``proposed`` is that same pre-safety decode and is
      nonnegative, and its ``applied`` is nonnegative (a speed target cannot
      be negative);
    * the corrected ``target_speed_m_s`` is the correction's applied value.

    A null interval forbids a determined target and any pace correction,
    because the pre-safety decode does not exist yet.
    """
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        pace = record.get("pace") or {}
        interval = pace.get("speed_profile_interval_m_s")
        target = pace.get("target_speed_m_s")
        pace_norm = pace.get("pace_norm")
        if not _is_number(pace_norm):
            continue  # the schema already bounds pace_norm; nothing to decode
        corrections = [
            (position, entry)
            for position, entry in enumerate(
                (record.get("safety") or {}).get("corrections") or []
            )
            if isinstance(entry, Mapping) and entry.get("field") == "pace.target_speed_m_s"
        ]
        if interval is None:
            if target is not None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "pace.target_speed_m_s"),
                        f"target speed {target} is determined but the difficulty "
                        "speed-profile interval is null (unratified until M4.3)",
                        check="pace_decode_consistency",
                    )
                )
            for position, _entry in corrections:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, f"safety.corrections.{position}"),
                        "a pace correction needs the pre-safety decode, which needs a "
                        "determined speed-profile interval",
                        check="pace_decode_consistency",
                    )
                )
            continue
        low = float(interval["min"])
        high = float(interval["max"])
        if low > high:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "pace.speed_profile_interval_m_s"),
                    f"speed-profile interval is inverted: min {low} m/s is above "
                    f"max {high} m/s",
                    check="pace_decode_consistency",
                )
            )
        decoded = low + float(pace_norm) * (high - low)
        for position, entry in corrections:
            proposed = entry.get("proposed")
            applied = entry.get("applied")
            if _is_number(proposed) and float(proposed) < 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, f"safety.corrections.{position}.proposed"),
                        f"a speed target cannot be negative: proposed {proposed} m/s",
                        check="pace_decode_consistency",
                    )
                )
            elif _is_number(proposed) and abs(float(proposed) - decoded) > TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, f"safety.corrections.{position}.proposed"),
                        f"proposed {proposed} m/s is not the pre-safety decode "
                        f"{decoded} m/s of pace_norm {pace_norm} into the interval "
                        f"[{low}, {high}] m/s",
                        check="pace_decode_consistency",
                    )
                )
            if _is_number(applied) and float(applied) < 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, f"safety.corrections.{position}.applied"),
                        f"a speed target cannot be negative: applied {applied} m/s",
                        check="pace_decode_consistency",
                    )
                )
            if target is None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "pace.target_speed_m_s"),
                        "a pace correction was applied but target_speed_m_s is null",
                        check="pace_decode_consistency",
                    )
                )
            elif _is_number(applied) and abs(float(target) - float(applied)) > TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "pace.target_speed_m_s"),
                        f"target speed {target} does not match the applied correction "
                        f"value {applied}",
                        check="pace_decode_consistency",
                    )
                )
        if not corrections:
            if target is None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "pace.target_speed_m_s"),
                        "the speed-profile interval is determined but target_speed_m_s "
                        "is null",
                        check="pace_decode_consistency",
                    )
                )
            elif abs(float(target) - decoded) > TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "pace.target_speed_m_s"),
                        f"target speed {target} is not the decode "
                        f"min + pace_norm x (max - min) = {decoded} m/s of the "
                        f"interval [{low}, {high}] m/s",
                        check="pace_decode_consistency",
                    )
                )
    return failures


def check_label_thresholds(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        commitment = record["commitment"]
        raw = float(commitment["commitment_raw"])
        if raw < constants.commitment_follow_below:
            expected = "follow"
        elif raw > constants.commitment_commit_above:
            expected = "commit_pass"
        else:
            expected = "wait"
        if commitment["label"] != expected:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "commitment.label"),
                    f"commitment_raw {raw} decodes to {expected!r}, not {commitment['label']!r}",
                    check="label_thresholds",
                )
            )
        drift = record["drift"]
        drift_raw = float(drift["drift_raw"])
        if drift_raw > constants.drift_above:
            drift_expected = "drift"
        elif drift_raw < constants.drift_below:
            drift_expected = "grip"
        else:
            drift_expected = "retain"
        if drift["label"] != drift_expected:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "drift.label"),
                    f"drift_raw {drift_raw} decodes to {drift_expected!r}, not {drift['label']!r}",
                    check="label_thresholds",
                )
            )
    return failures


def check_sampling_cadence(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    records = fixture["records"]
    failures: list[Failure] = []
    for index in range(1, len(records)):
        previous, current = records[index - 1], records[index]
        if int(current["sampled_tick"]) <= int(previous["sampled_tick"]):
            failures.append(
                Failure(
                    "semantic",
                    "records",
                    f"sampled_tick is not ascending at records.{index}",
                    check="sampling_cadence",
                )
            )
        gap = int(current["generated_tick"]) - int(previous["generated_tick"])
        if gap != constants.sampling_period_ticks:
            failures.append(
                Failure(
                    "semantic",
                    "records",
                    f"generated_tick gap between records.{index - 1} and records.{index} "
                    f"is {gap} ticks, expected {constants.sampling_period_ticks} "
                    f"({constants.tactical_rate_hz} Hz at 60 Hz)",
                    check="sampling_cadence",
                )
            )
    return failures


def check_age_arithmetic(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        expected = int(record["sampled_tick"]) - int(record["generated_tick"])
        if int(record["intent_age_ticks"]) != expected:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index),
                    f"intent_age_ticks {record['intent_age_ticks']} is not "
                    f"sampled_tick - generated_tick = {expected}",
                    check="age_arithmetic",
                )
            )
    return failures


def check_difficulty_age(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    if not fixture["context"]["traffic_age_is_difficulty_default"]:
        return failures
    for index, record in enumerate(fixture["records"]):
        expected = constants.traffic_age_ticks[record["difficulty"]]
        if int(record["traffic_age_ticks"]) != expected:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index),
                    f"traffic_age_ticks {record['traffic_age_ticks']} is not the "
                    f"{record['difficulty']} default {expected}",
                    check="difficulty_age",
                )
            )
    return failures


def check_reset_mask(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        reset = record["reset"]
        if reset["post_reset_defaults_applied"]:
            if int(reset["history_valid"]) != 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "reset"),
                        "post_reset_defaults_applied is true but history_valid is not 0",
                        check="reset_mask",
                    )
                )
            if int(reset["reset_generation"]) < 1:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "reset"),
                        "post_reset_defaults_applied is true but reset_generation is 0",
                        check="reset_mask",
                    )
                )
    return failures


def check_safety_deferral(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        if int(record["safety"]["max_deferral_ticks"]) != 0:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "safety"),
                    "a held intent must never defer hazard checks; "
                    f"max_deferral_ticks is {record['safety']['max_deferral_ticks']}",
                    check="safety_deferral",
                )
            )
    return failures


def check_correction_materiality(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    car_width = float(fixture["context"]["car_width_m"])
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        for position, entry in enumerate(record["safety"]["corrections"]):
            proposed = float(entry["proposed"])
            applied = float(entry["applied"])
            change = abs(applied - proposed)
            if entry["field"] == "lateral.decoded_offset_m":
                material = change > constants.material_lane_change_car_widths * car_width
                rule = (
                    f"lateral change {change} m vs threshold "
                    f"{constants.material_lane_change_car_widths} car widths "
                    f"({constants.material_lane_change_car_widths * car_width} m)"
                )
            else:
                material = change / max(proposed, 1.0) > constants.material_speed_change_fraction
                rule = (
                    f"relative speed-target change {change / max(proposed, 1.0)} vs threshold "
                    f"{constants.material_speed_change_fraction}"
                )
            if bool(entry["material"]) != material:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, f"safety.corrections.{position}"),
                        f"material is {entry['material']!r} but {rule}",
                        check="correction_materiality",
                    )
                )
    return failures


def check_correction_shape(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """One correction entry per corrected field.

    ``tactical_intent.schema.json`` describes ``safety.corrections`` as
    "Safety-layer changes to the proposed intent, one entry per corrected
    field". Two entries naming the same field would double-count one 5 Hz
    intent's correction in BENCHMARKS.md telemetry, and the record cannot
    represent two sequential corrections of one field anyway: a correction
    carries no tick (tick-level exposure lives in interventions) and every
    entry's applied value must equal the single decoded/executed field value.
    """
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        seen: set[str] = set()
        for entry in record["safety"]["corrections"]:
            field = entry["field"]
            if field in seen:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.corrections"),
                        f"field {field!r} has more than one correction entry; "
                        "the contract allows one entry per corrected field",
                        check="correction_shape",
                    )
                )
            else:
                seen.add(field)
    return failures


def check_min_commitment(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        commitment = record["commitment"]
        if abs(float(commitment["min_commitment_s"]) - constants.commitment_min_s) > TOLERANCE:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "commitment"),
                    f"min_commitment_s {commitment['min_commitment_s']} is not the "
                    f"specified {constants.commitment_min_s} s",
                    check="min_commitment",
                )
            )
    return failures


def check_commitment_hold(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Executed commitment state, the 0.4 s minimum and hazard interruption.

    ``commitment.label`` is the pure threshold decode of the proposed
    ``commitment_raw``; ``commitment.executed_label`` and
    ``commitment.commit_started_tick`` record what the safety layer and path
    follower actually ran (OPPONENT_AI.md: 'Record the proposed intent,
    ordinary difficulty decoding, safety changes and final commands
    separately'). The rules:

    * a commitment that starts at a record matches that record's proposed
      decode and starts at that record's generated_tick;
    * an executing commit_pass carries a non-null commit_started_tick at or
      before its generated_tick, and every other state carries null;
    * an executing commit_pass may not lapse before commitment_min_ticks
      (0.4 s) unless the record is interrupted, and a restart inside the
      minimum is an early lapse too;
    * an interruption requires a reason, and a reason requires an
      interruption.

    Fixture records are one participant's 5 Hz intent sequence, so the
    cross-record rules compare consecutive records.
    """
    min_ticks = constants.commitment_min_ticks
    failures: list[Failure] = []
    previous: Mapping[str, Any] | None = None
    for index, record in enumerate(fixture["records"]):
        commitment = record.get("commitment") or {}
        executed = commitment.get("executed_label")
        start = commitment.get("commit_started_tick")
        label = commitment.get("label")
        generated = record.get("generated_tick")
        interrupted = bool(commitment.get("interrupted"))
        reason = commitment.get("interruption_reason")
        if executed == "commit_pass":
            if start is None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "commitment.commit_started_tick"),
                        "executed_label is commit_pass but commit_started_tick is null",
                        check="commitment_hold",
                    )
                )
            elif _is_number(generated) and int(start) > int(generated):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "commitment.commit_started_tick"),
                        f"commit_started_tick {start} is after this intent's "
                        f"generated_tick {generated}",
                        check="commitment_hold",
                    )
                )
        elif start is not None:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "commitment.commit_started_tick"),
                    f"commit_started_tick {start} is set but executed_label is "
                    f"{executed!r}, not commit_pass",
                    check="commitment_hold",
                )
            )
        if interrupted and not reason:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "commitment.interruption_reason"),
                    "the commitment is interrupted but interruption_reason is null",
                    check="commitment_hold",
                )
            )
        if not interrupted and reason is not None:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "commitment.interruption_reason"),
                    "interruption_reason is set but the commitment is not interrupted",
                    check="commitment_hold",
                )
            )
        previous_commitment = (previous.get("commitment") or {}) if previous is not None else {}
        previous_executed = previous_commitment.get("executed_label")
        previous_start = previous_commitment.get("commit_started_tick")
        previous_generation = (previous.get("reset") or {}).get("reset_generation") if previous is not None else None
        current_generation = (record.get("reset") or {}).get("reset_generation")
        reset_boundary = (
            _is_number(previous_generation)
            and _is_number(current_generation)
            and int(current_generation) > int(previous_generation)
        )
        continuing = (
            executed == "commit_pass"
            and previous_start is not None
            and start == previous_start
            and not reset_boundary
        )
        if (
            interrupted
            and executed == "commit_pass"
            and previous_executed == "commit_pass"
            and previous_start is not None
            and start == previous_start
        ):
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "commitment.interrupted"),
                    "the record claims a hazard interruption while the same executing "
                    "commit_pass continues unchanged from the previous record; an "
                    "interruption must end or restart the commitment",
                    check="commitment_hold",
                )
            )
        if previous_executed == "commit_pass" and previous_start is not None and _is_number(generated):
            if reset_boundary and executed == "commit_pass" and start == previous_start:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "commitment.commit_started_tick"),
                        f"the executing commit_pass continues from tick {previous_start} "
                        f"across a reset_generation increase "
                        f"({previous_generation} -> {current_generation}); a reset "
                        "restores timers and history, so the commitment must end or "
                        "restart at this record",
                        check="commitment_hold",
                    )
                )
            elif not continuing:
                elapsed = int(generated) - int(previous_start)
                if elapsed < min_ticks and not interrupted and not reset_boundary:
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "commitment"),
                            f"the pass commitment lapsed after {elapsed} ticks "
                            f"({elapsed / 60:.3f} s), before the "
                            f"{constants.commitment_min_s} s minimum, without a "
                            "hazard interruption",
                            check="commitment_hold",
                        )
                    )
                if executed == "commit_pass":
                    # A restart: the previous commitment ended here and a new one
                    # begins at this decision tick.
                    if start is None or int(start) != int(generated):
                        failures.append(
                            Failure(
                                "semantic",
                                _record_path(index, "commitment.commit_started_tick"),
                                f"a restarted commitment must begin at this intent's "
                                f"generated_tick {generated}, not {start}",
                                check="commitment_hold",
                            )
                        )
                    if executed != label:
                        failures.append(
                            Failure(
                                "semantic",
                                _record_path(index, "commitment.executed_label"),
                                "a commitment that starts at this record must match the "
                                "threshold decode of commitment_raw",
                                check="commitment_hold",
                            )
                        )
        elif executed == "commit_pass" and _is_number(generated):
            if start is None or int(start) != int(generated):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "commitment.commit_started_tick"),
                        f"a new commitment must begin at this intent's generated_tick "
                        f"{generated}, not {start}",
                        check="commitment_hold",
                    )
                )
            if executed != label:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "commitment.executed_label"),
                        "a commitment that starts at this record must match the "
                        "threshold decode of commitment_raw; the hold rule applies "
                        "only to a commitment that is already executing",
                        check="commitment_hold",
                    )
                )
        previous = record
    return failures


def check_executed_drift_preference(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """The executed drift preference after 'retain' is resolved.

    ``drift.label`` records the decode band; ``drift.executed_preference``
    records the preference actually executed. Outside the retain band the
    two must agree. Inside it, 'retain' keeps the prior preference, except
    when the reset masked the history (history_valid 0 or
    post_reset_defaults_applied): then there is no prior preference and the
    executed value is 'none'.
    """
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        drift = record.get("drift") or {}
        label = drift.get("label")
        executed = drift.get("executed_preference")
        reset = record.get("reset") or {}
        masked = bool(reset.get("post_reset_defaults_applied")) or int(
            reset.get("history_valid", 1)
        ) == 0
        if label in ("drift", "grip") and executed != label:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "drift.executed_preference"),
                    f"drift label {label!r} decodes outside the retain band, so the "
                    f"executed preference is {label!r}, not {executed!r}",
                    check="executed_drift_preference",
                )
            )
        elif label == "retain":
            if masked:
                if executed != "none":
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "drift.executed_preference"),
                            "retain with masked post-reset history has no prior preference "
                            f"to keep, so the executed preference is 'none', not {executed!r}",
                            check="executed_drift_preference",
                        )
                    )
            elif executed == "none":
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "drift.executed_preference"),
                        "retain keeps the prior drift/grip preference while the history is "
                        "valid; 'none' is legal only when the reset masked the history",
                        check="executed_drift_preference",
                    )
                )
    return failures


def check_intervention_window(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Per-tick safety exposure stays inside the intent's hold window.

    ``safety.interventions.ticks`` lists the 60 Hz ticks at which immediate
    per-tick safety overrode this intent. They must be ascending and distinct
    and lie in ``[generated_tick, generated_tick + period_ticks)``, the window
    this 5 Hz intent covers, so tick-level exposure reconciles with the
    per-intent counting BENCHMARKS.md prescribes.
    """
    period = constants.sampling_period_ticks
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        ticks = (record.get("safety") or {}).get("interventions", {}).get("ticks")
        generated = record.get("generated_tick")
        if not isinstance(ticks, list) or not _is_number(generated):
            continue
        window_end = int(generated) + period
        previous_tick: int | None = None
        for tick in ticks:
            if not isinstance(tick, int) or isinstance(tick, bool):
                continue
            if previous_tick is not None and tick <= previous_tick:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.interventions.ticks"),
                        f"intervention ticks must be ascending and distinct; tick "
                        f"{tick} follows {previous_tick}",
                        check="intervention_window",
                    )
                )
            if tick < int(generated) or tick >= window_end:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.interventions.ticks"),
                        f"intervention tick {tick} is outside this intent's hold "
                        f"window [{int(generated)}, {window_end})",
                        check="intervention_window",
                    )
                )
            previous_tick = tick
    return failures


def check_emergency_consistency(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Emergency substitution/reset and Classic-fallback telemetry coherence.

    ``safety.emergency`` is where tick-linked replacement evidence lives,
    separate from the per-field corrections and from the 5 Hz intent identity
    used for deduplication:

    * substituted is true exactly when kind is set;
    * a substitution carries a reason and a tick inside this intent's hold
      window;
    * classic_fallback replaces a learned or cloning-only producer, never a
      Classic planner;
    * persistent is true exactly when the immediately preceding intent of this
      participant carries the same-kind substitution.
    """
    period = constants.sampling_period_ticks
    failures: list[Failure] = []
    previous: Mapping[str, Any] | None = None
    for index, record in enumerate(fixture["records"]):
        emergency = (record.get("safety") or {}).get("emergency") or {}
        substituted = bool(emergency.get("substituted"))
        kind = emergency.get("kind")
        tick = emergency.get("tick")
        persistent = bool(emergency.get("persistent"))
        reason = emergency.get("reason")
        generated = record.get("generated_tick")
        if substituted != (kind is not None):
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "safety.emergency.kind"),
                    f"substituted is {substituted!r} but kind is {kind!r}; the two "
                    "must agree",
                    check="emergency_consistency",
                )
            )
        if substituted:
            if not reason:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.reason"),
                        "an emergency substitution requires a reason",
                        check="emergency_consistency",
                    )
                )
            if kind == "classic_fallback" and (record.get("producer") or {}).get(
                "kind"
            ) == "classic_planner":
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.kind"),
                        "a Classic planner cannot fall back to Classic control; "
                        "classic_fallback replaces a learned or cloning-only producer",
                        check="emergency_consistency",
                    )
                )
            if tick is None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.tick"),
                        "an emergency substitution requires the tick it took effect",
                        check="emergency_consistency",
                    )
                )
            elif _is_number(generated) and not (
                int(generated) <= int(tick) < int(generated) + period
            ):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.tick"),
                        f"substitution tick {tick} is outside this intent's hold "
                        f"window [{int(generated)}, {int(generated) + period})",
                        check="emergency_consistency",
                    )
                )
            previous_emergency = (
                (previous.get("safety") or {}).get("emergency") or {}
                if previous is not None
                else {}
            )
            continues = bool(previous_emergency.get("substituted")) and (
                previous_emergency.get("kind") == kind
            )
            if persistent != continues:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.persistent"),
                        f"persistent is {persistent!r} but the previous intent "
                        f"{'continues' if continues else 'does not continue'} the "
                        f"same {kind!r} substitution",
                        check="emergency_consistency",
                    )
                )
        else:
            if tick is not None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.tick"),
                        "tick is set but nothing was substituted",
                        check="emergency_consistency",
                    )
                )
            if reason is not None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.reason"),
                        "reason is set but nothing was substituted",
                        check="emergency_consistency",
                    )
                )
            if persistent:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "safety.emergency.persistent"),
                        "persistent is true but nothing was substituted",
                        check="emergency_consistency",
                    )
                )
        previous = record
    return failures


def check_intent_identity(
    fixture: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """Distinct proposals in one fixture carry distinct intent_ids.

    ``intent_id`` is the identity BENCHMARKS 'AI metrics' uses to count
    material corrections and emergency replacements once per proposed 5 Hz
    intent (and ``safety.interventions.ticks`` is the tick-level exposure
    reported beside that count). Two records of one fixture are two distinct
    proposals, so sharing an ID would make that accounting collapse them.
    The checked scope is one fixture - a self-contained scenario run; a
    deployed capture stream must keep the same per-record uniqueness across
    every intent it counts together. No cross-run reuse rule is invented here
    because no document states one.
    """
    failures: list[Failure] = []
    seen: dict[str, int] = {}
    for index, record in enumerate(fixture["records"]):
        intent_id = record.get("intent_id")
        if not isinstance(intent_id, str):
            continue
        if intent_id in seen:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "intent_id"),
                    f"intent_id {intent_id!r} is already used by "
                    f"records.{seen[intent_id]}; intent identity counts each "
                    "proposed 5 Hz intent once (BENCHMARKS 'AI metrics'), so two "
                    "distinct proposals may not share an ID",
                    check="intent_identity",
                )
            )
        else:
            seen[intent_id] = index
    return failures


def check_record_sequence(
    fixture: Mapping[str, Any], constants: ContractConstants | None = None
) -> list[Failure]:
    """One fixture is one participant's ascending 5 Hz sequence.

    ``check_commitment_hold`` and the emergency-persistence rule compare
    consecutive records as the same car's state over time, so every record of
    a fixture must name the same ``participant_id``. ``reset_generation`` is
    the counter a reset advances; over a forward-moving intent sequence it
    cannot decrease. Both facts follow from the record semantics rather than
    from an invented schedule.
    """
    failures: list[Failure] = []
    first_participant_index: int | None = None
    first_participant: str | None = None
    last_generation_index: int | None = None
    last_generation: int | None = None
    for index, record in enumerate(fixture["records"]):
        participant = record.get("participant_id")
        if isinstance(participant, str):
            if first_participant is None:
                first_participant = participant
                first_participant_index = index
            elif participant != first_participant:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "participant_id"),
                        f"participant_id {participant!r} differs from "
                        f"records.{first_participant_index}'s {first_participant!r}; "
                        "commitment-hold and emergency-persistence rules compare "
                        "consecutive records as one participant's 5 Hz sequence",
                        check="record_sequence",
                    )
                )
        generation = (record.get("reset") or {}).get("reset_generation")
        if _is_number(generation):
            value = int(generation)
            if last_generation is not None and value < last_generation:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "reset.reset_generation"),
                        f"reset_generation {value} is lower than "
                        f"records.{last_generation_index}'s {last_generation}; the "
                        "reset counter advances with resets and cannot decrease "
                        "across a forward-moving intent sequence",
                        check="record_sequence",
                    )
                )
            else:
                last_generation = value
                last_generation_index = index
    return failures


def check_source_observation(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Every intent's source observation resolves and agrees.

    ``source_observation_id`` names a record of the accepted shared
    observation contract. When the ID resolves to a shipped positive
    observation record, the intent must agree with it on participant,
    difficulty, style, delayed traffic age, reset generation, history
    validity and route frame, and its ``generated_tick`` may neither precede
    the observation's ``sampled_tick`` nor lag it by more than one 5 Hz
    sampling period: GAME_DESIGN documents an additional 0-200 ms of 5 Hz
    planning phase latency, so an older source must still come from the
    current or immediately preceding tactical sample. Exact observation-to-
    decision synchrony is not specified, so equality is deliberately not
    required; ``traffic_age_ticks`` remains the source snapshot's age and the
    phase delay is the extra latency on top of it. The local section road width is
    deliberately not compared - observation features 14/19/24 describe the
    road 20/50/100 m ahead, which can differ from the scenario section's
    local width on a legitimately varying-width road; the local width stays
    under the decode/geometry rules. An ID that does not resolve is legal
    only when the fixture declares it in illustrative_sources, and declaring
    an ID that does resolve is itself a failure, so a broken reference stays
    distinguishable from an intentional illustration. Within one fixture each
    record uses its own source observation, including a declared illustrative
    one.
    """
    sources = constants.observation_sources
    declared: dict[str, Mapping[str, Any]] = {}
    for entry in fixture.get("illustrative_sources") or []:
        if isinstance(entry, Mapping) and isinstance(entry.get("observation_id"), str):
            declared[entry["observation_id"]] = entry
    failures: list[Failure] = []
    seen: dict[str, int] = {}
    for index, record in enumerate(fixture["records"]):
        source_id = record.get("source_observation_id")
        if not isinstance(source_id, str):
            continue
        matches = sources.get(source_id, [])
        if len(matches) > 1:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "source_observation_id"),
                    f"source observation {source_id!r} is ambiguous: it appears in "
                    f"{len(matches)} shipped observation records",
                    check="source_observation",
                )
            )
            continue
        if not matches:
            if source_id in declared:
                if source_id in seen:
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "source_observation_id"),
                            f"declared illustrative source observation {source_id!r} "
                            f"is already used by records.{seen[source_id]}; each 5 Hz "
                            "intent is computed from its own observation, and the "
                            "illustrative declaration does not relax that uniqueness",
                            check="source_observation",
                        )
                    )
                else:
                    seen[source_id] = index
                continue
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "source_observation_id"),
                    f"source observation {source_id!r} does not resolve to a shipped "
                    "observation record and is not declared in illustrative_sources",
                    check="source_observation",
                )
            )
            continue
        if source_id in declared:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "source_observation_id"),
                    f"source observation {source_id!r} is declared illustrative but "
                    "resolves to a shipped observation record; remove the declaration",
                    check="source_observation",
                )
            )
            continue
        if source_id in seen:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "source_observation_id"),
                    f"source observation {source_id!r} is already used by "
                    f"records.{seen[source_id]}; each 5 Hz intent is computed from "
                    "its own observation",
                    check="source_observation",
                )
            )
            continue
        seen[source_id] = index
        observation = matches[0]
        pairs = (
            ("participant_id", record.get("participant_id"), observation.get("participant_id")),
            ("difficulty", record.get("difficulty"), observation.get("difficulty")),
            ("style", record.get("style"), observation.get("style")),
            (
                "traffic_age_ticks",
                record.get("traffic_age_ticks"),
                observation.get("traffic_age_ticks"),
            ),
        )
        for field, actual, expected in pairs:
            if actual != expected:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, field),
                        f"{field} is {actual!r} but the source observation "
                        f"{source_id!r} records {expected!r}",
                        check="source_observation",
                    )
                )
        observation_reset = observation.get("reset") or {}
        observation_masks = observation.get("masks") or {}
        record_reset = record.get("reset") or {}
        if record_reset.get("reset_generation") != observation_reset.get("reset_generation"):
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "reset.reset_generation"),
                    f"reset_generation {record_reset.get('reset_generation')!r} is not "
                    f"the source observation's {observation_reset.get('reset_generation')!r}",
                    check="source_observation",
                )
            )
        if record_reset.get("history_valid") != observation_masks.get("history_valid"):
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "reset.history_valid"),
                    f"history_valid {record_reset.get('history_valid')!r} is not the "
                    f"source observation's {observation_masks.get('history_valid')!r}",
                    check="source_observation",
                )
            )
        observation_frame = observation.get("road_frame") or {}
        record_frame = record.get("road_frame") or {}
        for axis in ("forward", "right", "up"):
            if record_frame.get(axis) != observation_frame.get(axis):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, f"road_frame.{axis}"),
                        f"road_frame.{axis} is {record_frame.get(axis)!r} but the source "
                        f"observation records {observation_frame.get(axis)!r}",
                        check="source_observation",
                    )
                )
        generated = record.get("generated_tick")
        sampled = observation.get("sampled_tick")
        if _is_number(generated) and _is_number(sampled):
            delay = int(generated) - int(sampled)
            if delay < 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "generated_tick"),
                        f"generated_tick {generated} precedes the source "
                        f"observation's sampled_tick {sampled}",
                        check="source_observation",
                    )
                )
            elif delay > constants.sampling_period_ticks:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "generated_tick"),
                        f"generated_tick {generated} lags the source observation's "
                        f"sampled_tick {sampled} by {delay} ticks, beyond the "
                        f"{constants.sampling_period_s} s ("
                        f"{constants.sampling_period_ticks}-tick) 5 Hz planning "
                        "phase latency GAME_DESIGN documents; the source must be "
                        "the current or immediately preceding tactical sample",
                        check="source_observation",
                    )
                )
    return failures


def check_metric_status_honesty(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """A fixture file carries documented targets, never measured values.

    ``schemas/intent/intent_fixture.schema.json`` (comparison.metrics) and
    ``schemas/observation/observation_fixture.schema.json`` both state that a
    metric with status 'measured' is invalid in a fixture file; the shared
    ``acceptance_metric`` vocabulary still allows 'measured' because
    reference-run records need it. The fixture schema's rule lives only in
    prose, so it is enforced here.
    """
    legal = constants.metric_vocabulary.fixture_statuses
    failures: list[Failure] = []
    for index, metric in _metric_entries(fixture):
        status = metric.get("status")
        if status == MEASURED_STATUS:
            failures.append(
                Failure(
                    "semantic",
                    _metric_path(index, "status"),
                    "status 'measured' is invalid in a fixture file: fixtures carry "
                    "documented targets and reporting requirements, never measured "
                    "values; measured values belong to reference-run records",
                    check="metric_status_honesty",
                )
            )
        elif status not in legal:
            failures.append(
                Failure(
                    "semantic",
                    _metric_path(index, "status"),
                    f"status must be one of {list(legal)}, found {status!r}",
                    check="metric_status_honesty",
                )
            )
    return failures


def check_metric_shape(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Enforce which bound members each comparator may carry.

    The rules are the ``allOf`` clauses of ``schemas/common.schema.json``'s
    ``$defs.acceptance_metric``: threshold comparators (eq, lte, gte, lt, gt)
    require a numeric ``value`` and no range bounds; range/ratio_range require
    numeric ``value_min``/``value_max`` (ordered) and no ``value``; ``report``
    carries no bound at all. This validator's JSON Schema subset does not
    evaluate ``if``/``then``/``allOf``, so without this check a fixture could
    mix the point and range forms (or attach a threshold to a report) and
    still validate.
    """
    comparators = constants.metric_vocabulary.comparators
    failures: list[Failure] = []
    for index, metric in _metric_entries(fixture):
        comparator = metric.get("comparator")
        if comparator not in comparators:
            failures.append(
                Failure(
                    "semantic",
                    _metric_path(index, "comparator"),
                    f"comparator must be one of {list(comparators)}, found {comparator!r}",
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
                        _metric_path(index, "value"),
                        f"comparator {comparator!r} requires a numeric value",
                        check="metric_shape",
                    )
                )
            if value_min is not None or value_max is not None:
                failures.append(
                    Failure(
                        "semantic",
                        _metric_path(index, "value_min"),
                        "threshold comparators use value, not value_min/value_max",
                        check="metric_shape",
                    )
                )
        elif comparator in RANGE_COMPARATORS:
            if not _is_number(value_min) or not _is_number(value_max):
                failures.append(
                    Failure(
                        "semantic",
                        _metric_path(index),
                        f"comparator {comparator!r} requires numeric value_min and value_max",
                        check="metric_shape",
                    )
                )
            elif value_min >= value_max:
                failures.append(
                    Failure(
                        "semantic",
                        _metric_path(index),
                        "value_min must be smaller than value_max",
                        check="metric_shape",
                    )
                )
            if value is not None:
                failures.append(
                    Failure(
                        "semantic",
                        _metric_path(index, "value"),
                        "range comparators use value_min/value_max, not value",
                        check="metric_shape",
                    )
                )
        else:  # report
            if value is not None or value_min is not None or value_max is not None:
                failures.append(
                    Failure(
                        "semantic",
                        _metric_path(index),
                        "comparator 'report' records without declaring a pass/fail "
                        "threshold; remove value/value_min/value_max",
                        check="metric_shape",
                    )
                )
    return failures


def check_unknown_pairing(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    unknown_paths = {
        entry["path"] for entry in fixture.get("unknowns", []) if isinstance(entry, Mapping)
    }
    for index, record in enumerate(fixture["records"]):
        for field in NULL_REQUIRES_UNKNOWN:
            container: Any = record
            for token in field.split("."):
                container = container[token] if isinstance(container, Mapping) else None
                if container is None:
                    break
            dotted = f"records.{index}.{field}"
            if container is None and dotted not in unknown_paths:
                failures.append(
                    Failure(
                        "semantic",
                        dotted,
                        "null means 'not yet determined' but has no unknowns entry",
                        check="unknown_pairing",
                    )
                )
            if container is not None and dotted in unknown_paths:
                failures.append(
                    Failure(
                        "semantic",
                        dotted,
                        "has an unknowns entry but carries a determined value",
                        check="unknown_pairing",
                    )
                )
    return failures


def check_expectations_declared(fixture: Mapping[str, Any]) -> list[Failure]:
    failures: list[Failure] = []
    record_count = len(fixture["records"])
    metric_count = len(_metric_entries(fixture))
    for index, expectation in enumerate(fixture.get("expectations", [])):
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
        if path == "records":
            continue
        record_match = re.fullmatch(r"records\.(\d+)", path)
        if record_match:
            if int(record_match.group(1)) >= record_count:
                failures.append(
                    Failure(
                        "semantic",
                        f"expectations.{index}.path",
                        f"path {path!r} does not reference a record in this fixture",
                        check="expectation_implemented",
                    )
                )
            continue
        if path in ("comparison", "comparison.metrics"):
            continue
        metric_match = re.fullmatch(r"comparison\.metrics\.(\d+)", path)
        if metric_match:
            if int(metric_match.group(1)) >= metric_count:
                failures.append(
                    Failure(
                        "semantic",
                        f"expectations.{index}.path",
                        f"path {path!r} does not reference a metric in this fixture",
                        check="expectation_implemented",
                    )
                )
            continue
        failures.append(
            Failure(
                "semantic",
                f"expectations.{index}.path",
                f"path {path!r} does not reference a record or metric in this fixture",
                check="expectation_implemented",
            )
        )
    return failures


def check_content_hash(fixture: Mapping[str, Any]) -> list[Failure]:
    recorded = fixture.get("content_hash")
    if not isinstance(recorded, str) or not CONTENT_HASH_RE.match(recorded):
        return [
            Failure(
                "semantic",
                "content_hash",
                f"must look like 'sha256:<64 lowercase hex>', found {recorded!r}",
                check="content_hash",
            )
        ]
    actual = canonical_hash(fixture)
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


SEMANTIC_CHECKS = (
    check_context_agreement,
    check_decode_consistency,
    check_pace_decode_consistency,
    check_label_thresholds,
    check_commitment_hold,
    check_executed_drift_preference,
    check_sampling_cadence,
    check_age_arithmetic,
    check_difficulty_age,
    check_reset_mask,
    check_safety_deferral,
    check_intervention_window,
    check_emergency_consistency,
    check_correction_materiality,
    check_correction_shape,
    check_intent_identity,
    check_record_sequence,
    check_source_observation,
    check_min_commitment,
    check_metric_status_honesty,
    check_metric_shape,
    check_unknown_pairing,
)


# ---------------------------------------------------------------------------
# Fixture pipelines
# ---------------------------------------------------------------------------


@dataclasses.dataclass
class Contracts:
    fixture_schema: Mapping[str, Any]
    record_schema: Mapping[str, Any]
    constants: ContractConstants
    schemas_dir: Path
    observation_sources: Mapping[str, Sequence[Mapping[str, Any]]]
    unreadable_observations: Sequence[str] = ()


def load_contracts(schemas_dir: Path, observations_dir: Path | None = None) -> Contracts:
    cache = SchemaCache()
    fixture_schema = cache.document(schemas_dir / FIXTURE_SCHEMA_NAME)
    record_schema = cache.document(schemas_dir / RECORD_SCHEMA_NAME)
    if not isinstance(fixture_schema, Mapping) or not isinstance(record_schema, Mapping):
        raise DocumentError("schema documents must be JSON objects")
    if observations_dir is None:
        # schemas/intent -> <repo>/fixtures/observation
        observations_dir = schemas_dir.parents[1] / "fixtures" / "observation" / "positive"
    observation_sources, unreadable = load_observation_sources(observations_dir)
    return Contracts(
        fixture_schema=fixture_schema,
        record_schema=record_schema,
        constants=load_constants(record_schema, load_metric_vocabulary(schemas_dir), observation_sources),
        schemas_dir=schemas_dir,
        observation_sources=observation_sources,
        unreadable_observations=tuple(unreadable),
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

    failures.extend(check_expectations_declared(document))
    for check in SEMANTIC_CHECKS:
        failures.extend(check(document, contracts.constants))
    failures.extend(check_content_hash(document))
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


def update_hashes(positive_dir: Path) -> int:
    updated = 0
    for path in sorted(positive_dir.glob("*.json")):
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
        description="Validate Roadstorm tactical-intent fixtures against schemas/intent."
    )
    parser.add_argument(
        "--schemas",
        type=Path,
        default=here.parents[1] / "schemas" / "intent",
        help="directory holding tactical_intent.schema.json and intent_fixture.schema.json",
    )
    parser.add_argument(
        "--positive", type=Path, default=here / "positive", help="directory of valid fixtures"
    )
    parser.add_argument(
        "--negative", type=Path, default=here / "negative", help="directory of invalid fixtures"
    )
    parser.add_argument(
        "--observations",
        type=Path,
        default=here.parent / "observation" / "positive",
        help="directory of valid observation fixtures the source_observation check "
        "resolves source_observation_id against (read-only)",
    )
    parser.add_argument(
        "--update-hashes",
        action="store_true",
        help="recompute and write content_hash for positive fixtures, then exit",
    )
    args = parser.parse_args(argv)

    if args.update_hashes:
        changed = update_hashes(args.positive)
        print(f"content_hash update complete ({changed} file(s) written)")
        return 0

    try:
        contracts = load_contracts(args.schemas, args.observations)
    except DocumentError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    for name in contracts.unreadable_observations:
        print(
            f"warning: observation fixture {name} could not be read; references to "
            "its records cannot resolve",
            file=sys.stderr,
        )

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
