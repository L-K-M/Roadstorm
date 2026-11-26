# M0.1 Jolt settings inventory

Self-contained, read-only inventory of the Godot Jolt 3D physics settings that
the game project runs on, for the M0.1 evidence record
(`docs/evidence/jolt-settings.md`).

Why it exists: Opus review finding R3 (a residual of finding 5) in
`review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md`
records that the game project pins `physics/3d/physics_engine="Jolt Physics"`
but leaves Jolt's own `physics/jolt_physics_3d/*` settings unrecorded. This
tool records them: the engine build, the host, the effective value of every
Jolt setting, and which of them the game project explicitly overrides.

**It pins nothing.** It only reads settings. Whether any Jolt setting should be
pinned is a separate, evidence-driven decision; this tool is the measurement
that decision would rest on.

## Files

| Path | Role |
| --- | --- |
| `project.godot` | throwaway project template that sets **no** physics settings, so the Jolt settings read back as engine defaults |
| `src/jolt_inventory.gd` | headless entry point (`SceneTree` script); reads `ProjectSettings`, prints a report, always quits |
| `run_inventory.sh` | supported entry point: builds two isolated temporary projects, runs the engine under a 30 s timeout in each, compares them, writes the evidence |
| `evidence/<date>-<host>/` | recorded runs: raw logs, JSON reports, the override diff and the classification |

## Requirements

- Godot **4.7.2 Standard** editor or runtime on `PATH` (M0.1 pinned version).
  The wrapper refuses to run against any other build, because the recorded
  values are build-specific.
- A `timeout` utility (`timeout` or `gtimeout`). Without one the wrapper
  exits 2 rather than run an unbounded engine command.
- Python 3 (standard library) only to parse-check the JSON reports; the
  wrapper notes and continues if it is absent.

No packages are installed and no network service is used.

## Run

From the repository root:

```sh
# Inventory the game project and write the evidence under evidence/<date>-<host>
tools/jolt_inventory/run_inventory.sh

# Inventory another checkout, write the evidence elsewhere
tools/jolt_inventory/run_inventory.sh --project <dir> --out-dir <dir>

# Use a specific engine binary
GODOT_BIN=/path/to/godot tools/jolt_inventory/run_inventory.sh
```

Exit codes: 0 = inventory complete and consistent, 1 = an engine run failed,
the two runs disagreed, or the engine is not the pinned build, 2 = the wrapper
could not run.

## How it separates overrides from defaults

`run_inventory.sh` builds two throwaway Godot projects in a temporary
directory and runs the same script in each:

1. **engine defaults** - this tool's `project.godot`, which contains no
   physics settings;
2. **main project** - a copy of the game project's own `project.godot`.

The wrapper then compares the two runs setting by setting. A setting whose
effective value differs is an explicit game-project override; one that does
not differ is an engine default (which is not the same as "not written down":
an explicit setting that happens to equal the default, such as
`common/physics_ticks_per_second=60`, is reported by the text scan as present
in `project.godot` but identical to the default).

The engine is never pointed at the game project, so the inventory cannot write
the game project's `.godot/` cache or any other file there. The temporary
projects are deleted when the wrapper exits.

## What the script records

Stable `key value` lines plus one `JOLT_INVENTORY_JSON` line (schema
`roadstorm.jolt_inventory.v1`):

- `engine_version`, `engine_version_info`, `engine_commit`;
- `os`, `processor`, `model`, `display_driver` (host identification);
- `context_setting` lines for the physics settings that select and pace the
  backend: `physics/3d/physics_engine`, `physics/common/physics_ticks_per_second`,
  `physics/common/physics_interpolation`, `physics/3d/default_gravity`;
- one `setting` line per `physics/jolt_physics_3d/*` entry: name, type,
  effective value and the editor's hint string (the documented range).

Float values are printed with full float32 round-trip precision
(`0.01999999955297`, not `0.02`), so the record is not silently rounded.

## Limitations (do not overread)

- **Read-only.** The tool reads `ProjectSettings`; it never writes a setting,
  instantiates a physics world, loads a scene, or observes simulation. It
  says what the engine is configured to do, not what a running world does.
- **Build- and host-specific.** The values are the defaults of the pinned
  4.7.2 official build on the recorded host. Another build, platform or
  backend selection is a different record; re-run the tool there.
- **Headless** dummy display and audio drivers: no rendering, input, audio or
  windowing claim.
- **Backend identity is still inferred, not observed.** As in
  `tools/tick_probe`, GDScript cannot name the instantiated 3D physics
  backend. The inventory records the `physics/3d/physics_engine` setting
  value; the tick probe's contrast run remains the evidence that the setting
  really selects Jolt.
- **No pinning decision is made here.** In particular the job-system limits
  (`max_bodies`, `max_body_pairs`, `max_contact_constraints`,
  `temporary_memory_buffer_size`) are recorded as defaults, not validated
  against any load the game will actually produce.
- The intermittent Jolt job-system warning (R7) is recorded in the evidence
  document, not diagnosed and not fixed by this tool.

## Provenance

Authored by a StepFun 5 Preview agent running through pi (provider
`stepfun`) for Roadstorm Racer! job `52ab36a7-ac1b-4aa4-9994-3f6310a49d45`
on 26 November 2026, against input revision
`bd94d17686924e38483ba10b0da05c4954d0ede6`. Original code under the
Unlicense. No third-party assets or network services.
