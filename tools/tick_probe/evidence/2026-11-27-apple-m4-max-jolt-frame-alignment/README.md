# Recorded probe evidence — b5c4f99 frame-alignment correction slice

Both independent `b5c4f99` reviews passed the checkpoint but required changes.
This bounded slice implements them in `tools/tick_probe/**` only:

1. a behavioural callback-frame alignment gate that detects the misalignment
   the old `1..n` sequence assertion cannot, plus a targeted priority=0
   negative mutation;
2. precise idle/publication-window documentation as M1 integration
   constraints, with no blanket claim that every pausable node avoids an extra
   callback;
3. the requested doc, runner, errata and provenance corrections;
4. all new outputs in this directory. Prior raw measurement files are not
   rewritten.

Reported candidate `b5c4f99950bebc551849c1cc197db3b4c810b8c8`; the corrected
working tree is uncommitted. Engine `4.7.2.stable.official.ed1daf0bf`, Jolt,
Apple M4 Max, macOS 27.0.1, arm64.

## 1. Behavioural frame-alignment gate (Opus R1)

The earlier contract check only asserted that both default-priority observers
recorded the consecutive tick sequence `[1..12]`. As the review derived, an
earlier-in-tree observer with the coordinator's priority removed still records
`[1..12]` one iteration late: it misses the arming iteration, reads the previous
tick in each later iteration, and reads tick 12 again in the publication
iteration. The sequence and callback-count checks cannot see that.

The correction adds a separate, bounded diagnostic pairing:

- `src/tick_coordinator.gd` records `Engine.get_physics_frames()` for each
  committed logical tick in `tick_engine_frames` (parallel to, but deliberately
  outside, `tick_log`). Engine frame IDs therefore never enter the compared
  per-tick trace digest, and simulation ownership is unchanged.
- `tests/callback_observer.gd` records the engine frame beside every observed
  tick in `tick_frame_sequence`.
- `tests/contract_driver.gd` asserts that for every observed tick the
  observer's frame equals the coordinator's frame for that SAME logical tick,
  for both the earlier-in-tree and the later-in-tree observer across all 12
  frames. The numeric `process_physics_priority` comparison remains a separate
  configuration check; it is not the behavioural gate.

Contract check count rises from 135 to **137**.

### Priority=0 negative mutation

`tests/run_frame_alignment_mutation.py` copies the project to a private scratch
directory, patches `PHYSICS_CALLBACK_PRIORITY` from `-1000` to `0`, and
replaces the numeric priority assertion with an excluded placeholder so only
the behavioural checks discriminate. At equal priority the coordinator's tree
position leaves it after the earlier-in-tree observer and before the later one.

Results (`mutation-frame-alignment-{fixed,default,max}.txt`): each pacing exits
1 with exactly one failure, the earlier-in-tree observer's frame alignment,
while the `1..12` sequence checks and the callback-count check still pass. The
observer frame list is off by exactly one iteration (for example fixed:
observer `[420..431]` versus coordinator `[419..430]`). The captured output
shows only the earlier-in-tree check failing: at equal priority the
later-in-tree observer remains ordered after the coordinator and still aligns.
This demonstrates that the older assertion alone passes the broken ordering
while the new behavioural check fails it.

## 2. Documentation corrections

- **Idle/publication windows.** `README.md` now documents two distinct
  intervals around publication: the idle gap between the final tick's
  physics-server step and the next coordinator callback (during which a
  pausable `_process`, timer, tween or animation can advance), and the
  publication iteration itself (which a pausable node with lower-or-equal
  priority ordered before the coordinator observes while still unpaused).
  There is no blanket claim that all pausable nodes avoid an extra unpaused
  callback; M1 nodes that must not advance after the final tick are told to
  enforce that themselves. The old phase-followup README's blanket sentence is
  recorded as superseded in `corrections.md`, not rewritten.
- **`FAKE_CHECKS` negative control.** The documented contract command now uses
  `FAKE_CHECKS=137` with `--expect-checks 137`, so it reaches the
  reported-failure branch instead of exiting on a count mismatch.
  `fake-checks-negative-control.txt` records exit 1 through that branch.
- **Repeat runner.** `tests/run_repeat_tests.py` docstring and
  `--expect-checks` default changed from 54 to **70**.
- **Prior evidence docs.** See `corrections.md`: the phase-followup `errata.md`
  repeat-file references were corrected and its stale provenance README hash
  was aligned with the archived README. Raw outputs and the b5c4f99 source
  bindings were left intact.

## 3. Results (pinned engine, isolated copies, private XDG/TMPDIR)

| Run | Checks | Exit |
| --- | --- | ---: |
| contract fixed/default/max | 137/137 each | 0 |
| repeat hard gate fixed/default/max | 70/70 each | 0 |
| strict N1 fixed/default/max | 76/76 each | 0 |
| structural fixed/default/max | 108/108 each | 0 |
| compare_modes throughput (4) + trace (2) | 12 PASS | 0 |
| fake `FAKE_CHECKS=137` negative control | 137 reported / 1 failed | 1 |
| structural exit-code selftest | 5 total / 1 injected failure | 1 |
| mutation: frame alignment, fixed/default/max | 1 failure / 137 each | 1 |
| mutation: immediate publish | 17 failures / 70 | 1 |
| mutation: deferred refusal pause | 1 failure / 70 | 1 |
| mutation: publication guard removed | 1 failure / 70 | 1 |

The frame-alignment mutation harness exits 0 when the demonstration succeeds
(the mutated run fails the behavioural check); the Godot child itself exits 1.
The three prior repeat-gate mutations were rerun unchanged against the
corrected source and still fail 17/1/1.

Structural `fixed` output is byte-identical to the phase-followup capture.
`default`/`max` differ only in the wall-clock-derived
`wait_freeze.frozen_engine_physics_frames` field (50 versus 51 and 122 versus
121); the per-tick trace digests compared by `compare_modes.py` are unchanged
(max `|diff| = 0`). `repeat-*` and `n1-fixed/default` outputs are byte-identical
to the prior capture; `n1-max` differs only in cold-registration
`first_integ_pf` timing values, with 76/76 checks still passing.

## 4. Residual limitations

- Contact, `Area3D` and contact-manifold freshness at publication remain
  ungated; dynamic transform/velocity equality is gated.
- `process_physics_priority = -1000` is scene-local, not globally unbeatable;
  lower-priority pausable nodes can still run before the coordinator and see
  the publication iteration.
- Contract and N1 runners still default `--expect-checks` to 0 and do not
  reconcile `checks_failed` with `len(failures)`; recorded runs pin counts
  explicitly. The repeat runner default is now 70.
- No full M0/M0.8 signoff and no M1 acceptance claim; no motor implementation.

## Files

| Path | Role |
| --- | --- |
| `contract-{fixed,default,max}/` | 137-check contract suite |
| `repeat-{fixed,default,max}.txt` | 70-check hard gate incl. publication regression |
| `n1-{fixed,default,max}.txt` | 76-check strict N1 |
| `structural-*` | 108-check structural suite |
| `compare-modes.txt` | pacing/fidelity and per-tick trace digest comparison |
| `fake-checks-negative-control.txt` | documented `FAKE_CHECKS=137` runner negative control |
| `exit-code-selftest.txt` | structural injected-failure exit-code self-test |
| `mutation-frame-alignment-{fixed,default,max}.txt` | priority=0 behavioural negative control |
| `mutation-{publish,refusaldelay,pubguard}.txt` | three targeted repeat-gate mutations |
| `corrections.md` | documentation corrections applied to prior evidence |
| `provenance.json` / `manifest.sha256` | hash-bound record |
