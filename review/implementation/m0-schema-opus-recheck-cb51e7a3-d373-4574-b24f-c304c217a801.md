# M0.9 schema checkpoint recheck: independent Opus pass

| Item | Value |
| --- | --- |
| Job | cb51e7a3-d373-4574-b24f-c304c217a801 |
| Reviewer model | Claude Opus 5.5 (`claude-opus-5-5`) |
| Provider | Anthropic first-party, through the Claude Code CLI |
| Date (UTC) | 2026-11-27 |
| Candidate | `d1827be92bec746696090929a069af95e1d7b0a3` (d1827be, "Repair intent and observation contract invariants") |
| Base | aee1822 (the candidate of my earlier report `m0-schema-opus-a525aeef-…`) |
| Inspected tree | `work/agents/cb51e7a3-d373-4574-b24f-c304c217a801/snap` (copied snapshot, read only) |
| Verdict | **Changes required.** Runtime claims are **not verified**: no code ran in this session. |

M0 and the schema freeze stay open. This review closes neither.

## Scope

In scope: `schemas/**` and `fixtures/**` in the snapshot, checked against `docs/BENCHMARKS.md`,
`docs/TECHNICAL_DESIGN.md`, `docs/OPPONENT_AI.md` and my earlier report
`review/implementation/m0-schema-opus-a525aeef-0873-477c-a666-a4d8d8795041.md` (F1–F8).
I also read the earlier implementation-audit evidence I was allowed to use:
`work/agents/fb0c61c6-…/report.md` (LongCat, intent and observation repair) and
`work/agents/6e2ca91b-…/review-scenario-b8c76b03.md` (LongCat, scenario review R1–R10).

Read in full: `schemas/intent/tactical_intent.schema.json`, `docs/OPPONENT_AI.md`.
Read in the relevant parts:
- `fixtures/intent/validate_intent_contract.py`: lines 576–1721, which hold every semantic check.
- `fixtures/observation/validate_observation_contract.py`: lines 637–1196, which hold the
  neighbor, range, age, history and reset checks.
- `fixtures/scenario/validate_scenario_contract.py`: lines 140–190 and 658–1694, which hold
  linkage, capture structure, evidence, initial state, arms, arm identity, context and
  pose/slot checks.
- `fixtures/scenario/positive/fixture.scenario.tactical_window_slower_lead.json`: lines 1–260.
- `fixtures/intent/positive/fixture.intent.surge_commit_pass.json`: lines 1–140.
- `schemas/README.md`: lines 95–136.
- The usable-half-width and emergency passages of the slice READMEs, found with grep.
- `docs/BENCHMARKS.md`: the matching and AI-metrics lines, found with grep.

Not reviewed in depth: the handling slice (`schemas/handling/**`, `handling_config.schema.json`),
`reference_run.schema.json`, the fixture schemas outside their check enums, the unit-test
suites, and the bodies of individual negative fixtures beyond their names and counts.

I consulted no Sol report. I spawned no agents or helpers, did not change Git, and edited no
source, asset or installed template. The only file written is this report.

## Commands and results

| Command | Result |
| --- | --- |
| `ls`/`find` over `snap/schemas`, `snap/fixtures` | Inventory: 11 schema documents; 4 slice validators |
| `ls fixtures/*/negative \| grep -c expected` | observation 38, intent 44, scenario 41 negatives. With 6/5/3 positives that gives **44 / 49 / 44** fixtures, which matches the claimed counts (by inventory only) |
| `mkdir scratch && cp -R snap/{schemas,fixtures} scratch/run` | **Refused** (cp with flags needs approval; non-interactive) |
| `ditto snap/schemas scratch/run/schemas` | **Refused** (needs approval) |
| `sh fixtures/{observation,intent,scenario}/run_tests.sh`, `sh schemas/handling/run_tests.sh` (with `PYTHONPYCACHEPREFIX`/`PYTHONDONTWRITEBYTECODE` into scratch) | **Refused** (needs approval) |
| `python3 -B -c "print(1)"` | **Refused**: no Python execution in this session |
| `grep`/`sed`/`Read` over the snapshot | Used for every finding below |

## Capability limits

- **No code was executed.** The claimed results (handling 59 tests; observation 37 tests / 44
  fixtures; intent 27 / 49; scenario 78 / 44) are **not verified** by me. Only the fixture
  counts were confirmed, by inventory. The LongCat reports say they ran these suites. That is
  third-party evidence, not mine.
- I made no scratch copy because copying was refused. Every read went to the read-only snapshot.
- None of the repros below was run. Each one gives the input, the code path and the result that
  path produces, as I read it. Run them before relying on them.

## Status of earlier findings (aee1822 report)

| ID | Earlier finding | Status at d1827be (static) |
| --- | --- | --- |
| F1 | No home for a held commitment, 0.4 s unenforced, proposed and executed labels conflated | **Resolved for the commit_pass path.** Schema 1.1.0 adds `executed_label`, `commit_started_tick` and `drift.executed_preference`. `check_commitment_hold` (`validate_intent_contract.py:1161-1310`) enforces start, continuation, the 24-tick minimum and restart-as-lapse. `check_executed_drift_preference` (`:1313-1366`) resolves retain. Residual gap: see D3. |
| F2 | Matched drivers co-located as simultaneous participants | **Resolved structurally.** There is one `evaluated` slot plus `comparison.arms`, enforced by `check_comparison_arms` (`validate_scenario_contract.py:1355-1494`). Residual gaps: D1 and D2. |
| F3 | Observation slice missing `metric_shape` | **Resolved.** `check_metric_shape` is present (`validate_observation_contract.py:1452`) and the expectation enum includes it. |
| F4 | Usable-half-width convention unratified | **Recorded as a blocking unknown**, correctly: `observation_record.schema.json:213,260-261,356`, `schemas/observation/README.md:48-56`, `fixtures/observation/README.md:76-83`. This is unsettled design, not an implementation defect. It must be decided before the freeze. |
| F5 | Intent-to-observation reference never resolved | **Resolved.** `check_source_observation` (`validate_intent_contract.py:1548-1721`) resolves IDs, requires `illustrative_sources` for IDs that do not resolve, and compares participant, difficulty, style, age, reset generation, history validity, frame, tick order and road width. Residual: D5. |
| F6 | No emergency or Classic-fallback record | **Resolved.** `safety.emergency` and `safety.interventions` (`tactical_intent.schema.json:272-310`), with `check_emergency_consistency` and `check_intervention_window`. The kind vocabulary is provisional and listed as unknown, which is correct. |
| F7 | Neighbor tie-break uncheckable | **Resolved (optional diagnostic).** `neighbor_ids` and the tie check are at `validate_observation_contract.py:865-922`. Enforcement depends on the record carrying the optional list. That is acceptable for a diagnostic. |
| F8 | Slice evaluators type `1.0` as non-integer | **Open, now documented** as a stricter-than-Ajv profile (observation README; LongCat report item 5). Low. It is a cross-slice decision. |

LongCat scenario findings R1–R7 and R10: each now has a matching negative fixture
(`bad_reference_subject_learned`, `bad_arm_duplicate_producer`, `bad_classic_arm_style_surge`,
`bad_nonbenchmark_arm`, `bad_learned_arm_no_style`, `bad_capture_traffic`,
`bad_tactical_solo_evaluated`, `bad_course_revision_drift`, `bad_duplicate_slot`,
`bad_duplicate_record_id`, `bad_duplicate_unknown_path`) and a matching check, which I read at
`:749-802`, `:886-914`, `:1507-1693` and `:714-728`. R8 is fixed at `:1016-1017`.

## Ranked verified defects (static)

### D1: Medium. Comparison arms need not share a difficulty, and a difficulty difference makes duplicate producers look distinct

- `docs/BENCHMARKS.md:11`: "Match an evaluated Roadstormer and Classic by car, loadout,
  **difficulty**, assists, initial scenario and reference revision." Line 64 compares the
  producers "from matched initial states".
- `validate_scenario_contract.py:1497-1504`: `_arm_spec_key` includes `difficulty` in the
  producer identity. `check_comparison_arm_identity` (`:1507-1578`) only rejects identical keys.
  The validator has no rule that the arms of one comparison share a difficulty (grep for
  `difficulty` finds only the key, docstrings and Arcade Rush factors). Per
  `scenario.schema.json:375-377`, `difficulty` is optional on a driver, so a producer arm may
  also omit it.
- **Repro:** in `fixture.scenario.tactical_window_slower_lead.json`, set the `classic` arm's
  `driver.difficulty` to `"expert"` and leave `surge` and `switch` at `"racer"`. Recompute
  `content_hash`. No check fires: kinds, styles and slots are valid and the keys are distinct.
  The fixture then claims a matched Classic–Surge comparison across difficulties.
- **Variant:** replace the four arms with two `classic_planner`/`none` arms at `rookie` and
  `expert`. Both pass identity, and the comparison has no producer diversity at all, which is
  exactly the duplicate-baseline case the identity check was added to stop (LongCat R2).
- **Fix:** require every arm of a tactical comparison to carry a non-null `difficulty`, and
  require all arms to share it. Take `difficulty` out of `_arm_spec_key`. Add negatives for both
  cases.

### D2: Medium-low. The pose-distinctness rule only catches byte-identical poses, so co-located cars still pass

- `check_participant_pose_distinctness` (`validate_scenario_contract.py:1619-1662`) flags two
  participants only when all four members (`forward_gap_m`, `lateral_offset_m`, `speed_m_s`,
  `heading_offset_deg`) are equal, nulls included. Speed and heading say nothing about where a
  car is. It uses no position tolerance and has no car-footprint notion.
- **Repro A:** add a context car with `forward_gap_m 10, lateral_offset_m 0, speed_m_s 29,
  heading_offset_deg 0` next to the evaluated slot's `10, 0, 30, 0`. The poses differ, so the
  check accepts two cars at one position.
- **Repro B:** `10, 0, null, null` against `10, 0, 30, 0` is also accepted.
- The frame of a context participant's `forward_gap_m` is also undefined. The evaluated slot's
  gap is to the lead, and the lead's own entry authors no gap. So the rule cannot be made exact
  until the frame is defined (unsettled design).
- **Impact:** the F2 guarantee that the window does not start in contact is weaker than the
  check name says.
- **Fix:** define the reference frame of per-participant positions. Then compare only position
  (gap, lateral) with a minimum separation of about one car length and width, or document the
  rule as an "identical authored pose" lint only.

### D3: Medium-low. Outside a held commit, `executed_label` is unconstrained, so a proposed pass can silently not execute

- `check_commitment_hold` (`validate_intent_contract.py:1161-1310`) constrains `executed_label`
  only when it is, or was, `commit_pass`. No check ties `executed_label` to `label` otherwise.
- **Repro:** in `fixture.intent.post_reset_defaults.json`, or any record not under a held commit,
  set `commitment_raw 0.8` and `label "commit_pass"`, keep `executed_label "wait"`, leave
  `interrupted false` and `corrections []`, and recompute the hash. Every check passes. The
  record shows a commit proposal that was never executed, with no interruption, correction or
  emergency explaining why.
- OPPONENT_AI.md:61 says "commit to a **legal** pass", and line 64 says to record safety changes
  separately. A refused commit is a safety change, but `correction.field` cannot name
  commitment (`tactical_intent.schema.json:476-477`), and `interrupted` is defined only for a
  held commitment. The anti-jitter hold window (`hold_window_s`, unratified) may legitimately
  make executed and proposed differ in the follow/wait band.
- **Classification:** partly unsettled design (the hold window and how a refused commit is
  recorded), partly a missing rule. At least `label commit_pass → executed ≠ commit_pass`
  without `interrupted` should be rejected or given a recorded reason.
- **Related, low:** `interrupted: true` is accepted on a record with no held commitment, and
  together with a continuing `commit_pass`, which is self-contradictory. This was LongCat's Q1,
  still open.

### D4: Low-medium. Cross-record intent rules assume one participant, but nothing enforces it

- `check_commitment_hold` (`:1183-1184`) and `check_emergency_consistency`'s `persistent` rule
  (`:1497-1515`) both assume "Fixture records are one participant's 5 Hz intent sequence".
  `check_context_agreement` (`:645-672`) compares difficulty, style and producer, but not
  `participant_id`. The observation slice does (`validate_observation_contract.py:664`). No
  check requires `reset_generation` to be non-decreasing, or `intent_id` to be unique.
- **Repro:** in `fixture.intent.surge_commit_pass.json`, change `records.1.participant_id` to
  `ai.surge_2`. Record 1's source is in `illustrative_sources`, so the source check skips it.
  The record passes, and the commit-hold continuity is then evaluated across two different cars.
  A `persistent: true` Classic fallback can likewise "continue" another participant's
  substitution.
- **Also:** a commitment continuing across a `reset_generation` increment is accepted, although
  a reset restores timers (OPPONENT_AI.md:76).
- **Fix:** add `participant_id` to the context agreement, or require equality across records.
  Require a non-decreasing `reset_generation` and unique `intent_id`. End an executing commit at
  a reset.

### D5: Low. The intent road-width cross-check reads lookahead feature 14 as the section's current width

- `check_source_observation` (`validate_intent_contract.py:1701-1720`) compares
  `context.road_width_m` with observation `feature_vector[14] × 20`. Per OPPONENT_AI.md:42,
  indices 12–26 are "At 20/50/100 m ahead", so index 14 is the road width **20 m ahead**.
  The action-0 corridor width (`:59`) does not say which width it uses.
- **Consequence:** on a section whose width changes within 20 m (the `narrow_section_patience`
  family), a correct intent is rejected, or a builder is pushed to use the lookahead width for
  the corridor. That would freeze an undecided rule through a validator.
- **Fix:** state which road width action 0 uses and which observation quantity carries it, or
  label the check as a constant-width fixture assumption and say so in the schema description.

### D6: Low (stale evidence). `schemas/README.md` still reports the aee1822 suite results

`schemas/README.md:95-131` still states "27 tests … 33 fixtures" (observation), "17 … 27"
(intent), "48 … 22" (scenario), "all 19 files … valid under Ajv" and "All 90 content hashes
recompute". It also lists five negatives as the full metric-shape set. The candidate's own
claimed results are 37/44, 27/49 and 78/44. The shared README is the evidence record a freeze
reviewer reads, so it should be refreshed with the d1827be run, including the Ajv sweep. The
alternative is to mark that section as historical.

### Unsettled design to decide before the freeze (not defects)

- The usable-half-width convention (F4), and whether history features 51–52 store
  `decoded_offset_m / half-width` or `lateral_target_norm`.
- The emergency `kind` vocabulary, and who owns per-intervention magnitude. Both are recorded
  as unknowns (`schemas/scenario/README.md:351-370`).
- Source tick equality (`generated_tick == sampled_tick` against `>=`), and `retain` continuity
  across records (LongCat items 1 and 3).
- `cloning_only_policy` `producer_revision: null` counts as pinned. Acceptable before M4B, but
  the freeze must require a real value.

## Checked and consistent (static)

- Intent constants (5 Hz/12 ticks, 24-tick minimum, ±1/3, ±0.25, 0.5 m margin, materiality
  0.1 car width and 0.05 with `max(proposed, 1 m/s)`, ages 18/12/7) match OPPONENT_AI.md and
  BENCHMARKS.md:70.
- The pace decode (`check_pace_decode_consistency`, `:768-912`) rejects an inverted interval, a
  negative or mismatched `proposed`, a negative `applied` and a target/applied mismatch. A null
  interval forbids any target or correction.
- The intervention ticks and emergency tick are confined to `[generated, generated+12)`.
  `classic_fallback` is forbidden for a Classic planner. `persistent` requires the same kind in
  the preceding record.
- Observation neighbor checks use only canonical `raw_inputs` keys, so aliases cannot bypass the
  window or ordering checks (`:637-652`, `:926-968`). Absent slots must be zero and present
  slots form a prefix. Post-reset `defaults_applied` must be non-empty and use known names.
- Scenario capture structure is enforced: exactly one participant, a `reference_subject`, and
  a `calibration_driver`. Course revision linkage and record-ID uniqueness are enforced.
  Measured standing-start records skip the medal arithmetic.

## Verdict

**Changes required.** The earlier blocking findings F1, F2, F3, F5 and F6 are resolved in
contract shape. F4 is correctly held open as a blocking unknown.

D1 should be fixed before the schema freeze, because it lets an unmatched comparison through
the matched-comparison contract. D2–D4 are validator gaps in the new rules. D5–D6 are low.
Runtime results (the suite counts, Ajv agreement and hash recomputation) are **not verified** in
this pass, because the session could not execute code. M0 and the schema freeze remain open.
