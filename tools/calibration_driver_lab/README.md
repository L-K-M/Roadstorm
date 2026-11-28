# M1.7 CalibrationDriver CONTROL laboratory

Pinned-Godot checks for the pure `src/calibration/calibration_driver.gd`
CONTROL component. The driver consumes a committed `CarState`, an authored
open 2D road-plane line profile and externally validated route progress, and
returns one normalized `DriverCommand` plus bounded telemetry, or a
path/state/tuning/progress-specific refusal with no command. It never runs the
motor, mutates its inputs, touches physics/body state, uses RNG, plans
tactically, scales difficulty or adds deliberate driver noise.

This lab is not a driving test. It proves the follower contract and control
sign conventions only.

## Prerequisites

- Pinned Godot editor at
  `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
  printing `4.7.2.stable.official.ed1daf0bf`.
- POSIX shell, `lockf`, `mktemp`, `sleep`, and the shared coordinator lock.
- Run from the repository root of an isolated checkout copy. The runner stages
  its own private project copy plus private Godot cache/config/data/home
  directories and never writes the live checkout's `.godot/` cache.

## Run

```sh
timeout 600 lockf -k -w -t 600 work/agents/coordinator/godot-test.lock \
  sh tools/calibration_driver_lab/run_calibration_driver_lab.sh \
  --timeout 120 --outer-timeout 300 \
  --log <this-job-dir>/calibration_driver_lab.log
```

Options: `--project DIR`, `--godot BIN`, `--lock FILE`, `--timeout SECONDS`
(inner per-engine watchdog, default 120), `--outer-timeout SECONDS` (default
600), `--log FILE`, `--keep-scratch`.

Exit codes:

- `0`: validator passed (`"pass":true`, `CHECKS_FAILED=0`) and the deliberate
  failure probe exited nonzero with `"pass":false`;
- `1`: a validator check, output gate or probe expectation failed;
- `2`: unsafe arguments or an unusable/mismatched engine.

Every engine invocation records the exact PID of its one Godot child and stops
only that child if it strands after a parse error or the outer bound. The
deliberate-failure probe runs only after the validator has passed; a failed
validator skips it so no additional engine child is launched.

The validator prints one `CALIBRATION_DRIVER_LAB_CASE {...}` line per case,
then `CALIBRATION_DRIVER_LAB_SUMMARY {...}`, `CHECKS_TOTAL=n CHECKS_FAILED=n`,
and exits 0/1. The probe prints `CALIBRATION_DRIVER_FAILURE_PROBE {...}` with
`"pass":false` and exits 3.

## Cases

| Case | Coverage |
| --- | --- |
| `profile_validation_and_interpolation` | valid 500 m straight profile; length/station/segment/interpolation checks; explicit low/high clamp; empty, single-sample, duplicate, decreasing, NaN/Inf/negative station, NaN/Inf position, NaN/Inf/negative speed, mismatched arrays and malformed types refused with specific diagnostics |
| `steering_sign_and_matched_straight` | on-line aligned car steers zero and coasts at target speed; target right gives positive steer, target left gives negative steer, each matching the declared bearing law exactly |
| `speed_control_and_exclusivity` | under/over target speed, inside/outside deadband, full and partial throttle/brake, throttle/brake exclusivity, no handbrake, no reset |
| `lookahead_interpolation_and_end_clamping` | linear interpolation at a fractional station; lookahead addition; speed-scaled lookahead cap; target clamping at the final sample; explicit low/high progress clamp flags; exact-end progress |
| `invalid_inputs_return_refusals` | null/wrong-type/nonfinite/airborne state, null/wrong/invalid path, null/wrong/out-of-bounds tuning and NaN/Inf/non-numeric progress all refuse with `command == null` and a specific label/detail |
| `determinism_nonmutation_and_output_contract` | repeated calls produce identical commands and telemetry; committed state, profile samples and tuning fields are unchanged; caller mutation of a returned command cannot affect later calls; output stays normalized and exclusive across a bounded input sweep |
| `example_profiles_authored_smoke` | authored 500 m straight and 90-degree 120 m radius sweeper profiles validate; right-hand sweeper steers right mid-corner and its mirror steers left; start/midpoint behaviour is accepted |

## Example profiles and speeds are test-only

Both example profiles carry a version ending in `_test_only`:

- Straight: 500 m of 30 m/s samples, using the BENCHMARKS handling fixture's
  30 m/s rolling-start entry as an explicit test-only value.
- Sweeper: 50 m approach, a 90-degree constant-radius 120 m arc (approximately
  188.5 m), 50 m tangent exit, all at the BENCHMARKS sweeper fixture's 30 m/s
  entry as an explicit test-only value.

These speeds prove the interpolation and steering paths. They are **not**
measured cornering limits, not tuned calibration references, and not evidence
that the car can hold them. No measured or tuned claim is made here.

## Missing gates this lab does not close

- **Ordinary-motor gate:** commands are never fed through `ArcadeMotor` or a
  gearbox. No acceleration, braking, yaw/grip envelope, drift/assist or
  surface response is exercised, so the example target speeds remain
  unvalidated.
- **Fixture/evidence gate:** BENCHMARKS handling fixtures (straight, sweeper,
  hairpin, esses, gravel, grounding, contact, draft) are not run. There is no
  immutable fixture source/hash set, no paired-run procedure, and no elapsed
  time comparison against the 5% sweeper target.
- **Line-calibration gate:** the speed profile is an authored test input, not a
  conservative profile calibrated against measured envelopes. Real line and
  speed-hint calibration belongs with the M2 course/geometry pipeline and the
  M1.7 comparison record; this driver deliberately adds no braking-distance or
  corner-speed model.
- **Lap-evidence gate:** there is no course progress/geometry pipeline, gate
  set, sector timing, reference-run harness or five-run lap record. No lap
  time, pace ratio, medal threshold or reference-record claim is produced.
- **Progress-authority gate:** the lab supplies synthetic stations directly. It
  does not demonstrate ordered swept-gate progress validation, nearest-point
  discrimination or recovery behavior.

## Limits

- Pure in-memory CONTROL math only: no scene, body, physics query, clock,
  rendering, audio, input routing, traffic, networking or race rules.
- One pinned local engine; no cross-version, exported-template, platform,
  controller, visual or release claim.
- Determinism here means identical inputs give bit-identical outputs in this
  lab. It is not a cross-host physics parity claim.
