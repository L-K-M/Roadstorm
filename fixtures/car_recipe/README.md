# Car handling source-recipe fixtures

Fixtures for the Roadstorm car handling source recipes:

* `positive/` holds valid authored examples, and
* `negative/` holds one-defect files that the checker must reject.

The contracts are [`../../schemas/handling_config.schema.json`](../../schemas/handling_config.schema.json)
(`1.0.0`) and
[`../../schemas/handling_config_v1_1.schema.json`](../../schemas/handling_config_v1_1.schema.json)
(`1.1.0`). The checker is
[`../../tools/car_recipe_schema/validate_car_recipe.py`](../../tools/car_recipe_schema/validate_car_recipe.py).

## Positives

| File | Contract | Notes |
| --- | --- | --- |
| `example_rookie_finite.json` | 1.1.0 | finite yaw cap `2.5`; boundary trigger `1.0`, hold `0.3`, reverse acceleration `0`/top `0` |
| `example_rookie_unlimited.json` | 1.1.0 | `{"unlimited": true}` yaw; boundary trigger `0.0`, hold `0.3`, reverse acceleration `2.0`/top `5.0` |
| `example_rookie_null_motor_inputs.json` | 1.1.0 | two of the five fields are `null` with matching `unknowns` entries; schema-valid but refused by motor-ready mode |
| `example_rookie_v1_0_0.json` | 1.0.0 | historical schema validity only; no five fields, so motor-ready mode refuses it |

All values are clearly authored placeholders (`status` `example`), not
measured production car data. Every positive recomputes its `content_hash`.

## Negatives

One declared defect per file: missing each of the five fields, a `null` without
its `unknowns` entry, a determined value listed as unknown, an unresolved
`unknowns` path, yaw zero/negative/string/boolean/`Infinity`/`{"unlimited":
false}`/extra-key forms, trigger above `1`, hold below `0.3`, negative reverse
acceleration or top speed, acceleration `> 0` with top speed `0`/`null`, a stale
`content_hash`, unsupported versions (including `1.1.0\n`), a duplicate JSON
member, a closed-shape violation and a boolean used as a number.

`stale_content_hash.json` intentionally carries a wrong hash. The other
negatives carry correct hashes so their reported defect is the intended one.
`yaw_infinity_literal.json` is not parseable JSON at all, so it cannot carry a
canonical content hash; its declared defect is strict parsing.

## Validating

```sh
python3 tools/car_recipe_schema/validate_car_recipe.py --mode schema fixtures/car_recipe/positive
sh tools/car_recipe_schema/run_tests.sh
```

Original project files under the Unlicense.
