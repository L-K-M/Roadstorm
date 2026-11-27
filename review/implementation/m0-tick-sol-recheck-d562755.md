# M0.8 independent tick, query and reset recheck

**Verdict — pass for the minimal M0.8 probe.** The exact candidate passes the independent-callback and structural suites, the injected failure returns nonzero, and both 600-tick pacing modes produce the same final state in this trace.

| Item | Review scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `d562755c83af1129b4ddf7043baee8d8a742d358`, committed 2026-11-27 04:19:05 +01:00 |
| Base | `55b04cec80fc842d1f40b5ac393a8a6492f112f3` |
| Review date | 2026-11-27, Europe/Zurich |
| Files | `tools/tick_probe/**`, M0.8 in `PLAN.md`, movement ownership in `docs/TECHNICAL_DESIGN.md`, numerical and compute evidence in `docs/BENCHMARKS.md`, and the prior audit at `work/agents/1b8fe3ed-3088-4847-a0e1-ea1676abc013/m08-probe-audit/REPORT.md`. |

## Findings

1. **Resolved · Reset result ownership.** Both previously consumed and still-pending step results are unavailable after reset. Structural checks show exact pose, rotation, seeded RNG draws, event count and distance/substep totals on replay. [Reset and result handling](../../tools/tick_probe/src/tick_coordinator.gd#L159)
2. **Resolved · Exhausted budget and over-bound commands.** Caps of 0 and below truncate with no motion or logical advance. The one-tick cap consumes one tick. The supported 240 m/s boundary completes the request with bounded substeps, while faster forward and reverse commands are refused before movement and report the residual. [Budget gate](../../tools/tick_probe/src/tick_coordinator.gd#L207) · [Motion preflight](../../tools/tick_probe/src/tick_coordinator.gd#L260)
3. **Verified · Logical ticks are tied to callbacks.** In the independent suite the requested 1, 7, 12, and 13 steps match a separate `SceneTree.physics_frame` tally. During a trainer wait frame callbacks continue while the logical count and body pose remain unchanged. A direct-motion control moved the probe body while producing zero logical ticks. The structural path terminates at tick 6 and truncates a thirty-tick scenario after 12 + 12 + 6 ticks. Requests after either ending consume zero. [Independent checks](../../tools/tick_probe/tests/contract_driver.gd) · [M0.8 requirement](../../PLAN.md#L63)
4. **Verified · Same-host trace fidelity.** Structural wall motion follows committed physics and stops at the wall face with no tunneled endpoint. The accelerated and real-time open-road traces each consumed 600 ticks at 1/60 s and ended at z = −99.999641418 m with zero between-mode difference in final position. Wall times in this run were 0.186 s and 10.004 s, about 53.9× and 1.00× relative to simulated time. These are this probe's measurements under current host load. [Pacing comparison](../../tools/tick_probe/compare_modes.py)

No new blocking defect in the checkpoint scope. The finite one-car commands, open-road/wall queries, and probe-state reset exercised here establish the coordinator mechanics. M1 still needs motor and pair-contact fidelity, multi-car reset and progress semantics, and interactive/headless equivalence. The setting pins Jolt and the historical contrast distinguishes that setting from GodotPhysics3D. The current GDScript run did not query instantiated backend identity directly. No rendering, controller, audio, cross-platform equality, full-simulation throughput, or 1/2/4-worker training benchmark is claimed. [Probe limitations](../../tools/tick_probe/README.md) · [Compute evidence protocol](../../docs/BENCHMARKS.md#L80)

## Verification

I confirmed the destination is ignored and exported `git archive d562755` into `work/agents/sol-tick-20261127/snapshot/`. Godot reported `4.7.2.stable.official.ed1daf0bf`. Headless runs used separate probe copies or the contract runner's own isolation, with private home, temporary, cache and output paths. Logs are in the snapshot's parent.

| Command from the snapshot | Result |
| --- | --- |
| `python3 tools/tick_probe/tests/run_contract_tests.py --out ../contract --timeout 25` | Exit 0. All 30 checks passed. |
| `godot --headless --fixed-fps 60 --path ../structure/project --script res://src/tick_probe.gd -- mode=structural` | Exit 0. All 73 checks passed. |
| `python3 ../comparison/project/compare_modes.py --timeout 25` | Exit 0. All 10 comparisons passed over 600 ticks per mode. |
| Same fixed-FPS headless probe with `mode=throughput requests=2 inject_failure=1` | Exit 1 within the 15 s external timeout. The JSON reports one failure and names the injected control. |
| `shasum -a 256 -c evidence/2026-11-27-apple-m4-max-jolt-contract/manifest.sha256` from `tools/tick_probe/` | All 26 entries agree, including probe sources, test sources and recorded evidence. |

The live suite totals match the coordinator's copied-tree results. I reviewed the recorded pre-fix and mutation evidence through the audit and the bound manifest. I did not mutate the candidate or repeat the historical alternate-backend comparison.
