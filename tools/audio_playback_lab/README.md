# M1.5 one-car synthesized feedback playback laboratory

A one-car `Node` component around the committed `VehicleFeedbackSynth`, plus a
pinned-Godot isolated headless node validator. This is a playback prototype:
two nonpositional voices, one fixed engine loop and one fixed tire loop,
mapped to `pitch_scale`/`volume_db`. It is not the eventual shared
`AudioDirector`, not a four-player mixer and not an audio-quality approval.

## Files

| Path | Role |
| --- | --- |
| `src/audio/vehicle_feedback_player.gd` | `VehicleFeedbackPlayer` node: two `AudioStreamPlayer` children, one-time PCM-to-`AudioStreamWAV` conversion, read-only `CarState`/`DriverCommand` mapping |
| `tools/audio_playback_lab/validate_audio_playback.gd` | headless `SceneTree` validator: seven cases plus deliberate-failure proof |
| `tools/audio_playback_lab/run_validation.sh` | isolated-copy wrapper: pin check, staged import, bounded validator and failure proof |

Helper scripts live only under `tools/audio_playback_lab/`; CI test
auto-discovery scans `tests/` and `tools/smoke/`, so these helpers are not
silently run as project checks.

## Component contract

- Owns exactly two children named `Engine` and `Tire`, both plain
  `AudioStreamPlayer` (nonpositional), and nothing else.
- `setup()` renders one reference loop per voice through the real
  `VehicleFeedbackSynth` at the configured sample rate, segment duration and
  seed, converts each returned segment into one `AudioStreamWAV`
  (`FORMAT_16_BITS`, mono, `LOOP_FORWARD`, `loop_begin=0`,
  `loop_end=frame_count`), and assigns each stream once. Conversion preserves
  the synth bytes exactly.
- `apply(car_state, command)` reads committed speed, slip, grounded and
  normalized throttle, then writes only `pitch_scale`/`volume_db`. It never
  re-synthesizes, replaces or rebuilds a stream and allocates no per-tick
  container.
- Inputs and every derived target are validated before any playback write. A
  refusal leaves the last accepted pitch/gain and both stream assignments
  untouched, leaves the rejected records untouched, and records a reason in
  `get_last_error()`.
- Setup memory is bounded by two segments at the synth frame ceiling
  (`MAX_SETUP_BYTES = 768000` bytes of PCM).
- `teardown()` removes both players and drops both streams; `setup()` can run
  again afterwards.

### Provisional coefficients

These mirror the committed synth defaults; they are laboratory starting points,
not frozen M1.5/M5 specification. Pitch shifting one fixed loop changes timbre
with speed.

| Engine map | Value | Tire map | Value |
| --- | --- | --- | --- |
| full speed | 65 m/s | full slip | 35 deg |
| idle / top fundamental | 55 / 240 Hz | slip threshold | 2 deg |
| throttle pitch lift | 1.25x | speed gate / reference | 3 / 30 m/s |
| level weights | 0.35 speed + 0.65 throttle | full intensity | 1.0 |
| idle level | 0.18 | | |
| reference loop | full speed, full throttle | reference loop | full slip, full speed |
| pitch clamp | [0.1, 4.0] | gain clamp | [-80, 0] dB |

The engine reference loop is rendered at full speed/full throttle, so runtime
pitch scales sit at or below 1.0. The tire reference loop is rendered at full
slip/full speed, so runtime tire gain sits at or below 0 dB. Tire pitch is
fixed; this slice maps engine pitch/gain and tire gain only.

## Run

From the repository root, against an isolated copy:

```sh
tools/audio_playback_lab/run_validation.sh \
    --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
    --private-dir work/agents/<job-id>/private/audio_playback_lab \
    --log work/agents/<job-id>/logs/audio-playback-main.log \
    --timeout 180 --overall-timeout 300
```

With `--log`, all scratch logs and caches stay next to that file. Every Godot
invocation has a per-engine watchdog capped at 180 s and the whole run shares a
300 s outer deadline. The runner verifies the pinned engine version, stages a
private copy excluding `.git`, `.godot`, `work`, `tools/ci/out` and Python
caches, runs a bounded headless import, requires `CHECKS_FAILED=0`, and finally
requires `--case=intentional_failure` to exit nonzero with `"pass":false`.

## Validation cases

`nodes_and_streams`, `stream_stability_no_resynthesis`, `response_bounds`,
`invalid_atomic_refusal`, `deterministic_setup`, `teardown`,
`headless_play_flag`.

Coverage includes actual node classes and counts, `AudioStreamWAV` format,
mono flag, mix rate, PCM byte sizes, exact zero seam bytes, loop mode and loop
points, byte equality with independent synth renders, stable stream references
and unchanged PCM across 240 updates, bounded/monotonic idle-to-fast and
grip-to-slide response, atomic refusal for null, NaN, infinite,
overflow-to-infinite-speed, out-of-range and incompatible inputs, caller-state
immutability, byte-identical setup, teardown/re-setup and the dummy-driver
play/stop flag.

## Failure proof and limits

The runner invokes `--case=intentional_failure`; a green run is not inferred
from an exit code alone. Honest limits:

- Headless Godot uses dummy display and audio drivers. The play/stop case
  proves only that the dummy server accepts voice start/stop; it cannot prove
  audible output, mix balance, timbre or comfort.
- No listener, bus routing, stereo pan, attenuation, voice budget, mixing,
  pause policy or `AudioDirector` is exercised.
- Car states and commands are scripted records; no simulation authority is
  read or written, and no sound feeds physics, score, AI or car state.
- All mapping coefficients are provisional and require perceptual review and
  production tuning.
- LongCat-authored creative source remains un-cleared for release; provenance
  OI-02 is open. No M1.5 or M1 acceptance claim is made.
