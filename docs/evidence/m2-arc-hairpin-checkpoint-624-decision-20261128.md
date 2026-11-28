# M2 arc sampler and M1 hairpin path checkpoint decision — `624f053`

Date: 2026-11-28. Candidate: `624f05385fddfc1872a302d925f29d8e9214eb40`. The two reviewers used separate plain archives and private Godot builds. [Opus 5.5 via Pi Venice](../../review/implementation/m2-arc-hairpin-checkpoint-opus-5-5-624f053.md) and [GPT-6.2 Sol via Codex CLI](../../review/implementation/m2-arc-hairpin-checkpoint-gpt-6-2-sol-624f053.md) each report **changes required** for both scoped components. The Sol CLI identified the exact requested model, without an additional runtime attestation. Neither report covers the concurrently changed source parser, new sweeper/baker/reward-C slices, or later frame work.

## Supported blocking findings and actions

1. **Arc quadrature:** Both reviewers independently reproduced ordinary cubic spans for which the Simpson/Richardson estimate understates actual length error beyond the authored 0.001 m tolerance. Sol supplied an analytic quadratic with 0.027163445 m error despite a 0.000825063 m estimate; Opus supplied several pinned-engine road-like counterexamples, including a 1.433 m hook discrepancy. A LongCat worker owns `src/course/road_arc_sampler.gd` and its lab. Require conservative acceptance/cap refusal and independent analytic/curved regressions. Do not accept a tighter claimed tolerance from the existing estimated error alone.
2. **Hairpin missing and nonfinite scalar guards:** Both reviewers reproduced missing values passing the converter's NaN fallback comparisons. Opus also demonstrated missing section station fields and NaN bay width, and found that `grip_entry` speed is not bound. A LongCat worker owns the hairpin converter/lab. Require presence, numeric finiteness and expected-value checks for every required authored/fixture scalar and section station; verify the actual source authority before accepting a successful build.
3. **Global station representability:** Sol reproduced a positive 0.25 m span after a 2^53 m prefix whose local length is positive but global `start_s == end_s`. Require refusal of the entire arc table when any positive span does not advance the global station; the arc worker owns the regression.
4. **Ordered hairpin tags:** Sol changed an interior approach/asphalt raw sample to exit/gravel and the filter accepted it. The hairpin worker owns section/surface ownership checks with explicit two-sided join handling.

The scoped gate remains **open**. Freeze each correction, rerun pinned validation and negative controls, then obtain **both named scoped rechecks on the corrected exact candidate**. No whole M1, M1.7, M2 or M2.1 gate follows from these reviews.

## Lower-priority dispositions

- Opus notes width and bank interpolate linearly in Bezier parameter and are only C0 at knots, whereas the technical design requests smooth transitions. Keep this as an open M2.1 geometry-policy decision; do not claim smooth baked geometry from the current sampler.
- Opus notes a vanishing final station interval, an inversion-error estimate without an independent bound, and the distinction between `grade_dy_ds` and rise/run grade. Inspect these during the arc correction and frame/mesh integration; the sample-length breach above is blocking now.
- Opus finds the hairpin test comment says samples sit inside the circle, whereas the builder's midpoint stepping places them about 2.73 mm outside. Correct the comment in the hairpin worker's owned lab. The 1 cm fixture tolerance still passes.
- Both reviewers verified the existing 7-case/274-check arc and 7-case/397-check hairpin labs and distinct deliberate-failure exits in private pinned-engine builds. Those suites did not detect the findings, so they are not acceptance evidence for the unchanged candidate.
- The road-source huge-exponent decoder finding from the separate exact-`63fa101` Sol review remains under a separate repair and both corrected-SHA rechecks.
