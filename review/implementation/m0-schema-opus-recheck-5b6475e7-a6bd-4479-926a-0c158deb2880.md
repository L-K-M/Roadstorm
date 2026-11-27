# M0.9 schema scoped recheck: independent Opus pass on a7dc804

| Item | Value |
| --- | --- |
| Job | 5b6475e7-a6bd-4479-926a-0c158deb2880 |
| Reviewer model | Claude Opus 5.5 (`claude-opus-5-5`) |
| Provider | Anthropic first-party, through the Claude Code CLI |
| Date (UTC) | 2026-11-27 |
| Candidate | `a7dc804aa62dd0244bf599b8486fe64fbd1359dd` (a7dc804, "Reject invalid relative scenario positions") |
| Base | c416f43 (`c416f43f6a4446e37f24ca7c7009ffd71880e426`, the candidate of my earlier report `m0-schema-opus-recheck-2a1763f5-…`) |
| Inspected tree | `work/agents/5b6475e7-a6bd-4479-926a-0c158deb2880/snap` (copied snapshot, read only) |
| Verdict | **Pass (static, scoped)** for the pose and `ahead_slot` rules. Suite, Ajv and hash results are **not verified**: no code ran in this session. |

This review accepts neither M0, the schema freeze, nor any physical-placement or collision semantics.

## Scope and inputs

The inputs were the snapshot, my previous report
`review/implementation/m0-schema-opus-recheck-2a1763f5-22a3-4964-8bb8-64e2b66269f0.md` (F1–F5), and the related
design documents in the snapshot. I did not read the current Sol report (`m0-schema-sol-recheck-a7dc804.md`). I
spawned no agents or helpers, changed nothing in Git, and edited no source, asset, tool or template. I created
the empty private scratch directory `work/agents/5b6475e7-…/scratch`. Copying the snapshot into it was refused
(see below), so it stays empty. The only other file written is this report.

The snapshot has no `.git`. I therefore could neither tie it to the SHA myself nor diff it against c416f43. I
took it to be a7dc804, as the job states. Each "resolved" status below comes from reading the current code,
tests, fixtures and documents, not from a diff.

Files read (relevant parts):

- `fixtures/scenario/validate_scenario_contract.py`: `:181` (`POSE_POSITION_MEMBERS`), `:254-266` (loader),
  `:363-365` (`_is_number`), `:1200-1283` (`initial_state_agreement`, `ahead_slot` membership and
  self-reference), `:1714-1773` (`check_participant_pose_distinctness`), `:2101-2119` (semantic checks run
  only on schema-valid documents).
- `fixtures/scenario/tests/test_validate_scenario_contract.py`: `:390-430` (sector bounds), `:771-859`
  (self-reference, distinct-predecessor convoy, mutual references), `:1153-1278`
  (`ParticipantPoseDistinctnessTests`).
- `schemas/scenario/scenario.schema.json:161-178, 415-440` (`forward_gap_m`, `lateral_offset_m`,
  `per_participant_state`, `ahead_slot`, `participant_initial_state`).
- Fixtures: `positive/fixture.scenario.tactical_window_slower_lead.json:112-136`; `negative/bad_pose_identity`,
  `negative/bad_pose_same_position_different_motion`, `negative/bad_ahead_slot_self_reference` (documents and
  `.expected.json`).
- `schemas/scenario/README.md:185-200, 320-341`; `fixtures/scenario/README.md:15-32, 55-79`;
  `schemas/README.md:140-175`; `docs/STATUS.md:246-262`. I grepped `docs/*.md` and `PLAN.md` for collision,
  footprint and co-location wording (TECHNICAL_DESIGN:87-89, GAME_DESIGN:51).

## Commands and results

| Command | Result |
| --- | --- |
| `grep -c "def test_"` over `fixtures/scenario/tests/*.py` | **89**. This matches the coordinator's count. It is a static count and assumes no parametrized tests. |
| `ls` and `grep -c` over `fixtures/scenario/{positive,negative}` | 3 positives + 43 negatives (43 `.expected.json`) = **46**. This matches the coordinator's count (inventory only). |
| `grep -rn -e a7dc804 -e c416f43` over `schemas fixtures docs` | No in-tree Ajv, hash or suite record for c416f43 or a7dc804. Only STATUS narrative lines mention them. |
| `mkdir -p …/scratch` | OK (empty directory). |
| `cp -R snap scratch/tree` | **Refused** (`cp` with flags needs manual approval). |
| `sh snap/fixtures/scenario/run_tests.sh` with `PYTHONDONTWRITEBYTECODE=1` | **Refused** (needs approval; the session is non-interactive). |
| `python3 -B -m unittest discover -s snap/fixtures/scenario/tests -t snap/fixtures/scenario` | **Refused** (needs approval). |

## Capability limits

- **No code was executed.** The coordinator's copied-tree result (89 tests and 46 scenario fixtures passing) is
  **not verified by me**. I confirmed only that the test-function and fixture-case inventories match it.
- **The Ajv 8 sweep and the content-hash recompute were not run.** a7dc804 adds two negatives and changes
  schema descriptions, so their hashes and schema-layer outcomes for this candidate are unverified.
- The other three suites (handling, observation, intent) were outside this scoped recheck and were not
  recounted.
- I did not run the repros or reasoning below. Each one states the input, the code path and the result I
  expect from reading that path.

## Status of my earlier findings (c416f43 report)

| ID | Earlier finding | Status at a7dc804 (static) |
| --- | --- | --- |
| F1 | Co-location key included speed and heading | **Resolved.** The key is now `(ahead_slot, forward_gap_m, lateral_offset_m)` (`:181, 1741-1759`). `test_shared_reference_with_equal_position_but_different_motion_is_rejected` (`tests:1224-1244`) covers a speed difference, a heading difference and both, and asserts rejection at `per_participant_state.2.slot`. The new negative `bad_pose_same_position_different_motion` (29 m/s, 5°, shared `lead`) pins the same rule. The vacuous heading test is gone. The failure message states that speed and heading do not move a car. |
| F2 | Undetermined gaps were treated as equal | **Resolved.** An entry is compared only when both position members pass `_is_number` (`:1741-1743`), which excludes `None`, an absent member and booleans. `test_undetermined_gap_is_not_treated_as_equal` (`:1254-1278`) covers an absent gap behind a shared `lead`. Explicit `null` and a null lateral offset take the same branch but have no test of their own (N3). |
| F3 | `ahead_slot` could name the entry's own slot | **Resolved.** `elif ahead == slot` (`:1261-1272`) rejects self-reference under `initial_state_agreement` at `….ahead_slot`. The ordering is sound: non-members are rejected first, and duplicate or unknown slots `continue` before this check. The rule is covered by a unit test (`:771-802`) and by the negative `bad_ahead_slot_self_reference` (expected path `per_participant_state.2.ahead_slot`). |
| F4 | No Ajv, hash or suite record tied to the candidate | **Open as an evidence limit, not a code defect.** "Later checks" in `schemas/README.md` still covers only cc5dac9, and says so. A commit cannot record its own SHA, so this belongs in the coordinator's sweep for a7dc804 (see N4). |
| F5 | The 2.4 ms test value could not arise under the millisecond model | **Resolved.** The test now uses whole-millisecond splits `[10.001, 10.001, 10.001, 9.999]` = 40.002 s against a 40 s lap (2 ms) (`tests:404-414`). |

## Scoped checks requested by the job

- **Self-ahead rejection:** correct and minimal (F3 above). It is reported under `initial_state_agreement`.
  Semantic checks run only on schema-valid documents (`:2113-2118`), so a non-string `ahead_slot` cannot
  reach the set-membership test and raise `TypeError` on an unhashable value.
- **Legitimate equal-gap convoys:** legal. Entries are compared only when both name the same string
  `ahead_slot` (`:1759`). This is covered without `ahead_slot` (`tests:1192-1197`), with different named
  predecessors (`:1211-1215`, `:1246-1252`), and in the full pipeline with a `lead`/`evaluated` chain at
  identical tuples (`:804-830`).
- **Distinct-car circular ordering:** A→B and B→A with positive gaps is not rejected (`:832-859`). The schema
  (`:418`), both READMEs and the self-reference message state the closed-course rationale. Because the two
  entries name different references, the pose check does not compare them either. That is consistent.
- **Known shared-reference position equality independent of motion:** implemented as described (F1). JSON `10`
  and `10.0` compare equal after `float()`. `-0.0 == 0.0` for the lateral offset, which is correctly treated
  as the same place.
- **Unknown/null coordinates:** never assumed equal (F2). An entry without a usable pose is simply not
  compared, which matches the schema's "null means undetermined" plus the `unknowns` requirement.
- **Scope versus physical collision:** the check is an exact-duplicate authoring lint. Within that scope it
  is sound. With one shared reference car, a gap measured to that car and a centerline-relative lateral
  offset, equal numbers name one point, whatever the gap convention (bumper or centre). The documents do not
  overclaim:
  - `schemas/scenario/README.md:324-340` states that no tolerance, footprint or absolute route frame exists,
    that near-equal tuples are never collisions, and that the negative is "not a collision claim".
  - The docstring says the same (`:1728-1730`).
  - It is also right not to derive transitive positions through chains (A behind `lead`, B behind A,
    C behind `lead` at the summed gap). The contract does not say whether `forward_gap_m` runs bumper to
    bumper or centre to centre, so summed gaps would differ by unknown car lengths. Equal sums do not prove
    co-location.
  - Physical overlap (10 m vs 10.5 m behind one car at lateral 0, or a 1 m gap to the car ahead) remains
    accepted and unaddressed. That is a documented open design issue (absolute route frame and
    minimum-separation rule) and is outside this lint's scope. It must not be read as placement acceptance.

## Ranked findings (static, all low or nit)

### N1: Low (docs). `fixtures/scenario/README.md` still describes the old full-tuple key

- `fixtures/scenario/README.md:24-26` says entries are rejected when they "name the same `ahead_slot` and
  agree on **every relative pose member**". Since F1, the rule compares only `forward_gap_m` and
  `lateral_offset_m`. The paragraph is a dated history entry (the cd8a5eda follow-up), but nothing marks
  it as superseded.
- `scenario.schema.json:178` (`per_participant_state` description) still says "declare the same relative
  pose". The neighbouring `:418` and `:440` descriptions define it correctly as gap plus lateral only.
- **Fix:** amend the README sentence (or add "superseded by the a7dc804 position-only key"), and say
  "same forward gap and lateral offset" in `:178`.

### N2: Nit (docs). "Signed" forward gap contradicts the schema

The docstring (`:1721-1722`) and `schemas/scenario/README.md:327-328` speak of a "signed forward gap". Both
`forward_gap_m` definitions have `exclusiveMinimum: 0` (`schema:161-164, 420-423`), so the gap is a positive
distance to the car ahead. **Fix:** drop "signed".

### N3: Nit (tests). Null-coordinate and duplicate-test coverage

- No test covers an explicit `"forward_gap_m": null` or a null or absent `lateral_offset_m` behind a shared
  reference. The code path is the same `_is_number` gate, so this is coverage only.
- `test_different_named_predecessors_are_not_compared` (`:1211-1215`) and
  `test_same_position_without_shared_reference_is_not_compared` (`:1246-1252`) have identical bodies.
- **Fix:** turn one duplicate into the explicit-null case (both entries `ahead_slot: "lead"`, one or both
  members `null`, expect `[]`).

### N4: Low (evidence gate, carried from F4). No Ajv, hash or suite record for a7dc804

a7dc804 adds `bad_ahead_slot_self_reference` and `bad_pose_same_position_different_motion` and changes schema
descriptions. Until someone runs the Ajv 8 draft 2020-12 sweep, the content-hash recompute and all four suites
on the exact a7dc804 export, and records the SHA, breakdown and logs as was done for cc5dac9, schema-layer
agreement and hash integrity for this candidate are **not verified**. This blocks acceptance on evidence. It
does not block the logic.

### N5: Nit (fixture prose). The base fixture's note still credits speed and heading for distinguishability

The evaluated entry's note in `tactical_window_slower_lead.json:124` (also copied into the derived negatives)
says that the lead and the evaluated slot "are distinguishable by forward gap, speed and heading". Under the
new rule, only the 10 m gap behind `lead` separates them. **Optional:** reword when the fixture is next
re-hashed. Changing it alters `content_hash`, so do it in a batch that is re-swept anyway.

## Verdict

**Pass (static, scoped).** All three code defects from my c416f43 report are fixed with matching unit tests and
negatives: F1 (position-only key), F2 (null/absent coordinates not compared) and F3 (self-reference
rejected). F5 is fixed too. Equal-gap convoys and mutual references between distinct cars stay legal. The
documents describe the check as an identity lint, not a collision check. The remaining items are
documentation and coverage nits (N1–N3, N5) and the evidence gate (N4).

The runtime results (89 tests and 46 scenario fixtures), the Ajv sweep and the hash integrity for a7dc804 are
**not verified** by this session: execution was refused. M0, the schema freeze, the physical-placement and
minimum-separation semantics, and the absolute pose frame are **not accepted** by this review and remain open.
