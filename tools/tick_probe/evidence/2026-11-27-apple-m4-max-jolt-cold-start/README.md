# Recorded probe evidence — cold-start characterization, 27 November 2026, Apple M4 Max

Current evidence for the cold-start follow-up after the N1 server-step turn.
Reported candidate `bdb0a9820b847d23628cce35a9070bb63ae17acd`; the worktree also
carries the uncommitted Sol API-edge and N1 fixes described in
`../2026-11-27-apple-m4-max-jolt-n1-server-steps/`. Previous evidence is
preserved unchanged.

## What was measured

`tests/counting_body.gd` counts `_integrate_forces` calls (actual physics-server
integration steps) and records the engine physics-frame indices of the first and
last integration. `tests/n1_regression_entry.gd` creates a fresh active body in
a frozen world and runs:

- single requests of 1 and 12 logical ticks;
- two repeated 12-tick requests;
- a continuous cold baseline of 1 and 12 frames after unfreezing the same kind
  of freshly created body;
- a 30-frame frozen wait after completion.

Measured on the fixed tree (`fixed-fps`, default and `--max-fps 60` pacing,
identical numbers):

| Case | Requested/logical | Counted server integrations |
| --- | ---: | ---: |
| first single request | 1 | **1** |
| first single request | 12 | **12** |
| repeated request #1 | 12 | **12** |
| repeated request #2 | 12 | **12** |
| first request | 24 (scratch driver) | **24** |
| continuous cold baseline | 1 frame | 0 |
| continuous cold baseline | 12 frames | 11 |
| frozen wait | 30 frames | 0 |

On pristine `bdb0a98`: first single 1-tick request → **0**, first single 12-tick
request → **11**, repeated 12-tick requests → **11, 11**. The committed
regression fails there with exactly 8 failures.

## Separating the three effects

- **Registration latency (real, baseline-only).** A body created while the world
  is paused is registered on its first unpaused server step and integrates from
  the second: a continuously paced cold run advances `k - 1` steps over `k`
  frames. This affects a naive continuous reference, not the coordinator's
  request lifecycle.
- **Observation timestamp/engine-frame lag (accounted separately).** A normal
  request spans `n + 1` engine physics frames because the pause happens on the
  callback after the final tick; counted integrations are still exactly `n`.
  `step_accounted` samples the independent tally at the final logical tick
  (`ext_delta == n`), while `engine_pf_delta == n + 1` records the extra pause
  callback. The last state velocity read inside `_integrate_forces` equals the
  body's `linear_velocity` read after `take_result()`, so property-read lag is
  zero here.
- **Actual missed engine integration.** On the fixed tree the request path shows
  none: a freshly created body receives exactly one integration per requested
  tick, including the first request. On `bdb0a98` the first and every later
  request loses exactly one integration, which is the confirmed defect.

Conclusion: the earlier “cold-start may miss one step” caveat came from
comparing against a continuous cold baseline that itself loses one step to
registration. It is withdrawn; first-request semantics are exact in this tree.

## Run policy

- Apple M4 Max, macOS, arm64; Godot `4.7.2.stable.official.ed1daf0bf`;
  Python 3.15.2.
- Headless isolated copies; outputs in an ignored private scratch directory; no
  GUI, Git mutation, installed-tool writes or network; no `HOME` reassignment
  (the runner redirects XDG caches/config/data and `TMPDIR`).
- Pristine comparison used `git archive bdb0a98 | tar -x` plus only the committed
  counting/regression test files.
- Every run bounded to <= 30 s. Slowest recorded: max-fps structural (12 s),
  compare_modes (14 s).

Commands:

```sh
godot --headless --fixed-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural pacing=fixed
godot --headless --path <isolated> --script res://src/tick_probe.gd -- mode=structural pacing=default
godot --headless --max-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural pacing=max
python3 tools/tick_probe/tests/run_contract_tests.py --pacing fixed   --timeout 25 --expect-checks 77
python3 tools/tick_probe/tests/run_contract_tests.py --pacing default --timeout 25 --expect-checks 77
python3 tools/tick_probe/tests/run_contract_tests.py --pacing max     --timeout 25 --expect-checks 77
python3 tools/tick_probe/compare_modes.py --project <isolated> --timeout 25 \
    --expect-throughput-checks 4 --expect-trace-checks 2
godot --headless --fixed-fps 60 --path <isolated> --script res://tests/n1_regression_entry.gd
godot --headless --fixed-fps 60 --path <pristine-bdb0a98> --script res://tests/n1_regression_entry.gd
```

## Results

| Run | Checks | Exit | Wall |
| --- | --- | ---: | ---: |
| structural `--fixed-fps 60` / default / `--max-fps 60` | 108/108 each | 0 | 3 s / 8 s / 12 s |
| contract `--pacing fixed` | 77/77 | 0 | < 1 s |
| contract `--pacing default` | 77/77 | 0 | 7 s |
| contract `--pacing max` | 77/77 | 0 | 7 s |
| `compare_modes.py` throughput + trace digests | 9 + 2 PASS | 0 | 14 s |
| N1 regression, fixed tree, three pacings | 14/14 each | 0 | < 1 s each |
| N1 regression, pristine `bdb0a98` | 6/14 (expected) | 1 | < 1 s |
| combined four-fix mutation | 9 failures / 77 checks | 1 | < 1 s |
| N1 regression, mutation | 6/14 | 1 | < 1 s |
| exit-code self-test | 5 total, 1 injected failure | 1 | < 1 s |
| runner SCRIPT ERROR detection | detected, exit 1 | 1 | < 1 s |
| runner expected-count enforcement | refused, exit 1 | 1 | < 1 s |

The strengthened N1/cold-start regression replaced the previous warm-up step:
it now asserts a fresh first request, which fails on pristine `bdb0a98` with
8 failures (request integration and pause-callback frame accounting) and passes
on the fixed tree under all three pacings.

## Files

| Path | Role |
| --- | --- |
| `structural-{fixed-fps,default,max-fps-60}.json` | full payloads with pacing metadata |
| `structural-*.checks.txt` / `.raw.txt` | summary and raw output |
| `contract-{fixed,default,max}/` | 77-check contract suite under each pacing |
| `compare-modes.txt` | throughput + per-tick trace digest comparison |
| `n1-regression-fixed-{fixed,default,max}.txt` | cold-start regression pass with metrics |
| `n1-regression-original-bdb0a98.txt` | same regression failing on the reported candidate |
| `n1-regression-mutated.txt` | same regression failing when the fix is reverted |
| `mutation-sensitivity.txt` | four-fix combined mutation, 9 failures |
| `runner-script-error.txt` / `runner-wrong-count.txt` | runner strictness checks |
| `exit-code-selftest.txt` | injected-failure exit-code check |
| `manifest.sha256` | SHA-256 of sources, tests, provenance and evidence |
| `provenance.json` | machine-readable record and limits |

## Limits (do not overread)

- One-car probe plus one counting `RigidBody3D`; not the M1 motor, AI, pair
  contacts, multi-car reset, interactive invocation or full simulation.
- Integration semantics measured on Godot 4.7.2-stable/Jolt; cross-version or
  cross-platform equivalence is not claimed.
- Continuous cold baselines show registration latency (`k - 1` over `k`);
  request-path first-request behavior is asserted directly and is exact.
- Wall times host-dependent; no commit created, so hashes bind the current
  worktree contents and reported candidate blobs separately.
