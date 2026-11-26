# M0 checkpoint recheck (Opus)

- Reviewer: Claude Opus 5.5. Provider `venice`, model `claude-opus-5-5` (from `PI_PROVIDER`/`PI_MODEL`), run through pi. Job `2963edd5-0b1f-4713-ad3b-64f7f9e4f332`.
- Date: 2026-11-26. Checks ran from about 22:38 to 22:40 UTC.
- Candidate: `15faf0d572c1fd917b680a123f431c7086806227`. Commits since the base: `935b9e2`, `6e5b0d1`, `b28d5bf`, `15faf0d`.
- Base: `bdeb8e24619ba7f833613301df43ffa09b0ce36d`.
- Prior report: `review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md`, which raised findings R1–R9.
- Scope: verify R1–R9 at the candidate, and probe the newly committed CI wiring where it touches those findings. This is not an M0 acceptance review.

## Independence and isolation

- I did not open or consult any Sol review. The candidate commits `review/implementation/m0-five-jobs-sol-recheck-bdeb8e2.md`, and the live tree has an untracked `m0-checkpoint-sol-recheck-15faf0d.md`. I read neither file. `ci.sh all` copied the committed Sol file into its scratch project copy; I deleted that copy without opening it.
- I spawned no agents, did not mutate Git, edited no game, source or asset file, and accessed no secrets. The Git commands I ran were read-only: `rev-parse`, `log`, `diff`, `ls-tree`, `show`, `status` and `check-ignore --no-index`.
- I extracted the snapshot with `git archive 15faf0d… | tar -x -C work/agents/2963edd5-…/snapshot`. It has no `.git` and no `.godot`.
- Every command ran with these variables pointing into the job directory: `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and `PYTHONPYCACHEPREFIX`. `PYTHONDONTWRITEBYTECODE=1` and `NO_COLOR=1` were also set.
- Because the isolated `HOME` has no export templates, `ci.sh` warned about missing templates. I did not rerun `tools/toolchain/verify.sh --deep` against the real home.
- Fault-injection copies went under `<job>/fi/` and were deleted after each run. Logs and probe scripts are kept in `<job>/out/`.
- Tools: Godot `4.7.2.stable.official.ed1daf0bf` and Python 3.15.2, on an Apple M4 Max.

## Files inspected

- The full `git diff bdeb8e2..15faf0d` for:
  - `tools/smoke/{boot_smoke.gd,fault_injection.sh,README.md}`
  - `tools/asset_manifest/{manifest_validator.py,README.md}`
  - `.gitignore`
  - `docs/{TOOLCHAIN.md,STATUS.md}`
- In the snapshot:
  - `tools/asset_manifest/tests/test_manifest_validator.py` (fixture helpers)
  - `tools/ci/{ci.sh` (test discovery, runner and exit-code proof), `lib/common.sh` (error-line helpers), `contracts.list}`
  - `.github/workflows/ci.yml`
  - `provenance/MANIFEST_CONTRACT.md` (line 50)
  - the `provenance/` and `docs/evidence/` listings
  - `tools/tick_probe/README.md`
- The presence of `schemas/` and `docs/evidence/` at the SHA, confirmed with `git ls-tree`.

## Commands and results (in the snapshot)

| # | Command | Result |
| --- | --- | --- |
| 1 | `tools/asset_manifest/run_tests.sh` | 99 tests OK, exit 0 |
| 2 | `validate_manifest.py assets/manifest.json --check-hashes` | PASS, exit 0 (the registry is empty) |
| 3 | `tools/smoke/run_boot_smoke.sh` | PASS, exit 0; no `WARNING` lines |
| 4 | `run_boot_smoke.sh --expect-failure` | exit 1 |
| 5 | `tools/smoke/fault_injection.sh` | 8/8 cases as expected, isolation verified, exit 0 |
| 6 | My own copies with `3d/physics_engine` set to `"DEFAULT"`, set to `"GodotPhysics3D"`, or removed (my own `grep -v`, not the harness's injector) | Each exits 1 with `FAIL: physics/3d/physics_engine is '<value>', expected 'Jolt Physics'`. The removed setting reads back as `'DEFAULT'`. |
| 7 | `out/probe_r.py`: 43 independent validator probes, including one CLI run | 43/43 as expected (list below) |
| 8 | `sh tools/ci/tests/run_tests.sh` | 53/53, exit 0 |
| 9 | `sh tools/ci/ci.sh all` | PASS, exit 0. Warnings: export templates absent (isolated `HOME`); `tests/`, `schemas/`, `fixtures/`, `content/`, `models/` and `training/` absent; `export_presets.cfg` absent |
| 10 | Copy with a missing-dictionary-key runtime error at the top of `boot.gd::_ready`, then `ci.sh test` | **PASS, exit 0**. The log shows `[ci:warn] 1 engine error line(s) … (informational)` (finding N1) |
| 11 | The same copy through `run_boot_smoke.sh` | exit 1, `SCRIPT ERROR: Invalid access to … 'missing_key'` |
| 12 | Tick probe in structural mode with `--fixed-fps 60`, six runs on a copy of `tools/tick_probe` | each run exit 0 with 58/58 checks; 0 `WARNING` lines and 0 Jolt job-system warnings |
| 13 | `git check-ignore --no-index` against the committed `.gitignore` | See R9 |

### Validator probes (command 7)

These probes extend the test suite's own fixtures.

- **Service terms reference:**
  - Accepted, as they should be: the register, the register with `#pi-longcat`, and a snapshot file under `provenance/provider_terms/pi-longcat/`.
  - Rejected, as they should be: `not_applicable`, `N/A`, ` none `, `TBD` and `unknown`, each as `unknown-legal-origin`.
  - Also rejected:
    - `x`, `provenance/NOPE.md`, `provenance/OWNER_AUTHORITY.md` (outside the register) and a missing snapshot file, each as `unresolved-reference`;
    - a snapshot directory with no file;
    - `..`, `/etc/hosts`, `#pi-longcat` and `""`;
    - a terms snapshot reached through a symlinked directory or a symlinked leaf.
- **Rights holder record:**
  - Rejected: `provenance/NOPE.md`, `README.md`, `provenance/` (a directory), and `provenance/` itself replaced by a symlink to `/etc`.
  - Accepted, as they should be: `provenance/OWNER_AUTHORITY.md#owner`.
  - Also accepted: `provenance/PROVIDER_TERMS.md` (see R5′).
- **Perceptual review:**
  - On an approved, shipped entry, `unknown`, `UNKNOWN`, a missing value, `null` and `""` are all rejected.
  - A pending entry with `unknown` passes, as intended.
  - A pending entry with `release_inclusion: true` is rejected.
- **Symlink escape (R1):** each of these fails with `symlinked-path`:
  - an output reached through a symlinked parent directory, with or without `--check-hashes`;
  - `assets/generated` itself replaced by a symlink;
  - a symlinked parent on a source path;
  - a symlinked parent on a recipe path;
  - an in-root alias directory.

  My original R1 repro, run through the CLI with `--check-hashes`, now exits 1 instead of 0. A `..` path and a wrong hash still fail.

## Disposition of R1–R9

| # | Finding at `bdeb8e2` | Status at `15faf0d` | Evidence |
| --- | --- | --- | --- |
| R1 | A symlinked parent directory escapes the root | **Fixed** | `_symlinked_component` tests every component below the root, both in `check` and in `digest`. Probes, plus the CLI repro now exiting 1. The README states that TOCTOU (time-of-check/time-of-use) races are only simulated. |
| R2 | Placeholder or unresolvable `service_terms_ref` | **Fixed (as a reference check)** | Placeholders are rejected, and the reference must resolve to the register or to a file under `provider_terms/`. The `#route-id` anchor is **not** resolved against a register row, so `PROVIDER_TERMS.md#anything` passes. This is documented. Reference existence is not an assessment of the terms, as `docs/STATUS.md` says. |
| R3 | Nothing guards the main project's Jolt pin | **Fixed for the backend name; settings still open** | `boot_smoke.gd::_check_settings` asserts `"Jolt Physics"`. Fault-injection cases 7 and 8 and my own repros (command 6) fail on it. CI's `test` stage runs `boot_smoke.gd`, so CI also catches a reverted backend. The 32 `physics/jolt_physics_3d/*` settings are still neither recorded nor pinned. `docs/evidence/jolt-settings.md` does not exist, and `docs/STATUS.md` says honestly that "Jolt default/settings evidence remains open". |
| R4 | Referenced files missing at the SHA | **Mostly fixed** | `tools/ci/**`, `.github/workflows/ci.yml` and `docs/evidence/*` are committed and the references resolve. `schemas/common.schema.json` is still absent; it is staged in the live tree but not committed. The README labels it "pending integration", but `manifest_validator.py:77,81` still say "reused verbatim from schemas/common.schema.json" without that qualifier (minor). |
| R5 | `perceptual_review: unknown` ships; `rights_holder_record` unresolved | **Fixed, with residual R5′** | See the probes above. |
| R6 | Stale documentation | **Partly fixed** | `docs/TOOLCHAIN.md` is fixed. `provenance/MANIFEST_CONTRACT.md:50` still says `assets/manifest.json` is "not yet created". `tools/ci/contracts.list` still lists `provenance/`, `licenses/` and `assets/` as `pending` although all three are committed. |
| R7 | Intermittent Jolt job-system warning | **Not reproduced; not resolved** | Six more structural runs (command 12) and every smoke and CI run printed no `WARNING`. The single earlier occurrence is recorded as open in `docs/STATUS.md`, and its cause is uninvestigated. The smoke wrapper and `ci.sh` still do not fail on `WARNING:` lines, so a recurrence would not be caught. Recording it as open is an honest disposition. |
| R8 | `fault_injection.sh` prints a misleading expected exit | **Fixed** | The output now reads `expected: fail / observed exit: 1 -> yes`. |
| R9 | `.gitignore` coverage | **Fixed for the stated scope** | Ignored: `/.env`, `/.env.*` (with `.env.example` kept), `/build/`, `/dist/`, `/captures/tmp/`, `/saves/`, `.godot/`, `/work/` and `tools/ci/out/`. Not ignored: nested `.env` files such as `sub/.env`, and key or keystore patterns such as `*.pem`, `*.p12` and `*.keystore`. Godot's `export_credentials.cfg` is covered by `.godot/`. This is a minor residual. |

## Ranked actionable findings at `15faf0d`

### Medium

**N1. Committed CI does not apply the smoke fix from finding 3: runtime script errors pass `ci.sh test` and therefore the GitHub workflow.**

- **Cause:**
  - `ci_run_one_test` (`tools/ci/ci.sh` around lines 790–835) runs every discovered `tools/smoke/*.gd` directly with `--script` and judges only the exit code.
  - Engine `ERROR:`/`SCRIPT ERROR:` lines are reported as `[ci:warn] … (informational)`.
  - `tools/smoke/README.md` names `run_boot_smoke.sh` as the supported entry point because a direct run misses these errors, but CI does not call that wrapper.
  - `.github/workflows/ci.yml` runs `ci.sh … test`.
- **Repro (commands 10 and 11):** a missing-key error in `boot.gd::_ready` gives `ci.sh test` exit 0 and the wrapper exit 1. By the same mechanism, `push_error` in `game.gd`, which a direct run already missed at `bdeb8e2`, would also pass CI.
- **Why it matters:** CI is the gate that will be cited as M0.4 evidence. As committed, it is weaker than the local smoke check that review finding 3 required.
- **Fix:** either
  - make `ci.sh test` fail on engine error lines for smoke and test scripts, keeping a documented allow-list if needed; or
  - run `tools/smoke/run_boot_smoke.sh` (and optionally `fault_injection.sh`) from `ci.sh`.

  Add a self-test case to `tools/ci/tests` that injects a runtime error.

### Minor

- **R5′. Reference checks are existence checks only.**
  - `rights_holder_record` accepts any file under `provenance/`, for example `provenance/PROVIDER_TERMS.md` or `MANIFEST_CONTRACT.md`, not only `OWNER_AUTHORITY.md` or a contributor record.
  - `service_terms_ref` anchors are not resolved against a register row.
  - `docs/STATUS.md` and the README disclose both limits.
  - **Fix:** tighten when real entries are added.
- **R3′. Jolt settings inventory is still missing.** Record the effective values of `physics/jolt_physics_3d/*` that handling relies on, or pin them, as the plan's "Jolt and its settings" requires. Optionally have the smoke check assert the ones handling depends on. This is already tracked as open.
- **R7′. A warning would not be caught.** Neither the smoke wrapper nor `ci.sh` fails on, or even surfaces, a Jolt `WARNING:` line. If R7 recurs in CI it would go unnoticed. Consider counting `WARNING:` lines into the report.
- **R4′/R6′. Stale wording.**
  - `manifest_validator.py:77,81` cite the uncommitted `schemas/common.schema.json` without saying it is pending.
  - `provenance/MANIFEST_CONTRACT.md:50` says "not yet created".
  - `tools/ci/contracts.list` classifies `provenance/`, `licenses/` and `assets/` as pending.
- **CI coverage gaps.** The workflow runs `validate_manifest.py` without `--check-hashes`; that is harmless while the manifest is empty. It does not run `tools/asset_manifest/run_tests.sh` or `tools/smoke/fault_injection.sh`.
- **The fault harness does not prove its failure reasons.** For cases 7 and 8, `fault_injection.sh` checks only exit 1, not that the `physics_engine` assertion fired; its README says the failure "can only come from" that assertion. My direct repros (command 6) show that it does today. Asserting the message would keep it that way.
- **R9′. `.gitignore` gaps:** nested `.env` files and key or keystore patterns (see the R9 row).

## Limits

- All checks were headless with dummy display and audio drivers. I made no windowed, renderer, audio, controller, Windows/Linux, export or GitHub-hosted CI observation. `ci.sh all` ran locally only.
- Backend identity is still inferred from the setting value and the earlier contrast run. The engine does not expose the instantiated backend.
- I did not rerun `tools/toolchain/verify.sh` or download any engine or Python archive, so the checksum evidence rests on the committed records.
- I did not review the content of provenance or terms, rights adequacy, schemas or fixtures (mostly uncommitted), or the CI capture and export paths beyond `ci.sh all`.
- The R7 warning was not reproduced in six runs, so its absence is not proven.
- Uncommitted live-tree changes (`docs/STATUS.md`, `tools/smoke/boot_smoke.gd`, `schemas/`, `fixtures/`) are outside this candidate and were not reviewed.

## Verdict

**Changes required, narrow.**

- **Fixed and independently reproduced:** R1, R2 (as a reference check), R5 and R8.
- **Fixed for the stated scope:** R3 (the backend-name guard) and R9.
- **Mostly fixed:** R4 (`schemas/common.schema.json` is still pending) and R6.
- **R7:** recorded honestly as open and not reproduced.
- **Before the committed CI is relied on as smoke evidence, fix N1:** CI must fail on runtime script errors, as the wrapper does. The remaining items are minor, or are open evidence tasks that are already tracked: the Jolt settings inventory, the warning's cause, and the schema commit.
- **Still open:** M0 itself, AI, the rights and terms gates, hardware/platform/controller/audio evidence, and release. Nothing here verifies them.
