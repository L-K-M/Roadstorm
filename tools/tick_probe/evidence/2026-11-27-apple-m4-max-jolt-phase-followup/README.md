# Recorded probe evidence — phase-alignment follow-up slice

Both exact-source `8b7146b` reviews passed the checkpoint but identified
follow-ups. This bounded slice implements the requested hardening:

1. coordinator physics-callback priority plus a committed consecutive-tick
   sequence assertion for earlier/later observers;
2. deterministic physics-ordered mid-request motion-bound injection, returned
   `requested_ticks` checks and real dynamic-change checks in the hard gate;
3. an inter-callback `_pending_publish` regression (refused overlap, empty
   retrieval, reset cancellation);
4. precise comment/operator/evidence corrections with old raw outputs kept;
5. all new outputs in this directory; the prior phase-alignment directory is
   untouched.

Base candidate `8b7146b7ae81b326a638ab283c42bbbb91841e94`; Godot
`4.7.2.stable.official.ed1daf0bf`, Jolt, Apple M4 Max.

## 1. Callback priority and actual sequence

`src/tick_coordinator.gd` sets `process_physics_priority = -1000`
(`PHYSICS_CALLBACK_PRIORITY`), below ordinary default-priority observers for
this scene. This is **not globally unbeatable**: nodes with an even lower
priority still run first. Simulation state remains inside the coordinator.

The committed contract test places default-priority `CallbackObserver` nodes
both earlier and later in the tree. Both record `coord.tick_count` at each
unpaused physics callback during a 12-tick request; both must observe exactly
`[1..12]`, with no tick-0 phantom and no extra publication-iteration callback.
The contract also asserts `coord.process_physics_priority < observer priority`.

Remaining unpaused idle window: while waiting, pausable `_process`, timers,
tweens and animations do not advance (`SceneTree.paused`). In the publication
iteration the pause is set in the coordinator physics callback before idle, so
pausable nodes never see an unpaused step without a logical tick.
`PROCESS_MODE_ALWAYS` nodes can still run in that iteration with
`paused == true`; they are outside coordinator authority and must not mutate
simulation state.

## 2. Deterministic injection and stronger hard gate

`tests/motion_injector.gd` is a default-priority physics node armed before the
request; on the first callback observing `tick_count >= 3` it raises speed to
250 m/s. The next coordinator callback deterministically refuses, independent
of process-frame polling/catch-up.

The committed repeat driver now checks, per request: returned
`requested_ticks == n`, and dynamic-body y decreases and velocity becomes more
negative across every request and the one-tick terminal (real change, not only
the existing server-state equality). The 12+12+1 idle/callback/mixed gate is
unchanged and passes.

Targeted mutations:

- publish immediately in the final callback → 17 failures; final integrations
  missing, dynamic-change checks fail;
- defer the refusal pause → 1 failure; `k+1=4` steps, integration `[1,2,3,3]`.

## 3. Inter-callback `_pending_publish` regression

`tests/publication_probe.gd` runs with `process_physics_priority = -2000`
(test-only, before the coordinator) and exercises the real publication window:
inside it, `begin_step(12)` is refused, `take_result()` is empty, then
`reset()` cancels publication. The committed driver waits and asserts zero
further server steps, zero further ticks, frozen tree, `tick_count == 0` and no
additional `step_finished`. Before this slice those paths were code-guarded
but untested; they are now deterministic regression checks.

## 4. Comment / operator / evidence corrections

- Coordinator comments now describe arm-then-activate and post-final-server-step
  publication; removed the stale synchronous-final-callback and
  may-flush-later wording.
- Contract comments no longer mention a deferred unpause or final-callback
  pause.
- Main probe README no longer claims the gate directly asserts a changing
  dynamic value; it states the actual dynamic y/velocity change checks.
- `FAKE_CHECKS` example corrected from 85 to the pinned 135.
- Stale N1 example count corrected from 61 to 76; the historical “76 to 77”
  note now states current counts without rewriting history.
- `errata.md` records that the old `phase-post.txt` / `repeat-pre-*` files were
  failed launches and that old recorded counts remain historical. No prior raw
  file or review report was edited.

## Results (pinned engine, private XDG/TMPDIR)

| Run | Checks | Exit |
| --- | --- | ---: |
| contract fixed/default/max | 135/135 each | 0 |
| strict N1 fixed/default/max | 76/76 each | 0 |
| repeat hard gate fixed/default/max | 70/70 each | 0 |
| structural fixed/default/max | 108/108 each | 0 |
| compare_modes throughput + trace | 9 + 2 PASS | 0 |
| exit-code selftest | 5 total, 1 injected failure | 1 |
| mutation: immediate publish | 17 failures / 70 | 1 |
| mutation: deferred refusal pause | 1 failure / 70 | 1 |
| mutation: publication guard removed | 1 failure / 70 | 1 |

Realtime in the captured run: 0.923× against the 0.923× boundary-iteration
ceiling; host variance applies. One activation/publication boundary iteration is added
per request and adds no physics-server step.

## Residual limitations

- Contacts/`Area3D`/contact manifolds are still not gated for publication
  freshness; dynamic transform/velocity equality is gated.
- Priority `-1000` is scene-local, not a global ordering guarantee.
- Runner gaps remain: `--expect-checks` defaults to 0 and `checks_failed` is
  not reconciled with `len(failures)` (recorded runs pin counts explicitly).
- No M0.8/M0 signoff and no M1 motor implementation.

## Files

| Path | Role |
| --- | --- |
| `contract-{fixed,default,max}/` | 135-check contract suite |
| `n1-{fixed,default,max}.txt` | 76-check strict N1 |
| `repeat-{fixed,default,max}.txt` | 70-check hard gate incl. publication regression |
| `structural-*` | 108-check structural suite |
| `compare-modes.txt` / `exit-code-selftest.txt` | pacing/fidelity and exit code |
| `mutation-{publish,refusaldelay,pubguard}.txt` | three targeted negative controls |
| `errata.md` | precise corrections; no old raw files rewritten |
| `manifest.sha256` / `provenance.json` | hash-bound record |

Coordinator verification: corrected the observer priority assertion to use
`process_physics_priority`; private verified Godot 4.7.2 reran the 135-check
contract in fixed/default/max pacing, all 135/135, exit 0. The captured
contract stdout/JSON bytes matched the existing evidence in all three modes.
The source/provenance hashes below include the assertion correction.
