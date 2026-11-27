# Roadstorm tactical intent contract (M0.9)

Versioned, machine-readable contract for the `TacticalIntent` that a Classic
planner or a Roadstormer learned policy produces and the shared safety layer
and path follower consume, plus fixtures and a standard-library validator.

Ownership: `schemas/intent/**` and `fixtures/intent/**` (PLAN.md M0.9, job
8cfeb70f-e5b3-4cac-8b4c-83a933d0970b). Nothing outside these two directories
is owned or edited here; the partial `schemas/*.json` files and other
workers' schemas are untouched.

**Revision 1.1.0 (2026-11-27, M0.9 independent schema checkpoint).** Two
independent reviews of the M0.9 draft (`review/implementation/`) required
changes before the M2.7 ratification. This slice took them: `schema_version`
moved from 1.0.0 to 1.1.0 in both intent schemas and in every fixture, as the
record schema's own versioning rule requires for a contract change. The
changes are the proposed/executed split (commitment, drift), the pace interval
and decoded-target rules, nonnegative speed corrections, the 0.4 s commitment
hold with hazard interruption, tick-level and emergency safety telemetry, and
the source-observation linkage. The recorded decision is this section; no
tuning value was invented anywhere.

**Checkpoint follow-up (2026-11-27, job
fb0c61c6-dcc6-4806-9d79-702ac9261178).** Independent cross-contract probes found
three unenforced statements and closed them without changing the record
contract: documents are now strict JSON (`NaN`/`Infinity`/`-Infinity` are
refused at parse time and non-finite numbers in memory fail the evaluator, so
a NaN lateral target or pace-correction value can no longer satisfy
comparisons that are false for NaN); `safety.corrections` may carry only one
entry per corrected field (new `correction_shape` check); and `drift.label
retain` with valid history may not execute `none` (that value is legal only
when the reset masked the history). Four negatives pin the new rejections. The
record schema stays 1.1.0; only the fixture wrapper's expectation vocabulary
gained `correction_shape`, matching how the observation checkpoint added
checks without moving its 1.0.0 revision.

Sources of truth for every field, bound and rule below:
[docs/OPPONENT_AI.md](../../docs/OPPONENT_AI.md) ("Architecture", "Shared
schema version 1", "Training approach", "Implementation and acceptance"),
[docs/TECHNICAL_DESIGN.md](../../docs/TECHNICAL_DESIGN.md) ("Content
contracts", row `AIObservation/TacticalIntent`), and
[docs/BENCHMARKS.md](../../docs/BENCHMARKS.md) ("AI metrics").

## What is defined

`schemas/intent/tactical_intent.schema.json` — the record contract
(`schema_version` 1.1.0, `intent_layout_revision` `tactical_intent_v1`):

| Area | Ratified semantics |
| --- | --- |
| Producer | `classic_planner`, `cloning_only_policy` or `learned_policy`, each with a recorded `producer_revision`; all three emit this same contract (required from M4.2). `cloning_only_policy` is the behavioral-cloning-only Roadstormer producer that OPPONENT_AI.md ("Training approach") and docs/BENCHMARKS.md ("Tactical comparison") require to be evaluated separately from the PPO-trained policy; it is the same driver kind `schemas/scenario/scenario.schema.json`'s participant enum already names, so the intent and scenario slices now agree on the producer vocabulary and the two producers stay distinguishable by `producer_revision`. |
| Inputs | Explicit `difficulty` (rookie/racer/expert) and `style` (surge/switch/none; `none` = Classic-only style inputs 0/0), route frame (forward tangent, right lateral, up road normal; positive offset right). |
| Lateral | `lateral_target_norm` in [-1,1]; decode `target x ((road_width - car_width)/2 - 0.5 m)` bounded to the legal corridor; proposed normalized value and decoded/executed meters recorded separately. |
| Pace | `pace_norm` in [0,1] = `(a+1)/2` mapped into the difficulty's desired speed-profile interval before safety counting. When a record fixes the interval it is ordered (`min <= max`), the decoded `target_speed_m_s` is `min + pace_norm x (max - min)`, and a pace correction's `proposed` is that same pre-safety decode with nonnegative `proposed`/`applied`; the corrected target equals the applied value. |
| Commitment | `commitment_raw` in [-1,1]; below -1/3 `follow`, -1/3 through +1/3 `wait`, above +1/3 `commit_pass`; minimum commitment 0.4 s (24 ticks at 60 Hz), interrupted by hazards. `label` is the proposed threshold decode; `executed_label` and `commit_started_tick` record the executed state, so a commitment held inside its minimum is visible even when the proposal has moved on. |
| Drift | `drift_raw` in [-1,1]; above +0.25 `drift`, below -0.25 `grip`, `retain` between; `executed_preference` resolves `retain` to the preference actually run (`drift`/`grip`, or `none` when masked post-reset history leaves nothing to retain). The follower still enforces legal entry conditions. |
| Age | 5 Hz decisions = 12-tick period at 60 Hz; `intent_age_ticks = sampled_tick - generated_tick`; 12-tick staleness threshold; `traffic_age_ticks` 18/12/7 by difficulty, inherited from the delayed traffic snapshot of the source observation. |
| Interpolation | Required, window 0.2 s (the sampling period), to prevent jitter and lane weaving. |
| Safety | `max_deferral_ticks` 0 — a held intent never suspends hazard checks; corrections recorded per field with the four constraint categories (road, passing_room, contact_rule, physical_capability), proposed/applied values and the BENCHMARKS materiality flag. Tick-level exposure lives in `safety.interventions.ticks` (ascending, distinct 60 Hz ticks inside the intent's hold window `[generated_tick, generated_tick + 12)` at which per-tick safety overrode the intent), and wholesale replacement lives in `safety.emergency` (`substituted`, `kind` in emergency_stop/reset/classic_fallback, `tick`, `persistent`, `reason`). One intent corrected on several ticks counts once by intent identity (BENCHMARKS.md); the tick list is the exposure reported beside that count. |
| Reset | `reset_generation` counter, `history_valid` mask (0 after a reset, mirroring the observation's zero/masked defaults), `post_reset_defaults_applied` and the reverted field list. |
| Constants | All numeric semantics live in the schema's `$defs.constants`; the validator reads them from there instead of restating them. |
| Observation source | `source_observation_id` names a record of the accepted shared observation contract, `schemas/observation/observation_record.schema.json` (field `observation_id`); `intent_layout_revision` is parallel to that schema's `observation_layout_revision`. The validator resolves every reference against the shipped positive observation fixtures and requires agreement (see "Observation references" below); unresolvable IDs must be declared in the fixture's `illustrative_sources`. |
| Metrics | The fixture's `comparison.metrics` use the shared `schemas/common.schema.json` `acceptance_metric` vocabulary; a fixture metric never claims status `measured`, and the bound members must match the comparator (threshold → `value`, range/ratio_range → ordered `value_min`/`value_max`, report → no bound). |

`schemas/intent/intent_fixture.schema.json` — the fixture wrapper
(`schema_version` 1.1.0): one scenario (60 Hz tick, road/car geometry,
difficulty, style, producer), intent records at the 5 Hz cadence, declared
expectations, documented initial acceptance metrics, `unknowns`, the
`illustrative_sources` declarations for references the observation slice does
not ship, canonical `content_hash` and `provenance` — the same conventions as
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
- Whether a record exported at `sampled_tick` inside its hold window must
  truncate `safety.interventions.ticks` (and `safety.emergency.tick`) to the
  ticks observed so far; this contract fixes the window
  `[generated_tick, generated_tick + period_ticks)` and leaves the export
  rule open (unknowns entry `safety.interventions.ticks`, blocking, M4.2).
- The final `safety.emergency.kind` vocabulary; the three kinds map to the
  documented concepts, but OPPONENT_AI.md preregisters intervention
  categories before evaluation (unknowns entry `safety.emergency.kind`,
  blocking, M4.2).

## Fixtures

- `positive/fixture.intent.surge_commit_pass.json` — three 5 Hz intents, a
  learned_policy producer exercising a `commit_pass` with one material
  `passing_room` correction (status `example`: exercises the producer kind
  without claiming a model exists). The second record proposes `wait` while
  the executed `commit_pass` is held inside the 0.4 s minimum, and the third
  releases the commitment exactly at the 0.4 s mark. Its 12 m section matches
  the referenced observation `obs.t000996.ai_surge_1` (12 m road width at all
  three lookaheads, usable half-width 6.0 m).
- `positive/fixture.intent.classic_wait_hold.json` — Classic planner
  `wait`/`grip` intents, no corrections, Rookie 18-tick traffic age. Its 10 m
  section matches the referenced observation `obs.t000500.ai_classic_2`
  (a clear 10 m straight).
- `positive/fixture.intent.post_reset_defaults.json` — post-reset intent
  with masked history and Expert 7-tick traffic age; `reset_generation` 2
  matches the referenced observation `obs.t000800.ai_classic_4`, and its 10 m
  section matches that observation's 10 m road width.
- `positive/fixture.intent.hazard_interrupted_commit.json` — a Classic
  planner `commit_pass` whose held commitment ends after 12 ticks because a
  hazard interrupted it: the counterpart to the held commitment, and the only
  legal early release.
- `positive/fixture.intent.classic_fallback_substitution.json` — a
  learned_policy participant whose nonfinite actor output is replaced wholesale
  by safe Classic control, recorded in `safety.emergency` (status `example`:
  exercises the producer kind without claiming a model exists). The second
  intent continues the substitution with `persistent` true, which BENCHMARKS.md
  counts as a learned failure rather than a learned finish; the fixture records
  the representation, not a measured outcome.
- `negative/*.json` — 44 deliberately invalid fixtures, each derived from a
  valid base with exactly one defect (schema `const`/`enum`/`maximum`/
  `required`/`additionalProperties` violations and semantic violations:
  unknown pairing, content hash, decode mismatch, pace interval/decode/
  correction rules, threshold mislabel, executed commitment state and the
  0.4 s hold, interruption pairing, executed drift preference, intervention
  window, emergency substitution coherence, difficulty age, cadence, age
  arithmetic, reset mask, materiality flag, one-entry-per-field correction
  shape, retain resolution, context disagreement, source observation linkage,
  measured metric status, and comparator/bound shape:
  report carrying a threshold, range carrying a point value, inverted range
  bounds, threshold missing `value`). Each has a `.expected.json` sidecar
  listing the exact failure set; the validator requires an exact match, so a
  rejection cannot silently disappear or grow.

  Two negative fixtures carry more than one declared failure because one
  authored defect necessarily trips two independent gates: `bad_reset_mask`
  (the claimed valid history is rejected by the reset-mask rule and by the
  source-observation link) and, for the same reason, no other fixture does.
  The pace negatives instantiate speed-profile intervals that are otherwise
  unratified; the values are arbitrary inputs for the rule under test and the
  file is invalid by construction, so nothing is ratified.

  `bad_difficulty_age` places its defect on the record whose source
  observation is declared illustrative, so the difficulty-age rule stays the
  only gate that fires; the traffic-age comparison of the source-observation
  link has its own dedicated negative (`bad_source_observation_mismatch`,
  which uses `reset_generation`).

## Observation references: verified links and declared illustrations

Every record's `source_observation_id` is resolved by the validator against
the shipped **positive** observation fixtures (`fixtures/observation/positive`,
read-only for this slice). The rule, implemented as the `source_observation`
check:

- a resolvable link must agree with the observation on participant,
  difficulty, style, delayed traffic age, reset generation, history validity,
  route frame and the section road width (observation feature 14 x 20 m), and
  the intent's `generated_tick` may not precede the observation's
  `sampled_tick`;
- an ID that resolves must be unique across the shipped records, and one
  fixture may not use the same source observation twice;
- an ID that does **not** resolve is legal only when the fixture declares it
  in `illustrative_sources` with a reason, and declaring an ID that does
  resolve is itself a failure, so the declarations cannot be used to skip
  verification;
- a source observation captured with the safe diagnostic fallback active
  carries safe-default features, so its road width is not compared.

The three first records of `fixture.intent.surge_commit_pass.json`,
`fixture.intent.classic_wait_hold.json` and
`fixture.intent.post_reset_defaults.json` resolve and agree on every compared
field; `fixture.intent.hazard_interrupted_commit.json` and
`fixture.intent.classic_fallback_substitution.json` add two more resolvable
first records. The follow-on IDs (`obs.t001008.ai_surge_1`,
`obs.t001020.ai_surge_1`, `obs.t000512.ai_classic_2`) are declared
illustrative: the observation slice ships no such record, each fixture says so
in its description, and the shipped `obs.t001008.ai_surge_2` (a different
participant) must not be read as the surge fixture's second source
observation. Resolving the gap would mean authoring further illustrative
observation records in the observation slice, which this slice does not do;
if that slice later ships them, the declarations can be removed and the links
become verified.

## Validation

Standard library only (Python 3); no installs, no network, no engine.

```sh
fixtures/intent/run_tests.sh              # unittest suite, then the validator
python3 -m unittest discover -s fixtures/intent/tests -t fixtures/intent
python3 fixtures/intent/validate_intent_contract.py            # validate all
python3 fixtures/intent/validate_intent_contract.py --update-hashes
python3 fixtures/intent/validate_intent_contract.py --observations DIR   # override the read-only observation slice
```

The validator implements a small JSON Schema 2020-12 subset evaluator
(`$ref`, `type`, `const`, `enum`, `required`, `additionalProperties`,
`properties`, `items`, `minItems`/`maxItems`, `minimum`/`maximum`/
`exclusiveMinimum`, `pattern`, `minLength`) with `$ref` resolution into
`schemas/common.schema.json` and between the two intent schemas, rejects
strict-JSON violations (duplicate members and NaN/Infinity literals; the
evaluator also refuses non-finite numbers in memory), recomputes the canonical
content hash, and runs the
semantic checks named in `intent_fixture.schema.json`'s expectation enum
(decode consistency, pace decode consistency, label thresholds, commitment
hold, executed drift preference, sampling cadence, age arithmetic,
difficulty age, context agreement, reset mask, safety deferral, intervention
window, emergency consistency, correction materiality, correction shape,
source observation, minimum commitment, metric status honesty, metric shape,
unknown pairing).
Schema failures short-circuit semantic checks so each negative fixture pins
exactly one rejection.

The two metric checks cover rules the subset evaluator cannot express:
`schemas/intent/intent_fixture.schema.json` forbids status `measured` in a
fixture file, and `schemas/common.schema.json`'s `acceptance_metric`
`allOf` clauses tie the bound members to the comparator. Their check ids and
failure paths match the scenario slice's `metric_status_honesty` and
`metric_shape` checks; the comparator/status vocabulary itself is read from
`schemas/common.schema.json` rather than restated, so it cannot drift from
the handling and scenario slices. An expectation may address a single metric
(`comparison.metrics.0`) or the whole array (`comparison.metrics`).

The pace-correction nonnegativity rule lives in both layers by design:
`tactical_intent.schema.json`'s `$defs.correction` carries an
`allOf`/`if`/`then` clause that a full draft 2020-12 validator (Ajv) rejects,
and the slice's `pace_decode_consistency` check rejects the same file
semantically, because the subset evaluator ignores `allOf`. The suite was
cross-checked with Ajv 8.20.0 from the local Cline bundle on 2026-11-27: all
11 schema documents pass meta-schema validation, all 5 positive fixtures
validate, and of the 44 negatives 13 are rejected at the schema layer, 2 fail
strict JSON parsing (the non-finite literals) and the remaining 29 are
rejected by the semantic checks.

Exit codes: 0 = all fixtures valid / all negatives rejected as declared;
1 = failures; 2 = unreadable input or bad command line.

## Remaining decisions for the ratifying milestones

1. M4.2: commitment window length, interpolation curve, stale-intent
   behavior, post-reset default intent values, fallback-intent
   representation, the intervention-export truncation rule, the final
   emergency kind vocabulary.
2. M4.3: per-difficulty desired speed-profile intervals (unblocks decoded
   target speeds and the pace decode/correction rules' positive fixtures;
   until then those rules are covered by unit tests and negative fixtures).
3. M4B.1: producer revisions for the Classic planner, the
   cloning-only policy and the learned policy; the learned-policy export
   interface stays outside this contract.
4. Whether intent records should also carry a pass-side label (currently
   carried by the lateral target, per the action table).
5. Boundary reading taken here and worth confirming at ratification: an
   executed `commit_pass` satisfies the minimum at `elapsed >= 24` ticks, so
   a commitment may lapse exactly at 0.4 s, and only a strict early lapse
   without interruption is rejected.
6. Whether a resolvable `source_observation_id` must be the observation
   sampled at the intent's decision tick. Every shipped link has
   `generated_tick == sampled_tick`, but the validator enforces only
   `generated_tick >= sampled_tick`, so an older observation of the same
   participant, difficulty, style, age and road width still resolves. The
   docs do not state the equality rule explicitly; this probe reports it
   rather than inventing it.
7. Whether `commitment.interrupted: true` needs evidence that a commitment
   was held at or before that record. Today any record may claim a hazard
   interruption with a reason; a fresh wait/follow record with no prior
   `commit_started_tick` is accepted.
8. Whether `drift.label retain` must repeat the immediately preceding
   record's `executed_preference`. The current check resolves the value
   (`none` only when masked; otherwise drift/grip) but does not compare
   across records, so a retain band may switch preference between intents.
9. Whether `reset.defaults_applied` must be non-empty when
   `post_reset_defaults_applied` is true. The observation record contract
   states the non-empty rule; the intent schema does not, so the validator
   does not enforce it.

## Cross-slice notes for the integrator (2026-11-27)

- `tactical_intent.schema.json`'s `producer.kind` and
  `intent_fixture.schema.json`'s `context.producer_kind` include
  `cloning_only_policy`, matching `scenario.schema.json`'s participant driver
  enum; no fixture instantiates it yet.
- The `producer.kind` enum is read from the schema by the mini evaluator, so
  the added value needs no validator change; a fixture that used it would only
  need `context.producer_kind` to agree.
- Revision 1.1.0 (2026-11-27): the observation references are now verified
  against the observation slice instead of asserted in prose; the two
  follow-on IDs remain declared-but-unverifiable and are recorded in
  `illustrative_sources` rather than papered over.
- The observation slice is read-only for this validator. If it later ships
  the two missing records, remove the matching `illustrative_sources`
 declarations and the links verify automatically; if it changes a compared
  field (road width encoding, traffic age, masks), the resolvable links fail
  until the intent fixtures are refreshed with it.
- Strict JSON now matches the observation slice: NaN/Infinity literals are
  refused at parse time and non-finite numbers fail the evaluator. The
  stricter-than-draft-2020-12 treatment of integral numbers written with a
  fractional point (for example `500.0`) remains a shared four-slice decision
  recorded in the observation README.
