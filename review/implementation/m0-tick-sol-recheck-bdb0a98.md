# M0.8 independent tick, wait and reset follow-up

**Verdict — changes required.** The probe reproduces the expected logical motion and pacing fidelity, but its callback-count test fails intermittently under max-FPS pacing and two immediate request paths violate the documented API.

| Item | Scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `bdb0a9820b847d23628cce35a9070bb63ae17acd`, committed 2026-11-27 04:53:11 +01:00 |
| Base | `d562755c83af1129b4ddf7043baee8d8a742d358` |
| Review date | 2026-11-27, Europe/Zurich |
| Inputs | `tools/tick_probe/**`, M0.8 in `PLAN.md`, `docs/TECHNICAL_DESIGN.md` movement ownership, previous Opus report for job `64cbe5b0-7cc7-4130-80a3-cfc7d4d59f43`, and my d562755 report. |

## Ranked findings

1. **Medium · Callback-accounting evidence is intermittently red at max-FPS pacing.** The first max-FPS run, launched concurrently with the fixed/default contract runs, structural run and pacing comparison, had two failures. After those processes exited, three max-FPS reruns on the same project copy, run one at a time, produced three, three, and zero failures respectively. For example, a one-tick request advanced exactly one logical tick while both engine-frame tallies advanced twice. The driver starts the tally before requesting work and ends it after polling on `process_frame`, which can include a physics callback after synchronous completion. That timing explanation follows from the sampled window and needs a signal-boundary test to confirm when the extra callback occurs. Record the independent tally at `step_finished` or explicitly partition active callbacks and callbacks after completion. Preserve the test that further frames while frozen advance no logical state. I did not observe extra logical ticks. [Polling and sampling](../../tools/tick_probe/tests/contract_driver.gd#L93)
2. **Low · A terminal episode accepts a negative request and returns it as a valid result.** After a one-tick cap truncates and its result is consumed, my scratch probe calls `begin_step(-2)`. It returns true and publishes `requested_ticks = -2`, zero elapsed ticks, and `terminal = truncated`. The terminal fast path precedes the negative-request guard. Validate negative requests before the terminal response and assert that they neither create a result nor alter tick or pose state. [Request ordering](../../tools/tick_probe/src/tick_coordinator.gd#L224)
3. **Low · A zero-tick completion is published while unpaused.** After reset, `begin_step(0)` returns with the tree frozen, but my synchronous `step_finished` listener observes `SceneTree.paused == false` when the result is emitted. No physics callback advanced in this probe. Keep the freeze in effect through empty-request completion and publish only after the waiting state is in place. The same scratch script also confirms that a zero-cap `reset()` returns observation terminal `none`, despite the README saying an episode starts truncated. Make the documented initial state and the observation agree. [Zero-tick path](../../tools/tick_probe/src/tick_coordinator.gd#L244) · [Exhausted-budget contract](../../tools/tick_probe/README.md#L124)

## Verified behavior and limits

The contract tests use an independent falling rigid body. They reproduce freezing during post-reset and post-step waits and after an empty request returns, with motion only on positive work. The structure suite verifies early termination and truncation, replay equality, stale-result invalidation, immediate zero/negative-cap request results, refusal of ordinary in-flight and unconsumed-result overlap, and over-envelope command refusal before its next logical tick. The in-loop residual backstop visibly returns a terminal failure in source and is not independently reachable through the supported probe configuration. It should not be cited as measured atomic rollback.

The accelerated and real-time traces each completed 600 ticks at 1/60 s, with identical final z of −99.999641418 m (0.233 s vs 10.001 s wall time in this run). The added intermediate trace agrees across fixed, default, and max-FPS pacing, with zero observed difference across its checked fields. These are same-host, headless, single-car results. Full motor/query planning, multi-car reset and contact resolution, interactive/gameplay behavior, and platform or performance acceptance remain open.

## Commands and evidence

I verified the destination is ignored and exported `git archive bdb0a98` to `work/agents/sol-tick-2-20261127/snapshot/`. Each execution used a separate project copy, private home and temporary paths, and bounded subprocess timeouts. Godot reported `4.7.2.stable.official.ed1daf0bf`. All paths below are relative to the snapshot unless noted.

| Command | Result |
| --- | --- |
| `godot --headless --path <private project> --script res://tests/contract_entry.gd` with no pacing option, `--fixed-fps 60`, or `--max-fps 60` | Fixed and default each 51/51. Max-FPS first run 49/51. Serial reruns 48/51, 48/51, 51/51. Logs in `../contract-{fixed,default,max}/`. |
| `godot --headless --fixed-fps 60 --path <private project> --script res://src/tick_probe.gd -- mode=structural` | Exit 0, 99/99. Log in `../structure/run.log`. |
| `python3 ../comparison/project/compare_modes.py --timeout 25` | Exit 0. Throughput and intermediate comparisons pass. Log in `../comparison/run.log`. |
| `godot --headless --fixed-fps 60 --path ../edge/project --script res://edge_review.gd` | Bounded scratch harness captures findings 2–3 without editing candidate source. Script and output under `../edge/`. |
| `shasum -a 256 -c evidence/2026-11-27-apple-m4-max-jolt-waitguard/manifest.sha256` from `tools/tick_probe/` | All 34 listed entries match. |

The coordinator's copied candidate passed all three paced contract runs. My serial reruns confirm that max-FPS has both passing and failing outcomes on this host.
