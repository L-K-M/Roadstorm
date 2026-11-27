#!/usr/bin/env python3
"""Tests for tools/asset_manifest/manifest_validator.py.

Ownership: tools/asset_manifest/** (PLAN.md M0 provenance manifest tooling,
job 6058a51e-ae48-4329-8fb0-52c3c36eddad).

Run from anywhere with:

    python3 -m unittest discover -s tools/asset_manifest/tests \
        -t tools/asset_manifest -v

or with the wrapper:

    tools/asset_manifest/run_tests.sh

The fixtures are written into temporary directories; nothing here touches the
shared checkout except the read-only check of the shipped
assets/manifest.json.

Original project code under the Unlicense.
"""

from __future__ import annotations

import builtins
import contextlib
import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

_TOOL_DIR = Path(__file__).resolve().parents[1]  # tools/asset_manifest
_REPO_ROOT = _TOOL_DIR.parents[1]  # the project checkout
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

import manifest_validator  # noqa: E402  (path set up above)
from manifest_validator import (  # noqa: E402  (path set up above)
    MANIFEST_ID,
    SCHEMA_VERSION,
    Findings,
    _reference_target,
    main,
    validate_manifest,
)

SHIPPED_MANIFEST = _REPO_ROOT / "assets" / "manifest.json"


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------


def complete_entry(entry_id: str = "car.fixture.body") -> dict:
    """A complete, structurally valid first-party entry (content is a fixture)."""
    return {
        "id": entry_id,
        "category": "car",
        "origin": "llm_script_generated",
        "authoring": {
            "task": "M7.2",
            "agent": "unknown",
            "provider": "unknown",
            "model": "unknown",
            "date": "unknown",
        },
        "identity": {
            "source_paths": ["assets/source/fixture/recipe.json"],
            "output_paths": ["assets/generated/fixture/body.res"],
        },
        "hashes": {},
        "generation": {
            "generator": "tools/bake/fixture_baker.gd",
            "generator_version": "unknown",
            "recipe_path": "content/fixture/recipe.json",
            "seed": 0,
            "input_asset_ids": [],
            "regeneration_command": "godot --headless --script tools/bake/fixture_baker.gd -- content/fixture/recipe.json",
            "tool_versions": {"godot": "4.7.2.stable"},
        },
        "reproducibility_class": "canonical_deterministic",
        "rights": {
            "license_spdx": "CC0-1.0",
            "rights_holder_record": "provenance/OWNER_AUTHORITY.md",
            "rights_basis": "fixture reference to the project authority instrument",
            "service_terms_ref": "not_applicable",
        },
        "review": {
            "status": "approved",
            "reviewer": "fixture-reviewer",
            "approval_revision": "fixture-rev-1",
            "technical_check": "fixture: structure verified by the manifest validator tests",
            "perceptual_review": "not applicable: fixture entry with no rendered output",
            "limitations": ["fixture entry; no real asset"],
            "release_inclusion": True,
        },
        "lineage": {
            "upstream_inputs": [],
            "modifications": [],
            "superseded_outputs": [],
            "depends_on": [],
        },
    }


REAL_TERMS_REGISTER = _REPO_ROOT / "provenance" / "PROVIDER_TERMS.md"


def write_terms_register(root: Path, route_ids) -> Path:
    """Write a register fixture whose rows are exactly ``route_ids``.

    Mirrors the real register's shape (one backticked route ID per row of the
    observed-routes table) so row resolution is exercised against the same
    text form the checkout uses.
    """
    rows = "".join(
        "| `{}` | fixture service route | fixture-model | fixture terms | fixture basis | "
        "fixture output | OPEN / BLOCKING |\n".format(route_id)
        for route_id in route_ids
    )
    path = root / "provenance" / "PROVIDER_TERMS.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "# Provider-terms intake (fixture)\n\n"
        "## Observed authoring routes\n\n"
        "| Route ID | Service / API route | Model(s) observed | Terms document, version, "
        "date | Input-rights basis | Output redistribution / dedication compatibility | "
        "Verification |\n"
        "| --- | --- | --- | --- | --- | --- | --- |\n" + rows,
        encoding="utf-8",
    )
    return path


def copy_real_terms_register(root: Path) -> Path:
    """Copy the checkout's real register into a fixture root (read-only source)."""
    path = root / "provenance" / "PROVIDER_TERMS.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(REAL_TERMS_REGISTER, path)
    return path


def touch(root: Path, relative: str) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("fixture bytes for " + relative + "\n", encoding="utf-8")
    return path


def digest_of(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def service_entry(root: Path, entry_id: str = "texture.service.sky") -> dict:
    """A structurally valid service-generated entry, with its files created."""
    entry = materialize(root, complete_entry(entry_id))
    entry["origin"] = "service_generated"
    entry["reproducibility_class"] = "frozen_service_output"
    return entry


def materialize(root: Path, entry: dict) -> dict:
    """Create the files an entry references and record their real hashes."""
    for relative in entry["identity"]["source_paths"]:
        touch(root, relative)
    for relative in entry["identity"]["output_paths"]:
        touch(root, relative)
    if entry["generation"].get("recipe_path"):
        touch(root, entry["generation"]["recipe_path"])
    # The rights record the entry links to must exist for the reference to
    # resolve (the fixtures point at the project authority instrument).
    holder = entry.get("rights", {}).get("rights_holder_record")
    if isinstance(holder, str) and holder.strip():
        touch(root, _reference_target(holder))
    entry["hashes"] = {
        relative: digest_of(root / relative) for relative in entry["identity"]["output_paths"]
    }
    return entry


def with_output(entry: dict, relative: str) -> dict:
    """Point an entry at its own output path.

    Each registered output path has exactly one owning entry, so fixtures that
    register more than one entry must give each of them a distinct output.
    """
    entry["identity"]["output_paths"] = [relative]
    return entry


def write_manifest(root: Path, entries: list, status: str = "populated", **extra) -> Path:
    document = {
        "manifest_id": MANIFEST_ID,
        "schema_version": SCHEMA_VERSION,
        "registry_status": status,
        "assets": entries,
    }
    document.update(extra)
    path = root / "assets" / "manifest.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    return path


def validate(root: Path, manifest: Path, **kwargs) -> Findings:
    return validate_manifest(manifest, root=root, **kwargs)


def error_codes(findings: Findings) -> list[str]:
    return [f.code for f in findings.errors]


def messages(findings: Findings) -> str:
    return "\n".join(f.render() for f in findings)


def bounded_call(func, timeout: float = 30):
    """Run ``func`` in a worker thread; return ``(result, timed_out)``.

    A read that blocks - a FIFO with no writer - would otherwise hang the
    suite instead of failing it. The deadline is part of the assertion, so the
    caller must check ``timed_out`` rather than trusting a ``None`` result. An
    exception raised by ``func`` is re-raised here, never swallowed into a
    ``None`` that a refusal assertion would accept.
    """
    outcome: dict = {}

    def run() -> None:
        try:
            outcome["result"] = func()
        except BaseException as exc:  # noqa: BLE001 - re-raised below
            outcome["error"] = exc

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    worker.join(timeout)
    if worker.is_alive():
        return None, True
    if "error" in outcome:
        raise outcome["error"]
    return outcome.get("result"), False


REGISTER_BASENAME = "PROVIDER_TERMS.md"

_UNIX_MODE_SKIP = (
    "Unix mode-000 read control needs os.geteuid(); Windows ACL coverage is "
    "in WindowsNativeGuardTestCase"
)


def require_unix_mode_controls(case) -> None:
    """Skip a mode-000 test unless Unix permission bits can deny a read.

    ``os.chmod(0)`` does not model a Windows ACL denial, so these controls are
    Unix-specific by construction; the native ACL equivalents live in
    ``WindowsNativeGuardTestCase``.
    """
    geteuid = getattr(os, "geteuid", None)
    if geteuid is None:
        case.skipTest(_UNIX_MODE_SKIP)
    if geteuid() == 0:
        case.skipTest("running as root: permission bits do not block reads")


class ReadAttempts:
    """What a validation run actually did to the provider-terms register.

    ``entered`` records calls into the module's read path
    (``manifest_validator._read_record_text``); ``opened`` records raw open
    attempts at the OS level (``os.open``, ``builtins.open``,
    ``Path.read_text``, ``Path.read_bytes``); ``guarded`` records every call
    through the shared guarded-open primitive together with its result, which
    is the platform-neutral way to see an actual successful open - Windows
    uses ``CreateFileW``, invisible to ``os.open``. A rejected register path
    must appear nowhere as a successful guarded open.
    """

    def __init__(self) -> None:
        self.entered: list[str] = []
        self.opened: list[str] = []
        self.guarded: list[tuple[str, object]] = []

    def note_entered(self, target) -> None:
        self.entered.append(str(target))

    def note_opened(self, target) -> None:
        self.opened.append(str(target))

    def note_guarded(self, target, descriptor) -> None:
        self.guarded.append((str(target), descriptor))

    def register_guards(self):
        """Guarded-open results for paths naming the register."""
        return [descriptor for path, descriptor in self.guarded if REGISTER_BASENAME in path]

    def __repr__(self) -> str:  # pragma: no cover - diagnostics only
        return "ReadAttempts(entered={!r}, opened={!r}, guarded={!r})".format(
            self.entered, self.opened, self.guarded
        )


@contextlib.contextmanager
def spy_on_register_reads():
    """Instrument every way the register could be read, and yield the record.

    Both the documented read path and the raw calls that could bypass it are
    wrapped, so a regression that reads the register some other way is seen as
    an open attempt instead of passing silently. Only paths naming the register
    are recorded; the wrappers delegate to the real functions unchanged.
    """
    attempts = ReadAttempts()
    stack = contextlib.ExitStack()
    real_os_open = os.open
    real_builtin_open = builtins.open
    real_read_text = Path.read_text
    real_read_bytes = Path.read_bytes
    real_read_record_text = getattr(manifest_validator, "_read_record_text", None)
    real_guarded_open = manifest_validator._open_regular_file_descriptor

    def spy_os_open(path, *args, **kwargs):
        if REGISTER_BASENAME in str(path):
            attempts.note_opened(path)
        return real_os_open(path, *args, **kwargs)

    def spy_builtin_open(file, *args, **kwargs):
        if REGISTER_BASENAME in str(file):
            attempts.note_opened(file)
        return real_builtin_open(file, *args, **kwargs)

    def spy_read_text(self, *args, **kwargs):
        if REGISTER_BASENAME in str(self):
            attempts.note_opened(self)
        return real_read_text(self, *args, **kwargs)

    def spy_read_bytes(self):
        if REGISTER_BASENAME in str(self):
            attempts.note_opened(self)
        return real_read_bytes(self)

    def spy_read_record_text(root, relative):
        attempts.note_entered(root / relative)
        return real_read_record_text(root, relative)

    def spy_guarded_open(root, relative):
        descriptor = real_guarded_open(root, relative)
        # The manifest input calls the primitive with root=None and an
        # absolute path; record that spelling too.
        target = Path(relative) if root is None else root / relative
        attempts.note_guarded(target, descriptor)
        return descriptor

    try:
        stack.enter_context(mock.patch.object(os, "open", spy_os_open))
        stack.enter_context(mock.patch.object(builtins, "open", spy_builtin_open))
        stack.enter_context(mock.patch.object(Path, "read_text", spy_read_text))
        stack.enter_context(mock.patch.object(Path, "read_bytes", spy_read_bytes))
        stack.enter_context(
            mock.patch.object(
                manifest_validator, "_open_regular_file_descriptor", spy_guarded_open
            )
        )
        if real_read_record_text is not None:
            stack.enter_context(
                mock.patch.object(
                    manifest_validator, "_read_record_text", spy_read_record_text
                )
            )
        yield attempts
    finally:
        stack.close()


class ManifestValidatorTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    # -- the shipped manifest ------------------------------------------------

    def test_shipped_empty_manifest_passes(self):
        """The committed empty registry must validate with zero errors."""
        self.assertTrue(SHIPPED_MANIFEST.is_file(), "assets/manifest.json is missing")
        findings = validate(_REPO_ROOT, SHIPPED_MANIFEST)
        self.assertEqual(
            findings.errors,
            [],
            "the shipped empty manifest must validate cleanly:\n" + messages(findings),
        )
        self.assertEqual(findings.warnings, [], messages(findings))

    def test_shipped_empty_manifest_declares_no_assets(self):
        """An empty manifest must not imply that milestone content exists."""
        document = json.loads(SHIPPED_MANIFEST.read_text(encoding="utf-8"))
        self.assertEqual(document["registry_status"], "empty")
        self.assertEqual(document["assets"], [])
        joined = " ".join(document.get("notes", [])).lower()
        self.assertIn("empty", joined)
        # The note must not read as a claim that any inventory is complete.
        self.assertNotIn("complete", joined)

    def test_shipped_manifest_hashes_optionally_verifiable(self):
        """--check-hashes on the empty manifest is a trivial pass."""
        findings = validate(_REPO_ROOT, SHIPPED_MANIFEST, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    # -- required entries ----------------------------------------------------

    def test_missing_required_entry_fields_are_errors(self):
        entry = materialize(self.root, complete_entry())
        del entry["rights"]
        del entry["lineage"]
        del entry["identity"]["output_paths"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("missing-required-field", codes)
        text = messages(findings)
        self.assertIn("'rights'", text)
        self.assertIn("'lineage'", text)
        self.assertIn("'output_paths'", text)

    def test_missing_required_manifest_fields_are_errors(self):
        manifest = write_manifest(self.root, [])
        document = json.loads(manifest.read_text(encoding="utf-8"))
        del document["registry_status"]
        del document["schema_version"]
        manifest.write_text(json.dumps(document), encoding="utf-8")
        findings = validate(self.root, manifest)
        text = messages(findings)
        self.assertIn("'registry_status'", text)
        self.assertIn("'schema_version'", text)

    def test_missing_hash_for_output_path_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        entry["hashes"] = {}
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("missing-hash", error_codes(findings))

    def test_missing_recipe_and_regeneration_for_first_party(self):
        entry = materialize(self.root, complete_entry())
        del entry["generation"]["recipe_path"]
        del entry["generation"]["regeneration_command"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        text = messages(findings)
        self.assertIn("'recipe_path'", text)
        self.assertIn("'regeneration_command'", text)

    # -- duplicate stable IDs ------------------------------------------------

    def test_duplicate_stable_ids_are_errors(self):
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(self.root, complete_entry("car.fixture.body"))
        manifest = write_manifest(self.root, [first, second])
        findings = validate(self.root, manifest)
        self.assertIn("duplicate-id", error_codes(findings))
        self.assertIn("car.fixture.body", messages(findings))

    def test_distinct_stable_ids_pass(self):
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(
            self.root,
            with_output(complete_entry("car.fixture.wing"), "assets/generated/fixture/wing.res"),
        )
        manifest = write_manifest(self.root, [first, second])
        findings = validate(self.root, manifest)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_invalid_stable_id_spelling_is_an_error(self):
        entry = materialize(self.root, complete_entry("Car Fixture/Body"))
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("invalid-id", error_codes(findings))

    # -- missing referenced files -------------------------------------------

    def test_missing_referenced_files_are_errors(self):
        entry = complete_entry()
        # Referenced paths are never created on disk.
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertEqual(codes.count("missing-file"), 3, messages(findings))
        text = messages(findings)
        self.assertIn("assets/source/fixture/recipe.json", text)
        self.assertIn("assets/generated/fixture/body.res", text)
        self.assertIn("content/fixture/recipe.json", text)

    def test_no_file_checks_skips_existence_but_keeps_structure(self):
        entry = complete_entry()
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, file_checks=False)
        self.assertNotIn("missing-file", error_codes(findings))

    def test_paths_must_be_clean_and_relative(self):
        entry = materialize(self.root, complete_entry())
        entry["identity"]["source_paths"] = ["/etc/passwd"]
        entry["identity"]["output_paths"] = ["assets\\generated\\fixture\\body.res"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertEqual(error_codes(findings).count("invalid-path"), 2, messages(findings))

    def test_check_hashes_detects_mismatch_and_match(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        self.assertEqual(validate(self.root, manifest, check_hashes=True).errors, [])
        # Corrupt the recorded hash.
        document = json.loads(manifest.read_text(encoding="utf-8"))
        document["assets"][0]["hashes"]["assets/generated/fixture/body.res"] = "sha256:" + "0" * 64
        manifest.write_text(json.dumps(document), encoding="utf-8")
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertIn("hash-mismatch", error_codes(findings))

    def test_seed_must_not_be_a_boolean(self):
        """bool is a subclass of int, so True must not pass as seed 1."""
        entry = materialize(self.root, complete_entry())
        entry["generation"]["seed"] = True
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("invalid-value", error_codes(findings))
        self.assertIn("seed", messages(findings))

    def test_seed_accepts_strings_integers_and_null(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        for seed in (0, 42, "2026-11-26-fixture", None):
            entry["generation"]["seed"] = seed
            manifest = write_manifest(self.root, [entry])
            self.assertEqual(
                validate(self.root, manifest).errors, [],
                "seed {!r} must be accepted".format(seed),
            )

    def test_symlinked_reference_is_rejected(self):
        """A symlink can vouch for a file outside the root the entry does not govern."""
        entry = complete_entry()
        touch(self.root, "assets/source/fixture/recipe.json")
        touch(self.root, "content/fixture/recipe.json")
        # A real file elsewhere, symlinked into the referenced output location.
        real = self.root / "content" / "real" / "body.res"
        real.parent.mkdir(parents=True, exist_ok=True)
        real.write_text("real bytes\n", encoding="utf-8")
        link = self.root / "assets" / "generated" / "fixture" / "body.res"
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(real)
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("symlinked-path", codes)
        self.assertNotIn("hash-mismatch", codes)

    def test_symlink_escaping_the_root_is_rejected(self):
        entry = complete_entry()
        touch(self.root, "assets/source/fixture/recipe.json")
        touch(self.root, "content/fixture/recipe.json")
        outside = self.root.parent / ("roadstorm-fixture-target-" + self.root.name)
        outside.write_text("outside the checkout\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        link = self.root / "assets" / "generated" / "fixture" / "body.res"
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(outside)
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertIn("symlinked-path", error_codes(findings))

    def test_symlinked_parent_directory_is_rejected(self):
        """Independent failure: a symlinked intermediate directory escapes the root.

        The leaf is a regular file, so a final-component-only symlink check
        lets the reference through, and --check-hashes then vouches for a file
        outside the checkout that the entry does not govern.
        """
        entry = materialize(self.root, complete_entry())
        outside = self.root.parent / ("roadstorm-fixture-dir-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "body.res").write_text("outside the checkout\n", encoding="utf-8")
        link = self.root / "assets" / "generated" / "fixture" / "etcdir"
        link.symlink_to(outside)
        entry["identity"]["output_paths"] = ["assets/generated/fixture/etcdir/body.res"]
        entry["hashes"] = {
            "assets/generated/fixture/etcdir/body.res": digest_of(outside / "body.res")
        }
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("symlinked-path", codes)
        self.assertIn("etcdir", messages(findings))
        # A hash-mismatch here would prove the file outside the root was read.
        self.assertNotIn("hash-mismatch", codes)

    def test_symlinked_parent_directory_is_rejected_for_every_reference(self):
        """Source paths and recipe paths are gated by the same rule."""
        entry = materialize(self.root, complete_entry())
        outside = self.root.parent / ("roadstorm-fixture-dir-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "recipe.json").write_text("outside the checkout\n", encoding="utf-8")
        link = self.root / "assets" / "source" / "fixture" / "etcdir"
        link.symlink_to(outside)
        entry["identity"]["source_paths"] = ["assets/source/fixture/etcdir/recipe.json"]
        entry["generation"]["recipe_path"] = "assets/source/fixture/etcdir/recipe.json"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(error_codes(findings).count("symlinked-path"), 2, messages(findings))
        self.assertNotIn("hash-mismatch", error_codes(findings))

    def test_cli_symlinked_parent_directory_exits_1(self):
        """End to end: the CLI must not PASS a manifest that escapes through a parent."""
        entry = materialize(self.root, complete_entry())
        outside = self.root.parent / ("roadstorm-fixture-dir-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "body.res").write_text("outside the checkout\n", encoding="utf-8")
        link = self.root / "assets" / "generated" / "fixture" / "etcdir"
        link.symlink_to(outside)
        entry["identity"]["output_paths"] = ["assets/generated/fixture/etcdir/body.res"]
        entry["hashes"] = {
            "assets/generated/fixture/etcdir/body.res": digest_of(outside / "body.res")
        }
        manifest = write_manifest(self.root, [entry])
        self.assertEqual(
            main([str(manifest), "--root", str(self.root), "--check-hashes", "--quiet"]), 1
        )

    def test_digest_refuses_a_path_through_a_symlinked_parent(self):
        """The hash access itself refuses, not only the existence check."""
        entry = materialize(self.root, complete_entry())
        checker = manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )
        self.assertEqual(
            checker.digest(entry["identity"]["output_paths"][0]),
            hashlib.sha256((self.root / entry["identity"]["output_paths"][0]).read_bytes()).hexdigest(),
        )
        outside = self.root.parent / ("roadstorm-fixture-dir-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "body.res").write_text("outside the checkout\n", encoding="utf-8")
        link = self.root / "assets" / "generated" / "fixture" / "etcdir"
        link.symlink_to(outside)
        self.assertIsNone(checker.digest("assets/generated/fixture/etcdir/body.res"))

    def test_hash_step_rejects_a_symlink_swapped_in_after_the_existence_check(self):
        """Race-aware: the file can become a symlink between check and hash.

        The existence check accepts the real file; the swap happens inside the
        hash step, exactly as a TOCTOU race would. Hashing must re-validate
        the path instead of trusting the earlier check.
        """
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        outside = self.root.parent / ("roadstorm-fixture-swap-" + self.root.name)
        outside.write_text("swapped in after the check\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        original_digest = manifest_validator.PathChecker.digest

        def racing_digest(checker, relative):
            target = checker.root / relative
            if target.is_file() and not target.is_symlink():
                target.unlink()
                target.symlink_to(outside)
            return original_digest(checker, relative)

        with mock.patch.object(manifest_validator.PathChecker, "digest", racing_digest):
            findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("missing-file", codes)
        self.assertNotIn("hash-mismatch", codes)

    def test_hash_step_rejects_a_parent_swapped_for_a_symlink_after_the_check(self):
        """Race-aware: a parent directory can be replaced by a symlink mid-pass."""
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        outside = self.root.parent / ("roadstorm-fixture-parent-swap-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        fixture_dir = self.root / "assets" / "generated" / "fixture"
        original_digest = manifest_validator.PathChecker.digest
        swapped: list[bool] = []

        def racing_digest(checker, relative):
            if not swapped:
                swapped.append(True)
                (fixture_dir / "body.res").rename(outside / "body.res")
                fixture_dir.rmdir()
                fixture_dir.symlink_to(outside)
            return original_digest(checker, relative)

        with mock.patch.object(manifest_validator.PathChecker, "digest", racing_digest):
            findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("missing-file", codes)
        self.assertNotIn("hash-mismatch", codes)

    def test_check_hashes_does_not_hash_paths_outside_the_root(self):
        """Independent failure: malformed output_paths must not make /etc/hosts hashed."""
        entry = complete_entry()
        # output_paths is not an array, so identity never validates the keys.
        entry["identity"]["output_paths"] = "assets/generated/fixture/body.res"
        entry["hashes"] = {"/etc/hosts": "sha256:" + "0" * 64}
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("not-an-array", codes)
        self.assertIn("invalid-path", codes)
        # A hash-mismatch here would prove the file outside the root was read.
        self.assertNotIn("hash-mismatch", codes)
        self.assertIn("/etc/hosts", messages(findings))

    def test_check_hashes_does_not_hash_through_a_symlinked_parent(self):
        """Independent failure: a malformed output_paths leaves the key to the hash step."""
        entry = materialize(self.root, complete_entry())
        outside = self.root.parent / ("roadstorm-fixture-dir-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "body.res").write_text("outside the checkout\n", encoding="utf-8")
        link = self.root / "assets" / "generated" / "fixture" / "etcdir"
        link.symlink_to(outside)
        # output_paths is not an array, so identity never validates the key.
        entry["identity"]["output_paths"] = "assets/generated/fixture/etcdir/body.res"
        entry["hashes"] = {
            "assets/generated/fixture/etcdir/body.res": digest_of(outside / "body.res")
        }
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("not-an-array", codes)
        # The hash step refused the key instead of hashing through the link.
        self.assertIn("missing-file", codes)
        self.assertNotIn("hash-mismatch", codes)

    # -- hashing refuses what it cannot safely read -------------------------
    # (2026-11-27 Sol recheck finding 1 / Opus independent finding F2: an
    # unreadable or swapped output used to raise out of the hash step.)

    def test_digest_hashes_a_regular_output_file(self):
        """Positive control: a readable regular output hashes normally."""
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        checker = manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )
        self.assertEqual(checker.digest(relative), digest_of(self.root / relative)[len("sha256:"):])
        findings = validate(self.root, write_manifest(self.root, [entry]), check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_unreadable_output_is_a_structured_finding_not_a_traceback(self):
        """Independent failure: a mode-000 output fails closed, with a finding."""
        require_unix_mode_controls(self)
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        target = self.root / relative
        target.chmod(0)
        self.addCleanup(target.chmod, 0o644)
        manifest = write_manifest(self.root, [entry])
        checker = manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )
        self.assertIsNone(checker.digest(relative))
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("missing-file", codes)
        text = messages(findings)
        self.assertIn("cannot hash", text)
        self.assertIn("unreadable", text)
        self.assertNotIn("hash-mismatch", codes)

    def test_unreadable_output_cli_emits_json_instead_of_a_traceback(self):
        """End to end: the CLI reports the structured finding, not a traceback."""
        require_unix_mode_controls(self)
        import contextlib
        import io

        entry = materialize(self.root, complete_entry())
        target = self.root / entry["identity"]["output_paths"][0]
        target.chmod(0)
        self.addCleanup(target.chmod, 0o644)
        manifest = write_manifest(self.root, [entry])
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main(
                [str(manifest), "--root", str(self.root), "--check-hashes", "--json"]
            )
        self.assertEqual(exit_code, 1)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["result"], "fail")
        self.assertEqual([error["code"] for error in payload["errors"]], ["missing-file"])
        self.assertEqual(stderr.getvalue(), "")

    def test_oversized_json_integer_is_an_invalid_json_finding(self):
        """Independent failure: a huge integer literal must not escape as ValueError."""
        limit = getattr(sys, "get_int_max_str_digits", lambda: 0)()
        if not limit:
            self.skipTest("this interpreter has no integer digit limit")
        manifest = self.write_raw('{"schema_version": ' + ("9" * (limit + 100)) + "}")
        findings = validate(self.root, manifest)
        self.assertIn("invalid-json", error_codes(findings))
        self.assertIn("not valid JSON", messages(findings))

    def test_oversized_json_integer_cli_exits_2_with_json(self):
        """End to end: the decode failure keeps the documented exit contract."""
        import contextlib
        import io

        limit = getattr(sys, "get_int_max_str_digits", lambda: 0)()
        if not limit:
            self.skipTest("this interpreter has no integer digit limit")
        manifest = self.write_raw('{"schema_version": ' + ("9" * (limit + 100)) + "}")
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main([str(manifest), "--root", str(self.root), "--json"])
        self.assertEqual(exit_code, 2)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["result"], "fail")
        self.assertEqual([error["code"] for error in payload["errors"]], ["invalid-json"])
        self.assertEqual(stderr.getvalue(), "")

    def test_digest_refuses_a_fifo_swapped_in_at_the_open_boundary(self):
        """The fd-level defenses are exercised, not just the path checks.

        The pre-check is replaced by one that swaps the real output for a FIFO
        at the moment it is asked, exactly the window between the path check
        and the open. The guarded open must refuse it without blocking, and the
        outside content must never be hashed.
        """
        if not hasattr(os, "mkfifo"):
            self.skipTest("this platform has no FIFOs")
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        target = self.root / relative
        checker = manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )

        def swapped_pre_check(root, spelled):
            target.unlink()
            os.mkfifo(target)
            return True

        with mock.patch.object(manifest_validator, "_record_file_is_readable", swapped_pre_check):
            digest, timed_out = bounded_call(lambda: checker.digest(relative))
        self.assertFalse(timed_out, "digest blocked on a FIFO swapped in at the open boundary")
        self.assertIsNone(digest)

    def test_digest_refuses_a_symlink_swapped_in_at_the_open_boundary(self):
        """A leaf swapped for a symlink at the open boundary is not followed."""
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        target = self.root / relative
        outside = self.root.parent / ("roadstorm-fixture-hash-swap-" + self.root.name)
        outside.write_text("outside the checkout\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        outside_digest = digest_of(outside)
        checker = manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )

        def swapped_pre_check(root, spelled):
            target.unlink()
            target.symlink_to(outside)
            return True

        with mock.patch.object(manifest_validator, "_record_file_is_readable", swapped_pre_check):
            digest, timed_out = bounded_call(lambda: checker.digest(relative))
        self.assertFalse(timed_out)
        self.assertIsNone(digest)
        self.assertNotEqual(digest, outside_digest)
        # Full validation reports the refusal rather than a hash mismatch, so
        # the recorded hash can never be satisfied by the file outside.
        findings = validate(self.root, write_manifest(self.root, [entry]), check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("missing-file", codes)
        self.assertNotIn("hash-mismatch", codes)

    @unittest.skipUnless(
        os.name != "nt",
        "POSIX-only control: on Windows the guarded open uses CreateFileW, not "
        "O_NOFOLLOW/O_NONBLOCK (see WindowsGuardedOpenTestCase)",
    )
    def test_guarded_open_fails_closed_without_fd_protections(self):
        """Where no-follow/non-blocking flags are unavailable, reads refuse."""
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        checker = manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )
        register = write_terms_register(self.root, ["pi-stepfun"])
        self.assertTrue(register.is_file())
        with mock.patch.object(manifest_validator, "_guarded_open_flags", lambda: None):
            self.assertIsNone(checker.digest(relative))
            self.assertIsNone(
                manifest_validator._read_record_text(
                    self.root, manifest_validator.PROVIDER_TERMS_REGISTER
                )
            )

    def test_malformed_hash_spelling_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        entry["hashes"]["assets/generated/fixture/body.res"] = "0" * 64
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("invalid-hash", error_codes(findings))

    # -- registry status -----------------------------------------------------

    def test_empty_status_with_entries_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry], status="empty")
        findings = validate(self.root, manifest)
        self.assertIn("registry-status-mismatch", error_codes(findings))

    def test_populated_status_without_entries_is_an_error(self):
        manifest = write_manifest(self.root, [], status="populated")
        findings = validate(self.root, manifest)
        self.assertIn("registry-status-mismatch", error_codes(findings))

    # -- rights and legal origin --------------------------------------------

    def test_unknown_legal_origin_blocks(self):
        entry = materialize(self.root, complete_entry())
        entry["rights"]["license_spdx"] = "unknown"
        entry["rights"]["rights_holder_record"] = "unknown"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertEqual(error_codes(findings).count("unknown-legal-origin"), 2, messages(findings))

    def test_disallowed_first_party_license_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        entry["rights"]["license_spdx"] = "LicenseRef-Commercial"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("disallowed-license", error_codes(findings))

    def test_external_cc0_requires_item_level_evidence(self):
        entry = materialize(self.root, complete_entry("prop.external.rock"))
        entry["origin"] = "external_cc0"
        entry["rights"]["license_spdx"] = "CC0-1.0"
        entry["rights"]["upstream"] = {"url": "https://example.invalid/rock", "date": "unknown"}
        entry["generation"].pop("recipe_path")
        entry["generation"].pop("regeneration_command")
        entry["lineage"]["upstream_inputs"] = [
            {"path": "assets/source/external/rock.obj", "license": "unknown"}
        ]
        manifest = write_manifest(self.root, [entry])
        touch(self.root, "assets/source/external/rock.obj")
        findings = validate(self.root, manifest)
        text = messages(findings)
        self.assertIn("upstream.evidence", text)
        self.assertIn("upstream_inputs[0].evidence", text)

    def test_external_cc0_rejects_non_cc0_license(self):
        entry = materialize(self.root, complete_entry("prop.external.rock"))
        entry["origin"] = "external_cc0"
        entry["rights"]["license_spdx"] = "CC-BY-4.0"
        entry["generation"].pop("recipe_path")
        entry["generation"].pop("regeneration_command")
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("disallowed-license", error_codes(findings))

    def test_service_generated_requires_terms_reference(self):
        entry = materialize(self.root, complete_entry("texture.service.sky"))
        entry["origin"] = "service_generated"
        entry["rights"]["service_terms_ref"] = "unknown"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unknown-legal-origin", error_codes(findings))

    def test_service_generated_terms_reference_cannot_be_omitted(self):
        """Independent failure: the gate must not be bypassable by omission."""
        entry = materialize(self.root, complete_entry("texture.service.sky"))
        entry["origin"] = "service_generated"
        del entry["rights"]["service_terms_ref"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("missing-required-field", codes)
        self.assertIn("service_terms_ref", messages(findings))

    def test_service_generated_terms_reference_null_is_an_error(self):
        entry = materialize(self.root, complete_entry("texture.service.sky"))
        entry["origin"] = "service_generated"
        entry["rights"]["service_terms_ref"] = None
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("missing-required-field", error_codes(findings))

    def test_service_generated_rejects_the_first_party_placeholder(self):
        """Independent failure: 'not_applicable' is the first-party sentinel, not terms."""
        entry = service_entry(self.root)
        entry["rights"]["service_terms_ref"] = "not_applicable"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unknown-legal-origin", codes)
        self.assertIn("not_applicable", messages(findings))

    def test_service_generated_rejects_an_arbitrary_terms_string(self):
        """Independent failure: a string that names no terms record is not terms."""
        entry = service_entry(self.root)
        entry["rights"]["service_terms_ref"] = "x"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("service_terms_ref", messages(findings))

    def test_service_generated_rejects_a_nonexistent_terms_record(self):
        entry = service_entry(self.root)
        entry["rights"]["service_terms_ref"] = "provenance/provider_terms/pi-stepfun/INTAKE.md"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unresolved-reference", codes)
        self.assertIn("pi-stepfun", messages(findings))

    def test_service_generated_rejects_a_terms_reference_outside_provenance(self):
        entry = service_entry(self.root)
        entry["rights"]["service_terms_ref"] = "docs/someone-elses-terms.md"
        touch(self.root, "docs/someone-elses-terms.md")
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))

    def test_service_generated_accepts_the_terms_register_with_a_route_anchor(self):
        """Positive control: the anchor names a row that exists in the register."""
        entry = service_entry(self.root)
        write_terms_register(self.root, ["pi-stepfun", "pi-longcat"])
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-stepfun"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_service_generated_rejects_an_invented_register_fragment(self):
        """Independent failure: a '#route-id' for a row that was never written."""
        entry = service_entry(self.root)
        write_terms_register(self.root, ["pi-stepfun", "pi-longcat"])
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#missing-fixture-route"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("unresolved-reference", codes)
        text = messages(findings)
        self.assertIn("missing-fixture-route", text)
        self.assertIn("no row for that route exists", text)

    def test_service_generated_rejects_a_wrongly_cased_register_fragment(self):
        """Route IDs are identifiers: the row 'pi-stepfun' is not 'PI-STEPFUN'."""
        entry = service_entry(self.root)
        write_terms_register(self.root, ["pi-stepfun"])
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#PI-STEPFUN"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("PI-STEPFUN", messages(findings))

    def test_service_generated_rejects_a_bare_register_anchor(self):
        """A trailing '#' names no route row."""
        entry = service_entry(self.root)
        write_terms_register(self.root, ["pi-stepfun"])
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))

    def test_service_generated_accepts_a_real_register_route_row(self):
        """End to end against the checkout's real register: 'pi-stepfun' is a row."""
        entry = service_entry(self.root)
        copy_real_terms_register(self.root)
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-stepfun"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_service_generated_rejects_an_unregistered_route_against_the_real_register(self):
        """The real register's rows resolve; anything else is an invented fragment.

        The register is a living record - rows are added as routes are observed -
        so the fragment may not hard-code a route that happens to be absent
        today. It is therefore chosen against the rows the register currently
        records and asserted absent, which keeps the check meaningful whichever
        rows the checkout holds. (This test previously named ``pi-mistral``,
        which the register gained in a later provenance commit, so it stopped
        testing anything.)
        """
        entry = service_entry(self.root)
        copy_real_terms_register(self.root)
        recorded = manifest_validator._terms_register_route_ids(self.root)
        self.assertIsNotNone(recorded, "the real register must be readable")
        self.assertTrue(recorded, "the real register must record at least one route")
        invented = "pi-no-such-route"
        while invented in recorded:
            invented += "-x"
        entry["rights"]["service_terms_ref"] = (
            "provenance/PROVIDER_TERMS.md#" + invented
        )
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn(invented, messages(findings))

    def test_route_row_resolution_is_skipped_without_file_checks(self):
        """Reading the register is resolution: --no-file-checks stays structural."""
        entry = service_entry(self.root)
        write_terms_register(self.root, ["pi-stepfun"])
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-missing"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, file_checks=False)
        self.assertNotIn("unresolved-reference", error_codes(findings))

    # -- a rejected register path is refused, never read --------------------
    # (M0 checkpoint recheck, Sol 2026-11-27, finding 3: the fragment checker
    # read the register after the path validator had rejected it.)

    def register_reference_manifest(self, reference: str) -> Path:
        """A service entry whose terms reference is ``reference``."""
        entry = service_entry(self.root)
        entry["rights"]["service_terms_ref"] = reference
        return write_manifest(self.root, [entry])

    def outside_register(self, rows=("pi-outside",)) -> Path:
        """A register-shaped file outside the checkout, with the given rows."""
        outside = self.root.parent / ("roadstorm-fixture-register-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        path = outside / REGISTER_BASENAME
        path.write_text(
            "# register elsewhere\n\n"
            "| Route ID | Service / API route | Model(s) observed | Terms | Basis | Output | "
            "Verification |\n| --- | --- | --- | --- | --- | --- | --- |\n"
            + "".join("| `{}` | s | m | t | b | c | V |\n".format(row) for row in rows),
            encoding="utf-8",
        )
        return path

    def validate_within(self, timeout: float, root: Path, manifest: Path, **kwargs) -> Findings:
        """Validate in a worker thread and fail if it does not return.

        A read that blocks - a FIFO with no writer, a device node - would
        otherwise hang the suite instead of failing it, so the deadline is part
        of the assertion.
        """
        outcome: dict = {}

        def run() -> None:
            outcome["findings"] = validate_manifest(manifest, root=root, **kwargs)

        worker = threading.Thread(target=run, daemon=True)
        worker.start()
        worker.join(timeout)
        self.assertFalse(
            worker.is_alive(),
            "validation did not finish within {}s; a rejected register path was "
            "opened for reading".format(timeout),
        )
        return outcome["findings"]

    def test_symlinked_register_is_reported_and_never_read(self):
        """A symlinked register is refused once; its rows are not read at all."""
        entry = service_entry(self.root)
        target = self.outside_register()
        register = self.root / "provenance" / REGISTER_BASENAME
        register.symlink_to(target)
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-outside"
        manifest = write_manifest(self.root, [entry])
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("symlink", messages(findings))
        self.assertEqual(reads.entered, [], "a rejected register must not be read")
        self.assertEqual(reads.opened, [], "a rejected register must not be opened")
        # The row in the file outside the root must not resolve the anchor, and
        # the reference error must be the only one about the terms record.
        self.assertNotIn("no row for that route", messages(findings))

    def test_register_through_a_symlinked_parent_is_reported_and_never_read(self):
        """A symlinked provenance/ directory escapes the root the same way."""
        entry = service_entry(self.root)
        target = self.outside_register()
        (target.parent / "OWNER_AUTHORITY.md").write_text(
            "authority elsewhere\n", encoding="utf-8"
        )
        provenance = self.root / "provenance"
        shutil.move(str(provenance / "OWNER_AUTHORITY.md"), target.parent / "OWNER_AUTHORITY.md")
        provenance.rmdir()
        provenance.symlink_to(target.parent)
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-outside"
        manifest = write_manifest(self.root, [entry])
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("symlink", messages(findings))
        self.assertEqual(reads.entered, [], "a rejected register must not be read")
        self.assertEqual(reads.opened, [], "a rejected register must not be opened")

    def test_missing_register_is_reported_and_never_read(self):
        """A register that was never written is reported, not opened."""
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("does not exist", messages(findings))
        self.assertEqual(reads.entered, [], "a missing register must not be read")
        self.assertEqual(reads.opened, [], "a missing register must not be opened")
        self.assertNotIn("no row for that route", messages(findings))

    def test_register_that_is_a_directory_is_reported_and_never_read(self):
        """A directory in place of the register is not a file, and is not read."""
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        (self.root / "provenance" / REGISTER_BASENAME).mkdir()
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("is not a file", messages(findings))
        self.assertEqual(reads.entered, [], "a directory must not be read as a register")
        self.assertEqual(reads.opened, [], "a directory must not be opened as a register")

    def test_register_that_is_a_fifo_is_refused_without_being_opened(self):
        """A special file exists but is not a readable record: it is not opened."""
        if not hasattr(os, "mkfifo"):
            self.skipTest("this platform has no FIFOs")
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        fifo = self.root / "provenance" / REGISTER_BASENAME
        os.mkfifo(fifo)
        with spy_on_register_reads() as reads:
            findings = self.validate_within(30, self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("is not a file", messages(findings))
        self.assertEqual(reads.entered, [], "a special file must not be read")
        self.assertEqual(reads.opened, [], "a special file must not be opened")

    def test_unreadable_register_is_rejected_before_any_read(self):
        """A register this process cannot read is not read, and is an error."""
        require_unix_mode_controls(self)
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        register = write_terms_register(self.root, ["pi-stepfun"])
        register.chmod(0)
        self.addCleanup(register.chmod, 0o644)
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("cannot be read", messages(findings))
        self.assertEqual(reads.entered, [], "an unreadable register must not be read")
        self.assertEqual(reads.opened, [], "an unreadable register must not be opened")

    def test_binary_register_is_reported_and_never_trusted(self):
        """A register that is not UTF-8 text resolves no row, and is an error."""
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        register = self.root / "provenance" / REGISTER_BASENAME
        register.write_bytes(b"\xff\xfe| `pi-stepfun` | s | m | t | b | c | V |\n")
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("could not be read", messages(findings))
        # A binary register is a real, readable regular file: the guard lets it
        # through and the decode fails, which resolves no row. The guarded-open
        # result is the platform-neutral proof of the open; ``os.open`` only
        # sees it on POSIX (Windows uses CreateFileW).
        self.assertEqual(len(reads.entered), 1, reads)
        register_guards = reads.register_guards()
        self.assertEqual(len(register_guards), 1, reads)
        self.assertIsNotNone(register_guards[0], "the binary register must be opened")
        if os.name != "nt":
            self.assertEqual(len(reads.opened), 1, reads)
        self.assertNotIn("no row for that route", messages(findings))

    def test_accepted_register_reference_is_read_exactly_once(self):
        """The guard must not disable normal route resolution."""
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        write_terms_register(self.root, ["pi-stepfun", "pi-longcat"])
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))
        self.assertEqual(len(reads.entered), 1, reads)
        register_guards = reads.register_guards()
        self.assertEqual(len(register_guards), 1, reads)
        self.assertIsNotNone(register_guards[0], "an accepted register must actually be opened")
        if os.name != "nt":
            self.assertEqual(len(reads.opened), 1, reads)

    def test_register_reference_without_an_anchor_is_not_read(self):
        """No anchor means no row to resolve, so the register text is not read."""
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md")
        write_terms_register(self.root, ["pi-stepfun"])
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))
        self.assertEqual(reads.entered, [], "no anchor, no row check, no read")
        self.assertEqual(reads.opened, [], "no anchor, no row check, no read")

    def test_register_swapped_for_a_symlink_after_the_check_is_not_followed(self):
        """Race-aware: the read re-validates the path instead of trusting the check.

        The check accepts the real register; the swap happens inside the
        reference check, exactly as a time-of-check/time-of-use race would. The
        read must refuse the path rather than follow it to the rows outside the
        root. This narrows the window; it does not close it - nothing here is
        race-free resolution.
        """
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        write_terms_register(self.root, ["pi-stepfun"])
        target = self.outside_register(["pi-stepfun"])
        register = self.root / "provenance" / REGISTER_BASENAME
        original = manifest_validator._check_reference_resolves

        def racing_check(findings, location, target, what, checker, require_readable=False):
            resolved = original(findings, location, target, what, checker, require_readable)
            if resolved and target == manifest_validator.PROVIDER_TERMS_REGISTER:
                register.unlink()
                register.symlink_to(target)
            return resolved

        with mock.patch.object(manifest_validator, "_check_reference_resolves", racing_check):
            with spy_on_register_reads() as reads:
                findings = validate(self.root, manifest)
        self.assertFalse(findings.ok)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("could not be read", messages(findings))
        # The row in the file outside the root must not resolve the anchor.
        self.assertNotIn("no row for that route", messages(findings))
        self.assertEqual(len(reads.entered), 1, reads)
        self.assertEqual(reads.opened, [], "the swapped-in symlink must not be opened")

    def test_register_swapped_for_a_fifo_after_the_check_does_not_block(self):
        """Race-aware: a special file swapped in after the check is closed unread."""
        if not hasattr(os, "mkfifo"):
            self.skipTest("this platform has no FIFOs")
        manifest = self.register_reference_manifest("provenance/PROVIDER_TERMS.md#pi-stepfun")
        write_terms_register(self.root, ["pi-stepfun"])
        register = self.root / "provenance" / REGISTER_BASENAME
        original = manifest_validator._check_reference_resolves

        def racing_check(findings, location, target, what, checker, require_readable=False):
            resolved = original(findings, location, target, what, checker, require_readable)
            if resolved and target == manifest_validator.PROVIDER_TERMS_REGISTER:
                register.unlink()
                os.mkfifo(register)
            return resolved

        with mock.patch.object(manifest_validator, "_check_reference_resolves", racing_check):
            with spy_on_register_reads() as reads:
                findings = self.validate_within(30, self.root, manifest)
        self.assertFalse(findings.ok)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertEqual(len(reads.entered), 1, reads)
        self.assertEqual(reads.opened, [], "a FIFO swapped in after the check must not be opened")

    def test_service_generated_accepts_a_route_snapshot(self):
        """Positive control: a bounded snapshot under provenance/provider_terms/."""
        entry = service_entry(self.root)
        touch(self.root, "provenance/provider_terms/pi-stepfun/INTAKE.md")
        entry["rights"]["service_terms_ref"] = "provenance/provider_terms/pi-stepfun/INTAKE.md"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_service_generated_accepts_a_real_route_snapshot(self):
        """End to end: the real register's route id with a real snapshot directory."""
        entry = service_entry(self.root)
        copy_real_terms_register(self.root)
        touch(self.root, "provenance/provider_terms/pi-stepfun/user-agreement.html")
        entry["rights"]["service_terms_ref"] = (
            "provenance/provider_terms/pi-stepfun/user-agreement.html"
        )
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_service_generated_rejects_a_snapshot_file_without_a_route_directory(self):
        """Malformed nesting: a file written directly under provider_terms/."""
        entry = service_entry(self.root)
        touch(self.root, "provenance/provider_terms/terms.md")
        entry["rights"]["service_terms_ref"] = "provenance/provider_terms/terms.md"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unresolved-reference", codes)
        self.assertIn("documented snapshot layout", messages(findings))

    def test_service_generated_rejects_a_route_directory_without_a_file(self):
        """Malformed nesting: <route-id>/ with no file below it."""
        entry = service_entry(self.root)
        (self.root / "provenance" / "provider_terms" / "pi-stepfun").mkdir(parents=True)
        entry["rights"]["service_terms_ref"] = "provenance/provider_terms/pi-stepfun"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("documented snapshot layout", messages(findings))

    def test_service_generated_rejects_a_deeper_snapshot_nesting(self):
        """Malformed nesting: deeper than <route-id>/<file> is not documented."""
        entry = service_entry(self.root)
        touch(self.root, "provenance/provider_terms/pi-stepfun/2026-11-26/INTAKE.md")
        entry["rights"]["service_terms_ref"] = (
            "provenance/provider_terms/pi-stepfun/2026-11-26/INTAKE.md"
        )
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("documented snapshot layout", messages(findings))

    def test_service_generated_rejects_a_snapshot_fragment(self):
        """The documented snapshot form has no '#fragment' to resolve."""
        entry = service_entry(self.root)
        touch(self.root, "provenance/provider_terms/pi-stepfun/INTAKE.md")
        entry["rights"]["service_terms_ref"] = (
            "provenance/provider_terms/pi-stepfun/INTAKE.md#output-rights"
        )
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("output-rights", messages(findings))

    def test_service_generated_rejects_a_missing_route_directory(self):
        """A route that was never captured has no snapshot directory."""
        entry = service_entry(self.root)
        entry["rights"]["service_terms_ref"] = "provenance/provider_terms/pi-missing/INTAKE.md"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unresolved-reference", codes)
        text = messages(findings)
        self.assertIn("pi-missing", text)
        self.assertIn("route directory", text)

    def test_service_generated_rejects_a_route_path_that_is_a_file(self):
        """The route component must be a directory, not a file in its place."""
        entry = service_entry(self.root)
        touch(self.root, "provenance/provider_terms/pi-stepfun")
        entry["rights"]["service_terms_ref"] = "provenance/provider_terms/pi-stepfun/INTAKE.md"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("is not a", messages(findings))

    def test_service_generated_rejects_a_symlinked_route_directory(self):
        """A symlinked route directory can point outside the checkout."""
        entry = service_entry(self.root)
        outside = self.root.parent / ("roadstorm-fixture-terms-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / "INTAKE.md").write_text("terms elsewhere\n", encoding="utf-8")
        route_dir = self.root / "provenance" / "provider_terms" / "pi-stepfun"
        route_dir.parent.mkdir(parents=True)
        route_dir.symlink_to(outside)
        entry["rights"]["service_terms_ref"] = "provenance/provider_terms/pi-stepfun/INTAKE.md"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("symlink", messages(findings))

    def test_cli_valid_route_reference_exits_0(self):
        """End to end through the CLI: a real register row and a real snapshot pass."""
        first = service_entry(self.root, "texture.service.sky")
        copy_real_terms_register(self.root)
        first["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-stepfun"
        second = service_entry(self.root, "texture.service.ground")
        with_output(second, "assets/generated/fixture/ground.res")
        touch(self.root, "assets/generated/fixture/ground.res")
        second["hashes"] = {
            "assets/generated/fixture/ground.res": digest_of(
                self.root / "assets/generated/fixture/ground.res"
            )
        }
        touch(self.root, "provenance/provider_terms/pi-longcat/private.html")
        second["rights"]["service_terms_ref"] = (
            "provenance/provider_terms/pi-longcat/private.html"
        )
        manifest = write_manifest(self.root, [first, second])
        self.assertEqual(
            main([str(manifest), "--root", str(self.root), "--check-hashes", "--quiet"]), 0
        )

    def test_cli_missing_route_reference_exits_1(self):
        """End to end through the CLI: an invented route fragment fails."""
        entry = service_entry(self.root)
        copy_real_terms_register(self.root)
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-unknown"
        manifest = write_manifest(self.root, [entry])
        self.assertEqual(main([str(manifest), "--root", str(self.root), "--quiet"]), 1)

    def test_first_party_entry_may_record_the_not_applicable_sentinel(self):
        """The sentinel stays valid where no service produced the asset."""
        entry = materialize(self.root, complete_entry())
        entry["rights"]["service_terms_ref"] = "not_applicable"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_rights_holder_record_must_resolve_to_an_existing_record(self):
        """Independent failure: a rights record that does not exist is no link to an instrument."""
        entry = materialize(self.root, complete_entry())
        entry["rights"]["rights_holder_record"] = "provenance/NOPE.md"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("unresolved-reference", codes)
        self.assertIn("provenance/NOPE.md", messages(findings))

    def test_rights_holder_record_must_point_into_provenance(self):
        entry = materialize(self.root, complete_entry())
        entry["rights"]["rights_holder_record"] = "docs/OWNER.md"
        touch(self.root, "docs/OWNER.md")
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))

    def test_symlinked_rights_record_is_rejected(self):
        entry = materialize(self.root, complete_entry())
        outside = self.root.parent / ("roadstorm-fixture-authority-" + self.root.name)
        outside.write_text("authority elsewhere\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        record = self.root / "provenance" / "OWNER_AUTHORITY.md"
        record.unlink()
        record.symlink_to(outside)
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))

    def test_rights_holder_record_may_use_an_anchor(self):
        entry = materialize(self.root, complete_entry())
        entry["rights"]["rights_holder_record"] = "provenance/OWNER_AUTHORITY.md#owner"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_reference_resolution_is_skipped_without_file_checks(self):
        """--no-file-checks validates structure only, like every existence check."""
        entry = complete_entry()
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, file_checks=False)
        self.assertNotIn("unresolved-reference", error_codes(findings))

    def test_external_cc0_upstream_record_cannot_be_omitted(self):
        """Independent failure: no rights.upstream and no upstream inputs."""
        entry = materialize(self.root, complete_entry("prop.external.rock"))
        entry["origin"] = "external_cc0"
        entry["rights"]["license_spdx"] = "CC0-1.0"
        entry["rights"].pop("service_terms_ref")
        entry["generation"].pop("recipe_path")
        entry["generation"].pop("regeneration_command")
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        text = messages(findings)
        self.assertIn("missing-required-field", codes)
        self.assertIn("rights.upstream", text)
        self.assertIn("upstream_inputs", text)

    def test_external_cc0_upstream_null_is_an_error(self):
        entry = materialize(self.root, complete_entry("prop.external.rock"))
        entry["origin"] = "external_cc0"
        entry["rights"]["license_spdx"] = "CC0-1.0"
        entry["rights"]["upstream"] = None
        entry["generation"].pop("recipe_path")
        entry["generation"].pop("regeneration_command")
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("missing-required-field", error_codes(findings))
        self.assertIn("rights.upstream", messages(findings))

    def test_external_cc0_with_full_evidence_passes(self):
        """Positive control for the tightened external gate."""
        entry = materialize(self.root, complete_entry("prop.external.rock"))
        entry["origin"] = "external_cc0"
        entry["rights"]["license_spdx"] = "CC0-1.0"
        entry["rights"]["upstream"] = {
            "url": "https://example.invalid/rock",
            "date": "2026-11-26",
            "evidence": "provenance/external/rock-cc0-evidence.md",
        }
        entry["generation"].pop("recipe_path")
        entry["generation"].pop("regeneration_command")
        entry["lineage"]["upstream_inputs"] = [
            {
                "path": "assets/source/external/rock.obj",
                "license": "CC0-1.0",
                "evidence": "https://example.invalid/rock (item-level CC0)",
            }
        ]
        manifest = write_manifest(self.root, [entry])
        touch(self.root, "assets/source/external/rock.obj")
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_first_party_unlicense_is_an_error(self):
        """Unlicense covers code/tools, not the creative assets registered here."""
        entry = materialize(self.root, complete_entry())
        entry["rights"]["license_spdx"] = "Unlicense"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("disallowed-license", error_codes(findings))
        self.assertIn("CC0-1.0", messages(findings))

    # -- technical metadata and identity schema/revision --------------------

    def test_technical_group_is_recorded_not_verified(self):
        """The contract's Technical group must be recordable, contents free-form."""
        entry = materialize(self.root, complete_entry())
        entry["technical"] = {
            "dimensions": "2.1 x 0.9 x 1.2 m",
            "triangle_count": 18432,
            "lod_count": 3,
            "material_count": 2,
            "model_dimensions": "n/a",
        }
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))
        self.assertNotIn("unknown-field", error_codes(findings))

    def test_technical_group_must_be_an_object(self):
        entry = materialize(self.root, complete_entry())
        entry["technical"] = "2.1 x 0.9 x 1.2 m"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("not-an-object", error_codes(findings))

    def test_identity_schema_and_revision_are_recorded(self):
        entry = materialize(self.root, complete_entry())
        entry["identity"]["schema"] = "schemas/asset_body.schema.json"
        entry["identity"]["revision"] = "3"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_identity_schema_must_be_a_string(self):
        entry = materialize(self.root, complete_entry())
        entry["identity"]["schema"] = {"major": 1}
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("missing-required-field", error_codes(findings))

    # -- review and release inclusion ---------------------------------------

    def test_release_inclusion_requires_approval(self):
        entry = materialize(self.root, complete_entry())
        entry["review"]["status"] = "pending"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unapproved-release", error_codes(findings))

    def test_rejected_entry_cannot_be_released(self):
        entry = materialize(self.root, complete_entry())
        entry["review"]["status"] = "rejected"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unapproved-release", error_codes(findings))

    def test_pending_review_without_release_is_accepted(self):
        entry = materialize(self.root, complete_entry())
        entry["review"]["status"] = "pending"
        entry["review"]["release_inclusion"] = False
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_pending_review_may_record_unknown_reviewer(self):
        """Unknowns are honest while a review is open; only shipping claims are not."""
        entry = materialize(self.root, complete_entry())
        entry["review"] = {
            "status": "pending",
            "reviewer": "unknown",
            "limitations": ["review not started"],
            "release_inclusion": False,
        }
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_approved_entry_with_unknown_reviewer_is_an_error(self):
        """Independent failure: an approval with no capable reviewer recorded."""
        entry = materialize(self.root, complete_entry())
        entry["review"]["reviewer"] = "unknown"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unknown-value", codes)
        self.assertIn("review.reviewer", messages(findings))

    def test_approved_entry_requires_approval_revision_and_technical_check(self):
        entry = materialize(self.root, complete_entry())
        del entry["review"]["approval_revision"]
        del entry["review"]["technical_check"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertEqual(codes.count("missing-required-field"), 2, messages(findings))
        text = messages(findings)
        self.assertIn("approval_revision", text)
        self.assertIn("technical_check", text)

    def test_release_inclusion_with_unknown_approval_revision_is_an_error(self):
        """The gate keys on the shipping claim, not only on status."""
        entry = materialize(self.root, complete_entry())
        entry["review"]["status"] = "pending"
        entry["review"]["release_inclusion"] = True
        entry["review"]["approval_revision"] = "unknown"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unapproved-release", codes)
        self.assertIn("unknown-value", codes)

    def test_approved_entry_requires_perceptual_review(self):
        """Independent failure: the contract's Review group lists visual/audio/model review."""
        entry = materialize(self.root, complete_entry())
        del entry["review"]["perceptual_review"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("missing-required-field", codes)
        self.assertIn("perceptual_review", messages(findings))

    def test_approved_entry_rejects_unknown_perceptual_review(self):
        entry = materialize(self.root, complete_entry())
        entry["review"]["perceptual_review"] = "unknown"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unknown-value", codes)
        self.assertIn("perceptual_review", messages(findings))

    def test_release_inclusion_with_unknown_perceptual_review_is_an_error(self):
        """The gate keys on the shipping claim, not only on status."""
        entry = materialize(self.root, complete_entry())
        entry["review"]["status"] = "pending"
        entry["review"]["release_inclusion"] = True
        entry["review"]["perceptual_review"] = "unknown"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertIn("unapproved-release", codes)
        self.assertIn("unknown-value", codes)

    def test_pending_entry_may_omit_perceptual_review(self):
        """A review that has not happened yet may still record the unknown."""
        entry = materialize(self.root, complete_entry())
        entry["review"] = {
            "status": "pending",
            "reviewer": "unknown",
            "limitations": ["review not started"],
            "release_inclusion": False,
        }
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertEqual(findings.errors, [], messages(findings))

    # -- lineage and references ---------------------------------------------

    def test_dangling_dependency_reference_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        entry["lineage"]["depends_on"] = ["car.ghost.missing"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("dangling-reference", error_codes(findings))

    def test_registered_dependency_reference_passes(self):
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(
            self.root,
            with_output(complete_entry("car.fixture.paint"), "assets/generated/fixture/paint.res"),
        )
        second["lineage"]["depends_on"] = ["car.fixture.body"]
        manifest = write_manifest(self.root, [first, second])
        findings = validate(self.root, manifest)
        self.assertEqual(findings.errors, [], messages(findings))

    # -- structure and spelling ---------------------------------------------

    def test_unknown_field_is_an_error_and_can_be_downgraded(self):
        entry = materialize(self.root, complete_entry())
        entry["invented_field"] = "not in the contract"
        manifest = write_manifest(self.root, [entry])
        self.assertIn("unknown-field", error_codes(validate(self.root, manifest)))
        relaxed = validate(self.root, manifest, allow_unknown_keys=True)
        self.assertEqual(relaxed.errors, [], messages(relaxed))
        self.assertIn("unknown-field", [f.code for f in relaxed.warnings])

    def test_unsupported_schema_version_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry], schema_version="9.9.9")
        findings = validate(self.root, manifest)
        self.assertIn("unsupported-schema-version", error_codes(findings))

    def test_wrong_manifest_id_is_an_error(self):
        manifest = write_manifest(self.root, [], manifest_id="some-other-format")
        findings = validate(self.root, manifest)
        self.assertIn("invalid-value", error_codes(findings))

    def test_non_object_root_and_invalid_json_are_errors(self):
        manifest = self.root / "assets" / "manifest.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text("[]", encoding="utf-8")
        self.assertIn("not-an-object", error_codes(validate(self.root, manifest)))
        manifest.write_text("null", encoding="utf-8")
        self.assertIn("not-an-object", error_codes(validate(self.root, manifest)))
        manifest.write_text("{not json", encoding="utf-8")
        self.assertIn("invalid-json", error_codes(validate(self.root, manifest)))

    def test_missing_manifest_file_is_reported(self):
        manifest = self.root / "assets" / "manifest.json"
        findings = validate(self.root, manifest)
        self.assertIn("unreadable-manifest", error_codes(findings))

    def test_bad_root_is_reported(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        findings = validate_manifest(manifest, root=self.root / "does-not-exist")
        self.assertIn("bad-root", error_codes(findings))

    def test_complete_entry_passes(self):
        """Positive control: a fully recorded entry validates cleanly."""
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))
        self.assertEqual(findings.warnings, [], messages(findings))

    # -- CLI ----------------------------------------------------------------

    def test_cli_exit_codes(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        self.assertEqual(main([str(manifest), "--root", str(self.root), "--quiet"]), 0)
        document = json.loads(manifest.read_text(encoding="utf-8"))
        document["assets"][0]["rights"]["license_spdx"] = "unknown"
        manifest.write_text(json.dumps(document), encoding="utf-8")
        self.assertEqual(main([str(manifest), "--root", str(self.root), "--quiet"]), 1)
        self.assertEqual(main([str(self.root / "nope.json"), "--root", str(self.root)]), 2)

    def test_cli_unreadable_manifest_exits_2(self):
        """Exit 2 means 'could not be read', not 'failed validation'."""
        require_unix_mode_controls(self)
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        manifest.chmod(0)
        self.addCleanup(manifest.chmod, 0o644)
        self.assertEqual(main([str(manifest), "--root", str(self.root), "--quiet"]), 2)

    def test_cli_invalid_json_exits_2(self):
        manifest = self.write_raw("{not json")
        self.assertEqual(main([str(manifest), "--root", str(self.root), "--quiet"]), 2)

    def test_cli_bad_root_exits_2(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        self.assertEqual(
            main([str(manifest), "--root", str(self.root / "does-not-exist"), "--quiet"]), 2
        )

    def test_cli_invalid_utf8_still_exits_1(self):
        """Decodable bytes with a defective document are content errors, not read errors."""
        manifest = self.root / "assets" / "manifest.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_bytes(b'{"registry_status": "\xff"}')
        self.assertEqual(main([str(manifest), "--root", str(self.root), "--quiet"]), 1)

    def test_cli_json_output_still_reports_read_failures(self):
        manifest = self.write_raw("{not json")
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            exit_code = main([str(manifest), "--root", str(self.root), "--json"])
        self.assertEqual(exit_code, 2)
        payload = json.loads(buffer.getvalue())
        self.assertEqual(payload["result"], "fail")
        self.assertEqual(
            [error["code"] for error in payload["errors"]], ["invalid-json"]
        )

    def test_run_tests_sh_pattern_argument(self):
        """The documented <pattern> form must select tests, not fail to import."""
        import subprocess

        script = _TOOL_DIR / "run_tests.sh"
        completed = subprocess.run(
            ["sh", str(script), "test_shipped_empty_manifest_passes", "-v"],
            capture_output=True,
            text=True,
            timeout=300,
        )
        self.assertEqual(
            completed.returncode,
            0,
            "run_tests.sh <pattern> must run the matching test:\n"
            + completed.stdout
            + completed.stderr,
        )
        self.assertIn("Ran 1 test", completed.stdout + completed.stderr)
        self.assertIn("test_shipped_empty_manifest_passes", completed.stderr)
        self.assertIn("OK", completed.stderr)

    # -- output ownership ----------------------------------------------------

    def test_one_output_path_has_one_owner(self):
        """Two valid entries must not claim the same output path.

        Independent failure: distinct IDs, correct hashes and hash verification
        enabled, so only the ownership rule can catch the conflict.
        """
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(self.root, complete_entry("car.fixture.paint"))
        # Same output path, same on-disk file, same recorded hash.
        second["identity"]["output_paths"] = list(first["identity"]["output_paths"])
        second["hashes"] = dict(first["hashes"])
        manifest = write_manifest(self.root, [first, second])
        findings = validate(self.root, manifest, check_hashes=True)
        codes = error_codes(findings)
        self.assertEqual(codes.count("duplicate-output-path"), 1, messages(findings))
        self.assertEqual(codes.count("hash-mismatch"), 0, messages(findings))
        text = messages(findings)
        self.assertIn("assets/generated/fixture/body.res", text)
        self.assertIn("assets[0]", text)
        self.assertIn("assets[1]", text)

    def test_output_path_listed_twice_in_one_entry_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        entry["identity"]["output_paths"].append(entry["identity"]["output_paths"][0])
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertEqual(error_codes(findings).count("duplicate-output-path"), 1, messages(findings))
        self.assertIn("listed twice", messages(findings))

    def test_shared_source_path_is_not_an_ownership_conflict(self):
        """A shared source is ordinary lineage; only outputs have one owner."""
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(
            self.root,
            with_output(complete_entry("car.fixture.paint"), "assets/generated/fixture/paint.res"),
        )
        manifest = write_manifest(self.root, [first, second])
        self.assertEqual(validate(self.root, manifest).errors, [], messages(validate(self.root, manifest)))

    # -- dependency cycles ---------------------------------------------------

    def test_direct_dependency_cycle_is_an_error(self):
        """Independent failure: two valid entries that depend on each other."""
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(
            self.root,
            with_output(complete_entry("car.fixture.paint"), "assets/generated/fixture/paint.res"),
        )
        first["lineage"]["depends_on"] = ["car.fixture.paint"]
        second["lineage"]["depends_on"] = ["car.fixture.body"]
        manifest = write_manifest(self.root, [first, second])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(error_codes(findings).count("dependency-cycle"), 1, messages(findings))
        self.assertIn("car.fixture.body -> car.fixture.paint -> car.fixture.body", messages(findings))

    def test_indirect_dependency_cycle_is_an_error(self):
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(
            self.root,
            with_output(complete_entry("car.fixture.paint"), "assets/generated/fixture/paint.res"),
        )
        third = materialize(
            self.root,
            with_output(complete_entry("car.fixture.decal"), "assets/generated/fixture/decal.res"),
        )
        first["lineage"]["depends_on"] = ["car.fixture.decal"]
        second["lineage"]["depends_on"] = ["car.fixture.body"]
        third["lineage"]["depends_on"] = ["car.fixture.paint"]
        manifest = write_manifest(self.root, [first, second, third])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(error_codes(findings).count("dependency-cycle"), 1, messages(findings))
        self.assertIn(
            "car.fixture.body -> car.fixture.decal -> car.fixture.paint -> car.fixture.body",
            messages(findings),
        )

    def test_self_dependency_is_an_error(self):
        entry = materialize(self.root, complete_entry("car.fixture.body"))
        entry["lineage"]["depends_on"] = ["car.fixture.body"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertEqual(error_codes(findings).count("dependency-cycle"), 1, messages(findings))
        self.assertIn("car.fixture.body -> car.fixture.body", messages(findings))

    def test_cycle_with_a_dangling_reference_is_still_reported(self):
        """Unknown IDs are dangling references; the cycle itself is separate."""
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(
            self.root,
            with_output(complete_entry("car.fixture.paint"), "assets/generated/fixture/paint.res"),
        )
        first["lineage"]["depends_on"] = ["car.ghost.missing", "car.fixture.paint"]
        second["lineage"]["depends_on"] = ["car.fixture.body"]
        manifest = write_manifest(self.root, [first, second])
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertEqual(codes.count("dependency-cycle"), 1, messages(findings))
        self.assertEqual(codes.count("dangling-reference"), 1, messages(findings))

    def test_valid_noncyclic_dependency_graph_passes(self):
        """Positive control: a three-entry acyclic graph verifies cleanly."""
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(
            self.root,
            with_output(complete_entry("car.fixture.paint"), "assets/generated/fixture/paint.res"),
        )
        third = materialize(
            self.root,
            with_output(complete_entry("car.fixture.decal"), "assets/generated/fixture/decal.res"),
        )
        second["lineage"]["depends_on"] = ["car.fixture.body"]
        third["lineage"]["depends_on"] = ["car.fixture.paint"]
        manifest = write_manifest(self.root, [first, second, third])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))
        self.assertEqual(findings.warnings, [], messages(findings))

    def test_deep_acyclic_chain_does_not_exhaust_the_stack(self):
        """The cycle search is iterative: a long chain must not blow the stack."""
        entries = []
        for index in range(1500):
            output = "assets/generated/fixture/part{:04d}.res".format(index)
            entry = with_output(
                complete_entry("car.fixture.part{:04d}".format(index)), output
            )
            # A well-formed recorded hash; the files themselves are not needed
            # because this test runs without file checks.
            entry["hashes"] = {output: "sha256:" + "0" * 64}
            if index:
                entry["lineage"]["depends_on"] = ["car.fixture.part{:04d}".format(index - 1)]
            entries.append(entry)
        manifest = write_manifest(self.root, entries)
        findings = validate(self.root, manifest, file_checks=False)
        self.assertEqual(findings.errors, [], messages(findings))

    # -- duplicate JSON members ---------------------------------------------

    def write_raw(self, text: str) -> Path:
        path = self.root / "assets" / "manifest.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_duplicate_top_level_members_are_errors(self):
        """Independent failure: the review's contradictory registry_status pair."""
        manifest = self.write_raw(
            """{
              "manifest_id": "roadstorm-asset-manifest",
              "schema_version": "0.1.0",
              "registry_status": "populated",
              "registry_status": "empty",
              "assets": []
            }
            """
        )
        findings = validate(self.root, manifest)
        codes = error_codes(findings)
        self.assertEqual(codes.count("duplicate-json-member"), 1, messages(findings))
        self.assertNotIn("registry-status-mismatch", codes)
        self.assertIn("registry_status", messages(findings))
        self.assertIn("appears 2 times", messages(findings))

    def test_duplicate_members_are_reported_at_every_depth(self):
        """Nested rights and review members are checked too, inside arrays."""
        manifest = self.write_raw(
            """{
              "manifest_id": "roadstorm-asset-manifest",
              "schema_version": "0.1.0",
              "registry_status": "populated",
              "assets": [
                {
                  "id": "car.fixture.body",
                  "rights": {
                    "license_spdx": "CC0-1.0",
                    "license_spdx": "CC-BY-4.0"
                  },
                  "review": {
                    "status": "approved",
                    "status": "pending"
                  },
                  "lineage": {
                    "upstream_inputs": [
                      { "path": "a.obj", "path": "b.obj" }
                    ]
                  }
                }
              ]
            }
            """
        )
        findings = validate(self.root, manifest, file_checks=False)
        locations = sorted(
            f.location for f in findings.errors if f.code == "duplicate-json-member"
        )
        self.assertEqual(
            locations,
            [
                "assets[0].lineage.upstream_inputs[0].path",
                "assets[0].review.status",
                "assets[0].rights.license_spdx",
            ],
            messages(findings),
        )
        # The member is reported once, not once per occurrence beyond the first.
        self.assertEqual(
            len([f for f in findings.errors if f.code == "duplicate-json-member"]),
            3,
            messages(findings),
        )
        # The surviving value is the last one written, so validation still runs
        # against it: the duplicate member must not hide the rest of the record.
        self.assertIn("CC-BY-4.0", messages(findings))

    def test_repeated_array_items_are_not_duplicate_members(self):
        """Repeated values are not repeated members; only object members count."""
        manifest = self.write_raw(
            """{
              "manifest_id": "roadstorm-asset-manifest",
              "schema_version": "0.1.0",
              "registry_status": "empty",
              "assets": [],
              "open_items": ["OI-01", "OI-01", "OI-01"]
            }
            """
        )
        findings = validate(self.root, manifest)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_repeated_members_in_a_valid_document_are_not_reported(self):
        entry = materialize(self.root, complete_entry())
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, check_hashes=True)
        self.assertNotIn("duplicate-json-member", error_codes(findings))
        self.assertEqual(findings.errors, [], messages(findings))

    # -- encoding ------------------------------------------------------------

    def test_malformed_utf8_is_a_structured_error(self):
        """Independent failure: a one-byte invalid UTF-8 manifest."""
        manifest = self.root / "assets" / "manifest.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_bytes(
            b'{"manifest_id": "roadstorm-asset-manifest", "schema_version": "0.1.0", '
            b'"registry_status": "\xff", "assets": []}'
        )
        findings = validate(self.root, manifest)
        self.assertEqual(len(findings.errors), 1, messages(findings))
        self.assertEqual(findings.errors[0].code, "invalid-encoding")
        self.assertIn("UTF-8", findings.errors[0].message)
        self.assertEqual(findings.ok, False)

    def test_malformed_utf8_cli_reports_json_instead_of_a_traceback(self):
        manifest = self.root / "assets" / "manifest.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_bytes(b'{"registry_status": "\xff"}')
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            exit_code = main([str(manifest), "--root", str(self.root), "--json"])
        self.assertEqual(exit_code, 1)
        payload = json.loads(buffer.getvalue())
        self.assertEqual(payload["result"], "fail")
        self.assertEqual(
            [error["code"] for error in payload["errors"]], ["invalid-encoding"]
        )
        self.assertEqual(payload["warnings"], [])

    def test_malformed_utf8_cli_text_mode_is_not_a_traceback(self):
        manifest = self.root / "assets" / "manifest.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_bytes(b'{"registry_status": "\xff"}')
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            exit_code = main([str(manifest), "--root", str(self.root)])
        self.assertEqual(exit_code, 1)
        self.assertIn("invalid-encoding", buffer.getvalue())
        self.assertIn("FAIL", buffer.getvalue())


class RegisterReadGuardTestCase(unittest.TestCase):
    """Unit tests for the guard that decides whether the register may be read.

    These test the guard directly, independently of the manifest plumbing: a
    rejected path must yield ``None`` from ``_read_record_text`` (no text, so no
    rows) and ``False`` from ``_record_file_is_readable``, without anything
    being opened.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def register_path(self) -> Path:
        path = self.root / manifest_validator.PROVIDER_TERMS_REGISTER
        path.parent.mkdir(parents=True, exist_ok=True)
        return path

    def read_register(self, spelling=None):
        return manifest_validator._read_record_text(
            self.root,
            spelling if spelling is not None else manifest_validator.PROVIDER_TERMS_REGISTER,
        )

    def register_is_readable(self, spelling=None):
        return manifest_validator._record_file_is_readable(
            self.root,
            spelling if spelling is not None else manifest_validator.PROVIDER_TERMS_REGISTER,
        )

    def test_reads_a_real_register(self):
        register = self.register_path()
        register.write_text("| `pi-stepfun` | s | m | t | b | c | V |\n", encoding="utf-8")
        text = self.read_register()
        self.assertIsNotNone(text)
        self.assertIn("pi-stepfun", text)
        self.assertTrue(self.register_is_readable())

    def test_refuses_a_symlinked_register(self):
        register = self.register_path()
        outside = self.root.parent / ("roadstorm-fixture-guard-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        target = outside / REGISTER_BASENAME
        target.write_text("| `pi-outside` | s | m | t | b | c | V |\n", encoding="utf-8")
        register.symlink_to(target)
        self.assertIsNone(self.read_register())
        self.assertFalse(self.register_is_readable())

    def test_refuses_a_symlinked_parent_directory(self):
        outside = self.root.parent / ("roadstorm-fixture-guard-parent-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        (outside / REGISTER_BASENAME).write_text(
            "| `pi-outside` | s | m | t | b | c | V |\n", encoding="utf-8"
        )
        (self.root / "provenance").symlink_to(outside)
        self.assertIsNone(self.read_register())
        self.assertFalse(self.register_is_readable())

    def test_refuses_a_missing_register(self):
        self.assertIsNone(self.read_register())
        self.assertFalse(self.register_is_readable())

    def test_refuses_a_directory_in_place_of_the_register(self):
        self.register_path().mkdir()
        self.assertIsNone(self.read_register())
        self.assertFalse(self.register_is_readable())

    def test_refuses_a_fifo_in_place_of_the_register(self):
        """A FIFO exists, but opening it for reading would block."""
        if not hasattr(os, "mkfifo"):
            self.skipTest("this platform has no FIFOs")
        os.mkfifo(self.register_path())
        outcome: dict = {}

        def run() -> None:
            outcome["text"] = self.read_register()

        worker = threading.Thread(target=run, daemon=True)
        worker.start()
        worker.join(30)
        self.assertFalse(
            worker.is_alive(),
            "reading a FIFO blocks: the guard must refuse it before any open",
        )
        self.assertIsNone(outcome["text"])
        self.assertFalse(self.register_is_readable())

    def test_refuses_an_unreadable_register(self):
        require_unix_mode_controls(self)
        register = self.register_path()
        register.write_text("| `pi-stepfun` | s | m | t | b | c | V |\n", encoding="utf-8")
        register.chmod(0)
        self.addCleanup(register.chmod, 0o644)
        self.assertIsNone(self.read_register())
        self.assertFalse(self.register_is_readable())

    def test_refuses_a_register_that_is_not_utf8_text(self):
        self.register_path().write_bytes(b"\xff\xfe\x00")
        self.assertIsNone(self.read_register())
        # A binary file is still a readable regular file: the guard lets it
        # through and the decode fails.
        self.assertTrue(self.register_is_readable())

    def test_refuses_a_spelling_that_leaves_the_root(self):
        """The guard re-checks spelling: it is the last gate before an open."""
        outside = self.root.parent / ("roadstorm-fixture-guard-escape-" + self.root.name)
        outside.write_text("| `pi-outside` | s | m | t | b | c | V |\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        for spelling in (
            str(outside),
            "../" + outside.name,
            "provenance/../" + outside.name,
            "/etc/" + REGISTER_BASENAME,
            "provenance/" + REGISTER_BASENAME + "/",
        ):
            self.assertIsNone(
                self.read_register(spelling),
                "{} must not be read".format(spelling),
            )
            self.assertFalse(
                self.register_is_readable(spelling),
                "{} must not be readable".format(spelling),
            )

    # -- the window after the pre-check (Opus independent finding F1) ------

    def test_refuses_a_fifo_swapped_in_after_the_pre_check(self):
        """The fd-level defenses are exercised, not just the path checks.

        The pre-check is replaced by one that swaps the real register for a
        FIFO at the moment it is asked - exactly the window between
        ``_record_file_is_readable`` and ``os.open``. The guarded open must
        refuse it without blocking, so no row can resolve from it.
        """
        if not hasattr(os, "mkfifo"):
            self.skipTest("this platform has no FIFOs")
        register = self.register_path()
        register.write_text("| `pi-stepfun` | s | m | t | b | c | V |\n", encoding="utf-8")

        def swapped_pre_check(root, spelled):
            register.unlink()
            os.mkfifo(register)
            return True

        with mock.patch.object(manifest_validator, "_record_file_is_readable", swapped_pre_check):
            text, timed_out = bounded_call(lambda: self.read_register())
        self.assertFalse(timed_out, "reading a FIFO swapped in after the check blocked")
        self.assertIsNone(text)
        # No rows resolve from a register the checker refused to read: the
        # path is now a FIFO, and the row reader refuses it too.
        self.assertIsNone(manifest_validator._terms_register_route_ids(self.root))

    def test_refuses_a_symlink_swapped_in_after_the_pre_check(self):
        """A leaf swapped for a symlink after the pre-check is not followed."""
        register = self.register_path()
        register.write_text("| `pi-stepfun` | s | m | t | b | c | V |\n", encoding="utf-8")
        outside = self.root.parent / ("roadstorm-fixture-register-swap-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        target = outside / REGISTER_BASENAME
        target.write_text("| `pi-outside` | s | m | t | b | c | V |\n", encoding="utf-8")

        def swapped_pre_check(root, spelled):
            register.unlink()
            register.symlink_to(target)
            return True

        with mock.patch.object(manifest_validator, "_record_file_is_readable", swapped_pre_check):
            text, timed_out = bounded_call(lambda: self.read_register())
        self.assertFalse(timed_out)
        self.assertIsNone(text)
        self.assertNotIn("pi-outside", text or "")

    def test_guarded_open_returns_a_descriptor_for_a_regular_file(self):
        """Positive control for the primitive the readers share."""
        register = self.register_path()
        register.write_text("| `pi-stepfun` | s | m | t | b | c | V |\n", encoding="utf-8")
        descriptor = manifest_validator._open_regular_file_descriptor(
            self.root, manifest_validator.PROVIDER_TERMS_REGISTER
        )
        try:
            self.assertIsNotNone(descriptor)
            self.assertTrue(stat.S_ISREG(os.fstat(descriptor).st_mode))
        finally:
            if descriptor is not None:
                os.close(descriptor)

    def test_guarded_open_refuses_a_fifo_without_blocking(self):
        """Directly at the open: a FIFO is opened non-blocking and rejected."""
        if not hasattr(os, "mkfifo"):
            self.skipTest("this platform has no FIFOs")
        register = self.register_path()
        os.mkfifo(register)
        descriptor, timed_out = bounded_call(
            lambda: manifest_validator._open_regular_file_descriptor(
                self.root, manifest_validator.PROVIDER_TERMS_REGISTER
            )
        )
        self.assertFalse(timed_out, "opening a FIFO blocked")
        self.assertIsNone(descriptor)

    def test_guarded_open_refuses_a_symlink_leaf(self):
        """Directly at the open: a symlinked leaf is refused, not followed."""
        outside = self.root.parent / ("roadstorm-fixture-open-link-" + self.root.name)
        outside.write_text("outside\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        register = self.register_path()
        register.symlink_to(outside)
        self.assertIsNone(
            manifest_validator._open_regular_file_descriptor(
                self.root, manifest_validator.PROVIDER_TERMS_REGISTER
            )
        )

    @unittest.skipUnless(
        os.name != "nt",
        "POSIX-only control: the Windows branch never consults _guarded_open_flags "
        "(see WindowsGuardedOpenTestCase)",
    )
    def test_guarded_open_fails_closed_where_flags_are_unavailable(self):
        """Without no-follow/non-blocking the primitive refuses to open."""
        register = self.register_path()
        register.write_text("| `pi-stepfun` | s | m | t | b | c | V |\n", encoding="utf-8")
        with mock.patch.object(manifest_validator, "_guarded_open_flags", lambda: None):
            self.assertIsNone(
                manifest_validator._open_regular_file_descriptor(
                    self.root, manifest_validator.PROVIDER_TERMS_REGISTER
                )
            )


class JunctionComponentTestCase(unittest.TestCase):
    """Cross-platform controls for detecting directory junctions.

    A Windows directory junction carries ``FILE_ATTRIBUTE_REPARSE_POINT`` but
    is *not* a symbolic link, so ``Path.is_symlink()`` alone reports False for
    it while ``CreateFileW`` still resolves through it. The checks below fake
    that combination - ``is_symlink`` False plus a reparse attribute on the
    intermediate directory - and assert every guarded path refuses it.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        (self.root / "a").mkdir()
        (self.root / "a" / "b").write_text("fixture bytes\n", encoding="utf-8")

    def _fake_lstat(self, path):
        # Windows spells the same relative path with backslashes; normalise
        # before matching the component suffix.
        normalized = str(path).replace("\\", "/")
        attributes = (
            manifest_validator._FILE_ATTRIBUTE_REPARSE_POINT
            if normalized.endswith("/a")
            else 0
        )

        class Attributes:
            st_file_attributes = attributes

        return Attributes()

    def _patched(self):
        return (
            mock.patch.object(Path, "is_symlink", lambda self: False),
            mock.patch.object(manifest_validator.os, "lstat", self._fake_lstat),
        )

    def test_junction_like_intermediate_is_detected_as_a_link(self):
        first, second = self._patched()
        with first, second:
            self.assertEqual(
                manifest_validator._symlinked_component(self.root, "a/b"), "a"
            )

    def test_junction_fake_matches_windows_backslash_spelling(self):
        """Regression: the fake must recognise ``\\a`` as well as ``/a``."""
        self.assertEqual(
            self._fake_lstat(r"C:\Users\RUNNER~1\Temp\tmpX\a").st_file_attributes,
            manifest_validator._FILE_ATTRIBUTE_REPARSE_POINT,
        )
        self.assertEqual(
            self._fake_lstat(r"C:\Users\RUNNER~1\Temp\tmpX\a\b").st_file_attributes,
            0,
        )

    def test_plain_real_components_are_not_reported_as_links(self):
        self.assertIsNone(manifest_validator._symlinked_component(self.root, "a/b"))

    def test_symlink_leaf_is_detected_without_the_reparse_attribute(self):
        def no_reparse(path):
            class Attributes:
                st_file_attributes = 0

            return Attributes()

        with mock.patch.object(
            Path, "is_symlink", lambda self: self.name == "b"
        ), mock.patch.object(manifest_validator.os, "lstat", no_reparse):
            self.assertEqual(
                manifest_validator._symlinked_component(self.root, "a/b"), "a/b"
            )

    def test_existence_and_read_paths_refuse_a_junction_like_parent(self):
        """The same refusal must reach the existence, hash and record paths."""
        checker = manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )
        first, second = self._patched()
        with first, second:
            findings = manifest_validator.Findings()
            checker.check(findings, "loc", "a/b", "test output path")
            self.assertIn("symlinked-path", [f.code for f in findings.errors])
            self.assertIn("symlink", messages(findings))
            self.assertIsNone(checker.digest("a/b"))
            references = manifest_validator.Findings()
            manifest_validator._check_reference_resolves(
                references, "loc", "a/b", "test record", checker
            )
            self.assertIn("unresolved-reference", [f.code for f in references.errors])


class ManifestPathSpellingTestCase(unittest.TestCase):
    """Alias-prone spellings must be refused before any path resolution.

    These are pure checks, so they run on every platform; the native
    ``WindowsNativeGuardTestCase`` repeats the integration through the real
    Windows filesystem call path.
    """

    LEGITIMATE = (
        "assets/generated/car/body.res",
        "content/fixture/recipe.json",
        "assets/car.body.res",
        "assets/v1.2/body.res",
        "a/b.c/d_e-f.g",
        "Assets/Generated/Fixture/Body.RES",
    )

    ALIASES = (
        "assets/textures/body.res:stream",   # NTFS alternate data stream
        "assets/textures/body.res:",
        "assets/textures/body.res.",          # trailing dot normalizes away
        "assets/textures/body.res ",          # trailing space normalizes away
        "assets/textures/plan.",
        "assets/CON",                          # reserved device basename
        "assets/con.txt",
        "assets/LPT1.res",
        "assets/a\x00b.res",                  # embedded NUL
    )

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def test_legitimate_godot_style_paths_are_accepted(self):
        for spelling in self.LEGITIMATE:
            self.assertIsNone(
                manifest_validator._path_spelling_error(spelling), spelling
            )

    def test_alias_prone_spellings_are_rejected(self):
        for spelling in self.ALIASES:
            self.assertIsNotNone(
                manifest_validator._path_spelling_error(spelling), repr(spelling)
            )

    def test_rejected_spelling_is_a_structured_invalid_path_finding(self):
        entry = complete_entry()
        entry["identity"]["output_paths"] = ["assets/textures/body.res:stream"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("invalid-path", error_codes(findings))


class ManifestInputGuardTestCase(unittest.TestCase):
    """The caller-selected manifest document must use the guarded read.

    A manifest symlink to a valid document outside the root must be refused
    as ``unreadable-manifest`` (exit 2), not read through. An explicitly
    supplied real regular manifest outside the project root stays accepted,
    as long as its leaf is opened guarded and no checked component is a link.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        (self.root / "assets").mkdir(parents=True)
        self.manifest = self.root / "assets" / "manifest.json"
        self.manifest.write_text(
            SHIPPED_MANIFEST.read_text(encoding="utf-8"), encoding="utf-8"
        )
        self.outside_dir = self.root.parent / ("roadstorm-input-outside-" + self.root.name)
        self.outside_dir.mkdir()
        self.addCleanup(shutil.rmtree, self.outside_dir, True)
        self.outside = self.outside_dir / "manifest.json"
        shutil.copyfile(SHIPPED_MANIFEST, self.outside)

    def make_symlink(self, link: Path, target: Path) -> None:
        if link.exists() or link.is_symlink():
            link.unlink()
        try:
            link.symlink_to(target)
        except OSError as exc:
            self.skipTest("cannot create a symlink on this host: {}".format(exc))

    def test_external_regular_manifest_is_accepted(self):
        """An operator-supplied real manifest outside the root still validates."""
        findings = validate(self.root, self.outside)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_symlinked_manifest_is_refused_not_read_through(self):
        """A valid outside document must not PASS through a linked manifest path."""
        self.make_symlink(self.manifest, self.outside)
        # The target itself is a perfectly valid empty registry: if the reader
        # followed the link this control would show zero findings.
        control = validate(self.root, self.outside)
        self.assertEqual(control.errors, [], messages(control))
        findings = validate(self.root, self.manifest)
        codes = error_codes(findings)
        self.assertIn("unreadable-manifest", codes)
        self.assertNotIn("invalid-json", codes)
        self.assertNotIn("invalid-encoding", codes)
        self.assertIn("link", messages(findings))

    def test_symlinked_manifest_cli_exits_2_with_json(self):
        import contextlib
        import io

        self.make_symlink(self.manifest, self.outside)
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main([str(self.manifest), "--root", str(self.root), "--json"])
        self.assertEqual(exit_code, 2)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(
            [error["code"] for error in payload["errors"]], ["unreadable-manifest"]
        )
        self.assertEqual(stderr.getvalue(), "")

    def test_manifest_parent_link_component_is_refused(self):
        """A junction/symlink-like intermediate directory fails closed too."""
        from types import SimpleNamespace

        reparse = manifest_validator._FILE_ATTRIBUTE_REPARSE_POINT

        def fake_lstat(path):
            normalized = str(path).replace("\\", "/")
            value = reparse if normalized.endswith("/assets") else 0
            return SimpleNamespace(st_file_attributes=value)

        with mock.patch.object(Path, "is_symlink", lambda self: False), mock.patch.object(
            manifest_validator.os, "lstat", fake_lstat
        ):
            findings = validate(self.root, self.manifest)
        self.assertIn("unreadable-manifest", error_codes(findings))
        self.assertIn("link", messages(findings))

    def test_manifest_leaf_swapped_after_the_component_check_is_refused(self):
        """Open-boundary control: the guard, not just the precheck, refuses.

        The manifest is replaced by a symlink to the valid outside document at
        the moment the component check is asked, exactly the window before the
        open. Reading through it would produce zero findings.
        """
        control = validate(self.root, self.outside)
        self.assertEqual(control.errors, [], messages(control))
        original = manifest_validator._manifest_input_problem

        def swapped(manifest, root):
            problem = original(manifest, root)
            if problem is None:
                manifest.unlink()
                self.make_symlink(manifest, self.outside)
            return problem

        with mock.patch.object(manifest_validator, "_manifest_input_problem", swapped):
            findings = validate(self.root, self.manifest)
        self.assertIn("unreadable-manifest", error_codes(findings))
        self.assertIn("link", messages(findings))

    def test_invalid_utf8_manifest_still_reports_invalid_encoding(self):
        """The guard must not change the decoding contract."""
        self.manifest.write_bytes(b'{"registry_status": "\xff"}')
        findings = validate(self.root, self.manifest)
        self.assertEqual([f.code for f in findings.errors], ["invalid-encoding"])


class FakeWindowsFileApi:
    """Recorded Win32 answers for the Windows guarded-open branch.

    Stands in for ``_WindowsFileApi`` so call order, failure branches and
    handle ownership can be asserted without a Windows host. ``attributes``
    of ``None`` means the metadata query failed; ``handle`` of ``None`` means
    ``CreateFileW`` failed.
    """

    FILE_ATTRIBUTE_REPARSE_POINT = 0x400
    FILE_ATTRIBUTE_DIRECTORY = 0x10
    FILE_TYPE_DISK = 0x1

    def __init__(
        self,
        handle=42,
        attributes=0,
        file_type_value=None,
        descriptor=7,
        create_error=None,
        tag_error=None,
        type_error=None,
        open_error=None,
    ) -> None:
        self.handle = handle
        self.attributes = attributes
        self.file_type_value = (
            FakeWindowsFileApi.FILE_TYPE_DISK
            if file_type_value is None
            else file_type_value
        )
        self.descriptor = descriptor
        self.create_error = create_error
        self.tag_error = tag_error
        self.type_error = type_error
        self.open_error = open_error
        self.calls: list[tuple[str, object]] = []
        self.closed: list = []

    def create_file(self, path):
        self.calls.append(("create_file", path))
        if self.create_error is not None:
            raise self.create_error
        return self.handle

    def file_attribute_tag(self, handle):
        self.calls.append(("file_attribute_tag", handle))
        if self.tag_error is not None:
            raise self.tag_error
        return None if self.attributes is None else (self.attributes, 0)

    def file_type(self, handle):
        self.calls.append(("file_type", handle))
        if self.type_error is not None:
            raise self.type_error
        return self.file_type_value

    def open_osfhandle(self, handle):
        self.calls.append(("open_osfhandle", handle))
        if self.open_error is not None:
            raise self.open_error
        return self.descriptor

    def close_handle(self, handle):
        self.calls.append(("close_handle", handle))
        self.closed.append(handle)
        return True

    @property
    def names(self) -> list[str]:
        return [name for name, _argument in self.calls]


class WindowsGuardedOpenTestCase(unittest.TestCase):
    """Fake-WinAPI controls for the Windows guarded-open branch.

    These run on every platform: they replace the Win32 adapter with a recorder
    and assert call order, each refusal branch, exactly-one handle close and
    the ``None`` error mapping. They prove the control flow, not real Windows
    semantics - see ``WindowsNativeGuardTestCase``.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def guard(self, api):
        return manifest_validator._windows_open_regular_descriptor(
            self.root, "assets/generated/fixture/body.res", api=api
        )

    def test_happy_path_bridges_without_closing_the_raw_handle(self):
        """A normal file: open, query, type, bridge - and no CloseHandle."""
        api = FakeWindowsFileApi(handle=42, attributes=0x80, descriptor=9)
        self.assertEqual(self.guard(api), 9)
        self.assertEqual(
            api.names,
            ["create_file", "file_attribute_tag", "file_type", "open_osfhandle"],
        )
        self.assertEqual(api.closed, [], "a bridged handle must not be closed twice")

    def test_create_failure_returns_none_and_touches_nothing_else(self):
        api = FakeWindowsFileApi(handle=None)
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names, ["create_file"])
        self.assertEqual(api.closed, [])

    def test_create_oserror_is_mapped_to_none(self):
        api = FakeWindowsFileApi(create_error=OSError("open failed"))
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names, ["create_file"])
        self.assertEqual(api.closed, [])

    def test_metadata_query_failure_closes_exactly_once(self):
        api = FakeWindowsFileApi(attributes=None)
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names, ["create_file", "file_attribute_tag", "close_handle"])
        self.assertEqual(api.closed, [42])

    def test_metadata_query_oserror_closes_exactly_once(self):
        api = FakeWindowsFileApi(tag_error=OSError("query failed"))
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names[-1], "close_handle")
        self.assertEqual(api.closed, [42])

    def test_reparse_leaf_is_refused_without_type_or_bridge(self):
        api = FakeWindowsFileApi(attributes=FakeWindowsFileApi.FILE_ATTRIBUTE_REPARSE_POINT)
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names, ["create_file", "file_attribute_tag", "close_handle"])
        self.assertEqual(api.closed, [42])

    def test_directory_is_refused_without_type_or_bridge(self):
        api = FakeWindowsFileApi(attributes=FakeWindowsFileApi.FILE_ATTRIBUTE_DIRECTORY)
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names, ["create_file", "file_attribute_tag", "close_handle"])
        self.assertEqual(api.closed, [42])

    def test_non_disk_type_is_refused_without_bridging(self):
        api = FakeWindowsFileApi(file_type_value=0x3)  # FILE_TYPE_PIPE
        self.assertIsNone(self.guard(api))
        self.assertEqual(
            api.names, ["create_file", "file_attribute_tag", "file_type", "close_handle"]
        )
        self.assertEqual(api.closed, [42])

    def test_file_type_oserror_closes_exactly_once(self):
        api = FakeWindowsFileApi(type_error=OSError("type failed"))
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names[-1], "close_handle")
        self.assertEqual(api.closed, [42])

    def test_bridge_failure_closes_exactly_once(self):
        """If open_osfhandle fails the raw handle is still ours to close."""
        api = FakeWindowsFileApi(open_error=OSError("no fd"))
        self.assertIsNone(self.guard(api))
        self.assertEqual(api.names[-1], "close_handle")
        self.assertEqual(api.closed, [42])

    def test_every_refusal_branch_maps_to_none(self):
        scenarios = [
            # (adapter, number of raw handles that must be closed)
            (FakeWindowsFileApi(handle=None), 0),  # CreateFileW failed: no handle
            (FakeWindowsFileApi(create_error=OSError()), 0),
            (FakeWindowsFileApi(attributes=None), 1),
            (FakeWindowsFileApi(tag_error=OSError()), 1),
            (FakeWindowsFileApi(attributes=FakeWindowsFileApi.FILE_ATTRIBUTE_REPARSE_POINT), 1),
            (FakeWindowsFileApi(attributes=FakeWindowsFileApi.FILE_ATTRIBUTE_DIRECTORY), 1),
            (FakeWindowsFileApi(file_type_value=0x2), 1),  # FILE_TYPE_CHAR
            (FakeWindowsFileApi(type_error=OSError()), 1),
            (FakeWindowsFileApi(open_error=OSError()), 1),
        ]
        for api, expected_closes in scenarios:
            self.assertIsNone(self.guard(api), api.names)
            self.assertEqual(len(api.closed), expected_closes, api.names)

    def test_requested_path_is_root_relative_with_posix_spelling(self):
        api = FakeWindowsFileApi(descriptor=5)
        self.guard(api)
        self.assertEqual(
            api.calls[0],
            ("create_file", str(self.root / "assets" / "generated" / "fixture" / "body.res")),
        )

    def test_dispatch_uses_the_windows_branch_on_nt(self):
        api = FakeWindowsFileApi(descriptor=11)
        with mock.patch.object(os, "name", "nt"), mock.patch.object(
            manifest_validator, "_windows_file_api", lambda: api
        ):
            result = manifest_validator._open_regular_file_descriptor(
                self.root, "assets/generated/fixture/body.res"
            )
        self.assertEqual(result, 11)
        self.assertEqual(api.names[0], "create_file")

    def test_dispatch_keeps_the_posix_branch_off_windows(self):
        with mock.patch.object(os, "name", "posix"), mock.patch.object(
            manifest_validator, "_guarded_open_flags", lambda: None
        ):
            self.assertIsNone(
                manifest_validator._open_regular_file_descriptor(
                    self.root, "assets/generated/fixture/body.res"
                )
            )

    def test_windows_api_construction_failure_fails_closed(self):
        """A platform where even the guarded API cannot bind refuses."""
        with mock.patch.object(
            manifest_validator,
            "_windows_file_api",
            mock.Mock(side_effect=AttributeError("no CreateFileW")),
        ):
            self.assertIsNone(
                manifest_validator._windows_open_regular_descriptor(
                    self.root, "assets/generated/fixture/body.res"
                )
            )

    def test_no_builtin_open_fallback_on_the_windows_branch(self):
        """The requirement is a guarded descriptor, never a plain open()."""
        api = FakeWindowsFileApi(descriptor=13)
        with mock.patch.object(
            builtins, "open", side_effect=AssertionError("unguarded open fallback")
        ):
            self.assertEqual(self.guard(api), 13)


@unittest.skipUnless(os.name == "nt", "native Win32 acceptance requires a Windows host")
class WindowsNativeGuardTestCase(unittest.TestCase):
    """Real-host acceptance for the Windows guarded-open branch.

    Skipped everywhere else. Hosted run `46005883236` at `04015ca` executed
    the nine output/register/manifest-ACL controls in this class 9/9; the
    manifest-input and path-spelling controls added afterwards await their own
    rerun. These are the only tests allowed to claim the Windows behavior
    actually works.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)

    def checker(self):
        return manifest_validator.PathChecker(
            self.root, file_checks=True, check_hashes=True
        )

    def remove_link(self, link: Path) -> None:
        try:
            os.rmdir(link)
        except OSError:
            try:
                os.unlink(link)
            except OSError:
                pass

    def make_junction(self, link: Path, target: Path) -> bool:
        import subprocess

        completed = subprocess.run(
            ["cmd", "/c", "mklink", "/J", str(link), str(target)],
            capture_output=True,
            text=True,
        )
        return completed.returncode == 0

    def write_raw(self, text: str) -> Path:
        """Write raw manifest text into the fixture root."""
        path = self.root / "assets" / "manifest.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def deny_read(self, path: Path) -> None:
        """Deny this account read access through icacls; restored on cleanup.

        The Unix mode-000 controls do not model an ACL denial, so the native
        suite carries the equivalent coverage here.
        """
        import subprocess

        icacls = shutil.which("icacls")
        user = os.environ.get("USERNAME") or os.environ.get("USER")
        if not icacls or not user:
            self.skipTest("ACL control needs icacls and an account name")
        deny = subprocess.run(
            [icacls, str(path), "/deny", "{}:(R)".format(user)],
            capture_output=True,
            text=True,
        )
        if deny.returncode != 0:
            self.skipTest(
                "could not deny read access: {}".format((deny.stdout + deny.stderr).strip())
            )
        self.addCleanup(
            lambda: subprocess.run(
                [icacls, str(path), "/remove:d", user], capture_output=True, text=True
            )
        )

    def test_native_regular_outputs_hash_and_anchors_resolve(self):
        """Positive control: the previously broken normal case."""
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        self.assertEqual(self.checker().digest(relative), digest_of(self.root / relative)[7:])
        findings = validate(self.root, write_manifest(self.root, [entry]), check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))
        service = service_entry(self.root, "texture.service.sky")
        copy_real_terms_register(self.root)
        service["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-stepfun"
        findings = validate(self.root, write_manifest(self.root, [service]), check_hashes=True)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_native_symlinked_output_is_refused(self):
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        target = self.root / relative
        outside = self.root.parent / ("roadstorm-native-link-" + self.root.name)
        outside.write_text("outside the checkout\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        target.unlink()
        try:
            target.symlink_to(outside)
        except OSError as exc:
            self.skipTest("cannot create a symlink on this host: {}".format(exc))
        self.assertIsNone(self.checker().digest(relative))
        findings = validate(self.root, write_manifest(self.root, [entry]), check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("missing-file", codes)
        self.assertNotIn("hash-mismatch", codes)

    def test_native_junction_parent_is_refused(self):
        """A static intermediate junction must fail closed, and never be read.

        Setup writes only to the outside fixture: the linked path inside the
        root is never created or written through the junction. The recorded
        hash is the outside file's real digest, so an implementation that
        wrongly read through the junction would produce a matching digest and
        lose the ``missing-file`` finding - the test detects that.
        """
        outside = self.root.parent / ("roadstorm-native-junction-" + self.root.name)
        outside.mkdir()
        self.addCleanup(shutil.rmtree, outside, True)
        outside_body = outside / "body.res"
        outside_body.write_text("outside the checkout\n", encoding="utf-8")
        outside_bytes = outside_body.read_bytes()
        link = self.root / "assets" / "generated" / "junction"
        link.parent.mkdir(parents=True, exist_ok=True)
        if not self.make_junction(link, outside):
            self.skipTest("mklink /J unavailable on this host")
        self.addCleanup(self.remove_link, link)
        # Materialize the entry without ever touching the linked path.
        entry = complete_entry()
        relative = "assets/generated/junction/body.res"
        touch(self.root, "assets/source/fixture/recipe.json")
        touch(self.root, "content/fixture/recipe.json")
        touch(self.root, "provenance/OWNER_AUTHORITY.md")
        entry["identity"]["output_paths"] = [relative]
        entry["hashes"] = {relative: digest_of(outside_body)}
        self.assertIsNone(self.checker().digest(relative))
        findings = validate(self.root, write_manifest(self.root, [entry]), check_hashes=True)
        codes = error_codes(findings)
        self.assertIn("missing-file", codes)
        self.assertNotIn("hash-mismatch", codes)
        self.assertIn("symlink", messages(findings))
        self.assertEqual(outside_body.read_bytes(), outside_bytes, "validation wrote through the junction")

    def test_native_directory_in_place_of_output_is_refused(self):
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        (self.root / relative).unlink()
        (self.root / relative).mkdir()
        self.assertIsNone(self.checker().digest(relative))
        findings = validate(self.root, write_manifest(self.root, [entry]), check_hashes=True)
        codes = error_codes(findings)
        self.assertTrue({"not-a-file", "missing-file"} & set(codes), codes)

    def test_native_swap_at_the_pre_check_seam_is_still_refused(self):
        """The reparse bit is checked on the opened handle, not the pre-check path."""
        entry = materialize(self.root, complete_entry())
        relative = entry["identity"]["output_paths"][0]
        target = self.root / relative
        outside = self.root.parent / ("roadstorm-native-seam-" + self.root.name)
        outside.write_text("outside the checkout\n", encoding="utf-8")
        self.addCleanup(outside.unlink)
        original = manifest_validator._record_file_is_readable

        def swapped_pre_check(root, spelled):
            target.unlink()
            try:
                target.symlink_to(outside)
            except OSError as exc:
                raise AssertionError("seam test needs a symlink: {}".format(exc)) from exc
            return True

        with mock.patch.object(
            manifest_validator, "_record_file_is_readable", swapped_pre_check
        ):
            digest, timed_out = bounded_call(lambda: self.checker().digest(relative))
        self.assertFalse(timed_out)
        self.assertIsNone(digest)

    def test_native_unreadable_output_is_structured_not_a_traceback(self):
        import contextlib
        import io

        entry = materialize(self.root, complete_entry())
        target = self.root / entry["identity"]["output_paths"][0]
        self.deny_read(target)
        manifest = write_manifest(self.root, [entry])
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main(
                [str(manifest), "--root", str(self.root), "--check-hashes", "--json"]
            )
        self.assertEqual(exit_code, 1)
        payload = json.loads(stdout.getvalue())
        self.assertEqual([e["code"] for e in payload["errors"]], ["missing-file"])
        self.assertEqual(stderr.getvalue(), "")

    def test_native_unreadable_register_is_rejected_before_any_read(self):
        """The register ACL equivalent of the Unix mode-000 control."""
        entry = service_entry(self.root, "texture.service.sky")
        write_terms_register(self.root, ["pi-stepfun"])
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-stepfun"
        manifest = write_manifest(self.root, [entry])
        self.deny_read(self.root / "provenance" / REGISTER_BASENAME)
        with spy_on_register_reads() as reads:
            findings = validate(self.root, manifest, check_hashes=True)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("read", messages(findings))
        # Whatever the ACL reports to os.access, the guarded open must fail.
        self.assertTrue(
            all(descriptor is None for descriptor in reads.register_guards()),
            "an unreadable register must not produce a descriptor",
        )

    def test_native_unreadable_manifest_exits_2_with_json(self):
        """An ACL-denied manifest is 'could not be read', not a content defect."""
        import contextlib
        import io

        manifest = self.root / "assets" / "manifest.json"
        manifest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SHIPPED_MANIFEST, manifest)
        self.deny_read(manifest)
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main([str(manifest), "--root", str(self.root), "--json"])
        self.assertEqual(exit_code, 2)
        payload = json.loads(stdout.getvalue())
        self.assertEqual([e["code"] for e in payload["errors"]], ["unreadable-manifest"])
        self.assertEqual(stderr.getvalue(), "")

    def native_input_paths(self):
        """A real manifest under the root and a valid copy outside it."""
        assets = self.root / "assets"
        assets.mkdir(parents=True, exist_ok=True)
        manifest = assets / "manifest.json"
        manifest.write_text(SHIPPED_MANIFEST.read_text(encoding="utf-8"), encoding="utf-8")
        outside_dir = self.root.parent / ("roadstorm-native-input-" + self.root.name)
        outside_dir.mkdir()
        self.addCleanup(shutil.rmtree, outside_dir, True)
        outside = outside_dir / "manifest.json"
        shutil.copyfile(SHIPPED_MANIFEST, outside)
        return manifest, outside

    def test_native_external_regular_manifest_is_accepted(self):
        _manifest, outside = self.native_input_paths()
        findings = validate(self.root, outside)
        self.assertEqual(findings.errors, [], messages(findings))

    def test_native_manifest_symlink_is_refused_not_read_through(self):
        """The manifest document itself must not be read through a link."""
        manifest, outside = self.native_input_paths()
        control = validate(self.root, outside)
        self.assertEqual(control.errors, [], messages(control))
        target = manifest
        target.unlink()
        try:
            target.symlink_to(outside)
        except OSError as exc:
            self.skipTest("cannot create a symlink on this host: {}".format(exc))
        findings = validate(self.root, target)
        self.assertIn("unreadable-manifest", error_codes(findings))
        self.assertIn("link", messages(findings))

    def test_native_manifest_junction_parent_is_refused(self):
        assets = self.root / "assets"
        assets.mkdir(parents=True, exist_ok=True)
        outside_dir = self.root.parent / ("roadstorm-native-jlink-" + self.root.name)
        outside_dir.mkdir()
        self.addCleanup(shutil.rmtree, outside_dir, True)
        outside = outside_dir / "manifest.json"
        shutil.copyfile(SHIPPED_MANIFEST, outside)
        link = assets / "jlinked"
        if not self.make_junction(link, outside_dir):
            self.skipTest("mklink /J unavailable on this host")
        self.addCleanup(self.remove_link, link)
        # The same document validates directly; only the junction path fails.
        control = validate(self.root, outside)
        self.assertEqual(control.errors, [], messages(control))
        findings = validate(self.root, link / "manifest.json")
        self.assertIn("unreadable-manifest", error_codes(findings))
        self.assertIn("link", messages(findings))

    def test_native_manifest_leaf_swapped_at_the_guarded_open_boundary(self):
        """Open-boundary leaf swap on a real Windows path is refused by the fd guard."""
        manifest, outside = self.native_input_paths()
        control = validate(self.root, outside)
        self.assertEqual(control.errors, [], messages(control))
        original = manifest_validator._manifest_input_problem

        def swapped(path, root):
            problem = original(path, root)
            if problem is None:
                path.unlink()
                try:
                    path.symlink_to(outside)
                except OSError as exc:
                    raise AssertionError(
                        "native seam test needs a symlink: {}".format(exc)
                    ) from exc
            return problem

        with mock.patch.object(manifest_validator, "_manifest_input_problem", swapped):
            findings = validate(self.root, manifest)
        self.assertIn("unreadable-manifest", error_codes(findings))
        self.assertNotIn("invalid-json", error_codes(findings))

    def test_native_alias_prone_manifest_paths_are_rejected(self):
        """Exact Windows control for stream/trailing-dot/reserved spellings."""
        aliases = (
            "assets/generated/fixture/body.res:stream",
            "assets/generated/fixture/body.res.",
            "assets/generated/fixture/body.res ",
            "assets/CON",
            "assets/con.txt",
            "assets/LPT1.res",
            "assets/a\x00b.res",
        )
        for spelling in aliases:
            entry = complete_entry()
            entry["identity"]["output_paths"] = [spelling]
            findings = validate(self.root, write_manifest(self.root, [entry]))
            self.assertIn("invalid-path", error_codes(findings), repr(spelling))
        good = materialize(self.root, complete_entry())
        findings = validate(
            self.root, write_manifest(self.root, [good]), check_hashes=True
        )
        self.assertEqual(findings.errors, [], messages(findings))

    def test_native_oversized_integer_cli_exits_2_with_json(self):
        import contextlib
        import io

        limit = getattr(sys, "get_int_max_str_digits", lambda: 0)()
        if not limit:
            self.skipTest("this interpreter has no integer digit limit")
        manifest = self.write_raw('{"schema_version": ' + ("9" * (limit + 100)) + "}")
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            exit_code = main([str(manifest), "--root", str(self.root), "--json"])
        self.assertEqual(exit_code, 2)
        payload = json.loads(stdout.getvalue())
        self.assertEqual([e["code"] for e in payload["errors"]], ["invalid-json"])
        self.assertEqual(stderr.getvalue(), "")


if __name__ == "__main__":
    unittest.main()