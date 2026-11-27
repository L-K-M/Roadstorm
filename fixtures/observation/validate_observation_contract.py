#!/usr/bin/env python3
"""Roadstorm shared AI-observation contract validator.

Ownership: fixtures/observation/** together with schemas/observation/**
(PLAN.md M0.9, job 8667d71d-5817-4955-b069-aed859c8d8f8).

This module is the executable form of the two text contracts in
``schemas/observation/``:

* ``observation_record.schema.json`` - the versioned AIObservation record
  contract (fields, the ordered 64-feature layout, masks, age and reset
  semantics, normalization coefficients) from docs/OPPONENT_AI.md and
  docs/TECHNICAL_DESIGN.md;
* ``observation_fixture.schema.json`` - the fixture wrapper that fixes one
  scenario and declares behavioral expectations.

It does three jobs a plain JSON Syntax check cannot:

1. Validates every ``fixtures/observation/positive/*.json`` fixture against
   the fixture schema (which pulls in the record schema by ``$ref``) with a
   small standard-library JSON Schema evaluator - no third-party packages, no
   installs, no network.
2. Runs the semantic checks that make the contract meaningful rather than
   merely well-formed: difficulty/style one-hot encoding against the declared
   inputs, neighbor presence masks / absent-slot zeroing / present-as-prefix /
   ascending-gap ordering (including the stable-participant-ID tie order when
   the record carries the optional diagnostic neighbor_ids list), the declared
   70 m ahead / 35 m behind neighbor window, the declared per-feature kinds and
   ranges from feature_layout, traffic-age arithmetic and the difficulty age,
   reset history masking including the reset defaults list, canonical
   raw_inputs keys (a decimal index string naming each index at most once, so
   an aliased key cannot satisfy one check while bypassing another),
   normalization consistency of every raw_inputs probe against the schema's
   coefficients and the fixture context, safe-fallback defaults, context
   agreement, the null/unknowns pairing rule (also for an omitted optional
   field), the acceptance-metric status/shape rules (comparator-bound
   agreement and no 'measured' metric in a fixture file), and the canonical
   content hash.
3. Runs every ``fixtures/observation/negative/*.json`` fixture and requires it
   to fail with exactly the failure set declared in its ``.expected.json``
   sidecar, so each documented rejection stays rejected.

Constants (64 features, 5 Hz / 12-tick cadence, 18/12/7 traffic ages, the
70 m / 35 m neighbor window, every normalization divisor/multiplier) and the
ordered feature layout are read from the record schema instead of being
restated here, so the schema is the single source of truth. (The 2 s
history_recent_window_s constant describes a producer-side window that no
fixture field can express, so it is documented rather than enforced.)

Documents are strict JSON: NaN, Infinity and -Infinity are rejected at parse
time (Python's json accepts them as an extension; JSON itself does not), and
the schema evaluator refuses non-finite numbers in memory.

Deliberate limitations, mirroring tools/asset_manifest/manifest_validator.py
and fixtures/intent/validate_intent_contract.py:

* Standard library only, standalone. It does not run Godot, execute any
  policy, or measure anything; fixtures carry authored illustrative values,
  never measurements.
* It cannot make unknown facts known. Unratified values stay null with an
  unknowns entry; the validator enforces the pairing, never fills values in.
* It validates fixture documents, not a runtime observation builder. A green
  run means the contract and its fixtures agree, not that an AI exists.

Usage::

    python3 validate_observation_contract.py                 # validate everything
    python3 validate_observation_contract.py --update-hashes  # (re)write content_hash
    python3 validate_observation_contract.py --schemas DIR --positive DIR --negative DIR

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
from typing import Any, Mapping, Sequence

# ---------------------------------------------------------------------------
# Contract constants
# ---------------------------------------------------------------------------

RECORD_SCHEMA_NAME = "observation_record.schema.json"
FIXTURE_SCHEMA_NAME = "observation_fixture.schema.json"
COMMON_SCHEMA_NAME = "common.schema.json"

# Acceptance-metric vocabulary subsets (schemas/common.schema.json
# $defs.acceptance_metric): threshold comparators carry a point value,
# range/ratio_range carry ordered bounds, report carries no bound.
THRESHOLD_COMPARATORS = ("eq", "lte", "gte", "lt", "gt")
RANGE_COMPARATORS = ("range", "ratio_range")
MEASURED_STATUS = "measured"

# A canonical raw_inputs key: the decimal index string with no leading zeros,
# sign or whitespace ("0", "1", ... "63"). Anything else ("027", " 27",
# "+27", "27.0", "fast") is rejected, and two keys that int() to the same index
# are a duplicate probe.
RAW_INPUT_KEY_RE = re.compile(r"^(?:0|[1-9][0-9]*)$")

# Record fields whose JSON null means "not yet determined": each null at one
# of these paths requires a matching entry in the fixture's unknowns array.
NULL_REQUIRES_UNKNOWN = (
    "occupancy_encounter_gap_m",
)

# Semantic checks implemented here; observation_fixture.schema.json's
# expectation enum must stay equal to this set.
IMPLEMENTED_CHECKS = frozenset(
    {
        "context_agreement",
        "difficulty_one_hot",
        "style_one_hot",
        "neighbor_presence",
        "neighbor_ordering",
        "neighbor_window",
        "feature_declared_ranges",
        "traffic_age_arithmetic",
        "difficulty_age",
        "history_mask",
        "normalization_consistency",
        "raw_input_keys",
        "fallback_defaults",
        "unknown_pairing",
        "metric_status_honesty",
        "metric_shape",
    }
)

STABLE_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_-]+)*$")
CONTENT_HASH_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

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
    additionalProperties (both ``false`` and a subschema), properties, items,
    minItems, maxItems, minimum, maximum, exclusiveMinimum, pattern,
    minLength. Annotation keywords (title, description, examples, default,
    $schema, $defs, $comment) are ignored, as is any non-schema data member
    (e.g. the record schema's feature_layout). Every number instance must be
    finite: NaN/Infinity are not valid JSON.
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
        additional = schema.get("additionalProperties")
        if additional is False:
            for key in instance:
                if key not in properties:
                    failures.append(
                        Failure(
                            "additionalProperties",
                            f"{path}.{key}" if path else key,
                            f"member {key!r} is not allowed",
                        )
                    )
        elif isinstance(additional, Mapping):
            # Schema form (e.g. raw_inputs' {"type": "number"}): every member
            # not named in properties must validate against the subschema.
            for key, value in instance.items():
                if key in properties:
                    continue
                child = f"{path}.{key}" if path else key
                validate_node(additional, value, child, context, failures, cache)
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
# Contract constants and feature layout, read from the record schema
# ---------------------------------------------------------------------------


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

    ``schemas_dir`` is the observation schema directory, so the shared
    vocabulary lives one level up in ``schemas/common.schema.json``. Reading
    it instead of restating it keeps this validator from drifting away from
    the handling, intent and scenario slices that share
    ``$defs.acceptance_metric`` and re-implement its ``allOf`` rules
    semantically.
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


@dataclasses.dataclass(frozen=True)
class ContractConstants:
    clip_min: float
    clip_max: float
    feature_count: int
    neighbor_slot_count: int
    neighbor_slot_size: int
    neighbor_ahead_m: float
    neighbor_behind_m: float
    traffic_age_ticks: Mapping[str, int]
    normalization_scales: Mapping[str, float]
    features: tuple[Mapping[str, Any], ...]
    feature_names: frozenset[str]
    group_names: frozenset[str]
    difficulty_hot: Mapping[str, int]
    style_hot: Mapping[str, int]
    presence_indices: tuple[int, ...]
    route_gap_indices: tuple[int, ...]
    history_indices: tuple[int, ...]
    metric_vocabulary: MetricVocabulary


def load_constants(
    record_schema: Mapping[str, Any], metric_vocabulary: MetricVocabulary
) -> ContractConstants:
    props = record_schema["$defs"]["constants"]["properties"]
    ages = {
        difficulty: int(entry["const"])
        for difficulty, entry in props["traffic_age_ticks_by_difficulty"]["properties"].items()
    }
    scales = {
        name: float(entry["const"])
        for name, entry in props["normalization_scales"]["properties"].items()
    }
    layout = record_schema["feature_layout"]
    features = layout["features"]
    feature_count = int(props["feature_count"]["const"])
    if len(features) != feature_count or [f["index"] for f in features] != list(range(feature_count)):
        raise DocumentError(
            "record schema feature_layout must list exactly "
            f"{feature_count} features with indices 0..{feature_count - 1}"
        )
    by_name = {f["name"]: f for f in features}
    groups = layout["groups"]
    slot_count = int(props["neighbor_slot_count"]["const"])
    neighbor_group = next((g for g in groups if g["name"] == "neighbor"), None)
    if neighbor_group is None or int(neighbor_group["count"]) % slot_count != 0:
        raise DocumentError(
            "record schema feature_layout must have a neighbor group whose count "
            f"divides evenly into neighbor_slot_count {slot_count}"
        )
    # Six features per neighbor slot, derived from the layout instead of being
    # restated here (the schema stays the single source of truth).
    neighbor_slot_size = int(neighbor_group["count"]) // slot_count

    def hot(group: str) -> dict[str, int]:
        mapping: dict[str, int] = {}
        for feature in features:
            if feature["group"] == group:
                label = feature["name"].split("_", 1)[1]
                mapping[label] = int(feature["index"])
        return mapping

    difficulty_hot = hot("difficulty_one_hot")
    style_hot = hot("style_one_hot")
    presence = tuple(
        int(f["index"]) for f in features
        if f["group"] == "neighbor" and f["name"].endswith("_presence")
    )
    route_gap = tuple(
        int(f["index"]) for f in features
        if f["group"] == "neighbor" and f["name"].endswith("_route_gap")
    )
    history = tuple(int(f["index"]) for f in features if f["group"] == "history")
    # Named convenience indices used by the history/reset checks.
    _ = by_name  # kept for readability; checks address indices by group.
    return ContractConstants(
        clip_min=float(props["clip_min"]["const"]),
        clip_max=float(props["clip_max"]["const"]),
        feature_count=feature_count,
        neighbor_slot_count=slot_count,
        neighbor_slot_size=neighbor_slot_size,
        neighbor_ahead_m=float(props["neighbor_ahead_m"]["const"]),
        neighbor_behind_m=float(props["neighbor_behind_m"]["const"]),
        traffic_age_ticks=ages,
        normalization_scales=scales,
        features=tuple(features),
        feature_names=frozenset(str(f["name"]) for f in features),
        group_names=frozenset(str(g["name"]) for g in groups),
        difficulty_hot=difficulty_hot,
        style_hot=style_hot,
        presence_indices=presence,
        route_gap_indices=route_gap,
        history_indices=history,
        metric_vocabulary=metric_vocabulary,
    )


# ---------------------------------------------------------------------------
# Semantic checks
# ---------------------------------------------------------------------------


def _record_path(index: int, suffix: str = "") -> str:
    return f"records.{index}" + (f".{suffix}" if suffix else "")


def _clip(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def _is_number(value: Any) -> bool:
    """True for a JSON number; JSON booleans are not numbers here."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


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


def _canonical_raw_probes(record: Mapping[str, Any]) -> dict[int, Any]:
    """The record's raw_inputs entries keyed by feature index.

    Only canonical keys are returned: a non-canonical key is rejected by
    check_raw_input_keys, and the consumers here deliberately ignore it so one
    defect produces one failure set instead of cascading. Callers therefore
    never look an index up under an alias.
    """
    raw_inputs = record.get("raw_inputs")
    if not isinstance(raw_inputs, Mapping):
        return {}
    return {
        int(key): value
        for key, value in raw_inputs.items()
        if isinstance(key, str) and RAW_INPUT_KEY_RE.match(key)
    }


def check_context_agreement(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    context = fixture["context"]
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        pairs = (
            ("difficulty", record["difficulty"], context["difficulty"]),
            ("style", record["style"], context["style"]),
            ("participant_id", record["participant_id"], context["participant_id"]),
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


def check_difficulty_one_hot(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        hot = {label: vector[idx] for label, idx in constants.difficulty_hot.items()}
        set_labels = [label for label, value in hot.items() if value == 1]
        non_binary = [label for label, value in hot.items() if value not in (0, 1)]
        if non_binary:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index),
                    f"difficulty one-hot has non 0/1 entries {non_binary}",
                    check="difficulty_one_hot",
                )
            )
        if set_labels != [record["difficulty"]]:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index),
                    f"difficulty one-hot encodes {set_labels or ['<none>']} but the "
                    f"declared difficulty is {record['difficulty']!r}",
                    check="difficulty_one_hot",
                )
            )
    return failures


def check_style_one_hot(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        style = record["style"]
        surge_idx = constants.style_hot["surge"]
        switch_idx = constants.style_hot["switch"]
        surge = vector[surge_idx]
        switch = vector[switch_idx]
        if surge not in (0, 1) or switch not in (0, 1):
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index),
                    "style one-hot entries must be 0/1",
                    check="style_one_hot",
                )
            )
            continue
        if style == "surge":
            ok = surge == 1 and switch == 0
        elif style == "switch":
            ok = surge == 0 and switch == 1
        else:  # Classic-only style input pair 0/0
            ok = surge == 0 and switch == 0
        if not ok:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index),
                    f"style one-hot is (surge={surge}, switch={switch}) but the "
                    f"declared style is {style!r}",
                    check="style_one_hot",
                )
            )
    return failures


def check_neighbor_presence(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    slot_count = constants.neighbor_slot_count
    slot_size = constants.neighbor_slot_size  # features per neighbor slot, from the layout
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        presence = [vector[idx] for idx in constants.presence_indices]
        declared = record["masks"]["neighbor_slots"]
        for slot in range(slot_count):
            mask = presence[slot]
            if mask not in (0, 1):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        f"neighbor slot {slot} presence mask is {mask}, not 0/1",
                        check="neighbor_presence",
                    )
                )
                continue
            if float(declared[slot]) != float(mask):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "masks.neighbor_slots"),
                        f"neighbor_slots[{slot}] is {declared[slot]} but the in-vector "
                        f"presence mask is {mask}",
                        check="neighbor_presence",
                    )
                )
            if mask == 0:
                base = constants.presence_indices[slot] - (slot_size - 1)
                nonzero = [
                    base + offset
                    for offset in range(slot_size)
                    if vector[base + offset] != 0
                ]
                if nonzero:
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "feature_vector"),
                            f"neighbor slot {slot} is absent (presence mask 0) but "
                            f"features {nonzero} are not zero",
                            check="neighbor_presence",
                        )
                    )
        # Present neighbors form a prefix of the slots (fill sorted present
        # neighbors first, then zero the rest), so no present slot may follow
        # an absent one.
        seen_absent = False
        for slot in range(slot_count):
            present = presence[slot] == 1
            if seen_absent and present:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "masks.neighbor_slots"),
                        f"neighbor slot {slot} is present after an absent slot; "
                        "present neighbors must fill the slots in order",
                        check="neighbor_presence",
                    )
                )
            if presence[slot] == 0:
                seen_absent = True
    return failures


def check_neighbor_ordering(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Present neighbors are sorted by absolute route gap, then stable ID.

    OPPONENT_AI.md sorts neighbor candidates 'by absolute gap then stable
    participant ID'. The feature vector carries the gaps (clipped), so the gap
    order is always checked. The stable-ID tie-break is checkable only when the
    record carries the optional diagnostic neighbor_ids list; when it does, the
    list must name one ID per present slot in slot order and equal absolute
    gaps must appear in ascending stable-ID order. A pinned raw_inputs gap is
    authoritative for the decoded magnitude, exactly as in
    check_neighbor_window; otherwise the clipped feature value is all the
    record expresses, so two features decoding equal are treated as a tie.
    """
    failures: list[Failure] = []
    gap_scale = float(constants.normalization_scales["neighbor_gap_scale_m"])
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        probes = _canonical_raw_probes(record)
        present = [
            slot
            for slot, presence_idx in enumerate(constants.presence_indices)
            if vector[presence_idx] == 1
        ]
        gaps: list[float] = []
        for slot in present:
            gap_idx = constants.route_gap_indices[slot]
            raw = probes.get(gap_idx)
            if _is_number(raw):
                gaps.append(abs(float(raw)))
            else:
                gaps.append(abs(float(vector[gap_idx]) * gap_scale))
        for position in range(1, len(gaps)):
            if gaps[position] < gaps[position - 1] - TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        "present neighbors are not sorted by ascending absolute route "
                        f"gap: {gaps}",
                        check="neighbor_ordering",
                    )
                )
                break
        neighbor_ids = record.get("neighbor_ids")
        if neighbor_ids is None:
            continue
        if not isinstance(neighbor_ids, list) or not all(
            isinstance(item, str) for item in neighbor_ids
        ):
            # The record schema enforces this shape; kept defensive so a direct
            # call cannot crash on a malformed record.
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "neighbor_ids"),
                    "neighbor_ids must be an array of stable participant ID strings",
                    check="neighbor_ordering",
                )
            )
            continue
        if len(neighbor_ids) != len(present):
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "neighbor_ids"),
                    f"neighbor_ids lists {len(neighbor_ids)} IDs but {len(present)} "
                    "neighbor slots are present; the diagnostic list carries one ID "
                    "per present slot, in slot order",
                    check="neighbor_ordering",
                )
            )
            continue
        if len(set(neighbor_ids)) != len(neighbor_ids):
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "neighbor_ids"),
                    "neighbor_ids repeats a stable participant ID; each present slot "
                    "names a different neighbor (a car cannot be its own neighbor "
                    "twice)",
                    check="neighbor_ordering",
                )
            )
        for position in range(1, len(present)):
            if (
                abs(gaps[position] - gaps[position - 1]) <= TOLERANCE
                and neighbor_ids[position] < neighbor_ids[position - 1]
            ):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "neighbor_ids"),
                        f"neighbor slots {position - 1} and {position} have equal "
                        f"absolute route gap {gaps[position]:g} m but their diagnostic "
                        f"IDs are out of order: {neighbor_ids[position - 1]!r} then "
                        f"{neighbor_ids[position]!r}; OPPONENT_AI.md breaks absolute-gap "
                        "ties by ascending stable participant ID",
                        check="neighbor_ordering",
                    )
                )
                break
    return failures


def check_neighbor_window(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Present neighbors must lie inside the declared route-neighborhood window.

    The window (70 m ahead, 35 m behind) is read from the record schema's
    $defs.constants, so it is enforced rather than merely documented. The gap
    feature is clip(gap / 70), so a gap decoded from the feature value alone is
    ambiguous only where clipping saturates it; when raw_inputs pins the
    pre-normalization gap it is authoritative. Only canonically keyed probes
    count: an aliased key is rejected by check_raw_input_keys and must not be
    able to stand in for the canonical lookup here.
    """
    failures: list[Failure] = []
    ahead = constants.neighbor_ahead_m
    behind = constants.neighbor_behind_m
    gap_scale = float(constants.normalization_scales["neighbor_gap_scale_m"])
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        probes = _canonical_raw_probes(record)
        for slot, (gap_idx, presence_idx) in enumerate(
            zip(constants.route_gap_indices, constants.presence_indices)
        ):
            if vector[presence_idx] != 1:
                continue
            raw = probes.get(gap_idx)
            if isinstance(raw, (int, float)) and not isinstance(raw, bool):
                gap_m = float(raw)
                source = "raw_inputs"
            else:
                gap_m = float(vector[gap_idx]) * gap_scale
                source = "feature value"
            if gap_m > ahead + TOLERANCE or gap_m < -behind - TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        f"neighbor slot {slot} route gap is {gap_m} m ({source}), outside the "
                        f"declared window {behind} m behind to {ahead} m ahead",
                        check="neighbor_window",
                    )
                )
    return failures


def check_feature_declared_ranges(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Every feature_vector entry must satisfy its feature_layout declaration.

    The record schema promises booleans/one-hots/flags are 0/1 and occupancy
    fractions are clipped to [0,1], and each layout entry declares its kind and
    range; this check enforces the declared kind and range per index instead of
    trusting the author. kind: boolean/one_hot are 0/1, signed_enum is
    -1/0/1, and every other kind must sit inside its declared range (which for
    ratio features is the physical clipping range, e.g. [0,1] for widths,
    cooldowns and grip).
    """
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        for feature in constants.features:
            idx = int(feature["index"])
            value = vector[idx]
            kind = feature["kind"]
            declared = feature.get("range") or [constants.clip_min, constants.clip_max]
            lo, hi = float(declared[0]), float(declared[1])
            if not math.isfinite(value):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "feature_vector"),
                        f"feature {idx} ({feature['name']}) is {value!r}; features must be finite",
                        check="feature_declared_ranges",
                    )
                )
                continue
            if kind in ("boolean", "one_hot"):
                if value not in (0, 1):
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "feature_vector"),
                            f"feature {idx} ({feature['name']}) is kind {kind!r} and must be "
                            f"0/1, found {value}",
                            check="feature_declared_ranges",
                        )
                    )
            elif kind == "signed_enum":
                if value not in (-1, 0, 1):
                    failures.append(
                        Failure(
                            "semantic",
                            _record_path(index, "feature_vector"),
                            f"feature {idx} ({feature['name']}) is a signed enum and must be "
                            f"-1/0/1, found {value}",
                            check="feature_declared_ranges",
                        )
                    )
            elif value < lo - TOLERANCE or value > hi + TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "feature_vector"),
                        f"feature {idx} ({feature['name']}) is {value} outside its declared "
                        f"range [{lo}, {hi}]",
                        check="feature_declared_ranges",
                    )
                )
    return failures


def check_traffic_age_arithmetic(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        expected = int(record["sampled_tick"]) - int(record["traffic_snapshot_tick"])
        if int(record["traffic_age_ticks"]) != expected:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index),
                    f"traffic_age_ticks {record['traffic_age_ticks']} is not "
                    f"sampled_tick - traffic_snapshot_tick = {expected}",
                    check="traffic_age_arithmetic",
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


def check_history_mask(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    history = list(constants.history_indices)  # [51, 52, 53, 54, 55, 56]
    pass_side_idx, attempt_idx, distance_idx, contact_idx = history[2], history[3], history[4], history[5]
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        masks = record["masks"]
        reset = record["reset"]
        history_valid = masks["history_valid"]
        if history_valid == 0:
            nonzero = [idx for idx in history if vector[idx] != 0]
            if nonzero:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        f"history_valid is 0 but history features {nonzero} are not "
                        "masked to zero",
                        check="history_mask",
                    )
                )
        else:
            if vector[pass_side_idx] not in (-1, 0, 1):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        f"previous pass side {vector[pass_side_idx]} is not -1/0/1",
                        check="history_mask",
                    )
                )
            if vector[contact_idx] not in (0, 1):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        f"recent contact flag {vector[contact_idx]} is not 0/1",
                        check="history_mask",
                    )
                )
            if vector[attempt_idx] < 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        f"seconds since last attempt {vector[attempt_idx]} is negative",
                        check="history_mask",
                    )
                )
            if vector[distance_idx] < 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        f"valid forward distance {vector[distance_idx]} is negative",
                        check="history_mask",
                    )
                )
        if reset["post_reset_defaults_applied"]:
            if int(masks["history_valid"]) != 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        "post_reset_defaults_applied is true but history_valid is not 0",
                        check="history_mask",
                    )
                )
            if int(reset["reset_generation"]) < 1:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index),
                        "post_reset_defaults_applied is true but reset_generation is 0",
                        check="history_mask",
                    )
                )
            if not reset["defaults_applied"]:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "reset.defaults_applied"),
                        "post_reset_defaults_applied is true but defaults_applied lists no "
                        "substituted defaults",
                        check="history_mask",
                    )
                )
            unknown_names = sorted(
                name
                for name in reset["defaults_applied"]
                if name not in constants.feature_names and name not in constants.group_names
            )
            if unknown_names:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "reset.defaults_applied"),
                        f"defaults_applied names {unknown_names}, which are not feature_layout "
                        "feature or group names",
                        check="history_mask",
                    )
                )
    return failures


def _resolve_scale(
    scale_ref: str, constants: ContractConstants, context: Mapping[str, Any]
) -> float | None:
    if scale_ref in constants.normalization_scales:
        return float(constants.normalization_scales[scale_ref])
    if scale_ref in context:
        try:
            return float(context[scale_ref])
        except (TypeError, ValueError):
            return None
    return None


def check_normalization_consistency(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """Every raw_inputs probe must normalize to the recorded feature value.

    Only canonically keyed probes are recomputed here; a non-canonical or
    duplicated key is rejected by check_raw_input_keys, so this check never
    resolves an index through an alias.
    """
    failures: list[Failure] = []
    context = fixture["context"]
    feature_by_index = {f["index"]: f for f in constants.features}
    for index, record in enumerate(fixture["records"]):
        vector = record["feature_vector"]
        probes = _canonical_raw_probes(record)
        if not probes:
            continue
        for idx in sorted(probes):
            raw = probes[idx]
            feature = feature_by_index.get(idx)
            if feature is None:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "raw_inputs"),
                        f"raw_inputs index {idx} is outside 0..{constants.feature_count - 1}",
                        check="normalization_consistency",
                    )
                )
                continue
            kind = feature["kind"]
            if kind not in ("ratio_divide", "ratio_multiply"):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "raw_inputs"),
                        f"feature {idx} ({feature['name']}) is kind {kind!r}, not a "
                        "linear-normalized feature, so it cannot be probed via raw_inputs",
                        check="normalization_consistency",
                    )
                )
                continue
            if not _is_number(raw):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "raw_inputs"),
                        f"raw_inputs[{idx}] is not a number",
                        check="normalization_consistency",
                    )
                )
                continue
            scale = _resolve_scale(str(feature["scale_ref"]), constants, context)
            if scale is None or scale == 0:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "raw_inputs"),
                        f"cannot resolve scale {feature['scale_ref']!r} for feature {idx}",
                        check="normalization_consistency",
                    )
                )
                continue
            if kind == "ratio_divide":
                expected = _clip(float(raw) / scale, constants.clip_min, constants.clip_max)
            else:
                expected = _clip(float(raw) * scale, constants.clip_min, constants.clip_max)
            actual = float(vector[idx])
            if abs(actual - expected) > TOLERANCE:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "feature_vector"),
                        f"feature {idx} ({feature['name']}) is {actual} but raw {raw} "
                        f"normalizes to {expected}",
                        check="normalization_consistency",
                    )
                )
    return failures


def check_raw_input_keys(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """raw_inputs keys must be canonical index strings, one probe per index.

    The record schema declares raw_inputs keyed 'by the canonical decimal index
    string'. JSON itself only forbids duplicate members, so "27" and "027" (or
    " 27") are distinct members that int() to the same index; without this
    check an aliased key could satisfy a check that normalizes keys with
    int(key) while a check that looks the index up canonically falls back to
    the clipped feature value - letting an authoritative out-of-window raw
    input ride along with an in-window eligibility decision.
    """
    failures: list[Failure] = []
    for index, record in enumerate(fixture["records"]):
        raw_inputs = record.get("raw_inputs")
        if not isinstance(raw_inputs, Mapping) or not raw_inputs:
            continue
        first_key_for_index: dict[int, str] = {}
        for key in raw_inputs:
            if not (isinstance(key, str) and RAW_INPUT_KEY_RE.match(key)):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, f"raw_inputs.{key}"),
                        f"raw_inputs key {key!r} is not a canonical feature-index "
                        "string (a decimal index with no leading zeros, sign or "
                        "whitespace)",
                        check="raw_input_keys",
                    )
                )
            try:
                parsed = int(key)
            except (TypeError, ValueError):
                continue
            if parsed in first_key_for_index:
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "raw_inputs"),
                        f"raw_inputs keys {first_key_for_index[parsed]!r} and {key!r} "
                        f"both name feature index {parsed}; each index may be probed "
                        "at most once",
                        check="raw_input_keys",
                    )
                )
            else:
                first_key_for_index[parsed] = key
    return failures


def check_fallback_defaults(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    failures: list[Failure] = []
    # OPPONENT_AI.md 'Shared schema version 1': zero usable width produces a
    # safe diagnostic fallback, so a zero-width scenario must set fallback.active.
    zero_width = float(fixture["context"].get("usable_half_width_m", 1)) == 0.0
    for index, record in enumerate(fixture["records"]):
        fallback = record["fallback"]
        if fallback["active"]:
            if not fallback.get("defaults_applied"):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "fallback.defaults_applied"),
                        "safe diagnostic fallback is active but lists no defaults_applied",
                        check="fallback_defaults",
                    )
                )
            if not (isinstance(fallback.get("reason"), str) and fallback["reason"]):
                failures.append(
                    Failure(
                        "semantic",
                        _record_path(index, "fallback.reason"),
                        "safe diagnostic fallback is active but has no reason",
                        check="fallback_defaults",
                    )
                )
        elif zero_width:
            failures.append(
                Failure(
                    "semantic",
                    _record_path(index, "fallback.active"),
                    "context usable_half_width_m is 0 but fallback.active is false; "
                    "zero usable width must produce a safe diagnostic fallback",
                    check="fallback_defaults",
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
                # An omitted optional field means the same "not yet determined"
                # state as an explicit null; both must be paired with unknowns.
                container = container.get(token) if isinstance(container, Mapping) else None
                if container is None:
                    break
            dotted = f"records.{index}.{field}"
            if container is None and dotted not in unknown_paths:
                failures.append(
                    Failure(
                        "semantic",
                        dotted,
                        f"{field} is null or absent ('not yet determined') but has no "
                        "unknowns entry",
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


def check_metric_status_honesty(
    fixture: Mapping[str, Any], constants: ContractConstants
) -> list[Failure]:
    """A fixture file carries documented targets, never measured values.

    ``observation_fixture.schema.json`` (comparison.metrics) states that a
    metric with status 'measured' is invalid in a fixture file; the shared
    ``acceptance_metric`` vocabulary still allows 'measured' because
    reference-run records need it. The fixture schema's rule lives only in
    prose, so it is enforced here - the same split the handling, intent and
    scenario slices enforce.
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
                    "values; measured values belong to reference-run records and "
                    "evaluation reports",
                    check="metric_status_honesty",
                )
            )
        elif status not in legal:
            failures.append(
                Failure(
                    "semantic",
                    _metric_path(index, "status"),
                    f"status must be one of {list(legal)}, found {status!r}; a fixture "
                    "carries documented targets and reporting requirements, never "
                    "measured values",
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
    still validate - which is exactly the disagreement the M0.9 review found
    between this slice's checker and any draft 2020-12 validator.
    """
    comparators = constants.metric_vocabulary.comparators
    failures: list[Failure] = []
    for index, metric in _metric_entries(fixture):
        comparator = metric.get("comparator")
        if comparator not in comparators:
            # The schema enum already rejects this; keep the check defensive.
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
            elif float(value_min) >= float(value_max):
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
                        _metric_path(index, "value"),
                        "a report metric carries no pass/fail bound",
                        check="metric_shape",
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
    check_difficulty_one_hot,
    check_style_one_hot,
    check_neighbor_presence,
    check_neighbor_ordering,
    check_neighbor_window,
    check_feature_declared_ranges,
    check_traffic_age_arithmetic,
    check_difficulty_age,
    check_history_mask,
    check_raw_input_keys,
    check_normalization_consistency,
    check_fallback_defaults,
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


def load_contracts(schemas_dir: Path) -> Contracts:
    cache = SchemaCache()
    fixture_schema = cache.document(schemas_dir / FIXTURE_SCHEMA_NAME)
    record_schema = cache.document(schemas_dir / RECORD_SCHEMA_NAME)
    if not isinstance(fixture_schema, Mapping) or not isinstance(record_schema, Mapping):
        raise DocumentError("schema documents must be JSON objects")
    return Contracts(
        fixture_schema=fixture_schema,
        record_schema=record_schema,
        constants=load_constants(record_schema, load_metric_vocabulary(schemas_dir)),
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

    failures.extend(check_expectations_declared(document))
    failures.extend(check_metric_status_honesty(document, contracts.constants))
    failures.extend(check_metric_shape(document, contracts.constants))
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
        description="Validate Roadstorm AI-observation fixtures against schemas/observation."
    )
    parser.add_argument(
        "--schemas",
        type=Path,
        default=here.parents[1] / "schemas" / "observation",
        help="directory holding observation_record.schema.json and observation_fixture.schema.json",
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
        help="recompute and write content_hash for positive fixtures, then exit",
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
