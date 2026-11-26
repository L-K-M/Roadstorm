# Jolt 3D physics settings — M0.1 evidence

2026-11-26. Job `52ab36a7-ac1b-4aa4-9994-3f6310a49d45`, StepFun 5 Preview through
pi (provider `stepfun`), against input revision
`bd94d17686924e38483ba10b0da05c4954d0ede6`. Tool and raw runs:
`tools/jolt_inventory/**`, evidence directory
`tools/jolt_inventory/evidence/2026-11-26-apple-m4-max/`.

This record answers review finding R3 (the residual of finding 5) in
`review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md`:
the game project pins the Jolt *backend* but leaves Jolt's own settings
unrecorded. It also records the intermittent job-system warning reported there
as R7.

## Scope and ownership

This job owned only `docs/evidence/jolt-settings.md` and `tools/jolt_inventory/**`.
It changed no game file, pinned no handling setting, ran no subagent, mutated no
Git state and read no secret.

**Ownership overlap to resolve before merging.** `docs/STATUS.md` also assigns
`docs/evidence/jolt-settings.md` to job `a35656d6-09c1-4698-a699-ad211125217d`
(which owns `tools/smoke/**` and this path for the R3 smoke assertion and its
fault injection). Both jobs write this file. The sections below are the bounded
settings inventory and the R7 warning record produced here; the main-project
Jolt assertion in the smoke wrapper and its fault injection belong to that job
and are not claimed here.

## Engine build and host

| Item | Value |
| --- | --- |
| Engine version | `4.7.2.stable.official.ed1daf0bf` (Godot 4.7.2, status `stable`, build `official`) |
| Engine commit | `ed1daf0bf001b61586d9930840f2f1394092c079` |
| Binary | `/opt/homebrew/bin/godot` (M0.1 pinned build; the wrapper refuses any other `--version` string) |
| OS | macOS 27.0.1 (26A434), arm64 |
| Processor | Apple M4 Max (Mac16,9), 14 logical processors |
| Display/audio | headless dummy drivers |
| Jolt settings registered by this build | 32 |

## Method

`tools/jolt_inventory/run_inventory.sh` built **two throwaway Godot projects in
a temporary directory** and ran `src/jolt_inventory.gd` (a `SceneTree` script)
headless in each, every engine command bounded by `timeout 30`:

1. **engine defaults** — this tool's own `project.godot`, which sets no physics
   settings at all;
2. **main project** — a copy of the game project's `project.godot`, so the
   settings read back exactly as the game project sees them.

Comparing the two runs separates explicit overrides from engine defaults. The
engine was never pointed at the game project, so the game project's `.godot/`
cache and files were not touched; the temporary projects were deleted when the
wrapper exited. The script only reads `ProjectSettings` — it writes no setting,
loads no scene and instantiates no physics world — and it always exits through
`quit()`, from `_initialize()` on the normal path and after one frame from
`_process()` if that path were ever bypassed.

Both runs exited 0, printed 32 `physics/jolt_physics_3d/*` settings and no
`SCRIPT ERROR` / `ERROR:` lines. Raw logs, JSON reports, the diff and the
classification are in `tools/jolt_inventory/evidence/2026-11-26-apple-m4-max/`.

## Effective Jolt settings (all 32)

Full path = `physics/` + the first column. Values are printed with float32
round-trip precision (`0.01999999955297` is the stored float32 value of 0.02),
so they are not silently rounded.

| Setting (path continues after `physics/`) | Type | Effective value | Editor hint (range/step/suffix) | Source in the game project |
| --- | --- | --- | --- | --- |
| `jolt_physics_3d/collisions/active_edge_threshold` | float | `0.87266463041306` | `0,90,0.01,radians_as_degrees` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/collisions/collision_margin_fraction` | float | `0.07999999821186` | `0,1,0.00001` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/joints/world_node` | int | `0` | `Node A,Node B` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/limits/max_angular_velocity` | float | `47.1238899230957` | `0,2700,0.01,or_greater,radians_as_degrees,suffix:°/s` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/limits/max_bodies` | int | `10240` | `1,10240,or_greater` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/limits/max_body_pairs` | int | `65536` | `8,65536,or_greater` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/limits/max_contact_constraints` | int | `20480` | `8,20480,or_greater` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/limits/max_linear_velocity` | float | `500.0` | `0,500,0.01,or_greater,suffix:m/s` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/limits/temporary_memory_buffer_size` | int | `32` | `1,32,or_greater,suffix:MiB` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/limits/world_boundary_shape_size` | float | `2000.0` | `2,2000,0.1,or_greater,suffix:m` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/motion_queries/recovery_amount` | float | `0.40000000596046` | `0,1,0.01` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/motion_queries/recovery_iterations` | int | `4` | `1,8,or_greater` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/motion_queries/use_enhanced_internal_edge_removal` | bool | `true` | `-` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/queries/enable_ray_cast_face_index` | bool | `false` | `-` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/queries/use_enhanced_internal_edge_removal` | bool | `false` | `-` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/allow_sleep` | bool | `true` | `-` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/baumgarte_stabilization_factor` | float | `0.20000000298023` | `0,1,0.01` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/body_pair_contact_cache_angle_threshold` | float | `0.03490658476949` | `0,180,0.01,radians_as_degrees` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/body_pair_contact_cache_distance_threshold` | float | `0.0010000000475` | `0,0.01,0.00001,or_greater,suffix:m` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/body_pair_contact_cache_enabled` | bool | `true` | `-` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/bounce_velocity_threshold` | float | `1.0` | `0,1,0.001,or_greater,suffix:m/s` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/continuous_cd_max_penetration` | float | `0.25` | `0,1,0.01` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/continuous_cd_movement_threshold` | float | `0.75` | `0,1,0.01` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/generate_all_kinematic_contacts` | bool | `false` | `-` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/penetration_slop` | float | `0.01999999955297` | `0,1,0.00001,or_greater,suffix:m` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/position_steps` | int | `2` | `1,16,or_greater` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/sleep_time_threshold` | float | `0.5` | `0,5,0.01,or_greater,suffix:s` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/sleep_velocity_threshold` | float | `0.02999999932945` | `0,1,0.001,or_greater,suffix:m/s` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/soft_body_point_radius` | float | `0.00999999977648` | `0,1,0.001,or_greater,suffix:m` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/speculative_contact_distance` | float | `0.01999999955297` | `0,1,0.00001,or_greater,suffix:m` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/use_enhanced_internal_edge_removal` | bool | `true` | `-` | engine default (not set in `project.godot`) |
| `jolt_physics_3d/simulation/velocity_steps` | int | `10` | `2,16,or_greater` | engine default (not set in `project.godot`) |

## Explicit game-project overrides versus engine defaults

The game project's `project.godot` sets exactly three physics entries:

| Key in `project.godot` | Value | Engine default | Status |
| --- | --- | --- | --- |
| `3d/physics_engine` | `"Jolt Physics"` | `DEFAULT` | **explicit override** |
| `common/physics_interpolation` | `true` | `false` | **explicit override** |
| `common/physics_ticks_per_second` | `60` | `60` | explicit, identical to the default |

`physics/3d/default_gravity` is not set and reads back as the engine default
`9.8`.

**None of the 32 `physics/jolt_physics_3d/*` settings is set by the game
project.** Every one of them therefore runs at the engine default of the pinned
build, and the two inventory runs agree on all 32 values (the recorded diff's
only changed lines are the two physics overrides above). On this build `DEFAULT` for
`physics/3d/physics_engine` is the value an unset project would get;
`tools/tick_probe/evidence/2026-11-26-apple-m4-max-jolt/` contains that probe's
contrast run showing `DEFAULT` behaved as GodotPhysics3D on this build — that
is the tick probe's measurement, not this job's.

**Nothing was pinned here.** This job records values only; it deliberately does
not add Jolt settings to the game project, and no handling setting is claimed
validated. The job-system limits in particular (`max_bodies` 10240,
`max_body_pairs` 65536, `max_contact_constraints` 20480,
`temporary_memory_buffer_size` 32 MiB) are recorded as defaults, not checked
against any load the game will produce.

## The intermittent Jolt job-system warning (R7)

Reported in
`review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md`
(finding R7, Opus 5.5 via Venice, job `929c4082-…`, checks run about
22:16–22:20 UTC on 2026-11-26), verbatim:

> **R7. Intermittent Jolt warning.** One of three structural tick-probe runs
> (`--fixed-fps 60`) printed the engine warning `Jolt Physics job system
> exceeded the maximum number of jobs … Please report this`. The checks still
> passed. This should be recorded and tracked; it is not hidden by the smoke
> wrapper, which ignores `WARNING:` lines.

What was done here, and what was not:

- **Reproduction attempts.** On an isolated copy of `tools/tick_probe` (never
  the game project), 15 structural runs on the same host and build: 12 with
  `--fixed-fps 60` (two batches of six) and 3 with default headless pacing.
  Every run passed 58/58 checks with exit 0. The warning appeared **0 times**,
  and no `WARNING:` line appeared in any run. The two inventory runs above also
  printed no warnings (`warnings.txt` in the evidence directory is empty). The
  per-run record is `r7-repro-attempts.txt` in that directory.
- **Status: not reproduced here, and not diagnosed.** No cause is identified and
  none is claimed. This job's runs do not bound when the warning can appear, do
  not estimate its frequency, and do not establish that it is gone. No setting
  was changed in response to it, and nothing in `tools/jolt_inventory/**` gates
  on it: if the warning appears during an inventory run it is recorded in
  `warnings.txt` and reported in the wrapper summary as a note, not a failure.
- **Open.** The warning remains an open item for M0 acceptance, to be tracked
  with the review that reported it. The command that produced it is the tick
  probe's structural run, reproduced below.

## Reproduce

From the repository root:

```sh
# Settings inventory (the two bounded engine runs, the comparison and the
# evidence files)
tools/jolt_inventory/run_inventory.sh

# The engine runs the wrapper performs, written out explicitly. Each is
# bounded by 30 s and each script always calls quit().
mktemp -d /tmp/roadstorm-jolt-inventory.XXXXXX   # the wrapper's isolation step
# run 1: tools/jolt_inventory/project.godot  (engine defaults)
timeout 30 godot --headless --path <tmp>/defaults \
    --script res://src/jolt_inventory.gd -- label=engine-defaults
# run 2: a copy of the game project's project.godot
timeout 30 godot --headless --path <tmp>/main \
    --script res://src/jolt_inventory.gd -- label=main-project

# The tick-probe command under which the review observed the R7 warning,
# run here on an isolated copy of tools/tick_probe
timeout 30 godot --headless --fixed-fps 60 --path <copy> \
    --script res://src/tick_probe.gd -- mode=structural
```

Re-running `run_inventory.sh` overwrites the evidence directory for the current
date and host; keep earlier directories if the record must be preserved.

## Limitations (do not overread)

- **Read-only measurement.** The tool reports what the engine is configured to
  do. It does not run a physics world, so it says nothing about simulation
  behaviour, contact resolution or performance.
- **Build- and host-specific.** These are the defaults of the pinned 4.7.2
  official build on the recorded host. Another build, platform or backend
  selection is a different record and needs its own run.
- **Headless** dummy display and audio drivers: no rendering, input, audio or
  windowing claim.
- **Backend identity remains inferred, not observed**, exactly as in
  `tools/tick_probe`: GDScript cannot name the instantiated 3D physics backend.
  This record covers the setting values and the backend selection setting, not
  a directly observed runtime identity.
- **No pinning decision.** No Jolt setting is recommended or set by this job.
- **The R7 warning is unresolved.** Not reproduced in 15 runs here; no
  diagnosis, frequency estimate or fix is claimed.
- The settings list itself is build-specific: this build registers 32
  `physics/jolt_physics_3d/*` entries, and the inventory reports the count it
  read so a future build that adds or removes settings is visible.

## Provenance

Original tool code authored by a StepFun 5 Preview agent through pi (provider
`stepfun`) for Roadstorm Racer! job `52ab36a7-ac1b-4aa4-9994-3f6310a49d45` on
26 November 2026, under the Unlicense. No third-party assets, installs or
network services were used.
