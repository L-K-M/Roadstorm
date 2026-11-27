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

Remediation pass (job `b8c76b03-bb34-4c2f-8721-d4b5d673ab9d`, model
`stepfun-ai-step-plan/step-5-preview`, 2026-11-27) for the independent M0.9
schema checkpoints (Sol `aee1822`, Opus `a525aeef`): matched comparisons are
now modeled as **one evaluated slot plus alternative producer arms that are
separate runs of the same scenario**, instead of simultaneous co-located
cars (Opus F2); the reference record retains **track and handling hashes
alongside the car/loadout/assist hashes** so both cited documents' content
contracts are represented (Sol 5); the scenario contract reserves the
**tick-level `safety_interventions` telemetry channel** where emergency
substitution/reset, persistent Classic replacement and material-correction
tick evidence live (Sol 4 / Opus F6); and the validator gained
`comparison_arms` and `participant_pose_distinctness` checks with ten new
negative controls. Only `schemas/scenario/**` and `fixtures/scenario/**`
were modified.

Correction pass (job `3e9684f8-f772-40e8-b847-408673ce5fc6`, 2026-11-27)
for the independent review of `b8c76b03` (R1-R10): a reference capture must
declare exactly one calibration-driver subject with no traffic; comparison
arms must be distinct BENCHMARKS producers with coherent style inputs, while
the full four-producer set stays a benchmark-level requirement rather than a
per-scenario one; a tactical family needs a fixed context car; scenario and
referenced-record course revisions must agree; participant slots, embedded
record IDs and unknowns paths must be unique; standing-start records are
exempt from medal arithmetic; and the stale measured-evidence expectation
wording was corrected. The cross-slice `safety_interventions` claims were
reconciled with the current intent schema. Only `schemas/scenario/**` and
`fixtures/scenario/**` were modified.

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
| `../../fixtures/scenario/tests/test_validate_scenario_contract.py` | `unittest` suite: shipped artifacts validate, 41 deliberately broken copies are rejected with specific finding codes, and the measured-record accounting and remediation rules are exercised on synthetic data. |
| `../../fixtures/scenario/positive/*.json` | Three authored fixtures: the two planned reference captures and one tactical opportunity window. |
| `../../fixtures/scenario/negative/*.json` (+ `.expected.json`) | Deliberately broken variants, each pinned to its exact failure set. |

## The contracts in one paragraph

A **scenario configuration** (`scenario.schema.json`) fixes the authored
configuration of a measurement or matched comparison: the course and its
revision; every dependency revision (engine, physics backend, handling,
calibration driver, Classic planner, learned policy, reference line, metric
version); the participants of one execution (fixed context cars plus the
single evaluated slot) and, for a matched comparison, the alternative
producer arms that run the evaluated slot in separate executions from the
same seed, initial state and history; the initial state, commands and history
(per-participant matched initial states, the source of the initial commands,
and how the shared pre-window history is established); the protocol (60 Hz
fixed tick, 0.10 m / 0.10 m/s handover tolerance, and for tactical families
the fixed 2 s history warm-up and 3 s opportunity window); the seeds; the
required telemetry (including the tick-level `safety_interventions`
channel); an optional reference linkage; and the documented exclusion rules.
A **reference record**
(`reference_run.schema.json`) fixes the measured-evidence half: the
CalibrationDriver and line revisions, the car/loadout/assist/track/handling
hashes and course revision, the platform and seeds, the capture protocol
(five clean laps per kind after warm-up, rejecting runs with contacts,
reset, missed gates, invalid progress or numerical errors), and the retained
individual lap times, median, min/max, sector splits, speed samples and
derived medal thresholds.
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
  1.25/1.12/1.05 x the measured median on a flying-lap record, complete
  dependencies) are exercised only by unit tests over synthetic arithmetic
  data inside the test file.

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
* **Measured-record accounting.** A measured record (unit-test only: fixture
  files reject measured status) must retain five clean laps with median/min/max
  over exactly those laps, an invalid reason for every rejected lap, complete
  dependencies and the retained evidence; each clean lap's four sector splits
  must sum to that lap's recorded time within one 60 Hz tick. That is a
  deliberately conservative, unresolved precision bound, not a ratified
  format - see Recorded decisions.
* **Family agreement.** `fixture_family` equals the enclosed scenario's
  `scenario_family`.
* **Reference linkage.** A scenario's `reference` member must resolve to an
  embedded record of the same revision and kind, and the evaluated
  participant must agree with that record on car, loadout, assists, course ID
  and course revision (nulls may agree while course content is unratified)
  (BENCHMARKS: match by car, loadout, difficulty, assists, initial scenario and
  reference revision).
* **Telemetry minimums.** A capture scenario must declare gate crossings, lap
  times, sector splits, speed samples, contacts, resets, progress corrections
  and validity flags; a tactical scenario must declare commands, intents,
  safety corrections, the tick-level safety interventions, contacts, poses,
  gate crossings and race RNG state.
* **Initial state, commands and history.** A tactical comparison must fix a
  per-participant initial state for its evaluated slot - the state every arm
  starts from - and name its history source; per-participant entries must
  name real slots without duplicates and must agree with the
  single-participant summary members; a stored-snapshot history must name its
  snapshot; an authored command schedule must be present; a history warm-up
  must equal the protocol warm-up (TECHNICAL_DESIGN 'Content contracts':
  initial state/commands/history; BENCHMARKS 'Tactical comparison': matched
  initial states and histories).
* **Comparison arms.** A tactical family declares exactly one `evaluated`
  participant and a `comparison` naming that slot plus at least two producer
  arms; the evaluated slot carries no driver of its own, context participants
  must declare theirs, arm IDs are unique, and `evaluated_slot` names the
  evaluated participant. Each arm must name one of the compared producer kinds
  (`classic_planner`, `cloning_only_policy`, `learned_policy`), carry a style
  coherent with that kind (`none` for Classic and cloning-only, `surge`/`switch`
  for a Roadstormer), declare the matched `difficulty`, be pairwise distinct
  in kind/style/producer_revision, and all share one difficulty; human
  proxies and scripted drivers are context participants, not compared
  producers. Arms are separate executions of the
  same scenario with the same seed, initial state and history, so the compared
  producers are never simultaneous cars (BENCHMARKS 'Tactical comparison').
* **Tactical context car.** Every tactical family is an encounter with another
  car, so a tactical scenario must declare at least one fixed context
  participant besides the evaluated slot; a solo evaluated slot leaves
  `forward_gap_m` pointing at nothing.
* **Reference-capture shape.** A `reference_lap_capture` scenario declares
  exactly one participant, role `reference_subject`, driven by
  `calibration_driver`; no traffic or proxy shares a traffic-free capture run,
  and an evaluated AI producer cannot establish its own reference.
* **Identity uniqueness.** Participant slots are unique inside one execution
  (they key `per_participant_state` and `evaluated_slot`), embedded reference
  `record_id`s are unique (linkage resolves by ID), and each null has exactly
  one `unknowns` explanation.
* **Participant pose distinctness.** No two participants of one execution may
  declare an identical authored initial pose (forward gap, lateral offset,
  speed and heading offset all equal); entries that author no pose member are
  not compared. This is an authored-pose identity lint, not a physical
  collision test: the forward gaps use per-participant frames (see Recorded
  decisions).
* **Driver revision pinning.** A `cloning_only_policy` driver - on a
  participant or on a comparison arm - must carry `driver.producer_revision`,
  because no dependencies member pins that producer and OPPONENT_AI evaluates
  it separately from the PPO-trained policy. While the producer is unratified
  the value is null with an unknowns entry, which distinguishes nothing yet;
  the M0.9 freeze/ratification step must require a real revision (review X4,
  2026-11-27). The intent contract's `producer.producer_revision` is already a
  non-null string, so the two contracts agree once producers are ratified.
* **Evidence status.** Only `planned` records in fixtures; no results in a
  planned record; a measured record (unit-test only) must retain at least five
  clean laps, consistent median/min/max, invalid reasons for rejected laps, and
  complete dependencies. Medal thresholds equal the documented factors times
  the median on a flying-lap record; they do not apply to a
  `standing_start_lap_set`, whose sector times feed Arcade Rush instead.
* **Retained measured evidence.** A measured record (unit-test only) must
  retain at least one speed sample, the car/loadout/assist/track/handling
  hashes, and four sector splits on every clean lap - the evidence BENCHMARKS
  'Reference driver and records' and TECHNICAL_DESIGN 'Content contracts'
  promise to keep and Arcade Rush budgets are built from.
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
  JSON Schema semantics. The mini evaluator ignores the one applicator this
  contract uses - the `anyOf` on `$defs/participant` that makes `driver`
  required for every role except `evaluated` - so that rule is enforced
  semantically by `comparison_arms` and by any full draft 2020-12 validator
  (verified with Ajv 8.20.0 from the local Cline bundle: a `slower_lead`
  without a driver is rejected, an `evaluated` participant without one is
  accepted). As before, the schema files remain the text contracts of record,
  and no `jsonschema` dependency is introduced.
* The validator treats every non-capture family as a tactical family for the
  window-protocol, telemetry and initial-state checks; a capture-flavored
  `regression` fixture would need those checks extended. The
  comparison-structure and arm-identity checks bind the six BENCHMARKS tactical
  families; a `regression` fixture may declare a comparison but is not required
  to, and its arms are outside the preregistered producer set.
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

* **Pose comparison is authored-pose identity only.** Each
  `per_participant_state.forward_gap_m` is that participant's gap to its own
  car ahead, so two entries do not share an absolute position frame;
  `lateral_offset_m` is centerline-relative but still cannot establish
  longitudinal separation. The contract also fixes no position tolerance or
  car-footprint geometry. The validator therefore rejects only byte-identical
  authored pose tuples. A near-collision rule needs a design decision on the
  reference frame and minimum separation; until then it is an open issue, not
  an enforced guarantee.
* **Sector-split sum tolerance.** BENCHMARKS 'Reference driver and records'
  requires retaining individual lap times and sector splits but does not state
  the capture format's precision, and TECHNICAL_DESIGN adds no precision. No
  decimal precision contract is invented. As a deliberately conservative
  unresolved constraint the validator accepts a discrepancy of at most one
  60 Hz simulation tick (1/60 s), the coarsest timing unit the fixed-tick
  contract names; independent millisecond rounding of four splits and the lap
  total can differ by up to 2.5 ms, well inside this bound. Grossly impossible
  totals (four 100 s sectors against a 40 s lap) remain rejected. Exact
  agreement precision stays open until M1 capture tooling defines it; no
  measured record is authored at M0.9, so this affects only the unit-test
  accounting rule until then.

* **Hashes versus revisions.** `docs/TECHNICAL_DESIGN.md` 'Content contracts'
  asks for "car/loadout/assist/track/handling hashes" while
  `docs/BENCHMARKS.md` asks for "engine/backend/handling/course revisions".
  The two requirements are complementary, not conflicting, and this contract
  represents both: the revisions live in `course` and `dependencies`, and all
  five hashes - car, loadout, assist, track and handling - live in
  `results.hashes`, null until capture tooling computes them. No requirement
  is dropped and no hash is fabricated. (The 2026-11-27 remediation pass
  replaced the earlier "record the BENCHMARKS wording" decision with this
  combined representation, which the independent schema checkpoints required.)
* **Matched comparisons are runs, not simultaneous cars.** BENCHMARKS
  'Tactical comparison' compares Classic, cloning-only, Surge and Switch
  "from matched initial states and histories". Modeling the compared
  producers as simultaneous participants co-locates them at the window start
  and makes each compared car traffic for the others, so their histories
  cannot match. The contract therefore declares one `evaluated` participant -
  the slot - plus `comparison.arms`, each arm a driver spec that runs the slot
  in a separate execution with the same seed, initial state and history. The
  matched state/history semantics are preserved: the evaluated slot's
  per-participant initial state, the shared history source and the handover
  tolerances are authored once and bind every arm. The four `matched_*`
  participant roles were removed rather than left as dead enum values; arm IDs
  (`classic`, `cloning_only`, `surge`, `switch`) name the compared producers
  instead. (Opus checkpoint F2, 2026-11-27.)
* **Per-scenario arms versus the full benchmark producer set.** BENCHMARKS
  'Tactical comparison' says "Compare Classic, cloning-only, Surge, and
  Switch" and its acceptance gate reports Classic-Surge, Classic-Switch and
  Surge-Switch separately on at least 200 matched windows per pair across the
  six families; OPPONENT_AI additionally requires cloning-only to be evaluated
  separately so PPO must demonstrate useful learning beyond its teacher. Those
  are properties of the whole six-family benchmark, not of one scenario file.
  The contract therefore requires each tactical scenario to declare at least
  two distinct producer arms drawn from the three producer kinds
  (`classic_planner`, `cloning_only_policy`, `learned_policy`) with coherent
  style inputs; it does not force all four producers into every scenario. A
  scenario may instantiate any subset, and the union of the six families must
  cover the four named producers before final acceptance. Human proxies and
  scripted drivers belong to the noisy-human-proxy family as context cars,
  never as compared producers, so an arm may not declare them. The intent
  contract independently fixes the same three producer kinds in
  `producer.kind`, which corroborates the arm vocabulary. (R2 disposition,
  2026-11-27.)
* **Where tick-level safety evidence lives.** BENCHMARKS counts "emergency
  replacements and material road/collision corrections per proposed 5 Hz
  intent", with tick-level exposure also reported, and OPPONENT_AI keeps
  "emergency substitution/reset" separate from material corrections and
  counts persistent replacement by Classic as a learned failure. This contract
  reserves the `safety_interventions` telemetry channel for that evidence and
  links it to the current TacticalIntent contract
  (`../intent/tactical_intent.schema.json`, schema version 1.1.0 as of
  2026-11-27): per-tick override exposure is `safety.interventions.ticks`, and
  wholesale emergency substitution/reset including persistent Classic
  replacement is `safety.emergency` (`substituted`, `kind`, `tick`,
  `persistent`, `reason`). `safety_corrections` keeps the 5 Hz material
  corrections with their `proposed`/`applied` magnitudes; those magnitudes are
  authoritative for interventions because neither `interventions.ticks` nor
  `emergency` carries a magnitude field. One intent corrected on several ticks
  counts once by intent identity, and the tick list is the exposure reported
  beside that count. Remaining open until preregistration - not claimed as
  frozen here: the final `safety.emergency.kind` vocabulary and intervention
  categories OPPONENT_AI requires before evaluation, and whether any
  per-intervention magnitude beyond a correction's `proposed`/`applied` values
  needs its own field. No payload, count or measurement is fabricated in this
  slice. This linkage describes the current uncommitted intent schema; if that
  schema changes again, re-verify the two sides before ratification.
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
