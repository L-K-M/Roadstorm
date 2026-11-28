# Roadstorm M1 interim wall-region and frame-trace review

**Wall correction: pass. Frame preflight: changes required. Overall scoped verdict: changes required.** The exact-candidate wall lab closes the reported 1.2 m pulse. Three genuine 30/60/120 nominal headless runs match. The comparator also passes a genuine 30-FPS run labeled as 60 and a trace whose station rows contradict its claimed gate time.

Independent first-party GPT-6.2 Sol review, 2026-11-28. Candidate `49d60a12c96322cbc71af8a9a3a77f711c644634`, base `39ce8d0a3c6a2a6d1a97cac584688dd30aeadfa2`. The supplied SHA and eight-path patch identify the candidate, and `diff -qr ../source . -x .godot` returned 0. The three scoped wall files match the coordinator's frozen overlay byte for byte. The five frame files match the coordinator's frozen stage, disregarding its generated UID sidecars.

## Ranked findings

1. **High, frame — A launch at the wrong process cadence can replace the required 60-FPS run.** At `tools/frame_trace_lab/frame_trace_driver.gd:348–378`, both the nominal label and the reported fixed-FPS argument come from `FTP_FPS`. At `tools/frame_trace_lab/compare_frame_traces.py:129–160`, timing is optional and neither the engine frame counters nor the recorded version/backend establish the comparison cohort. I launched the unchanged entry with `FTP_FPS=60 FTP_VARIANT=full` and `--fixed-fps 30`. It exited 0, labeled itself 60, and recorded 602 process frames for 1,204 physics frames. Replacing the genuine 60 result with that file returned 0 and `COMPARISON PASS`. No result editing was needed. The shell runner passes the same value to both fields today, so the standard launch command produced the correct modes. The comparator's success nevertheless cannot establish that the supplied runs covered all three cadences. Require and validate the measured physics/process frame counters against the nominal ratio, allowing for startup/drain rounding. Validate the recorded engine version and backend for the pinned same-host suite. Add the wrong-cadence launch as a negative control. Evidence: `logs/frame-30-mislabeled.json`, `logs/control-mislabeled.log`.

2. **Medium, frame — The comparator can pass a gate time two ticks outside the allowed window.** At `tools/frame_trace_lab/compare_frame_traces.py:232–236,266–268,305`, the comparator compares the supplied gate tick and checks that station rows are finite. It never finds the first committed row at or above 100 m. In a copy of the genuine 60 result I changed only rows 357 and 358 to 99.99 m. The first qualifying row became tick 359 while the summary still said 357. The comparator exited 0 and reported a zero-tick difference. Changing only the gate summary from 357 to 358 likewise passes an internally inconsistent trace. Recompute the gate from the committed rows and verify the summary before applying the one-tick comparison. Evidence: `logs/control-hidden-gate.json`, `logs/control-hidden-gate.log`, `logs/control-stale-gate.log`.

3. **Low, frame — A malformed mode field raises an uncaught exception.** At `tools/frame_trace_lab/compare_frame_traces.py:149–151,359`, set membership happens before type validation. Setting `mode.nominal_fixed_fps` in the genuine 60 JSON to `[]` exits 1 via `TypeError` with no normal comparison result. The runner's exit-only check at `tools/frame_trace_lab/run_frame_trace_lab.sh:421–428` cannot distinguish that crash from an intended rejection. Validate the type first and require the structured failed comparison marker for negative controls. Evidence: `logs/control-bad-type.log`.

## Wall correction

- The adapter selects the response and witness with the same planar-opposition index and preserves the collision-time point and basis before final yaw (`src/simulation/motor_body_adapter.gd:483–506,633–669,869–941`). The producer checks committed velocity and projects the selected normal into the road plane before expressing it in the same local basis as the point (`src/simulation/wall_impact_producer.gd:145–215`). The revision only affects published region selection.
- Both normalized absolute plane distances must be at most 0.04 for the response normal to name a face (`wall_impact_producer.gd:275–314`). On the default hull this is 36 mm at either side plane and 76 mm at either end plane. Inside the capture the dominant component must beat the other by more than 0.001 and point inward for the corresponding quadrant. Otherwise the normalized point rule applies, with exact ties going to the longitudinal axis. The condition deliberately includes points just outside the hull planes. The synthetic checks exercise the mirrored quadrants, incompatible sign, collision-time basis, both sides of the diagonal margin, 75/77 mm end-plane insets, and a scaled 2.4 × 1.0 × 3.0 m hull. The scaled-hull evidence is synthetic.
- The pinned wall runner exited 0 with 16 cases, 1,527 checks and zero failures. The deliberate failure exited 3. The material 1.2 m case at 35 m/s, heading 0.9 rad, steer −1, throttle 1 retained LEFT on ticks 30–32 and transitioned to FRONT at 33 with the normal. Tick 31 carried 4.573 m/s severity and 19.255/39.565 mm side/end insets. The local normal was (0.981878, 0, 0.189513). The other two prior 1.2 m cases at ticks 19 and 34 also passed. The coordinator's old-producer control failed seven checks, including four physical assertions. Its frozen width/flat sweeps cover 10,166 witnesses with zero refusals or compatible-normal mismatches or constant-face flips.
- I additionally reused the coordinator's completed probe source in a private stage and limited it to 120 offset scenarios at 40 ticks each. Each width/offset pair used 20 and 35 m/s, headings 0.70/0.785398/0.90/1.00/1.10 rad, steer −1/+1 and throttle 1. Results for width/offset in meters were 121 witnesses at 0.6/+0.30, 377 at 1.2/−0.30, 372 at 1.2/−0.65, 217 at 1.2/+0.30, 86 at 1.2/+0.65 and 309 at 2.4/+0.65. All six runs completed. Across **1,482 witnesses** there were zero refused publications, noncommitted steps, compatible-normal mismatches or constant compatible-face flips. Three witnesses were diagonal or incompatible and excluded from the normal-agreement metric. The metric compares labels to the selected solver response. It cannot certify exact geometric features independently of that response.

## Frame preflight runs

The entry pins the engine physics rate to 60 before starting the driver. The driver configures the authored one-car DriveLab scene with 420 throttle, 120 coast and 660 brake ticks. It allows DriveLab's ordinary `_physics_process` command cursor to drive `step_once` (`src/laboratory/drive_lab.gd:345–367`). Commit records supply the state and adapter observations. The driver reconstructs the command column from the scheduled command array (`frame_trace_driver.gd:251–301`). This verifies the schedule supplied to the current cursor and commit agreement. An independent record of the command actually consumed would be needed to detect a future cursor regression that keeps the same number of steps.

| Nominal fixed FPS | Physics frames | Process frames | Commands/commits | Gate tick | Gear shifts | Contact ticks |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 30 | 1,204 | 602 | 1,200/1,200 | 357 | 9 | 0 |
| 60 | 1,204 | 1,204 | 1,200/1,200 | 357 | 9 | 0 |
| 120 | 1,204 | 2,408 | 1,200/1,200 | 357 | 9 | 0 |

All genuine launches exited 0. Commit callback indices ran consecutively from 10 through 1,209. The comparator exited 0 with zero differences for endpoint position, speed, heading and gate tick in all pairs. Discrete sequences and counts matched. The comparator uses pairwise Euclidean position distance, scalar speed difference, wrapped heading and inclusive benchmark limits of 0.10 m, 0.10 m/s, 1 degree and one tick. Missing, corrupt, drop relabeled as full, short relabeled as full, and 0.5 m endpoint displacement controls all exited 1 for the expected reason. The drop variant substitutes idle commands on every third tick, and the short variant actually commits 1,199 ticks. The direct runs reproduced a four-instance ObjectDB exit warning.

## Commands and evidence limits

From `build/`, `C="$(cd ../../.. && pwd)"`, `L="$(cd ../logs && pwd)"`, `PIN="$C/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"`. All engine invocations used the shared lock and private HOME, TMPDIR and XDG paths below `$L`. The frame stage was a copy of the read-only archive below `$L/frame-stage` so import output stayed private. Only the standalone reviewer probe was added there after the frame runs.

```sh
timeout -k 5 240 sh tools/wall_impact_lab/run_wall_impact_lab.sh \
  --project "$PWD" --godot "$PIN" --lock "$C/godot-test.lock" \
  --timeout 60 --outer-timeout 180 --log "$L/wall.log"
timeout -k 5 180 lockf -k -w -t 160 "$C/godot-test.lock" \
  "$PIN" --headless --path "$L/frame-stage" --import
# fps/label/variant = 30/30/full, 60/60/full, 120/120/full,
# 60/60/drop, 60/60/short, 30/60/full for the wrong-cadence control.
FTP_FPS="$label" FTP_VARIANT="$variant" FTP_RESULT="$output" \
  timeout -k 5 90 lockf -k -w -t 65 "$C/godot-test.lock" \
  "$PIN" --headless --fixed-fps "$fps" --path "$L/frame-stage" \
  --script res://tools/frame_trace_lab/frame_trace_entry.gd
python3 -B tools/frame_trace_lab/compare_frame_traces.py \
  "$L/frame-30-full.json" "$L/frame-60-full.json" "$L/frame-120-full.json"
python3 -B "$L/frame-controls.py"
# width/offset pairs listed in the wall section.
OPUS_WALLW="$width" OPUS_X="$offset" \
  timeout -k 5 45 lockf -k -w -t 32 "$C/godot-test.lock" \
  "$PIN" --headless --fixed-fps 60 --path "$L/frame-stage" \
  --script res://reviewer_probe/entry.gd
python3 -B "$L/wall-target-summary.py"
sh -n tools/frame_trace_lab/run_frame_trace_lab.sh
```

The Gitless archive precluded running the frame shell wrapper unchanged. I reviewed all five files, checked shell syntax, read the coordinator's successful frozen-run summary, and ran the unchanged engine entry and comparator directly. The headless fixed-FPS argument varies nominal process cadence. PLAN's rendered-FPS acceptance remains open. The 100 m station threshold is a numerical gate-time proxy. This straight trace does not exercise race rules, rewards, heading changes, drift or contact events. Wall findings are limited to the measured pinned macOS Godot `4.7.2.stable.official.ed1daf0bf` Jolt fixtures, default physical hull, and flat static box walls. Other geometry, platforms, physical hull dimensions and tolerances remain unverified. This review provides no M1.7, M1.8 or M1 completion, controller, rights or release sign-off. Hosted base CI status was supplied at handoff. I did not verify candidate hosted CI, and the hosted workflow does not run these labs. Candidate source and assets are intact. No Git mutations, delegation, current-reviewer consultation or publication occurred.
