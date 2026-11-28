# M0/M1/M2 interim checkpoint: exact `b49c10c` dual-review decision

Date: 2026-11-28 UTC. Reviewed source: `b49c10c88bfce7b4d84669fb700a0c9c6971bf51` (archive sha256 `be3cdd8dd0280dd11543ada5e8ffdd386272685712469388a1ae2be7209b8a50`). The later docs-only commit `e9cbe2b` was outside the reviewed source. Both reviewers worked from their own immutable plain archives with pinned Godot 4.7.2 (`4.7.2.stable.official.ed1daf0bf`), private `HOME`/`TMPDIR`/XDG and `/usr/bin/lockf -k` on the shared engine lock.

Reviews: [Opus 5.5](../review/implementation/m012-five-slice-opus-5-5-b49c10c.md), [GPT-6.2 Sol](../review/implementation/m012-five-slice-gpt-6-2-sol-b49c10c.md).

## Verdicts

| Slice | Commit | Opus 5.5 | GPT-6.2 Sol |
| --- | --- | --- | --- |
| Practice entry (menu to real DriveLab) | `e799bf6` | PASS (scoped) | PASS (scoped) |
| Accepted wall retry independent of live config | `e5683ab` | PASS (scoped) | PASS (scoped) |
| Cosmetic part-state reducer | `f97f3f9` | PASS (scoped, pure reducer) | PASS (scoped) with two diagnostic defects |
| One-tick physical hairpin proof | `b34e2d4` | PASS (one tick) | PASS (one tick) with a runner cancellation defect |
| Strip seam diagnostic | `b49c10c` | PASS as diagnostic only; defect confirmed | PASS as diagnostic only; defect confirmed |

Both reviewers reproduced the seam measurement: 26/230 center misses and 11/230 ungrounded poses at one segment per chunk versus 0/230 for both with a single chunk. Opus adds that every miss is at an exact shared row (26/115 seam poses, 22.6%) and that the lab asserts none of the numbers it prints. Hosted CI on the pushed revision passed all four declared jobs.

## Accepted findings and dispositions

| # | Severity | Finding | Disposition |
| --- | --- | --- | --- |
| Sol 1 | Medium | Hairpin runner continues after HUP/INT/TERM, can signal a stale PID | Repair dispatched to free Seaglass Alpha (`work/agents/coordinator/m17-hairpin-runner-cancel-seaglass-20261128`). Gate stays open until its cancellation control and frozen rerun pass. |
| Sol 2 | Low | Cosmetic coalesce counted twice (0 to 2 to 4) | Repair dispatched to LongCat 2.5 (`work/agents/coordinator/m18-cosmetic-sol-findings-longcat-20261128`). |
| Sol 3 | Low | `content_digest()` sorts retained contacts, hiding FIFO eviction order | Same LongCat job. |
| Sol 4 | Low | Practice lab teardown check misses root-level HUD leftovers | Repair dispatched to StepFun 5 Preview (`work/agents/coordinator/m02-practice-sol-findings-stepfun-20261128`). |
| Opus F1 | Medium | Seam defect confirmed; lab asserts nothing | Collision remedy dispatched to GLM 5.4 (`work/agents/coordinator/m21-collision-seam-glm54-retry-20261128`); asserted remeasurement with car-rolled banked poses follows. M2.1 and drivability gates remain open. |
| Opus F2 | Low | Wall retry returns false with no counter when the onset coalesced | Coordinator-owned small patch with a regression case; not yet started. |
| Opus F3 | Low | Runner hygiene: practice runner lacks the shared lock and an upper timeout bound; hairpin and cosmetic runners fall back to `/var` scratch | Practice runner in the StepFun job; hairpin runner in the Seaglass job; cosmetic runner after the LongCat job releases that path. |
| Opus F4 | Informational | Bounded retention trades idempotency at eviction | Document the bound or pin the behavior after the current cosmetic repair lands. |
| Sol (audio) | Low | Four ObjectDB audio instances at exit in headless runs | Residual headless audio resources; no cumulative growth across two cycles. Not attributed to the game or the dummy backend yet. |

## Still open

Whole M0 to M9 milestones, including M4B. The seam defect keeps M2.1 closed. The one committed tick does not close M1.7. The wall and cosmetic scoped passes do not close M1.8 or M5.9. The practice checks do not close M0.2 or M5. Provider-rights items OI-02 and OI-03 remain open for release rights. Rendered GUI, audio output, real devices, sustained calibration, swept seam traversal and target-platform exports were outside this checkpoint. A windowed desktop check of the imported exact archive (menu, graybox car, 31 km/h in second gear, Escape return) passed with no engine errors, but it is synthetic input, not handling-quality or hardware signoff.
