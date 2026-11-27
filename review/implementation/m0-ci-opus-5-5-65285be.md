# Roadstorm M0 CI scoped review of 65285be: report publication and the pre-engine `.ci-lock` guard

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party Claude Code CLI. I did no delegation and used no helpers or subagents.
**Date:** 2026-11-27
**Candidate:** `65285be7fd7cb3f56ba5e4687126377378b4cd85`
**CI comparison base:** `fed4f616fc9dbf60904ce4f622aef7d723de7b91`. The base is an ancestor of the candidate. 65285be changes only the four CI files.
**Scope:** `tools/ci/ci.sh`, `tools/ci/lib/common.sh`, `tools/ci/tests/run_tests.sh` and `tools/ci/README.md`, with their call sites and what they mean for `.github/workflows/ci.yml`.

## Scoped verdict: **changes required** (one P2)

- **Prior P1, exact-destination report publication: fixed.**
  - A directory or a symlink to a directory at the report name is now refused at all three sites: `ci_init_report`, the outer publication and the direct `__export-inner` publication.
  - Publication now fails closed, before any lock, scratch copy or engine export.
  - The new tests tell the old defect apart from the fix.
- **Prior P2, `.ci-lock` refusal before the engine starts: partly fixed.**
  - These calls are now refused before any Godot process runs: the direct `__export-inner` call, and the outer `export --export <preset> --out X.ci-lock` call in both lower and upper case.
  - **Gap (F1):** the outer form that passes `--mode` is not caught early. In that form the engine's `--version` probe still runs before the request is refused.
- **Not verified:**
  - the full shell selftest and anything that needs Godot;
  - any hosted CI run on 65285be;
  - native Windows behavior;
  - full M0 acceptance, including the M0.3 rights item.

## Provenance and limits

- The snapshot directory has no `.git` of its own. Git inside it resolves to the parent Roadstorm repository (`git rev-parse --show-toplevel` returns `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm`). I used only objects addressed by SHA.
- **The snapshot is exact.** For each file, `git hash-object <file>` equals `git rev-parse 65285be:<file>`:
  - `tools/ci/ci.sh`: `d851185…`
  - `tools/ci/lib/common.sh`: `d649af2…`
  - `tools/ci/tests/run_tests.sh`: `a126849…`
  - `tools/ci/README.md`: `4598d67…`
  - `plan/IMPLEMENTATION.md`: `f62f1b5…`
- **Plan mode was active for this session.** I wrote no files at all, not even in scratch, and ran only read-only, non-mutating probes. I did not run `run_tests.sh` or Godot. For the 249/249 result I rely on the coordinator's report and say so here; I did not reproduce it.
- **Read:**
  - the diff `git diff fed4f61 65285be -- ':/tools/ci'`;
  - `ci.sh` lines 160–420, 1684–1711 and 1870–2125, plus the PASS tail near 2400;
  - `common.sh` lines 88–113, 1036–1160 and 1320–1387;
  - the new and changed selftest blocks in `run_tests.sh`;
  - `ci.yml`: the `runs-on` lines, the `ci.sh` call sites and the required-needle list;
  - both prior fed4f61 reports.

## Commands run and evidence

1. **Syntax:** `sh -n` and `dash -n` passed on all three scripts.
2. **`os.link` refuses directory occupants** (Python 3.15.2, macOS): `os.link("/etc/hosts", "/private/tmp")` and `os.link(..., "/tmp")` both raised errno 17 (EEXIST), and nothing was created inside the directory.
   - Running the extracted candidate `ci_link_create_only` with a real symlink-to-directory destination (`/etc`, `/tmp`) returned `rc=1`.
   - Plain two-operand `ln` would create a link inside the directory instead (shown in my fed4f61 report).
3. **Early parser compared with the real parser** (`_ci_early_export_request` taken from the candidate blob and run under `/bin/sh`):

   | Call | Early guard sees `--out` | Real `cmd_export` |
   | --- | --- | --- |
   | `export --export p --out /x/a.ci-lock` | yes | accepted |
   | `export --export --mode debug p --out /x/a.ci-lock` | **no** | accepted, builds with mode=debug |
   | `export --export --mode=debug --preset p --out /x/a.CI-LOCK` | **no** | accepted |
   | `export --mode debug --export p --out …` | yes | rejected (`unknown mode '--mode'`) |
   | `__export-inner p release /x/a.ci-lock` | yes | accepted |

   I confirmed the real parser's behavior by running `cmd_export --export --mode debug p --out /x/a.ci-lock` with a stubbed `ci_export_build`: it was dispatched with `mode=debug`.

## Findings

### Implementation defects

**F1 (P2, confirmed): the early `.ci-lock` guard does not catch the `--mode` form, so the engine version probe still runs.**
- **Where:** `tools/ci/ci.sh:299-309`, the first loop of `_ci_early_export_request`.
- **Root cause:** the early parser expects `--mode` *before* `--export`. `cmd_export` (`ci.sh:1684-1708`) works the other way round: it takes the first argument as the subcommand and accepts `--mode` *after* it. The early parser also accepts an order the real parser rejects.
  - For `export --export --mode debug <preset> --out X.ci-lock`, the second loop reaches `--mode`, stops at `-*) break`, finds no `--out`, and returns without a result.
  - `ci_find_godot` (`ci.sh:412`) then runs `"$GODOT_BIN" --version`. Only after that does the canonical guard at `ci.sh:1984-1993` refuse the request.
- **Impact:**
  - **Still holds:** no lock file, scratch copy or package write, because the canonical guard runs before `_ci_lock_precheck`.
  - **Not met for this form:** the prior P2 requirement that no Godot process is invoked at all.
  - Every debug-mode export takes this path.
- **Fix:** make the early parser mirror `cmd_export`: take `$1` as the subcommand, then read `--mode`/`--mode=` options, then the build arguments. Alternatively, scan every argument after the `export` command for `--out`/`--out=`; the global `--out` has already been consumed at `ci.sh:180-188`.
- **Tests to add:** the seam case with `--mode debug` and with `--mode=debug`, asserting that `pub-seam.log` stays empty.

### Lower-priority implementation items

**F2 (P3): Python 3 is now required for every `ci.sh` command on macOS, and its absence costs up to 101 retries.**
- **Where:** `common.sh:1129-1145` (`ci_link_create_only`) and `common.sh:1066-1093`.
- `ci_init_report` runs for every command, including `pin`, `verify-engine` and the template commands, which are meant to work on a bare host.
- **When `python3` is missing on macOS, or is the macOS `/usr/bin/python3` stub on a host without the Command Line Tools:**
  - there is no `ln` fallback outside Linux;
  - the retry loop calls the helper up to 101 times, treating "the tool cannot link" the same as "the name is taken";
  - the run ends in `ci_die`.
- **This is not a gap in hosted CI:** every `ci.yml` job is `ubuntu-latest`, and the README documents the new dependency.
- **Suggested change:** check once for a working linker (for example `python3 -c ''`) and die immediately with a clear message, rather than retrying.

**F3 (nit): the publication-failure message names a cause that is not always the cause.**
- **Where:** `ci.sh:1964` and `ci.sh:2116`.
- The text "occupied by something that is not this attempt's report" also appears when no linker is available or the link fails with EPERM/EXDEV. The verdict is still a correct fail-closed result.

### Test and evidence gaps

**G1: the new selftests do tell the old defects apart from the fix, but they do not cover F1.**
- **Helper-level cases** (`run_tests.sh` around 308-380):
  - the new positive-control gate closes the vacuity I reported earlier: a helper that is missing or always fails now fails every case;
  - the directory and symlink-to-directory cases fail against two-operand `ln`, because they assert the directory is still empty.
- **`ci_init_report` directory and symlink-to-directory cases:** these also fail against the old `ln`.
- **Call-site cases** (outer and inner, directory and symlink-to-directory):
  - they assert a nonzero exit, `reason=report-publication-failed`, no `--export-*` call, no package and no `.ci-lock`;
  - the outer cases also assert that the seam log holds exactly one line, the `--version` probe;
  - against fed4f61 they fail on both the reason string and the empty-directory check.
- **The race case now shims `python3` rather than `ln`.** It still fails against the old code, because there was no fail-closed reason there.
  - Strictly, it now tests a pre-existing regular file: the candidate has no check-then-link window to race.
- **Namespace seam cases:** they cover lower case, upper case and direct inner, but not the `--mode` form (F1).

**G2 (carried forward, F3 of the fed4f61 review): hosted CI does not require the new cases by name.**
- `.github/workflows/ci.yml:381` names only the older namespace case.
- The new publication and seam cases are covered by the overall PASS of the engine-gated block whenever it runs, but they are not required by name.
- 65285be did not touch `ci.yml`.

### Optional improvements

- **O1:** run the helper as `python3 -I -c …` in `ci_link_create_only`.
  - Only builtins and already-loaded modules are imported, so there is no shadowing risk today.
  - `-I` would match the repository's isolation rule and ignore `PYTHONPATH` and user site packages.
- **O2 (carried forward):** the package upload still includes `*.ci-lock` files. `ROADSTORM_CI_REPORT` is still trusted from the environment.

## What I verified as correct in scope

- **Exact-destination linking:**
  - `ci_link_create_only` uses `link(2)` through `os.link`, which never follows or descends into the destination. That means EEXIST for a regular file, a dangling symlink, a directory or a symlink to a directory.
  - Off Linux it never falls back to a non-exact `ln`. On Linux without Python it uses `ln -T`.
  - All three sites use it: `common.sh:1086`, `common.sh:1160`, and through it `ci.sh:1964-1971` and `ci.sh:2113-2122`.
- **Publication fails closed:**
  - **Outer and inner paths:** on failure they log a structured verdict in the attempt's existing report and return `CI_FAIL`. This happens before the namespace and lock prechecks, before any `exec 9>>` and before the scratch copy.
  - **Normal handoff:** the worker receives the already-published name, so `src == dst` and no second link is made.
  - **PASS append:** the passing verdict is now checked when it is appended (`ci.sh:2403-2406`). An export can no longer exit 0 with its PASS unrecorded.
- **Early guard:**
  - **`__export-inner` argument order** matches the dispatcher (`ci.sh:2441`).
  - **The early refusal** creates only log and report evidence, and runs before `ci_find_godot` (`ci.sh:400` comes before `412`).
  - **The canonical guards** on both paths still check the main output and the derived sidecar separately, case-insensitively.
- **Hosted call sites:** `ci.yml` builds only on `ubuntu-latest`, which has `python3`. `manifest-windows.yml` does not run `ci.sh`. I make no hosted or native Windows claim.
