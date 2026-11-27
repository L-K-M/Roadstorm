# One-slot control normalizer laboratory

`src/input/one_slot_controls.gd` is a plain `RefCounted` normalizer for one
local player slot, plus this directory's headless Godot 4.7.2 validation entry
point and bounded isolated runner. The component is an M1.1/M3.1 seam, not an
integrated input router or a product-ready controls implementation.

## Files

| Path | Role |
| --- | --- |
| `src/input/one_slot_controls.gd` | owned component: analog deadzone/sensitivity, digital steering ramp, rising-edge reset plus normalized `reset_held` level, lifecycle clear, atomic rejection of invalid raw/dt |
| `src/input/reset_hold_gate.gd` | owned pure one-second hold gate consuming `reset_held` and emitting exactly one latched action per eligible hold |
| `src/simulation/driver_command.gd` | owned seam record carrying the `reset_held` level alongside `reset_requested` (also owned by this M1.1 slice) |
| `tools/input_lab/validate_one_slot_controls.gd` | headless `SceneTree` validation entry point for the controls, command fields and hold gate |
| `tools/input_lab/run_validation.sh` | pinned-engine wrapper that stages an isolated copy, imports resources, bounds every Godot run, and runs the pass plus deliberate-failure cases |

## Component behaviour

`sample(raw_steer, raw_throttle, raw_brake, raw_handbrake, reset_pressed, dt,
steer_left=false, steer_right=false)` accepts already-routed values once per
tick and returns a fresh `DriverCommand`, or `null` when `dt` is nonfinite or
negative or any analog value is nonfinite. Invalid calls leave the stored
digital ramp and reset level untouched.

Analog steering uses the documented formula
`sign(x) * clamp((|x| - deadzone) / (1 - deadzone) * sensitivity, 0, 1)`, with
values at or below the deadzone mapped to 0. Digital left/right buttons target
-1/0/+1 (both pressed cancels to 0) and move toward that target by at most
`digital_ramp_per_second * dt`, so press, release and reversal are rate
limited. Digital output wins while a button is held or while the stored ramp
is still returning to center; otherwise the normalized analog axis drives
steering. Reset is a rising edge, emitted once per press. Valid finite values
outside their ranges are clamped by `DriverCommand.create()`, preserving its
validation contract.

Call `clear_lifecycle_state()` on focus loss, pause, reassignment or
reconnect. It clears the digital ramp. If reset was held at the last sample,
it also requires release and repress before another edge or held level, so a
continuing hold is not mistaken for a new press; a press that begins after the
clear emits normally, and repeated clears keep that requirement until release.
Tuning values persist. `configure(deadzone, sensitivity, ramp_per_second)` validates all
three values atomically and changes nothing on rejection.

Alongside the rising-edge `reset_requested`, each command carries
`reset_held`: true while a valid fresh press is held, false while released, and
false throughout the post-clear suppression window. `DriverCommand.create()`
and `set_from_raw()` accept it as an optional final argument; `copy()` copies
it and rejected updates leave it untouched.

`ResetHoldGate` consumes normalized commands and dt, never the press edge. It
returns true exactly once when a continuous eligible `reset_held` level reaches
`HOLD_SECONDS_S` (1.0). Releasing early clears progress, holding after firing
never repeats, releasing and pressing again rearms, zero dt does not advance,
invalid dt/command is refused atomically, and `clear_lifecycle_state()`
cancels progress. The gate places no car and does not implement the Practice
pause menu's immediate reset path; those remain separate future callers.

Unimplemented seams, explicitly not claimed: device enumeration and
device-to-player ownership, joining/leaving, remapping, persistent profiles,
assists, reverse/brake rules, gears, camera/menu actions, keyboard/gamepad
event routing, and actual hardware behaviour. No M1/M3 acceptance claim.

## Run

From the repository root, with the pinned Godot 4.7.2 binary:

```sh
mkdir -p work/agents/<job-id>/scratch-input-lab work/agents/<job-id>/logs
tools/input_lab/run_validation.sh \
    --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
    --private-dir work/agents/<job-id>/scratch-input-lab/private \
    --log work/agents/<job-id>/logs/input-lab-run.log \
    --timeout 120
```

The runner checks the engine against `tools/toolchain/pin/engine.txt`, stages a
fresh private copy (excluding `.git`, `.godot`, `work` and Python caches),
redirects XDG/TMP caches into scratch, then runs, all under `timeout`:

1. `godot --headless --path <private> --import`;
2. `godot --headless --fixed-fps 60 --path <private> --script res://tools/input_lab/validate_one_slot_controls.gd` (pass case);
3. the same script with `-- --expect-failure` (deliberate-failure proof).

Exit code 0 means both cases passed; exit 1 means a check failed or the output
was invalid; exit 2 means unsafe inputs or an unpinned engine. The validator
prints one machine-readable `INPUT_LAB_RESULT <json>` line per run and a
`CHECKS_TOTAL=... CHECKS_FAILED=...` line.

## Scope limits

- Pure headless component checks; no rendering, audio, GUI, integrated race
  wiring or physical controller verification.
- The hold gate times an explicit hold only: no car placement, route anchor,
  RaceSession integration or Practice menu immediate-reset path.
- All deadzone, sensitivity and ramp defaults are provisional starting values
  pending M3 device profiles and play testing.
- The deliberate-failure case proves only that a failing check exits nonzero.
