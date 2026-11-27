# M0.9 independent schema recheck

**Verdict — pass for the provisional schema checkpoint.** The scoped changes resolve the preceding convoy, source-age, sector-tolerance, and exact-candidate evidence findings. One nonblocking validation gap remains for self-referential predecessor slots.

| Item | Review scope |
| --- | --- |
| Reviewer | GPT-6.2 Sol, native OpenAI Codex |
| Candidate | `c416f43f6a4446e37f24ca7c7009ffd71880e426`, committed 2026-11-27 03:50:22 +01:00 |
| Base | `cc5dac91ed89b934defdd6d1240e729791885ccb` |
| Review date | 2026-11-27, Europe/Zurich |
| Scope | Candidate schema and fixture slices, relevant contract passages in `docs/{BENCHMARKS,GAME_DESIGN,OPPONENT_AI,TECHNICAL_DESIGN}.md`, my Sol report on cc5dac9 and the historical Opus report for job `12304df5-b4fc-4ab9-902a-222107c96f9e`. |

## Recheck findings

1. **Resolved · Equal-gap convoy.** The full validator accepts identical tuples with an omitted or distinct predecessor and rejects identical tuples behind the same named lead. A nonexistent predecessor fails `initial_state_agreement`. The renamed negative represents a relative identity check. Neither equal speed nor an exact tuple threshold provides a full spatial separation test. The absolute frame and footprint/separation rule remain open. [Pose lint](../../fixtures/scenario/validate_scenario_contract.py#L1704) · [Recorded pose decision](../../schemas/scenario/README.md#L319)
2. **Resolved · Half-open source age.** Rehashed probes at offsets 0, 1, and 11 ticks pass. Offsets −1, 12, 13, and 1,200 fail. The fixture guard permits sub-period delay and rejects an entire missed sample. Actual runtime ego/road freshness, source alignment, and total traffic-snapshot-to-intent latency still require implementation evidence. The previous varying-width positive and repeated ID cases retain their corrected behavior. [Timing check](../../fixtures/intent/validate_intent_contract.py#L1847) · [Phase allowance](../../docs/GAME_DESIGN.md#L123)
3. **Resolved · Sector arithmetic.** The independent synthetic measured probe accepts discrepant sums of 2.4 and 2.5 ms on the 40 s sample, and rejects 2.6 ms, one 60 Hz tick, and the original 400 s split total. Four independently rounded splits and an independently rounded lap total yield a 2.5 ms conservative bound at millisecond granularity. Final precision is an M1 capture decision. [Accounting check](../../fixtures/scenario/validate_scenario_contract.py#L985) · [Precision decision](../../schemas/scenario/README.md#L330)
4. **Resolved · Exact-candidate evidence.** The earlier evidence table identifies cc5dac9 and explicitly excludes its successor. The fresh results below tie the checks to c416f43. The follow-up documents corridor width selection and mid-commitment capture as open decisions. [Schema evidence history](../../schemas/README.md#L143) · [Intent decisions](../../fixtures/intent/README.md#L350)

## Nonblocking finding

- **Low · A participant can name itself as the car ahead.** The full validator accepts a rehashed `traffic_1` entry with `ahead_slot: traffic_1` and a positive 10 m gap at `scenario.initial_state.per_participant_state.2.ahead_slot`. The full repro is `work/agents/sol-schema-4-20261127/convoy-traffic_1.json`. The lookup checks membership only. The dangling-slot repro `convoy-unknown.json` fails at that exact path. A named predecessor with an omitted gap and mutual predecessor names both pass; the current contract neither requires a gap when the name is supplied nor defines a common longitudinal frame or cycle policy for closed courses. Before consuming this reference in scenario setup, reject direct self-reference and add the case beside the existing unknown-slot coverage. This guard follows from naming a distinct car ahead and does not require a decision on absolute position frames. No shipped positive uses a self-reference. [Ahead-slot schema](../../schemas/scenario/scenario.schema.json#L415) · [Membership check](../../fixtures/scenario/validate_scenario_contract.py#L1249)

## Verification

I confirmed the destination is ignored and exported `git archive c416f43` into `work/agents/sol-schema-4-20261127/snapshot/`. The suite logs, separate Python 3.15.2 caches, and scripts and generated inputs remain in its parent directory. The independent suite outputs agree with the prior copied-tree counts.

| Command from the snapshot | Result |
| --- | --- |
| `bash schemas/handling/run_tests.sh` | 59 tests pass. Eight fixtures and the schema pass without warnings. |
| `bash fixtures/observation/run_tests.sh` | 37 tests pass and all 44 fixture cases behave as declared. |
| `bash fixtures/intent/run_tests.sh` | 30 tests pass and all 53 fixture cases behave as declared. |
| `bash fixtures/scenario/run_tests.sh` | 84 tests pass and all 44 fixture cases behave as declared. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../probe.py` | Confirms the outcomes above. Rehashed cases are stored as `convoy-*.json`, `source-offset-*.json`, and the replayed prior intent mutants. Measured sector probes run in memory. |
| `node ../ajv.cjs` | Local Ajv draft 2020-12 sweep validates all 11 schema documents and all 23 positives. Of 126 observation, intent, and scenario negatives, 3 fail strict parsing, 32 fail wrapper validation, and 91 pass the wrapper and are rejected by project checks. |
| `env PYTHONPYCACHEPREFIX=../cache-probe python3 ../audit.py` | Recomputed canonical hashes over 149 fixture files, including the parse-error negatives for this hash-only check. Only `fixtures/intent/negative/bad_content_hash.json`, `fixtures/observation/negative/bad_content_hash.json`, and `fixtures/scenario/negative/bad_hash.json` disagree as intended. |

This review verifies fixture and schema behavior, including synthetic measured arithmetic. Runtime observation scheduling and reset behavior, physical placement, capture format and real reference runs, platform/controller/perceptual checks, and M0 acceptance remain outside this verdict.
