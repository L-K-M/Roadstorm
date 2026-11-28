# Provisional M1.7 physical sweeper bridge laboratory

This directory contains a bounded, provisional physical bridge from the
committed `CalibrationDriver` to the ordinary `DriveLab`
motor/gearbox/`MotorBodyAdapter` integration on the authored M1.2 HandlingLab
`sweeper` bay. It is the first physical sweeper run in this repository: it
drives the real car body over the real sweeper collider at a fixed 60 Hz and
crosses the 50 m approach-to-arc boundary.

This is not a grip/drift parity test, not a completed lap, not a pace or
fixture-performance claim, and not M1.7 acceptance. The 12 m/s target-speed
profile comes from `tools/calibration_path_lab/calibration_path_source.gd` and
is explicitly provisional, not measured or tuned.

## What actually runs

- `scenes/laboratory/drive_lab.tscn` is instantiated unchanged. Its own
  `ArcadeMotor`, `AutomaticGearbox`, `CharacterBody3D` hull and
  `MotorBodyAdapter` commit path are the only motion path.
- `HandlingLabBuilder` builds the full committed laboratory, including the
  authored `sweeper` bay geometry and `ConcavePolygonShape3D` colliders. A
  structural case verifies three sweeper terrain colliders, three surface
  runs, the authored section stations, the `Spawn_sweeper` marker pose, and a
  downward ray probe at 17 exact interpolated path stations landing on
  sweeper asphalt.
- `CalibrationPathSource.build()` converts the authored sweeper through the
  builder's private `_sample_bay` seam into a `CalibrationDriver.CalibrationPath`.
- Each logical tick: nearest projection of the committed road-plane position
  onto that path produces an externally validated station (independent of
  `DriveLab.get_road_station_m()`, whose single-axis straight projection cannot
  describe an arc); `CalibrationDriver.decide()` returns one command;
  `DriveLab.step_once()` performs exactly one motor/adapter commit.
- The bridge never integrates motion itself and never moves the body between
  ticks.

## Spawn seam

`DriveLab` starts every car at the authored straight-bay marker and exposes no
public spawn API for another bay. This lab reads the authored
`Bay_sweeper/Spawn_sweeper` marker and writes the already-built public
`CarState`, `start_position_m` and `body.global_transform` fields once, before
the first tick. The gearbox keeps its deterministic reset pair, no tick has
run, and no body-pose block is set. The bridge then verifies the installed
basis and origin map back to the published `CarState` through the committed
`MotorBodyAdapter.world_vector_to_road` mapping before accepting the run.

If that placement could not be made consistent with the adapter contract, this
lab would report the interface blocker instead of running; see `REPORT.md`.

## Recorded evidence

Per tick, both runs record: external station before/after, signed lateral error,
nearest distance, road and world positions, speed, heading, gear, normalized
and mutually exclusive command, lookahead, target station/speed, physical
result status, grounded/contact flags, substeps, remainder, and DriveLab's
straight-only projection as a diagnostic contrast. The summary reports actual
commit counts, drive time, maximum lateral error, minimum station delta and the
first arc-entry tick.

Two runs execute on the same host. They must agree within the declared
`REPEAT_TOLERANCE` (`1e-6`) on JSON-facing numbers and exactly on gear and
physical status.

## Prerequisites

- Pinned Godot editor at
  `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
  printing `4.7.2.stable.official.ed1daf0bf`.
- POSIX shell, `lockf`, `mktemp`, `sleep`, and the shared coordinator lock.
- A project tree containing `src/`, `fixtures/`, `project.godot`,
  `tools/calibration_path_lab/` and this directory. For frozen verification,
  use a `git archive HEAD` snapshot with only this directory overlaid.

## Run

From the repository root:

```sh
timeout 600 sh tools/calibration_sweeper_lab/run_validation.sh \
  --project <frozen-project-copy> \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --lock work/agents/coordinator/godot-test.lock \
  --timeout 120 --outer-timeout 300 \
  --summary-out <job-dir>/calibration_sweeper_summary.json \
  --log <job-dir>/calibration_sweeper_validator.log
```

Options: `--project DIR`, `--godot BIN`, `--lock FILE`, `--timeout SECONDS`,
`--outer-timeout SECONDS`, `--log FILE`, `--summary-out FILE`, `--keep-scratch`.

The runner stages a private copy plus private `HOME`, `TMPDIR`, `XDG_CACHE_HOME`,
`XDG_CONFIG_HOME` and `XDG_DATA_HOME`. It never writes the source checkout's
`.godot/` cache. Every engine invocation is serialized on the coordinator lock,
records the exact PID of the one Godot child it starts, and stops only that
child if the outer bound strands it. The console view drops the huge per-tick
trace lines; they remain in the bounded log file.

Exit codes:

- `0`: validator passed (`"pass":true`, `CHECKS_FAILED=0`) and the deliberate
  failure probe exited nonzero with `"pass":false`;
- `1`: a validator check, output gate or probe expectation failed;
- `2`: unsafe arguments or an unusable/mismatched engine.

## Output contract

The validator prints one `CALIBRATION_SWEEPER_LAB_CASE {...}` line per case,
then `CALIBRATION_SWEEPER_SUMMARY {...}` and `CHECKS_TOTAL=n CHECKS_FAILED=n`,
and exits 0/1. Per-run traces print as `CALIBRATION_SWEEPER_TRACE {...}`.
With `--summary-out`, the full summary JSON is written. The deliberate probe
prints `CALIBRATION_SWEEPER_FAILURE_PROBE {...}` with `"pass":false` and exits 3.

## Coverage

- live authored sweeper geometry, collider, fixture and path identity;
- two complete real 60-Hz runs with exactly one adapter step and commit per tick;
- externally validated nearest/projection station, lateral error, road/world
  positions, contact/ground/finite state, gear, drive time and arc entry;
- repeat determinism within a declared tolerance;
- refusal of missing, changed or internally invalid source without any motor
  step.

## Limits

- One pinned local engine; no cross-version or cross-host determinism claim.
- The private `HandlingLabBuilder._sample_bay` call remains a labelled
  provisional seam.
- The car starts from rest at the authored spawn; the fixture's rolling 30 m/s
  entry and paired grip/drift controllers are out of scope.
- No drift model, surface modifier, lap timing, fun or acceptance claim. Any
  arc entry here is preliminary physical evidence only.
