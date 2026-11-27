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
| `src/simulation/automatic_gearbox.gd` | pure gearbox: config/state validation, stateful gear selection, reverse-latch handling, rpm indication, atomic refusal, deterministic reset, validated canonical-state restore and committed CarState mirror helper |
| `tools/gear_lab/validate_gear_lab.gd` | headless `SceneTree` validator with one case per required behavior |
| `tools/gear_lab/gear_lab_extensions.gd` | follow-up dwell-domain and restore-and-mirror cases, loaded dynamically so the historical-source control still parses against the older gearbox |
| `tools/gear_lab/gear_lab_driver.gd` | shared builders/checks; calls the real gearbox, never re-implements its math |
| `tools/gear_lab/run_validation.sh` | bounded isolated-copy wrapper (stages, imports, runs validator and failure proof) |
| `tools/gear_lab/legacy_automatic_gearbox.gd.txt` | historical motion-only-guard gearbox source for the old-source negative control (inert text, staged over the gearbox only for `--legacy-gearbox`) |

Helper scripts live only under `tools/gear_lab/`; nothing here is placed in
`tests/`, so CI's test auto-discovery does not pick up lab helpers.

## Component contract

- `AutomaticGearbox.create(config)` copies and validates a `GearboxConfig`;
  it returns `null` for null/invalid configuration. Config values are copied,
  so later caller mutation cannot change a live gearbox.
- `gearbox.propose(car_state, dt)` requires a fully finite committed record
  (`CarState.is_finite()`), then reads the signed forward speed
  (`velocity_m_s` projected on `heading_rad`) and the committed
  `car_state.reverse_engaged` latch. It returns `GearboxProposal` with
  `gear_index` (`-1` or `1..N`), `normalized_rpm` in `[0, 1]`, and a
  `ShiftEvent` (`from_gear`, `to_gear`, `direction`, post-shift
  `normalized_rpm`) only when the gear actually changed. `dt` must be the
  declared `DT` (1/60 s).
- Invalid input or an unexpected nonfinite result is refused atomically:
  `propose` returns `null` and leaves the gearbox and car untouched. Any
  nonfinite numeric `CarState` field refuses, including fields the gearbox
  does not consume (`position_m` and the inert seams); motion is validated as
  part of the whole record rather than by a narrower field subset.
- `gearbox.reset()` restores the deterministic initial state: gear 1, zero
  dwell, zero rpm. No clock, RNG or input is consulted.
- The private `GearboxState` is the canonical gear/dwell/rpm indication.
  `gearbox.restore_state(state)` atomically replaces it with a validated copy:
  finite, gear `-1` or `1..forward_gear_count` for this configuration, dwell in
  `[0, min_shift_dwell_s]` (never above `MAX_SHIFT_DWELL_S`), rpm in
  `[0, 1]`. Invalid or null input returns `false` and leaves the gearbox
  unchanged; the caller's object is copied, not shared.
- `gearbox.restore_and_mirror(candidate_state, car_state)` is the
  all-or-nothing checkpoint form: it validates the candidate state against
  this configuration and the finite committed `CarState` together, commits a
  copy of the candidate, and returns a repaired copy of the car. Any refusal
  returns `null` and leaves both the gearbox and the input record unchanged.
- `gearbox.mirror_gear(car_state)` returns a copy of a finite committed
  `CarState` whose `gear_index` mirrors the gearbox's canonical current gear,
  or `null`. It reads only this gearbox's own validated canonical state; no
  proposal enters the call, so a stale or foreign proposal cannot affect it.
  Call it after a successful `propose()` or immediately after
  `restore_state()`. Neither the input record nor the gearbox is mutated.
  `mirror_gear()` cannot bind an arbitrary car/tick identity by itself; the
  integrator owns pairing the returned gear with the accepted tick.
- Reverse obeys the existing motor latch, never signed velocity alone: a
  negative signed speed with the latch released selects a forward gear;
  entering `-1` requires the latch. Leaving `-1` requires the latch to clear
  and forward travel to reach `reverse_exit_forward_speed_m_s`, so latch
  release during backward roll does not snap to a forward gear.
- Forward shifts use strict thresholds (`>` up, `<` down), each pair keeps at
  least `min_hysteresis_gap_m_s` of separation, and committed shifts are
  separated by `min_shift_dwell_s`. Boundary dither inside the band therefore
  produces exactly one event.

The future simulation integrator owns calling `mirror_gear()` after a
successful proposal, choosing whether to feed this indicator from
throttle/brake state, and routing `ShiftEvent` to presentation/audio. This
component neither applies torque nor emits sound.

State boundary (resolved): `AutomaticGearbox.GearboxState` is canonical;
`CarState.gear_index` is a committed mirror initialized to gear 1 like
`reset()`. A replay/restore MUST save and restore the `GearboxState`
alongside the `CarState`, then apply them as one explicit atomic step with
`restore_and_mirror(saved_gearbox_state, car_state_copy)` and no intervening
tick. The compatible two-call form `restore_state()` followed immediately by
`mirror_gear()` is available, but that window is not transactional. In the
normal tick path `propose()` commits the canonical state immediately and
must be called exactly once per accepted tick from that car's committed
record; the integrator then pairs the returned gear with the matching car and
tick via `mirror_gear()`. Restoring `CarState` alone is insufficient: it
carries no dwell or canonical rpm, so shift timing changes.

## Provisional defaults

Six forward gears span the committed 0-45 m/s laboratory motor envelope
(`src/laboratory/drive_lab.gd` `make_laboratory_tuning()` reaches zero
acceleration at 45 m/s; the M1.1 pure-motor fixture curve also ends there):

| Field | Default |
| --- | --- |
| `forward_gear_count` | 6 |
| `upshift_speeds_m_s` | 8, 14, 21, 29, 38 |
| `downshift_speeds_m_s` | 5, 10, 16, 23, 31 |
| `min_shift_dwell_s` | 0.25 (accepted in `[0, MAX_SHIFT_DWELL_S]`, inclusive) |
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
`--legacy-gearbox FILE` runs only the historical-source negative control: the
supplied older source is staged over the isolated gearbox and must fail
`--legacy-case` (default `invalid_atomicity`).

Cases: `custom_config_boundaries`, `acceleration_through_each_threshold`,
`downshifts`, `boundary_dithering`, `reverse_latch_transition`, `rpm_bounds`,
`invalid_atomicity`, `reset_replay`, `restore_replay`, `dwell_domain`,
`restore_and_mirror`, plus the intentional-failure proof.

## Limits

Pure-kernel checks only: no scene, body, physics query, clock, rendering,
audio device, input routing or gameplay claim. Car states are explicit
scripted values, not integrated motor/airborne/contact physics. Airborne,
throttle/brake awareness, launch control and shift-torque effects are out of
scope. `restore_state()` is an in-memory state-boundary API; persistence,
DriveLab wiring, HUD/audio routing and an integrated automatic transmission
remain future integration work. This is not M1 acceptance evidence.
