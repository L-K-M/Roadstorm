# M1.3 pure drift-phase laboratory

A deterministic, pure, side-effect-free 60 Hz drift-phase evaluator for PLAN.md
M1.3, plus headless black-box checks. This is an integration-ready component:
it consumes committed `CarState` / normalized `DriverCommand` records and
proposes a phase, drift influence, advisory stability factor and transition
event. It does not integrate yaw or lateral physics, and it makes no claim that
the car already drifts.

## Files

| Path | Role |
| --- | --- |
| `src/simulation/drift_phase_model.gd` | pure model: phases, entry/sustain/recovery/airborne transitions, blend, stability factor, validation |
| `tools/drift_lab/validate_drift_lab.gd` | headless `SceneTree` validator with one case per required behavior |
| `tools/drift_lab/drift_lab_driver.gd` | shared builders/checks; calls the real model, never re-implements its math |
| `tools/drift_lab/run_validation.sh` | bounded isolated-copy wrapper (stages, imports, runs validator and failure proof) |

Helper scripts live only under `tools/drift_lab/`; nothing here is placed in
`tests/`, so CI's test auto-discovery does not pick up lab helpers.

## Model contract

- `DriftPhaseModel.propose(car_state, command, drift_state, tuning, dt, impact_speed_loss_m_s)`
  returns a `Proposal` or `null`. It never mutates any input; a refusal leaves
  the caller's prior `State` and `Tuning` untouched.
- Phases: `GRIP`, `ENTRY`, `SUSTAINED`, `RECOVERY`, `AIRBORNE`. Entry requires
  forward speed strictly above the design floor of 12 m/s, `|steer|` at/above
  `entry_steer_min`, and a true rising-edge handbrake tap. With
  `AssistMode.STANDARD`, a brake rising edge while steering is the documented
  alternative; `AssistMode.OFF` refuses it. Handbrake always works.
- `drift_blend` is finite and in `[0, 1]`: smoothstep over
  `entry_blend_time_s` (provisional 0.2 s), 1 in sustain, smooth decay over
  `recovery_blend_time_s` (provisional 0.35 s), 0 in grip/airborne.
- Sustain tolerates ordinary countersteer and exits on steering unwind, low
  speed, major impact or loss of ground. Hold timers prevent one-frame chatter.
- `stability_factor` is finite and in `[stability_floor_factor, 1]`: 1 up to
  `stability_start_deg` (~50 degrees absolute slip), linearly down to the floor
  at `stability_full_deg`. Assist off or airborne gives 1. The integrator owns
  applying it to additional rotation; this model enforces no slip.

Every physical/timing value is a field on `DriftPhaseModel.Tuning` with
provisional defaults. Only `min_entry_forward_speed_m_s` has a validation floor
(12 m/s); lowering it requires a recorded design decision.

### Deliberately out of scope

Style points, surge grants, course-zone qualification, surface response,
player input routing, contact classification, and actual yaw/lateral damping
integration are absent seams. `useful_slip` (12-40 degrees) is telemetry only.
A drift-phase exit alone is not a clean or qualifying exit.

## Run

From the repository root:

```sh
tools/drift_lab/run_validation.sh \
    --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
    --private-dir work/agents/<job-id>/private/drift_lab_fresh \
    --log work/agents/<job-id>/logs/drift-lab-run.log \
    --timeout 180
```

The default `--godot` path is the privately verified pinned executable above;
`--project` defaults to this checkout. The runner verifies the engine version
against `tools/toolchain/pin/engine.txt`, stages a private copy (excluding
`.git`, `.godot`, `work` and Python caches), redirects XDG/TMP caches into
scratch, bounds every Godot invocation, gates engine errors, and requires a
`CHECKS_TOTAL` line with `CHECKS_FAILED=0`.

An explicit `--private-dir` is create-only and refused if it exists as a file,
directory, symlink or dangling symlink. Omit it for an auto-created temporary
copy. `--case=<id>` selects one validator case; `--case=intentional_failure`
runs the deliberate failing check.

Direct invocation from an isolated project copy also works after a headless
import:

```sh
godot --headless --fixed-fps 60 --path <isolated-project> \
    --script res://tools/drift_lab/validate_drift_lab.gd
```

## Failure proof and limits

The runner invokes `--case=intentional_failure` and fails unless that process
exits nonzero with `"pass":false`; the probe asserts a deliberately false
assist-off brake-entry expectation. This proves the harness detects failures;
a green run is not inferred from an exit code alone.

Honest limits: pure-kernel checks only. No body, scene, physics query, clock,
rendering, audio or input device is exercised. Car states are scripted values,
not integrated motor or contact physics. Headless dummy display/audio drivers.
No M1.3 or M1 acceptance result is claimed.
