# M0.9 schema-definition decision — 2026-11-27

**Decision:** the M0.9 requirement to create versioned handling, AI, reference and scenario schemas and initial BENCHMARKS fixture configurations is complete as a **definition-only** checkpoint. This does not freeze runtime AI or handling semantics, validate physical placement or measured references, or accept M0 as a whole.

## Exact input and verification

- Definition source reviewed by the named pair: `a7dc804aa62dd0244bf599b8486fe64fbd1359dd`. At coordinator decision source `9c7fe2be9598cc1f3c5bd094e18f3c670aba5570`, `schemas/**` still has Git tree `f777c9e4c6ff24e4a4584c31832e4683b132d02d` and `fixtures/**` still has tree `e8ec78c634519ffefd40d1395d9a25885cc2525b`. The coordinator independently checked both tree IDs and clean paths.
- Existing contracts: `schemas/handling/`, `schemas/observation/`, `schemas/intent/`, `schemas/scenario/`, `schemas/common.schema.json`; eight BENCHMARKS handling fixture configurations under `fixtures/handling/`, plus versioned observation, intent, scenario and planned-reference fixtures. The earlier partial top-level observation draft is explicitly identified as unaccepted in `schemas/README.md`.
- LongCat 2.5 read-only audit `work/agents/97b6d466-d79b-4c3d-8a71-d1303ea8dc46/REPORT.md` exported `9c7fe2b` with `git archive` and ran each suite once with a 180-second bound. The coordinator inspected the logs: handling 59/59 tests and 8 shipped fixtures, observation 37/37 and 44 cases, intent 30/30 and 53 cases, scenario 89/89 and 46 cases. Total **215 tests, 151 fixture cases**; shipped fixture validation passed. The handling log's one-error/one-warning line belongs to a deliberately invalid test copy, followed by the clean eight-fixture result.
- The independent GPT-6.2 Sol report `review/implementation/m0-schema-sol-recheck-a7dc804.md` passed its scoped provisional scenario recheck with 89 scenario tests, Ajv 11 schema documents/23 positive fixtures, and a 151-fixture hash sweep. The independent first-party Opus 5.5 report `review/implementation/m0-schema-opus-recheck-5b6475e7-a6bd-4479-926a-0c158deb2880.md` passed statically on the same source, but executed no tests. The fresh four-suite run is additional LongCat evidence, not an Opus/Sol execution claim. M0 milestone review remains due when its other requirements are ready.

## Open decisions assigned forward

- **M1/M4:** specify reference-capture precision and replace the provisional 2.5 ms sector-sum envelope if the actual recorder uses finer timing. No current fixture contains a measured lap or car-handling result.
- **M2.3/M2.7:** define absolute route pose, car footprint, clearance and placement legality; the present scenario lint rejects only exact duplicate poses for the same named `ahead_slot`.
- **M4.2/M4B:** settle the usable-half-width normalization convention, the road width used for intent action 0, the current/delayed split within history, and how a proposed pass commitment refused by safety is recorded and held. Ratify the runtime schema before demonstrations or training.
- **M4.3/M4B:** author and evaluate the five tactical families beyond the single current example and the full matched producer union. An enum reservation is not a scenario run.
- **M2 documentation upkeep:** resolve the handling-versus-scenario README attribution of the mixed-loop and stock-car-spread targets; optionally version the shared `common.schema.json` vocabulary explicitly. These documentation gaps do not invalidate the present versioned slice contracts.

M0.9 marks files and validation rules as present. It makes no claim that an observation builder, Classic planner, Roadstormer model, road, physical fixture or reference-capture implementation exists.
