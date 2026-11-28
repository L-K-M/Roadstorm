# Independent recheck: corrected M2 arc sampler, M1 hairpin path and OPEN-road frame, candidate 6f03243

- Date: 2026-11-28
- Reviewer: Claude Opus 5.5 through the Pi harness, Venice provider route (`PI_PROVIDER=venice`, `PI_MODEL=claude-opus-5-5`, reasoning `medium`). Venice forwards requests to a third-party host.
- Candidate: `6f032431133cb44fe6702291b35b38e79505e902`. Prior pair: `624f05385fddfc1872a302d925f29d8e9214eb40`, plus the tracked decision `docs/evidence/m2-arc-hairpin-checkpoint-624-decision-20261128.md`.
- Independence:
  - I did not read the concurrently assigned Sol report and spawned no agents.
  - I made no tracked edits, Git mutations, branches, worktrees or clones.
  - I read the archived prior Opus and Sol 624f053 reports and the decision, which the task permits.

## Verdicts

| Scope | Verdict |
| --- | --- |
| `src/course/road_arc_sampler.gd` + `tools/road_sampling_lab/**` | **changes required** (F1) |
| `tools/calibration_hairpin_path_lab/**` | **pass** (scoped; one low optional item, F3) |
| `src/course/road_transport_frame.gd` + `tools/road_frame_lab/**` | **pass** (scoped, OPEN-only component; F2 blocks practical use) |

- Nothing here closes whole M1, M1.7, M2 or M2.1.
- The source parser's mantissa-decoder defect from the separate exact-f199 recheck is OPEN under another worker. M2 source acceptance is not claimed.
- The frame pass covers no residual-roll closure, closed loops, mesh, collision, course acceptance or physical handling.
- Sweeper, baker, reward-C and wall-policy scopes were not reviewed.

## Archive integrity and exact source state

- `shasum -a 256 source.tar` = `f6dc76e0451a089c68de30dfb906c10e93c74b10707b4b5a59a5c33f3eabfe9c`, which matches `source.tar.sha256`.
- `source-sha.txt` names the candidate. `git get-tar-commit-id < source.tar` (read-only) returned `6f032431133cb44fe6702291b35b38e79505e902`.
- Tree comparisons, both run with `diff -r` and both identical:
  - `source.tar` extracted to scratch, against `source/`.
  - A read-only `git archive 6f03243…` from the shared repository, against `source/`.
- All 16 `scope.paths` entries exist (8128 lines in total).
- `git log 624f053..6f03243` lists five commits: 23d0aaa (review records), f199089 (parser, out of scope), 5d762f8 (frame), 54039e4 (hairpin), 6f03243 (arc).
- The test build `private/build` was a byte copy of `source/`. After the runs it differs only in Godot import artifacts (`.godot/`, `*.uid`) and my `review_probes/`. Sampler and frame file hashes matched `source/`.

## Inspected lines

- `src/course/road_arc_sampler.gd`:
  - The complete 624f053→6f03243 diff: header, bracket constants, global-advance refusal, recursive acceptance, `_bezier_interval_length_bounds`, slack.
  - Read in full at lines 330–630, 730–905, 996–1050, 1050–1330 and 1490–1650.
  - Lines 1–330, 630–730 and 1330–1490 are unchanged since 624f053. I reviewed them then and only skimmed them now.
- `tools/road_sampling_lab/`:
  - README lines 108–160 and 262–276, plus its diff.
  - `road_sampling_checks.gd` lines 129–967, including the new `conservative_bracket_regressions` case and its helpers.
- `tools/calibration_hairpin_path_lab/`:
  - `calibration_hairpin_path_source.gd`: all 1069 lines.
  - `calibration_hairpin_path_checks.gd`: lines 1–40, the corrected circle comment. The rest was exercised through the validator only.
- `src/course/road_transport_frame.gd`: all 963 lines.
- `tools/road_frame_lab/`: README lines 1–~170 and all four fixtures. `road_frame_checks.gd` and `run_validation.sh` were exercised but not read line by line.
- Context:
  - `src/laboratory/handling_lab_builder.gd:201–208`, the bank convention.
  - `fixtures/handling/hairpin.json`.
  - `docs/GAME_DESIGN.md:133–138`, course lengths of about 3.5–4.3 km.

## Commands actually run

Every engine process ran from `private/build` with private HOME, TMPDIR and XDG directories. Each was wrapped as `lockf -k -t 600 <shared godot-test.lock> timeout <T> <pinned Godot>`, through the wrapper `private/g.sh`. The packet's git-dependent `run_validation.sh` runners were not used.

| Command | Result |
| --- | --- |
| `Godot --version` | `4.7.2.stable.official.ed1daf0bf` |
| `--headless --path build --import` | rc 0 |
| `validate_road_sampling_lab.gd` | rc 0, **8 cases / 325 checks / 0 failed**, no ERROR/WARNING lines |
| `validate_calibration_hairpin_path_lab.gd` | rc 0, **9 cases / 515 checks / 0 failed**, no ERROR/WARNING lines |
| `validate_road_frame_lab.gd` | rc 0, **7 cases / 1773 checks / 0 failed**, no ERROR/WARNING lines |
| The three `failure_probe.gd` files | each rc **3**, `pass:false`, 1 of 2 checks failed |
| `review_probes/sampler_probe.gd` (mine) | rc 0. Three attempts failed on unsupported GDScript `%g`/`%e` formats; parse errors, no results. |
| `review_probes/threshold_probe.gd` (mine) | rc 0 |
| `review_probes/hairpin_probe.gd` (mine) | rc 0 |
| `review_probes/frame_probe.gd` (mine, run twice after adding a bank-angle check) | rc 0 |
| `python3 private/replica.py 40` | Replica of the sampler's Simpson and bracket algorithm, with float32-emulated or float64 vectors |

These runs reproduce the coordinator's counts and rc 3 exits on exact 6f03243. I did not rebuild the coordinator's earlier overlays on 54039e4, 5d762f8 or f199089.

## Ranked findings

### F1. High, implementation defect (arc sampler): the conservative bracket is computed in float32 and refuses ordinary road spans

`_bezier_interval_length_bounds` (lines 996–1045) evaluates positions and derivatives with Godot `Vector3`. In this official build that is float32: `Vector3(0.1,0,0).x == 0.1` printed `false` (0.10000000149011612). Two acceptance rules then fail against that noise:

- **Slack too small:** lines 846–862 require the bracket and the extrapolated Simpson value to agree within `ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF = 1e-12 × length`. That is about five orders of magnitude below float32 rounding.
- **Tolerance shrinks below the noise floor:** the local tolerance halves at every depth (lines 896–903), while the float32 bracket noise per leaf stays roughly constant. Subdivision therefore cannot converge once a leaf needs a few levels.

Pinned-engine counterexamples from the actual sampler at default options. Each is a single valid `road_source.v1` span (or the lab fixture as noted).

| Span | Result |
| --- | --- |
| Opus `road1` (the lab's own regression span) at the origin | ok, 147.905653572 m |
| Same span translated by +100 m in x | **refused `table_inconsistent`**, "geometric arc-length bracket is inverted beyond roundoff" (lower 0.137390704825521 > upper 0.137390704359859 at depth 10) |
| Same span translated by +100 m in x and −100 m in z, or by 150–100000 m | **refused `subdivision_cap_exceeded`** at depth 20. Typical diagnostic: extrapolated 1.342e-4 m, float32 bracket [1.635e-4, 1.635e-4], local tolerance 9.5e-10 m |
| `road2` and `hook` translated by 1000–100000 m | all **refused `subdivision_cap_exceeded`** |
| Straight at the origin, P0=(0,0,0), P3=(100.1,0,−0.3), handles at 1/3 and 2/3 | **refused `table_inconsistent`** at depth 0 (lower 100.100448608398 > upper 100.100448131561) |
| Straight to (37.3, 4.1, −61.7) at the origin | **refused `table_inconsistent`** |
| Straights to (60,0,0), (0,0,−60), (3,0,−4), (0,7,−60) | ok, because their values are exactly representable |
| 150 random gentle road-like spans near the origin (chord 30–200 m, handles 0.25–0.4 of the chord, ±0.6 rad) | 134 ok, **16 refused** (15 cap, 1 inconsistent) |
| The same family 2 km from the origin | 6 ok, **144 refused** |
| 150 random aggressive spans near the origin | 53 ok, **97 refused** |

**Root cause.** In `replica.py`, the same algorithm with float64 vector arithmetic refused **0 of 40** spans in each family at 0 m and at 1 km. Emulated float32 arithmetic reproduced the refusals: 4/40, 32/40, 26/40 and 40/40.

**Impact:**

- The design's courses are about 3.5–4.3 km, so typical world coordinates are hundreds of metres to kilometres. The corrected sampler, and with it the frame builder, cannot build tables for ordinary course geometry.
- The failure is closed: no wrong table is emitted. It is still a material functional regression from 624f053, which accepted these spans.
- The code comment and the README treat an inverted bracket beyond 1e-12 as an inconsistent derived state. That is false under float32: a plain straight hits it.

**Not found:**

- No accepted table understated its error. Across every accepted probe span, |actual error against a float64 Gauss–Legendre reference| ≤ reported estimate.
- The largest actual length error was 3.8e-5 m.
- The largest error of a nominal station against the float64 arc length at `span_t` was 3.8e-5 m.

**Fix direction:**

- Evaluate the bracket, and preferably the speed integrand, in float64 scalars from the control-point components, or at least relative to a local leaf origin. Otherwise the slack must be derived from float32 epsilon times the coordinate magnitude, which weakens the guarantee by that amount.
- Do not let the per-leaf acceptance tolerance fall below the achievable noise floor without a structured, explained refusal.
- Add regressions:
  - `road1`, `road2` and `hook` translated by ±1–5 km.
  - Non-dyadic diagonal straights.
  - A seeded random road-like sweep with zero false refusals and error ≤ reported.

**Missing evidence:** every lab fixture and regression uses near-origin, mostly dyadic coordinates. That is why the suite passes.

### F2. Medium, dependency (frame): practical frame building is blocked by F1

`RoadTransportFrame` consumes only `RoadArcSampler.Table`. Every F1 refusal therefore prevents a frame table. This is not a defect in the frame component. It means the frame pass is not evidence for any non-origin course.

### F3. Low, optional improvement (hairpin): duplicate `gate_id` and `run_id` silently shadow earlier entries

`calibration_hairpin_path_source.gd:408–413` and `462–470` key gates and runs by id, so the last entry wins.

- A wrong `corner_entry` gate (segment 2, arc length 77) inserted **before** the real one: `build()` returned `ok=true`.
- A `drift_entry` run with velocity 44 inserted before the real one: `ok=true`.
- The same bad gate appended **after** the real one was refused.

The live fixture has unique ids, so current output is correct. Refusing duplicate ids would remove the ambiguity about which entry is authoritative.

### F4. Low, optional nits (arc)

- `road_arc_sampler.gd:437`: the `"section_id"` dictionary entry in the new refusal is mis-indented. Cosmetic.
- Residual of the global-advance fix: the `total_length <= span_start` check catches a span that collapses completely, but not partial station-resolution loss after a huge prefix. That is irrelevant at course scale, where ulp(4 km) is about 1e-12 m. Sol's 2^53 regression is correctly refused, and its error text names the global station.

## Rechecks of prior findings

- **Prior Opus F1, Simpson underestimation: fixed for the reported cases. The fix introduces F1 above.**
  - **`road1`:** 147.905653572 m, error −1.53e-6 m against a float64 reference on the float32 control points (−4.9e-6 m against the authored float64 points). Reported 6.9e-4 m, 12 leaves, depth 4.
  - **`hook`, spacing 5:** 39.246615444 m, error +4.8e-7 m, reported 4.7e-4 m. The former `inversion_failed` refusal at spacing 5 is gone.
  - **`road2`:** error 2.6e-7 m.
  - **Sol quadratic:** 3.108784705 m against exact 3.1086978942948535 m, a difference of **8.681e-5 m**, within the reported 5.73e-4 m bound. The difference matches the coordinator's 0.00008681 m. The near-end spacing of 3.05 m also passes.
  - **Theory:** in exact arithmetic the bound is mathematically sound. The chord sum is a lower bound. The control polygon of the reparameterised subsegment (Q1 = B(u) + h·B′(u)/3, Q2 = B(v) − h·B′(v)/3) is an upper bound.
- **Sol global station collapse:** fixed (refused `table_inconsistent`, regression present).
- **Cap refusals:** the depth, node and output caps remain structured refusals, and the lab covers them. The cap diagnostic now carries the bracket fields. Under F1 the depth cap is the common symptom.
- **Fixed-panel inversion and wrong nominal stations:**
  - No new defect found. Across all accepted probe spans, nominal station errors were ≤ 3.8e-5 m.
  - On the named spans, inversion residuals were ≤ 4.4e-6 m and inversion estimates ≤ 6e-7 m.
  - The inversion error is documented as not independently bounded (README lines 128–132). That is the separate, documented limit, not a new defect.
- **Prior Opus F2, hairpin NaN/missing scalars: fixed.** `_required_scalar`, `_required_close`, `_required_pair_close` and `_required_index` check presence, numeric type and finiteness, and compare in the fail-closed direction. My probe refused every case:
  - **Fixture:** a string `grip_entry` velocity, a missing `grip_entry` velocity, and `grip_entry` velocity 40; a missing fixture `radius_m`.
  - **Bay:** NaN bay width, INF bay length and a missing bay yaw.
  - **Section records:** missing or NaN section `start_s_m`, `end_s_m`, `length_m` and `width_m`.
- **Sol tag corruption: fixed, with two-sided joins preserved.**
  - **Refused:** interior sample 1 retagged exit/gravel, which Sol reproduced; surface-only corruption; an interior arc sample tagged approach; sample 29 tagged arc; the last sample tagged arc.
  - **Refused at joins:** the first join copy tagged arc, the second tagged approach, the pair swapped, and the exit-join second copy tagged arc.
  - **Refused, whole section:** exit section and samples consistently changed to gravel ("section 2 surface changed").
  - **Preserved:** the baseline stream (158 raw, 156 unique, joins at 31 and 127) passes.
- **Width and bank smoothness (low): open plan item, unchanged.** Width and bank are still linear in t and C0 at knots. README line 113 documents this and claims nothing smoother. It remains an M2.1 geometry-policy decision.
- **Vanishing final interval (low): not addressed.** `_make_uniform_stations` (1493–1503) is unchanged and can still emit a final interval of about 1e-14 m. It is still undocumented. This is optional, and relevant to later mesh baking.
- **Grade semantics (low): partly addressed.** The README states grade is the tangent's y component (dy/ds). It does not warn that the design's percentage grade is rise over run. Optional.
- **Hairpin circle comment (low): fixed.** `calibration_hairpin_path_checks.gd:16–21` now says "outside the ideal circle … +2.73 mm".

## Frame component checks (pinned engine, my probes)

- **Orthonormality and handedness:**
  - On a twisted, climbing 3D S-bend with bank between −8° and +12°: max |dot| 6e-8, |det−1| 2.4e-7, |right×forward − up| 1.9e-7.
- **Transport against an independent RMF:**
  - **Method:** compared with an independent float64 double-reflection rotation-minimizing frame (Wang et al.) after removing the authored bank.
  - **Agreement:** maximum roll difference 0.080°, 0.0070° and 0.00040° at spacings 8, 2 and 0.5 m.
  - **Convergence:** about second order, and roll between spacings converges the same way. This supports genuine minimal-rotation transport, not a world-up rebuild.
- **Bank:**
  - **Angle:** the measured rotation of the banked right vector about forward matched each sample's `bank_deg` within 4.5e-6°.
  - **Sign:** positive bank tilts up toward road right and lowers the right edge. This matches the `handling_lab_builder` `rotated(tangent, angle)` convention.
  - **No accumulation:** a mid-course +25° bank pulse left the final frame bit-identical to the zero-bank build (Δ = 0.0).
  - **Large values:** a 3630° bank builds.
- **Seed:**
  - A tangent of exactly +Y seeds right = +X, up = +Z. A tangent of −Y seeds right = +X.
  - Both transport to forward −Z, right +X, up +Y with no flip.
- **Reversal:**
  - A U-turn shorter than the spacing (dot −1.0) is refused as `reversing_tangent` with a diagnostic.
  - A turn with dot about −0.9999989 is also refused, as documented.
  - The same U-turn at 1 m spacing builds.
- **Closed loop:** a closed sampler table is refused as `closed_loop_unsupported`.
- **Metadata:** `s`, position, width, bank, grade, `span_index`, `span_t`, section, surface and role were copied with 0 mismatches over 66 frames.
- **Copy safety:** mutating `frames` and `frame(i)` copies did not alter the stored table.
- **Not examined:**
  - The frame does not cross-check sample section/surface against `span_tables`; it treats them as opaque, as documented.
  - A caller can construct a `Table` through the public `Table.make`.

## Capability limits and missing evidence

- I did not run the packet's `run_validation.sh` runners or observe hosted CI. The results come from one host and one pinned engine.
- The float32 replica in Python approximates Godot's float32 operations. The headline counterexamples come from the actual pinned-engine sampler.
- Not reproduced: coordinator overlays on 54039e4, 5d762f8 and f199089.
- I performed no visual, audio, hardware, performance, gameplay or rights evaluation and approve none.

## Scratch

All scratch is under `private/`: `build/` with `review_probes/`, `logs/` (84 KB), `g.sh`, `replica.py` and `hairpin_src.diff`. The temporary `tarx/` and `gitx/` comparison trees were removed after verification. Nothing was written outside this packet.
