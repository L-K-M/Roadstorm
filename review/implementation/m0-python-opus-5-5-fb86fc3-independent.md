# M0.1 Python pin follow-up: independent Opus 5.5 review of fb86fc3

| Field | Value |
| --- | --- |
| Reviewer model / provider | Claude Opus 5.5 (`claude-opus-5-5`) / Anthropic, via Claude Code (non-interactive). No subagents, helpers or workflows. |
| Date | 2026-11-27 |
| Candidate | `fb86fc3a006a4c2351a9ca463fa04b6a1c2af4ba` (fb86fc3, "Fail closed on unresolved or broken Python baselines"), resolved with `git rev-parse` |
| Base | `d8cd39cbfe926ba5321f59b4cc1ada727fd44b08` (d8cd39c), resolved with `git rev-parse` |
| Scope | `tools/python_pin/**`, `docs/PYTHON_TOOLCHAIN.md`. In d8cd39c..fb86fc3 only `verify.sh` (139 lines changed), `tests/test_verify.sh` (153 lines changed), `README.md` and `docs/PYTHON_TOOLCHAIN.md` change (4 files, +302/−45). `pin/` is unchanged. |
| Source of truth | `git show fb86fc3:<path>` and `git diff d8cd39c fb86fc3 -- <scope>` (immutable Git objects only) |
| Earlier reports assessed | `m0-python-opus-5-5-d8cd39c-independent.md` (Opus, d8cd39c) and `m0-python-sol-recheck-d8cd39c.md` (Sol, d8cd39c) |
| Not consulted | The other model's fb86fc3 report, other workers' outputs, coordinator notes beyond the brief |
| Verdict | **Pass, with low-severity follow-ups.** All d8cd39c findings in scope are fixed. Two low residuals (L1, L2) and nits remain; none blocks. Dynamic behaviour was **not** executed by this reviewer (see Limitations). |

## Checks performed

| Check | Result |
| --- | --- |
| `git rev-parse fb86fc3`, `git rev-parse d8cd39c fb86fc3^` | Candidate and base resolve as above; `fb86fc3^` = `f69bfe9…`. |
| `git log --oneline d8cd39c..fb86fc3` | 7 commits; only fb86fc3 touches the scope (`git diff --stat` shows 4 files). |
| `git diff d8cd39c fb86fc3 -- <scope>` | Read in full. |
| `git show fb86fc3:tools/python_pin/verify.sh` lines 95–265, 342–480, 700–777 | Read: output helpers, `digest_get`, `sha256_of`, discovery, `set_digest_state`, `canonical_path`, `check_interpreter`, `check_interpreter_digest`, main flow and summaries. |
| External commands used by `verify.sh` (grep) | `sed tail dirname pwd mkdir date hostname uname readlink realpath` plus `shasum`/`sha256sum`. All are in `make_restricted_path`'s list, so restricted-PATH tests do not lose a needed tool. |
| Static assertion count | 118 `assert_*` matches − 3 definitions = **115 call sites**. 93 at d8cd39c + 22 new sites. With realpath present, the conditional "harness chain equals realpath" runs, and the 4-iteration `for _bad` loop adds 3 extra executions: 88 + 22 + 3 = **113**. That matches the coordinator's 113 per shell. **Static only.** |
| `realpath /USR/BIN/PYTHON3` (read-only probe) | Prints `/usr/bin/python3`: macOS `realpath` returns on-disk case. This is the basis for N1. |
| `mktemp -d`, `sh -n` on Git-object content, `sh -c` running `canonical_path` from the Git object | **Refused**: the permission layer requires approval, and none is available non-interactively. |
| `test_verify.sh` under sh/bash/dash, FIFO/noclobber probe | **Not run**: execution was blocked. I rely on the coordinator's independent 113/113 × sh/bash/dash for dynamic results. |

Nothing was written except this file. No source was edited, no Git state was changed, no agent or GUI was used, and no installed tool or shared file was modified.

## Status of earlier findings (d8cd39c → fb86fc3)

| Earlier finding | Status | Basis (fb86fc3 line numbers in `verify.sh`) |
| --- | --- | --- |
| **Sol #1 (Medium)**: the readlink fallback left `..`, followed one hop, so a drifted build behind `../` passed without realpath | **Fixed.** | `canonical_path` (about `:289-340`) walks components left to right from `/`. Each prefix is tested with `-L`. A link target is spliced before the unconsumed components and reprocessed from `/`, so links in parent directories, chains and `..` after expansion are handled physically. `..` pops one component of an already-physical prefix, which is correct. Hops are bounded (64), and the final target must exist (`-e`). Patterns are literal (`%%/*`, `#*/`), and values are quoted, so spaces, brackets and `*` survive. A relative input uses logical `pwd`, but every component is then re-tested with `-L`, so a symlinked cwd is still resolved. Tests reproduce Sol's case (`../spaces [literal]/stub python`, no realpath → compared; drift → exit 1), plus chained links, a directory link, and `..` after expansion compared to realpath. |
| Sol #1 remedy "fail when resolution is impossible and a baseline applies" | **Fixed.** | `RESOLVED_OK` (`:369-380`); `check_interpreter_digest` fails closed with `not compared (unresolved path)` when a digest is recorded and resolution failed (`:440-447`). Test: no realpath, no readlink, symlinked `--python` → exit 1 and the summary names the state; a direct regular file still resolves lexically → compared. |
| **Opus L1**: unprobeable build *at the recorded path* was skipped | **Fixed.** | `:387-398`: if `_real` equals `local_interpreter_<maj><min>_path`, the result is `bad` with state `recorded build unprobeable`; other unprobeable candidates still warn and skip. Test: recorded `python3.15` exits 1, another pinned `python3` exists, `--quiet` → exit 1, failure names the recorded build, summary state is specific. See L1 below for a sibling case not covered. |
| **Opus L2**: noclobber wording exact only for regular files | **Fixed (wording).** | README now says that an existing regular file or a link to one is refused, and that a FIFO or device planted in the window may be opened without truncation. This matches my earlier reading of bash/dash. The README says "Verified on bash 3.2 … and dash here". I could not re-run that probe, so I accept it only as the author's claim. |
| **Opus N1**: "canonical/realpath-resolved" wording held only with realpath | **Fixed (code and docs).** | The fallback is now a full resolver, and docs and README name it. See N1 below for a remaining case-folding divergence. |
| **Opus N2**: no leading-`-` hashing test; the `hostname` stub cannot fail for its reason; py2 test depended on host `python3` | **Fixed / clarified.** | A leading-dash test sources the extracted `sha256_of` and hashes `-dashname`. The `hostname` comment now says the stub "pins that claim" rather than implying host logic. The py2 test runs with a restricted PATH. |
| **Opus N3**: generic FAIL state when hashing fails | **Fixed.** | `not compared (digest unavailable)` (`:426-429`). |
| Sol #2/#3 (host semantics, record safety, odd names) | **Unchanged and still correct (static).** | `validate_record_target` / `record_digests` / `sha256_of` were not modified in this commit, apart from the new test. |

## Digest state and quiet

`set_digest_state` (`:269-278`) makes `compared`, `recorded build
unprobeable`, `not compared (unresolved path)` and `not compared (digest
unavailable)` sticky. Every non-`compared` sticky state comes with `bad`, so it
can only appear in a FAIL summary. A PASS summary therefore always states
`compared`, `different path`, `no recorded digest`, or the `--no-interpreter`
/ none states. Every new failure uses `bad` and every new skip uses `warn`; both
bypass `QUIET`. Only the hint lines (`info "  make realpath/readlink
available…"`) are hidden by `--quiet`, which is acceptable.

## Findings (ranked)

### L1: Low. A recorded-path build that now reports a *different* version is still not checked when another pinned build exists
L1 at d8cd39c was fixed only for the *unprobeable* case. The sibling case
remains. Suppose the build at `_real == local_interpreter_315_path` runs but
reports, for example, `3.15.3` or `3.9.6`. `check_interpreter` then takes the
"version does not match the pin" branch (`:413-418`): it prints `info` only,
sets no state and calls no `bad`. If any other 3.15.2 interpreter is
discovered, for example a uv or pyenv build or `--python` absent with
`python3` elsewhere, the run reports **PASS** with `local digest: not compared
(different path)`. Under `--quiet` the only line about the recorded path is
hidden, because it is `info`.

This exists at d8cd39c too, so it is not a regression. But it is the same
"recorded baseline goes unchecked" class that the commit is meant to close, and
the docs' fail-closed wording invites the reader to assume it is covered. With
the Homebrew Cellar path (versioned directory), a different version at that
exact path means the file was replaced.

**Fix:** in the version-mismatch branch, if `RESOLVED_OK=1` and `_real` equals
the recorded path, call `bad` with a sticky state such as `recorded build
changed version`. Add a test that mirrors the unprobeable one, with the stub
printing `3.15.3`.

### L2: Low. An unresolved *and* unprobeable candidate bypasses the new fail-closed rule
The fail-closed check for unresolved paths sits in `check_interpreter_digest`,
which is reached only for a pinned-version candidate. When resolution fails
(`RESOLVED_OK=0`, `_real=$_py`) and the probe also fails, the
recorded-path test at `:394` compares the *raw* `$_py` with the canonical
recorded path. It does not match, so the candidate is warned and skipped. A
second pinned build at a resolvable path then yields PASS (`different path`).

Reaching this needs realpath *and* readlink missing, or realpath failing and
the fallback failing. The candidate must also be a symlink to the recorded
build, and that build must be broken. It is very narrow. Still, README rule 8
and `PYTHON_TOOLCHAIN.md` say that with a recorded baseline "the run fails
closed rather than reporting 'different path' for an unresolved input", and
this path contradicts that.

**Fix:** in the unprobeable branch, also fail when `RESOLVED_OK=0` and a
recorded `_path`/`_sha256` exists, or narrow the docs.

### N1: Nit. `canonical_path` is not `realpath`-equivalent on case-insensitive volumes or with nonexistent/non-directory intermediates
I ran `realpath /USR/BIN/PYTHON3` here and it returned `/usr/bin/python3`:
Darwin `realpath(3)` returns on-disk name case. `canonical_path` is lexical for
non-link components, so it would keep `/USR/...`, and a mismatch then becomes
`different path` (a warned PASS) rather than a comparison. Likewise
`/x/missing/../python3` or `/x/file/../python3` is accepted, because only the
final component is checked with `-e`, where realpath fails.

Both cases need realpath to be absent or failing. macOS 13+ ships
`/bin/realpath`, and PATH entries are normally in canonical case. The test
"harness applies .. after symlink expansion like realpath" is correct for
existing directories. **Fix (optional):** append `-d`-checks to intermediate
components, or document "equivalent to realpath on case-sensitive paths".

### N2: Nit. The "broken links, loops" wording describes `canonical_path`, not end-to-end behaviour
A discovered broken or looping link fails `[ -x ]` in `consider_candidate`
(`:252`) and is skipped *silently*. An explicit `--python` to one ends as "no
Python interpreter found" (FAIL). Neither reaches the new "cannot canonically
resolve" path. The outcome is safe (nothing passes on a broken link), but the
docs read as if loops and broken links produce the unresolved-path failure.
Consider "rejected by the resolver; such candidates are not executable and are
skipped or, if explicit, fail".

### N3: Nit. A sticky `compared` can label a FAIL caused by another candidate
Example: candidate A at the recorded path compares OK, then candidate B is
pinned but unresolved. The result is `FAIL (local digest: compared)`. The
`[fail]` line names the real cause, so this only affects the summary. Optional:
let fail-closed states override `compared`.

### N4: Nit. Evidence row and test-harness hygiene
- `PYTHON_TOOLCHAIN.md` evidence row: "base candidate `ab3ac754…`, this
  verifier repair applied" with **113** assertions. The 113-assertion suite
  only exists from fb86fc3 on, so the named base is stale (d8cd39c). As before,
  a document cannot name its own commit; the binding rests on the
  coordinator's independent run.
- `test_verify.sh`: `WORK="$(cd "$WORK" && pwd -P)"` has no `|| exit 2`. If it
  ever failed, `WORK` would be empty and fixtures would be created under `/`.
  It is unlikely because `mkdir -p` just succeeded, but the guard costs nothing.

## What I judge correct (static)

- `canonical_path` implements POSIX left-to-right physical resolution
  correctly for existing paths: relative, absolute and chained links, links in
  parent directories, `..` after expansion, bounded hops, and an existence
  check on the final path. It is safe for spaces, `[`, `*` and leading `-`
  (paths are always absolute).
- Resolution uses `realpath` first and the resolver second. Unresolved input
  with a recorded digest fails closed with a specific state. Unresolved input
  without a baseline is harmless and gives a visible warning.
- An unprobeable build at the recorded path fails closed. Unrelated
  unprobeable candidates are still skipped, and the run still fails if no
  pinned build exists.
- The digest state is specific in every FAIL path that the commit added.
  `--quiet` cannot hide any new failure or warning.
- The tests now avoid host `python3` dependence. They exercise
  realpath-less and readlink-less paths through a restricted PATH whose tool
  list covers every external command `verify.sh` uses. The static assertion
  count reconciles exactly with 113.
- Record safety, archive evidence gating, exit codes and odd-name hashing are
  unchanged and remain as previously judged.

## Verdict

**Pass, with low-severity follow-ups.** fb86fc3 fixes Sol's medium finding
(full canonical fallback, fail-closed on unresolved paths) and all of the
d8cd39c Opus findings (L1, L2, N1–N3) in scope.

- **L1** (recorded path now reports a different version while another
  pinned build exists → PASS) is the one residual I would fix next. It is
  pre-existing and narrow, but it is the same baseline-bypass class.
- **L2** and **N1** are realpath-absent corner cases.
- **N2–N4** are wording and hygiene nits.

## Execution limitations

I could execute only `git rev-parse/log/diff/show`, `grep` on Git-object
content, and one read-only `realpath` probe. `mktemp -d`, `sh -n`, and running
the extracted `canonical_path` with `sh -c` all needed approval that a
non-interactive session cannot give. So the test suite, the
sh/bash/dash runs, the FIFO/noclobber claim, and the Sol reproduction were
**not run by this reviewer**. For those I rely on the coordinator's
independent 113/113 under sh, bash and dash in an isolated copy, which matches
my static count.
