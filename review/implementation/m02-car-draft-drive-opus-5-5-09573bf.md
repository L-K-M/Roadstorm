# Independent scoped recheck: M0.2 car-draft content agreement and M1.8 DriveLab accepted-witness gate

**Verdict: pass** for this bounded candidate. Both prior medium defects (Opus F1/Sol 2 on mismatched handling; Opus F2/Sol 1 on a forged second same-tick wall event) are fixed in the scoped code, and I confirmed the fixes by execution. Old-source controls fail the new assertions. My findings below are test-coverage gaps, optional hardening and documentation nits. None is an implementation defect in the corrected seams.

## Identity, candidate and scope

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, run through Claude Code. Date 2026-11-28.
- Candidate `09573bf159e9cba7e98d3778b36b54e8b7afaba6`; scoped base `2cab43957c0b0b930a16a092a6f077208c076283`.
- Scope (`../../scope.patch`, `../../scope-stat.txt`): `src/data/car_recipe_mapper.gd`, `tools/car_draft_lab/{README.md,validate_car_draft_lab.gd}`, `src/laboratory/drive_lab.gd`, `tools/drive_lab/drive_lab_driver.gd` (5 files, +952/-57).
- Source: `../source/` (read-only plain archive) and `./` (writable copy). Neither has Git metadata, so I did not verify the commit identity. I rely on the coordinator for the SHA. I did not open the other reviewer's current report. I made no Git, source or asset edits. Every probe ran in a private staged copy under `../logs/own/`.

## Files inspected

- `../../scope.patch` (all 1,243 lines), `../../scope-stat.txt`, `../../task.md`.
- `src/data/car_recipe_mapper.gd` (`map_draft` :156-218, `_check_handling_agreement` :307-339, `_check_handling_content` :348-438, `_same_float` :442, `_copy_verified_handling` :868-874).
- `src/data/handling_definition.gd` (exported fields :56-69), `src/data/definition_identity.gd` (exported identity fields :43-50), `src/data/handling_recipe_mapper.gd` (identity derivation :179-183).
- `src/laboratory/drive_lab.gd` (`publish_wall_event` :873-943, `_wall_witness_snapshot` :950, fingerprint, `_wall_witness_mismatch_field` :1000-1022, `step_once` :1044-1135, `retire_wall_event_scope`).
- `src/simulation/wall_impact_producer.gd` (`produce` :103-213), `src/simulation/impact_event.gd` (`encode_for_digest` :363 uses `var_to_bytes`, `Ledger.publish` duplicate/conflict path around :668-685), the gearbox `mirror_gear` (returns `car_state.copy()`).
- `tools/car_draft_lab/validate_car_draft_lab.gd` (new case and helpers), `tools/drive_lab/drive_lab_driver.gd` :3844-4055, both READMEs/runners.
- Prior reports: `review/implementation/m02-car-draft-drive-opus-5-5-2cab439.md`, `review/implementation/m02-car-draft-drive-gpt-6-2-sol-2cab439.md`.

## Commands actually run and results

All runs used the pinned editor `.../toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot` (reports `4.7.2.stable.official.ed1daf0bf`). Each ran under `timeout` plus `lockf -k -w -t 600|900 work/agents/coordinator/godot-test.lock`, with `TMPDIR`/XDG pointed at `../logs/own/`.

1. `sh tools/car_draft_lab/run_validation.sh --godot $G --case all --private-dir ../logs/own/car-priv --log ../logs/own/car_all.log`: exit 0. 9 cases, 561 checks, 0 failed. `handling_content_agreement` ran 165 checks, 0 failed. The deliberate-failure proof exited nonzero with its marker. This matches `../../car-new-run.log`.
2. `sh tools/drive_lab/run_validation.sh --project $PWD --godot $G --timeout 180 --log ../logs/own/drive_all.log`: exit 0. 16 cases, 5,255 checks, 0 failed. Bad config 99/99. Failure probe rc=3 with its marker. This matches `../../drive-new-run.log`.
3. **Old-mapper control.** In a private copy (`../logs/own/car-old`), I reverse-applied only the `car_recipe_mapper.gd` hunk of `scope.patch`, then ran the car lab: exit 1, 95/561 failed, of which 92/165 were in `handling_content_agreement`. Positive finite/unlimited and `handling_agreement_refusals` each lost one check (aliasing / old diagnostic). This reproduces `../../car-old-control.log`.
4. **Old-DriveLab control.** In a private copy (`../logs/own/drive-old`), I reverse-applied only the `drive_lab.gd` hunk and ran the DriveLab suite with the candidate driver: exit 1, 57/5,255 failed, all `wall.mutant.*`. Among them were `contact_point_retains_one_event`, `..._no_new_publication` and `..._digest_unchanged`, so the old forgery reproduces and the new driver discriminates it.
5. **Mapper probe** (`../logs/own/probes/mapper_probe.gd`, staged copy `../logs/own/probe-proj`, after `--import`): 17 of 18 checks passed. All of these passed:
   - the positive path, with no alias;
   - `duplicate(true)` keeps the `HandlingDefinition` script, the typed `Array[float]` element type and the identity tags;
   - an append to the caller's array does not reach the draft;
   - halved braking: the handling validates on its own, yet the draft is refused with `handling.braking_acceleration_m_s2: handling-content-mismatch` and `car == null`;
   - a one-bit flip of `yaw_gain_grip` and of the finite `max_yaw_rate_rad_s` is refused with path diagnostics;
   - NaN yaw against an INF source is refused;
   - an identity and content mismatch together is diagnosed on both paths;
   - a null handling is refused.

   The one "failure" was the signed-zero probe. I traced it to a GDScript compiler behavior, not to the mapper; see N1. A follow-up probe (`sz2_probe.gd`) with a genuine stored `-0.0` (bytes `...80`) was refused: `handling.acceleration_curve_speeds_m_s[0]: handling-content-mismatch: expected 0.0, got 0.0`. `sz3_probe.gd` showed that `var y := -0.0` yields `1/y = +inf` when a `0.0` literal appears earlier in the same function, and `-inf` otherwise. Logs are `../logs/own/mapper_probe.log`, `sz_probe.log`, `sz2_probe.log`, `sz3_probe.log`.
6. **DriveLab probe.** In a private copy (`../logs/own/drive-proj`), I inserted 8 checks after the driver's restore/coalesce step at the real pinned-Jolt tick-171 wall witness. The full suite exited 0 with 5,263 checks and 0 failed. What the probe showed:
   - **Committed velocity.** Mutating `witness.committed_state.velocity_m_s.x += 0.1` was refused with `accepted witness fingerprint mismatch (committed planar velocity)`. The refusal counter rose by one, the event count stayed 1, the digest did not change, and `lab.state.velocity_m_s` was unaffected, because the published state is a gearbox copy. After restoring the value, the retry coalesced.
   - **Committed position.** Mutating `committed_state.position_m` (a field the producer does not consume) coalesced to the same single event and digest. This is correct, because the event payload does not depend on it.
   - **Adapter config.** Mutating `lab.adapter_config.hull_size_m` passed the fingerprint and reached the producer and ledger, which refused it: `conflicting payload for event id drive_lab.wall.1.171.0`. The event count stayed 1. See H1.

## Assessment against the brief

**Car mapper.**
- **Independent derivation.** The mapper derives the expected handling with `HandlingRecipeMapper.map_handling(recipe)` from the same recipe (`car_recipe_mapper.gd:189`). It requires that derivation to succeed, so a missing, non-object, mistyped or unknown source handling is refused with path diagnostics and a `handling: handling-content-mismatch` header (:190-195).
- **Fields compared.** It compares exactly every physical exported field of `HandlingDefinition`: both curve arrays element-wise including length, braking, both drags, grip yaw, max yaw (finite or INF), lateral damping and the four reverse values. It also compares `display_name`. The identity tags (`definition_id`, `revision`, `status`, `schema_version`) are checked at :307-339.
- **No partial car.** Any diagnostic returns before `_build_car` (:206-208).
- **Float comparison.** `_same_float` (:442) is truthful. Equality plus a reciprocal check distinguishes the signed zeros, NaN never matches, and INF matches INF. Because all compared fields are binary64 script floats, this amounts to bit-exact comparison except for NaN payloads, which are always refused.
- **Deep copy.** The draft holds a deep copy (:868-874). No nested object of the returned draft stays aliased to the caller's handling. I verified the scalars, the typed arrays and the script.
- **Null/unknown honesty.** This stays with the external checker, as the docs say. The derivation additionally refuses unknown required handling inputs.

**DriveLab gate.**
- **Snapshot timing.** The snapshot and fingerprint are taken in `step_once` only after the physical commit, a successful proposal, a mirrored, finite and gear-agreeing pair, `state = published` and `ticks_committed += 1` (`drive_lab.gd:1107-1120`).
- **Order of checks in `publish_wall_event`** (:873-943):
  1. Object identity, current tick and `failed`/`halted`/stale pose (:876-884).
  2. Then the full-snapshot fingerprint (:885-896).
  3. Only after both pass is an ID assigned. That ID is pinned to `.<tick>.0`, so no per-tick sequence can mint a second ID.
- **Fingerprint coverage.** The fingerprint covers every Result field the producer consumes: status, both witness flags, point, normal, pre and post velocity, transform origin and basis, and committed planar velocity. It is encoded through `var_to_bytes`, so it is bit-exact and keeps signed zero.
- **Mutation bypass.** The snapshot is stored by value: Vector3, Basis and the computed committed-world Vector3. So neither mutating the same object nor mutating its nested `committed_state` can alter the accepted reference.
- **Behavior on each refusal.**
  - Foreign identical Result, stale tick and retired scope: refused, as the driver checks.
  - Blocked physical/gearbox pair: never reaches the acceptance assignment, so the previous tick's Result is refused by the tick check.
  - Diagnostics and `wall_events_refused`: reflect each refusal, as asserted per mutant.
  - Identical retry: coalesces.

## Ranked actionable findings

No implementation defects found in the scoped seams.

### T1 (low, test coverage): the committed-velocity mutant is defined but never exercised

`tools/drive_lab/drive_lab_driver.gd:3855-3865` lists nine mutants and leaves out `committed_velocity`. Yet `_apply_wall_witness_mutation` supports it (:4052-4053), and the brief names committed velocity explicitly. `_saved_wall_witness_state`/`_restore_wall_witness_state` (:4000, :4015) also do not save or restore `committed_state.velocity_m_s`, which is probably why it was left out.

My probe (command 6) shows the implementation refuses it correctly, with a specific diagnostic and no state change. Without this check, though, the supplied suite would not detect the field being dropped from `_wall_witness_snapshot`. The producer's `post_velocity != committed_world` check would still refuse, but only after an ID was mapped, and with a producer diagnostic rather than a fingerprint diagnostic.

Fix: save and restore the committed velocity and add the entry to the loop.

### H1 (low, optional hardening): `adapter_config` is not part of the accepted snapshot

The producer also consumes `adapter_config` (`drive_lab.gd:917`; `hull_size_m` drives region classification). The config is a public lab member and is not fingerprinted. If a caller mutates it between the first publication and a retry, the fingerprint passes, the same ID is reused, and the real ledger refuses with `conflicting payload` (probe 6). That increments the ledger's `conflict_count` and `wall_events_refused`.

No second event is forged, so the one-event invariant holds. The brief's "refused before … ledger state changes" is still met for Result fields, but not for this lab-owned input. Optional fix: snapshot `adapter_config.hull_size_m` (or the built event) at acceptance.

### N1 (nit, test robustness): the signed-zero fixture depends on GDScript constant folding

`tools/car_draft_lab/validate_car_draft_lab.gd:819` writes `-0.0` as a literal. On pinned 4.7.2, a `-0.0` literal folds to `+0.0` if a `0.0` literal appears earlier in the same function (probe `sz3`). Separately, runtime `-z` for `z = 0.0` produced `+0.0` (probe `sz`).

The current case does store a real `-0.0`; I confirmed the observed refusal on the exact path. If someone edits that function to add a `0.0` literal before line 819, this check would fail loudly rather than pass vacuously. Building the value from bytes (`PackedFloat64Array`/`to_byte_array` with the sign bit set) would make it robust.

### N2 (nit, completeness of the "every core exported field" claim): `notes` is not compared

`DefinitionIdentity.notes` (`definition_identity.gd:50`) is exported, never set by `HandlingRecipeMapper`, and not compared by `_check_handling_content` (`car_recipe_mapper.gd:348`). A supplied handling with `notes = "measured on track, production ready"` maps `ok=true`, and the copied draft carries that text (probe 5).

It has no effect on physics or identity, and the docs say "core", but it is a free-text claim channel on an INCOMPLETE draft. Either require it to equal the derived value (empty) or document it as not compared.

### N3 (nit, hardening): a `HandlingDefinition` subclass script is accepted and preserved

A caller-provided subclass that overrides `validate()` passes content agreement, and `duplicate(true)` keeps that subclass script on the draft (probe 5). This is an in-process trust boundary and is not reachable from data. Optionally require `handling.get_script() == HandlingDefinition` or construct the copy from the expected handling's script.

### N4 (nit, docs): one limitation string is stale

`validate_car_draft_lab.gd:1416` still says "the typed handling reference are mapped". The README and mapper docs now say "deep copy of the verified typed handling".

### N5 (nit, diagnostics): signed-zero-only witness differences get a generic label

`_wall_witness_mismatch_field` (`drive_lab.gd:1000-1022`) compares with `!=`. A witness that differs only in a signed zero is refused correctly by the byte fingerprint, but the diagnostic falls back to "witness state" (:1022). This is cosmetic.

## Out of scope and still open (not findings against this candidate)

- Sustained-contact and zero-delta publication policy, car-car events and cosmetics (prior Opus F3).
- `DEFERRED_FIELDS_V1` inventory (prior Opus F4).
- Hosted CI runs neither suite (prior Opus F5). The coordinator notes hosted CI on 09573bf was queued; I did not inspect it.
- The baker, wall-producer and status commits between base and candidate were treated as context only.
- No file bake, measured car, general importer, full M0.2/M1.8, platform or release claim is made or supported.

## Capability limits

- No Git metadata, so I did not verify commit identity or ancestry myself.
- Headless pinned macOS engine only. No cross-version, export-template or platform runs.
- My DriveLab probes cover the single head-on wall fixture at tick 171 that the driver uses. I did not construct other wall geometries.
- I relied on the supplied coordinator logs only for comparison. Every number reported as "matches" was reproduced in my own runs above.

Report path: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator/m02-drive-recheck-09573bf159e9cba7e98d3778b36b54e8b7afaba6/opus/report.md`
