# Recorded probe evidence — N1 server-step follow-up, 27 November 2026, Apple M4 Max

Current evidence responding to
`review/implementation/m0-tick-opus-5-5-bdb0a98-independent.md`. Reported
candidate: `bdb0a9820b847d23628cce35a9070bb63ae17acd` (`bdb0a98`). The worktree
also carries the uncommitted Sol API-edge fixes from
`../../2026-11-27-apple-m4-max-jolt-api-edges/`; hashes distinguish the reported
candidate, that prior evidence and the follow-up files (P1).

Previous evidence directories are preserved unchanged. The earlier wait-guard
manifest was re-verified against its committed candidate: **34/34** entries of
`../2026-11-27-apple-m4-max-jolt-waitguard/manifest.sha256` match
`git show bdb0a98:<path>` byte-for-byte. The API-edge evidence has no commit
binding because those fixes were never committed, and later N1/Sol revisions
changed its source files, so its recorded manifest cannot be re-verified
against the current worktree; it is preserved unchanged as a historical record.
The wait-guard manifest verification above is the reproducible one.

## N1 measurement (independent dynamic body)

`tests/counting_body.gd` subclasses `RigidBody3D` and counts its own
`_integrate_forces` calls, i.e. actual physics-server integration steps.
`tests/n1_regression_entry.gd` drives one-tick cold-start warm-up, two
repeated 12-tick requests, a continuous 12-frame control and a frozen wait.

| Run | Warm-up steps | 12-tick request server steps | Continuous control | Frozen wait |
| --- | ---: | ---: | ---: | ---: |
| pristine `bdb0a98` | 0 | 11, 11 | 12 | 0 |
| fixed tree | 1 | 12, 12 | 12 | 0 |

N1 is confirmed on the original: freezing inside the coordinator's final
physics callback suppressed that tick's server step, so each 12-tick request
integrated only 11. After the fix, repeated 12-tick requests integrate exactly
12, matching the continuous control; frozen waits integrate nothing. The
one-step cold-start difference between the two rows is the shared activation
boundary artifact also present in the continuous reference and is documented,
not charged to the coordinator.

The same regression fails on pristine `bdb0a98` with exactly the two request
checks (`n1-regression-original-bdb0a98.txt`) and passes on the fixed tree
(`n1-regression-fixed.txt`). It also fails when the fix is reverted in the
combined mutation run.

## Setup and run policy

- Host: Apple M4 Max, macOS, arm64; Godot `4.7.2.stable.official.ed1daf0bf`;
  Python 3.15.2.
- Headless runs used isolated copies of `tools/tick_probe`; outputs went to an
  ignored private scratch directory. No GUI, no desktop, no installed-tool or
  repository-file mutation, no Git changes, no network. `HOME` was not
  reassigned; the contract runner redirects XDG caches/config/data and
  `TMPDIR`.
- The pristine comparison used `git archive bdb0a98 | tar -x` into the same
  private scratch area; only the committed counting/regression test files were
  added there to run the new regression.
- Every run was bounded to <= 30 s. Slowest: `--max-fps 60` structural (12 s),
  `compare_modes.py` (14 s), default structural (9 s).

Commands:

```sh
godot --headless --fixed-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural pacing=fixed
godot --headless --path <isolated> --script res://src/tick_probe.gd -- mode=structural pacing=default
godot --headless --max-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural pacing=max
python3 tools/tick_probe/tests/run_contract_tests.py --pacing fixed   --timeout 25 --expect-checks 76
python3 tools/tick_probe/tests/run_contract_tests.py --pacing default --timeout 25 --expect-checks 76
python3 tools/tick_probe/tests/run_contract_tests.py --pacing max     --timeout 25 --expect-checks 76
python3 tools/tick_probe/compare_modes.py --project <isolated> --timeout 25 \
    --expect-throughput-checks 4 --expect-trace-checks 2
godot --headless --fixed-fps 60 --path <isolated> --script res://tests/n1_regression_entry.gd
godot --headless --fixed-fps 60 --path <pristine-bdb0a98> --script res://tests/n1_regression_entry.gd
```

## Results

| Run | Checks | Exit | Wall |
| --- | --- | ---: | ---: |
| structural `--fixed-fps 60` (`pacing=fixed`) | 108/108 | 0 | 2 s |
| structural default (`pacing=default`) | 108/108 | 0 | 9 s |
| structural `--max-fps 60` (`pacing=max`) | 108/108 | 0 | 12 s |
| contract `--pacing fixed` | 76/76 | 0 | < 1 s |
| contract `--pacing default` | 76/76 | 0 | 7 s |
| contract `--pacing max` | 76/76 | 0 | 7 s |
| five suites concurrently (contract x3, structural, N1) | all pass | 0 | < 30 s each |
| `compare_modes.py` throughput + trace digests | 9 + 2 PASS | 0 | 14 s |
| N1 regression on fixed tree | 5/5 | 0 | < 1 s |
| N1 regression on pristine `bdb0a98` | 3/5 (expected) | 1 | < 1 s |
| exit-code self-test (`inject_failure=1`) | 5 total, 1 injected failure | 1 | < 1 s |
| combined mutation (4 fixes disabled) | 9 failures / 76 checks | 1 | < 1 s |
| runner SCRIPT ERROR detection | detected, exit 1 | 1 | < 1 s |
| runner expected-count enforcement (`--expect-checks 75`) | refused, exit 1 | 1 | < 1 s |

### Follow-up items addressed

- **N1** fixed as described above; new regression in `tests/`.
- **N2** backstop now rolls the probe car back to the last accounted tick-start
  pose before failing `motion_bound`, so the observation never shows uncounted
  partial motion.
- **N3** both runners detect `SCRIPT ERROR`/`Parse Error` (including a hung
  parse-error process captured at timeout) and enforce expected check totals
  via `--expect-checks` / `--expect-throughput-checks` /
  `--expect-trace-checks`; a `TESTS_TOTAL` missing or disagreeing with
  `TEST_RESULT` also fails.
- **N4/P4** mutation coverage now disables all four current fixes (deferred
  pause, zero-tick freeze-before-emit, cap-0 reset terminal, negative-first)
  and fails 9 checks including every targeted path. The N1 reproduction and
  measurement scripts live in `tests/` and are hash-bound, not referenced from
  an uncommitted scratch path.
- **P1** provenance names `bdb0a98` as reported candidate, records its blob
  hashes separately from current follow-up file hashes, and states which fixes
  were uncommitted.
- **P2** `provenance.json` is listed in `manifest.sha256`.
- **P3** payloads record `engine_pacing` (detected `Engine.max_fps`),
  `requested_pacing` and the resulting JSON/raw files differ between pacings.
- **L7** trace rows now carry per-tick x/y/z start/end positions and rotation,
  not only z.
- **L2/L8** from the earlier Opus report remain fixed in this tree (cap-0 reset
  starts truncated; negative validated before terminal fast paths), verified by
  contract/api-edge checks.

## Files

| Path | Role |
| --- | --- |
| `structural-{fixed-fps,default,max-fps-60}.json` | full `PROBE_RESULT` payloads with pacing metadata |
| `structural-*.checks.txt` / `.raw.txt` | summary and raw output |
| `contract-{fixed,default,max}/` | 76-check contract suite under each pacing |
| `compare-modes.txt` | throughput + expanded per-tick trace digest comparison |
| `n1-regression-fixed.txt` | dynamic-body regression pass with measured steps |
| `n1-regression-original-bdb0a98.txt` | same regression failing on the original |
| `n1-regression-mutated.txt` | same regression failing when the fix is reverted |
| `mutation-sensitivity.txt` | four-fix combined mutation, 9 failures |
| `runner-script-error.txt` | runner detects a parse-error/hung run |
| `runner-wrong-count.txt` | runner refuses an unexpected check total |
| `concurrent-load/` | contract fixed/default/max, structural and N1 launched together |
| `exit-code-selftest.txt` | injected-failure exit-code check |
| `manifest.sha256` | SHA-256 of sources, tests, `provenance.json` and evidence |
| `provenance.json` | machine-readable run record, candidate separation and limits |

## Limits (do not overread)

- One-car `CharacterBody3D` probe plus one counting `RigidBody3D`; not the M1
  motor, AI, pair contacts, multi-car reset, interactive invocation or full
  simulation.
- The deferred-pause mechanism is measured on Godot 4.7.2-stable/Jolt;
  cross-version or cross-platform equivalence is not claimed.
- Cold-start activation can miss one engine step for the first request, exactly
  as for a continuous reference; the regression isolates it with a warm-up.
- Backend identity inferred from the pinned setting plus historical contrast.
- Concurrent host load can change wall times, not the recorded invariants.
