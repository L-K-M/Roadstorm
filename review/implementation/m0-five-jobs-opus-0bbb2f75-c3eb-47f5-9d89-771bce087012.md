# M0 five-job checkpoint review — Opus

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), provider `venice`, run through pi. Job `0bbb2f75-c3eb-47f5-9d89-771bce087012`.
- Date: 2026-11-26
- Candidate SHA: `6b571835837dff8e9a25d1696f5622ecf9fa451b` (commits `ee0ec19`, `d544c1c`, `6b57183`)
- Base SHA: `0ea596a4fa85ade19375e130313f020ed6010619`
- Checkpoint type: an early partial M0 batch, not an M0 acceptance review.
- Independence: I did not open or consult the other reviewer's report. I spawned no agents, did not mutate Git and did not edit source or assets. Apart from this report, I wrote only under `work/agents/0bbb2f75-…/`.

## Scope and files inspected

All 28 files changed between the base and the candidate (`git diff --stat`): `.gitignore`, `project.godot`, `scenes/{boot,game,main_menu}.tscn`, `src/boot/*.gd` and their `.uid` files, `tools/smoke/{boot_smoke.gd,README.md}`, `tools/toolchain/{README.md,verify.sh,pin/engine.txt,pin/checksums.txt}`, `tools/asset_manifest/{manifest_validator.py,validate_manifest.py,run_tests.sh,README.md,tests/*}`, `assets/manifest.json`, `docs/STATUS.md`, `docs/TOOLCHAIN.md` and `docs/evidence/godot-4.7.2-archive-verification.md`.

I checked them against the candidate's `PLAN.md` (M0.1–M0.9), `plan/IMPLEMENTATION.md`, `docs/TECHNICAL_DESIGN.md`, `docs/ASSET_PRODUCTION.md` (manifest contract and release rights gate) and `docs/BENCHMARKS.md`.

## Commands and outcomes

I ran every check on a plain snapshot made with `git archive 6b57183… | tar -x -C work/agents/0bbb2f75-…/snap`. The snapshot was not a clone or worktree and started without a `.godot/` directory. Each Godot run used `HOME=work/agents/0bbb2f75-…/home`, and Python used `PYTHONPYCACHEPREFIX`/`PYTHONDONTWRITEBYTECODE`. Logs are in `work/agents/0bbb2f75-…/out/`.

| Command (in the snapshot) | Outcome |
| --- | --- |
| `tools/asset_manifest/run_tests.sh` (Python 3.15.2) | 35 tests, OK, exit 0 |
| `python3 tools/asset_manifest/validate_manifest.py assets/manifest.json --check-hashes` | PASS, exit 0 |
| `tools/asset_manifest/run_tests.sh test_cli` (the documented `<pattern>` form) | **exit 1**: `ImportError: Start directory is not importable: 'test_cli'` |
| `out/probe.py`: boundary-case probes against the validator, built on the suite's own fixture | see findings 1, 2, 4, 9 and 12; log in `out/probe.log` |
| `godot --headless --path . --script res://tools/smoke/boot_smoke.gd` (4.7.2.stable.official.ed1daf0bf, clean snapshot, no import) | PASS, exit 0 |
| same, with `-- --expect-failure` | FAIL, exit 1 (as intended) |
| Smoke test on a scratch copy with a GDScript **parse error** injected into `src/boot/game.gd` | **PASS, exit 0**, although the log shows `SCRIPT ERROR: Parse Error` and `Failed to load script` |
| Smoke test on a scratch copy with a **runtime null dereference** injected into `main_menu.gd::_ready` | **PASS, exit 0**, although the log shows `SCRIPT ERROR: Cannot call method 'queue_free' on a null value` |
| Probe script printing `physics/3d/physics_engine` | `DEFAULT` (the project does not select Jolt explicitly) |
| `NO_COLOR=1 TMPDIR=<job>/tmp tools/toolchain/verify.sh --deep` | PASS, exit 0; the installed editor, the three target templates and the macOS template release binary match the recorded digests |
| `verify.sh --quiet` with `HOME` pointing at an empty directory, so no template directory exists | **PASS, exit 0**, with only a warning |
| `verify.sh --quiet --templates <empty dir>` | FAIL, exit 1 |

I deleted the scratch fault-injection copies after use.

## Evidence and capability limits

- **Upstream checksums.** I did not download the official ZIP, TPZ or `SHA512-SUMS.txt`, so I did not independently reproduce the upstream archive comparison. I verified only that the installed files match the digests recorded in the candidate.
- **Headless only.** The runs used the dummy display and audio drivers. I made no windowed, renderer, audio, controller, target-OS (Windows/Linux) or export observation.
- **Physics backend.** I could not determine which backend `DEFAULT` resolves to at runtime, because the `PhysicsServer3D` singleton class is opaque from GDScript.
- **Absent dependencies.** The provenance and licensing files (`provenance/`, `licenses/`), schemas (`schemas/`) and CI files (`tools/ci/`) that the changed files reference are not in this SHA, so I could not review them.
- **Open gates.** No game, controller, audio, platform, rights, M0 or release gate is claimed or verified here.

## Findings, ranked

### Major (implementation defects)

1. **The rights gate can be bypassed by omitting fields, contrary to the README and contract.** In `tools/asset_manifest/manifest_validator.py:1011` the service-terms check only runs `if "service_terms_ref" in rights`. In `:1027` the upstream check only runs when `upstream` is present and non-null. In `:1235` the per-input license/evidence checks only apply to listed inputs, and `upstream_inputs: []` is accepted. The probes showed:
   - a `service_generated` entry with **no** `service_terms_ref` passes;
   - an `external_cc0` entry with no `rights.upstream` and empty `upstream_inputs` passes;
   - an `external_cc0` entry with `upstream: null` passes.

   `tools/asset_manifest/README.md:94` states that these entries "must reference provider terms" and "must record upstream URL/date/evidence". `docs/ASSET_PRODUCTION.md` §Release rights gate requires blocking unknown origins.

   The tests (`tests/test_manifest_validator.py:333-367`) only cover fields that are present but unknown. **Fix:** make `service_terms_ref` required for `service_generated`, and `rights.upstream` (url/date/evidence) plus at least one upstream input with license and evidence required for `external_cc0`. Add tests for omission and `null`.

2. **An "approved, release-included" entry with an unknown reviewer and unknown approval revision passes, and the positive control locks that in.** The fixture used by `test_complete_entry_passes` sets `reviewer`, `approval_revision`, `technical_check` and `perceptual_review` all to `"unknown"` with `release_inclusion: true` (`tests/test_manifest_validator.py:89-94`). `_validate_review` (`manifest_validator.py:1062`, `:1120`) accepts `unknown` and does not require `approval_revision` at all.

   The contract's Review group requires a reviewer and an approval revision. The release gate blocks "unapproved outputs", and BENCHMARKS requires actual capable-reviewer records. **Fix:** when `status == "approved"` or `release_inclusion` is true, require a known `reviewer` and `approval_revision`, and a non-unknown `technical_check`. Make the positive control use real-looking values, and add a negative test.

3. **The headless smoke test passes despite GDScript parse errors and runtime script errors.** Fault injection proved both cases (see the commands table). This contradicts `tools/smoke/boot_smoke.gd:9` and `tools/smoke/README.md:34` ("instantiate without script errors"). `README.md:41-43` partly concedes the limit but implies that errors surface as a timeout, which they do not when the handoff still completes.

   PLAN M0.4 needs checks whose failures produce failing exit codes, and the T01 "boots without script errors" intent is not met. **Fix (one or more):**
   - assert that each scene root has its expected script attached and loadable (`get_script() != null`, `script.can_instantiate()`), and check a ready marker set by each script's `_ready`;
   - or run the smoke check through a wrapper that fails on `SCRIPT ERROR`/`ERROR:` lines in engine output;
   - add a fault-injection fixture test.

### Medium (plan mismatches and incorrect claims)

4. **The manifest schema cannot record the contract's Technical group or identity schema/revision.** `ENTRY_OPTIONAL_KEYS = ("display_name",)` (`manifest_validator.py:118`) leaves no `technical` field, and the probe showed an entry with `technical: {...}` fails with `unknown-field`. `docs/ASSET_PRODUCTION.md` (manifest contract table) requires Technical data (dimensions, triangle counts, LODs, duration, sample rate, loops, model dimensions) and Identity "schema/revision". `README.md:122-125` claims technical metadata "is recorded by entries". **Fix:** add these fields, even if their contents stay unvalidated, before any producer writes entries.

5. **Jolt is not selected in the project, but the documentation says it is pinned.** `project.godot:25-28` has no `physics/3d/physics_engine` setting, and the runtime value is `DEFAULT`. `docs/TOOLCHAIN.md:3-5` says the "built-in Jolt backend [is] pinned", while `:72-73` defers the project setting to M0.2. PLAN M0.1 and TECHNICAL_DESIGN require pinning Jolt and its settings, where a backend change counts as a handling revision. **Fix:** set `physics/3d/physics_engine="Jolt Physics"` explicitly, and assert it in the smoke test.

6. **The toolchain documents contradict their own verification status.**
   - `docs/TOOLCHAIN.md:3-8` says the digests "have **not** been confirmed against the official release assets", but `:95-97` and `pin/engine.txt:39` (`upstream_verified=yes`) say selected files were.
   - `pin/engine.txt:28-30` ("HEAD requests only, no content was downloaded") and `:36-38` ("local sha256 vs the publisher's SHA512-SUMS") misdescribe the method recorded in `docs/evidence/godot-4.7.2-archive-verification.md`.
   - The `verify.sh:18-19` header disclaims upstream verification, while its summary prints "upstream verification yes".

   **Fix:** reconcile the text so that it matches the evidence record and its stated scope (editor binary and three templates only).

7. **`verify.sh` passes when export templates are entirely absent.** `tools/toolchain/verify.sh:227-229` only warns when no template directory exists, and the run exits 0. Line 212 also returns success when no SHA-256 tool is found. The pin covers the templates (M0.1), so a missing install should not report PASS. **Fix:** fail by default, or require an explicit `--no-templates` flag.

8. **Changed files point to files that do not exist at this SHA.** `assets/manifest.json:6,13`, `tools/asset_manifest/README.md:10,40,46-48,131,134,138,145` and `manifest_validator.py:8,63,67,70,73,87,971,1023,1261` cite `provenance/MANIFEST_CONTRACT.md`, `provenance/OPEN_ITEMS.md`, `provenance/PROVIDER_TERMS.md`, `schemas/common.schema.json` and `licenses/README.md`. `tools/toolchain/README.md:29,45-46`, `verify.sh:132`, `run_tests.sh:14` and `validate_manifest.py:15` cite `tools/ci/…`. None of these files exist in the candidate. The validator claims to be the "executable form" of a contract that is not in the tree. **Fix:** integrate the referenced files before relying on them, or reference the authoritative `docs/ASSET_PRODUCTION.md` contract until they land.

9. **The exit-code contract is violated.** The README documents `2` for "manifest could not be read" (`tools/asset_manifest/README.md:75`), but an unreadable manifest (permission denied) and a nonexistent `--root` both exit **1**. They are reported as validation findings (`manifest_validator.py:461`, `:471`), and only a missing file returns 2 (`:1321`). **Fix:** map `bad-root`, `unreadable-manifest` and `invalid-json` to exit 2, or correct the documentation.

### Minor (fix or record a disposition)

10. **The documented `<pattern>` form of `run_tests.sh` is broken.** The script appends the argument to `unittest discover` as a positional start directory (`run_tests.sh:11`, `:46`). Use `-k`/`-p` handling instead.

11. **First-party creative assets may be marked `Unlicense`.** `FIRST_PARTY_LICENSES` includes `Unlicense` (`manifest_validator.py:91`), but the manifest covers only creative assets and model artifacts. `docs/ASSET_PRODUCTION.md:18` requires CC0 for creative outputs and weights/datasets.

12. **Further boundary cases pass that should not** (from the probes):
    - two entries can claim the same output path;
    - duplicate JSON keys are silently resolved last-wins (`json.loads` at `:477`; use `object_pairs_hook` to reject them);
    - `seed: true` is accepted (`:900`, because `bool` is a subclass of `int`);
    - a symlink under the root pointing outside it passes existence and hash checks (`PathChecker.check` at `:372`, `digest` at `:422`);
    - with malformed `output_paths`, `--check-hashes` hashes unchecked absolute keys such as `/etc/hosts` (`:822`).

13. **The smoke version check ignores the build and commit.** `boot_smoke.gd:81-88` compares only major, minor and patch, so a non-official or custom 4.7.2 build passes. `verify.sh` covers this separately; note the split or check `version["status"]`/`hash` too.

14. **`.gitignore` covers only `/work/`, `.godot/` and Python caches.** M0.2 and TECHNICAL_DESIGN §layout also ask for ignore rules for local credentials, build/export outputs, temporary captures and save data. This is an open M0.2 item, not a regression.

### Claims checked and found accurate

- The placeholder scenes and scripts honestly disclaim gameplay, and their scope matches the M0.2 shell.
- The boot → menu → game handoff works headlessly on 4.7.2, and `--expect-failure` exits 1.
- `assets/manifest.json` is an honest empty registry, and the 35 tests pass.
- The installed toolchain matches the recorded digests.
- `docs/STATUS.md` does not claim that any milestone or gate is complete.

## Verdict

**Changes required** for this partial batch. Findings 1–3 are implementation defects in exactly the checks this batch introduces: the rights/review gate and the failing-check guarantee. They should be fixed with regression tests before these tools are relied on for M0.4/M0.3 or for any asset intake. Findings 4–9 should be resolved or explicitly dispositioned before M0 acceptance. Upstream archive verification and all platform, audio, controller and rights evidence remain **not verified** by this review.
