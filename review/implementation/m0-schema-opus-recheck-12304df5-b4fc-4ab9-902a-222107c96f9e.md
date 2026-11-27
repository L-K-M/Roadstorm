# M0.9 schema checkpoint recheck: independent Opus pass on cc5dac9

| Item | Value |
| --- | --- |
| Job | 12304df5-b4fc-4ab9-902a-222107c96f9e |
| Reviewer model | Claude Opus 5.5 (`claude-opus-5-5`) |
| Provider | Anthropic first-party, through the Claude Code CLI |
| Date (UTC) | 2026-11-27 |
| Candidate | `cc5dac91ed89b934defdd6d1240e729791885ccb` (cc5dac9, "Refine schema timing and matched comparisons") |
| Base | d1827be (`d1827be92bec746696090929a069af95e1d7b0a3`, the candidate of my earlier report `m0-schema-opus-recheck-cb51e7a3-…`) |
| Inspected tree | `work/agents/12304df5-b4fc-4ab9-902a-222107c96f9e/snap` (copied snapshot, read only) |
| Verdict | **Changes required (minor).** Runtime results are **not verified** by me: no code ran in this session. |

M0 and the schema freeze stay open. This review closes neither.

## Scope and inputs

Inputs: the snapshot, my historical report
`review/implementation/m0-schema-opus-recheck-cb51e7a3-d373-4574-b24f-c304c217a801.md` (D1–D6), and
the design documents in the snapshot. I consulted no Sol report, spawned no agents or helpers, changed
nothing in Git, and edited no source, asset, tool or template. The only file written is this report.
My scratch directory needed nothing written to it.

I could not tie the snapshot to the SHA myself: the snapshot has no `.git`, and `git rev-parse`/`git diff`
on the repository were refused without approval. The snapshot is taken to be cc5dac9 as the job states.

Files read, in the relevant parts:

- `fixtures/scenario/validate_scenario_contract.py`: lines 185–215 (tolerances), 920–1180 (clean-lap,
  medal and evidence checks), 1520–1765 (arm identity, tactical context, pose distinctness, slot
  uniqueness).
- `fixtures/intent/validate_intent_contract.py`: lines 1145–1415 (commitment hold, executed drift),
  1593–1875 (intent identity, record sequence, source observation), and grep over width and corridor.
- `fixtures/intent/README.md`: lines 40–46, 140–220, 300–360 (remaining decisions 1–10).
- `fixtures/scenario/README.md` and `schemas/scenario/README.md`: the pose, difficulty and
  sector-tolerance passages, including recorded decisions at lines 315–340.
- `schemas/README.md` (in full), `schemas/scenario/scenario.schema.json` (pose members, 155–175 and
  410–425), `schemas/scenario/reference_run.schema.json` (lap definition, 300–395),
  `schemas/intent/tactical_intent.schema.json` (grep: source, staleness, commitment).
- Unit tests: `fixtures/scenario/tests/…:380–440, 570–600` and `fixtures/intent/tests/…:820–900`.
- Positive fixtures: tick and source ID inventory. `fixtures/scenario/negative/bad_pose_collision.json:123–140`.
- `docs/BENCHMARKS.md:9–13, 60–70`, `docs/GAME_DESIGN.md:79–81, 103, 123`, `docs/OPPONENT_AI.md:42`,
  `docs/REVIEW_RESPONSE.md:57, 159`, `docs/STATUS.md` (grep).

## Commands and results

| Command | Result |
| --- | --- |
| `ls`/`grep -c expected` over `fixtures/*/{positive,negative}` | observation 6 + 38 = **44**, intent 6 + 47 = **53**, scenario 3 + 41 = **44** fixture cases. This matches the coordinator's counts (inventory only) |
| `grep -c "def test_"` over the three slice test files | observation **37**, intent **30**, scenario **83**. This matches the coordinator's test counts, if no test is parametrized (static count) |
| `grep` over the positive fixtures for `source_observation_id`, `generated_tick` and `sampled_tick`, and over the observation positives for `observation_id` and `sampled_tick` | Every **resolvable** source link in the shipped positives has `generated_tick == observation.sampled_tick` (delay 0) |
| `python3 -B -c "print(1)"` | **Refused** (approval required; non-interactive) |
| `git -C <repo> rev-parse/log/diff` | **Refused** (approval required) |
| `grep`/`sed`/`Read` over the snapshot | Used for every finding below |

## Capability limits

- **No code was executed.** The coordinator's results (handling 59; observation 37/44; intent 30/53;
  scenario 83/44) are **not verified by me**. I only confirmed that the test-function and fixture-file
  counts match them. The Ajv sweep and content-hash recomputation were also not run.
- I could not diff cc5dac9 against d1827be. Each "resolved" status below comes from reading the current
  code, not from a diff.
- The repros were not run. Each one gives the input, the code path and the result I expect from reading
  that path.

## Status of earlier findings (d1827be report)

| ID | Earlier finding | Status at cc5dac9 (static) |
| --- | --- | --- |
| D1 | Arms need not share a difficulty; difficulty separates duplicate producers | **Resolved.** `_arm_spec_key` is now (kind, style, producer_revision) (`validate_scenario_contract.py:1527-1540`). `check_comparison_arm_identity` requires a non-null difficulty on every arm and one shared value (`:1601-1628`). Unit test `test_arms_must_share_one_declared_difficulty` (`tests:1244`). There is no negative fixture, only the unit test; acceptable. Both of my repros (expert Classic arm; rookie/expert Classic pair) now fail. |
| D2 | Pose rule only catches byte-identical poses | **Reclassified honestly** as an "authored-pose identity lint" with an open frame decision (`:1685-1733`; `schemas/scenario/README.md:319-327`; `test_near_identical_poses_are_accepted_by_design`). The rule itself has a new defect under its own stated frame: see **N1**. |
| D3 | `executed_label` unconstrained outside a held commit | **Recorded as an explicit unresolved decision** (`fixtures/intent/README.md` remaining decision 8). The rationale holds: no correction field names commitment, and `hold_window_s` is unratified. Acceptable for M0.9. It must be decided at M4.2, before any freeze that claims executed-intent accounting. |
| D3b | `interrupted` without a held commit | Self-contradictory continuing case now **rejected** (`validate_intent_contract.py:1264-1280`, unit test). The broader evidence rule is **recorded** as decision 7. Acceptable. |
| D4 | Cross-record rules assume one participant | **Resolved.** `check_record_sequence` (`:1631-1684`) enforces one `participant_id` and a non-decreasing `reset_generation`. `check_intent_identity` (`:1593-1628`) enforces unique `intent_id`, with negative `bad_duplicate_intent_id`. `check_commitment_hold` rejects a commit that continues across a reset increase (`:1253-1294`, unit test at `tests:842`). |
| D5 | Width check read 20 m lookahead as local width | **Resolved** by removing the comparison (docstring `:1703-1707`). New positive `fixture.intent.varying_width_road` (local 12 m against 11/11/10 m lookahead). Residual nit: **N5**. |
| D6 | `schemas/README.md` carried stale counts | **Resolved in substance.** The file is now labelled historical (`:3-7`, sections headed "Historical"), and "Later checks" (`:142-152`) records 59 / 37·44 / 30·53 / 83·44. Residual: **N4**. |

Unsettled items from my previous report remain correctly open: the usable-half-width convention (F4),
the emergency `kind` vocabulary, `retain` continuity across records (decision 9), and the
`cloning_only_policy` null revision. Source tick timing moved from "unsettled" to a new enforced bound
(see N2).

## Ranked findings (static)

### N1: Medium-low. The pose-identity lint rejects legitimate convoys under its own frame, and its negative fixture is misnamed

- The docstring and the recorded decision (`validate_scenario_contract.py:1693-1699`,
  `schemas/scenario/README.md:319-327`) both say that each `forward_gap_m` is "that participant's gap
  to its own car ahead", so the entries share no position frame. The schema (`scenario.schema.json:415-419`)
  says "gap to the car ahead" and never names which car that is.
- Under that frame, two context cars with equal (gap, lateral offset, speed, heading) are a **legal,
  evenly spaced convoy**. Example: car B is 20 m behind car A, which is 20 m behind the lead, all in
  lane +3.5 m at 25 m/s. That is exactly the natural authoring of BENCHMARKS' "multi-car merge"
  family (`docs/BENCHMARKS.md:62`). The check (`:1716-1732`) rejects it as "simultaneous participants
  must not share one authored pose".
- Conversely, two cars that both measure their gap to the *same* car ahead, with different speeds,
  are truly co-located and are accepted (my earlier D2 repro). So an identical tuple neither proves a
  collision nor proves that the cars are distinguishable. The rule is unsound in both directions.
- **Repro (not run):** take `fixture.scenario.tactical_window_slower_lead.json`. Add two `scripted`
  context participants `merge_a` and `merge_b`. Give each a `per_participant_state` entry with
  `forward_gap_m 20, lateral_offset_m 3.5, speed_m_s 25, heading_offset_deg 0`, and recompute
  `content_hash`. Expected: `participant_pose_distinctness` fails at
  `scenario.initial_state.per_participant_state.<merge_b>.slot`, although the stated frame describes
  a valid 20 m-spaced pair.
- `bad_pose_collision` is named as a collision, but by the recorded decision it is only identity.
  Calling it a collision overstates the guarantee in exactly the way D2 warned about.
- **Fix:** add an explicit reference to the car ahead (for example `ahead_slot`) or an absolute
  route-distance frame. Then compare only entries that share it. Until then, either restrict the lint
  to entries whose tuples are identical **and** whose car ahead is provably the same, or drop the
  rejection, keep the open issue, and rename the negative fixture (for example `bad_pose_identity`).

### N2: Low-medium. The new 12-tick source-timing bound is inclusive and double-counts the phase latency

- `check_source_observation` (`validate_intent_contract.py:1846-1873`) accepts
  `0 <= generated_tick - observation.sampled_tick <= 12`. The justification is GAME_DESIGN:123:
  "5 Hz planning adds another 0–200 ms of phase latency".
- That phase latency is the gap between an event and the next 5 Hz planning sample. The observation
  record already defines ego and road features as "current as of sampled_tick" and says it "feeds the
  5 Hz tactical decision" (`observation_record.schema.json:80`). Letting a decision use an observation
  up to 12 ticks old adds a *second* 0–200 ms on top of the inherent phase. End-to-intent latency could
  then reach about 400 ms plus traffic age. That contradicts REVIEW_RESPONSE:159: "publish its
  additional phase latency rather than conflate it".
- The bound also includes 12, which is inconsistent with the slice's own conventions:
  - `intent_staleness_ticks` says an age "at or beyond" 12 ticks marks a missed 5 Hz update
    (`tactical_intent.schema.json:103, 379-381`).
  - The hold and intervention window is half-open, `[generated, generated+12)`.
  - Docstring and README decision 6 call the allowed source "the current or immediately preceding
    tactical sample". At delay 12, the preceding sample is a whole period old, and on a 12-tick
    cadence a current sample exists at that same tick.
- Every resolvable link in the shipped positives has delay 0. A tighter rule (equality, or
  `0 <= delay < 12`) would therefore cost no fixture.
- **Repro (not run):** in `fixture.intent.post_reset_defaults.json` (one record, source
  `obs.t000800.ai_classic_4` with sampled_tick 800), set `generated_tick 812` and `sampled_tick 815`,
  keep `intent_age_ticks 3`, and recompute the hash. Expected: accepted, so a decision made from a
  12-tick-old ego/road observation passes.
- **Fix:** either require equality, which matches the record semantics, or make the bound exclusive
  (`delay < sampling_period_ticks`). Then state in decision 6 that any non-zero delay is extra latency
  that BENCHMARKS must report as part of the observed end-to-intent latency (GAME_DESIGN:123 "Record
  observed end-to-intent latency").

### N3: Low-medium. The 1/60 s sector-split sum tolerance is not derived from the contract and is loose enough to hide a one-tick timing bug

- `SECTOR_SPLIT_SUM_TOLERANCE_S = 1/60` (`validate_scenario_contract.py:193-204`). The recorded
  decision (`schemas/scenario/README.md:328-340`) says no document states the capture precision, so
  "the coarsest timing unit" was chosen.
- GAME_DESIGN:79 does state one for race crossings: "Interpolate the crossing within the accepted tick
  trajectory and store integer microseconds". Sector splits and the lap time are differences of
  crossing timestamps, so they telescope. The only legitimate disagreement is rounding, which the unit
  test itself bounds at 2.5 ms for millisecond rounding (`tests:404-412`).
- Caveat: GAME_DESIGN:81 says timing gates are separate from validation gates, so applying the
  microsecond rule to intermediate timing gates is an inference, not a statement. The bound is still
  about 6.7× the documented rounding worst case. A systematic one-tick error in a sector split, such as
  a crossing taken at the tick instead of interpolated, sums to 16.7 ms or less and passes. That is the
  class of bug this accounting check exists to catch. The value then feeds Arcade Rush budgets, which
  are rounded to milliseconds (GAME_DESIGN:103).
- The rejection test (`10.017` against a 0.01667 bound) sits 0.33 ms from the boundary. Fine, but it
  shows how much error is tolerated.
- **Fix:** cite GAME_DESIGN:79 and 103 in the recorded decision, and use a rounding-derived bound,
  for example `(sector_count + 1) × 0.5 ms`. Alternatively keep a looser bound, but record it as a
  fixture `unknowns`-style open constraint tied to M1 capture tooling, with the microsecond statement
  named as the likely target. No measured record exists yet, so this only affects the unit-test rule
  now.

### N4: Low. Missing evidence: no Ajv or hash sweep for cc5dac9, and the "later checks" run is not tied to a SHA

- `schemas/README.md:80-128` (Ajv agreement, 90 fixture files, hash recompute) is now explicitly
  historical. Nothing replaces it for the current 149 fixture files (8 handling + 44 + 53 + 44). The
  added fixtures and negatives (for example `bad_pose_collision`, `bad_duplicate_intent_id` and
  `varying_width_road`) have no independent schema-layer confirmation.
- `:142-152` names a work directory and calls the tree "an uncommitted snapshot". It records no
  candidate SHA. The coordinator's run of this copied tree is the relevant evidence, but it lives
  outside the tree.
- **Fix:** rerun the Ajv sweep and hash recompute on cc5dac9 (or its successor) and record the SHA, or
  state explicitly that Ajv agreement is unverified after aee1822.
- Formatting nit: `schemas/README.md:6` joins two sentences into one line ("…semantic correctness. It
  adds no contract…").

### N5: Nit. Which width the action-0 corridor uses is now an implicit decision

D5's fix rests on "local width stays under the decode/geometry rules" (`fixtures/intent/README.md:42-45`,
`validate_intent_contract.py:1703-1707`). OPPONENT_AI.md still does not say which width action 0's
corridor uses, and the "Remaining decisions" list (items 1–10) does not include it. Add it as a
ratification item, so that the M4.2 design does not inherit "local width" from a validator by default.

### N6: Nit. A fixture cannot begin mid-commitment

With no previous record, `check_commitment_hold` sends an executing `commit_pass` to the "new
commitment" branch (`:1332-1353`), which requires `commit_started_tick == generated_tick`. A captured
5 Hz window that starts while a commitment is already held is therefore unrepresentable. This is
harmless for authored fixtures, but worth a sentence in the README, because capture slices will hit it.

## Checked and consistent (static)

- The D1 fix is complete for both repros, and the `_arm_spec_key` docstring states why difficulty left
  the key.
- Reset handling in `check_commitment_hold`: a reset-boundary lapse is exempt from the 24-tick minimum
  (`:1297`), while continuation across the boundary is rejected (`:1282-1294`). A restart after a reset
  must start at `generated_tick` and match the proposed decode. This is consistent with OPPONENT_AI's
  "reset restores timers".
- Medal arithmetic still skips `standing_start_lap_set`. Evidence completeness requires four splits on
  every clean lap of a measured record (`:1160-1176`), which closes the Arcade Rush input gap. The
  `arcade_rush_factors` constant is loaded (`:556`), but no budget arithmetic is checked. That is
  correct, because reference records carry no budget field (budgets live in Event data,
  GAME_DESIGN:103).
- The intent README's remaining decisions 6–10 accurately describe what the validator does and does
  not enforce.

## Verdict

**Changes required (minor).** D1 and D4 are resolved. D3 and D3b are now explicit, justified unresolved
decisions. D5 and D6 are resolved, with small residuals (N4, N5). The new rules added for D2 and for
source timing, and the sector-split tolerance, are not adequately justified by the design contracts:

- N1: the pose lint is unsound in both directions under its own recorded frame and would reject a
  legitimate merge convoy.
- N2: the 12-tick source bound is inclusive, inconsistent with the slice's own staleness convention,
  and double-counts phase latency.
- N3: the 1/60 s split tolerance ignores GAME_DESIGN's microsecond crossing statement.

None of them breaks a shipped positive fixture, and each is a small change. Runtime claims (suite
counts, Ajv agreement and hashes) are **not verified** by this session; only the fixture and
test-function inventories were confirmed. M0 and the schema freeze remain open.
