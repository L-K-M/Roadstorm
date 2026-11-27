# M0 CI checkpoint recheck (Opus), candidate deaf052

- **Job:** 78dd9016-970c-43de-9f7a-a3cd5450a493
- **Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), provider Anthropic, run through Claude Code (Claude Agent SDK).
- **Date:** 2026-11-27
- **Candidate:** `deaf0522469b57891b9119cd9245b529b6a7fa62` ("Harden CI template setup and warning checks")
- **Base:** `49dd9c5`
- **Snapshot:** `work/agents/78dd9016-…/snap`. It is an exported tree with no `.git`.
- **Hosted evidence:** `work/agents/78dd9016-…/hosted-failed.log`, from GitHub Actions run 45921573623 on this exact SHA.
- **Scope:** fixes for the historical findings in `review/implementation/m0-checkpoint-opus-recheck-4803d848-….md` (E1–E4, W1–W3); the CI workflow; the warning and error policy; archive and template installation; export presets; package and manifest changes.

**M0 remains open.** Nothing in this report verifies M0 or any part of it.

## Independence and isolation

- I did not open the other reviewer's current report.
- I spawned no agents or helpers.
- I made no Git changes. In fact this sandbox refused every Git command, read-only ones included.
- I made no edits to source, assets or installed editors or templates.
- I opened no GUI and read no secrets.
- My only writes are this report and private scratch files under `work/agents/78dd9016-…/scratch/`: two synthetic one-line engine logs and an empty `tmp/`.

## Capability limits (read before the findings)

1. **No script execution.** The sandbox's permission layer refused to run any project script: `sh tools/ci/scripts/warning_watch.sh …`, and therefore `ci.sh`, `run_tests.sh` and the runtime-error gate. I re-ran none of the local results the coordinator quoted (selftest 149/149, gate 6/6, actionlint, toolchain verify), and I make no claim about them.
2. **No engine.** No Godot binary is reachable from this sandbox. The workspace contains none, and `/Applications` is outside the allowed paths. Statements about engine behaviour are therefore either:
   - read from the hosted log, which is engine output from the pinned 4.7.2 Linux editor; or
   - marked as an inference from Godot's documented behaviour.
3. **No Git.** `git ls-tree`/`log`/`rev-parse` were refused, so I did not diff the candidate against `49dd9c5`. Which commit introduced each defect is not established. The findings hold for the candidate as a tree.
4. **No hosted rerun.** I could not trigger or observe a new hosted run.

Every finding below is supported by static reading of the snapshot together with the hosted log. None depends on a local run I could not perform.

## Files inspected

- `.github/workflows/ci.yml` (whole file)
- `export_presets.cfg` (whole file)
- `tools/ci/ci.sh`: CLI dispatch, `ci_tooling_selfcheck` (lines 902–937), `ci_tooling_selftest`, the export check, list and build paths (lines 1571–1810), and the engine-check judging (lines 1136–1236)
- `tools/ci/lib/common.sh`:
  - `ci_run_godot` (lines 103–149)
  - the log classifiers (lines 151–322)
  - `ci_copy_project` and `ci_prepare_copy` (lines 594–650)
- `tools/ci/scripts/warning_watch.sh` and `tools/ci/warnings.allow` (whole files)
- `tools/ci/out/.gitignore` and the root `.gitignore`
- `tools/ci/tests/run_tests.sh`: the end-to-end export case (lines 1600–1649) and the `--out` usages
- `tools/ci/README.md`: references to `tools/ci/out` and to `--out`
- `tools/jolt_inventory/` (directory listing only), and the file list of `tools/**`
- The historical report `m0-checkpoint-opus-recheck-4803d848-…md`: its findings, limits and verdict sections
- `review/baddc856-…md` line 153: the recommendation for macOS ad-hoc signing
- `hosted-failed.log`, all 148 lines

## Commands and results

| # | Command (cwd = snap unless stated) | Result |
| --- | --- | --- |
| 1 | `ls -la` the job directory and `snap/` | Snapshot present. It has no `.git`. |
| 2 | `git … rev-parse/log/ls-tree` | **Refused by the sandbox** (needs approval) |
| 3 | `find tools .github -type f` | `tools/ci/out/.gitignore` is present in the candidate tree. `tools/jolt_inventory/` is a nested project. |
| 4 | `grep -n "must not be committed\|ls-files\|tools/ci/out" tools/ci/ci.sh tools/ci/lib/common.sh` | Self-check at `ci.sh:925-933` |
| 5 | `cat tools/ci/out/.gitignore .gitignore` | `tools/ci/out/.gitignore` contains `*` / `!.gitignore`, so it keeps itself tracked. |
| 6 | Read `warning_watch.sh`, `warnings.allow`, `common.sh:170-322` | Jolt classification is `grep -i 'jolt'` on unaccepted lines. The allow-list covers only `tools/tick_probe`. |
| 7 | `grep -rn -i -e codesign/codesign -e "Xcode codesign" -e codesign=3 -e "ad-hoc only" .` | `export_presets.cfg:99:codesign/codesign=3`. `review/baddc856…:153` recommends "Built-in (ad-hoc only)". |
| 8 | `grep -n "_out=\|abspath\|ci_abs" tools/ci/ci.sh tools/ci/lib/common.sh` | The export `--out` value is never made absolute. |
| 9 | `grep -n "export --export\|--out" tools/ci/tests/run_tests.sh …` | The only end-to-end export case uses an **absolute** `--out "$PKG/linux"`. |
| 10 | `find <workspace> -maxdepth 6 -name 'Godot*' -perm -u+x` | No engine binary available |
| 11 | `sh tools/ci/scripts/warning_watch.sh <scratch synthetic log dir>` | **Refused by the sandbox**. The hosted log (lines 140–148) is the same reproduction on the real engine output. |

## Hosted run 45921573623: what it shows

- **The editor and template archives were downloaded, digest-verified and installed.** Template provisioning passed. This is the first hosted evidence for the historical E1 fix.
- **`import, validate, test`: the Validate step failed** at the tooling self-check (log line 108). Because Validate failed, the Test step and the Runtime-error gate step did not run. The Warning watch step ran under `if: always()` and failed too (lines 140–148).
- **`export preparation`: the `export --check` step passed** (it is not in the excerpt, and the job reached the build step). **The build step then failed on the first preset**, macOS (lines 27–44). Because the loop runs under `set -e`/`pipefail`, the Windows and Linux presets were **never attempted**.
- **The hosted tooling self-test reported 132/132**, not 149/149. It skipped the end-to-end export, sidecar, ffmpeg and actionlint cases (lines 110–114). So the hosted runner lints nothing, and the export cases that would have exercised a real build are skipped exactly where CI runs.

## Findings at `deaf052`, ranked

### Blocking

**C1. `validate` fails on every Git checkout because the output directory's own `.gitignore` is tracked.**

- **Evidence:** hosted log line 108: `[ci:fail] 1 tracked file(s) under tools/ci/out - build output must not be committed`.
- **Cause:**
  - `ci.sh:925-933` counts `git ls-files tools/ci/out` and requires 0.
  - `tools/ci/out/.gitignore` (`*` + `!.gitignore`) is deliberately committed. `tools/ci/README.md:90` describes it as the ignore mechanism, and it is present in the candidate tree.
  - The count is therefore always ≥ 1 in any clone.
- **Why local runs miss it:** the check only runs when `$CI_PROJECT/.git` is a directory. It is skipped in exported snapshots like this one, and probably in linked worktrees, where `.git` is a file. The hermetic self-test runs "no Git", so nothing covers it. The local 149/149 and the reviewer snapshots therefore cannot catch it.
- **Effect:** the blocking checks job is red on every push and PR.
- **Fix:**
  - Exclude the marker from the count, for example `git ls-files -- "$CI_OUT_REL_PATH" ':!:'"$CI_OUT_REL_PATH"'/.gitignore'`. Alternatively, move the rule to the root `.gitignore` and delete the tracked file.
  - Also add a self-test case that runs the self-check in a throwaway `git init` checkout, so the Git branch of the check is exercised.

**C2. The Warning watch step fails the job on a path name. A non-physics warning about `res://tools/jolt_inventory` is classified as a Jolt physics warning.**

- **Evidence:** hosted log lines 140–148. The only warning is `WARNING: Detected another project.godot at res://tools/jolt_inventory. The folder will be ignored.` It is labelled `[unexpected]` and then reported as "a Jolt physics warning … contacts were ignored or a slower allocator was used".
- **Cause:**
  - `warning_watch.sh:117` uses `grep -i 'jolt'` on unaccepted lines, and `common.sh:257` (`ci_log_jolt_warning_lines`) uses the same rule.
  - `tools/ci/warnings.allow` accepts only the `tools/tick_probe` variant of this nested-project message.
  - The new nested project `tools/jolt_inventory/` (it has its own `project.godot`) produces the same benign message with "jolt" in its path.
- **Two defects here:**
  1. **The allow-list was not updated for the new nested project.**
  2. **The Jolt classifier is a substring match, not a match on the five engine messages** that `common.sh:241-250` itself lists ("Jolt Physics job system exceeded…", "…cache exceeded capacity and contacts were ignored", "temporary memory allocator exceeded capacity…"). Any unaccepted warning whose path, resource or script name contains "jolt" is reported as a physics failure, with an `::error::` annotation that states a false cause.
- **The same rule is in `ci.sh`'s engine-check judging** (`ci.sh:1207-1216`, through `ci_log_jolt_warning_count`). Any check log carrying such a line fails the same way. Whether the boot smoke's `--script` run prints the nested-project line was not measured.
- **Fix:**
  - Add an allow-list entry for `res://tools/jolt_inventory`, with its reason, as for `tick_probe`.
  - Anchor the Jolt classifier on the engine's actual message shapes, for example `^(USER )?WARNING: .*Jolt Physics` or the five messages explicitly, rather than on any occurrence of "jolt".
  - Add a self-test case with a non-physics warning that mentions `jolt_inventory`, expecting no Jolt failure.

**C3. The macOS preset requests Xcode `codesign` (`codesign/codesign=3`), which the Linux runner cannot do. Its own comment claims built-in ad-hoc signing.**

- **Evidence:** hosted log lines 40–42: `export exited 1`, then `ERROR: Cannot export project with preset "macOS Apple Silicon" due to configuration errors:` (log line 14) and `Project export for preset … failed.` (log line 19).
- **Cause (inference, high confidence; the error detail lines were not printed, see M1):**
  - In the pinned engine's macOS exporter, `codesign/codesign` is the enum `Disabled, Built-in (ad-hoc only), rcodesign, Xcode codesign` (0–3, editor default 1), so `3` selects Xcode `codesign`. That tool exists only on a macOS host.
  - On the historical reviewer's Mac the same preset exported. On `ubuntu-latest` it is a configuration error.
- **The file contradicts itself:**
  - Its header (`export_presets.cfg:16-19`) says "the macOS preset uses Godot's built-in AD-HOC signing".
  - The earlier research recommendation (`review/baddc856…:153`) also says "Built-in (ad-hoc only)".
  - The value is the Xcode mode.
- **Effect:** the export-preparation job cannot pass on hosted Linux. Because the loop stops at the first failure, **Windows and Linux exports have no hosted evidence at all**.
- **Fix:**
  - Set `codesign/codesign=1` (built-in ad-hoc).
  - Then re-verify on the Mac that the arm64 slice still launches, and re-check the signature that M0 smoke relies on.
  - Optionally, make the build loop attempt every preset and fail at the end, so one preset cannot hide the others.

### Medium

**M1. The workflow's build step passes a relative `--out`, which the engine resolves against the scratch project copy, not the checkout. This is untested and likely to fail once C3 is fixed.**

- **Cause:**
  - `ci.yml:356` builds `out="build/${name}.ext"` and passes it unchanged.
  - `ci_export_build` (`ci.sh:1772-1792`) runs Godot with `--path "$CI_PROJECT_COPY"` and the same relative path. It creates `dirname "$_out"` relative to the **caller's cwd**, then checks `[ -s "$_out" ]` relative to that cwd.
  - Godot documents the `--export-release` path as "absolute or relative to the project directory". The project directory here is `tools/ci/out/project-copy`. The package would therefore land in `tools/ci/out/project-copy/build/…`.
- **Two probable outcomes:**
  - `ci.sh` reports "export produced no output" for a successful export.
  - Or, if a `build/` directory happens to be present in the copy (the workflow creates `build/` before the copy is made), the package is written into the scratch copy, and the `Upload built packages` step uploads an empty `build/`.
- **Coverage:** the only end-to-end export case (`run_tests.sh:1631`) uses an absolute `--out`, and it is skipped on hosted runners anyway.
- **Not engine-verified here** (limit 2). The hosted run never reached a successful export.
- **Fix:** in `ci_export_build`, make `_out` absolute against the invoking cwd before calling the engine. Add a relative-path case to the end-to-end export test.

**M2. Export failures are not diagnosable from hosted output.**

- **Cause:**
  - `ci.sh:1779-1780` prints only lines matching the anchored `^(ERROR|…):` pattern. Godot's configuration-error **reasons** (log lines 15–18, between the two printed `ERROR:` lines) are therefore dropped.
  - The `export-preparation` job uploads only `build/`, not `tools/ci/out/logs` or `tools/ci/out/reports` (`ci.yml:364-371`). Compare `ci.yml:182-189` in the checks job.
- **Effect:** for C3 the actual reason is invisible in the run. That is why C3 rests on an inference.
- **Fix:**
  - On export failure, print the log tail, or the lines following `due to configuration errors:`.
  - Upload `tools/ci/out/` from the export job under `if: always()`.

### Minor

- **N1. The hosted self-test is materially weaker than the local one: 132 versus 149 cases.**
  - It skips actionlint, every engine-backed export case and the ffmpeg probe on the runner that CI actually uses.
  - Local "149/149, actionlint passed" is therefore not evidence about the hosted workflow. The coordinator's brief already notes this, and this report agrees.
  - Consider installing actionlint, by a pinned digest, in the checks job.
- **N2. Stale comments.** `common.sh:178-179` and `warnings.allow:17-20` still describe `tools/tick_probe` as the only benign nested-project warning. The hosted run shows only the `jolt_inventory` line, so which nested project the engine reports is not stable across hosts or trees. Allow both.

## Disposition of the historical findings (4803d848)

| Item | Status at deaf052 |
| --- | --- |
| E1 templates not installed/verified; `GODOT_TEMPLATES_DIR` misleading | **Fixed for provisioning.** The hosted run downloaded, digest-verified and installed the templates, and `export --check` passed. The **export itself still fails** (C3, then probably M1), so hosted export preparation is still not demonstrated. |
| E2 wrong-architecture acceptance | Code reviewed (`ci_export_templates_check` derives the files from the preset architecture and refuses empty files). Appears addressed. **Not executed here.** |
| E3 sidecar `.pck` hashing | Code reviewed (`ci.sh:1794-1810`). It appears addressed. Covered only by an absolute-path end-to-end case that is skipped on hosted runners. **Not executed here.** |
| E4 dev tooling in packages | `exclude_filter` covers tools/fixtures/schemas/docs/plan/review/work/.github/tests/`*.py`/`*.sh`/`assets/manifest.json`. The text is consistent. The pack inventory check was **not executed here.** |
| W1 warning watch skipped on failure | **Fixed.** `if: always()`, and the hosted run shows the step ran after Validate failed. |
| W2 workflow/`ci.sh` disagreement | **Fixed as designed.** Both use `ci_warning_is_accepted`. The shared classifier is itself wrong, though (C2). |
| W3 misleading "surfaced, not fatal" line | Partly: `warning_watch.sh` prints a FAIL verdict only. `ci_log_warning_gate` still prints "surfaced, not fatal" for import and export logs whose line later fails the watch step (hosted lines 35 and 61, then 142). This is cosmetic, but it recurs together with C2. |

## Verdict

**Changes required.**

- **C1 and C2** are reproducible blocking defects, both shown directly by the hosted run on this exact SHA. Because of them, the blocking `import, validate, test` job cannot be green.
- **C3** blocks the export-preparation job on hosted Linux. Its cause is a high-confidence inference, because the engine's reason lines were not surfaced (M2).
- **M1** is a likely next failure once C3 is fixed. It is not engine-verified.

Template provisioning (E1) and W1/W2 are the parts of this candidate that I can confirm work on hosted CI. Hosted Windows and Linux export, hosted runtime-error gating and the hosted Test step are **not verified**: they never ran in run 45921573623.

M0 remains open.
