# Independent recheck: M2 arc sampler, M1 hairpin path and OPEN-road frame, candidate 9751e56

- **Date:** 2026-11-28
- **Reviewer:** Claude Opus 5.5 through the Pi harness.
  - Route: `PI_PROVIDER=venice`, `PI_MODEL=claude-opus-5-5`, reasoning `medium`.
  - Identity limit: Venice forwards requests to a third-party host. I can attest the harness selection from my environment, not the backend model revision.
- **Candidate:** `9751e567d3ebe6a60882e05ec9e84a346977b049`
- **Prior state:**
  - Exact-6f candidate: `6f032431133cb44fe6702291b35b38e79505e902`.
  - Decision: `docs/evidence/m2-arc-hairpin-frame-recheck-6f-decision-20261128.md`.
  - I read both archived 6f reports, Opus and Sol, from the 6f packet directory.
- **Independence:**
  - I did not read the concurrently assigned 975 Sol packet or report, and I spawned no agents.
  - I made no tracked edits, Git mutations, branches, worktrees or clones. The shared repository was used only for read-only `git log`/`git diff` between `6f03243` and `9751e56`.
  - I did not import the live checkout.
  - Everything I wrote is in this `report.md` and in `private/`.

## Verdicts

| Scope | Verdict |
| --- | --- |
| Arc sampler: `src/course/road_arc_sampler.gd` and `tools/road_sampling_lab/**` | **Pass**, scoped. Prior F1 and Sol's diagonal case are fixed and verified independently. Low items F1–F3 remain: two numeric-envelope documentation items and one cosmetic item. |
| Hairpin converter: `tools/calibration_hairpin_path_lab/**` | **Pass**, scoped. Prior F3 is fixed and Sol's near-join case is fixed. Low residual item F4. |
| OPEN frame: `src/course/road_transport_frame.gd` and `tools/road_frame_lab/**` | **Pass**, scoped to the OPEN-only component. The 6f dependency blocker (my former F2) is cleared. A translated non-dyadic multi-span course now builds through arc plus frame. |
| Closed-loop roll closure, mesh/collision bake, course acceptance, physical 18 m/s hairpin run | **Not verified.** Out of scope, with no evidence. |

- Nothing here accepts whole M1, M1.7, M2 or M2.1.
- I make no visual, audio, hardware, performance, gameplay or rights determination.
- The road-source parser commits in the same range (`cd4cdd4`, the mantissa window) were not reviewed.

## Archive integrity and exact source state

- `shasum -a 256 source.tar` = `c6ec0fd265f42259abdfea30ad6e427f3f77d69951df626943125644b30f6dea`. This matches `source.tar.sha256`.
- `source-sha.txt` = `9751e567d3ebe6a60882e05ec9e84a346977b049`. `git get-tar-commit-id < source.tar` (read-only, no repository) returned the same SHA.
- **Tree comparisons:**
  - `source.tar` extracted to `private/tmp/x`, then `diff -rq private/tmp/x source`: rc 0, identical. The scratch extraction was removed afterwards.
  - `diff -rq source private/build` before the engine runs: rc 0, identical.
  - After the runs, `private/build` differs only in Godot import artifacts (`.godot/`, generated `*.uid`) and my `review_probes/`.
  - The SHA-256 of `road_arc_sampler.gd`, `road_transport_frame.gd` and `calibration_hairpin_path_source.gd` is identical in `source/` and `private/build`.
- **Read-only `git log 6f03243..9751e56`:**
  - `8ffb0c5`: review records.
  - `cd4cdd4`: parser, out of scope.
  - `16f566f`: hairpin duplicate IDs and ownership.
  - `9751e56`: arc scalar precision.
- `git diff --stat 6f03243 9751e567 -- src/course/road_transport_frame.gd tools/road_frame_lab` is empty. The frame source is unchanged since 6f.

## Inspected paths and lines

- **`src/course/road_arc_sampler.gd` (1744 lines):**
  - The full `6f03243..9751e56` diff.
  - Read in full: 342–620 (build, global-advance refusal, caps), 622–1075 (degeneracy, recursive integration, acceptance, bracket, slack), 1250–1335 (`_evaluate_sample`), 1517–1606 (stations and sample validation), 1617–1735 (new scalar component helpers and `_speed`).
- **`tools/road_sampling_lab/`:**
  - README diff and lines 100–208.
  - `road_sampling_checks.gd` diff, including the new `translated_float64_regressions` case and its Gauss–Legendre reference helpers.
- **`tools/calibration_hairpin_path_lab/`:**
  - Diffs of `calibration_hairpin_path_source.gd` and README.
  - Source lines 333–430 and 480–503 (duplicate gate/run refusal), 558–770 (filter, join duplicate check), 1033–1083 (ownership).
  - The checks file was exercised through the validator only. I located `_case_tag_ownership_refusal` at line 992.
- **`src/course/road_transport_frame.gd`:** sample-validation region 466–710, read to confirm the frame consumes tangents, not position differences. The rest was reviewed at 6f and is unchanged.
- **`src/course/road_source.gd` 1423–1460 (`_read_vector`):** context only, to confirm that authored JSON coordinates are stored as float32 `Vector3`.
- **Context:**
  - Both 6f reports.
  - The 6f decision.
  - My 6f probes (`.../m2-arc-hairpin-frame-recheck-6f-20261128/opus/private/build/review_probes/`), read and partly reused.

## Commands actually run

- **Engine environment:** every engine process ran through `private/g.sh`. The wrapper sets:
  - `HOME=private/home`, `TMPDIR=private/tmp/`, and `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME` under `private/`.
  - `cd private/build`.
  - `lockf -k -t 900 <coordinator>/godot-test.lock timeout -k 10 <T> <pinned Godot> ...`.
- **Engine:** `.../toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`.
- **Runners not used:** the packet's git-dependent `run_validation.sh` runners. The validators were invoked directly.

| Command | Exact result |
| --- | --- |
| `Godot --version` | `4.7.2.stable.official.ed1daf0bf` |
| `--headless --path private/build --import` | rc 0. Single warning: "Detected another project.godot at res://tools/tick_probe", a benign nested project. |
| `--headless --fixed-fps 60 --path build --script res://tools/road_sampling_lab/validate_road_sampling_lab.gd -- --summary-out=…` | rc 0, **9 cases / 611 checks / 0 failed**, 0 ERROR/WARNING lines |
| same for `calibration_hairpin_path_lab/validate_calibration_hairpin_path_lab.gd` | rc 0, **10 cases / 540 checks / 0 failed**, 0 ERROR/WARNING lines |
| same for `road_frame_lab/validate_road_frame_lab.gd` | rc 0, **7 cases / 1773 checks / 0 failed**, 0 ERROR/WARNING lines |
| the three `failure_probe.gd` | each rc **3**, `pass:false`, 2 checks, 1 failed |
| `review_probes/arc_probe.gd --out=logs/arc_probe.jsonl` (mine) | rc 0, 847 tables or refusals written, 8.7 s |
| `python3 private/ref.py logs/arc_probe.jsonl` (mine, independent float64 reference) | see the arc evidence below |
| `review_probes/edge_probe.gd` (mine) | First run: rc 0 but two print lines hit GDScript's unsupported `%g` format, so those rows were unreadable. Fixed and re-ran: rc 0, no ERROR lines. |
| `python3 ref.py logs/edge_probe.jsonl` | 6 accepted spans checked; 0 understated |
| `review_probes/cusp_probe.gd` plus a Python check at 4096 and 32768 panels (mine) | rc 0 |
| `review_probes/hairpin_probe.gd` (mine; 6f cases plus new ones) | rc 0. Re-ran once (`hairpin_probe2`) with tighter overlap and gap values. |

### Coordinator claim, reproduced on the exact candidate

| Claim | Observed in `logs/road_sampling_lab.json` |
| --- | --- |
| 9 cases / 611 checks; failure probe rc 3 | Yes, both |
| All 40 seeded spans accepted | `seeded_normal_accepted_count` = 40 |
| Worst actual length error 3.33e-5 m | `seeded_normal_worst_actual_error_m` = 3.32772e-5 |
| Diagonal actual error about 7e-12 m | `sol_diagonal_actual_error_m` = 7.276e-12 |
| Diagonal reported bound 3.48e-8 m | `sol_diagonal_reported_error_m` = 3.4756e-8 |

- **Hairpin:** 10 cases / 540 checks and rc 3, reproduced.
- **Frame:** 1773 checks and rc 3, reproduced.

## Arc sampler evidence (independent)

**Method:**

- `arc_probe.gd` builds single-span tables at default options, except where noted, and writes the following to JSONL:
  - the float32 control points exposed by the parsed document;
  - length, reported error, depth and leaf count;
  - up to 65 sampled stations with `span_t` and positions.
- `ref.py` recomputes everything independently of the Godot code:
  - **Length:** composite 10-point Gauss–Legendre at 64 and 256 panels, summed with `math.fsum`.
  - **Station:** true arc length at each sample's `span_t`.
  - **Position:** the float64 Bezier point at `span_t`, compared with the emitted float32 `Vector3`.
  - **Authored length:** the length of the authored float64 control points, which isolates float32 storage quantisation.

**Named spans:**

- **Coverage:** road1, road2 and hook at offsets 0 m, 100 m, 1 km, 3 km, 5 km, 10 km, 20 km, 50 km, 100 km and 1000 km, in x and z. y is also offset, and is non-dyadic.
- **Result:** all 30 accepted. Depth 4/4/6 and leaf counts 12/13/28 are unchanged across every offset, so the method is translation-invariant.
- **Actual |error| against the float32 control points:**

| Span | Actual error | Reported |
| --- | --- | --- |
| road1 | 1.07e-7 m | 6.63e-4 m |
| road2 | 8.3e-9 m | 4.45e-4 m |
| hook | 7.96e-7 m | 4.45e-4 m |

- At 6f, the same spans refused from 100–150 m outward.

**Sol diagonal:**

| Case | Length | Actual error | Reported |
| --- | --- | --- | --- |
| Exact diagonal | 34755.712508881 m | 0 (Python), 7.3e-12 (lab) | 3.476e-8 m |
| Translated by (1234.567, 89.1, −4321.987) | — | 7.3e-12 m | — |
| Translated by (−30000.3, 0.7, 25000.1) | — | 0 | — |

**Non-dyadic straights:**

- Displacements (37.3, 4.1, −61.7), (100.1, 0, −0.3) and (0.013, 0, −0.017), at offsets 0, 2 km, 10 km and 100 km, all at 0.5 m spacing.
- All 12 accepted. Actual error ≤ 6e-13 m, except a 2 cm span at 100 km, which had 8.5e-6 m against a reported 1.85e-5 m.

**Seeded sweeps:** 800 spans with seed `975000+offset(+13)`.

- **Families:**
  - **Gentle:** chord 20–250 m, handles 0.25–0.4 of the chord, ±0.6 rad, grade ±12%.
  - **Aggressive:** handles 0.2–0.9 of the chord, ±2.4 rad, which includes loops.
- **Spacing and placement:** spacing 0.5–10 m; offsets 0, 2 km, 5 km and 20 km, with ±300 m scatter.

| Family@offset | Accepted | Worst actual error | Worst (error − reported) | Worst station error | Worst position error |
| --- | --- | --- | --- | --- | --- |
| gentle@0 | 100/100 | 1.56e-5 | −2.18e-4 | 1.56e-5 | 2.2e-5 |
| aggressive@0 | 100/100 | 1.26e-4 | −2.06e-4 | 1.54e-4 | 2.1e-5 |
| gentle@2 km | 100/100 | 7.40e-5 | −2.34e-4 | 7.40e-5 | 1.7e-4 |
| aggressive@2 km | 100/100 | 7.53e-5 | −2.86e-4 | 7.65e-5 | 1.7e-4 |
| gentle@5 km | 100/100 | 2.85e-4 | −1.91e-4 | 2.85e-4 | 3.4e-4 |
| aggressive@5 km | 100/100 | 6.25e-5 | −3.64e-4 | 6.25e-5 | 3.4e-4 |
| gentle@20 km | 100/100 | 2.34e-4 | −1.95e-4 | 2.34e-4 | 1.36e-3 |
| aggressive@20 km | 100/100 | 4.16e-5 | −2.83e-4 | 4.45e-5 | 1.37e-3 |

- **Totals:** 0 refusals, **0 understated** (actual > reported), 0 over the 1 mm tolerance.
- **Reference quality:** the reference's coarse/fine uncertainty is ≤ 7.6e-8 m on the hardest aggressive loops and ≤ 3e-14 m elsewhere. That is far below every observed margin.
- **Prior result:** the same families at 6f refused 16/150 at the origin and 144/150 at 2 km.

**Tight options at 3 km:**

| Option | Result |
| --- | --- |
| Tolerance 1e-6 m | Accepted at depth 9 with 393 leaves; actual 2.8e-14 m, reported 5.7e-7 m |
| Spacing 0.01 m | Accepted with 14,792 samples; station error ≤ 4e-6 m |

**Near-cusp margin**, `cusp_probe` and `edge_probe`:

- Span: P0=(0,0,0), P1=(100,0,0), P2=(0,0,−d), P3=(100,0,0), at offsets 0 and 1 km. The speed is near zero at t=0.5.

| d | Result | Actual error | Reported |
| --- | --- | --- | --- |
| 0.01 | Accepted, one leaf at depth 0 | 9.54e-4 m | 9.99e-4 m |
| 0.001 | Accepted | 9.85e-5 m | 1.00e-4 m |
| ≤ 1e-4 | **Refused `degenerate_derivative`** | — | — |

- With d = 0.01 the bound is tight but holds. The reference is stable to 32,768 panels.
- At 1 km, float32 storage turned d = 1e-5 into an exact cusp, which was also refused correctly.
- A separate near-cusp span at 5 km (`near_cusp@5km`) had actual error 9.32e-4 m against a reported 9.76e-4 m.

**Refusals, all structured and fail-closed:**

| Case | Result |
| --- | --- |
| Control differences above FLT_MAX (±3e38) | `nonfinite_derived_state` |
| Derivative component above FLT_MAX with control differences below it (0, 2e38, 2.5e38, 3e38) | `nonfinite_derived_state` |
| JSON 1e39 | parser refuses as not representable as a finite engine component |
| 3e30 m span at 1 m spacing | `sample_cap_exceeded` |
| 3e30 m span at 1e27 m spacing | `inversion_failed` (absolute inversion tolerance) |
| Translated road1 at depth 0 | `subdivision_cap_exceeded` |
| Translated road1 with node cap 2 | `table_node_cap_exceeded` |
| Translated road1 with output cap 2 | `sample_cap_exceeded` |
| Translated road1 at tolerance 1e-8, 1e-9 or 1e-12, and the same span at the origin at 1e-9 | `table_node_cap_exceeded`, a budget limit identical at the origin, not a precision false refusal |
| Exact cusp at 5 km | `degenerate_derivative` |

The lab's global-station collapse regression (a 2^53 m prefix followed by a 0.25 m span) is still present and passes.

**Source reasoning:**

- **Scalar evaluation:** `_bezier_*_components`, `_bezier_displacement_components` and `_components_length` (1620–1695) read float32 `Vector3` components into GDScript floats, which are float64.
  - Control-point differences of float32 values are exact in float64 for any realistic exponent gap.
  - The displacement uses the power-basis identity B(b)−B(a) = (b−a)[L + Q(a+b) + C(a²+ab+b²)] with difference coefficients. I verified the identity algebraically.
  - World translation therefore cannot enter any subtraction. This is the root-cause fix for prior F1.
- **Bracket:** the chord lower bound and the subdivided control-polygon upper bound are unchanged in meaning.
- **Error and slack:**
  - The reported leaf error is now distance + slack (869–874).
  - The slack is 1e-12 × max(lower, upper), with the old 1.0 floor removed (1069–1071). That is now well above double-precision noise for ordinary leaves.
- **Finite range:** `_speed` (1697–1714) refuses differences or derivative components beyond the float32 range. Positions are built in float64 and checked finite after conversion to `Vector3`, and tangents likewise.

**Finding: none at medium or higher severity for the arc sampler.**

## Hairpin evidence

Pinned engine, `hairpin_probe`, with `build()` or `_filter_join_duplicates` on the live builder stream.

**Prior Opus F3, duplicate IDs: fixed in both orders.**

| Case | Result |
| --- | --- |
| Wrong `corner_entry` gate (segment 2, arc 77) before the real one | refused `duplicate_id:corner_entry`. At 6f this returned `ok=true`. |
| The same gate appended after the real one | refused, same diagnostic |
| Drift run with velocity 44 before the real one | refused `duplicate_id:drift_entry`. At 6f this returned `ok=true`. |
| Drift run with velocity 44 after the real one | refused |
| Identical duplicate gate | refused |
| Identical duplicate `grip_entry` run | refused |
| Extra gate ID used twice | refused |
| Extra gate ID used once | accepted, which is permitted |
| Missing `gate_id` | refused (`start missing`) |

The source checks `has()` before the dictionary write (422–427, 497–503).

**Sol near-join tolerance: fixed.**

- With exact recorded intervals, sample 29 moved to 30 − δ and tagged `hairpin.arc` is refused, for δ = 5e-5, 1e-6 and 1e-9.
- Sample 32 moved to 30 + δ and tagged `hairpin.approach` is also refused.
- Control: the same moved stations keeping their correct tag pass, so the refusal comes from ownership.
- The genuine two-sided joins still pass:
  - Baseline: 158 raw, 156 unique, joins at 31 and 127.
  - Join-copy swap, retag and exit-join corruption are refused.

**Prior 6f cases re-run, all unchanged:**

- **Refused:** string, missing and 40 m/s `grip_entry` velocity; missing radius; NaN bay width; INF bay length; missing yaw; missing or NaN section start, end, length and width.
- **Refused:** interior, surface-only, last-sample and pre-join tag corruption; exit section and samples consistently retagged to gravel.

## Frame dependency evidence

- `edge_probe` built a five-knot, four-span open course at offsets 0, 3 km and 20 km and passed each table to `RoadTransportFrame.build_open_frame_table`.
- **Course:** non-dyadic coordinates, climbing and falling, banks −6.5° to +12°, length 608.99 m, 2 m spacing.
- **Result at each offset:**
  - Sampler OK, 306 samples, reported error 2.273e-3 m in total (per span ≤ 1 mm).
  - Frame OK with 306 frames.
  - max |pairwise dot| ≤ 8.9e-8, max |det − 1| = 2.4e-7, max |forward − sample tangent| = 8.4e-8.
- Bank angle and RMF agreement were verified in my 6f run and by the lab's 1773 checks. This run did not independently re-measure them. `bank_err_deg=0` in the log is vacuous, because the frame dict exposes no `unbanked_right` key.
- No closed loop, roll closure, mesh or collision behaviour was exercised.

## Ranked actionable findings

### F1. Low, documentation/plan (arc): the reported error excludes the change from authored JSON to stored float32 control points

`road_source.gd:1446` stores authored doubles in a float32 `Vector3`. The sampler's bound is honestly relative to the stored points; the README says "from the stored `Vector3` control-point components". The distance between authored and stored geometry is neither reported nor bounded.

| Coordinate magnitude | Measured \|L(authored) − L(stored)\| per span |
| --- | --- |
| ≤ 2 km | ≤ 2.4e-4 m |
| about 5 km | ≤ 5.4e-4 m |
| about 20 km | ≤ 1.8e-3 m (exceeds the 1 mm tolerance) |
| 100 km | up to 6.9e-3 m on a 2 cm span (geometry materially changed) |
| 1000 km | 2e-2 m |

- **Impact:** for the designed 3.5–4.3 km courses near the origin, the effect stays well under 1 mm per span. This is a declared-envelope gap, not a sampler defect.
- **Fix direction:** state the envelope in the README and table contract, for example "|coordinate| ≤ 8192 m keeps the float32 half-ulp ≤ 4.9e-4 m". Alternatively, have the source or a later validation gate refuse coordinates beyond the envelope.

### F2. Low, documentation/plan (arc): output positions are float32 and can collapse below the spacing resolution at large offsets

`_validate_samples` (1561–1603) checks finiteness and strictly increasing `s`, not spatial spacing. On a 10.47 m span at 2 mm spacing:

| Offset | Effect |
| --- | --- |
| 5 km | Interior position step/Δs ranges 0.77–1.09 |
| 20 km | 89 identical consecutive positions |
| 100 km | 3646 identical consecutive positions |

- At ordinary spacing (≥ 0.5 m) and ≤ 5 km, the distortion is ≤ about 0.1 %.
- The frame is unaffected, because it uses tangents.
- Sol raised this at 6f. It remains undocumented as an envelope.
- **Fix direction:** document a spacing-versus-coordinate envelope before mesh and strip consumers rely on spatial spacing, or refuse when spacing < k·ulp(max |coordinate|).

### F3. Low, cosmetic and optional (arc)

- **Indentation:** `road_arc_sampler.gd:444`, the `"section_id"` entry of the global-advance refusal, is still mis-indented. This was 6f F4.
- **Reported error can exceed the tolerance:** acceptance compares `distance <= tolerance` but reports `distance + slack`. A leaf at the limit can therefore report `tolerance + 1e-12·L`. The lab asserts `reported <= DEFAULT tolerance` only on its fixed spans. Impact is sub-nanometre. Either compare `distance + slack` or document it.
- **Slack is not derived from a forward-error bound:**
  - Near the degeneracy threshold (speed / coefficient scale down to 1e-7), relative double rounding in the displacement can reach about 2e-9, above the 1e-12 relative slack.
  - Worst consequence: a fail-closed "inverted bracket" refusal, or an understatement of about 2e-9 × leaf length, which is picometres.
  - I could not provoke either. Every near-cusp acceptance I probed held its bound.
  - Optional: document the derivation, or scale the slack by coefficient scale over leaf length.
- **Final interval (unchanged, still undocumented):** the final station interval can still be arbitrarily short. A 0.0057 m last step was observed at 0.01 m spacing; about 1e-14 m is possible.

### F4. Low (hairpin): recorded section intervals may overlap by up to 1e-4 m, so the ownership exclusivity in the README is not enforced against corrupted records

- **What is checked:** each record is compared with the expected stations within `SECTION_STATION_TOLERANCE` = 1e-4 (626–631). Adjacent records are compared only by `|left_end − right_start| ≤ 1e-4` in `_join_duplicate_error`.
- **Reproduction:** with approach `end_s_m` = 30.00004 and arc `start_s_m` = 29.99996:
  - Baseline samples pass.
  - Sample 29 moved to 29.99998 and tagged `hairpin.arc` **passes**.
  - A gap (29.99996 / 30.00004) is refused ("outside every recorded section"), which is correct.
- **Precondition:** the overlap needs corrupted section records from the builder, and the live builder emits exact shared boundaries. The ownership code itself is exact, as documented.
- **Fix direction:** require `section_ends[i] == section_starts[i+1]` exactly, or at least no overlap. Alternatively, narrow the README sentence that says an interior sample "cannot borrow the neighbouring section's tag".

### Not a finding (noted for scope)

The filter does not cross-check a sample's `s` against its position. A moved station with the correct tag passes the filter. Geometry is instead validated by the lab's shape and turn cases on the live build.

## Plan mismatches (unchanged, open, not defects of this candidate)

- **Width and bank:** still linear in Bezier t and only C0 at knots. Technical Design calls for smooth transitions. This is an M2.1 policy decision.
- **Grade:** `grade_dy_ds` is the tangent's y component, not the design's rise-over-run percentage.
- **Tolerance scope:** the tolerance is per span. A table's total reported error grows with span count; the four-span course reported 2.27 mm. That is consistent with the README, but a course-level budget is not declared.
- **Frame:** OPEN only. Closed-loop residual roll and seam handling remain M2.1 work.

## Optional improvements

- Add an envelope regression: one span at about 8 km near the stated limit, and one beyond it expecting a documented refusal or warning, after F1/F2 are decided.
- Add a near-cusp regression (d = 0.01 above) asserting actual ≤ reported. It is a tight-margin case that the seeded spans do not reach.
- Make the lab's seeded sweep cover aggressive or looping spans and more than one offset. The current 40 are gentle and at about 2 km only.

## Missing evidence and capabilities

- No hosted CI and no `run_validation.sh` shell runners. The results come from one host and one pinned engine.
- **External blockers, not source defects:**
  - No physical 18 m/s hairpin car run.
  - No closed-loop frame, mesh or collision bake.
  - No course-scale authored data, because the Riviera route is not in the repository.
- The Python reference is float64 fixed-panel Gauss–Legendre. It is independent of the GDScript code but is not interval-certified. Its coarse/fine agreement was ≤ 7.6e-8 m on the hardest spans and ≤ 3e-14 m on ordinary ones.
- I did not reproduce the coordinator's overlay builds on 8ffb0c5 or 16f566f. I tested the exact final candidate only.

## Scratch

Everything is under `private/` (logs about 3.6 MB):

- **Engine and reference tools:** `g.sh` and `ref.py`.
- **`build/review_probes/`:** `arc_probe.gd`, `edge_probe.gd`, `cusp_probe.gd` and `hairpin_probe.gd`.
- **`logs/`:**
  - Validator and failure logs and summary JSONs.
  - Probe logs.
  - `arc_probe.jsonl`, `edge_probe.jsonl` and `cusp.jsonl`.
  - `ref.txt`, `ref_edge.txt` and `ref_cusp.txt`.
- The temporary tar extraction was removed.
