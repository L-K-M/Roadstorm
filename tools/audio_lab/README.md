# M1.5 procedural vehicle feedback laboratory

A deterministic, bounded oscillator/noise PCM source for one car's basic engine
tone and tire scrub (PLAN.md M1.5), plus a pinned-Godot isolated headless
numeric validator. This is a pure synthesis prototype: no `AudioStreamPlayer`,
listener, bus, simulation authority, sampled audio or automatic playback lives
here.

## Files

| Path | Role |
| --- | --- |
| `src/audio/vehicle_feedback_synth.gd` | pure `RefCounted` generator: engine/tire requests, provisional tuning, deterministic PCM segments, read-only `CarState`/`DriverCommand` bundle mapping |
| `tools/audio_lab/audio_lab_driver.gd` | shared builders and numeric measurement helpers; calls the real synth, never re-implements its math |
| `tools/audio_lab/validate_audio_lab.gd` | headless `SceneTree` validator, eight cases plus deliberate-failure proof |
| `tools/audio_lab/render_preview.gd` | bounded local 16-bit mono WAV preview writer (diagnostic only) |
| `tools/audio_lab/run_validation.sh` | isolated-copy wrapper: pin check, staged import, bounded validator and failure proof |

Helper scripts live only under `tools/audio_lab/`; CI test auto-discovery scans
`tests/` and `tools/smoke/`, so these helpers are not silently run as project
checks.

## Generator contract

- Every render is stateless: identical validated inputs and seed produce
  byte-identical signed 16-bit little-endian mono PCM. Noise uses a local
  seeded `RandomNumberGenerator`; no global RNG.
- Requests are explicit records (`EngineParams`, `TireParams`) with finite,
  normalized fields. Nonfinite values, nonpositive durations and out-of-range
  loop modes are refused; failed `set_from_raw()` leaves prior values intact.
  Direct field assignment is rechecked at render time.
- Duration is clamped to `[0.05, 2.0]` s; sample rate is limited to
  `[8000, 48000]` Hz; frame count is independently capped at 192000.
- Synthesis applies DC removal, downward-only peak limiting to `PEAK_LIMIT`
  (0.89, about 1 dB headroom), then symmetric raised-cosine fades and exact
  zero endpoint samples for clean looping. Encoded 16-bit codes are clamped to
  the same peak ceiling, so decoded magnitude never exceeds it.
- Output records carry `source`, sample rate, frame count, requested/actual
  duration, clamping flag, loop mode, seed, pre-limit peak, limiter gain,
  post-limit peak/RMS/DC, fade length and effective-coefficient metadata.
- `render_bundle(car_state, command)` reads committed `CarState` speed/slip/
  grounded and `DriverCommand` throttle only. It returns separate `engine` and
  `tire` segments plus telemetry naming both sources. It writes no simulation
  state and has no force, score, assist or AI effect.

### Provisional coefficients

These are starting points for numeric and preview work, not frozen M1.5/M5
audio specification. They require perceptual review.

| Engine | Value | Tire | Value |
| --- | --- | --- | --- |
| sample rate | 44100 Hz | sample rate | 44100 Hz |
| max speed | 65 m/s (~234 km/h) | max speed | 65 m/s |
| idle / top fundamental | 55 / 240 Hz | slip threshold / full | 2 / 35 deg |
| throttle pitch lift | 1.25x | noise band centre | 1500 Hz |
| harmonics | 8, base 0.55, rolloff 1.15 | resonance tone | 2200 Hz |
| sub-octave / detune | 0.22 / 0.28 at 9 cents | tone / noise gain | 0.35 / 0.55 |
| AM depth | 0.10 | speed gate / reference | 3 / 30 m/s |
| noise floor / throttle / speed | 0.03 / 0.10 / 0.05 | fade | 0.02 s |
| idle level / output gain | 0.18 / 1.0 | | |
| fade | 0.012 s | | |

Partial gains are normalized by their summed magnitude so ordinary full-level
operation stays near the peak budget; `output_gain` above one deliberately
exercises the limiter and is clamped by it. Engine pitch maps exponentially
across normalized speed with throttle lift. Tire intensity uses smoothstep over
normalized absolute slip above the threshold, scaled by a speed gate and
silenced while airborne.

## Run

From the repository root, against an isolated copy:

```sh
tools/audio_lab/run_validation.sh \
    --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
    --private-dir work/agents/<job-id>/private/audio_lab \
    --log work/agents/<job-id>/logs/audio-lab-main.log \
    --timeout 300
```

The runner verifies the pinned engine version, stages a private copy excluding
`.git`, `.godot`, `work` and Python caches, runs a bounded headless import,
then requires `CHECKS_FAILED=0`, and finally requires the
`--case=intentional_failure` proof to exit nonzero with `"pass":false`.
`--case <id>` selects one case. Direct invocation from an isolated project copy
after import also works:

```sh
godot --headless --fixed-fps 60 --path <isolated-project> \
    --script res://tools/audio_lab/validate_audio_lab.gd "--case=all"
```

## Validation cases

`deterministic_replay`, `nonfinite_and_invalid_input`, `length_bounds`,
`engine_speed_throttle_response`, `tire_intensity_vs_slip`,
`clipping_peak_dc_limits`, `loop_endpoints`, `car_independence`.

Coverage includes identical-input byte equality, seed sensitivity, NaN/inf and
range refusal, duration/rate limits and clamping, low/medium/high speed and
throttle RMS/fundamental response, tire intensity versus slip, zero-slip /
airborne silence, default full-throttle bounds, a deliberately overdriven
limiter fixture, peak/DC/16-bit limits, exact zero loop endpoints, and
one/two-car independence with source-labelled telemetry.

## Local WAV preview

Diagnostic only, normally under an ignored `work/` directory:

```sh
godot --headless --path <isolated-project> \
    --script res://tools/audio_lab/render_preview.gd -- \
    --out=/absolute/path/to/ignored/previews --seconds=1.0
```

It writes four bounded 16-bit mono files (`engine_medium.wav`,
`engine_high.wav`, `tire_scrub.wav`, `combined.wav`), clamps total output to
2,000,000 bytes, and prints `PREVIEW_WRITTEN` lines. Numeric tests and this
preview prove nothing about audible quality, mix balance or comfort.

## Failure proof and limits

The runner invokes `--case=intentional_failure`; a green run is not inferred
from an exit code alone. Honest limits: pure-kernel checks only. No scene,
body, physics query, clock, rendering, audio device, listener, bus, mixing,
attenuation, voice budget or input routing is exercised. Headless Godot uses
dummy display/audio drivers. Car states are scripted values, not integrated
motor or contact physics. No M1.5/M1 acceptance or audio-listening claim is
made.

LongCat-authored creative source remains un-cleared for release; provenance
OI-02 is open. This tool does not resolve that gate.
