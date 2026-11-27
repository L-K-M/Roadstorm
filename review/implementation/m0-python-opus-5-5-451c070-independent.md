# M0.1 Python pin follow-up: independent Opus 5.5 review of 451c070

| Field | Value |
| --- | --- |
| Reviewer model / provider | Claude Opus 5.5 (`claude-opus-5-5`) / Anthropic, via Claude Code (non-interactive). No subagents, helpers, workflows or GUI. |
| Date | 2026-11-27 |
| Candidate | `451c070b31edc46be61917af6ec6c0cdca35582c` (451c070, "Handle absent and replaced Python baselines safely"), resolved with `git rev-parse` |
| Base | `43b667b62ec5546c07fb8504b6cbef1b0eb824c7` (43b667b), resolved with `git rev-parse` |
| Commits in range | `d008cc7` and `c13779d` (review records only), `451c070` (the code change) |
| Scope | `tools/python_pin/**`, `docs/PYTHON_TOOLCHAIN.md`. Changed in scope: `verify.sh` (+72/−1 net), `tests/test_verify.sh` (+78/−2), `README.md`, `docs/PYTHON_TOOLCHAIN.md`. `pin/` is unchanged. |
| Source of truth | `git diff 43b667b 451c070 -- <scope>`. `git diff --stat 451c070 -- tools/python_pin docs/PYTHON_TOOLCHAIN.md` was empty, so for the remaining line ranges I read the working-tree copies, which are byte-identical to the commit in scope. Line numbers below refer to 451c070. |
| Prior reports assessed | `m0-python-opus-5-5-43b667b-independent.md` (my 43b667b review) and `m0-python-sol-recheck-43b667b.md` (Sol on 43b667b). |
| Not consulted | Sol's report on 451c070, and other workers' outputs. |
| Verdict | **Pass with low/nit residuals. Nothing blocks.** The blocking absent-baseline regression (my H1 / Sol #1) is fixed. The final-component symlink substitution (my L1) is fixed, and so are the GNU `stat -f` hazard (N1), the precedence test (N2) and the host-dependent count (N3). This was established statically; see Execution. |

## Execution

**Execution was blocked.** The permission layer in this non-interactive session
again refused `mktemp -d`, `git check-ignore`, and every compound shell command
(`;`, `&&`, pipes into `awk`). No approval could be given. Commands that did run
were `git rev-parse`, `git log`, `git diff` (full and `--stat`), `git show` of
the two prior reports, and single-file `grep`. Nothing from the candidate was
executed, and I did not create a private snapshot.

For dynamic results I rely on the coordinator's independent run: **148
assertions in each of sh, bash and dash** in a copied candidate. My static count
below matches that figure.

The only file written is this report. No source was edited, Git state was not
changed, and nothing installed or shared was touched.

## Checks performed (static)

| Check | Result |
| --- | --- |
| Full diff 43b667b..451c070 in scope | Read. |
| `verify.sh:250-612` | Read: discovery, `consider_candidate`, `set_digest_state` / `set_digest_failure`, `canonical_path`, `file_identity`, the new `known_absent`, `check_interpreter`, `check_interpreter_digest`. Also read `:107-111` (`info` is quiet-suppressed; `warn` and `bad` are not) and `:856-879` (the main flow). |
| Global-name collisions from the new helper | `known_absent` sets `_p`, `_cur`, `_rest`, `_c` and `_next`. `for_each_python_candidate` (`:233-234`) also uses `_p`, but reassigns it before each use and does not read it after the callback returns. The second loop's `for _path in …` list is expanded once, up front. No functional collision. |
| Committed baseline | `pin/checksums.txt:21`: `/opt/homebrew/Cellar/python@3.15/3.15.2/…/bin/python3.15`. Only the `local_interpreter_315_*` key is consulted (`PIN_MAJOR PIN_MINOR`). |
| Restricted test PATH | `make_restricted_path` (`test_verify.sh:76-84`) links `uname` and `stat`, so the new `uname`-gated BSD branch is reachable in the fixtures. |
| Assertion count | Starting from 133 at 43b667b on case-insensitive APFS: +1 (hard-link `compared` check), +3 (symlink-replaced block), +8 (absent-baseline loop: 4 call sites × 2 cases), +3 (inaccessible baseline, non-root). That gives **148** on this Mac and **146** on a case-sensitive filesystem. Both match the coordinator's figure and the updated evidence row. As root, the inaccessible block runs only its 1 skip assertion, so the totals are 146 and 144. |

## Status of earlier findings

| Earlier finding | Status | Basis (451c070) |
| --- | --- | --- |
| **H1 (Opus) / #1 (Sol)**: an absent recorded path fails every candidate with "equivalence undetermined" | **Fixed.** | `check_interpreter:498-503`: if `stat` of the recorded path fails *and* `known_absent` proves ENOENT/ENOTDIR through searchable parents, the run logs `info "… absent on this host; not compared"` and falls through to the normal probe. A version-matching candidate then gets the existing `different local build … NOT compared` warning and the `not compared (different path)` state (`:593-598`), and exits 0. An inaccessible but possibly present comparator still goes to the fail-closed `else` (`:509-515`). Tests cover a missing file and a missing parent, in both discovery and explicit `--python` modes (`test_verify.sh` absent-baseline loop), plus a mode-000 parent that fails closed. This is exactly the separation Sol asked for. |
| **L1**: a recorded path replaced by a symlink hides the change | **Fixed for the final component.** | `:491-497`: if `[ -L "$_rec_path" ]`, the run records the sticky state `recorded build path replaced` (added to both sticky lists, `:274`, `:286`), calls `bad`, and returns 1. This happens before the absent/identity logic, so a dangling link cannot pass as "absent". `_real` is always canonical, so it never string-equals a link, and the check is always reached. A replaced *intermediate* directory is handled differently; see L1 below. |
| **N1**: GNU `stat -f` is a filesystem query | **Fixed.** | `file_identity:370-378` tries `-f` only when `uname -s` is Darwin, `*BSD`, SunOS, AIX or HP-UX. For residual risk, see N1 below. |
| **N2**: the precedence test never reached `compared` | **Fixed.** | The test now hard-links the recorded file (`ln "$_target" …`), drops `--quiet`, and asserts `interpreter sha256 matches the recorded LOCAL observation` before the later unresolved failure. |
| **N3**: assertion count depends on the host | **Fixed (documented).** | The evidence row now says "148 … (146 on a case-sensitive filesystem)". |
| **N4**: the summary can name a secondary cause after a digest mismatch | **Open (pre-existing, unchanged).** | A mismatch at `:608` still leaves the state at `compared` without calling `set_digest_failure`. Both `[fail]` lines print, so only the one-line summary is imprecise. |
| Option 2 of my H1 fix (`test -ef` before `stat`) | Not adopted. That is acceptable: `stat` remains the only identity primitive, and when it is missing an existing comparator still fails closed. | — |

## Findings (ranked)

None of these findings is High or Medium.

### L1: Low. An intermediate component replaced by a symlink is not reported as "replaced", and `known_absent` can misclassify it

The new guard checks only `[ -L "$_rec_path" ]`, which tests the final
component. Two cases follow from replacing an intermediate directory (for
example `…/3.15.2/Frameworks`) with a symlink after recording:

- **The target is accessible.** `stat` of the recorded path follows the parent
  link, so identity comparison still works. If the substituted build is
  discovered, it is treated as the baseline and digest-compared, and a byte
  change fails. If it is not discovered, the run does not use it, and the run
  passes as "different path".
  - Impact: no bypass of the drift gate for a build the run actually uses.
  - The documentation scopes the "replaced" claim to the "recorded canonical
    path itself", so the docs are accurate.
- **The target is in a directory the user cannot search.** `known_absent`
  (`:411-416`) evaluates `[ -d link ]`. That test follows the link and fails
  with EACCES, then `[ -L link ]` is true, so the function returns 0 ("exists
  but is not a directory: ENOTDIR"). A possibly-present comparator is then
  classified as definitely absent. This contradicts the function's contract,
  and also the docs' "comparator may exist but cannot be inspected … fails
  closed".
  - Impact is near zero: a candidate could be that file only through a hard
    link outside the unsearchable directory, and the parent replacement must
    already have happened.

**Fix (optional):** in `known_absent`, return 1 (uncertain) when a non-final
component is a symlink. A canonical recorded path has no symlinks, so any
symlink means the path was altered. Alternatively, extend the "replaced" check
to any symlink component of `_rec_path`, reusing the `canonical_path` walk.

### N1: Nit. The `uname` allow-list includes platforms whose `stat` is not BSD-style

On SunOS (where `/usr/bin/stat` is GNU on Solaris 11), AIX and HP-UX, `stat -f
'%d:%i'` is either GNU filesystem mode or not supported. If GNU `-c` ever
failed there, the same pseudo-identity for every file on a filesystem could come
back.

I traced the consequence: a false equality only makes `_baseline_here=1`, which
then requires the version to equal the pin *and* the digest to match the
recorded value. So the error direction is a false failure, never a bypass.
Narrowing the list to `Darwin | *BSD | DragonFly` would remove the question.

### N2: Nit. Absence is invisible under `--quiet` and in the summary

The "absent on this host" line is `info` (`:503`), which `--quiet` suppresses.
The summary state is the generic `not compared (different path)`.

On the recording Mac, a vanished baseline therefore looks the same as an
unrelated host. One example is `brew reinstall`, which moves the build to
`3.15.2_1`: the gate downgrades from compare to warn with no specific signal.
This is the documented path-scoped design, and the generic `[warn] different
local build` line is still shown, so it is not a defect.

A distinct non-sticky state such as `not compared (recorded path absent)`, or a
`warn` instead of `info`, would make it auditable.

### N3: Nit. A message overstates certainty

The fail-closed `else` branch (`:513`) still says "recorded local baseline
**exists** but …". After this change it is also reached when existence is
unknown (a parent that cannot be searched). "May exist" would be truthful.

The symlink failure also repeats once per discovered candidate. That is
cosmetic, and the state is sticky.

### N4: Nit. Test gaps

- The ENOTDIR branch of `known_absent` (a regular file as an intermediate
  component) and the dangling-intermediate-symlink branch are untested.
- The symlink-replaced fixture uses an unrelated candidate. It does not use
  `--python "<recorded link>"` (the substituted build itself as the candidate).
  The code path is the same, so the fixture is adequate, but the direct case
  would document intent.
- The mode-000 fixture restores permissions only on normal completion. An
  interrupted run could leave a directory that the fixture cleanup cannot
  delete. This affects only private temporary directories.

### N5: Nit (doc wording)

The docs (`PYTHON_TOOLCHAIN.md:240-242`, README rule 8) say "if `stat` is
unavailable … the run fails closed". The code checks absence first, so a
definitely absent recorded path passes even without `stat`. That is the correct
behaviour, but the sentence reads as unconditional. Suggested wording: "if the
recorded path exists (or may exist) and `stat` is unavailable …".

## Regression and correctness checks (static)

- **Absent vs inaccessible.** `known_absent` returns 0 only for:
  - ENOENT under a searchable parent;
  - a non-directory intermediate (ENOTDIR), apart from the L1 symlink case.

  It returns 1 for an unsearchable directory on the walk, and for an existing
  or link final path. The `(a || b) && return 1` precedence on `:391` is
  correct in POSIX sh. As root, `-x` on directories is always true, which
  matches root's real access. The function uses only shell builtins (`test`,
  `pwd`), so missing external tools cannot change the result.
- **Changed version or build at the recorded path.** This is unchanged from
  43b667b and still decided before the probe.
  - A changed version gives `recorded build changed version`.
  - An unprobeable build gives `recorded build unprobeable`.
  - Same version with different bytes gives the `interpreter sha256 changed`
    failure.
  - The new absent branch is reached only when `stat` of the recorded path
    fails, so a present recorded build can never take it.
- **Hard links and case aliases.** When both files exist, the `stat`
  device:inode equality is unchanged. The hard-link test now proves the
  `compared` path. The case-variant test from 43b667b is unchanged and
  host-gated.
- **`stat` variants and missing tools.**
  - With no `stat`, or no `uname` on Darwin, and an existing recorded path, the
    run fails closed (existing test).
  - With no `stat` and an absent recorded path, the run passes as "different
    path" (correct; see N5).
  - With no `realpath`/`readlink` and a symlinked candidate, the run still
    fails closed (`:476-480`, unchanged).
- **Sticky state.** `recorded build path replaced` is in both sticky lists, so
  neither a later `compared` nor a later normal state can mask it. The first
  fail-closed reason is kept.
- **No new bypass found.** Every path that skips comparison leads to the
  existing visible `[warn] different local build` (unless the candidate's
  version differs, which is not a pinned match) or to a `bad`. The run still
  needs `FOUND_PINNED=1` to pass.

## Verdict

**Pass, with low/nit residuals (L1, N1–N5; N4 from 43b667b remains open).**
451c070 correctly separates a definitely absent baseline (warned, not compared,
exit 0) from an inaccessible or indeterminate one (fail closed). It fails closed
when the recorded canonical path has become a symlink, and it fixes the
remaining 43b667b nits. The tests target the new branches. The documented and
coordinator-observed count of 148/146 matches my static count. Nothing I found
lets a changed build that the run actually uses pass the drift gate.

## Limitations

- Every conclusion above is static. I did not run `verify.sh` or the test suite
  and reproduced nothing; scratch creation and compound commands were refused.
  The dynamic evidence is the coordinator's 148 assertions in each of
  sh/bash/dash, which I did not observe directly.
- I did not test behaviour on Solaris, AIX, HP-UX, BusyBox or MSYS. The `stat`
  and `uname` reasoning for those systems comes from documented tool behaviour.
- I did not check whether the recorded Cellar path exists on this Mac. No
  finding depends on it.
