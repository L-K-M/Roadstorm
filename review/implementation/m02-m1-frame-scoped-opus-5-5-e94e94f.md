# Independent Opus 5.5 review: scoped M0.2/M1 interim checkpoint at e94e94f

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, run in Claude Code. No delegation; I did not read the other current reviewer's materials.
- Candidate: `e94e94feb3a04c872138db9de267ffffd1fb21c7` (matches `../../candidate.sha`). Base: `ee44a11b52fefee93cf5770778425da1d6ba5446`.
- Inputs: the read-only `../source` archive, the writable `build` archive, and `../../scope.patch` (13 paths). Private logs are in `../logs/{a,b,c}`.
- Date: 2026-11-28.

## Verdicts

| Scope | Verdict |
| --- | --- |
| A: baker identity transport (`tools/car_recipe_bake/`, from 6343854) | **pass** |
| B: provisional starter recipes (`content/cars/starter/`, from 154bd90) | **pass** (provisional data only, with nonblocking observations) |
| C: second repair of the frame preflight (`tools/frame_trace_lab/`, e94e94f) | **pass** |
| Overall scoped interim checkpoint | **pass** |

I found no important (blocking) defects. Every finding below is a nit or a recorded limit.

## Checks actually run

### A: baker

1. **Full suite with the pinned editor.** I ran `run_tests.py --godot-bin <pinned editor>` from the build archive under the shared `godot-test.lock` (`lockf -t 300`, `timeout 600`), with private HOME, TMPDIR and XDG directories.
   - First run (`logs/a/run_tests.log`): 19 passed, 2 failed. The finite and unlimited positive cases failed with "engine wrote into the caller's HOME despite isolation".
   - Root cause: an environment artifact, not a candidate regression. The suite starts the bake CLI with `/Applications/Xcode.app/.../python3`, whose default `pycache_prefix` writes `~/Library/Caches/com.apple.python` into the HOME it inherits. The writer is the Python CLI process, not the engine.
   - Rerun with `PYTHONDONTWRITEBYTECODE=1` (`logs/a/run_tests_nobytecode.log`): **21/21 passed, rc 0**. That run includes the U+0001 and U+000B end-to-end bakes, the NUL `display_name` refusal and the malformed-transport unit controls.
2. **Direct decoder probe** (`logs/a/probe.py` and `probe.log`) against `_decode_identity_transport`.
   - Accepted the valid entry, including U+0001.
   - Refused with a `BakeError`:
     - uppercase hex
     - `byte_length` given as `true` or `13.0`
     - an encoded surrogate (`eda080`)
     - an overlong encoding (`c0af`)
     - embedded whitespace or a trailing newline in the hex
     - an extra top-level transport key
     - `fields` given as a list
   - No other exception escaped.
   - An encoded NUL decodes, which is intended. Fidelity is decided afterwards by exact comparison with the source string, and the end-to-end NUL case refuses there because Godot rewrites NUL to U+FFFD.
3. **Code reading**, with these findings:
   - `bake_handling.gd`: all four reloaded identity strings, including the `_status_name` output, are emitted as `to_utf8_buffer().hex_encode()` (lowercase) plus their byte lengths. The mismatch diagnostic now prints hex, so it no longer embeds raw control characters.
   - `bake_handling_recipe.py`:
     - `_decode_identity_transport` runs in `_read_and_validate_report` before the `DEFINITION_ID_RE`/`REVISION_RE` checks, the identity-fidelity check and publication.
     - It requires an exact key set at every level (transport, fields, entry), lowercase even-length hex checked with `fullmatch`, a strict-`int` byte length checked before decoding, and strict UTF-8.
   - The numeric bit-fidelity path, the publication path (`os.replace` of the manifest) and the recheck/atomicity code are not touched by this diff.

### B: starter recipes

1. Ran `validate_car_recipe.py --mode motor-ready content/cars/starter/*.json` from the source archive: `checked 3 recipe file(s) in mode 'motor-ready': 0 error(s), 0 warning(s)`, rc 0 (`logs/b/checker.log`). The checker also recomputes and verifies the canonical `content_hash`.
2. Read all three files, the README and `docs/GAME_DESIGN.md`, "Cars and garage" and "Upgrades".
3. I did not re-bake; the 21/21 baker suite above covers the bake path. I did not re-check the coordinator's private bakes.

### C: frame comparator

The runner calls `git archive HEAD` and cannot run unchanged in a Gitless archive. Instead I ran `../source/tools/frame_trace_lab/compare_frame_traces.py` with `python3 -I` directly against the worker's frozen exact-ee44 results (`frame-second-repair-devin-20261128/exact-ee44/preflight/run.qJEVoK/results/full-{30,60,120}.json`), plus my own mutations of `full-60.json` (`logs/c/mut.py`, `mut-summary.log`).

- **Positive control:** rc 0, `COMPARISON PASS`, 1,200 ticks at each FPS, gate tick 357, all deltas 0. The 60 FPS file records physics 1204 and process 1204. Row 356 is at 99.94 m and row 357 at 100.41 m, so 357 is the true first crossing.
- **Mutation results.** Every rejected mutation exited rc 1 with exactly one `COMPARISON_RESULT` marker containing `"pass":false` and no traceback.

| Mutation | Outcome | Reason reported |
| --- | --- | --- |
| row 357 `tick` = `357.0` | rejected | "tick field is 357.0, expected integer 357" |
| row 1 `tick` = `true` | rejected | tick type check |
| physics and process = 1 | rejected | outside [1200, 1208] |
| physics = 1199 | rejected | outside [1200, 1208] |
| physics = 1209 | rejected | outside [1200, 1208] |
| physics = 1208, process = 1208 | **accepted**, rc 0 | at the documented bound |
| process = 1208 with physics 1204 at 60 FPS (exactly +4) | **accepted** | within tolerance |
| process = 1209 (+5) | rejected | exact integer cadence inequality |
| physics = `10**400` | rejected | structured bound failure |
| gate tick = `10**400` | rejected | structured |
| row 357 station = `10**400` | rejected | "road_station_m is not finite" |
| row 301 station = `10**300` | rejected | the scan finds the earlier crossing and reports the summary-gate mismatch |
| endpoint speed = `10**300` | rejected | speed delta failure |
| `command_index` = 4,201-digit integer | rejected | structured |
| 200,000-deep JSON array | rejected | `RecursionError` caught by the new top-level handler and emitted as one structured failure |
| 5,000-digit integer | rejected | Python's digit limit raises `ValueError`, which `load_result` converts to `InputError` |

## Scope A assessment

- **Source-to-reloaded identity:** exact. Python compares the four decoded strings with the checker-parsed source through the existing `_verify_identity_fidelity` path, and the manifest takes `handling_display_name` from the decoded value. Both new positive fixtures assert exact manifest identity and pass.
- **Numeric fidelity:** unchanged and still covered by the suite (the negative-zero refusal passed).
- **Malformed transport:** refused before any identity comparison or publication.
- **NUL:** refused at `display_name` with no output.
- **Publication trust and atomicity:** the diff does not change them, and the recheck seam controls pass.
- **Prior open findings** from `docs/evidence/m02-baker-identity-decision-20261128.md`:
  - U+0001/U+000B fail-closed: **resolved** by the lossless transport (verified end to end).
  - Case 18 does not isolate the descriptor reread: **still open**, not in this diff.
  - "different file" wording for same-inode refusals: **still open**, not in this diff.

## Scope B assessment

The files are honestly provisional:

- `status: "provisional"`, `revision: "0.1.0"`.
- Provenance names the authoring job, `longcat/LongCat-2.5`, the provider and the date.
- The `unknowns` list covers every null: `engine.acceleration_curve`, `stability_assist_max_slip_deg`, `surge.selected_delta_m_s`, airborne gravity and adhesion, and contact-proxy roof and underside.
- The README explicitly disclaims pace, tuning, the 5% spread, upgrade effects and release.

The upgrade arrays transcribe GAME_DESIGN's L = 0/1/2 formulas exactly. In each car's `upgrades` block:

| Upgrade | Formula | Values |
| --- | --- | --- |
| Engine acceleration | `1 + 0.03L` | 1.0, 1.03, 1.06 |
| Engine top speed | `1 + 0.015L` | 1.0, 1.015, 1.03 |
| Tire grip damping | `1 + 0.05L` | 1.0, 1.05, 1.1 |
| Drift-exit blend | divided by the same factor | divisors 1.0, 1.05, 1.1 |
| Chassis yaw gain | `1 + 0.04L` | 1.0, 1.04, 1.08 |
| Impact speed loss | `1 - 0.05L` | 1.0, 0.95, 0.9 |

`max_increase_percent` is 6/3. Stock top speeds of 212/222/230 km/h follow the 2/3/4 speed scores. Grip damping 7.0/6.0/5.0 and grip yaw gain 2.6/2.4/2.0 follow the 5/4/3 grip scores.

I found nothing that would corrupt a future data mapping. The IDs, hashes, schema version, units and frame all validate.

Nonblocking observations for the M1 tuning owner (not defects of a provisional file):

- **B-1 (nit, design consistency).** Acceleration curves do not mirror the 4/4/3 acceleration scores.
  - Slidewinder (score 3) has the highest point at 50 m/s (2.5 vs 2.0/1.5) and ties Comet at 20 m/s.
  - Sparrow and Comet (both 4) differ at every point.
  - Higher drag may offset this. Rank it at M1 measurement.
  - Location: `content/cars/starter/slidewinder.json`, `handling.acceleration_curve`.
- **B-2 (nit, semantics).**
  - Drift-state lateral damping rises with the drift score (2.5/2.6/3.2), but GAME_DESIGN says a higher drift score means easier sustained sliding.
  - Whether higher drift damping makes slides easier or harder depends on the unimplemented controller's meaning. Record the intended direction before tuning.
- **B-3 (limit).**
  - Every `handling.acceleration_curve` ends at 50 m/s, below the stock caps (58.9/61.7/63.9 m/s) and the upgraded caps.
  - Neither `schemas/handling_config_v1_1.md` nor the schema JSON defines the value beyond the last point (clamp or extrapolate).
  - A future mapper must define this before it consumes these files.

## Scope C assessment: the three prior Sol defects

1. **Float tick hiding the first 100 m crossing: fixed.**
   - `compare_frame_traces.py:372-374` requires `is_int(tick) and tick == index` on every row.
   - The gate scan at `compare_frame_traces.py:402-415` only counts rows with an integer tick that matches the ordinal and `status == 0`.
   - The `357.0` mutation now fails on the row itself rather than being skipped.
2. **Trace with 1,200 commits and one physics/process frame: fixed.**
   - `compare_frame_traces.py:42-56` and `:240-255` bound physics to [1200, 1208] and process to [596, 2420] before the cadence check.
   - The bounds are tight enough to reject the impossible counters and loose enough to keep the genuine observed triples 1204/602, 1204/1204 and 1204/2408.
3. **Huge integer `OverflowError`: fixed.**
   - `is_number` catches `OverflowError` (`:116-125`).
   - The cadence test is exact integer arithmetic (`:259-266`).
   - `validate_result`, `compare_valid_results` and `main` are wrapped so that any residual exception becomes one structured `pass:false` marker (`:537-543`, `:564-571`, `:640-641`, and `emit_exception_failure` at `:498-520`).

The bounds are plausible. The upper physics allowance of +8 is documented as 4 drain frames plus 4 counter-boundary frames. The process band is cohort-wide, but the per-FPS ±4 exact inequality is what discriminates between cadences.

The runner's three new controls also require that no traceback appears (`run_frame_trace_lab.sh:477-490`).

Regression risk is low. The changes only add rejections and exception containment; the positive path is unchanged and still passes on the frozen results.

Nits:

- **C-1.** Failure messages other than `tick` still use an unbounded `!r`. Example: `command_index` at `compare_frame_traces.py:376`. A 4,201-digit `command_index` produced a single failure line over 4,000 characters. This is cosmetic; it is still a structured failure.
- **C-2.** The top-level `except Exception` emits its own `COMPARISON_RESULT`. If an exception were raised after `main` had already printed a marker, the log would hold two markers, which I could not trigger. Consumers that grep for `"pass":false` stay fail-closed.

## Limits (not defects)

- **Frame lab run.**
  - I did not run the frame lab end to end with Godot. Scope C was verified by running the comparator directly on the worker's frozen exact-ee44 results plus my own mutations.
  - I did not independently verify that those frozen JSONs came from the pinned engine. I relied on the worker's and coordinator's logs.
- **Baker test HOME sentinel.** The suite's caller-HOME check fails on hosts where the Python running the CLI writes bytecode into the inherited HOME (Xcode `python3` here). This is a harness portability limit that predates this diff; it also affects base.
  - Suggested follow-up: run the CLI subprocess with `-I`/`PYTHONDONTWRITEBYTECODE=1` in `run_tests.py`.
- **Hosted CI.** I did not check hosted CI for e94.
- **Out of scope.** This review does not cover or close full M0.2/M0/M1, rendered or presented FPS, physical controllers, audio, gameplay balance, pace or tuning, rights (OI-02/OI-03) or release.

## Ranked actionable findings

No important findings. Nits, in priority order:

1. B-3: define the semantics of `handling.acceleration_curve` beyond its last point before any production mapper consumes the starter files.
2. B-1/B-2: reconcile the acceleration ordering and the direction of the drift-damping score at M1 tuning.
3. Baker test HOME-sentinel portability (`tools/car_recipe_bake/run_tests.py:240`, a pre-existing limit).
4. C-1: bound the remaining `!r` failure reprs (`tools/frame_trace_lab/compare_frame_traces.py:376` and similar).
5. Carried forward, still open: the case-18 reread isolation and the "different file" wording from the 2026-11-28 baker decision.
