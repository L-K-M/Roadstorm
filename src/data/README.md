# Runtime typed definitions (M0.2 slice)

This directory holds the first runtime `Resource` slice for Roadstorm Racer!:
versioned stable semantic identity, a typed handling definition covering the
core physical values the committed pure motor kernel accepts, and a typed car
definition with dimensions/contact envelope, intact mass, a typed handling
reference and explicit draft/completeness semantics.

This is an infrastructure slice, not a content milestone and not a handling
freeze. It creates no production car or track content and makes no M0.2
closure claim beyond the typed resource contracts below.

## Files

| Path | Contents |
| --- | --- |
| `definition_identity.gd` | `DefinitionIdentity` base `Resource`: schema version, stable semantic ID, revision, display name, lifecycle status, documented units/frame constants, identity diagnostics. |
| `handling_definition.gd` | `HandlingDefinition extends DefinitionIdentity`: piecewise acceleration, braking, drag, grip yaw/lateral damping, reverse bounds, validation, code-facing curve helpers and a motor-tuning field projection. |
| `car_definition.gd` | `CarDefinition extends DefinitionIdentity`: dimensional/contact envelope, intact mass, contact proxy, typed handling reference, draft/completeness semantics, validation. |
| `handling_recipe_mapper.gd` | `HandlingRecipeMapper`: pure, in-memory source-recipe (1.1.0) to typed `HandlingDefinition` mapping with exact version dispatch, path-level refusal diagnostics and no file/scene mutation. |

`tools/data_lab/` contains the pinned-Godot validation laboratory and runner.

## Identity contract

- `schema_version` must equal `1.0.0`, the contract implemented by these
  classes. Any other value produces `schema_version: unsupported ...`; there
  is no automatic migration.
- `definition_id` follows `schemas/common.schema.json#/$defs/stable_id`:
  `^[a-z][a-z0-9_]*(?:\.[a-z0-9_-]+)*$`. IDs are semantic and must not be
  renamed when a display name changes.
- `revision` is `MAJOR.MINOR.PATCH` with no leading zeros. This typed-resource
  requirement is deliberately stricter than `schemas/handling_config.schema.json`,
  whose source `revision` is any nonempty string; a future baker must reject a
  non-triplet revision with an explicit diagnostic instead of rewriting it.
  Ordering/comparison belongs to the recipe/review layer.
- `display_name` must be non-empty.
- `status` uses the typed uppercase vocabulary: `PROVISIONAL`, `MEASURED`,
  `FROZEN`, `SUPERSEDED`, `EXAMPLE`. The source schema spells the same five
  lifecycle states in lowercase (`provisional|measured|frozen|superseded|
  example`); the mapping is one-to-one after validation, and an out-of-domain
  integer-backed value is rejected.
- `identity_key()` renders `schema_version/definition_id@revision` for logs.
  It is not a content hash. Recipe-level `content_hash`/`provenance` remain at
  the authored source-recipe layer and are deliberately not invented here.

## Units and frame

The constants on `DefinitionIdentity` are the documented car conventions from
`docs/TECHNICAL_DESIGN.md` ("Content contracts"):

- length `m`, mass `kg`, time `s`, angle `deg`;
- local `+Y` up, `-Z` forward;
- origin at the ground projection of the axle midpoint;
- wheel pivots at local axle centers.

Speeds in this slice are ground-speed magnitudes in m/s; accelerations are
m/s²; yaw rate is rad/s. The HUD-only km/h conversion stays in presentation.

## HandlingDefinition

### Serialized fields

| Field | Meaning / JSON overlap |
| --- | --- |
| `acceleration_curve_speeds_m_s` | Piecewise curve speed abscissae; pairs index-for-index with the acceleration array. Mirrors `handling.acceleration_curve[].speed_m_s`. |
| `acceleration_curve_accelerations_m_s2` | Matching accelerations. Mirrors `handling.acceleration_curve[].acceleration_m_s2`. |
| `braking_acceleration_m_s2` | Maximum brake deceleration; same JSON field. |
| `drag_aerodynamic` | Deceleration contribution `k * |v|^2`; `handling.drag.aerodynamic`. |
| `drag_rolling` | Constant deceleration contribution; `handling.drag.rolling`. |
| `yaw_gain_grip` | Yaw rate per unit steer per m/s signed forward speed; `handling.yaw_gain.grip`. |
| `max_yaw_rate_rad_s` | Absolute yaw-rate cap; `INF` disables it (matches `ArcadeMotor.MotorTuning`). |
| `lateral_damping_grip_per_s` | Exponential lateral decay rate; `handling.lateral_damping.grip_per_s`. |
| `reverse_trigger_speed_m_s` | Brake becomes reverse strictly below this speed. Design ceiling 1 m/s. |
| `reverse_hold_time_s` | Required brake hold below the trigger. Design minimum 0.3 s. |
| `reverse_acceleration_m_s2` | Explicit reverse drive acceleration. |
| `reverse_top_speed_m_s` | Reverse drive speed cap; required positive when reverse acceleration is nonzero. |

Defaults are inert zeros plus the two documented reverse control constants
(1 m/s, 0.3 s). They are not measured coefficients, product handling data or a
frozen specification.

### Acceleration-curve representation and serialization finding

The JSON contract stores `acceleration_curve` as an array of
`{speed_m_s, acceleration_m_s2}` point objects. An earlier in-memory design
used `Array[AccelerationPoint]` with a nested `Resource` class. Godot 4.7.2
cannot reload that shape from `.tres`: the loader reports
`Attempted to assign an object into a TypedArray, that does not inherit from
'GDScript'` and the exported array comes back empty. A focused experiment in a
scratch project confirmed that a global (non-nested) class and native typed
containers (`Array[float]`, `Array[Dictionary]`,
`Array[PackedFloat32Array]`) do round-trip, while a nested class does not.

The serialized resource therefore uses the parallel native typed arrays above,
which preserve every value exactly and keep the typed fields authored in
`.tres`. The code-facing API still presents points:

- `get_acceleration_points() -> Array[AccelerationPoint]` builds transient
  `AccelerationPoint` records. If the arrays differ in length (invalid
  content), it returns an empty list rather than a truncated curve.
- `set_acceleration_points(points) -> bool` replaces both arrays atomically.
  It returns `false` and changes nothing if any entry is null or not an
  `AccelerationPoint`.
- `clear_acceleration_curve()` empties both arrays.

Validation requires equal lengths, at least one pair, finite non-negative
values and strictly increasing speeds. It does not clamp or repair mismatches.

### MotorTuning adapter seam (not integrated)

`to_motor_tuning_fields()` projects the validated scalars under
`ArcadeMotor.MotorTuning` field names plus `acceleration_curve` as
`AccelerationPoint` records. A future adapter owns converting each record to
`ArcadeMotor.SpeedAccelerationPoint` and calling
`ArcadeMotor.MotorTuning.make(...)`. This slice neither imports nor calls the
motor and applies no physics.

## CarDefinition

### Dimensional/contact envelope

Metres/kg/seconds, `+Y` up, `-Z` forward, origin at the ground projection of
the axle midpoint. Limits are the initial envelopes from
`docs/TECHNICAL_DESIGN.md` and `schemas/handling_config.schema.json`:

| Field | Rule |
| --- | --- |
| `length_m` | finite, 3.6–4.8 m |
| `width_m` | finite, 1.7–2.2 m |
| `height_m` | finite, 1.0–1.8 m |
| `wheelbase_m` | `null` (undetermined) or finite `> 0` and `<= length_m` |
| `ground_clearance_m` | `null` or finite `>= 0` and `<= height_m` |
| `jump_envelope_m` | `null` or finite `>= 0` |
| `mass_kg` | finite `> 0`; intact mass unaffected by cosmetic damage |
| `contact_proxy_shape` | `ROUNDED_BOX` or `CONVEX_HULL`, derived from declared dimensions |
| `contact_roof`, `contact_underside` | string description or `null` (undetermined); wrong types are diagnosed |
| `handling` | typed `HandlingDefinition`; missing/null is invalid, its full diagnostics are included with identity paths prefixed `handling.` and physical paths passed through once |

Optional dimension fields use `null` rather than a fake zero so a draft can be
honest about undetermined values. Contact geometry is always the simplified
hull derived from these dimensions; rendering detail cannot change it.

### Draft/completeness semantics

`completeness` is distinct from lifecycle `status`:

- `DRAFT`: early structural placeholder; requires a non-blank
  `completeness_note` and a complete `deferred_fields` declaration.
- `INCOMPLETE`: some authored fields, declared gaps; same note/list rules.
- `COMPLETE`: reserved for a later full-car definition. This partial slice
  cannot represent `DEFERRED_FIELDS_V1`, so it always refuses `COMPLETE`, even
  when `deferred_fields` is cleared. A `COMPLETE` record therefore never
  validates; a later full-car definition owns closing that claim.

While `DEFERRED_FIELDS_V1` exists, a `DRAFT` or `INCOMPLETE` declaration must
name every listed v1 path exactly once; blank and duplicate entries are
diagnosed. Entries for fields introduced by later slices may be added, but the
known v1 set cannot be silently omitted, so `["todo"]` does not validate.
Out-of-domain integer-backed `completeness` values are rejected instead of
falling through the named cases.

`is_complete()` returns true only when `completeness == COMPLETE` **and**
`validate()` is empty, so an invalid record can never report completion.
`DEFERRED_FIELDS_V1` lists the car fields deliberately absent from this slice:

- `presentation.mesh_id`, `presentation.lod_ids`, `presentation.paints`,
  `presentation.icon`
- `engine.top_speed_kmh`
- `upgrades.levels`
- `detachable_parts`
- `handling.drift`, `handling.surge`, `handling.drafting`, `handling.airborne`,
  `handling.contact_caps`, `handling.surfaces`

## Validation policy

A referenced handling is validated with its full `validate()`, not only the
physical subset, so malformed handling IDs/revisions/schema versions/blank
display names/status/out-of-domain values make the car invalid as well.
Referenced-handling identity diagnostics are prefixed with `handling.`; its
physical diagnostics already start with `handling.` and pass through once, so a
shared defect in both records remains attributable to each record.

Every `validate()` returns `Array[String]` diagnostics with dotted field paths;
`is_valid()` is exactly `validate().is_empty()`. Diagnostics cover malformed
IDs/revisions/schema versions, out-of-domain enum values, missing handling
references, nonfinite, negative and inconsistent physical values,
out-of-envelope dimensions, incomplete deferred-field declarations and
contradictory completeness claims. Validation never clamps, substitutes
defaults, drops entries or partially repairs authored content.

`HandlingDefinition.validate()` is physical-range and consistency validation of
the motor-ready core subset. It is **not** proof that a coefficient is measured,
that provenance/unknowns are resolved, or that the content is production
complete. Source recipes may legitimately carry `null`/unknown coefficients;
see the runtime/source mapping below.

## Runtime/source mapping

`schemas/handling_config.schema.json` is the historical 1.0.0 editable source
recipe; `schemas/handling_config_v1_1.schema.json` is the separate version 1.1.0
source contract. Their nullable coefficients and `unknowns` lists preserve values
that have not been measured. `HandlingDefinition` is a runtime-ready core subset
and requires resolved values for every field used by `ArcadeMotor.MotorTuning`.
A baker must refuse to emit a motor-ready `HandlingDefinition` when a required
source coefficient is absent, `null`, invalid or listed as unknown, report the
missing paths and preserve the source `null`/`unknowns`; it must never silently
substitute the resource's inert zero. A draft `CarDefinition` can exist for
structural editing, but its validation alone does not authorize a motor, a
measured status or product-complete content.

`HandlingRecipeMapper` implements this refusal and mapping contract as a pure
interface:

```gdscript
var result := HandlingRecipeMapper.map_handling(recipe)
if result.ok:
    var handling := result.handling  # fully validated HandlingDefinition
else:
    for diagnostic in result.diagnostics:  # "<path>: <code>: <message>"
        ...
```

`recipe` is an authored Dictionary matching the 1.1.0 source contract. The
mapper reads it without mutating it or any nested member, writes no files and
touches no scene tree. Version dispatch is exact: `"1.0.0"` is refused with the
five missing `handling.*` paths added by 1.1.0, and every other `schema_version`
value (including absent, non-string or trailing-newline forms) is refused as
unsupported. For `1.1.0` all eleven motor inputs must be present, non-null,
valid and absent from `unknowns`; the five added fields are required rather than
defaulted. The exact sole-member object `{"unlimited": true}` maps to Godot
`INF`; a finite positive yaw number maps through unchanged. The source declares
`units.length = m`, `units.mass = kg`, `units.time = s` and `units.angle = deg`
must all match; `max_yaw_rate_rad_s` is the documented field-level rad/s
exception and is never converted. The mapped acceleration curve keeps
authored order and fails closed on unordered, empty or malformed points.
Null values paired with matching `unknowns` entries are reported as unresolved;
resolved values marked unknown are refused. Direct callers cannot bypass this
check through a curve-point member.

A refusal returns `ok == false`, `handling == null` and at least one
path-level diagnostic. A success runs the resulting definition's full
`validate()` and returns `ok == true` with an empty diagnostic list; a
definition that cannot validate is never returned as a half-valid resource.
Identity is derived as `<car_id>.handling` with display name
`<car display_name> handling`; the car recipe's triplet `revision` and
lifecycle `status` are copied after validation, and the typed `schema_version`
stays `1.0.0`. The source version belongs in the handling bake manifest and
provenance `source_contract`, never in the typed resource. Full JSON
Schema/strict-parse/content-hash validation remains the external prerequisite
owned by `tools/car_recipe_schema/validate_car_recipe.py`; the mapper defends
only against malformed dictionaries reaching it directly. It writes no `.tres`,
bake manifest or provenance sidecar.

The closed 1.0.0 schema has **no** source property for five required fields:
`max_yaw_rate_rad_s` (rad/s), `reverse_trigger_speed_m_s` (m/s),
`reverse_hold_time_s` (s), `reverse_acceleration_m_s2` (m/s²) and
`reverse_top_speed_m_s` (m/s); the uncapped-yaw choice is likewise unsourced.
See `docs/evidence/m02-typed-runtime-mapping-20261127.md` for the decision.

For this first runtime mapping the nested source `handling` has no independent
identity: derive `HandlingDefinition.definition_id` as `<car_id>.handling` and
copy the car recipe's `revision` and lifecycle `status`, and derive its display
name as `<car display_name> handling`. The typed `schema_version` stays at
`1.0.0`; record the source version `1.1.0` separately in the handling bake manifest
and provenance `source_contract`. Never copy the source version into the typed
resource. The car's typed `handling` reference points to that derived identity,
so changing a
car's inline handling requires a car revision change. A future reusable handling
recipe needs its own versioned contract and must not invent an identity from a
display name. The bounded `tools/car_recipe_bake/` command now writes one
validated derived handling `.tres` and manifest from one checked motor-ready
recipe. It does not yet emit a `CarDefinition` or populate a runtime cache.

## Explicitly deferred work

No closure is claimed for content or systems beyond this slice.

- **Car content:** presentation meshes/LODs/paints/icon, engine top speed and
  engine curve duplication question, upgrades, detachable parts/attachment
  transforms/impact regions/thresholds.
- **Remaining handling:** drift entry/sustain/recovery/stability assist,
  surge candidates/selection, drafting geometry, airborne gravity/adhesion,
  contact caps, per-surface modifiers and route-local surface semantics.
- **Other definitions:** Track, Event, Upgrade, AI profile, Ghost, Model,
  AIObservation/TacticalIntent, ReferenceRun/Scenario resources. The existing
  `schemas/` text contracts remain the source contracts.
- **Systems:** motor integration/adapter, `.tres` artifact writer and bake
  manifest/provenance recording for mapped recipes, content-hash computation,
  baking and validation wiring.
- **Product:** no authored cars, tracks, events, tunes, measures or
  milestones are produced or frozen by this slice.

## Data lab

```sh
timeout 600 lockf -k -w -t 600 work/agents/coordinator/godot-test.lock \
  sh tools/data_lab/run_validation.sh --case all
```

See `tools/data_lab/README.md` for cases, output markers and limits.
