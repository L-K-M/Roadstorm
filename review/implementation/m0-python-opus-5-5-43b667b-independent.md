# M0.1 Python pin follow-up: independent Opus 5.5 review of 43b667b

| Field | Value |
| --- | --- |
| Reviewer model / provider | Claude Opus 5.5 (`claude-opus-5-5`) / Anthropic, via Claude Code (non-interactive). No subagents, helpers, workflows or GUI. |
| Date | 2026-11-27 |
| Candidate | `43b667b62ec5546c07fb8504b6cbef1b0eb824c7` (43b667b, "Verify recorded Python identity before version selection"), resolved with `git rev-parse` |
| Base | `fb86fc3a006a4c2351a9ca463fa04b6a1c2af4ba` (fb86fc3), resolved with `git rev-parse` |
| Scope | `tools/python_pin/**`, `docs/PYTHON_TOOLCHAIN.md`. Across fb86fc3..43b667b (5 commits) only `verify.sh` (118 lines changed), `tests/test_verify.sh` (118 lines changed), `README.md` and `docs/PYTHON_TOOLCHAIN.md` change in scope: 4 files, +257/−37. `pin/` is unchanged. |
| Source of truth | `git diff fb86fc3 43b667b -- <scope>`, `git show 43b667b:tools/python_pin/verify.sh`, `git grep … 43b667b`. `git diff --stat 43b667b -- tools/python_pin docs/PYTHON_TOOLCHAIN.md` was empty, so for reading the remaining line ranges I used the working-tree copies of `verify.sh`, `tests/test_verify.sh` and `docs/PYTHON_TOOLCHAIN.md`, which are byte-identical to the commit. |
| Prior reports assessed | `m0-python-opus-5-5-fb86fc3-independent.md` (my earlier fb86fc3 review). |
| Not consulted | `m0-python-sol-recheck-43b667b.md` (Sol's report on this candidate), other workers' outputs. |
| Verdict | **Fail. One high finding (H1) blocks.** The fb86fc3 residuals L1, L2, N1, N2 and N3 are fixed as intended. The new identity check, however, fails closed on every host where the recorded path does not exist. This was established statically only; see Execution. |

## Execution

**Execution was blocked.** In this non-interactive session the permission layer
rejected `mktemp -d`, a combined `git archive | tar` snapshot command,
`git diff -U0`, `git ls-tree`, and `ls` on the recorded Homebrew path, and no
approval could be given. Commands that did run: `git rev-parse`, `git log`,
`git diff` (full and `--stat`), `git show` piped to `sed`, `git grep`, and
`git grep -c`. Nothing was executed from the candidate, and no private snapshot
was created.

For dynamic results I therefore rely on the coordinator's independent
**133/133 per sh/bash/dash** run in an isolated copy. My static assertion count
is consistent with that result (see Checks).

Nothing was written except this file. No source was edited, Git state was not
changed, and no installed or shared files were touched.

## Checks performed (static)

| Check | Result |
| --- | --- |
| Full diff of `verify.sh`, README and docs | Read. |
| `verify.sh` lines 230–560 at 43b667b | Read: discovery, `consider_candidate`, `set_digest_state` / `set_digest_failure`, `canonical_path`, `file_identity`, `check_interpreter`, `check_interpreter_digest`. |
| `test_verify.sh` lines 380–818 | Read, covering all new fixtures and the `canonical_path` harness. |
| `set -e`? | No. Only `set -u` (`:72`), and `bad` only sets `RC` (`:110`), so `return 1` from a callback does not abort discovery. |
| Committed baseline | `pin/checksums.txt:21-22`: `local_interpreter_315_path=/opt/homebrew/Cellar/python@3.15/3.15.2/Frameworks/Python.framework/Versions/3.15/bin/python3.15` plus its sha256. |
| CI use | `.github/workflows/ci.yml` and `tools/ci/tests/run_tests.sh` run only `tests/test_verify.sh`, which uses fixtures. CI never runs `verify.sh` against the real pin, so H1 does not show up in CI. |
| Assertion count | `assert_*` lines: 118 at fb86fc3 and 139 at 43b667b, so **21 new call sites**. The case-variant block (`:555-565`) runs 1 assertion on a case-sensitive filesystem and 3 on a case-insensitive one. That gives 113 + 20 = **133** on case-insensitive APFS, matching the coordinator, and **131** on a case-sensitive filesystem such as ubuntu-latest. Static only. |

## Status of fb86fc3 findings

| Earlier finding | Status | Basis (43b667b) |
| --- | --- | --- |
| **L1**: a recorded-path build reporting another version is skipped while another pinned build exists | **Fixed.** | Identity is decided before the probe (`verify.sh:416-449`). When `_baseline_here=1` and `_ver != PIN_VERSION`, the run calls `bad` and sets the sticky state `recorded build changed version` (`:472-481`). The test (`test_verify.sh:494-510`) has a stub reporting 3.16.0 at the recorded path plus a pinned `python3`, and expects exit 1 with the specific state. |
| **L2**: an unresolved and unprobeable candidate bypasses fail-closed | **Fixed (broadened).** | `:423-427` fails any candidate with `RESOLVED_OK=0` whenever a recorded sha256 exists, before the probe. Test `:512-530` uses a chain through `chain1` with realpath and readlink removed. The rule now also fails unrelated unresolved symlinks, such as a symlinked Python 2. That is conservative, and the docs (`PYTHON_TOOLCHAIN.md:240-242`) state it. |
| **N1**: case-insensitive volumes and missing or non-directory intermediates | **Fixed for intermediates.** Case folding is **replaced by a `stat` identity check** whose missing-file branch causes H1. | `canonical_path:345-350` now applies `-d` to every non-final, non-link component, which matches realpath for `/x/missing/..` and `/x/file/..`. Trailing `.`/`..` after a file is also rejected because `_cp_work` is non-empty. Harness tests `:768-772`. |
| **N2**: broken/loop wording | **Fixed (wording).** | The docs and README now say that a discovered broken or looping link is not executable and is skipped, and that an explicit `--python` to one fails the run. This matches `consider_candidate` (`-x`) and `check_interpreter`'s `bad "not executable"`. |
| **N3**: sticky `compared` hides a later fail-closed reason | **Fixed in code.** The test does not exercise it (see N2 below). | `set_digest_failure` (`:282-289`) overrides `compared` and keeps the first failure. |
| **N4** (evidence row and `WORK` guard) | Evidence row updated to base fb86fc3 and 133. `WORK` guard not rechecked (out of the changed lines). | — |

## Findings (ranked)

### H1: High. A recorded path that does not exist makes every discovered interpreter fail with "equivalence undetermined"

In `check_interpreter` (`verify.sh:429-447`), when `_real != _rec_path` the code
calls `file_identity` on both paths. `file_identity` returns failure when the
file does not exist (`:365`, `[ -e "$_f" ] || return 1`). Any failure in either
call goes to the else branch. That branch calls `set_digest_failure "not
compared (equivalence undetermined)"`, emits `bad`, and returns 1 **before the
version probe**.

The committed pin records a Homebrew Cellar path that exists only on the
recording Mac. These hosts all lack that file:

- every other host: Linux, Windows, another Mac, or a Mac without Homebrew
  python@3.15 3.15.2;
- this Mac after `brew upgrade` moves the Cellar directory to `3.15.x`.

On those hosts **every** discovered candidate fails, whether it is
`/usr/bin/python3`, a uv or pyenv 3.15.2, or an unrelated 3.9. `verify.sh`
without `--no-interpreter` therefore always exits 1 there. A valid pinned
interpreter at a genuinely different path can never pass.

At fb86fc3 the same input gave `not compared (different path)` with a visible
warning and exit 0. This contradicts the documented contract:

- `PYTHON_TOOLCHAIN.md:230-231`: "genuinely different paths remain warnings".
- `PYTHON_TOOLCHAIN.md:243-244` and README rule 8: "An interpreter at a
  genuinely different path is reported as a version match but left `NOT
  RECORDED`".

The failure message also misdiagnoses the cause. The docs attribute this state
to "`stat` is unavailable", and the message says sameness "cannot be
determined", but here `stat` works and the answer is certain: a file that does
not exist cannot be the candidate.

**Test gap:** every new fixture keeps the recorded file present. In
`other-build` (`test_verify.sh:392-421`), `fake-a` exists. In
`equivalence-undetermined` (`:567-583`), `stat` is removed instead. No test
covers a recorded path that is absent while `stat` is available, so the
coordinator's 133/133 cannot catch this.

**Valid alternatives:**
1. Before the identity comparison, if `[ ! -e "$_rec_path" ] && [ ! -L
   "$_rec_path" ]`, set `_baseline_here=0` and let the candidate continue to
   the existing "different path" warning. A distinct, non-sticky state such
   as `not compared (recorded path absent)` would make this visible under
   `--quiet`.
   - If the project wants a vanished baseline on the recording host to fail,
     that needs an explicit opt-in, such as `--require-baseline`. The docs
     deliberately rule out host identity as the signal.
2. Reserve "equivalence undetermined" for the case where both paths exist and
   no identity primitive is available. Before giving up, try `[ "$_real" -ef
   "$_rec_path" ]`. The `test` builtins of dash, bash, ksh, zsh and busybox
   all support it, so `stat` is needed only as a fallback.
3. Add regression tests:
   - recorded path absent, `stat` present, other pinned candidate → exit 0
     with a "different path" or "absent" warning;
   - the same under `--quiet`.

### L1: Low (pre-existing). A recorded path replaced by a symlink hides the change

`file_identity` uses `stat` without `-L`. BSD `stat -f` and GNU `stat -c` both
lstat by default. Suppose the file at `_rec_path` is replaced by a symlink to
another 3.15.2 build `X` with different bytes. The canonical `_real` of any
candidate is `X`, which is not equal to `_rec_path`. The lstat identity of the
link differs from `X`'s inode, so `X` is warned as "different path" and the run
passes. The recorded build was really replaced, but nothing fails.

fb86fc3, which compared strings only, behaved the same way, so this is not a
regression. It does contradict the new comment "a recorded baseline belongs to
its canonical path, whatever bytes … now sit there".

**Fix (optional):** if `[ -L "$_rec_path" ]`, the recorded canonical path is
no longer canonical. Fail with `recorded build changed` or a similar state.

### N1: Nit. The `stat -f` fallback on GNU systems is a filesystem query

If GNU `stat -c` ever failed on an existing file, `stat -f '%d:%i'` would print
free inodes and the filesystem ID. That string is non-empty and the same for
any two files on one filesystem, so two different files would compare equal.
In practice `-c` does not fail on GNU or busybox for an existing path, so this
is not reachable today. It becomes moot if `-ef` is tried first, or if the BSD
branch is selected by `uname`.

### N2: Nit. The "fail-closed reason wins over compared" test never reaches `compared`

`failure-after-compared` (`test_verify.sh:585-601`) creates
`pathbin/python3.15` with `cp`, which gives a new inode. With `stat` present,
that candidate is a *different path*, not the baseline. The state before the
unresolved `python3` is therefore `not compared (different path)`, which is not
sticky. The final assertion would pass even without `set_digest_failure`'s
override. To exercise the precedence, put the recorded file itself, or a hard
link to it, first on PATH.

### N3: Nit. The assertion count depends on the host

On a case-sensitive filesystem the suite yields 131, not 133 (see Checks).
The docs' "133 assertions" row is accurate for this Mac only. Linux CI will
report 131.

### N4: Nit. Summary precedence can still name a secondary cause

A digest mismatch at the recorded path leaves the state at `compared`, since a
mismatch is not a "failure state". A later unresolved candidate then replaces
it with `not compared (unresolved path)`. Both `[fail]` lines are printed, so
only the one-line summary under-reports the root cause.

## What I judge correct (static)

- Identity before the version probe correctly closes L1 for both a changed
  version and an unprobeable build. The `changed version` path still records
  the observed digest.
- The intermediate `-d` check in `canonical_path` matches realpath for
  missing, non-directory, and trailing `.`/`..` components. Symlinked
  intermediates are still handled by the `-L` branch first.
- The `stat`-based identity correctly treats case variants and hard links as
  the recorded file **when both files exist**, and fails closed when no
  identity tool exists.
- When the fallback resolver has no realpath, a hard link elsewhere to the
  recorded inode is compared, not warned. That is the stricter outcome.
- Every new failure path uses `bad` plus a sticky, specific state, so
  `--quiet` cannot hide it. `set_digest_state` can no longer overwrite a
  failure, including through the "no local interpreter found" and "no
  pinned-version interpreter" endings, which now go through it.
- The new regression tests are hermetic (restricted PATH, fixture-local
  links) and, except for N2, test what they name.

## Verdict

**Fail: H1 blocks.** 43b667b fixes all of my fb86fc3 residuals (L1, L2, N1,
N2, N3) in code. However, the new `stat` identity step treats a nonexistent
recorded path as an undeterminable equivalence. With the committed
Homebrew-Cellar baseline, `verify.sh` then exits 1 for **every** interpreter
on any host or install where that exact path is absent. That is the documented
"different path → warning" case, and the change regresses it from a warned
PASS to a hard FAIL with a misleading message. CI does not show this because
CI runs only the fixture suite, and every fixture keeps the recorded file
present.

Smallest fix: treat an absent (non-existent, non-link) recorded path as
"different path", try `test -ef` before `stat`, and add the missing absent-path
regression test. L1 and the nits can follow.

## Limitations

- Every conclusion above is static. I did not run `verify.sh` or the suite, and
  did not reproduce H1. My trace of H1 is `verify.sh:429-447` together with
  `file_identity:363-371` and `pin/checksums.txt:21`.
- I could not check whether the recorded Cellar file exists on this Mac
  (`ls` outside the workspace was refused). H1 does not depend on that.
- The coordinator's 133/133 × sh/bash/dash is accepted as the dynamic baseline
  and is consistent with my static count on a case-insensitive volume.
