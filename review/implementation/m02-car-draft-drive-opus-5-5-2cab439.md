# Independent exact-source review: provisional M0.2 car draft mapper and one-car M1.8 DriveLab wall publication

**Verdict: changes required for the bounded scope.** Both seams mostly do what their contracts say, and the frozen evidence matches what I reproduced. I confirmed two defects by execution. First, `CarRecipeMapper.map_draft` accepts a valid `HandlingDefinition` whose physical values differ from the source recipe and returns `ok=true` (F1). Second, `DriveLab.publish_wall_event` publishes a second, fabricated committed `ImpactEvent` for the same tick when a caller mutates the accepted adapter result and calls it again (F2).

## Identity, candidate and scope

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, through Claude Code (Claude Agent SDK). Date: 2026-11-28.
- Candidate: `2cab43957c0b0b930a16a092a6f077208c076283`, taken from the brief. The source is a plain archive with no Git metadata, so I could not verify the SHA independently. `diff -rq ../source build -x work` reported no differences before testing.
- Scope (a): `src/data/car_recipe_mapper.gd` and `tools/car_draft_lab/**` at 2cab439.
- Scope (b): the wall-event publication in `src/laboratory/drive_lab.gd` and `tools/drive_lab/**`, introduced at 07b2858.
- `../../scope.patch` was read in full for those paths.
- Excluded, as instructed: the known M0.2 baker numeric defect, the wall-corner region defect, and their uncommitted live-checkout repairs.
- No helpers or subagents were used. I did not consult the other reviewer.

## Files inspected

- `src/data/car_recipe_mapper.gd` (all), `src/data/car_definition.gd` (all).
- `src/data/handling_definition.gd` (fields and doc), `src/data/handling_recipe_mapper.gd` (identity derivation, unknown-path canonicalization), `src/data/definition_identity.gd` (constants).
- `schemas/handling_config_v1_1.schema.json` (property tree).
- `tools/car_recipe_schema/validate_car_recipe.py` (unknowns policy, by search).
- `tools/car_draft_lab/README.md`, plus the validator's case list and the handling-agreement case.
- `src/laboratory/drive_lab.gd`: `step_once`, the whole M1.8 publication surface, `_reset_run_state`, `_reject_gearbox_step`.
- `src/simulation/motor_body_adapter.gd` (`Result` fields), `src/simulation/wall_impact_producer.gd` (`produce` inputs), `src/simulation/impact_event.gd` (ledger bounds).
- `tools/drive_lab/README.md` M1.8 section. The `drive_lab_driver.gd` wall case and fault injector, in full from the patch.
- `.github/workflows/ci.yml` lab steps.
- `PLAN.md` M0.2/M1.8 lines and `docs/STATUS.md`, by search.
- Prior reports `review/implementation/m02-bake-recheck-{opus-5-5,gpt-6-2-sol}-c4b99fd.md` and `m1-wall-producer-{opus-5-5,gpt-6-2-sol}-5620581.md`.
- Coordinator evidence `../../evidence/{car-draft-run.log,drive-wall-run.log}`, for summary lines only.

## Commands I ran and outcomes

All engine runs used the shared pinned editor (`--version` gave `4.7.2.stable.official.ed1daf0bf`). Every run went through `lockf -k -t 900` on `build/work/agents/coordinator/godot-test.lock`, bounded by `timeout`. `HOME`, `TMPDIR` and the XDG directories were private, under `build/work/opus-probe/`. The project was a private rsync copy at `build/work/opus-probe/proj` (`work/` and `.godot` excluded). I added three probe scripts under `tools/opus_probe/`, in that copy only.

1. `Godot --headless --path proj --import`: exit 0, no `ERROR` lines (`../logs/probe-import.log`).
2. `Godot --headless --path proj --script res://tools/opus_probe/probe_car.gd`: exit 0 (`../logs/probe-car.log`).
   - The committed `example_rookie_finite.json` maps through `HandlingRecipeMapper`.
   - **B1:** a deep duplicate of that handling with halved braking (9.0 → 5.5), aerodynamic drag +0.25 and display name `"Unrelated handling"` validates. `map_draft(recipe, it)` returned `ok=true` with no diagnostics. `car.handling.braking_acceleration_m_s2` is 5.5, while the recipe's source value is 9.0.
   - **B2:** removing `handling`, `engine` and `upgrades` from the recipe still gives `ok=true`.
   - **B3:** `result.car.handling` is the very object that was passed in.
3. `Godot --headless --fixed-fps 60 --path proj --script res://tools/opus_probe/probe_drive.gd`: exit 0 (`../logs/probe-drive.log`). The probe driver subclasses the committed `drive_lab_driver.gd` and reuses its real wall fixture.
   - The real Jolt head-on hit produced the witness on committed tick 171, severity 17.8935 m/s, event `drive_lab.wall.1.171.0`. This matches the coordinator evidence.
   - **A:** I moved `wall_contact_point` on the returned accepted result by 0.05 m and called `publish_wall_event(result)`. It returned `true`, with `published` 2 and `retained` 2. `get_wall_events_for_tick(171)` returned two events, `.171.0` and `.171.1`, at different contact points.
   - **A2:** a fresh `MotorBodyAdapter.Result.new()` was refused (`false`), so the identity gate works for foreign objects.
   - **A3:** I kept throttle on against the wall for 10 more ticks. All 10 committed ticks carried a witness, and 10 more events were published. The ledger then retained 8 of the 12 (its default 8-tick window), so the original hit event had already been evicted.

I did not rerun the coordinator's full suites: car draft 8 cases/354 checks, DriveLab 16/5,160, bad config 99/99, the deliberate failures and the publication mutant. Those remain coordinator evidence. I also did not run GitHub Actions. Reading `ci.yml` shows the hosted workflow runs `tools/data_lab` but neither `tools/car_draft_lab` nor `tools/drive_lab`.

## Ranked actionable findings

### F1 (medium, confirmed): a valid but mismatched handling is silently paired with the source recipe

- **Where:** `src/data/car_recipe_mapper.gd:279-311` (`_check_handling_agreement`), `:169`, `:182`, `:672`. Doc claims at `:46-51`.
- **Condition:** `_check_handling_agreement` compares only four fields:
  - the derived ID `<car_id>.handling`
  - `revision`
  - `status`
  - typed `schema_version`

  The constructed car's `validate()` then checks that the handling is *valid*, not that it *agrees* with the source. The mapper never reads `recipe["handling"]`. Any `HandlingDefinition` carrying the right four identity tags is attached as the car's motor tuning, whatever its curve, braking, drag, yaw, damping or reverse values and its display name. Probe B1 reproduces this with halved braking. Probe B2 shows the source handling block need not even exist.
- **Who else could catch it:** the external checker never sees the typed handling, so it cannot catch this either. No component in the chain enforces the doc's "must agree with the source recipe" for content. "Changing a car's inline handling therefore requires a car revision change" (`:50-51`) is an authoring convention the code does not enforce. Two recipe edits with the same revision produce interchangeable handlings.
- **Classification:** this is a defect in this seam's own contract, not a missing-integration gap. The typed handling reference is the only motor-relevant member of the draft, and the mapper already holds the recipe, so enforcing agreement costs little.
- **Fix, either:**
  - (a) derive the handling inside `map_draft` with `HandlingRecipeMapper.map_handling(recipe)` and compare all 18 exported fields with the passed one, including display name and the sign of infinite yaw. Refuse on mismatch with `handling.<field>: handling-content-mismatch`. Or drop the parameter and use the derived handling.
  - (b) if pairing by identity tags alone is intended, state plainly that only identity tags are checked and that the caller must pass the handling mapped from this exact recipe object, and record the risk.

  Either way, add a lab case with a valid, same-identity, different-physics handling. The current `handling_agreement_refusals` case (`validate_car_draft_lab.gd:556-620`) covers only the four tags plus a physically invalid handling.

### F2 (medium, confirmed): the same committed tick can publish a second, fabricated wall event

- **Where:** `src/laboratory/drive_lab.gd:864-924` (`publish_wall_event`), especially `:867`, `:886-897`. Doc claims at `:226-227` and `:856-860`.
- **Condition:**
  - The acceptance gate is object identity (`result != _wall_event_accepted_result`) plus the tick. `step_once` returns that same mutable `MotorBodyAdapter.Result` to its caller (`:1049-1054`), and all witness fields are plain `var`s.
  - The ID is chosen per fingerprint and per-tick sequence. A caller that edits any witness field on the returned result and calls `publish_wall_event(result)` therefore passes the gate, gets a new ID (`.<tick>.1`), and the real producer and ledger publish a second committed event built from the edited values. Probe A reproduces this on the real Jolt hit.
  - A committed adapter tick carries exactly one wall witness. "A different witness in the same tick gets a new ID" (`:860`) can therefore only ever be triggered by a mutated result. The sequence machinery has no legitimate use and opens this hole.
- **Effect:** one-event-per-commit publication and committed-only provenance depend on callers not mutating results. No in-tree caller mutates results, so the effect is limited to this public retry API.
- **Fix:** at acceptance in `step_once`, store the fingerprint, or the produced event. On a later call for that tick, coalesce only when the fingerprint is identical and refuse anything else with a diagnostic. Drop the per-tick sequence or pin it to 0. Add a negative check that mutates the returned witness and expects refusal with `published == 1`.
- **Test gap:** the existing negative checks would not catch removing the identity gate itself, because the `failed`/`halted`/tick conditions already refuse every result they try. No check passes a foreign or edited `Result` at the current tick.

### F3 (low, carried plan gap, now live in the lab): sustained wall contact publishes one event per tick

- **Where:** `src/laboratory/drive_lab.gd:1049`, with the producer policy left open by the 5620581 reports (Opus F2).
- **Condition:** probe A3 held throttle against the wall for 10 ticks and published 10 more events. With `Ledger.DEFAULT_MAX_RETAINED_TICKS == 8` (`impact_event.gd:592`), the original 17.9 m/s hit event was evicted about 8 ticks (0.13 s) after it happened.
- **Status:** not a regression in this SHA. It is the open sustained-contact/continuity policy, and the lab README states that repeated contacts are not covered. Any consumer of `get_last_wall_event()` or the retained window sees scrape events rather than the impact.

### F4 (low, inventory truth): unmapped source members not named by `DEFERRED_FIELDS_V1`

- **Where:** `src/data/car_definition.gd:39-53`, as used by `car_recipe_mapper.gd:24-26,675-678`.
- **Condition:** the 1.1.0 source carries members the draft drops without listing them:
  - `engine.acceleration_curve`
  - `handling.yaw_gain.drift` and `handling.lateral_damping.drift_per_s`. These are not under `handling.drift`.
  - `upgrades.engine.*`, `upgrades.tires.*`, `upgrades.chassis.*`, `upgrades.max_increase_percent.*`. Only `upgrades.levels` is listed.
  - `content_hash` and `provenance`, which would also make F1 detectable later.

  INCOMPLETE remains true and COMPLETE is refused, so nothing claims completeness falsely. But the comment "every deferred handling field stay absent exactly as `DEFERRED_FIELDS_V1` declares them" overstates how exact the inventory is.
- **Fix:** extend the list, or document that these entries are section-level placeholders.

### F5 (low, evidence gap, not a code defect): hosted CI runs neither new behavior suite

- **Where:** `.github/workflows/ci.yml` runs `tools/data_lab/run_validation.sh` (around `:135`) and `ci.sh` stages, but neither `tools/car_draft_lab/run_validation.sh` nor `tools/drive_lab/run_validation.sh`.
- **Effect:** hosted run 46097242620 is build and import evidence only for these seams. The car-draft and DriveLab results are local coordinator evidence plus my probes.

### Minor notes

- `_reject_gearbox_step` (`drive_lab.gd:1532-1541`) sets only a "withheld" diagnostic. The `refused` and `missed_witnesses` counters stay 0, so the telemetry counters alone cannot show that a witness was withheld.
- `_wall_refusal_paths_emit_no_event_checks` runs its gearbox-failure leg on the plain straight, where there is no wall witness, so its "no event" assertion is vacuous. The real-wall withheld case (`_wall_postcommit_gearbox_failure_withholds_witness_checks`) does cover it.
- The stale-later-tick refusal is correct by construction: each tick has a new result object, and `:867` checks the tick. But no check republishes the tick-N witness after tick N+1.
- `CarDefinition.handling` aliases the caller's handling (probe B3). The mapper does not mutate it, but later caller edits change an already validated draft.
- The `typeof(recipe) != TYPE_DICTIONARY` check (`car_recipe_mapper.gd:139`) is unreachable because the parameter is typed.
- The status-mismatch diagnostic prints integers rather than lifecycle names (`:302-306`).

## Verified as working in the bounded seams

Mapper:

- Exact version dispatch: only 1.1.0 maps, and 1.0.0 is refused naming its five paths.
- Units and frame checks.
- Required dimensions, mass and contact shape: missing, null and unknown are each refused, including ancestor unknowns.
- Optional nulls are preserved, and a resolved optional listed in `unknowns` is refused.
- Finite-number checks.
- Refusal is atomic: `ok=false`, `car=null`, path diagnostics.
- The fixed INCOMPLETE note plus the exact `DEFERRED_FIELDS_V1` copy, with full car and handling validation.
- No input mutation, by code reading. The lab's snapshot checks are coordinator evidence.

DriveLab:

- Publication happens only after the canonical gearbox/CarState pair is published (`:1036-1049`).
- Adapter refusal, nonfinite commit, gearbox failure and the stale-pose block all return before publication.
- An identical retry reuses its ID and coalesces.
- Retiring a scope advances the generation and clears the maps without touching the car state or body.
- Nothing in presentation, audio or the motor reads `last_wall_event` or the ledger. `grep` found no reference outside the publication surface, so cosmetic feedback cannot reach the motor.
- My real Jolt probe reproduced the coordinator's tick-171 head-on FRONT event at 17.8935 m/s.

The real Jolt case covers one head-on hit on one bay. The coordinator's publication mutant only proves the `step_once` call matters; it does not exercise the gate (see F2).

## Capability limits

- The checks were static reading plus three targeted probes on a private copy.
- No full-suite rerun, no hosted CI run, and no Git ancestry verification.
- No cross-platform, oblique or multi-contact physics.
- No assessment of the excluded baker or corner repairs.

No full M0.2, M0, M1 or M1.8 acceptance, and no rights clearance, is claimed.

Report path: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator/m02-drive-review-2cab439/opus/report.md`
