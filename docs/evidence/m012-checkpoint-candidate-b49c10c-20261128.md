# M0/M1/M2 interim checkpoint candidate, 28 November 2026

Exact combined source: `b49c10c88bfce7b4d84669fb700a0c9c6971bf51` on shared `main`, after five scoped commits `e799bf6`, `e5683ab`, `f97f3f9`, `b34e2d4`, `b49c10c`. This is an interim implementation checkpoint, not milestone acceptance. The required independent Opus 5.5 and GPT-6.2 Sol reviews on this exact revision are due.

| Scope | Coordinator's pinned Godot 4.7.2/Jolt result | Limit |
| --- | --- | --- |
| Boot/menu to graybox Driving Lab | Isolated flow 31/31: two menu entries, 14 committed input ticks per cycle, finite 0.2131 m movement, return by Escape and public method, teardown, forced-halt diagnostic. Boot smoke passed. Deliberate flow failure nonzero. | No rendered, controller, handling, race, split-screen, M0.2 or M5 acceptance. |
| Accepted wall retry | Frozen DriveLab 17 cases/5,428 checks; bad-config 99; deliberate failure rc 3. Invalid and changed live hulls coalesce saved accepted payload, ledger conflict refuses, retired scope refuses. | One car/head-on authored wall; M1.8 remains open. Exact corrected-source named rechecks due. |
| Cosmetic part-state reducer | Frozen 13 cases/86 checks; deliberate failure rc 3. Validated region copies and finite post-detach accumulation included. | Pure reducer only; no meshes, debris, effects, audio, integration or M5.9 acceptance. |
| Hairpin physical first tick | Frozen real DriveLab/Jolt 47/47; one COMMITTED tick at 18 m/s, ending 17.9991665 m/s and 0.2999916 m station; deliberate failure rc 3. | No steering, sustained contact, calibration, pace, M1.7 acceptance. |
| Banked road strip support | Frozen real GroundSupportProbe/Jolt diagnostic 2 cases/14 checks, 460 poses/2,300 rays; deliberate failure rc 3. With one-segment collision chunks: 26/230 center misses, 11/230 ungrounded. With one chunk: zero of each. | Confirms a seam-support defect; no falling-through claim or M2.1 acceptance. A collision remedy and remeasurement are required. |

Each scoped run used a private plain source archive with only owned-file overlays, or the tracked isolated runner, private engine state, bounded Godot calls and the shared test lock. Live `.godot` was not imported. The exact logs and source hashes are under ignored `work/agents/coordinator/` (practice, wall-source, cosmetic-final, hairpin-final, seam-validation directories). Worker reports are evidence inputs, not acceptance decisions. The five commits are the review candidate; combined-source regression and the named pair follow.

The user confirmed LongCat and StepFun accounts use standard public terms. `provenance/OPEN_ITEMS.md` OI-02/OI-03 remain open for release rights; neither this checkpoint nor the user's copyright assertion clears them. All whole M0–M9 milestones, including M4B, remain open.
