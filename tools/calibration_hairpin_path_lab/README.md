# Provisional M1.7 hairpin calibration-path laboratory

This directory contains a bounded, provisional conversion check for the M1.2
HandlingLab `hairpin` bay. It converts the live authored bay through
`HandlingLabBuilder._sample_bay` into a `CalibrationDriver.CalibrationPath`,
then validates ordered station identity, section/surface identity, exact
boundary-duplicate semantics, geometric turn and heading reversal, world-to-road
mapping, repeatability, provisional labels and negative-control refusals.

This is not a physical hairpin test. It does not drive a car, run the motor,
measure grip or drift, calibrate a racing line, produce fixture evidence, or
establish M1.7 acceptance. The constant 18 m/s target speed is an authored
preliminary laboratory value tied to the fixture's benchmark entry speed; it is
explicitly not measured or tuned.

## Authored input

The source of truth is the authored 30 m approach + 180-degree radius-30 m left
arc + 30 m exit, width 12 m, benchmark entry 18 m/s from
`fixtures/handling/hairpin.json` and `docs/BENCHMARKS.md` "Handling fixtures".
The authored bay places the centerline at world origin `(240, 0, 60)` with yaw 0.

| Quantity | Expected |
| --- | --- |
| Approach length | 30 m |
| Arc length `r*theta` | `30*pi` = 94.2477796 m |
| Exit length | 30 m |
| Total station length | 154.2477796 m |
| Boundary stations | 0, 30, 124.2477796, 154.2477796 m |
| Road width / surface | 12 m / `asphalt` |
| Builder raw samples | 158 |
| Join duplicates skipped | 2 (raw indices 31 and 127) |
| Unique path samples | 156 |
| Arc center (road plane) | `(210, -30)` |

The conversion never re-derives geometry. A different authored radius, angle,
direction, length, width, surface, origin or yaw fails the build instead of
falling back to these constants.

## Boundary-station semantics

`HandlingLabBuilder._sample_bay` intentionally emits the exact same centerline
cross-section at both sides of an ordinary section join so adjacent road ribbons
abut without a gap. For this 1 m sampling the raw stream has 158 samples; raw
indices 31 (approach/arc) and 127 (arc/exit) are exact position and station
duplicates.

`CalibrationPath` requires strictly increasing stations, so exactly one copy of
each boundary can survive. The conversion keeps the preceding section's copy and
drops the following duplicate. Consequently:

- the surviving approach-end sample at station 30 carries `hairpin.approach`;
- the dropped arc-start duplicate would carry `hairpin.arc`;
- the surviving arc-end sample at station 124.2477796 carries `hairpin.arc`;
- the dropped exit-start duplicate would carry `hairpin.exit`.

Per-sample section and surface identity for the 156 unique samples is preserved
in `summary.sample_section_ids` and `summary.sample_surface_ids`, aligned by
index with `path.samples`. A repeated station is accepted only when it is the
identical world position at the recorded end/start station of adjacent sections
and is marked `joined_prev` without `break_before`. Any other repeat, decrease,
reorder, discontinuity or broken run is refused.

Tag ownership uses the recorded section intervals exactly. A station strictly
inside one interval belongs to that section alone; no interval is expanded by a
tolerance for this check. The only multi-owner station is one exactly equal to a
shared boundary, where the two recognized duplicate-join side copies each carry
their own adjacent section id. An ordinary interior sample moved into the old
1e-4 m boundary band therefore cannot borrow the neighbouring section's tag.
The `SECTION_STATION_TOLERANCE` of 1e-4 m applies only to comparing recorded
section boundary stations and lengths against the authored expected values and
to matching adjacent section records at a join. Exact boundary ownership is a
property of the recorded intervals; this lab does not prove that an
independently re-authored stream cannot place a single sample exactly on a
shared boundary.

## Route-progress policy

The hairpin turns back alongside its approach: the exit leg runs parallel to the
approach leg at a separation of one diameter (60 m) in the opposite direction.
A nearest-point query alone cannot establish ordered route progress after an
off-road position, shortcut or reset, so it must never become authoritative.

This lab therefore validates conversion only. It walks the builder's ordered
station stream and exposes `resolve_progress_by_nearest_point()` solely to refuse
that operation with a diagnostic. Physical driver integration with
caller-supplied ordered route progress is later M1.7 work.

## Prerequisites

- Pinned Godot editor at
  `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`
  printing `4.7.2.stable.official.ed1daf0bf`.
- POSIX shell, `git`, `tar`, `lockf`, `mktemp`, `sleep`, and the shared
  coordinator lock.
- A git checkout containing `src/`, `fixtures/handling/hairpin.json`,
  `project.godot` and this directory.

## Run

From the repository root, freezing the declared input SHA:

```sh
candidate_sha=$(git rev-parse HEAD)
sh tools/calibration_hairpin_path_lab/run_validation.sh \
  --source . \
  --sha "$candidate_sha" \
  --expect-sha "$candidate_sha" \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --lock work/agents/coordinator/godot-test.lock \
  --timeout 300 \
  --log <job-dir>/calibration_hairpin_validator.log
```

Options: `--source DIR` (git checkout to freeze; default repository root),
`--sha SHA` (default `HEAD` of `--source`), `--expect-sha SHA` (refuse a
mismatch), `--godot BIN`, `--lock FILE`, `--timeout SECONDS` (outer watchdog,
1-300), `--log FILE`, `--keep-scratch`.

The runner extracts `git archive <sha>` into a private staging directory,
overlays only `tools/calibration_hairpin_path_lab`, and stages private `HOME`,
`TMPDIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME`. It never
imports the live working tree and never writes the checkout's `.godot/` cache.
Every engine invocation is serialized on the coordinator lock, records the exact
PID of the one Godot child it starts, and stops only that child if the outer
bound strands it. Each engine call is bounded by `--timeout`; the deliberate
whole-run bound is at most 300 seconds.

Exit codes:

- `0`: validator passed (`"pass":true`, `CHECKS_FAILED=0`) and the deliberate
  failure probe exited nonzero with `"pass":false`;
- `1`: a validator check, output gate or probe expectation failed;
- `2`: unsafe arguments, a SHA mismatch, an unusable/mismatched engine, or a
  frozen-source extraction failure.

## Output contract

The validator prints one `CALIBRATION_HAIRPIN_PATH_LAB_CASE {...}` line per case,
then `CALIBRATION_HAIRPIN_PATH_LAB_SUMMARY {...}` and
`CHECKS_TOTAL=n CHECKS_FAILED=n`, and exits 0/1. On success it can write the full
summary JSON with `--summary-out=<path>`. The deliberate probe prints
`CALIBRATION_HAIRPIN_FAILURE_PROBE {...}` with `"pass":false` and exits 3.

## Coverage

- live authored bay and fixture identity/shape guards;
- exact raw sample count (158), unique sample count (156) and two genuine join
  duplicates at raw indices 31 and 127;
- distinct ordered section boundaries and their section/surface identity;
- exact boundary duplicate semantics, including which copy survives;
- refusal of duplicate `gate_id` and `run_id` entries in either array order,
  including identical duplicates and ids outside the four required gates, with
  a stable `duplicate_id:<id>` diagnostic;
- ordered tag ownership by exact recorded intervals, including refusal of an
  interior sample moved into the former 1e-4 m boundary band and retagged with
  the neighbouring section, while both genuine join side copies still pass;
- 30 m approach, 180-degree radius-30 m left arc, 30 m exit;
- geometric turn (+pi about the derived arc center) and 180-degree heading
  reversal between approach and exit travel directions;
- parallel legs separated by one diameter, with nearest-point lookup refused;
- committed `MotorBodyAdapter.world_vector_to_road` mapping
  (`Vector2(world.x, -world.z)`), cross-checked for every produced sample;
- repeatability, interpolation and end clamping;
- fail-closed numeric guards: every required authored bay, fixture,
  timing-gate, run initial-state and builder section scalar must be present,
  numeric and finite before any float conversion or tolerance comparison;
  missing, wrong-type, NaN and infinite values refuse the build (this covers
  all four timing-gate `arc_length_m` values, both run entry speeds and all
  section `start_s_m`/`end_s_m`/`length_m` fields);
- ordered tag ownership: every raw sample's section and surface tag is checked
  against the recorded section whose station interval contains it, with
  explicit allowance for the two legitimate side copies at each exact join;
- refusal of missing/changed bay or fixture data, corrupted timing gates,
  non-join repeated stations, reordered stations, discontinuous or mispaired
  joins, missing section records and corrupted produced paths;
- provisional provenance labels for the target speed and private sampling seam.

## Limits

- Pure conversion validation only: no physics body, car control, rendering,
  audio, input, export, platform or release claim.
- One pinned local engine; no cross-version or cross-host determinism claim.
- The private `_sample_bay` call is a labelled provisional seam, not a stable
  production API.
- The arc is the builder's sampled polyline, not an independently re-derived
  analytic replacement. Positional checks use a documented 1 cm tolerance;
  station, ordering and duplicate checks remain much stricter.
- No physical hairpin, lap-time, pace, fixture-performance or M1.7 acceptance
  claim is made. The 18 m/s profile is provisional and untuned.
- Ownership is exact at recorded interval boundaries. A station exactly equal
  to a shared boundary may be claimed by either adjacent section; the builder
  emits that station only as the duplicate-join pair, and this lab does not
  model a single non-duplicate sample placed exactly on a boundary.
