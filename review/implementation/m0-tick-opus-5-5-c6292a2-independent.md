# M0.8 tick recheck: independent Opus review of `c6292a2`

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, running in the Claude Code agent harness
- Date: 2026-11-27
- Candidate: `c6292a2661b48d7f090225bd531427967b404359` ("Correct tick probe test command counts"). The code change is in `8a5615c` ("Account for every physics-server step in tick probe"). `c6292a2` changes only `tools/tick_probe/README.md`: the example `--expect-checks` goes from 76 to 77, plus a note saying so.
- Base: `bdb0a98` (`bdb0a9820b847d23628cce35a9070bb63ae17acd`)
- Scope: `tools/tick_probe/**` changes in `bdb0a98..c6292a2` (`tick_coordinator.gd`, `probe_driver.gd`, `compare_modes.py`, `tests/contract_driver.gd`, `tests/counting_body.gd`, `tests/n1_regression_{driver,entry}.gd`, `tests/run_contract_tests.py`, `README.md`) and the current evidence folder `evidence/2026-11-27-apple-m4-max-jolt-cold-start/`.
- Prior inputs: my own report `m0-tick-opus-5-5-bdb0a98-independent.md`, and the Sol findings in `m0-tick-sol-recheck-bdb0a98.md` that I was asked to assess.
- Not consulted: any current review of `8a5615c`/`c6292a2` by another reviewer, or other files in `review/`.
- No agents or helpers. No source edits, no Git mutation, no GUI, no shared or installed writes. This file is the only write.

**Verdict: static PASS for the one-car M0.8 probe scope. Runtime NOT VERIFIED by me: execution was blocked.**
- N1 is fixed. The deferred pause is the right mechanism, and the recorded evidence agrees with the code.
- The Sol API-edge findings are fixed, and the Sol max-FPS accounting flake is fixed in the contract suite.
- No blocking defect.
- Two Low/Medium items should be settled before M1 builds on the coordinator:
  - the extra unpaused physics callback per request (ordering and wall-clock cost, F1/F2);
  - a misattributed "registration latency" explanation that hides a one-iteration lag in rigid-body callbacks (F3).
- I make no claim about the motor, multiple cars or gameplay.

## Execution: blocked

| Attempted | Outcome |
| --- | --- |
| `git log`, `git diff bdb0a98 c6292a2 -- tools/tick_probe/{src,tests,compare_modes.py}`, `git diff 8a5615c c6292a2`, `git show c6292a2:<path>` for the coordinator, README, evidence README, manifest, N1 outputs (fixed/default/max, original `bdb0a98`, mutated), `compare-modes.txt`, `mutation-sensitivity.txt`, `contract-max/contract-tests.txt` | Done |
| `godot --version` | **Refused** by the tool permission layer (non-interactive session) |
| `git archive -o /tmp/... c6292a2 tools/tick_probe` (private snapshot) | **Refused**, same reason |
| `git ls-tree`, `git grep` on Git objects, chained/variable shell commands | Refused, same reason |

So I did **not** run anything myself: not the contract tests (77/77 ×3), not N1 (14/14), not structural (108/108), not compare-modes, and not the manifest hashes. Every runtime number below is either recorded evidence or the coordinator's report. I checked those numbers against the code and against each other.

## Status of earlier findings

| Finding | Change | Assessment |
| --- | --- | --- |
| **N1** (mine): pausing inside the final `_physics_process` loses that tick's server step | `_finish_step(terminal, true)` now only sets `_emit_scheduled` and stores the result (`tick_coordinator.gd:376-377`, `:508-532`). The **next** physics callback pauses the tree, publishes `step_finished` and returns (`:333-339`). That iteration's `PhysicsServer3D` step is then suppressed, so N ticks give N server steps. `begin_step` refuses during the window ("result awaiting emission", `:243-244`). `reset()` clears the flag (`:206-208`). | **Fixed (static and recorded).** Recorded counts on the fixed tree under all three pacings: fresh-body 1-tick request = 1, 12-tick = 12, repeated 12 = 12 and 12, 30-frame frozen wait = 0 steps with zero drift. Pristine `bdb0a98` and the reverted mutation give 0, 11, 11, 11. So the regression discriminates. The 24-tick first request is from an uncommitted scratch driver (evidence README table); no committed test covers it. |
| N1 sub-question: frozen waiting | Unchanged freeze paths, plus a dynamic-body wait check in both the contract test and the N1 driver | Recorded 0 server steps and exact `==` y/velocity over 30 frames. Consistent with the code. |
| **N2** (mine): backstop committed partial motion | `body.global_transform = start` before `return true` (`:463-466`) | **Fixed** in code. Still not executed by any test (README says so). |
| **N3** (mine): runners cannot detect lost checks | `run_contract_tests.py` fails on `SCRIPT ERROR`/`Parse Error`/`Failed to load script`. It requires a `TESTS_TOTAL` line, cross-checks it against the JSON, and enforces `--expect-checks`. `compare_modes.py` does the same with `--expect-{throughput,trace}-checks`. Recorded negative controls: `runner-script-error.txt`, `runner-wrong-count.txt`. | **Fixed for both runners.** Gaps: the count gate is opt-in (default 0 disables it), and the N1 entry has no runner (F5). |
| **N4** (mine): mutation covered one freeze site | Combined mutation now reverts the N1 deferral, negative ordering, zero-tick ordering and cap-0 initial state | **Addressed.** But the evidence README misstates the failure count (F6). |
| **L2** (mine) / **Sol 3b**: cap ≤ 0 observation says `none` | `_reset_state` sets `episode_terminal = "truncated"` when `max_ticks <= 0` (`:183-185`) | **Fixed.** Tested in both the contract and structural suites. |
| **L8** (mine) / **Sol 2**: negative request accepted on a terminal episode | Negative check is now first in `begin_step` (`:241-242`) | **Fixed.** Tests cover refusal, no result, no tick, and the last signal unchanged. |
| **Sol 3a**: zero-tick result published while unpaused | `set_frozen(true)` now runs before `_emit_result(0, 0, "none")` (`:266-271`), and before the unfreeze, so a zero request never unpauses | **Fixed.** The contract test snapshots `paused` inside the signal. The structural variant is weaker (F7). |
| **Sol 1**: max-FPS callback-count flake (tally sampled after polling) | New `step_accounted` signal at the final logical tick (`:528-532`). The contract `frame-account` check samples there, and separately checks that a trailing frozen callback adds no tick. | **Fixed in the contract suite.** Its sampling point no longer depends on poll timing. The same class of flake remains in the N1 driver's `engine_pf_delta == n + 1` check (F4). |
| **L5/P3** (mine): pacing not recorded | `pacing=` argument; `engine_pacing`, `engine_max_fps` and `requested_pacing` are recorded in the structural environment | **Addressed** for structural. The contract `contract-tests.txt` is still byte-identical across pacings (same SHA in the manifest); only `run.txt` differs. |
| **P2** (mine): `provenance.json` not hashed | Now listed in the manifest | **Fixed.** |
| **L7** (mine): trace has only z per tick | Rows add `start_pos`/`end_pos` and rotation | **Addressed.** The trace still has no dynamic body. |

## New findings, ranked

**F1 (Medium, design; affects M1, not this probe): the deferred pause adds one unpaused physics callback per request, with no logical tick in it.**
- In the emission iteration (N+1), `physics_frame` fires while the tree is still unpaused, so the coordinator's own `frozen_physics_frames` does not count it.
- Every `PROCESS_MODE_INHERIT` node that the engine processes *before* the coordinator (lower `process_priority`, or earlier in tree order) also gets a `_physics_process` call before the coordinator pauses. That call happens with no tick and no server step after it.
- Nodes processed after the coordinator are skipped.
- In this probe only the coordinator and the test drivers exist, so nothing is affected.
- Once gates, triggers, AI or other cars live outside the coordinator, such nodes would see N+1 callbacks per N-tick request, depending on processing order. They could also queue forces or impulses that get applied on the next request's first step.
- Fix: pin it in the M1 design. Either all simulation runs inside the coordinator's tick, or the coordinator gets the lowest `process_priority` and other nodes gate on the coordinator's tick rather than on `_physics_process`. Add a test with a second node processed before the coordinator.

**F2 (Low–Medium, recorded): the fix costs one engine frame per request, and the pacing gate hides it.**
- Recorded `compare-modes.txt`: realtime 600 ticks take 11.004 s (0.909×). At `bdb0a98` the Sol run recorded 10.001 s. This is 12/13 of real time for 12-tick requests, and 1/2 for 1-tick requests.
- Fixed-FPS training throughput drops by the same 1/(n+1) in engine iterations.
- The README describes `engine_pf_delta = n + 1` but not the wall-clock effect. The 0.5–2.0 realtime band in `compare_modes.py` lets it pass silently.
- Fix: state the n/(n+1) realtime factor as part of the contract, and tighten the realtime check to it. Otherwise, choose a pause point that costs no physics iteration.

**F3 (Low, plausible, based on recorded data): the "registration latency" explanation contradicts the recorded data. A one-iteration callback lag fits all of it.**
- The README says a body created while paused "is registered on its first unpaused server step and integrates from the second". That model cannot produce the fixed-tree result for a fresh 1-tick request: the request runs one server step, and the emission iteration's step is suppressed. Under that model the count would be 0, but it was **1**.
- A model where pausing can step the emission iteration is ruled out too. It predicts 12 for pristine warm request #2, but the record says **11**.
- One model fits all eight recorded cells: Jolt delivers `_integrate_forces` (and, I infer, the state sync) during the *next* iteration's `flush_queries`, before scene callbacks. This holds for fixed 1/12/12/12, pristine 0/11/11/11 and continuous k−1. The recorded `first_integ_pf` is always 2 above the request's starting frame, which also matches.
- The request-path conclusions stand.
- But two consequences are undocumented:
  - Sampling `server_steps` at `step_accounted` would show n−1.
  - The result's `observation` is built at tick N, before tick N's server step (`_build_result` inside `_finish_step`). Server-stepped state is therefore one step behind `tick_count`. The probe car moves by explicit `move_and_collide`, so it is unaffected. Any M1 observation of rigid or area state would be affected.
- Fixes:
  - Rename the control.
  - Rebuild the observation at emission (`:336`), after the final step's flush.
  - Add a check that a rigid body's position in `result.observation` reflects n steps.
- Unverified by me at runtime.

**F4 (Low): the N1 driver's `engine_pf_delta == n + 1` check depends on poll timing under default and max-FPS pacing.**
- `_request_scenario` reads `Engine.get_physics_frames()` after polling `has_pending_result()` on `process_frame` (`n1_regression_driver.gd:806-836`).
- If a catch-up frame runs a further paused iteration after emission and before the idle poll, the delta is n+2. This is the same mechanism as Sol finding 1.
- The `server_steps` check is robust, because paused iterations do not step.
- Each pacing has a single recorded pass, which does not exclude flakes.
- Fix: measure `pf` at `step_finished`, or assert `>= n + 1` plus the server-step equality.

**F5 (Low): the N1 regression has no strict runner.**
- It is run as a bare `godot ... --script res://tests/n1_regression_entry.gd` and relies on the `quit(1)` exit code.
- It has none of the `SCRIPT ERROR` or expected-count gating that N3 added to the other runners.
- A parse error in the driver, or an early abort, gives a misleading exit code.
- Mitigation: the contract suite (which is gated) duplicates the core request checks (`dynamic-steps`). Not covered there: the `engine_pf_delta` and continuous-control checks.
- In the same family: `--expect-checks` defaults to 0 (disabled), so only callers who pass 77 get the count gate.

**F6 (Low, evidence accuracy): the evidence README misstates the mutation result.**
- The cold-start README table says "combined four-fix mutation | 9 failures / 77 checks".
- `mutation-sensitivity.txt` records `TESTS_FAILED=10` (`checks_failed: 10`): 3 dynamic-steps, 2 begin-step, 5 api-edge.

**F7 (Nit): weaker check and a stale comment.**
- The structural `_scenario_api_edges` uses the persistent `signal_paused` flag (`probe_driver.gd`, `_on_step_finished`). If `begin_step(0)` returned true without emitting, the value left from the previous signal (true) would pass the "zero-tick signal observed with the world frozen" check. The contract variant has no such hole, because it also checks the snapshot's `elapsed_ticks`/`terminal`.
- `tick_coordinator.gd:103` describes "the idle-phase emission", but emission happens in the next *physics* callback.
- `_deferred_terminal` is written but never read.

**F8 (Info): negative, zero and terminal edges reviewed with no defect.**
- Order: negative → awaiting emission → pending → terminal → in flight → cap ≤ 0 → zero → unfreeze. Every refusal leaves state unchanged.
- Terminal and cap-0 paths freeze before emitting.
- `motion_bound` paths still pause inside the callback without deferral. That is correct: no tick was accounted in that iteration, so suppressing its server step keeps steps equal to ticks. No test pins it with a counting body.
- Remaining exposure: a bridge that ignores the boolean (README limit).

## Evidence provenance

- The cold-start `manifest.sha256` binds the probe files as committed in `8a5615c`. It also hashes `README.md` (the tick-probe README), so that entry is **expected to fail** against `c6292a2`. The README note added in `c6292a2` discloses this.
- I could not hash any blob, so I neither confirmed the `8a5615c` binding nor saw the `c6292a2` README mismatch myself.
- Statically: `git diff 8a5615c c6292a2` touches only `tools/tick_probe/README.md`, so source and test inputs are identical between the two commits.
- The evidence README still calls `bdb0a98` the "reported candidate" with uncommitted fixes. That wording comes from before the commit. It is consistent with the `c6292a2` note, but a reader has to combine the two.
- The coordinator reports 77/77 per pacing, N1 14/14, structural 108/108 and compare PASS. These agree with the recorded files I read (`contract-max/contract-tests.txt` 77/0; the N1 files for fixed, default and max are 14/0, and default and max share a SHA). I did not reproduce them.

## Limitations

- **Execution blocked.** No Godot run, no snapshot, no hash recomputation. Everything here is static review of Git objects plus the recorded evidence.
- F3 is reasoned from recorded counts and frame indices against Godot's main-loop order. I did not check it against Jolt source or by running it.
- Scope is the one-car `CharacterBody3D` probe plus one test-only counting `RigidBody3D`, in headless Godot 4.7.2 with Jolt (by setting) on one Apple M4 Max host.
- No claim about: the M1 motor, multiple cars, contacts between cars, gameplay or triggers, the training bridge, rendered or interactive runs, cross-version or cross-platform behaviour, or the actual backend at runtime.

## Recommended next actions

1. An approved runner reruns the contract suite (`--expect-checks 77`, all three pacings), N1 and structural tests, `compare_modes.py`, and `shasum -c` (expecting only the README entry to differ) on a `git archive c6292a2` snapshot.
2. Before M1: settle the F1 ordering contract, and rebuild the result observation after the final server step (F3).
3. Correct the "registration latency" wording (F3) and the 9→10 count (F6). Sample the N1 frame delta at the signal (F4). Give the N1 entry a strict runner (F5).
4. Record the n/(n+1) realtime cost and tighten the realtime band to it (F2).
