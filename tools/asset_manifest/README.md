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

# Run the test suite (a <pattern> filters tests with unittest -k)
tools/asset_manifest/run_tests.sh            # or: python3 -m unittest discover -s tools/asset_manifest/tests -t tools/asset_manifest -v
tools/asset_manifest/run_tests.sh rights    # only tests whose names match "rights"
```

Exit codes follow the project convention (`tools/toolchain/verify.sh`;
`tools/ci/ci.sh` states the same convention): `0` = no errors, `1` =
validation errors, `2` = the manifest could not be read or the command line
was wrong. "Could not be read" is the read itself: a missing or unreadable
file, a nonexistent `--root` (`bad-root`), or text that is not JSON
(`invalid-json`) each exit 2. A document that decodes but breaks the
contract - including one that is not valid UTF-8 (`invalid-encoding`) - is a
content defect and exits 1.

## What the validator checks

Top level: the manifest is a JSON object; `manifest_id` and `schema_version`
match this tool's format; `registry_status` (`empty` or `populated`) agrees
with the entry list; only known fields appear (unknown fields are errors unless
`--allow-unknown-keys` downgrades them to warnings).

Per asset entry, the essential provenance and lineage metadata:

| Group | Checked |
| --- | --- |
| Identity | `id` is a non-empty, unique, project-pattern stable ID; `category` is present; `identity.source_paths` and `identity.output_paths` are non-empty, clean, project-relative POSIX paths that exist as regular files, reached through real directories; optional `identity.schema`/`identity.revision` record which definition of the asset's format the entry describes (recorded, not verified). |
| Hashes | Every `identity.output_paths` entry has a `sha256:<64 hex>` record, and no hash is recorded for an unlisted path; hash keys must be clean project-relative POSIX paths, so `--check-hashes` never resolves or hashes a path outside the root - not even one whose only problem is a symlinked parent directory; `--check-hashes` recomputes them. |
| Origin | `origin` is one of `llm_script_generated`, `service_generated`, `external_cc0`. |
| Authoring | `authoring` is present; `task`/`prompt_ref`/`agent`/`provider`/`model`/`date`/`route` are strings and may be `unknown`. |
| Generation | `generator` is recorded; first-party assets also record `recipe_path` and `regeneration_command` (the release gate blocks missing source recipes); `input_asset_ids` reference registered IDs; `seed` is a string, integer or null (a boolean is not a seed). |
| Reproducibility | `reproducibility_class` is one of the contract's three classes. |
| Technical | Optional free-form group: dimensions, triangle/material counts, LODs, duration, sample rate/channels, loop settings, model dimensions as applicable. Recorded, not verified (see Limitations); its members are deliberately not key-checked. |
| Rights | `license_spdx` and `rights_holder_record` are present and not `unknown` (unknown legal origin blocks shipping); first-party creative material is limited to `CC0-1.0` (Unlicense covers code/tools/tests/schemas/text, which are not in this manifest), external input to verified item-level `CC0-1.0`; `service_generated` entries must reference provider terms (omission or `null` is an error, not a bypass, and the reference must resolve in one of the two documented forms: the register `provenance/PROVIDER_TERMS.md`, optionally with a `#route-id` anchor that must name a row that actually exists in the register - matched exactly, case included, so invented and wrongly-cased fragments are rejected - or a bounded snapshot `provenance/provider_terms/<route-id>/<file>` whose route component is a real directory in the checkout; the `not_applicable` first-party sentinel, any other placeholder, a file written directly under `provenance/provider_terms/` with no route directory, a route directory with no file, deeper nesting, a fragment on a snapshot reference, and a path to a record that does not exist are all rejected); `rights_holder_record` must resolve to a record under `provenance/`; `external_cc0` entries must record upstream url/date/evidence. |
| Review | `status`, `reviewer`, `limitations`, `release_inclusion` are present; `release_inclusion: true` requires `status: approved`, and a rejected entry cannot be marked for release; an approved or release-included entry additionally records a known `reviewer`, `approval_revision`, `technical_check` and `perceptual_review` (the contract's Review group requires the visual/audio/model review), because `unknown` on a shipping claim is not an approval record. |
| Lineage | `upstream_inputs` is present (possibly `[]`); each input has an `asset_id` or `path`, and external inputs carry license and evidence; an `external_cc0` entry records at least one upstream input, so its evidence trail is never empty; `depends_on` references registered IDs; referenced paths exist. |

Cross-entry, once the whole registry is known:

| Check | Rule |
| --- | --- |
| Output ownership | Each `identity.output_paths` entry has exactly one owning entry, and is listed once inside it (`duplicate-output-path`). Two entries claiming one output path make the provenance, lineage and hash of that file ambiguous. Sharing a *source* path is ordinary lineage and stays allowed. |
| Path safety | Referenced paths must be regular files inside the root reached through real directories: a symlink is rejected (`symlinked-path`) - at the leaf *and* at any parent directory, because a parent symlink resolves to a file outside the checkout that the entry does not govern, and its existence and hash would vouch for unaccounted content. Hash keys are spelling-checked and re-checked for symlinks before hashing, so a malformed `output_paths` cannot make `--check-hashes` read `/etc/hosts`. Every root-relative record or hash file the checker opens - a hashed output or the provider-terms register - goes through one guarded open: no-follow, non-blocking and an `fstat` regular-file check, failing closed where those flags do not exist, so an unreadable, missing, special-file or swapped path yields a structured finding rather than a traceback, a hang or a followed symlink. A record the checker *reads* (the register, whose rows a `#route-id` anchor is resolved against) is additionally read only after the reference itself resolved to a real, readable, non-symlinked regular file inside the root, so a rejected register path is never opened. |
| Dependency order | `lineage.depends_on` is acyclic (`dependency-cycle`): direct (A↔B), self (A→A) and indirect (A→B→C→A) loops are all rejected, because an asset can only be built once the entries it depends on exist. The search is iterative, so a long chain cannot exhaust the stack. |

Document level:

| Check | Rule |
| --- | --- |
| Duplicate JSON members | A member written twice in the same JSON object is an error at any depth (`duplicate-json-member`) — top level, entry level, and nested `rights`, `review`, `lineage` and array-element objects. Python's JSON keeps only the last value, so a repeat silently overwrites the earlier record (for example a second `registry_status`). Repeated *array items* are values, not members, and stay allowed. |
| Encoding | The manifest must be valid UTF-8. A decoding failure is reported as the structured finding `invalid-encoding` (exit 1) instead of a traceback, in both text and `--json` output. |

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
  evidence, service-generated terms (placeholder, arbitrary-string and
  nonexistent-record references rejected; the register row and a bounded
  route snapshot accepted), rights-record resolution;
- review/release consistency (including the perceptual review of a shipping
  claim), dangling lineage references, unknown fields,
  schema version/manifest ID mismatches, malformed JSON, unreadable manifest,
  bad root, and CLI exit codes 0/1/2.
- **output ownership**: two individually valid entries with distinct IDs, the
  same output path and correct hashes are rejected with
  `duplicate-output-path` even with `--check-hashes`; a path listed twice in
  one entry is rejected; a shared *source* path stays valid;
- **dependency cycles**: a direct A↔B loop, a self-dependency, an indirect
  A→B→C→A loop, and a loop combined with a dangling reference are each
  rejected with `dependency-cycle`, while a three-entry acyclic chain and a
  1500-entry acyclic chain validate cleanly with hash verification on;
- **duplicate JSON members**: the contradictory `registry_status` pair and
  repeated nested `rights.license_spdx`, `review.status` and
  `lineage.upstream_inputs[0].path` members are each reported once at their
  exact location; repeated array items are not;
- **encoding**: a one-byte invalid UTF-8 manifest yields the structured
  `invalid-encoding` finding and exit 1, in text mode and under `--json`
  (no traceback).
- **rights omissions** (the gate must not be bypassable by leaving a field
  out): a `service_generated` entry with no `service_terms_ref`, or with it
  set to `null`; an `external_cc0` entry with no `rights.upstream`, with it
  `null`, or with an empty `upstream_inputs` list; and the positive control
  of a fully evidenced external entry that passes with hash verification.
- **approval records**: an approved entry with an `unknown` reviewer, and an
  approved entry missing `approval_revision`/`technical_check`, are errors,
  while a pending, non-released entry may still record `unknown`.
- **technical and identity metadata**: the free-form `technical` group is
  accepted (unknown members are not errors) but must be an object;
  `identity.schema`/`revision` are recorded strings.
- **creative licensing**: a first-party entry claiming `Unlicense` is a
  `disallowed-license` error, with the message naming the CC0-1.0
  requirement for creative assets.
- **type and path safety**: `seed: true` is rejected (a boolean is not a
  seed); a symlinked reference - including one escaping the root - is
  `symlinked-path`; with a malformed `output_paths`, `--check-hashes` does
  not hash an absolute key such as `/etc/hosts`.
- **symlinked parent directories**: an output, source or recipe path that
  resolves through a symlinked intermediate directory is `symlinked-path`,
  even though its leaf is a regular file, and `--check-hashes` refuses to
  hash it (no `hash-mismatch`, i.e. the file outside the root is never
  read). Covered end to end through the CLI (exit 1) and, for the
  time-of-check/time-of-use window, by tests that swap the file - or its
  parent directory - for a symlink inside the hash step and require the
  digest to refuse rather than follow it.
- **unreadable, special and swapped outputs under `--check-hashes`** (the
  2026-11-27 Sol recheck finding 1 / Opus independent finding F2): a mode-000
  output is the structured `missing-file` finding ("cannot hash ...",
  unreadable), not a `PermissionError` traceback - checked directly, through
  the CLI in `--json` mode (exit 1, empty stderr), and by the digest unit
  control; a FIFO and a symlink swapped in at the pre-check/open boundary
  are refused by the guarded descriptor without blocking and without
  following the link (the outside bytes are never hashed); a passing
  regular file still hashes normally. The fd-level primitive
  (`_open_regular_file_descriptor`) has direct controls too: it returns a
  descriptor for a regular file, refuses a FIFO without blocking and a
  symlinked leaf, and fails closed when no-follow/non-blocking flags are
  unavailable.
- **oversized JSON integers** (the 2026-11-27 Sol recheck finding 2): a
  decimal integer literal longer than this interpreter's conversion limit is
  the structured `invalid-json` finding, not a `ValueError` traceback -
  checked in text mode and through the CLI in `--json` mode (exit 2, empty
  stderr). Skipped where the interpreter has no digit limit.
- **reference resolution**: a `service_terms_ref` that is the first-party
  `not_applicable` sentinel, another placeholder, an arbitrary string, a
  record outside `provenance/`, or a record that does not exist is an error,
  while `provenance/PROVIDER_TERMS.md#<route-id>` and
  `provenance/provider_terms/<route-id>/<file>` are accepted; a
  `rights_holder_record` that does not resolve to an existing record under
  `provenance/` (including a symlinked one) is an error; resolution is
  skipped under `--no-file-checks` like every other existence check.
- **a rejected register path is never read** (the 2026-11-27 Sol recheck,
  finding 3): the fragment checker no longer reads the register after the
  path check has refused it. Each of a symlinked register, a register
  reached through a symlinked `provenance/`, a missing register, a directory
  in its place, a FIFO in its place, an unreadable register and a register
  that is not UTF-8 is reported as `unresolved-reference` and produces no
  read at all - the tests instrument the read itself (the module's read
  path plus `os.open`, `builtins.open`, `Path.read_text` and
  `Path.read_bytes`) and require zero open attempts, and a FIFO is required
  to finish instead of hanging, which is what the previous code did. The
  positive controls are kept: an accepted `#route-id` is still read exactly
  once, and a register reference with no anchor is not read at all. Two
  time-of-check/time-of-use tests swap the register for a symlink and for a
  FIFO inside the reference check and require the read to refuse; that
  narrows the window but is explicitly *not* race-free resolution.
- **provider-terms route resolution** (the M0 checkpoint recheck): a
  `#route-id` anchor on the register must name a row that exists in
  `provenance/PROVIDER_TERMS.md` - an invented fragment
  (`#missing-fixture-route`), a wrongly-cased one (`#PI-STEPFUN` against the
  row `pi-stepfun`) and a bare trailing `#` are `unresolved-reference`
  errors, while the real rows (`pi-longcat`, `pi-stepfun`) and the real
  snapshot directories resolve; a snapshot reference must match
  `provenance/provider_terms/<route-id>/<file>` exactly - a file directly
  under `provenance/provider_terms/` with no route directory, a route
  directory with no file, deeper nesting, and a `#fragment` on a snapshot
  are rejected - and the route directory must be real: missing, a plain
  file in its place, or a symlink are all rejected. Covered end to end
  through the CLI (valid route exits 0, invented route exits 1) and against
  the checkout's real register and snapshot layout.
- **exit contract**: an unreadable manifest (permission denied), invalid
  JSON and a nonexistent `--root` each exit 2, in text and `--json` mode,
  while invalid UTF-8 still exits 1.
- **test runner**: `run_tests.sh <pattern>` runs the matching tests via a
  unittest `-k` filter instead of failing with "Start directory is not
  importable".

Run them with `tools/asset_manifest/run_tests.sh` (or the `unittest discover`
command above). They use only the standard library and write fixtures into a
temporary directory.

## Limitations

- **Scope.** This validates the manifest, not the assets. Technical metadata
  (triangle/material counts, LODs, duration, sample rate, loop settings, model
  dimensions) is recorded by entries in the free-form `technical` group but is
  not independently verified here; that belongs to the producing pipeline and
  to the review record. Likewise `identity.schema`/`revision` are recorded
  declarations: no per-asset schema files exist yet.
- **No hash discovery.** Hashes are only checked for paths the manifest
  records, and only with `--check-hashes`. Nothing scans the tree for
  unregistered files; that is the package validator's job at T15.
- **Single-format checker.** `schema_version` is `0.1.0`; any format change
  needs a new version recorded with a decision, exactly as for
  `schemas/common.schema.json` (that file is referenced as the shared
  `stable_id`/`content_hash` vocabulary and is not committed with this
  candidate - see the disposition of finding 8). The contract constants live
  at the top of `manifest_validator.py`; there is no separate JSON Schema
  file to drift from.
- **Policy-derived license sets.** The allowed license identifiers are derived
  from `docs/ASSET_PRODUCTION.md` and `licenses/README.md` at M0. This
  manifest covers creative assets and model artifacts only, so its first-party
  set is `CC0-1.0`: Unlicense remains the project dedication for code, tools,
  tests, schemas and text definitions, which are not listed here. If the
  rights work revises scope, this list must be revised with it.
- **References resolve, their content is not verified.**
  `rights_holder_record` must resolve to an existing record under
  `provenance/` and `service_terms_ref` to the terms register (with a
  `#route-id` anchor that names a real register row, matched exactly and
  case included) or a bounded route snapshot
  `provenance/provider_terms/<route-id>/<file>` with a real route
  directory, but the validator checks that the referenced file and row
  exist, not that the referenced instrument is executed or that the terms
  are compatible: `provenance/OWNER_AUTHORITY.md` may exist while OI-01 is
  still open, and a located terms document is not a verified one. Provider
  eligibility and terms verification remain separate, open tasks; nothing
  here is a claim of legal adequacy. Route rows are read as register text,
  so the row check is skipped under `--no-file-checks` like every other
  existence check, and a snapshot route directory is checked on the local
  filesystem (its case follows the local filesystem, per "Existence is
  local" below).
- **Dependency edges.** The cycle check covers `lineage.depends_on`, the
  production dependency order. `generation.input_asset_ids` records which
  registered assets a recipe consumed, not the build order, so it is checked
  for registration (dangling references) but not for cycles.
- **Existence is local.** Path checks resolve against the given root on the
  machine running the check, and referenced files must be regular files
  reached through real directories: a symlink at any component is rejected
  rather than followed. Cross-platform path case sensitivity is not
  simulated.
- **Reads narrow, they do not close, the swap window.** Every open this tool
  performs re-validates spelling, every component for symlinks, file type and
  read permission before opening, then re-checks the descriptor with `fstat`
  and opens no-follow and non-blocking. That catches a leaf swapped between
  the check and the open. It does **not** make resolution race-free: parent
  components are still resolved by name by the kernel after those checks, so
  a parent directory replaced by a symlink in that window would be followed,
  and a swap after the open is invisible. A `dir_fd`-based walk would be
  needed for that, and it is not implemented. Where the platform offers
  neither `O_NOFOLLOW` nor `O_NONBLOCK`, reads fail closed instead.
- **Limited CI wiring.** The committed GitHub workflow runs the manifest CLI
  separately; full content validation and package inventory remain open.
- **No asset entries exist.** The positive-control entry in the tests is a
  fixture. The first real entries will exercise parts of this contract that
  fixtures cannot, and may legitimately require a `schema_version` bump.

## Disposition of review findings

Recorded from `review/implementation/m0-five-jobs-opus-0bbb2f75-c3eb-47f5-9d89-771bce087012.md`
(job `ed8c1319-fabb-47d5-8b27-266cc1348576`, owned paths
`tools/asset_manifest/**` and `assets/manifest.json`). Each item below states
what was done, or why nothing was done; nothing was implemented that the plan
and contract do not require.

| Finding | Disposition |
| --- | --- |
| 1 - rights gate bypassable by omitting fields | Fixed. `service_terms_ref` is required for `service_generated`; `rights.upstream` (url/date/evidence) and at least one upstream input with license and evidence are required for `external_cc0`. Omission and explicit `null` are both errors. First-party entries may still record `upstream_inputs: []`. |
| 2 - approved/released entry with unknown reviewer and no approval revision | Fixed. When `status == "approved"` or `release_inclusion` is true, `reviewer`, `approval_revision` and `technical_check` must be present and not `unknown`. Pending entries may keep unknowns. The positive-control fixture now uses real-looking values. |
| 3 - headless smoke test passes despite script errors | Out of scope: `tools/smoke/**` and the engine runs are owned elsewhere. Not addressed here. |
| 4 - Technical group and identity schema/revision not recordable | Fixed. `technical` is an optional free-form object (recorded, not verified); `identity.schema`/`revision` are optional recorded strings. No per-asset schema exists yet, so contents are not validated - see Limitations. |
| 5 - Jolt not selected in `project.godot` | Out of scope: `project.godot` is owned elsewhere. Not addressed here. |
| 6 - toolchain documents contradict their verification status | Out of scope: `docs/TOOLCHAIN.md` and `tools/toolchain/**` are owned elsewhere. Not addressed here. |
| 7 - `verify.sh` passes when export templates are absent | Out of scope: `tools/toolchain/**` is owned elsewhere. Not addressed here. |
| 8 - changed files point to files absent at the reviewed SHA | Reconciled honestly against the **committed candidate**, not the working tree. At the reviewed revisions (`bdeb8e2`, `935b9e2`) `provenance/**` and `licenses/**` *are* committed, so every `provenance/...` and `licenses/README.md` reference resolves in the candidate. `schemas/common.schema.json` (cited by `manifest_validator.py` for the shared `stable_id`/`content_hash` vocabulary, by the Limitations note on `schema_version`, and by the tests) and `tools/ci/**` (cited by the exit-code convention and the CI-wiring limitation) are **not** part of the committed candidate: they exist only as uncommitted work owned by other jobs. The references are therefore marked as pending rather than claimed as committed content, and no file was added, moved or committed here. |
| 9 - exit-code contract violated | Fixed. `bad-root`, `unreadable-manifest` and `invalid-json` now exit 2 ("could not be read or the command line was wrong"), matching the documented convention; a decodable but defective document (including `invalid-encoding`) still exits 1, because it was read and failed validation. The documentation was not changed to match the old behavior. |
| 10 - documented `<pattern>` form of `run_tests.sh` broken | Fixed. A first positional argument is passed to `unittest` as a `-k` filter; flags still pass through. |
| 11 - first-party creative assets may be marked `Unlicense` | Fixed. `FIRST_PARTY_LICENSES` is now `CC0-1.0` only, per `docs/ASSET_PRODUCTION.md` ("original editable scores, glyph/mesh artwork sources and their creative outputs use CC0, as do original weights/datasets"). Unlicense remains correct for code, tools, tests, schemas and text definitions, which are not creative assets and are not listed in this manifest; the error message says so. |
| 12 - further boundary cases that should not pass | Fixed for the remaining items. `seed: true` is rejected (a boolean is not a seed, though `bool` subclasses `int`); symlinked references are rejected; hash keys are spelling-checked so `--check-hashes` cannot hash a path outside the root. The symlink rule is deliberately stricter than the review's minimum (reject only symlinks escaping the root): a symlink inside the root still hides the governed file's real location, so any symlinked reference is reported. Duplicate output paths and duplicate JSON members were fixed by the previous job and are preserved. The rule was later extended to symlinked *parent* directories - see R1 below. |
| 13 - smoke version check ignores build and commit | Out of scope: `tools/smoke/**`. Not addressed here. |
| 14 - `.gitignore` coverage | Out of scope: repository-root file, open M0.2 item. Not addressed here. |

No review recommendation conflicted with the plan or the manifest contract;
where the review offered a choice (finding 9: map exit codes vs. correct the
documentation), the documented contract was kept and the code was made to
match it.

## Disposition of the M0 five-job recheck (Opus)

Recorded from
`review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md`
(job `929c4082-0280-464e-830a-00dd35c164e1`, candidate `bdeb8e2`). The
remediation below was implemented in job
`bc086adc-5f31-492e-8d48-54b10fb081cf` (model `stepfun/step-5-preview`, input
revision `935b9e2`) inside the owned paths only; the coordinator's null-root
decoder-sentinel fix in `935b9e2` is preserved untouched, and its regression
test still passes.

| Finding | Disposition |
| --- | --- |
| R1 (Major) - a symlinked directory in a manifest path escapes the root, including under `--check-hashes` | Fixed. `PathChecker.check` and `PathChecker.digest` no longer test only the final component: every component below the root is tested, for existence checks and for hashing alike, so a reference that resolves through a symlinked parent directory is `symlinked-path` and is never hashed. The digest re-validates the path itself, so a file (or parent) swapped for a symlink between the check and the hash step is refused rather than followed. Regression tests cover a symlinked parent for an output, source and recipe path, the CLI end to end (exit 1, no `hash-mismatch`), the hash-key path when `output_paths` is malformed, and both time-of-check/time-of-use races. |
| R2 (Medium) - `service_generated` accepts a placeholder or unresolvable `service_terms_ref` | Fixed. For `service_generated` the reference must be meaningful *and* resolvable: the first-party `not_applicable` sentinel and the other placeholders (`not-applicable`, `n/a`, `na`, `none`, `tbd`, `-`) are `unknown-legal-origin` errors, an arbitrary string or a path outside the terms register is `unresolved-reference`, and the target must exist in the checkout. Accepted forms are the register itself with an optional `#route-id` anchor (`provenance/PROVIDER_TERMS.md#pi-stepfun`) and a bounded snapshot (`provenance/provider_terms/<route-id>/<file>`). First-party entries keep `not_applicable`, because no service produced them. |
| R5 (Minor) - a shipping entry passes with `perceptual_review: "unknown"`, and `rights_holder_record` is not resolved | Fixed for the supported parts. An approved or release-included entry must record `perceptual_review` (the contract's Review group requires the visual/audio/model review) and it may not be `unknown`; a pending entry may still omit it or record the unknown. `rights_holder_record` must resolve to an existing record under `provenance/` (`provenance/NOPE.md`, a URL and a symlinked record are `unresolved-reference`); an optional `#anchor` is allowed. Resolution is skipped under `--no-file-checks`, like every other existence check. |
| R3 - nothing guards the Jolt pin in the main project | Out of scope: `project.godot` and `tools/smoke/**` are owned elsewhere. Not addressed here. |
| R4 - referenced files missing at the SHA, stale disposition text | The stale-text part is in this file and is fixed (see finding 8 above and the marked `schemas/`/`tools/ci/` references): the disposition now states which references exist in the committed candidate and which are pending, and it does not claim that `schemas/common.schema.json` or `tools/ci/**` are committed. Committing those files belongs to their owning jobs. |
| R6-R9 - stale docs, Jolt job warning, cosmetic runner text, `.gitignore` | Out of scope: `docs/**`, `tools/smoke/**`, `.gitignore` and the engine runs are owned elsewhere. Not addressed here. |

Original project code under the Unlicense.

**Follow-up:** `tools/ci/` was committed as `6e5b0d1` after the historical recheck above. `schemas/common.schema.json` remains pending integration.

## Disposition of the M0 checkpoint recheck (Sol, 2026-11-26)

Recorded from
`review/implementation/m0-checkpoint-sol-recheck-15faf0d.md` (candidate
`15faf0d572c1fd917b680a123f431c7086806227`, comparison base
`bdeb8e24619ba7f833613301df43ffa09b0ce36d`). The remediation below was
implemented inside the owned paths (`tools/asset_manifest/**`) only; the
previous null-root fix (`935b9e2`) and the symlink hardening (`b28d5bf`) are
preserved untouched, and their regression tests still pass.

| Finding | Disposition |
| --- | --- |
| 1 (Medium) - a provider-terms snapshot passes without a route directory | Fixed. A snapshot reference must match the documented layout `provenance/provider_terms/<route-id>/<file>` exactly: a file written directly under `provenance/provider_terms/` (the reviewed `terms.md` case), a route directory with no file, and nesting deeper than `<route-id>/<file>` are `unresolved-reference` errors, and the route component must be a real directory in the checkout (missing, a plain file in its place, or a symlink are rejected). A `#fragment` on a snapshot reference is rejected as an invented fragment; the documented snapshot form has no fragment. |
| 2 (Low) - explicit references to nonexistent register rows pass | Fixed. The `#route-id` anchor on `provenance/PROVIDER_TERMS.md` is now resolved against the register text: the anchor must name a row that exists (route IDs are read from the first backticked cell of the register's table rows and matched exactly, case included), so `#missing-fixture-route`, `#PI-STEPFUN` against the row `pi-stepfun`, and a bare trailing `#` are errors. The register itself without an anchor stays accepted, and reading the register is part of resolution, so the row check is skipped under `--no-file-checks` like every other existence check. This distinguishes file resolution from route resolution; it is not a terms verification and claims no legal adequacy - provider eligibility and terms verification remain open tasks. |
| 3 (Low) - the smoke log confirms Jolt after reporting its settings check failed | Out of scope: `tools/smoke/**` is owned elsewhere. Not addressed here; reported to the coordinator instead. |

Tests added for the two in-scope findings: real and missing route
directories, malformed nesting (no route directory, no file, deeper
nesting), unknown and wrongly-cased register fragments, snapshot fragments,
a route path that is a file, a symlinked route directory, valid routes
against the real register and real snapshot layout, and CLI end-to-end runs
(valid route exits 0, invented route exits 1).

## Disposition of the M0 checkpoint recheck (Sol, 2026-11-27)

Recorded from
`review/implementation/m0-checkpoint-sol-recheck-49dd9c5.md` (candidate
`49dd9c5b2b5f321be9550e2336c6495d04395208`). Only finding 3 is in scope for
this tool; findings 1, 2, 4 and 5 concern `.github/workflows/**` and
`tools/ci/**`, which are owned elsewhere and are not addressed here. The
previous register-row resolution (`bd94d17`) and the path/symlink hardening
(`b28d5bf`) are preserved untouched.

| Finding | Disposition |
| --- | --- |
| 3 (Medium) - fragment validation still reads a rejected register path | Fixed. `_check_terms_register_reference` now uses the verdict of the reference check instead of discarding it: `_check_reference_resolves` returns whether the reference resolved, and the register is read only when it did. The register reference is additionally required to be *readable* (`require_readable=True`), because an unreadable register resolves no row. The read itself goes through the new `_read_record_text`, which re-validates spelling, every path component and the open descriptor and opens with `O_NOFOLLOW | O_NONBLOCK`, so a rejected path - unreadable, symlinked (leaf or parent), outside the root, missing, or a non-file such as a directory, FIFO or device node - is refused before anything is opened. The read and the check remain two steps, so this is not race-free resolution and is not claimed as such; the descriptor check and `O_NOFOLLOW` only narrow the window, and the two time-of-check/time-of-use tests say so. |

Tests added: an instrumented read spy (the module's read path plus
`os.open`, `builtins.open`, `Path.read_text`, `Path.read_bytes`) that requires
zero open attempts for each rejected register shape, a FIFO that must not hang
the validator (the previous code blocked on it), a directory, a missing, an
unreadable and a non-UTF-8 register, both time-of-check/time-of-use swaps
(symlink and FIFO), and the positive controls that an accepted `#route-id` is
still read exactly once and that an anchor-free register reference is not read
at all. `RegisterReadGuardTestCase` tests the guard directly, including the
spellings that would leave the root.

One pre-existing test defect was repaired in passing: the real-register test
named `#pi-mistral` as an unregistered route, but `provenance/PROVIDER_TERMS.md`
gained that row in a later provenance commit (outside this tool's ownership),
so the test asserted nothing. It now derives a fragment that is provably
absent from the rows the register records, which keeps it meaningful as rows
are added.

## Disposition of the 6cc0058 manifest rechecks (Sol and Opus, 2026-11-27)

Recorded from
`review/implementation/m0-manifest-sol-recheck-6cc0058.md` and
`review/implementation/m0-manifest-opus-5-5-6cc0058-independent.md`
(candidate `6cc0058af4680f8ac04409974888c8b12e053e01`). The prior rejected-path
read fix is preserved untouched. Only the in-scope low findings are addressed
here.

| Finding | Disposition |
| --- | --- |
| Sol 1 / Opus F2 - `--check-hashes` raises or hangs on an unreadable or special output file | Fixed. `PathChecker.digest` now goes through the same guarded open as `_read_record_text`: spelling, symlinked components, file type and read permission are re-checked before the open, then `_open_regular_file_descriptor` opens no-follow and non-blocking and requires `S_ISREG` from `fstat`. Any refusal or read error yields `None`, which the caller reports as the existing structured `missing-file` finding ("cannot hash ... unreadable"); no `OSError` escapes. Where `O_NOFOLLOW`/`O_NONBLOCK` are unavailable the primitive fails closed rather than opening without them. |
| Sol 2 - an oversized JSON integer raises `ValueError` out of the decoder | Fixed. `_decode_manifest_document` catches `ValueError` alongside `JSONDecodeError` and reports the existing `invalid-json` finding, so the CLI keeps its exit-2 contract with JSON output and empty stderr. |
| Opus F1 - the descriptor-level defenses have no test | Fixed. New controls swap a FIFO and a symlink in at the pre-check/open boundary of both the register reader and the digest path, and assert refusal with a bounded deadline; direct unit tests cover `_open_regular_file_descriptor` itself. |

New controls: an unreadable mode-000 regular output under a non-root user
(skipped as root), an oversized integer literal (skipped where the interpreter
has no digit limit), FIFO and symlink swaps at the final open boundary for both
readers, a fail-closed control with the fd flags unavailable, passing regular
files for both readers, and CLI end-to-end runs (`--json`) asserting the
structured result and empty stderr. Against the pre-fix module the new suite
reports 2 failures and 9 errors; against the fixed module all 149 tests pass.

Residual limits (unchanged and documented): parent components are resolved by
name after the checks, so a parent swapped for a symlink in that window is
still followed - this narrows the window, it is not race-free resolution, and
no `dir_fd` walk is implemented.
