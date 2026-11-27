# M0.8 tick/reset checkpoint: independent Opus recheck

- Job: `64cbe5b0-7cc7-4130-80a3-cfc7d4d59f43`
- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, running in the Claude Code agent harness
- Date: 2026-11-27
- Candidate: `d562755c83af1129b4ddf7043baee8d8a742d358` (`d562755`), base `55b04ce` (`55b04cec80fc842d1f40b5ac393a8a6492f112f3`)
- Inspected tree: `work/agents/64cbe5b0-7cc7-4130-80a3-cfc7d4d59f43/snap` (a copy with no `.git`)
- Other inputs: `PLAN.md` M0.8, `docs/TECHNICAL_DESIGN.md` ("Fixed tick and movement ownership" and the collision paragraphs), `docs/BENCHMARKS.md` (training-throughput paragraph), and the prior audit `work/agents/1b8fe3ed-3088-4847-a0e1-ea1676abc013/m08-probe-audit/REPORT.md`
- Not consulted: any Sol report, including the untracked Sol recheck in `review/implementation/`
- No agents spawned. No Git mutation. No source or asset edits, no GUI, no secrets read. This file is the only write.

**Verdict: NOT VERIFIED.** I could not run anything in this session, so no runtime result below comes from me. Static review found no blocking defect in the three audit fixes: the stale result, the zero/negative cap and the motion-bound refusal. Medium finding 1 and the low findings should be fixed or explicitly accepted before M0.8 is ticked. **M0 remains open.**

## What I could and could not run

| Attempted | Outcome |
| --- | --- |
| `godot --version` and every Godot run (structural, contract, compare) | **Not run.** The tool permission layer requires interactive approval, and this session is non-interactive. |
| `shasum -a 256` and `python3 -I -c hashlib…` over the probe files | **Not run**, blocked for the same reason |
| Read-only `cat`/`grep`/`ls`/file reads inside the snapshot | Done |

Consequences:

- **Snapshot identity.** I did not verify that `snap` is identical to `d562755`. It has no `.git`, the scope rule forbids reading the repository's object store, and hashing was blocked. The evidence `manifest.sha256`/`provenance.json` lists file hashes, but I could not recompute them.
- **Every runtime number is the worker's or coordinator's.** That covers the 73/73 structural checks under three pacings, the 30/30 contract checks, the 600-tick comparison and the mutation run. I read the recorded outputs and checked that they agree with the code. I reproduced none of them.
- **Scope of the claim.** Everything here is a minimal one-car `CharacterBody3D` probe in headless Godot 4.7.2 with Jolt pinned by setting. It says nothing about the M1 motor, multiple cars, contacts between cars, the training bridge, interactive/rendered execution or physical hardware.

## Files reviewed

`tools/tick_probe/{project.godot,README.md,compare_modes.py,src/tick_coordinator.gd,src/probe_driver.gd,src/tick_probe.gd(listed),tests/contract_driver.gd,tests/run_contract_tests.py}`, and from `evidence/2026-11-27-apple-m4-max-jolt-contract/`: `README.md`, `manifest.sha256`, `provenance.json`, `compare-modes.txt`, `mutation-sensitivity.txt`, `structural-max-fps-60.raw.txt`, plus the `wait_freeze` blocks of `structural-{default,fixed-fps}.json`.

## Checklist (static review plus recorded evidence)

| Item | Static reading | Recorded evidence (not rerun) | Status |
| --- | --- | --- | --- |
| Stale result after reset | `_reset_state` sets `_result = {}` and `_pending_result = false` (`tick_coordinator.gd:182-185`). `take_result` returns `{}` unless a result is pending (`:235-243`). Both the "taken" and "untaken" paths are covered (`contract_driver.gd:122-143`). | Mutation run: both stale checks fail with the fix removed | Fixed (static) |
| Zero/negative cap | `begin_step` returns `(0, truncated)` before unfreezing when `max_ticks <= 0` (`:211-217`). `_physics_process` also guards `tick_count >= max_ticks` (`:263`). Cap 1 gives exactly 1 tick. | Contract and structural checks pass. Mutation shows the old run executed 12 ticks. | Fixed (static); see L2 |
| Residual-motion refusal | The pre-tick envelope check refuses travel above 4.0 m + 1e-6 with `motion_bound` before any motion (`:273-278`). Forward and reverse are tested. | 250 m/s gives `(0, motion_bound)` with zero movement. 240 m/s gives 12 ticks with 0 violations. | Fixed (static); see L3 |
| Independent physics-frame counting | The contract suite counts `SceneTree.physics_frame` itself for requests of 1/7/12/13 (`contract_driver.gd:81-98`) | 30/30 under `--fixed-fps 60` only | Plausible; see L4 |
| 12-tick requests | Budget decrements once per accepted tick and finishes at `_budget == 0` (`:280-293`) | `[12,12,12,12,12]`, total 60 | Consistent |
| Early termination/truncation | Terminal is evaluated after each tick. Termination takes precedence over truncation. A later request returns 0 ticks. | Termination gives 6 ticks. The cap-30 sequence is (12,12,6,0). | Consistent |
| Paused waiting | The tree is frozen after each finished request. `_freeze` guards the `PROCESS_MODE_ALWAYS` callback. | 60 frozen frames give 0 ticks. A free `RigidBody3D` is held. | Holds between requests; **not after reset or after a 0-tick request (M1)** |
| Reset/replay | Pose, RNG seed, events, counters and stats are cleared. A 24-tick replay is bit-exact. | 24/24 events; exact transform and RNG match | Consistent within the one-car scope |
| Backend | The setting is pinned to Jolt and checked each run. Identity is inferred from the setting plus the earlier contrast run. | Setting check passes | Pinned, not observed |
| Accelerated vs real-time fidelity | `compare_modes.py` compares only scalar `final_z`, delta and the error bound on a straight constant-speed open-road trace | 600 ticks each, `|dz|=0`, 58.9x vs 0.995x | **Weak; see M2** |

## Findings, ranked

**M1 (Medium): the freeze gate does not cover the wait after `reset()` or after a zero-tick request.**
- `reset()` calls `set_frozen(false)` and never refreezes (`tick_coordinator.gd:190-194`).
- `begin_step(0)` or `begin_step(n<0)` unfreezes at `:222-223`, then emits a `(0, none)` result at `:224-225` without refreezing.
- The early-return paths at `:208-217` leave whatever pause state was already set.
- So between reset and the first action (the trainer's first policy evaluation), and after a zero-tick request, the authoritative world runs free.
- The structural suite asserts the unfrozen state as intended (`probe_driver.gd:429-430`, "reset: episode open and world unfrozen").
- In this probe no logical tick can occur: the guard `_budget <= 0` holds and the car is moved explicitly. But it contradicts the coordinator's stated contract ("frozen until the next request", `:13-14`) and M0.8's "zero advancement while waiting". Any autonomous body would drift, as `_scenario_wait_freeze` measures for an unpaused `RigidBody3D`.
- Fix: leave the world frozen after `reset()` and after every early-return or zero-tick result. Add a contract test that waits N frames after reset, and after `begin_step(0)`, with an autonomous body present.

**M2 (Medium): the accelerated-vs-real-time fidelity evidence is one scalar on a trivial trace.**
- `compare_modes.py:112-115` compares only the final z (plus an error bound) of a constant 10 m/s straight run with no contact, termination, reset or RNG.
- PLAN M0.8 asks for *measured* accelerated-vs-real-time fidelity "before the motor depends on it". The prior audit's next actions asked for intermediate states and a contact-rich trajectory, and this response did not address that.
- Fix: emit a per-tick trace digest (pose, rotation, RNG draws, events, terminal), and compare the digests across `--fixed-fps 60`, `--max-fps 60` and default pacing for the wall, 65 m/s, termination and reset/replay scenarios.

**L1 (Low): `begin_step` has no in-flight guard.** A second `begin_step` before the pending result arrives resets `_budget` and `_step_elapsed` (`:218-221`). The first request's ticks then never appear in any `elapsed_ticks`, while `tick_count` keeps them. A buggy bridge would get silently inconsistent accounting. Refuse or return an error result while a step is in flight. Also refuse negative `requested_ticks` instead of treating them as 0.

**L2 (Low): the README and the code disagree on cap ≤ 0.** The README says the episode "starts `truncated`". In the code, `observe()` after `reset()` reports `terminal: "none"` until the first `begin_step` (`:211-216`). Either set `episode_terminal = "truncated"` in `reset()`/`_reset_state()` when `max_ticks <= 0`, or correct the wording.

**L3 (Low): the backstop branch counts residual motion without failing the request.**
- `:373-375` increments `motion_bound_violations` but lets the tick, and the request, finish with `terminal` unchanged.
- The mutation run shows this: with the envelope pre-check disabled, "residual deficit is recorded, not silently dropped" still **passes** while the car moves 48 m of 50 (`mutation-sensitivity.txt:26-27`). That check therefore does not by itself prove fail-closed behavior; the terminal/elapsed checks do.
- Make the backstop end the step with `motion_bound` so the two paths agree.
- Mid-request refusal (elapsed > 0 then `motion_bound`) is also untested, because speed is constant per configuration.

**L4 (Low): limits of the frame-counting evidence.**
- The independent count runs only under `--fixed-fps 60`, where 1 physics frame equals 1 process frame (`run_contract_tests.py:65-74`).
- It counts engine iterations, which `physics_frame` emits even while paused, not world steps applied to the body.
- Under default pacing, `frozen_engine_physics_frames` is 50 for 60 waiting process frames (`structural-default.json:125`). The structural inter-request 5-frame wait check (`probe_driver.gd:180-184`) may therefore observe zero physics iterations and pass vacuously.
- Run the contract suite under default and `--max-fps 60` pacing as well, and wait on a physics-frame count rather than a process-frame count.

**L5 (Info): two evidence sets are byte-identical across pacings.** `structural-fixed-fps` and `structural-max-fps-60` have byte-identical `.json` and `.raw.txt` hashes in the manifest, while default pacing differs. That is plausible, since `--max-fps 60` usually gives 1:1 frames, but it cannot be told apart from a copy error without a rerun. The README's different wall times (2 s vs 8 s) are not inside the hashed files.

**L6 (Info): signal and runner hygiene.**
- `step_finished` emits the internal `_result` dictionary by reference (`:434`), so a listener can mutate the stored result before `take_result()`.
- `compare_modes.py` runs in place by default and creates `.godot/` in the repository copy (gitignored). The recorded run used `--project <isolated>`.

## Still open (not claimed by this probe or this review)

- Multi-car reset of velocities, gates, timers and contacts.
- The M1 motor and the contact resolver.
- The training bridge with real IPC.
- Interactive execution through the same coordinator.
- Backend identity observed at runtime.
- Cross-platform determinism.
- The BENCHMARKS 1/2/4-worker throughput, peak memory and real-time parity measurements.
- Rendering, input and controller hardware.

## Recommended next actions

1. Fix M1 and add the post-reset and zero-tick frozen-wait tests.
2. Extend `compare_modes.py` to per-tick digests over the contact, termination and reset scenarios (M2).
3. Address L1-L3.
4. Have an approved runner recompute `manifest.sha256` against `d562755` and rerun the structural, contract and compare suites, so this recheck's NOT VERIFIED runtime items can be closed.
