# Roadstorm observation schemas (M0.9)

Two versioned, machine-readable contracts for the shared `AIObservation`,
defined at M0.9 from docs/OPPONENT_AI.md, docs/TECHNICAL_DESIGN.md and
docs/BENCHMARKS.md (PLAN.md M0.9, job 8667d71d-5817-4955-b069-aed859c8d8f8):

- `observation_record.schema.json` — the record contract: the fixed ordered
  64-feature vector (as machine-readable `feature_layout` data), road frame,
  current-vs-delayed snapshot split, masks, traffic-age and reset semantics,
  the `$defs.constants` normalization coefficients, and the safe-fallback
  fields. `observation_layout_revision` is `ai_shared_v1`.
- `observation_fixture.schema.json` — the fixture wrapper: one scenario plus
  records, declared expectations, documented targets, `unknowns`, canonical
  `content_hash` and `provenance`.

M0.9 checkpoint repairs (2026-11-27, job
0bc309a1-9344-455f-8dca-93c23a7edc64, from the two independent schema reviews):

- **Normalization revision binding.** `$defs.constants` now declares
  `coefficients_revision` `ai_shared_v1_norm`, and
  `normalization.coefficients_revision` `$ref`s that member. The revision name
  and the coefficient set cannot drift apart: the validator recomputes
  normalizations with these scales only for records declaring this revision,
  so a record naming any other revision (e.g. `foreign_v99`) is rejected at
  the schema layer instead of being silently checked against - or trained
  with - the wrong coefficients. A coefficient change is a new revision string
  plus a new `schema_version`, recorded as a decision.
- **Canonical raw-input keys.** `raw_inputs` keys must be canonical decimal
  index strings naming each index at most once. The validator's
  `raw_input_keys` check rejects a non-canonical key (`"027"`, `" 27"`,
  `"+27"`, `"27.0"`, `"fast"`) and two keys that resolve to the same index, so
  an aliased key can no longer satisfy the normalization check while the
  window/eligibility check falls back to the clipped feature value.
- **Metric vocabulary parity.** The fixture schema's expectation enum admits
  `metric_status_honesty` and `metric_shape` (paths under `comparison`), and
  the validator implements both, reading the comparator/status vocabulary from
  `../common.schema.json`. The observation slice now enforces the same
  `acceptance_metric` `allOf` rules as the handling, intent and scenario
  slices, so a malformed acceptance target is rejected by both the semantic
  layer and (via the shared schema) any draft 2020-12 validator.
- **Diagnostic neighbor IDs.** The record contract gained the optional
  `neighbor_ids` array (stable participant IDs, one per present neighbor slot,
  in slot order; never part of the feature vector). When present, the
  validator enforces the list length against the present-slot count and the
  OPPONENT_AI.md tie order (equal absolute route gaps require ascending
  stable IDs). A record that omits the list keeps the documented limitation
  that an equal-gap tie cannot be verified.
- **Blocking unknown: the usable-half-width convention.** OPPONENT_AI.md
  normalizes feature 4 by the "usable half-width" and divides history lane
  targets 51-52 "by its then-usable half-width" without defining the
  quantity, while its action-0 decode derives the narrower legal corridor
  `(road_width - car_width)/2 - 0.5 m`. The sources do not decide which
  quantity "usable half-width" names, so this slice does not decide it: the
  fixtures author `road_width/2` as an illustrative value and every fixture
  carrying the value declares the ambiguity as a blocking `unknowns` entry
  (`context.usable_half_width_m`, blocking, until M4.2). The convention must
  be ratified before demonstrations are collected; ratifying it changes the
  index-4 and 51-52 normalization and is a cross-slice decision with the
  intent contract.

**Serialization note (deliberately stricter than draft 2020-12).** The slice's
JSON Schema subset types a JSON number with a fractional part (e.g.
`500.0`) as `"number"`, not `"integer"`, so an integral value written with a
decimal point is rejected where Ajv would accept it. This is the stricter of
the two options the M0.9 reviews allowed ("align the checker or document the
tighter serialization profile"): no defect passes that Ajv would catch, and
the canonical content hash covers the exact serialization, so `500` and
`500.0` also hash differently. Whether all four slice validators adopt this
stricter profile or align with draft 2020-12 is a cross-slice decision left to
the coordinator; this slice documents rather than changes the rule.

These files are text contracts; they require no working AI implementation and
define no model, weights, export or training interface. They are **distinct**
from the partial, unaccepted top-level `schemas/ai_observation.schema.json`,
which is not superseded or edited here.

**Layout-revision disambiguation (2026-11-27, M0.9 integration).** The partial
top-level file used to declare the same layout revision string
(`ai_shared_v1`) as this record contract, so two different documents claimed
one revision name. `observation_record.schema.json` remains the sole owner of
`ai_shared_v1`; the partial file now declares `ai_shared_partial_v0`, is titled
and described as a superseded draft, and points here. It is retained as the
authoring record of the earlier attempt; deleting it outright remains the
coordinator's decision.

Companion vocabulary lives in `../common.schema.json`. Executable fixtures and
the standard-library validator live in `../../fixtures/observation/`; see the
README there for the full description, fixtures, validation commands and open
decisions.
