# Independent Roadstorm geometry recheck

**Candidate** `bf4b2d5afecea5fb1cb4ed2e72beff04edee3d89`  
**Prior checkpoint** `9751e567d3ebe6a60882e05ec9e84a346977b049`

| Scope | Verdict | Independent evidence |
|---|---|---|
| M2 arc sampler | **Scoped pass.** The exact-975 changes-required finding is cleared. | 10 of 10 cases, 631 checks. A below-floor request refuses. Both accepted tightened requests report estimates within budget. The supplied default and translated controls still pass. |
| Provisional M1 hairpin converter | **Scoped pass.** The prior adjacent-section overlap finding is cleared. | 10 of 10 cases, 544 checks. Overlap plus relabeling and a small gap refuse. Both legitimate join pairs survive validation and produce 156 unique path samples from 158 raw samples. |
| OPEN-road transported frame | **Scoped pass with the corrected arc dependency.** | 7 of 7 cases, 1,773 checks. The OPEN component builds successfully and explicitly refuses closed input. |
| Physical hairpin, closed-loop frame closure, mesh and collision | **Not verified.** | The supplied geometry labs provide no evidence for these capabilities. |

No blocking source finding remains in the reviewed scope. The direct runs are environment-qualified, and exact-model launch attribution still needs the coordinator’s record.

## Reviewer identity, independence, and archive integrity

I performed the review in the OpenAI Codex CLI session assigned **GPT-6.2 Sol** (`gpt-6.2-sol`). The available `codex --version` reported `codex-cli 0.171.0`. The packet identifies the intended model and OpenAI route. The effective bf4 launcher arguments and provider override were unavailable from inside the session. `ps` was denied, and the readable user-config default `gpt-6-sol` does not establish this invocation’s selection. The tracked exact-975 decision records `codex exec --ignore-user-config -m gpt-6.2-sol …` for **975**. Credit for the exact **bf4** model/provider invocation requires the corresponding bf4 launch record. Even that record would establish the selected route and model alias only. The serving revision is unavailable to me.

I read both tracked prior reports, `review/implementation/m2-arc-hairpin-frame-recheck-gpt-6-2-sol-9751e56.md` and `review/implementation/m2-arc-hairpin-frame-recheck-opus-5-5-9751e56.md`, and the tracked decision `docs/evidence/m2-arc-hairpin-frame-recheck-975-decision-20261128.md`. I used only this packet for the current review. I read no concurrent Opus packet or report, spawned no agents, made no source edits or Git mutations, and created or ran no new probes.

- `shasum -a 256 -c source.tar.sha256` passed. The archive SHA-256 is `fe275b910fa7fa422733c06dbd1ac9f1a16cc471c04a5d90983076cd76a5dda3`.
- `cat source-sha.txt` and read-only `git get-tar-commit-id < source.tar` both returned `bf4b2d5afecea5fb1cb4ed2e72beff04edee3d89`.
- I extracted the tar into private scratch and compared it recursively with `source/`. The trees matched, and I removed the scratch extraction. Before import, `diff -qr source private/build` found no differences. Both were plain trees without `.git`. After validation, only `.godot/` and generated `.gd.uid` additions appeared in `private/build`.

## Execution and results

I ran the following from `private/build`. The logs and structured summaries are in `private/results/`.

```sh
private_dir="$(cd .. && pwd -P)"
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
    timeout -k 5 120 "$engine" "$@" >"$private_dir/results/$label.log" 2>&1
  printf '%s rc=%s\n' "$label" "$?"
}

run_engine version --quit-after 1 --version
run_engine import --headless --path "$PWD" --import --quit-after 1
for lab in road_sampling_lab calibration_hairpin_path_lab road_frame_lab; do
  run_engine "$lab" --headless --fixed-fps 60 --path "$PWD" --quit-after 1 \
    --script "res://tools/$lab/validate_$lab.gd" \
    -- --summary-out="$private_dir/results/$lab.json"
  run_engine "$lab-failure" --headless --fixed-fps 60 --path "$PWD" \
    --quit-after 1 --script "res://tools/$lab/failure_probe.gd"
done
```

| Invocation | Exit | Result |
|---|---:|---|
| `--version` | 0 | `4.7.2.stable.official.ed1daf0bf`, matching `tools/toolchain/pin/engine.txt:27` |
| Headless import | 0 | Private import cache generated |
| Road sampling validator | 0 | `pass:true`, 10/10 cases, 631 checks, 0 failed |
| Hairpin path validator | 0 | `pass:true`, 10/10 cases, 544 checks, 0 failed |
| OPEN frame validator | 0 | `pass:true`, 7/7 cases, 1,773 checks, 0 failed |
| Each supplied deliberate failure probe | 3 | `pass:false`, 2 checks, 1 intentional assertion failure each |

All seven headless logs contained the same `ERROR: Condition "ret != noErr" is true. Returning: ""` from `get_system_ca_certificates (platform/macos/os_macos.mm:1035)`. Import also warned that the nested `tools/tick_probe` project would be ignored. There were no `SCRIPT ERROR`, parse errors, script-load failures, or timeouts. The complete case lines, matching JSON summaries, and deliberate exit codes establish that the scripts ran. The CA lookup diagnostic would trigger the supplied wrappers’ strict `ERROR:` log filters. These results reproduce the claimed counts on the exact candidate through the direct GDScript entry points. Wrapper status, overlay construction, and the historical old-source negative runs were not independently reproduced. I verified the installed binary’s version at the specified path. The original publisher archive digest was outside this recheck.

## Arc sampler

I inspected `src/course/road_arc_sampler.gd:352–472` for option dispatch, span records, chaining, and error aggregation, `:747–998` for the floor, subdivision, padded acceptance and accumulation, `:1034–1120` for the scalar bracket and chord, `:1121–1239` for inversion, and `:1392–1437,1664–1776` for the option range and scalar arithmetic. I inspected the corresponding contracts in `tools/road_sampling_lab/README.md:120–170` and the regressions in `tools/road_sampling_lab/road_sampling_checks.gd:1049–1084,1088–1455`.

The corrected leaf compares the same quantity it reports, `max(distance to either bracket endpoint) + roundoff_slack`. Child budgets halve on subdivision. The span therefore gets one requested budget, distributed among its leaves, and the table sums the reported estimates of all spans. **The default 1 mm is a per-span budget.** A multi-span table can legitimately report more than 1 mm. The endpoint chord times `1e-12` is an early floor for the sampler’s own reporting allowance. It does not certify the minimum achievable forward error. A request above the chord floor may still exceed the available numerical or subdivision budget and receive a structured refusal.

For the analytic diagonal with 24,576 m on each of two axes, the chord is approximately `34,755.71250888118 m`, yielding a floor of `3.475571250888118e-8 m`. The supplied `1e-8 m` request returned `precision_unreachable`, with no table and the expected floor diagnostics. Requests of `5e-8 m` and `1e-6 m` both accepted and reported `3.475571250888118e-8 m`. The default diagonal differed from `24576√2` by about `7.276e-12 m`. The changed branch directly addresses the old false success: the historical acceptance compared the unpadded distance while returning the padded estimate. The exact-bf4 lab verifies the new behavior. The claimed old-source failure remains historical evidence from the prior review and coordinator.

| Default-option control | Absolute discrepancy against lab reference, m | Reported estimate, m |
|---|---:|---:|
| Analytic diagonal | `7.276e-12` | `3.476e-8` |
| Translated road1 | `1.071e-7` | `6.629e-4` |
| Translated road2 | `8.335e-9` | `4.453e-4` |
| Translated hook | `7.960e-7` | `4.454e-4` |
| Prior quadratic counterexample | `8.689e-5` | `5.735e-4` |

All 40 seeded default-option road-like spans accepted. Their largest measured discrepancy was `3.328e-5 m`, the largest reported estimate was `6.819e-4 m`, and the largest signed discrepancy minus estimate was `−3.082e-4 m`. The two non-dyadic straight controls also passed. I found no default-option regression or false success in the supplied cases.

The `2^53 m` prefix case now exercises the earlier refusal. The first span alone has a floor of roughly `9,007 m`, above every public request in `(0, 0.001] m`. Execution never reaches the subsequent positive `0.25 m` span or the global station advance guard at `road_arc_sampler.gd:431–454`. The guard remains present and checks strict advance. This fixture provides no runtime coverage of it on bf4.

The estimates apply to cubics through the stored `Vector3` components. Authored-coordinate quantization and output-position rounding are separate. The chord and control polygon bracket the arc in exact arithmetic. The implementation uses relative float64 padding and ordinary additions, with no outward-rounded proof or separate accounting for all leaf and global prefix accumulation. Inversion uses a separate fixed-panel estimate and residual against the nominal table. Passing those checks does not prove true station accuracy to the residual alone.

## Provisional hairpin converter

I inspected `tools/calibration_hairpin_path_lab/calibration_hairpin_path_source.gd:112–171,212–555,559–775,1053–1105`, plus the authored controls, ID checks, and ownership cases in `calibration_hairpin_path_checks.gd:231–337,782–1126,1315–1321`.

At `calibration_hairpin_path_source.gd:636–651`, each recorded end must equal the following start exactly before the filter assigns ownership. Individual record values still receive the authored-station tolerance check. Ownership uses unexpanded closed intervals, so exact adjacency confines dual membership to the shared boundary. The raw duplicate path checks order, position and section pairing, retains the previous section’s point, and skips the following copy when building the path.

The supplied overlap combined with an interior relabel, and the small recorded gap, both refused with the exact-join diagnostic. The near-join borrowed-tag negatives, legitimate duplicate pairs, scalar guards and duplicate gate/run ID cases also passed. This clears the specific malformed-record ownership finding. The authored 30 m approach, radius-30 m half-turn and 30 m exit are converter geometry. The provisional 18 m/s grip/drift entries are fixture data, and no vehicle ran them in this review.

## OPEN-road transported frame

I inspected `src/course/road_transport_frame.gd:159–275,288–412,429–466,708–945` and `tools/road_frame_lab/road_frame_checks.gd:441–737`. The frame consumes the exact candidate’s arc table, starts with a deterministic seed near vertical, transports the unbanked orientation by the shortest rotation between tangents, re-orthonormalizes, and applies authored bank separately. It carries station and surface data through and exposes copied containers. Near reversal and closed input have explicit refusals.

The seven supplied cases passed with bf4, including straight zero bank, graded and banked transport, return to authored zero bank, rapid grade near vertical, deterministic repeat and copy safety, malformed input, and explicit closed refusal. The arc lab’s closed sampling seam case verifies arc endpoints and seam metadata. It supplies no closed transported-frame residual-roll or seam-matching evidence.

## Ranked follow-ups and remaining gates

1. **Verification gap, exact reviewer attribution and strict runner status.** Attach the bf4 launcher record if the checkpoint requires verified `gpt-6.2-sol` and OpenAI selection. Preserve the distinction between the passing direct validator runs and the strict wrapper’s CA log gate. No hosted CI, PR, or merge status was established in this archive review.
2. **Low, numerical contract and coverage.** The table API could state explicitly beside its error fields that the caller’s tolerance is per span and that the table field sums the span estimates. A tightened, multi-leaf curved control would exercise budget splitting and summation more directly than the single-leaf analytic controls. If downstream code needs a strict stored-value cap or certified whole-course station error, define and test that contract with explicit treatment of accumulation. The current prefix fixture should continue to be credited only for early precision refusal.
3. **Low, downstream coordinate and spacing policy.** Before strip and collision consumers rely on spatial edge lengths, define their supported coordinate and spacing range. Strictly increasing stations can still yield coincident float32 positions at large offsets, and endpoint inclusion can produce a very short last edge. This review gives no mesh or collision result for either condition.

`docs/TECHNICAL_DESIGN.md:115–119` calls for smooth width, bank and surface transitions and shared samples for downstream consumers. The sampler interpolates width and bank in Bézier parameter and carries discrete surface IDs. That preserves compatible endpoint values and leaves smooth derivative and surface-transition policy open. `grade_dy_ds` is the unit tangent’s vertical component. Enforcing the design’s 12% rise-over-run target requires a horizontal-run calculation and a policy for vertical tangents. `PLAN.md:78–94` also leaves physical M1 calibration, shared consumer output, chunked mesh and collision baking, course validation, and closed-loop frame closure beyond this packet. The separate road-source parser repairs were outside the reviewed scope.

**No whole M1, M1.7, M2, or M2.1 gate is approved. No visual, audio, hardware, performance, or rights gate is approved.**