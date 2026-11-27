# M0.9 independent schema recheck

**Verdict — pass for the provisional schema checkpoint.** The four findings from the prior Sol report are resolved on this candidate. This verdict covers the immutable schema and fixture paths. M0 acceptance and schema ratification remain separate gates.

| Item | Review scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `cc5dac91ed89b934defdd6d1240e729791885ccb`, committed 2026-11-27 03:22:52 +01:00 |
| Base | `d1827be92bec746696090929a069af95e1d7b0a3` |
| Review date | 2026-11-27, Europe/Zurich |
| Files | Candidate `schemas/**` and `fixtures/**`, checkpoint rules in `plan/IMPLEMENTATION.md`, contract sections in `docs/BENCHMARKS.md`, `docs/TECHNICAL_DESIGN.md`, `docs/OPPONENT_AI.md`, `docs/GAME_DESIGN.md`, and `docs/REVIEW_RESPONSE.md`. Rechecked my [prior report](m0-schema-sol-recheck-d1827be.md). |

## Prior findings

1. **Variable road width resolved.** The previous rehashed 12 m local / 10 m ahead case passes, and the new positive varying-width fixture passes. The linkage compares shared source fields without using the 20 m lookahead as local decode geometry. Corridor validation remains in the standalone intent check. [Source contract](../../fixtures/intent/validate_intent_contract.py#L1687) · [Lookahead feature](../../schemas/observation/observation_record.schema.json#L223)
2. **Unbounded source delay resolved.** Independently generated offsets of −1, +13, and +1,200 ticks fail at `records.0.generated_tick`. Offsets of 0, +1, +11, and +12 ticks pass with the source's declared Expert traffic age of seven ticks. The inclusive 12-tick upper bound corresponds to the documented 0–200 ms phase allowance. The two ages remain distinguishable by observation sample and intent generation timestamps. [Link check](../../fixtures/intent/validate_intent_contract.py#L1847) · [Difficulty and planning latency](../../docs/GAME_DESIGN.md#L123)
3. **Duplicate identity resolved.** The original rehashed repeated intent ID now fails at `records.1.intent_id`, and the repeated illustrative observation ID fails at `records.2.source_observation_id`. The fixture is one participant's sequence. Deployed telemetry must preserve uniqueness across the set of proposals counted together. [Intent identity](../../fixtures/intent/validate_intent_contract.py#L1593) · [Record sequence](../../fixtures/intent/validate_intent_contract.py#L1631) · [Illustrative source check](../../fixtures/intent/validate_intent_contract.py#L1736)
4. **Inconsistent measured sector totals resolved.** Synthetic accounting now rejects four 100 s splits for a 40 s clean lap. Differences of 0, 1 ms, and 16 ms pass, and 17 ms fails. One fixed tick is a provisional consistency bound consistent with the 60 Hz timing contract. The capture format's precision still needs to be defined at M1. [Accounting check](../../fixtures/scenario/validate_scenario_contract.py#L982) · [Precision decision](../../schemas/scenario/README.md#L329)

## Open design decisions and follow-through

- **Nonblocking · Pin the runtime observation schedule and report end-to-intent age.** The fixture allows one period between observation sampling and intent generation. This is an envelope for recorded planning phase latency. Runtime evidence must establish how ego and road data stay current, how discretionary traffic uses the delayed snapshot, and how the current guard stays immediate. For example, an accepted Expert fixture at the +12-tick boundary has a seven-tick delay at observation sampling and a 19-tick offset from the traffic snapshot to intent generation. It does not establish that the running planner uses that schedule. [Observation timestamp semantics](../../schemas/observation/observation_record.schema.json#L80) · [Cadence review decision](../../docs/REVIEW_RESPONSE.md#L57)
- **Nonblocking · Preserve the documented fixture limits into the relevant implementation gates.** M4.2 still owns hold/interruption telemetry, refused commitment, retain-state continuity and post-reset defaults, plus the stale-intent, replacement, and intervention export and category decisions. M4.3 still owns tuned pace intervals. Scenario pose validation compares authored tuples. Its longitudinal reference frame and physical separation rule remain open, as does measured sector capture precision at M1. [Intent design decisions](../../fixtures/intent/README.md#L114) · [Sequence and intent decisions](../../fixtures/intent/README.md#L328) · [Scenario decisions](../../schemas/scenario/README.md#L317)

## Verification

I verified `work/agents/` is ignored and exported with `git archive cc5dac9` into `work/agents/sol-schema-3-20261127/snapshot/`. These checks used Python 3.15.2 with separate cache prefixes beside the snapshot. Logs, probe scripts, and mutated inputs are in its parent directory.

| Command from the snapshot | Result |
| --- | --- |
| `bash schemas/handling/run_tests.sh` | 59 tests pass. Eight fixtures and the schema pass without warnings. |
| `bash fixtures/observation/run_tests.sh` | 37 tests pass and all 44 fixtures behave as declared. |
| `bash fixtures/intent/run_tests.sh` | 30 tests pass and all 53 fixtures behave as declared. |
| `bash fixtures/scenario/run_tests.sh` | 83 tests pass and all 44 fixtures behave as declared. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | Reproduced the repaired outcomes above. Rehashed inputs include `current-width-differs-from-lookahead.json`, `source-observation-20-seconds-stale.json`, `source-offset-*.json`, `duplicate-intent-id.json`, and `duplicate-illustrative-source.json`. Sector cases run on in-memory synthetic records. |
| `node ../ajv.cjs` | The local Cline-bundled Ajv validates all 11 schema documents and all 23 positive fixtures as draft 2020-12. Of the 126 observation, intent, and scenario negatives, 3 fail strict parsing, 32 fail the wrapper schema, and 91 pass the wrapper schema and are rejected by project checks. |

The suite totals match the earlier supplied copied-tree results. The intent suite also covers commitment across resets, false interruption, and single-participant sequence consistency. The scenario suite covers shared comparison-arm difficulty. I found no new acceptance-blocking regression in this scope. Runtime observation chronology, reset behavior, Float32 parity, measured references, actual intervention counts, controller and platform checks, and perceptual evidence remain unverified.
