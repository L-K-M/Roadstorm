# Roadstorm shared AI observation contract (M0.9)

Versioned, machine-readable contract for the `AIObservation` that the
ObservationBuilder assembles and a Classic planner or a Roadstormer learned
policy consumes through the shared observation/intent/follower hierarchy, plus
fixtures and a standard-library validator.

Ownership: `schemas/observation/**` and `fixtures/observation/**` (PLAN.md
M0.9, job 8667d71d-5817-4955-b069-aed859c8d8f8). Nothing outside these two
directories is owned or edited here; the partial, unaccepted
`schemas/ai_observation.schema.json`, the other schema slices
(`schemas/handling/`, `schemas/intent/`, `schemas/scenario/`,
`schemas/*.json`) and all other workers' files are untouched.

Sources of truth for every field, index, mask, coefficient and rule below:
[docs/OPPONENT_AI.md](../../docs/OPPONENT_AI.md) ("Architecture", "Shared
schema version 1", "Training approach", "Implementation and acceptance"),
[docs/TECHNICAL_DESIGN.md](../../docs/TECHNICAL_DESIGN.md) ("Content
contracts", row `AIObservation/TacticalIntent`; "Runtime ownership",
`ObservationBuilder`), and [docs/BENCHMARKS.md](../../docs/BENCHMARKS.md)
("AI metrics", "Numerical comparisons", "Performance and compute evidence").

## Relationship to the partial `schemas/ai_observation.schema.json`

That top-level file is an earlier, incomplete, unaccepted flat schema. This
slice is a **distinct, complete** contract and does not supersede or edit it:
different directory and filenames (`schemas/observation/observation_record.schema.json`
and `observation_fixture.schema.json`), an explicit `schema_version`/`observation_layout_revision`,
a full machine-readable 64-feature layout, explicit `difficulty`/`style` inputs
with one-hot checks, `raw_inputs` normalization probes, reset-generation and
fallback semantics, and a fixture wrapper with executable expectations. The
coordinator decides whether the partial file is retired once this slice is
reviewed; that decision is out of scope here.

## What is defined

`schemas/observation/observation_record.schema.json` — the record contract
(`schema_version` 1.0.0, `observation_layout_revision` `ai_shared_v1`):

| Area | Ratified semantics |
| --- | --- |
| Shape | Fixed 64-element float32 vector, finite, clipped to [-1,1]; booleans/one-hots/flags 0/1; occupancy fractions clipped [0,1]. |
| Order | Seven ordered groups, given as machine-readable data in `feature_layout`: ego 0-11, road_ahead 12-26, neighbor 27-50, history 51-56, difficulty_one_hot 57-59, style_one_hot 60-61, occupancy 62-63. Each of the 64 entries names its group, kind, snapshot source and normalization. |
| Road frame | Forward tangent, right lateral, up road normal; positive lane offset right. |
| Snapshot split | Ego/road and the emergency guard are current as of `sampled_tick`; neighbor traffic, corridor occupancy and traffic-derived pass/contact history use the delayed snapshot at `traffic_snapshot_tick`, so no current-position leaks around the reaction setting. |
| Neighbors | Up to four candidates within 70 m ahead / 35 m behind on the valid route neighborhood, sorted by absolute gap then stable participant ID; absent slots are fully zero including the presence mask; present slots fill the slots in order and are in ascending absolute-gap order. |
| Declared kinds and ranges | Every feature_vector entry must satisfy its `feature_layout` entry: `boolean`/`one_hot` are 0/1, `signed_enum` is -1/0/1, and every other kind must sit inside its declared `range` (e.g. `[0,1]` for widths, grip, cooldowns, occupancy fractions). Enforced by the `feature_declared_ranges` check. |
| Neighbor window | A present neighbor's route gap must lie inside `$defs.constants`' 70 m ahead / 35 m behind window, enforced by the `neighbor_window` check. When `raw_inputs` pins the pre-normalization gap it is authoritative; a gap decoded from the clipped feature value alone is ambiguous only at the +70 m saturation edge (see below). |
| Finite numbers | NaN, `Infinity` and `-Infinity` are not valid JSON and are rejected at parse time; the evaluator also refuses non-finite numbers for in-memory documents. |
| Reset defaults | `post_reset_defaults_applied` true requires `masks.history_valid` 0, `reset_generation` at least 1, and a non-empty `defaults_applied` whose entries all name `feature_layout` features or groups. |
| Fixture metrics | A `comparison.metrics` entry with status `measured` is rejected: fixtures carry targets and requirements, never measured outcomes. |
| Null/unknowns pairing | A null-or-absent `occupancy_encounter_gap_m` requires a matching `unknowns` entry; a determined value must not have one. Omitting the optional field fails gracefully (previously a validator crash). |
| Age | `traffic_age_ticks = sampled_tick - traffic_snapshot_tick` and equals the difficulty default: Rookie 18, Racer 12, Expert 7 ticks at 60 Hz. |
| History | Own executed lane targets retain recorded normalized values (not raw meters); recent-contact and traffic-derived pass history cover the prior 2 s ending at the delayed timestamp; reset masks history to zero/default (`masks.history_valid` 0). |
| Normalization | Every divisor/multiplier lives in `$defs.constants.normalization_scales` (single source of truth); `top_speed_m_s` and `usable_half_width_m` are per-car/per-section and come from the fixture context. `raw_inputs` pins pre-normalization values the validator recomputes. |
| Fallback | Unknown schema, zero usable width or nonfinite input produces a safe diagnostic fallback (`fallback.active`, `reason`, `defaults_applied`); the validator requires a zero usable width to set it. |
| Constants | All numeric semantics live in the schema's `$defs.constants` and the `feature_layout` data; the validator reads them instead of restating them. |

`schemas/observation/observation_fixture.schema.json` — the fixture wrapper
(`schema_version` 1.0.0): one scenario (60 Hz tick, participant, difficulty,
style, per-car top speed, per-section usable half-width, observation-builder
revision), observation records, declared expectations, documented initial
acceptance metrics, `unknowns`, canonical `content_hash` and `provenance` —
the same conventions as `schemas/intent/intent_fixture.schema.json` and
`schemas/handling/handling_fixture.schema.json`.

## What is deliberately NOT defined (unratified)

The contract is the sensor → policy input interface only. It defines no model,
weights, export, inference or training interface, and no fixture claims a
working AI or a frozen model exists. Each unratified item is a `null` (when it
has a field) plus an `unknowns` entry, or an `unknowns` entry alone:

- The "planned encounter" route gap at which corridor occupancy (62-63) is
  evaluated (`occupancy_encounter_gap_m`, M4.2).
- The exact safe diagnostic fallback vector contents (zeros for sensor
  features here are an authored placeholder, M4.2).
- The exact masked history default values and the post-reset ego defaults
  (M4.2).
- The current-vs-delayed split *inside* the history group: own lane targets
  (51,52) and own forward distance (55) are treated as current; traffic-derived
  pass side (53), attempt age (54) and recent contact (56) as delayed. This is
  an interpretation of OPPONENT_AI.md, to confirm when demonstrations are
  collected (M4.2/M4B).
- Whether `history_valid: 0` without any reset is permitted, and whether a
  safe fallback must additionally bump `reset_generation`. The record schema
  describes 0 as "masked to zero/default after a reset", but the shipped
  fallback fixture legitimately carries 0 with `reset_generation: 0` and
  `post_reset_defaults_applied: false`, and OPPONENT_AI.md never ties the two
  together. The validator therefore accepts 0-without-reset (one-way
  implication only) and records the ambiguity in the fallback fixture's
  `unknowns` instead of inventing a stricter rule.
- Float32 representability of feature literals: finiteness is enforced, but a
  JSON literal such as 0.1234567890123 that is not exactly a float32 is not
  rejected; the documents promise finite float32 values without fixing a
  rounding rule, so the validator does not invent one.
- `history_recent_window_s` (2.0) describes a producer-side window ending at
  the delayed traffic timestamp; no fixture field expresses it, so it is
  documented here rather than enforced.
- A non-default `traffic_age_ticks` (context flag
  `traffic_age_is_difficulty_default: false`) "must be explained in the
  description". That is a prose requirement the validator cannot check; it
  remains a human responsibility, and the record schema's description now
  scopes the difficulty-default equality to the flag.
- The absolute-gap tiebreak "then stable participant ID": participant IDs are
  not part of the vector, so two present neighbors with equal |gap| cannot be
  distinguished and are accepted.
- A neighbor beyond +70 m ahead is indistinguishable from exactly 70 m once
  clipped to 1.0; the window check rejects it only when `raw_inputs` pins the
  pre-normalization gap.
- Observation-builder revision (placeholder until M4.2).
- Per-car top speeds and per-section usable half-widths (authored illustrative
  values; handling parameters fixed at M1).

## Fixtures

- `positive/fixture.observation.surge_full_vector.json` — full 64-feature
  observation, Racer/Surge, two ordered neighbors, valid history, occupancy,
  twelve `raw_inputs` normalization probes (status `example`: exercises the
  learned-style input without claiming a model exists).
- `positive/fixture.observation.classic_rookie_clear.json` — Classic-only
  (style `none`, both style one-hots 0/0), Rookie 18-tick age, clear road with
  all neighbor slots absent and zeroed.
- `positive/fixture.observation.post_reset_masked.json` — post-reset
  observation with `history_valid` 0 and every history feature masked, Expert
  7-tick age, one neighbor still drawn from the delayed snapshot.
- `positive/fixture.observation.fallback_zero_width.json` — safe diagnostic
  fallback on zero usable width; sensor features zeroed, explicit
  difficulty/style one-hots and tick bookkeeping still correct.
- `negative/*.json` — 28 deliberately invalid fixtures, each derived from the
  full-vector base with exactly one defect. Seven pin schema rejections
  (`const`, `minItems`, `maximum`, `required`, `additionalProperties`,
  `pattern` via `$ref`) and thirteen pin semantic rejections covering every
  implemented check (context agreement, difficulty/style one-hot, neighbor
  presence/absent-zeroing/mask-agreement/ordering, traffic-age arithmetic,
  difficulty age, history masking, normalization consistency, fallback
  defaults, unknown pairing) plus the canonical content hash. Each has a
  `.expected.json` sidecar listing the exact failure set; the validator
  requires an exact match, so a rejection cannot silently disappear or grow.
  Eight further regression fixtures (job
  74b35657-1cb2-47c1-8753-ed569921f41f) pin the remediated audit findings:
  `bad_nonfinite_feature` (NaN literal is not valid JSON),
  `bad_feature_declared_range` (occupancy fraction outside its declared
  `[0,1]`), `bad_neighbor_window` (neighbor 42 m behind, outside the 35 m
  window), `bad_raw_inputs_type` (schema-form `additionalProperties`),
  `bad_reset_defaults_empty` and `bad_reset_defaults_name` (reset defaults
  list), `bad_measured_metric` (status `measured` in a fixture file), and
  `bad_missing_optional_field` (omitted optional field fails gracefully
  instead of crashing).
- `positive/fixture.observation.regression_neighbor_window.json` — regression
  fixture pinning the inclusive window edges (one neighbor exactly 35 m behind,
  one exactly 70 m ahead, both pinned by `raw_inputs`) and declaring
  expectations for the `neighbor_window` and `feature_declared_ranges` checks.

## Validation

Standard library only (Python 3); no installs, no network, no engine.

```sh
fixtures/observation/run_tests.sh              # unittest suite, then the validator
python3 -m unittest discover -s fixtures/observation/tests -t fixtures/observation
python3 fixtures/observation/validate_observation_contract.py            # validate all
python3 fixtures/observation/validate_observation_contract.py --update-hashes
```

The validator implements a small JSON Schema 2020-12 subset evaluator (`$ref`,
`type`, `const`, `enum`, `required`, `additionalProperties` (both `false` and
the subschema form), `properties`, `items`, `minItems`/`maxItems`,
`minimum`/`maximum`/`exclusiveMinimum`, `pattern`, `minLength`) with `$ref`
resolution into `schemas/common.schema.json` and between the two observation
schemas, refuses non-finite numbers (NaN/Infinity are not valid JSON),
rejects duplicate JSON members, recomputes the canonical content hash, and
runs the semantic checks named in
`observation_fixture.schema.json`'s expectation enum (plus the fixture-level
`comparison_metrics` check). Schema failures short-circuit semantic checks so
each negative fixture pins exactly one rejection. The ordered feature layout,
the 70/35 m neighbor window and all constants are read from the record
schema, not restated in the validator (the per-slot neighbor feature count is
derived from the layout's neighbor group and `neighbor_slot_count`).

Exit codes: 0 = all fixtures valid / all negatives rejected as declared;
1 = failures; 2 = unreadable input or bad command line.

## Remaining decisions for the ratifying milestones

1. M4.2: planned-encounter occupancy gap, safe-fallback vector contents,
   masked-history and post-reset ego defaults, observation-builder revision,
   confirmation of the history-group current/delayed split, and whether
   `history_valid: 0` without a reset (safe fallback) must also bump
   `reset_generation`.
2. M4B.1: the learned-policy export/inference interface stays outside this
   contract; only the observation/intent/follower input shape is ratified here.
3. Coordinator: whether to retire the partial `schemas/ai_observation.schema.json`
   in favor of this slice. Resolved on 2026-11-27 by the M0.9 integration:
   the partial file keeps its place in the tree but declares its own
   `feature_layout_revision` `ai_shared_partial_v0` instead of the ratified
   `ai_shared_v1`, so the two revision namespaces can no longer collide.
   Whether the file is deleted outright is still the coordinator's call.

## Cross-slice issues for the coordinator (out of scope here)

Reported by the observation contract audit (job
bec6cc5e-d448-432c-8979-0b7390f5c063), not fixed in this slice because the
files belong to other owners:

1. `schemas/intent/tactical_intent.schema.json` cites the partial, superseded
   `schemas/ai_observation.schema.json` (and its `feature_layout_revision`
   field) in three descriptions; the completed contract is
   `schemas/observation/observation_record.schema.json` with
   `observation_layout_revision`. **Fixed 2026-11-27**: the intent schema now
   cites the completed contract.
2. Cross-fixture scenario mismatches for the same participant+tick:
   `fixtures/intent/positive/fixture.intent.classic_wait_hold.json` declares
   `road_width_m: 9.5` where the referenced observation
   (`fixture.observation.classic_rookie_clear.json`) encodes 10 m, and
   `fixtures/intent/positive/fixture.intent.post_reset_defaults.json` has
   `reset_generation: 3` where the referenced observation
   (`fixture.observation.post_reset_masked.json`) has `reset_generation: 2`.
   **Fixed 2026-11-27** (10.0 m and `reset_generation` 2), together with the
   stale 9.5 m/12 m geometry that 18 negative intent copies still carried.
3. `common.schema.json`'s `acceptance_metric.status` enum admits `measured`,
   which both the observation and scenario fixture contracts declare invalid
   in fixture files; the observation slice enforces this semantically, and the
   shared vocabulary decision belongs to its owner.
4. The 5 Hz decision phase (tick mod 12) is unratified; shipped pairs agree
   with each other but no check can express a phase.

### Fixed inside this slice on 2026-11-27 (road-width consistency)

`fixture.observation.surge_full_vector.json` described a "12 m section" while
encoding road widths of 11/11/10 m and a 5.0 m usable half-width, and the
intent fixture that references it declares `road_width_m: 12.0`. The fixture
now encodes 12 m at all three lookaheads with a 6.0 m usable half-width (the
same convention as `fixture.observation.classic_rookie_clear.json`: 10 m road,
5.0 m usable half-width), the pinned `raw_inputs` probe for feature 14 is 12 m,
and the ego lane-offset probe stays 1.5 m (1.5/6.0 = 0.25). Nothing else in the
vector changed.

The second records of `fixture.intent.classic_wait_hold.json` and
`fixture.intent.surge_commit_pass.json` still reference observation records
that this slice does not ship (`obs.t000512.ai_classic_2`,
`obs.t001008.ai_surge_1`); the intent README records that limitation and each
fixture declares it in its description.
