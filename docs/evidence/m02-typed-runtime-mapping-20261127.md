# M0.2 typed-resource mapping decision (2026-11-27)

This decision closes the provisional design question raised by the exact-source Opus 5.5 review of `8f02cc9`. It does not claim that a JSON importer, production car content or M0.2 is complete.

`schemas/handling_config.schema.json` is an editable source-recipe contract. Its nullable coefficients and `unknowns` list preserve values that have not been measured. `HandlingDefinition` is a runtime-ready core physical subset: it requires explicit numeric values for every core field used by `ArcadeMotor.MotorTuning`. A future baker must **refuse to emit** a motor-ready `HandlingDefinition` when any required source coefficient is `null` or listed as unknown, and likewise when a required field has no source property at all (the five fields below). It must report the missing paths and leave the source recipe's `null` and `unknowns` intact. It must never silently replace an unknown coefficient with the resource's inert default zero. A draft `CarDefinition` can exist for structural editing, but its validation alone does not authorize a motor, a measured status or product-complete content.

## Five required inputs with no closed-schema source

The current closed schema (root and `handling` both `additionalProperties: false`) has **no** property for five required typed fields:

| Typed field | Unit | Closed-schema source | Provisional mapping |
| --- | --- | --- | --- |
| `max_yaw_rate_rad_s` | rad/s | none | missing-field refusal |
| `reverse_trigger_speed_m_s` | m/s | none | missing-field refusal |
| `reverse_hold_time_s` | s | none | missing-field refusal |
| `reverse_acceleration_m_s2` | m/s² | none | missing-field refusal |
| `reverse_top_speed_m_s` | m/s | none | missing-field refusal |

The uncapped-yaw choice (`INF`) is itself a required authored value with no
source property. None of the five can come from a design constant, an
`unknowns` entry, a schema default or another nullable field. The typed
defaults (including the documented 1 m/s trigger and 0.3 s hold) are inert
direct-authoring placeholders, not measured reverse data; a baker must not
infer authored reverse values from `docs/GAME_DESIGN.md`.

## Versioned route and provisional refusal

A recipe that is valid under the current closed schema therefore cannot supply
the full declared runtime subset, even when every present coefficient is
non-null and every `unknowns` entry is resolved. For this provisional slice the
safe rule is an **explicit missing-field refusal**: a future baker must refuse
every schema-valid recipe until a versioned source schema supplies each of the
five fields, and it must report the missing paths. The refusal must not depend
on whether the currently nullable fields happen to be resolved, and it must
not silently substitute typed defaults.

The safe route is a deliberate source-contract revision: a new `schema_version`
whose `handling` object adds exactly the five properties with stated units and
keeps `additionalProperties: false`. The baker validates the declared version,
maps each field by its unit rule, and emits only when all five are present and
finite. An explicitly versioned external input is an acceptable alternative
only when its version is declared and validated. A mapper/importer and its
refusal code do not exist in this slice; this is a decision about required
behavior, not implemented behavior.

Only directly authored typed resources are usable today. `HandlingDefinition`
and `CarDefinition` validate and round-trip when their `.tres` values are
authored in code or by hand, but they cannot be derived from the current source
recipe. This does not complete M0.2; the importer/baker, conversion tests,
content hashes and provenance remain open.

The source schema nests `handling` within a car and gives that nested object no independent ID or revision. For this first runtime mapping, derive `HandlingDefinition.definition_id` as `<car_id>.handling` and copy the car recipe's `revision`, `schema_version` and lifecycle `status`. The car's typed `handling` reference points to that derived identity. Changing a car's inline handling therefore requires a car revision change. A future explicit reusable handling recipe would need its own versioned contract before sharing a handling resource between cars; it must not invent a second identity from a display name. Lowercase source status values map one-to-one to the typed enum after validation.

The typed `revision` grammar is deliberately stricter than the source schema's nonempty string rule: the baker must reject a non-triplet revision with an explicit diagnostic instead of altering it. The overall authoring unit field says angles are degrees; `max_yaw_rate_rad_s` is an explicit field-level rad/s exception required by the motor. The baker must convert only fields with a stated unit mapping and verify the result. None of these decisions substitutes for the pending source-to-runtime conversion tests, content hashes, asset references, provenance review or the remainder of `CarDefinition.DEFERRED_FIELDS_V1`.

Until an importer exists, the M0.2 resource slice remains provisional. The resource validator and its direct-run scratch safety are being corrected after the named reviews; a later exact-candidate recheck must assess the implemented fixes and this mapping decision.
