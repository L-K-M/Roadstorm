# Roadstorm M1 interim review: wall-end regions and frame-trace preflight

Reviewer: Claude Opus 5.5, first-party, independent. Date: 2026-11-28.
Candidate `49d60a12c96322cbc71af8a9a3a77f711c644634` (`../../candidate.sha`),
base `39ce8d0a3c6a2a6d1a97cac584688dd30aeadfa2`. The private build matches
`../source` (`diff -qr` gave no output). I read the eight-path
`../../scope.patch` and the prior Sol 39ce report. I did not consult the other
current reviewer, delegate, mutate Git, edit candidate files or publish
anything. Private evidence is under `../logs/`.

## Verdicts

- **Wall correction (M1.8 scope): pass**, within the measured scope stated below.
- **Frame preflight (interim M1 numerical): pass as a bounded preflight**, with
  one low-severity discrimination finding (F2) that should be fixed before this
  lab is cited as cadence evidence in M1 acceptance.
- **Overall scoped verdict: pass.**

This does not mark M1.7, M1.8 or M1 complete. It also does not cover the
controller, rendered or presented FPS, general geometry, rights or release.

## Ranked findings

### F1. Low: the measured normalized envelope is already exceeded, and X headroom is about 2 mm

`src/simulation/wall_impact_producer.gd:76-80` documents the deepest
sign-compatible wall-end disagreement as 0.0374 X / 0.0259 Z normalized, and
justifies `REGION_CORNER_BAND_NORMALIZED := 0.04` (line 83) by that envelope.
My targeted probe found a witness beyond the documented Z value:

- 1.3 m wall, 7 m/s, heading 0.29 rad, steer +1, throttle 1, tick 37.
  Local point (-0.866267, -0.5, 1.834007). Local normal (1, 0). Insets
  33.73 mm X / 65.99 mm Z, which is **0.0375 X / 0.0347 Z normalized**.
  Severity 0.091 m/s. The point rule says REAR. The producer published
  **LEFT**, matching the normal. The result is correct.

The capture held, but the remaining margins are 0.0025 in X (2.3 mm on the
0.9 m half width) and 0.0053 in Z (10 mm). Both of the deepest witnesses
(this one and the lab's `v8_h0.300_s1_t1`, 0.0374 X) are near-zero-severity
rear-quarter scrapes against a wall end, with a pure side normal. If a witness
exceeds 0.04 in X while its X distance is still larger than its Z distance, it
falls back to the point rule and publishes REAR or FRONT against a LEFT or
RIGHT normal. That is the same class of flip as the 39ce finding. I found no
such witness. The fix is documentation only: update the envelope comment to
include this measurement (or describe the envelope as a lower bound), and keep
the thin X margin visible for any future hull or tolerance retune.

Why the band is only needed on one axis per disagreement: for a FRONT normal,
the point rule disagrees only when the normalized Z distance exceeds the X
distance. If X distance is above 0.04, then Z distance is too, so both axes
fall outside the band. A FRONT-normal mislabel therefore needs the Z distance
above 0.04 (76 mm). A LEFT/RIGHT-normal mislabel needs the X distance above
0.04 (36 mm). The X axis is the binding margin.

### F2. Low: the comparator and the driver cannot detect a wrong or reused fixed-FPS process

`tools/frame_trace_lab/frame_trace_driver.gd:349,368` sets both
`mode.nominal_fixed_fps` and `engine.fixed_fps_argument` from the `FTP_FPS`
environment label. Neither value comes from `OS.get_cmdline_args()` or from
observed cadence. `compare_frame_traces.py:156` then checks that the two
labels agree, which is tautological. The comparator never reads
`timing.process_frames` or `physics_per_process_frame`, which are the only
signals that the cadence actually varied (602/1204/2408 here).

Reproduction (comparator only):

```sh
# relabel the real 60 Hz trace as 30 and 120 (mode + fixed_fps_argument)
python3 -B tools/frame_trace_lab/compare_frame_traces.py \
  ../logs/mislabel-30.json ../logs/ft-60.json ../logs/mislabel-120.json
# rc=0, COMPARISON PASS   (../logs/mislabel.log)
```

So three copies of one 60 Hz run pass, and so would three `--fixed-fps 60`
launches with different `FTP_FPS` labels. The runner launches matching pairs
(`run_frame_trace_lab.sh:331`), so the coordinator's run is not invalidated by
this. Suggested fix: record the parsed `--fixed-fps` from
`OS.get_cmdline_args()`. In the comparator, require
`physics_frames == process_frames * 60 / fps` within a small allowance for
settle and drain frames, and add a relabeled-copy negative control.

### F3. Informational: limits of the frame preflight that must stay stated

- Zero deltas are expected by construction. The simulation runs only in
  `_physics_process` at a pinned 60 Hz, and `--fixed-fps` changes only how
  many physics steps run per process frame. The lab therefore detects
  simulation logic that depends on process delta or frame count. It does not
  show rendered-FPS independence or drift behavior. The README says this.
- The trace's `command` field is copied from the driver's own `schedule[index]`
  (`frame_trace_driver.gd` trace loop). It is not the command DriveLab
  consumed, so the per-tick command check verifies the authored schedule.
  Consumption is covered only by the `commands_consumed` and
  `one_step_per_committed_tick` counters. The `drop` control still
  discriminates, because it changes the schedule and the trajectory.
- Per-tick continuous state is not compared, only endpoint and gate values.
  This matches the `docs/BENCHMARKS.md` "Numerical comparisons" endpoint
  wording.
- The runner overlays working-tree `tools/frame_trace_lab` files onto
  `git archive HEAD`. Evidence from a dirty tree mixes revisions. The
  documented hashes mitigate this.

No wall-scope finding reaches medium or above. I found no correctness issue in
the comparator's validation of schema, sections, finite numbers, the
1200-tick schedule, phases, strictly increasing callback indices, harness
checks, the duplicate- or missing-FPS rule, exact discrete sequences and
counts, or the tolerances (0.10 m, 0.10 m/s, 1 degree, 1 tick).
`angle_difference_deg` wraps correctly.

## Wall correction assessment

- **Rule** (`wall_impact_producer.gd:275-318`). Each axis's two-sided plane
  distance, normalized by that axis's half extent, must be at most 0.04 on
  both axes. Within that band, a dominant axis (component difference above
  0.001) whose sign points into the contacted quadrant names the face.
  Otherwise the normalized point rule applies, and a tie resolves to
  FRONT/REAR. Using absolute plane distances fixes Sol's one-sided-band
  finding. Normalization makes the absolute bands 36 mm X and 76 mm Z on the
  default 1.8 x 3.8 m hull. Widening only adds normal-authored overrides, and
  each one is sign-compatible with the selected response normal. A diagonal
  or opposite-sign normal still falls back to the point rule and can never
  publish the opposite face. Contacts at a face centre fall outside the band.
- **Witness authority.** Unchanged from 39ce and verified there by Sol: the
  same committed collision supplies the point, normal and frame.
- **Lab** (`wall_impact_lab_driver.gd`). The lab mirrors the constant and
  tests both sides of the boundary at 0.04 x 1.9 m. It treats a 2.4 x 3.0 m
  hull as covering the normalized scaling. It also replaces the old 40 mm
  synthetic guard with the legacy point (now FRONT, inside the band), and
  asserts the three 1.2 m physical regressions. These are Sol's tick-31
  material pulse (insets 19.26/39.57 mm, LEFT normal, severity 4.573 m/s),
  the 8 m/s tick-19 case and the `v8_h0.300` rear case.
- **My run**: `sh tools/wall_impact_lab/run_wall_impact_lab.sh --project "$PWD"
  --godot <pin> --lock <shared> --log ../logs/wall.log` returned rc=0 with
  **16 cases, 1,527 checks, 0 failed**. That includes
  `real_jolt_1_2_wall_end_envelope` (157 checks) and
  `real_jolt_narrow_wall_end` (229 checks). I did not repeat the old-producer
  negative or the deliberate-failure exit. The coordinator reports those (7
  failing checks, exit 3).
- **Targeted counterexample search**: 1,301 witnesses through the real adapter
  and the candidate producer, using a copy of the coordinator's probe
  parameterized by environment lists, in a private stage copy
  (`../logs/stage/reviewer_probe/`). The runs were:
  1. Low-speed rear-quarter scrape, the region of the deepest X witness:
     widths 0.9/1.2/1.5 m, 4-15 m/s, headings 0.2-0.4, steer +1, throttle 0/1.
  2. High speed: widths 0.6/1.2 m, 45/55 m/s, headings 0.6-1.3, steer -1/0/+1.
  3. A fine pass around the deepest witness: widths 1.1/1.3 m.

  Results: **0 refusals, 0 non-committed steps, 0 sign-compatible
  normal/published disagreements, 0 constant-face flips**. Logs:
  `../logs/probe-*.log`. Summary: `python3 -I ../logs/analyze.py`. The only
  new finding is F1's envelope extension.
- **Scope limit.** All of this is local macOS evidence on pinned Godot
  4.7.2/Jolt: flat static box walls, the default hull, the default
  orientation tolerance. Slopes, tilted, curved or mesh walls, other hulls
  and tolerances at wall ends, other platforms, sustained-contact policy,
  car-car contact and cosmetic damage are unverified.

## Frame preflight assessment

The coordinator's runner uses `git archive HEAD`, so I ran direct launches in
my build after a locked `--import`. Each launch used private
HOME/TMPDIR/XDG, the shared lock and bounded timeouts:

```sh
FTP_FPS=$f FTP_VARIANT=full FTP_RESULT=$L/ft-$f.json \
  timeout -k 5 240 lockf -k -w -t 150 $LOCK $PIN --headless --fixed-fps $f \
  --path $PWD --script res://tools/frame_trace_lab/frame_trace_entry.gd   # f=30,60,120
python3 -B tools/frame_trace_lab/compare_frame_traces.py ft-30.json ft-60.json ft-120.json
```

All four returned rc=0. Each run had 1,200 committed ticks and 1,204
physics frames. Process frames were **602 / 1,204 / 2,408**, so the nominal
cadence did vary. The gate was at tick 357 in all three runs. Endpoint speed
was 7.99916648864746 m/s in all three, and every position, speed, heading and
gate delta was 0. Discrete counts and sequences matched. Engine: Jolt, physics
60 pinned and observed, `max_physics_steps_per_frame` 8. This reproduces the
coordinator's result.

I did not rerun the runner's missing, corrupt, drop, short or 0.5 m controls.
The code inspection supports the coordinator's report that they fail. My own
relabel control is F2. Hosted CI for 49d is not verified here, and the
workflow does not run either lab.

## Limits of this review

The review took about 20 minutes. It used bounded targeted probes, not a
dense grid. Local checks are not CI results. Headless `--fixed-fps` is not
rendered or presented FPS.

Report: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator/m1-wall-frame-review-49d60a1/opus/report.md`
