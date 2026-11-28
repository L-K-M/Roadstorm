<!-- Coordinator attestation: Claude CLI JSON modelUsage records claude-opus-5-5, provider firstParty, is_error=false and no subagents; reviewer used a separate read-only plain archive of candidate 316705ddf3063e272da54c704612b11a6a25fdca. -->

# Roadstorm checkpoint review: Opus 5.5 on candidate `316705d` (combined interim M1 component and provisional M0.2 recheck)

This is **not** M0 or M1 milestone acceptance.

## Verdicts

| Slice | Verdict |
|---|---|
| (a) Provisional M0.2 typed-resource slice | **Pass (provisional).** No implementation defects found. The importer/baker and the source-schema revision remain open work. |
| (b) M1 component slice: impact contract and ledger, gearbox domain and atomicity, wall-point witness, one-car gearbox DriveLab | **Pass at component scope.** Only low findings (N1–N4) and nits. None blocks this interim checkpoint. The M1.8 impact producer and the physical integration are absent and not claimed. |

All material prior d910c72 findings from both reviewers are closed in code and have their own checks.

## Identity

- **Candidate:** `316705ddf3063e272da54c704612b11a6a25fdca`
- **Tree:** `eca7404151317787b3ede0f5a0deafc3acb737fd`
- **Base:** `d910c725f12e4762fa5480aca6f8a00a2ceb6200`
- All three come from `evidence/identity.txt`. I did not recompute them with Git.
- **Reviewer:** Claude Opus 5.5, model ID `claude-opus-5-5`, Anthropic first party, in the Claude Code CLI (Claude Agent SDK). This comes from the session's own model metadata.
- **Date:** 2026-11-28, from `date`: Sat Nov 28 00:57 CET 2026.
- **How I worked:**
  - Read-only plan-mode session. No helpers or subagents.
  - Nothing written to `./source` and no Git state changed.
  - I did not read the live checkout or the other current reviewer's report.

## Files inspected

**Evidence packet:**
- `identity.txt`, `change-list.txt` (24 paths), `checks.md`, `checks.sha256`, `hosted.md`
- all seven `checks/*.log`
- `diff.patch` (5,197 lines): read in full for the adapter, `drive_lab.gd`, gearbox, `car_state`, mapping doc, the two READMEs, `car_definition`, `data_lab_checks` and the body-lab witness cases

**Source:**
- `review/implementation/m1-m02-interim-opus-5-5-d910c72.md` and `m1-m02-interim-gpt-6-2-sol-d910c72.md`
- `src/simulation/impact_event.gd`: read in full
- `src/simulation/motor_body_adapter.gd`: step flow, collection, selection and `_reject`
- `src/simulation/automatic_gearbox.gd`: `propose`, restore, `restore_and_mirror`, `_is_restorable_state`
- `src/laboratory/drive_lab.gd`: the changed regions
- `tools/data_lab/validate_data_lab.gd`: scratch constants, cleanup and teardown, and the schema-version comparisons at `:408` and `:490`
- `tools/impact_lab/impact_lab_driver.gd`: case list and the two-perspective case
- `tools/body_lab/body_lab_driver.gd`: the witness cases
- `docs/evidence/m02-typed-runtime-mapping-20261127.md`, `src/data/README.md`, `tools/data_lab/README.md`, `project.godot`, `tools/ci/ci.sh` (warning gate)

I relied on the prior reports for the PLAN.md M0.2/M1 and `plan/IMPLEMENTATION.md` scope. I did not re-read those files in full.

## Commands actually run (mine, not the coordinator's)

- `cat`, `sed`, `grep`, `ls`, `wc`, `date` on the packet and the archive.
- `shasum -a 256 evidence/checks/*`: all seven hashes match `checks.sha256`.
- `grep` of the logs for summary, intentional-failure and WARNING lines:
  - The only WARNINGs are:
    - "4 ObjectDB instances were leaked at exit": DriveLab and its probe.
    - "Detected another project.godot at res://tools/tick_probe": one each in the data and gear runner logs.
  - None comes from the new impact enum sentinel.

I ran no Godot, Python, lab runner or CI. The session was read-only and the runners write staged copies. Every pass/fail count below is coordinator evidence.

## Supplied evidence assessed (coordinator logs, not my execution)

| Log | Content | Gaps |
|---|---|---|
| `body-runner.log` | 18 cases / 2,654 checks, 0 failed. Includes `wall_contact_point_selection` and `wall_contact_point_telemetry`. | Source batch was `eddef9a` plus 14 paths. The coordinator attests it is byte-equal to the candidate. I checked hashes of logs, not of the sources. |
| `impact-runner.log`, `impact-validator.log` | 18 / 459, 0 failed. Deliberate probe pass=false, rc 3. | |
| `data-runner.log`, `data-validator.log` | 13 / 289, 0 failed. `scratch_cleanup_reports` lists unexpected, subdir and hidden entries as retained. Intentional failure proof present. | |
| `gear-runner.log` | 11 / 3,159, 0 failed, including `dwell_domain` and `restore_and_mirror`. Three-probe intentional failure. | |
| `drive-runner.log` | 15 / 4,975, 0 failed. Bad config 99/99. Deliberate probe present. ObjectDB leak warning. | |
| Worker mutation controls | | Not in the packet. They rest on attestation only. |
| `hosted.md` | Run 46084852580 was pending at freeze. | **Not** a CI pass. |

**Capability limits:** I performed no rendered-frame, motion-feel, listening, controller, multi-player, Linux or Windows launch, export or release check, and the packet contains none.

## Disposition of prior d910c72 findings

| Prior finding | Status | Evidence in `316705d` |
|---|---|---|
| Opus F1: car-to-car `event_id` per contact drops the second perspective | **Closed** | Identity is now per (contact, primary car), with an optional shared `contact_id` (`impact_event.gd:42–50, 131–145`). `_case_two_perspective_car_car` (`impact_lab_driver.gd:287`) publishes both perspectives. |
| Sol 2: duplicate ID silently coalesces a conflict | **Closed** | `same_payload()` compares every field (`:300–317`). The ledger coalesces only exact repeats and refuses conflicts with `conflict_count` (`:582–600`). Duplicate detection runs before the capacity check. Reuse after pruning is documented (`:491–496`). Covered by `_case_conflicting_duplicate_refused` and `_case_duplicate_retention_window`. |
| Sol 1: mandatory field omission | **Closed** | Builder defaults are out-of-domain sentinels: `UNSET_VECTOR` = INF, NaN severity, `REGION_UNSET`, zero normal, committed=false (`:376–391`). Each one fails `validation_error()`. `missing_fields()` (`:426`) gives a per-field report. Covered by `_case_required_field_omission`. |
| Opus F4 / Sol 1: claimed authority and severity derivation | **Closed as wording** | `committed` is documented as a caller assertion (`:63–71, 160–162`). Severity derivation is stated as an integrator obligation that the lab cannot verify (`:18–24`). |
| Sol 4: numeric domain | **Closed** | An unknown `NormalMode` is refused (`:397, 455`). `stable_norm` uses scaling (`:352–359`) and backs both the exported magnitude and NORMALIZE. Covered by `_case_large_finite_vector_domain` (1e20 gives a finite norm) and the normalization case. |
| Opus F5: ledger settings and forward ticks | **Closed** | Settings are private and re-clamped on use (`:528–559`). Covered by `_case_ledger_settings_immutable`. The far-future tick is now documented as an integration obligation (`:498–504`). |
| Sol, digest sampling | **Closed** | The digest is a loss-free `var_to_bytes` encoding of every field (`:682–737`). Covered by `_case_digest_covers_every_field`. |
| Opus F2: restore and mirror not atomic | **Closed** | `restore_and_mirror()` (`automatic_gearbox.gd:346`) validates both inputs, then commits. The two-call form is documented as non-transactional. |
| Opus F3: `propose()` contract | **Closed** | The commit discipline is documented in both headers (`automatic_gearbox.gd:76–86`, `car_state.gd:24–31`). |
| Sol 6: dwell domain and header claim | **Closed** | `MAX_SHIFT_DWELL_S = 10.0` (`:105`) is enforced in the config, in `GearboxState.is_valid()` and in restore (`:461`). The header's reverse-exit wording is corrected. Covered by `dwell_domain`. |
| Sol 3: five unmapped runtime properties | **Closed as a decision** | The mapping doc and `src/data/README.md` list all five with units. They require an explicit missing-field refusal of every schema-valid recipe until a versioned schema adds them. Uncapped yaw (`INF`) is called out. Typed defaults are forbidden as authored values. The doc correctly says no refusal code exists yet. |
| Opus F7a: exact deferred declaration | **Closed** | A surrounding-whitespace entry is refused, not stripped (`car_definition.gd:216–232`). |
| Opus F6: fixture handling ID | **Closed** | The fixture now uses `example.data_lab.car.handling`. The README says the validator does not enforce the derivation, which is acceptable because it is a baker obligation. |
| Sol: schema-version round trip | **Closed** | Explicit comparisons at `validate_data_lab.gd:408` (handling) and `:490` (car), with 9.9.9 alteration controls at `:301` and `:365`. |
| Sol 5 / Opus F7c: scratch cleanup safety | **Closed** | `_cleanup_scratch_dir` (`validate_data_lab.gd:1580–1615`) works as follows: <br>• It snapshots the listing, including hidden entries. <br>• It removes only the four known basenames and only when they are not directories. <br>• It never recurses: `remove_absolute` unlinks a symlink rather than following it. <br>• It retains and reports every other entry. <br>• It removes the reservation only when the reservation is empty. <br>The runner log shows unexpected, subdir and `.hidden` entries retained. Test teardown checks bytes and basenames. |
| Opus F7d: impact tripwire on `wall_contact_point` | **Closed** | `impact_lab_driver.gd:944–950` now requires the witness to be present. |

## Newly integrated work, assessed against its contracts

**Wall contact point witness (`motor_body_adapter.gd`)** holds. Specifically:
- `wall_points` is appended in the same loop and the same block as `wall_normals`, so the two lists stay index-aligned across collision indices and substeps.
- The normal and the point share one selector, `_select_wall_response_index` (`:773`), driven by the same `velocity_world` (`:572–584`).
- Fields are written to `Result` only on the committed path (`:603+`). `_reject` and the motion-bound refusal never set the witness.
- A degenerate road-plane projection or a nonfinite point publishes `has_wall_contact_point=false`, while the response normal is still applied. That is documented.
- The pinned-Jolt case checks three things: the point lies on the wall plane within 5 cm, the point equals the replayed `get_position(index)`, and it equals the replayed winner.

**One-car gearbox DriveLab (`drive_lab.gd`)** holds. Specifically:
- `step_once` proposes exactly once per COMMITTED tick from the committed physical record (`:757`), mirrors it, then publishes the pair (`:782`).
- A refusal halts with a bounded reason and never publishes an unmirrored record.
- Spawn and reconfiguration reset the gearbox and the mirror together.
- `restore_drive_snapshot` (`:656`) validates the pair in a temporary gearbox before swapping, then blocks every tick because the body pose is not restored. The no-reconciliation limit is stated plainly.
- Shift-event telemetry is bounded at 128 and records only paired ticks.

## Findings, most severe first

Every finding below is **Low**. Implementation defects are separated from test-strength and documentation items.

### Implementation defects

**N1. Low (M1.8 contract): the same perspective can be published twice under two IDs and double-count damage.**
- **Where:** `impact_event.gd:582–623`. Deduplication keys on `event_id` only.
- **Reproduction:** a producer retry that allocates a fresh ID:
  1. Publish (id `e1`, contact `c`, primary `A`, tick 5).
  2. Publish an identical payload as (id `e2`, contact `c`, primary `A`, tick 5).
  3. Both return PUBLISHED, so `A` receives two damage records for one physical contact.
- **Context:** the contract makes `event_id` per (contact, primary car). When `contact_id` is non-empty, (`contact_id`, `primary_car_id`) is therefore a second uniqueness key that the ledger could enforce cheaply.
- **Fix:** when `contact_id` is set, refuse or coalesce a second retained record with the same (`contact_id`, `primary_car_id`). Otherwise, document this as an obligation of the producer that allocates IDs.

**N2. Low (M1.8 contract): `is_opposite_perspective()` does not check the cross-pairing of car IDs.**
- **Where:** `impact_event.gd:179–188`.
- **Counterexample:** records (primary A, other B, contact `c`, tick t) and (primary C, other D, contact `c`, tick t) are reported as opposite perspectives.
- **Test gap:** the test at `impact_lab_driver.gd:~301–302` asserts the crossing itself, outside the predicate, so it does not exercise this.
- **Fix:** also require `primary_car_id == other.other_car_id` and `other_car_id == other.primary_car_id`.

**N3. Low (integration caveat, wall witness): the reported point is taken at the moment of contact, but the contract's local frame is the committed pose.**
- **Where:** `motor_body_adapter.gd:572–584`; `impact_event.gd:32–34`.
- **The mismatch:**
  - `get_position()` comes from a substep sweep that uses the tick-start basis.
  - After that contact, later substeps can slide the body along the wall, up to roughly v·dt (about 0.5 m at 30 m/s).
  - The yaw constraint applies at commit.
- **Consequence:** if the future producer expresses the world point in the committed local frame, near a hull corner `region` can flip, for example FRONT versus LEFT.
- **Not a defect of the witness itself.** The M1.8 producer must decide which frame defines `contact_point_local_m` and `region`, and test a corner case.

**N4. Low (DriveLab): `restore_drive_snapshot()` does not check `failed`.**
- **Where:** `drive_lab.gd:656–686`.
- **Effect:** on a laboratory that already failed, for example after a gearbox refusal, a restore replaces the gearbox and `state`, increments `drive_restores` and returns true. `failure_reason` stays set and ticks stay blocked.
- **Harm:** no unsafe outcome, but the "restore succeeded" telemetry on a failed laboratory is misleading.
- **Fix:** refuse the restore when `failed`, or document the behaviour.

### Test-strength and optional improvements

- **T1. Weak source-string guards.** Three of the wall-witness checks are source-string guards (`body_lab_driver.gd:1356–1370`). A dead-code mutant can satisfy them.
- **T2. The real-Jolt replay cannot catch a wrong-index mutant.** It replays the first colliding substep against a single wall. All candidates there are the same wall, so a mutant that published `wall_points[0]` would still pass the Jolt case. That mutant would be caught only by the fixture case on `_select_wall_contact`, not by a `step()`-level test.
- **T3. Replay uses a different velocity from the adapter.** The replay selects with `proposed_state.velocity_m_s` (`:1653`), while the adapter uses the post-yaw-constraint `committed_velocity_road`. This is equivalent only in the single-wall, unconstrained case, which the test asserts (`heading_constrained == false`). A two-wall corner case through real `step()` would close T2 and T3. Multi-wall corners are already an open M1 item.
- **T4. Non-fatal ObjectDB leak.** DriveLab leaks 4 ObjectDB instances at exit. This is non-fatal and pre-existing (Sol flagged it at d910c72). Worth tracing before strict-warnings CI.
- **Nit: unused gearbox helper.** `drive_lab.gd` repeats the logic of `restore_and_mirror()` inline (temporary box plus `restore_state` plus `mirror_gear`). Reusing the gearbox helper would keep one transactional path.
- **Nit: `REGION_UNSET` assignment.** `REGION_UNSET` (−1) is assigned to a `ContactRegion`-typed variable without a cast (`impact_event.gd:159, 388`). No warning appears in the supplied logs. Recheck under `--strict-warnings`.

## Missing milestone evidence (not implementation defects)

- **M0.2:**
  - the importer/baker and its missing-field refusal code;
  - the versioned source schema that adds the five fields;
  - source-to-runtime conversion tests, content hashes and provenance;
  - the track, event, upgrade, AI, ghost and scenario resources;
  - every `DEFERRED_FIELDS_V1` field.
- **M0.3/M0.4:**
  - the output-rights items OI-02 and OI-03;
  - the remaining entry points;
  - whole-M0 boot, smoke and desktop acceptance records.
- **M1.8:**
  - the impact producer that turns a committed adapter result into an `ImpactEvent`, including the frame choice in N3 and ID allocation (N1);
  - committed publication and reset behaviour;
  - the cosmetic consumer.
- **M1, other:**
  - body-pose reconciliation for drive restore;
  - multi-wall corners and depenetration (M1.4);
  - support adhesion, landing and reset recovery;
  - drift, surge, drafting, and calibration of gear thresholds and dwell (M1.6/M1.7);
  - shift audio and HUD gear readout, which are explicitly not wired;
  - keyboard and physical-controller traces and 30/60/120 FPS trace tolerances;
  - rendered-motion and listening evidence;
  - four-player routing.
- **Verification:**
  - hosted CI run 46084852580 on `316705d` was pending at freeze;
  - no Linux or Windows launch evidence exists.
- **Milestones:** M0 and M1 acceptance both remain open.