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
