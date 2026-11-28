# M0.2 typed-resource mapping decision (2026-11-27)

This decision closes the provisional design question raised by the exact-source Opus 5.5 review of `8f02cc9`. It does not claim that a JSON importer, production car content or M0.2 is complete.

`schemas/handling_config.schema.json` is the historical editable source-recipe contract at version 1.0.0. Its nullable coefficients and `unknowns` list preserve values that have not been measured. The separate version 1.1.0 contract is `schemas/handling_config_v1_1.schema.json`; it adds the five previously missing fields below. `HandlingDefinition` is the runtime-ready core physical subset. A future baker must **refuse to emit** it when any required source coefficient is `null`, listed as unknown, absent or invalid. It must report the paths and leave the source recipe's `null` and `unknowns` intact. It must never silently replace an unknown coefficient with the resource's inert defaults. A draft `CarDefinition` can exist for structural editing, but its validation alone does not authorize a motor, a measured status or product-complete content.

## Five required inputs added in source version 1.1.0

The closed source version 1.0.0 schema (root and `handling` both `additionalProperties: false`) has **no** property for five required typed fields. Version 1.1.0 adds all five as required but nullable `handling` members:

| Typed field | Unit | v1.0.0 source | v1.1.0 resolved mapping |
| --- | --- | --- | --- |
| `max_yaw_rate_rad_s` | rad/s | none | positive finite number, or exact `{"unlimited": true}` mapped to Godot `INF` |
| `reverse_trigger_speed_m_s` | m/s | none | number in `[0, 1]` |
| `reverse_hold_time_s` | s | none | number `>= 0.3` |
| `reverse_acceleration_m_s2` | m/s² | none | number `>= 0` |
| `reverse_top_speed_m_s` | m/s | none | number `>= 0`; positive when reverse acceleration is positive |

The uncapped-yaw choice is an authored value only when the source contains the
exact object `{"unlimited": true}`. Standard JSON does not carry `INF`; `null`
means unresolved. None of the five can come from a design constant, an
`unknowns` entry, a schema default or another nullable field. The typed
defaults (including the documented 1 m/s trigger and 0.3 s hold) are inert
direct-authoring placeholders, not measured reverse data; a baker must not
infer authored reverse values from `docs/GAME_DESIGN.md`.

## Versioned route and provisional refusal

A recipe that is valid under the historical version 1.0.0 closed schema cannot supply
the full declared runtime subset, even when every present coefficient is
non-null and every `unknowns` entry is resolved. For this provisional slice the
safe rule is an **explicit missing-field refusal**: a future baker must refuse
every version 1.0.0 recipe and report the five missing paths. The refusal must not depend
on whether the currently nullable fields happen to be resolved, and it must
not silently substitute typed defaults.

Version 1.1.0 supplies those properties with stated units and keeps
`additionalProperties: false`. The baker must dispatch on the declared source
version and emit a typed resource only when all required version 1.1.0 inputs
are resolved and valid. Its yaw mapping accepts a positive finite number or
the sole explicit unlimited object; reverse acceleration greater than zero
requires positive reverse top speed. A mapper/importer and its artifact-writing
refusal code do not exist in this slice; this is a decision about required
behavior, not implemented behavior.

Only directly authored typed resources are usable today. `HandlingDefinition`
and `CarDefinition` validate and round-trip when their `.tres` values are
authored in code or by hand, but they cannot yet be derived from either source
recipe contract. This does not complete M0.2; the importer/baker, conversion tests,
content hashes and provenance remain open.

The source schema nests `handling` within a car and gives that nested object no independent ID or revision. For this first runtime mapping, derive `HandlingDefinition.definition_id` as `<car_id>.handling`, set its display name to `<car display_name> handling`, and copy the car recipe's `revision` and lifecycle `status`. The **typed** `schema_version` remains `1.0.0`, the only version `DefinitionIdentity` accepts. Record the **source** version `1.1.0` separately in the future bake manifest and provenance `source_contract`; never copy it into the typed resource. The car's typed `handling` reference points to the derived identity. Changing a car's inline handling therefore requires a car revision change. A future explicit reusable handling recipe would need its own versioned contract before sharing a handling resource between cars; it must not invent a second identity from a display name. Lowercase source status values map one-to-one to the typed enum after validation.

The typed `revision` grammar is deliberately stricter than the source schema's nonempty string rule: the baker must reject a non-triplet revision with an explicit diagnostic instead of altering it. The overall authoring unit field says angles are degrees; `max_yaw_rate_rad_s` is an explicit field-level rad/s exception required by the motor. The baker must convert only fields with a stated unit mapping and verify the result. None of these decisions substitutes for the pending source-to-runtime conversion tests, content hashes, asset references, provenance review or the remainder of `CarDefinition.DEFERRED_FIELDS_V1`.

Until an importer exists, the M0.2 resource slice remains provisional. The directly authored typed resource validation passed the exact `316705d` scoped Opus 5.5 and GPT-6.2 Sol rechecks; the new source version and future baker require their own review and conversion evidence.
