# Car handling source-recipe checker

Standard-library validator and tests for the Roadstorm car handling source
recipes:

* `schemas/handling_config.schema.json` (`schema_version` `1.0.0`), and
* `schemas/handling_config_v1_1.schema.json` (`schema_version` `1.1.0`).

The contract note for `1.1.0` is
[`../../schemas/handling_config_v1_1.md`](../../schemas/handling_config_v1_1.md).
Fixtures live in [`../../fixtures/car_recipe/`](../../fixtures/car_recipe).

## Running

```sh
python3 tools/car_recipe_schema/validate_car_recipe.py \
    --mode schema fixtures/car_recipe/positive
sh tools/car_recipe_schema/run_tests.sh
```

Exit codes: `0` valid, `1` validation/content error, `2` unreadable path or bad
usage. The tool only validates; it writes no artifacts.

## Modes

* `--mode schema` checks historical schema validity. A valid `1.0.0` recipe
  passes even though it cannot supply the five motor inputs.
* `--mode motor-ready` (default) additionally refuses a recipe whose required
  typed motor inputs are missing, `null` or listed in `unknowns`, naming their
  dotted paths. A `1.0.0` recipe is always refused here, naming all five
  `handling.<field>` paths.

Version dispatch accepts exactly `1.0.0` and `1.1.0`; any other value is
refused. Versions are never migrated.

## What it checks

Required members, closed objects (`additionalProperties: false`), types,
ranges, the five added `1.1.0` fields, the reverse cross-field rule, the
null/`unknowns` honesty rule in both directions, strict JSON parsing (duplicate
members and `Infinity`/`NaN` literals rejected), and the canonical
`content_hash`.

## Deliberate limitations

* Standard library only. It does not run the engine, execute a recipe or check
  physics outcomes.
* It implements these two contracts in plain Python, not the full JSON Schema
  draft 2020-12 vocabulary. The schema documents remain the text contracts.
  Finiteness, the null/`unknowns` pairing and the reverse cross-field rule are
  semantic checks the schema cannot fully express, so they live here as well
  as (where expressible) in the schema.
* It cannot make unknown facts known. Missing or null values are reported,
  never filled in and never guessed.

Original project code under the Unlicense.
