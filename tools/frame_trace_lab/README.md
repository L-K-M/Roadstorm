# Frame trace lab

Bounded numerical preflight for the M1 frame-rate comparison in
`docs/BENCHMARKS.md`. It runs the committed one-car
`scenes/laboratory/drive_lab.tscn` through its normal
`DriveLab._physics_process()` -> `DriveLab.step_once()` integration path; it
does not reimplement motor, gearbox, adapter, collision or presentation math.

## Files

| File | Role |
| --- | --- |
| `frame_trace_entry.gd` | headless `SceneTree` entry; validates the environment, pins `Engine.physics_ticks_per_second` to 60, and starts the driver |
| `frame_trace_driver.gd` | builds the fixed traffic-free command schedule, instantiates the committed DriveLab scene, writes one result JSON |
| `compare_frame_traces.py` | standard-library comparator and input validator for the 30/60/120 result files |
| `run_frame_trace_lab.sh` | frozen-source runner, shared-lock serialization, negative-control execution and evidence capture |

## What is measured

One launch uses `--fixed-fps 30`, one `--fixed-fps 60`, and one `--fixed-fps
120`. Every launch pins the logical physics rate to 60 Hz. The command trace is
1200 committed ticks (20 logical seconds), zero steer and traffic-free:

1. ticks 1-420: full throttle
2. ticks 421-540: coast
3. ticks 541-1200: full brake, including the committed motor's reverse
   transition when its own rules engage reverse

The comparator requires all three full traces to be present, parse cleanly,
use the expected schema and be independently coherent: 1200 consumed commands,
1200 adapter steps, 1200 committed ticks, 1200 tick records, no dropped
records, consecutive ticks/callbacks, completion by `script complete`, no
failure, constant zero-steer heading, fixed full-schedule command values, and a
valid 100 m gate crossing. It compares exact tick counts, command sequences,
per-tick discrete state, endpoint discrete state, and event/count fields.
Continuous endpoint tolerances are the benchmark values:

- position: at most 0.10 m
- speed: at most 0.10 m/s
- heading: at most 1 degree
- 100 m gate time: at most one 60 Hz physics tick

`--fixed-fps` in a headless editor process is only the engine's nominal
process cadence. It does not create a window, does not present frames, and does
not measure real rendered or presented FPS. These results are numerical
same-host physics-preflight evidence only.

## Runner

Use the repository-pinned Godot and the coordinator's shared lock:

```sh
tools/frame_trace_lab/run_frame_trace_lab.sh \
  --work-root work/agents/coordinator/frame-harness-devin-20261128/preflight
```

The runner:

- exports a plain frozen `git archive HEAD` source tree (read-only Git use; no
  branch, worktree, index or publish operation);
- overlays the current `tools/frame_trace_lab` files because they are the
  bounded candidate under test;
- never runs Godot against the live checkout and never writes the live
  project's `.godot` cache;
- uses private `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and
  `XDG_DATA_HOME` directories inside the fresh run directory;
- serializes every Godot invocation on `work/agents/coordinator/godot-test.lock`
  with `lockf` and bounds it with an outer watchdog that can stop only the exact
  child PID started by this runner;
- keeps the frozen stage, result JSON files, logs and hashes in the fresh
  ignored run directory;
- runs full traces at nominal 30/60/120 plus the driver's `drop` and `short`
  60 Hz control variants.

`--timeout` is documented for interface compatibility with the other lab
runners; the important hard bound is `--outer-timeout`, which includes lock
waiting and the engine invocation. `--lock-wait` bounds how long one invocation
may wait for the shared lock. `--outer-timeout` must exceed `--lock-wait`.

## Negative controls

After the positive comparison, the runner verifies that
`compare_frame_traces.py` exits 1 for each of these discriminatory cases:

- missing input file;
- corrupt JSON input;
- the real `drop` trace relabeled as full: every third command is idle, so its
  command sequence and trajectory differ;
- the real `short` trace relabeled as full: 1199 rather than 1200 committed
  ticks;
- a deliberate 0.5 m forward displacement of the otherwise valid 60 Hz
  trajectory.

These controls are evidence that the comparator is not vacuously green. They do
not prove the production game is frame-rate independent.

## Result schema

The result schema identifier is `roadstorm.frame_trace.result.v1`. Important
sections are:

- `mode`: nominal fixed-FPS label and variant;
- `engine`: engine version, configured/observed physics rate and fixed-FPS
  argument;
- `timing`: wall time plus engine process/physics frame counters, reported for
  diagnostics rather than as presented-frame evidence;
- `schedule`: logical tick and command counts;
- `run`: completion/failure state, counts and laboratory telemetry;
- `endpoint`: final position, velocity, speed, heading and discrete state;
- `counts`: discrete gearbox/contact/wall/substep counts;
- `gate`: first committed tick at or beyond 100 m;
- `tick_trace`: per-tick command, adapter status, continuous motion summary and
  discrete state;
- `harness`: producer coherence checks, independently rechecked by the
  comparator.

## Limits

This is not whole-M1 acceptance. It uses one flat straight, one car, one fixed
longitudinal command schedule, no traffic, no steering/drift scenario, no
rendered window, no audio judgment, no cross-platform matrix, no chaotic race
trajectory, and no hardware display measurement. It does not ratify handling
coefficients, gearbox thresholds, renderer selection, performance, gameplay
feel or release readiness. Cross-platform physics evidence requires separate
invariant/tolerance checks; byte-identical physics is not claimed here.
