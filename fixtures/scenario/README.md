# Scenario and reference fixtures

M0.9 reference/scenario-contract slice (job `847d8664-1028-4233-a67c-39f1465b4964`),
remediated by job `f4b734f4-85a2-4f26-993f-c752e0539e49` (2026-11-27) for
contract-review findings 5, 9, 10, 11, 12 and 13.
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
| `positive/fixture.scenario.tactical_window_slower_lead.json` | slower_lead_straight_pass | 1 planned flying record (matched reference) | status `example`: Classic/cloning-only/learned producers are unratified; 30 m/s entry and 10 m gap are authored and fixed per matched participant in `initial_state.per_participant_state`; the shared history is `replay_from_seed`; the cloning-only producer is pinned by `driver.producer_revision`; three exclusion rules with count 0; the clean-pace-ratio window is recorded as the two threshold metrics 0.90/1.10, and the AI-metric targets (heavy-contact bound, >=99% completion, evaluation timeout) are recorded as documented initial targets |

The `negative/` directory holds 19 deliberately broken variants, each with an
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
  additionally retain the evidence BENCHMARKS promises: speed samples, the
  car/loadout/assist hashes and four sector splits per clean lap.
* **No invented undetermined numbers.** Unratified revisions (handling,
  calibration driver, line, course, producers, the cloning-only
  `producer_revision`), the unrecorded platform, the unspecified warm-up lap
  count and every result are JSON null with matching `unknowns` entries; the
  validator rejects any null that is not explained and any explanation that
  points at a determined value.
* **No unpinned history.** The tactical fixture fixes the matched initial
  states per participant and names its history source
  (`initial_state.history`), so two scenarios with the same participants cannot
  silently differ in history; a stored-snapshot history must name its
  snapshot, and an authored command schedule must actually be present.
* **No fabricated laps even as negative examples.** The "planned record
  carrying results" and "measured record without results" rejections are
  demonstrated with a hash and a status change, not with invented lap times.
  The measured-record accounting rules (five clean laps, median/min/max,
  medal arithmetic) are exercised only inside the unit tests, with round
  arithmetic test data.
* **No claim that AI exists.** The tactical fixture's Classic, cloning-only
  and learned-policy participants are contract placeholders; the fixture
  status is `example` and the producer revisions are null with unknowns.

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
