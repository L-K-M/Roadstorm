# M1.8 wall producer corner and post-velocity recheck: Opus 5.5 independent review

## Identity and scope

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, via Claude Code. Date 2026-11-28.
- Candidate: `408d6198766fe040d932d10d94df0d68e2f34bae`. Scoped base: `5620581`.
- Scope: `src/simulation/wall_impact_producer.gd` and `tools/wall_impact_lab/**` as changed in `../../scope.patch`, plus their dependencies and physics contract.
- Scope checks I ran (Git, read-only): `git diff --stat 5620581 408d619` touches only those three files under `src/simulation`, `tools/wall_impact_lab` and `tools/body_lab`. The producer blob at `5620581`, `07b2858` and `2cab439` is the same (`a3de087`). The coordinator's "old 2cab439 producer" control therefore really is the scoped-base producer. My private `build/src` and `build/tools` match `../source/` byte for byte (`diff -rq`, no output).
- The DriveLab mutable-result retry defect is outside this scope and is not assessed. Live uncommitted repairs in the shared checkout were not read into this verdict.

## Files inspected

- `src/simulation/wall_impact_producer.gd` (all of it)
- `src/simulation/motor_body_adapter.gd`: the commit path, witness sampling and response at :543-698, the road/world mapping at :700-747, wall selection and response at :888-992, and the orientation tolerance at :118-120 and :184
- `tools/wall_impact_lab/wall_impact_lab_driver.gd` (every new case, the helpers and the steering Jolt case), `README.md`, `run_wall_impact_lab.sh`, `validate_wall_impact_lab.gd`
- `tools/body_lab/body_lab_checks.gd`, `body_lab_world.gd` (API only)
- `src/laboratory/drive_lab.gd:855-910` (the only live producer caller, for the integration note)
- `review/implementation/m1-wall-producer-opus-5-5-5620581.md` and `m1-wall-producer-gpt-6-2-sol-5620581.md`
- `../../evidence/new-producer-run.log` and `old-producer-control.log`

## Commands and outcomes

1. Candidate lab in my private build, using a temp stage under `../logs/tmp`, the shared lock and bounded timeouts:
   `TMPDIR=../logs/tmp timeout 900 tools/wall_impact_lab/run_wall_impact_lab.sh --project <build> --godot <pinned 4.7.2> --lock <build>/work/agents/coordinator/godot-test.lock --timeout 180 --outer-timeout 700 --log ../logs/opus-lab.log`
   - Result: rc=0, **13 cases/906 checks, 0 failed**. The deliberate failure probe exited rc=3.
   - Steering measurements match the coordinator's: in each direction, 29 witnesses, all 29 FRONT, and 28 named a side by the old point rule. First hit 20.10 m/s.
   - This reproduces `new-producer-run.log`.
2. A reviewer-only Jolt sweep probe. It is not candidate code: `../logs/probe/opus_corner_probe.gd` and its entry script.
   - Setup: a staged rsync copy of `build` (without `work/`) under `../logs/tmp/probe-stage`, with an isolated `HOME`. It ran `--import` (rc=0), then the probe under `lockf` with a 900 s timeout (rc=0, `OPUS_PROBE_DONE`). I deleted the stage afterwards. The log is `../logs/probe-run.log`.
   - Grid: 180 scenarios, made of speed {8, 20, 35} m/s × start heading {0, 0.15, 0.3, 0.5, 0.7, π/4, 0.9, 1.1, 1.4, π/2} × steer {-1, 0, 1} × throttle {0, 1}. Each scenario drives straight at a wide box wall for 40 ticks through the real `MotorBodyAdapter.step` and calls the candidate `WallImpactProducer.produce` on every witness.
   - Analysis: `python3 -I ../logs/probe/analyze.py` and `flips.py`.
   - Results: **3,672 witnesses**, all COMMITTED. **0 refusals** under exact post equality. Every contact was a hull vertex: both normalized coordinates were > 0.97.
3. Hosted CI was not queried. Coordinator evidence is cited as coordinator evidence only.

## Verdict: **changes required**

The post-velocity, frame, sign-mapping, severity, point, normal and imparted-motion repairs are correct. The 0.01 near-tie margin is not justified by physical noise. Real pinned-Jolt corner contacts routinely fall just outside it, and the original defect class recurs there: the region depends on solver noise, the label flips within one sustained contact, and the label contradicts the response normal on high-speed first hits.

## Verified correct

- **Exact post equality** (`wall_impact_producer.gd:148`):
  - The adapter writes `witness_post_velocity = velocity_world` and `committed.velocity_m_s = world_vector_to_road(velocity_world)` (`motor_body_adapter.gd:660-664`). The map is `(x, -z)` and back `(x, 0, -road.y)` (`:701-707`), so the round trip is a sign flip twice, which is exact.
  - `_apply_wall_response` uses a road-plane unit normal (`:981`), and `velocity_world.y` starts at 0, so post `y` is exactly ±0, and `-0.0 == 0.0`.
  - No false refusal occurred across 3,672 real witnesses, including steering and yaw-constrained ticks.
  - The lab rejects one ULP at 1 and at 20, offsets of 1e-9, 1e-7 and 1e-6, and an off-plane 1e-3. `_next_float32(20.0)` rounds to one float32 ULP when stored in a Vector3, so that probe is valid.
  - This closes Sol's prior finding. Sol's specific example, off-plane 5e-7, is not a fixture, but exact `!=` covers it.
- **Committed source for the published fields:**
  - Severity is `stable_norm(pre - committed_world)` (`:182`).
  - The post field is `committed_world` (`:196`).
  - The point is the witness world point plus `wall_contact_transform.affine_inverse()` (`:170`).
  - The normal is the road-plane projection (`:160`).
  - `imparted_motion_m` is explicitly zero (`:199`).
  - The probe saw no zero-severity event.
- **Local normal frame and sign mapping** (`:176`, `:266-281`):
  - `basis.inverse()` comes from the same collision-time transform as the point. The adapter's basis is orthonormal, so this equals the rotation part of `affine_inverse()`.
  - Local -Z is forward. A front-face hit pushes the car rearward (+Z), giving FRONT. A left-face hit pushes it rightward (+X), giving LEFT. Both mappings are correct.
  - Among 3,302 real in-band witnesses, none had a region inconsistent with the point's quadrant.
  - The rotated-frame synthetic case (`heading 0.3`) proves the normal is not read in world axes.
- **Steering Jolt case:**
  - It honestly demonstrates the original bug: 28/29 side labels under the old rule, which the old-producer control confirms with 58 failed region checks.
  - It demonstrates the corrected label for heading-0 steering only.
  - The summary keeps `physical_authority_verified:false` and makes no M1.8 or M1 claim.
- **Negative cases distinguish revisions:**
  - Near-tie, post-velocity and steering checks fail on the base producer (76 failures in the coordinator control).
  - `collision_time_frame_discrimination` passes on the old producer, which was already correct there. It is a regression guard against `committed_transform` and does not distinguish the two revisions. That is fine, but it should not be counted as discrimination evidence.

## Findings, ranked

### 1. Important: the 0.01 near-tie margin is below observed real corner noise, so FRONT/side labels still flip on solver noise

- **Where:** `wall_impact_producer.gd:62-69` (`REGION_TIE_MARGIN := 1e-2` and its justification comment) and `:266`.
- **Measured distribution:** `|lateral - longitudinal|` over the 3,672 real vertex contacts:
  - median 2.9e-3, p90 1.0006e-2, p99 1.198e-2, max **1.324e-2**
  - **370 witnesses (10%) lie in (0.01, 0.0133]**
  - 364 of those have an unambiguous response normal that names a different face than the point rule. The producer publishes the point label.
- **Cause:**
  - The adapter's installed-orientation probe shrinks the hull by `2 × orientation_contact_tolerance_m` (0.02 m; `motor_body_adapter.gd:118`, `:565-567`). An installed pose may therefore overlap the wall by about 0.02 m per face.
  - Jolt then reports the vertex inset by up to **1.58 cm in x and 1.38 cm in z** (probe minima of |x| and |z|).
  - Normalized by the 0.9 m half width, that inset alone reaches about 0.022.
  - The candidate's 4.1e-3 bound came from two heading-0 steering probes only. The comment's general claim, "this band therefore admits the solver noise", does not hold.
- **Effect, with real examples (`../logs/probe-run.log`):**
  - A 26.35 m/s first hit, `v35_h1.100_s1_t0` tick 4, comes in at about 63° yaw. The local normal is side-dominant and names LEFT, and diff = -0.0101, so it is **published FRONT**. Other high-speed cases: 14.63 m/s (`v20_h0.785_s1`), 14.07 m/s, 13.84 m/s, 13.43 m/s. 13 such events exceed 2 m/s.
  - In 19 of 170 scenarios the region flips within one continuous contact while the normal's face label never changes.
    - `v20_h0.900_s0_t0` publishes `lffffffffffffffffffffffllflffflfl` (8 flips).
    - `v20_h1.100_s-1_t0` flips 10 times.
    - In `v8_h0.900_s0_t0` the normal is constant at (0.783, 0.622) while diff hovers between -0.0099 (published LEFT) and -0.0113 (published FRONT).
  - This is the same consumer-visible defect as prior Opus finding 1, moved to yaw angles of roughly 40-70°. For M5.9, which selects a bumper from `region`, the result still depends on solver rounding.
- **Suggested fix (design choice for the producer owner):**
  - Derive vertex proximity in metres from the validated config instead of a fixed normalized difference. For example, treat a point as a corner contact when `|x| >= half.x - band` and `|z| >= half.z - band`, with `band` at least `orientation_contact_tolerance_m` plus a measured Jolt slop (≥ about 0.025 m today).
  - Or classify by the unambiguous response normal for every contact and use the point only when the normal is diagonal.
  - Either way, add a pinned-Jolt regression at a non-zero heading. For example, `v20_h0.900_s0_t0` (speed 20, start heading 0.9 rad, no steer, idle) currently fails "constant region for constant normal". Also add `v35_h1.100_s1_t0` for the high-speed first hit.
- **Scope of the evidence:** I did not test whether a larger band ever captures a genuine face-centre contact. Every witness in my sweep was a vertex, and the band would only ever widen around vertices.

### 2. Medium (test quality): the lab encodes the brittle constant and covers only heading-0 physics

- `LAB_REGION_TIE_MARGIN := 1e-2` (`wall_impact_lab_driver.gd:54`) mirrors the producer value. No case asserts that the margin covers physical noise.
- The only real-physics corner case uses `"heading": 0.0` for both scenarios (`:1394`, `:1403`). It cannot reach the 40-70° yaw regime where finding 1 occurs.
- `side_rule_count >= 1` (`:1513`) is weak next to the 28/29 the README claims. Asserting the measured count, or at least a majority, would catch a scenario drift that quietly stops exercising the bug.
- The `unambiguous` fixtures (`:1000`, `left_face` and `right_face` given a nose-facing normal (0, 0, 1)) assert "point beats a contradicting normal outside the band". Finding 1 shows that real contacts at 0.0101 are exactly the case where this rule is wrong. Keep these fixtures only with genuinely face-centre points, and do not treat them as evidence that the band is right.
- README (`tools/wall_impact_lab/README.md`, "Authority label") and the producer comment should state that the margin is calibrated on two heading-0 probes only.

### 3. Low: in-band classification does not check the normal's sign against the point's quadrant

- `:266-281` accepts any normal sign. For example, a front-left near-tie point with a −X response normal would publish RIGHT, a face that does not touch that vertex.
- Real Jolt contacts never did this (0 of 3,302 in-band witnesses), so this is defensive only. Falling back to the point rule, or refusing, when the normal's face does not border the point's corner would make malformed witnesses fail closed, in line with the producer's other refusal rules.

### 4. Separate integration issue (not a defect in this slice): sustained, continuing and zero-delta contact still yields one event per tick

- The sweep: up to 37 events per scenario, and **3,462 of 3,672 events (94%) below 0.5 m/s**, which is a grind stream. I observed no zero-severity event, but by code one is still possible (`motor_body_adapter.gd:985-986` returns the velocity unchanged while the witness flag remains set).
- This now reaches a live caller. `src/laboratory/drive_lab.gd:864-910` (`publish_wall_event`, pushed in `07b2858`) calls `WallImpactProducer.produce` for each witness tick with an empty `contact_id`.
- **Suggested owner:**
  - The coordinator decides the policy: a severity floor or zero-delta suppression, a stable continuing-contact `contact_id`, and whether grinding counts toward the `GAME_DESIGN` 8 m/s accumulation. STATUS records read-only LongCat `8c19992d` assessing this.
  - The DriveLab wall-publication seam (`src/laboratory/drive_lab.gd` `publish_wall_event` and its lab) implements and tests the policy. Later, the race coordinator does the same. The producer should stay a pure per-witness mapper.
  - The candidate README correctly lists "sustained-contact policy" as later work.

## Capability limits

- My sweep uses one straight box wall, the lab tuning and config, and the flat support plane. I did not test wall ends (convex edges), tilted walls, car-car contact, or other hull sizes and tolerances.
- I did not query hosted CI, and the workflow does not run this lab in any case.
- I did not modify candidate source, Git or assets. The probe is reviewer-only code under `../logs/probe/`.
- No helpers or other reviewers were consulted.
- This review does not claim full M1.8, M1 or rights clearance.

## Classification summary

| Item | Status |
| --- | --- |
| Exact post equality, adapter round trip, no false refusal | Verified pass |
| Severity, post, point, normal, imparted motion from committed source | Verified pass |
| Local normal frame and FRONT/REAR/LEFT/RIGHT sign mapping | Verified pass |
| Old-versus-new discrimination by the new negative cases | Verified (frame case is a guard only) |
| 0.01 near-tie margin justified by physical noise | **Fails**: 10% of real vertex contacts exceed it, with flips and high-speed mislabels |
| Physical corner regression coverage | Partial: heading 0 only |
| Sustained, continuing and zero-delta policy | Open integration issue (coordinator policy, DriveLab seam) |

Report path: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator/m1-corner-review-408d619/opus/report.md`
