<!-- Coordinator attestation: Claude CLI JSON exited 0 with is_error=false and modelUsage claude-opus-5-5, provider=firstParty. Review used a separate plain archive of exact source 55aa2497cbd93431f8c4e688e6fde32793787694 (tree f5b93f16b80f80dfe3a97b319adf79245252a8a2). Reviewer text follows verbatim. The later exact-SHA hosted CI run 46088146120 passed all jobs; the reviewer did not see that result in its packet. -->

# Roadstorm scoped repair recheck: Opus 5.5 on candidate `55aa249`

## Identity

| Item | Value |
|---|---|
| Candidate | `55aa2497cbd93431f8c4e688e6fde32793787694` (tree `f5b93f16b80f80dfe3a97b319adf79245252a8a2`, per `evidence/identity.txt`) |
| Base | `316705ddf3063e272da54c704612b11a6a25fdca` |
| Reviewer | Claude Opus 5.5, model ID `claude-opus-5-5`, provider Anthropic, running in Claude Code (Agent SDK). Taken from my own session metadata. |
| Date | 2026-11-28 01:32 CET (from `date`) |
| Scope | Three repair slices only: DriveLab post-COMMITTED gearbox failure, ImpactEvent reciprocal pairing / normalization / duplicate-pair protection, and the SpeedHud committed-gear readout. The M0.2 JSON source schema is absent from this SHA and outside this review. |
| Verdict | **Pass** for the bounded M1 component repair scope. There are no Medium or higher implementation defects. Two Low findings and several test-strength items are listed below. This is not M0, M1, M1.5 or M1.8 acceptance. |

## Files inspected

- **Plans and design:**
  - `PLAN.md` lines 66–82 (M1.1, M1.5, M1.8 and M1 acceptance)
  - `docs/TECHNICAL_DESIGN.md` impact paragraph (the diff and line 73)
- **Prior reports:**
  - `review/implementation/m1-m02-recheck-gpt-6-2-sol-316705d.md`
  - `review/implementation/m1-m02-recheck-opus-5-5-316705d.md`
- **Changed source, read in the frozen archive:**
  - `src/laboratory/drive_lab.gd`: the `step_once`, `restore_drive_snapshot`, `_physics_process`, `_fail`/`_halt`/`_complete`, `_reset_run_state`, `_rollback_pre_tick_gearbox`, `_mark_body_pose_stale`, `_update_presentation` and `_update_speed_hud` paths, plus `make_laboratory_gearbox_config`
  - `src/simulation/automatic_gearbox.gd`: `get_state`, `restore_state`, `mirror_gear`, `restore_and_mirror`, `propose` and `MAX_FORWARD_GEARS`
  - `src/simulation/impact_event.gd`: `is_opposite_perspective`, `validation_error`, `same_payload`, `stable_norm`, `Builder._resolve_normal` / `_unit_from_scaled_length`, `Ledger.publish`, prune, reset and `_pair_key`
  - `src/presentation/speed_hud.gd` and `scenes/ui/speed_hud.tscn`
- **Changed tests and tools (through `evidence/focused-diff.patch` and the archive):**
  - `tools/drive_lab/drive_lab_driver.gd`: `GearboxFaultInjector` and the failure-path cases
  - `tools/drive_lab/run_gearbox_mutant_control.sh`
  - `tools/impact_lab/impact_lab_driver.gd`: the pairing, dup_pair, ambig and large-domain cases
  - `tools/hud_lab/validate_speed_hud.gd`: the gear cases and fit checks
- **Evidence packet:** `identity.txt`, `focused-diff.patch` (12 files), the three `*-independent.log` files, and the three worker reports (skimmed only; I reasoned from source).

## Commands I ran myself

Everything I ran was read-only: `ls`, `cat`, `sed`, `awk`, `grep`, `wc`, `head`, `tail` and `date` over `./source` and `./evidence`.

I ran **no Godot, no test runner, no mutation control and no shell syntax check**. The session was in plan (read-only) mode, so I did not create the isolated copy that executable checks would need. I wrote nothing to `./source`, made no Git changes, did not delegate, and did not consult the other current reviewer.

## Supplied evidence (coordinator logs, not my execution)

| Log | Content | Assessment |
|---|---|---|
| `drive-independent.log` | Pinned Godot 4.7.2 with Jolt: 15 cases, 5,022 checks, 0 failed. `gearbox_integration` has 3,566 checks. It shows the proposal refusal at tick 40, the mirror refusal at tick 70 and "cannot restore … already failed". | Consistent with the new code paths. The 4 ObjectDB instances leaked at exit are pre-existing (T4 in the earlier review). No deliberate-failure DriveLab probe is in this packet's tail. |
| `impact-independent.log` | 21 cases, 580 checks, 0 failed. Includes `opposite_perspective_pairing` (8 negative controls), `duplicate_perspective_pair_refused`, `ambiguous_separator_pair_keys` and `large_finite_vector_domain` (diagonal 3e38 norm 4.24e38). | Consistent with the source. The packet has no impact-specific failing probe. |
| `hud-independent.log` | 296 checks, 0 failed. A deliberate `--expect-failure` run gives 297 checks with 1 failed. Records gear font 32 at 100% and 48 at 150%. | Headless dummy driver, so there is no rendering evidence. |
| Hosted CI on `55aa249` | Not in the packet | Unverified. |

## Disposition of prior material findings

| Prior finding | Status | Evidence |
|---|---|---|
| **Sol 1 (Medium): DriveLab resumes with a diverged body pose; mirror failure leaves the canonical gearbox advanced** | **Closed** | See the breakdown below this table. |
| **Sol 2 / Opus N2: `is_opposite_perspective` pairs unrelated records** | **Closed** | `impact_event.gd:188–206` requires a different `event_id`, both records to have an other car, different primaries, and reciprocal participants. The negative controls cover A→B vs C→D, nonreciprocal, two linked wall records, car vs wall, different tick, missing link, same `event_id` and a self-paired record. They call the predicate directly, so they do not mirror its logic. |
| **Sol 2 (doc): TECHNICAL_DESIGN "unique contact/event ID" and "road/local point" wording** | **Closed** | Now reads "unique event ID per (physical contact, primary car) perspective … world and primary-car-local contact points". |
| **Sol 3: huge diagonal finite normal collapses under `Vector3 / float`** | **Closed** | See the breakdown below this table. |
| **Sol 4: `--log` overwrite and symlink follow** | **Closed** | See the breakdown below this table. |
| **Opus N1: the same perspective published under two IDs** | **Closed for linked records** | See the breakdown below this table. |
| **Opus N4: restore on a failed lab** | **Closed** | `drive_lab.gd:671–674` refuses with an explicit reason before touching anything. The test confirms the pair, the canonical state and the pose block are unchanged and that a reason is recorded. |
| **Opus N3: contact-point frame and `region` at the committed pose** | **Open (M1.8 producer)** | Unchanged and out of these slices. |

**Sol 1 (Medium), DriveLab post-COMMITTED failure:**
- **Gearbox rollback.** `step_once` (`drive_lab.gd:776–804`) saves `pre_tick_gearbox := gearbox.get_state()`, which is a copy (`automatic_gearbox.gd:313`). On a proposal refusal, a mirror refusal, or a mirror that disagrees or is nonfinite, it calls `_rollback_pre_tick_gearbox`, which runs `restore_state`, then `_reject_gearbox_step`.
- **Pose block.** That call sets `_drive_body_pose_stale` with `DRIVE_BODY_POSE_STALE_HALT` and calls `_fail`. The missing or nonfinite committed-state branch (`:762–768`) also marks the pose stale.
- **Published pair.** `state` is assigned only at `:805`, so the published pair is unchanged on every failure branch.
- **Pose block survives `configure()`.** `_reset_run_state` does not clear the block, and `step_once:747` returns before any adapter call while it is set. The flag is assigned only at `:1266`, so nothing in the archive clears it.
- **No false rollback claim.** The reason strings say the canonical gearbox was restored and that no CarState was published. They make no claim about the body.
- **Mirror test is sensitive to a missing rollback.** The lab config upshifts at 8.0 m/s (`drive_lab.gd:385`). The test warms above 8.5 m/s and installs gear 1 with zero dwell, so the real `propose` advances to gear 2 before the injected mirror refusal. A no-rollback mutant therefore fails `canonical_gear_is_pre_tick`.
- **Postconditions tested on both paths:** physical travel above 1e-4, exactly one adapter call, the published pair unchanged, `configure()` accepted with the block kept, and the blocked tick making no adapter call.

**Sol 3, normalization:** `_unit_from_scaled_length` (`impact_event.gd:~509`) divides each scalar component, so every quotient is within [-1, 1]. The test (driver diff, around line 402) pins that `diagonal / diagonal_norm == Vector3.ZERO` on the pinned Standard build, then builds a NORMALIZE event from (3e38, 3e38, 0). The supplied log records this case passing. The `stable_norm` docstring now warns against `Vector3` division.

**Sol 4, mutant runner `--log`:** the `[ -e ] || [ -L ]` pre-check refuses existing files and dangling symlinks. The `( set -C; … >"$log_file" )` write uses noclobber, which closes the race for regular files: a dangling symlink fails exclusive creation. A pre-existing non-regular target is caught by the pre-check, and the race window is negligible.

**Opus N1, same perspective under two IDs:** the `_pair_keys` index (`publish`, around `:664`) refuses a second retained record with the same (`contact_id`, `primary_car_id`). It counts in `refused_count` only, leaves the retained digest unchanged, and the complementary perspective still publishes.
- **Ordering.** The check runs after the event-ID coalesce and conflict checks and before the capacity check, so an identical retry still coalesces.
- **Prune and reset.** Prune erases keys (around `:830`) and `reset` clears them; both are tested.
- **Key is unambiguous.** `_pair_key` (`:845–854`) is `len:contact len:primary`. Parsing the first count delimits the contact exactly and the second count delimits the primary, so the encoding is injective. The U+001F collision control (`ambig.*`) shows a single-separator join would collide and that both records are retained.
- **Unlinked records.** Records with an empty `contact_id` stay outside the index. That is documented as a producer obligation; see the remaining gates.

## Ranked actionable findings

### Implementation defects

**L1. Low (M1.8 contract documentation): the stated producer-retry path for a later tick is wrong.**
- **Where:** `src/simulation/impact_event.gd:546–551`. The text says a contact reported again on a later tick "must either reuse the perspective's `event_id`, so the retry coalesces, or supply a distinct `contact_id` per tick".
- **Why it is wrong:** `same_payload()` compares `tick_index` (`:323`). Reusing a retained `event_id` with a different tick is therefore classified at `publish` (around `:646–660`) as **"conflicting payload"**, refused, and counted in `conflict_count`. It never coalesces.
- **Reproduction (reasoned from source):**
  1. Publish E1 (id `e`, contact `c`, primary `A`, tick 5).
  2. Publish E2 with the same id and payload but tick 6, inside the window. The result is REFUSED with a conflict, not COALESCED.
  3. Publish E3 (id `e'`, contact `c`, primary `A`, tick 6). The result is REFUSED as a duplicate perspective.
- **Consequence:** while the first record is retained, a sustained contact with the same `contact_id` can be republished only under a fresh `contact_id`.
- **Fix:** correct the doc so the only later-tick option is a distinct `contact_id` per tick. Alternatively, make it an explicit design decision that the pair key is not tick-scoped and add a test for the later-tick case.
- **Safety:** this is not unsafe; both outcomes refuse rather than double-count. A future producer written to this doc would see unexpected conflict refusals.

**L2. Low (DriveLab telemetry): a pose-blocked lab can report a completed script without any adapter call.**
- **Where:** `drive_lab.gd:305–325` with `:747`.
- **What happens:** after a post-commit failure, `configure(…, commands)` clears `failed` and `halted`; the pose block remains. If the caller then calls `start()` with auto-tick on, `_physics_process` consumes one scripted command per frame and `step_once` returns `null` silently. At the end, `_complete("script complete")` sets `completed = true` with `halt_reason = "script complete"`.
- **Safety:** this is safe, because no adapter call happens. But `completed` can read as success for a run that executed zero ticks. The `drive_replay_blocked` telemetry is the only signal.
- **Origin:** the path existed at `316705d` for state-only restore and now also covers the failure path.
- **Fix:** have `start()` (or `_physics_process`) refuse or halt with `get_drive_replay_block_reason()` while the pose is stale.

No defect found in:
- the pairing predicate, pair-key injectivity, prune and reset;
- normalization;
- the rollback ordering;
- HUD gear validation atomicity;
- the HUD gear's independence from travel direction.

`_valid_gear` (`speed_hud.gd:~362`) runs inside `_valid_update_inputs` before any widget mutation, and gear text comes only from `state.gear_index`.

### Test-strength gaps and integration risks (not defects)

- **T1. The proposal-refusal test cannot detect a missing rollback.** The injector returns `null` before `super.propose` runs, so `canonical_restored` holds even without rollback. Only the mirror path proves rollback, and adequately so.
- **T2. Two failure branches have no exercising test:**
  - the "mirror disagreed with canonical gear / nonfinite published" branch (`:795–804`);
  - the missing or nonfinite committed-state branch (`:762–768`), which also lacks a pose-block assertion.

  Both are a few lines and reviewable by reading. A fault-injector mode returning a wrong-gear mirror would cover the first.
- **T3. The rollback restore-failed branch is unreachable in tests.** If it ever fired, the failure reason would contain "RESTORE FAILED", but the canonical gearbox would remain advanced with no separate flag. That is acceptable at lab scope.
- **T4. No integrated DriveLab check of the HUD gear readout.** No DriveLab check reads `Contents/GearLabel`. The HUD gear behaviour is proven only in the standalone HUD lab.
- **T5. The HUD shows a stale gear after a valid state-only restore.** `restore_drive_snapshot` (`drive_lab.gd:670–703`) publishes a new `state` at `:695` but does not call `_update_presentation()`. The HUD keeps the previous gear and speed until a reconfigure. Ticks are blocked in that state, so it is only a presentation mismatch.
- **T6. The HUD domain is broader than the active configuration.** `MAX_GEAR_INDEX := 8` (`speed_hud.gd:104`) is a hand-maintained copy of `AutomaticGearbox.MAX_FORWARD_GEARS` (`automatic_gearbox.gd:92`) with no cross-check test. The HUD also accepts gears 7–8 when the active config has 6. That is by design, because presentation does not see the configuration.
- **T7. Gear fit checks use limited metrics.** They use the headless fallback font and exclude the 4 px outline. `GEAR_RECT` is 28 px wide at 32 px font (`speed_hud.gd:90`). Readability with the final font is unverified.
- **T8. The diagonal normalization witness depends on the build.** The `diagonal / norm == ZERO` check would fail on a double-precision engine build. That is acceptable because the engine is pinned, but worth a comment.

## Verdict

**Pass** for the bounded M1 component repair scope (the DriveLab failure path, the ImpactEvent pairing / normalization / duplicate-pair work and the SpeedHud gear readout). L1 and L2 are Low and can be fixed in a follow-up. T1–T5 are recommended test hardening. This verdict rests on my reading of the source plus the coordinator-supplied logs; I executed nothing.

## Capability limits

- I ran no engine, tests or mutation controls.
- No visual, rendered-HUD, contrast, audio, controller, Linux or Windows launch, or release-rights evidence was reviewed or claimed.
- Hosted CI for `55aa249` is unverified.

## Remaining gates (not satisfied by this candidate)

- **M1.8:**
  - the coordinator-owned physical producer, covering committed tick ceiling, participant identity, contact-ID allocation (L1), contact-only severity sampling, and local point / `region` in the committed frame (N3);
  - reset and grid behaviour;
  - a producer-side guard against double publication for unlinked records;
  - the cosmetic consumer and isolation from it.
- **M1.1:**
  - a body-pose reconciliation operation, which is the only way out of the pose block;
  - reset;
  - gear threshold and dwell calibration;
  - shift audio.
- **M1.5:**
  - rendered HUD and visual review;
  - an integrated gear-readout check (T4);
  - cameras, rear view and feedback listening evidence.
- **Whole M1:**
  - M1.2–M1.4 graybox, adhesion, landing and multi-wall work;
  - M1.3 drift and surge;
  - M1.6 keyboard and controller runs;
  - M1.7 calibration fixtures (5% sweeper target, stock/max comparison);
  - 30/60/120 FPS trace tolerances;
  - capability-labelled motion review.
- **M0 / M0.2:**
  - the versioned source schema and importer/baker with missing-field refusal;
  - conversion tests, content hashes and provenance;
  - remaining definition resources;
  - M0.3 rights and notices (OI-02, OI-03);
  - M0.4 entry points;
  - whole-M0 boot, smoke and desktop acceptance, with target-platform launch evidence recorded separately.
