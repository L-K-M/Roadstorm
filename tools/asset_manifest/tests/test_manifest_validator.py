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

import hashlib
import json
import os
import shutil
import sys
import tempfile
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
        """The real register holds two rows; anything else is an invented fragment."""
        entry = service_entry(self.root)
        copy_real_terms_register(self.root)
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-mistral"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("unresolved-reference", error_codes(findings))
        self.assertIn("pi-mistral", messages(findings))

    def test_route_row_resolution_is_skipped_without_file_checks(self):
        """Reading the register is resolution: --no-file-checks stays structural."""
        entry = service_entry(self.root)
        write_terms_register(self.root, ["pi-stepfun"])
        entry["rights"]["service_terms_ref"] = "provenance/PROVIDER_TERMS.md#pi-missing"
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest, file_checks=False)
        self.assertNotIn("unresolved-reference", error_codes(findings))

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
        if os.geteuid() == 0:
            self.skipTest("running as root: permission bits do not block reads")
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


if __name__ == "__main__":
    unittest.main()
