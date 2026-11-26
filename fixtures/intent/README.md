# Roadstorm tactical intent contract (M0.9)

Versioned, machine-readable contract for the `TacticalIntent` that a Classic
planner or a Roadstormer learned policy produces and the shared safety layer
and path follower consume, plus fixtures and a standard-library validator.

Ownership: `schemas/intent/**` and `fixtures/intent/**` (PLAN.md M0.9, job
8cfeb70f-e5b3-4cac-8b4c-83a933d0970b). Nothing outside these two directories
is owned or edited here; the partial `schemas/*.json` files and other
workers' schemas are untouched.

Sources of truth for every field, bound and rule below:
[docs/OPPONENT_AI.md](../../docs/OPPONENT_AI.md) ("Architecture", "Shared
schema version 1", "Training approach", "Implementation and acceptance"),
[docs/TECHNICAL_DESIGN.md](../../docs/TECHNICAL_DESIGN.md) ("Content
contracts", row `AIObservation/TacticalIntent`), and
[docs/BENCHMARKS.md](../../docs/BENCHMARKS.md) ("AI metrics").

## What is defined

`schemas/intent/tactical_intent.schema.json` — the record contract
(`schema_version` 1.0.0, `intent_layout_revision` `tactical_intent_v1`):

| Area | Ratified semantics |
| --- | --- |
| Producer | `classic_planner`, `cloning_only_policy` or `learned_policy`, each with a recorded `producer_revision`; all three emit this same contract (required from M4.2). `cloning_only_policy` is the behavioral-cloning-only Roadstormer producer that OPPONENT_AI.md ("Training approach") and docs/BENCHMARKS.md ("Tactical comparison") require to be evaluated separately from the PPO-trained policy; it is the same driver kind `schemas/scenario/scenario.schema.json`'s participant enum already names, so the intent and scenario slices now agree on the producer vocabulary and the two producers stay distinguishable by `producer_revision`. |
| Inputs | Explicit `difficulty` (rookie/racer/expert) and `style` (surge/switch/none; `none` = Classic-only style inputs 0/0), route frame (forward tangent, right lateral, up road normal; positive offset right). |
| Lateral | `lateral_target_norm` in [-1,1]; decode `target x ((road_width - car_width)/2 - 0.5 m)` bounded to the legal corridor; proposed normalized value and decoded/executed meters recorded separately. |
| Pace | `pace_norm` in [0,1] = `(a+1)/2` mapped into the difficulty's desired speed-profile interval before safety counting. |
| Commitment | `commitment_raw` in [-1,1]; below -1/3 `follow`, -1/3 through +1/3 `wait`, above +1/3 `commit_pass`; minimum commitment 0.4 s, interrupted by hazards. |
| Drift | `drift_raw` in [-1,1]; above +0.25 `drift`, below -0.25 `grip`, `retain` between; the follower still enforces legal entry conditions. |
| Age | 5 Hz decisions = 12-tick period at 60 Hz; `intent_age_ticks = sampled_tick - generated_tick`; 12-tick staleness threshold; `traffic_age_ticks` 18/12/7 by difficulty, inherited from the delayed traffic snapshot of the source observation. |
| Interpolation | Required, window 0.2 s (the sampling period), to prevent jitter and lane weaving. |
| Safety | `max_deferral_ticks` 0 — a held intent never suspends hazard checks; corrections recorded per field with the four constraint categories (road, passing_room, contact_rule, physical_capability), proposed/applied values and the BENCHMARKS materiality flag. |
| Reset | `reset_generation` counter, `history_valid` mask (0 after a reset, mirroring the observation's zero/masked defaults), `post_reset_defaults_applied` and the reverted field list. |
| Constants | All numeric semantics live in the schema's `$defs.constants`; the validator reads them from there instead of restating them. |
| Observation source | `source_observation_id` names a record of the accepted shared observation contract, `schemas/observation/observation_record.schema.json` (field `observation_id`); `intent_layout_revision` is parallel to that schema's `observation_layout_revision`. |
| Metrics | The fixture's `comparison.metrics` use the shared `schemas/common.schema.json` `acceptance_metric` vocabulary; a fixture metric never claims status `measured`, and the bound members must match the comparator (threshold → `value`, range/ratio_range → ordered `value_min`/`value_max`, report → no bound). |

`schemas/intent/intent_fixture.schema.json` — the fixture wrapper
(`schema_version` 1.0.0): one scenario (60 Hz tick, road/car geometry,
difficulty, style, producer), intent records at the 5 Hz cadence, declared
expectations, documented initial acceptance metrics, `unknowns`, canonical
`content_hash` and `provenance` — the same conventions as
`schemas/handling/handling_fixture.schema.json`.

## What is deliberately NOT defined (unratified)

The contract is the planner → safety → follower interface only. It defines
no model, weights, export, inference or training interface, and no fixture
claims a working AI exists. Each unratified item is a `null` (when it has a
field) plus an `unknowns` entry, or an `unknowns` entry alone:

- Per-difficulty desired speed-profile intervals and therefore decoded
  `target_speed_m_s` (tuned at M4.3).
- The length of the "short commitment window" (M4.2).
- The interpolation curve (M4.2).
- Required behavior for a stale intent (a missed 5 Hz update) (M4.2).
- Exact post-reset default intent values; only zero/masked history defaults
  are specified (M4.2).
- Producer revisions (placeholders until M4.2/M4B.1 exist).
- How a safe fallback intent is represented when weights are invalid or
  missing (the OPPONENT_AI fault path); not represented in this contract.
- Whether a separate pass-side field is needed, or the lateral target alone
  carries side as the action table implies.

## Fixtures

- `positive/fixture.intent.surge_commit_pass.json` — two 5 Hz intents, a
  learned_policy producer exercising a `commit_pass` with one material
  `passing_room` correction (status `example`: exercises the producer kind
  without claiming a model exists). Its 12 m section matches the referenced
  observation `obs.t000996.ai_surge_1` (12 m road width at all three
  lookaheads, usable half-width 6.0 m).
- `positive/fixture.intent.classic_wait_hold.json` — Classic planner
  `wait`/`grip` intents, no corrections, Rookie 18-tick traffic age. Its 10 m
  section matches the referenced observation `obs.t000500.ai_classic_2`
  (a clear 10 m straight).
- `positive/fixture.intent.post_reset_defaults.json` — post-reset intent
  with masked history and Expert 7-tick traffic age; `reset_generation` 2
  matches the referenced observation `obs.t000800.ai_classic_4`, and its 10 m
  section matches that observation's 10 m road width.
- `negative/*.json` — 24 deliberately invalid fixtures, each derived from a
  valid base with exactly one defect (schema `const`/`enum`/`maximum`/
  `required`/`additionalProperties` violations and semantic violations:
  unknown pairing, content hash, decode mismatch, threshold mislabel,
  difficulty age, cadence, age arithmetic, reset mask, materiality flag,
  context disagreement, measured metric status, and comparator/bound shape:
  report carrying a threshold, range carrying a point value, inverted range
  bounds, threshold missing `value`). Each has a `.expected.json` sidecar
  listing the exact failure set; the validator requires an exact match, so a
  rejection cannot silently disappear or grow. The copies were refreshed
  against the current positive bases on 2026-11-27: the 17 copies of the
  classic-wait-hold base no longer carry the pre-remediation 9.5 m section
  geometry, and the `bad_reset_mask` copy no longer carries the
  pre-remediation 12 m section geometry.

## Observation references that are deliberately not verifiable

The first record of each multi-record positive fixture references an
observation record that `fixtures/observation/` ships, so its participant,
tick, difficulty, style, traffic age, reset generation and road width all
agree with the observation slice. The **second** record of
`fixture.intent.classic_wait_hold.json` (`obs.t000512.ai_classic_2`) and of
`fixture.intent.surge_commit_pass.json` (`obs.t001008.ai_surge_1`) references
an observation record that is **not** shipped as an observation fixture. Those
two IDs follow the observation contract's `obs.t<tick>.<participant>`
convention and are illustrative only; each fixture declares this in its
description rather than implying a verifiable pairing, and the shipped
`obs.t001008.ai_surge_2` (a different participant) must not be read as the
surge fixture's second source observation. Resolving the gap would mean
authoring two further illustrative observation records, which this slice does
not do; the limitation is recorded instead of being papered over.

## Validation

Standard library only (Python 3); no installs, no network, no engine.

```sh
fixtures/intent/run_tests.sh              # unittest suite, then the validator
python3 -m unittest discover -s fixtures/intent/tests -t fixtures/intent
python3 fixtures/intent/validate_intent_contract.py            # validate all
python3 fixtures/intent/validate_intent_contract.py --update-hashes
```

The validator implements a small JSON Schema 2020-12 subset evaluator
(`$ref`, `type`, `const`, `enum`, `required`, `additionalProperties`,
`properties`, `items`, `minItems`/`maxItems`, `minimum`/`maximum`/
`exclusiveMinimum`, `pattern`, `minLength`) with `$ref` resolution into
`schemas/common.schema.json` and between the two intent schemas, rejects
duplicate JSON members, recomputes the canonical content hash, and runs the
semantic checks named in `intent_fixture.schema.json`'s expectation enum
(decode consistency, label thresholds, sampling cadence, age arithmetic,
difficulty age, context agreement, reset mask, safety deferral, correction
materiality, minimum commitment, metric status honesty, metric shape,
unknown pairing). Schema failures short-circuit semantic checks so each
negative fixture pins exactly one rejection.

The two metric checks cover rules the subset evaluator cannot express:
`schemas/intent/intent_fixture.schema.json` forbids status `measured` in a
fixture file, and `schemas/common.schema.json`'s `acceptance_metric`
`allOf` clauses tie the bound members to the comparator. Their check ids and
failure paths match the scenario slice's `metric_status_honesty` and
`metric_shape` checks; the comparator/status vocabulary itself is read from
`schemas/common.schema.json` rather than restated, so it cannot drift from
the handling and scenario slices. An expectation may address a single metric
(`comparison.metrics.0`) or the whole array (`comparison.metrics`).

Exit codes: 0 = all fixtures valid / all negatives rejected as declared;
1 = failures; 2 = unreadable input or bad command line.

## Remaining decisions for the ratifying milestones

1. M4.2: commitment window length, interpolation curve, stale-intent
   behavior, post-reset default intent values, fallback-intent
   representation.
2. M4.3: per-difficulty desired speed-profile intervals (unblocks decoded
   target speeds).
3. M4B.1: producer revisions for the Classic planner, the
   cloning-only policy and the learned policy; the learned-policy export
   interface stays outside this contract.
4. Whether intent records should also carry a pass-side label (currently
   carried by the lateral target, per the action table).

## Cross-slice notes for the integrator (2026-11-27)

- `tactical_intent.schema.json`'s `producer.kind` and
  `intent_fixture.schema.json`'s `context.producer_kind` now include
  `cloning_only_policy`, matching `scenario.schema.json`'s participant driver
  enum; no fixture instantiates it yet.
- The `producer.kind` enum is read from the schema by the mini evaluator, so
  the added value needs no validator change; a fixture that used it would only
  need `context.producer_kind` to agree.
- The observation references of the second records are declared-but-unverifiable
  (see the section above); this is recorded rather than fixed by authoring new
  observation fixtures.
