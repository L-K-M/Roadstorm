# Road arc-length sampling laboratory

This directory is the standalone validation laboratory for the first M2
arc-length sampling slice. It checks the deterministic
`RoadArcSampler.build_uniform_table()` API in `src/course/road_arc_sampler.gd`
against three original lab fixtures and meaningful in-memory refusals. It
consumes a validated `roadstorm.road_source.v1` document and produces uniform
station tables; it does not bake geometry or validate a course.

This is provisional M2 sampling work. It does not implement mesh, collision,
shoulders, barriers, gates, grid, sectors, AI hints, minimap, course authoring,
drivability or course-quality gates, and it does not claim M2.1 or milestone
acceptance.

## Files

| File | Role |
| --- | --- |
| `fixtures/road_sampling_open_straight.json` | original three-knot open fixture, two collinear spans |
| `fixtures/road_sampling_open_curve.json` | original two-knot open fixture with climb, bank reversal and width narrowing |
| `fixtures/road_sampling_closed_loop.json` | original four-knot closed fixture with wrapping final span |
| `road_sampling_checks.gd` | positive, independent-length, boundary, determinism, preservation, refusal and budget checks |
| `validate_road_sampling_lab.gd` | headless `SceneTree` validator entry point |
| `failure_probe.gd` | deliberate failing-check control; exits 3 when detection works |
| `run_validation.sh` | frozen-source, private-cache, shared-lock runner |

## Source dependency

The sampler consumes the public accessors of schema `roadstorm.road_source.v1`
(`src/course/road_source.gd`). `build_uniform_table()` requires an already
validated `RoadSourceDocument` object; it never parses JSON, revalidates the
document, or mutates it. It reads the ordered `spans` array, each span's
`control_points()`, knot `width_m`/`bank_deg`, and its `section_id`,
`surface_id` metadata. A wrong object type, a span count inconsistent with the
document, or a span without exactly four finite control points is refused.

The source schema owns authored data validity: exact keys, unique stable
section IDs, finite components, plausible width band, ordered sections and
ordered spans, degenerate anchor/handle guards, and the float32 conversion
refusal for finite JSON scalars that cannot become finite `Vector3`
components. The sampler does not repeat those checks; it refuses a malformed
or overflowing derived state with its own codes.

## Sampler API

`RoadArcSampler` is a `RefCounted` utility class.

```gdscript
static func build_uniform_table(
    p_document: Variant,
    p_spacing_m: Variant,
    p_options: Variant = {}
) -> Dictionary
```

On success it returns:

```gdscript
{"ok": true, "code": 0, "code_name": "none", "error": "", "diagnostic": {}, "table": Table}
```

On failure it returns a structured refusal and no partial table:

```gdscript
{"ok": false, "code": <Refusal>, "code_name": "<name>", "error": "...",
 "diagnostic": {...}, "table": null}
```

`RoadArcSampler.refusal_name(code)` maps a code to its stable name.
`Table` exposes read-only `schema` (`roadstorm.road_arc_table.v1`), `course_id`,
`revision`, `closed`, `sample_spacing_m`, `total_length_m`,
`length_error_estimate_m`, `max_inversion_error_estimate_m`,
`max_inversion_residual_m`, `span_count`, `sample_count`, `options`,
`span_tables`, `samples`, `section_boundary_policy` and `closed_seam_policy`.
Indexed `span_table(i)` and `sample(i)`, `closed_seam()`, `summary()` and
`to_dictionary()` return deep copies. GDScript cannot fully hide a private
member from `Object.set`; wholesale replacement remains the documented
residual mutation path.

Each sample records:

- `index`, `s` (nominal metres along the chained spans);
- `position` (Godot `Vector3`, metres, +Y up, -Z forward);
- `forward_tangent` (normalized unit `Vector3`);
- `width_m`, `bank_deg`;
- `grade_dy_ds` (tangent y component);
- `span_index`, `span_t`;
- `section_id`, `surface_id`;
- `sample_role`: `open_start`, `open_end`, `closed_seam_start`,
  `closed_seam_end`, or `interior`.

Each span record records `span_index`, `start_knot_index`, `end_knot_index`,
`section_id`, `surface_id`, `start_s`, `end_s`, `length_m`,
`length_error_estimate_m`, `integration_leaf_count`, `max_depth_used`,
`table_node_count`, and the ordered `nodes` array of `{t, s}` pairs.

## Stations, seams and boundaries

Stations are nominal metres along the chained spans, strictly increasing, and
include exact course start and end samples. The final interval is shorter
unless the total length is an exact multiple of the spacing.

- Each span owns the half-open station interval `[start_s, end_s)`. A station
  exactly on an interior knot boundary uses the following span at `t=0` and
  therefore the following section and surface metadata.
- The final course end is the one exception: it uses the final span at `t=1`
  and keeps the incoming final section.
- An open course labels its endpoints `open_start` and `open_end`.
- A closed course emits an ordered seam pair: `s=0` is `closed_seam_start`
  from span 0 at `t=0`, and `s=total_length` is `closed_seam_end` from the
  final span at `t=1`. `closed_seam()` reports their indices and stations.

Width and bank are linear in Bezier parameter `t` inside each span. Clamping
the parameter keeps them continuous and free of overshoot between the two
authored knot values; it does not make them linear in distance. Grade is
reported as the tangent's y component, not a separately integrated quantity.
No transported frame, up vector, roll correction, render normal or collision
normal is produced here.

## Numerical method, budgets and refusals

Each cubic span's speed `|dB/dt|` is integrated by adaptive recursive Simpson
quadrature in a fixed left-to-right order. The speed and geometric bracket are
evaluated in scalar float64 arithmetic directly from the stored `Vector3`
control-point components rather than through intermediate float32 `Vector3`
operations. Bracket displacements are computed from control-point differences,
so kilometres of world translation do not enter the subtraction. Local
derivative differences outside the finite `Vector3` component range remain
derived-state refusals; output positions and tangents are still `Vector3`
values. A candidate leaf is accepted only after an independent eight-piece
geometric bracket places its extrapolated length between summed chord and
control-polygon bounds within an explicit roundoff allowance. Its reported
error is the conservative maximum distance to either bound plus that leaf's
relative roundoff allowance; acceptance compares that padded estimate, not
the bare bracket distance, and the per-span error sums accepted leaf bounds.
Because every leaf allowance is relative to a bracket enclosing its subarc,
the summed reported error cannot fall below `ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF`
times the span endpoint chord; a request below that precision floor is refused
as `precision_unreachable` rather than accepted above the budget. The floor
bounds the conservative reported estimate, not a proven forward error. A cap
reached before this check passes is a structured refusal. Arc-length
inversion brackets the target from the adaptive table, then uses bounded
Newton steps with bisection fallback and fixed Richardson-refined composite
Simpson quadrature.
The inversion estimate is separate and is not an independently bounded
geometric error estimate.

Defaults and caps:

| Option | Default | Tightening range |
| --- | --- | --- |
| `arc_length_tolerance_m` | `0.001` m | `(0, 0.001]` |
| `max_subdivision_depth` | `20` | integer `0..20` |
| `max_table_nodes_per_span` | `4097` | integer `2..4097` |
| `max_output_samples` | `20000` | integer `2..20000` |

Options may only tighten the defaults. Unknown keys, non-numeric values,
non-integer caps, looser tolerances and loosened caps are refused with
`bad_options`.

Inversion uses 8 coarse and 16 fine panels, at most 16 iterations, and stops
when the residual is within `0.05` of the inversion tolerance. The inversion
tolerance is `arc_length_tolerance_m * 0.1`, so the default final residual
bound is `0.0001` m. Derivative degeneracy is detected from the quadratic
roots of each axis derivative using relative speed epsilon `1e-7`, root
parameter tolerance `1e-12` and discriminant epsilon `1e-7`.

Stable refusal codes: `bad_document`, `bad_spacing`, `bad_options`,
`nonfinite_derived_state`, `degenerate_derivative`,
`subdivision_cap_exceeded`, `table_node_cap_exceeded`, `sample_cap_exceeded`,
`inversion_failed`, `precision_unreachable`, `table_inconsistent`. Hitting a
budget cap or an unconverged inversion is a structured refusal, not a silent
approximation or partial table.

## Validation coverage

The validator runs 10 cases and 631 checks in one pinned-engine cohort:

- `open_straight_uniform_table`: analytic 60 m straight length, exact stations,
  endpoint positions and roles, interior knot boundary ownership, linear
  width/bank interpolation, normalized tangent, flat grade, one integration
  leaf per straight span;
- `open_curve_length_and_fields`: curved length agrees with an independent
  65536-panel fixed midpoint reference within 0.005 m, reported error stays
  inside the tolerance, inversion residual stays inside the inversion
  tolerance, strict stations, normalized tangents, grade identity, section
  metadata and width/bank bounds;
- `closed_loop_seam_and_boundaries`: analytic 120 m loop, nine samples,
  coincident ordered seam endpoints, `closed_seam()` metadata, interior
  boundary ownership across three knots, final span `t=1`, span order and
  wrap-around knot indices;
- `deterministic_repeats`: repeated builds serialize identically;
- `source_preservation_and_table_copies`: building does not mutate the source
  summary; mutating returned containers cannot rewrite the table;
- `malformed_and_derived_refusals`: null document, bad spacings (`0`, `-1`,
  `NaN`, `Inf`, string), unknown option, looser tolerance, interior cusp,
  non-dyadic interior zero derivative, and derived-state overflow from large
  control points;
- `budget_controls`: output sample cap, table node cap, subdivision depth cap,
  non-integer cap, and a loosened cap;
- `conservative_bracket_regressions`: Sol's analytic short quadratic and
  near-end spacing, Opus's road-like and hook counterexamples against
  independent length references, and refusal of a positive span after a 2^53 m
  prefix. That prefix makes the first span's endpoint chord huge, so at the
  default tolerance the span is refused as `precision_unreachable`; this
  fixture no longer reaches the later global-station advance guard retained in
  source, which is a change of test reachability rather than removal of the
  guard;
- `translated_float64_regressions`: Sol's exact 24,576 m diagonal straight
  (actual error must fit both the 1 mm tolerance and the reported estimate),
  two non-dyadic straight lines, the road1/road2/hook review spans translated
  by about 1.4, 2.8 and 5 km, and 40
  seeded gentle road-like spans around 2 km from the origin. Every span must
  build at default options. Lengths are compared with a fixed scalar
  Gauss-Legendre reference computed from the parsed float32 control points;
  the coarse/fine reference uncertainty must be below one picometre and the
  sampler's reported error estimate must cover the observed length error
  without an added comparison tolerance;
- `tightened_tolerance_precision_contract`: an analytic dyadic diagonal whose
  roundoff-implied reported-error floor exceeds a 1e-8 m request refuses as
  `precision_unreachable` with the derived floor, endpoint chord and request
  in its diagnostic, while requests just above the floor and at 1e-6 m build
  and report padded errors within budget.

The deliberate failure probe prints `ROAD_SAMPLING_FAILURE_PROBE` with two
checks and one intentional failure, then exits 3. A zero exit would mean
failing checks are not detectable.

## Run

From the repository root, using the publisher-pinned engine and the shared
coordinator lock:

```sh
sh tools/road_sampling_lab/run_validation.sh \
  --project . \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --lock work/agents/coordinator/godot-test.lock \
  --work-root work/road_sampling_lab \
  --lock-wait 120 --outer-timeout 120 \
  --log work/road_sampling_lab/road_sampling_validator.log \
  --summary-out work/road_sampling_lab/road_sampling_summary.json \
  --evidence-out work/road_sampling_lab/runner_evidence.txt \
  --keep-scratch
```

Without `--source-sha`, the runner freezes the selected checkout's current
committed `HEAD`, so a normal run validates the parser you actually have
rather than a stale hard-coded revision. `--source-sha COMMIT` (or
`ROADSTORM_ROAD_SAMPLING_SOURCE_SHA`) pins an exact historical candidate for
reproduction. The resolved source SHA, the `project_head_sha`, the
`source_sha_source` (`project_head` or `explicit`), and the archive SHA-256 are
recorded in the evidence.

`--work-root`, when supplied, must resolve under the repository's ignored
`work/` tree; otherwise the runner uses a fresh temporary directory and
removes it after a normal run. `--keep-scratch` preserves the frozen stage,
logs and private cache.

Because the archive is a commit, uncommitted changes to tracked files other
than the two overlaid paths are not exercised. A normal run therefore tests
the committed parser with the current sampler and lab overlay, never the live
working tree.

The runner:

- exports a plain frozen `git archive` source tree without mutating Git;
- overlays only `src/course/road_arc_sampler.gd` and files under
  `tools/road_sampling_lab/` from the selected checkout;
- records the source SHA, archive SHA-256, per-file overlay SHA-256 values and
  combined overlay-manifest SHA-256, and verifies staged overlay hashes match
  the source overlay;
- uses private `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and
  `XDG_DATA_HOME` directories and never writes the live checkout's `.godot/`;
- verifies the engine prints `4.7.2.stable.official.ed1daf0bf`;
- serializes the bounded version/import/validator/probe sequence on the shared
  coordinator lock;
- records the exact PID and command of a stranded Godot child, stops only that
  child, and preserves the run log in that case;
- runs the positive validator and then the deliberate failure probe.

## Output contract and exit codes

The validator prints one `ROAD_SAMPLING_LAB_CASE` line per case, then
`ROAD_SAMPLING_LAB_SUMMARY` and `CHECKS_TOTAL=n CHECKS_FAILED=n`. With
`--summary-out`, the full summary JSON (`roadstorm.road_sampling_lab.summary.v1`)
is copied to that path when validation passes. The probe prints
`ROAD_SAMPLING_FAILURE_PROBE` (`roadstorm.road_sampling_lab.failure_probe.v1`)
and exits 3.

Runner exit codes:

- `0`: import succeeded, the validator reported `pass:true` with zero failed
  checks, and the failure probe exited nonzero with `pass:false`;
- `1`: a validation, output-gate or probe expectation failed;
- `2`: unsafe arguments, missing tools, an unusable engine, an engine-version
  mismatch, or an archive/overlay failure.

## Limits

This laboratory evaluates the pure sampling table only. It does not measure
mesh or collision baking, seams or discontinuities, clearance, intersections,
overpasses, gates, grid space, safe anchors, recovery legality, scenery,
render or collision normals, performance, gameplay feel or release readiness.
It does not enforce the design's grade, bank, width or road-rhythm targets,
and it makes no cross-host, cross-version or rendered determinism claim. The
independent length references are fixed-panel midpoint and Gauss-Legendre
quadrature, not a second adaptive integrator or a proof of correctness. The
fixtures are original lab data, not the Riviera Run route.
