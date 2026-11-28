# Scoped recheck: M2 road-source exponent correction, candidate f199089

- **Date:** 2026-11-28 (about 07:00 UTC)
- **Reviewer:** Claude Opus 5.5, running in Pi (`PI_PROVIDER=venice`, `PI_MODEL=claude-opus-5-5`). There is no signed attestation of the model. The attribution comes from the runtime environment.
- **Candidate:** `f1990894531084f9f5623ecbe04651f39d425027`, from `git get-tar-commit-id < source.tar`
- **Prior reviewed candidate:** `63fa101a8d76ee951ef498866b18f27b8e053422`. That round had an Opus scoped pass and a Sol changes-required finding on exponent decoding. The coordinator's decision accepted that finding as blocking (`docs/evidence/m2-road-source-recheck-63fa-decision-20261128.md:7`).
- **Scope:**
  - `src/course/road_source.gd`
  - `tools/road_source_lab/road_source_checks.gd`
  - `tools/road_source_lab/README.md`. The brief's "README.md" means this lab README. The top-level `README.md` has no road-source text.
  - This review covers only the JSON-text numeric decoding contract. It does not cover M2 or M2.1 geometry or course acceptance.
- **Verdict:** **changes required**
  - Sol's exponent-wrap finding is closed.
  - A sibling defect remains in the same class and is reproduced below: valid, in-range JSON numbers decode to plausible wrong values because of the engine's mantissa window.

## Archive and source integrity

- `shasum -a 256 source.tar` gives `8fed8cfd0102a0ab911e15cbf2bac2aaa58a9b37b20780a252ae4ab0dfee2fde`, which matches `source.tar.sha256`.
- I extracted `source.tar` to private scratch and ran `diff -r` against `source/`. There were no differences. I deleted the scratch copy afterwards.
- The pre-created `private/build` copy also matched `source/` exactly (`diff -r`) before I imported it or added any probe.
- SHA-256 of the scoped files in the archive:
  - `road_source.gd`: `9a54863a…e6ae574`
  - `road_source_checks.gd`: `140fc4db…e21e5f5`
  - lab `README.md`: `639d4489…3767896`
- I did not read the concurrent Sol report (`../sol`).
- **Prior reports consulted** (tracked in the archive):
  - `review/implementation/m2-road-source-recheck-{gpt-6-2-sol,opus-5-5}-63fa101.md`
  - the 63fa decision file
  - `docs/STATUS.md:729` and `docs/IMPLEMENTATION_LOG.md:101`

## Files and lines inspected

- **`src/course/road_source.gd`:**
  - the preflight class documentation (406–420);
  - the exponent constants and their rationale (464–475);
  - `validate` and the state machines (483–690);
  - `_parse_number` (704–762), including the saturating exponent accumulator at 737–749 and the two refusals at 750–761;
  - `parse_document` (1076–1173) and `parse_json` (1179–1196);
  - `_parse_knot` (1261–1311), `_read_vector` (1396–1432) and `_read_number` (1436–1441).
- **`tools/road_source_lab/road_source_checks.gd`:**
  - the case list (around 132);
  - `_case_exponent_decoder_bounds` (1102–1249);
  - the 1e40 overflow controls (759–775).
- **Lab `README.md`:**
  - the parser API (80–117);
  - the run and runner contract (119–186);
  - coverage (188–209);
  - limits (211–218).
- **Other callers:** `tools/road_sampling_lab/road_sampling_checks.gd:174–193` decodes fixtures with `JSON.parse_string` and then calls `parse_document`. `src/course/road_arc_sampler.gd` only consumes documents.

## Checks actually run

All engine runs used:
- the exact archive copy `private/build`;
- private HOME, TMPDIR and XDG directories under `private/`;
- `lockf -t 600 work/agents/coordinator/godot-test.lock`;
- `timeout -k 5s <N>s` on every Godot call;
- the pinned binary `toolchain-m01/.../Godot` (local file SHA-256 `c7cccbf8…718ccf`).

The wrapper is `private/run.sh`. Logs and probe sources are in `private/logs/`.

| Command | rc | Result |
| --- | --- | --- |
| `--headless --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| `--headless --path . --import` | 0 | |
| `--script res://tools/road_source_lab/validate_road_source_lab.gd` | 0 | **9 cases, 668/668 checks, 0 failed**. The new case `exponent_decoder_bounds` ran 90 checks. |
| `--script res://tools/road_source_lab/failure_probe.gd` | **3** | The deliberate failure was detected. |
| `opus_probe.gd`, my independent probe | 0 | 189 probe lines. Results below. |
| `opus_probe2.gd` and `opus_probe3.gd` | 0 | Decoder mechanism and end-to-end width confirmation. `probe3` first failed with a GDScript type-inference parse error in my own probe. After the fix, `probe3b` ran cleanly. |

### Probe results

1. **Sol payloads closed.**
   - Tokens tested:
     - `12e4294967296`, `12e18446744073709551616`, `12e-4294967296`, `1e2147483648` and `1e4294967296`;
     - plus `-12e4294967296`, `12E+4294967296`, `12.0e4294967306` and a 35-digit exponent.
   - Each token went into five fields:
     - width;
     - bank;
     - anchor x on knot 1;
     - `handle_out` y on knot 1;
     - the unused open `handle_in` z on knot 0.
   - All **45/45** returned `invalid_json_text` with "number exponent magnitude exceeds the supported range [-308, +308]" and a byte offset.
   - The raw engine decode of the same tokens confirmed that they would otherwise wrap: 12.0, -12.0, 0.0, 1.0, 1.2 and 1.2e11.
   - Nesting and position did not matter. The giant exponent was refused as:
     - a bare root;
     - inside `[[[[...]]]]`;
     - in `{"a":{"b":[1,{"c":1e-4294967296}]}}`;
     - under a schema key;
     - as the second array element.
   - Exponent-like text inside strings (`feature_tags`, `exception.kind` and `exception.detail`) was correctly left as string content, and the document was accepted.
   - Exponents of 200,000 nines and of 200,000 zeros followed by 1 were both refused promptly: one by magnitude, one by the digit limit. The accumulator cannot overflow.
2. **Ordinary spellings are preserved.**
   - These forms in width, bank and anchor x all decoded to exactly 12.0: `1.2e1`, `1.2E1`, `1.2e+1`, `1.2E+1`, `120e-1`, `1200E-2`, `12e0`, `12e-0`, `12e+0`, `12e0000`, `1.2e0001`, `12000e-0003` and `0.12e2`.
   - `1e308`, `1e0308`, `9.9e307` and `1.7976931348623157e308` are accepted lexically. Each then gets its correct downstream outcome:
     - width: `bad_width`;
     - bank: accepted finite;
     - vector: `nonfinite_component` after float32 conversion.
   - `1.8e308` and `1000e306` decode to inf. They are refused as non-finite in all three fields.
   - `1e-308` and `1e-0308` are accepted. A bank keeps 1e-308; a vector component becomes float32 0.0.
3. **Lexical boundaries.**
   - Refused by magnitude: `1e309`, `1e-309`, `1e0309`, `1e3080`, `1e999` and `1e-999`.
   - Refused by the digit limit: `1e00001` and `1e+00012`.
   - `4.9e-324` (the smallest subnormal) is now refused. This is a documented contract narrowing, not an acceptance.
4. **Direct `parse_document` path.**
   - Decoded doubles cannot carry a wrapped exponent.
   - Width: 1e308, INF, NAN, 1e-308, `true` and `"12"` were all refused.
   - Bank: INF and NAN were refused. 1e308, -1e308 and 1e-308 were accepted, which matches the documented finiteness-only bank rule.
5. **New counterexample: the mantissa window.** See Finding 1.

## Ranked findings

### Implementation defects

1. **Medium, blocking: valid strict JSON with an in-range exponent still decodes to a plausible wrong value. It passes all downstream guards.**

   **Mechanism.** The pinned decoder (`JSON.parse`, the same as `String.to_float`) keeps only the first 18 mantissa digit characters, *including leading zeros after `0.`*. It discards the rest and then applies the exponent. So a `0.000…` mantissa with a compensating positive exponent loses its significant digits.
   - `opus_probe2`: `0.000000000000000025e17` → 2.0 (true value 2.5).
   - `0.0000000000000000012e18` → 0.0 (true value 1.2).
   - `0.0012345678901234567e4` → 12.3456789012345.

   **Reproduced end to end through `RoadSourceDocument.parse_json`** on the exact archive:
   - Open fixture, knot 0, `"width_m": 0.000000000000000025e17` (2.5 m): **accepted with width 2.0**. `0.000000000000000012e17` (1.2 m): **accepted with width 1.0**. Both are inside the [1, 100] band.
   - Closed fixture, knot 2, `"bank_deg": -0.0000000000000000014e19` (-14°): **accepted with bank 0.0**.
   - Open fixture, knot 1:
     - `anchor[0] = 0.00000000000000000050e20` (50 m): **accepted as 0.0**;
     - `handle_out[1] = 0.0000000000000000012e19` (12): **accepted as 0.0**;
     - `0.000000000000001234e15` in width, bank, anchor and handle: **accepted as 1.23** (true value 1.234).

   **Why it matters.** This is the class Sol reported: grammatically valid text that the engine silently decodes, wrong by a large factor, into a value that passes the authored-value checks. Only the trigger differs.
   - The fix bounds only the exponent spelling (`road_source.gd:737–761`).
   - The class documentation (416–420) and the README (109–114) explain the limit as guarding against plausible wrong decodes, but they do not mention this path.
   - The exponents involved are 15 to 20, well inside [-308, +308].

   **Status.** This is not introduced by f199089: 63fa101 used the same decode path. It is a newly identified, material residual of the corrected component's contract.

   **Suggested repair.** In `_parse_number`, before Godot decodes the number, refuse any number where significant digits fall beyond the decoder's 18-character mantissa window enough to change the value. Concretely, count mantissa digit characters, including the leading `0` and fractional leading zeros. Refuse when:
   - the count is above 18;
   - some nonzero digit lies past position 18;
   - that digit is not merely rounding noise (for example, more than one fractional leading zero precedes it).

   The simplest conservative rule is to refuse a mantissa longer than 18 digit characters whenever its leading fractional zeros exceed a small bound, or whenever an exponent is present. An alternative is an independent decimal decode check. Document the rule next to the exponent limit.

   **Regression tests to add.** Width `0.000000000000000025e17` must not be accepted as 2.0. Bank `-0.0000000000000000014e19` must not be accepted as 0.0. Add one vector-component case. Add positive controls that must still decode exactly: `0.25e1`, `0.00000000025e10`, the canonical `0.30000000000000004`, and a long nonzero-led mantissa such as `1234567890123456789012e-20`.

No other implementation defect was found:
- The saturating accumulator is correct. `SUPPORTED_EXPONENT_ABS_MAX / 10` is integer 30, so the most a further digit can produce is 309, which saturates.
- The magnitude check takes priority over the digit check, and both report the exponent's byte offset.
- Only the 309-to-324 subnormal band can decode differently, and the preflight refuses all of it. Inside the bound, a combined exponent beyond the decoder's 511 clamp yields inf (refused downstream) or a value within about 1e-290 of zero. I found no NaN path inside the bound.

### Plan and contract mismatches

- **Low, wording.** README 96–100 and the class docstring present the [-308, +308] and four-digit rules as part of the "strict JSON text grammar". The refusal text is "text is not valid strict JSON". These rules are contract constraints beyond RFC 8259: `1e-309` and `1e00001` are valid JSON. README 109–112 also calls such tokens "malformed JSON text". It would be more accurate to describe them as unsupported numeric spellings refused under `INVALID_JSON_TEXT`, as the README already does for surrogates and NUL.
- No PLAN.md mismatch was identified within this component.

### Optional improvements

- `tools/road_sampling_lab/road_sampling_checks.gd:178` decodes fixtures with permissive `JSON.parse_string` and then calls `parse_document`. That path bypasses the strict preflight. The input is committed fixtures, so the risk is low. Using `parse_json` there would keep every text path under one contract.
- The lab tests the padded positive `1e+0308` but not the padded negative `1e-0308`. My probe found that `1e-0308` is accepted correctly. The lab also lacks an uppercase `E` giant-exponent case, which my probe found refused. Both would be cheap to add as lab coverage.
- `JSON.stringify` without full precision serializes 1e-300 as `"0.0"` and 0.30000000000000004 as `"0.3"`. A canonical text writer built on it would not round-trip doubles exactly. The lab's round trip compares dictionaries, so this is only a caution for later serializers.

### Missing evidence and capability limits

- **Coordinator claims.**
  - Reproduced independently on the exact f199089 archive: pinned import rc 0, **9 cases / 668 checks**, failure probe rc 3.
  - Not independently verified:
    - the LongCat private 668/668 run;
    - the separate `23d0aaa` plus three-file overlay archive and its live SHA-256 match;
    - frozen `run_validation.sh` rc 0.
  - The archive carries no Git history, so the runner's `git archive HEAD` path and the 23d0aaa→f199089 relation could not be exercised. I also did not diff f199089 against 63fa101; the prior Opus report lists only truncated hashes.
- I did not verify the pinned engine binary against the publisher archive digest. I only recorded its local SHA-256 and version string.
- Hosted CI was not consulted and is not evidence for this lab.
- The review covers only the macOS headless road-source parser and its lab. It provides no M2 or M2.1 geometry, course, gameplay, audio, visual, hardware, rights or release acceptance.

## Summary

| Item | Status |
| --- | --- |
| Sol 63fa101 exponent-wrap finding (width, bank, vectors, nested, signed, giant) | **Closed**. Refused before decode; no wrapped value accepted. |
| Ordinary positive and negative exponent spellings, and the ±308 boundaries | Preserved |
| New malformed-input or overflow acceptance from the change | None found |
| Mantissa-window decode of valid in-range numbers (Finding 1) | **Open, Medium, blocking**. Plausible wrong width, bank and vector values are accepted. |
| Verdict | **Changes required** |
