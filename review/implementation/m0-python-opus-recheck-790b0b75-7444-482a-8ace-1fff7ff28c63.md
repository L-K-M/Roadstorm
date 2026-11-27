# M0.1 Python pin scoped recheck: Opus (job 790b0b75-7444-482a-8ace-1fff7ff28c63)

| Field | Value |
| --- | --- |
| Reviewer model / provider | Claude Opus 5.5 (`claude-opus-5-5`) / Anthropic, via Claude Code (non-interactive) |
| Date | 2026-11-27 |
| Candidate | `ab3ac754ce58f3ca9693064bf5888d51ee2813b0` (ab3ac75), as supplied |
| Base | `cc5dac9` (`cc5dac91ed89b934defdd6d1240e729791885ccb` per my prior report; **not re-resolved** here) |
| Inspected tree | `work/agents/790b0b75-7444-482a-8ace-1fff7ff28c63/snap` only |
| Prior report reread | `review/implementation/m0-python-opus-recheck-10a3535f-84e3-4362-854e-d5a42d24e4e6.md` (snapshot copy) |
| Not consulted | Any Sol report (current or earlier), coordinator notes, other jobs' directories |
| Scratch | `work/agents/790b0b75-7444-482a-8ace-1fff7ff28c63/scratch/` (created empty; nothing could be copied or run there) |
| Verdict | **Changes required** (low severity: contract and evidence wording plus a silent drift-gate skip). The fixes for the destructive `--record`, space/glob, `--no-interpreter` and `-I` findings look correct on static reading. **None of the dynamic behaviour was verified by this reviewer.** |
| M0 | Remains **open**. This review neither claims nor recommends acceptance. |

## Files inspected (read in full)

* `tools/python_pin/verify.sh` (661 lines)
* `tools/python_pin/tests/test_verify.sh` (487 lines)
* `tools/python_pin/README.md`
* `tools/python_pin/pin/python.txt` (keys), `tools/python_pin/pin/checksums.txt` (full)
* `docs/PYTHON_TOOLCHAIN.md` (full)
* `docs/PYTHON_TOOLCHAIN_EVIDENCE.md` §8 (incident note) and a grep for wording residues

## Commands run, results and limits

| Command | Result |
| --- | --- |
| `find …/790b0b75…/` and `find snap/tools/python_pin … -ls` | OK; inventory and sizes listed above |
| `grep` over the pin/checksum keys and the docs (incident, universal2, symlink wording) | OK; results cited below |
| `grep -c` of the assertion call sites in `test_verify.sh` | 74 call sites (see "Test-count claim") |
| `diff -r snap/tools/python_pin <repo>/tools/python_pin`; `diff snap/docs/PYTHON_TOOLCHAIN.md <repo>/docs/…` | no differences from the main checkout's **working tree** |
| `cat <repo>/.git/HEAD`, `refs/heads/main` | `main` is now `d415db12…`, **not** ab3ac75, so the diff above does not prove the snapshot equals ab3ac75 |
| `ls snap/.gitattributes`, `snap/tools/python_pin/.gitattributes` | neither exists |
| `mkdir -p scratch/tree` | OK (empty) |
| `cp -R snap/tools/python_pin scratch/tree/` | **refused** by the permission layer |
| `sh snap/tools/python_pin/tests/test_verify.sh` | **refused** (needs approval; none available non-interactively) |
| `shasum -a 256 snap/tools/python_pin/verify.sh` | **refused** |
| `git -C <repo> rev-parse ab3ac75 cc5dac9` | **refused** |

**Limits.** As in my prior job, this session could not execute any shell
script, hashing tool, interpreter or git command. Therefore:

* I **did not** run `test_verify.sh` under sh, bash or dash. The coordinator's
  report of 70 assertions under each shell is **unexecuted** here; I only
  checked that the number is statically consistent (below).
* I **did not** confirm that the snapshot is byte-identical to ab3ac75 or
  diff it against cc5dac9.
* I **did not** test `-I` against a real interpreter with a planted
  `platform.py`, the `set -C` behaviour of the shells, or a race.
* No GUI was opened, no secrets were read, nothing in Git was changed, and no
  source, asset, shared file or installed tool was edited. The only writes
  are this file and the empty `scratch/tree/` directory.

## Status of my prior findings (static reading of ab3ac75 snapshot)

| Prior | Status | Basis |
| --- | --- | --- |
| F1 spaces/glob word-splitting | **Fixed (static)** | Archives are kept in a newline-separated list (`verify.sh:573,580`) and iterated with `IFS=<NL>` and `set -f` (`:623-631`). Interpreter candidates go to a callback as a single quoted argument (`:217-239`). Newlines are rejected (`:122-126`). Only the `$HOME/.../cpython-3.15*` glob is unquoted, which is intended. Test: `test_verify.sh:271-299` (space + `*` dir, `--archive=` form). |
| F2 destructive `--record` | **Fixed (static)** | Any existing target is refused, including dangling links (`-e \|\| -L`, `:473`). That covers symlink and hard-link aliases, directories and FIFOs. Exact string overlap with the pin, digest, `--python` and `--archive` paths is refused (`:477-489`). The check runs again just before creation (`:503`), and `set -C` then makes `>` an exclusive create (`:507-549`). Bash and dash both open with `O_EXCL` when the path is absent; that is my knowledge of the shells, not a test. Tests: `:168-268`. |
| F3 global host digest gate | **Partially fixed**, see R1/R2 | The gate is now scoped to `local_interpreter_315_path` (`:338-349`). |
| F4 record format / `--no-interpreter` | **Mostly fixed**, see R3 | `--no-interpreter` now runs nothing during recording either (`:518-548`, test `:302-316`). Keys use `local_interpreter_<maj><min>`. |
| F5 Sigstore claim after a mismatch | **Fixed (static)** | The evidence block now prints only on a match (`:400-416`). The wording reads "published SHA-256 as recorded in pin/python.txt" (`:393`), and `PYTHON_TOOLCHAIN.md:212` says "not a live release-page fetch". Test `:391-404`. |
| F6 evidence binding / incident | **Partially fixed**, see R4 | The incident is now `PYTHON_TOOLCHAIN_EVIDENCE.md` §8. |
| F7 probes not isolated | **Fixed (static)** | `read_version` and `read_build` use `-I` (`:265-272`). The test only checks that `-I` is passed (`:355-365`), not that a planted module is ignored. |
| N1/N2 | not rechecked (outside this scope) | |
| N3 "universal2" | **Open**, see R6 | |
| N4 no `.gitattributes` | **Open** (nit) | Neither file exists. |
| N5 empty options / duplicate keys | Empty options **fixed** (`:560-594`, tests `:434-451`). Duplicate keys still resolve silently to the last one (`:137,144`); the tests now *depend* on this to override digests (`test_verify.sh:98,289`). | |

### Test-count claim

`test_verify.sh` has 74 assertion call sites. On a non-root run, the three
"mode 000 is readable here" skip branches (`:411,424,462`) and one arm of
`:472-477` are not taken. That leaves 74 − 4 = **70** assertions, which
matches the coordinator's figure. This is a static count only; I have not
seen a run.

## Findings (ranked)

### R1: Low-Medium. The contract says "never failed against another host's digest", but the gate is keyed by path, not by host
README rule 8 (`README.md:122-126`), `verify.sh:57-59` and
`PYTHON_TOOLCHAIN.md:225-226` all say that a different build "is never failed
against another host's digest". The code compares any interpreter whose
resolved path equals `local_interpreter_315_path`
(`/opt/homebrew/Cellar/python@3.15/3.15.2/.../bin/python3.15`, recorded on
`mac-studio-2026-32-1.home`). Another Apple Silicon Mac with Homebrew
`python@3.15` 3.15.2 has the same Cellar path. If its bottle (another macOS
bottle tag) or pour-time relocation differs, it gets
`[fail] interpreter sha256 changed` and exits 1. That is exactly the
cross-host case the docs say cannot happen. It fails closed (no false PASS),
but the stated contract is wrong.
**Fix:** either key the record by host as well (for example
`local_interpreter_315_host=` compared with `hostname`, or skip comparison on
any other host), or change the three statements to "per recorded path; a
same-path build on another machine is compared and may fail".
A test with the same path but a different host would pin this down.

### R2: Low. When the drift gate is skipped, it is silent under `--quiet` and absent from the summary
When the resolved path differs from the recorded path, the message goes out
only through `info` (`verify.sh:343-347`), which `--quiet` suppresses. The
summary line still says `PASS (local interpreter observations; …)`. This is
inconsistent with the empty-digest case, which uses `warn` (`:334`).
Realistic triggers:

* a Homebrew revision rebuild (`3.15.2_1/` path);
* a host without `realpath`, where the `readlink` fallback (`:288-290`)
  yields a relative or one-hop target that never equals the recorded
  absolute path.

In both cases the only local-change check is disabled without notice.
**Fix:** use `warn` for "different local build … NOT RECORDED", and add a
summary field such as `local digest: compared/not compared`. The fallback
should resolve to an absolute path, not raw `readlink` output.

### R3: Low. The record key and path claims do not hold for non-pinned versions
README `:71-74` and `PYTHON_TOOLCHAIN.md:242-243` say records "use the same
`local_interpreter_<major><minor>` keys as `pin/checksums.txt`" and store
"the resolved real binary … (not a launcher)".

* `checksums.txt:29-30` uses `local_interpreter_396_*` for 3.9.6, but the
  recorder emits `local_interpreter_39_*` (`verify.sh:537-540`).
* For `/usr/bin/python3`, `realpath` returns the 200 KB launcher itself,
  because it is a real file and not a symlink. The record therefore stores
  the launcher digest, while `checksums.txt:26-28` stores the Xcode framework
  binary.
* `<major><minor>` is also ambiguous in principle (3.1x vs 31.x).

This does not affect the pinned 3.15.2 line.
**Fix:** rename the 3.9.6 key to `local_interpreter_39_*`, or scope the claim
to the pinned version. State that macOS `/usr/bin/python3` records the
launcher.

### R4: Low. Evidence wording is stale or not bound to the candidate
* `PYTHON_TOOLCHAIN.md:299-301` still says "Tests create no symlinks or
  hardlinks". `test_verify.sh` now deliberately creates both, inside its
  private temp directory (`:208,221,234,246`; the header at `:7-9` says so).
  Reword the sentence so it covers the old integration tests only, or add
  the qualifier the test header uses.
* "Checks run and results" (`:295-321`) still cites job `9a09e936`'s logs
  from an earlier revision. It does not list `tests/test_verify.sh`, its
  shell matrix, or the candidate SHA it ran against. The 70-assertion
  sh/bash/dash result exists only as a coordinator report. Add a row that
  records the command, the shells, the assertion count, the exit status and
  `ab3ac754…`.
* README `:81-84` says the exclusive-create behaviour was "tested" on bash
  3.2 and dash. I found no test in `test_verify.sh` that exercises the race
  or noclobber path (all existence refusals are decided at `:473`). Cite
  where it was tested, or say "by shell semantics".
* `EVIDENCE.md` §8 is now adequate (cause, retained altered copy, fresh copy
  checked against the pinned SHA-256, offline Sigstore). It would be better
  if it stated the restored file's sha256 (`f74e1db0…0943`) explicitly.

### R5: Nit. The new `-I` makes a Python 2 `python` on PATH fail the whole run
`for_each_python_candidate` also probes plain `python` (`:223`). On a host
where that is Python 2.7, `-I` is an unknown option. `read_version` returns
nothing, `bad "cannot read a Python version"` sets RC=1, and the run FAILs
even if a correct 3.15.2 was found. This fails closed, but it is a new false
failure. Consider skipping (with `warn`) candidates that cannot be probed
once a pinned interpreter is found, or dropping bare `python`.

### R6: Nit. Leftover nits from the prior round
* "universal2" is still unsupported by the retained release-page row
  (`python.txt:66,73`; `PYTHON_TOOLCHAIN.md:93,162,186`). Cite the source or
  drop it.
* There is no `.gitattributes` (CRLF checkout fails closed with exit 2).
* `sha256_of` passes the path as an argument. A name starting with `-`, or
  one containing a backslash (GNU/Perl escape the output line with a leading
  `\`), fails closed with "cannot compute". `shasum -a 256 < "$_file"` would
  avoid both.
* `pin_get`/`digest_get` silently take the last duplicate key, and the
  tests rely on that.

## What I judge correct (static)

* Exit-code discipline: usage, an unsafe record target, a missing or
  unreadable pin or digest file, and a missing sha256 tool all exit 2. Check
  failures exit 1. A failing hash is never an empty pass (`:150-166`), and a
  hash must be 64 hex characters.
* A failed run still writes its record, but the record is marked as
  diagnostic (`:514-517`). Nothing is re-probed at record time.
* `--no-interpreter` with `--python` or `PYTHON_BIN` executes nothing
  (`:610-611`, and the record branch at `:518`).
* The scope text keeps three things separate: recorded publisher digest and
  Sigstore results, the per-run comparison against the *recorded* published
  digest, and local-build drift.

## Verdict

**Changes required (low severity).** On static reading, the in-scope
safety findings from cc5dac9 are fixed:

* destructive or aliased `--record` targets are refused;
* space and glob paths are handled;
* `--no-interpreter` executes nothing, including at record time;
* probes run with `-I`;
* hash and metadata failures fail closed.

Changes are still required because of R1–R4. The host-specific digest
contract is overstated (the gate is per path, not per host). The skip is
silent under `--quiet`. The record-key and test-evidence wording is
inaccurate or not bound to ab3ac75.

None of the dynamic claims are verified here: the tests, the 70 × sh/bash/dash
result, `-I` effectiveness, noclobber behaviour and snapshot identity with
ab3ac75. This reviewer could not execute anything in this session. M0
remains open.
