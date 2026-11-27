# M0 export-smoke repair: independent review at `bc2cf9f` (Claude Opus 5.5)

- **Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, running in Claude Code. No delegation and no helper models.
- **Date:** 2026-11-27
- **Candidate:** `bc2cf9f1f8c43880d3c149340e7eb6fdec527e12` ("Preserve smoke output paths and bind frozen candidate evidence")
- **Scope:** `tools/export_smoke/**` changes from `e7e3882` to `bc2cf9f`. `git log e7e3882..bc2cf9f -- tools/export_smoke` lists only `bc2cf9f`, which confirms the brief's claim that the intervening commits did not touch these paths.
- **Files changed (diffstat):** `README.md` (+47), `launch_macos_app.sh` (+22), `lib/common.sh` (+462/−), `run_export_smoke.sh` (+160/−), `tests/test_common.sh` (+306/−). I also read `lib/pack_inventory.py`, which is unchanged in this commit, to check the inventory behaviour.
- **Evidence source:** only the Git objects. I used `git show bc2cf9f:<path>` and `git diff e7e3882 bc2cf9f -- tools/export_smoke`, and saved private copies with `git show … > work/agents/opus-smoke-bc2cf9f/scratch/src/...`. `git show … | cmp - <copy>` confirmed that `lib/common.sh` was copied byte for byte. `git rev-parse bc2cf9f:<path>` gave these blob ids: common.sh `b71522d`, pack_inventory.py `1f0d4c8`, run_export_smoke.sh `d381e65`, launch_macos_app.sh `6234001`, test_common.sh `f2a3492`, README.md `9d22c1c`. I did not use the live working tree as evidence. I did not read the current Sol review (`m0-smoke-gpt-6-2-sol-bc2cf9f.md`). As historical input I read only the section headings and findings of the earlier `e7e3882` Opus review.

## Execution status: STATIC-ONLY

This session's permission policy blocked every attempt to execute candidate code: `sh …/tests/test_common.sh` (with `EXPORT_SMOKE_TEST_WORK` pointing at my scratch directory), `sh -n`, `git archive`, `git hash-object` and multi-command shell lines. **I did not run the test suite, shellcheck, the runner or the launcher.** Every claim below comes from reading the code. I did not reproduce the coordinator's results (sh/dash 189/189, shellcheck, the Linux cross-export PASS, the inventory PASS, the binding matches, and the rc2 no-clobber rerun), so I have not confirmed or contradicted them.

## Verdict: **Conditional pass — targeted changes required before `presets_sha256`/`candidate_digest` is cited as "bound to `head_commit`"**

The preservation work holds up when read statically:
- `--out` is reserved with an exclusive `mkdir`. The default path uses `mktemp -d run.XXXXXX`.
- Every report and log is first created with `O_CREAT|O_EXCL`.
- The staging directory, the evidence files and the launcher's work directory are no longer deleted with `rm -rf`.
- The snapshot is checked for replacement before `cd`, and `.` is checked again after `cd` and before the overlay.
- Archive members are restricted to regular files and directories with safe paths before extraction.
- The archive digest is taken from the exact tar that was extracted.

I found no ordinary (non-adversarial) path that overwrites or deletes an existing user path, and none that reports PASS incorrectly. The main remaining issue is that the preset bytes come from the working tree, not from the commit (finding 1).

## Ranked findings

### 1. Medium: the overlaid `export_presets.cfg` comes from the live working tree, not from `head_commit`, but the docs say it is commit-bound
- `lib/common.sh:384` and `:399` copy `$_br_proj/export_presets.cfg`, the live working-tree file. `:416` then `mv`s that copy over the committed copy extracted from `git archive $SRC_SHA`.
- `export_presets.cfg` is **tracked** at `bc2cf9f` (`git cat-file -e bc2cf9f:export_presets.cfg` succeeds), so the overlay replaces committed bytes with whatever is on disk at run time.
- **Reproduction (static):** in a repository where HEAD = C1, edit `export_presets.cfg` without committing (for example, add `assets/*` to `exclude_filter`), or let a concurrent agent do so in the shared checkout. Then run `run_export_smoke.sh`. The report shows `head_commit=C1`, and `presets_sha256` and `candidate_digest` hash the uncommitted bytes. The packages are built with uncommitted presets. Nothing in the report says that the presets differ from `C1:export_presets.cfg`.
- **Where this contradicts the docs:**
  - `README.md` §Usage: "`head_commit`, `head_tree`, `archive_sha256` and `presets_sha256` all describe the exact bytes that were extracted and exported".
  - `README.md` Rule 1: "never a working-tree copy that could include another job's uncommitted files".
  - `run_export_smoke.sh:10-12`: "No concurrent uncommitted file enters it".
- **Test gap:** `tests/test_common.sh:474-475` ("digest records original-commit presets bytes") passes only because the fixture's second commit never changes `export_presets.cfg`. The live file and the C1 file are identical, so the assertion cannot catch this.
- **Fix (pick one):**
  - (a) Overlay from `git show $SRC_SHA:export_presets.cfg` captured with `es_run_exclusive`. The overlay is then a no-op and could be dropped.
  - (b) Keep the working-tree overlay, but record `presets_source=working-tree` and `presets_matches_commit=true|false` (compare with the committed blob), and correct the README and header claims.
  - Either way, add a test that changes the live presets *without committing* and asserts the chosen behaviour.

### 2. Low-Medium: the launcher keeps a full extracted `.app` in `$TMPDIR` on every macOS launch, and the README does not mention it
- `launch_macos_app.sh:63-67` and `:74` unzip the package into `${TMPDIR:-/tmp}/rs-maclaunch.XXXXXX/x` and never remove it, even on success. This is outside the reserved `--out`.
- `README.md` "Failure evidence and cleanup" lists only `<out>/…` items and says "Bounded cost: about one `git archive HEAD` per run plus a few kilobytes". That is not accurate: every macOS run also leaves a full uncompressed universal `.app` in `$TMPDIR`, and repeated runs accumulate them.
- On `die` paths after `mktemp`, the location is not printed, because the log line is only at `:180`. Examples: the unzip failure at `:74`, the missing `.app` at `:79`, and the `SIG_LOG`/`WIN_LOG` refusals at `:95`, `:133` and `:139`.
- **Fix:** extract under the reserved `--out`, for example by passing `--work "$OUT_DIR/.maclaunch"` from the runner. Alternatively, document the `$TMPDIR` leftover and its cleanup, and print `$WORK` immediately after `mktemp`.

### 3. Low: `es_run_exclusive` reads all of stdout before stderr, so it can deadlock with no timeout
- `lib/common.sh:255-267` drains `p.stdout` to EOF and only then reads `p.stderr`. If a child writes more than the stderr pipe buffer (about 16–64 KiB) while stdout is still open, the child blocks on stderr and Python blocks on stdout. The callers (`git archive` at `:585`, `tar -tvf`/`-tf` at `:327`/`:342`) are not wrapped in `es_run_bounded`, so such a hang would never end. With the current repository (no `.gitattributes`, no filters) these commands write little or nothing to stderr, so in practice the risk is low.
- **Other issues in the same function:**
  - `os.write` short writes are not looped. A short final write on a nearly full disk silently truncates the capture and still exits 0. The archive digest would then describe the truncated bytes, although the coordinator's independent git-object comparison would catch the mismatch.
  - The `exec failed` message is lost because of `2>/dev/null` at `:272`.
  - A child killed by a signal makes Python exit with a nonzero code computed from a negative value (for example, 241 for SIGTERM). That is harmless.
- **Fix:** `Popen(cmd, cwd=wd, stdout=fd_o, stderr=fd_e or subprocess.DEVNULL)`. The child then writes directly through the descriptors held with `O_EXCL`, with no pipes, no deadlock and no short-write handling needed. It also preserves the "no pathname reopen" property.
- The same short-write gap exists in `_es_copy_exclusive` (`:307-310`).

### 4. Low: `_es_copy_exclusive` does not check the source type or refuse symlinks
- `lib/common.sh:299` uses `os.open(src, O_RDONLY)`, which follows symlinks and blocks forever on a FIFO, and has no `fstat`/`S_ISREG` check. The caller's precheck `[ -f "$_br_proj/export_presets.cfg" ]` at `:384` also follows symlinks.
- **Consequences:**
  - A live `export_presets.cfg` that is a symlink to any readable regular file is silently copied into the candidate. The archive validator rejects only *committed* symlinks.
  - A same-UID swap of the source to a FIFO between `:384` and `:299` hangs the run with no bound.
- The ordinary-use risk is nil, because the file is a regular `100644` file. The hang is in the same-UID adversary class.
- **Fix:** open with `O_RDONLY|O_NOFOLLOW|O_NONBLOCK`, require `S_ISREG(fstat(fs).st_mode)`, then clear `O_NONBLOCK`.
- Also, `fd=dst and op(dst)` at `:303` gives `fd=""` when `dst` is empty, and `os.write("",…)` then raises `TypeError`. No caller passes an empty `dst`, so this is a nit.

### 5. Low: several remaining pathname truncations contradict "no output is truncated after creation"
- `lib/common.sh:379`: `tar -x … 2>"$_br_err"` truncates `stage.err` by pathname. That file was created exclusively by the `git archive` step (`:585`) and holds that step's stderr evidence, which is lost.
- `launch_macos_app.sh:146`: `"$EXE" >"$WIN_LOG"` truncates the log that was just created exclusively at `:138`.
- `pack_inventory.py:432` and `:665` open `--report` and `--json` with `"w"`, which follows symlinks and truncates. The runner never pre-creates these, and the README's same-UID paragraph names `pack_inventory.py`.
- In ordinary runs every one of these paths is new inside the fresh `--out`, so no pre-existing user data is at risk. The issue is the precision of `run_export_smoke.sh:79-81` and the README's "never followed or truncated".
- **Fix:** use `>>` for the first two and give `stage.err` a distinct name, such as `extract.err` created exclusively. Narrow the claim about `pack_inventory.py`.

### 6. Low: repeating `--platform` turns a successful export into a misleading failure
- `run_export_smoke.sh:117` appends to `PLATFORMS` without removing duplicates. On the second `Linux` iteration, `es_run_bounded` (`lib/common.sh:99-102`) cannot create `export-Linux.log` exclusively and returns `1` without running Godot. The report then records `status=FAILED reason=godot --export-release exited 1` and the run exits 1.
- This fails closed, so it is not an incorrect success. However, the reason text is wrong, and the log-creation failure is indistinguishable from a child exit status of 1.
- **Fix:** de-duplicate `PLATFORMS`, or have `es_run_bounded` return a distinct code (for example 125) and report "log creation refused".

### 7. Nit / documentation precision
- `README.md` says "No recursive deletion is ever performed". `pack_inventory.py:619` still calls `shutil.rmtree` on its own `mkdtemp`. CPython's fd-based rmtree resists symlinks there, so the risk is negligible, but the sentence is too absolute.
- `README.md` says "the snapshot itself stays confined to the reserved inode". That is true for the top-level directory only. A same-UID swap of an *intermediate* directory inside the snapshot during `tar -x` can redirect writes with GNU tar, which does not refuse intermediate symlinks by default. bsdtar on macOS refuses them by default. This belongs in the same-UID limitation paragraph.
- `_es_copy_exclusive`'s comment "Bytes read are exactly the bytes hashed afterwards" (`lib/common.sh:277`) is not strictly true. `:403` re-reads `./.roadstorm-presets.$$` by name, although it is relative to the held cwd. This only matters under same-UID tampering.
- `candidate_digest` is computed before `--diagnostic-enable-etc2-astc` patches `project.godot` in the snapshot (`run_export_smoke.sh:247-265`). The report does show `diagnostic_enable_etc2_astc=1`, but the digest does not cover the exported `project.godot` in that mode. State this next to the flag.
- `es_check_package`'s no-python3 branch (`run_export_smoke.sh:317-328`) cannot be reached, because `es_make_frozen_snapshot` already requires python3. That branch could also mark a run PASS without inventory checks. Remove it, or make it set `FAILED=1`.
- The README launcher example `--out /tmp/rs-mac` refuses (rc 2) on a second run because `macos-codesign.txt` exists. That is correct no-clobber behaviour, but the example should say to use a fresh directory.

## Requirement-by-requirement assessment (static)

| Area | Assessment |
| --- | --- |
| Preserve every pre-existing destination | **Pass.** Explicit `--out`: `-e`/`-L` refusal, then an exclusive `mkdir`, with "appeared" detection (`run_export_smoke.sh:183-191`). Default: `mktemp -d` under a non-symlink base (`:194-203`). Snapshot: occupancy refusal plus an exclusive `mkdir` (`common.sh:544-557`). Tests 2–5, 12 and 17 cover dirs, files, dangling links, directory symlinks and an occupied runner output. |
| Pre/post-`cd` snapshot swap | **Pass.** Pathname identity check at `:604`. In the subshell, `.` dev:inode is checked against the reservation immediately after `cd` (`:371-378`) and again before the overlay (`:388-395`), then pathname re-checks at `:617` and `:649`. Writes are relative to the held cwd. Tests in §18 cover swaps before `cd` and before `tar`. Limit: intermediate-directory swaps (finding 7). |
| Archive member type/path validation | **Pass.** First character of `tar -tvf` must be `-` or `d`; paths are rejected if they are empty, absolute, `..` or contain `/../` or end in `/..`. Names containing newlines split into extra lines, which can only cause false rejections (fail-closed). GNU tar strips a leading `/` in both listing and extraction, so the conditional absolute-path test may be skipped on Linux without exposure. The pax global header that `git archive` emits is not listed by GNU tar or bsdtar (consistent with the coordinator's Linux PASS, which I did not reproduce). |
| Stage cleanup | **Pass (by design: no deletion).** `_es_cleanup_stage` is a no-op, and staging is retained inside the reserved `--out`. The cost per run is one full candidate tar plus the snapshot, which is acceptable because it is per-run, but the launcher's `$TMPDIR` copy is not covered (finding 2). I did not measure the archive size, because `git archive` was blocked. |
| Output/default reservation | **Pass.** Two concurrent ordinary runs with the same `--out`: one wins the `mkdir`, the other gets rc 2 ("appeared" or "already exists"). Default runs get unique `run.XXXXXX` directories. |
| O_CREAT\|O_EXCL descriptor writes and presets copy | **Pass with caveats.** `_es_create_exclusive` writes through the held fd with a buffered, looped write. `es_run_exclusive` and `_es_copy_exclusive` are descriptor-based but have the gaps in findings 3–5. The overlay uses an `O_EXCL` temp file in the held cwd plus `mv -f`, which replaces rather than follows a symlink at the destination. A same-UID swap of the destination to a directory or a symlink to a directory between `:412` and `:416` would move the temp file *into* it. That is a same-UID limitation and should be noted. |
| Archive/preset/candidate digest binding | **Archive: Pass.** The digest is of the extracted tar from `git archive $SRC_SHA`. **Presets: digest is bound to the copied bytes (fixes `e7e3882` finding 1), but the source is not `head_commit`: finding 1.** **Candidate:** sha256 of `"<archive>\n<presets>\n"`, created exclusively and consistent with test 17. |
| Log/report retention | **Pass.** Report, SUMS, inventory log, `macos-launch.log`, export logs and launcher logs are created exclusively and then appended to. The evidence file and `.candidate-digest-input` are retained. Truncation exceptions are in finding 5. |
| No-clobber rerun | **Pass.** A second run with the same `--out` gets rc 2 before writing anything (test 17; coordinator reports the tree unchanged, which I did not reproduce). A standalone launcher rerun into the same `--out` gets rc 2 at `macos-codesign.txt`. |
| macOS launcher | **Pass with finding 2.** Exclusive `SIG_LOG`/`WIN_LOG`/`HEAD_LOG`. Refuses a pre-existing screenshot path, although `screencapture` still writes by pathname, as documented. The windowed process is still killed. Problems: the `$TMPDIR` extraction is retained, and `:146` truncates. |
| `es_run_exclusive` stdout/stderr | Finding 3 (serial drain can deadlock with no timeout; short writes; lost exec error). |
| `_es_copy_exclusive` source type | Finding 4 (follows symlinks, FIFOs can hang, no `S_ISREG` check). |
| Pack inventory | **Unchanged in this commit.** It fails the run on a nonzero status (`run_export_smoke.sh:341-344`), its inventory log is created exclusively, and it appends SUMS with `"a"`. Report and JSON writes truncate by pathname (finding 5). It uses `zipfile.extractall`, which sanitises `..` and absolute names and does not create symlinks, into its own `mkdtemp`. |

## Same-UID adversary versus ordinary concurrency

- **Ordinary concurrent invocations** (two runs, same or default `--out`, a concurrent commit moving HEAD): I found no overwrite, deletion or incorrect success. The one exception is that an ordinary concurrent *uncommitted edit* to `export_presets.cfg` is exported under the label of `head_commit` (finding 1). That is not adversarial.
- **Malicious same-UID pathname replacement** after reservation (swapping in symlinks or FIFOs, swapping intermediate directories, swapping the overlay destination): partly mitigated, and documented in the README's residual-limits paragraph. The FIFO hang (finding 4) and the intermediate-directory and overlay-destination redirects (findings 7 and the table) belong in that paragraph.

## Not verified

- I executed nothing: no test suite (sh/dash), no shellcheck, no fake-Godot runner run, no real export and no launcher run (permission policy).
- I did not measure the candidate's `git archive` size, so I could not quantify the retained staging cost.
- I did not verify that `( "$@" ) &` in `es_run_bounded` execs Godot directly under dash or bash-as-sh, so that a TERM on timeout reaches Godot rather than only the subshell. This behaviour predates this commit.
- Windows and Linux target launches were not tested by anyone. A successful cross-export is not a platform launch.

## Commands run (all read-only except writes inside my scratch directory and this file)

```
git diff --stat e7e3882 bc2cf9f1f8c43880d3c149340e7eb6fdec527e12 -- tools/export_smoke
git log --oneline e7e3882..bc2cf9f1f8c43880d3c149340e7eb6fdec527e12 -- tools/export_smoke
git show bc2cf9f…:tools/export_smoke/{lib/common.sh,run_export_smoke.sh,launch_macos_app.sh}
git diff e7e3882 bc2cf9f… -- tools/export_smoke/{launch_macos_app.sh,README.md,run_export_smoke.sh,lib/common.sh}
git show bc2cf9f…:tools/export_smoke/lib/pack_inventory.py | grep/sed (write and extract sites)
git show bc2cf9f…:<each of 6 files> > work/agents/opus-smoke-bc2cf9f/scratch/src/tools/export_smoke/<file>
git show bc2cf9f…:tools/export_smoke/lib/common.sh | cmp - <scratch copy>      -> SAME
git rev-parse bc2cf9f…:tools/export_smoke/<6 files>                              -> blob ids above
git cat-file -e bc2cf9f…:export_presets.cfg                                      -> TRACKED
git show bc2cf9f…:.gitattributes                                                 -> absent
grep over scratch test_common.sh and README.md; Read of test_common.sh 1-110, 446-585
Blocked by permission: sh test_common.sh, sh -n, git archive, git hash-object, compound shell lines
```
