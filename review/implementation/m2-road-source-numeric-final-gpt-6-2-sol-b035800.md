# Roadstorm M2 road-source parser review

**Verdict: Pass for the scoped JSON-text parser correction** on candidate `b0358007e5bd685026304f1118a1d5dfc4260beb`. Both exact-f199 numeric decoder findings are closed. The pinned Godot import exited 0, the supplied validator passed all 871 checks across 11 cases, and the deliberate failure exited 3. I found no blocking residual in the reviewed JSON-text path.

## Reviewer identity and candidate integrity

This was the assigned OpenAI GPT-6.2 Sol review through Codex CLI. The runtime reported Codex CLI `0.171.0-alpha.13`, and the packet recorded a Codex thread start. The assigned model/provider route was OpenAI `gpt-6.2-sol`. The packet did not expose the launcher's complete argument vector or a backend model attestation, and sandboxed process inspection was denied. The model/provider attribution is therefore the declared invocation, with the CLI version independently visible in the runtime.

`shasum -a 256 -c ../../source.tar.sha256` returned `OK` for `c533f5338ceaa444f125f3c7f28cc9017100953bf56d8674fc9961943191c0c8`. Both `../../source-sha.txt` and the embedded commit extracted by the read-only `git get-tar-commit-id < ../../source.tar` returned `b0358007e5bd685026304f1118a1d5dfc4260beb`. I extracted the tar to disposable private scratch and compared it recursively with `source/`. I also compared `source/` with `private/build` before import. Both comparisons matched. After the run the differences were Godot-generated `.godot/` data and `.gd.uid` sidecars.

I read the tracked exact-f199 Sol and Opus reports under `review/implementation/` and the reconciliation at `docs/evidence/m2-road-source-numeric-recheck-f199-decision-20261128.md`. The tracked Sol report is a short verdict. The decision records its exact underflow trigger and the coordinator's reproduction. This review used the packet's archives and supplied lab independently of the concurrent Opus review. No source edits, Git mutations, new probes, or delegation.

## Inspected implementation and results

- **Shared number path.** `src/course/road_source.gd:512–707` routes root, object-value and array-element numbers through the same `_parse_number` before schema validation. This covers `width_m`, `bank_deg`, all axes of `anchor`, `handle_in` and `handle_out`, and numbers in nested schema-unknown data. Quoted strings follow the string scanner. The supplied lab exercises all three vector fields and root, array and nested positions for the mantissa guard. The adjusted-exponent regressions exercise bank and nested positions at runtime. Its coverage of the other positions follows from inspecting the shared dispatch.
- **Long significands.** `road_source.gd:732–806` counts all integer and fractional mantissa digit characters before decode. This catches `0.000000000000000025e17`, the signed bank case `-0.0000000000000000014e19`, and the prior anchor and handle cases. The 127-check mantissa case at `road_source_checks.gd:1254–1450` verified structured refusals and accepted `0.25e1`, `0.00000000025e10`, and the 18-digit boundary `0.00000000000000025e16` at 2.5. It also checked exact equality for bank `0.30000000000000004`.
- **Adjusted-exponent underflow.** `road_source.gd:763–814` applies the signed explicit exponent and subtracts every fractional digit. Both `1.0e-308` and `1.00e-307` have an adjusted exponent of −309 and receive `INVALID_JSON_TEXT` with an unsupported-spelling diagnostic and byte offset before the engine decode. `1e-308`, `0.1e-307` and `1.0e-307` have an adjusted exponent of −308. The 76-check case at `road_source_checks.gd:1451–1569` verified that these banks and their uppercase forms remain finite and nonzero, with ratios of 1, 1 and 10 against `1e-308`. It also verified ordinary nonzero width spellings such as `1.2e+1` and `0.12E+2`, and signed uppercase bank `-1.2E+1` at −12. The separate 90-check explicit-exponent case retained coverage of oversized and padded exponents.
- **Malformed text and downstream validation.** I inspected delimiter and end-of-input checks, duplicate-member handling, string escapes and numeric grammar at `road_source.gd:512–941`, then the preflight-to-engine handoff at `1232–1250` and knot conversion at `1315–1365` and `1450–1495`. The strict preflight case at `road_source_checks.gd:944–1103` passed 97 checks. I found no malformed-text bypass in that inspection. The lexical limits keep the exponent accumulator bounded, all accepted mantissa digits inside the decoder window, and the negative power-of-ten divisor within the supported range. Downstream checks still refuse nonfinite scalars and vector overflow. `parse_document` receives already-decoded values and has no access to their original spellings, as documented at `tools/road_source_lab/README.md:132–135`.

## Ranked findings and optional improvements

1. **Low, document the conversion boundary.** `road_source.gd:1450–1486` only checks finiteness after conversion to `Vector3`. A legal nonzero double such as `1e-308` can become exactly zero in a float32 vector component. For example, placing it on an otherwise zero axis of a fixture handle can leave the handle valid because the other axis still distinguishes it from its anchor. This is a source-derived storage conversion result. The tracked f199 Opus report also observed tiny bank values surviving while tiny vectors became zero. The candidate's documented vector rule is finiteness after conversion, so this is outside the corrected JSON decoder defect. Add an explicit README sentence and a lab assertion for the chosen behavior. If the source contract later requires preservation of nonzero coordinates, reject nonzero-to-zero conversion with the field and component index on both entry points.
2. **Low, tighten regression assertions.** The adjusted-exponent case checks the diagnostic in bank and nested values. Add one adjusted-exponent assertion for a vector component and one for the exact UTF-8 byte offset with non-ASCII text before the token. The shared scanner provides the position coverage today, and the existing mantissa test checks that a byte offset is present.
3. **Optional, keep text callers on `parse_json`.** The road-sampling lab's fixture loader and its `parse_document` call around `tools/road_sampling_lab/road_sampling_checks.gd:207` use the already-decoded path. The fixtures are controlled. Routing raw fixture text through `parse_json` would exercise the same lexical contract in that lab.

The spelling limits are conservative. For example, a harmless trailing zero can put a token above the 18-digit cap, and `0.0e-308` fails the adjusted-exponent floor despite denoting zero. `tools/road_source_lab/README.md:96–135` describes the limits as spelling restrictions and explains the decoder mechanism. I found no unjustified narrowing for the scoped authored format. An exhaustive guarantee of correctly rounded decimal conversion across all supported tokens would require separate evidence. The current assertions establish the reported behavior for the tested values.

## Commands and observed results

All engine commands ran from the packet's `private/build`. The wrapper below gives the exact engine arguments and environment. Output was captured separately for each call under `private/`.

```sh
root=/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm/work/agents/coordinator
godot="$root/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot"
lock="$root/godot-test.lock"
export HOME="$PWD/../home" TMPDIR="$PWD/../tmp"
export XDG_CACHE_HOME="$PWD/../xdg/cache"
export XDG_CONFIG_HOME="$PWD/../xdg/config"
export XDG_DATA_HOME="$PWD/../xdg/data"

engine() {
  /usr/bin/lockf -k -t 120 "$lock" timeout -k 5 120 \
    "$godot" --headless --quit-after 1 "$@"
}

engine --version
engine --import --path "$PWD"
engine --path "$PWD" --fixed-fps 60 \
  --script res://tools/road_source_lab/validate_road_source_lab.gd \
  -- --summary-out="$PWD/../road-source-summary.json"
engine --path "$PWD" --fixed-fps 60 \
  --script res://tools/road_source_lab/failure_probe.gd
```

| Call | Exit | Observed evidence |
| --- | ---: | --- |
| Version | 0 | `4.7.2.stable.official.ed1daf0bf` |
| Import | 0 | Scan and registration completed, including `RoadSourceDocument`. |
| Validator | 0 | `ROAD_SOURCE_LAB_SUMMARY` reported `pass:true`, 11 cases passed, 871 checks and zero failures. `CHECKS_TOTAL=871 CHECKS_FAILED=0`. The summary file was written. |
| Failure probe | 3 | `ROAD_SOURCE_FAILURE_PROBE` reported `pass:false`, two checks and the one deliberate failure. `CHECKS_TOTAL=2 CHECKS_FAILED=1`. |

The import and both scripts emitted the macOS system CA lookup diagnostic from `os_macos.mm:1035`. Import also emitted an editor ObjectDB snapshot-directory creation error and the nested `tools/tick_probe` project warning. These diagnostics were separate from script execution. I found no `SCRIPT ERROR` or other `ERROR:` lines. The private build accepted import writes and both scripts returned their expected structured output, so the editor snapshot error did not block parser validation.

## Plan alignment and evidence limits

I found no mismatch with the road-format portion of `PLAN.md:87` or the separation of authored source validation from T09 geometry validation in `docs/TECHNICAL_DESIGN.md:117,205`. The evidence is one independent, headless macOS run of the supplied lab against the immutable candidate. It reproduces the coordinator's stated import, validator and failure-control results. The coordinator's separate overlay assembly, hosted CI and frozen-source shell runner were outside this run. I verified the local binary version and recorded its SHA-256 as `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf`. Publisher archive verification was outside this review.

**No whole M2.1, M2, course, visual, audio, hardware or rights gate is accepted by this review.**