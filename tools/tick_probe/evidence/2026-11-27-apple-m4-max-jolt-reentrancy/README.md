# Recorded probe evidence — completion-callback reentrancy, 27 November 2026, Apple M4 Max

Current evidence responding to
`review/implementation/m0-tick-sol-recheck-c6292a2.md`. Reported candidate:
`c6292a2661b48d7f090225bd531427967b404359` (`c6292a2`). Previous evidence is
preserved unchanged; this worktree also carries the uncommitted cold-start/N1
revisions that `c6292a2` committed.

## Findings reproduced on the reported candidate

Private copy of `tools/tick_probe` at `c6292a2`; synchronous listeners on
`step_accounted`/`step_finished`:

| Probe | `c6292a2` result |
| --- | --- |
| `begin_step(2)` inside `step_accounted` of a 12-tick request | **accepted** (`true`); original result survived by luck |
| `reset()` inside `step_accounted` of a 1-tick request | old tick-1 result republished: `pending=true`, `tick_count=1`, live `tick_count=0`, `paused=true` |
| contract runner with a well-formed report `checks_failed=1` but child exit 0 | **exit 0** (failure not enforced) |

## Fixes

- `_finish_step()` now arms all publication state (`_result`/`_pending_result`
  or `_emit_scheduled`/`_deferred_result`) **before** dispatching
  `step_accounted`, and dispatches signals under a completion-callback depth
  counter.
- `begin_step()` refuses while a completion callback is running or a deferred
  publication is scheduled; a listener cannot interleave a new request into a
  half-published completion.
- `reset()` during a completion callback marks publication cancelled
  (`_completion_reset`); `_finish_step()` does not re-arm or publish afterwards,
  so no stale tick result can reappear at tick 0.
- `run_contract_tests.py` treats the report's `checks_failed` as authoritative:
  a failing report exits 1 even when the child process exits 0. A new test
  double, `tests/inject_failure_fake_godot.sh`, emits a valid 85-check report
  with one failure and exit 0 for this check.

Post-fix private repro: accounting reentry refused (`false`), original result
intact; reset in `step_accounted` leaves `pending=false`, empty `take_result()`,
live tick count 0 and frozen; injected failing report exits 1, while an
all-pass report still exits 0.

## Run policy

- Apple M4 Max, macOS, arm64; Godot `4.7.2.stable.official.ed1daf0bf`;
  Python 3.15.2.
- Headless isolated copies; outputs in an ignored private scratch directory; no
  GUI, Git mutation, installed-tool writes or network; no `HOME` reassignment
  (XDG/TMPDIR redirected by the runner).
- Every run bounded to <= 30 s. Slowest recorded: max-fps structural (12 s),
  compare_modes (14 s).

Commands:

```sh
godot --headless --fixed-fps 60 --path <isolated> --script res://src/tick_probe.gd -- mode=structural pacing=fixed
python3 tools/tick_probe/tests/run_contract_tests.py --pacing fixed|default|max --timeout 25 --expect-checks 85
python3 tools/tick_probe/compare_modes.py --project <isolated> --timeout 25 \
    --expect-throughput-checks 4 --expect-trace-checks 2
godot --headless --fixed-fps 60 --path <isolated> --script res://tests/n1_regression_entry.gd
FAKE_CHECKS=85 FAKE_FAILED=1 python3 tools/tick_probe/tests/run_contract_tests.py \
    --godot tools/tick_probe/tests/inject_failure_fake_godot.sh \
    --project <isolated> --pacing fixed --expect-checks 85   # must exit 1
```

## Results

| Run | Checks | Exit | Wall |
| --- | --- | ---: | ---: |
| structural `--fixed-fps 60` / default / `--max-fps 60` | 108/108 each | 0 | 3 s / 8 s / 12 s |
| contract `--pacing fixed` | 85/85 | 0 | < 1 s |
| contract `--pacing default` | 85/85 | 0 | 7 s |
| contract `--pacing max` | 85/85 | 0 | 7 s |
| N1/cold-start regression, three pacings | 14/14 each | 0 | < 1 s each |
| `compare_modes.py` throughput + trace digests | 9 + 2 PASS | 0 | 14 s |
| post-fix edge repro | reentry refused, reset clean | 0 | < 1 s |
| post-fix injected zero-exit failure | runner fails closed | 1 | < 1 s |
| post-fix injected all-pass report | runner accepts | 0 | < 1 s |
| exit-code self-test | 5 total, 1 injected failure | 1 | < 1 s |
| combined ordering/guard mutation | 2 targeted failures / 85 | 1 | < 1 s |
| mutated runner (failed-check disabled) | exits 0 on reported failure (bug shown) | 0 | < 1 s |

The cold-start physical-server controls remain green: first 1-tick request
integrates exactly once, first/repeated 12-tick requests integrate exactly 12,
continuous cold baseline shows registration latency (0 over 1 frame, 11 over
12), and a 30-frame frozen wait integrates nothing. Terminal/zero-tick
publication and cap/negative refusal checks remain green in the 85-check suite.

## Files

| Path | Role |
| --- | --- |
| `pre-fix-edge-reproduction.txt` | c6292a2 reentry/reset reproduction |
| `post-fix-edge-verification.txt` | same driver after the fix |
| `pre-fix-runner-injected.txt` | old runner exits 0 on a reported failure |
| `post-fix-runner-injected.txt` | new runner exits 1 on the same report |
| `runner-all-pass.txt` | new runner accepts an all-pass report |
| `mutation-sensitivity.txt` | guards/ordering disabled: 2 targeted failures |
| `mutation-edge-reproduction.txt` | mutation restores accepted reentry and stale result |
| `mutation-runner-injected.txt` | disabled failed-check lets exit 0 through |
| `contract-{fixed,default,max}/` | 85-check contract suite per pacing |
| `structural-*` / `compare-modes.txt` / `n1-regression-*` / `exit-code-selftest.txt` | refreshed supporting evidence |
| `manifest.sha256` / `provenance.json` | hash-bound record |

## Limits

- One-car probe plus counting dynamic body; not M1 motor/AI/contacts/multi-car
  reset/interactive/full simulation.
- Completion semantics measured on Godot 4.7.2/Jolt; cross-version/platform
  equivalence not claimed.
- Reentrancy protection covers GDScript signal dispatch; it cannot prevent a
  caller from ignoring the boolean return outside callbacks.
- No commit created; hashes bind current worktree contents and the reported
  candidate blobs separately.
