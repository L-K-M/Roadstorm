# Road source contract laboratory

This directory is the standalone validation laboratory for the first M2 road
source slice, schema `roadstorm.road_source.v1`. It checks the versioned pure
GDScript parser and value representation in `src/course/road_source.gd` against
two original tiny fixtures and meaningful malformed in-memory mutations.

This slice is only the authored source contract. It does not resample by arc
length, bake meshes or collision, create a course, run physics, validate the
full geometric course contract, or claim M2.1 or milestone acceptance.

## Files

| File | Role |
| --- | --- |
| `fixtures/road_source_open_tiny.json` | original three-knot open fixture with two spans |
| `fixtures/road_source_closed_tiny.json` | original four-knot closed fixture with four wrapping spans and one authored bank exception |
| `road_source_checks.gd` | positive, round-trip, immutability, span-semantics, strict-JSON, numeric-conversion and malformed-mutation checks |
| `validate_road_source_lab.gd` | headless `SceneTree` validator entry point |
| `failure_probe.gd` | deliberate failing-check control; exits 3 when detection works |
| `run_validation.sh` | frozen-source, private-cache, shared-lock runner |

## Source format

A road source is one JSON object with exactly these document keys:

- `schema`: the exact string `roadstorm.road_source.v1`;
- `course_id`: non-empty stable course identity;
- `revision`: non-empty authored revision string;
- `closed`: JSON boolean, never a string or number;
- `knots`: ordered array of authored cubic Bezier knots;
- `sections`: ordered array with exactly one record per Bezier span.

Unknown keys, missing required keys and implicit defaults are refused.

Each knot has exactly:

- `anchor`: `[x, y, z]` in metres, Godot world units with +Y up and -Z forward;
- `handle_in`: incoming cubic control point in the same frame;
- `handle_out`: outgoing cubic control point in the same frame;
- `width_m`: finite authored road width in the schema's broad data-entry band
  [1, 100] metres;
- `bank_deg`: finite authored bank in degrees.

Vector components must be finite JSON numbers whose converted engine `Vector3`
components also remain finite. A finite source scalar outside the engine
vector's representable range, such as `1e40`, is therefore refused with its
field and component index. Large values that remain finite after conversion,
such as `1e30`, are valid source data even though later geometric gates may
reject their course. The width band is only a guard against implausible data
entry. It is not the course-authoring width gate. No universal grade or bank
limit is enforced here: the design targets and their reviewed exceptions
belong to the later geometry-validation gate.

An open source with N knots has N-1 spans and needs at least two knots. A
closed source with N knots has N spans, with the final span wrapping to knot 0,
and needs at least three knots. Cubic span i uses:

1. P0: knot i `anchor`;
2. P1: knot i `handle_out`;
3. P2: the end knot's `handle_in`;
4. P3: the end knot's `anchor`.

Each section record requires a unique non-empty `section_id` and non-empty
`surface_id`. Optional `feature_tags` are unique non-empty strings in authored
order. Optional `exception` metadata is an object with required non-empty
`kind` and optional string `detail`; it is carried verbatim for the later
geometry gate. Section order is meaningful and is never sorted or re-derived.

The schema refuses exactly coincident adjacent span anchors and a
span-participating handle that coincides with its own knot anchor, because
such a span has no usable tangent. In an open source the first knot's
`handle_in` and the last knot's `handle_out` participate in no span; they are
carried as authored data but are not tangent-checked by this schema. In a
closed source every incoming and outgoing handle participates in a span.
Near-coincident geometry, curvature, grade, bank targets, clearance,
self-intersection and all other geometric course rules remain outside this
slice.

## Parser API

`RoadSourceDocument.parse_document(value)` is pure. It reads one Variant,
normally the Dictionary produced by JSON decoding, performs no file or engine
access, and returns either:

```gdscript
{"ok": true, "code": RoadSourceDocument.Refusal.NONE, "error": "", "document": document}
```

or:

```gdscript
{"ok": false, "code": <RoadSourceDocument.Refusal>, "error": "field-specific diagnostic", "document": null}
```

`RoadSourceDocument.parse_json(text)` is the JSON-text convenience wrapper. It
first runs an iterative lexical/structural preflight for the strict JSON text
grammar: only the four JSON whitespace bytes, strict number forms, lowercase
literals, properly closed objects and arrays without trailing commas, and
valid quoted strings with valid escapes. Numbers carry three deliberate
source-contract limits beyond RFC 8259: the decimal exponent must stay within
[-308, +308] and use at most four digits; the significand must use at most
18 digit characters, counting the integer part's leading zero and fractional
leading zeros but excluding sign and decimal point; and the adjusted decimal
exponent (explicit exponent minus fractional digit count) must be at least
-308. The exponent limit exists because the pinned engine's JSON reader wraps
an oversized exponent into a plausible finite value (`12e4294967296` decodes as
`12.0`). The significand limit exists because the pinned decoder retains only
the first 18 mantissa digit characters and then applies the exponent, so a
longer spelling drops significant digits while still decoding to a plausible
value (`0.000000000000000025e17`, true value 2.5, decodes as `2.0`). The
adjusted-exponent limit exists because the pinned decoder uses that adjusted
exponent to choose an intermediate power of ten; below -308 the divisor itself
overflows, so valid JSON `1.0e-308` decodes as exact zero although its
mathematical value is representable. These tokens are valid JSON; they are
unsupported spellings under this contract, refused with `INVALID_JSON_TEXT` and
a byte offset rather than described as malformed grammar. The limits are
lexical and do not by themselves guarantee a finite decoded double, so
decoded-value finiteness is still enforced downstream.
The scanner is not a regex stripper; it tracks nested object/array state while
treating commas, braces and brackets inside strings as content. Object member
names are canonicalized after escape decoding, including `\uXXXX` sequences
and surrogate pairs, and duplicate member names are refused in every object
before Godot's permissive JSON reader constructs a `Dictionary`. As additional
contract constraints, unpaired surrogate escapes are refused rather than being
interpreted as implementation-defined text, and NUL escapes are refused because
the pinned engine decoder lossily replaces them. Only after those checks does
the wrapper decode the text and apply `parse_document`, using the same
structured refusal contract. Malformed JSON, unsupported numeric spellings and
non-finite literals are rejected rather than accepted.

`RoadSourceDocument.parse_document(value)` reads numbers as already-decoded
Variants. It cannot inspect or re-derive their source spelling, so the lexical
limits above protect the `parse_json` text path only; a caller that decodes JSON
itself owns the correctness of that decode.

A successful document exposes read-only `schema`, `course_id`, `revision`,
`closed`, `knot_count`, `section_count`, `span_count`, `knots`, `sections` and
`spans`; indexed `knot(i)`, `section(i)` and `span(i)` accessors;
`expected_span_count()`, `to_dictionary()` and `summary()`. Container accessors
hand out copies. `to_dictionary()` returns a fresh mutable canonical structure
that re-parses to the same summary. `Span.control_points()` returns the ordered
cubic control-point chain. GDScript cannot fully hide private members from
`Object.set`; replacing a private member wholesale is the documented residual
mutation path.

## Run

From the repository root, using the publisher-pinned engine and shared
coordinator lock:

```sh
sh tools/road_source_lab/run_validation.sh \
  --project . \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
  --lock work/agents/coordinator/godot-test.lock \
  --work-root work/road_source_lab \
  --lock-wait 120 --outer-timeout 120 \
  --log work/road_source_lab/road_source_validator.log \
  --summary-out work/road_source_lab/road_source_summary.json \
  --evidence-out work/road_source_lab/runner_evidence.txt \
  --keep-scratch
```

`--work-root` is optional. When supplied it must stay under the repository's
ignored `work/` tree; without it the runner uses a fresh temporary directory
and removes that directory after a normal run. `--keep-scratch` preserves the
frozen stage, logs and private cache for inspection.

The runner:

- exports a plain frozen `git archive HEAD` source tree without mutating Git;
- overlays only `src/course/road_source.gd` and files under
  `tools/road_source_lab/` from the selected checkout;
- records the exact HEAD revision, source archive SHA256, per-file overlay
  SHA256 values and combined overlay-manifest SHA256;
- verifies that the staged overlay hashes match the source overlay hashes;
- uses private `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `XDG_CONFIG_HOME` and
  `XDG_DATA_HOME` directories and never writes the live checkout's `.godot/`;
- verifies the engine prints `4.7.2.stable.official.ed1daf0bf`;
- serializes the bounded version/import/validator/probe sequence on the shared
  coordinator lock;
- records the exact PID and command of a stranded Godot child, stops only that
  child, and preserves the run log in that case;
- runs the positive validator and then the deliberate failure probe.

## Output contract and exit codes

The validator prints one `ROAD_SOURCE_LAB_CASE` line per case, then
`ROAD_SOURCE_LAB_SUMMARY` and `CHECKS_TOTAL=n CHECKS_FAILED=n`. With
`--summary-out`, the full summary JSON is copied to that path when validation
passes.

Runner exit codes:

- `0`: import succeeded, the validator reported `pass:true` with zero failed
  checks, and the failure probe exited nonzero with `pass:false`;
- `1`: a validation, output-gate or probe expectation failed;
- `2`: unsafe arguments, missing tools, an unusable engine, an engine-version
  mismatch or archive/overlay failure.

The deliberate probe prints `ROAD_SOURCE_FAILURE_PROBE` with two checks and one
intentional failure, then exits 3. A zero exit would mean failing checks are
not detectable.

## Coverage

The laboratory currently covers:

- both original tiny open and closed fixture files;
- exact schema/course/revision/closure identity and unknown/missing keys;
- open N-1 and closed N ordered span-count semantics, including closure wrap;
- ordered section/surface/feature/exception metadata and stable unique IDs;
- finite vector, width and bank values, including finite source scalars that
  overflow converted engine vector components and a large finite representable
  coordinate;
- malformed JSON and non-finite JSON literals, strict trailing-comma and
  duplicate-member refusals, nested structural scanning, escaped-key duplicate
  equivalence, and valid escaped string content;
- numeric-exponent decoder bounds: the exact Sol giant-exponent width, bank
  and vector payloads, ordinary signed e+2/e-2 spellings, +/-308 boundary
  controls and excessive leading-zero exponent spellings;
- significand-window bounds: the exact Opus mantissa-window width, bank and
  vector payloads, nested schema-unknown positions, a 22-digit nonzero-led
  refusal, positive controls `0.25e1`, `0.00000000025e10`, an exact 18-digit
  boundary spelling, `0.30000000000000004`, signed and uppercase exponent
  forms, and the direct-parse_document spelling-blindness control;
- adjusted-exponent decoder bounds: the exact Sol follow-up spellings
  `1.0e-308` and `1.00e-307` refused in bank and nested schema-unknown
  positions, uppercase `E` forms, nonzero relative-value positive controls
  `1e-308`, `0.1e-307` and `1.0e-307`, and ordinary signed/unsigned ratio
  controls;
- degenerate adjacent anchors and degenerate span-participating tangent
  handles, with explicit coverage of the two unused open-endpoint handles;
- canonical round-trip, repeated parsing, accessor copies and read-only public
  properties;
- authored-order preservation and representative malformed mutations;
- the nonzero deliberate failure probe.

## Limits

This laboratory does not evaluate arc-length sampling, curvature, stopping
distance, grade or bank targets, clearance, intersections, overpasses, seams,
grid space, safe anchors, recovery legality, render/collision meshes, scenery,
AI lines, minimaps, performance, gameplay feel or release readiness. It runs
one pinned local engine in one headless process cohort and makes no
cross-version, cross-host, rendered or milestone acceptance claim.

The accepted JSON number spellings are deliberately narrower than RFC 8259:
exponents outside [-308, +308] or longer than four digits, significands longer
than 18 digit characters, spellings whose adjusted decimal exponent is below
-308, unpaired surrogates and NUL escapes are refused even though several of
these are valid JSON. `parse_document` callers that decode text with another
reader bypass these lexical limits and own that decode.
