# Independent Roadstorm geometry review

**Date** 2026-11-28  
**Candidate** `9751e567d3ebe6a60882e05ec9e84a346977b049`  
**Prior checkpoint** `6f032431133cb44fe6702291b35b38e79505e902`

| Scope | Verdict |
|---|---|
| M2 arc sampler | **Prior defects cleared at the default tolerance on the supplied cases. Changes required for the advertised tightened-tolerance range.** All 46 targeted regressions accepted, including the exact diagonal, and their measured discrepancies were covered by the reported estimates within the lab’s reference checks. The acceptance test still allows a requested tolerance smaller than the error it can establish. |
| M1 provisional hairpin path converter | **Scoped pass for the authored fixture and the supplied regressions.** Duplicate gate and run IDs refused in either order. Near-join interior tag borrowing refused with genuine builder metadata, while both legitimate join pairs survived validation. A residual overlap case exists if section records are also corrupted. |
| OPEN-road transported frame | **Scoped pass.** All seven cases exercised the frame component with the imported candidate and working arc dependency. Closed input explicitly refused. |

**Reviewer identity and independence.** I performed this review in OpenAI Codex CLI runtime `0.171.0-alpha.13`. The packet assigns `gpt-6.2-sol`. I could verify the CLI session and its assignment, but could not recover an authoritative effective model flag, provider override, or backend serving revision for this launch. Process inspection was denied, and the readable config default is `gpt-6-sol`, which does not establish the model used by this invocation. The coordinator’s launch record is needed to confirm exact model and provider selection. Even a confirmed CLI selection would establish the invocation only. I read the two tracked **prior** exact-6f reports and their tracked decision in the archive. I did not read the concurrently assigned Opus packet or report, spawn agents, run new probes, edit source, or mutate Git.

## Archive integrity and execution

From the packet directory, `shasum -a 256 -c source.tar.sha256` returned `source.tar: OK`. The recorded SHA-256 was `c6ec0fd265f42259abdfea30ad6e427f3f77d69951df626943125644b30f6dea`. Both `cat source-sha.txt` there and the read-only `git get-tar-commit-id < ../../source.tar` from `private/build` identified the full candidate SHA above. An extracted copy of the tar in private scratch matched `source/` by recursive comparison. Before import, `diff -qr ../../source .` found no differences against `private/build`. After execution it showed only `.godot` and generated `.gd.uid` additions. I removed the scratch archive comparison copy and retained the private execution logs and summaries.

I used the following command sequence from the packet’s `private/build`. Each engine invocation acquired the same coordinator lock and had its own timeout. The installed binary was used at the designated publisher-pinned path. The version check matched `tools/toolchain/pin/engine.txt:27`. I did not independently verify the original publisher download archive during this review.

```sh
private_dir="$(cd .. && pwd -P)"
build_dir="$PWD"
coordinator="/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator"
engine="$coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"

mkdir -p "$private_dir/results" "$private_dir/xdg/"{cache,config,data}
export HOME="$private_dir/home" TMPDIR="$private_dir/tmp"
export XDG_CACHE_HOME="$private_dir/xdg/cache"
export XDG_CONFIG_HOME="$private_dir/xdg/config"
export XDG_DATA_HOME="$private_dir/xdg/data"

run_engine() {
  local label="$1"
  shift
  /usr/bin/lockf -k -t 60 "$coordinator/godot-test.lock" \
    /opt/homebrew/bin/timeout -k 2s 60s "$engine" "$@" \
    >"$private_dir/results/$label.log" 2>&1
}

run_engine version --version
run_engine import --headless --path "$build_dir" --import
for lab in road_sampling_lab calibration_hairpin_path_lab road_frame_lab; do
  run_engine "$lab" --headless --fixed-fps 60 --path "$build_dir" \
    --script "res://tools/$lab/validate_$lab.gd" \
    -- --summary-out="$private_dir/results/$lab.json"
  run_engine "$lab-failure" --headless --fixed-fps 60 --path "$build_dir" \
    --script "res://tools/$lab/failure_probe.gd"
done
```

| Invocation | Exit | Observed result |
|---|---:|---|
| Godot `--version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| Headless import | 0 | Private cache generated. No script, parse, or dependency load errors. |
| Road sampling validator | 0 | 9 of 9 cases passed, 611 checks, 0 failed |
| Hairpin path validator | 0 | 10 of 10 cases passed, 540 checks, 0 failed |
| OPEN frame validator | 0 | 7 of 7 cases passed, 1,773 checks, 0 failed |
| Each of the three supplied failure probes | 3 | Each emitted `pass:false`, 2 checks, and 1 deliberate failure |

All seven headless calls logged `ERROR: Condition "ret != noErr" is true. Returning: ""` at `get_system_ca_certificates (platform/macos/os_macos.mm:1035)`. Import also warned that the nested `tools/tick_probe` project was ignored. I found no private cache or result write failure, timeouts, or script dependency failures. Full check counts and structured summaries distinguish this run from the incomplete exact-6f Sol run. The CA lookup message is a platform diagnostics issue of undetermined cause. It prevents claiming a clean engine log, and the supplied runners’ strict log check would reject it. I invoked the supplied GDScript entry points directly against the pre-staged plain archive and did not run the Git-staging shell wrappers.

## Ranked actionable findings

1. **Medium, arc acceptance can exceed a caller’s tightened precision budget.** `src/course/road_arc_sampler.gd:845–875` checks `distance <= p_tolerance`, then reports `distance + roundoff_slack`. The option parser at `:1378–1393` accepts any positive finite tolerance up to `0.001 m`. The diagonal’s measured allowance alone is about `3.48e-8 m`. An even tighter request can leave a zero-distance, zero-Richardson leaf eligible for acceptance while its reported bound exceeds the request. For the exact diagonal, constant speed at the dyadic nodes makes the coarse and refined Simpson values agree, and the observed estimate is accounted for by the allowance. No binary64 result can represent its irrational length exactly. This is a source-derived issue with the advertised tightening range, with no extra runtime probe performed. If the option promises a bound on actual integration error, use the padded bound for acceptance and return a structured precision refusal when the requested budget cannot be established. Alternatively, define the tolerance explicitly as the geometric subdivision budget before roundoff and document the precision floor. Cover a below-floor analytic straight when changing this behavior. The default-range regressions show no recurrence of the prior millimetre-scale defect.

2. **Low, malformed hairpin section records can reintroduce dual ownership inside a join.** `tools/calibration_hairpin_path_lab/calibration_hairpin_path_source.gd:617–631` checks each record boundary separately against the authored station with `1e-4 m` tolerance. The join-pair check at `:726–754` also allows disagreement of up to `1e-4 m`. The ownership loop at `:1033–1082` then accepts any recorded interval containing the station. For example, a recorded arc start of `29.99995 m` and an unchanged approach end of `30 m` overlap. The genuine pair at `30 m` can still satisfy the join check, while a relocated ordinary sample at `29.999975 m` can borrow the arc tag. This is a source-derived malformed-metadata case. The supplied pre- and post-join regressions passed with the genuine section records. If the raw validator is the fail-closed boundary for section metadata, require adjacent records to share the exact builder station before assigning ownership, and cover a corrupted boundary plus interior relabeling in the lab.

3. **Verification gap, strict runner evidence and exact launcher attribution.** The direct validator evidence is substantive, but the CA lookup error would fail the runners’ log gate. The coordinator should retain both the direct results and the environment qualification. The exact model flag and selected provider need the coordinator’s launch record before this report can be credited as a verified exact-model invocation.

## Component inspection and measurements

### Arc sampler

I inspected `src/course/road_arc_sampler.gd:350–516` for options, span chaining and output budgeting, `:739–1071` for adaptive integration, leaf acceptance and the bracket, `:1077–1230` for inversion, and `:1635–1725` for scalar evaluation and overflow handling. I inspected the supplied regressions and reference checks in `tools/road_sampling_lab/road_sampling_checks.gd:292–439,724–1067,1072–1306` and the numerical contract in its `README.md:120–166`.

The corrected code reads stored `Vector3` components into scalar arithmetic for derivative differences and the norm. It computes a subinterval displacement without subtracting two rounded world-space `Vector3` positions, then derives three local control-polygon edges. The summed chord and polygon lengths bound the subarc in exact arithmetic. The reported estimate now adds the leaf roundoff allowance. This removes the common float32 norm error that let the old Simpson estimate and bracket agree on an understated diagonal length. The geometry under review is the cubic through the **stored** control points. Import quantization from authored coordinates and rounding of output `Vector3` positions and tangents are separate.

| Regression | Absolute discrepancy against lab reference, m | Reported estimate, m |
|---|---:|---:|
| Exact diagonal, analytic `24576√2` | `7.276e-12` | `3.476e-8` |
| Non-dyadic straight A | `1.563e-13` | `1.001e-10` |
| Non-dyadic straight B | `9.948e-14` | `7.221e-11` |
| Translated road1 | `1.071e-7` | `6.629e-4` |
| Translated road2 | `8.335e-9` | `4.453e-4` |
| Translated hook | `7.960e-7` | `4.454e-4` |

The diagonal supplied exactly two endpoint samples. All 40 seeded road-like spans accepted at default options. Their largest discrepancy was `3.328e-5 m`, their largest estimate was `6.819e-4 m`, and their largest signed discrepancy minus estimate was `−3.082e-4 m`. The largest coarse/fine reference difference for that sweep was `2.842e-13 m`. The prior quadratic regression measured a discrepancy of about `8.689e-5 m` against its analytic reference, covered by its reported `5.735e-4 m` estimate. I observed neither an accepted understated estimate nor an ordinary false refusal in the supplied default-option cases. Finite test coverage and the relative padding do not establish a formal outward-rounded error bound for all accepted inputs. Chaining also sums nominal span lengths and span error estimates without an explicit allowance for prefix accumulation at `:428–437`.

The existing budget and malformed-state tests passed. They exercise subdivision depth, node and output sample caps, illegal cap options, non-dyadic stationary derivatives, and derived overflow from individually representable controls. The explicit scalar guards retain the component-range refusal for derived differences and derivatives. The `2^53 m` prefix followed by a positive `0.25 m` span still refuses when global station fails to advance. That guard establishes strict advance, with no guarantee about the fidelity of a small increment that does advance at an extreme prefix.

Inversion uses bounded Newton/bisection against fixed 8/16-panel Richardson estimates. Exact nominal node hits can produce zero residual while the accumulated station still has integration error. The README documents this distinction. I found no separate inversion defect in the supplied cases.

### Hairpin path converter

I inspected `tools/calibration_hairpin_path_lab/calibration_hairpin_path_source.gd:102–171,212–555,565–754,914–1082` and `calibration_hairpin_path_checks.gd:231–327,782–1102`. The gate check detects duplicates before dictionary insertion. The run check tracks all IDs before selecting `drift_entry` and `grip_entry`. The supplied case tries altered entries before and after the legitimate entries for both collections and checks the same named refusal and a null path. It also checks an identical gate duplicate and a duplicate spare gate ID.

The previous scalar checks still require present, numeric, finite values before comparing authored values. The comparison run is required and has its own speed and heading validation. Raw sample ownership now checks section and surface against unexpanded recorded intervals. Both near-join borrowing cases refused, and the two genuine equal-station, equal-position join pairs passed raw validation. Filtering retained the preceding section’s copy and dropped the following copy, yielding 156 unique path samples from 158 raw samples. The overlap finding concerns altered section records. These are converter and fixture checks. No physical 18 m/s hairpin run was performed.

### OPEN transported frame

I inspected `src/course/road_transport_frame.gd:159–275,288–412,429–466,708–945` and `tools/road_frame_lab/road_frame_checks.gd:441–737`. The implementation seeds from world up with a deterministic right-axis fallback near vertical. It transports between successive tangents using the cross/dot shortest rotation, refuses near reversal, then re-orthonormalizes and checks coherence. The next step transports the unbanked frame. Authored positive bank rolls canonical road-right down and does not accumulate. Frames preserve station and surface metadata, use `Basis(right, up, -forward)`, and expose copied containers.

The seven executed cases covered straight zero bank, graded and banked transport, return to authored zero bank, near-vertical rapid grade, deterministic repeat and copy isolation, malformed inputs, and explicit closed-loop refusal. I found no blocking defect in the bounded OPEN component. The fallback can change seed roll across two separately authored starts on opposite sides of its alignment threshold. The choice is deterministic and occurs only at the start.

## Plan alignment, optional improvements, and missing evidence

- **M2.1 still has open integration requirements.** `docs/TECHNICAL_DESIGN.md:115–119` calls for smooth width, banking and surface transitions and shared output for rendering, collision and other consumers. The sampler interpolates width and bank in Bézier parameter and assigns a discrete surface ID. Shared endpoints provide value continuity where authored consistently, with no general guarantee of smooth derivatives or blended surface transitions. `grade_dy_ds` is the vertical component of the unit tangent. The plan’s 12% rise/run target requires a horizontal-run calculation and a vertical-tangent policy when it is enforced. `PLAN.md:87` includes mesh and collision baking beyond this packet.
- **Optional numerical follow-up.** Before building strips and collision from these samples, define the supported coordinate and spacing envelope. At large offsets, distinct stations can quantize to coincident output positions. A total just above a spacing multiple can also leave a very short final edge. Preserve exact endpoint and boundary semantics when deciding how downstream consumers handle those edges. Independent position and station references would add coverage beyond the inversion residual.
- **Evidence boundaries.** `PLAN.md:78` requires physical calibration evidence that the provisional hairpin path lab has yet to establish. This review covers no closed-loop residual-roll correction, mesh or collision seams, course acceptance, physical handling, sweeper, baker, reward-C, wall policy, or separate road-source mantissa-decoder remediation. The candidate was reviewed as an immutable archive. No PR, CI, or merge status was established in this review.

**No whole M1, M1.7, M2, or M2.1 gate is approved. No visual, audio, hardware, or rights gate is approved.**