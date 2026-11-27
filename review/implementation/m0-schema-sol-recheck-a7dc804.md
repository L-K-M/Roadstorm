# M0.9 independent scenario schema recheck

**Verdict — pass for this scoped provisional schema recheck.** The validator rejects direct self-reference and known co-location behind a shared predecessor. It accepts equal-gap convoys, mutual references between distinct cars, and positions left unknown.

| Item | Review scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `a7dc804aa62dd0244bf599b8486fe64fbd1359dd`, committed 2026-11-27 04:09:03 +01:00 |
| Base | `c416f43f6a4446e37f24ca7c7009ffd71880e426` |
| Review date | 2026-11-27, Europe/Zurich |
| Files | Scenario schema, validator, tests, fixtures and documentation. Compared the initial-state and matched-window design in `docs/BENCHMARKS.md` and `docs/TECHNICAL_DESIGN.md`, the historical Opus report for job `2a1763f5-22a3-4964-8bb8-64e2b66269f0`, and my prior report on c416f43. |

## Findings

1. **Resolved · Predecessor references.** The full validator rejects a direct self-reference and a nonexistent slot at `scenario.initial_state.per_participant_state.2.ahead_slot`. Equal-gap entries with distinct named predecessors pass. So do omission of the predecessor and a two-car cycle of distinct predecessor slots. The check imposes no ordering incompatible with a closed course. [Predecessor validation](../../fixtures/scenario/validate_scenario_contract.py#L1249)
2. **Resolved · Shared-reference position identity.** Same shared predecessor, same known gap and offset fail at `scenario.initial_state.per_participant_state.2.slot`, whether the added car changes speed or heading. Omitted and explicitly unknown gap or lateral offset each pass when otherwise valid, including the required unknowns explanation for an explicit null. [Position identity](../../fixtures/scenario/validate_scenario_contract.py#L1714)
3. **Open · Physical placement.** The check establishes identity from two known relative coordinates with a shared predecessor. Physical overlap and consistency of relative positions on a course still depend on a route-distance frame, separation or footprint rules, and runtime placement. No new blocking defect found in the scoped fixture contract. [Recorded design limit](../../schemas/scenario/README.md#L324)

## Verification

I confirmed the destination was ignored and exported `git archive a7dc804` into `work/agents/sol-schema-5-20261127/snapshot/`. Python 3.15.2 caches, scripts, logs, and rehashed fixtures are in its parent directory.

| Command from snapshot | Result |
| --- | --- |
| `env PYTHONPYCACHEPREFIX=../cache-scenario bash fixtures/scenario/run_tests.sh` | 89 tests pass and all 46 scenario fixtures behave as contracted. Matches the supplied copied-tree run. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | Eleven rehashed full-validator cases match the outcomes above. Inputs include `self.json`, `dangling.json`, `independent-leaders.json`, `circular-distinct.json`, `same-position-different-*.json`, and omitted/null coordinate cases. |
| `node ../ajv.cjs` | Local Ajv draft 2020-12 sweep validates all 11 schema documents and 23 positives. Of 128 negatives, 3 fail strict parsing, 32 fail the wrapper schema, and 93 pass the wrapper and are rejected by the project checks. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../audit.py` | Canonical hash sweep over 151 fixtures finds only the three intentional mismatches in the intent and observation `bad_content_hash.json` cases and scenario `bad_hash.json`. |

The other slice suites were outside this targeted rerun. This result covers authored fixture semantics and static schema contracts. It provides no runtime placement, measured capture, platform, hardware, or perceptual evidence. M0 and schema ratification remain separate gates.
