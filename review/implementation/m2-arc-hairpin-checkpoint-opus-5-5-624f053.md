# Independent review: M2 arc sampler and M1.7 hairpin path, candidate 624f053

- Date: 2026-11-28
- Reviewer: Claude Opus 5.5 through the Pi harness, Venice provider route (`PI_PROVIDER=venice`, `PI_MODEL=claude-opus-5-5`, reasoning `medium`). Venice forwards requests to a third-party host.
- Candidate: `624f05385fddfc1872a302d925f29d8e9214eb40`. Prior named parser candidate: `63fa101a8d76ee951ef498866b18f27b8e053422`.
- Independence: I did not read the concurrent Sol report or the current checkpoint report, and I spawned no agents. Tracked source was not edited and Git was not changed.

## Verdicts (primary scope)

| Scope | Verdict |
| --- | --- |
| `src/course/road_arc_sampler.gd` + `tools/road_sampling_lab/**` | **changes required** |
| `tools/calibration_hairpin_path_lab/**` | **changes required** |

A scoped pass would not have closed any milestone gate either. The whole M1, M1.7, M2 and M2.1 gates remain open. The source parser's huge-exponent decoder mismatch is OPEN and outside this packet, so nothing here claims M2 source or M2.1 closure. Frame transport, mesh, collision, the Riviera course and a physical hairpin are not implemented by this scope.

## Source verification

- `shasum -a 256 source.tar` = `e09573ac0047b8a1edf6ede4dfdfb9f982aeac7497767a59a84d91408d2e9584`, which matches `source.tar.sha256`.
- Extracting `source.tar` to scratch and running `diff -rq` against `source/` showed the two trees are identical (1491 tar entries).
- `git archive 624f053...` from the shared repository, a read-only object read extracted to private scratch, also matched `source/` under `diff -rq` (`MATCH_624`).
- `git log 63fa101..624f053`: 8978873, 8c9b343, ac28712, 451ebd8, 624f053. The 15 `scope.paths` files are all new in this range: sampler 1520 lines, sampling lab 1720, hairpin lab 2038. Sweeper, baker and evidence changes in the same range were not reviewed (outside this packet).

## Inspected

- `src/course/road_arc_sampler.gd`: all of it, 1–1520.
- `tools/road_sampling_lab/`: README, checks (all 725 lines), validator, probe, and the fixtures by reference. Runner `run_validation.sh` was read only for its pass gates (lines 488–540).
- `tools/calibration_hairpin_path_lab/`: README, source (all 659 lines), checks (all 778 lines), validator, probe. Runner lines 263–340 were read for its gates.
- Context, read only:
  - `src/course/road_source.gd`: span semantics, `control_points()` and the degeneracy guards at 1187–1215.
  - `src/laboratory/handling_lab_builder.gd` `_sample_bay`: lines 219–330.
  - `src/calibration/calibration_driver.gd`: lines 1–30, the progress policy.
  - `src/simulation/motor_body_adapter.gd`: line 706.
  - `fixtures/handling/hairpin.json`.
  - `docs/TECHNICAL_DESIGN.md`: lines 102–117.
  - `PLAN.md`: lines 78 and 87.

## Commands actually run

All engine runs used a private copy of `source/` at `private/build`, with private HOME, TMPDIR and XDG_* directories, wrapped as `lockf -k -t 300 <shared godot-test.lock> timeout <240|90> <pinned Godot>`. The archive's git-dependent runners were not used, and the live checkout was not imported.

| Command | Result |
| --- | --- |
| `Godot --version` | `4.7.2.stable.official.ed1daf0bf` |
| `--headless --path build --import` | rc 0 |
| Sampling validator | rc 0, **7 cases / 274 checks / 0 failed**, no `ERROR` lines in the log |
| Hairpin validator | rc 0, **7 cases / 397 checks / 0 failed**, no `ERROR` lines in the log |
| Sampling `failure_probe.gd` | rc 3, `"pass":false`, 1 of 2 checks failed |
| Hairpin `failure_probe.gd` | rc 3, `"pass":false`, 1 of 2 checks failed |
| `review_probes/sampler_probe.gd` (mine, scratch only) | Results under F1 and in the observations below. The first attempt hit a GDScript `%g` format error, never reached `quit`, and timed out (rc 124). It was fixed and rerun with rc 0. |
| `review_probes/hairpin_probe.gd` and `hairpin_probe2.gd` (mine, scratch only) | Results under F2 |
| `python3 private/search*.py` | Float64 replica of the sampler's adaptive Simpson, compared with a fine midpoint reference over random spans |

These runs reproduce the coordinator's claimed counts and probe exit codes. The prepared runners themselves were not run.

## Findings (ranked)

### F1. High: adaptive Simpson can stop too early, and the table then reports a wrong length with a small error estimate (implementation defect, sampler)

- **Where:** `road_arc_sampler.gd:809-813` accepts a leaf as soon as `|S2−S1|/15 <= tol`, including at depth 0 for the whole span `[0,1]`. There is no minimum subdivision depth or second check. The sum at lines 541/548 then reports that wrong error estimate as `length_error_estimate_m`.
- **Pinned-engine counterexamples** from the actual sampler. Each is a single valid `road_source.v1` span. The reference is a 262144-panel midpoint rule.

  | Span | Sampler length (m) | Reference (m) | Error (m) | Reported estimate (m) | Leaves |
  | --- | --- | --- | --- | --- | --- |
  | `p.road1` (gentle 141 m S-bend: P1 (46.68, −30.63), P2 (88.92, −19.57), P3 (141.37, 0) in plan x/−z) | 147.893787 | 147.905655 | −0.011868 | 0.000788 | 1 |
  | `p.road2` (P1 (51.00, 18.45), P2 (95.86, 28.36), P3 (144.71, 0)) | 150.271624 | 150.278642 | −0.007017 | 0.0000205 | 1 |
  | `p.hook`, spacing 100 (P1 (−41.51, −26.79), P2 (−5.40, −15.30), P3 (−12.43, −10.97); minimum speed 10.6, not near a cusp) | 40.679873 | 39.246615 | +1.433 (3.6 %) | 0.00014 | 1 |

- The same hook at spacing 5 is refused as `inversion_failed`. Station 40.0 lies beyond the true length, so the refusal is safe but names the wrong cause.
- **Frequency:** the float64 replica on 5000 random road-like spans (chord 30–200 m, handles 0.25–0.4 of the chord, ±0.6 rad) gave 19 spans above the 1 mm tolerance. A minimum depth of 2, 3 or 4 left 0 spans above it (worst 3.9e-4, 1.4e-5 and 3.2e-6 m), and the hook's error fell to 2.4e-6 m at depth 4.
- **Impact:**
  - Stations, span `start_s`/`end_s` and the final interval are silently wrong by far more than the explicit 1 mm contract.
  - The README and module both claim that reaching a cap or tolerance is never a silent approximation. That claim is false here.
- **Fix:** force at least 3–4 levels of subdivision before accepting any leaf, or require a second, finer estimate. Add an independent-length regression on adversarial or random spans, including `p.road1` and `p.hook`.
- **Test fallout:** the straight-span checks at `road_sampling_checks.gd:364-365` expect exactly one integration leaf. They will need to change with the fix.
- **Missing evidence:** the lab compares the independent length on only one curved fixture, and with a 5 mm tolerance (`road_sampling_checks.gd:16`), 5× the contract. That is why it does not catch this defect.

### F2. Medium: hairpin source-authority guards pass when a value is missing or NaN (implementation defect, hairpin)

- **Where:** `calibration_hairpin_path_source.gd`. Every check written as `absf(float(x.get(key, NAN)) - expected) > tol` passes when the value is NaN or the key is missing, because the comparison is then false. Affected lines: 210, 239–265, 299–339, 351–353, 387–393, 492–493.
- **Pinned-engine counterexamples.** `build()` returned `ok=true` with 156 samples in each case:
  - `drift_entry.initial_state.velocity_m_s` removed, or set to NaN. This is the value the provisional 18 m/s label is said to equal.
  - `arc_length_m` removed from all four timing gates.
  - Fixture segment `width_m`, arc `radius_m`, arc `angle_deg` and approach `length_m` removed.
  - Bay segment `width_m` set to NaN. The summary then records a NaN width.
- `_validate_samples(raw_samples, sections)` returned `''` after `start_s_m`, `end_s_m` and `length_m` were removed from every section record (`hairpin_probe2`). Joins at lines 488–500 are therefore accepted without the documented "exact recorded end/start station" check.
- Bay yaw NaN and bank NaN were refused, but only indirectly, by the downstream nonfinite-position and nonfinite-right checks.
- **Impact:**
  - The live data are correct today, so the current output is right.
  - The guard does not match the README's claim that a changed authored value "fails the build instead of falling back".
  - The 18 m/s value's tie to the fixture can pass with no fixture value present.
  - `grip_entry` speed is not checked: setting it to 40 was accepted.
- **Fix:** compare in the fail-closed direction, for example `not (absf(v - e) <= tol)`, or require `is_finite(v)` and the key's presence. Add missing-key and NaN negative controls.

### F3. Low: plan mismatch, width and bank are linear in t and only C0 at knots (plan mismatch, sampler)

- `road_arc_sampler.gd:1146-1147` interpolates width and bank linearly in t within each span. `TECHNICAL_DESIGN.md:115` asks to "interpolate width, banking, and surface transitions smoothly".
- The README states this limitation and claims no more, so it is not a defect of this slice. It must be resolved or ratified before M2.1.

### F4. Low: optional improvements (sampler)

- **Near-zero final interval.** `_make_uniform_stations` (1363) accepts a vanishing final interval. Spacing `59.99999999999999` on the 60 m fixture gives stations `[0, 59.99999999999999, 60]`, a 7e-15 m final interval. Consider merging a final interval below a fraction of the spacing, or documenting it for later mesh and collision baking.
- **Unbounded inversion error estimate.** `max_inversion_error_estimate_m` is reported but never compared with any tolerance. The residual check at 1016 uses the same quadrature, so it cannot detect that quadrature's own error. Enforce a bound or document the limit.
- **Name collision risk for `grade_dy_ds`.** The field is the sine of pitch (dy/ds). The design's 12 % grade target is rise over run. Consumers at T09 must not compare the two directly; a note would help.

### F5. Low: hairpin documentation nit

- `calibration_hairpin_path_checks.gd:18` says the polyline sits about 3 mm *inside* the circle. The builder steps by arc length (`ds = r·dθ`) along the mid-heading, so the samples lie *outside* the circle. A replica measured up to +2.73 mm at the arc exit, and the exit leg is offset by the same amount.
- The 1 cm tolerance still holds.

## Checked without findings

- **Sampler:**
  - **Refusal bounds:** spacing 0, −1, NaN, INF and a string; spacing `5e-324` (refused `bad_spacing`); spacing `1e-300` and `0.0030001` (`sample_cap_exceeded`, with the pre-check matching the actual count of 20001); spacing `1e308` (stations `[0, L]`).
  - **Behaviour on success and refusal:** stations are strictly increasing, with exact start and end. Refusals never return a partial table, and returned tables are deep copies.
  - **Section ownership:** spans own `[start_s, end_s)`, a station exactly on an interior knot goes to the following span, and the course end uses the final span at t=1 (lines 1424–1435 and 528–530).
  - **Closed seam:** the start and end come from the same anchor at t=0 and t=1. Tangent continuity at the seam is the source document's concern, not the sampler's.
  - **Exact-zero derivatives:** cusp and interior zeros are refused.
  - **Precision and range:** spans with coordinates around 20 km, and straights of 1, 3, 10 and 30 km, sampled within 3e-5 m. The float32 `Vector3` concern was unfounded at these scales.
- **Hairpin:**
  - Stream identity: raw 158 samples, unique 156, join duplicates at raw indices 31 and 127, and the preceding section's copy survives. Per-sample section and surface order is ordered and asserted.
  - Mapping: world-to-road mapping is `Vector2(x, −z)` and is cross-checked for every sample.
  - Geometry: the signed turn totals +π and the heading reverses.
  - Nearest-point progress refuses unconditionally, which matches the `CalibrationDriver` policy.
  - The 18 m/s value is labelled provisional, not measured or tuned. That label is truthful for the current fixture, but see F2.

## Capability limits and missing evidence

- I did not run the prepared runners; runner shell gates were only skimmed.
- Hosted CI was not observed.
- Results come from one host and one pinned engine; no cross-host determinism is shown.
- The float64 replica approximates the GDScript implementation. The headline counterexamples were confirmed on the pinned engine.
- No gameplay, visual, audio, hardware, performance or rights evaluation was performed, and none is approved.

## Scratch

Everything I created is under `private/`: the build copy, `review_probes/`, `search*.py` and `logs/` (largest log 300 KB). An empty `private/tarcheck` directory I created by mistake in the packet's parent directory (`m2-arc-hairpin-checkpoint-624/private`) was removed immediately.
