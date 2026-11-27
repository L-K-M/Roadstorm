# Roadstorm M0 CI repair review: `e46f396470b8da7721e1101da6540ffe1e5ed1f5`

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, in the Claude Code harness. That identity comes from my own session; I have no separate CLI provider log. I used no subagents, helpers, branches, worktrees or clones.
**Base:** `037bff0664d55eb8493d0e984a7e7dc05544001f`
**Scope:** `tools/ci/ci.sh`, `tools/ci/lib/common.sh`, `tools/ci/tests/run_tests.sh`; the README and `ci.yml` for integration only.

## Verdict: **pass** for the scoped CI repair

The candidate fixes every 037bff0 finding that blocked or was in scope, from both the Opus and Sol reviews. I found no consequential regression in this scope. Six minor findings or nits remain (m1, m2, n1–n4 below); none blocks.

This verdict does not cover:
- target-platform launch, rights, or whole-M0 acceptance;
- the M1 lab files that are in the same diff range.

## Provenance and limits

- **Exact snapshot.** `git hash-object source/<f>` equals `git rev-parse e46f396:<f>` for all five files:
  - `ci.sh` `9e17586`
  - `common.sh` `4946bb7`
  - `run_tests.sh` `2bace09`
  - `README.md` `ec62195`
  - `ci.yml` `8376fc1`
- **Changed scope.** Only `ci.sh`, `common.sh` and `run_tests.sh` changed in the CI scope (48, 91 and 261 changed lines). The README and `ci.yml` are unchanged.
- **Plan mode was active, so I ran nothing that writes.**
  - I did not run `run_tests.sh`, Godot or any probe that writes files.
  - I could not write `result.json`. The report file is at `/Volumes/PaseoData/TrueNAS/paseo-home/.claude/plans/you-are-the-mandatory-agile-meteor.md`, which is outside the review directory.
- **Supplied evidence, which I did not reproduce:**
  - the coordinator's macOS run: 264/264, plus sh/dash syntax checks and actionlint;
  - the worker's sh and dash runs: 264/264 each;
  - hosted run 46049772897.
- **Hosted log, as I read it:**
  - It checked out `e46f396…` (lines 101–119).
  - The export-preparation self-test reported `262/262` and `[ci-selftest] PASS` (:347–348).
  - The validate self-test reported `176/176`.
  - ffmpeg and actionlint are unavailable on the runner. That plausibly explains 262 hosted versus 264 on macOS.
  - The log shows only the last 8 case lines. The individual results of the new cases on Ubuntu are therefore not visible; only the summary covers them.

## Commands I ran (all read-only)

1. **Syntax:** `sh -n` and `dash -n` on `ci.sh`, `common.sh` and `run_tests.sh`. All six passed.
2. **Lint:**
   - `actionlint .github/workflows/ci.yml` passed.
   - `shellcheck -s sh -S error` on `ci.sh` and `common.sh` returned rc 0.
3. **`dash` helper probe.** I sourced the candidate `common.sh`, replaced `python3`, `uname` and `ln` with functions, and fed input through `/dev/stdin`.
   - **Header check:** an exact header line returns 0. CRLF, a trailing space, a backslash in the id, and a `.` that must match literally all return 1. A header on a later line, not line 1, still returns 0 (see n1).
   - **Mechanism selection:**
     - Linux with broken Python selects `lnT` (rc 0).
     - Darwin with broken Python selects `none` (rc 1).
     - The selection now persists in the parent shell (cache fixed).
   - **`lnT` classification:** a failed `ln` with no occupant returns 2; with a file or directory occupant it returns 1.
   - **`none`:** returns 2.
   - **Python exit-code classification:**

     | Python exit | Return |
     | --- | --- |
     | 0 | 0 |
     | 17, 20, 21 | 1 |
     | 1, 2, 13, 18, 126, 127 | 2 |
4. **Write failure:** `if ! { printf a; printf b; } >&-` is detected by both `/bin/sh` and `dash`.
5. **Variable clobbering:** `ci_run_bounded` uses the globals `_rc`, `_pid`, `_watch` and `_limit`, and it now runs in the caller's shell through `ci_link_mechanism`. I found no conflicting use in `ci_export_build`, `ci_export_build_inner` or the `ci_init_report` call sites.
6. **Code reading:**
   - the full scoped diff;
   - `ci.sh:291-345`, `2025-2125`, `2177-2245`, `2385-2420`, `2470-2520`, and the dispatch tail;
   - `common.sh:54-118` and `1040-1240`;
   - the imports in `pack_inventory.py`;
   - `ci.yml:455-473`;
   - both historical 037bff0 reports.

## Requested points

| Point | Result | Where |
| --- | --- | --- |
| Native-Linux missing-linker case (prior Opus B1 / Sol 1) | **Fixed.** Four host-independent cases now cover: no mechanism (`uname`=Darwin stub), the Linux `ln -T` fallback with exact-inode and occupant checks, a broken `ln -T` failing fast with one `mktemp`, and broken Python on Linux. | `run_tests.sh:3550-3705` |
| GNU `ln -T` fallback | **Correct by reading.** It classifies after the failure: an occupant returns 1, anything else returns 2. A failing `ln` no longer retries 101 times. | `common.sh:1173-1210` |
| Exact report/header binding | **Fixed.** A whole-line match plus the bounded id alphabet is checked at both publication sites and again before PASS. A headerless inherited report is refused at both the outer and inner entry. The run then has no writer, lock or `attempts/`, and the report file is left byte-identical. | `common.sh:1115-1125`; `ci.sh:310`, `:2039`, `:2196`, `:2506`; tests at `:394-413` and `:3464-3507` |
| Failed body write | **Fixed.** The body file is removed and `ci_die` exits 2 before any link. There is **no test** for this (m1). | `common.sh:1077-1088` |
| Classification and caching | **Fixed** (probe 3). | `common.sh:1136-1210` |
| No package writer before the inventory capability check | **Fixed.** The check runs after publication and the lock-namespace checks, but before locks, scratch preparation and the writer. It probes exactly the top-level imports of `pack_inventory.py`. The test confirms `pin` still works via `ln -T` while the export is refused with `reason=inventory-python-unavailable` and leaves no writer, package or lock. | `ci.sh:317-338`, `:2232-2238` |
| Report deleted after publication | **Fixed.** The PASS step re-asserts the report. The "not a regular file" branch writes only to stderr, so nothing recreates the file. The outer path and the dispatch tail append nothing. The test checks that the report stays absent and that there is no `[ci:ok] export:` and no `result=pass`. | `ci.sh:2499-2510`; `run_tests.sh:3509-3548` |
| Final PASS ordering | **Fixed.** The `ci_ok` success lines are printed only after the verdict append succeeds. | `ci.sh:2510-2515` |
| Failure-path safety | **Preserved.** Early guards, lock prechecks and exact-destination publication are unchanged. New branches return `CI_FAIL` or call `ci_die`. Package upload is still gated by `if: success()`. | `ci.yml:467` |

## Ranked findings (none blocking)

- **m1 (minor, test coverage): the failed body write has no regression test.**
  - Location: `common.sh:1077-1088`.
  - The code is correct (probe 4), but the repository's bug-fix rule asks for a test.
  - Suggested test: a `mktemp` shim that returns a directory path. Expect exit 2, the "could not write the reserved report body" message, and no `*.txt` report.
- **m2 (minor, capability gap): no test runs the real GNU `ln -T`.**
  - Every fallback test uses an `ln` emulator backed by Python.
  - Hosted Ubuntu selects the `python3` mechanism.
  - The real coreutils path is verified only by reading.
- **n1 (nit): the header check accepts `attempt-id: <id>` on any line, not just the first.**
  - Location: `common.sh:1124`.
  - In-tree code cannot inject such a line: presets must be declared, newline outputs are refused, and the id alphabet is bounded.
  - Matching only `NR == 1` would make the check exact.
- **n2 (nit): stale message at the publication sites.**
  - Location: `ci.sh:2047-2048` and `:2205-2206`.
  - On rc 2 these still say "no atomic hard-link mechanism is available".
  - rc 2 now also covers EPERM, EXDEV and EACCES. The `ci_init_report` message was updated; these were not.
- **n3 (nit): the capability probe misses a lazy import.**
  - Location: `ci.sh:331`.
  - `pack_inventory.py:713` lazily imports `shutil`, which the probe does not import. It is a standard-library module.
- **n4 (residual, documented): narrow window before the PASS append.**
  - Location: `ci.sh:2499-2510`.
  - A file could be swapped between the check and the append, or replaced by a regular file with the same header. Both need a hostile process.
- **Carried forward:**
  - `ci.yml` does not require the new cases by name, and the hosted log shows only the tail.
  - The README (line 122) does not describe header binding, the early Python refusal, or the behavior when the report is deleted after publication. The existing README text is still accurate.

## Prior 037bff0 findings

- **Fixed:**
  - Opus B1 / Sol 1 (Linux test).
  - Opus M2 (`ln -T` retries).
  - Opus M1 (cache).
  - Opus M3 / Sol 2b (report deleted after publication). A documented race remains (n4).
  - Sol 2a (headerless inherited report).
  - Sol 2c (header write status ignored). It has no test (m1).
  - Sol 2d (success lines before the verdict).
  - Sol 3 (writer could run before the Python check).
- **Unchanged:** Opus N1 and N3. Opus N2 is carried forward.

## Recheck

None is required for this scope. If m1 or n2 is addressed:
1. Run the new body-write test.
2. Run the macOS `sh` and `dash` self-tests.
3. Run the hosted ubuntu-latest self-test on the new SHA.

**Coordinator invocation attestation:** First-party Claude CLI JSON `modelUsage.claude-opus-5-5.provider=firstParty` confirmed the exact model for this immutable e46f396 snapshot. The Sol review on the same SHA separately found reproducible defects, so this scoped Opus pass does not close the joint gate.
