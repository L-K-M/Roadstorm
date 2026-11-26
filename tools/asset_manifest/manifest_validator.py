#!/usr/bin/env python3
"""Roadstorm Racer! asset manifest validator.

Ownership: tools/asset_manifest/** (PLAN.md M0 provenance manifest tooling,
job 6058a51e-ae48-4329-8fb0-52c3c36eddad).

This module is the executable form of the manifest contract in
``provenance/MANIFEST_CONTRACT.md`` ("Creative asset and model manifest
fields") and the release rights gate in ``docs/ASSET_PRODUCTION.md``
("Release rights gate"). For every registered creative asset or learned
model artifact it checks the essential provenance and lineage metadata that
lets a reviewer answer:

* what it is - stable ID, category, source/output paths, SHA-256 hashes;
* where it came from - origin, authoring route, generator, recipe, seed and
  the exact regeneration command;
* what it is made of - lineage: upstream inputs with their licenses and
  evidence, dependency references, superseded outputs;
* who may ship it - license/SPDX identifier, rights record, service terms;
* whether it was reviewed and is approved for release inclusion.

Across entries it also enforces the two rules that make the registry usable as
a record rather than a pile of independent claims: every registered output
path has exactly one owning entry, and ``lineage.depends_on`` is acyclic, so
the lineage can be traversed as a production dependency order. At the document
level it rejects repeated JSON members (Python keeps only the last value of a
repeat, which silently overwrites the earlier record) and manifests that are
not valid UTF-8, both as structured findings rather than as tracebacks.

Deliberate limitations (documented in README.md):

* Standard library only, standalone. It does not resolve hashes against a
  network, run the engine, or check technical metadata such as triangle
  counts, LODs, audio meters or model dimensions; those belong to the
  producing pipeline and the review record.
* It cannot make unknown facts known. Missing or ``unknown`` metadata is
  reported, never filled in and never guessed.
* Unknown legal origin is a blocking error, per policy.
* It validates the manifest, not the assets. A manifest entry whose files
  exist and hash correctly can still be an unreviewed or bad asset.

Usage as a library::

    from manifest_validator import validate_manifest
    findings = validate_manifest(Path("assets/manifest.json"), root=Path("."))

Exit codes for the CLI wrapper: 0 = no errors, 1 = validation errors,
2 = the manifest could not be read or the command line was wrong. "Could
not be read" means the read itself failed or the bytes are not a JSON record
at all: a missing/unreadable file, a nonexistent ``--root`` (``bad-root``)
and text that is not JSON (``invalid-json``) all exit 2, while a document
that decodes but violates the contract - including one that is not valid
UTF-8 (``invalid-encoding``) - is a content defect and exits 1.

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
from typing import Any, Iterable, Mapping, Sequence

# ---------------------------------------------------------------------------
# Contract constants
# ---------------------------------------------------------------------------

MANIFEST_ID = "roadstorm-asset-manifest"
SCHEMA_VERSION = "0.1.0"

# Stable semantic ID pattern, reused verbatim from schemas/common.schema.json
# ("stable_id") so manifest IDs and resource IDs share one vocabulary.
STABLE_ID_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z0-9_-]+)*$")

# Hash spelling, reused from schemas/common.schema.json ("content_hash").
SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

# Origin classes from provenance/MANIFEST_CONTRACT.md.
ORIGINS = ("llm_script_generated", "service_generated", "external_cc0")

# Reproducibility classes from provenance/MANIFEST_CONTRACT.md.
REPRODUCIBILITY_CLASSES = (
    "canonical_deterministic",
    "statistical_training",
    "frozen_service_output",
)

# Registry states of this file. "empty" asserts only that no entry is
# registered; it asserts nothing about what content exists in the tree.
REGISTRY_STATUSES = ("empty", "populated")

REVIEW_STATUSES = ("pending", "approved", "rejected")

# Policy-derived license sets (docs/ASSET_PRODUCTION.md "License scope" and
# "External material policy"; licenses/README.md "Scope rule"): first-party
# creative material - artwork sources, creative outputs, weights and
# datasets - is dedicated CC0-1.0, and the only external creative input the
# policy accepts is verified item-level CC0. Unlicense covers executable
# generators, tests, schemas and game/event definitions, which are not
# creative assets and are therefore never listed in this manifest; an entry
# claiming Unlicense is claiming the wrong dedication for a creative asset.
FIRST_PARTY_LICENSES = ("CC0-1.0",)
EXTERNAL_LICENSES = ("CC0-1.0",)

# Findings that mean the manifest could not be read (or the command line was
# wrong) rather than that its contents failed validation. The CLI maps these
# to exit code 2, per README.md; everything else that fails is exit 1.
READ_FAILURE_CODES = ("bad-root", "unreadable-manifest", "invalid-json")

# Explicit unknown markers. A field carrying one of these is recorded as
# unknown; it is never treated as a fact.
UNKNOWN_MARKERS = ("", "unknown")

# Top-level manifest fields (all required unless noted).
MANIFEST_REQUIRED_KEYS = ("manifest_id", "schema_version", "registry_status", "assets")
MANIFEST_OPTIONAL_KEYS = ("prepared_utc", "scope", "notes", "open_items")
MANIFEST_KNOWN_KEYS = MANIFEST_REQUIRED_KEYS + MANIFEST_OPTIONAL_KEYS

# Asset entry fields. Required ones carry the essential provenance/lineage
# metadata; the rest are recorded when applicable.
ENTRY_REQUIRED_KEYS = (
    "id",
    "category",
    "origin",
    "authoring",
    "identity",
    "hashes",
    "generation",
    "reproducibility_class",
    "rights",
    "review",
    "lineage",
)
ENTRY_OPTIONAL_KEYS = ("display_name", "technical")
ENTRY_KNOWN_KEYS = ENTRY_REQUIRED_KEYS + ENTRY_OPTIONAL_KEYS

AUTHORING_KEYS = ("task", "prompt_ref", "agent", "provider", "model", "date", "route")
# "schema" and "revision" record which definition/revision of the asset's
# format the entry describes (provenance/MANIFEST_CONTRACT.md, Identity
# group). They are recorded, not verified: no per-asset schema exists yet.
IDENTITY_KEYS = ("source_paths", "output_paths", "schema", "revision")
# "technical" is a free-form recorded group: dimensions, triangle/material
# counts, LODs, duration, sample rate/channels, loop settings and model
# dimensions as applicable (contract, Technical group). Its contents belong
# to the producing pipeline and the review record and are not verified here,
# so its members are deliberately not key-checked.
HASHES_KEYS = ()  # hashes is a free-form map: output path -> "sha256:<hex>"
GENERATION_KEYS = (
    "generator",
    "generator_version",
    "recipe_path",
    "seed",
    "input_asset_ids",
    "regeneration_command",
    "tool_versions",
)
RIGHTS_KEYS = (
    "license_spdx",
    "rights_holder_record",
    "rights_basis",
    "service_terms_ref",
    "upstream",
)
REVIEW_KEYS = (
    "status",
    "reviewer",
    "approval_revision",
    "technical_check",
    "perceptual_review",
    "limitations",
    "release_inclusion",
)
LINEAGE_KEYS = ("upstream_inputs", "modifications", "superseded_outputs", "depends_on")
UPSTREAM_INPUT_KEYS = ("asset_id", "path", "license", "evidence", "note")

ERROR = "error"
WARNING = "warning"


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------


@dataclasses.dataclass(frozen=True)
class Finding:
    """One validation result. ``location`` is a JSON-pointer-ish path."""

    level: str
    code: str
    location: str
    message: str

    def render(self) -> str:
        return "[{level}] {code} {location}: {message}".format(
            level=self.level,
            code=self.code,
            location=self.location or "<root>",
            message=self.message,
        )

    def as_dict(self) -> dict[str, str]:
        return dataclasses.asdict(self)


class Findings:
    """Collects findings and answers whether any of them are errors."""

    def __init__(self) -> None:
        self._items: list[Finding] = []

    def add(self, level: str, code: str, location: str, message: str) -> None:
        self._items.append(Finding(level=level, code=code, location=location, message=message))

    def error(self, code: str, location: str, message: str) -> None:
        self.add(ERROR, code, location, message)

    def warning(self, code: str, location: str, message: str) -> None:
        self.add(WARNING, code, location, message)

    def extend(self, other: "Findings") -> None:
        self._items.extend(other._items)

    def __iter__(self) -> Iterable[Finding]:
        return iter(self._items)

    def __len__(self) -> int:
        return len(self._items)

    @property
    def errors(self) -> list[Finding]:
        return [f for f in self._items if f.level == ERROR]

    @property
    def warnings(self) -> list[Finding]:
        return [f for f in self._items if f.level == WARNING]

    @property
    def ok(self) -> bool:
        return not self.errors


# ---------------------------------------------------------------------------
# Small typed helpers
# ---------------------------------------------------------------------------


def _is_unknown(value: Any) -> bool:
    """True when a value explicitly marks an unknown fact."""
    return isinstance(value, str) and value.strip().lower() in UNKNOWN_MARKERS


def _is_mapping(value: Any) -> bool:
    return isinstance(value, dict)


def _is_sequence(value: Any) -> bool:
    return isinstance(value, (list, tuple))


def _is_string(value: Any) -> bool:
    return isinstance(value, str)


def _join(location: str, key: str) -> str:
    return "{}.{}".format(location, key) if location else key


def _check_known_keys(
    findings: Findings,
    location: str,
    obj: Mapping[str, Any],
    known: Sequence[str],
    allow_unknown: bool,
    what: str,
) -> None:
    for key in obj:
        if key not in known:
            message = "unknown {} field '{}' (known fields: {})".format(
                what, key, ", ".join(known)
            )
            if allow_unknown:
                findings.warning("unknown-field", _join(location, key), message)
            else:
                findings.error("unknown-field", _join(location, key), message)


def _require_mapping(
    findings: Findings,
    location: str,
    obj: Any,
    what: str,
    required: bool = True,
) -> Mapping[str, Any] | None:
    if obj is None and not required:
        return None
    if not _is_mapping(obj):
        findings.error("not-an-object", location, "{} must be a JSON object".format(what))
        return None
    return obj


def _require_string(
    findings: Findings,
    location: str,
    value: Any,
    what: str,
    allow_unknown: bool = True,
) -> str | None:
    if not _is_string(value) or not value.strip():
        findings.error(
            "missing-required-field",
            location,
            "{} must be a non-empty string".format(what),
        )
        return None
    if _is_unknown(value) and not allow_unknown:
        findings.error(
            "unknown-value",
            location,
            "{} is marked '{}'; record the fact or resolve the unknown, do not ship it".format(
                what, value
            ),
        )
        return None
    return value


def _require_array(
    findings: Findings,
    location: str,
    value: Any,
    what: str,
    min_items: int = 0,
) -> Sequence[Any] | None:
    if not _is_sequence(value):
        findings.error("not-an-array", location, "{} must be a JSON array".format(what))
        return None
    if len(value) < min_items:
        findings.error(
            "missing-required-field",
            location,
            "{} must list at least {} item(s), found {}".format(what, min_items, len(value)),
        )
        return None
    return value


def _require_bool(findings: Findings, location: str, value: Any, what: str) -> bool | None:
    if not isinstance(value, bool):
        findings.error("not-a-boolean", location, "{} must be a JSON boolean".format(what))
        return None
    return value


def _require_enum(
    findings: Findings,
    location: str,
    value: Any,
    what: str,
    allowed: Sequence[str],
) -> str | None:
    if not _is_string(value) or value not in allowed:
        findings.error(
            "invalid-value",
            location,
            "{} must be one of: {} (got {!r})".format(what, ", ".join(allowed), value),
        )
        return None
    return value


# ---------------------------------------------------------------------------
# Path handling
# ---------------------------------------------------------------------------


def _path_spelling_error(value: Any) -> str | None:
    """Return why a manifest path spelling is unacceptable, or ``None``.

    Pure and filesystem-free, so it can gate both existence checks and
    hashing: a path that fails here must never be resolved against the root.
    """
    if not _is_string(value) or not value.strip():
        return "must be a non-empty path string"
    path = value
    if path.startswith("/") or re.match(r"^[A-Za-z]:", path):
        return "must be project-relative, not absolute: {!r}".format(path)
    if "\\" in path:
        return "must use POSIX '/' separators: {!r}".format(path)
    parts = path.split("/")
    if any(part in ("", ".", "..") for part in parts):
        return "must be a clean relative path without '', '.' or '..' segments: {!r}".format(
            path
        )
    return None


class PathChecker:
    """Resolves manifest-relative paths against a project root.

    Manifest paths must be POSIX-style, project-relative, and free of ``..``
    so that a manifest cannot point outside the checkout or hide an absolute
    machine path in the record. Referenced files must additionally be regular
    files: a symlink can name a file outside the checkout that the entry does
    not govern, so its existence and hash would vouch for content the record
    never accounted for.
    """

    def __init__(self, root: Path | None, file_checks: bool = True, check_hashes: bool = False):
        self.root = root
        self.file_checks = file_checks
        self.check_hashes = check_hashes

    def resolve(self, relative: str) -> Path | None:
        if self.root is None:
            return None
        return self.root / relative

    def check(self, findings: Findings, location: str, value: Any, what: str) -> None:
        """Validate the spelling and (optionally) the existence of a path."""
        problem = _path_spelling_error(value)
        if problem is not None:
            findings.error("invalid-path", location, "{} {}".format(what, problem))
            return
        path = value
        if not self.file_checks:
            return
        target = self.resolve(path)
        if target is None:
            return
        if target.is_symlink():
            findings.error(
                "symlinked-path",
                location,
                "{} is a symlink ({}); a manifest reference must be a regular file inside the "
                "checkout, because a symlink can point at a file outside the root that the "
                "entry does not govern, and its existence and hash would vouch for content the "
                "record never accounted for".format(what, path),
            )
            return
        if not target.exists():
            findings.error(
                "missing-file",
                location,
                "{} references a path that does not exist: {} (resolved against {})".format(
                    what, path, self.root
                ),
            )
        elif not target.is_file():
            findings.error(
                "not-a-file",
                location,
                "{} references a directory, not a file: {}".format(what, path),
            )

    def digest(self, relative: str) -> str | None:
        if self.root is None:
            return None
        if _path_spelling_error(relative) is not None:
            # Never resolve an unvalidated spelling against the root: an
            # absolute key such as /etc/hosts would otherwise be hashed.
            return None
        target = self.resolve(relative)
        if target is None or target.is_symlink() or not target.is_file():
            return None
        hasher = hashlib.sha256()
        with open(target, "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                hasher.update(chunk)
        return hasher.hexdigest()


# ---------------------------------------------------------------------------
# Document decoding
# ---------------------------------------------------------------------------


class _DuplicateMemberCollector:
    """Counts repeated JSON object members while a document is decoded.

    Python's ``json`` module keeps the *last* value of a repeated member and
    says nothing about the repeat. A manifest is a record, so a member written
    twice (for example a second ``registry_status``, or a second
    ``review.status`` inside one entry) is a contradiction in the record: the
    earlier value is silently overwritten and cannot be reviewed. The
    collector records, per decoded object, which members were repeated so the
    findings can point at the exact location.
    """

    def __init__(self) -> None:
        # id(decoded object) -> {member name: number of repeats}
        self.repeats: dict[int, dict[str, int]] = {}

    def __call__(self, pairs: Sequence[tuple[str, Any]]) -> dict[str, Any]:
        obj: dict[str, Any] = {}
        for key, value in pairs:
            if key in obj:
                repeats = self.repeats.setdefault(id(obj), {})
                repeats[key] = repeats.get(key, 0) + 1
            obj[key] = value
        return obj


_JSON_DECODE_FAILED = object()


def _decode_manifest_document(
    findings: Findings, raw: str, source: Path
) -> Any | None:
    """Decode manifest JSON, reporting duplicate members as findings.

    Returns a unique sentinel when the text is not valid JSON; the caller then stops,
    because nothing else about the document can be trusted.
    """
    collector = _DuplicateMemberCollector()
    try:
        document = json.loads(raw, object_pairs_hook=collector)
    except json.JSONDecodeError as exc:
        findings.error(
            "invalid-json",
            "<manifest>",
            "{} is not valid JSON: {}".format(source, exc),
        )
        return _JSON_DECODE_FAILED
    if collector.repeats:
        _report_duplicate_members(findings, document, collector.repeats)
    return document


def _report_duplicate_members(
    findings: Findings,
    document: Any,
    repeats: Mapping[int, Mapping[str, int]],
) -> None:
    """Emit one finding per repeated member, at any depth in the document."""
    pending = dict(repeats)
    stack: list[tuple[str, Any]] = [("", document)]
    while stack:
        location, value = stack.pop()
        if _is_mapping(value):
            counted = pending.pop(id(value), None)
            if counted:
                for key in sorted(counted):
                    findings.error(
                        "duplicate-json-member",
                        _join(location, key),
                        "JSON member '{}' appears {} times in the same object; JSON keeps only the "
                        "last value, so the earlier record is silently overwritten - list the "
                        "member once with the value that is meant".format(
                            key, counted[key] + 1
                        ),
                    )
            for key in reversed(list(value)):
                stack.append((_join(location, key), value[key]))
        elif _is_sequence(value):
            for index in reversed(range(len(value))):
                stack.append(("{}[{}]".format(location, index), value[index]))


# ---------------------------------------------------------------------------
# Manifest validation
# ---------------------------------------------------------------------------


def validate_manifest(
    manifest_path: Path,
    root: Path | None = None,
    file_checks: bool = True,
    check_hashes: bool = False,
    allow_unknown_keys: bool = False,
) -> Findings:
    """Validate one manifest document and return all findings.

    ``root`` is the project root that manifest-relative paths resolve
    against. It defaults to the parent of the manifest's directory (the
    manifest lives at ``<root>/assets/manifest.json``).
    """
    findings = Findings()

    manifest_path = Path(manifest_path)
    if root is None:
        root = manifest_path.resolve().parent.parent
    root = Path(root)
    if not root.is_dir():
        findings.error(
            "bad-root",
            "<root>",
            "project root directory does not exist: {}".format(root),
        )
        return findings

    try:
        raw = manifest_path.read_bytes().decode("utf-8")
    except OSError as exc:
        findings.error(
            "unreadable-manifest",
            "<manifest>",
            "cannot read {}: {}".format(manifest_path, exc),
        )
        return findings
    except UnicodeDecodeError as exc:
        findings.error(
            "invalid-encoding",
            "<manifest>",
            "{} is not valid UTF-8 ({}); the manifest is a UTF-8 JSON document, so it cannot be "
            "read as a record - re-save it as UTF-8".format(manifest_path, exc),
        )
        return findings

    document = _decode_manifest_document(findings, raw, manifest_path)
    if document is _JSON_DECODE_FAILED:
        return findings

    checker = PathChecker(root, file_checks=file_checks, check_hashes=check_hashes)
    _validate_document(findings, document, checker, allow_unknown_keys)
    return findings


def _validate_document(
    findings: Findings,
    document: Any,
    checker: PathChecker,
    allow_unknown_keys: bool,
) -> None:
    if not _is_mapping(document):
        findings.error(
            "not-an-object",
            "<root>",
            "the manifest must be a JSON object at the top level",
        )
        return

    _check_known_keys(
        findings, "", document, MANIFEST_KNOWN_KEYS, allow_unknown_keys, "manifest"
    )
    for key in MANIFEST_REQUIRED_KEYS:
        if key not in document:
            findings.error(
                "missing-required-field",
                key,
                "manifest is missing the required field '{}'".format(key),
            )

    if "manifest_id" in document:
        manifest_id = document["manifest_id"]
        if manifest_id != MANIFEST_ID:
            findings.error(
                "invalid-value",
                "manifest_id",
                "manifest_id must be {!r} (got {!r})".format(MANIFEST_ID, manifest_id),
            )

    if "schema_version" in document:
        schema_version = document["schema_version"]
        if schema_version != SCHEMA_VERSION:
            findings.error(
                "unsupported-schema-version",
                "schema_version",
                "schema_version must be {!r} (got {!r}); a changed record format needs a new "
                "schema version recorded with a decision".format(SCHEMA_VERSION, schema_version),
            )

    status = None
    if "registry_status" in document:
        status = _require_enum(
            findings,
            "registry_status",
            document["registry_status"],
            "registry_status",
            REGISTRY_STATUSES,
        )

    entries: Sequence[Any] = []
    if "assets" in document:
        assets = document["assets"]
        entries = _require_array(findings, "assets", assets, "assets") or []

    # An empty registry and a populated registry are different claims; the
    # status must agree with the entry list.
    if status is not None:
        if status == "empty" and entries:
            findings.error(
                "registry-status-mismatch",
                "assets",
                "registry_status is 'empty' but {} asset entr{} registered; an empty manifest "
                "must not claim content that is not registered".format(
                    len(entries), "y is" if len(entries) == 1 else "ies are"
                ),
            )
        if status == "populated" and not entries:
            findings.error(
                "registry-status-mismatch",
                "assets",
                "registry_status is 'populated' but no asset entries are registered",
            )

    if "notes" in document:
        notes = _require_array(findings, "notes", document["notes"], "notes") or []
        for index, note in enumerate(notes):
            if not _is_string(note) or not note.strip():
                findings.error(
                    "invalid-value",
                    "notes[{}]".format(index),
                    "each note must be a non-empty string",
                )

    for key in ("prepared_utc", "scope"):
        if key in document:
            _require_string(findings, key, document[key], key)

    if "open_items" in document:
        open_items = _require_array(findings, "open_items", document["open_items"], "open_items") or []
        for index, item in enumerate(open_items):
            _require_string(
                findings,
                "open_items[{}]".format(index),
                item,
                "each open item reference",
            )

    # Collect IDs first so cross-entry reference checks can run afterwards.
    entry_ids: list[str] = []
    for index, entry in enumerate(entries):
        location = "assets[{}]".format(index)
        if not _is_mapping(entry):
            findings.error("not-an-object", location, "each asset entry must be a JSON object")
            continue
        entry_id = entry.get("id")
        if _is_string(entry_id) and entry_id.strip():
            entry_ids.append(entry_id)

    seen: dict[str, int] = {}
    for index, entry in enumerate(entries):
        location = "assets[{}]".format(index)
        if not _is_mapping(entry):
            continue
        entry_id = entry.get("id")
        if _is_string(entry_id) and entry_id.strip():
            if entry_id in seen:
                findings.error(
                    "duplicate-id",
                    _join(location, "id"),
                    "duplicate stable asset ID {!r} (first seen at assets[{}]); stable IDs must "
                    "be unique because they survive renaming and regeneration".format(
                        entry_id, seen[entry_id]
                    ),
                )
            else:
                seen[entry_id] = index
        _validate_entry(findings, location, entry, checker, allow_unknown_keys, set(entry_ids))

    # Cross-entry checks: they need the whole registry, not one entry.
    _check_output_ownership(findings, entries)
    _check_dependency_cycles(findings, entries)


def _check_output_ownership(findings: Findings, entries: Sequence[Any]) -> None:
    """Enforce one owner per registered output path.

    An output path is the asset the entry stands for: the file its recipe
    writes and the file its hash identifies. Provenance for that file is the
    entry, so a path registered by two entries has two owners, two lineage
    records and (potentially) two hashes for one file. A reviewer can no
    longer tell which entry governs it, and the lineage cannot be traversed
    as a production dependency order. Every output path therefore needs
    exactly one owning entry, and must be listed once inside it.
    """
    owners: dict[str, str] = {}
    for index, entry in enumerate(entries):
        if not _is_mapping(entry):
            continue
        location = "assets[{}]".format(index)
        identity = entry.get("identity")
        if not _is_mapping(identity):
            continue
        output_paths = identity.get("output_paths")
        if not _is_sequence(output_paths):
            continue
        claimed_here: set[str] = set()
        for position, path in enumerate(output_paths):
            if not _is_string(path) or not path.strip():
                continue
            where = "{}.output_paths[{}]".format(location, position)
            if path in claimed_here:
                findings.error(
                    "duplicate-output-path",
                    where,
                    "output path '{}' is listed twice in {}.identity.output_paths; list each "
                    "output path once so the entry names one file per hash".format(path, location),
                )
                continue
            claimed_here.add(path)
            if path in owners:
                findings.error(
                    "duplicate-output-path",
                    where,
                    "output path '{}' is registered by {} as well (first claimed by {}); each "
                    "output path must have exactly one owning entry, otherwise the provenance, "
                    "lineage and hash of that file are ambiguous and the dependency order "
                    "cannot be traversed".format(path, location, owners[path]),
                )
                continue
            owners[path] = location


def _check_dependency_cycles(findings: Findings, entries: Sequence[Any]) -> None:
    """Reject dependency cycles in ``lineage.depends_on``.

    ``depends_on`` is the production dependency order: an entry may only be
    built once the entries it depends on exist. A cycle (A needs B, B needs A;
    or a longer loop) makes that order impossible, so it is an error. Unknown
    or malformed IDs are reported by the per-entry checks and ignored here.
    """
    order: list[str] = []
    rank: dict[str, int] = {}
    edges: dict[str, set[str]] = {}
    for entry in entries:
        if not _is_mapping(entry):
            continue
        entry_id = entry.get("id")
        if not _is_string(entry_id) or not entry_id.strip() or entry_id in rank:
            # Missing, non-string and duplicate IDs are reported elsewhere; a
            # duplicate ID cannot be given a second node in the graph.
            continue
        rank[entry_id] = len(order)
        order.append(entry_id)
        lineage = entry.get("lineage")
        depends_on = lineage.get("depends_on") if _is_mapping(lineage) else None
        successors: set[str] = set()
        if _is_sequence(depends_on):
            for dependency in depends_on:
                if _is_string(dependency) and dependency.strip():
                    successors.add(dependency)
        edges[entry_id] = successors

    for component in _strongly_connected_components(order, rank, edges):
        members = set(component)
        if len(members) == 1:
            node = component[0]
            if node not in edges.get(node, ()):
                continue  # a lone entry without a self-dependency is not a cycle
        cycle = _cycle_path(rank, edges, members)
        first = cycle[0]
        location = "assets[{}].lineage.depends_on".format(rank[first])
        path = " -> ".join(cycle + [cycle[0]])
        message = (
            "dependency cycle in lineage.depends_on: {}; an asset can only be built once the "
            "entries it depends on exist, so a cyclic dependency order cannot be traversed - "
            "record the upstream dependencies so the graph is acyclic".format(path)
        )
        unlisted = sorted(members.difference(cycle), key=lambda node: rank[node])
        if unlisted:
            message += "; the same cycle also involves {}".format(", ".join(unlisted))
        findings.error("dependency-cycle", location, message)


def _cycle_path(
    rank: Mapping[str, int],
    edges: Mapping[str, set[str]],
    members: set[str],
) -> list[str]:
    """Walk one closed cycle out of a strongly connected component.

    The walk starts at the component member that appears first in the manifest
    and always takes the earliest-registered successor inside the component,
    so the reported path is deterministic.
    """
    start = min(members, key=lambda node: rank[node])
    path = [start]
    current = start
    while True:
        successors = sorted(
            (node for node in edges.get(current, ()) if node in members),
            key=lambda node: rank[node],
        )
        if not successors:
            return path  # unreachable inside a strongly connected component
        successor = successors[0]
        if successor in path:
            return path[path.index(successor):]
        path.append(successor)
        current = successor


def _rank_key(rank: Mapping[str, int]):
    """Deterministic traversal order: manifest order, unknown IDs last."""
    return lambda node: rank.get(node, len(rank))


def _strongly_connected_components(
    order: Sequence[str],
    rank: Mapping[str, int],
    edges: Mapping[str, set[str]],
) -> list[list[str]]:
    """Tarjan's algorithm, iterative so deep chains cannot exhaust the stack.

    Only registered IDs are nodes; dependencies on unregistered IDs are
    reported as dangling references by the per-entry checks. Successors are
    visited in manifest order so the traversal is deterministic.
    """
    index: dict[str, int] = {}
    lowlink: dict[str, int] = {}
    on_stack: set[str] = set()
    stack: list[str] = []
    components: list[list[str]] = []
    counter = 0

    for root in order:
        if root in index:
            continue
        index[root] = lowlink[root] = counter
        counter += 1
        stack.append(root)
        on_stack.add(root)
        work: list[tuple[str, Any]] = [
            (root, iter(sorted(edges.get(root, ()), key=_rank_key(rank))))
        ]
        while work:
            node, successors = work[-1]
            descended = False
            for successor in successors:
                if successor not in index:
                    index[successor] = lowlink[successor] = counter
                    counter += 1
                    stack.append(successor)
                    on_stack.add(successor)
                    work.append(
                        (
                            successor,
                            iter(sorted(edges.get(successor, ()), key=_rank_key(rank))),
                        )
                    )
                    descended = True
                    break
                if successor in on_stack:
                    lowlink[node] = min(lowlink[node], index[successor])
            if descended:
                continue
            work.pop()
            if lowlink[node] == index[node]:
                component: list[str] = []
                while True:
                    member = stack.pop()
                    on_stack.discard(member)
                    component.append(member)
                    if member == node:
                        break
                components.append(component)
            if work:
                parent = work[-1][0]
                lowlink[parent] = min(lowlink[parent], lowlink[node])
    return components


def _validate_entry(
    findings: Findings,
    location: str,
    entry: Mapping[str, Any],
    checker: PathChecker,
    allow_unknown_keys: bool,
    known_ids: set[str],
) -> None:
    _check_known_keys(findings, location, entry, ENTRY_KNOWN_KEYS, allow_unknown_keys, "asset entry")
    for key in ENTRY_REQUIRED_KEYS:
        if key not in entry:
            findings.error(
                "missing-required-field",
                _join(location, key),
                "asset entry is missing the required field '{}'".format(key),
            )

    if "display_name" in entry:
        _require_string(findings, _join(location, "display_name"), entry["display_name"], "display_name")

    if "technical" in entry:
        _validate_technical(findings, _join(location, "technical"), entry["technical"])

    if "id" in entry:
        entry_id = entry["id"]
        if _is_string(entry_id) and entry_id.strip():
            if _is_unknown(entry_id):
                findings.error(
                    "unknown-value",
                    _join(location, "id"),
                    "the stable asset ID cannot be 'unknown'; IDs survive renaming and "
                    "regeneration and must be assigned by the producing task",
                )
            elif not STABLE_ID_RE.match(entry_id):
                findings.error(
                    "invalid-id",
                    _join(location, "id"),
                    "stable asset ID {!r} does not match the project stable_id pattern {}".format(
                        entry_id, STABLE_ID_RE.pattern
                    ),
                )
        else:
            findings.error(
                "missing-required-field",
                _join(location, "id"),
                "the stable asset ID must be a non-empty string",
            )

    if "category" in entry:
        _require_string(findings, _join(location, "category"), entry["category"], "category")

    origin = None
    if "origin" in entry:
        origin = _require_enum(
            findings, _join(location, "origin"), entry["origin"], "origin", ORIGINS
        )

    if "authoring" in entry:
        _validate_authoring(findings, _join(location, "authoring"), entry["authoring"], allow_unknown_keys)

    if "identity" in entry:
        _validate_identity(findings, _join(location, "identity"), entry["identity"], checker, allow_unknown_keys)

    if "hashes" in entry:
        _validate_hashes(
            findings,
            _join(location, "hashes"),
            entry["hashes"],
            entry.get("identity", {}).get("output_paths")
            if _is_mapping(entry.get("identity"))
            else None,
            checker,
            allow_unknown_keys,
        )

    if "generation" in entry:
        _validate_generation(
            findings,
            _join(location, "generation"),
            entry["generation"],
            origin,
            checker,
            allow_unknown_keys,
            known_ids,
        )

    if "reproducibility_class" in entry:
        _require_enum(
            findings,
            _join(location, "reproducibility_class"),
            entry["reproducibility_class"],
            "reproducibility_class",
            REPRODUCIBILITY_CLASSES,
        )

    if "rights" in entry:
        _validate_rights(findings, _join(location, "rights"), entry["rights"], origin, allow_unknown_keys)

    if "review" in entry:
        _validate_review(findings, _join(location, "review"), entry["review"], allow_unknown_keys)

    if "lineage" in entry:
        _validate_lineage(
            findings,
            _join(location, "lineage"),
            entry["lineage"],
            origin,
            checker,
            allow_unknown_keys,
            known_ids,
        )


def _validate_technical(findings: Findings, location: str, value: Any) -> None:
    """Record the Technical group without verifying it.

    The contract's Technical data (dimensions, triangle/material counts, LODs,
    duration, sample rate/channels, loop settings, model dimensions, as
    applicable) is produced by the pipeline and confirmed by the review
    record, not by this validator: it cannot measure an asset. The group is
    therefore free-form - its members are deliberately not key-checked, so a
    producer may record whatever its category needs - but it must be a JSON
    object, so the group cannot silently swallow a malformed record.
    """
    _require_mapping(findings, location, value, "technical")


def _validate_authoring(
    findings: Findings, location: str, value: Any, allow_unknown_keys: bool
) -> None:
    authoring = _require_mapping(findings, location, value, "authoring")
    if authoring is None:
        return
    _check_known_keys(findings, location, authoring, AUTHORING_KEYS, allow_unknown_keys, "authoring")
    for key in AUTHORING_KEYS:
        if key in authoring and authoring[key] is not None:
            _require_string(
                findings,
                _join(location, key),
                authoring[key],
                "authoring.{}".format(key),
                allow_unknown=True,
            )


def _validate_identity(
    findings: Findings,
    location: str,
    value: Any,
    checker: PathChecker,
    allow_unknown_keys: bool,
) -> None:
    identity = _require_mapping(findings, location, value, "identity")
    if identity is None:
        return
    _check_known_keys(findings, location, identity, IDENTITY_KEYS, allow_unknown_keys, "identity")
    for key in ("source_paths", "output_paths"):
        if key not in identity:
            findings.error(
                "missing-required-field",
                _join(location, key),
                "identity is missing the required field '{}'".format(key),
            )
            continue
        paths = _require_array(
            findings, _join(location, key), identity[key], "identity.{}".format(key), min_items=1
        )
        if paths is None:
            continue
        for index, path in enumerate(paths):
            checker.check(findings, "{}.{}[{}]".format(location, key, index), path, "identity.{}".format(key))

    # Schema/revision of the asset's own format definition. Recorded, not
    # verified: the project has no per-asset schema files yet, so the field
    # carries the producer's declaration for reviewers to check.
    for key in ("schema", "revision"):
        if key in identity:
            _require_string(
                findings, _join(location, key), identity[key], "identity.{}".format(key)
            )


def _validate_hashes(
    findings: Findings,
    location: str,
    value: Any,
    output_paths: Any,
    checker: PathChecker,
    allow_unknown_keys: bool,
) -> None:
    hashes = _require_mapping(findings, location, value, "hashes")
    if hashes is None:
        return
    if _is_sequence(output_paths):
        outputs = [p for p in output_paths if _is_string(p) and p.strip()]
        for path in outputs:
            if path not in hashes:
                findings.error(
                    "missing-hash",
                    location,
                    "no SHA-256 recorded for output path '{}'; every shipped output path needs a "
                    "hash".format(path),
                )
        for path in hashes:
            if path not in outputs:
                findings.error(
                    "unknown-hash",
                    _join(location, path),
                    "a hash is recorded for '{}' but that path is not listed in "
                    "identity.output_paths".format(path),
                )
    for path, digest in hashes.items():
        where = _join(location, path)
        if not _is_string(digest) or not SHA256_RE.match(digest):
            findings.error(
                "invalid-hash",
                where,
                "hash for '{}' must look like 'sha256:<64 lowercase hex>' (got {!r})".format(
                    path, digest
                ),
            )
            continue
        if checker.check_hashes:
            if _path_spelling_error(path) is not None:
                # The key is unchecked by identity when output_paths is
                # malformed, so it is validated here before anything is
                # resolved and hashed.
                findings.error(
                    "invalid-path",
                    where,
                    "hashes key {}; --check-hashes only hashes clean, project-relative paths "
                    "inside the root".format(_path_spelling_error(path)),
                )
                continue
            actual = checker.digest(path)
            if actual is None:
                findings.error(
                    "missing-file",
                    where,
                    "cannot hash '{}' with --check-hashes: the file is missing, unreadable, a "
                    "symlink or outside the root".format(path),
                )
            elif "sha256:" + actual != digest:
                findings.error(
                    "hash-mismatch",
                    where,
                    "recorded hash for '{}' is sha256:{} but the file hashes to sha256:{}".format(
                        path, digest[len("sha256:"):], actual
                    ),
                )


def _validate_generation(
    findings: Findings,
    location: str,
    value: Any,
    origin: str | None,
    checker: PathChecker,
    allow_unknown_keys: bool,
    known_ids: set[str],
) -> None:
    generation = _require_mapping(findings, location, value, "generation")
    if generation is None:
        return
    _check_known_keys(findings, location, generation, GENERATION_KEYS, allow_unknown_keys, "generation")

    if "generator" in generation:
        _require_string(
            findings,
            _join(location, "generator"),
            generation["generator"],
            "generation.generator",
            allow_unknown=False,
        )
    else:
        findings.error(
            "missing-required-field",
            _join(location, "generator"),
            "generation is missing the required field 'generator'",
        )

    if "generator_version" in generation:
        _require_string(
            findings,
            _join(location, "generator_version"),
            generation["generator_version"],
            "generation.generator_version",
        )

    first_party = origin != "external_cc0"
    for key in ("recipe_path", "regeneration_command"):
        if key not in generation:
            if first_party:
                findings.error(
                    "missing-required-field",
                    _join(location, key),
                    "generation is missing the required field '{}' for a first-party generated "
                    "asset; the release rights gate blocks missing source recipes and "
                    "regeneration commands".format(key),
                )
            continue
        if key == "recipe_path":
            checker.check(findings, _join(location, key), generation[key], "generation.recipe_path")
        else:
            _require_string(
                findings,
                _join(location, key),
                generation[key],
                "generation.regeneration_command",
                allow_unknown=False,
            )

    if "seed" in generation and generation["seed"] is not None:
        seed = generation["seed"]
        # bool is a subclass of int in Python, so True would otherwise pass as
        # the integer 1 and record a regeneration seed that was never given.
        if isinstance(seed, bool) or not (_is_string(seed) or isinstance(seed, int)):
            findings.error(
                "invalid-value",
                _join(location, "seed"),
                "generation.seed must be a string, an integer or null (got {!r}); a boolean is "
                "not a seed".format(seed),
            )

    if "input_asset_ids" in generation:
        inputs = _require_array(
            findings,
            _join(location, "input_asset_ids"),
            generation["input_asset_ids"],
            "generation.input_asset_ids",
        )
        if inputs is not None:
            for index, asset_id in enumerate(inputs):
                where = "{}.input_asset_ids[{}]".format(location, index)
                if not _is_string(asset_id) or not asset_id.strip():
                    findings.error(
                        "invalid-value",
                        where,
                        "each input asset ID must be a non-empty string",
                    )
                elif asset_id not in known_ids:
                    findings.error(
                        "dangling-reference",
                        where,
                        "input asset ID '{}' is not registered in this manifest".format(asset_id),
                    )

    if "tool_versions" in generation:
        tools = _require_mapping(
            findings, _join(location, "tool_versions"), generation["tool_versions"], "generation.tool_versions"
        )
        if tools is not None:
            for name, version in tools.items():
                _require_string(
                    findings,
                    "{}.tool_versions.{}".format(location, name),
                    version,
                    "generation.tool_versions.{}".format(name),
                )


def _validate_rights(
    findings: Findings, location: str, value: Any, origin: str | None, allow_unknown_keys: bool
) -> None:
    rights = _require_mapping(findings, location, value, "rights")
    if rights is None:
        return
    _check_known_keys(findings, location, rights, RIGHTS_KEYS, allow_unknown_keys, "rights")

    for key in ("license_spdx", "rights_holder_record"):
        if key not in rights:
            findings.error(
                "missing-required-field",
                _join(location, key),
                "rights is missing the required field '{}'".format(key),
            )

    license_spdx = None
    if "license_spdx" in rights:
        license_spdx = _require_string(
            findings, _join(location, "license_spdx"), rights["license_spdx"], "rights.license_spdx"
        )
        if license_spdx is not None and _is_unknown(license_spdx):
            findings.error(
                "unknown-legal-origin",
                _join(location, "license_spdx"),
                "unknown legal origin blocks shipping: record the exact license/SPDX identifier or "
                "resolve the rights question before this asset can ship "
                "(provenance/OPEN_ITEMS.md tracks the open authority/terms items)",
            )
        elif license_spdx is not None:
            if origin == "external_cc0":
                if license_spdx not in EXTERNAL_LICENSES:
                    findings.error(
                        "disallowed-license",
                        _join(location, "license_spdx"),
                        "external creative input must be verified item-level CC0-1.0 (got {!r}); "
                        "the asset policy accepts no other external license".format(license_spdx),
                    )
            elif license_spdx not in FIRST_PARTY_LICENSES:
                findings.error(
                    "disallowed-license",
                    _join(location, "license_spdx"),
                    "first-party creative material must be CC0-1.0 (got {!r}); this manifest "
                    "covers creative assets and model artifacts, and Unlicense - the project "
                    "dedication for code, tools, tests, schemas and text definitions - is not "
                    "a creative-asset dedication, so an entry claiming it claims the wrong "
                    "license for what it registers".format(license_spdx),
                )

    if "rights_holder_record" in rights:
        holder = _require_string(
            findings,
            _join(location, "rights_holder_record"),
            rights["rights_holder_record"],
            "rights.rights_holder_record",
        )
        if holder is not None and _is_unknown(holder):
            findings.error(
                "unknown-legal-origin",
                _join(location, "rights_holder_record"),
                "the rights holder/contributor record is unknown; rights records must link to the "
                "owner/contributor authority instrument or a recorded contributor entry "
                "(open item OI-01)",
            )

    if "rights_basis" in rights:
        _require_string(
            findings, _join(location, "rights_basis"), rights["rights_basis"], "rights.rights_basis"
        )

    if "service_terms_ref" in rights and rights["service_terms_ref"] is not None:
        terms = _require_string(
            findings,
            _join(location, "service_terms_ref"),
            rights["service_terms_ref"],
            "rights.service_terms_ref",
        )
        if origin == "service_generated" and (terms is None or _is_unknown(terms)):
            findings.error(
                "unknown-legal-origin",
                _join(location, "service_terms_ref"),
                "a service-generated asset must reference the applicable provider/service terms "
                "entry in provenance/PROVIDER_TERMS.md; unknown or incompatible terms block "
                "inclusion",
            )
    if origin == "service_generated" and (
        "service_terms_ref" not in rights or rights["service_terms_ref"] is None
    ):
        # The legal origin of a service-generated asset *is* its provider
        # terms. Omitting the field (or recording null) hides exactly the fact
        # the release rights gate needs, so it is required for this origin
        # rather than merely checked when present.
        findings.error(
            "missing-required-field",
            _join(location, "service_terms_ref"),
            "a service_generated entry must reference the applicable provider/service terms "
            "entry in provenance/PROVIDER_TERMS.md; omitting the reference, or recording it as "
            "null, leaves the asset's legal origin unrecorded and blocks inclusion",
        )

    if origin == "external_cc0":
        upstream_value = rights.get("upstream")
        if "upstream" not in rights or upstream_value is None:
            findings.error(
                "missing-required-field",
                _join(location, "upstream"),
                "an external_cc0 entry must record rights.upstream with the item-level CC0 "
                "evidence (url, date, evidence); omitting it, or recording it as null, leaves the "
                "external material's origin unverifiable and blocks inclusion",
            )
        else:
            upstream = _require_mapping(
                findings, _join(location, "upstream"), upstream_value, "rights.upstream"
            )
            if upstream is not None:
                for key in ("url", "date", "evidence"):
                    if key not in upstream or _is_unknown(upstream.get(key)):
                        findings.error(
                            "missing-required-field",
                            "{}.upstream.{}".format(location, key),
                            "external creative input must record upstream '{}' as item-level CC0 "
                            "evidence".format(key),
                        )
    elif "upstream" in rights and rights["upstream"] is not None:
        _require_mapping(
            findings, _join(location, "upstream"), rights["upstream"], "rights.upstream"
        )


def _validate_review(
    findings: Findings, location: str, value: Any, allow_unknown_keys: bool
) -> None:
    review = _require_mapping(findings, location, value, "review")
    if review is None:
        return
    _check_known_keys(findings, location, review, REVIEW_KEYS, allow_unknown_keys, "review")

    status = None
    if "status" in review:
        status = _require_enum(
            findings, _join(location, "status"), review["status"], "review.status", REVIEW_STATUSES
        )
    else:
        findings.error(
            "missing-required-field",
            _join(location, "status"),
            "review is missing the required field 'status'",
        )

    if "reviewer" in review:
        _require_string(findings, _join(location, "reviewer"), review["reviewer"], "review.reviewer")
    else:
        findings.error(
            "missing-required-field",
            _join(location, "reviewer"),
            "review is missing the required field 'reviewer'",
        )

    if "limitations" in review:
        limitations = _require_array(
            findings, _join(location, "limitations"), review["limitations"], "review.limitations"
        )
        if limitations is not None:
            for index, item in enumerate(limitations):
                if not _is_string(item) or not item.strip():
                    findings.error(
                        "invalid-value",
                        "{}.limitations[{}]".format(location, index),
                        "each review limitation must be a non-empty string",
                    )
    else:
        findings.error(
            "missing-required-field",
            _join(location, "limitations"),
            "review is missing the required field 'limitations'",
        )

    release_inclusion = None
    if "release_inclusion" in review:
        release_inclusion = _require_bool(
            findings,
            _join(location, "release_inclusion"),
            review["release_inclusion"],
            "review.release_inclusion",
        )
    else:
        findings.error(
            "missing-required-field",
            _join(location, "release_inclusion"),
            "review is missing the required field 'release_inclusion'",
        )

    if status is not None and release_inclusion is not None:
        if release_inclusion and status != "approved":
            findings.error(
                "unapproved-release",
                _join(location, "release_inclusion"),
                "release_inclusion is true but review.status is {!r}; only approved outputs may "
                "be marked for release".format(status),
            )
        if status == "rejected" and release_inclusion:
            findings.error(
                "unapproved-release",
                _join(location, "release_inclusion"),
                "review.status is 'rejected' but release_inclusion is true",
            )

    for key in ("approval_revision", "technical_check", "perceptual_review"):
        if key in review:
            _require_string(
                findings, _join(location, key), review[key], "review.{}".format(key)
            )
    # An approved or release-included entry is a shipping claim, and the
    # release rights gate blocks "unapproved outputs". "unknown" records the
    # absence of a fact, so an approval whose reviewer, approval revision or
    # technical check is unknown is not an approval record at all; a capable
    # reviewer's actual record is required (docs/BENCHMARKS.md). A pending
    # entry may still carry unknowns while its review is open.
    shipping = status == "approved" or release_inclusion is True
    if shipping:
        if _is_unknown(review.get("reviewer")):
            findings.error(
                "unknown-value",
                _join(location, "reviewer"),
                "review.reviewer is 'unknown' on an approved or release-included entry; record "
                "the actual reviewer (a capable independent agent or a human) that approved "
                "this revision",
            )
        for key in ("approval_revision", "technical_check"):
            value = review.get(key)
            what = {
                "approval_revision": "the revision this approval applies to",
                "technical_check": "the actual technical check result",
            }[key]
            if key not in review or value is None:
                findings.error(
                    "missing-required-field",
                    _join(location, key),
                    "an approved or release-included entry must record review.{}; the release "
                    "rights gate blocks unapproved outputs, and an approval without its revision "
                    "and technical check cannot be reviewed".format(key),
                )
            elif _is_unknown(value):
                findings.error(
                    "unknown-value",
                    _join(location, key),
                    "review.{} is 'unknown' on an approved or release-included entry; record {}, "
                    "or keep the entry pending".format(key, what),
                )


def _validate_lineage(
    findings: Findings,
    location: str,
    value: Any,
    origin: str | None,
    checker: PathChecker,
    allow_unknown_keys: bool,
    known_ids: set[str],
) -> None:
    lineage = _require_mapping(findings, location, value, "lineage")
    if lineage is None:
        return
    _check_known_keys(findings, location, lineage, LINEAGE_KEYS, allow_unknown_keys, "lineage")

    if "upstream_inputs" not in lineage:
        findings.error(
            "missing-required-field",
            _join(location, "upstream_inputs"),
            "lineage is missing the required field 'upstream_inputs'; record [] when the asset "
            "has no upstream inputs",
        )
    else:
        inputs = _require_array(
            findings,
            _join(location, "upstream_inputs"),
            lineage["upstream_inputs"],
            "lineage.upstream_inputs",
        )
        if inputs is not None:
            if origin == "external_cc0" and not inputs:
                # An external asset's evidence trail *is* its upstream inputs:
                # an empty list leaves the CC0 material it derives from
                # unrecorded, so the origin cannot be verified.
                findings.error(
                    "missing-required-field",
                    _join(location, "upstream_inputs"),
                    "an external_cc0 entry must record at least one upstream input with its "
                    "license and item-level CC0 evidence; an empty list leaves the external "
                    "material's lineage unverifiable",
                )
            for index, item in enumerate(inputs):
                _validate_upstream_input(
                    findings,
                    "{}.upstream_inputs[{}]".format(location, index),
                    item,
                    origin,
                    checker,
                    allow_unknown_keys,
                    known_ids,
                )

    for key in ("modifications", "superseded_outputs"):
        if key in lineage:
            items = _require_array(
                findings, _join(location, key), lineage[key], "lineage.{}".format(key)
            )
            if items is not None:
                for index, item in enumerate(items):
                    if not _is_string(item) or not item.strip():
                        findings.error(
                            "invalid-value",
                            "{}.{}[{}]".format(location, key, index),
                            "each {} entry must be a non-empty string".format(key),
                        )

    if "depends_on" in lineage:
        deps = _require_array(
            findings, _join(location, "depends_on"), lineage["depends_on"], "lineage.depends_on"
        )
        if deps is not None:
            for index, asset_id in enumerate(deps):
                where = "{}.depends_on[{}]".format(location, index)
                if not _is_string(asset_id) or not asset_id.strip():
                    findings.error(
                        "invalid-value",
                        where,
                        "each dependency asset ID must be a non-empty string",
                    )
                elif asset_id not in known_ids:
                    findings.error(
                        "dangling-reference",
                        where,
                        "dependency asset ID '{}' is not registered in this manifest".format(asset_id),
                    )


def _validate_upstream_input(
    findings: Findings,
    location: str,
    value: Any,
    origin: str | None,
    checker: PathChecker,
    allow_unknown_keys: bool,
    known_ids: set[str],
) -> None:
    item = _require_mapping(findings, location, value, "upstream input")
    if item is None:
        return
    _check_known_keys(
        findings, location, item, UPSTREAM_INPUT_KEYS, allow_unknown_keys, "upstream input"
    )

    asset_id = item.get("asset_id")
    path = item.get("path")
    if not ((_is_string(asset_id) and asset_id.strip()) or (_is_string(path) and path.strip())):
        findings.error(
            "missing-required-field",
            location,
            "each upstream input needs either an asset_id or a path",
        )
    if _is_string(asset_id) and asset_id.strip() and asset_id not in known_ids:
        findings.error(
            "dangling-reference",
            _join(location, "asset_id"),
            "upstream asset ID '{}' is not registered in this manifest".format(asset_id),
        )
    if _is_string(path) and path.strip():
        checker.check(findings, _join(location, "path"), path, "upstream input path")

    if origin == "external_cc0":
        for key in ("license", "evidence"):
            field = item.get(key)
            if not _is_string(field) or not field.strip() or _is_unknown(field):
                findings.error(
                    "missing-required-field",
                    _join(location, key),
                    "external creative input must record the upstream '{}' with item-level CC0 "
                    "evidence".format(key),
                )

    if "note" in item:
        _require_string(findings, _join(location, "note"), item["note"], "upstream input note")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="validate_manifest.py",
        description=(
            "Validate a Roadstorm Racer! asset manifest (assets/manifest.json) for the "
            "essential provenance and lineage metadata required by "
            "provenance/MANIFEST_CONTRACT.md and the release rights gate in "
            "docs/ASSET_PRODUCTION.md."
        ),
    )
    parser.add_argument(
        "manifest",
        help="path to the manifest JSON file (default: assets/manifest.json in the project root)",
        nargs="?",
        default=None,
    )
    parser.add_argument(
        "--root",
        default=None,
        help="project root that manifest-relative paths resolve against (default: the parent of "
        "the manifest's directory)",
    )
    parser.add_argument(
        "--no-file-checks",
        action="store_true",
        help="do not check that referenced paths exist (structure-only validation)",
    )
    parser.add_argument(
        "--check-hashes",
        action="store_true",
        help="hash every referenced output file and compare it with the recorded SHA-256",
    )
    parser.add_argument(
        "--allow-unknown-keys",
        action="store_true",
        help="report unrecognized fields as warnings instead of errors",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="print findings as a JSON object instead of text lines",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="print only the final summary line",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    manifest_arg = args.manifest
    if manifest_arg is None:
        root_guess = Path(args.root) if args.root else Path.cwd()
        manifest_arg = root_guess / "assets" / "manifest.json"
    manifest_path = Path(manifest_arg)

    if args.root:
        root = Path(args.root)
    else:
        root = manifest_path.resolve().parent.parent

    if not manifest_path.is_file():
        print("[error] manifest file not found: {}".format(manifest_path), file=sys.stderr)
        print("usage: validate_manifest.py [--root <dir>] <manifest.json>", file=sys.stderr)
        return 2

    findings = validate_manifest(
        manifest_path,
        root=root,
        file_checks=not args.no_file_checks,
        check_hashes=args.check_hashes,
        allow_unknown_keys=args.allow_unknown_keys,
    )

    # Exit-code contract (README.md): 2 is for a manifest that could not be
    # read, or a wrong command line - a missing/unreadable file, a nonexistent
    # --root, or bytes that are not JSON at all. A document that decodes but
    # breaks the contract (including invalid UTF-8) is a content defect: 1.
    unreadable = any(f.code in READ_FAILURE_CODES for f in findings.errors)

    if args.as_json:
        payload = {
            "manifest": str(manifest_path),
            "root": str(root),
            "errors": [f.as_dict() for f in findings.errors],
            "warnings": [f.as_dict() for f in findings.warnings],
            "result": "pass" if findings.ok else "fail",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
    else:
        if not args.quiet:
            print("manifest: {}".format(manifest_path))
            print("root:     {}".format(root))
            for finding in findings:
                print(finding.render())
            print("")
        if findings.ok:
            print(
                "asset manifest validation: PASS ({} error(s), {} warning(s))".format(
                    len(findings.errors), len(findings.warnings)
                )
            )
        else:
            print(
                "asset manifest validation: FAIL ({} error(s), {} warning(s))".format(
                    len(findings.errors), len(findings.warnings)
                )
            )

    if unreadable:
        if not args.as_json and not args.quiet:
            print(
                "the manifest could not be read as a JSON record: {}".format(manifest_path),
                file=sys.stderr,
            )
        return 2
    return 0 if findings.ok else 1


if __name__ == "__main__":  # pragma: no cover - CLI entry point
    sys.exit(main())
