<!-- Coordinator attestation: Claude Code --model claude-opus-5-5 in plan permission mode independently reviewed an immutable git archive of 0b18f007bde78286e89ddc2a3e4d1c6c2359897c. Result modelUsage recorded claude-opus-5-5 via firstParty; process exited 0. Reviewer did not see the current GPT-6.2 Sol report. Relative file references in the unedited reviewer text below refer to its archive. -->

## Roadstorm M0 CI repair recheck, candidate `0b18f007bde78286e89ddc2a3e4d1c6c2359897c`

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, in the Claude Code harness. That identity comes from my own session.

**What I used:**
- No subagents, helpers, network access, Godot runs or builds.
- No edits and no Git mutation. Plan mode was active and I wrote no files.
- I did not consult any GPT-6.2 Sol review of this candidate.
- I did not read the live checkout, apart from `git` object reads of the immutable commits.

### Verdict

- **The code review passes.** Every supported d6c4bd0 finding is closed in the code. No blocking defect remains; four nits and two doc or test gaps are listed below.
- **Hosted Ubuntu is not verified.** No artifact was supplied, so the hosted run on exact `0b18f00` is **pending**. In particular, Linux execution of the fd pin and of the now-required real `ln -T` case has not been observed.

### Identity and scope

`git hash-object` of each archive file equals `git rev-parse 0b18f00:<path>`:

| File | Blob |
| --- | --- |
| `ci.yml` | `b2708bf` |
| `ci.sh` | `1fc3aa6` |
| `common.sh` | `293e65f` |
| `run_tests.sh` | `6e6c8d8` |
| `README.md` | `1ef6f87` |

I read the full scoped diff `d6c4bd0..0b18f00`. The changes are: +1 needle in `ci.yml`, the README cell, the fd pin in `common.sh`, `ci.sh` switching to fd-based matching plus a post-append recheck, and the `run_tests.sh` fixtures plus new case 29.

### How the repair works

1. **Pin.** `ci_init_report` (`common.sh:1128-1146`) opens fd 7 read-only on the private mktemp body before it links the body into place. The identity comes from `fstat(7)`.
2. **Handoff.** Fd 7 stays open through the outer process and is passed to the nested worker by `eval` (`ci.sh:2132-2151`), along with `ROADSTORM_CI_REPORT_FD=7`.
3. **Inner trust.** The inner trusts only an inherited, `fstat`-able fd 7 (`common.sh:1068-1078`). It no longer trusts the env identity string.
4. **Matching.** Every check goes through `ci_report_matches_bound_fd` (`common.sh:1221`), comparing `stat(path)` with `fstat(7)`. Appends go through `ci_append_report_verdict` (`common.sh:1238`): `O_WRONLY|O_APPEND|O_NONBLOCK|O_NOFOLLOW`, no `O_CREAT`, the target must be a regular file (`S_ISREG`), and its `fstat` must equal `fstat(7)`.
5. **Recheck.** After the PASS append and before `ci_ok`, `ci.sh:2551-2558` checks that the path is not a symlink, is a regular file, and still matches fd 7.
6. **Close.** Fd 7 is closed after the inner returns (`ci.sh:2151`) and on the inner's EXIT/INT trap (`ci.sh:2327-2328`).

### Prior findings

| d6c4bd0 finding (Opus F#, Sol #) | Status | Basis |
| --- | --- | --- |
| Opus F1 / Sol 1: inode reuse after unlink | **Closed in code** | The held fd keeps the inode allocated for the whole outer and inner lifetime, so a recreated file cannot share `st_dev`/`st_ino`. The inner trusts only an inherited live fd (`common.sh:1068-1078`), which meets Sol's "require a live reference". A same-header substituted report fails at `_ci_verify_report_identity` (`ci.sh:2234`) before the writer, or at the bound append afterwards. No foreign FAIL or PASS line is written and no success is printed (cases 246-249). Linux execution is pending. |
| Sol 2: attribution lost after the append | **Closed (up to an unavoidable residual)** | Post-append recheck at `ci.sh:2551-2558`; `ci_ok` is at `:2559`. What remains is a hostile same-user change after this recheck, plus in-place edits of the genuine inode. No tool-level check can prevent either. |
| Opus F2 / Sol 3: real `ln -T` not required | **Closed** | The needle is added at `ci.yml:416` inside the `export-preparation` job (`runs-on: ubuntu-latest`). The probe skip (`run_tests.sh:3862`) emits no `-> yes` line, so a skip on Ubuntu now fails the job. The case itself disables Python with a shim and checks exact linking and refusal of occupants (`:3866-3895`). |
| Opus F3: Python-less behavior described dishonestly | **Mostly closed** | README `:122` now says that on a Python-less host, exports fail closed with the diagnostic on stderr while `pin` still reserves reports. Leftover overstatements are in N1. |
| Opus F4: FIFO hang and symlink on append | **Closed for the append** | `O_NONBLOCK` gives `ENXIO` on a FIFO with no reader, and `S_ISREG` rejects a FIFO that has one. `O_NOFOLLOW` rejects a symlink. The path-based header read remains (N4). |
| Opus F5: stale comments | **Partly closed** | `_ci_verify_report_identity` was rewritten. `ci.sh:2537-2543` still describes a "POSIX shell … without O_CREAT" residual race. |
| Sol 3 (e46f396): final verdict lacks continuity | **Closed** | Same basis as Opus F1. |

### Findings, ranked (none blocking)

**N1 (minor, docs). README `:122` mislocates the residual and keeps one overstatement.**
- It says "only a narrow swap between the last check and the write itself remains inherently racy". The write is already bound to the fd, so attribution has no check-to-write race. The real residuals are:
  - a hostile change after the post-append recheck (`ci.sh:2551-2558`), including after the process exits;
  - in-place content edits or truncation of the genuine inode by a same-user writer.
- The same cell still ends with "failure paths record their distinct verdict and print the report location". On a Python-less host, export failure verdicts reach stderr only.
- The "GNU/busybox `ln -T`" claim is only exercised for GNU on hosted Ubuntu; busybox is untested.

**N2 (minor, test proof). The end-to-end replacement tests no longer show that `ci.sh` itself depends on the fd.**
- Cases 246-249 (`run_tests.sh:3721-3855`) now run `exec 7<"$REPORT"` in the test subshell. That alone prevents inode reuse, so d6c4bd0's string comparison would also pass them on any filesystem.
- The only case that tells the old and new code apart is case 29 (`run_tests.sh:417-448`). It is a unit test of the helper: it unlinks the original, sets `CI_REPORT_IDENTITY` to the replacement's numbers, and expects a refusal. The old helper would have accepted the replacement, so the case is genuine. It is unconditional, so it needs no workflow needle.
- Missing tests:
  - a direct `__export-inner` with a valid `ROADSTORM_CI_REPORT_IDENTITY` but no fd 7 must refuse with "no authentic attempt-report identity". This would prove the inner requires the live reference.
  - nothing exercises the post-append recheck at `ci.sh:2551-2558`. It is reachable by reading only. A `python3` shim that swaps the path after a successful append would cover it.
- Fd inheritance through `eval` is covered indirectly: positive outer exports (for example `run_tests.sh:2654`, `:4126`) would fail with "no authentic identity" if fd 7 did not reach the inner.

**N3 (nit, robustness). `common.sh:1129` `if ! exec 7<"$_body"; then rm …; ci_die …` cannot reach its else-branch under dash.**
- A failed redirection on the special builtin `exec` terminates a non-interactive POSIX shell. My probe: dash exits with rc=2 without reaching the branch; macOS `sh` (bash) does reach it.
- On Ubuntu `/bin/sh`, the structured message and the `rm` of the private body are skipped, leaving a `.ci-report-body.*` file. The run still fails closed.
- The same pre-existing pattern is at `ci.sh:2305` and `:2316` for the lock fds.
- Fix: probe with `( : <"$_body" )` first, or open the fd inside `command exec`.

**N4 (nit, hostile-only liveness). Header checks still read the file by path.**
- `ci_report_has_attempt_header` (`common.sh:1270`) runs `awk` on the path. It is called from `_ci_assert_publishable_report` (`ci.sh:313`, reached from `:2067`, `:2231` and `:2544`), after the `stat` match.
- A swap to a FIFO between the `stat` and the `awk` blocks indefinitely. This is not an attribution bypass: any later append still refuses.
- Fix: read line 1 through the held descriptor (`os.pread(7, …, 0)`). That also removes the path time-of-check/time-of-use gap on the header.

**N5 (nit, dead code).**
- `ROADSTORM_CI_REPORT_IDENTITY` is still exported (`ci.sh:2134`) and sanitized in the nested init (`common.sh:1079-1083`), but nothing reads it.
- Either drop it, or as a cross-check require it to equal `fstat(7)` in the inner.
- `CI_REPORT_FD` defaults to `"7"` even when no fd is held (`common.sh:1050`). This is safe today only because every matcher call is gated on `CI_REPORT_IDENTITY`, which is set only when the fd is held. Gating on `_CI_REPORT_FD_HELD` would be more robust.

**N6 (portability limit, fails closed).**
- The handoff assumes the shell leaves fds opened by `exec 7<` inheritable. That holds for bash and dash (my probe saw Python `fstat(7)` succeed).
- ksh93 and mksh set close-on-exec on such fds. Under them, the inner sees no fd and refuses ("no authentic identity") whenever Python works. This is safe but undocumented.

### File-descriptor lifecycle

- **stdout and stderr are preserved.** All closes are literal `exec 7>&-` with no extra redirection. The comment at `common.sh:1195-1198` correctly warns against `2>/dev/null` there. My probe confirmed stderr still works after closing fd 7 inside a function, under both shells.
- **No descriptor collisions.** The lock fds are 9 and 8; the report fd is 7.
- **Godot child inherits fd 7 read-only.** This is harmless: a hostile writer can only prolong the pin, not write through it.
- **Retry loop closes correctly.** The fd is closed and `_CI_REPORT_FD_HELD` reset before the body is removed after a collision (`common.sh:1153-1154`).
- **No reports after close.** The outer closes fd 7 after the inner returns; no outer `ci_report` follows in the export flow (dispatch tail `ci.sh:2588-2616`).
- **Non-export commands** keep fd 7 for their whole lifetime, which is harmless.

### Checks run vs supplied

**Run by me:**
- blob identity for all five files;
- the scoped diff;
- reading the outer, inner and PASS paths, `ci_init_report`, the helpers and the tests;
- `sh -n` and `dash -n` on the three shell files: all pass;
- `actionlint` on `ci.yml`: passes;
- shell probes:
  - a failed `exec 7<` exits dash (rc=2) but not bash-sh;
  - fd 7 is inherited by `python3 -I`;
  - fd 7 closes inside a function and stderr survives.
- reading the evidence logs:
  - sh and dash each report 271/271;
  - cases 29 and 246-249 show `yes`;
  - the macOS note at line 312 says the real `ln -T` case was skipped.

**Not run:** the self-test, Godot, shellcheck, or any write or FIFO probes.

**Supplied by the coordinator, not reproduced:** pinned macOS sh and dash 271/271 (rerun sequentially after the signing-path collision in cases 185/189).

**Pending:** hosted Ubuntu on `0b18f00`. It is the first place Linux inode-reuse resistance (cases 246-249) and the real `ln -T` case get exercised.

### Limits

- This covers only the report and export binding in the five CI files.
- No M0.5 or whole-M0 acceptance is implied, and nothing about target-platform launch, signing or notarization, or the M1/audio changes in the same range.
- Closure still depends on a green hosted Ubuntu run on this exact SHA that shows the real `ln -T` needle line and cases 246-249 passing.
