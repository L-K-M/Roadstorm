# Independent Opus 5.5 review: scoped M0.2/M1/M2 checkpoint at b6ab93a

- **Reviewer:** Claude Opus 5.5 (`claude-opus-5-5`), Anthropic first-party, run in Claude Code. I did not delegate and did not read the other current reviewer's directory.
- **Date:** 2026-11-28.
- **Candidate:** `b6ab93a31075a4596e6d4ea9bdc98e504a7477c3`, matching `../../candidate.sha`.
- **Base:** `e94e94feb3a04c872138db9de267ffffd1fb21c7`, matching `../../base.sha`.
- **Scope:** the 27 paths in `../../changed-paths.txt` and `../../scope.patch`.
- **Inputs:** the read-only `../source` archive; the writable `build` archive, which I imported into its own `build/.godot`; and private logs under `../logs/{a,b,c,d}`.
- **Engine:** every engine run used the pinned editor printing `4.7.2.stable.official.ed1daf0bf`, under `lockf` on the shared `godot-test.lock`, with private HOME, TMPDIR and XDG directories (wrapper `../logs/godot.sh`) and a `timeout` bound.
- **Changes:** I edited no source, content or Git state.

## Verdicts

| Scope | Verdict |
| --- | --- |
| A: Comet stable ID and frame comparator repair | **pass** |
| B: provisional M2 road-source syntax/metadata slice | **changes required** (one medium defect, B-1) |
| C: preliminary M1.7 physical sweeper bridge | **pass**, with low-severity assertion and claim gaps |
| D: six provisional reward-car recipes | **pass** (provisional data only) |
| **Overall scoped checkpoint** | **changes required** (B-1 only). No M0, M1, M2 or release gate closes. |

## Ranked findings

Each finding is labelled as a defect, missing evidence, or optional tuning.

1. **B-1, medium, defect.** A road source with finite JSON coordinates beyond the float32 range validates and stores non-finite geometry.
   - **Location:** `src/course/road_source.gd:889-915`.
   - **Cause:** `_read_vector` checks `is_finite()` on the binary64 component (line 903) and only then builds a single-precision `Vector3` (line 914). The official 4.7.2 build uses 32-bit `real_t`. My probe confirms this: `Vector3(0.1,0,0).x == 0.1` is false.
   - **Reproduction:** `../logs/b/probe_rs.gd`, run with the build archive. A two-knot open source with `knots[0].anchor = [1e39, 0, 0]`, `[3.5e38, 0, 0]`, or `handle_out = [0, 0, -1e39]` returns `ok=true`. The stored values are `anchor=(inf, 0, 0)` and `handle_out=(0, 0, -inf)`.
   - **Consequence 1:** the summary JSON emits `1e99999`.
   - **Consequence 2:** `parse_document(doc.to_dictionary())` refuses with `nonfinite_component` (`../logs/b/probe_rs2.gd`).
   - **Contradicted claims:**
     - "finite components" in the class comment (lines 49-50);
     - "Vector components must be finite JSON numbers" (README:47);
     - "re-parses to the same summary" (README:95-96; `road_source.gd:501`);
     - "never silently defaults a malformed source".
   - **Related narrowing:** every authored coordinate is also silently narrowed to float32. `0.1` comes back as `0.100000001490116` from `to_dictionary()`. Distinct binary64 anchors 16777216 and 16777217 are refused as "the same anchor". This narrowing is not documented.
   - **Fix:** check finiteness after the `Vector3` conversion (or reject magnitudes above the float32 maximum), and document the float32 representation. Alternatively, store binary64 values. Add a lab case for each.
   - **Lab coverage:** the lab has no case beyond the float32 range. The 456/456 checks still pass.

2. **B-2, low, defect.** The contract claims stable identities, but the IDs have no identity syntax.
   - **Location:** `road_source.gd:607-613` (`course_id`, `revision`) and `:825-830` (`section_id`).
   - **Current check:** strings are only required to be non-empty after `strip_edges()`.
   - **Probe results** (`probe_rs.log`), all accepted:
     - `course_id = " lab.p\n"`;
     - `revision = "not a revision!"`;
     - two sections `"s0"` and `"s0 "`, accepted as distinct "unique" IDs.
   - **Contrast:** the repository's `src/data/definition_identity.gd` deliberately rejects `"car.comet\n"` and trailing-space IDs.
   - **Recommendation:** reuse that validator, or record that course and section ID syntax is deferred, before course authoring depends on these IDs.

3. **C-1, low, defect: an assertion does not cover its stated scope.** The sweeper bridge never asserts that the car stays out of contact or on the ground.
   - **Location:** `tools/calibration_sweeper_lab/calibration_sweeper_lab_driver.gd:374-402`.
   - **Current checks:** `contact` is only compared between the two runs (line 402). `wall_contact`, `grounded`, `substeps`, `remainder_m` and `world_y_m` are recorded but neither asserted nor repeat-compared.
   - **Overstated claims:** README:118 claims externally validated "contact/ground/finite state". STATUS reports "zero contact flags".
   - **Measured result:** both runs had 0 contact, 0 wall-contact, 0 ungrounded and 0 non-committed ticks out of 420 (my trace tally). So the claim holds for this run.
   - **Risk:** a regression that scrapes a wall would still pass.
   - **Fix:** add per-run `contact == 0`, `wall_contact == 0` and `grounded` checks, or narrow the README wording.

4. **C-2, low, missing evidence: the refusal case is weaker than its name.** Case `invalid_or_mismatched_source_refusal_no_motor_step` (`driver.gd:665-727`) calls `SourceScript.build` and `DriverScript.decide` directly and never calls `step_once`.
   - **What it does not show:** the "no additional adapter step" assertions (line 722 onwards) hold by construction. They do not show that the bridge's own run path refuses a bad source before stepping.
   - **What the code shows:** reading `_case_physical_bridge_repeat:338-341` confirms the run path does return before any step when the build fails. That path is not exercised with a bad source.
   - The summary's "changed/missing source refused before motor step" is accurate for the component APIs, not as an end-to-end bridge control.

5. **C-3, optional/missing evidence: arc tracking is unbounded in the observed window.**
   - Lateral error grows through the arc: 0.299, 0.441 and 0.566 m at ticks 380, 400 and 419, with steer at -0.193 and still increasing in magnitude.
   - The only bound is `LATERAL_ERROR_BOUND_M = 6 m` (`driver.gd:50`), which is road half-width for the car's centre and ignores car width.
   - This fits the stated "arc entry only" scope. It shows nothing about bounded tracking in the arc; that belongs to the full-arc follow-up.

6. **Nits:**
   - **C-4:** README:48 cites `REPORT.md`, which does not exist in the directory.
   - **C-5:** `run_validation.sh:204` copies sources with `cp -R`, which keeps read-only modes. With a read-only project (my immutable archive), the scratch removal fails with many `Permission denied` lines, yet the runner still prints PASS with rc 0 and leaves the stage behind. I removed my stage manually.
   - **B-3:** Godot `JSON.parse` keeps the last duplicate member (`probe_rs.log`: `course_id` "a" then "b" yields "b"). This is the same class as Sol's earlier baker-report observation, so record it for the malformed-source contract.
   - **B-4:** assigning to a getter-only property (`knot.anchor = ...`) is silently ignored rather than raising an error. Immutability holds.
   - **A-1, missing evidence:** every genuine trace has endpoint heading 0.0, so the new 1e-12 rad/deg consistency tolerance has not been exercised on a nonzero producer heading. The producer computes `rad_to_deg(state.heading_rad)` in binary64 (`frame_trace_driver.gd:320`), and Godot's default `JSON.stringify` prints the shortest round-trip digits (seen in the sweeper logs), so I expect no false refusal.

7. **D-1, optional tuning, not a defect:**
   - Meridian (grip score 3) has the highest grip yaw gain of all nine recipes (2.7).
   - Longshot's grip damping (4.6) is the lowest, consistent with its grip score of 2.
   - Score-to-coefficient direction is explicitly not claimed, so leave this to M1 measurement.
   - The rewards A README omits the five-score column that rewards B transcribes. Both READMEs give character and award descriptions that match GAME_DESIGN.

## A: Comet identity and frame comparator

**Comet.**
- The diff changes only `car_id` (`car.comet` to `car.balanced_starter`), `content_hash`, and the README stable-ID row.
- The new ID matches `docs/BENCHMARKS.md:9`, `fixtures/handling/sweeper.json:197,223`, the other handling fixtures, GAME_DESIGN:107 and the scenario schemas.
- **My hash recomputation** (`../logs/d/hash_and_upgrades.py`, stdlib `json` with sorted keys, compact separators, `ensure_ascii=False`):
  - It confirms all nine starter and reward hashes.
  - Setting Comet's ID back to `car.comet` reproduces exactly the e94 hash `783e1d07…628b4`, which proves no other recipe field changed.
- **Checker:** `validate_car_recipe.py --mode motor-ready` on all nine recipes: 0 errors, 0 warnings, rc 0 (`../logs/d/checker.log`).
- **Coordinator's Comet bake:**
  - The baked recipe is byte-identical to the candidate (`cmp`).
  - The manifest shows `car.balanced_starter.handling`, the new source content hash, engine 4.7.2 and an 18-field round trip.
  - I inspected this bake but did not re-bake.

**Comparator.**
- `compare_frame_traces.py` and the rest of `tools/frame_trace_lab/` are byte-identical between the coordinator's 9da stage and the candidate (sha256). The coordinator's 24 result files verified against their recorded sha256 list.
- I ran the candidate comparator directly with `python3 -I -B` (`../logs/a/replay.py`, `replay.log`, per-case logs in `../logs/a/out/`). For every case I checked the exit code, the marker count, strict JSON parsing with `NaN`/`Infinity` refused, the `pass` value, and that no traceback appeared.

| Input | Result |
| --- | --- |
| 9da genuine 30/60/120 traces | rc 0, one strict marker, `pass:true` |
| 0d9 e94-era genuine traces (Sol's base) | rc 0, one strict marker, `pass:true` |
| **Sol exact** `heading-overflow-{30,60,120}.json` | rc 1, one strict marker, `pass:false`, "heading_deg is inconsistent with heading_rad" ×3, no NaN token |
| **Sol exact** `finite-coordinate-overflow.json` | rc 1, "endpoint position derived delta is not finite", no Infinity token |
| **Sol exact** `impossible-callback-cohort.json` | rc 1, "span is 2399 … expected exactly 1200" and "exceeding measured timing.physics_frames/physics_callbacks" |
| Own: huge headings ±1.7e308 with *consistent* radians | rc 1: normalized difference of 56 degrees reported, finite |
| Own: +360 degree wrap with consistent radians | rc 0 (correct equivalence) |
| Own: 1.5 degree heading deviation | rc 1 (tolerance unchanged) |
| Own: mixed-sign positions, mixed-sign speeds | rc 1, derived-delta-not-finite, strict JSON |
| Own: delta of [1e308, 1e308] (finite hypot 1.41e308) | rc 1 by tolerance |
| Own: callback step 2; one gap at row 600 (span 1201) | rc 1 |
| Own: contiguous callbacks at offset 987654321 or -5000 | rc 0 (arbitrary offset allowed, as documented) |
| Own: `physics_callbacks` 1199; `run`/`timing` callback mismatch | rc 1 |
| Own: position delta 0.1000001 m | rc 1 |

- **Genuine facts** (each of 30/60/120):
  - 1,200 committed ticks;
  - physics frames 1,204;
  - process frames 602 / 1,204 / 2,408;
  - `physics_callbacks` 1,204 in both `timing` and `run`;
  - callback indices 10..1209 (span 1,200);
  - gate tick 357;
  - identical endpoint `[-360.0, 107.774719238281]`, heading 0, speed 7.99916648864746.
- **Tolerances:** the diff leaves the position, speed, heading and gate tolerances and the [1200, 1208] and [596, 2420] bounds unchanged.
- **Producer support:** the new `physics_callbacks` requirement is met by the unchanged producer (`frame_trace_driver.gd:382,410`).
- **Runner:** the runner's added `single_failure_marker_valid` rejects `NaN`/`Infinity` constants, multiple markers and `pass != false`.
- **Not rerun:** I did not rerun Godot frame traces. The genuine traces are the coordinator's frozen 9da run. This is numerical preflight only; it does not show presented FPS or handling acceptance.

## B: road source

- **Pinned validator** on my imported build (`../logs/b/validate.log`): seven cases, **456/456** checks, rc 0, no script errors.
- **Failure probe:** rc 3, 2 checks with 1 failure (`probe.log`).
- **Import:** rc 0 (`import.log`).
- **Code review, sound behaviour:**
  - exact key sets at document, knot, section and exception level;
  - JSON booleans only for `closed`;
  - open spans N-1 (minimum 2 knots) and closed spans N (minimum 3), with wrap from knot N-1 to 0 in both `_build_spans` and the degeneracy check (`road_source.gd:702-752`);
  - P0..P3 = anchor, handle_out, next handle_in, next anchor;
  - unused open-end handles are not degeneracy-checked (fine);
  - section count is checked before parsing;
  - unique, non-empty, ordered feature tags;
  - exception `kind` required and `detail` optional;
  - containers are read-only and accessors return copies (my probe confirms that assignment is ignored, `_anchor` via `set()` is the documented residual path, and an unvalidated `RoadSourceDocument.new()` is constructible).
- **Defects:** B-1 and B-2 above.
- **Not covered:** arc-length sampling, meshing, collision, course authoring or M2.1 acceptance.

## C: sweeper bridge

- **Runner** (`run_validation.sh --project ../source`, private HOME and TMPDIR, `timeout 900`): rc 0 (`../logs/c/runner.console`, `validator.log`, `summary.json`).
  - Validator: **176/176** checks in 3 cases (79 + 77 + 20).
  - Failure probe: rc 3.
  - Backend: Jolt Physics, engine 4.7.2.
- **Runs:** two 420-commit runs gave:
  - arc entry at tick 304, station 50.086240725258904 m;
  - final station 72.56826427886368 m;
  - maximum lateral error 0.5659506916999817 m;
  - `steps_called` = `ticks_committed` = 420;
  - repeat difference within 1e-6.
- These match the coordinator's numbers.
- **Is the observation real?** Yes.
  - `step_once` goes through `MotorBodyAdapter.step`, which commits with `CharacterBody3D.move_and_collide` (`src/laboratory/drive_lab.gd:1062`; `motor_body_adapter.gd:9`).
  - Auto-tick is disabled, one `CalibrationDriver.decide` runs per tick, and the progress station is an external nearest projection.
  - The spawn seam writes public state and the body once before tick 0, and is checked against the adapter mapping.
- Assertions match the "arc-entry bridge" scope except C-1 and C-2.
- **Not covered:** the full arc, grip/drift comparison, or M1.7.

## D: reward recipes

- **Checker:** all six recipes pass motor-ready.
- **Hashes:** I recomputed all six canonical hashes; they match.
- **Stable IDs:** `car.trailbox`, `car.longshot`, `car.meridian`, `car.rook`, `car.sandhammer` and `car.prism` all match GAME_DESIGN:167-172.
- **Awards:** the award and cup assignments match GAME_DESIGN:167-172 and 193-195.
- **Rewards B scores** match the design: 4/3/5/3/4, 5/3/3/4/4 and 3/5/4/4/3.
- **Top speeds** are all within 205-235 km/h.
- **Upgrade blocks** are exactly `[1, 1.03, 1.06]`, `[1, 1.015, 1.03]`, `[1, 1.05, 1.1]` ×2, `[1, 1.04, 1.08]`, `[1, 0.95, 0.9]` and a 6/3 maximum. I checked these against independent formula arithmetic (`../logs/d/inspect.py`).
- **Unknowns:** in every file the set of null paths equals the set of `unknowns` paths. Surfaces are empty, and Trailbox's gravel identity is honestly disclosed as unvalidated.
- **Provenance** names the LongCat job and model. Rewards B cites `PROVIDER_TERMS.md` `pi-longcat` OPEN/BLOCKING. Rewards A disclaims rights claims but does not cite that entry.
- **Coordinator bakes:** all six manifests show engine 4.7.2, status provisional, an 18-field round trip, and `source_file_sha256` equal to the candidate bytes (`../logs/d/bake-manifests.log`). I did not re-bake.
- **Not covered:** pace, tuning or rights approval.

## Capability limits and unverified items

- **Hosted CI:** for b6ab93a, `gh run list` showed run 46113265541 `in_progress` at review time. It is not verified.
- **Not rerun:** I did not rerun Godot frame traces or recipe bakes. Those rely on coordinator artifacts I inspected.
- **Not verified:** no audio, gamepad, visual, rendered or presented-FPS, platform, provider-output-rights, handling-acceptance or whole-milestone claims.
- **Leftovers:** `build/.godot` is left from my import inside my own writable archive.

## Commands and exits

| Command | Exit |
| --- | --- |
| `python3 -I replay.py <candidate comparator> <out>` (20 comparator invocations, each rc as tabulated) | 0 |
| `shasum -c` of the coordinator's 9da result hashes | all OK |
| `validate_car_recipe.py --mode motor-ready` on 9 recipes | 0 |
| `hash_and_upgrades.py`, `inspect.py`, manifest check | 0 |
| Godot `--version` | 0 |
| Godot `--import` | 0 |
| Road-source validator | 0 |
| Road-source failure probe | 3 |
| `probe_rs.gd` | 0 |
| `probe_rs2.gd` | 0 |
| Sweeper `run_validation.sh` | 0 (validator 0, probe 3) |
| `gh run list --commit b6ab93a` | 0 (run in progress) |
