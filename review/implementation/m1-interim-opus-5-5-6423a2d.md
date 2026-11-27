<!-- Coordinator identity attestation: first-party Claude CLI JSON modelUsage reports claude-opus-5-5; source candidate 6423a2dffabbceff6e3d5a6fbafb9bc84d993ca4; read-only independent archive. The review text below is the reviewer result verbatim. -->

# Roadstorm interim M1 review: Opus 5.5, candidate `6423a2d`

**Scoped verdict: changes required.**

All six prior findings in scope are closed or partly closed in the code. Two new defects should be fixed before the slices are relied on:
- **Audio:** the new audio wiring plays tire scrub while the car reverses in a straight line.
- **Support probe:** the selected support identity can belong to a hit that did not ground the car.

Both are bounded fixes. Neither is a gap in M1 acceptance.

## Reviewer, candidate and scope

- **Model:** Opus 5.5 (`claude-opus-5-5`), Anthropic, running in the Claude Code CLI. I used no helpers or subagents.
- **Candidate:** `6423a2dffabbceff6e3d5a6fbafb9bc84d993ca4`, tree `be5642ed…`. **Base:** `4ff7becf…`.
- **Source scope:** the plain export in `source/`, plus `../evidence/change-list.txt` and `diff.patch`.
- **Not used:** the live checkout, and any current peer report. I read the prior `4ff7bec` Opus and Sol reports only to check finding disposition.

## What I inspected and ran

- **Read in full:**
  - `src/simulation/motor_body_adapter.gd`
  - `src/simulation/automatic_gearbox.gd`
  - `src/audio/vehicle_feedback_player.gd`
- **Read in the relevant parts:**
  - `src/simulation/ground_support_probe.gd` (diff and lines 385–530)
  - `src/laboratory/drive_lab.gd` (lifecycle, focus, audio, spawn heading, course limit, reset)
  - `src/simulation/car_state.gd`
  - `src/simulation/arcade_motor.gd` (yaw and reverse parameters)
  - the synth tire-intensity and default-tuning code
- **Tests:** I read these test cases:
  - support lab: `coherent_cluster_three_plus_one`, `support_identity`
  - body lab: the `yaw_constrained_velocity_policy` header and the full case list
  - DriveLab: the focus case and the audio oracle
- **Commands:** `cat`, `sed`, `grep`, and `wc` on source and evidence. `python3 -I -B -c` for the numeric reproductions below.
- **Godot not run.** `/opt/homebrew/bin/godot` exists, but this session was in read-only plan mode, and an import writes `.godot` caches and temp stages. Every pass/fail count below is supplied coordinator evidence, not my own run.

## Evidence and its limits

The supplied logs show these results, all headless on pinned Godot 4.7.2 with Jolt on macOS:

| Suite | Cases | Checks | Other |
|---|---|---|---|
| Body lab | 16 | 2599 | |
| DriveLab | 14 | 1377 | bad-config 99/99; deliberate failure exits nonzero |
| Gear lab | 8 | 3051 | intentional failure proof |
| Support lab | 16 | 846 | 8 mutants detected |

- `yaw-body.log` contains only the summary line, with no per-case detail.
- The old-source failures the coordinator describes (for example "1/194, 0.534 m/s") do not appear in the supplied logs. I treat them as coordinator statements.
- None of this is perceptual, rendered-frame-rate, controller or target-platform evidence.

## Findings, most severe first

### F1. Medium: the wired audio plays tire scrub during straight-line reverse
- **Where:**
  - `src/audio/vehicle_feedback_player.gd:226, 238–240, 384–395`
  - `src/simulation/car_state.gd:92–99`
  - reached through `src/laboratory/drive_lab.gd:512–515` and `:704–706`
- **Mechanism:**
  - `slip_deg()` returns `atan2(lateral, forward)`, so a car travelling straight backwards reads ±180°.
  - `_tire_intensity` uses `abs(slip)/35°`, which saturates at 1, and scales it only by speed.
  - The lab tuning (`make_laboratory_tuning`, reverse top speed 8 m/s) and the keyboard path (`S` held at low speed, reverse latch) make this reachable in DriveLab.
- **Reproduced numerically** (Python mirror of the component's constants and mapping, not a Godot run):

  | Straight reverse speed | Tire level |
  |---|---|
  | 4 m/s | −28.6 dB |
  | 6 m/s | −19.1 dB |
  | 8 m/s | −14.7 dB |
  | Forward straight, any speed | −80 dB (silent) |

- **Test gap:** the DriveLab oracle (`tools/drive_lab/drive_lab_driver.gd:1911–1923`) copies the same `abs(slip)` formula, so it cannot catch this. No case reverses.
- **Fix:** define slip relative to the direction of travel for tire scrub, for example by folding the angle when `reverse_engaged` is set or forward speed is negative. Add a case that reverses straight and expects silent tires.

### F2. Medium: the selected support identity, point and normal can come from a hit outside the grounding cluster
- **Where:** `src/simulation/ground_support_probe.gd:403–430` and the identity contract at `:59–64`.
- **Mechanism:**
  - When the centre ray misses, `grounded` comes from the unique coherent footprint cluster.
  - `support_probe_index`, `support_point`, `support_distance_m` and `support_collider_id/rid/shape_index` still come from the closest legal hit of all.
  - `support_normal` still averages every legal normal.
- **Example:** three footprints read the road at 0.50 m and the fourth reads a same-mask car roof or kerb top at 0.20 m. Python reproduction of `_uniquely_largest_coherent_cluster`: cluster = [1, 2, 3], closest hit = index 0.
  - The result is grounded because of the road.
  - It reports the roof's identity and height.
  - This is the road-versus-car-roof case the identity telemetry was added to separate (prior Sol support boundary).
- **Test gap:**
  - `_case_support_identity` (`support_lab_driver.gd:1407+`) uses single-surface stages only.
  - `_case_coherent_cluster_three_plus_one` (`:922+`) puts the outlier lower, never closer.
- **Fix:** when grounding comes from the cluster, choose the support and normal from the cluster's members, or expose both views explicitly. Add a 3+1 case with a closer outlier.

### F3. Low, latent: the rotated-bay fix stops at the spawn
- **Where:** `src/laboratory/drive_lab.gd:709–718`.
- **What happens:** `_course_limit_reached` still measures station along road +y (`state.position_m.y - start_position_m.y`). For any rotated bay the halt boundary is wrong.
- **Why it is latent:** all bays are still `yaw_deg = 0`, so it is not reachable today. It is the remaining half of prior F6.

### F4. Low, integration boundary: the gearbox and `CarState` disagree on the gear field
- **Where:** `src/simulation/car_state.gd:46` against `automatic_gearbox.gd:174, 199, 250`.
- **What happens:**
  - `CarState.gear_index` defaults to 0, which the gearbox treats as invalid. The gearbox uses −1 or 1..N, resets to 1, and keeps its shift cooldown privately.
  - A replay or reset restored from a committed `CarState` cannot reproduce the gearbox state.
- **Why it is Low:** the kernel is not integrated anywhere (grep finds no consumer outside `tools/gear_lab`), so nothing breaks now.
- **Before integration:** decide the source of truth, the shared initial value and where the cooldown lives.
- **Related calibration note:** forward gears follow the magnitude of forward speed, not ground speed. A drift at 30 m/s with 35° slip indicates about 24.6 m/s and may downshift. Backward roll with the latch clear indicates forward gears. That is a calibration choice, not a defect.

### F5. Nits and residuals
- **Corner contacts (prior F7, still open):** `_select_wall_response_normal` (`motor_body_adapter.gd:735–749`) answers one wall per tick. Example from my Python check: velocity (−10, 0, −10) into walls (1,0,0) and (0,0,1) leaves (0, 0, −10) still pressing into the second wall. This is M1.4 multi-contact work.
- **Zero normal:** a zero contact normal is classified as wall-like (`:724`, since `ZERO.normalized()·up = 0`). The projection guard prevents any harm.
- **Stale audio after a stop:** after `_fail` or `_halt`, the voices keep playing at the last applied pitch and gain. Reconfiguring does not reset them to idle (`drive_lab.gd:844–879`).
- **Unused method:** `GearboxState.is_valid()` has no caller.

## Disposition of prior findings

| Prior finding | Disposition |
|---|---|
| Opus F1, small gentle-yaw overlap | **Closed in code.** The skip threshold is gone. Every nonzero yaw probes the installed pose (`motor_body_adapter.gd:472–521`). Coordinator evidence: 15/2405 with the old source failing. Side effect: floor or ramp contact can now trigger `REFUSED_ORIENTATION` on more ticks (see acceptance gaps). |
| Opus F4 / Sol support boundary, coherent clusters | **Closed for the grounding rule.** The uniquely largest maximal cluster is implemented and documented, and a 3+1 case is added. A linear chain such as 0.50/0.70/0.90 is a tie and stays ungrounded (my Python check), which is conservative and consistent with the doc. **Selected-hit identity:** IDs are recorded without strong references, but the selection is not bound to the cluster (F2). |
| Sol 1, tilted-wall response | **Closed.** The response and the selection both use the normalized road-plane projection, with a guard for degenerate normals (`:751–783`). |
| Sol 2, all reported contacts | **Closed.** `_collect_collision_contacts` walks `get_collision_count()` and keeps generic telemetry separate (`:708–727`). A fixture seam allows deterministic ordering. The corner residual is in F5. |
| Sol 3, yaw-constrained velocity | **Closed.** On a constrained tick, `_reproject_velocity_road` (`:536–540, 596–611`) reprojects the longitudinal and lateral scalars before the wall response. My Python check preserved both scalars and the speed to 1e-9. |
| Sol 4, keyboard focus loss | **Closed for Godot focus notifications.** `_notification` clears `_keys` and rear view on window or application focus-out (`drive_lab.gd:251–254, 839–841`). The test injects the notification and is not a real OS focus change. A key still physically held on refocus needs a fresh press, as documented. |
| Opus F6, rotated builder heading | **Partly closed.** The spawn conversion is correct for both the marker and the manifest fallback, and preserves zero exactly (`:662–694, 930–933`). The course limit remains axis-locked (F3). |

## New slices

- **`VehicleFeedbackPlayer` wiring:**
  - One component is built once with two voices.
  - `apply()` runs only on the `COMMITTED` branch, and an audio refusal is counted without halting.
  - Validation is atomic, setup refuses and retries cleanly, and `_exit_tree` stops and tears down the voices. The streams are assigned once.
  - Defect: F1. Gap: the stale state after halt or reconfigure in F5.
- **`AutomaticGearbox`:**
  - **Invalid input:** every refusal (null input, dt, nonfinite velocity, heading, forward speed or rpm) returns before any mutation, and `create()` copies the config.
  - **Reverse latch:** the latch alone enters reverse. Exit needs the latch clear and forward speed at or above 0.5 m/s.
  - **Reset:** deterministic. Hysteresis is validated per pair.
  - **Multi-gear steps:** a jump of several gears emits one event.
  - **Integration:** none (F4).

## M1 acceptance gaps (open scope, not defects)

- Support eligibility, adhesion and landing.
- Floor- and ramp-aware orientation. The per-yaw probe now reports any collider in the mask, so sloped ground will refuse ticks until this lands.
- Scrape-then-steer-away feel (Opus F2) and multi-wall corner response.
- Full reset placement.
- Calibration of drift, surge, drafting and gear thresholds.
- Real controller input.
- Rendered traces at 30, 60 and 120 FPS.
- Actual audio listening, the four-player mix and audible shifts.
- Gearbox integration and HUD gear display.
- Target-platform launches.

M0.3 output rights (OI-02/OI-03) remain separate release blockers. This review implies no legal clearance.

## Verdict

**changes required.** The code checkpoint closes the prior adapter and focus findings. F1 and F2 are real, reachable mismatches in the newly delivered audio and support-identity slices, each needing a small fix and a regression case. F3 and F4 should be tracked before rotated bays or gearbox integration. Nothing here constitutes M1 acceptance.