# Scoped recheck: M2 road-source numeric-spelling repairs, candidate b035800

- **Date:** 2026-11-28, about 08:00 UTC (`date -u` at the end of the engine runs: Sat Nov 28 08:03:46 UTC 2026).
- **Reviewer:** Claude Opus 5.5 in Pi, with `PI_PROVIDER=venice` and `PI_MODEL=claude-opus-5-5` (reasoning level `medium`, session `01a22129-…`).
  - **Identity limits:** this attribution comes only from the runtime environment variables and the harness identity statement. Nothing attests the model cryptographically. The Venice route forwards requests to a third-party inference provider, and I cannot verify which weights served this session.
- **Candidate:** `b0358007e5bd685026304f1118a1d5dfc4260beb`, from `source-sha.txt` and from `git get-tar-commit-id < source.tar`. This is not live HEAD.
- **Independence:** I did not read the concurrent Sol packet or report. I spawned no agents and made no Git operations, branches, worktrees or clones. I edited no source or tracked files. I wrote only this report and private scratch under `private/`.
- **Scope:**
  - `src/course/road_source.gd`
  - `tools/road_source_lab/road_source_checks.gd`
  - `tools/road_source_lab/README.md`
  - This review covers only the JSON-text numeric-spelling contract of the road-source parser. It makes no M2, M2.1, course, geometry, gameplay, audio, visual, hardware, rights or release claim.
- **Parser verdict: PASS for the scoped numeric-spelling repairs.**
  - **Pass:** both prior exact-f199 counterexample families are closed. Every supported equivalent spelling I tested decodes to a nonzero value at the correct magnitude. I found no new acceptance of malformed JSON.
  - **Changes required:** none blocking.
  - **Not verified:** listed in "Missing evidence and capability limits" below.

## Archive and source integrity

| Check | Result |
| --- | --- |
| `shasum -a 256 source.tar` | `c533f5338ceaa444f125f3c7f28cc9017100953bf56d8674fc9961943191c0c8`, which matches `source.tar.sha256` |
| `git get-tar-commit-id < source.tar` | `b0358007e5bd685026304f1118a1d5dfc4260beb`, which matches `source-sha.txt` |
| Extracted `source.tar` to private scratch, then `diff -r` against `source/` | identical |
| `diff -rq` of the extraction against `private/build` before import | identical |
| `private/build` after the engine runs | Only additions: `.godot/` and the generated `*.gd.uid` files. No tracked file was modified. |
| `.git` in the archive | absent (0 entries) |

SHA-256 of the three owned files. Each value was byte-identical in `source.tar`, `source/` and `private/build`:

- `src/course/road_source.gd`: `0a6de2a92b5bf28fd6b78ca518e5eb0f525a4da1154670aaf98000542cbb1e88`
- `tools/road_source_lab/road_source_checks.gd`: `a40aa1815fa787787ae199381837e61b1223055519ae416f1959f1795918b4d1`
- `tools/road_source_lab/README.md`: `398aa4773e3a1ca7ddda13274f121a9d3bdd54020a641715a281f216edb205a4`

The coordinator's recorded overlay hashes are not in this archive. I can confirm that all three copies match each other, but I cannot check them against the coordinator's values.

## Prior material read before evaluating the repairs

These documents are tracked in the archive:

- `review/implementation/m2-road-source-numeric-recheck-opus-5-5-f199089.md`. Finding 1: the mantissa window silently drops significant digits, for example `0.000000000000000025e17` becomes 2.0.
- `review/implementation/m2-road-source-numeric-recheck-gpt-6-2-sol-f199089.md`. This is the short verbatim Sol final message: two paths decode to zero, including a bank authored as 10.
- `docs/evidence/m2-road-source-numeric-recheck-f199-decision-20261128.md`. It accepts both findings as blocking: the mantissa guard (`cd4cdd4`) and the adjusted-exponent underflow guard (`1.0e-308`, which decodes to 0).
- `docs/STATUS.md` (around lines 719–741) and `docs/IMPLEMENTATION_LOG.md` (around lines 90–105) for the context of the road-source rounds.

## Files and lines inspected

**`src/course/road_source.gd`**

| Lines | Content |
| --- | --- |
| 406–428 | `_StrictJsonPreflight` class documentation, including the three numeric-spelling limits |
| 472–503 | Constants and their rationale: `SUPPORTED_EXPONENT_ABS_MAX` 308, `SUPPORTED_EXPONENT_DIGIT_MAX` 4, `SUPPORTED_MANTISSA_DIGIT_MAX` 18, `SUPPORTED_ADJUSTED_EXPONENT_MIN` -308 |
| 511–730 | `validate`, the object, array and value state machines, and literals. Every number at any depth goes through `_consume_value` → `_parse_number`. |
| 732–814 | `_parse_number`: mantissa and fraction digit counting, the saturating exponent, then the exponent-magnitude, exponent-digit, mantissa and adjusted-exponent refusals, in that order |
| 1128–1225 | `parse_document` |
| 1232–1250 | `parse_json`: runs the preflight first, then `JSON.parse`, then `parse_document` |
| 1315–1365 | `_parse_knot`: width band and bank finiteness |
| 1450–1496 | `_read_vector` (float32 conversion and finiteness checks) and `_read_number` |

**`tools/road_source_lab/road_source_checks.gd`**

| Lines | Content |
| --- | --- |
| 22–113 | `Case` helpers. `refuses` checks the code, document, diagnostic and expected substring. |
| 126–136 | 11-case list |
| 214–219 | `replace_once` |
| 1104–1251 | `_case_exponent_decoder_bounds` |
| 1254–1448 | `_case_mantissa_window_bounds` |
| 1451–1567 | `_case_adjusted_exponent_decoder_bounds` |

**`tools/road_source_lab/README.md`**

| Lines | Content |
| --- | --- |
| 96–135 | Parser API and numeric limits |
| 206–238 | Coverage |
| 240–254 | Limits and the narrowing statement |

**Other material**

- Fixtures under `tools/road_source_lab/fixtures/`.
- `PLAN.md:87` and `docs/TECHNICAL_DESIGN.md:97,102`, read for plan context.
- Other callers: `tools/road_sampling_lab/road_sampling_checks.gd:196,207` and `tools/road_frame_lab/road_frame_checks.gd:205`.

## Commands and results

All engine calls used:

- the exact archive copy: `private/build` for the lab runs, and `private/scratch/probe`, an rsync copy of the imported build plus my `zz_probe/` scripts, for the probes;
- private `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and `XDG_DATA_HOME` directories under `private/`;
- `lockf -k -t 600 …/work/agents/coordinator/godot-test.lock`;
- `timeout -k 5 120` on every call;
- `--quit-after 1` on every call;
- the pinned binary `…/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot`, with local SHA-256 `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf`.

The wrapper is `private/run.sh`. Logs, probe sources and the fuzz corpus are in `private/logs/`. I checked every log for `ERROR` and `SCRIPT ERROR`, not only the exit status.

| Command | rc | Inspected result |
| --- | --- | --- |
| `--headless --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| `--headless --path . --import` | 0 | No ERROR or SCRIPT ERROR lines. `global_script_class_cache.cfg` contains `RoadSourceDocument` and `RoadSourceLabChecks`. |
| `--headless --fixed-fps 60 --path . --script res://tools/road_source_lab/validate_road_source_lab.gd` | 0 | 11 `ROAD_SOURCE_LAB_CASE` lines, all `pass:true`. Summary `"cases":11, "cases_passed":11, "checks":871`. `CHECKS_TOTAL=871 CHECKS_FAILED=0`. No ERROR lines. Per-case checks: open 25, closed 18, round-trip 24, identity 221, numeric/geometry 142, strict-JSON 97, exponent 90, **mantissa 127**, **adjusted-exponent 76**, mutation 28, span 23. |
| `--script res://tools/road_source_lab/failure_probe.gd` | **3** | `ROAD_SOURCE_FAILURE_PROBE … "pass":false`, `CHECKS_TOTAL=2 CHECKS_FAILED=1` |
| `zz_probe/opus_probe.gd` (targeted) | 0 | See below |
| `zz_probe/raw2.gd` (raw decoder characterization) | 0 | See below |
| `zz_probe/fuzz.gd` with `gen_tokens.py` and `check_fuzz.py` (6000-token differential) | 0 | See below |
| `zz_probe/long.gd` (200,000-digit mantissas) | 0 | Refused in about 57 ms each with the significand diagnostic |
| `zz_probe/rt.gd` (`JSON.stringify` interop) | 0 | See Finding 1 |

This confirms the coordinator's import rc 0, 11 cases / 871 checks and deliberate-failure rc 3 on the exact archive.

### Targeted probe (`opus_probe.gd`)

**Coverage.** Each negative token was placed in five document positions:

- width (open knot 0);
- bank (closed knot 2);
- anchor x (open knot 1);
- `handle_out` y (open knot 1);
- the unused open `handle_in` z (knot 0).

It was also placed in six wrappers:

- a bare root;
- the second element of a root array;
- a deep unknown nest `{"a":{"b":[1,{"c":[[tok]]}]}}`;
- an unknown key inside a real knot;
- an unknown document key;
- an unknown key inside a real `exception` object.

Every refusal had to return `INVALID_JSON_TEXT`, carry the precise substring and report a byte offset.

**1. Mantissa-window negatives: all refused at all 11 positions.**
- Diagnostic: `number significand has more than 18 digit characters at byte N`.
- Tokens: `0.000000000000000025e17`, `…E17`, `-…E+17`, `…e+17`, `1234567890123456789`, `-1234567890123456789`, `12.34567890123456789`, `0.0000000000000000001`, `1000000000000000000e-18`, `…E-18`, `0.0012345678901234567`, `-0.0000000000000000014E19` and `1234567890123456789012e-20`.
- The raw engine decode confirms what each refusal prevents, for example 2.0, 0.0, 12.345678901234567 and 0.00123456789012345.

**2. Adjusted-exponent negatives: all refused at all 11 positions.**
- Diagnostic: `unsupported number spelling: adjusted decimal exponent -309 is below the supported -308 lower bound at byte N`.
- Tokens: `1.0e-308`, `1.0E-308`, `-1.0e-308`, `-1.0E-308`, `0.01e-307`, `-0.01E-307`, `10.5e-308`, `1.7e-308`, `0.0e-308` and `-0.000E-306`.
- The raw engine decode of every nonzero token is 0.0.

**3. Exponent bounds remain.**
- `1e309`, `1E-309` and `-1e+309` are refused at every position. The raw engine decode gives inf, 0.0 and -inf.
- `12e4294967296` is refused. The raw engine decode gives 12.0.
- `1e00001` and `1E+00012` are refused by the digit limit.

**4. Equivalent spellings decode to the right value, not merely `ok`.** I compared each decoded value, as a nonzero ratio, against the expected value.
- **2.5:** all decoded exactly to 2.5 in width, bank and all three vector positions:
  - `2.5`, `25e-1` and `25E-1`;
  - `0.25e1` and `0.25E+1`;
  - `2.5e0` and `2.5E-0`;
  - `250000000000000000e-17` (an 18-digit integer);
  - `0.00000000000000025e16` and `0.00000000000000025E+16` (18-digit leading-zero forms);
  - `2500E-3` and `0.0025e3`.
- **-14:** these all decoded exactly to -14.0 in bank and the three vector positions:
  - `-14` and `-14.0`;
  - `-1.4e1` and `-1.4E+1`;
  - `-140E-1` and `-0.14e2`;
  - `-0.0000000000000014e16` and `-14000000000000000e-15`.
- **±50:** `50000000000000000e-15` and `0.5E+2` decode to 50 in width and anchor; `-0.5e2` decodes to -50 in the vectors.
- **Tiny bank values (double):** each decoded nonzero with the expected ratio to 1e-308:

  | Token | Ratio to 1e-308 |
  | --- | --- |
  | `1e-308` | 1 |
  | `-1e-308` | -1 |
  | `0.1e-307` | 1 |
  | `-0.1E-307` | -1 |
  | `1.0e-307` and `1.0E-307` | 10 |
  | `12.5e-307` | 125 |
  | `0.00000000000000001e-291` (18 digits, adjusted -308) | 1 |
  | `1e-0308` | 1 |
- **18-digit spellings at adjusted -308 are accepted and decode correctly:**
  - `123456789012345678e-308` → 1.2345678901234568e-291
  - `99999999999999999e-308` → 1e-291
  - `1.00000000000000000e-291` → 1e-291
  - `123456789.123456789e-299` → 1.2345678912345678e-291
  - My probe had first mis-sorted these four as negatives. The "anomaly" lines in `opus_probe.log` for them, and for `10e-309`, are my probe's classification errors. The `val=0.0` text in those lines is GDScript `print` formatting of tiny floats; `raw2.log` shows the true values. `10e-309` is refused by the pre-existing exponent bound.
- **Large values:**
  - `1.7976931348623157e308`, `17976931348623157e292` and `-1.7976931348623157E+308` are finite and accepted as bank.
  - `1.8e308` and `9e308` decode to inf and are refused downstream as non-finite.
- **Zero spellings:** `-0`, `0`, `0e0`, `0E0`, `0.0` and `-0.0E+0` are accepted as 0.

**5. No new malformed-JSON acceptance.** All of these were refused with `INVALID_JSON_TEXT`:
- `1.`, `.5`, `01`, `-`, `-01`, `+1`, `1.e5`, `--1`, `-.5`;
- `1e`, `1e+`, `1E-`, `1ee5`, `1e+-5`, `1e5e5`;
- `0x10`, `1E5.0`, `1 2`, `1..2`, `0.5.`;
- `Infinity`, `NaN`, `-Infinity`;
- the full-width digit `１`.

Exponent-like text inside strings, such as `"1.0e-308"` and `"0.000000000000000025e17"` in `feature_tags`, remains string content and is accepted.

**6. Vector float32 storage.** Bank keeps double values. Vector components are stored as float32:
- `1e-308` and `1e-50` become 0.0, the nearest float32;
- `1e-45` and `1e-38` survive as float32 subnormal or normal values.

This is the engine's Vector3 representation, not the text decoder. The result is the nearest representable value, which is numerically appropriate.

### Differential fuzz (6000 seeded random tokens)

**Method.**
- `gen_tokens.py` (seed 20261128) generated tokens covering:
  - mantissas of 1 to 21 digit characters;
  - optional leading fractional zeros;
  - exponents absent, or in [-320, 320], biased toward [-310, -280];
  - zero-padded exponents;
  - mixed `e`/`E`, optional `+`, and optional negative sign.
- For each token, Godot recorded:
  - whether `parse_json` passed the preflight (a bare number then refuses as `NOT_AN_OBJECT`, otherwise as `INVALID_JSON_TEXT`);
  - the raw `JSON.parse_string` value.
- `check_fuzz.py` compared the results with an independent model. It used Python `Decimal` for exact values and the documented rule for acceptance:
  - mantissa digits ≤ 18;
  - |exponent| ≤ 308;
  - exponent digits ≤ 4;
  - explicit exponent minus fractional digits ≥ -308.

**Results.**
- The preflight decision matched the documented rule for **6000 of 6000** tokens.
- **3300 tokens were accepted.** In 0 cases was a nonzero value lost to zero, or a value inaccurate beyond 1e-14 relative. Overflow to inf happened only when the true value exceeds DBL_MAX, and finite-range values decoded finite.
- The maximum relative error among accepted tokens was **3.6e-16** (`6.0116315e256` → `6.011631500000002e+256`). The decoder is not correctly rounded but stays within a few ULP.
- **2700 tokens were refused:**
  - **Mantissa limit (2160):** 38 would have decoded wrong, 111 to zero or inf, and 2011 within 1e-13. The mantissa rule is conservative.
  - **Adjusted-exponent limit (247):** all 247 would have decoded to zero or inf. The adjusted bound is tight: below -308 the decoder's divisor always overflows.
  - **Exponent limits (293):** 184 would have decoded to zero or inf, and 109 within 1e-13.

### Why the guards are sufficient (source reasoning, consistent with the probes)

Observed decoder behaviour matches the classic `strtod` that Godot uses for `String.to_float` and the JSON reader:

- It keeps only the first 18 mantissa digit characters and sets `fracExp = decPt − min(mantSize, 18)`.
- It computes `exp = fracExp ± explicit`.
- It builds `10^|exp|` from products of 10^(2^i) and then multiplies or divides.

Under the candidate's guards:

- **No truncation.** With mantissa ≤ 18, nothing is truncated and `exp` equals the lexical adjusted exponent.
- **Finite divisor.** With adjusted ≥ -308, the divisor is at most about 1e308 and finite, so a nonzero mantissa (≥ 1) yields at least about 1e-308. It is never zero.
- **Inf only above DBL_MAX.** Positive adjusted exponents are at most +308. The only extreme result is inf, which every authored field refuses downstream, and unknown positions are refused by `parse_document` anyway.
- **No exponent wrap.** The decoder's exponent integer cannot wrap with at most 4 digits.

The guards run inside `_parse_number`, which every number token reaches through the generic `_consume_value`. This covers any depth, any key (known or unknown) and the root.

## Ranked actionable findings

No blocking findings.

1. **Low (contract interoperability, documentation). Godot's own full-precision JSON writer can emit spellings this parser refuses.**
   - `JSON.stringify(0.0006666666666666666, "", false, true)` produces `0.0006666666666666666`, which has 19 digit characters. `parse_json` refuses it with the significand diagnostic (`rt.log`).
   - The default-precision writer emits `0.000666666666666667`. That is accepted but loses precision.
   - No road-source text writer exists at this SHA. The lab round trip goes through `to_dictionary` → `parse_document`, not text.
   - A future authoring or export tool built on `JSON.stringify(full_precision=true)` would produce files that its own parser rejects for some values between 1e-4 and 1e-3. The candidate refuses these fail-closed with a precise diagnostic. It does not accept them with a wrong value.
   - **Suggestion:** add one README sentence on writer guidance, for example "emit at most 17 significant digits in exponent form, or otherwise keep significands within 18 digit characters". Alternatively, record a canonical-writer requirement for the later M2.1 tooling. This does not block the parser.

2. **Low (lab coverage). The checks do not pin some guard positions that my probes verified.**
   - `_case_adjusted_exponent_decoder_bounds` tests its negatives only in bank and nested unknown positions. It has no width or vector negative and no negative-sign negative such as `-1.0e-308`.
   - `_case_mantissa_window_bounds` has no uppercase `E` negative.
   - No positive control covers an 18-digit significand exactly at adjusted -308, such as `123456789012345678e-308`.
   - The implementation is position-agnostic and my probe verified all of these, so this is regression-hardening only.

3. **Low (diagnostic consistency).** Only the adjusted-exponent refusal begins with `unsupported number spelling:`.
   - The significand message (`number significand has more than 18 digit characters`) and the exponent messages are precise and carry byte offsets.
   - The wrapper's prefix ("does not satisfy the road-source strict JSON text contract") correctly avoids calling the token malformed.
   - A uniform `unsupported number spelling:` prefix would make the narrowing class machine-recognizable. This is optional.

4. **Informational (documented narrowing side effects).**
   - Values in (1e-308, 1e-307) with two or more significant digits cannot be spelled at all. For example, `1.7e-308`, `17e-309` and `0.17e-307` are all refused, and the raw decoder would give 0.0 for `1.7e-308`.
   - Mantissas longer than 18 characters are refused even when the decoder would be ULP-close: 2011 of 2160 such fuzz refusals. Examples are `1234567890123456789012e-20` and the leading-zero 17-significant-digit output of `%.17g`.
   - `0.0e-308` (zero) is refused.
   - All of these are explained by the README "Limits" paragraph (lines 249–254) and the class documentation. None matters for authored road values.
   - I judge this narrowing justified, not unjustified: it is the simple, bounded rule that the prior Opus report offered as acceptable, and the adjusted bound is exactly tight.

## Plan mismatches

None found within scope.

- `PLAN.md:87` (M2.1 road spline format) and `docs/TECHNICAL_DESIGN.md:97` ("editable source recipes can be JSON/text") specify no numeric-spelling requirements that the narrowing would violate.
- The prior f199 wording concern, which described the limits as "malformed grammar", is addressed. README 100–117 and 249–254 and `road_source.gd` 416–427 now describe the limits as deliberate narrowings of valid JSON spellings.

## Optional improvements

- `replace_once` (checks 214–219) silently returns the unmodified text when the needle is missing.
  - Refusal tests would then fail loudly, and most acceptance tests compare a changed value.
  - A missing-needle assertion would remove the residual risk of a vacuous acceptance check.
- `tools/road_sampling_lab/road_sampling_checks.gd:196` and `tools/road_frame_lab/road_frame_checks.gd:205` still decode fixtures with the permissive `JSON.parse_string` and then call `parse_document`. That bypasses the numeric-spelling preflight.
  - The inputs are committed fixtures and these files are outside this scope.
  - Routing them through `parse_json` would keep one text contract.
- The 1e-14 decode accuracy is at the decoder level. If a later consumer needs correctly rounded doubles, `JSON.parse` would have to be replaced. Nothing in scope needs this.

## Missing evidence and capability limits

- **Not run:** the frozen exact-overlay runner `tools/road_source_lab/run_validation.sh`.
  - It requires `git archive HEAD` from a checkout. The archive has no `.git`, and Git mutation and clones were out of bounds.
  - So I did not independently verify the coordinator's "frozen exact-overlay" runner rc or its overlay-manifest hashes.
  - Its byte match of the three owned files is consistent with my hashes, but the coordinator's recorded values are not in the archive for comparison.
- **Engine binary:** only the local SHA-256 and the version string were recorded. I did not verify it against the publisher archive digest.
- **Decoder source:** I did not read the engine C++ source. The decoder model comes from observed behaviour (`raw2.log`, the fuzz differential) and matches the classic `strtod` algorithm.
- **Scope of the evidence:** hosted CI was not consulted. There was one host (macOS) and one headless engine process cohort.
- **Model identity:** environment-reported only, as described at the top.
- **Not covered:** M2 or M2.1 acceptance, geometry, sampling, frames, course, gameplay, audio, visual, hardware, rights and release. No whole-milestone approval is implied.

## Summary

| Item | Status |
| --- | --- |
| Archive SHA-256 and commit ID, source/ and private/build identity | Verified |
| Prior Opus mantissa-window counterexamples (width, bank, vector, nested, root, uppercase, signed) | **Closed.** Refused before decode with a precise diagnostic. |
| Prior Sol `1.0e-308` underflow family (bank, width, vector, nested, root, uppercase, signed) | **Closed.** Refused with `unsupported number spelling: adjusted decimal exponent …`. |
| Supported equivalent spellings decode nonzero and at the right magnitude | Verified: targeted probe plus 3300 fuzz acceptances, max relative error 3.6e-16, none lost to zero |
| New malformed-JSON acceptance | None found |
| Unjustified contract narrowing | None. The narrowing is documented and bounded. Note the Finding 1 writer interop. |
| Coordinator claims: import rc 0, 11 cases / 871 checks, failure rc 3 | Reproduced independently on the exact archive |
| Frozen-runner rc and overlay-manifest comparison | Not verified |
| **Parser verdict (scoped)** | **PASS.** Changes required: none blocking. Not verified: as listed above. |
