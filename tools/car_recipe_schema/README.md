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
  passes even though it cannot supply the five motor inputs. `revision` keeps
  its historical rule: any nonempty string.
* `--mode motor-ready` (default) additionally refuses a recipe whose required
  typed motor inputs are missing, `null` or listed in `unknowns`, naming their
  dotted paths; refuses an acceleration curve whose speeds do not strictly
  increase after binary64 conversion (so distinct authored numbers that
  collapse to the same runtime float are refused at
  `handling.acceleration_curve[i].speed_m_s`); and runs two typed-resource
  preflight checks, a `revision` that is
  not `MAJOR.MINOR.PATCH` (`bad-revision-format`) and a derived
  `<car_id>.handling` identity that would fail `DefinitionIdentity`'s
  whole-string stable-ID match (`bad-handling-id`). For a version `1.1.0`
  recipe it also requires the authored `provenance.source_contract` to be
  exactly `roadstorm.handling_config.1.1.0`, so the future bake manifest claim
  agrees with the accepted source: null or absent is `source-contract-missing`
  and any other value is `source-contract-mismatch`, both reported at
  `provenance.source_contract`. A `1.0.0` recipe is always
  refused here, naming all five `handling.<field>` paths.

`motor-ready` is a necessary gate, not a complete typed bake. Passing it means
the recipe can supply the typed motor inputs and the identity preflight; it
does not run the engine, does not write a `.tres`, does not evaluate the rest
of `HandlingDefinition` or `CarDefinition`, and does not produce a bake
manifest. The baker remains a separate gate.

Version dispatch accepts exactly `1.0.0` and `1.1.0`; any other value is
refused. Versions are never migrated.

## Numbers: the source decimal to binary64 boundary

The boundary is defined in one place, `to_binary64` in the checker:

* JSON numbers with a fraction or exponent are parsed as `decimal.Decimal`, so
  the authored literal survives into validation. Integer literals stay Python
  `int`, which keeps integer and floating syntax distinct in bounds and in the
  canonical hash.
* Every integer literal must also be exactly representable as binary64:
  `int(float(value)) == value`. A 309-digit in-range integer such as `10**308`
  converts to a finite float but not back to itself, so it is refused as
  `number-not-representable`; a 91-digit power of two such as `2**300` converts
  exactly and is accepted. Without this rule the mapper would silently lose
  source precision.
* Every declared bound is compared against the exact decimal value, never
  against a pre-rounded float. `reverse_trigger_speed_m_s` of
  `1.00000000000000001` is therefore above the maximum of `1`, even though it
  would round to `1.0`.
* A literal is refused at its own path when it has no binary64 value the source
  text can be recovered from:
  * `non-finite-number` when it is out of binary64 range, for example `1e999`
    or an integer beyond roughly `1.8e308` (about 309 digits). JSON has no
    infinity, and a reader that parses numbers as floats would see `INF`.
  * `number-not-representable` when the literal is not round-trip stable, that
    is, it is neither the shortest decimal of its binary64 value nor that value
    written out exactly. `1.00000000000000001` rounds to `1.0` and `1e-400`
    rounds to `0.0`; baking either would silently change the authored value.
  * Ordinary decimals such as `0.1`, `0.3`, `1e-07` and `1e-300` are stable and
    accepted.
* `to_binary64` is the only place a parsed decimal becomes a Python `float`,
  and it is used for hashing and for anything a consumer reads out of a loaded
  document. Bound comparisons happen before it, in exact decimal arithmetic.
* Acceleration-curve ordering in `motor-ready` mode compares the binary64
  values, matching the mapper, while schema mode keeps the historical
  shape-only acceptance.

These checks run over the whole document, including the open `presentation`
subtree, before any semantic check and before hashing. An escaped lone
surrogate in any key or string is refused the same way (`unpaired-surrogate`),
because such a string cannot be encoded as UTF-8; a paired escape such as
`\ud83d\ude00` is combined by the JSON parser and accepted.

## Boundary robustness

Documents nest at most 200 containers (`MAX_NESTING_DEPTH`). The depth gate
runs before any recursive scan, canonicalization or hashing, so deeper input
is refused with `nesting-too-deep` and cannot exhaust the interpreter stack.
Parse-time boundary defects are reported the same way: a `Decimal` exponent
the decimal machinery cannot construct is `invalid-number`, and a document the
parser cannot materialize is `nesting-too-deep`. The CLI prints findings and
exits 1; none of these cases produces a traceback.

## Canonical `content_hash`

`content_hash` is SHA-256 over the canonical JSON of the document with the
`content_hash` member removed. Canonical JSON is recursively sorted keys,
compact separators, UTF-8 text, non-ASCII left unescaped. Number serialization
is CPython's: an integer literal keeps integer syntax and every other number is
written as `repr` of its binary64 value. Therefore `30` and `30.0` hash
differently, while `100.0` and `1e2` agree, and two literals that round to the
same binary64 value hash identically. Whitespace and member order never change
the hash.

The canonicalizer never emits `NaN` or `Infinity`: `canonical_json` raises
`CanonicalizationError` instead, and `_validate_content_hash` reports
`content-hash-uncomputable`. The hash rule is tied to the Python tool; a
baker written in another language has to reproduce CPython's number formatting
or always hash with this tool.

## Null and `unknowns` paths

A `null` in a closed physical subtree means "undetermined" and must be paired
with an `unknowns` entry whose `path` names it exactly; a declared ancestor path
may cover its own children (`handling.surfaces` covers
`handling.surfaces[0].notes`). The rule is enforced in both directions: an
unpaired null is `unlisted-null`, an entry that does not resolve is
`unresolved-unknown`, and an entry that resolves to a determined value is
`resolved-but-unknown`.

The open `presentation` subtree is exempt. It is cosmetic
(`additionalProperties: true`; "presentation never changes contact or
handling"), its keys may contain dots or hyphens, and its nested nulls are not
undetermined physical data, so they are never collected and never require an
`unknowns` entry. The five `1.1.0` handling inputs and every closed physical
subtree keep exact-path pairing.

Keys are collected with a segment rule that keeps paths unambiguous: a plain
`[a-z_][a-z0-9_]*` key is dotted, and anything else is written as a bracketed
quoted segment such as `presentation["paint.color"]`. No `unknowns` path can
spell a bracketed segment, so a literal dotted key can never be mistaken for a
nested member, and an ancestor path can never falsely explain it.

The path grammar is applied as a whole-string match, so a trailing line feed is
reported as `bad-unknown-path` instead of reaching the resolver. Array-index
segments are bounded in digit count (nine) and range-checked before integer
conversion, so an over-long index such as 4,400 digits is also a structured
`bad-unknown-path` finding rather than an exception.

## What it checks

Required members, closed objects (`additionalProperties: false`), types,
ranges, the five added `1.1.0` fields, the reverse cross-field rule, the
null/`unknowns` honesty rule in both directions, strict JSON parsing (duplicate
members and `Infinity`/`NaN` literals rejected), whole-string unknowns paths
with bounded indices, number representability, the nesting-depth limit and
UTF-8 encodability, the canonical `content_hash`, and the motor-ready
`provenance.source_contract` agreement for version `1.1.0`.

## Deliberate limitations

* Standard library only. It does not run the engine, execute a recipe or check
  physics outcomes.
* It implements these two contracts in plain Python, not the full JSON Schema
  draft 2020-12 vocabulary, and it evaluates no JSON Schema document at
  runtime. The schema documents remain the text contracts. Finiteness, the
  null/`unknowns` pairing and the reverse cross-field rule are semantic checks
  the schema cannot fully express, so they live here as well as (where
  expressible) in the schema.
* `motor-ready` is a necessary gate, not a complete typed bake (see Modes).
* It cannot make unknown facts known. Missing or null values are reported,
  never filled in and never guessed.
* `provenance.source_contract` keeps its historical optional meaning in
  `schema` mode, including honest null drafts. In `motor-ready` mode a
  `1.1.0` recipe must name the exact versioned token
  `roadstorm.handling_config.1.1.0`; null/absent and every other value are
  refused at `provenance.source_contract`. This is a necessary consistency
  gate only: the shared provenance vocabulary, producer-side recording and
  rights review remain M0.3 work.

Original project code under the Unlicense.
