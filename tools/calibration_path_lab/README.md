# Provisional M1.7 calibration-path laboratory

This directory contains a bounded, provisional conversion check for the M1.2
HandlingLab `sweeper` bay. It converts the live authored bay through
`HandlingLabBuilder._sample_bay` into a `CalibrationDriver.CalibrationPath`,
then validates station ordering, section-boundary handling, coordinate mapping,
arc shape, repeatability, provisional labels and negative-control refusals.

This is not a physical sweeper test. It does not drive a car, run the motor,
measure grip or drift, calibrate a racing line, produce fixture evidence, or
establish M1.7 acceptance. The constant 12 m/s target speed is an authored
preliminary laboratory value, explicitly not measured or tuned.

## Boundary-station semantics

`HandlingLabBuilder._sample_bay` intentionally emits the exact same centerline
cross-section at both sides of an ordinary section join so adjacent road ribbons
abut without a gap. For the sweeper's 1 m sampling this produces 292 raw
samples: indices 51 and 241 are exact join duplicates. The conversion validates
that each repeated station is the same world position at the recorded end/start
station of adjacent sections, then skips the duplicate because
`CalibrationPath` requires strictly increasing stations. The resulting path has
290 unique samples and a 288.49556 m nominal station range (50 m approach +
120 m radius * pi/2 + 50 m exit). Other repeated stations, decreasing or
reordered stations, broken runs and discontinuous positions are refused.

## Prerequisites

- Pinned Godot editor at
  `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
  printing `4.7.2.stable.official.ed1daf0bf`.
- POSIX shell, `lockf`, `mktemp`, `sleep`, and the shared coordinator lock.
- A project tree containing `src/`, `fixtures/`, `project.godot` and this
  directory. For repair verification, use a frozen `git archive HEAD` snapshot
  with this directory overlaid; do not validate other agents' live edits.

## Run

From the repository root:

```sh
timeout 600 sh tools/calibration_path_lab/run_validation.sh \
  --project <frozen-project-copy> \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --lock work/agents/coordinator/godot-test.lock \
  --timeout 120 --outer-timeout 300 \
  --log <job-dir>/calibration_path_validator.log
```

Options: `--project DIR`, `--godot BIN`, `--lock FILE`, `--timeout SECONDS`
(inner per-engine watchdog value retained for interface compatibility; the
runner's outer watchdog is the enforced bound), `--outer-timeout SECONDS`,
`--log FILE`, `--keep-scratch`.

The runner stages a private copy and private `HOME`, `TMPDIR`,
`XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME`. It never writes the
source checkout's `.godot/` cache. Every engine invocation is serialized on the
coordinator lock, records the exact PID of the one Godot child it starts, and
stops only that child if the outer bound strands it.

Exit codes:

- `0`: validator passed (`"pass":true`, `CHECKS_FAILED=0`) and the deliberate
  failure probe exited nonzero with `"pass":false`;
- `1`: a validator check, output gate or probe expectation failed;
- `2`: unsafe arguments or an unusable/mismatched engine.

## Output contract

The validator prints one `CALIBRATION_PATH_LAB_CASE {...}` line per case, then
`CALIBRATION_PATH_LAB_SUMMARY {...}` and `CHECKS_TOTAL=n CHECKS_FAILED=n`, and
exits 0/1. On success it can write the full summary JSON with
`--summary-out=<path>`. The deliberate probe prints
`CALIBRATION_PATH_FAILURE_PROBE {...}` with `"pass":false` and exits 3.

## Coverage

- live authored bay and fixture identity/shape guards;
- exact raw sample count, unique sample count and two genuine join duplicates;
- station order, first/last station and declared open-profile length;
- committed `MotorBodyAdapter.world_vector_to_road` mapping
  (`Vector2(world.x, -world.z)`), with road-plane `+x` right and `+y` forward;
- approach, left quarter-circle arc and exit shape for the authored sweeper;
- repeatability, interpolation and end clamping;
- refusal of missing/changed bay or fixture data, non-join repeated stations,
  reordered stations and discontinuous join duplicates;
- provisional provenance labels for the target speed and private sampling seam.

## Limits

- Pure conversion validation only: no physics body, car control, rendering,
  audio, input, export, platform or release claim.
- One pinned local engine; no cross-version or cross-host determinism claim.
- The private `_sample_bay` call is a labelled provisional seam, not a stable
  production API.
- The arc is the builder's sampled polyline, not an independently re-derived
  analytic replacement. Boundary positions are checked within a documented
  millimetre-scale tolerance; stations remain much stricter.
- No physical sweeper, lap-time, pace, fixture-performance or M1.7 acceptance
  claim is made.
