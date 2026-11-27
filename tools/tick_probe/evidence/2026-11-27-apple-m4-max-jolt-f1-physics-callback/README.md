# Recorded probe evidence — F1 physics-callback unpause correction

Responds to Opus finding F1 in
`review/implementation/m0-tick-opus-5-5-1295892.md`, base candidate
`12958922d34f1a7a89675a4e89381f2c298caba4`. Sol’s pass review is treated as
input; this change is limited to F1 plus a hard regression and evidence.

## Reproduction on the reported candidate

A test-only `PROCESS_MODE_ALWAYS` caller ordered after the coordinator calls
`begin_step(12)` from `_physics_process` while the tree is paused. A warmed
counting `RigidBody3D` (activated for several unpaused frames first) measures
actual physics-server integrations. Identical under fixed/default/max pacing:

| Metric | pre-fix `1295892` | fixed |
| --- | ---: | ---: |
| `begin_step` accepted | true | true |
| `SceneTree.paused` immediately after call | **false** | **true** |
| result elapsed / live ticks | 12 / 12 | 12 / 12 |
| counted server steps | **13** | **12** |

Traces: `f1-pre-{fixed,default,max}.txt`, `f1-post-{fixed,default,max}.txt`.
The extra step was an already-unaccounted iteration: the caller’s synchronous
unpause let that frame’s physics-server step run with zero logical ticks. The
probe car did not expose it because it moves by explicit `move_and_collide`.

## Fix

`src/tick_coordinator.gd`: when `begin_step()` is called from inside a physics
callback while the tree is paused, it no longer unpauses synchronously. It arms
`_arm_unpause_pf = Engine.get_physics_frames() + 1`; the coordinator’s next
`_physics_process` applies the unpause before executing the first tick, pairing
each server step with a logical tick. Ordinary idle-time calls keep immediate
unpause; zero-budget, terminal, reset, reentrancy and final-step publication
paths are unchanged.

New `tests/physics_caller.gd` plus the contract `physics-caller:*` checks assert
accepted request, frozen-immediately-after-call, exactly 12 logical ticks, and
exactly 12 counted server steps, then repeat an ordinary idle-time request on
the same warmed body. Contract total goes 91 → **97**.

Mutation sensitivity: reverting only the new deferred-unpause branch yields
`paused_after_call=false` and `server_steps_delta=13`; the two new contract
checks fail (`mutation-f1-reverted.txt`).

## Results

| Run | Checks | Exit |
| --- | --- | ---: |
| contract fixed/default/max (`--expect-checks 97`) | 97/97 each | 0 |
| structural fixed/default/max | 108/108 each | 0 |
| strict N1 runner fixed/default/max (`--expect-checks 21`) | 21/21 each | 0 |
| compare_modes throughput + trace digests | 9 + 2 PASS | 0 |
| exit-code selftest | 5 total, 1 injected failure | 1 |
| mutation: F1 branch reverted | 2 targeted failures / 97 | 1 |

All runs used private copies with private TMPDIR/XDG and bounded Godot
invocations; no HOME/shared/installed writes, no Git mutation.

## Remaining Opus dispositions (not implemented in this bounded change)

- **F2 (open):** N1’s signal-sampled frame check uses `>= n+1`; exact equality
  should be restored now that sampling is deterministic, and warmed-body exact
  request checks added alongside fresh-body cases.
- **F3 (open):** the motion-bound no-server-step check uses a cold body and may
  be insensitive to a one-step leak; warm the body and add a defer-pause
  mutation control.
- **F4 (open):** enforcer ordering/prior-node exposure remains documented;
  consider minimum `process_physics_priority` for the enforcer.
- **F5 (open):** freed-enforcer fallback uses `is_instance_valid` correctly but
  `configure()` still ends unpaused; freeze at end of configure.
- **F6 (open):** strict parsers default `--expect-checks 0`; reconcile
  `checks_failed` with failure-list length and use last summary lines.
- **F7 (open):** documentation/evidence consistency items (README max-fps
  figures, stale cold wording, uncommitted F1/F3 measurement driver, evidence
  produced from uncommitted trees).

No M0.8 acceptance claim is made; the coordinator will independently verify the
corrected SHA and obtain scoped rechecks.

## Files

| Path | Role |
| --- | --- |
| `f1-pre-{fixed,default,max}.txt` | pre-fix physics-callback traces (13 steps) |
| `f1-post-{fixed,default,max}.txt` | post-fix traces (12 steps, stays frozen) |
| `contract-{fixed,default,max}/` | 97-check suite per pacing |
| `structural-*` | 108-check structural suite per pacing |
| `n1-regression-{fixed,default,max}.txt` | strict-runner N1 results |
| `compare-modes.txt` / `exit-code-selftest.txt` | pacing/fidelity and exit-code evidence |
| `mutation-f1-reverted.txt` | reverted branch: two new checks fail |
| `manifest.sha256` / `provenance.json` | hash-bound record |

## Limits

- Godot 4.7.2/Jolt on one Apple M4 Max host; callback/pause semantics are not
  cross-version guarantees.
- The F1 regression covers positive requests from a later physics callback;
  other call-order/terminal interactions remain covered by existing tests.
- Physics-callback-origin requests now span one additional paused iteration
  (`engine_pf_delta=14` for a nominal 12-tick request) while their server-step
  count stays exactly 12.
