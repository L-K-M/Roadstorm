# M0 checkpoint scoped recheck (Opus), candidate 49dd9c5

- Reviewer: Claude Opus 5.5. Provider `venice`, model `claude-opus-5-5` (from `PI_PROVIDER`/`PI_MODEL`), run through pi. Job `4803d848-c82b-4902-97d7-feee789a5b7b`.
- Date: 2026-11-26. Checks ran from about 23:45 to 23:51 UTC.
- Candidate: `49dd9c5b2b5f321be9550e2336c6495d04395208`. Commits since the base: `bd94d17`, `10d9e51`, `7b27c2f`, `49dd9c5`.
- Base: `15faf0d572c1fd917b680a123f431c7086806227`.
- Prior report: `review/implementation/m0-checkpoint-opus-recheck-2963edd5-0b1f-4713-ad3b-64f7f9e4f332.md`. It raised N1 and the residuals R3′, R4′/R6′, R5′, R7′ and R9′.
- Scope:
  - N1, the CI runtime-error gate, checked with my own injected cases;
  - warning visibility;
  - the export-preset and checksum gates;
  - the remaining R3, R4 and R7 evidence at the exact candidate.

  This is not an M0 acceptance review.

## Independence and isolation

- **No Sol reports.** I did not open or consult any Sol report. I extracted the snapshot with `git archive 49dd9c5… | tar -x --exclude='*sol*'`. I first confirmed with `git ls-tree` that only the three committed `*sol*` review files matched that pattern.
- **No agents.** I spawned none.
- **No Git changes.** I ran only read-only Git commands: `rev-parse`, `log`, `diff`, `ls-tree`, `archive` and `status`.
- **No edits outside my report.** I changed no source, asset or tracked file other than this report.
- **No secrets.** I read none.
- **Isolated environment.** Every command used `work/agents/4803d848-…/env.sh`. It points `HOME`, `TMPDIR`, `XDG_*` and `PYTHONPYCACHEPREFIX` into the job directory, and sets `PYTHONDONTWRITEBYTECODE=1` and `NO_COLOR=1`.
- **Export templates.** To build the export packages, I linked the isolated `HOME`'s `export_templates/4.7.2.stable` to the installed template directory and used it read-only.
- **Scratch files.**
  - Fault-injection copies went under `<job>/fi/`. The large scratch (`fi/`, exported packages, the unzipped app) was deleted afterwards.
  - Logs and scripts are kept in `<job>/out/`: `inject.sh`, `warnwatch.sh`, `fi-*.log`, `P_*.log`, `ve*.log`, `export-*.log`, `build-sha256.txt`, `jolt-inv/` and `tick-*.log`.
- **Tools:** Godot `4.7.2.stable.official.ed1daf0bf` and Python 3.15.2, on an Apple M4 Max running macOS.

## Files inspected

- The full `git diff 15faf0d..49dd9c5` for:
  - `tools/ci/{ci.sh,lib/common.sh,warnings.allow,scripts/runtime_error_gate.sh}`
  - `.github/workflows/ci.yml`
  - `tools/smoke/boot_smoke.gd`
  - `project.godot`
  - `export_presets.cfg`
- `tools/ci/pin/engine.txt` and `tools/toolchain/pin/{engine,checksums}.txt`
- `tools/export_smoke/run_export_smoke.sh` (header only)
- `docs/evidence/jolt-settings.md`
- `tools/jolt_inventory/**`, including its evidence directory
- `docs/STATUS.md` (the relevant lines)
- For R4/R6: `tools/asset_manifest/{manifest_validator.py,README.md}`, `provenance/MANIFEST_CONTRACT.md` and `tools/ci/contracts.list`

## Commands and results (all in the snapshot)

| # | Command | Result |
| --- | --- | --- |
| 1 | `sh tools/ci/tests/run_tests.sh` | 86/86, exit 0 |
| 2 | `sh tools/ci/ci.sh test` on the clean snapshot | PASS, exit 0. The exit-code proof ran: the probe exited 3 and `--expect-failure` exited 1. |
| 3 | `bash tools/ci/scripts/runtime_error_gate.sh` (the committed harness) | 6/6 as expected, exit 0 |
| 4 | My own `out/inject.sh` cases, run through `ci.sh test` (table below) | 7 cases behaved as a correct gate should; 1 is a documented coverage limit |
| 5 | The workflow's Warning-watch step body, extracted verbatim and run on the case H, I and G trees | exit 1 on the Jolt warning; exit 0 on a plain warning and on the clean tree. Every warning line was written to the summary file. |
| 6 | `ci.sh export --check` with the isolated `HOME` and no templates | exit 1. Templates are missing for all three targets; preset coverage is OK for macOS, `Windows Desktop` and Linux. |
| 7 | `GODOT_TEMPLATES_DIR=<installed> ci.sh export --check` | PASS, exit 0 |
| 8 | Preset probes: Windows `platform="Windows"`, Linux preset deleted, `platform="linux"` | Each exits 1 with `preset platform missing: …` |
| 9 | A template directory holding only the `*_x86_32` Windows and Linux templates | **PASS, exit 0** (finding E2) |
| 10 | `ci.sh export --export <preset>` for each preset, the workflow's loop replayed, with `GODOT_TEMPLATES_DIR` only | All 3 exit 1: Godot reports `No export template found at the expected path` under its own data directory (finding E1) |
| 11 | The same, with templates under the isolated Godot data directory | All 3 exit 0; sizes in the table below |
| 12 | `codesign -dv`, `lipo -archs` and a headless launch (`--headless --quit-after 300`) of the exported macOS app | Ad hoc signature, no team ID, `x86_64 arm64`. Exit 0; boot reached the menu; no process was left running. |
| 13 | `ci.sh verify-engine` with a random archive, a random binary, a missing file, the Linux template as the "editor", and a blank `release_archive_sha512` | Each exits 1; the blank pin refuses with `no pinned digest recorded` |
| 14 | `verify-engine` and `pin --field` with no Godot on `PATH` (as on a fresh runner) | Both work. `pin --field` prints only the value on stdout. |
| 15 | `sh tools/toolchain/verify.sh --deep` | PASS. The editor, `version.txt` and the macOS, Windows and Linux templates match the recorded digests, and so does the macOS template release binary. |
| 16 | `tools/jolt_inventory/run_inventory.sh --project <snapshot> --out-dir <job>/out/jolt-inv` | PASS. 32 settings; the classification matches the committed evidence, ignoring path text. |
| 17 | Tick probe, structural mode with `--fixed-fps 60`, 8 runs on a copy of `tools/tick_probe` | Each run exit 0 with 58/58 checks; 0 `WARNING` lines and 0 Jolt job-system lines |
| 18 | `ci.sh all`, `run_boot_smoke.sh`, `fault_injection.sh`, `asset_manifest/run_tests.sh`, `validate_manifest.py --check-hashes`, and a YAML parse of the workflow | All exit 0. `ci.sh all` warns only about the accepted import warning and about absent content paths. |

Export sizes for command 11:

| Package | Size |
| --- | --- |
| macOS ZIP | 59,184,265 bytes |
| Windows `.exe` | 109,128,192 bytes |
| Linux binary | 73,519,416 bytes |

Each `.pck` was 27,604 bytes. The SHA-256 digests are in `out/build-sha256.txt`.

### Independent N1 injections (command 4)

Each case ran `ci.sh test` on a fresh copy of the snapshot.

| Case | Injection, inserted at the top of `_ready` | `ci.sh test` exit | Notes |
| --- | --- | --- | --- |
| A | `boot.gd`: a real `Dictionary` with a missing key (`var _d := {}; print(_d["missing_key"])`) | **1** | `reason=engine-errors`; `SCRIPT ERROR: Invalid access … 'missing_key' on … 'Dictionary'` |
| B | `main_menu.gd`: `push_error(...)` | **1** | `ERROR: opus injected menu error` |
| C | `game.gd`: a 0 s timer whose callback calls `push_error` | **1** | The deferred error is caught |
| D | `game.gd`: `load("res://does/not/exist.tres")` | **1** | 2 `ERROR` lines |
| E | `boot.gd`: `await process_frame`, then `push_error` | **1** | |
| F | `game.gd`: a 5 s timer whose callback calls `push_error` | 0 | The smoke quits before the timer fires. This is a coverage limit, not a gate defect. |
| G | No defect, run with `--strict-warnings` | 0 | The only warning (the nested tick-probe `project.godot`) is labelled as accepted |
| H | `main_menu.gd`: `push_warning("Jolt Physics job system exceeded …")` | **1** | `reason=jolt-warning`, in the default (non-strict) mode |
| I | `main_menu.gd`: `push_warning("opus plain warning")` | 0 | Printed with the log line, counted in the report as `warnings=1 unexpected_warnings=1`, and not fatal (as documented) |

## Disposition

| Item | Status at `49dd9c5` | Evidence |
| --- | --- | --- |
| **N1** CI passed runtime script errors | **Fixed. Independently verified.** | `ci_run_one_test` now fails a check that exits 0 but whose log has `ERROR`, `SCRIPT ERROR`, `FATAL`, `USER ERROR`, `Failed to load script` or `Parse Error` lines. My cases A–E, in three different scripts and with deferred and awaited errors, all fail `ci.sh test`, and the clean tree passes. The committed harness (6/6) also runs as its own workflow step. |
| **R7′** warning visibility | **Fixed.** | Every `WARNING:` line is printed with its log line number and counted in the per-check and stage reports. `warnings.allow` records accepted shapes without hiding them. A Jolt-named warning fails both `ci.sh test` and the workflow's Warning-watch step. `--strict-warnings` fails on unaccepted warnings. |
| **R7** the intermittent Jolt job-system warning | **Still open; not reproduced.** | 8 more runs here plus the 15 recorded by job 52ab36a7 showed no recurrence. No cause has been found. `docs/evidence/jolt-settings.md` and `STATUS.md` record it honestly as open. CI does not run the tick probe that produced the warning (see L2). |
| **R3/R3′** Jolt backend and settings | **Backend guarded; settings recorded.** | My inventory rerun matches the committed evidence: all 32 `physics/jolt_physics_3d/*` settings are engine defaults; the explicit overrides are `physics_engine` and `physics_interpolation`. The project's `[physics]` section is unchanged since that input revision, and `49dd9c5` adds only a `rendering` key. No settings are pinned, and no handling decision rests on them (stated). One minor mislabel: see M4. |
| **R4/R4′** references missing at the SHA | **Unchanged and minor.** | `schemas/` is still absent at the SHA. `manifest_validator.py:77,81` still cite `schemas/common.schema.json` without saying it is pending; the README now says "pending integration". |
| **R6′** stale wording | **Unchanged and minor.** | `MANIFEST_CONTRACT.md` says `assets/manifest.json` is "not yet created". `contracts.list` still lists `licenses/`, `provenance/` and `assets/` as `pending`. |
| Export-preset platform gate | **Fixed.** | Windows maps to `platform="Windows Desktop"`. A wrong platform, a missing preset or a lowercase platform each fails (command 8). The workflow's build loop uses the same value. All three presets export with the pinned templates. The macOS package is universal and ad hoc signed, and boots headless to the menu. |
| Engine checksum gate (CI download path) | **Works as designed.** | The publisher's SHA-512 is checked before extraction, the binary's SHA-256 before execution, and a blank pin refuses (command 13). It works without Godot on `PATH`, and `pin --field` output is clean for `$(…)` (command 14). The toolchain `--deep` digests match (command 15). |

## Findings at `49dd9c5`

### Medium

**E1. The hosted `export-preparation` job cannot pass as committed, and the template gate does not match what Godot uses.**

- **What happens.** Since `export_presets.cfg` is now committed, `hashFiles('export_presets.cfg') != ''` is true, so the job runs on `ubuntu-latest`. The workflow installs no export templates and verifies none. `ci.sh export --check` will therefore fail on "templates: … none of" for all three targets: command 6 reproduces this with a clean `HOME`.
- **The obvious fix also fails.** `ci_templates_dir` honours `GODOT_TEMPLATES_DIR`, but the engine ignores it: command 10 passes `--check` and then fails all three exports with Godot's own `No export template found at the expected path` under the engine data directory. Pointing `GODOT_TEMPLATES_DIR` at templates would turn a red check green while the build still fails.
- **No template checksum in CI.** On that path, CI never checks the templates against a digest. The `.tpz` digest and the per-file template digests exist only in `tools/toolchain` (command 15).
- **Fix:**
  - Add a workflow step that downloads `templates_url` and verifies it against the publisher's SHA-512 before extraction, as `verify-engine` does for the editor.
  - Install the templates into Godot's own data directory: `~/.local/share/godot/export_templates/4.7.2.stable` on Linux.
  - Make `export --check` look where the engine looks, or have it warn that `GODOT_TEMPLATES_DIR` is not read by Godot.
  - Optionally run `tools/toolchain/verify.sh` against the installed templates.
  - Until that is done, do not cite the hosted export job as M0.5 evidence.

### Minor

- **E2. The template presence check accepts the wrong architecture.**
  - For Windows and Linux, `export --check` passes if *either* the `x86_64` or the `x86_32` template exists. Both presets are `x86_64`.
  - A directory with only the 32-bit templates passes (command 9), and the export would then fail.
  - **Fix:** require the template for each preset's `binary_format/architecture`.
- **E3. The export result hashes only the main file.**
  - `ci.sh export --export` reports the size and SHA-256 of the main output only. The Windows and Linux presets write a separate `.pck` (`embed_pck` defaults to false), which is neither checked to be non-empty nor hashed.
  - For Linux, the reported "package" digest equals the pinned stock template digest (`d9f79ab8…`), so it identifies no game content.
  - **Fix:** check and report the sidecar `.pck`, or embed it.
- **E4. Packages include development tooling.**
  - With `export_filter="all_resources"` and an empty exclude filter, the packages contain `tools/ci/scripts/*.gd` (including `environment_report.gd`), `tools/smoke/boot_smoke.gd` and `assets/manifest.json`.
  - This is harmless for an M0 shell smoke, but release presets (M9) should exclude `tools/*`.
- **W1. The Warning-watch step has no `if: always()`.** When the Test step fails because of a Jolt warning, the watch step and its summary are skipped. The lines are still printed in the Test step's log, so nothing is hidden, but the summary is missing exactly when it matters.
- **W2. The Warning-watch step and `ci.sh` disagree on accepted warnings.**
  - The watch step fails on any line containing "jolt", even one accepted in `warnings.allow`; `ci.sh` honours the allow list.
  - The watch step is stricter, so this is safe. A future accepted Jolt warning would need both places changed.
- **W3. A misleading summary line.** After a Jolt warning has already failed the check (case H), the stage summary still says "surfaced, not fatal (use --strict-warnings …)". This is cosmetic.
- **M4. The inventory mislabels one explicit setting.**
  - `tools/jolt_inventory/evidence/…/classification.txt` labels `physics/common/physics_ticks_per_second = 60` as "engine default: not set by …/project.godot". The project sets it explicitly; `jolt-settings.md` gets this right.
  - The classifier compares values, not presence.
  - The evidence also cites the live-tree path rather than a frozen snapshot. Its recorded input revision is `bd94d17`; the physics section is unchanged at `49dd9c5`.
- **Still open from earlier reviews:** R4′, R5′, R6′ and R9′.

## Limits

- **L1. Short smoke window.** The CI error gate sees only what the discovered checks print before they quit. An error raised after the smoke's few frames passes (case F). This is inherent, and it should be stated wherever CI is cited as runtime evidence.
- **L2. The R7 path is not in CI.** CI discovers only `tests/**` and `tools/smoke/**`. The boot smoke does not run a physics world under load, and the tick probe that produced R7 is a nested project that CI does not run. The Jolt warning gate therefore watches a run that is unlikely to trigger R7. The gate itself was proven only with an injected `push_warning`; I did not produce a genuine engine Jolt warning.
- **Local checks only.** No GitHub-hosted run was observed. The Linux download path, `unzip` and `find` were reasoned about, not executed; the Linux editor archive was not downloaded.
- **Launch coverage.** Windows and Linux packages were built but not launched. The macOS app was launched headless only: no window, renderer, audio or controller.
- **Backend identity** is still inferred from the setting value, not observed at runtime.
- **Not reviewed:** the content of rights, terms and provenance; schemas and fixtures (uncommitted at the SHA); `tools/export_smoke/**` beyond its header. I did not run `run_export_smoke.sh`, because inside the snapshot its `git archive HEAD` would resolve to the enclosing live repository rather than the candidate.
- Uncommitted live-tree changes are outside the candidate and were not reviewed.

## Verdict

**N1: pass.** CI now fails on runtime engine errors like the smoke wrapper, independently reproduced with 5 new error injections. Warning visibility (R7′) and the export-preset platform mapping also pass. The engine checksum gate works.

**Overall for this scoped recheck: changes required (narrow).**

- **E1:** the hosted export-preparation job cannot pass. It installs and verifies no templates, and `GODOT_TEMPLATES_DIR` lets the check pass where the engine still fails. Fix this before CI export preparation is cited.
- **E2–E4, W1–W3 and M4:** minor.
- **R7** is still open and undiagnosed; it is not reproduced in 8 more runs here and is honestly recorded.
- **R3:** the settings are recorded but not pinned, which is acceptable as evidence only.
- **R4 and R6:** the wording residuals are unchanged.
- **Still open:** M0 itself, the game, AI, the rights and terms gates, hardware/platform/controller/audio evidence (Windows and Linux launches included), signing and notarization, and release. Nothing here verifies them.
