# M0 five-job checkpoint recheck (Opus)

- Reviewer: Claude Opus 5.5. Provider `venice`, model `claude-opus-5-5` (from `PI_PROVIDER`/`PI_MODEL`), run through pi. Job `929c4082-0280-464e-830a-00dd35c164e1`.
- Date: 2026-11-26. Checks ran from about 22:16 to 22:20 UTC.
- Candidate: `bdeb8e24619ba7f833613301df43ffa09b0ce36d`. Commits since the base: `f763ae1`, `ae8a134`, `7733fb1`, `f4cee18`, `bdeb8e2`.
- Base (previously reviewed SHA): `6b571835837dff8e9a25d1696f5622ecf9fa451b`.
- Prior report: `review/implementation/m0-five-jobs-opus-0bbb2f75-c3eb-47f5-9d89-771bce087012.md`.
- Scope: recheck of my earlier findings 1–14 in four areas (smoke, manifest, Jolt and toolchain), plus new probes in those areas. This is not an M0 acceptance review.

## Independence and isolation

- I did not open or consult any Sol review or recheck. An untracked `review/implementation/m0-five-jobs-sol-recheck-bdeb8e2.md` exists in the live checkout, and I did not read it.
- I spawned no agents, did not mutate Git, did not edit source or assets, and accessed no secrets.
- Apart from this report, all writes went under `work/agents/929c4082-…/`.
- The snapshot was made with `git archive bdeb8e2… | tar -x -C work/agents/929c4082-…/snap`. It is a plain tree with no `.git` and no `.godot`.
- Every command except one used `HOME=<job>/home`, `TMPDIR=<job>/tmp`, `PYTHONPYCACHEPREFIX=<job>/pycache`, `PYTHONDONTWRITEBYTECODE=1` and `NO_COLOR=1`.
  - **Exception:** for `tools/toolchain/verify.sh --deep`, I set `HOME` to the real user home so it could find the installed export templates. That run only read them; `--deep` extracts `macos.zip` into `TMPDIR`, which was the job directory.
- Fault-injection copies were made under `<job>/fi/` and deleted after use. The logs and probe scripts remain in `<job>/out/`.
- Tools used: Godot `4.7.2.stable.official.ed1daf0bf` (`/opt/homebrew/bin/godot`) and Python 3.15.2.

## Files inspected

I read the full `git diff 6b57183..bdeb8e2` for the following files and inspected them in the snapshot:

- `project.godot`
- `tools/smoke/{boot_smoke.gd,run_boot_smoke.sh,fault_injection.sh,README.md}`
- `tools/toolchain/{verify.sh,README.md,pin/engine.txt}`
- `docs/TOOLCHAIN.md`
- `docs/STATUS.md`
- `tools/asset_manifest/{manifest_validator.py,run_tests.sh,README.md,tests/test_manifest_validator.py}`
- `tools/tick_probe/{README.md,project.godot,src/*.gd,compare_modes.py}`
- `provenance/MANIFEST_CONTRACT.md`
- `tools/python_pin/{README.md,verify.sh}`, for a smoke run only

## Commands and results (all in the snapshot)

| # | Command | Result |
| --- | --- | --- |
| 1 | `tools/smoke/run_boot_smoke.sh` | PASS, exit 0 |
| 2 | `tools/smoke/run_boot_smoke.sh --expect-failure` | exit 1 |
| 3 | `tools/smoke/fault_injection.sh` | 6/6 cases as expected, isolation verified, exit 0 |
| 4 | Independent fault injection, direct `godot … boot_smoke.gd` vs wrapper (my own injections, not the harness's) | see the table below |
| 5 | Wrapper with `GODOT_BIN` set to a fake binary that prints `4.7.2.stable.custom_build.deadbeef` | exit 1, "engine is not the pinned build" |
| 6 | Probe script: `physics/3d/physics_engine`, its hint, Jolt settings and `JoltPhysicsServer3D` class | setting is `Jolt Physics`; hint is `DEFAULT,Jolt Physics,GodotPhysics3D,Dummy`; 32 `physics/jolt*` settings exist, none set in `project.godot`; the class exists |
| 7 | Copy with the setting misspelt (`"Jolt Phyiscs"`), then the wrapper | **PASS, exit 0**, with no engine error |
| 8 | Copy with the `3d/physics_engine` line removed, then the wrapper | **PASS, exit 0** |
| 9 | Tick probe in structural mode under `--fixed-fps 60`, default pacing and `--max-fps 60` | each run 58/58 checks, exit 0 |
| 10 | Tick probe `mode=throughput requests=2 inject_failure=1` | exit 1 |
| 11 | `tools/tick_probe/compare_modes.py` | COMPARISON PASS; 600 ticks in both modes; identical final z of −99.999641418; 62.2× speedup in accelerated mode |
| 12 | Tick probe with its own `project.godot` switched to `GodotPhysics3D` | exit 1, `FAIL pinned 3D physics backend is Jolt Physics`; the stop positions also differ (−0.599852 vs −0.599701) |
| 13 | `verify.sh --deep` (real `HOME`, read-only) | PASS, exit 0 |
| 14 | `verify.sh --quiet` with an empty `HOME` (no templates) | **FAIL, exit 1** |
| 15 | `verify.sh --quiet --no-templates` with an empty `HOME` | PASS, exit 0 |
| 16 | `verify.sh --deep --no-templates` | exit 2 |
| 17 | `verify.sh --quiet --templates <empty dir>` | exit 1 |
| 18 | `verify.sh` with a `PATH` that has no `shasum`/`sha256sum` | exit 2, "no sha256 utility found" |
| 19 | `tools/asset_manifest/run_tests.sh` | 76 tests OK, exit 0 |
| 20 | `run_tests.sh test_cli` (the pattern form) | 6 tests OK, exit 0 |
| 21 | `validate_manifest.py assets/manifest.json --check-hashes` | PASS, exit 0 |
| 22 | `out/probe2.py`: 26 validator boundary probes, plus CLI exit codes | 21 behave as expected; 5 do not (see findings R1, R2 and R5) |
| 23 | `out/probe3.py`: CLI end to end with a symlinked directory | **PASS, exit 0**; the validator hashed `/etc/hosts` through the link |
| 24 | `tools/python_pin/verify.sh` | PASS, exit 0 (local interpreter only, out of my original scope) |

### Independent smoke repros (command 4)

| Injection (separate scratch copy each) | Direct `boot_smoke.gd` | Wrapper |
| --- | --- | --- |
| Parse error appended to `game.gd` (`func broken(:`) | 1 | 1 |
| Null deref in `main_menu.gd::_ready`; this is my original repro | 1 | 1 |
| Missing dictionary key in `boot.gd::_ready` | **0** | 1 |
| `push_warning` in `boot.gd::_ready` (negative control) | 0 | 0 |
| `push_error` in `game.gd::_ready` | 0 | 1 |

A direct run still misses runtime errors in scripts that have no ready marker, such as `boot.gd` and `game.gd`. The README documents this limit and names the wrapper as the supported entry point, so I accept it.

## Disposition of my prior findings

| # | Prior finding | Status at `bdeb8e2` | Evidence |
| --- | --- | --- | --- |
| 1 | Rights gate bypassable by omission | **Fixed for omission and null; residual issue in R2** | Probes: `service_generated` without terms → FAIL; `null` → FAIL; `external_cc0` without upstream → FAIL; upstream `null` → FAIL. But `service_terms_ref: "not_applicable"` or any arbitrary string passes. |
| 2 | Approved or released entry with unknown reviewer/revision | **Fixed** | Unknown reviewer/revision → FAIL; missing `approval_revision` → FAIL; unknown `technical_check` → FAIL; pending with `release_inclusion: true` → FAIL; pending and not shipped → PASS. The positive fixture now uses concrete values. |
| 3 | Smoke passes on parse and runtime errors | **Fixed (through the wrapper)** | Commands 3 and 4. A direct run still misses some runtime errors; this is documented. |
| 4 | No Technical group or identity schema/revision | **Fixed (recorded, not validated)** | Both are now accepted. Contents are unvalidated, as disclosed. |
| 5 | Jolt not selected | **Partly fixed; residual issue in R3** | `project.godot:32` sets `3d/physics_engine="Jolt Physics"`, and the value reads back at runtime. The main smoke check does not assert it (commands 7 and 8), and Jolt's own settings are not pinned. |
| 6 | Toolchain documents contradict verification status | **Fixed** | `docs/TOOLCHAIN.md:3`, `pin/engine.txt` and the `verify.sh` header and summary now consistently say "selected files only" and describe the download method. One stale sentence remains (R6). |
| 7 | `verify.sh` passes with no templates or no sha tool | **Fixed** | Commands 14–18. |
| 8 | References to files absent at the SHA | **Partly fixed; residual issue in R4** | `provenance/*` and `licenses/README.md` are now committed. `schemas/common.schema.json` and `tools/ci/{ci.sh,lib/common.sh,pin/engine.txt}` are **still missing** at this SHA; they are only untracked in the live tree. |
| 9 | Exit-code contract | **Fixed** | A bad root, unreadable file, invalid JSON or missing file each exits 2. |
| 10 | `run_tests.sh <pattern>` broken | **Fixed** | Command 20. |
| 11 | First-party creative `Unlicense` | **Fixed** | `disallowed-license`. |
| 12 | Boundary cases | **Mostly fixed; one bypass remains (R1)** | Duplicate output paths, duplicate JSON members, `seed: true`, a symlinked leaf file and absolute or `../` hash keys are all rejected now. A symlinked **intermediate directory** still escapes the root. |
| 13 | Smoke ignores build and commit | **Fixed** | Status, build and commit hash are checked in-engine, and the wrapper compares the exact `--version` string (command 5). |
| 14 | `.gitignore` coverage | **Open, not addressed** | Deferred as an M0.2 item; `.gitignore` is unchanged at this SHA. |

## Ranked findings at `bdeb8e2`

### Major

**R1. A symlinked directory in a manifest path escapes the root, including under `--check-hashes`. Finding 12 is incomplete.**

- **Cause:** `PathChecker.check` and `PathChecker.digest` (`tools/asset_manifest/manifest_validator.py:437` and `:470`) call `is_symlink()` on the final path component only.
- **Repro:** create `assets/generated/fixture/etcdir -> /etc` and list the output path `assets/generated/fixture/etcdir/hosts`, with the SHA-256 of `/etc/hosts` as its hash. The CLI then prints `PASS (0 error(s))` and exits 0 (probe3). The validator read and vouched for a file outside the checkout.
- **Conflict with the claim:** the README disposition row 12 says "symlinked references are rejected".
- **Fix:** reject the reference if any component under the root is a symlink, or require `target.resolve()` to be relative to `root.resolve()`. Add a regression test for a symlinked parent directory.

### Medium

**R2. `service_generated` entries accept a placeholder or unresolvable `service_terms_ref`. This is a residual of finding 1.**

- `"not_applicable"`, which is the sentinel first-party entries use, passes for `service_generated`.
- An arbitrary string such as `"x"` also passes.
- So the rights gate still lets a service-generated asset ship without a real terms reference.
- **Fix:** reject `not_applicable` for `service_generated`. Require the reference to resolve to an entry in `provenance/PROVIDER_TERMS.md`, or at least to an existing repo path.

**R3. Nothing in the main project's checks guards the Jolt pin. This is a residual of finding 5.**

- If the main `project.godot` setting is misspelt or deleted, `run_boot_smoke.sh` still passes, and the engine reports no error (commands 7 and 8).
- The tick-probe evidence states that pre-pin `DEFAULT` matched GodotPhysics3D bit for bit. A silent revert would therefore change handling physics, and no check would fail.
- The tick probe asserts the setting only in its **own** `tools/tick_probe/project.godot`, which is a separate copy that can drift. It also differs from the main project in other settings, for example `rendering_method_setting=forward_plus`.
- Jolt's 32 `physics/jolt_physics_3d/*` settings are left at engine defaults and are not recorded. TECHNICAL_DESIGN and PLAN M0.1 ask for "Jolt and its settings".
- **Fix:** add `physics/3d/physics_engine == "Jolt Physics"` to `boot_smoke.gd::_check_settings`. Record or pin the Jolt settings that matter for handling.

**R4. Referenced files are still missing at this SHA, and the disposition text is stale. This is a residual of finding 8.**

- **Missing:** `schemas/common.schema.json` (cited by `manifest_validator.py:76,80` and `README.md:193`) and `tools/ci/**` (cited by `tools/toolchain/verify.sh:152`, `tools/toolchain/README.md:30,51-54`, `tools/asset_manifest/README.md:74,214`, `run_tests.sh:19` and `validate_manifest.py:15`).
- **Stale text:** `tools/asset_manifest/README.md:238` says `provenance/` and `licenses/` are uncommitted, which is no longer true, and judges the references "accurate against the working tree". That does not hold for a frozen candidate.
- **Fix:** commit these files with the candidate, or reword the references as pending.

### Minor

- **R5.** An approved, release-included entry still passes with `perceptual_review: "unknown"`, although the contract's Review group lists "visual/audio/model review". Separately, `rights_holder_record` is not resolved: `provenance/NOPE.md` passes, although the contract says rights records "link to OWNER_AUTHORITY.md".
- **R6. Stale documentation.**
  - `docs/TOOLCHAIN.md:67-68` says "the project's own physics settings are M0.2's business and were not modified", but `project.godot` now selects Jolt.
  - `provenance/MANIFEST_CONTRACT.md` says `assets/manifest.json` is "not yet created", but the file exists.
- **R7. Intermittent Jolt warning.** One of three structural tick-probe runs (`--fixed-fps 60`) printed the engine warning `Jolt Physics job system exceeded the maximum number of jobs … Please report this`. The checks still passed. This should be recorded and tracked; it is not hidden by the smoke wrapper, which ignores `WARNING:` lines.
- **R8. Cosmetic.** `fault_injection.sh` prints `expected: fail (exit 0)` for the expected-failure cases, which is misleading. The verdict logic itself is correct.
- **R9.** `.gitignore` coverage (finding 14) remains open.

## Limitations

- All checks were headless with dummy display and audio drivers. I made no windowed, renderer, audio, controller, Windows/Linux or export observation.
- **Backend identity is inferred, not observed.** The engine does not expose the instantiated 3D physics backend. I inferred it from the setting value and from the tick probe's GodotPhysics3D contrast run (command 12).
- I did not download any upstream archive, so the upstream checksum claims rest on the candidate's evidence record.
- I did not review provenance or terms content, rights adequacy, the Python pin beyond one smoke run, the schemas/fixtures or the untracked CI work.
- I ran the tick-probe throughput and fidelity checks once on one machine (Apple M4 Max). There was no repeated statistical run.

## Verdict

**Changes required, much narrower than before.**

- **Fixed and independently reproduced:** findings 2, 3, 6, 7, 9, 10, 11 and 13, plus finding 4 as record-only.
- **Partly fixed:** findings 1, 5, 8 and 12.
- **R1 should be fixed with a regression test before the validator is relied on for asset intake.** It is a real escape in a check the remediation claims to close.
- **Resolve or explicitly disposition R2–R4 before M0 acceptance.**
- **Still open:** M0 itself, the rights and terms gates, hardware/platform/controller/audio evidence and release. Nothing here verifies them.
