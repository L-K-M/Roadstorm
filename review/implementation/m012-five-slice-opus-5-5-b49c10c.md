# Independent Opus 5.5 checkpoint review: exact b49c10c (five scoped slices)

- **Reviewer route / identity as observed:** Pi harness, `PI_PROVIDER=venice`, `PI_MODEL=claude-opus-5-5`, identifying as Claude Opus 5.5. No helpers or sub-agents were used. I did not read the current GPT-6.2 Sol report or contact that reviewer.
- **Candidate:** `b49c10c88bfce7b4d84669fb700a0c9c6971bf51`. The docs-only `e9cbe2b` was not reviewed as source.
- **Archive:** `work/agents/coordinator/checkpoint-b49-opus-20261128/source.tar`. `shasum -a 256` gives `be3cdd8dd0280dd11543ada5e8ffdd386272685712469388a1ae2be7209b8a50`, which matches `source.tar.sha256` and the task statement. I extracted it fresh to `…/checkpoint-b49-opus-20261128/priv/proj` (no `.godot` present; live `.godot` not imported). I read the commit diffs with read-only `git show` in the live repo and compared them against the archive files.
- **Prior findings rechecked:** Opus 9f9ef37 S1 (seam ray leak) and Sol 9f9ef37 finding 1 (accepted retry reads mutable `adapter_config`).
- **Time box:** about 20 minutes. The depth was bounded to fit: see Limits.

## Commands and results

Every Godot call used pinned `4.7.2.stable.official.ed1daf0bf` (`--version` confirmed it). Each call ran with private `HOME`/`TMPDIR`/`XDG_*` under `priv/` and `/usr/bin/lockf -k …/godot-test.lock timeout -k 5 120`. The wrapper is `run_godot.sh` and the logs are in `logs/`. The error gate greps `SCRIPT ERROR|^ERROR|ERROR:` and was applied even on rc 0.

| Run | rc | Gate hits | Result |
| --- | --- | --- | --- |
| `--import --quit-after 1` | 0 | 0 | ok |
| practice_flow_lab.gd | 0 | 0 | 31/31, 2 cycles |
| practice_flow_lab.gd `-- --expect-failure` | 1 | 0 | 1 deliberate failure, so nonzero exit as intended |
| tools/smoke/boot_smoke.gd | 0 | 0 | `PASS: M0 shell boots … DriveLab-backed practice scene` |
| validate_drive_lab.gd (all cases) | 0 | 0 | 5,428/5,428. `wall_impact_integration` 330 checks, `config_retry_coalesced=5`, changed-hull oracle region `right`. One `WARNING: 4 ObjectDB instances were leaked at exit` (not a gate hit; baseline not compared). |
| validate_cosmetic_damage_lab.gd | 0 | 0 | 86/86 |
| cosmetic failure_probe.gd | 3 | 0 | deliberate failure |
| hairpin_first_tick_probe.tscn | 0 | 0 | 47/47. 1 adapter step and 1 committed tick; final speed 17.9991664886475 m/s |
| hairpin failure_probe.gd | 3 | 0 | deliberate failure |
| validate_road_strip_seam_lab.gd | 0 | 0 | 2 cases, 14 checks, 460 poses, 2,300 rays. k=1 (24 chunks): center_miss 26/230, ungrounded 11/230. k=1024 (1 chunk): 0 and 0. |
| seam failure_probe.gd | 3 | 0 | deliberate failure |
| private `review_opus/seam_breakdown.gd` (sha256 `5eaf546f…`, a copy of the seam lab that prints each center miss) | 0 | 0 | See finding F1 |

I did not use the tracked shell runners (`run_practice_flow_lab.sh`, the cosmetic and hairpin `run_validation.sh`, or the drive_lab runner). I invoked the same validator entry points directly so that every engine call stayed under the mandated lock. The bad-config fixture and the gearbox mutant control were not run.

## Findings, ordered by severity

### F1. Medium (slice 5, recheck of prior S1): the seam defect is confirmed and is more concentrated than "26/230" suggests. The lab asserts none of the measurements it reports.

Reproduced exactly: k=1 gives 26/230 center misses and 11/230 ungrounded poses; k=1024 gives 0 and 0. The private breakdown adds the following:

- **All 26 misses are at `FORWARD_OFFSETS = 0.0`**, the exact shared-row poses. None of the +1 mm control poses miss. The exact-seam miss rate is therefore **26/115 (22.6%)**, not 11.3%. The headline denominator mixes 115 control poses with the 115 seam poses (`validate_road_strip_seam_lab.gd:21,224-229`). Misses occur at every lateral fraction (−0.4:4, −0.2:3, 0.0:6, 0.2:7, 0.4:6), so this is not an edge effect.
- **The 11 ungrounded poses are mostly not caused by footprint misses.** In 5 of them, all four footprint rays hit (`footprint_support_count=4`) but `grounding_cluster_size=0`. Under `Basis.IDENTITY` on the banked bend, the four world-down footprint distances spread by more than `footprint_support_spread_max_m = 0.25` (`ground_support_probe.gd:154`), or tie 2+2, so the fallback refuses (`ground_support_probe.gd:428-439`). The lab poses the probe body world-upright (`validate_road_strip_seam_lab.gd:227-228`), whereas a car on a bank would be rolled with it. The 11/230 figure therefore depends on the lab's pose choice. It is neither an upper nor a lower bound for an in-car seam outcome. The footprint rays themselves are identical across k: the support histograms differ by exactly the 26 center rays.
- **k=1024 zero does not mean "no defect inside a shape".** Interior rows are still triangle edges there, and the k=1024 center rays hit them. So the leak is specific to separate shapes and bodies, which is consistent with prior S1. On its own, the 1-chunk result does not justify shipping one shape per course: shape size, BVH and streaming were not tested.
- **Test blind spot:** the 14 checks cover only bake success, chunk count, Jolt backend, config/box match, status OK, 5 queries used and pose/ray budgets (`:84-92,100,106,127-128,263-264`). No check asserts `center_miss_count > 0` for k=1 (that the defect reproduces) or `== 0` for k=1024. A remedy or a regression produces the same green result, and the failure probe is a generic harness control that never touches seam geometry. The README and evidence packet correctly call this a diagnostic baseline, not seam safety. **I am not treating the pass as seam safety.** The S1 gate on M2.1 integration and drivability remains open. A collision remedy and remeasurement are still required, as the packet itself states.

Reproduce: `run_godot.sh seam_breakdown --fixed-fps 60 --path priv/proj --script res://review_opus/seam_breakdown.gd`, then `grep OPUS_MISS logs/seam_breakdown.log`.

### F2. Low (slice 2): retry silently returns false if the onset coalesced rather than published

`_wall_event_accepted_record` is set only on `is_published()` (`src/laboratory/drive_lab.gd:1186-1190`), not on the coalesced branch (`:1192-1196`). After that, `publish_wall_event` returns false with no counter or diagnostic (`:1042-1044`), although the doc comment says every refusal is recorded. With a per-scope ledger and unique policy IDs, I found no reachable path in normal operation. It is reachable only if a caller swaps in the public `wall_event_ledger` already holding the record. This is not a correctness defect in the scoped contract.

**Prior Sol finding 1 is resolved.** The retry now replays a copy of the saved accepted record and never calls the producer or reads `adapter_config` (`drive_lab.gd:1042-1057`). The record is cleared on each new committed tick (`:1407`) and on retirement (`:848`). The new regression (`drive_lab_driver.gd:4169-4340`) covers the following, all of which I ran green:

- an untouched control;
- zero hull;
- a 10× valid hull, with an oracle precondition that the region differs (`right`), so the test is not vacuous;
- restore;
- a tampered-ledger conflict that is refused, fabricates nothing and leaves the real ledger untouched;
- a coalesce after the conflict;
- refusal after retirement.

Each check also verifies there was no adapter step, no committed tick, and no change to state, pose or policy.

### F3. Low (slices 1, 3, 4): runner hygiene gaps in the tracked shell runners (read, not executed)

- `tools/practice_flow_lab/run_practice_flow_lab.sh:150-157` runs Godot under `timeout` but takes no shared test lock (no `lockf` anywhere in the file), and `--timeout` has no upper bound (`:63-85`). The hairpin runner caps at 120 s (`calibration_hairpin_physical_lab/run_validation.sh:105`). On this shared machine, concurrent invocations can contend with other agents' serialized Godot runs.
- The hairpin runner (`run_validation.sh:167-171`) and the cosmetic runner (`run_validation.sh:179-180`) fall back to `${TMPDIR:-/tmp}` when no `work/agents` exists, as in a plain archive. On macOS that is `/var/folders/…`, which conflicts with the project's avoid-/var scratch rule. Both delete only their own `mktemp` directories, so this is not data-unsafe.

### F4. Informational (slice 3): bounded retention trades idempotency at eviction

After more than 512 retained events, `_store_event` evicts the oldest ID (`cosmetic_damage_state.gd:703-710`). A replay of an evicted ID is then refused as `TICK_OUT_OF_ORDER` if its tick is older than the watermark (`:511-516`) rather than coalesced. If its tick equals the watermark (which requires more than 512 events on one tick), it is re-applied. Contact-ID eviction (`:713-720`) has the same window. This only matters at stress volumes. Worth a documented bound or a test that pins the behavior.

## Slice notes (verified, no finding)

1. **e799bf6 practice entry.**
   - `src/boot/game.gd` sets KEYBOARD mode in `_ready` before the first physics tick. Escape is handled through `ui_cancel` and the public `return_to_menu()`.
   - The overlay reports `failed` first, then `halted`, with fallback text. The scene comment claims no second camera, viewport or motor step.
   - The flow lab checks two menu cycles, camera/HUD teardown and the forced-halt overlay (31/31), and boot smoke passed.
   - Not checked: rendering, real devices, and the unchecked `change_scene_to_file` return value (`game.gd:44`, minor).
2. **e5683ab wall retry.** See F2. The primary recheck passes.
3. **f97f3f9 CosmeticDamageState.**
   - Regions are cloned on configure (`:425-436`). Accumulation stops after detach, so post-detach values stay finite (`:626-629`).
   - Exact-payload retries coalesce, and a conflicting payload under the same ID is refused before the watermark is checked (`:497-509`).
   - Stored events are copies, and retention is bounded (F4).
   - The effect toggle and cooldown never change part state (`:663-667`). The reducer has no simulation imports or writes. 86/86 checks green.
4. **b34e2d4 hairpin first tick.** It is real DriveLab/Jolt evidence for exactly one committed tick at 18 m/s. The README (`:10-12`) explicitly disclaims turn, steering, sustained contact, calibration, pace and M1.7. Real first-tick evidence is clearly distinguished from the missing sustained-turn calibration.
5. **b49c10c seam diagnostic.** See F1.

## Scoped verdict

| Slice | Verdict |
| --- | --- |
| 1 Practice entry (e799bf6) | PASS (scoped); F3 runner lock gap is Low |
| 2 Accepted wall retry (e5683ab) | PASS (scoped). Prior Sol mutable-config defect resolved and regression-covered; F2 Low |
| 3 Cosmetic reducer (f97f3f9) | PASS (scoped, pure reducer only); F4 informational |
| 4 Hairpin first tick (b34e2d4) | PASS (scoped to one tick); claims correctly limited |
| 5 Seam diagnostic (b49c10c) | PASS **as a diagnostic only**. The measurements reproduce. The prior S1 seam defect is **confirmed and still open** (22.6% of exact-seam center rays miss with per-segment chunks). The lab gates none of these numbers (F1). |

No slice needs CHANGES REQUIRED for what it claims. F1 must keep gating M2.1 strip integration and drivability. Its fix is a collision remedy plus an asserted remeasurement: k-variant miss counts and car-rolled poses on banked sections.

## Limits

- This is not M0–M9, M1.7, M1.8, M2.1 or M5.9 acceptance. Provider-rights items OI-02/OI-03 were not assessed and remain open.
- All tests were headless. There was no rendered, audio, device, split-screen, sustained-contact or car-dynamics seam crossing, and no falling-through test.
- I did not execute the tracked shell runners, the DriveLab bad-config fixture or the gearbox mutant control. F3 comes from reading the runners.
- I gave the cosmetic reducer (861 lines) and the practice-flow lab (491 lines) a targeted reading, not a line-by-line audit, within the 20-minute box.
- I did not compare the ObjectDB leak warning in the DriveLab run against the parent commit.
