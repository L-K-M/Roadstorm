# M0 CI scoped recheck (Opus), candidate 245ee1d

- **Job:** d3a096f3-6be6-4704-a64b-04b595fcfb18
- **Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), provider Anthropic, run through Claude Code (Claude Agent SDK).
- **Date:** 2026-11-27
- **Candidate:** `245ee1d4a8ae281a526916090f369d913f24b8cf` ("Fix hosted validation and cross-platform exports")
- **Base:** `deaf052`
- **Snapshot:** `work/agents/d3a096f3-…/snap`. It is an exported tree with no `.git`.
- **Hosted evidence:** `work/agents/d3a096f3-…/hosted.log`, from GitHub Actions run 45924755902 on this exact SHA. All jobs passed.
- **Scope:** fixes for my historical report `review/implementation/m0-ci-opus-recheck-78dd9016-….md` (C1–C3, M1, M2, N1, N2, W3); the CI workflow; the warning and error classifiers; the export path and macOS code signing; evidence upload; preservation of installed templates.

**The M0/CI gate remains open.** Nothing in this report closes M0 or any part of it.

## Independence and isolation

- I did not open the current Sol report or any other reviewer's report for this candidate.
- I spawned no agents or helpers.
- I made no Git changes. In fact the sandbox refused every Git command, read-only ones included.
- I made no edits to source or assets, and I did not touch installed tools or templates.
- I opened no GUI and read no secrets.
- My only write is this report. I attempted one scratch directory (`work/agents/d3a096f3-…/scratch/`), but the sandbox refused that command, so no scratch files exist.

## Capability limits (read before the findings)

1. **No script execution.** The sandbox refused `sh tools/ci/tests/run_tests.sh`, and with it every project script, and it also refused inline `awk` probes. I re-ran **none** of the worker's local results (170/170 self-test under sh/dash, 6/6 runtime gate), and I make no claim about them.
2. **No engine.** No Godot binary was used here. Statements about engine behaviour come from the hosted log, which is output from the pinned 4.7.2 Linux editor, or are marked as inferences.
3. **No Git.** `git diff deaf052 245ee1d` was refused, so I reviewed the candidate as a tree, not as a diff.
4. **No artifacts.** I did not download the run's artifacts (`export-logs`, `export-packages`, `ci-logs`). Claims about their contents rest on the upload step's output in the log and on the code.
5. **No macOS launch.** Whether the built-in ad-hoc–signed macOS package launches on Apple Silicon is **not verified** here, and I found no recorded re-launch since the signing mode changed.

## Files inspected

- `.github/workflows/ci.yml` (whole file)
- `export_presets.cfg`, lines 1–125: the header, the macOS preset and the signing-mode comment
- `tools/ci/ci.sh`:
  - the out-path setup (lines 255–279)
  - `ci_tooling_selfcheck` (lines 902–944)
  - `cmd_install_templates` (lines 578–685)
  - `ci_print_export_failure_log` and `ci_export_build` (lines 1740–1860)
- `tools/ci/lib/common.sh`:
  - `ci_run_godot`, the log classifiers and `ci_is_jolt_physics_warning` (lines 103–352)
  - `ci_copy_project` and `ci_prepare_copy` (lines 613–680)
  - `ci_tracked_output_paths` and `ci_abs_path` (lines 1134–1187)
- `tools/ci/scripts/warning_watch.sh` and `tools/ci/warnings.allow` (whole files)
- `tools/ci/tests/run_tests.sh`: the Jolt cases (around line 700), the tracked-output Git cases (709–767), the `ci_abs_path` cases (769–814) and the codesign case (1426–1442)
- `tools/export_smoke/` (listing only), plus a grep for `pack_inventory` across `tools/ci` and `.github`
- `hosted.log` (1,000+ lines), read through targeted greps for results, log file names, warnings and uploads
- My historical report `m0-ci-opus-recheck-78dd9016-….md`

## Commands and results

| # | Command | Result |
| --- | --- | --- |
| 1 | `ls -la` the job directory and `snap/` | Snapshot present, no `.git`. `task.md` and `hosted.log` (169 KB) present. |
| 2 | `git -C <repo> diff --stat deaf052 245ee1d…` | **Refused by the sandbox** |
| 3 | `sh snap/tools/ci/tests/run_tests.sh` (plain, then with isolated `TMPDIR`) | **Refused by the sandbox** |
| 4 | Inline `awk` probe of the `ci_abs_path` program | **Refused by the sandbox** |
| 5 | `grep codesign/codesign\|ad-hoc export_presets.cfg` | `codesign/codesign=1` at line 108. The comment at lines 99–107 explains the enum. |
| 6 | `grep ls-files\|tools/ci/out ci.sh`, then reading `ci_tracked_output_paths` | Excludes exactly `<out>/.gitignore`. Git-backed self-test cases exist. |
| 7 | `grep -i jolt common.sh warning_watch.sh warnings.allow` | Classifier matches the five message shapes. Allow-list has a `jolt_inventory` entry. |
| 8 | Hosted log grep for results, warnings and uploads | Details in the next section |
| 9 | Hosted log grep for `tools/ci/out/logs/*.log` names | In the export job, `export-1-import.log` and `export-2-export.log` are reused by all three preset builds (F1). |
| 10 | `grep -rn pack_inventory\|export_smoke tools/ci .github` | No hits. CI never runs the pack inventory (F3). |

## Hosted run 45924755902: what it shows

- **Checks job** (`import, validate, test`):
  - Doctor, Import, Validate and Test each report PASS. The runtime-error gate reports 6/6 (log line 991), and the warning watch PASS (line 999).
  - The self-check prints `no tracked build output under tools/ci/out (its own .gitignore sentinel is the intended exception)` (line 910).
  - The only engine warning is the `jolt_inventory` nested-project line. It is labelled `[accepted]` (line 998), and the watch passes.
  - The hosted self-test reports **144/144**, not 170. It skips ffmpeg, the export `--check` end-to-end cases, actionlint and the sidecar `.pck` case (lines 912–916).
- **Export-preparation job:**
  - Editor and templates were downloaded, digest-verified, installed and re-verified (lines 281–375). `export --check` passed (line 402).
  - **All three presets exported** to absolute paths under `build/` (lines 440–473):
    - macOS zip: 60,464,269 bytes, no sidecar
    - Windows exe: 109,128,192 bytes, plus an 8,660-byte `.pck`
    - Linux binary: 73,519,416 bytes, plus an 8,660-byte `.pck`
  - `export-logs` uploaded 498 files (101.7 MB, lines 488 and 510). `export-packages` uploaded 5 files (128 MB, lines 524 and 549).

## Disposition of the historical findings (78dd9016)

| Item | Status at 245ee1d | Basis |
| --- | --- | --- |
| C1 tracked `tools/ci/out/.gitignore` fails validate | **Fixed and hosted-verified.** `ci_tracked_output_paths` exempts only the exact sentinel. Self-test cases in a throwaway `git init` cover the sentinel exemption, a forced build log and a non-sentinel dotfile. | Code, plus hosted line 910 |
| C2 substring `jolt` classifier; allow-list missing `jolt_inventory` | **Fixed and hosted-verified.** Both the classifier (`common.sh:260-267`) and `warning_watch.sh` match only the five engine message shapes. The allow-list has an anchored `jolt_inventory` entry. A self-test case covers a non-physics line that mentions Jolt. | Code, plus hosted lines 997–999 |
| C3 macOS `codesign/codesign=3` (Xcode) | **Fixed and hosted-verified for export.** Set to `1`, built-in ad-hoc, and a self-test case pins it. Whether the package launches on a Mac with this signature is **not verified** (limit 5). | Code, plus hosted line 443 |
| M1 relative `--out` resolved against the scratch copy | **Fixed and hosted-verified.** `ci_export_build` makes `_out` absolute against `$PWD` before calling the engine. The hosted engine command lines show absolute `build/…` paths, and the uploaded packages are non-empty. Self-test cases cover `ci_abs_path`. | Code, plus hosted lines 440–473 and 524 |
| M2 export failures not diagnosable | **Fixed.** `ci_print_export_failure_log` prints the whole log on non-zero exit, on engine errors and on missing output. The export job uploads `tools/ci/out/` under `if: always()`. The upload has a new defect of its own: see F1 and F2. | Code, plus hosted lines 476–510 |
| N1 hosted self-test weaker than local | **Still open:** 144 hosted versus 170 local. actionlint and every engine-backed export case are still skipped on the runner CI uses. Partly offset because the export job now exercises a real export on hosted. | Hosted lines 912–916 |
| N2 stale nested-project comments | **Mostly fixed** in `warnings.allow` and the classifier comments. `common.sh:177-179` still cites only `tick_probe`, which is harmless. | Code |
| W3 "surfaced, not fatal" before a watch failure | **No longer contradictory in practice:** the nested-project line is now accepted, and the message says so. | Hosted line 438 onward |

## Findings at 245ee1d, ranked

### Medium

**F1. The export job overwrites engine logs from one preset to the next, so the `export-logs` artifact keeps only the last preset's import and export logs.**

- **Evidence:** the hosted log names the same files for all three builds. `tools/ci/out/logs/export-1-import.log` and `export-2-export.log` appear for macOS (lines 436 and 442), Windows (451 and 457) and Linux (466 and 472).
- **Cause:**
  - Each `ci.sh export --export` call is a fresh process. In it `CI_LOG_SEQ` starts at 0 (`common.sh:72`), and `CI_RUN_NAME` is the command name (`ci.sh:278`).
  - `ci_run_godot` (`common.sh:116-117`) therefore writes `export-<seq>-<label>.log` with the same names on every call, and the next preset truncates them.
- **Effect:**
  - The macOS and Windows export logs, including the macOS signing and packaging output that M0 depends on, are not in the uploaded evidence.
  - The workflow comment at `ci.yml:361-366` ("this upload preserves it") is therefore true only for the last preset.
  - On a failure the loop stops at the failing preset, and `ci.sh` prints that log in full, so failure diagnosis still works. The loss affects only the evidence for presets that succeeded.
- **Fix:**
  - Make the log names unique for each invocation, for example by adding the preset slug or a per-invocation id to `CI_RUN_NAME` in `ci_export_build`.
  - Alternatively, have the workflow loop set a distinct `--out` scratch directory per preset.
  - Add a self-test that runs two invocations and asserts that both logs survive.

**F2. Each preset's scratch copy contains the packages already built for earlier presets, and the `export-logs` artifact uploads them again.**

- **Cause:**
  - The workflow writes packages to `build/` inside the checkout (`ci.yml:338,356`).
  - `ci_copy_project` (`common.sh:634`) excludes only `.git`, `.godot`, `work` and the out directory. `build/` is copied.
  - `ci_prepare_copy` rebuilds the copy on every invocation, so the Windows copy holds the macOS zip, and the Linux copy holds both the zip and the Windows exe and `.pck`.
  - The job then uploads all of `tools/ci/out/` (`ci.yml:372`), which includes `project-copy/`.
- **Evidence:**
  - `export-logs` is 498 files and 101.7 MB (log lines 488 and 510), whereas the checks job's `ci-logs`, with the same kind of copy, is 2.5 MB (line 1055).
  - That `build/` causes the difference is an **inference**: I did not open the artifact (limit 4).
- **Impact:**
  - No package contamination was observed: both `.pck` files are 8,660 bytes, and the exclude filter does not pack non-resource files.
  - Still, each preset's input tree now depends on the order in which presets were built. The "logs and reports" artifact roughly doubles the stored package bytes, and it buries the logs among about 500 copied project files.
- **Fix:**
  - Build into `$RUNNER_TEMP/build`, or exclude `./build` in `ci_copy_project`.
  - Upload only `tools/ci/out/logs` and `tools/ci/out/reports` from the export job.

### Minor

**F3. Packages built by CI are not checked by the pack inventory. E4 is still not verified on hosted CI.**

- `export_presets.cfg:51-53` says `pack_inventory.py` "re-reads the res:// tree inside every produced .pck and FAILS the run" if an excluded path reappears.
- Only `tools/export_smoke/` runs it. `tools/ci` and `.github` never reference it (command 10).
- The packages that CI uploads as `export-packages` are therefore not inventory-checked.
- **Fix:** run `pack_inventory.py check` on each sidecar `.pck` in the build step. Alternatively, qualify the comment so it says the check applies to the local export smoke only.

**F4. The hosted self-test is still weaker than the local one (N1, carried over).**

- 144 hosted versus the reported 170 local. The hosted run skips actionlint and the engine-backed export, sidecar and ffmpeg cases.
- The local 170/170 is not evidence about the hosted workflow.
- **Fix:** install actionlint pinned by digest in the checks job, and point the self-test at the editor already downloaded there.

### Nits

- **Stale workflow comment.** `ci.yml:136-143` still says a warning "that names the physics backend fails the job", and that warnings "that do not name Jolt are reported". The policy is now the five message shapes, so a line that names Jolt without being one of them is reported, not fatal.
- **Likely misattributed run id.** `ci.sh:1784-1786` attributes "exit 0 followed by 'export produced no output' for all three presets" to hosted run 45921573623. In that run the macOS build failed on the configuration error, and Windows and Linux were never attempted (my 78dd9016 report, C3). The comment probably refers to a later, intermediate run.
- **The tracked-output check fails open.** `ci_tracked_output_paths` discards Git's stderr (`common.sh:1150`). If `git ls-files` errors, for example on a "dubious ownership" refusal on a persistent self-hosted runner, the check prints nothing and passes.
- **Latent loss of logs from the warning watch.** `ci_prune_logs` keeps the newest 20 logs, and every `ci.sh` call prunes. The checks job writes about 12 logs today. Once it exceeds 20, the warning watch, which runs last, would silently miss the oldest logs.
- **The build loop stops at the first failing preset.** `set -e`/`pipefail` in the loop means one failure still hides the presets after it. It was optional in the earlier report and is unchanged.

### Checked and found sound

- **Template installation preserves installed trees.** `cmd_install_templates` verifies the digest before extracting. It validates `version.txt` and the presets on a staged tree, then refuses if `<dest>/<ver>.stable` exists, either as a path or as a symlink, before the single `mv` (`ci.sh:666-679`). An existing install is never deleted or overwritten.
  - Two minor caveats. `mkdir -p "$_dest"` runs before validation. And a failed cross-device `mv` could leave a partial tree that later runs refuse. Neither destroys existing data.
- **The error classifier is unchanged and anchored** (`common.sh:171`). The runtime-error gate passes 6/6 on hosted.
- **The warning watch matches the classifier.** It uses `ci_warning_is_accepted` and `ci_is_jolt_physics_warning` from `common.sh`, so the workflow and `ci.sh` judge warnings with the same code.

## Verdict

**Changes required. They are not blocking for the CI jobs, which are green.**

- All three blockers from 78dd9016 (C1, C2, C3) and both medium findings (M1, M2) are fixed. Hosted run 45924755902 on this exact SHA verifies each one, at the level the log can show.
- The candidate leaves a concrete defect in the evidence upload, which is in this review's scope:
  - **F1:** the macOS and Windows export logs are overwritten.
  - **F2:** the scratch copies carry earlier packages, and the logs artifact uploads them again.
- Both are cheap to fix and should be fixed before hosted export evidence is relied on for M0. F3 and F4 are coverage gaps to record.
- **Not verified here:**
  - the worker's local 170/170 and 6/6 (no script execution);
  - the macOS package launching with built-in ad-hoc signing;
  - the contents of the uploaded artifacts.

The M0/CI gate remains open.
