# Provisional M1.7 hairpin physical first-tick laboratory

This directory contains a bounded, provisional physical diagnostic for the M1.2
HandlingLab `hairpin` bay. It instantiates the committed
`scenes/laboratory/drive_lab.tscn`, installs the car at the authored hairpin
start using the same public-field bridge as the sweeper lab, writes the authored
18 m/s entry speed, issues one `CalibrationDriver` command at caller-ordered
station 0.0, and executes exactly one real committed 60 Hz physical tick. It
then checks pose reconciliation, ground contact, and the committed state.

This is only a first-tick diagnostic. It is not a turn, handling, lap-time,
grip, drift, pace, fixture-performance, or M1.7 acceptance test.

## Authored input

The physical case uses the committed authored hairpin bay and the provisional
18 m/s benchmark entry speed from `fixtures/handling/hairpin.json` and
`docs/BENCHMARKS.md` "Handling fixtures". The authored bay places the centerline
at world origin `(240, 0, 60)` with yaw 0. The conversion-only hairpin path
laboratory in `tools/calibration_hairpin_path_lab/` remains the owner of path
geometry and ordering semantics.

## What the probe checks

- the committed hairpin path builds and reports bay id `hairpin`;
- the ordinary committed DriveLab scene configures, settles, and makes no
  adapter calls before the case starts;
- the three committed hairpin collision and surface runs exist under
  `Bay_hairpin`;
- the authored spawn marker, installed pose, hull support height, and initial
  18 m/s forward speed are correct;
- the ground under the installed hull is the committed hairpin collider;
- one `CalibrationDriver` command is accepted at caller-ordered station 0.0;
- exactly one adapter step and one committed tick occur;
- the final state, body pose, telemetry, and post-tick ground remain valid.

## Deliberate failure probe

`failure_probe.gd` is a harness control. It builds the committed hairpin path,
then records one deliberate failing check so a green runner cannot hide a red
check. It is expected to exit nonzero with `"pass":false`.

## Prerequisites

- Pinned Godot editor at
  `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
  printing `4.7.2.stable.official.ed1daf0bf`.
- POSIX shell, `git`, `tar`, `lockf`, `mktemp`, `timeout`, and the shared
  coordinator lock.
- A git checkout containing `src/`, `scenes/`, `fixtures/`, `project.godot`,
  and this directory.

## Run

From the repository root, freezing the declared input SHA:

```sh
candidate_sha=$(git rev-parse HEAD)
sh tools/calibration_hairpin_physical_lab/run_validation.sh \
  --source . \
  --sha "$candidate_sha" \
  --expect-sha "$candidate_sha" \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --lock work/agents/coordinator/godot-test.lock \
  --timeout 120 \
  --log <job-dir>/calibration_hairpin_physical_lab.log
```

Options: `--source DIR` (git checkout to freeze; default repository root),
`--sha SHA` (default `HEAD` of `--source`), `--expect-sha SHA` (refuse a
mismatch), `--godot BIN`, `--lock FILE`, `--timeout SECONDS` (per-call outer
bound, 1-120), `--log FILE`, `--keep-scratch`.

The runner extracts `git archive <sha>` into a private staging directory under
ignored `work/agents`, overlays only
`tools/calibration_hairpin_physical_lab`, and stages private `HOME`, `TMPDIR`,
`XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME`. It never imports the
live working tree and never writes the checkout's `.godot/` cache. Every engine
invocation is serialized on the coordinator lock and bounded by
`timeout -k 5`. The deliberate whole-run bound is at most 6 minutes.

Exit codes:

- `0`: probe scene reported `"pass":true` with `CHECKS_FAILED=0`, its exit
  code was 0, and the deliberate failure probe exited nonzero with
  `"pass":false`;
- `1`: a probe check, output gate, or probe expectation failed;
- `2`: unsafe arguments, a SHA mismatch, an unusable or mismatched engine, or
  a frozen-source extraction failure.

## Output contract

The probe prints one `M17_HAIRPIN_FIRST_TICK {...}` line and
`CHECKS_TOTAL=n CHECKS_FAILED=n`, then exits 0 when all checks pass. The
deliberate probe prints `CALIBRATION_HAIRPIN_PHYSICAL_FAILURE_PROBE {...}` with
`"pass":false` and exits 3. The runner gates `ERROR`, `SCRIPT ERROR`, `FATAL`,
`USER ERROR`, `Failed to load script`, and `Parse Error` lines in every log,
including successful runs.

## Limits

- One real committed tick only. No turn, handling, grip, drift, lap-time,
  pace, fixture-performance, or M1.7 acceptance claim.
- One pinned local engine; no cross-version or cross-host determinism claim.
- The private `_sample_bay` / spawn-field bridge is a labelled provisional
  seam, not a stable production API.
- The 18 m/s profile is provisional and untuned.
- No source or game files are modified by this lab.
