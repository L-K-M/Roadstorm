# Roadstorm interim M1 component review: Opus 5.5, candidate `b29f910`

**Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), from Anthropic, run through Claude Code.
**Candidate:** `b29f9106b07e193f4b2744472ba4830a7294211d`
**Scope:** an interim review of the components delivered so far. It is not M1 acceptance, and it says nothing about release readiness.
**Verdict:** **CHANGES REQUIRED.** Two code defects need fixing (F1 and F2). F3 needs a fix or a recorded decision. Camera, HUD and one-slot input pass statically, with notes.

## Method and limits

- **Archive identity.** I compared every file in `source/` with the `b29f910` tree using read-only `git rev-parse b29f910:<path>` and `git hash-object` (without `-w`). All 1,058 files matched, with none missing or different. `source/` has no `.git` of its own. Git resolves to the parent repository, and I did not mutate it.
- **Reading.** I read every scoped source file in full: `driver_command`, `car_state`, `arcade_motor`, `drift_phase_model`, `one_slot_controls`, `camera_rig`, `speed_hud` and its `.tscn`, `handling_lab*.gd` and `handling_lab.tscn`. I also read the relevant validator sections and PLAN M1, GAME_DESIGN "Controls" and "Handling and drift", and TECHNICAL_DESIGN on DriverCommand, tick ownership and movement.
- **My own checks.** I ran two inline Python mirrors of the GDScript logic with `python3 -I` from a heredoc. No files were written.
  - **Lab sampling and run splitting** (`_sample_bay` plus `_split_runs`): it found the uncovered intervals listed under F1.
  - **Reverse gate** (`arcade_motor.gd:250-264`): with forward speed −5 m/s, brake 1, no braking deceleration and no drag, reverse engaged at tick 18 in my mirror. The coordinator saw tick 20 under its own tuning, so the exact tick count may differ.
  - **Brake re-press:** with 8 m/s² braking, a brake press while rolling back at −5 m/s re-engaged reverse at tick 18 while the car was still moving at −2.73 m/s.
- **What I did not do.** I did not run pinned Godot or Jolt. The session was read-only apart from the review file, so I could not write probe scripts. The `godot` binary on the PATH (Homebrew) is not verified as the pinned build. The Python mirrors are reimplementations, not engine runs. The coordinator's six suite results are supplied evidence; I did not reproduce them. I spawned no agents and created no branches or worktrees.

## Findings, most severe first

### F1. High, code defect: the handling lab has holes at every section join, and the jump gap is 6 m instead of 5 m
**Where:** `src/laboratory/handling_lab_builder.gd`, `_split_runs` (around lines 347-364), together with `_sample_bay` (around lines 204-305).

**What happens:**
- Each new run starts at the first sample inside the new segment, which is one step (up to 1 m) past the boundary. The previous run ends at the boundary sample.
- No geometry covers the space between the two runs.
- Each run gets 1 m-deep end caps (`ROAD_THICKNESS_M`), so every join is a slot roughly 1 m wide and 1 m deep with nothing below it. Only the recovery pad has a slab under it.

**Uncovered stations (s, metres) from my mirror:**

| Bay | Uncovered intervals |
| --- | --- |
| sweeper | 50.0–51.0, 238.5–239.5 |
| hairpin | 30.0–31.0, 124.2–125.2 |
| bank | 30–31, 60–61, 90–91, 130–131, 160–161 |
| grounding | 60–61, 84–85, 144–145, 168–169 (crest and compression joins) |
| jump | 20–21, **35–41**, 80–81 |
| gravel | 50.0–51.0, **80–81**, **160–161**, 238.5–239.5 (both asphalt↔gravel transitions) |

**Why it matters:**
- The jump manifest records a 5 m gap ending at s=40, but the landing geometry starts at s=41.
- The holes sit exactly on the features M1.4 adhesion and surface-transition checks need: crest, compression, bank transitions and gravel boundaries.
- Per TECHNICAL_DESIGN, the car uses a central probe plus four footprint probes. Those probes would read "no ground" at each join.
- The 669 validator checks miss this because the ray probes sample only mid-section points or s=10 m (`_collect_probes`, around lines 573-626).
- A minor related issue: the `restart_at_origin` strips start 1 m ahead of the road, and their stations continue from 120 m instead of restarting at 0.

**Fix:**
- Start each run, unless `break_before` is set, with a copy of the previous run's last sample pose, relabelled with the new run's surface and section.
- Make the first sample after a gap land exactly at the gap's end.
- Reset `s` for restarted strips.
- Add validator rays at every in-bay join (s ± 0.25 m), and check measured geometry gap length against `gap_m`.

### F2. High, code defect: reverse engages while rolling backward (confirms the coordinator's probe)
**Where:** `src/simulation/arcade_motor.gd:254`, which tests `forward_speed <= tuning.reverse_trigger_speed_m_s`.

**What happens:**
- The comparison uses signed speed, so any backward speed passes the "below 1 m/s" trigger.
- Holding the brake for 0.3 s at any backward speed engages reverse, and reverse drive then accelerates the car backward.
- **How a player hits it:** while reversing, release the brake briefly, then press it again to stop. Reverse re-engages after 0.3 s and the car keeps reversing. Rolling back down a slope hits it too.

**Why it matters:**
- It breaks the GAME_DESIGN rules "brake becomes reverse below 1 m/s" and "reversing never initiates at road speed".
- M1 acceptance lists reverse explicitly.
- The tests missed it because `tests/handling/pure_motor_entry.gd` only starts from positive speeds (around lines 842-876), and its engagement assertion (line 375) is also signed.

**Fix:** use `absf(forward_speed)`, or ground-speed magnitude, at line 254. Add a regression test for −5 m/s with braking 0 and with braking 8, brake held for 120 ticks. Reverse must stay disengaged until |v| ≤ trigger and the full hold has elapsed after that point. Assert on |v| at engagement.

### F3. Medium, contract deviation (fix or record a decision): one ungrounded tick ends a drift abruptly, and landing does not blend
**Where:** `src/simulation/drift_phase_model.gd`:
- `grounded == false` moves ENTRY, SUSTAINED or RECOVERY straight to AIRBORNE with no hold (lines 344-346, 359-361, 384-386, 408-410).
- AIRBORNE blend is 0 (lines 510-511), so drift influence drops from 1 to 0 within one tick.
- Landing enters RECOVERY with start blend 0 (line 432), which means instant full grip at whatever slip angle the car lands with.

**Why it matters:**
- The class doc (lines 21-23) says every exit uses a hold timer.
- GAME_DESIGN says airborne should "suppress drift *rewards*", that recovery should align "without snapping", and that a "stable landing blends back into grip".
- `tools/drift_lab/validate_drift_lab.gd:671` asserts the current behaviour, so it was a deliberate reading of the design, but that reading conflicts with the text.
- Probe noise, small crests, or the F1 seams would collapse drifts.

**Fix:** decide which layer debounces grounded state (adhesion hysteresis or this model) and document it. Then either preserve or decay the blend while airborne, or start landing recovery from the blend the car had at takeoff.

### F4. Medium, needs a decision: reverse steering turns the opposite way to a real car
**Where:** `arcade_motor.gd:314-315`. Yaw is `steer * gain * |ground_speed|`.

**What happens:**
- In reverse, steering right rotates the nose right, so the rear swings left.
- A real car (and a kinematic bicycle model) does the opposite.
- This is undocumented and affects reverse and recovery manoeuvres.

**Also:** lateral-only sliding at zero forward speed still produces yaw, because the speed term includes lateral velocity.

**Fix:** use signed forward speed, or record the arcade convention as intentional.

### F5. Medium, plan gap: the reset command cannot express the required one-second hold
**Where:**
- `driver_command.gd:8-9, 29-30`: `reset_requested` is a rising edge only.
- `one_slot_controls.gd:140-149`: the input layer emits only that edge.

**Why it matters:** GAME_DESIGN requires an "explicit one-second hold". No layer can currently measure hold duration from the command.

**Fix:** decide before reset integration. Either add a `reset_held` level to the command, or time the hold in the input layer.

### F6. Low, design risk and plan gaps in the drift model
- **Low-speed exit uses only the forward component** (`drift_phase_model.gd:321, 336`). At 60° slip and 16 m/s ground speed, the forward component is 8 m/s, which triggers low-speed recovery while the car is still fast. Consider ground speed for this exit.
- **No direction-change transition.** `drift_sign` is fixed at entry, and PLAN M1.3's "transition" phase is not implemented. This is a plan gap, not a bug.
- **Standard-assist brake-tap entry** (lines 328-331, 489-490) fires on ordinary trail braking: brake ≥ 0.5 with |steer| ≥ 0.5 above 12 m/s. This follows the design text, but it is a risk for the M1.6 and M1.7 grip-competitiveness checks with Standard-assist bots.

### F7. Low, presentation and integration notes
- **HUD REVERSE label** (`speed_hud.gd:249`) follows backward motion, not `reverse_engaged`. It shows REVERSE when the car is rolling backward without reverse engaged, and shows nothing when reverse is engaged at a standstill. There is no gear indicator yet; gears are still open.
- **Duplicate phase enums.** `speed_hud.gd:53-59` duplicates `DriftPhaseModel.Phase`. The order matches today; add a mapping or a validator check so they cannot drift apart.
- **Hood-mode rear view** (`camera_rig.gd:394-396`) looks backward from the hood position, through the car body. Chase rear view looks backward from 7.2 m behind the car. A per-mode rear offset is a polish item.
- **Opposite frame conventions.**
  - The lab and camera use −Z forward, with heading growing to the left (`handling_lab_builder.gd:145`).
  - `CarState` uses +y forward, with heading positive to the right (`car_state.gd:5-13`).
  - The future adapter needs one tested conversion helper.
- **Digital steering release** (`one_slot_controls.gd:135-139`) ramps back to centre at the same 4/s rate, leaving about 0.25 s of residual steer. This is tuning.
- **Nit:** the HUD outline size does not scale with HUD scale.

## Components with no consequential defect found (static reading only)
- `DriverCommand`: clamping, refusal of non-finite values, and `is_normalized`.
- `CarState`: data record, copy and finiteness checks.
- `ArcadeMotor`: the non-reverse parts, including curve validation, drag not crossing zero, and refusal of non-finite proposals.
- `OneSlotControls`: atomic validation, and suppression of the reset edge after `clear_lifecycle_state`.
- `CameraRig`: horizon stabilisation, rejection of non-finite poses, and a single owned camera.
- `SpeedHud`: rejects invalid input before changing any widget, and gives every phase a redundant shape and text cue.

## Open gates (missing features, not defects)
Integration of the motor/body adapter and audio; adhesion, swept movement and contacts (M1.4); surge; surface modifiers; gears; reset policy and immunity; airborne yaw correction; drift direction transition; committed impact events (M1.8); esses and drafting fixtures (M1.7); CalibrationDriver; keyboard and controller captures; the 30/60/120 FPS trace; four-view cost; perceptual, handling and fun review; target-OS verification. Every coefficient remains provisional.

## Recommended next fixes (bounded)
1. **F2:** a one-line fix plus negative-speed regression cases in `pure_motor_entry.gd`.
2. **F1:** builder run continuity and gap-end alignment, plus join and gap-length probes in `validate_handling_lab.gd`.
3. **F3:** debounce the airborne transition and blend landing recovery, or record a design decision and fix the class doc. Update the validator either way.
4. **F4 and F5:** record decisions on reverse steering and the reset hold before reset and adapter integration.

A scoped recheck on the fixed source should cover the motor reverse cases, the lab geometry continuity, and the drift airborne and landing behaviour, run under pinned Godot/Jolt on an immutable snapshot.
