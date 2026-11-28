# M1.8 wall-region corner-band correction recheck: Opus 5.5 independent review

## Identity and scope

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, via Claude Code. Date 2026-11-28.
- Candidate: `4198a3891cdd83a652555b4ec73fd3a29f5acc54`. Prior scoped candidate: `408d619`.
- Scope: `../../scope.patch`, which changes `src/simulation/wall_impact_producer.gd`, `tools/wall_impact_lab/README.md` and `tools/wall_impact_lab/wall_impact_lab_driver.gd`. I also read the adapter witness contract in `src/simulation/motor_body_adapter.gd`.
- Source identity:
  - `diff -rq ../source build -x work` returns nothing.
  - The producer and driver SHA-256 values (`1148d8eb…`, `b0a68f75…`) match the coordinator's `source-hashes.txt` for the frozen copy.
- I did not consult the other current reviewer and did not delegate. I made no source, asset or Git changes and published nothing. I wrote only `logs/` and this report.

## Verdict: **pass** for the bounded producer and lab slice

The sweep below is my own.

- **Default hull contract** (the laboratory's 1.8 × 1.0 × 3.8 m hull, flat straight box wall, pinned Jolt):
  - The corner band, quadrant-sign check, collision-frame normal and diagonal fallback publish the face named by the unambiguous response normal for every one of **38,034** real flat-wall witnesses across ten sweep variants (0 disagreements).
  - Every remaining label change follows the normal crossing the 45° diagonal as the car yaws. None of them is solver noise.
- **What I do not mark complete:** full M1.8, M1, sustained-contact policy, car-car production, rights or release.
- **Not verified (outside the scope):** the remaining findings are non-blocking test-quality gaps, plus one piece of evidence about wall ends.

## Files inspected

- `src/simulation/wall_impact_producer.gd` (all of it, in particular `:39-78`, `:170-205` and `:252-304`)
- `src/simulation/motor_body_adapter.gd`:
  - `:112-120` and `:184` (orientation tolerance and its cap)
  - `:202-262` (`Config.is_valid`)
  - `:470-510` (collision-time transform)
  - `:540-700` (orientation probe, witness selection, response and result fields)
- `tools/wall_impact_lab/wall_impact_lab_driver.gd`:
  - the near-tie case at `:875-1126`
  - the nonzero-heading Jolt case at `:1616-1765`
  - helpers and constants at `:50-62`
- `tools/wall_impact_lab/README.md`, `run_wall_impact_lab.sh`, `wall_impact_lab_checks.gd:101-114`, and `tools/body_lab/body_lab_world.gd` (hull built from `config.hull_size_m`)
- `review/implementation/m1-wall-producer-opus-5-5-408d619.md` and `m1-wall-producer-gpt-6-2-sol-408d619.md`
- Coordinator logs `wall-corner-devin-frozen-2938079/run.log`, `old-control/runner.log` and `source-hashes.txt`

## Commands and results

The setup for every Godot run below:

- Pinned editor: `toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot` (`4.7.2.stable.official.ed1daf0bf`).
- Private `HOME`, `TMPDIR` and `XDG_*` under `logs/`.
- The shared lock: `lockf -k -w -t 600 work/agents/coordinator/godot-test.lock`.
- A `timeout` bound on every process.

### 1. Candidate lab suite (my private build)

Command:

```
run_wall_impact_lab.sh --project build --godot <pin> --lock <shared lock> --timeout 240 --outer-timeout 900 --log logs/lab.log
```

Result:

- rc=0, **14 cases, 1094 checks, 0 failed**. The deliberate failure probe exited rc=3. Logs: `logs/lab-runner.log` and `logs/lab.log`.
- This reproduces the coordinator's frozen run. The nonzero-heading measurements match the README:
  - `v20_h0.900_s0_t0`: 33 witnesses, all LEFT, 27 of them outside the old 0.01 band.
  - `v35_h1.100_s1_t0`: first hit at tick 4, 26.346 m/s, LEFT. The old point rule says FRONT, with diff -0.0101.

### 2. Old-producer discrimination (coordinator evidence, read only)

- `old-control/runner.log` shows 33 failures:
  - 30 physical: 26 + 1 per-tick checks and 2 aggregates for the two nonzero-heading scenarios, plus one further tick.
  - 3 synthetic: `wide_solver_inset` and both `malformed_sign` checks.
- The new nonzero-heading Jolt case therefore discriminates the 408d619 rule.
- The rotated-frame check `world_axes_would_name_side` is a fixture property and passes on any producer. Discrimination comes from `near_tie.rotated_frame.front` (see 3).

### 3. Mutation run (mine)

Method: each run perturbed a staged copy of the producer, ran the validator, then restored the copy. Logs and diffs are in `logs/mut/`.

| Mutation | Validator result |
| --- | --- |
| unmodified control | 0/1094 failed |
| normal read in world axes (no inverse) | 37 failed (rotated_frame.front + 36 physical) |
| quadrant sign check removed | 2 failed (malformed_sign) |
| band 0.012 / 0.011 / 0.0105 / 0.008 | 33 / 34 / 37 / 42 failed |
| **band 0.015** | **0 failed** |
| **band 0.5** | **0 failed** |
| band 1.8, 2.0, or normal used everywhere | 1 failed (`region.lateral_wins…`) |
| **axis margin 1e-3 replaced by 0** | **0 failed** |

The frame transform and sign check are pinned by tests. The band is pinned only to the interval (0.012, 1.8), and the axis-margin value is not pinned at all. See findings 1 and 2.

### 4. Broad pinned-Jolt sweep adapted to the new producer (mine, reviewer-only code)

- **Probe:** `logs/probe/opus_corner_probe2.gd`. It is the prior 408d619 probe with environment-driven variants, run from a staged copy (since deleted) after `--import` (rc=0). Every run reached `OPUS_PROBE_DONE` with rc=0.
- **Analysis:** `python3 -I logs/probe/analyze2.py <log> 0.025` and `bandsim.py`.
- **Columns in the table below:**
  - **disagree**: the published region differs from the face named by an unambiguous normal.
  - **noise flips**: the region changes while the non-diagonal normal face stays constant.
  - **inset max**: the maximum of `half − |local|` in x and in z.

| Variant | Witnesses | Max inset x / z (m) | Outside band | Disagree | Noise flips | Quadrants |
| --- | ---: | --- | ---: | ---: | ---: | --- |
| default grid (same 180 scenarios as 408d619) | 3672 | 0.01576 / 0.01384 | 0 | **0** (408d619: 364) | **0** (408d619: 19) | F, L |
| fine headings 0.60-1.47 rad, step 0.03 (504 scenarios) | 10568 | 0.01580 / 0.01387 | 0 | 0 | 0 | F, L |
| mirrored headings | 3672 | 0.01512 / 0.01384 | 0 | 0 | 0 | F, R |
| rear-first (heading + π) | 1768 | 0.01497 / 0.01384 | 0 | 0 | 0 | Rear, R |
| rear-first mirrored | 1769 | 0.01576 / 0.01384 | 0 | 0 | 0 | Rear, L |
| tolerance 0.0 (1793 ticks `REFUSED_ORIENTATION`) | 1907 | 0.01452 / 0.01286 | 0 | 0 | 0 | F, L |
| tolerance 0.05 | 3671 | 0.01602 / 0.01384 | 0 | 0 | 0 | F, L |
| tolerance 0.10 (config cap) | 3671 | 0.01602 / 0.01384 | 0 | 0 | 0 | F, L |
| hull 2.2 × 1.0 × 4.6 | 3651 | 0.01582 / 0.01393 | 0 | 0 | 0 | F, L |
| hull 1.4 × 1.0 × 3.0 | 3685 | 0.01517 / 0.01387 | 0 | 0 | 0 | F, L |

Further results from the sweep:

- **Refusals and point–quadrant consistency:** 0 refusals in every variant. No published region is inconsistent with the point's quadrant.
- **The 26.35 m/s `v35_h1.100_s1_t0` first hit** is now LEFT. `v20_h0.900_s0_t0` (408d619: `lfff…llflffflfl`) is now constant LEFT.
- **All remaining label changes are geometric** (10 of 170 default scenarios, 26 of 504 fine):
  - They occur where the yaw passes about 0.785 rad and the local normal crosses the diagonal. For example, `v8_h0.500_s1_t0` goes from n=(0.684, 0.730) FRONT to (0.718, 0.696) LEFT.
  - Diagonal normals within 1e-3 fall back to the point rule: 188 default witnesses, every one FRONT or REAR as documented. With these hull proportions, equal metre insets normalize to a longitudinal value above the lateral one, so the fallback is stable.
- **Band headroom:** replaying the recorded witnesses through other band widths (`bandsim.py`, all variants):

  | Band (m) | Mislabelled witnesses | Max severity (m/s) |
  | ---: | ---: | ---: |
  | 0.012 | 7,862 | 30.6 |
  | 0.014 | 395 | |
  | 0.015 | 24 | |
  | 0.016 | 2 | |
  | 0.018, 0.020, 0.025 | 0 | |

  The 0.025 m band therefore has about 9 mm (36 %) of headroom over the worst measured inset, 0.01602 m.
- **Correction to my prior 408d619 report:** the inset is not driven by `orientation_contact_tolerance_m`. It is about 0.0145 m at tolerance 0 and 0.0160 m at the 0.1 m cap, and is essentially independent of hull size. It behaves as fixed Jolt contact slop. The producer comment at `wall_impact_producer.gd:65-74` attributes it partly to the 0.02 m tolerance. That is harmless but not supported by these measurements.

### 5. Wall-end geometry (mine, explicitly outside the calibrated contract)

These runs use a 0.6 m-wide wall, so the car can strike its vertical convex edge.

- **Wall centred** (`OPUS_WALLW=0.6`): 1617 witnesses, 45 near-vertex points outside the band, and **2 disagreements**.
  - In `v20_h0.785_s-1_t1` tick 30 and `…_t0` tick 27, the wall edge slides along the left face. The normal is (0.914, 0.406), LEFT-dominant. The point is inset (0.0158, 0.0288) m, so it is 2.9 cm behind the nose and outside the z band.
  - These are **published FRONT** at 6.40 m/s and 5.38 m/s. In both scenarios the preceding ticks are LEFT with n = (1, 0), and the following tick is a genuine FRONT vertex contact.
- **Offset car** (`OPUS_X=-0.8`): 1925 witnesses, 0 disagreements.
- I do not treat this as a defect in this slice. The README (`:51-57`) and the producer comment (`:65-74`) explicitly limit the band to the flat straight box wall. See finding 3.

### 6. Hosted CI (read only, `gh run list` / `gh run view`)

- Run `46102918939` on `4198a38` completed successfully: import/validate/test, contract suites, inventory and export preparation.
- `.github/workflows` and `tools/ci/ci.sh` do not reference the wall lab (grep returns nothing). Hosted CI therefore does not exercise this behavior.

## Assessment of the review questions

- **0.025 m evidence against the original sweep:**
  - Supported for the default contract. The worst inset is 0.0160 m across 38,034 witnesses, the pinned lower guard sits at about 0.012-0.015 m, and the band has 9 mm of headroom.
  - It is robust within the tested hull sizes (1.4-2.2 m wide) and the full valid tolerance range 0-0.1 m.
- **Quadrant sign:**
  - The logic is correct (`:280-289`). A front quadrant needs +Z, rear −Z, left +X and right −X.
  - Sign-inconsistent normals fall through to the point rule rather than publishing the opposite face. This is pinned by `malformed_sign`.
  - No real witness hit this path.
- **Rotated collision frame:** `basis.inverse()` of the same collision-time transform (`:181`) is correct for the adapter's orthonormal yaw basis. The 1.2 rad fixture now discriminates: the world-axis mutation fails it.
- **Fallback:** the diagonal and sign-inconsistent fallbacks are deterministic and documented, and they match the observed FRONT/REAR resolution.
- **Normal axis margin:** 1e-3 is reasonable. 188 real witnesses fell inside it, all at a genuine 45° geometry, but no test pins its value (finding 2).
- **True face against corner:**
  - Face-centre contacts stay point-classified (band 1.8 m would be needed to capture them).
  - All flat-wall witnesses were vertex contacts, so the band never had to separate a true face contact from a corner on that geometry. The wall-end evidence in section 5 shows where it would.
- **Physical tests and the old control:** they discriminate the 408d619 rule (30 physical failures) and the world-axis mutation (36 physical failures). They do not discriminate a band narrowed to 0.015 (finding 1).

## Findings, ranked (all non-blocking for this slice)

### 1. Medium (test quality): the lab does not pin the band at the measured worst inset

- **Where:** `tools/wall_impact_lab/wall_impact_lab_driver.gd:982` (`wide_point` is inset (0.0108, 0.0036) m) and the nonzero-heading Jolt scenarios at `:1616` and following.
- **Evidence:**
  - Mutating `REGION_CORNER_BAND_M` (`wall_impact_producer.gd:74`) to 0.015 passes all 1094 checks.
  - Replaying the sweep at 0.015 m mislabels 24 real witnesses against the normal.
  - The producer comment and README cite 0.0158 / 0.0138 m as the covered inset, but nothing asserts it.
- **Fix:** add a synthetic near-tie fixture at the measured extreme, for example inset (0.0160, 0.0139) m in each quadrant with a face-consistent normal, expecting the normal's face. Optionally add a physical scenario whose inset exceeds 0.015 m (for example from the fine grid; `logs/probe-fine.log` contains them).

### 2. Low (test quality): no upper bracket for the band and no boundary fixture for the axis margin

- **Where:** the producer at `:74` and `:78`, and the driver's `unambiguous` fixtures at `:1053-1080` and the diagonal fixture at `:1034`.
- **Evidence:**
  - Band 0.5 m passes every check. The only upper guard is a face-centre point that needs a band of at least 1.8 m to capture.
  - Margin 0 passes because the diagonal fixture has an exactly zero component difference.
  - This repeats prior Sol finding 2 (bracket the boundary), which remains open.
- **Fix:**
  - Add a point just outside the band, for example inset (0.03, 0.005) m with a contradicting normal, expecting the point rule.
  - Add a normal with a component difference of about 5e-4 at an in-band point, expecting the fallback.

### 3. Low (forward risk, documented): wall-end contacts mislabel just outside the band

- **Where:** classification design at `wall_impact_producer.gd:277-304`; limitation recorded at README `:51-57`.
- **Evidence (section 5):**
  - A convex 0.6 m wall edge sliding along the left face publishes FRONT for 2 of 1617 witnesses, at 6.40 and 5.38 m/s.
  - In each case the normal is clearly LEFT and the point sits 2.9 cm behind the nose.
  - Under the alternative the prior review offered (normal first, point only for diagonals), these would be LEFT. The current `unambiguous` fixtures intentionally forbid that alternative.
- **Action:** none for this slice. Before track geometry with wall ends, barriers or posts feeds M5.9 bumper selection, the owner must either measure and calibrate that geometry or revisit "point beats normal outside the band". This should be recorded as an M1.8 / M5.9 integration item.

### 4. Informational: the producer comment's causal attribution

`wall_impact_producer.gd:65-74` ties the band to the 0.02 m orientation tolerance. The measured inset is independent of that tolerance (section 4). Suggest wording such as "pinned Jolt vertex slop, measured independent of `orientation_contact_tolerance_m` in [0, 0.1]" when the file is next touched. The README's caution about other tolerances is conservative and need not change.

## Limitations

- **Geometry tested:** macOS headless pinned Godot/Jolt only. One flat support plane and box walls: wide straight walls plus one narrow-wall variant. Hull heights stayed at 1.0 m. Lab tuning and the default motor only.
- **Untested:** tilted, curved or mesh walls, slopes, car-car contact, multiple simultaneous wall candidates, Linux and Windows.
- **Sweep code:** it is reviewer-only and runs through the real `MotorBodyAdapter.step` and `WallImpactProducer.produce`. The analysis classifies the normal face with the producer's own 1e-3 margin.
- **Mutations:** each perturbed only the staged producer, never `build/` or `../source`.
- **Sustained-contact policy is unchanged and still open:** one event per witness tick, with most events below 0.5 m/s. It remains later work, as the README states.
- **Not established here:** general physical authority, full M1.8 or M1 acceptance, rights, or release readiness.

## Artifacts

- `logs/lab-runner.log` and `logs/lab.log`: the candidate suite
- `logs/mut/*.log` and `*.diff`: the mutation runs
- `logs/probe/`: probe, entry, runners and analysis scripts
- `logs/probe-*.log`: sweep outputs
- The temporary probe stage has been deleted.

Report path: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator/m18-wall-corner-review-4198a38/opus/report.md`
