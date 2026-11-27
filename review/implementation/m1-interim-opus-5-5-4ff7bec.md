> Coordinator identity and source attestation: Claude Code JSON records `claude-opus-5-5`, provider `firstParty`, successful completion. The reviewer inspected a separate immutable `git archive` snapshot of candidate `4ff7becfdadea1788c6ba2606f4ae61d50b4b8b5`. The reviewer output follows verbatim.

# Roadstorm interim M1 review: Opus 5.5, candidate `4ff7bec`

**Scoped verdict: changes required, in one area.** The new yaw constraint in `motor_body_adapter.gd` closes the prior High rotated-hull finding only partly. Every other supported prior finding in scope is closed. The DriveLab camera/HUD wiring and the five-ray support probe have no blocking defects.

**M1 acceptance: open.** Nothing in this candidate shows adhesion, landing, the contact-response feel, reset placement, visual interpolation, a frame-rate trace or hardware behaviour.

| Item | Value |
| --- | --- |
| Reviewer | Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, run through Claude Code (Claude Agent SDK) |
| Candidate | `4ff7becfdadea1788c6ba2606f4ae61d50b4b8b5`, base `15c53ad` (20 commits, 48 files, +8083/−107) |
| Archive identity | `git ls-tree --full-tree -r 4ff7bec` compared with `git hash-object --no-filters`: **1,096/1,096 files match, 0 extra** |

## Findings, most severe first

### F1. Medium: the yaw constraint skips its world probe for small per-tick yaw, so the overlap bound is not enforced
- **Where:** `src/simulation/motor_body_adapter.gd:453-454`.
- **What happens:** the probe runs only when `0.5·|hull diagonal|·|Δyaw|` is more than `orientation_contact_tolerance_m`. With the 1.8×1.0×3.8 m hull and the 0.02 m default, that is |Δyaw| ≤ 0.00925 rad per tick, about **0.555 rad/s**. Gentle steering stays below that: the body lab's `yaw_gain_grip = 0.12` with steer × speed under 4.6 m/s, for example full lock at 4 m/s or steer 0.2 at 20 m/s.
- **Why the skip is unsafe:** it assumes the tick-start pose already clears by the tolerance, and nothing establishes that.
- **Repro, reasoned with a Python geometry mirror:** park the hull parallel to the wall with 5 cm clearance and turn toward it at 0.0092 rad per tick. The corner passes the wall plane plus the 2 cm allowance by tick 5, and no probe ever runs.
- **What happens on the next ticks:** when `move_and_collide` returns null, the adapter uses `actual = motion` and commits `start.origin + accepted` (`:385-388`, `:514-516`). Any Jolt recovery offset is therefore thrown away, and the overlap persists.
- **The refusal it leads to:** a later tick above the threshold probes the tick-start heading, finds overlap and returns `REFUSED_ORIENTATION` (`:462-472`). DriveLab treats any refusal as a permanent failure.
- **Not verified:** whether a Jolt cast collision with recovery cuts the build-up short in practice. Even the bound for one skipped tick (about 2 cm on top of an already allowed 2 cm) can exceed the lab's 3 cm no-tunnel gate.
- **Test gap:** the only regression, `_case_rotated_hull_wall_orientation`, uses about 3° per tick, far above the skip threshold. No case drives steering below the threshold toward a wall.
- **Fix:** always probe when Δyaw ≠ 0 (one `intersect_shape` per tick is cheap), or skip only after the tick-start pose has been verified clear by at least the tolerance. Add a Jolt case at about 0.5 rad/s toward a wall 5 cm away over at least 30 ticks, with the hull-plane assertion on every tick.

### F2. Low to medium, feel risk: the constraint can slow steering away from a wall the car is scraping
- **Where:** the rotation pivots on the hull centre (`_hull_overlaps_at` at `final_origin`).
- **What happens:** in a right-side scrape (`commit_safe_margin_m = 0` in both labs), turning left swings the rear-right corner into the wall by about 1.9·θ. The bisection then limits Δyaw to about 0.0105 rad per tick, until translation has opened a gap. Heading recovers roughly exponentially, at rate v/1.9 per second, which is sluggish at low speed.
- **Why it matters:** this works against the design rule "wall brushes scrub speed without gluing the car to a barrier" (`docs/GAME_DESIGN.md`).
- **Not tested:** no case covers scrape-then-steer-away. Record it as an M1.4 contact-response acceptance case, or pivot the constraint check about a more appropriate point.

### F3. Low, latent: the orientation probe rejects every collider, but the doc says wall-like only
- **Where:** `:93-94`, `:465`, `:470`, `:602-617`.
- **What happens:** `_hull_overlaps_at` reports any intersection within the body mask, floors included. The probe box is only 2 cm smaller than the hull. Once adhesion puts the hull on ramps, kerbs, crests or the graybox steps, steering would be constrained, or refused when the start heading overlaps the floor.
- **Scope:** flat-ground only today, which the adapter states. Correct the doc wording now, and require a floor-aware probe or a support-aligned basis before adhesion integration.

### F4. Low: the support probe's grounding rule differs from its own contract
- **Where:** `src/simulation/ground_support_probe.gd:38-40` against `:365-367`.
- **The mismatch:** the doc grounds on "at least `required_footprint_hits` legal footprint hits whose support distances agree". The code requires **all** legal footprint hits to fall within the spread.
- **Repro:** the centre ray misses at a seam. Three footprints are on the road and one is over a shoulder 0.3 m lower, still inside `max_support_distance_m`. Result: not grounded, although three hits agree. If the same shoulder is deeper than 0.75 m, that hit is discarded and the car is grounded again, so the decision is non-monotonic.
- **Test gap:** `_case_uneven_support_spread` only covers a 2-against-2 split. Under the doc's wording either pair should ground, yet the test asserts not grounded. The `spread` mutant therefore pins the implementation, not the documented contract.
- **Fix:** choose a rule (largest agreeing cluster, or all hits) and add a 3+1 case.

### F5. Medium, latent, known open: the tilted-wall road-plane response (prior Sol 3)
- **Status:** unchanged. `_apply_wall_response` (`:665`) still removes inward speed along the full 3D normal, and the road-plane conversion then drops the vertical part. Normals with |y| ≤ 0.5 still count as walls.
- **Severity now:** not reachable in the current labs, which have only vertical walls and a flat basis. It becomes real with banked barriers or sloped kerbs.
- **Fix before M1 acceptance:** respond against the normalized road-plane projection of the normal. The new authoritative-normal selection does not affect this.

### F6. Low, latent: DriveLab copies the builder's heading straight into `CarState`
- **Where:** `src/laboratory/drive_lab.gd:527/532`.
- **What happens:** the builder's heading grows to the left (`handling_lab_builder.gd:160-162`). DriveLab copies it into `CarState` without conversion, and `_course_limit_reached` (`:566`) assumes the straight runs along road +y.
- **Why it is latent:** every bay currently has `yaw_deg = 0.0` (`handling_lab_data.gd`). It becomes a real bug for any rotated bay. This is the prior "one explicit conversion" open item, now inside an integration.

### F7. Nits
- **Inconsistent refusal shape:** `REFUSED_ORIENTATION` sets `committed_state = null`, but `REFUSED_MOTION_BOUND` returns `state_in.copy()`. The doc comment on `step()` (`:299-300`) does not list the new status.
- **Counters not reset:** `_reset_run_state` does not reset `hud_updates`, `hud_rejected_updates`, `hud_error` or the camera counters, and it calls `_update_presentation()`, so a reconfigure inflates `hud_updates`.
- **Wall corners:** `_select_wall_response_normal` corrects one wall per tick, so inward speed into a second wall at a corner survives one tick. This is M1.4 multi-contact work.
- **Prior N3 adapter checks still open:** no check that the body basis matches `state_in`'s heading, no check that the shape belongs to the body, the `CollisionShape3D` offset is ignored, and only local scale is checked.

## Prior findings in scope

| Finding | Status at `4ff7bec` |
| --- | --- |
| Drift hold reset at ENTRY→SUSTAINED (Opus N1) | **Closed.** `preserve_holds` (`drift_phase_model.gd:399-402`, `:477-487`); `entry_promotion_hold_continuity` case exists. |
| Yaw penetration (Sol High) | **Partly closed.** Above-threshold yaw is constrained and tested; see F1 and F2. |
| Collision-mask query (Sol 2) | **Closed.** `query.collision_mask = body.collision_mask` in both the cast and the new probe. |
| Wall-normal retention (Opus N2) | **Closed in logic.** The most-opposed wall normal is retained separately. Evidence is a seam test plus one real Jolt wall; two-contact Jolt ordering is not measured, as you said. |
| Reverse boundary (Sol 5) | **Closed.** Strict `<` (`arcade_motor.gd:265`); docs and comments match. |
| Graybox first restart (Opus N5) | **Closed.** `_split_runs` only splits while a run is open. |
| Nonfinite audio (Sol 4) | **Closed.** Gains capped at 1e6 and a nonfinite-sample refusal before finalization. My earlier Nyquist and `pow` nits are untouched. |
| Reset one-second hold (Opus F5) | **Component only.** `ResetHoldGate` is correct: double accumulation fires at exactly tick 60 (checked), and it keys on `reset_held` with fresh-press suppression. Nothing calls it, so reset integration is acceptance work. |
| Tilted wall (Sol 3) | **Open** (F5). |
| Builder vs `CarState` heading convention | **Open** (F6). |

**DriveLab camera/HUD wiring:** no defects found.
- There is exactly one adapter call site, and HUD/camera are refreshed only after a committed tick. The HUD cue is honestly fixed at GRIP. Presentation keys never touch simulation state.
- The camera snaps once per physics tick, with no smoothing and no visual interpolation. That is not a defect for a lab, but `docs/TECHNICAL_DESIGN.md` requires interpolating the visual transform before the frame-rate acceptance traces.
- `attach_to_viewport` moves the rig out of the lab subtree. `_exit_tree` frees it, so there is no leak.

**Support probe:** sound as a sensor apart from F4. It casts exactly five rays after validation and refusal, uses the mask and excludes the body RID, applies the world-up normal gate and the upright frame gate, and gets the corner labels right. Things to settle in M1.4:
- A legal central hit up to 0.25 m below the hull bottom counts as grounded.
- The spread check uses distances along the frame axis, so an unpitched frame on a 12% grade gives a footprint spread of about 0.39 m.

## Checks run and evidence used

**Run myself, all read-only:**
- The blob-hash identity check above.
- `git log` and `git diff 15c53ad..4ff7bec` for the scoped files.
- Full reads of `ground_support_probe.gd`, `drive_lab.gd` and `reset_hold_gate.gd`, plus the adapter step and response code.
- Targeted reads of the camera rig, the body-lab and support-lab cases, the READMEs, the design docs and the latest `STATUS.md` entries.
- One `python3 -I -c` mirror for the reset float accumulation and the F1 yaw threshold and overlap geometry.

**Not run:** Godot or Jolt.

**Used as supplied, not reproduced:**
- `../evidence` logs: body lab 12 cases/2,233 checks; the old source fails the wall-normal case at 1 case/10 checks; DriveLab 10 cases/1,209 checks, bad config 99, deliberate failure rc=3; support lab 14 cases/660 checks with 8 mutants detected.
- These are coordinator overlay runs. No exact-SHA hosted CI exists for `4ff7bec`. The body, drive and support labs are still outside CI discovery (`tools/ci/ci.sh:1351`, `tests/` and `tools/smoke/` only).
- `STATUS.md` makes no acceptance claim, and its yaw-fix entry correctly says the fix is not a zero-penetration guarantee. It does not mention the skip threshold in F1.

## Limits
- Static review only: no engine runs, no rendering, no listening, no gamepad, no launches on target operating systems, no frame-rate trace.
- I did not run Jolt's recovery behaviour for F1. The persistent-overlap path is shown from the code; how large the overlap actually grows in Jolt is not measured.
- No files edited, no Git changes, no agents spawned, no network or GUI use.