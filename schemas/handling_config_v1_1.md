# Handling source recipe contract 1.1.0

This note documents `schemas/handling_config_v1_1.schema.json`, a standalone
JSON Schema draft 2020-12 source-recipe contract. It is derived from
`schemas/handling_config.schema.json` (contract `1.0.0`) and changes exactly
these things: `properties.schema_version.const` and the document's own
top-level `schema_version` metadata both become `1.1.0`; five added
`handling` required entries; five added `handling` properties; and one
`handling.allOf` cross-field rule. The metadata and the constant must stay
equal; the deep-diff test requires that difference. Everything else in the document is structurally identical,
including the root and `handling` `additionalProperties: false` closed shapes
and the relative `$ref`s to `common.schema.json`.

This file is a contract note, not runtime code. It does not implement an
importer or baker, and it does not complete M0.2.

## Why 1.1.0 exists

The typed runtime subset (`src/data/handling_definition.gd`) requires explicit
values for five inputs that the closed `1.0.0` source schema cannot supply:
`max_yaw_rate_rad_s`, `reverse_trigger_speed_m_s`, `reverse_hold_time_s`,
`reverse_acceleration_m_s2` and `reverse_top_speed_m_s`. A `1.0.0` recipe is
therefore never motor-ready, even when every present coefficient is non-null
and every `unknowns` entry resolves. Contract `1.1.0` adds those five source
properties with stated units and bounds so a future baker can validate and map
them.

The mapping decision is `docs/evidence/m02-typed-runtime-mapping-20261127.md`.
The concrete shape follows `work/agents/m02-version-design.Gc7vp9/result.md`.

## The five fields

All five are required members of `handling`. A required member may be JSON
`null`; `null` means the value is undetermined, not zero.

| Field | Unit | Accepted non-null form | Bounds |
| --- | --- | --- | --- |
| `max_yaw_rate_rad_s` | rad/s | finite number, or `{"unlimited": true}` | number `> 0`; object is the exact sole-member form |
| `reverse_trigger_speed_m_s` | m/s | finite number | `0 <= value <= 1` |
| `reverse_hold_time_s` | s | finite number | `value >= 0.3` |
| `reverse_acceleration_m_s2` | m/s^2 | finite number | `value >= 0` |
| `reverse_top_speed_m_s` | m/s | finite number | `value >= 0` |

`max_yaw_rate_rad_s` is an explicit field-level rad/s exception. The recipe's
overall `units.angle` is degrees; this field is not converted.

### Null means unresolved

A `null` value is an honest placeholder for an unmeasured input. Every JSON
`null` in a recipe outside documentation-only members and the `provenance`,
`unknowns` and `content_hash` subtrees must be explained by a resolving dotted
`unknowns` path, following the rule in `schemas/handling/validate_fixtures.py`.
For the five fields the entry must resolve to `handling.<field>` itself. A
non-null value that is also listed in `unknowns` is rejected: an entry may not
claim a determined value is undetermined. The schema cannot express this
pairing, so the standard-library checker enforces it.

### The only INF encoding

Godot's `INF` yaw cap is authored as the exact object `{"unlimited": true}`.
It maps to `INF` and needs no `unknowns` entry. Strings, bare `Infinity`/`NaN`
literals, `1e999`, `{"unlimited": false}`, `{}` and objects with extra members
are invalid. Standard JSON has no `Infinity` literal; the checker uses strict
parsing so those tokens and duplicate keys are rejected before validation.

Finiteness cannot be expressed with JSON Schema keywords. The schema states the
numeric bounds; the stdlib validator and strict JSON parsing reject non-finite
numbers (`NaN`, infinities, overflowing literals such as `1e999`).

### Cross-field rule

If `reverse_acceleration_m_s2` is a number greater than `0`, then
`reverse_top_speed_m_s` must be present and be a number greater than `0`. This
rejects reverse drive with acceleration but no positive top speed, including
top speed `0` and `null`. The rule lives in two places on purpose:

* `properties.handling.allOf` in the schema document, so a JSON Schema checker
  rejects the combination at the schema layer; and
* a duplicate semantic check in `tools/car_recipe_schema/validate_car_recipe.py`,
  because the project's stdlib checker does not evaluate `allOf`/`if`/`then`.

## Closed shapes

The root object and the `handling` object keep `additionalProperties: false`.
Undeclared members are rejected rather than ignored. No field beyond the five
is added, and no measured constant or production car content is invented here.

## Version dispatch

The checker accepts exactly `schema_version` `1.0.0` and `1.1.0`. Any other
value, including `1.1.0\n`, `1.2` and `2.0.0`, is refused with an explicit
diagnostic. There is no migration between versions: a `1.0.0` file is never
silently treated as `1.1.0`. `--mode schema` checks historical schema validity;
`--mode motor-ready` (the default) additionally refuses a recipe whose required
motor inputs are missing, `null` or listed in `unknowns`. A `1.0.0` recipe is
always refused in motor-ready mode, naming all five missing
`handling.<field>` paths.

## Typed resource version stays 1.0.0

`HandlingDefinition` and `DefinitionIdentity` remain at schema version
`1.0.0`; this job does not change them. The source recipe contract version and
the typed resource contract version are separate namespaces. A future baker
records the source contract `roadstorm.handling_config.v1.1.0` separately in a
bake-manifest sidecar and in `common.schema.json#/$defs/provenance`
(`source_contract`), not by copying `1.1.0` into a typed resource's
`schema_version`. The derived handling identity is `<car_id>.handling`, with
the car recipe's `revision` and lifecycle `status` copied after validation.

## What remains

This job ships the contract, its stdlib checker, fixtures and tests only. Still
open:

* the baker/importer that validates the declared version, refuses unsupported
  versions and non-motor-ready recipes, maps each field by its unit rule and
  emits a `HandlingDefinition`;
* conversion tests for source-to-runtime values, including the `INF` encoding
  and the `rad/s` exception;
* content-hash and bake-manifest/provenance recording of `source_version`
  `1.1.0`, the source revision/hash, the derived output identity and the output
  file SHA-256;
* production car content and asset references;
* review.

This is not M0.2 completion. The importer, conversion tests, production
content, asset references, provenance review and the remainder of
`CarDefinition.DEFERRED_FIELDS_V1` remain open.
