# Provisional M1.7 physical sweeper bridge laboratory

This directory contains a bounded, provisional physical bridge from the
committed `CalibrationDriver` to the ordinary `DriveLab`
motor/gearbox/`MotorBodyAdapter` integration on the authored M1.2 HandlingLab
`sweeper` bay. It is the first physical sweeper run in this repository: the
default case drives the real car body over the real sweeper collider at a fixed
60 Hz and crosses the 50 m approach-to-arc boundary. A separate opt-in witness
continues through the full authored arc and stops after crossing 245 m, early
in the straight exit segment.

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

If that placement cannot be made consistent with the adapter contract, the lab
fails the affected case instead of silently running from the wrong bay.

## Recorded evidence and assertions

Per tick, both default runs record: external station before/after and its
delta, signed lateral error, nearest distance, road and world positions, speed,
heading, gear, normalized and mutually exclusive command, lookahead, target
station/speed, physical result status, grounded/reverse/contact/wall-contact
flags, substeps, remainder, and DriveLab's straight-only projection as a
diagnostic contrast. The summary reports actual commit counts, drive time,
maximum lateral error, minimum station delta and the first arc-entry tick.

The default arc-entry case now asserts the intended clean-drive facts rather
than only recording them: every one of the 420 ticks in each run is grounded,
with zero contact flags and zero wall-contact flags. A wall scrape or airborne
tick fails the run.

Two runs execute on the same host. Every JSON-facing numeric trace field is
repeat-compared within the declared `REPEAT_TOLERANCE` (`1e-6`). The exact
repeat comparison covers tick number, gear, physical result status, grounded,
reverse, contact, wall-contact and substep fields. This is a same-host,
same-engine determinism check only.

## Refusal controls

The missing authored-source and changed-geometry probes are component-refusal
tests of `CalibrationPathSource.build()`: they prove that those component inputs
are rejected without fallback and that the idle laboratory used for the probe
does not step. They are not represented as end-to-end source-corruption tests.

The invalid produced-path probe is a genuine bridge-entry control. The same
`_run_physical_bridge` entry point used by the real runs receives a
structurally invalid `CalibrationPath`; its input validation must refuse it
before spawn placement or the first adapter step. The case checks zero adapter
steps, zero commits, zero recorded ticks, unchanged state and a noncompleted
run. `CalibrationDriver.decide()` is also checked directly for the expected
`invalid_path` refusal and absent command.

## Opt-in full-arc-exit witness

`--full-arc-exit` runs a separate witness after the default validator and
deliberate failure probe have passed. It uses the same authored spawn, source,
driver tuning and ordinary DriveLab motion path, but a hard budget of 1800
logical ticks and a threshold at station 245 m. The authored arc ends at about
238.4956 m, so the threshold is inside the straight exit segment rather than at
the arc boundary. The mode stops each run immediately after the first threshold
crossing; it does not drive the remainder of the exit segment.

Coordinator verification of frozen plain archive `d4dd56d` plus the two-file
full-arc-exit lab extension recorded two identical real DriveLab runs:

- 1306 committed ticks per run, with the zero-based threshold crossing at tick
  1305 and final station 245.1527094839 m;
- arc entry at zero-based tick 304, station 50.0862407253 m;
- authored arc end first crossed at zero-based tick 1272, station
  238.6883769034 m;
- maximum absolute lateral error 0.8535963297 m and maximum nearest distance
  0.8535962701 m, inside the 6 m road half-width bound;
- grounded 1306/1306 ticks, zero contact ticks, zero wall-contact ticks and no
  road half-width breach;
- minimum speed 0.1325000077 m/s, maximum speed 11.7592506409 m/s and final
  speed 11.7566394806 m/s under the provisional 12 m/s target profile;
- repeat worst numeric difference 0.0 and identical exact trace fields.

Those measurements are preliminary physical evidence for this specific pinned
host/engine/source combination. They do not establish bounded tracking quality,
the fixture's rolling 30 m/s entry, grip/drift parity, a lap or M1.7 acceptance.

The ignored local `REPORT.md`, when present, is worker-generated evidence for
the current repaired lab. It is not an input, a required file or part of the
validator output contract.

## Prerequisites

- Pinned Godot editor at
  `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
  printing `4.7.2.stable.official.ed1daf0bf`.
- POSIX shell, `lockf`, `mktemp`, `sleep`, and the shared coordinator lock.
- A project tree containing `src/`, `fixtures/`, `project.godot`,
  `tools/calibration_path_lab/` and this directory. For frozen verification of
  this revision, use a plain `git archive d4dd56d` snapshot with only this
  directory overlaid from the inspected lab revision.

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
`--outer-timeout SECONDS`, `--log FILE`, `--summary-out FILE`,
`--full-arc-exit`, `--exit-log FILE`, `--exit-summary-out FILE`,
`--keep-scratch`.

Add `--full-arc-exit` to run the opt-in witness. When `--log` or
`--summary-out` is supplied without explicit exit output paths, the runner
derives `<name>.exit.log` and `<name>.exit.json` respectively.

The runner stages a private copy plus private `HOME`, `TMPDIR`, `XDG_CACHE_HOME`,
`XDG_CONFIG_HOME` and `XDG_DATA_HOME`. It never writes the source checkout's
`.godot/` cache. Every engine invocation is serialized on the coordinator lock,
records the exact PID of the one Godot child it starts, and stops only that
child if the outer bound strands it. The console view drops the huge per-tick
trace lines; they remain in the bounded log file.

The scratch root is a fresh `mktemp` child owned by this runner. Copied
read-only source permissions are repaired only inside that scratch tree without
following symlinks. Before printing `PASS`, the runner verifies that this exact
scratch child was removed unless `--keep-scratch` was requested; cleanup failure
is reported and makes the run fail. The runner never accepts a user-supplied
cleanup path.

Exit codes:

- `0`: validator passed (`"pass":true`, `CHECKS_FAILED=0`) and the deliberate
  failure probe exited nonzero with `"pass":false`; when requested, the
  full-arc-exit witness also passed;
- `1`: a validator check, output gate, probe expectation, optional witness or
  scratch cleanup failed;
- `2`: unsafe arguments or an unusable/mismatched engine.

## Output contract

The default validator prints one `CALIBRATION_SWEEPER_LAB_CASE {...}` line per
case, then `CALIBRATION_SWEEPER_SUMMARY {...}` and
`CHECKS_TOTAL=n CHECKS_FAILED=n`, and exits 0/1. Per-run traces print as
`CALIBRATION_SWEEPER_TRACE {...}`. With `--summary-out`, the full summary JSON
is written. The deliberate probe prints `CALIBRATION_SWEEPER_FAILURE_PROBE
{...}` with `"pass":false` and exits 3.

The opt-in witness prints `CALIBRATION_SWEEPER_EXIT_CASE {...}`, compact
`CALIBRATION_SWEEPER_EXIT_TRACE {...}` selected samples,
`CALIBRATION_SWEEPER_EXIT_SUMMARY {...}` and `CHECKS_TOTAL=n
CHECKS_FAILED=n`. With `--exit-summary-out` (or the derived path), the full
structured exit summary is written.

## Coverage

- live authored sweeper geometry, collider, fixture and path identity;
- two complete real 60-Hz arc-entry runs with exactly one adapter step and
  commit per tick;
- externally validated nearest/projection station, lateral error, road/world
  positions, finite state, gear, drive time and arc entry;
- per-run assertions that every default arc-entry tick is grounded and free of
  contact and wall-contact flags;
- repeat comparison of every recorded numeric trace field within tolerance and
  every recorded flag/enumerated field exactly;
- component refusal of missing or changed source, plus a genuine invalid-path
  bridge-entry control that refuses before any motor step;
- with `--full-arc-exit`, two bounded real runs through the authored arc to
  station 245 m, with the same clean-drive and repeat evidence extended over
  the recorded ticks.

## Limits

- One pinned local engine; no cross-version or cross-host determinism claim.
- The private `HandlingLabBuilder._sample_bay` call remains a labelled
  provisional seam.
- The car starts from rest at the authored spawn. The fixture's rolling 30 m/s
  entry and paired grip/drift controllers are out of scope.
- The 12 m/s target is a provisional profile input, not a measured or tuned
  achievement. The observed full-arc-exit maximum speed was below 12 m/s.
- The full-arc-exit witness stops just inside the exit straight at 245 m. It
  does not complete the authored road, a lap, or a race scenario.
- Lateral containment is a 6 m road-center half-width bound, not car-body
  clearance and not a tuned controller quality limit.
- No drift model, surface modifier, lap timing, fun or acceptance claim. Arc
  entry and arc exit here are preliminary physical evidence only.
