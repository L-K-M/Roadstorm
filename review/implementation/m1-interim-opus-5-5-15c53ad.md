> Coordinator identity attestation: Claude Code JSON `modelUsage.claude-opus-5-5.canonicalModel=claude-opus-5-5`, `provider=firstParty`; output captured from read-only immutable archive of `15c53addd2ab37dbce8ac68f05c7cb58a7c9eba7`. Reviewer text follows verbatim.

# Roadstorm independent interim M1 recheck: Opus 5.5, candidate `15c53ad`

**Verdict for the scoped M1 component changes: pass.** I reviewed the code statically and assessed the coordinator's runs; I did not run Godot myself. Every earlier M1 finding in scope is fixed or now has a recorded decision. The new findings below are low severity or latent, and none blocks this interim checkpoint.

**M1 acceptance: open.** No integrated car exists yet. Adhesion, contact response, controls on real hardware, how the car feels, what the audio sounds like, the frame-rate and four-view costs, and launches on the target operating systems are all unverified.

| Item | Value |
| --- | --- |
| Reviewer | Claude Opus 5.5 (`claude-opus-5-5`), provider Anthropic, run through Claude Code (Claude Agent SDK) |
| Candidate | `15c53addd2ab37dbce8ac68f05c7cb58a7c9eba7` |
| Base | `b29f910` |
| Date | 2026-11-27 |
| Range | 17 commits, 34 files, +6963/−230 |

## Findings, most severe first

### N1. Low: moving from ENTRY to SUSTAINED clears the exit holds, which contradicts the new class doc
- **Where:** `src/simulation/drift_phase_model.gd:396-398` calls `_begin_phase(proposed, Phase.SUSTAINED)`, and `:470-481` sets `unwind_hold_s` and `low_speed_hold_s` to 0.
- **Contract it breaks:** the class doc at `:22-23` says each exit condition "accumulates independently ... cannot mask a mature exit".
- **Repro:** I mirrored the logic in Python with the defaults: 0.2 s entry blend (12 ticks) and 0.15 s unwind hold (9 ticks). If the player unwinds steering from ENTRY tick 5 onward, recovery happens at tick 21. That is 17 continuous unwind ticks instead of 9. Starting the unwind at ticks 1 to 4 exits correctly from ENTRY.
- **Size of the effect:** the extra delay is at most about 8 ticks (0.13 s). The low-speed hold behaves the same way, but reaching it from ENTRY is unlikely because entry needs more than 12 m/s forward speed.
- **Fix:** keep both hold values across the ENTRY to SUSTAINED change. Add a case with unwind from ENTRY tick 5 that expects recovery 9 ticks after the unwind starts.

### N2. Low, latent: the wall response can use a floor normal
- **Where:** `src/simulation/motor_body_adapter.gd:327-334, 376-377`.
- **What happens:** `wall_hit` stays true once set, but `hit_normal` is overwritten on every collision.
- **Repro:** one substep grazes a wall but travels the full segment, so the loop continues. A later substep reports a floor or ramp contact. The response then runs with the floor normal. Road-plane velocity dotted with that normal is 0, so the function returns the velocity unchanged and the wall's inward velocity is kept.
- **Why it is latent:** the body lab floats the hull 5 cm above the ground (`tools/body_lab/body_lab_checks.gd:17`, hull height 1.0), so floor contacts never occur there. They will once adhesion puts the hull on the ground.
- **Fix:** store the normal of the wall contact separately (or apply the response per wall contact). Add a test with a grounded hull hitting a wall.

### N3. Low: some adapter inputs are not checked against each other
All in `motor_body_adapter.gd:256-269`:
- It does not check that the body's start basis matches `basis_from_heading(state_in.heading_rad)`. A mismatched body is swept in the wrong orientation for one tick, then snapped to the state's heading.
- It does not check that `hull_shape` belongs to the body.
- It ignores the `CollisionShape3D` local offset. `_cast_safe_fraction` (`:445`) uses the body's origin, so the prediction diagnostics drift away from what `move_and_collide` actually does.
- It checks `body.scale`, which is local scale only; a scaled parent is not caught.

Related: the heading change is committed at `:380-383` without a rotational sweep. With a yaw rate of about 2 rad/s, a 3.8 m hull's corner can end up about 6 cm inside a wall. Depenetration is already listed as M1.4 work, so record this as an M1.4 requirement.

### N4. Low, evidence and process gap: most of the new labs are not in canonical CI
- Hosted CI only discovers scripts under `tests/` and `tools/smoke/` (`tools/ci/ci.sh:1326`). Of the scoped checks, only `tests/handling/pure_motor_entry.gd` runs in hosted CI.
- The body, drift, camera, audio and graybox validators are run only by the coordinator.
- The body-adapter evidence (1763 checks) dates from `143cb6e`. The motor it calls changed afterwards, in `63fe27a` and `15c53ad`. The body lab only drives forward, so the signed-yaw change probably does not affect it, but it has not been rerun on the exact candidate.
- No hosted CI result exists yet for `15c53ad`.

### N5. Low, latent: the builder can fail on an empty run
- **Where:** `src/laboratory/handling_lab_builder.gd:95, 98`.
- `_split_runs` (`:378`) adds an empty run when the very first sample has `break_before` set, for example a bay whose first segment is a restart strip.
- `run[0]` then indexes an empty array. No current bay is built that way.
- **Fix:** skip empty runs, or only split when `current` is non-empty.

### N6. Nits
- **Adapter doc mismatch:** `Result.proposed_state` and `committed_state` are documented as "Null on refusal" (`:192-195`), but `REFUSED_MOTION_BOUND` fills in both (`:275, 288, 367`).
- **Camera dead code (`camera_rig.gd:413-414`):** the fallback negates a vector that is already near zero, so it can never help.
- **Camera misleading comment (`:419-420`):** it says the guard protects `refine_desired_pose`, but the guard runs before refine (`:437`). What actually protects refine's output is `_assign_camera_transform`'s orthonormal check.
- **Camera orthonormal check (`:507+`):** it does not reject reflections. That is reachable only through the refine hook.
- **Audio inner loop (`vehicle_feedback_synth.gd:486-490`):** it recomputes `pow(n, rolloff)` per harmonic per sample.
- **Audio validation (`:107-148, 208-236`):** it allows `top_hz`, the harmonic count and `resonance_hz` to go above Nyquist at low sample rates.
- **Audio speed docs:** `EngineParams` and `TireParams` say "forward ground speed" (`:268, 336`), but `render_bundle` passes the speed magnitude (`:619-622`).

## Earlier findings: what is now fixed

| Earlier finding | Status at `15c53ad` |
| --- | --- |
| Opus F1 / Sol 1: 1 m holes at section joins, and a 6 m jump gap instead of 5 m | **Fixed.** Every non-gap section now starts with its exact start cross-section (`handling_lab_builder.gd:243-262`). There are no internal end caps at ordinary joins (`:90-99`). Restart strips reset `s` and break the run. New probes cover the joins (±0.25 m and ±5 mm), the restart strips, and the jump gap. The coordinator's Jolt run measured a 4.999985 m gap. A zero-width crack between separate trimesh bodies remains; see the design notes. |
| Opus F2 / Sol 2: reverse engaged while rolling backward | **Fixed.** Engagement now uses road-plane speed magnitude (`arcade_motor.gd:265`). Tests cover −5 m/s rolling back, a −20 m/s lateral slide, and exactly ±1 m/s, and they check that the full hold elapses after deceleration. While airborne, releasing the brake or applying throttle clears a partial hold (`:246-252`). |
| Opus F4: reverse steering turned the wrong way | **Fixed.** Yaw now uses signed forward speed (`:329`): reversing inverts it, and pure lateral sliding gives no yaw. Covered by `_case_signed_longitudinal_steering`. |
| Opus F3: airborne snapped the drift blend; landing started at blend 0 | **Fixed, plus a recorded decision.** Airborne keeps the outgoing blend and drains it over 0.5 s (`:538-541`). Landing recovery starts from what remains (`:438-440`). The class doc now says the future adhesion layer owns grounded hysteresis. `rewards_suppressed` is exposed. |
| Opus F6: low-speed exit used only forward speed | **Fixed.** It now uses ground speed (`:359-360`), with a test (`_case_high_slip_ground_speed`). |
| Sol 3: unwind could mask a low-speed exit | **Fixed** with `_advance_holds`, an oscillating-steer test, and a deterministic order when both mature together. N1 is the one remaining gap, at the phase boundary. |
| Sol 4: a zero tap threshold disabled drift entry | **Fixed.** Validation now requires a positive threshold (`:143-146`). |
| Sol 5: singular or scaled camera poses | **Fixed.** Target bases are rejected using a determinant-to-volume ratio. Camera poses must be orthonormal before they are assigned. A rear view with a scaled target is normalized. Smoothing never interpolates from a collapsed basis. |
| Adapter unbounded epsilon / silent truncation (coordinator finding) | **Fixed.** Absolute caps of 32 substeps and 1 m per substep. Epsilons are capped as a fraction of one substep. Any leftover travel is refused unless a real contact stopped the sweep (`:356-369`). The body is restored when refused. |
| Opus F5: reset needs a one-second hold | **Not in this candidate.** The input worker handling it is outside `15c53ad`. Still open. |
| Drift direction transition; Standard-assist brake taps triggering on trail braking; the lab and `CarState` use opposite heading conventions | **Still open.** These are plan gaps and design risks. The adapter adds a tested road-to-world mapping, but the lab builder still uses a heading that grows to the left (`handling_lab_builder.gd:160-162`). Integration needs one explicit conversion. |

Other things I confirmed while reading:
- The adapter's axis mapping is consistent with `CarState`, and `basis_from_heading` is right-handed: right × up = back.
- The adapter commits through one `move_and_collide` per substep and never calls `move_and_slide`.
- The audio synth is pure and deterministic for a given seed, has a bounded frame count, limits peaks downward only, and fades to zero at the loop seam.

## Recommendations that depend on design choices, not code correctness
1. **Who debounces "grounded":** the drift model leaves grounded hysteresis to the adhesion layer, but `docs/TECHNICAL_DESIGN.md:85` does not say so. Until it does, a single ungrounded tick still ends a sustained drift: it goes to RECOVERY on landing. The move is now smooth, but the drift still ends. Record this as an M1.4 adhesion contract.
2. **Recovery swallows taps:** any landing, even from GRIP, enters RECOVERY with blend 0, which blocks drift entry for 0.35 s and consumes a handbrake tap made in that window (`:445`). This behaviour predates the candidate. Decide whether that is intended.
3. **Seams between road sections:** joined sections are separate trimesh bodies, so the coordinator's run found that rays exactly on three seams miss, and a sliding box can catch on internal edges. Either merge joined runs into one collision body with per-face surface tags, or require footprint probes plus a box-sweep test across joins in M1.4.
4. **Audio playback model:** each render is a 0.5 s segment at a fixed pitch with fades at both ends. A continuous engine sound therefore depends on the future `AudioDirector` crossfading segments. GDScript per-sample cost for 4 to 8 cars has not been measured.

## Commands I ran (read-only)
- `git ls-tree`, `git rev-parse` and `git hash-object --no-filters` over the archive: **1075/1075 files match `15c53ad`, 0 mismatched.**
- `git log` and `git diff b29f910 15c53ad` for the scoped files, `docs/STATUS.md` and `docs/IMPLEMENTATION_LOG.md`.
- Read in full: `motor_body_adapter.gd`, `vehicle_feedback_synth.gd`, and the changed parts of `arcade_motor.gd`, `drift_phase_model.gd`, `camera_rig.gd` and `handling_lab_builder.gd`. Read selected cases in `pure_motor_entry.gd`, `validate_drift_lab.gd`, `validate_handling_lab.gd`, the body lab and `ci.sh` test discovery.
- Read both earlier `m1-interim-*-b29f910.md` reports, and grepped `PLAN.md` M1, `docs/GAME_DESIGN.md` and `docs/TECHNICAL_DESIGN.md`.
- One `python3 -I` heredoc mirror of the drift ENTRY and SUSTAINED hold logic. It wrote no files and produced the N1 numbers.

## Capabilities and limits
- **No Godot or Jolt runs of my own.** The session was in read-only plan mode, so I did not use the sibling `build/` directory. The Python mirror is a reimplementation, not an engine run.
- **Coordinator evidence I assessed but did not reproduce.** All logs show Godot 4.7.2.stable.official.ed1daf0bf, and every suite has a deliberate-failure proof.

  | Suite | Result |
  | --- | --- |
  | Body adapter | 9 cases / 1763 checks |
  | Audio | 8 cases / 155 checks |
  | Motor | 17 cases / 5187 checks |
  | Camera | 186 checks |
  | Drift | 15 cases / 308 checks |
  | Graybox (Jolt) | 886 checks, plus 9/9 safety checks |

  The logs do not record which SHA they ran on. Going by commit order, the body-lab result predates the final motor changes.
- **Hosted CI** passed on `101c95a` and `e46f396`, but there is no result for `15c53ad`.
- **Not checked:** how the car feels, what the audio sounds like, a physical gamepad, launches on the target operating systems, and the live one-car, reset and CI workers outside this candidate.
- I spawned no agents and edited no source or Git state.
