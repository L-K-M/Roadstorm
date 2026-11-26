# Asset manifest validator

M0 provenance manifest tooling (job `6058a51e-ae48-4329-8fb0-52c3c36eddad`,
model `stepfun/step-5-preview`, base revision
`d544c1cfaa96a120e11a1a884bd45d7fe06c60bb`). Owned paths: `assets/manifest.json`
and `tools/asset_manifest/**`.

This is a record format and a checker for the provenance/lineage metadata of
first-party creative assets and learned model artifacts. It implements the
manifest contract in [`../../provenance/MANIFEST_CONTRACT.md`](../../provenance/MANIFEST_CONTRACT.md)
("Creative asset and model manifest fields") and the release rights gate in
[`../../docs/ASSET_PRODUCTION.md`](../../docs/ASSET_PRODUCTION.md) ("Release
rights gate"). It is not a legal instrument, a rights dedication, or a claim
about any asset that does not exist.

## Files

| Path | Role |
| --- | --- |
| `manifest_validator.py` | Validator library: loads a manifest and returns findings (errors/warnings). |
| `validate_manifest.py` | Command-line entry point (thin wrapper). |
| `tests/test_manifest_validator.py` | Standard-library `unittest` suite, including the shipped empty manifest. |
| `run_tests.sh` | Runs the suite with no arguments needed. |
| `../../assets/manifest.json` | The manifest itself. Currently an honest empty registry. |

## The empty manifest

`assets/manifest.json` currently registers **no** assets. That is a statement
about the tree, not a promise about it:

- No first-party creative asset or learned model artifact has been produced or
  registered yet. The asset pipeline (M2/M7 and the other production
  milestones) has not started.
- An empty manifest is **not** evidence that the launch inventory in
  `docs/ASSET_PRODUCTION.md` exists, is complete, or is on track. It only means
  nothing is registered here.
- Entries are added by the producing tasks as outputs are hashed and reviewed.
  This file records assets; it does not create them and grants no rights.
- Rights authority and provider terms for the authoring routes remain open
  (`provenance/OPEN_ITEMS.md` OI-01, OI-02, OI-03). No entry may ship until its
  legal origin is resolved; the validator treats unknown legal origin as a
  blocking error.

Code, tools, tests, schemas and text definitions are not creative assets and
are not listed here. Their provenance lives in the task/commit records under
`provenance/` (the recommended commit trailer is in
`provenance/MANIFEST_CONTRACT.md`). The task-level record for this job belongs
in `provenance/TASK_<job-id>.md`, which is owned by the rights/provenance work,
not by this tool.

## Usage

```sh
# Validate the shipped manifest from the repository root
python3 tools/asset_manifest/validate_manifest.py assets/manifest.json

# Validate any manifest file, resolving paths against an explicit root
python3 tools/asset_manifest/validate_manifest.py --root . assets/manifest.json

# Also hash every referenced output file and compare it with the record
python3 tools/asset_manifest/validate_manifest.py assets/manifest.json --check-hashes

# Structure-only (do not touch the filesystem)
python3 tools/asset_manifest/validate_manifest.py assets/manifest.json --no-file-checks

# Machine-readable output
python3 tools/asset_manifest/validate_manifest.py assets/manifest.json --json

# Run the test suite
tools/asset_manifest/run_tests.sh            # or: python3 -m unittest discover -s tools/asset_manifest/tests -t tools/asset_manifest -v
```

Exit codes follow the project convention (`tools/ci/ci.sh`,
`tools/toolchain/verify.sh`): `0` = no errors, `1` = validation errors,
`2` = the manifest could not be read or the command line was wrong.

## What the validator checks

Top level: the manifest is a JSON object; `manifest_id` and `schema_version`
match this tool's format; `registry_status` (`empty` or `populated`) agrees
with the entry list; only known fields appear (unknown fields are errors unless
`--allow-unknown-keys` downgrades them to warnings).

Per asset entry, the essential provenance and lineage metadata:

| Group | Checked |
| --- | --- |
| Identity | `id` is a non-empty, unique, project-pattern stable ID; `category` is present; `identity.source_paths` and `identity.output_paths` are non-empty, clean, project-relative POSIX paths that exist. |
| Hashes | Every `identity.output_paths` entry has a `sha256:<64 hex>` record, and no hash is recorded for an unlisted path; `--check-hashes` recomputes them. |
| Origin | `origin` is one of `llm_script_generated`, `service_generated`, `external_cc0`. |
| Authoring | `authoring` is present; `task`/`prompt_ref`/`agent`/`provider`/`model`/`date`/`route` are strings and may be `unknown`. |
| Generation | `generator` is recorded; first-party assets also record `recipe_path` and `regeneration_command` (the release gate blocks missing source recipes); `input_asset_ids` reference registered IDs. |
| Reproducibility | `reproducibility_class` is one of the contract's three classes. |
| Rights | `license_spdx` and `rights_holder_record` are present and not `unknown` (unknown legal origin blocks shipping); first-party licenses are limited to `CC0-1.0`/`Unlicense`, external input to verified item-level `CC0-1.0`; `service_generated` entries must reference provider terms; `external_cc0` entries must record upstream URL/date/evidence. |
| Review | `status`, `reviewer`, `limitations`, `release_inclusion` are present; `release_inclusion: true` requires `status: approved`, and a rejected entry cannot be marked for release. |
| Lineage | `upstream_inputs` is present (possibly `[]`); each input has an `asset_id` or `path`, and external inputs carry license and evidence; `depends_on` references registered IDs; referenced paths exist. |

## Tests

`tests/test_manifest_validator.py` covers, among others:

- the shipped empty manifest validates with zero errors and warnings, with and
  without `--check-hashes`, and declares `registry_status: "empty"` with no
  entries;
- **missing required entries** (manifest-level and entry-level fields, missing
  hashes, missing recipe/regeneration for first-party assets);
- **duplicate stable IDs** (rejected) and distinct IDs (accepted);
- **missing referenced files** (source path, output path, recipe path),
  clean-relative-path spelling, hash recomputation and mismatch detection;
- rights gating: unknown legal origin, disallowed licenses, external-CC0
  evidence, service-generated terms;
- review/release consistency, dangling lineage references, unknown fields,
  schema version/manifest ID mismatches, malformed JSON, unreadable manifest,
  bad root, and CLI exit codes 0/1/2.

Run them with `tools/asset_manifest/run_tests.sh` (or the `unittest discover`
command above). They use only the standard library and write fixtures into a
temporary directory.

## Limitations

- **Scope.** This validates the manifest, not the assets. Technical metadata
  (triangle/material counts, LODs, duration, sample rate, loop settings, model
  dimensions) is recorded by entries but is not independently verified here;
  that belongs to the producing pipeline and to the review record.
- **No hash discovery.** Hashes are only checked for paths the manifest
  records, and only with `--check-hashes`. Nothing scans the tree for
  unregistered files; that is the package validator's job at T15.
- **Single-format checker.** `schema_version` is `0.1.0`; any format change
  needs a new version recorded with a decision, exactly as for
  `schemas/common.schema.json`. The contract constants live at the top of
  `manifest_validator.py`; there is no separate JSON Schema file to drift from.
- **Policy-derived license sets.** The allowed license identifiers are derived
  from `docs/ASSET_PRODUCTION.md` and `licenses/README.md` at M0
  (first-party `CC0-1.0`/`Unlicense`, external item-level `CC0-1.0`). If the
  rights work revises scope, this list must be revised with it.
- **References are not verified content.** `rights_holder_record` may point at
  `provenance/OWNER_AUTHORITY.md` while OI-01 is still open; the validator
  checks that a reference is recorded, not that the referenced instrument is
  executed. Likewise `service_terms_ref` is checked for presence, not for
  verified terms.
- **Existence is local.** Path checks resolve against the given root on the
  machine running the check. Cross-platform path case sensitivity is not
  simulated.
- **No CI wiring yet.** `tools/ci/` is owned by another job; wiring this
  validator into `ci.sh validate` (and `contracts.list`) is a follow-up for
  that owner. Until then, run it directly.
- **No asset entries exist.** The positive-control entry in the tests is a
  fixture. The first real entries will exercise parts of this contract that
  fixtures cannot, and may legitimately require a `schema_version` bump.

Original project code under the Unlicense.
