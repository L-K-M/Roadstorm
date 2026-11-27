# M1 one-car drive laboratory

`src/laboratory/drive_lab.gd` is the one-car driving laboratory: it instantiates
the committed M1.2 handling lab's 500 m asphalt straight, owns exactly one
`CharacterBody3D` hull, and drives it through `MotorBodyAdapter.step()` once per
physics tick from either a scripted command schedule or a minimal keyboard path.

This directory contains its headless Godot 4.7.2 validation entry points and the
bounded isolated runner.

## Files

| Path | Role |
| --- | --- |
| `src/laboratory/drive_lab.gd` | owned laboratory: car, camera rig, speed HUD, one `VehicleFeedbackPlayer`, tick loop, telemetry |
| `src/audio/vehicle_feedback_player.gd` | committed M1.5 component under test; this task treats it as read-only input and does not modify it |
| `tools/drive_lab/drive_lab_checks.gd` | assertion collector, explicit tuning/state/command fixtures, node-census and HUD-reading helpers |
| `tools/drive_lab/drive_lab_driver.gd` | headless `Node` driver that runs the validator cases |
| `tools/drive_lab/validate_drive_lab.gd` | headless `SceneTree` entry point |
| `tools/drive_lab/run_validation.sh` | pinned-engine wrapper that stages an isolated copy, imports it, bounds every Godot run, and runs the validator, the bad-config fixture and the deliberate failure probe |
| `tools/drive_lab/bad_config_fixture.gd` | atomic-refusal fixture for invalid adapter configs and hull mismatches |
| `tools/drive_lab/failure_probe.gd` | deliberate failing check, so a green run cannot be vacuous |
| `tools/drive_lab/run_gearbox_mutant_control.sh` | bounded negative control: stages a private copy, removes the gear mirror or forces a proposal refusal, and requires `gearbox_integration` to fail |
| `tools/drive_lab/apply_gearbox_mutation.py` | mutation helper invoked by `run_gearbox_mutant_control.sh` for both mutants; never runs against the real checkout |

## What the validator proves

Cases, in order: `scene_and_manifest`, `rotated_spawn_heading`,
`movement_from_rest`, `braking`,
`displacement_accounting`, `repeatability`, `finite_state`, `hull_road_overlap`,
`one_call_per_tick`, `refusal_halts`, `presentation_integration`,
`keyboard_focus_lifecycle`, `reconfigure_presentation_counters`,
`audio_feedback_integration`, `gearbox_integration`.

`presentation_integration` is the M1.5 presentation slice. It runs against the
real `scenes/laboratory/drive_lab.tscn` and checks that the committed
`CameraRig` and `SpeedHud` are wired into the laboratory's actual node tree:

* exactly one `Camera3D` and one `Viewport` in the whole tree, with the rig
  owning that camera and following the car;
* exactly one `CanvasLayer` holding exactly one `SpeedHud` instance, parented to
  that layer and using the committed component script;
* the HUD shows `0` / `km/h` / `GRIP` before any commit, and after 30 scripted
  throttle ticks shows the committed `CarState` speed in km/h (an independent
  conversion oracle), still `GRIP`, with one accepted update per commit plus the
  initial one and no rejected update;
* `cycle_camera_mode()` walks CHASE -> NEAR_CHASE -> HOOD -> CHASE, and
  `set_rear_view_held()` turns the same camera backwards and restores it on
  release, with dot-product evidence against the car's forward axis;
* those presentation calls change no adapter step count, no committed tick, no
  physics callback, no tick-log entry, no body transform and no committed state,
  and create no second camera or viewport;
* scripted mode ignores synthetic `C` and `Shift` key events (delivered through
  the real input pipeline and proven delivered by an input probe) with no extra
  physics frames, no state change and no body change;
* keyboard mode answers the same synthetic events: `C` cycles the mode,
  `Shift` holds and releases the rear view, key auto-repeat does not cycle
  twice, and the throttle key still drives bounded ticks;
* laboratory teardown frees the HUD, its canvas layer, the camera rig and the
  camera, and leaves no `SpeedHud`, `Camera3D` or `CanvasLayer` in the tree.

`keyboard_focus_lifecycle` holds `W` and `Shift` through the real input
pipeline, then loses focus without any key-up event and requires the held
throttle and rear view to be dropped immediately, with no residual acceleration
and a working fresh press afterward. Headless mode cannot create a genuine OS
window focus transition, so the case drives Godot's
`NOTIFICATION_WM_WINDOW_FOCUS_OUT` and `NOTIFICATION_APPLICATION_FOCUS_OUT`
through the scene-tree root, the same notifications the engine propagates on
window and application focus loss. It does not exercise DisplayServer or a
window-manager transition. The pre-fix source fails this case (five assertions,
including measurable residual throttle), which is kept as the old-source control
in the task log.

`reconfigure_presentation_counters` runs one schedule, cycles the camera,
holds and releases rear view, then calls `configure()` again with a new
schedule and requires every presentation and simulation counter to describe
only the new configuration, followed by an independent run of that schedule.
The pre-fix source carries the counters over and fails three assertions.

`audio_feedback_integration` is the M1.5 synthesized-feedback wiring slice. It
proves that exactly one committed `VehicleFeedbackPlayer` is a child of the
laboratory, owns exactly two named `AudioStreamPlayer` voices (`Engine`/`Tire`),
and holds one non-empty `AudioStreamWAV` per voice. Before any commit it must be
set up and parked at the independently calculated idle pitch, idle engine level
and silent-tire targets with both voices playing under the dummy driver, with no
apply attempt yet.

Over 60 real committed throttle ticks the case requires one apply attempt and
one accepted update per commit, monotonically rising engine pitch and level, tire
silence while slip is zero, and every measured target equal to an independent
oracle for the committed speed/slip/grounded values. Both stream references and
their PCM bytes must stay unchanged across those commits, so the update path
never re-synthesizes or rebuilds a stream.

A scheduled `null` command refuses at the adapter after ten committed ticks; the
case then requires no further apply attempt, unchanged last accepted pitch/gain,
an empty audio error, and the committed state/body still equal to the last trace
entry. A separate diagnostic-refusal control tears the component down through its
own public lifecycle, steps twice, and requires both commits to succeed while the
lab counts two rejected applies, records a reason, clears its ready flag and does
not fail the simulation; restoring setup recreates exactly two voices.

Reconfiguring with a new schedule must keep the same single component and two
voices, reset the audio counters/error, and then replay the `movement_from_rest`
90-throttle schedule to a bit-identical committed simulation trace (position,
velocity, heading, body transform), proving the audio wiring does not alter
committed motion. Teardown must free the component and leave no
`VehicleFeedbackPlayer` or `AudioStreamPlayer` in the tree.

Headless Godot uses a dummy audio driver. This case proves node ownership,
stream stability, mapped numeric targets and one-way update discipline only; it
**cannot certify audible output, timbre, mix balance or listening comfort**. Only
real-device listening can, and no such claim is made here. If the dummy server
emits `ObjectDB` shutdown warnings after voices are started and stopped, they are
benign dummy-driver teardown noise, not evidence of playback quality.

`rotated_spawn_heading` covers the F6 heading-convention fix. The handling-lab
builder's heading grows toward local left while `CarState`/`MotorBodyAdapter`
grow toward local right, so a rotated authored spawn must be converted once at
each input. The case builds the real builder geometry with a synthetic
`Spawn_straight` marker authored at 30 degrees, then repeats it through the
manifest fallback (no marker, straight-bay `yaw_deg` set to 30). Both variants
require the committed `CarState` heading to equal `-yaw`, its nose and the
installed body basis -Z to match `HandlingLabBuilder._forward(yaw)`, the spawn
position mapping to stay unchanged, and 30 bounded throttle ticks to displace
and move along the authored forward. A zero-yaw control requires exactly
positive-zero heading and the unchanged -Z forward. The pre-fix source copies
the builder yaw straight into `CarState`, so both rotated variants fail on the
heading and body-forward assertions and on the drive direction.

A deliberate negative control inside the presentation case feeds a scratch
collector a wrong expectation about a real measurement and requires it to
record exactly one failure while the live collector stays untouched, so the
case's assertions are demonstrably capable of failing.

## M1.1 gearbox integration

`gearbox_integration` integrates exactly one canonical `AutomaticGearbox`
into the laboratory and checks:

* initial pair agreement (published `CarState.gear_index` 1, canonical gear 1,
  zero dwell/rpm), read-only state copies and the bounded event log;
* natural forward shifts: event count equals logged gear transitions, every event
  matches its tick's from/to gear and rpm, events are UPSHIFT while accelerating
  and DOWNSHIFT while braking, consecutive events keep at least the shift dwell,
  gears strictly increase during acceleration, and the run reaches third gear;
* reverse latch entry produces exactly one ENTER_REVERSE event, and after the
  latch clears while the car is still rolling backwards the gear stays `-1`
  with no EXIT_REVERSE until forward travel resumes;
* every committed tick's published physical fields (position, velocity,
  heading, flags and inert seams) are copied verbatim from the adapter commit;
  only the gear mirror may differ, and `steps_called == ticks_committed`;
* an independent fresh run reproduces position, velocity, heading, body
  transform, gear, rpm and the whole event sequence bit-for-bit;
* snapshot/restore captures a checkpoint with nonzero cooldown and normalized
  rpm, restores both records exactly into a second laboratory, repairs a stale
  mirror from the canonical gear, publishes both together, and then blocks all
  ticks because the body pose is not restored; reconfiguring does not clear
  that block;
* invalid or incomplete pairs (nonfinite car, null/missing record, bad gear,
  out-of-range/nonfinite dwell or rpm, plain dictionary, null) are refused
  atomically with both live records unchanged and no side effects.

The snapshot/restore operation is deliberately **state-only**. It does not
restore the body transform, so it is not a runnable drive replay and claims no
replay completion. After a restore, `is_drive_replay_blocked()` stays true and
`step_once()` refuses without calling the adapter until a body-pose
reconciliation operation exists. Restoring a `CarState` alone is not offered;
shift dwell and canonical rpm would be lost.

A gearbox proposal or mirror refusal after an irreversible adapter COMMITTED
tick is reported as an explicit bounded failure and halts the run. The
unmirrored physical record is never published as the committed pair, and no
further adapter call is made; the last successfully published pair is not
reconciled with the irreversibly advanced body.

Gear selection drives no audio or HUD display here. This slice wires neither
shift sound nor a gear readout, and claims none.

## Negative control

`run_validation.sh` runs the deliberate failing probe, but it cannot prove the
new gearbox assertions can detect a missing integration. The bounded mutant
control does:

```sh
timeout 600 lockf -k -w -t 600 work/agents/coordinator/godot-test.lock \
  tools/drive_lab/run_gearbox_mutant_control.sh \
  --godot "$PWD/work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot" \
  --timeout 500 --mutation mirror_removed \
  --log work/agents/<job-id>/logs/gearbox-mutant-mirror.log
```

Repeat with `--mutation proposal_refused` to exercise the refusal path. Exit 0
means the mutation was detected (`gearbox_integration` failed behaviourally);
exit 1 means it was not. The script stages its own private copy, imports under
a watchdog, and never mutates the real checkout.

Scope: one car, one flat straight, structural and behavioural headless checks.
The validator does not prove rendering, visual readability, HUD contrast or
legibility at real resolutions, audible sound quality or mix, controller input,
split-screen cost, race integration, a real window-manager focus transition, or
M1.5/M1 acceptance. Audio feedback is validated structurally and numerically
against the committed component's provisional mapping; headless tests cannot
certify what a listener would hear.

## Run

From the repository root, with the pinned Godot 4.7.2 binary:

```sh
mkdir -p work/agents/<job-id>/logs
tools/drive_lab/run_validation.sh \
    --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
    --log work/agents/<job-id>/logs/drive-lab-run.log \
    --timeout 180
```

The runner checks the engine against `tools/toolchain/pin/engine.txt`, stages a
private copy of `project.godot`, `src`, `scenes` and `tools/drive_lab`, imports
it, then runs under a wall-clock watchdog:

1. `godot --headless --fixed-fps 60 --path <stage> --script res://tools/drive_lab/validate_drive_lab.gd`;
2. the same for `bad_config_fixture.gd`, which must report `pass=true`;
3. `failure_probe.gd`, which must exit nonzero and report `pass=false`.

Exit 0 means every check passed and the failure probe failed as expected; 1
means a check or a gate failed; 2 means unsafe inputs or an unusable engine.
Every engine invocation is bounded and only a bounded log tail is printed, so
the runner never emits unbounded output.
