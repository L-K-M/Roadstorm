I found no blocking defects. All three supported Sol findings at `0b18f00` are fixed in the code. Hosted Ubuntu is not verified because no `hosted.log` was supplied.

# Roadstorm M0.5 CI repair: independent Opus scoped recheck of `b679f58`

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, in Claude Code (plan permission mode). That identity comes from my own session.
**Candidate:** `b679f58c9c0ddd38ba9db4f762c5e94d7c6d15b2`, reviewed as the supplied git-archive export in `source/`.
**Baseline:** `0b18f007bde78286e89ddc2a3e4d1c6c2359897c`.
**Scope:** the five CI paths only: `.github/workflows/ci.yml`, `tools/ci/ci.sh`, `tools/ci/lib/common.sh`, `tools/ci/tests/run_tests.sh`, `tools/ci/README.md`.

**Conduct:**
- No subagents, helpers, network access or other models.
- No edits and no Git mutation; I wrote no files.
- I read only my own review directory, not the live checkout or another reviewer's current report.

## Verdict for M0.5 CI

- **Code review: pass.** Each of the three Sol findings at `0b18f00` is closed in the code. The remaining items below are test-strength gaps and nits.
- **Hosted Ubuntu: not verified.** My review directory has no `hosted.log` (it holds only `prompt.md`, an empty `result.json`, `source/` and an empty `stderr.log`). So no hosted run on exact `b679f58` is evidenced, and I claim no hosted pass. The Linux path still needs that run: inode pinning on ext4, the needle-gated FIFO case, and the real `ln -T` case.

This verdict covers only M0.5 CI report and export binding. It does not cover whole M0, rights, gameplay or release acceptance.

## Status of the three Sol findings at `0b18f00`

| # | Sol finding | Status | Basis |
|---|---|---|---|
| 1 | An early export rejection could append FAIL to an inherited, unbound report. | **Closed** | `ci_early_namespace_guard` now sets `CI_REPORT_REQUIRE_BOUND=1` before any `ci_init_report` or `ci_report` (`ci.sh:457`). This covers all three refusal branches: newline path, `.ci-lock` output, `.ci-lock` sidecar (`ci.sh:459-492`). An inherited `ROADSTORM_CI_REPORT` with no live fd 7 gets no identity (`common.sh:1060-1085`). `ci_report` then returns 1 before reaching the shell `>>` (`common.sh:1191-1193`), so it neither appends nor creates the file. A real bound inherited fd still appends through the bound helper. |
| 2 | A symlink to a second hard link of the authentic inode passed the identity check. | **Closed** | `ci_report_matches_bound_fd` now does a single `os.lstat` and requires `S_ISREG` on that result and on `fstat(7)` before comparing dev/inode (`common.sh:1236-1249`). A symlink, FIFO, directory or character device at the path is rejected. A genuine second hard link at the path is still accepted, which is correct. The post-append recheck (`ci.sh:2577-2581`) uses this helper, so a symlink swapped in after the append no longer yields success lines. |
| 3 | The path-based `awk` header read could block on a FIFO substituted after the identity check. | **Closed for every export path** | `_ci_assert_publishable_report` refuses an untrusted identity whenever `REQUIRE_BOUND=1`, before any path read (`ci.sh:314-318`). When bound, it reads the header through `ci_report_has_attempt_header_fd`, which uses `os.pread(fd, 4096, 0)` (`ci.sh:324-331`, `common.sh:1302-1321`). Every caller (`ci.sh:2091`, `:2255`, `:2567`) runs after `REQUIRE_BOUND=1` is set (`:2019`, `:2239`). The path-based `awk` form at `ci.sh:333` is therefore unreachable in production and is kept for unit tests. |

## Other points you asked me to examine

- **Trust of the held fd and the environment handoff.**
  - A fresh reservation first runs `exec 7>&-`, which drops any stray inherited fd 7 (`common.sh:1135`).
  - It then checks readability in a subshell before `exec 7<` (`common.sh:1136-1137`). This fixes the earlier dash N3 issue, where a failed `exec` killed the shell before cleanup.
  - The nested worker trusts only `ROADSTORM_CI_REPORT_FD=7` plus a successful `fstat(7)`.
  - A caller-supplied fd 7 on some other object fails closed: either `matches_bound_fd` rejects it (not a regular file, or the path's inode differs) or `pread` fails (ESPIPE on a pipe, which I probed).
  - A caller that opens fd 7 on a file of its own choosing is the same user writing their own file. That is not a trust boundary.
  - Fd 7 is never reused: only the lock fds 8 and 9 and the explicit closes touch other descriptors.
- **Regular-file no-follow check.** Correct (see finding 2). The append helper keeps `O_WRONLY|O_APPEND|O_NONBLOCK|O_NOFOLLOW`, no `O_CREAT`, plus `S_ISREG` and an inode match on the opened fd (`common.sh:1255-1281`).
- **Bounded first-line read.**
  - It reads at most 4096 bytes at offset 0 and leaves the shared file offset unchanged; two consecutive reads gave the same result.
  - On a pipe it fails; on `/dev/null` it returns empty, which fails the comparison.
  - An attempt id near 4 KB could never match, but the report filename's length limit makes that unreachable.
- **Append paths, failure and success.**
  - Every `ci_report` in the export flow (`ci.sh:2107-2545`) goes through `ci_report`. With an identity set, that is the bound helper; without one, it refuses under `REQUIRE_BOUND`.
  - The PASS path is: assert, bound append, then lstat/inode recheck, then `ci_ok` (`ci.sh:2567-2583`).
  - The outer closes fd 7 after the inner returns (`ci.sh:2175`), and the inner closes it in its traps (`ci.sh:2351-2352`). No outer `ci_report` follows the close; if one did, `fstat(7)` would fail closed.
- **Publication window.** `ci_link_create_only` links by pathname (`common.sh:1378-1415`). A hostile swap between the identity check and publication could link a foreign inode at the preset name. Every later bound append and the inner's assert then refuse, so no PASS and no foreign verdict can result. This is adversarial-only and fails closed.
- **Platforms.**
  - Every workflow job is `ubuntu-latest` (`ci.yml:43, 204, 238, 506`), and no Windows-native Python path is exercised.
  - `os.pread`, `O_NOFOLLOW` and `O_NONBLOCK` exist on Linux and macOS.
  - Fd 7 opened by `exec` is inheritable under both macOS `sh` and dash (probed: `os.get_inheritable(7)` is True).
  - The ksh93/mksh close-on-exec limit from my previous report (N6) still applies and still fails closed.
- **Needles.** The workflow requires each new case's `-> yes` line (`ci.yml:402-409`), so on Ubuntu a skipped FIFO case (no `mkfifo`) fails the job.

## Findings, ranked (none blocking)

1. **Minor, test strength: the FIFO case does not show the run got past the header gate** (`run_tests.sh:4074-4077`).
   - The pass condition is: nonzero rc, no FIFO marker, no PASS line, no package.
   - Any unrelated refusal before the first `_ci_assert_publishable_report` satisfies all four, so the case would pass without exercising the fd read.
   - It still discriminates against `0b18f00`: the old `awk` read would create the marker and hang until the 90s bound.
   - Fix: also assert writer-stage evidence, for example that the published report contains the `exit=99` failure verdict produced by `DELW` (`run_tests.sh:3884`).
2. **Minor, test strength: the missing-inherited-path early case did not fail at `0b18f00`** (`run_tests.sh:3537-3555`).
   - `ci_report`'s `[ ! -f ]` check (`common.sh:1182`) already refused a missing path there.
   - The race it is meant to guard (unlink between the shell test and `>>`) is not exercised.
   - The foreign-file case (`run_tests.sh:3515-3535`) is the one that discriminates, and it does.
3. **Nit, diagnostics and Python-less behavior** (`ci.sh:457`, `:464/482/490`).
   - The bound requirement now applies to self-reserved reports in the early guard too. On a Python-less host, an early `.ci-lock` refusal therefore leaves its own fresh report without a FAIL line. This fails closed, and the README's general "on a host with a usable interpreter" caveat covers it.
   - With an inherited unbound path, `ci_info "report: $CI_REPORT"` names the foreign inherited file even though nothing was recorded there.
4. **Nit, carried over from my N5: dead variable.** `ROADSTORM_CI_REPORT_IDENTITY` is still exported (`ci.sh:2158`) and sanitized (`common.sh:1079-1083`), but nothing reads it.
5. **Nit: leftover exports.** After the handoff, `ROADSTORM_CI_REPORT_FD`, `ROADSTORM_CI_REPORT_IDENTITY` and `ROADSTORM_CI_ATTEMPT_ID` stay exported in the outer process (`ci.sh:2157-2180`). This is harmless today because no child is spawned afterwards.

## Remaining limits

**Normal invocation vs local adversarial replacement.**
- With ordinary use and no same-user interference, the report is reserved, pinned, published, header-checked through fd 7, and every verdict is bound to the pinned inode.
- Every same-user hostile pathname swap now fails closed without blocking: unlink and recreate, same-header replacement, a symlink to a hard link, or a FIFO at any checked point.

**What remains, and cannot be closed by tool-level checks:**
- a hostile change after the post-append recheck, including after the process exits;
- in-place edits or truncation of the genuine inode by a same-user writer;
- a pathname-linked foreign inode at the preset name, which fails closed without a verdict;
- shells that set close-on-exec on fd 7 (ksh93/mksh), which fail closed.

## Checks I ran personally

| Check | Result |
|---|---|
| `sh -n` and `dash -n` on `ci.sh`, `common.sh`, `run_tests.sh` | all pass |
| `actionlint .github/workflows/ci.yml` | pass |
| `git hash-object --no-filters` on the five archive files | `ci.yml 465afba`, `ci.sh 1dbc8f2`, `common.sh 6e7a593`, `run_tests.sh 8c0ccfe`, `README.md 215258c` |
| `ci_report_matches_bound_fd` with fd 7 on `AGENTS.md`, under sh and dash | same file accepted; other regular file, `/dev/null`, directory and closed fd all rejected |
| `ci_report_first_line_fd` | correct first line, and a second read gives the same result; pipe fd gives rc=1 and the header is refused |
| fd 7 opened by `exec` under sh and dash | inheritable by `python3 -I` |
| Full read of the report/export code in `common.sh` and `ci.sh`, the new test cases, the workflow needles and the README cell | done |

I could not compare those blob hashes against the commit objects without reading outside my directory. Archive provenance therefore rests on the coordinator's attestation.

**Not run:**
- the self-test suite;
- Godot;
- any FIFO, symlink or write probe;
- a baseline diff (no `0b18f00` objects are in my archive).

These were left out to stay read-only, as plan mode and the brief require.

## Supplied evidence and its limits

- **Coordinator's local run:** this five-file overlay at 278/278 under macOS `sh` and under dash, plus syntax checks and actionlint. I did not reproduce the suite.
- **Hosted log:** none supplied, so a hosted Ubuntu run on exact `b679f58c9c0ddd38ba9db4f762c5e94d7c6d15b2` is unverified.

M0.5 CI closure still needs a green hosted Ubuntu run on that exact SHA showing every needle in `ci.yml:370-423`, in particular:
- the FIFO seam case;
- the symlink identity case;
- the unbound-inherited cases;
- the real `ln -T` case.

## Coordinator post-review attestation (not reviewer-observed)

The independent review above finished before the hosted run was available in that reviewer's archive. The coordinator later verified [GitHub Actions run 46068220462](https://github.com/L-K-M/Roadstorm/actions/runs/46068220462) checked out exact `b679f58c9c0ddd38ba9db4f762c5e94d7c6d15b2` and completed all four jobs successfully. On native Ubuntu, export preparation passed **277/277** CI self-tests; the workflow required the new descriptor-header, symlink, early-unbound-report and FIFO markers plus the real GNU `ln -T` success marker. The import/validate job passed **180/180** tooling self-tests and the runtime-error gate **6/6**. The three declared macOS, Windows and Linux export presets each produced a package and passed the package inventory check. This is export evidence, not a target-OS launch. The local coordinator's immutable exact five-file overlay passed **278/278** under macOS `sh` and **278/278** under `dash`, plus syntax and `actionlint`.

**Model identity attestation:** The first-party Claude Code result JSON records `modelUsage.claude-opus-5-5.provider=firstParty`; its original result and private session evidence are retained under ignored `work/agents/coordinator/ci-recheck-opus.b679.LV8Gn8`.
