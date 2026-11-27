# M0.1 Python pin follow-up: independent Opus 5.5 review of d8cd39c

| Field | Value |
| --- | --- |
| Reviewer model / provider | Claude Opus 5.5 (`claude-opus-5-5`) / Anthropic, via Claude Code (non-interactive). No subagents or helpers. |
| Date | 2026-11-27 |
| Candidate | `d8cd39cbfe926ba5321f59b4cc1ada727fd44b08` (d8cd39c), resolved with `git rev-parse` |
| Base | `ab3ac754ce58f3ca9693064bf5888d51ee2813b0` (ab3ac75), resolved with `git rev-parse` |
| Scope | `tools/python_pin/**` and `docs/PYTHON_TOOLCHAIN.md`. In this range only `verify.sh`, `tests/test_verify.sh`, `README.md` and `docs/PYTHON_TOOLCHAIN.md` change; `pin/` is unchanged. |
| Source of truth | `git show d8cd39c:<path>` and `git diff ab3ac75 d8cd39c -- <scope>` |
| Prior report assessed | `review/implementation/m0-python-opus-recheck-790b0b75-7444-482a-8ace-1fff7ff28c63.md` (the Opus report on ab3ac75), read from the d8cd39c tree |
| Not consulted | Any Sol report (including the current d8cd39c one), other workers' outputs, coordinator notes beyond the brief |
| Verdict | **Pass, with low-severity follow-ups** (L1 and L2 below are recommended but not blocking). The dynamic behaviour is **not verified** by this reviewer; see "Checks". |

## Checks performed or blocked

| Check | Result |
| --- | --- |
| `git rev-parse d8cd39c ab3ac75 HEAD` | Both SHAs resolve as above. `HEAD` is now `e926b15…`, not the candidate. |
| `git diff --stat d8cd39c -- tools/python_pin docs/PYTHON_TOOLCHAIN.md` | Empty: the live checkout's in-scope files match the candidate. I still read only git objects. |
| `git log ab3ac75..d8cd39c`, `git diff ab3ac75 d8cd39c -- <scope>` | Only d8cd39c touches the scope (4 files, +206/−64). |
| Full read of `verify.sh` (687 lines) and the changed and boundary parts of `test_verify.sh` at d8cd39c | Done; this is the basis for the findings below. |
| `pin/checksums.txt` keys at d8cd39c | `local_interpreter_315_*`, the legacy `_396_*`, and `_313/_311/_312_*` |
| Static assertion count | 96 `assert_*` matches − 3 function definitions = **93 call sites**. A non-root macOS run skips the three "mode 000 is readable" branches, the Windows odd-name arm and one arm of the `observed.txt` if/else: 93 − 5 = **88**. That matches the coordinator's 88 per shell. **Static count only.** |
| `git archive` into an ignored `work/agents/...` snapshot, and `mktemp -d` in `/tmp` | **Refused** by the permission layer (approval required; none available non-interactively). |
| `git show … \| dash -n` (syntax only, no writes) | **Refused** (approval required). |
| Running `test_verify.sh` under sh/bash/dash, a real `-I` probe, the noclobber race | **Not run**: execution was blocked. |

Nothing was written except this file. Nothing in Git was changed, no source
was edited, no GUI was used, and no installed tool or archive was touched.

## Status of prior findings (ab3ac75 report → d8cd39c)

| Prior | Status | Basis (d8cd39c line numbers) |
| --- | --- | --- |
| R1: contract said "never failed against another host's digest" | **Fixed (wording).** The contract is now honestly per exact path, not per host. | README rule 8; `PYTHON_TOOLCHAIN.md` §installed interpreter; `verify.sh:58-61`. The code matches: comparison happens iff `_real` = `local_interpreter_315_path` (`:357-369`); `hostname` is used only for display (`:530,627`). The new test (`test_verify.sh:405-435`) covers same path/unchanged → compared, a fake `hostname` → still compared, and changed bytes → exit 1. The `hostname` stub proves little, because the code never consults it, but the claim holds by inspection. |
| R2: silent skip under `--quiet`, absent from the summary | **Fixed.** | The different-path message is now `warn` (`:363`, not gated by `QUIET`, `:105`). `LOCAL_DIGEST_STATE` appears in both PASS and FAIL summaries (`:676-684`), with states compared / not compared (different path / no recorded digest) / skipped / no interpreter / no pinned version. "compared" is sticky across candidates (`:352,362,369`). Tested quiet (`test_verify.sh:398-404`). The `readlink` fallback now makes a relative target absolute (`:298-304`); see N1 for what it still does not do. |
| R3: record key and path claims | **Fixed (wording).** | README and docs now say the recorder uses the drift-lookup convention, that `checksums.txt:29-30` keeps a legacy `_396_*` entry (confirmed), and that a real launcher such as `/usr/bin/python3` stays the launcher. That matches `realpath` semantics. The `<maj><min>` ambiguity (3.1x vs 31.x) remains theoretical. |
| R4: stale evidence wording | **Fixed.** | "These integration tests create no symlinks…" plus a parenthetical about the unit suite's private alias fixtures. README now says "By shell semantics … the bundled suite exercises the deterministic existence refusals, not this race". A new evidence row records sh/bash/dash, 88 assertions, base `ab3ac754…` "with this verifier repair applied". It cannot name d8cd39c, its own commit. The binding to d8cd39c rests on the coordinator's independent run, not on this document. |
| R5: Python 2 `python` fails the run under `-I` | **Fixed, but see L1.** | An unprobeable candidate is now `warn` + skip (`:311-319`). If no pinned interpreter is found, the run still fails (`:640-642`). Tested with a fake that rejects `-I` (`test_verify.sh:437-453`). |
| R6: odd names in hashing | **Fixed.** | `sha256_of` feeds stdin (`shasum -a 256 - <`, `:156-172`), which removes both the leading `-` problem and the backslash-escape problem. The result is still checked to be 64 hex characters. Tested for a backslash name only (`test_verify.sh:455-473`); there is no leading-`-` test. |
| R6: other nits | **Open (out of this fix set).** | "universal2" wording, no `.gitattributes`, and last-wins duplicate keys are unchanged. |
| Record safety (F2) | **Unchanged and still correct (static).** | `validate_record_target` / `record_digests` (`:490-573`) were not modified by this commit. |

## Findings (ranked)

### L1: Low. An unprobeable interpreter *at the recorded path* is now skipped, so a run can PASS without the drift gate
`check_interpreter` skips any candidate whose `-I` version probe returns
nothing (`verify.sh:311-319`). It does this before the path comparison and
regardless of whether `_real` equals `local_interpreter_315_path`.

Scenario: the recorded Homebrew build at
`/opt/homebrew/Cellar/python@3.15/3.15.2/.../python3.15` is altered or broken
so that it no longer runs. Another 3.15.2 build is also present, for example
a uv `cpython-3.15*` that `for_each_python_candidate` finds at `:239`.

* At ab3ac75 this was `bad`: the run reported FAIL.
* At d8cd39c the run reports **PASS** with a `[warn] cannot read a Python
  version from …` line and `local digest: not compared (different path)`.

The warning is visible, so this is not silent. But the summary's reason is
misleading: the recorded path *was* seen, and it is the recorded baseline
that went unchecked. That loosens the only local-change check, which is the
case it exists for.

**Fix:** keep the skip for other paths, but treat an unprobeable candidate
as `bad` when it is the explicit `--python`/`PYTHON_BIN` or when `_real`
equals the recorded `local_interpreter_<maj><min>_path`. Alternatively, set
a distinct state such as `not compared (recorded-path build unprobeable)`
that forces FAIL. Add a test: a recorded-path stub that exits non-zero plus
a second pinned stub on PATH must exit 1.

### L2: Low. The noclobber race wording is exact only for regular-file targets
README (residual limitation) says that under noclobber "the final creation
then fails instead of truncating, even for a symlink". In bash and dash,
`set -C` with `>` refuses an existing **regular** file, including through a
symlink. For an existing **non-regular** target (a FIFO or device, or a
symlink to one), both shells open it for writing without `O_TRUNC` instead
of failing.

This comes from my reading of the shells' redirection code and was **not
tested** here. The consequence is narrow:

* the race already requires a hostile writer in the parent directory;
* nothing is truncated;
* the deterministic pre-checks (`-e || -L`, `:493,523`) refuse such nodes
  when they already exist.

Suggested wording: "fails for an existing regular file or a link to one; a
non-regular node planted in the race window may be written to (not
truncated)".

### N1: Nit. The "canonical path" wording holds only when `realpath` exists
The docs say comparison happens when the "resolved canonical path" equals
the recorded one. `PYTHON_TOOLCHAIN.md` calls the stored path
"realpath-resolved" without qualification. Without `realpath`, the fallback
(`:292-304`):

* follows only one `readlink` hop;
* does not normalize `..`;
* uses the logical `pwd`.

The Homebrew chain `bin/python3.15 → ../Cellar/… → …/Frameworks/…` is
multi-hop, so without `realpath` it never matches and is reported `not
compared (different path)`. This now happens with a visible warning, so it
fails visibly rather than silently. A `realpath` failure also falls back to
the raw, possibly relative, `$_py` (`:294`).

**Fix:** qualify the docs ("when `realpath` is available; otherwise an
approximation that may report a different path"), or use `pwd -P` and a
bounded readlink loop.

### N2: Nit. Test coverage gaps
* There is no leading-`-` file-name test, although the `sha256_of` comment
  claims that case is handled.
* The `hostname` stub test (`test_verify.sh:418-428`) cannot fail for the
  reason it names, because `verify.sh` never reads the host identity.
* The PATH-based py2 test also probes whatever real `python3` and
  `/usr/bin/python3` the host has. They are only executed with `-I -c`, but
  the result depends on the host. For example, a real 3.15.2 elsewhere adds
  a different-path warning; it does not change the exit status.

### N3: Nit. The FAIL summary state can be generic
When a pinned interpreter is found but cannot be hashed (`:344-347`), the
FAIL summary says `local digest: not compared` with no reason. The run still
fails closed.

## What I judge correct (static)

* Every wording change requested in the ab3ac75 report (R1, R3, R4) now
  matches the code: the per-path baseline, the legacy key, the launcher
  behaviour, "by shell semantics", and the unit suite's private aliases.
* The quiet-mode visibility fix is real. `warn` bypasses `QUIET`, and both
  summary forms carry the drift-gate state.
* Stdin hashing removes the odd-name false failures and still enforces 64
  hex characters.
* `--no-interpreter`, record-target refusal, exit-code discipline and the
  archive evidence gating are unchanged from ab3ac75, which I previously
  judged correct.
* The coordinator's 88-assertion figure is consistent with a static count of
  the candidate's suite.

## Verdict

**Pass (low-severity follow-ups recommended).** The candidate addresses each
ab3ac75 finding in scope: path-comparison wording, quiet skip visibility,
odd names, interpreter probing, unchanged record safety, symlink/launcher
behaviour and documentation.

* **L1** is the one behavioural regression I would fix next: a broken
  build at the recorded path can be skipped when another pinned build
  exists. It is visible and narrow.
* **L2** and **N1–N3** are wording and coverage nits.

**Not verified by this reviewer:** any execution. This includes the 88
assertions under sh/bash/dash, `-I` effectiveness against a planted module,
noclobber or race behaviour, and syntax checks. The snapshot, `mktemp` and
`sh -n` attempts all required approval that was unavailable in this
non-interactive session.
