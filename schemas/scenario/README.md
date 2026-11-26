# Scenario and reference contracts: schema, fixtures and validator

M0.9 reference/scenario-contract slice (job `847d8664-1028-4233-a67c-39f1465b4964`,
model `step-5-preview`, provider `stepfun-ai-step-plan`, authored 2026-11-26).
Owned paths: `schemas/scenario/**` and `fixtures/scenario/**`. Nothing else in
the tree was modified; the existing partial schemas
(`schemas/handling_config.schema.json`, `schemas/ai_observation.schema.json`,
`schemas/common.schema.json`) and the sibling `schemas/handling/` and
`schemas/intent/` slices are referenced, not edited. (The partial
`ai_observation.schema.json` was touched once afterwards, on 2026-11-27, by the
M0.9 integration pass that gave it its own non-ratified layout revision
`ai_shared_partial_v0` so it no longer collides with the accepted
`schemas/observation/observation_record.schema.json`'s `ai_shared_v1`; nothing
in this slice depends on it.)

Remediation pass (job `f4b734f4-85a2-4f26-993f-c752e0539e49`, model
`stepfun-ai-step-plan/step-5-preview`, 2026-11-27) for contract-review
findings 5, 9, 10, 11, 12 and 13: initial commands/history and per-participant
state are now represented and checked; a measured record must retain the
specified evidence (sector splits, speed samples, car/loadout/assist hashes);
metric shape and bounds are validated like the handling contract's; the
documented initial targets this slice can express are recorded; and the counts,
scope notes and recorded decisions below were corrected. Only
`schemas/scenario/**` and `fixtures/scenario/**` were modified.

This slice implements the reference/scenario half of PLAN.md M0.9: "Create
versioned handling/AI/reference/scenario schemas and fixture configurations
from BENCHMARKS; schema definitions do not require a working AI implementation
yet." The per-car handling configuration schema and the AI observation/intent
contracts are separate slices; this directory adds the **benchmark reference
record** and **scenario configuration** contracts that tie
`docs/BENCHMARKS.md` ("Reference driver and records", "AI metrics", "Tactical
comparison") and the ReferenceRun/Scenario row of
`docs/TECHNICAL_DESIGN.md` ("Content contracts") to machine-readable files.

## Files

| Path | Role |
| --- | --- |
| `scenario.schema.json` | Versioned scenario configuration contract (draft 2020-12 JSON Schema), schema version 1.0.0. |
| `reference_run.schema.json` | Versioned benchmark reference record contract (the measured-evidence half), schema version 1.0.0. |
| `scenario_fixture.schema.json` | Fixture wrapper: one scenario plus the reference records it depends on, expectations, targets, unknowns, hash. |
| `../../fixtures/scenario/validate_scenario_contract.py` | Standard-library validator: schema evaluation, semantic checks, negative-fixture sidecars. Also usable as a library. |
| `../../fixtures/scenario/tests/test_validate_scenario_contract.py` | `unittest` suite: shipped artifacts validate, 19 deliberately broken copies are rejected with specific finding codes, and the measured-record accounting and remediation rules are exercised on synthetic data. |
| `../../fixtures/scenario/positive/*.json` | Three authored fixtures: the two planned reference captures and one tactical opportunity window. |
| `../../fixtures/scenario/negative/*.json` (+ `.expected.json`) | Deliberately broken variants, each pinned to its exact failure set. |

## The contracts in one paragraph

A **scenario configuration** (`scenario.schema.json`) fixes the authored
configuration of a measurement or matched comparison: the course and its
revision; every dependency revision (engine, physics backend, handling,
calibration driver, Classic planner, learned policy, reference line, metric
version); the participants with their cars, loadouts, assists and driver kinds;
the initial state, commands and history (per-participant matched initial
states, the source of the initial commands, and how the shared pre-window
history is established); the protocol (60 Hz fixed tick, 0.10 m / 0.10 m/s
handover tolerance, and for tactical families the fixed 2 s history warm-up
and 3 s opportunity window); the seeds; the required telemetry; an optional
reference linkage; and the documented exclusion rules. A **reference record**
(`reference_run.schema.json`) fixes the measured-evidence half: the
CalibrationDriver and line revisions, the car/loadout/assist and course
revisions, the platform and seeds, the capture protocol (five clean laps per
kind after warm-up, rejecting runs with contacts, reset, missed gates, invalid
progress or numerical errors), and the retained individual lap times, median,
min/max, sector splits, speed samples, hashes and derived medal thresholds.
The **fixture** (`scenario_fixture.schema.json`) bundles one scenario with the
planned records it depends on, the expectations, the documented initial
targets, the unknowns, a content hash and provenance.

## Illustrative configuration versus measured evidence

The central honesty rule, enforced by the validator:

* A scenario is authored configuration. It carries seeds, gaps, participants
  and protocol constants, and never a lap time, median, contact rate or
  completed-test outcome.
* A reference record's `status` distinguishes `planned` (authored protocol and
  dependencies, no results) from `measured`/`superseded` (evidence produced by
  M1/M4 capture tooling as separate artifacts). The validator **rejects
  measured and superseded records inside fixture files**: an authored file must
  not impersonate a record. A `planned` record must carry no results at all.
* A JSON null means "not yet determined" and must be paired with an
  `unknowns` entry; an optional member that is absent means "not applicable".
  The pairing is enforced in both directions, and the validator rejects an
  entry that points at a determined value.
* No fixture contains a fabricated lap time, median, record or completed test.
  The accounting rules a measured record must satisfy (five clean laps,
  median/min/max over the clean laps, medal thresholds equal to
  1.25/1.12/1.05 x the measured median, complete dependencies) are exercised
  only by unit tests over synthetic arithmetic data inside the test file.

## Rules the validator enforces

* **Required fields.** All members of each schema, including the per-record
  units block and the five rejection criteria.
* **Numeric ranges and identifiers.** Tick rate 60; handover tolerances
  0.10 m / 0.10 m/s; warm-up 2.0 s and window 3.0 s for tactical families
  (omitted for captures); `required_clean_laps` 5; medal multipliers
  1.25/1.12/1.05; Arcade Rush factors 1.20/1.10/1.02; dotted-numeric
  revisions; stable-ID patterns for scenario, record and fixture IDs;
  `content_hash` recomputes exactly over canonical JSON with the member
  removed.
* **Family agreement.** `fixture_family` equals the enclosed scenario's
  `scenario_family`.
* **Reference linkage.** A scenario's `reference` member must resolve to an
  embedded record of the same revision and kind, and every `matched_*`
  participant must agree with that record on car, loadout, assists and course
  (BENCHMARKS: match by car, loadout, difficulty, assists, initial scenario and
  reference revision).
* **Telemetry minimums.** A capture scenario must declare gate crossings, lap
  times, sector splits, speed samples, contacts, resets, progress corrections
  and validity flags; a tactical scenario must declare commands, intents,
  safety corrections, contacts, poses, gate crossings and race RNG state.
* **Initial state, commands and history.** A tactical comparison must fix a
  per-participant initial state for every `matched_*` participant and name its
  history source; per-participant entries must name real slots without
  duplicates and must agree with the single-participant summary members; a
  stored-snapshot history must name its snapshot; an authored command schedule
  must be present; a history warm-up must equal the protocol warm-up
  (TECHNICAL_DESIGN 'Content contracts': initial state/commands/history;
  BENCHMARKS 'Tactical comparison': matched initial states and histories).
* **Driver revision pinning.** A `cloning_only_policy` participant must carry
  `driver.producer_revision`, because no dependencies member pins that
  producer and OPPONENT_AI evaluates it separately from the PPO-trained
  policy.
* **Evidence status.** Only `planned` records in fixtures; no results in a
  planned record; a measured record (unit-test only) must retain at least five
  clean laps, consistent median/min/max, medal thresholds equal to the
  documented factors times the median, invalid reasons for rejected laps, and
  complete dependencies.
* **Retained measured evidence.** A measured record (unit-test only) must
  retain at least one speed sample, the car/loadout/assist hashes, and four
  sector splits on every clean lap - the evidence BENCHMARKS 'Reference driver
  and records' promises to keep and Arcade Rush budgets are built from.
* **Metric honesty and shape.** No comparison metric may use status
  `measured` (or any status outside `documented_initial_target`/`undecided`),
  and the comparator vocabulary is checked exactly as the handling validator
  checks it: threshold comparators carry a numeric `value` and no bounds,
  range comparators carry ordered numeric `value_min`/`value_max` and no point
  `value`, and a `report` metric carries no pass/fail bound.

## Deliberate limitations

* The validator is standard-library only and standalone; it does not run the
  engine, execute a scenario, capture a lap, or judge physics. A valid fixture
  is a well-formed contract, not a completed test.
* It implements the contract's rules in Python rather than evaluating the full
  JSON Schema semantics (no `oneOf`/`if`-`then` constructs are used, so the
  mini evaluator covers every rule); the schema files remain the text
  contracts of record. No `jsonschema` dependency is introduced.
* The validator treats every non-capture family as a tactical family for the
  window-protocol, telemetry and initial-state checks; a capture-flavored
  `regression` fixture would need those checks extended.
* The five remaining tactical families from BENCHMARKS ("open two-lane corner
  entry", "narrow-section patience", "legal defended line/cutback",
  "multi-car merge", "noisy human proxy") are named in the contract enum but
  not yet instantiated by fixtures; the enum reserves them, and the same
  fixture shape covers them.
* Reference records are embedded in fixtures so each file is self-contained. A
  deployed measured record is a standalone evidence artifact; this contract
  defines its fields, and the capture tooling that produces it is M1/M4 work.
* `fixtures/scenario/` is not wired into `tools/ci/contracts.list` or
  `tools/ci/ci.sh`: that inventory is owned by `tools/ci/**`. The validator is
  runnable standalone and ready to be wired in by the CI owner.

## Running

```sh
# validate the shipped fixtures and the schema documents
python3 fixtures/scenario/validate_scenario_contract.py

# validate specific files or directories
python3 fixtures/scenario/validate_scenario_contract.py --positive fixtures/scenario/positive/fixture.scenario.tactical_window_slower_lead.json

# run the test suite (shipped-artifact checks + rejection checks + machinery)
sh fixtures/scenario/run_tests.sh
```

Exit codes: 0 = no errors, 1 = validation failures, 2 = a path could not be
read or the command line was wrong.

## Regenerating content hashes

`content_hash` covers the file with the `content_hash` member removed. After
any semantic edit to a fixture, bump `revision` and recompute the hash:

```sh
python3 fixtures/scenario/validate_scenario_contract.py --update-hashes
# or, for the negative fixtures:
python3 - <<'EOF'
import sys
from pathlib import Path
sys.path.insert(0, "fixtures/scenario")
from validate_scenario_contract import update_hashes
update_hashes(Path("fixtures/scenario/negative"))
EOF
```

Note that `--update-hashes` deliberately "repairs" `bad_hash.json`; that
fixture's corrupted hash is its defect and must be restored after any bulk
rehash (the test suite pins the rejection).

## Documented initial targets this slice records

`scenario_fixture.schema.json` claims to carry the documented initial targets,
and the shipped fixtures record every BENCHMARKS/GAME_DESIGN target this
slice's families can express: the clean-lap counts, medal factors
1.25/1.12/1.05, Arcade Rush factors 1.20/1.10/1.02 and the four-sector count
on the capture fixtures, and on the tactical fixture the clean-pace-ratio
bounds 0.90-1.10 (as two threshold metrics, so faster and slower violations
are both reported), the matched-window count, the semantic-difference
fraction, the 0.10 m / 0.10 m/s handover tolerances, the heavy-contact bound
(Classic rate + max(0.1 * Classic rate, 0.05 heavy contacts per
participant-race)), the >=99% completion target for aggregate entries and per
style, and the max(3 x reference event time, reference event time + 300 s)
evaluation timeout.

Two documented BENCHMARKS targets have no vehicle in this slice and are
**not** recorded here: the mixed-loop tuning target (within 3%) and the
stock-car spread (<=5% over an equal-weight mixed-course benchmark). Both are
handling-fixture comparisons: the scenario families are reference captures and
tactical windows, `fixture_family` has no mixed-loop or spread value, and a
single scenario configuration cannot express a cross-car handling comparison.
They belong to the `schemas/handling/` + `fixtures/handling/` slice; the gap
is recorded here so the schema claim stays honest about its scope.

## Recorded decisions

* **Hashes versus revisions.** `docs/TECHNICAL_DESIGN.md` 'Content contracts'
  asks for "car/loadout/assist/track/handling hashes" while
  `docs/BENCHMARKS.md` asks for "engine/backend/handling/course revisions".
  The two documents conflict. This contract records the BENCHMARKS wording -
  car/loadout/assist hashes in `results.hashes` plus course and handling
  revisions - as the decision of record, and flags the conflict in
  `reference_run.schema.json` for the documentation owner rather than silently
  picking one.
* **Range metrics versus the shared schema.** The metric shape rules mirror
  `schemas/handling/validate_fixtures.py`: threshold comparators carry a
  numeric `value` and no bounds, range comparators carry ordered numeric
  `value_min`/`value_max` and no point `value`, and a `report` metric carries
  no bound. `schemas/common.schema.json` (owned by another slice, read only
  here) was updated concurrently on 2026-11-27 to carry the same rules as
  `allOf` conditions, replacing its earlier universal `required: value` that
  made range and report metrics impossible; this slice's `check_metric_shape`
  enforces the identical rules in Python because the mini evaluator does not
  evaluate `allOf`. The interface dependency is resolved as of that edit; if
  the shared schema changes again, re-verify the two stay aligned (the test
  suite pins the shipped metrics against both this check and the schema).
  Until the shared schema's change, this slice deliberately shipped no
  range/report metrics - the clean-pace-ratio window is recorded as the two
  threshold metrics 0.90 and 1.1, which stay valid under either variant and
  report faster and slower violations separately.

Original project code under the Unlicense.
