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
import sys
import tempfile
import unittest
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]  # tools/asset_manifest
_REPO_ROOT = _TOOL_DIR.parents[1]  # the project checkout
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

from manifest_validator import (  # noqa: E402  (path set up above)
    MANIFEST_ID,
    SCHEMA_VERSION,
    Findings,
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
            "reviewer": "unknown",
            "approval_revision": "unknown",
            "technical_check": "unknown",
            "perceptual_review": "unknown",
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


def touch(root: Path, relative: str) -> Path:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("fixture bytes for " + relative + "\n", encoding="utf-8")
    return path


def digest_of(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def materialize(root: Path, entry: dict) -> dict:
    """Create the files an entry references and record their real hashes."""
    for relative in entry["identity"]["source_paths"]:
        touch(root, relative)
    for relative in entry["identity"]["output_paths"]:
        touch(root, relative)
    if entry["generation"].get("recipe_path"):
        touch(root, entry["generation"]["recipe_path"])
    entry["hashes"] = {
        relative: digest_of(root / relative) for relative in entry["identity"]["output_paths"]
    }
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
        second = materialize(self.root, complete_entry("car.fixture.wing"))
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

    # -- lineage and references ---------------------------------------------

    def test_dangling_dependency_reference_is_an_error(self):
        entry = materialize(self.root, complete_entry())
        entry["lineage"]["depends_on"] = ["car.ghost.missing"]
        manifest = write_manifest(self.root, [entry])
        findings = validate(self.root, manifest)
        self.assertIn("dangling-reference", error_codes(findings))

    def test_registered_dependency_reference_passes(self):
        first = materialize(self.root, complete_entry("car.fixture.body"))
        second = materialize(self.root, complete_entry("car.fixture.paint"))
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


if __name__ == "__main__":
    unittest.main()
