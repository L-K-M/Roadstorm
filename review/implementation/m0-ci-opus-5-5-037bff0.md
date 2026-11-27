# Roadstorm M0 CI corrective review of 037bff0: early `.ci-lock` guard and report publication

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, running in the Claude Code agent harness. That identity comes from my own session. I used no subagents, helpers, branches, worktrees or clones.
**Date:** 2026-11-27
**Candidate:** `037bff0664d55eb8493d0e984a7e7dc05544001f`
**Base reviewed implementation:** `65285be7fd7cb3f56ba5e4687126377378b4cd85`
**Scope:**
- `tools/ci/ci.sh`
- `tools/ci/lib/common.sh`
- `tools/ci/tests/run_tests.sh`
- `tools/ci/README.md`
- the self-test step of `.github/workflows/ci.yml`, for integration only

## Verdict: **changes required**

There is one blocking defect, and it is in the tests, not the guard. The new "missing hard-link mechanism" self-test assumes macOS behavior. On Linux it should fail, which would turn the hosted ubuntu-latest self-test job red.

The implementation corrections themselves pass static review and my no-write probes:
- the `--mode` and `--mode=` forms of the early guard;
- the newline marker;
- the asserted report source;
- the fast failure when no linker is available.

## Provenance and limits

- **Exact snapshot.** `source/` has no `.git` of its own. Git resolves to the parent Roadstorm repository, so I used only objects addressed by SHA. For each of the following files, `git hash-object <file>` equals `git rev-parse 037bff0:<file>`:
  - `ci.sh`: `95479e3…`
  - `common.sh`: `401d90b…`
  - `run_tests.sh`: `a897abd…`
  - `README.md`: `ec62195…`
  - `ci.yml`: `8376fc1…`
- **Corrective diff.** `git diff --stat 65285be 037bff0 -- tools/ci .github` touches only the four CI files (+342/−32). `ci.yml` is unchanged.
- **Plan mode was active.** I wrote nothing in `source/` or in scratch. I did not run `run_tests.sh`, Godot or any probe that writes files. My only write was the harness plan note outside the review directory.
- **Supplied evidence, which I did not reproduce:**
  - the coordinator's `sh -n`, `dash -n` and pinned-engine 257/257 result on its archive;
  - the worker's dash 257/257 result.
  - Both appear to come from macOS hosts. **Nothing on 037bff0 has run on hosted CI**, and I claim no hosted result.
- **Not claimed:** launch on any target platform, playability, rights clearance or whole-M0 acceptance.

## Commands I ran

1. **Syntax checks.** `sh -n` and `dash -n` on `ci.sh`, `common.sh` and `run_tests.sh` all passed (SYNTAX-OK).
2. **Early-parser probe (no writes).** Under `dash`, I sourced the candidate `common.sh`, then loaded `ci.sh:270-373` (`_ci_assert_publishable_report`, `_ci_early_emit_request`, `_ci_early_export_request`) and ran it on each call below:

   | Request | Early result |
   | --- | --- |
   | `export --export p --out /x/a.ci-lock` | `/x/a.ci-lock\|p\|release` |
   | `export --export --mode debug p --out /x/a.ci-lock` | `…\|p\|debug` (**prior F1 fixed**) |
   | `export --export --mode=debug --preset p --out /x/a.CI-LOCK` | `…\|p\|debug` (**fixed**) |
   | `export export --mode debug --mode release p --out=/x/a.Ci-Lock` | last mode wins, like `cmd_export` |
   | `export --export p --out a.ci-lock/` | out found; `ci_abs_path` resolves it to `…/a.ci-lock`, which is refused |
   | `__export-inner p release /x/a.ci-lock` | found |
   | outer or inner path with an embedded newline, or a trailing newline | `__ROADSTORM_CI_INVALID_OUTPUT_PATH__` (**fixed**) |
   | preset containing a newline | out is still line 1, so the guard is unaffected; only the report fields shift |
   | `export --export -dash --out /x/a.ci-lock` | empty (see N3) |

   I also checked `ci_abs_path /nonexistent/dir/../z.ci-lock`: it keeps the `.ci-lock` suffix. A missing parent does not make the early guard pass the request.
3. **Linker-mechanism probe (no writes).** Under `dash`, I sourced `common.sh` and replaced `python3` with a function that returns 127:
   - with `uname` reporting Linux, `ci_link_mechanism` returns **`lnT`**;
   - on real Darwin it returns `none`;
   - after a `$(ci_link_mechanism)` call, `_ci_LINK_MECHANISM` is still empty, so the cache never persists (see M1).
4. **Code reading:**
   - the corrective diff;
   - `ci.sh:160-462` (global parser, early guard, guard call at :450, `ci_find_godot` at :462);
   - `cmd_export` (:1734-1761), `ci_export_build` (:1939-2085), `ci_export_build_inner` (:2151-2190), the PASS append (:2467) and dispatch;
   - `common.sh`: `ci_die`, `ci_run_bounded` (:100), `ci_init_report` (:1042-1102), `ci_report` (:1105), `ci_link_mechanism` (:1125), `ci_link_create_only` (:1157-1183), `ci_publish_report_exclusive` (:1194), `ci_abs_path` (:1369);
   - the new test cases at `run_tests.sh:3260-3466`, the engine and template gates (:2193, :3988), and the summary;
   - `ci.yml:346-362`.

## Ranked findings

### B1 (blocking, test defect, hosted CI should go red): the new "missing hard-link mechanism" case assumes macOS

**Where:**
- `tools/ci/tests/run_tests.sh:3445-3466`
- `tools/ci/lib/common.sh:1131-1138`

**What happens:**
- The case adds a `python3` stub that exits 127 to the front of `PATH`, runs `ci.sh … pin`, and requires `rc == 2`, the message `no atomic hard-link mechanism`, and exactly one `mktemp` call.
- `ci_link_mechanism` falls back to `lnT` whenever `uname -s` is `Linux` and `ln` exists. That fallback is deliberate and documented in the README.
- On ubuntu-latest, GNU `ln -T` succeeds, the report is reserved, `pin` exits 0, and the case logs `-> no`.
- The summary then exits 1, so the `ci.yml:346-356` step (`sh tools/ci/tests/run_tests.sh … || exit 1`) fails.

**Why this applies to hosted CI:**
- The case sits inside the Godot- and template-gated block (`run_tests.sh:2193` through :3988). The hosted job installs the pinned templates and treats a skip marker as an error (`ci.yml:359-362`), so the case definitely runs there.
- Nothing in the file branches on `uname`.

**Evidence:** probe 3 above. This is a static derivation backed by the simulated-Linux probe. I did not run it on Linux, and macOS passes because it takes the `none` branch.

**Fix:** make the case match the platform.
- On Linux, also shadow `ln` so the case covers "neither mechanism", or assert the `lnT` success path there instead.
- Keep the `rc == 2`, one-`mktemp` assertion for the no-mechanism branch.
- See M2: shadowing `ln` with a stub that fails would currently show 101 retries, not a fast failure.

### M2 (minor, robustness): Linux `ln` without `-T` support still retries 101 times

**Where:** `common.sh:1133-1134` and `:1175-1177`

- `lnT` is chosen on `command -v ln` alone. If `ln -T` is unsupported (an older busybox) or fails with EPERM/EXDEV, it returns 1. That is treated as "name occupied", so the run makes 101 reservation attempts and then dies with "all 100 candidate names occupied".
- The same happens when `os.link` fails with EPERM/EXDEV on a filesystem without hard links. This is prior F3 carried forward.
- The README's new wording, "fails closed immediately (one attempt, not a retry loop)", holds only when no mechanism exists at all.
- **Impact:** fail-closed is preserved; only speed and diagnostics suffer.
- **Fix:** after a nonzero link, if neither `[ -e "$dst" ]` nor `[ -L "$dst" ]` holds, return 2. That treats it as a mechanism failure, not occupancy.

### M1 (minor, nit): the mechanism cache never persists

**Where:** `common.sh:1121-1140`, `:1164`

- `ci_link_create_only` calls `case "$(ci_link_mechanism)"`. The assignment happens in a command-substitution subshell, so `_ci_LINK_MECHANISM` stays empty in the parent (probe 3).
- Every link therefore re-runs a bounded `python3 -I -c 'import os'` probe.
- Each probe spawns a background watcher, and that watcher can leave an orphaned `sleep 10` (with `/dev/null` as stdio, so nothing hangs).
- **Impact:** correctness is unaffected. The comment "once per process" is false.
- **Fix:** call it once outside a subshell, for example `ci_link_mechanism >/dev/null; case "$_ci_LINK_MECHANISM" in`.

### M3 (minor, residual): a report deleted after publication can still be recreated without its header by the PASS append

**Where:** `common.sh:1109` (`>>"$CI_REPORT"`), `ci.sh:2467`

- The pre-publication skip that GPT's prior finding 3 described is fixed: an empty, missing or non-regular source, or an empty attempt id, now fails closed at both sites (`ci.sh:2013`, `:2170`).
- But if the published report is removed or replaced after publication, `>>` creates a new file without the header and the PASS line lands there.
- This needs another process to tamper with the evidence directory during the run; no `ci.sh` failure path causes it.
- **Optional fix:** before the PASS append, check `[ -f ] && [ ! -L ]` and the `attempt-id:` header, or hold an append descriptor opened at publication.

### N1 (nit): a non-regular or missing report source leaves no report-side FAIL record

**Where:** `ci.sh:298-301`

- This branch writes `ci_fail` to stderr only. That is correct, since there is nothing safe to append to.
- Worth a sentence in the README, which currently says "when the source still exists it records…". That sentence is accurate, so this is informational.

### N2 (carried forward): hosted CI does not require the new cases by name

- `ci.yml` was not changed in 037bff0, so its required-case list still lacks the mode, newline, invalid-source, no-attempt-id and no-mechanism cases.
- The overall PASS of the self-test covers them whenever the job runs.

### N3 (nit): early and real parsers disagree on a preset starting with a single `-`

- `ci_export_build` takes any first argument not starting with `--` as the positional preset. The early parser breaks on `-*`.
- A request such as `export --export -x --out a.ci-lock` would reach `--version` before the canonical refusal.
- No declared preset starts with `-` (`export_presets.cfg`: "macOS Apple Silicon", "Windows x86-64", "Linux x86-64"), so no valid request is affected today. Aligning the patterns (`--*`) would close it.

## Prior findings, each with a disposition

| Prior finding (65285be) | Status at 037bff0 |
| --- | --- |
| Opus F1 / Sol 1 (P2): the outer `--mode debug` and `--mode=debug` forms bypass the pre-engine guard | **Fixed.** The early parser now takes the subcommand first, then reads `--mode` options (`ci.sh:333-363`), matching `cmd_export` (:1734-1748). Probe 2 confirms both forms and both cases. Tests at `run_tests.sh:3260-3300` assert an empty seam log, no lock or package, and no `attempts/`; they would fail against 65285be. |
| Sol 2 (P3): a literal newline in the output path bypasses the guard (outer and inner) | **Fixed.** `_ci_early_emit_request` (`ci.sh:318-325`) emits a marker that `ci_early_namespace_guard` refuses with `reason=invalid-output-path` before `ci_find_godot` (:383-391, :450 before :462). This also covers a trailing newline. The outer and inner tests (`run_tests.sh:3303-3350`) tell the old and new code apart. |
| Sol 3 (P3): a missing report source or empty attempt id silently skips publication, allowing a headerless PASS | **Fixed** for the pre-publication window. `_ci_assert_publishable_report` (:291-311) runs at both sites, and `CI_REPORT` is always reassigned to the published name. Tests at :3354-3441 cover rm (outer), directory replacement (inner) and an empty id, all with no writer, no lock, no PASS and a nonzero exit. The tampering window after publication remains (M3, minor). |
| Opus F2 (P3): no Python means 101 retries | **Fixed** for "no mechanism" (returns 2, `ci_die` at `common.sh:1094-1096`) and for interpreter exit codes 126/127. **Partly open** for a present but non-working `ln -T` or a link refused with EPERM/EXDEV (M2). The test for this item is B1. |
| Opus F3 (nit): misleading "occupied" message | **Fixed** at the publication sites, which now give a separate message for rc 2. It still shows for EPERM/EXDEV (M2). |
| Opus O1: `python3 -I` | **Fixed** (`common.sh:1132`, `:1166`). |
| Opus G2 / O2: the new cases are not required by name in CI; `*.ci-lock` files are uploaded; `ROADSTORM_CI_REPORT` is trusted from the environment | **Carried forward**, unchanged (N2). Not a blocker. |
| Sol README item: inventory precheck wording | **Fixed.** The README now says the wrapper never pre-checks and the checker uses `O_EXCL`. |
| Exact-destination hard links (prior P1) | **Still correct.** `os.link` or `ln -T` at the exact name; same-name handoff is a no-op; no non-exact fallback. |

## What I verified as correct in scope

- **No valid reserved destination reaches the engine probe.** No valid outer `export --export [--mode …] <preset|--preset …> --out[=]X` or direct `__export-inner` request with a reserved `.ci-lock` destination (any case, absolute or relative, missing parent, trailing slash) reaches `ci_find_godot`. The guard at `ci.sh:450` runs before `:462`.
- **The canonical guards are unchanged.** They still run on both paths before `_ci_lock_precheck`, `exec` of lock descriptors, the scratch copy and the writer.
- **No failure path in `ci.sh` writes a package or a PASS line.** The PASS append is the last step, after inventory, and it checks its own status (:2467). The dispatch tail appends no verdict.
- **Without a linking mechanism, `ci_init_report` stops without creating a report.** It dies on the first attempt with exit 2.

## Scope of a future pass

Once B1 is fixed, this CI scope would pass on static review, provided that:
- the corrected self-test passes on hosted ubuntu-latest for the new SHA;
- no reviewer finds new defects.

M1, M2 and M3 are optional hardening.
