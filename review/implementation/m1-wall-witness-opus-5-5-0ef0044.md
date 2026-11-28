# Independent M1 interim checkpoint review: 0ef0044 (bounded slice)

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, run in Claude Code CLI. Date 2026-11-28.
- Role: read-only independent reviewer. No delegation, no other reviewer consulted, no Git
  mutation, shared checkout not used.
- Candidate: `0ef00441c6da7734721fa84012812351dbc9d161` exact committed tree (immutable archive at
  `opus/source`, no `.git`). Base for the relevant changes: `55aa249`.
- Scope: 22bed8e (DriveLab stale-pose halt, HUD gear assertions) and 0ef0044 (adapter wall-response
  witness), as given by `../scope.patch` (7 files: `src/simulation/impact_event.gd`,
  `src/simulation/motor_body_adapter.gd`, `tools/body_lab/{README.md,body_lab_driver.gd}`,
  `tools/drive_lab/{README.md,drive_lab_checks.gd,drive_lab_driver.gd}`). Schema/CI commits are out
  of scope.
- This is not an M1 or M1.8 pass claim. No wall-impact producer exists at this SHA.

## Verdict

**Changes required, bounded.** The component behaviour itself checks out. DriveLab halts correctly
on a stale pose, the HUD gear checks use the real label, and the adapter witness samples at the
right points and refuses invalid input. All pass, and mutation controls show the regressions catch
the intended faults. Two things must change before the witness can feed an M1.8 `ImpactEvent`
producer: the frame convention (F1) and the response normal (F2). Neither is an implementation
defect in the code at this SHA. Both are plan and contract mismatches between the new witness
documentation and the existing `ImpactEvent` contract, and the witness alone cannot yet satisfy that
contract. If the coordinator scopes this checkpoint strictly to "component behaves as its own docs
say", that part is a **pass**. Imparted motion (F3) is **not verified**, because there is no source
for it.

## Commands run and outcomes

Pinned engine: `work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`,
`--version` = `4.7.2.stable.official.ed1daf0bf`. All runs used private copies under `opus/`
with `TMPDIR` under `opus/`. Each runner stages its own scratch project, so the imports are isolated.

1. `shasum -a 256` over every source file before any run (1,184 files), and again after.
   `cmp` reports them identical: **source unchanged** (`logs/source-sha-{before,after}.txt`). No
   `.godot/` was created in the source.
2. Baseline, private copy `build-opus`:
   - `tools/body_lab/run_body_lab.sh --godot $G --project build-opus --timeout 900` gave
     `SLICE_SUMMARY {"cases":20,"checks":2901,"failed_cases":0,"pass":true}`, exit 0
     (`logs/opus-body-full.log`).
   - `tools/drive_lab/run_validation.sh --project build-opus --godot $G --timeout 900` gave
     DRIVE_LAB 15 cases / 5,079 checks / 0 failed on Jolt; bad-config 99/99; the deliberate failure
     probe rc=3 (fails as intended); exit 0 (`logs/opus-drive*.log`).
   - These reproduce the coordinator's counts.
   - Noise: the runners' scratch cleanup printed `rm: Permission denied`, because the archive's
     0400 file modes were copied into the stage. This did not affect results. I removed the scratch
     afterwards.
3. Mutation controls, each in its own private copy:
   - **(a)** Pre sample replaced by the unreprojected motor velocity: one added line after
     `motor_body_adapter.gd:648` (`witness_pre_velocity = road_vector_to_world(proposal.state.velocity_m_s)`).
     I kept the original source text so the string checks still pass.
     - `--case wall_response_witness_telemetry` **fails**.
     - Failures: "witness yaw tick 2..6: pre equals the reprojected proposal velocity (error
       0.596)", "post is the wall response applied to pre", and "contact change is along the wall
       normal (cosine -0.976)".
   - **(b)** Witness frame replaced by the final tick pose
     (`Transform3D(basis_from_heading(applied_heading), start.origin + accepted)` after `:662`).
     - The same case **fails**, but only on basis checks: "frame basis is the tick-start sweep
       basis" and "the frame is not the finalized tick pose", ticks 2-6.
     - No origin assertion failed. This confirms F5.
   - **(c)** Both `_halt_for_pose_block()` guards in `drive_lab.gd` disabled (`:314`, `:424`).
     - DriveLab **fails with exactly 21 checks**, all in `gearbox_integration`:
       `gearbox.{restore.auto,failure.proposal,failure.mirror}.{auto_start_terminal_state,
       auto_start_explicit_halt_reason, auto_no_scripted_command_consumed, auto_still_not_completed,
       repeat_start_no_script_progress, repeat_start_not_completed, halt_reason_stable}`.
   - **(d)** `SpeedHud._gear_text` forced to `"1"` for forward gears (`speed_hud.gd:371`).
     - DriveLab **fails 1 check**: `hud.gear.forward_label_mirrors_committed_gear (gear=2)`. The
       real label node is read.
4. I removed all private copies and scratch afterwards. Logs are kept under `opus/logs/opus-*`.
   I did not create the pre-existing `opus/build` directory and did not touch it.

## Files inspected

- `../scope.patch`, in full.
- `src/simulation/motor_body_adapter.gd`: Result fields 313-368, `step` 388-697, selection and
  response 840-993.
- `src/laboratory/drive_lab.gd`: 75-470, 670-830, 1098-1121, 1160-1339.
- `src/simulation/impact_event.gd`: 1-160, 280-306, 400-500.
- `src/presentation/speed_hud.gd`: gear lines 226-413.
- `scenes/ui/speed_hud.tscn`: GearLabel.
- `tools/drive_lab/drive_lab_checks.gd`: `hud_label_text`.
- `PLAN.md` M1 items (72-79).
- `docs/TECHNICAL_DESIGN.md`: 59, 71, 73, 87.
- The coordinator logs in `opus/logs`.

## Findings (ranked)

### F1. Frame convention conflicts with the ImpactEvent contract (plan/contract mismatch, blocks the producer)

- `impact_event.gd:32-34` requires `contact_point_local_m` in "the primary car's **committed**
  local frame ... at the tick of commitment". `:37-38` requires the region to be classified
  "against the **committed** hull".
- The new witness docs say the opposite. `motor_body_adapter.gd:349-368`
  (`wall_contact_transform`) states that the frame is deliberately *not* `committed_transform`, and
  that "a future `ImpactEvent` producer uses it to express the contact point in the car's
  **contact-time** local frame". The header at `:41-62` says the same.
- On a constrained-yaw tick the two frames differ by the applied yaw. Mutant (b) shows this: real
  Jolt contact ticks 2-6 have different bases.
- As a result, a producer that follows the witness docs violates the ImpactEvent contract, and one
  that follows the contract cannot use `wall_contact_transform` as documented. The region can flip
  near a corner (for example FRONT vs RIGHT) depending on the choice.
- On physics grounds the contact-time frame is the more defensible one: the contact point was found
  with the hull at the tick-start basis. Either way, one document must change.
- Required: pick one convention, then update `impact_event.gd:32-38`, the TECHNICAL_DESIGN impact
  paragraph (`:73`, which says only "primary-car-local") and the adapter docs to match. Do this
  before any producer lands.

### F2. The witness does not publish the normal the response actually used (contract gap, blocks the producer)

- The response projects the selected normal onto the road plane before using it:
  `_apply_wall_response` uses `_road_plane_unit_normal(normal)` (`:981`, defined `:963-968`).
- The published `wall_contact_normal` is the raw stored candidate. `_select_wall_response_normal`
  returns `normals[index]` unchanged (`:892-895`, documented at `:886-887`).
- Wall-like candidates may have up to `|n·up| <= wall_normal_max_up_alignment` (0.5 by default,
  `:188`, filter `:856-857`). So the raw normal can be tilted up to 30 degrees from the
  normal that produced the velocity change.
- `impact_event.gd:28-29` requires the "unit physical contact normal **used by the contact
  response**". A raw Jolt normal is unit length, so the `NormalMode.PRESERVE` builder would accept
  it silently. The result would be a published normal inconsistent with `pre - post`, which lies
  along the projected normal (the lab asserts this at `body_lab_driver.gd` `_check_witness_change_along_normal`).
- Current lab walls are vertical, so their normals are already horizontal and no regression
  exercises a tilted wall-like normal. This is static evidence, from the code paths cited above.
- Required: publish the projected response normal with the witness, or document that the producer
  must project. Add a tilted-barrier regression (for example a normal with y ≈ 0.4) when that is done.

### F3. `imparted_motion_m` has no authoritative source (missing evidence for M1.8)

- `impact_event.gd:35-36` requires contact-induced displacement.
- The witness explicitly provides none: `tools/body_lab/README.md` "does not ... infer
  contact-induced displacement".
- The sweep stops at the first short collision, and restitution in the lab is 0, so a producer
  would have to justify a value, including zero. The contract therefore cannot yet be met.
- **Not verified.** This is not a defect at this SHA.

### F4. The witness flag is true on non-approaching wall contact; this is untested (regression gap / producer obligation)

- `has_wall_response_witness` is set on every selected valid wall candidate (`:661-663`).
- When the normal speed is >= 0 (separating, or sliding along the wall), `_apply_wall_response`
  returns the input unchanged (`:984-986`), so pre == post. The witness is then true with zero
  severity.
- This is truthful, but every tick of a car scraping or resting against a barrier yields a
  zero-change witness. No regression asserts that behaviour.
- A producer needs an explicit rule for zero or minimum severity to avoid per-tick event floods.
  The ledger coalescing rules at `impact_event.gd:545-552` require a distinct contact ID per later
  tick.

### F5. Truthfulness detail: the frame origin equals the committed origin in real Jolt runs (documentation precision)

- The sweep breaks on the first collision with short travel (`:524-526`). So in practice the
  winning candidate is from the final substep, and the frame origin is `simulated.origin + actual`,
  which is `start.origin + accepted`, the committed origin.
- The doc claim that the frame is "not `committed_transform`" holds only for the basis, and only on
  ticks where the yaw was applied. Mutant (b) confirms this: it changed origin and basis, and only
  the basis checks failed.
- Different origins can occur only for grazing contacts with full travel, and only the fixture
  (`_case_wall_response_witness_selection`, "Later motion must not move the published frame")
  covers that.
- Also document that the pre sample is the end-of-tick motor proposal (reprojected), not an
  instantaneous mid-tick velocity. This matches the single-response model at `:619-652` and the
  contract wording "immediately before the response", but a severity consumer should know it.

### F6. Regression quality (nits)

- `body_lab_driver.gd` `_case_wall_response_witness_selection` source-text checks (`contains`/`find`
  around `:2546-2610`) are brittle and only prove textual order. Behaviour is properly covered by
  the real-Jolt yaw case, as mutant (a) shows.
- The selection case's "Yaw-only reprojection" block (around `:2923-2965`) never calls `step`. It
  recomputes from helpers, so it is tautological.
- "pre is a velocity, not the tick displacement" (`:3385`) compares a velocity against a
  displacement and cannot fail meaningfully.
- The HUD gear check at `drive_lab_driver.gd:1430` uses `lab.state.gear_index`, the same mirror the
  HUD consumes, as its oracle rather than the canonical gearbox state. It also does not check
  downshift text.

### F7. DriveLab patch provenance (evidence gap, not a defect)

- The runtime behaviour is correct by inspection and by test:
  - `_physics_process` (`drive_lab.gd:308-330`) and `start()` (`:421-427`) call
    `_halt_for_pose_block()` (`:1282-1286`) before consuming a script entry or `_complete()`.
  - `_reset_run_state()` (`:1172-1225`) deliberately keeps `_drive_body_pose_stale`.
  - `restore_drive_snapshot` and `_reject_gearbox_step` set it (`:705`, `:1296`). The nonfinite
    committed path does too (`:773`).
  - A manual `step_once` under the block returns null without halting (`:754`), as documented.
  - Mutant (c) shows the 21 new assertions depend on these guards. That matches the coordinator's
    "old-source control failed 21".
- However, `scope.patch` contains no hunk for `src/laboratory/drive_lab.gd`, although
  `tools/drive_lab/README.md` describes the halt as new behaviour.
- Without `.git` I cannot tell whether the guard code predates `55aa249` or the patch omits it. The
  coordinator should confirm that the scope patch covers every 22bed8e implementation path.

## Questions asked, answered

- **DriveLab stops after a committed physical step with unpublished state, including after
  configure/reset and automatic runs:** yes (F7). The mirror-failure and proposal-failure paths, and
  the state-only restore, all halt `start()` and the auto path with the explicit reason, with no
  script progress, adapter call, shift event or completion. Repeated start attempts stay inert.
  Verified by the baseline and mutant (c).
- **HUD gear tests use actual projected outputs:** yes. They read the `Contents/GearLabel` text, and
  mutant (d) is caught. Rendered readability and layout are not verified.
- **Witness bound to the selected point, normal and time:**
  - The point and frame use the same index as the response normal (`_select_wall_contact`
    `:912-942`).
  - There is no sub-tick time field: the witness is bound to the tick and to the colliding
    substep's pose.
  - The published normal is the raw candidate, not the response normal (F2).
- **Pre/post world velocities after reprojection:** correct. Pre is taken after reprojection
  (`:619-625`, `:648`) and post right after the response (`:652`). It equals the committed state
  velocity in world axes. Verified on real Jolt and by mutant (a).
- **Refuses or zeros invalid and no-contact records:**
  - The refusal and rejection early returns (`:401-438`, `:532-541`, `:575-582`) happen before the
    witness is written.
  - The fields are written only when the flag is set (`:688-692`).
  - `_finite_transform` (`:947-958`) guards the frame.
  - The real-Jolt open, refused and rejected checks pass.
- **Physics or authority fault:** none found in the code at this SHA.

## Limits

- The archive has no `.git`, so commit contents beyond `scope.patch` could not be checked (F7).
- Hosted CI does not run the body or Drive labs. My lab runs are local and headless on macOS, with
  the pinned 4.7.2 Jolt.
- No rendered or visual HUD check was done.
- No tilted wall-like collision was exercised; F2 is static evidence.
- No producer exists, so F1-F4 are implications for future work, not observed failures.


---

## Coordinator identity and scope attestation

The report above is copied verbatim from this reviewer's private packet. The Opus Claude CLI JSON records actual `claude-opus-5-5` on `firstParty`; the Sol Codex CLI stderr records `model: gpt-6.2-sol`, `provider: openai`. Both reviewed the exact `0ef00441c6da7734721fa84012812351dbc9d161` archive. The supplied `scope.patch` accidentally omitted `src/laboratory/drive_lab.gd`; `git show 22bed8e -- src/laboratory/drive_lab.gd` in the coordinator checkout confirms the runtime halt guards were introduced by that commit. Both reviewers nevertheless inspected the candidate runtime file and executed the DriveLab checks, so their behavior findings stand. The omission is an evidence-packet flaw, not an absent implementation. The two reports agree on the wall-event frame and normal contract gaps; the bounded M1 component gate remains open until the producer and those contracts are checked on a corrected exact candidate.
