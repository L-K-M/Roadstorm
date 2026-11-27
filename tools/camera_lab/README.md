# M1.5 camera rig and headless camera lab

`src/presentation/camera_rig.gd` is a presentation-only `CameraRig` component
for one eventual local player slot, as a bounded PLAN.md M1.5 slice rather than
an integrated race camera. This directory contains its headless Godot 4.7.2
validation entry point and bounded isolated runner.

## Files

| Path | Role |
| --- | --- |
| `src/presentation/camera_rig.gd` | owned component: one owned `Camera3D`, chase/near-chase/hood modes, momentary rear view, per-slot FOV preference |
| `tools/camera_lab/validate_camera_rig.gd` | headless `SceneTree` validation entry point |
| `tools/camera_lab/run_validation.sh` | pinned-engine wrapper that stages an isolated copy, imports resources, bounds every Godot run, and runs the pass plus deliberate-failure cases |
| `tools/camera_lab/check_runner_safety.sh` | non-destructive runner controls for refusal, containment and staging behavior |

## Component behaviour

The rig owns exactly one `Camera3D`. Slot code attaches it to a shared-world
slot viewport with `attach_to_viewport()`, supplies a visual `Node3D` target
with `set_target()` (or an explicit pose with `set_target_pose()`), and calls
`update_target_pose(delta)` each rendered frame. The rig never moves or rotates
its target and never writes simulation state.

Frame convention is local `+Y` up, `-Z` forward, `+X` right. Chase sits behind
and above the target, near chase is closer, and hood sits ahead of the target
origin at dash height. All offsets, look points and FOVs are provisional
authored values and runtime-configurable. Horizon stabilization derives the
camera basis from world `+Y`, so target bank and roll do not roll the camera.
A missing, nonfinite or singular target leaves the last valid camera pose
active, reports `NO_TARGET`/`INVALID`, and never emits a nonfinite or collapsed
camera transform. Every computed camera pose is checked for a finite origin and
an orthonormal basis before assignment; uniformly scaled targets are accepted
and keep unit camera axes with offsets that follow the scaled frame.

Momentary rear view redirects the same camera node backwards while held and
restores the selected forward mode on release. It creates no second camera or
viewport. Smoothing is opt-in and disabled by default; `snap_to_target()` gives
deterministic placement for tests and replays.

Unimplemented seams, explicitly not claimed: wall avoidance, corner
look-ahead, comfort/shake/drift-rotation tuning (see
`CameraRig.refine_desired_pose`), input mapping, viewport/split-screen
integration and four-player cost. The rig never writes car physics.

## Run

From the repository root, with the pinned Godot 4.7.2 binary:

```sh
mkdir -p work/agents/<job-id>/scratch-camera-lab
tools/camera_lab/run_validation.sh \
    --godot /opt/homebrew/bin/godot \
    --private-dir work/agents/<job-id>/scratch-camera-lab/private \
    --log work/agents/<job-id>/logs/camera-lab-run.log \
    --timeout 120
```

An explicit `--private-dir` must not already exist and its parent directory
must already exist; the runner never creates the parent, so a refused unsafe
destination cannot leave a partially created path behind.

The runner checks the engine against `tools/toolchain/pin/engine.txt`, stages a
fresh private copy (excluding `.git`, `.godot`, `work` and Python caches),
redirects XDG/TMP caches into scratch, then runs, all under `timeout`:

1. `godot --headless --path <private> --import`;
2. `godot --headless --fixed-fps 60 --path <private> --script res://tools/camera_lab/validate_camera_rig.gd` (pass case);
3. the same script with `-- --expect-failure` (deliberate-failure proof).

It fails if any invocation logs `SCRIPT ERROR`, `Parse Error`, `ERROR:` or
`USER ERROR:`, if `CHECKS_TOTAL` is absent, if the pass case exits nonzero or
reports failures, or if the deliberate-failure case exits zero without
reporting a failure. An explicit `--private-dir` is create-only and refused if
it already exists; omit it for an auto-cleaned temporary copy. Direct
invocation after an import is also possible:

```sh
godot --headless --fixed-fps 60 --path <isolated-project> \
    --script res://tools/camera_lab/validate_camera_rig.gd
```

Exit code 0 means every check passed; exit 1 means at least one check failed;
exit 2 means the runner refused unsafe input or could not execute the pinned
engine. The validator prints one machine-readable `CAM_RESULT <json>` line and
`CHECKS_TOTAL=<n> CHECKS_FAILED=<n>`.

Run the non-destructive runner controls (refusal paths, unsafe/missing-parent
containment, allowed fresh `work/` destination, occupied paths, default
scratch):

```sh
./tools/camera_lab/check_runner_safety.sh
```

## Scope limits

- Headless dummy display/audio drivers: no rendering, visual comfort or actual
  device/controller verification.
- The SubViewport check is headless structural evidence only: attach reparents
  one camera into an in-tree viewport and makes it current there, detach
  deactivates it. It does not render an image and makes no split-screen or
  four-player claim.
- Wall avoidance, corner look-ahead and comfort/shake/drift rotation are
  unimplemented seams and are not exercised.
- No four-player performance claim, no integrated race-camera claim, and no
  M1.5 or M1 acceptance claim. The coordinator integrates and judges the
  component.
