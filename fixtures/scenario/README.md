# Scenario and reference fixtures

M0.9 reference/scenario-contract slice (job `847d8664-1028-4233-a67c-39f1465b4964`),
remediated by job `f4b734f4-85a2-4f26-993f-c752e0539e49` (2026-11-27) for
contract-review findings 5, 9, 10, 11, 12 and 13, and by job
`b8c76b03-bb34-4c2f-8721-d4b5d673ab9d` (2026-11-27) for the independent M0.9
schema checkpoints: matched comparisons became one evaluated slot plus
separate producer arms (Opus F2), the records gained the track/handling
hashes (Sol 5), and the tactical telemetry minimum gained the tick-level
`safety_interventions` channel (Sol 4 / Opus F6).
Correction pass (job `3e9684f8-f772-40e8-b847-408673ce5fc6`, 2026-11-27)
for the independent review of `b8c76b03`: added twelve negatives pinning the
reference-capture subject shape, comparison-arm producer identity/style
coherence, the tactical context car, course-revision linkage, slot/record/unknowns
uniqueness, and the standing-start medal exemption, and corrected the stale
measured-evidence expectation wording. This job modified only the owned
`fixtures/scenario/**` and `schemas/scenario/**` paths.
Opus recheck follow-up (job `cd8a5eda-4a90-46df-bbf6-948f70062608`,
2026-11-27): the independent Opus pass reproduced matched-comparison and
co-location gaps. D1 is fixed: every tactical comparison arm must declare the
matched difficulty and all arms must share it, and `difficulty` is no longer
part of arm identity, so two classic arms at different difficulties can no
longer look like distinct producers or hide a duplicate baseline. D2 is
resolved by requiring a shared named reference: two entries are rejected as
one pose only when they name the same `ahead_slot` and agree on every relative
pose member. Identical tuples without a shared reference remain legal (an
evenly spaced convoy through different predecessors), and no unsupported
physical collision detection is asserted;
[`../../schemas/scenario/README.md`](../../schemas/scenario/README.md) records
the remaining frame decision.

Owned paths: `fixtures/scenario/**`. The contracts these files implement are
in [`../../schemas/scenario/`](../../schemas/scenario/); the checker is
[`./validate_scenario_contract.py`](./validate_scenario_contract.py). Every
fixture is derived from `docs/BENCHMARKS.md` ("Reference driver and records",
"AI metrics", "Tactical comparison") and `docs/GAME_DESIGN.md` (Arcade Rush
budgets), and is an authored initial contract, not a measurement.

| File | Family | Records | Notable authored choices |
| --- | --- | --- | --- |
| `positive/fixture.scenario.reference_capture_flying.json` | reference_lap_capture | 1 planned flying-lap record | balanced starter at stock/Standard; course ID `course.riviera_run`; seeds 4101/4102; engine/backend revisions are the pinned M0.1 values, all other dependency revisions null with unknowns |
| `positive/fixture.scenario.arcade_rush_standing_start.json` | reference_lap_capture | 1 planned standing-start record | seeds 4201/4202; medal thresholds null because they derive from the flying-lap median; Arcade Rush factors 1.20/1.10/1.02 as documented targets |
| `positive/fixture.scenario.tactical_window_slower_lead.json` | slower_lead_straight_pass | 1 planned flying record (matched reference) | status `example`: Classic/cloning-only/learned producers are unratified; the compared producers are `comparison.arms` (`classic`, `cloning_only`, `surge`, `switch`) that each run the single `evaluated` slot in a separate execution; 30 m/s entry and 10 m gap are authored and fixed for the evaluated slot in `initial_state.per_participant_state`; the shared history is `replay_from_seed`; the cloning-only arm is pinned by `driver.producer_revision`; three exclusion rules with count 0; the clean-pace-ratio window is recorded as the two threshold metrics 0.90/1.10, and the AI-metric targets (heavy-contact bound, >=99% completion, evaluation timeout) are recorded as documented initial targets |

The `negative/` directory holds 43 deliberately broken variants, each with an
`.expected.json` sidecar pinning its exact failure set: schema-level defects
(`bad_schema_version`, `bad_extra_property`, `bad_seed_missing`,
`bad_exclusion_negative_count`) and semantic defects (`bad_family_mismatch`,
`bad_warmup_window`, `bad_window_missing`, `bad_telemetry_missing`,
`bad_reference_dangling`, `bad_reference_mismatch`, `bad_planned_with_results`,
`bad_measured_without_results`, `bad_rejection_criteria`,
`bad_dependency_null_unpaired`, `bad_unknown_orphan`, `bad_metric_measured`,
`bad_metric_value_on_range`, `bad_metric_range_missing_bounds`, `bad_hash`).
The last two pin the metric-shape rules added in the remediation pass: a range
comparator carrying a point `value`, and a range comparator without bounds.
The 2026-11-27 second pass added ten more, each pinning one new rule:
`bad_comparison_missing` (a tactical family with no comparison structure),
`bad_single_arm` (a comparison with one arm), `bad_evaluated_slot_not_evaluated`
(`evaluated_slot` naming a context participant),
`bad_two_evaluated_participants` (two participants in the evaluated role, the
co-located-cars shape Opus F2 rejected), `bad_arms_duplicate_id`,
`bad_arms_cloning_unpinned`, `bad_evaluated_with_driver` (a second driver
source for the evaluated slot), `bad_pose_identity` (renamed from
`bad_pose_collision`: two participants at one relative pose behind the same
named car, not a general collision claim), `bad_safety_interventions_missing` (the tactical
telemetry minimum without the tick-level channel) and
`bad_track_hash_unpaired` (a null track hash without an unknowns entry).
The 2026-11-27 correction pass added twelve more, each pinning one rule:
`bad_reference_subject_learned` (an evaluated driver as capture subject),
`bad_capture_two_subjects`, `bad_capture_traffic` (a traffic-free capture with
another car), `bad_classic_arm_style_surge`, `bad_learned_arm_no_style`,
`bad_nonbenchmark_arm` (a human proxy as compared producer),
`bad_arm_duplicate_producer` (one producer under two arm IDs),
`bad_tactical_solo_evaluated` (no fixed context car),
`bad_course_revision_drift` (scenario and record course revisions differ),
`bad_duplicate_slot`, `bad_duplicate_record_id`, `bad_duplicate_unknown_path`,
`bad_ahead_slot_self_reference` (a participant names itself as its own car
ahead), and `bad_pose_same_position_different_motion` (equal named-relative
position with differing speed/heading).

On 2026-11-27 the M0.9 integration pass removed a second, undeclared defect
from `bad_exclusion_negative_count.json`: it still carried the pre-remediation
`clean_pace_ratio` metric (`ratio_range` plus a point `value: 1.0`), which
`schemas/common.schema.json`'s `allOf` clauses forbid. That defect was invisible
because a schema failure short-circuits the semantic checks, so the sidecar's
single declared failure masked it; an independent draft 2020-12 validator
(Ajv) exposed it. The metric is now a well-formed `ratio_range`, and the
fixture's only defect is again the negative exclusion count.

## What these files deliberately do not contain

* **No measured values.** Every record is status `planned` with empty results,
  and no metric uses status `measured`. Reference lap times, medians, sector
  splits, contact rates and completed-test outcomes are M1/M4/M8 evidence, not
  fixture content. The validator rejects a measured or superseded record
  inside a fixture file outright, and a measured record (unit-test only) must
  additionally retain the evidence BENCHMARKS and TECHNICAL_DESIGN promise:
  speed samples, the car/loadout/assist/track/handling hashes and four sector
  splits per clean lap, where each clean lap's splits must sum to its lap time
  within the GAME_DESIGN-derived millisecond-rounding envelope
  (`(sector_count + 1) x 0.5 ms`, recorded in
  [`../../schemas/scenario/README.md`](../../schemas/scenario/README.md)).
* **No invented undetermined numbers.** Unratified revisions (handling,
  calibration driver, line, course, producers, the cloning-only arm's
  `producer_revision`), the unrecorded platform, the unspecified warm-up lap
  count, the track/handling hashes and every result are JSON null with
  matching `unknowns` entries; the validator rejects any null that is not
  explained and any explanation that points at a determined value.
* **No unpinned history.** The tactical fixture fixes the evaluated slot's
  matched initial state - the state every arm starts from - and names its
  history source (`initial_state.history`), so two scenarios with the same
  participants cannot silently differ in history; a stored-snapshot history
  must name its snapshot, and an authored command schedule must actually be
  present.
* **No co-located compared cars.** The compared producers are arms, not
  participants: each arm is a separate execution of the same scenario with the
  same seed, initial state and history, and the validator rejects a second
  evaluated participant, an evaluated slot carrying its own driver, and two
  simultaneous participants sharing a pose. The matched state/history
  semantics are unchanged - one authored initial state and one shared history
  bind every arm.
* **No fabricated safety evidence.** The `safety_interventions` telemetry
  channel is reserved and required; it links to the intent contract's
  `safety.interventions.ticks` and `safety.emergency` members, but no event
  payload, intervention count or tick-level measurement is authored here. The
  final emergency-kind vocabulary and per-intervention magnitude ownership
  remain open until preregistration; see
  [`../../schemas/scenario/README.md`](../../schemas/scenario/README.md).
* **No fabricated laps even as negative examples.** The "planned record
  carrying results" and "measured record without results" rejections are
  demonstrated with a hash and a status change, not with invented lap times.
  The measured-record accounting rules (five clean laps, median/min/max,
  medal arithmetic, sector splits summing to each clean lap time within the
  derived millisecond-rounding envelope) are exercised only inside the unit
  tests, with round arithmetic test data.
* **No claim that AI exists.** The tactical fixture's Classic, cloning-only
  and learned-policy arms are contract placeholders; the fixture status is
  `example` and the producer revisions are null with unknowns.

## Running

```sh
sh run_tests.sh                      # unit suite + validator over all fixtures
python3 validate_scenario_contract.py  # validator only
python3 validate_scenario_contract.py --update-hashes   # rewrite content_hash values
```

Exit codes: 0 = all fixtures valid and all negative fixtures rejected as
expected; 1 = validation failures; 2 = a path could not be read or the command
line was wrong.

`--update-hashes` deliberately "repairs" `negative/bad_hash.json`; that
fixture's corrupted hash is its defect, so restore it after any bulk rehash of
the negative directory (the test suite pins the rejection).

Original project code under the Unlicense.
