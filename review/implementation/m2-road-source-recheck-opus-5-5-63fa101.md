# Scoped recheck: M2 road-source correction, candidate 63fa101

- **Date:** 2026-11-28
- **Reviewer:** Claude Opus 5.5, running in Pi (`PI_MODEL=claude-opus-5-5`, `PI_PROVIDER=venice`). The packet's `result.json` holds an earlier Claude Code attempt that failed with an OAuth error and made no tool calls. It is not part of this review.
- **Candidate:** `63fa101a8d76ee951ef498866b18f27b8e053422`
- **Base:** `b6ab93a31075a4596e6d4ea9bdc98e504a7477c3`, the prior jointly reviewed revision.
- **Scope:** only the road-source correction. This is not M2 or M2.1 acceptance.
- **Verdict:** **pass** (scoped correction only)

## Scope and source verification

- **Archive digest:** `shasum -a 256 source.tar` gives `91dbbca6…1168c83`, which matches `source.tar.sha256`.
- **Archive against `source/`:** I extracted the tar to private scratch. `diff -rq` against `source/` found no differences. I deleted the scratch copy afterwards.
- **Paths in `scope.patch`:** `src/course/road_source.gd`, `tools/road_source_lab/road_source_checks.gd` and `tools/road_source_lab/README.md`. The brief lists the third file as "README.md"; it is the lab README.
- **Patch against `source/`:** `git apply --check -R scope.patch` succeeds on a private copy of the three `source/` files. So the post-image of `scope.patch` is the archived content.
- **SHA-256 of the archived files:**
  - `road_source.gd`: `09e52a7e…a280`
  - `road_source_checks.gd`: `ff63415a…9e54`
  - `README.md`: `00ce37db…7217`
- **Not verified:** that the archive is commit 63fa. No git metadata is present, so I rely on the coordinator's statement that it is.
- **Not read:** I did not read the concurrent Sol recheck or any other current report.
- **Historical reports consulted:** `review/implementation/m02-m1-m2-checkpoint-{opus-5-5,gpt-6-2-sol}-b6ab93a.md`.

## Files and lines inspected

`src/course/road_source.gd`:
- full file;
- the preflight class (418–857), including:
  - `validate` (467);
  - the object and array state machines (550–606);
  - the duplicate key check (609–621);
  - number parsing (688–722);
  - escape handling (756–812);
- `parse_json` (1136–1153);
- the three `_read_vector` calls in `_parse_knot` (1235, 1238, 1241);
- `_read_vector` (1353–1388), which checks finiteness after conversion at 1373–1381.

`tools/road_source_lab/road_source_checks.gd`:
- every changed hunk, including:
  - the strict-wrapper round trip (431–442);
  - the overflow and representable cases (744–782);
  - the unused open-endpoint handles (876–893);
  - `_case_strict_json_text_preflight` (932–1090).

`tools/road_source_lab/README.md`: every changed hunk.

## Commands run

All engine runs used:
- a private copy of `source/` under `build/proj`, rsynced with `u+w`;
- private HOME, TMPDIR and XDG directories under `private/`;
- `lockf -t 600 <coordinator godot-test.lock>`;
- a `timeout` on every Godot call;
- the pinned binary at `toolchain-m01/.../Godot`.

No git-dependent runner was used. Logs are in `private/logs/`, 53 KB in total.

| Command | rc | Result |
| --- | --- | --- |
| `Godot --version` | 0 | `4.7.2.stable.official.ed1daf0bf` |
| `--headless --path . --import` | 0 | |
| `--script res://tools/road_source_lab/validate_road_source_lab.gd` | 0 | 8 cases, **578/578**, 0 failed. The new case `strict_json_text_preflight` ran 97 checks. |
| `--script res://tools/road_source_lab/failure_probe.gd` | **3** | The deliberate failure was detected. |
| `--script res://probe_review.gd`, my own probe, kept at `private/probe_review.gd`, run twice | 0 | Results below. No script errors or crashes. |

Probe results, all on the pinned engine. The engine uses 32-bit `real_t`: `Vector3(0.1,0,0).x != 0.1`.

1. **Vector3 finiteness after conversion, through the JSON text path.** I tested all three knots × anchor, handle_in and handle_out (x component) with 10 values each.
   - Refused with `nonfinite_component` and the correct field and index: `1e40`, `-1e39`, `3.4028236e38`, `3.40282357e38` and a 42-digit integer literal.
   - Refused by the binary64 check: `1E400` and `-1e400`.
   - Accepted: `3.4028235e38` (float32 maximum), `1e30` and `1e-50`.
   - In every accepted document, all stored vectors were finite: no `BUG` line was printed.
   - The lab covers y and z through `parse_document`. The loop at 1374–1381 handles every axis the same way.
2. **Strict grammar.** All of these are refused with `invalid_json_text`, an error message and a byte offset:
   - numbers: `1.`, `.5`, `-`, `+1`, `01`, `-01`, `1e`, `1e+`, `0x10`, `NaN`, `Infinity`, `-Infinity`, `--1`, `1..2`, Arabic-Indic digit;
   - truncation and separators: empty text, whitespace only, unclosed `{` and `[`, a stray `}` or `]`, missing comma, missing colon, empty value, `{,}`, `[,]`, `[,1]`, double comma, trailing comma in an object and in an array;
   - literals and trailing data: `tru`, `True`, `nul`, `nullx`, extra closers, trailing comments, trailing NBSP, leading BOM;
   - strings: unterminated strings, short or non-hex `\u`, an unpaired low surrogate, a high surrogate followed by a non-low escape or by a raw character, a raw tab.
   - Valid forms reach document validation: `1.5E3`, `-0`, `0e0`, `1E-2`, all four whitespace bytes, and spaced separators.
3. **Duplicate member names.** These are refused before the engine builds the Dictionary:
   - at the knot level (`anchor`);
   - five levels deep, in arrays inside objects (`"c"` against `"\u0063"`);
   - escape aliases: `\/` against `/`, `\"` against `\u0022`, `\t` against `\u0009`, upper-case against lower-case hex, an escaped surrogate pair against an escaped surrogate pair, raw against escaped emoji and `é` (lab tests);
   - the empty name;
   - escaped `sch\u0065ma` at the root.
   - NFC `é` and NFD `e\u0301` are correctly treated as distinct names.
   - 50,000 keys with one late duplicate: refused in 462 ms.
4. **Decoder agreement.** A surface ID containing `\u00e9\ud83d\ude00\/\b\f` decodes in the engine to UTF-8 `61 c3a9 f09f9880 2f 08 0c`. This is the same byte sequence the preflight canonicalizes, so the two decoders agree on escapes and surrogate pairs. A NUL escape is refused before decoding. I could not build a raw lone surrogate or NUL inside a Godot `String`: the engine replaces both with U+FFFD on construction, so that alias path cannot be reached.
5. **Pathological nesting.**
   - The preflight is iterative: 100,000 nested arrays or objects and 200,000 unclosed `[` all finish within 0.4 s without a crash.
   - Nesting up to depth 1000 reaches document validation.
   - The engine decoder refuses depth 1100 and above as `JSON structure is too deep`, and this is reported as `invalid_json_text`.
6. **Round trip.** Each fixture went through text, `to_dictionary`, stringify and `parse_json` again. The output equals the input canonically and by summary, for both fixtures. A document with float32-maximum, `0.1` and `-1e30` coordinates also round-trips through the strict text path.

## Prior findings rechecked

- **Opus B-1 and Sol #1, the Vector3 overflow: fixed.** `road_source.gd:1373-1381` checks every converted component. All three knot vectors go through `_read_vector` (1235, 1238, 1241). The lab covers all three roles at `road_source_checks.gd:744-781`, plus the representable `1e30` control.
- **Sol #2 and Opus B-3, the trailing comma and duplicate `closed`: fixed.** `parse_json` (1136–1153) runs the strict preflight before `JSON.parse`. The lab reproduces both Sol counterexamples and the escaped alias through `parse_json` (`checks.gd:941-964`).

## Findings

**Implementation defects:** none confirmed in scope.

**Plan mismatches:** none in scope.

**Missing evidence (low, not blocking):**
- **L1:** the lab has no pathological-nesting case. It also has no invalid-number controls beyond a leading zero: `1.`, `.5`, `+1`, `1e`, `-`, `NaN` and `Infinity` (in grammar position) are untested. My probes cover all of these.
- **L2:** the lab tests overflow only through `parse_document`, with no 1e40 overflow control through `parse_json`. My probes cover that path.

**Optional improvements and residual low follow-ups:**
- **L3, documentation:**
  - the README and class comment still do not state that coordinates are stored as float32;
  - `0.1` comes back as `0.100000001490116`;
  - `1e-50` silently underflows to 0, though a resulting coincident handle is still refused as degenerate (probe: `degenerate_handle`);
  - distinct binary64 anchors can collapse into one float32 value.

  This was the "related narrowing" note in the prior Opus report.
- **L4:** `bank_deg` and `width_m` stay binary64. `bank_deg = 1e300` is accepted (finiteness only, by design). Any later float32 or Basis conversion must recheck finiteness. This belongs to the geometry gate.
- **L5:** a leading UTF-8 BOM is refused as invalid JSON. RFC 8259 permits this, but authors should be told.
- **L6, outside this scope:** the prior Opus B-2, which has no ID syntax for course, revision and section IDs, remains open.

## Capability limits

- No git metadata: I did not verify the commit SHA independently.
- I did not run the git-dependent runner or hosted CI.
- I did not test a double-precision engine build.
- Gameplay, geometry, sampling, hardware, audio and rights are not assessed and are not approved.

## Verdict

**pass** for the scoped road-source correction at 63fa101. Both required b6 repairs hold, and the strict JSON boundary refused every case I tested without crashing. This is not M2 or M2.1 completion. L1–L6 remain as low follow-ups.
