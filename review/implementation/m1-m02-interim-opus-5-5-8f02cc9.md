# M1 interim follow-up and M0.2 typed resources: Opus 5.5

Review date: 2026-11-27 UTC. Model identity from Claude CLI JSON `modelUsage`: `claude-opus-5-5`, provider `firstParty`, `is_error=false`. Separate reviewer read-only plan-mode run; no source edits.

Candidate source: `8f02cc940cf835b9ce63cdae17cd71d4acf3050a` (tree `1a82a3ceaa5870ae4ba81d8e5191fd9549397f96`), plain immutable archive. Base: `6423a2dffabbceff6e3d5a6fbafb9bc84d993ca4`. Both reviewers received separate archives and did not read each other's current report.

Coordinator follow-up: the exact candidate [hosted CI run](https://github.com/L-K-M/Roadstorm/actions/runs/46076358459) completed successfully at 2026-11-27 22:30 UTC: import/validate/test, export preparation, content inventory, and contract suites. This outcome arrived after the reviewer evidence packets were frozen, so the reviewer text correctly calls it pending. No target-platform launch or milestone acceptance is inferred.

---

# Roadstorm checkpoint review: Opus 5.5 on candidate `8f02cc9`

**Scope:** combined M1 interim follow-up and M0.2 provisional typed-resource checkpoint. This is not milestone acceptance.

## Verdicts

| Slice | Verdict |
|---|---|
| Repaired M1 slices (audio, support probe, DriveLab station and limits, gearbox) | **pass** |
| Provisional M0.2 typed resources (`DefinitionIdentity`, `HandlingDefinition`, `CarDefinition`, data lab) | **changes required** |

- **M1:** all five supported interim findings are closed in code, and each has a regression check that would fail against the old behaviour. No new defect worth a code change turned up in these slices.
- **M0.2:** the overall structure is sound enough to keep building on. Out-of-range enum values pass validation, and identity errors in the referenced handling are reported without saying they come from the handling. Both need small fixes first. One design gap (F3) should be settled before any JSON-to-`.tres` importer is written.

## Reviewer, candidate and scope

- **Model:** Opus 5.5, `claude-opus-5-5`, Anthropic, running in the Claude Code CLI (Claude Agent SDK). This comes from the session's own model metadata; I saw no other CLI routing data. I used no helpers or subagents.
- **Candidate:** `8f02cc940cf835b9ce63cdae17cd71d4acf3050a`, tree `1a82a3ce…`. **Base:** `6423a2d…`.
- **Source:** the `source/` archive. **Context:** `../evidence/{identity.txt, change-list.txt, diff.patch, checks.md, checks/, hosted.md}`.
- **Read:**
  - both prior `6423a2d` interim reports;
  - `PLAN.md` M0.2;
  - `docs/STATUS.md` (latest entries);
  - `schemas/common.schema.json` and `schemas/handling_config.schema.json`;
  - `src/simulation/car_state.gd` and the `ArcadeMotor.MotorTuning` validation.
- **Not read:** the live checkout and the other current reviewer's report.
- **Note:** `diff.patch` leaves out the `docs/` and `review/` entries that `change-list.txt` lists, so I read those files directly from `source/`.

## Prior-finding disposition

| Prior finding | Disposition | Evidence |
|---|---|---|
| Opus F1: tire scrub during straight reverse | **Closed** | See below |
| Opus F2: support identity and normal taken from outside the grounding cluster | **Closed** | See below |
| Opus F3 / Sol 3: rotated-straight station and end/reverse limits | **Closed** | See below |
| Sol 1: audio `apply()` raising on primitive or partially compatible input | **Closed** | See below |
| Sol 2: gearbox checks only some fields for finiteness | **Closed** | See below |
| Opus F4: `CarState.gear_index` vs gearbox initial state and cooldown | **Documented, still open (correctly)** | See below |
| Opus F5 nits: stale voices after halt, corner contacts, unused `is_valid()` | **Not in scope; unchanged** | |

**Opus F1, reverse tire scrub**
- **Fix:** `Synth.direction_relative_slip_deg` (`vehicle_feedback_synth.gd:697`) computes `atan2(|lat|, |fwd|)`, the unsigned angle between the direction of travel and the car's nose axis. The player (`vehicle_feedback_player.gd:235`) and `render_bundle` both use it.
- **Why the tests catch the old code:** the playback and synth cases drive straight reverse at −30 m/s with the latch *clear* and expect silence. The old `abs(slip)` mapping read 180° there, which saturates. A latch-based fold would also fail these cases.
- **What the "broken-behaviour marker" proves:** it only asserts that raw `slip_deg()` is still saturated. It is not a mutant of the old code. The silence assertions are what fail against the old code.

**Opus F2, support identity**
- **Fix:** the selection candidates and the averaged normal are now limited to the witness set: the centre hit, or the unique grounding cluster (`ground_support_probe.gd:443–491`). The cluster indices are always a subset of `valid_indices`, so `candidate_slots[0]` cannot be empty.
- **New case `cluster_closer_outlier`:** three road hits at 0.55 m plus a legal 10°-tilted slab at 0.20 m. The case asserts that the selected identity, point, distance, height and normal all come from the road.
- **Mutant:** `witness_binding` restores the old selection rule. The log shows it detected.
- **Behaviour change, intended and documented:** the `distant_support` control now selects the centre lower floor at 1.55 m.

**Opus F3 / Sol 3, rotated-straight station and limits**
- **Fix:** station and both limits now project onto `_straight_axis_m`, which is derived from the spawn heading (`drive_lab.gd:541, 704, 733`). At zero yaw the axis is exactly `(0, 1)`, so the arithmetic is unchanged.
- **Tests:** stations and limit boundaries at ±1 mm are checked at 30° and 90°. A halt at the limit is confirmed to make no adapter call. The old code reads 12.5·cos 30° = 10.83 m, or 0 at 90°, so it fails these checks.
- **Not covered:** the limit probes place the car at synthetic poses rather than driving there.

**Sol 1, audio input refusal**
- **Fix:** both the player and `render_bundle` use `is CarStateScript` / `is DriverCommandScript` checks.
- **Tests:** the playback atomic-refusal case adds an int state, a float command, a state stand-in without `slip_deg` and a command stand-in without `throttle`. The synth lab adds equivalents. All runners fail on any `SCRIPT ERROR`, so the old raise would fail them.

**Sol 2, gearbox finiteness**
- **Fix:** `propose()` calls `car_state.is_finite()` before anything else (`automatic_gearbox.gd:300`). The documentation is aligned with the code.
- **Old-source control:** the original source is shipped as an inert `.txt` and staged over the gearbox by `--legacy-gearbox`. Its run failed the expected 5 assertions, and the runner requires the `nonfinite position is refused` marker.

**Opus F4, gear index and cooldown**
- Recorded in the gearbox header and the gear-lab README. No `gear_index` write was added. It must be resolved before integration.

## Findings, most severe first

### F1. Medium (M0.2): out-of-range enum values pass validation and bypass the draft-honesty rule
- **Where:** `car_definition.gd:158–181`, `definition_identity.gd:45–65, 82`.
- **What happens:**
  - `_validate_completeness` handles only `DRAFT`, `INCOMPLETE` and `COMPLETE`. Any other integer falls through with no diagnostic.
  - `status` and `contact_proxy_shape` are never range-checked.
  - Godot stores exported enums as plain integers and does not range-check them on `.tres` load.
- **Reproduction (from the code; not run in Godot):** a `.tres` with `completeness = 3`, an empty `completeness_note` and empty `deferred_fields` makes `validate()` return `[]`. The car is `is_valid() == true` with no declared gaps. That defeats the "a draft can never be mistaken for complete data" guarantee, even though `is_complete()` stays false.
- **Also:** `status = 9` validates, and `status_name()` then indexes `Status.keys()[9]` out of bounds, which is a script error.
- **Fix:** range-check all three enums in validation. Add negative `.tres` controls that load hand-written out-of-range integers.

### F2. Low–Medium (M0.2): identity errors in the referenced handling are not attributed to the handling
- **Where:** `car_definition.gd:92`.
- **What happens:**
  - The car appends `handling.validate()` unchanged.
  - Handling's physical diagnostics start with `handling.`, but its identity diagnostics do not. A malformed handling ID is reported as `definition_id: malformed 'Bad Handling'`, the same shape as the car's own identity error.
  - If the car and its handling carry the same bad value, the two diagnostics are identical strings.
- **Contract conflict:** this contradicts the README's "dotted field paths" claim.
- **Test gap:** `malformed_identity_controls` matches substrings, so it cannot tell which record failed.
- **Fix:** prefix nested diagnostics, for example `handling.definition_id: …`, and assert the prefix.

### F3. Low, design (M0.2): `HandlingDefinition` cannot record an undetermined value
- **What happens:**
  - The JSON contract makes braking, drag, yaw gain and lateral damping nullable, backed by an `unknowns` list.
  - `HandlingDefinition` defaults them to `0.0` and accepts 0.0 as valid. A one-point curve plus valid identity and all-default scalars validates as a handling with no steering, braking or drag.
- **Inconsistency:** `CarDefinition` deliberately uses `null` for undetermined values ("rather than a fake zero"), but the handling resource has no such mechanism.
- **Related importer gaps:**
  - The typed handling has its own ID and revision, while in the JSON contract handling is inline inside the car record with no identity of its own. An importer must define how the handling ID and revision are derived.
  - Status names are uppercase in the enum and lowercase in the schema.
- **Before an importer:** decide on nullable fields or an `unknowns` list, and on the handling-ID mapping.

### F4. Low (M0.2): the stable-ID and revision patterns accept a trailing newline
- **Where:** `definition_identity.gd:110–117`.
- **Mechanism:** with PCRE2's default flags, `$` also matches just before a final `\n`. This relies on Godot compiling with `PCRE2_UTF` only and no `DOLLAR_ENDONLY`, which I did not confirm in Godot.
- **Reproduction (Python stand-in, not Godot):** a `python3 -I` check with the same pattern returned true for `'example.car\n'`.
- **Inconsistency:** JSON Schema's ECMA-262 `$` rejects that string, so the two layers disagree on what a valid ID is.
- **Fix:** anchor with `\z`, or reject any string containing a newline.

### F5. Low (M0.2): `deferred_fields` is not checked against `DEFERRED_FIELDS_V1`
- **What happens:** a `DRAFT` with `deferred_fields = ["todo"]` validates, so the list can omit most of the fields that are actually missing. The README says the list keeps completeness claims inspectable, but nothing enforces that it is complete.
- **Fix:** require it to be a superset of `DEFERRED_FIELDS_V1` while that constant exists.

### F6. Low (M1 test oracle): the DriveLab tire oracle uses a different definition from the component
- **Where:** `drive_lab_driver.gd` `feedback_oracle_travel_relative_slip_deg`.
- **What happens:** the oracle folds by 180° only when `reverse_engaged` is set, while the component folds by geometry.
- **When they diverge:** for raw slip above 145° with the latch clear, for example a backward coast after the latch releases. The oracle then predicts saturation while the component is silent. No current DriveLab case reaches that state, so this cannot cause a false pass today. It would cause a false failure later.
- **No coverage loss:** the unit labs independently pin the geometric definition.
- **Fix:** use the geometric oracle the audio and playback labs already have.

### F7. Nits
- **Data-lab round-trip naming:** the handling is saved to its own path first, so the car `.tres` references it as an external resource. The checks labelled "embedded handling" do not exercise an embedded subresource. The reloaded nested handling is checked only for type and validity, not field equality.
- **Round-trip gaps:** a null `wheelbase_m` and the default `max_yaw_rate_rad_s = INF` are never round-tripped. The fixture sets all optional fields and a 2.5 cap.
- **Units:** `documented_units().angle = "deg"`, but `max_yaw_rate_rad_s` is in rad/s. The README names the exception; consider a per-field unit note.
- **Hard-coded length:** the DriveLab limit test uses the literal `500.0` rather than the lab's straight length.
- **Probe naming:** when ungrounded, `has_support` is still true for the diagnostic reading. Consumers must use `support_is_grounding_witness`.

## Answers to the review questions

1. **Do the interim findings close?** Yes; see the disposition table. The negative controls do tell old behaviour apart:
   - **Real mutant or old-source runs:** support `witness_binding` and the gearbox legacy run (5 expected failures).
   - **Assertions that fail by construction against the old code:** the audio silence-at-straight-reverse checks, the primitive and partial-object inputs under the `SCRIPT ERROR` gate, and the rotated-station values.
   - **Not verified:** I saw no old-source run logs for audio or DriveLab, so those two rest on reasoning, not observation.
2. **M0.2 contracts:**
   - **Matches the source contracts:**
     - the stable-ID grammar, apart from F4;
     - semver revisions, which are stricter than the schema's `minLength` and compatible with the fixtures' `1.0.1`;
     - the units and frame constants;
     - the dimension envelopes (3.6–4.8, 1.7–2.2 and 1.0–1.8 m);
     - the nullable optional dimensions;
     - handling validation, which mirrors `MotorTuning.is_valid()` exactly, including the 1 m/s and 0.3 s reverse bounds;
     - full nested handling validation, apart from attribution (F2);
     - a false `COMPLETE` is always refused.
   - **Accessors:** `get_acceleration_points` refuses to truncate mismatched arrays, and `set_acceleration_points` is atomic for null entries. Wrongly typed elements are rejected by GDScript's typed-array boundary, not by the method.
   - **Parallel float arrays:** a reasonable, documented workaround for the inner-class `.tres` reload limitation.
   - **Suitability:** fine to keep building on after F1 and F2. F3 must be settled before an importer.
3. **New defects:**
   - **M1:** none material. The changes are atomic, and the witness binding cannot index an empty array.
   - **M0.2:** F1 through F5.
   - **Integration:** the gear index and cooldown mismatch is documented and still open.
   - **Scope honesty:** no false-success harness found. Every runner requires the deliberate-failure marker and scans logs for engine errors. `STATUS.md` claims no M0.2, M0 or M1 closure.
4. **Frozen tests:** see "Checks run" and "Evidence limits" below.

## Checks run

- `shasum -a 256` on all 7 supplied logs: every hash matches `checks.md`.
- Summary lines from the logs:

  | Suite | Cases | Checks | Other |
  |---|---|---|---|
  | Support | 17 | 885 | 9 mutants detected, including `witness_binding` |
  | Data | 8 | 165 | intentional failure exits nonzero |
  | Audio (synth) | 10 | 227 | |
  | Playback | 9 | 1,542 | |
  | DriveLab | 14 | 1,430 | bad-config 99; deliberate failure 2 checks, 1 failed |
  | Gear | 8 | 3,061 | |
  | Gear, legacy source | 1 | 65 | 5 failed, as expected |

- Source inspection with `cat`, `sed`, `grep` and `awk` on the diff and the changed and dependent files.
- One `python3 -I -B` regex check (F4).
- **Godot not run.** This session was in read-only plan mode, and the runners write staged copies and caches. Every pass/fail count above is coordinator evidence.

## Evidence limits

- **Headless only:** numeric, structural and Jolt checks on the coordinator's macOS machine. No listening tests, no rendered 30/60/120 FPS traces, no physical controllers, no four-player mix and no target-OS launch.
- **Synthetic poses:** the DriveLab rotated-limit checks place the car directly instead of driving it there.
- **Data lab scope:** one engine version, synthetic `EXAMPLE` fixtures, and no hand-edited, malformed `.tres` inputs, which is why F1 was not caught.
- **Hosted CI:** run `46076358459` was still in progress at package freeze, so it is not a pass. An export would not be a platform launch in any case.

## Remaining milestone gaps (not defects of this checkpoint)

- **M1 behaviour:**
  - support eligibility, adhesion and landing;
  - floor- and ramp-aware orientation;
  - multi-wall corner response;
  - scrape-then-steer-away feel;
  - full reset placement.
- **Tuning and integration:**
  - calibration of drift, surge, drafting and gear thresholds;
  - wiring the gearbox into `CarState`, the HUD and audio (needs the F4 decision first);
  - stale voices after a halt (prior F5).
- **Verification:** real controllers, rendered traces, listening tests and target-platform launches.
- **M0.2 remainder:**
  - project, scene and directory deliverables;
  - track, event, upgrade, AI, ghost and scenario resources;
  - the importer;
  - content hashes and provenance;
  - every field in `DEFERRED_FIELDS_V1`.
- **M0.3:** output-rights items OI-02 and OI-03 remain release blockers.
- **Whole milestones:** M0 and M1 acceptance are both still open.
