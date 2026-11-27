# M1.1 automatic-gear indication laboratory

A deterministic, pure, side-effect-free 60 Hz automatic-gear indicator for
PLAN.md M1.1, plus headless black-box checks. It consumes committed
`CarState` records and proposes a gear index, a bounded normalized rpm value
and at most one shift event per tick. It changes no physics, writes no
`CarState` field, produces no audio, and makes no claim that an integrated
automatic transmission exists.

## Files

| Path | Role |
| --- | --- |
| `src/simulation/automatic_gearbox.gd` | pure gearbox: config/state validation, stateful gear selection, reverse-latch handling, rpm indication, atomic refusal, deterministic reset |
| `tools/gear_lab/validate_gear_lab.gd` | headless `SceneTree` validator with one case per required behavior |
| `tools/gear_lab/gear_lab_driver.gd` | shared builders/checks; calls the real gearbox, never re-implements its math |
| `tools/gear_lab/run_validation.sh` | bounded isolated-copy wrapper (stages, imports, runs validator and failure proof) |

Helper scripts live only under `tools/gear_lab/`; nothing here is placed in
`tests/`, so CI's test auto-discovery does not pick up lab helpers.

## Component contract

- `AutomaticGearbox.create(config)` copies and validates a `GearboxConfig`;
  it returns `null` for null/invalid configuration. Config values are copied,
  so later caller mutation cannot change a live gearbox.
- `gearbox.propose(car_state, dt)` reads the finite signed forward speed
  (`velocity_m_s` projected on `heading_rad`) and the committed
  `car_state.reverse_engaged` latch. It returns `GearboxProposal` with
  `gear_index` (`-1` or `1..N`), `normalized_rpm` in `[0, 1]`, and a
  `ShiftEvent` (`from_gear`, `to_gear`, `direction`, post-shift
  `normalized_rpm`) only when the gear actually changed. `dt` must be the
  declared `DT` (1/60 s).
- Invalid input or an unexpected nonfinite result is refused atomically:
  `propose` returns `null` and leaves the gearbox and car untouched.
- `gearbox.reset()` restores the deterministic initial state: gear 1, zero
  dwell, zero rpm. No clock, RNG or input is consulted.
- Reverse obeys the existing motor latch, never signed velocity alone: a
  negative signed speed with the latch released selects a forward gear;
  entering `-1` requires the latch. Leaving `-1` requires the latch to clear
  and forward travel to reach `reverse_exit_forward_speed_m_s`, so latch
  release during backward roll does not snap to a forward gear.
- Forward shifts use strict thresholds (`>` up, `<` down), each pair keeps at
  least `min_hysteresis_gap_m_s` of separation, and committed shifts are
  separated by `min_shift_dwell_s`. Boundary dither inside the band therefore
  produces exactly one event.

The future simulation integrator owns committing `CarState.gear_index`,
choosing whether to feed this indicator from throttle/brake state, and routing
`ShiftEvent` to presentation/audio. This component neither applies torque nor
emits sound.

## Provisional defaults

Six forward gears span the committed 0-45 m/s laboratory motor envelope
(`src/laboratory/drive_lab.gd` `make_laboratory_tuning()` reaches zero
acceleration at 45 m/s; the M1.1 pure-motor fixture curve also ends there):

| Field | Default |
| --- | --- |
| `forward_gear_count` | 6 |
| `upshift_speeds_m_s` | 8, 14, 21, 29, 38 |
| `downshift_speeds_m_s` | 5, 10, 16, 23, 31 |
| `min_shift_dwell_s` | 0.25 |
| `min_hysteresis_gap_m_s` | 0.5 (absolute floor 0.25) |
| `reverse_exit_forward_speed_m_s` | 0.5 |
| `top_reference_speed_m_s` | 45 |

These are provisional M1.1 starting values, not frozen product handling.
M1.6/M1.7 measured handling data own their ratification.

## Checks

```sh
tools/gear_lab/run_validation.sh --timeout 300
```

The runner uses the pinned editor at
`work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
unless `--godot` overrides it, stages an isolated project copy, performs a
headless import, runs every case under the wall-clock limit, then reruns a
deliberate failing assertion and requires a nonzero exit. Options:
`--case <id>|all|intentional_failure`, `--private-dir FRESH_DIR`, `--log FILE`.

Cases: `custom_config_boundaries`, `acceleration_through_each_threshold`,
`downshifts`, `boundary_dithering`, `reverse_latch_transition`, `rpm_bounds`,
`invalid_atomicity`, `reset_replay`, plus the intentional-failure proof.

## Limits

Pure-kernel checks only: no scene, body, physics query, clock, rendering,
audio device, input routing or gameplay claim. Car states are explicit
scripted values, not integrated motor/airborne/contact physics. Airborne,
throttle/brake awareness, launch control and shift-torque effects are out of
scope. This is an integration-ready indication component, not an integrated
automatic transmission, and it is not M1 acceptance evidence.
