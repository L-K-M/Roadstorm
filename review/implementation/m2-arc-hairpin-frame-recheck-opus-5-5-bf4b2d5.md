# Independent Opus 5.5 review: corrected arc sampler, hairpin converter, OPEN frame (exact bf4)

- **Date:** 2026-11-28, about 09:20 to 09:40 CET
- **Candidate:** `bf4b2d5afecea5fb1cb4ed2e72beff04edee3d89` ("Enforce padded arc precision budget")
- **Prior reviewed candidate:** `9751e567d3ebe6a60882e05ec9e84a346977b049` (exact-975)
- **Reviewer:** Claude Opus 5.5 running in the Pi coding agent. The process environment reports `PI_PROVIDER=venice`, `PI_MODEL=claude-opus-5-5` and `PI_REASONING_LEVEL=medium`.

## Scope verdicts

| Scope | Verdict |
|---|---|
| M2 arc sampler (`src/course/road_arc_sampler.gd`, `tools/road_sampling_lab/**`) | **Pass, scoped.** Sol's exact-975 medium finding is fixed. Acceptance now compares the padded reported estimate (`distance + roundoff_slack`) to the local tolerance, so no accepted table reports more error than requested. Below-floor requests refuse as `precision_unreachable`. I reproduced the old false acceptance on the parent sampler and confirmed the fix on bf4. Default-tolerance results match the parent bit for bit on every ordinary probe. Low findings A1 to A3 remain: one lost test of a guard that can still be reached, and two documentation-precision items. None blocks the gate. |
| Provisional M1 hairpin converter (`tools/calibration_hairpin_path_lab/**`) | **Pass, scoped.** My exact-975 low finding (F4, overlapping corrupted section records) is fixed for both joins. Overlap with relabel, overlap alone, a 50 µm gap and a one-ulp gap all refuse. The old source accepts both overlap variants. Both legitimate join copy pairs (raw indices 30/31 and 126/127) still validate. This is not a physical 18 m/s hairpin acceptance. |
| OPEN-road transported frame (`src/course/road_transport_frame.gd`, `tools/road_frame_lab/**`) | **Pass, scoped to the OPEN-only component.** Its source and lab are unchanged since exact-975. Its dependency on the corrected arc sampler passes 7/7 cases and 1,773 checks. Closed loops are still refused explicitly. |
| Not verified, outside this review | Closed-loop roll closure, mesh/collision seams, the physical 18 m/s hairpin, whole M1/M1.7/M2/M2.1, and visual, audio, hardware or rights gates. I did not do a substantive re-review of the `road_source.gd` parser change in `b035800`, which reaches this packet only as an upstream dependency. |

## Identity and route limits

- Pi reported provider `venice` and model id `claude-opus-5-5` through `PI_PROVIDER` and `PI_MODEL`, session `01a2213f-1183-7041-b14c-722ae771f5f8`. I can attest only to these environment values and to my self-identification as Claude Opus 5.5. I cannot verify the serving backend revision or the upstream provider behind Venice's route. The coordinator's launch record is authoritative for the exact invocation.
- **Independence:** I did not read the concurrent Sol packet or report, spawn agents, or use helper models. Inside the packet I wrote only `report.md` and files under `private/`. Read-only Git commands (`cat-file`, `log`, `diff`, `show`, `archive` to stdout) ran against the shared repository to confirm identity and pull parent-revision files into private scratch. I did not create branches, worktrees or clones, and I did not mutate the index or refs.
- **Prior reports read in the archive:** `review/implementation/m2-arc-hairpin-frame-recheck-opus-5-5-9751e56.md`, `review/implementation/m2-arc-hairpin-frame-recheck-gpt-6-2-sol-9751e56.md` and `docs/evidence/m2-arc-hairpin-frame-recheck-975-decision-20261128.md`.

## Archive integrity

| Check | Result |
|---|---|
| `shasum -a 256 source.tar` | `fe275b910fa7fa422733c06dbd1ac9f1a16cc471c04a5d90983076cd76a5dda3`. This equals `source.tar.sha256`. |
| `source-sha.txt` | `bf4b2d5afecea5fb1cb4ed2e72beff04edee3d89` |
| `git cat-file -t` / `git log -1` for that SHA in the shared repository (read-only) | `commit`. Subject "Enforce padded arc precision budget", dated 2026-11-28 09:20:56 +0100. |
| Fresh extraction of `source.tar` into private scratch, compared with `diff -r` against packet `source/` | Identical |
| `git archive bf4b2d5` streamed into private scratch, compared with `diff -r` against the tar extraction | Identical. The tar is exactly the candidate tree. |
| Packet `source/` (plain, no `.git`) against `private/build` before import | Identical. After execution only `.godot/` and generated `*.gd.uid` files are added. |
| Change set since exact-975 (`git diff --stat 9751e56 bf4b2d5`) | `road_arc_sampler.gd` (58 changed lines), `road_sampling_lab/{README,checks}`, the three hairpin lab files, `road_source.gd` (parser underflow narrowing, `b035800`) and `wall_contact_policy.gd` (new, out of scope). `road_transport_frame.gd` and `tools/road_frame_lab/**` are unchanged. |

The scratch extractions and parent-revision overlays were deleted after use. Logs, summaries and probe scripts are kept in `private/results/` and `private/review_probes/`.

## Commands and results

Environment for every engine call, from `private/review_probes/run.sh`:

```sh
P=<packet>/private
C=/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator
ENGINE=$C/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot
export HOME=$P/home TMPDIR=$P/tmp XDG_CACHE_HOME=$P/xdg/cache XDG_CONFIG_HOME=$P/xdg/config XDG_DATA_HOME=$P/xdg/data
/usr/bin/lockf -k -t 300 $C/godot-test.lock /opt/homebrew/bin/timeout -k 5 120 "$ENGINE" "$@" > $P/results/<label>.log 2>&1
```

Validators were run as `--headless --fixed-fps 60 --quit-after 1 --path $P/build --script res://tools/<lab>/validate_<lab>.gd -- --summary-out=$P/results/<lab>.json`. Failure probes used the same flags with `failure_probe.gd`. Import used `--headless --path $P/build --import --quit-after 1`. The `run_validation.sh` Git-staging wrappers were not used. Per the packet instructions, I invoked the supplied GDScript entry points directly against the plain archive build.

| Invocation | Exit | Log inspection | Summary |
|---|---:|---|---|
| `--version` | 0 | none | `4.7.2.stable.official.ed1daf0bf`. This matches `tools/toolchain/pin/engine.txt`. I did not re-verify the publisher archive digest. |
| Import | 0 | No `ERROR` or `SCRIPT ERROR`. One `WARNING`: nested `res://tools/tick_probe` project ignored. | Private cache created |
| `road_sampling_lab` validator | 0 | No `ERROR`, `SCRIPT ERROR` or `WARNING` | **10/10 cases, 631 checks, 0 failed** |
| `road_sampling_lab` failure probe | **3** | clean | `pass:false`, 2 checks, 1 deliberate failure |
| `calibration_hairpin_path_lab` validator | 0 | clean | **10/10 cases, 544 checks, 0 failed** |
| `calibration_hairpin_path_lab` failure probe | **3** | clean | `pass:false`, 2 checks, 1 deliberate failure |
| `road_frame_lab` validator | 0 | clean | **7/7 cases, 1,773 checks, 0 failed** |
| `road_frame_lab` failure probe | **3** | clean | `pass:false`, 2 checks, 1 deliberate failure |

Unlike the exact-975 Sol run, none of these calls logged the macOS `get_system_ca_certificates` error. This was a clean direct run.

The coordinator's claims were confirmed exactly on this source: arc 10/631 and failure exit 3, OPEN frame 7/1,773, hairpin 10/544 and failure exit 3.

Per-case counts:

- **Arc:** open_straight 49, open_curve 72, closed_loop 44, deterministic 9, preservation 9, malformed 62, budget 29, conservative_bracket 60, translated_float64 277, tightened_tolerance_precision_contract 20.
- **Hairpin:** authority 27, section_identity_and_boundary_duplicates 198, geometry 113, mapping 11, repeatability 9, changed_source 32, labels 9, scalar_guards 106, duplicate_ids 21, tag_ownership_refusal 18.
- **Frame:** 210, 515, 129, 812, 18, 75 and 14.

### Old-source controls (private overlays, deleted afterwards)

| Overlay | Exit | Result |
|---|---:|---|
| bf4 build with the hairpin source from parent `6bbfefd` (`3f6d900~1`, file sha256 `cde5afb6…`). Validator otherwise bf4. | 1 | 9/10 cases, 544 checks, **3 failed**, all in `tag_ownership_refusal`: "recorded overlap with relabelled interior sample is refused", "overlap refusal names the exact join station requirement" and "gap refusal names the exact join station requirement". The old source **accepts** the overlap with relabel. It refuses the gap through a different path (sample 31 ownership), which fails only the message check. The new control discriminates. |
| bf4 build with the arc sampler from parent `3f6d900` (`bf4b2d5~1`, sha256 `befff1a8…`) and the bf4 lab | **0** | `SCRIPT ERROR: Parse Error: Cannot find member "PRECISION_UNREACHABLE"` and `Failed to load script … Compilation failed`. No summary was written. **The engine exit status is 0 despite the compile failure.** Only the log and the missing summary reveal it. See the verification note below. |
| Parent arc sampler plus parent lab helpers, running my `arc_probe.gd` | 0, clean log | Reproduces Sol's defect. The diagonal accepts at requested tolerances `3.4e-8`, `1e-8` and `1e-12` while reporting `3.4756e-8 m`, above the request. |

Two notes on the probes:

- The first `probe_new` attempt hit a `SCRIPT ERROR` from my own unsupported `%g` format. I fixed the probe and reran it. The logs kept are from the clean rerun.
- Old-versus-new comparisons used read-only `git show <parent>:<path>` output written only into private scratch copies.

## Inspected paths and lines (bf4)

- `src/course/road_arc_sampler.gd`:
  - header contract at `:36–58`;
  - `Refusal.PRECISION_UNREACHABLE` and its name at `:119` and `:134`;
  - the `ARC_LENGTH_BOUND_RELATIVE_ROUNDOFF = 1e-12` comment at `:76–84`;
  - span chaining and global-station guard at `:390–487`, guard at `:447`;
  - `_integrate_span` with the precision floor at `:747–825`;
  - `_integrate_span_recursive` at `:827–941`: padded acceptance at `:896–903`, cap diagnostic with `bracket_reported_error_m` at `:910–931`, tolerance halving at `:934–941`;
  - `_accept_integration_leaf` at `:944–997`;
  - bracket and slack at `:1023–1103`;
  - `_scalar_control_chord_length` at `:1106–1115`;
  - `_validate_control_points` at `:1496–1514`.
- `tools/road_sampling_lab/road_sampling_checks.gd`:
  - `scalar_chord_length` at `:226–234`;
  - `_check_length_error_covered` at `:422–457`;
  - the malformed and overflow case at `:736–816`;
  - `_check_global_station_collapse_regression` at `:1051–1084`;
  - `_case_translated_float64_regressions` at `:1090–1181`;
  - the seeded sweep at `:1248–1324`;
  - `_case_tightened_tolerance_precision_contract` at `:1329–1456`.
- `tools/road_sampling_lab/README.md:120–225`.
- `tools/calibration_hairpin_path_lab/calibration_hairpin_path_source.gd`:
  - `:88–99` (constants);
  - `_filter_join_duplicates` at `:566–744`, with the exact adjacency check at `:636–651`;
  - `_join_duplicate_error` at `:747–775`;
  - `_samples_ownership_error` at `:1053–1100`.
- `calibration_hairpin_path_checks.gd`: `:160–175` and `:296–300` (join duplicates `[31,127]`, 2 skipped), `:992–1128` (tag ownership including the new overlap and gap controls), and `:1272–1321` (`_mutated_samples`).
- The hairpin `README.md` diff.
- `src/course/road_transport_frame.gd:1–10,289–295,429–466`: the arc dependency surface only, since the source is unchanged. Also `tools/road_frame_lab/road_frame_checks.gd:234`, where it builds its tables with default options.
- The full diffs `bf4b2d5~1..bf4b2d5` and `3f6d900~1..3f6d900`, the stat `9751e56..bf4b2d5`, and the `road_source.gd` diff (read for dependency context only).

## Arc sampler analysis

### Math of the correction

- **Acceptance (`:897–899`).** Acceptance now requires `error_estimate = max(extrapolated − lower, upper − extrapolated) + R·max(|lower|,|upper|) ≤ p_tolerance`, with R = 1e-12. Recursion passes `p_tolerance·0.5` to both children (`:936`, `:940`). An accepted leaf set is a complete binary partition of [0,1]. Any such partition satisfies Σ 2^−d_i = 1 (Kraft equality), so the summed per-span reported error is at most the requested tolerance in exact arithmetic. Only the final floating-point summation (`:995`) can add a few ulps. The header comment `:42–43` ("summed reported error stays within the requested per-span tolerance") is therefore correct, up to that summation rounding.
- **Precision floor (`:758–770`).** Each accepted leaf's error includes a slack of at least R·upper_i, and upper_i ≥ ℓ_i, the true subarc length, in exact arithmetic. Σℓ_i = L ≥ chord. So a request below R·chord can never be satisfied, and refusing it early is sound.
  - The README and code both state that the floor bounds the conservative *reported* estimate, not a proven forward error. This answers Sol's alternative wording.
  - The chord is computed in float64 from float32-stored components (`last.x − first.x` is float64 in GDScript). This matches the lab's `scalar_chord_length`, and the diagnostic reproduces the floor exactly: `3.475571250888118e-08` for the diagonal.
- **Floor is necessary, not sufficient.** At leaf level, acceptance needs roughly R·|B′(t)| ≲ tol near every t. My probe confirms this. A hook with chord 1 m and length 150 m, at tolerances 1e-10 to 1e-12, is above its 1e-12 floor and refuses as `subdivision_cap_exceeded` at depth 20 near t=0, where speed is 300 m. The diagnostic there shows `bracket_reported_error_m 2.86e-16` against a local tolerance of `9.5e-17`. At 1e-9 the same hook refuses as `table_node_cap_exceeded`. This fails closed and the new diagnostic field explains it. The documents claim only the necessary direction, so this is correct. See optional item O1.

### Probe results (bf4 against parent, default options unless noted)

| Input | bf4 | Parent `3f6d900` |
|---|---|---|
| Sol diagonal 24,576 m, tol 1e-3 / 1e-6 / 5e-8 / 3.5e-8 | accepted. Reported `3.4756e-8`, 1 leaf, length `34755.7125088812`. | identical |
| Sol diagonal, tol 3.4e-8 / 1e-8 / 1e-12 | **`precision_unreachable`**, with diagnostic request, floor, chord and allowance | **accepted while reporting 3.4756e-8 > request** (Sol's defect reproduced) |
| S-curves with chord 1 km and 100 km | accepted. Errors `5.80e-4` and `5.21e-4`, 50 and 562 leaves. | bit-identical |
| S-curves with chord 1e7 m and 5e8 m | `table_node_cap_exceeded` | same code (pre-existing cap, not a regression) |
| S-curve with chord 1e9 m | `subdivision_cap_exceeded` | `table_node_cap_exceeded` |
| S-curve with chord 2e9 m | `precision_unreachable` (floor 2e-3 > 1e-3) | `table_node_cap_exceeded` |
| Lab curve fixture at tol 1e-3, 1e-5, 1e-7 | accepted. Reported `5.69e-4`, `5.03e-6`, `5.09e-8` (each ≤ request). The 1e-7 length differs from the lab's independent reference by about 1.7e-9 m. | 1e-3 and 1e-5 identical. At 1e-7 the parent used 1,351 rather than 1,353 leaves and reported `5.11e-8`. |
| Lab curve fixture at tol 1e-9 | `table_node_cap_exceeded` | same |
| Hook (chord 1 m), tol 1e-3 | accepted, reported `1.79e-5` | identical |

There is **no ordinary false refusal.** For spans up to at least 100 km at the default tolerance, bf4 output is bit-identical to the parent. Every new refusal falls at non-physical scale (≥ 1e9 m chord) or at requested tolerances near 1e-10 m and below. All such inputs were already refused by caps or now refuse instead of being falsely accepted.

### Test integrity

- The old default regressions remain and pass:
  - the 1 mm Sol diagonal: actual `7.28e-12`, reported `3.48e-8`, 2 samples;
  - the two non-dyadic straights;
  - road1, road2 and hook translated by 1.4 to 5 km;
  - all **40/40** seeded road-like spans: worst actual error `3.33e-5`, worst reported `6.82e-4`, worst (actual − reported) `−3.08e-4`, reference uncertainty at most `2.8e-13`;
  - Sol's quadratic, and the Opus road1 and hook spans.
- `_check_length_error_covered` still asserts that actual ≤ reported and reported ≤ 1 mm.
- The new tightened case (20 checks):
  - checks that the request is below the floor;
  - checks the refusal code and the substring `"floor"`;
  - checks that the diagnostic's request, floor and chord fields match the lab's independent scalar chord;
  - accepts just above the floor (5e-8) and at 1e-6, with reported ≤ request and the analytic length within the request.
- Its control at 5e-8 is genuine. The probe shows 3.5e-8 accepting and 3.4e-8 refusing.
- Its geometry is a straight line with distance ≈ 0, so it does not test padded acceptance on a curved span at a tightened tolerance. My curve-fixture probe covers that informally. See O2.
- Caps and overflow behaviour remain:
  - the budget case still passes 29 checks: output, node and depth caps and illegal option values;
  - the derived-overflow case (`±2e38` handles with a 2 m chord) still yields `nonfinite_derived_state`, because the short chord keeps its floor tiny;
  - the global-station guard source (`:447–460`) and the leaf monotonicity guard (`:982–993`) are intact.
- The bf4 lab cannot compile against the parent sampler because it references `PRECISION_UNREACHABLE`. "Old source fails the new arc control" therefore holds only as a compile failure with engine exit 0. My standalone probe gives the behavioural old-source evidence.

## Ranked actionable findings

All findings are **Low**. None is a correctness defect in accepted output.

### A1. Low, arc test coverage: the global-station advance guard is reachable at public defaults, but no test exercises it now

`road_sampling_checks.gd:1051–1084` changed the 2^53 m fixture to expect `precision_unreachable`. The README (`:202–208`) honestly says the fixture "no longer reaches" the guard.

However, the in-code comment at `:1056–1057` says "A request above the floor could still expose that guard." That cannot happen through the public API, because tolerances above 1 mm are `bad_options` and this fixture's floor is about 9e3 m.

The guard is still reachable at default options with a different fixture. My probe kept the lab's straight fixture and set:

- prefix `2^29 m`, with handles at `P/4` and `P/2`;
- a second span of `2^-26 m` along z at `x = 2^29`.

The first span integrates normally, since its floor of `5.4e-4` is below 1 mm. The second span then refuses with `table_inconsistent`: "span 1 (lab.sampling.straight.b) produced a positive local length that does not advance the global station", with `span_start_s = span_end_s = 536870912.0` and `length_m = 1.49e-8`. Both bf4 and the parent produce this.

**Fix direction:** restore guard coverage with such a reachable fixture, keep the 2^53 m fixture as a precision-floor case, and correct the comment at `:1056–1057`.

### A2. Low, documentation precision: the scope of the tolerance option and the aggregate error are not stated where users read them

The header comment (`:41–44`) says the tolerance is per span. The README option table (`README.md:150–153`) lists `arc_length_tolerance_m` without saying "per span", and the text describes only per-span sums.

`Table.length_error_estimate_m` is the **sum** over spans (`:440`, `:606`), so it can exceed the requested option for multi-span courses. For example, 40 spans at the seeded worst case of `6.8e-4` sum to about 2.7 cm.

The test check "reported ≤ default tolerance" passes only because every regression is a single span. Downstream consumers reading the table-level estimate against 1 mm would be misled.

**Fix direction:** state "per span" in the option table and document that the table-level estimate is a sum, bounded by span_count × tolerance plus summation rounding. Also note that the floor applies per span to each span's endpoint chord.

### A3. Low, diagnostics: refusal codes for unreachable tight requests vary

The floor catches only requests below R·chord. Requests between that and the leaf-level requirement of about R·max|B′| refuse as `subdivision_cap_exceeded` or `table_node_cap_exceeded` (probe: hook at 1e-9 to 1e-12, S-curve at 1e9 m).

The floor check also runs before the derivative-degeneracy and speed checks (`:758` against `:781–794`). A huge degenerate span therefore now reports `precision_unreachable` instead of `degenerate_derivative`.

Both behaviours fail closed. The README's refusal list does not mention that a precision-limited request may surface as a cap refusal.

**Fix direction:** add one sentence to the README, or derive a tighter floor from 3·max control-edge length. This is optional.

### H1. Low, cosmetic (hairpin): the adjacency refusal message can print a zero difference

The message `%.9f` at `calibration_hairpin_path_source.gd:644–650` prints `difference 0.000000000 m` and identical stations for an ulp-scale gap (probe "join0 one-ulp gap"). The refusal itself is correct. Printing with `%.17g` or `str()` would make the diagnostic actionable.

No other actionable findings.

## Hairpin converter analysis

- The new check at `:641–651` runs after each record's start, end and length have been checked against the authored stations within `SECTION_STATION_TOLERANCE`. It runs before the sample loop and before `_samples_ownership_error`, so ownership can no longer be computed on overlapping or gapped intervals. It covers both joins (`range(2)`).
- In the live builder output the joins are exact:
  - `end0 = start1 = 30.0` and `end1 = start2 = 124.247779607694`;
  - raw samples 30/31 (approach/arc) and 126/127 (arc/exit) share those exact stations;
  - the unmodified raw stream validates;
  - the `section_identity_and_boundary_duplicates` case still asserts duplicates at `[31,127]`, 2 skipped and 156 unique samples;
  - `tag_ownership_refusal` asserts index 30 is approach and index 31 is arc.

  Both legitimate join copies survive.
- Probe on bf4 against the parent (`private/review_probes/hairpin_probe.gd`):

| Mutation | bf4 | Parent |
|---|---|---|
| Baseline | passes | passes |
| Join 1 overlap (exit start −5e-5), with sample 125 moved to end −2.5e-5 and tagged exit | refused, "adjacent section records do not share an exact join station" | **accepted** |
| Join 1 overlap only | refused | **accepted** |
| Join 0 one-ulp gap | refused (exact join station) | refused through sample-31 ownership |
| Lab controls: join 0 overlap with relabel, and the 5e-5 gap | refused | overlap **accepted**, gap refused through ownership |

- `_join_duplicate_error` still allows `1e-4` between a duplicate station and the records. Ownership is exact, so a duplicate pair shifted off the exact boundary now fails ownership on one side. I found no remaining borrowing path through altered records.
- The README limitation stays honest: a single non-duplicate sample placed exactly on a boundary may still be claimed by either side. The builder does not emit one.

## OPEN frame analysis

`road_transport_frame.gd` and `tools/road_frame_lab/**` are byte-identical to exact-975. Its arc dependency is reached only through `RoadArcSampler.build_uniform_table(document, spacing)` with default options (`road_frame_checks.gd:234`) and a `RoadArcSampler.Table` type check (`:289–295`).

The bf4 arc change cannot alter any default-option table at road scale, as the bit-identical probes show. It only adds a refusal code for out-of-range requests, and the frame never sees it, because a refusal yields no table.

The executed 7-case, 1,773-check lab confirms these:

- the straight zero-bank basis;
- graded and banked transport;
- bank return to the authored zero;
- near-vertical rapid grade;
- determinism and copy safety;
- malformed-input refusals;
- explicit closed-loop refusal.

My exact-975 inspection of the transport algorithm still applies. Closed-loop residual-roll distribution (`docs/TECHNICAL_DESIGN.md:117`) is still not implemented and is outside this pass.

## Plan mismatches

- `PLAN.md:87` and `docs/TECHNICAL_DESIGN.md:115–119` (M2.1) still require:
  - smooth width, bank and surface transitions;
  - shared outputs for strip, collision, AI and gates;
  - chunked mesh and collision baking;
  - closed-loop roll closure.

  None is provided here. Width and bank remain linear in Bézier t, and surfaces are discrete. This is unchanged since exact-975.
- `PLAN.md:78` (M1.7) requires physical calibration evidence. The hairpin lab is a converter and fixture check only.
- The exact-975 decision assigned a supported coordinate and spacing envelope (float32 authored-to-stored quantisation, small spacing at large offsets, a short final edge) to downstream strip and course components. bf4 does not address it, and it is not in scope here.

## Optional improvements

- **O1.** Document that the floor is necessary but not sufficient, or tighten it using 3·max control-edge length (an upper bound on |B′|), so more unreachable requests refuse as `precision_unreachable`. Related to A3.
- **O2.** Add a curved-span tightened-tolerance check, for example the curve fixture or road1 at 1e-5 and 1e-7. It would assert reported ≤ request and actual ≤ reported against the lab's Gauss reference.
- **O3.** Add join 1 (arc→exit) overlap and gap regressions to the hairpin lab. The source loop covers both joins, but only join 0 is tested. My probe shows join 1 refusing correctly.
- **O4.** Treat the engine exit status as non-authoritative. A compile failure of the `--script` entry exited 0 here. The supplied wrappers should, and reportedly do, require the summary line and an absence of `SCRIPT ERROR`. I did not run those wrappers in this pass.

## Missing evidence and capabilities

- I could not attest the serving backend or revision behind the Venice route.
- I did not run the `run_validation.sh` Git-staging wrappers or CI, and I did not re-verify the publisher archive digest for the engine.
- No PR, CI or merge status was established. The candidate was reviewed as an immutable archive.
- Not covered: physical driving, the 18 m/s hairpin, closed-loop frame closure, mesh and collision, performance, and visual, audio, hardware or rights review.
- My probes are bounded and finite. They do not prove an outward-rounded forward error bound for all inputs. The sampler explicitly does not claim one.

**No whole M1, M1.7, M2 or M2.1 gate is approved. No visual, audio, hardware or rights gate is approved.**
