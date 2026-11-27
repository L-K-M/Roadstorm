# M0.9 schema slices: integration record

This file records the historical M0.9 schema integration pass of 2026-11-27.
Its decisions and counts below describe that earlier candidate; later review
findings and repairs supersede parts of it. The contracts remain provisional,
and agreement with a JSON Schema checker does not prove semantic correctness.
It adds no contract of its own: the contracts of record are the schema
documents in this directory and the slice READMEs beside them.

## The slices

| Path | Contract | Fixtures and checker |
| --- | --- | --- |
| `handling/handling_fixture.schema.json` | benchmark handling fixture | `../../fixtures/handling/*.json`, `handling/validate_fixtures.py` |
| `observation/observation_record.schema.json`, `observation/observation_fixture.schema.json` | shared AI observation (`ai_shared_v1`) | `../../fixtures/observation/**`, `fixtures/observation/validate_observation_contract.py` |
| `intent/tactical_intent.schema.json`, `intent/intent_fixture.schema.json` | `TacticalIntent` (`tactical_intent_v1`) | `../../fixtures/intent/**`, `fixtures/intent/validate_intent_contract.py` |
| `scenario/scenario.schema.json`, `scenario/reference_run.schema.json`, `scenario/scenario_fixture.schema.json` | scenario configuration and benchmark reference record | `../../fixtures/scenario/**`, `fixtures/scenario/validate_scenario_contract.py` |
| `common.schema.json` | shared vocabulary (stable IDs, schema version, content hash, unknown entries, provenance, `acceptance_metric`) | used by all four slices through `$ref` |

`ai_observation.schema.json` is the earlier **partial, unaccepted** draft of the
observation contract. It is retained for its authoring record but now declares
its own `feature_layout_revision` `ai_shared_partial_v0`; the provisional
`ai_shared_v1` layout belongs solely to
`observation/observation_record.schema.json`. Deleting the partial file outright
is a coordinator decision that this pass did not take.

## Historical cross-slice decisions taken on 2026-11-27

The first decision below was later superseded: local road width and widths at
20/50/100 m ahead can differ. See the current slice READMEs and the varying-width
intent fixture; do not infer equality from the earlier example.

1. **Surge road width.** `fixtures/observation/positive/fixture.observation.surge_full_vector.json`
   described a 12 m section but encoded road widths of 11/11/10 m and a 5.0 m
   usable half-width, while the intent fixture that references it
   (`fixture.intent.surge_commit_pass.json`) declares `road_width_m: 12.0` and
   derives its legal corridor from it. The observation now encodes 12 m at all
   three lookaheads with a 6.0 m usable half-width - the same convention
   `fixture.observation.classic_rookie_clear.json` already used (10 m road,
   5.0 m usable half-width) - the pinned `raw_inputs` probe for feature 14 is
   12 m, and the ego lane-offset probe stays 1.5 m (1.5/6.0 = 0.25). The intent
   fixture is unchanged, so its 4.6 m corridor and its 3.68 m to 3.2 m material
   correction still hold. No new behaviour is invented: the 12 m figure was
   already the documented, declared value in both files' prose.
2. **Post-reset road width.** `fixture.intent.post_reset_defaults.json` declared
   `road_width_m: 12.0` while the observation it references
   (`obs.t000800.ai_classic_4`) encodes a 10 m road. The intent fixture now
   declares 10.0 m and a 3.6 m legal corridor; its recentered lateral target is
   0.0, so the decoded offset is unchanged. Its `bad_reset_mask` negative copy
   was refreshed the same way.
3. **Stale copied geometry.** Eighteen intent negative fixtures still carried
   the pre-remediation section geometry of their positive bases (9.5 m for the
   classic-wait-hold copies, 12 m for the post-reset copy). They were refreshed
   to the current base geometry and rehashed; each fixture's declared defect and
   its `.expected.json` sidecar are untouched, and `bad_content_hash.json` keeps
   its deliberately broken hash.
4. **Producer kinds.** `intent/tactical_intent.schema.json`'s `producer.kind`
   and `intent/intent_fixture.schema.json`'s `context.producer_kind` now admit
   `cloning_only_policy` beside `classic_planner` and `learned_policy`, matching
   the participant driver enum that `scenario/scenario.schema.json` already
   defines. OPPONENT_AI.md ("Training approach") and BENCHMARKS.md ("Tactical
   comparison") require the behavioral-cloning-only producer to be evaluated
   separately from the PPO-trained policy; the intent contract could not name it,
   so the two producers were distinguishable only by an undocumented
   `producer_revision` convention. They are now distinguished by the kind plus a
   recorded revision, exactly as the scenario slice does. No fixture
   instantiates the new kind.
5. **Duplicate layout revision.** See the `ai_observation.schema.json` note
   above.
6. **Undeclared second defect.** `fixtures/scenario/negative/bad_exclusion_negative_count.json`
   carried a `clean_pace_ratio` metric of the form `ratio_range` plus a point
   `value: 1.0`, which `common.schema.json`'s `allOf` clauses forbid. It was
   invisible because a schema failure short-circuits the semantic checks, so the
   sidecar's single declared failure masked it; the independent validator below
   exposed it. The stray `value` was removed and the hash recomputed.
7. **Provenance shape.** The eight handling fixtures lacked
   `provenance.author` (the authoring job appeared only inside
   `provenance.note`). The member was added so all four slices carry the same
   provenance shape; hashes were recomputed and no authored value changed.

## Historical independent JSON Schema verification

Each slice ships a small standard-library JSON Schema subset evaluator. To check
that the subset evaluators and the schemas themselves agree, an **independent**
draft 2020-12 validator was used: Ajv 8.20.0, which is already present on this
machine inside the Cline CLI bundle
(`.../cline/node_modules/ajv/dist/2020`). Nothing was installed, downloaded or
configured for this check.

Method: every schema document was added to an `Ajv2020` instance keyed by its
absolute path (so the relative `$ref`s such as `../common.schema.json#/$defs/stable_id`
resolve exactly as the slices resolve them), then

* every schema document was validated against the draft 2020-12 meta-schema, and
* all 90 shipped fixture files (positive and negative, all four slices) were
  validated against their fixture wrapper schema, which `$ref`s the record
  schemas and `common.schema.json`.

Results (reproducible with the same Ajv build):

* **Schema documents:** all 11 are valid draft 2020-12 schemas.
* **Positive and handling fixtures:** all 19 files that the slices call valid are
  also valid under Ajv.
* **Negative fixtures:** Ajv rejects every file whose defect is a schema-level
  defect, and accepts every file whose defect is purely semantic - the semantic
  rules are deliberately not expressible in the schemas.
* **One genuine disagreement was found and fixed** (decision 6 above): the
  scenario negative fixture whose second defect the slice's short-circuit hid.

Residual, documented gap (kept open on purpose): `common.schema.json` expresses
the `acceptance_metric` bound rules with `allOf`/`if`/`then`, which none of the
subset evaluators implements; each slice therefore re-implements the identical
rules semantically as its `metric_shape` check. Five negative fixtures
(`bad_metric_missing_value`, `bad_metric_range_with_value`,
`bad_metric_report_with_threshold`, `bad_metric_range_missing_bounds`,
`bad_metric_value_on_range`) are consequently rejected semantically by their
slice while Ajv rejects them at the schema layer. Both layers reject them, so no
defect is missed, but the rule lives in two places; a future slice should either
extend the evaluator with `allOf`/`if` or move the metric rules out of the
shared schema.

## Historical honesty checks

No fixture claims a measured value: every record is `planned`/`provisional`/
`example`, no metric uses status `measured` outside the negative fixtures whose
declared defect is exactly that, and no lap time, median, contact rate or
completed-test outcome appears in any fixture. All 90 content hashes recompute
except the two negative fixtures whose broken hash is their declared defect.
Every provenance block names source documents that exist in the tree.

## Historical suite results (isolated snapshot copies)

```
schemas/handling/run_tests.sh      -> 59 tests OK; 8 fixtures + schema document, 0 errors, 0 warnings
fixtures/observation/run_tests.sh  -> 27 tests OK; all 33 fixtures behave as contracted
fixtures/intent/run_tests.sh       -> 17 tests OK; all 27 fixtures behave as contracted
fixtures/scenario/run_tests.sh     -> 48 tests OK; all 22 fixtures behave as contracted
```

The suites were run on copies of the tree under `/tmp`, never on the working tree
directly, and they write nothing outside a temporary directory.

## Later checks

Exact-candidate sweep of `cc5dac91ed89b934defdd6d1240e729791885ccb`
("Refine schema timing and matched comparisons", committed 2026-11-27
03:22:52 +01:00), exported read-only with `git archive cc5dac9` into the
ignored job directory `work/agents/cd8a5eda-4a90-46df-bbf6-948f70062608/cc5dac9-snap/`:

| Check | Result |
| --- | --- |
| `schemas/handling/run_tests.sh` | 59 tests OK; 8 fixtures + schema document, 0 errors, 0 warnings |
| `fixtures/observation/run_tests.sh` | 37 tests OK; all 44 fixture cases behave as declared |
| `fixtures/intent/run_tests.sh` | 30 tests OK; all 53 fixture cases behave as declared |
| `fixtures/scenario/run_tests.sh` | 83 tests OK; all 44 fixture cases behave as declared |
| Ajv 8.20.0 draft 2020-12 sweep | 11 schema documents valid; 23/23 positive fixtures valid; of 126 observation/intent/scenario negatives, 3 fail strict parsing, 32 fail the wrapper schema and 91 are schema-valid files rejected by the project semantic checks |
| Content-hash sweep | 149 shipped fixture files; every `content_hash` recomputes except the three declared broken-hash negatives (`fixtures/observation/negative/bad_content_hash.json`, `fixtures/intent/negative/bad_content_hash.json`, `fixtures/scenario/negative/bad_hash.json`) |

Logs live beside the snapshot as `cc5dac9-suite-*.log`, `cc5dac9-ajv.log`
and `cc5dac9-hash.log`. The independent Sol pass review of the same SHA
(`review/implementation/m0-schema-sol-recheck-cc5dac9.md`) reports the same
suite totals and the same Ajv breakdown.

The follow-up changes made after this sweep - pose identity requiring a
shared named `ahead_slot`, the exclusive sub-period source-timing bound, and
the GAME_DESIGN-derived millisecond-rounding sector bound - are not covered by
these numbers; a fresh sweep is required on their successor. They supersede
two bounds the Sol pass review had accepted on this candidate: the inclusive
12-tick source-age envelope (a full period now counts as stale under the
slice's own staleness convention) and the one-tick sector envelope (replaced
by the derived `(sector_count + 1) x 0.5 ms` rounding bound). Open issues
include the absolute pose frame, execution of refused commitments, source
observation alignment, and reference-capture precision. See the slice
READMEs and `docs/STATUS.md` for their dispositions.
