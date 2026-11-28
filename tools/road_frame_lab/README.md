# Open-road transported-frame laboratory

This directory is the standalone validation laboratory for the first M2
open-course transported-frame slice. It checks
`RoadTransportFrame.build_open_frame_table()` in
`src/course/road_transport_frame.gd` against four original lab fixtures and
meaningful in-memory refusals. It consumes an already validated
`roadstorm.road_arc_table.v1` table from `RoadArcSampler` and produces
right-handed transported frames. It does not bake geometry, close a loop,
validate course quality, or certify drivability.

This is provisional M2 frame-transport work. It does not implement mesh,
collision, shoulders, barriers, gates, grid, sectors, AI hints, minimap,
closed-loop residual-roll closure, course authoring, drivability or
course-quality gates, and it does not claim M2.1 or milestone acceptance.

## Files

| File | Role |
| --- | --- |
| `fixtures/road_frame_open_straight.json` | original two-knot level straight, zero bank |
| `fixtures/road_frame_open_banked_bend.json` | original two-knot climb with negative-to-positive authored bank |
| `fixtures/road_frame_open_rapid_grade.json` | original two-knot near-vertical rapid grade |
| `fixtures/road_frame_closed_loop.json` | original closed fixture used only to prove explicit refusal |
| `road_frame_checks.gd` | positive, transport, bank-sign, metadata-preservation, determinism, copy-safety and refusal checks |
| `validate_road_frame_lab.gd` | headless `SceneTree` validator entry point |
| `failure_probe.gd` | deliberate failing-check control; exits 3 when detection works |
| `run_validation.sh` | frozen-source, private-cache, shared-lock runner |

## Source dependencies

The frame builder consumes the public `RoadArcSampler.Table` shape
(`src/course/road_arc_sampler.gd`) and its ordered samples. It requires an
already built open table; it never parses JSON, rebuilds or mutates the arc
table, or reads the authored source. `build_open_frame_table()` refuses a
non-table object, a closed table, a header or sample that violates the
`roadstorm.road_arc_table.v1` contract, and any derived nonfinite or
inconsistent state.

`src/course/road_source.gd` supplies the authored document parsed by the
sampler. The frame layer treats section and surface metadata as opaque strings
and preserves them unchanged per station.

## Frame API

`RoadTransportFrame` is a `RefCounted` utility class.

```gdscript
static func build_open_frame_table(p_table: Variant) -> Dictionary
static func build_frame_table(p_table: Variant) -> Dictionary   # compatible alias
```

On success:

```gdscript
{"ok": true, "code": 0, "code_name": "none", "error": "", "diagnostic": {}, "frame_table": FrameTable}
```

On failure, a structured refusal with no partial table:

```gdscript
{"ok": false, "code": <Refusal>, "code_name": "<name>", "error": "...",
 "diagnostic": {...}, "frame_table": null}
```

`RoadTransportFrame.refusal_name(code)` maps a code to its stable name.

`FrameTable` exposes read-only `schema` (`roadstorm.road_frame_table.v1`),
`source_table_schema`, `course_id`, `revision`, `closed` (always `false` for a
returned open table), `sample_spacing_m`, `total_length_m`, `frame_count`,
`sample_count`, `frames`, `source_summary`, the five policy strings, indexed
`frame(i)`, `summary()` and `to_dictionary()`. Container accessors return deep
mutable copies, so altering them cannot rewrite the stored result. GDScript
cannot fully hide a private member from `Object.set`; wholesale replacement
remains the documented residual mutation path.

Each frame records:

- `index`, `s`, `position`;
- `forward`, `right`, `up` (unit, orthogonal, right-handed Godot `Vector3`s);
- `basis` (`Basis(right, up, -forward)`);
- `width_m`, `bank_deg`, `grade_dy_ds`;
- `span_index`, `span_t`;
- `section_id`, `surface_id`, `sample_role`.

## Orientation, bank and transport policy

Positions and tangents use Godot world units with +Y up and world forward -Z.
Each frame is right-handed in the Godot `Basis` sense: local +X is road right,
local +Y is road up, local -Z is road forward, so `right.cross(forward) == up`
and `forward.cross(up) == right`.

Positive `bank_deg` is a positive right-hand rotation about the forward
tangent. Because `forward.cross(up) == right`, positive bank tilts up toward
road right; for canonical forward -Z it lowers the right edge. Bank is applied
per sample after transport and is not accumulated into later stations.

The first frame is seeded once from a deterministic world reference: world +Y
when usefully perpendicular to the first tangent, otherwise road +X
orthogonalized against a near-vertical tangent. Later frames transport the
previous right/up pair by the minimal rotation taking the previous tangent to
the current tangent, then re-orthonormalize in float32 engine vectors. Exact or
near-exact tangent reversal has no unique minimal rotation axis and is refused.

Closed courses are deliberately out of scope. A closed table receives an
explicit `closed_loop_unsupported` refusal because residual-roll closure
distribution and a matching seam are a later separate slice.

Stable refusal codes: `bad_table`, `closed_loop_unsupported`,
`table_inconsistent`, `bad_sample`, `nonmonotonic_stations`,
`degenerate_tangent`, `reversing_tangent`, `nonfinite_derived_state`,
`frame_numerics_inconsistent`.

## Validation coverage

The validator runs 7 cases and 1773 checks in one pinned-engine cohort:

- `open_straight_zero_bank_basis`: analytic 40 m length, exact spacing frame
  count, canonical zero-bank axes, unit/orthogonal frames and full metadata
  preservation;
- `graded_banked_bend_transport_and_bank`: 20 frames, independent zero-bank
  control, per-sample bank projection identities, no consecutive sign flips,
  strong-bank measurement and end-bank tilt direction;
- `bank_returns_to_authored_zero`: bank pulse reaches +12 degrees at the
  authored knot and returns to exactly zero with no cumulative roll;
- `near_vertical_rapid_grade_transport`: 35 frames up to a 0.9985 dy/ds grade,
  right stays +X with no vertical-reference flip, max grade occurs after the
  seed, metadata preserved;
- `deterministic_repeat_and_copy_safety`: repeated builds serialize
  identically, mutating returned containers cannot rewrite the stored table,
  and later input-table mutation cannot rewrite the completed result;
- `malformed_input_refusals`: null and wrong-object input, nonmonotonic
  stations, missing key, zero-length tangent, exact reversing tangent,
  nonfinite tangent/width, and grade inconsistent with the tangent;
- `closed_loop_explicit_refusal`: the closed fixture really is closed, the
  builder refuses with `closed_loop_unsupported`, the stable code name and the
  closed diagnostic are present, and the refusal names the later closure
  slice.

The deliberate failure probe prints `ROAD_FRAME_FAILURE_PROBE` with two checks
and one intentional failure, then exits the distinctive rc 3. A zero exit would
mean failing checks are not detectable.

## Run

From the repository root, using the publisher-pinned engine and the shared
coordinator lock:

```sh
sh tools/road_frame_lab/run_validation.sh \
  --project . \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --lock work/agents/coordinator/godot-test.lock \
  --work-root work/road_frame_lab \
  --lock-wait 300 --outer-timeout 180 \
  --log work/road_frame_lab/road_frame_validator.log \
  --summary-out work/road_frame_lab/road_frame_summary.json \
  --evidence-out work/road_frame_lab/runner_evidence.txt \
  --keep-scratch
```

Without `--source-sha`, the runner freezes the selected checkout's current
committed `HEAD`, so a normal run validates the builder you actually have
rather than a stale hard-coded revision. `--source-sha COMMIT` (or
`ROADSTORM_ROAD_FRAME_SOURCE_SHA`) pins an exact historical candidate for
reproduction. The resolved source SHA, the `project_head_sha`, the
`source_sha_source` (`project_head` or `explicit`), and the archive SHA-256 are
recorded in the evidence.

`--work-root`, when supplied, must resolve under the repository's ignored
`work/` tree; otherwise the runner uses a fresh temporary directory. A normal
run removes its scratch directory and only reports PASS when that removal
verified successfully. `--keep-scratch` preserves the frozen stage, logs and
private cache.

Because the archive is a commit, uncommitted changes to tracked files other
than the overlaid paths are not exercised. A normal run therefore tests the
committed sampler and source with the current frame-builder and lab overlay,
never the live working tree.

The runner:

- exports a plain frozen `git archive` source tree without mutating Git;
- overlays only `src/course/road_transport_frame.gd` and files under
  `tools/road_frame_lab/` from the selected checkout;
- records the source SHA, archive SHA-256, per-file overlay SHA-256 values and
  combined overlay-manifest SHA-256, and verifies staged overlay hashes match
  the source overlay;
- uses private `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and
  `XDG_DATA_HOME` directories and never writes the live checkout's `.godot/`;
- verifies the engine prints the publisher-pinned `4.7.2.stable.official.ed1daf0bf`;
- serializes the bounded version/import/validator/probe sequence on the shared
  coordinator lock, closing the lock fd in every child and watchdog;
- stops only the exact recorded Godot child PID if a call times out, and fails
  rather than passing when that happens;
- verifies the validator schema, case counts, per-case passes and zero failed
  checks, then requires the probe's distinctive rc 3 and `pass:false`;
- removes the scratch directory and verifies the removal before PASS.

## Output contract and exit codes

The validator prints one `ROAD_FRAME_LAB_CASE` line per case, then
`ROAD_FRAME_LAB_SUMMARY` and `CHECKS_TOTAL=n CHECKS_FAILED=n`. With
`--summary-out`, the full summary JSON
(`roadstorm.road_frame_lab.summary.v1`) is copied to that path when validation
passes. The probe prints `ROAD_FRAME_FAILURE_PROBE`
(`roadstorm.road_frame_lab.failure_probe.v1`) and exits 3.

Runner exit codes:

- `0`: import succeeded, the summary and case gates held with zero failed
  checks, the failure probe exited rc 3 with `pass:false`, and scratch cleanup
  verified (or `--keep-scratch` was given);
- `1`: a validation, summary, probe or cleanup gate failed, or a child had to
  be stopped at the timeout;
- `2`: unsafe arguments, missing tools, an unusable engine, an engine-version
  mismatch, or an archive/overlay failure.

## Limits

This laboratory evaluates the pure transported-frame table only. It does not
measure mesh or collision baking, seams or discontinuities, closed-loop
residual-roll closure, clearance, intersections, overpasses, gates, grid space,
safe anchors, recovery legality, scenery, render or collision normals,
performance, gameplay feel or release readiness. It does not enforce the
design's grade, bank, width or road-rhythm targets, and it makes no
cross-host, cross-version or rendered determinism claim. The fixtures are
original lab data, not the Riviera Run route.
