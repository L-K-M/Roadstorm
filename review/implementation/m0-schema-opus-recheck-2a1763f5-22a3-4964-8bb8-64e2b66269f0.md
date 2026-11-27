# M0.9 schema checkpoint recheck: independent Opus pass on c416f43

| Item | Value |
| --- | --- |
| Job | 2a1763f5-22a3-4964-8bb8-64e2b66269f0 |
| Reviewer model | Claude Opus 5.5 (`claude-opus-5-5`) |
| Provider | Anthropic first-party, through the Claude Code CLI |
| Date (UTC) | 2026-11-27 |
| Candidate | `c416f43f6a4446e37f24ca7c7009ffd71880e426` (c416f43, "Clarify schema timing and relative pose checks") |
| Base | cc5dac9 (`cc5dac91ed89b934defdd6d1240e729791885ccb`, the candidate of my earlier report `m0-schema-opus-recheck-12304df5-…`) |
| Inspected tree | `work/agents/2a1763f5-22a3-4964-8bb8-64e2b66269f0/snap` (copied snapshot, read only) |
| Verdict | **Changes required (minor).** Runtime results and the Ajv/hash sweep are **not verified** by me: no code ran in this session. |

M0 and the schema freeze stay open. This review closes neither.

## Scope and inputs

Inputs were the snapshot, my previous report
`review/implementation/m0-schema-opus-recheck-12304df5-b4fc-4ab9-902a-222107c96f9e.md` (N1–N6), and the
design documents in the snapshot. I did not consult the current Sol report (`m0-schema-sol-recheck-c416f43.md`),
spawned no agents or helpers, changed nothing in Git, and edited no source, asset, tool or template. The
only file written is this report. My scratch directory needed nothing written to it.

The snapshot has no `.git`, and I stayed inside it as the job required. So I could neither tie it to the
SHA myself nor diff it against cc5dac9. The snapshot is taken to be c416f43 as the job states. Each
"resolved" status below comes from reading the current code and docs, not from a diff.

Files read, in the relevant parts:

- `schemas/scenario/scenario.schema.json:140-200, 395-460` (`per_participant_state`, `participant_initial_state.ahead_slot`).
- `fixtures/scenario/validate_scenario_contract.py`: `:180` (`POSE_MEMBERS`), `:186-207` (sector rounding
  constant), `:975-1010` (clean-lap accounting), `:1230-1275` (`ahead_slot` membership),
  `:1701-1750` (`check_participant_pose_distinctness`).
- `fixtures/scenario/tests/test_validate_scenario_contract.py:390-432` (sector bound tests) and `:1060-1146`
  (`ParticipantPoseDistinctnessTests`).
- `fixtures/scenario/positive/fixture.scenario.tactical_window_slower_lead.json:110-150` and
  `fixtures/scenario/negative/bad_pose_identity.json` (description, `ahead_slot` lines, note).
- `schemas/scenario/README.md:185-200, 310-345` (pose identity and the sector-split recorded decisions);
  `fixtures/scenario/README.md:15-35`.
- `fixtures/intent/validate_intent_contract.py:1687-1880` (`check_source_observation`);
  `fixtures/intent/tests/test_validate_intent_contract.py:722-800`; `fixtures/intent/README.md:90-94, 315-365`
  (decisions 5, 6, 8 and 12); `schemas/intent/tactical_intent.schema.json:360-381` (grep).
- `schemas/README.md:1-12, 135-200` (historical record and "Later checks").
- `docs/GAME_DESIGN.md:79, 103, 123` and `docs/REVIEW_RESPONSE.md:57, 159`, used to verify the citations.

## Commands and results

| Command | Result |
| --- | --- |
| `grep -rn ahead_slot` over `*.py`, `*.json` and `*.md` | Schema member, validator membership and pose checks, 3 unit tests, the positive `slower_lead` (evaluated → `lead`) and `bad_pose_identity` (both entries → `lead`) |
| `grep -c "def test_"` over the four suites | handling **59**, observation **37**, intent **30**, scenario **84**. These match the coordinator's counts (static count; it assumes no parametrized test) |
| `ls` and `grep -c '\.expected'` over `fixtures/{observation,intent,scenario}/{positive,negative}` | observation 6 + 38 = **44**, intent 6 + 47 = **53**, scenario 3 + 41 = **44**. These match the coordinator's counts (inventory only) |
| `grep` over `docs/` for the GAME_DESIGN and REVIEW_RESPONSE citations | All cited statements exist as quoted (`GAME_DESIGN:79` integer microseconds, `:103` millisecond budgets, `:123` 0–200 ms phase latency; `REVIEW_RESPONSE:57` and `:159`) |
| `python3 -B -m unittest discover -s fixtures/scenario/tests -t .` | **Refused** (approval required; non-interactive) |
| `mkdir`/`cp -R` of the snapshot into `/tmp` scratch | **Refused** (approval required) |

## Capability limits

- **No code was executed.** The coordinator's copied-tree results (handling 59; observation 37/44;
  intent 30/53; scenario 84/44) are **not verified by me**. I confirmed only that the test-function and
  fixture-case inventories match them.
- **The Ajv sweep and content-hash recomputation were not run.** I also found no in-tree record of them
  for c416f43 (see F4).
- The repros below were not run. Each one gives the input, the code path and the result I expect from
  reading that path.

## Status of earlier findings (cc5dac9 report)

| ID | Earlier finding | Status at c416f43 (static) |
| --- | --- | --- |
| N1 | Pose lint rejects legitimate equal-gap convoys; negative misnamed | **Resolved.** The comparison now requires a shared, explicitly named `ahead_slot` (`validate_scenario_contract.py:1728-1736`). Entries without one are never compared. My convoy repro (A 20 m behind `lead`, B 20 m behind A, same tuple) passes whether `ahead_slot` is omitted or set to the true predecessor (`test_identical_relative_poses_without_shared_reference_are_a_legal_convoy`, `test_different_named_predecessors_are_not_compared`). `ahead_slot` must name a participant (`:1249-1258`). The negative is renamed `bad_pose_identity`, and its description makes no collision claim. Residual defects: **F1–F3**. |
| N2 | Source-timing bound inclusive at 12; double-counted phase latency | **Resolved.** The bound is now `0 <= delay < sampling_period_ticks` (`validate_intent_contract.py:1852-1876`). Unit tests cover delay 11 (accepted), 12 and −1 (rejected) (`tests:742-772`). Decision 6 (`README:319-332`) records the rationale and states that a sub-period delay is reported as end-to-intent latency. The citations check out. I accept that exact synchrony is not required, because no document fixes it. |
| N3 | 1/60 s sector tolerance not derived; hid a one-tick bug | **Resolved.** The bound is now `(sector_count + 1) × 0.5 ms = 2.5 ms` (`:194-206, 994-996`). The recorded decision cites GAME_DESIGN:79 and :103, labels applying them to timing gates as an inference, and names microsecond storage as the M1 tightening. A one-tick error (`10.0167`) and a 2.6 ms error are rejected (`tests:415-430`). Nit: **F5**. |
| N4 | No Ajv/hash sweep tied to a SHA | **Partly resolved.** "Later checks" (`schemas/README.md:142-160`) now names the full cc5dac9 SHA, the export method, the Ajv breakdown and the hash sweep. It also says plainly that the c416f43 follow-ups are not covered and need a fresh sweep. Still open for this candidate: **F4**. The line-6 formatting nit was fixed. |
| N5 | Width for action 0's corridor implicit | **Resolved** as remaining decision 8 (`fixtures/intent/README.md:339-345`). |
| N6 | A fixture cannot begin mid-commitment | **Resolved** as remaining decision 12 (`README:362`). |

## Ranked findings (static)

### F1: Low-medium. The co-location key includes speed and heading, so provably co-located cars pass

- The schema (`scenario.schema.json:178`) and `schemas/scenario/README.md:191-196, 321-325` justify the
  rejection because such cars are "provably co-located". Position at t0 is fixed by the shared reference
  car, `forward_gap_m` and `lateral_offset_m` alone. `speed_m_s` and `heading_offset_deg` do not move a car.
- The check compares the full `POSE_MEMBERS` tuple (`:180, 1726, 1732`). So two cars 10 m behind `lead` at
  lateral 0 are accepted if one runs at 30 m/s and the other at 29 m/s, or if their headings differ by 5°.
  By the contract's own reasoning, those cars occupy one place.
- `test_heading_alone_distinguishes_two_participants` (`tests:1131-1145`) now sets no `ahead_slot`. It
  passes through the "no shared reference" branch and no longer tests what its name says. With a shared
  `ahead_slot`, the behaviour it names would be the defect described above.
- **Repro (not run):** in `ParticipantPoseDistinctnessTests`, call
  `self._add_traffic(doc, ahead_slot="lead", speed_m_s=29)`. Expected: `[]`, so a co-located pair is
  accepted.
- **Fix:** key the comparison on `(ahead_slot, forward_gap_m, lateral_offset_m)` and ignore speed and
  heading. Then rewrite the heading test to assert rejection with a shared `ahead_slot`. Alternatively,
  keep the full-tuple rule but drop the "provably co-located" justification and call it an
  identical-authoring lint only.

### F2: Low. Undetermined gaps are treated as equal and flagged as co-location

- The signature uses `entry.get(member)`, so an absent or `null` member counts as `None == None`. Only an
  all-`None` signature is skipped (`:1726-1728`).
- Two entries that both name `ahead_slot: "lead"`, leave `forward_gap_m` absent or `null` (the schema says
  null means undetermined, with an `unknowns` entry), and share lateral, speed and heading are rejected as
  "co-located rather than distinguishable cars". The gap that would prove co-location is unknown, so the
  rejection is unsupported.
- **Repro (not run):** add scripted `traffic_1` and `traffic_2` to the slower-lead fixture, each with
  `{"ahead_slot": "lead", "lateral_offset_m": 3.5, "speed_m_s": 25, "heading_offset_deg": 0}` and no gap.
  Expected: a `participant_pose_distinctness` failure at `per_participant_state.3.slot`.
- **Fix:** compare only entries whose `forward_gap_m` and `lateral_offset_m` are both non-null numbers.
  This fits F1's key.

### F3: Low. `ahead_slot` may name the entry's own slot

- The only `ahead_slot` validation is membership in the participant set (`:1249-1258`). An entry with
  `slot: "evaluated", ahead_slot: "evaluated", forward_gap_m: 10` is accepted. It describes a gap to
  itself, which the schema's "slot of the car ahead" (`:415-418`) cannot mean.
- Two-entry cycles (A ahead of B and B ahead of A, both with positive gaps) are also accepted. That is a
  physically impossible ordering on an open section. The self-reference is the cheap, unambiguous part.
  A cycle check is optional, because closed-loop wraparound needs an ordering frame the contract lacks.
- **Repro (not run):** add `"ahead_slot": "evaluated"` to the evaluated entry of the positive fixture.
  Expected: no failure from `initial_state_agreement` or the pose check.
- **Fix:** reject `ahead_slot == slot` under `initial_state_agreement`, with a unit test.

### F4: Low (evidence gate). No Ajv, hash or suite evidence is recorded for c416f43

- c416f43 changes at least one positive fixture (`tactical_window_slower_lead` gains `ahead_slot`, which
  changes its `content_hash` input) and renames and edits a negative (`bad_pose_identity`). It also changes
  the schema document (`ahead_slot` member) and three validators.
- The only in-tree sweep is for cc5dac9. `schemas/README.md:164-170` says a fresh sweep is required on the
  successor. That statement is honest, but the sweep itself is not there. In this session I could not run
  Ajv, the hash recompute or the suites. The coordinator's copied-tree suite totals (59; 37/44; 30/53;
  84/44) live outside the tree and are not tied to c416f43 in any in-tree record I could read.
- **Fix:** run the Ajv 8 draft 2020-12 sweep and the content-hash recompute on the exact c416f43 export (or
  its successor), and record the SHA, the breakdown (positives valid; negatives split into
  parse/wrapper/semantic) and the log paths, as was done for cc5dac9. Until then, schema-layer agreement and
  hash integrity for this candidate are **not verified**.

### F5: Nit. The 2.4 ms "within bound" test value cannot arise under the stated millisecond model

If the splits and the lap are each stored at millisecond granularity, `Σ round(t_i) − round(L)` is a whole
number of milliseconds, at most 2 ms for four sectors. If the splits are differences of stored crossing
timestamps (GAME_DESIGN:79), they telescope exactly. The 2.5 ms bound is therefore safe, but
`[10.0006] × 4` (`tests:404-412`) uses sub-millisecond values the model rules out. Consider `[10.0005]` ×
4 against a `40.002` lap, or a 2 ms integer case, so that the test exercises the derivation it cites. No
change to the bound is needed.

## Checked and consistent (static)

- **Equal-gap convoys:** legal whether `ahead_slot` is omitted or names each car's true predecessor. The
  merge-family authoring of `docs/BENCHMARKS.md` "multi-car merge" is no longer rejected.
- **Optional `ahead_slot`:** omission keeps existing single-car-follow fixtures valid, and naming a
  non-participant is rejected. The schema, both READMEs and the docstring describe the same semantics.
  F1 and F2 concern the key, not the optionality.
- **Observation age boundary:** the exclusive `< 12` bound matches `intent_staleness_ticks` ("at or
  beyond" 12 is stale) and the half-open hold window. The README age row (`:94`) and decision 6 state
  0–11 ticks. Every shipped resolvable link still has delay 0 (from my earlier inventory; I did not recount
  it here).
- **Sector tolerance:** the derivation and its inference caveat are recorded, and the one-tick bug class is
  now rejected.
- **Inventories:** test-function and fixture-case counts match the coordinator's numbers.

## Verdict

**Changes required (minor).** N1, N2, N3, N5 and N6 are resolved. N4 is resolved for cc5dac9 but open for
this candidate. The new `ahead_slot` rule has three small defects:

- F1: its key includes speed and heading, so it misses co-location by its own rationale, and one test is
  now vacuous.
- F2: it flags undetermined gaps as co-location.
- F3: an entry may name itself as its car ahead.

Each is a few lines plus a unit test, and none breaks a shipped positive. F4 (no Ajv/hash/suite record tied
to c416f43) blocks a "pass" on evidence. Runtime and schema-layer claims for this candidate are **not
verified** by this session. M0 and the schema freeze remain open.
