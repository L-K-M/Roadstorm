# M1.2 handling laboratory (static graybox)

Static test geometry for PLAN.md M1.2 and the handling fixtures in
`docs/BENCHMARKS.md` / `fixtures/handling/*.json`. This is a preliminary
graybox authoring slice: no car body, motor, surface modifiers, gameplay or
acceptance measurement is implemented or claimed.

## Files

| Path | Role |
| --- | --- |
| `scenes/laboratory/handling_lab.tscn` | standalone scene; attaches `src/laboratory/handling_lab.gd` |
| `src/laboratory/handling_lab.gd` | scene root; builds the lab on ready and stores the manifest |
| `src/laboratory/handling_lab_data.gd` | authored bays, segments, surfaces, envelope and clearance constants |
| `src/laboratory/handling_lab_builder.gd` | deterministic mesh/collider/marker builder |
| `tools/handling_lab/validate_handling_lab.gd` | headless `SceneTree` validation entry point |
| `tools/handling_lab/run_validation.sh` | pinned-engine wrapper that stages an isolated copy and bounds the run |
| `tools/handling_lab/check_runner_safety.sh` | non-destructive controls for staging refusal and containment behavior |

## Bays

The lab supplies independent bays for the 500 m asphalt straight, a 90-degree
120 m sweeper, a 180-degree 30 m hairpin, bank transitions through +12 and -12
degrees, a 12 percent climb with crest and descent with compression, a short
preliminary jump with gap and landing, a 500 m contact straight with frontal and
oblique walls, an 80 m gravel sector, dirt shoulders with sand strips, and a
designated 24 m by 24 m recovery pad. Every bay carries deterministic spawn and
recovery markers; the recovery bay additionally exposes a `RecoveryZoneAnchor`.

All surfaces are tagged with stable `surface_id` metadata on both visible
meshes and static collision bodies. Collision is static and uses the same
vertex arrays as the visible ribbons. Face indices are never used as identity.

## Run

From the repository root, with the pinned Godot 4.7.2 binary:

```sh
tools/handling_lab/run_validation.sh \
    --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
    --private-dir work/agents/<job-id>/private/handling_lab_fresh \
    --log work/agents/<job-id>/logs/validation-run.log \
    --timeout 120
```

The runner always stages a private copy (excluding `.git`, `.godot`, `work` and
Python caches), checks the engine version against `tools/toolchain/pin/engine.txt`,
redirects XDG/TMP caches into scratch, applies `timeout` to every Godot
invocation including the version probe, and fails on script errors, a missing
`CHECKS_TOTAL` line, or any reported failure.

An explicit `--private-dir` is create-only: it must not already exist as a file,
directory, symlink or dangling symlink. The runner refuses such paths before any
copy and leaves them untouched, then reserves a fresh directory with an atomic
`mkdir`. Staging never uses `--delete` and never removes a caller supplied path.
A destination inside `--project` is refused unless it lies under the repository's
ignored `work/` scratch root, which staging excludes anyway; the destination path
is excluded once more so recursion cannot occur. Omit `--private-dir` to use an
auto-created temporary copy that the runner cleans up.

Run the non-destructive runner controls (occupied directory, symlink, dangling
symlink, occupied file, unsafe containment, allowed `work/` containment, fresh
destination and default temporary copy):

```sh
./tools/handling_lab/check_runner_safety.sh
```

Direct invocation is also possible from an isolated project copy:

```sh
godot --headless --fixed-fps 60 --path <isolated-project> \
    --script res://tools/handling_lab/validate_handling_lab.gd
```

Exit code 0 means every structural check passed; exit 1 means at least one
failed. The validator prints one machine-readable `LAB_RESULT <json>` line.

## Scope limits

- Fixture-declared unknowns stay unknown. The jump takeoff grade, airborne gap
  and required landing run are preliminary authored values; wall height is
  preliminary until M2 barrier content.
- Road colliders are exact static concave trimesh matching the visible ribbons.
  Car integration must add the thickened swept collision and contact response
  described in `docs/TECHNICAL_DESIGN.md`.
- Esses and draft fixtures are outside this slice.
- Geometry parameters are preliminary graybox authoring values, not validated
  handling measurements.
