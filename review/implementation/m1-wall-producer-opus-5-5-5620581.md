# M1.8 wall-impact producer recheck: Opus 5.5 independent review

## Identity and scope

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, through Claude Code. Date: 2026-11-28.
- Candidate: `5620581206fc1cb2504b5113a5f208a11fef62f3`. Scoped base: `0ef00441c6da7734721fa84012812351dbc9d161`.
- Scope: the nine files in `scope.patch`:
  - `docs/TECHNICAL_DESIGN.md`
  - `src/simulation/impact_event.gd`, documentation only
  - the new `src/simulation/wall_impact_producer.gd`
  - the new `tools/wall_impact_lab/*`
- Source identity: `git hash-object` on every scoped file in the read-only `source/` archive matches the post-image blob in `scope.patch` (`logs/opus-blob-check.txt`). SHA-256 values are in `logs/opus-source-hashes.txt`. I did not have a `.git` directory, so I did not verify the commit object itself.
- Process: I did not delegate, consult the other reviewer, mutate Git or the shared checkout, or publish anything. I wrote only this report, `logs/`, and the scratch files and `tools/opus_probe/` in my private `build/` copy.
- Not claimed: an M1 or M1.8 pass.

## Files inspected

- `src/simulation/wall_impact_producer.gd`, all lines.
- `src/simulation/impact_event.gd`: the contract header, `validation_error`, `stable_norm`, `Builder` and `Ledger.publish`/`_pair_key`.
- `src/simulation/motor_body_adapter.gd`: the header at lines 30-90, `Config.is_valid`, the `Result` fields at lines 282-372, sweep and commit at lines 440-700, and contact collection, selection and response at lines 820-1014.
- `tools/wall_impact_lab/*`, all files. I also read `tools/body_lab/body_lab_world.gd` and the `body_lab_checks.gd` fixtures.
- `docs/TECHNICAL_DESIGN.md:73`, `docs/GAME_DESIGN.md:57-59` and `PLAN.md:79` (M1.8).
- `review/implementation/m1-wall-witness-{opus-5-5,gpt-6-2-sol}-0ef0044.md`.
- `.github/workflows/ci.yml` and `tools/ci/ci.sh`, to check test discovery (`cmd_test`, line 1296 onward).

## Commands and outcomes

Every engine call used the pinned editor `toolchain-m01/.../Godot`, which reported `4.7.2.stable.official.ed1daf0bf`. All calls were serialized on the coordinator `godot-test.lock` and bounded by `timeout`. `HOME` and the `XDG_*` directories were isolated under `build/.home`, and scratch staging was under `build/.tmp`. Before the run, `diff -rq source build` reported the two trees identical.

1. `build/tools/wall_impact_lab/run_wall_impact_lab.sh --project build --godot <pinned> --lock <coordinator lock> --timeout 120 --outer-timeout 600 --log logs/opus-validator.log`
   - Runner exit code 0. Validator: 9 cases, 238 checks, 0 failed.
   - The real Jolt case hit the wall at tick 36: 30.0 m/s before the response, 0.0 after, severity 30.0, region FRONT.
   - The deliberate failure probe exited 3 with `"pass":false`.
   - This reproduces the coordinator's claim. Logs: `logs/opus-run.log` and `logs/opus-validator.log`.
2. Private reviewer probe, which is not candidate code (`logs/opus-probe-driver.gd`). It imported a staged copy, then drove the real `MotorBodyAdapter.step` with pinned Jolt into a wall for 30-180 ticks. For every witness tick it called `WallImpactProducer.produce`, then `publish` into a real `Ledger`.
   - Import, run 1, run 2 and run 3 all exited 0 with no engine errors. Logs: `logs/probe-import.log` and `logs/probe-run{,2,3}.log`. Results are summarized under the findings.
3. `gh run view 46094161787 -R L-K-M/Roadstorm` (read-only): headSha `5620581…`, completed, success in all four jobs. This confirms the coordinator's external claim. See finding 4 for what that run does not cover.

Capability limits: I made no Linux, Windows or other-renderer runs. My Jolt runs used flat ground with a single vertical box wall. I could not observe coordinator authority, multi-car behavior or tilted real walls, because none of them exist in this candidate.

## Verdict

**Changes required (narrow).** The producer's authority and refusal contract **passes**. Region classification on real corner contacts **needs a change** before cosmetic code consumes `region`. Event-rate and coordinator-authority policy is **not verified** and remains a plan gap.

These items pass, from source inspection backed by the lab and my probe:

- **Committed witness required.** `produce` refuses unless `status == COMMITTED` and both witness flags are set (`wall_impact_producer.gd:110-115`). It also requires a non-null, finite committed state (`:117-121`).
- **Inputs checked.** The producer checks that the pre and post velocities, the raw normal, the point and the frame are finite. It also checks that the frame is non-degenerate and that the local point is finite.
- **Post velocity matches the committed state.** Post must equal the committed planar velocity mapped to world axes, within 1e-6 (`:123-137`). The adapter writes `committed.velocity_m_s` from that same `velocity_world` (`motor_body_adapter.gd:664`), so the agreement is exact.
- **Collision-time frame.** `contact_point_local_m = wall_contact_transform.affine_inverse() * wall_contact_point` (`:156`). My probe confirms this is the right frame. In `near_steer_pos`, the collision-time frame puts the struck corner at the hull vertex, local (-0.89994, 0.5, -1.89988). The final post-yaw frame would put it at (-0.95028, 0.5, -1.87521), 5 cm outside the hull. That frame-alignment requirement from the prior Opus review is met.
- **Response normal.** The published normal is the road-plane projection of the selected `wall_contact_normal` (`:139-150`), never the generic `contact_normal`. This matches `_apply_wall_response`, which also uses `_road_plane_unit_normal`.
  - The tilted-normal lab case covers this, so the prior F2 item is met.
  - Rounding nit: the producer normalizes with `stable_norm` and the adapter with `sqrt(length_sq)`, so the two can differ in the last bit. This is harmless.
- **Severity.** Severity is only `stable_norm(pre - post)` (`:160`). The producer has no motor, throttle or travel input.
- **Imparted motion.** `imparted_motion_m = Vector3.ZERO` is explicit (`:177`), and `accepted_motion_m` is never read. The documentation in `impact_event.gd` and the producer states why. This is consistent with the adapter: the response changes only velocity, after the sweep.
- **No ID assignment.** The producer allocates no ID. It forwards the caller's `event_id`, `contact_id` and `tick_index`.
- **Real ledger, no mutation.** `publish` forwards to the real `ImpactEvent.Ledger.publish` (`:192-199`). The producer writes to no result, state, config or ledger field. The nonmutation lab case snapshots every `Result` field, and my reading of the source agrees.
- **Fail-closed refusals.** 22 refusal probes fail closed with no event and no ledger change. The ledger lab cases cover publication, identical-retry coalescing, conflicting-payload refusal, duplicate-perspective refusal and capacity.

## Findings, ranked

### 1. Region flips between FRONT and LEFT/RIGHT on real corner contacts (implementation and design; important for consumers)

- **Where:** `wall_impact_producer.gd:228-245` (`_classify_region`) and `:178`.
- **Cause:** Jolt reports box-wall contacts at a hull **vertex**. A vertex lies on the FRONT/LEFT boundary by construction. The classifier compares `|x|/hx` with `|z|/hz`, which differ by fractions of a millimetre of solver noise. The "deterministic exact tie goes to FRONT/REAR" rule never applies to real contacts, because they are near-ties rather than exact ties.
- **Pinned-Jolt evidence** (`logs/probe-run3.log`):
  - `near_steer_pos`: one continuous front-left corner contact against a wall whose local normal is (0.027, 0, 0.9996), so the wall faces the nose. It classified **FRONT** on the 20.1 m/s first hit (|x|/hx = 0.99993 vs |z|/hz = 0.99994). It then classified **LEFT** on the next 28 ticks (0.99943 vs 0.99760). `near_steer_neg` mirrors this with RIGHT.
  - `near_steer_pos_heading`: a **19.95 m/s**, nearly head-on hit, with a local response normal of (0.30, 0, 0.95), published as **LEFT**. Under `GAME_DESIGN.md:57` (5 m/s detaches the struck part), the front bumper would be untouched and the side would register the hit.
  - Even the passing lab Jolt case was FRONT by only 0.07% (local z = -1.90130 vs x = 0.9 exactly; `logs/probe-run.log`, `throttle_head_on`).
- **Why it matters:** `region` is the field the M5.9 cosmetic consumer uses to choose a bumper. As written, the classification depends on solver rounding.
- **Suggested fix** (a design decision for the owner): break near-ties using the response normal expressed in the same collision-time frame, `wall_contact_transform.basis.inverse() * contact_normal`. Alternatively, classify primarily by that normal and use the point only for laterally ambiguous cases. Add a pinned-Jolt corner case in which the struck face is known, such as `near_steer_pos_heading` above.

### 2. Sustained wall contact publishes one event per tick with no floor, continuity or zero-delta rule (plan gap; prior F4 still open)

- **Where:** the producer accepts any severity ≥ 0 (`:160-162`). `Builder` documents exact zero as a valid publication (`impact_event.gd:416-422`). The wall path's `contact_id` defaults to empty (`:94`), so the ledger's duplicate-perspective guard does not apply, and nothing links consecutive ticks of one physical contact.
- **Pinned-Jolt evidence** (`logs/probe-run.log`):

  | Scenario | Events | Severity < 2 m/s | Accumulated severity |
  | --- | --- | --- | --- |
  | Throttle held against a head-on wall, 180 ticks | 144 (one per tick from contact on) | 143 | 50.9 m/s |
  | Oblique 30° grind, 180 ticks | 146 | 145 | 56.3 m/s |
  | Idle 60° glance, 120 ticks | 87 | 86 | 48.9 m/s |

  - In the head-on case, each event after the first was about 0.133 m/s, which is the throttle's per-tick inward velocity being zeroed again.
  - The ledger does not overflow. At most one event per car per tick is far below the 64-per-tick capacity, and the retained window stays at 8 ticks.
  - However, `GAME_DESIGN.md:57` counts "8 m/s accumulated across that part's hits". Pushing into a wall would reach that in about 1 s (60 × 0.133), which conflicts with "repeated wall grinding cannot spawn an unlimited stream".
- **Zero-delta witnesses:** I observed none in these scenarios. By code they remain possible: `_apply_wall_response` returns velocity unchanged when `normal_speed >= 0` (`motor_body_adapter.gd:985-986`) while the witness flag stays true. The producer would then publish a severity-0 event. No lab case covers this.
- **Required decision** (coordinator or plan): whether the producer, the coordinator or the consumer owns the following, and test it in the chosen layer:
  - a minimum severity or zero-delta suppression;
  - a continuing-contact identity, such as a stable `contact_id` across ticks of one contact;
  - whether grinding events count toward accumulation.

### 3. The lab cannot detect a regression to the wrong frame, and its real case does not exercise the frame (test quality)

- **Synthetic fixture:** `wall_impact_lab_checks.gd:162` sets `committed_transform = wall_contact_transform`, so every synthetic case would still pass if the producer used `committed_transform`.
- **Real Jolt case:** heading 0, no steer, and a short stop give a frame gap of exactly 0 (my probe measured an origin gap of 0.0 and a yaw gap of 0.0 for that scenario).
- **Source contract case:** `_case_producer_source_contract` (driver `:776-830`) does not forbid `committed_transform` in the source.
- **Effect:** the requirement the prior Opus and Sol reviews raised, "test a case where using the final pose changes the result", is not met in the lab. My probe shows the code is correct (finding 1 evidence, 0.0267 rad yaw gap), but the candidate's own tests would not catch a regression.
- **Required:** make the fixture's `committed_transform` differ in yaw and origin, and assert that the local point and region follow `wall_contact_transform`. Also add a steering pinned-Jolt case such as `near_steer_pos`.

### 4. Hosted CI does not run this lab (missing evidence)

- `cmd_test` discovers only `tests/` and `tools/smoke/` (`tools/ci/ci.sh:1296-1342`). No workflow or CI script refers to `tools/wall_impact_lab`; a grep found none.
- The green run 46094161787 therefore shows that the new scripts import and pass the project scan. It does not show that any producer behavior passed.
- The only behavioral evidence is the local pinned-Jolt lab: the coordinator's run and mine.

### 5. Authority is the adapter's COMMITTED status alone (plan gap, carried forward)

- `produce` trusts `MotorBodyAdapter.Status.COMMITTED` and a caller-supplied `tick_index`.
- There is still no race-coordinator acceptance gate, for example after the DriveLab pair publication. The Sol 0ef0044 report flagged that adapter-level COMMITTED cannot stand in for coordinator acceptance.
- The documentation is honest about this: `wall_impact_producer.gd:48-53` and `impact_event.gd` state that commitment is a caller assertion. No coordinator wiring exists yet.

### Minor

- `_classify_region` ignores local Y, which is fine for the four regions. A point with x = z = 0 resolves to REAR. This is unreachable for a wall vertex.
- The refusal and lab check counts are self-consistent. The deliberate failure probe proves that the harness detects a failing check.

## Still absent at this SHA (not defects in this slice)

- Race-coordinator authority and event-ID allocation, including retry and ID policy.
- Car-car impact production and the committed-frame path that `TECHNICAL_DESIGN.md:73` reserves for it.
- Wiring of any presentation, sound or cosmetic-damage consumer.
- A tilted-wall pinned-Jolt producer case (the tilt is covered only synthetically).
- Multi-car and non-flat-ground behavior.

## Classification summary

| Kind | Items |
| --- | --- |
| Implementation or design defect | 1. Corner-contact region instability |
| Plan gaps | 2. Event rate, zero-delta and continuity; 5. Coordinator authority |
| Missing evidence or test quality | 3. Frame-discriminating test; 4. CI does not run the lab |
| Verified pass | The witness, post-velocity, frame, normal, severity, zero imparted motion, no-ID, ledger forwarding and no-mutation contracts listed under Verdict |


---

## Coordinator identity and disposition attestation

The report above is copied verbatim from this reviewer’s isolated packet. Opus CLI JSON confirms `claude-opus-5-5` on `firstParty`; the separate Sol Codex CLI header confirms `model: gpt-6.2-sol`, `provider: openai`. Each reviewed its own read-only plain archive of exact `5620581206fc1cb2504b5113a5f208a11fef62f3` and could not see the other current report. Hosted CI run 46094161787 completed green in all four jobs on that SHA. Opus independently reran pinned Jolt 9 cases/238 checks and a corner-contact probe; Sol’s Godot import hit a private sandbox editor-settings write limit, so its executable review is limited. Opus’s corner-region finding and Sol’s strict post-velocity finding are assigned to LongCat job `2310a6a6-c592-4456-a611-c0202939379f`; the sustained-contact/zero-delta policy, race publication authority and wall-lab hosted coverage remain open. No full M1.8/M1 gate is accepted by these scoped reports.
