# Recorded probe evidence — Jolt backend, 26 November 2026, Apple M4 Max, macOS

Supersedes `../2026-11-26-apple-m4-max/` for every measured result: that
directory was recorded with **no** `physics/3d/physics_engine` setting, i.e.
backend `DEFAULT`, which this job's contrast run shows behaved as
GodotPhysics3D on this build. The project now pins Jolt (PLAN M0.1,
docs/TECHNICAL_DESIGN.md; review finding 5 of
`review/implementation/m0-five-jobs-opus-0bbb2f75-c3eb-47f5-9d89-771bce087012.md`),
so the evidence below was re-recorded under `Jolt Physics`.

## Setup

Commands were run from an **isolated copy** of the self-contained probe
(`work/agents/9725ba2c-802a-4115-9aeb-337b1dca99c8/isolated/tick_probe`, a
byte-identical copy of `tools/tick_probe` at the time of the run, no shared
`.godot/` cache), with Godot 4.7.2-stable (official, `ed1daf0bf`) on `PATH`:

```sh
godot --headless --fixed-fps 60 --path <copy> --script res://src/tick_probe.gd -- mode=structural
godot --headless --path <copy> --script res://src/tick_probe.gd -- mode=structural
godot --headless --max-fps 60 --path <copy> --script res://src/tick_probe.gd -- mode=structural
python3 tools/tick_probe/compare_modes.py --project <copy>
godot --headless --fixed-fps 60 --path <copy> --script res://src/tick_probe.gd -- \
    mode=throughput requests=2 inject_failure=1     # exit-code self-test
```

A second isolated copy with `3d/physics_engine="GodotPhysics3D"` recorded
`backend-contrast-godotphysics3d.*`, and a scratch script
(`margin-experiment.txt`) characterized the query margins.

## Results

| Run | Checks | Exit | Backend setting |
| --- | --- | --- | --- |
| `structural-fixed-fps` | 58/58 | 0 | Jolt Physics |
| `structural-default` | 58/58 | 0 | Jolt Physics |
| `structural-max-fps-60` | 58/58 | 0 | Jolt Physics |
| `compare_modes.py` | 9/9 PASS | 0 | Jolt Physics |
| `mode=throughput requests=2 inject_failure=1` | 5 checks, 1 failed | 1 | Jolt Physics |
| `backend-contrast-godotphysics3d` | 57/58 | 1 | GodotPhysics3D |

The contrast run's single failure is the intended one: the new check
"pinned 3D physics backend is Jolt Physics" fails because that copy
deliberately selects GodotPhysics3D. The exit-code self-test's single failure
is the injected failure; exit 1 confirms a failing check exits nonzero.

`compare_modes.py` (50 requests, 600 ticks, 10 simulated seconds):

| Mode | Ticks | Wall time | Logical ticks/s | Speedup | Final z |
| --- | ---: | ---: | ---: | ---: | ---: |
| `--fixed-fps 60` | 600 | 0.152 s | 3,935.7 | 65.6x | -99.999641418 m |
| `--max-fps 60` | 600 | 10.013 s | 59.9 | 0.999x | -99.999641418 m |

Both modes report a constant 1/60 s physics delta and identical final
positions (`|dz| = 0`). Wall-clock numbers are host/load specific.

## Backend verification (and its limits)

- **Setting, read at runtime.** Every Jolt run reports
  `physics_engine_setting = "Jolt Physics"` with allowed values
  `["DEFAULT", "Jolt Physics", "GodotPhysics3D", "Dummy"]` from the engine
  property list. The main project (`project.godot`) reads back the same value
  when launched from an isolated copy.
- **Direct backend identity is NOT observable from GDScript.**
  `PhysicsServer3D` is opaque, and this build prints no backend line even with
  `--verbose`, so no run can name the instantiated backend from inside the
  engine. The pin is therefore verified indirectly: the setting value plus the
  contrast below.
- **The setting is honored at runtime.** The identical probe under explicit
  `GodotPhysics3D` vs `Jolt Physics` produces measurably different contact
  physics (table below), so the selection changes the physics server actually
  used; it is not a cosmetic label.
- **What `DEFAULT` was.** The explicit-`GodotPhysics3D` run reproduces the old
  `DEFAULT` evidence bit-for-bit on every contact metric (wall stop
  -1.09970760345459 m, prediction error 0.000183820724487305 m, `test_move`
  artifact 0.0759787634015083 m), i.e. the superseded evidence was measured on
  Godot Physics. Per engine documentation `DEFAULT` is GodotPhysics3D on this
  platform, but that mapping is documented behavior, not something these runs
  directly observed.

## Measured differences: Jolt vs GodotPhysics3D (same command trace)

| Metric (structural, `--fixed-fps 60`) | Jolt (this dir) | GodotPhysics3D (contrast / old DEFAULT) |
| --- | ---: | ---: |
| Wall stop z (contact plane -1.1 m) | -1.099748135 m | -1.099707603 m |
| Wall max prediction error (margin-0 cast) | 0.000162363 m | 0.000183821 m |
| Wall `test_move` recovery artifact | 0.069633216 m | 0.075978763 m |
| 65 m/s stop z (contact plane -0.6 m) | -0.599701285 m | -0.599851549 m |
| 65 m/s substeps / max substep | 14 / 0.25 m | 14 / 0.25 m |
| Open-road 60-tick prediction error | 0 m | 0 m |
| Open-road 600-tick final z | -99.999641418 m | -99.999641418 m |

## Correction made when switching to Jolt: cast margin

Under Jolt, `DirectSpaceState3D.cast_motion` **grows** the query shape by
`PhysicsShapeQueryParameters3D.margin`, and `CharacterBody3D.move_and_collide`
stops at the real surface regardless of the body's `safe_margin`. The old
probe cast with `margin = SAFE_MARGIN (0.08)`, which under GodotPhysics
happened to track the committed motion (error <= 0.000184 m) but under Jolt:

- predicts a stop 0.08 m early on approach (e.g. gap 0.10 m, margin 0.08:
  predicted travel 0.0182 m vs committed 0.0990 m), and
- reports the whole segment **clear** once the grown hull already overlaps the
  contact, while the committed motion stays 0 — a full-substep (0.1667 m)
  prediction error that failed the probe's own wall check.

`margin-experiment.txt` is the controlled measurement (margin 0 / 0.04 / 0.08
across approach gaps 0.20-0.00 m). With `margin = 0` — casting the real hull —
the prediction reproduces the committed travel to <= 1e-6 m on approach and
0 m while resting in contact, under Jolt. The probe now casts with margin 0
(`CAST_QUERY_MARGIN` in `src/tick_coordinator.gd`); the body's own
`safe_margin` is unchanged. Both values are recorded in every report's
`environment` block (`swept_cast_margin_m`, `character_body_safe_margin_m`).

Consequence for M1: a margin-grown `cast_motion` must not be used as the
committed-motion predictor under Jolt. Plan speculative queries against the
real hull (margin 0) and treat any margin as a separate, explicit safety
buffer.

## Files

| Path | Role |
| --- | --- |
| `structural-{fixed-fps,default,max-fps-60}.json` | full `PROBE_RESULT` payloads under Jolt |
| `structural-*.checks.txt` | matching `CHECKS_TOTAL/FAILED` summary |
| `compare-modes.txt` | accelerated-vs-real-time comparison output |
| `backend-contrast-godotphysics3d.*` | same probe with explicit GodotPhysics3D (1 intended failure) |
| `exit-code-selftest.txt` | injected-failure run, exit 1 |
| `margin-experiment.txt` | cast/test_move/move_and_collide margin characterization |

## Limitations

- Headless dummy display/audio drivers: no rendering, input, audio or
  windowing claim. `rendering_method_setting` is the project default and is
  irrelevant to these results.
- Same-host determinism only; cross-platform byte equality is not claimed.
- The active physics backend cannot be named from inside the engine (see
  above); the pin is verified through the setting value and the contrast run.
- Wall-clock throughput is host-load dependent; the structural checks are the
  stable gate.
