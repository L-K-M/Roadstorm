<!-- Coordinator attestation: immutable git archive of d6c4bd0; Claude Code --model claude-opus-5-5 returned JSON modelUsage.claude-opus-5-5.provider=firstParty and is_error=false. Reviewer wrote the body below in plan mode. Hosted Ubuntu run 46057085429 completed after the reviewer prompt was frozen and failed cases 244 and 246 (267/269); that result corroborates F1. This note is coordinator evidence and not part of the independent reviewer text. -->

# Roadstorm M0 CI scoped recheck: `d6c4bd0` (base of failed review `e46f396`)

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, in the Claude Code harness. That identity comes from my own session. I used no subagents, helpers, or network access, and I did not consult any GPT-6.2 Sol review of `d6c4bd0`.
**Mode:** read-only. Plan mode was active, so this file is the only one I wrote. I did not edit the archive or any report in it.

## Verdict: changes required (narrow)

`d6c4bd0` closes four of the five e46f396 Sol points outright:
- identical Python startup for the preflight and the real checker;
- complete header-write checking;
- no create-on-append on either writer outcome;
- the success line gated on a bound append.

The fifth point, binding to the reserved inode, holds against every **path-swap timing** race. It is not robust against **inode-number reuse** after all of the report's names are unlinked. The README now states that the same-header swapped case fails closed without qualification. Pinning the inode is about three lines; alternatively, narrow the claim (F1). Nothing else blocks.

## Identity and scope checked

`git hash-object` equals `git rev-parse d6c4bd0:<f>` for all five scoped files:

| File | Blob |
| --- | --- |
| `ci.yml` | `73dbdb7` |
| `ci.sh` | `cbb1133` |
| `common.sh` | `5b5d584` |
| `run_tests.sh` | `0e568f0` |
| `README.md` | `30cf43f` |

- In `e46f396..d6c4bd0`, only `de9bd7c` touches these files (+438/−21).
- I read both e46f396 reports in `review/implementation/`.

## Ranked findings

**F1 (P3, blocks a clean pass): the dev/inode binding is not stable across unlink, and the README overstates it.**
- **Where:**
  - `common.sh:1113`: the identity is captured as a string.
  - `common.sh:1165-1192`: `ci_report_identity` and `ci_append_report_verdict` compare the `st_dev st_ino` strings.
  - `ci.sh:311-321` and `:333-351`: the path-level checks.
  - README `:122`: "a missing, deleted or same-header swapped report fails closed".
- **Reproduction logic:**
  1. A writer (the Godot child, which inherits `ROADSTORM_CI_REPORT` and `ROADSTORM_CI_ATTEMPT_ID`) unlinks every name of the reserved report.
     - Through the outer path there are two names: the run report and the preset hard link.
     - Through a direct `__export-inner` there is one, as in the tests at `run_tests.sh:3700-3817`.
  2. The inode is freed.
  3. The writer creates a new file at the preset path, starting with `attempt-id: <id>`.
  4. On filesystems that reuse freed inode numbers (ext4 and XFS on Linux, including hosted ubuntu-latest), the new file can receive the same `st_ino` on the same `st_dev`.
  5. `_ci_assert_publishable_report` and the `fstat` check in `ci_append_report_verdict` then both match. The PASS verdict lands in the replacement, and `ci_ok` prints.
- **Limits of this finding:**
  - APFS (macOS) does not reuse inode numbers, so the 270/270 macOS runs cannot exhibit this.
  - I did not demonstrate it on Linux. Whether ext4 hands back the just-freed number depends on lower free bits in the block group. The finding rests on the mechanism, not on an observed failure.
- **Hosted risk:** cases 246 and 248 (the replace and swap tests) could fail on Ubuntu if reuse happens. Their outcome on the pending hosted run is a small data point, not proof either way.
- **Fix, preferred:** pin the inode for the life of the attempt.
  1. After the body is fully written, open a read descriptor on it in `ci_init_report` (`exec 9<"$_body"`) before capturing the identity.
  2. Keep it open. The nested `eval`'d `__export-inner` inherits it, so the number cannot be reused while any binder runs.
  3. Optionally close it for the Godot child.
- **Fix, alternative:** qualify the README sentence ("while the reserved inode remains allocated").

**F2 (minor, CI coverage): the real GNU `ln -T` case is not required by name.**
- **Where:** `run_tests.sh:3820-3861`; the needle list at `ci.yml:368-414`.
- The case runs only where `ln -T` works and otherwise logs a note. On macOS it was skipped (the sh log at line 311 says so).
- The workflow does not list "the real host ln -T fallback links exactly with Python disabled". If the probe silently skipped on Ubuntu, hosted CI would still pass.
- Add the needle, or a `grep -qF 'ln lacks -T'` hard failure, to the Linux job. Until then, prior m2 (the real GNU fallback never exercised) is closed only once the hosted log shows that case line.

**F3 (minor, evidence/docs): on a Python-less host, export failure verdicts are no longer recorded in the report.**
- **Where:** `ci.sh:2005-2007` and `:2225` set `CI_REPORT_REQUIRE_BOUND=1`; `common.sh:1155-1157` then refuses the unbound append.
- **Behavior:** with no identity, `reason=inventory-python-unavailable` (`ci.sh:371`) and every other export failure verdict reach stderr only. The test at `run_tests.sh:3621-3622` now asserts this absence.
- This fails closed, which is defensible. However, README `:122` still says "failure paths record their distinct verdict". State the Python-less exception there.

**F4 (nit, residual): `ci_append_report_verdict` is unbounded and opens without `O_NONBLOCK`/`O_NOFOLLOW`.**
- **Where:** `common.sh:1178`.
- A path swapped to a FIFO between the shell `[ -f ]` test (`:1146`) and `os.open` blocks indefinitely: `O_WRONLY` on a FIFO with no reader blocks.
- A symlink swap is harmless, because the `fstat` check rejects foreign inodes.
- Hostile-only. Use `O_NONBLOCK` (and reject a non-regular file in `fstat`) or run it under `ci_run_bounded`.

**F5 (nit): stale comments.**
- `ci.sh:2549-2553` still says "POSIX shell cannot atomically append without O_CREAT … documented residual race". Since the Python helper landed, the append never creates.
- `_ci_verify_report_identity` (`ci.sh:327-331`) calls the env handoff "authentic". In fact it is format-validated only (`common.sh:1058-1067`) and then checked against `stat`. The effect is "bind to the inode the caller named", which is acceptable for a caller-controlled entry point.

## Prior-finding disposition

| e46f396 finding | Status at d6c4bd0 | Evidence |
| --- | --- | --- |
| Sol 1: preflight vs checker Python startup | **Closed** | Both use `ci_python3` → `python3 -I`, through the same PATH lookup (`common.sh:1208-1211`, `ci.sh:368`, `:2476`). `shutil` was added to the import list (closes Opus n3). `PYTHONHOME=/nonexistent python3 -I -c 'import …all ten…'` succeeded here, while the plain startup aborted (my probe). Test 244 uses a shim that fails without `-I`, so the old code would fail it; it is a genuine regression test. |
| Sol 2: partial header write | **Closed** | Seven individually status-checked `printf`s; the first uses `>` and the rest `>>`. Any failure sets `_body_ok=0`, then `rm` and `ci_die` before identity capture or link (`common.sh:1098-1109`). Test 29 overrides only the first `printf`. The old compound group would return the last `printf`'s 0 and link, so the test discriminates. |
| Sol 3a: header anywhere in the file | **Closed** | `NR == 1` (`common.sh:1202`); a later-line case was added (`run_tests.sh:402,408`). Also closes Opus n1. |
| Sol 3b: final check by path, append by path | **Closed for timing races; F1 residual** | See the guarantee below. |
| Sol 3c: failing writer recreates a headerless FAIL | **Closed** | `ci_report` returns 1 for a missing, symlinked or non-regular report (`common.sh:1146-1148`). The bound helper has no `O_CREAT`. With `REQUIRE_BOUND`, an unbound export never falls back to `>>`. Test 245 checks that the report stays absent, there is no package, and there is no `[ci:ok]`. |
| Success only after an attributable verdict | **Closed (modulo F1)** | The only export `ci_ok` lines (`ci.sh:2561-2562`) follow a successful `ci_report` at `:2557`, which with an identity is the `fstat`-bound append. The outer path returns the inner's exit code and prints only the diagnostic `report:` line (dispatch tail). Test 248 covers a passing writer that swaps the report. |
| Opus m1 (no body-write test) | Closed | Test 29. |
| Opus m2 (real `ln -T` untested) | Partly closed | Case added, but it is conditional and not required (F2). |
| Opus n2 (stale rc-2 message) | Closed | `ci.sh:2090`, `:2252`. |
| Opus n4 (window before PASS) | Superseded | The window is now F1, plus the F4 hang. |

## Practical guarantee (path/inode timing)

1. **Identity.** `ci_init_report` captures `st_dev st_ino` from the private mktemp body after a fully checked write and before the create-only link. A same-header file swapped in before binding never becomes trusted (test 247).
2. **Outer path.** It re-verifies the identity before preset publication (`ci.sh:2082`) and hands it to the inner via `ROADSTORM_CI_REPORT_IDENTITY`. Publication links the run-report path by name, so a swap between the check and the link gives the preset name a foreign inode. The inner then rejects it at `:2244` before locks, scratch preparation or the writer.
3. **Inner path, after the writer.** Every verdict append, PASS and FAIL alike, opens the path `O_WRONLY|O_APPEND` without `O_CREAT`, then `fstat`s the descriptor it actually holds and writes only if `dev/ino` matches. Resolving the path and checking the identity are therefore atomic with respect to the write. A rename or unlink at any moment either writes into the original inode, if it still has that name, or writes nothing.
4. **Result.** Verdict bytes can only land in a file whose `dev/ino` equals the reserved one at write time, and no path is ever created.
5. **Residuals, all of which need a hostile process with write access to the reports directory:**
   - (a) inode-number reuse after every name is unlinked (F1);
   - (b) in-place content edits of the genuine inode. Identity is not content integrity: a writer can truncate the header after the `NR==1` check at `:2554` and before the append, or forge lines;
   - (c) the FIFO-swap hang (F4);
   - (d) the report being unlinked after a successful append. The PASS line is printed, but the evidence then exists only in an unlinked inode. The verdict was attributable when written; nothing re-checks afterward.

## Workflow and static portability

- **Required case names.** All 46 required needles in `ci.yml:368-414` exist literally in `run_tests.sh` (my loop found none missing). The 14 new names cover every new case except the real `ln -T` case (F2).
- **Skip detection.** The template and engine skip greps are intact.
- **`ln -T` fallback (`common.sh:1283`).** Unchanged from e46f396 and classified correctly by reading.
- **Python-less Linux:**
  - `pin` reserves via `ln -T` and appends unbound (`REQUIRE_BOUND=0`).
  - `export` passes `_ci_verify_report_identity` only because the interpreter is unusable. It is then refused by the inventory guard before the writer (test 243).
  - A host where Python imports `os` but identity capture failed is refused outright. That is fail-closed.
- **New shell constructs** are POSIX: `case` patterns, `wc -w`, `exec`-free. The `ci_run_bounded ci_python3` probe runs a shell function in a background subshell, which is fine in sh and dash. The only new tool dependency is the existing `python3`.

## Directly checked vs supplied

**Directly checked by me:**
- the blob identity above;
- the scoped diff `e46f396..d6c4bd0`, read through `git diff` of the commit objects only (not the live working tree);
- full reads of the export build, inner and PASS paths, `ci_init_report`, `ci_report` and the new helpers, plus the new tests;
- the needle-existence loop;
- the evidence-log case lines: cases 29 and 243-251 are `yes` in the sh log, and line 311 shows the real `ln -T` case skipped on macOS;
- the `PYTHONHOME` `-I` probe;
- the `pack_inventory.py` imports (lines 59-67 and the lazy `shutil` import at 713).

**Not run:** the self-test, Godot, write probes, dash probes against the helpers, shellcheck or actionlint.

**Supplied by the coordinator, not reproduced:**
- `sh -n` and `dash -n`;
- actionlint (the log is empty, consistent with no findings);
- 270/270 under both sh and dash on macOS (I confirmed the summary lines in `../evidence`).

**Pending:** hosted Ubuntu for this SHA. That is where F1's test sensitivity and F2's real `ln -T` case would show.

## Limits

This is a scoped review of the CI report and export guard only. It says nothing about:
- M0.5 or whole-M0 acceptance;
- target-platform launches, signing or rights;
- the M1 or audio commits in the same range.

A passing self-test is not proof of its own correctness. I judged each new test by whether the pre-fix code would fail it.

## Recheck needed after a fix

1. Apply the F1 fix (held descriptor or README qualification), optionally with F2-F5.
2. Rerun the sh and dash self-tests.
3. On hosted Ubuntu, confirm that the "real host ln -T fallback" line appears with `yes` and that cases 245-248 pass.
