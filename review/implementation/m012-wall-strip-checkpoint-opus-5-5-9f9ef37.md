# Independent Opus 5.5 checkpoint review: exact 9f9ef37 (M0.2 upgrade, M1.8 wall-policy seam, M2.1 OPEN strip, arc A1-A3)

- **Date:** 2026-11-28, about 09:58 to 10:10 CET
- **Reviewer route (as observed):** Claude Opus 5.5 in the Pi coding agent.
  The environment reports `PI_PROVIDER=venice`, `PI_MODEL=claude-opus-5-5`
  and `PI_REASONING_LEVEL=medium`. I make no claim about the backend revision.
- **Candidate:** `9f9ef376f8e17ec5025ad6c899c4c93f4b348504` ("Add provisional
  OPEN driving strip and physical lab").
- **Independence:** I did not read the concurrent reviewer's packet or report.
  That includes the untracked `review/implementation/m012-*-sol-9f9ef37.md`,
  which `git status` lists. I spawned no helpers and changed no tracked
  source, Git index, refs or worktrees. I wrote only this report and ignored
  files under `opus/private/`.

## Archive identity

| Check | Result |
|---|---|
| `shasum -a 256 source.tar` | `3571ed0aec92f38b012fe082fdba9ded03e28ffd9ddbd04d3fc2f35c312ceee7`, matching `source.tar.sha256` |
| `git archive 9f9ef376… \| shasum -a 256` | The same digest, so the tar is the exact commit tree |
| `git cat-file -t 9f9ef37` | `commit`. Subject and date are as stated above. |
| Fresh extraction to `private/verify`, then `diff -r` against `source/` and `private/build/` | Identical. No `.git` directory. |

## Verdicts

| Slice | Verdict |
|---|---|
| 1. M0.2 `UpgradeDefinition` and data-lab additions | **PASS (scoped).** No defects in the slice. One Low residual (U1) and one plan-level mismatch with the pre-existing car-recipe contract (P1). This is not garage, save or M0.2 acceptance. |
| 2. Provisional M1.8 DriveLab wall-policy seam | **PASS (scoped).** My private Jolt probe confirmed every authority, identity, retry, suppression, renewal and retirement property I targeted. Coverage gaps are Low (W1, W2). This is not M1.8 acceptance. |
| 3. Provisional M2.1 OPEN driving strip | **PASS (provisional scope), with one Medium follow-up (S1).** S1 must gate scene integration and drivability. Winding, normals, metadata, refusal atomicity and determinism check out on the real pipeline fixtures. Jolt ray queries leak at exact chunk seams. This is not M2.1 acceptance. |
| 4. Arc-test A1/A2/A3 follow-up | **PASS.** A1 is fixed with a discriminating regression, which a guard-removal mutation proves. A2 is fixed. The cap-code half of A3 is documented. The ordering note remains optional. |

No slice gets CHANGES REQUIRED. None of the findings below is a correctness defect in accepted output within a slice's claimed scope.

## Commands run (all engine calls in my private trees)

Every engine call used the pinned `toolchain-m01/.../Godot`
(`4.7.2.stable.official.ed1daf0bf`; summaries report hash `ed1daf0bf001…`).
Each ran under the following wrapper:

```text
env -i HOME/TMPDIR/XDG_* = private
/usr/bin/lockf -k work/agents/coordinator/godot-test.lock
/opt/homebrew/bin/timeout -k 5 120 Godot ...
```

After each run I grepped the log for `SCRIPT ERROR|^ERROR|ERROR:`. The wrapper
is `private/run.sh`, and logs are in `private/logs/`.

One exception: early on I ran `Godot --version` once without the lock or the private env. It only prints the version.

The data-lab case is different because its own runner pre-creates sentinel files. I ran the tracked `tools/data_lab/run_validation.sh --project private/verify --private-dir private/datastage --timeout 120` under one lock hold, with a 600 s outer timeout. The runner applies its own 120 s watchdog to each engine call.

| Run | Result | Error gate |
|---|---|---|
| import `private/build` | rc 0 | clean |
| `road_strip_lab/validate_road_strip_lab.gd` | rc 0, **3 cases/108 checks, 0 failed** | clean |
| `road_strip_lab/failure_probe.gd` | rc **3**, 2 checks/1 failed | clean |
| `drive_lab/validate_drive_lab.gd` | rc 0, **17 cases/5333 checks, 0 failed**, backend Jolt Physics | clean |
| `drive_lab/bad_config_fixture.gd` | rc 0, **99 checks, 0 failed** (one ObjectDB-leak warning at exit) | clean |
| `drive_lab/failure_probe.gd` | rc **3**, 2 checks/1 failed | clean |
| data lab through the tracked runner (`--case all`) | runner rc 0, **21 cases/779 checks, 0 failed**: `upgrade_definition_contract` 161, `upgrade_tres_round_trip` 77; deliberate-failure proof nonzero; runner prints PASS | runner gate clean |
| data lab run directly, without the runner | 772/2 failed, both in `scratch_reservation_control` ("preexisting sentinel present"). Expected: that case needs the runner's sentinels. **Not a defect.** | clean |
| `road_sampling_lab/validate_road_sampling_lab.gd` | rc 0, **11 cases/646 checks, 0 failed**; `global_station_advance_guard` 15 checks | clean |
| `road_sampling_lab/failure_probe.gd` | rc **3** | clean |

### Private probes

All probe scripts are in `private/build/_opus_probe/`. None is tracked.

- `strip_probe.gd` (6054 checks): the real pipeline (road source → arc → frame → strip) for the frame-lab fixtures:
  - open straight at 5 m spacing (9 frames);
  - banked bend at 2 m (25 frames);
  - rapid grade at 0.2 m (35 frames).
  
  Each is baked at `max_segments_per_chunk` 1, 2, 3, 7, 32 and 1024. Results:
  - Mesh and metadata vertex/index counts agree in every chunk, and so do segment station ownership, section IDs and face↔index order.
  - Shared seam rows are bit-exact, and vertex positions equal `position ± right·w/2`.
  - Baking is deterministic.
  - Refusals are atomic, with `bake:null` and `chunks:[]` for 9 synthetic defects.
  - Jolt rays: 24/24 downward mid-segment rays hit on the banked bend. Upward rays from below hit 0 times, even with `hit_back_faces=true`.
  - A rigid sphere rests on the bend.
  - 13 "failures" are reviewer-chosen thresholds, explained under S1 and S3.
- `seam_probe.gd`, `drop_probe.gd`: seam ray and contact behaviour (S1).
- `grade_probe.gd`: frame dump for the rapid-grade fixture (S3).
- `opus_drive_driver.gd`: a private copy of the tracked driver with one extra case, `opus_policy_probe`, on real Jolt. Its 8 checks pass (detail under slice 2).
- `upg_probe.gd`: hand-authored `.tres` coercion (U1).
- `guard_probe.gd` and a guard-removal mutation in a separate private copy, since deleted: slice 4.

What I did **not** run:

- the full `tools/ci/ci.sh` suite or export smoke;
- the `wall_contact_policy_lab`, `wall_impact_lab` and `road_frame_lab` validators on their own (their runtime sources are unchanged in this range);
- the private old-source probe the coordinator describes (metadata 3 vs mesh 4);
- any GUI, rendering, audio or controller check.

Nothing here supports a visual-culling, platform or output-rights conclusion.

## Inspected files and lines

- `src/data/upgrade_definition.gd` 1–178 (full);
- `src/data/README.md`, UpgradeDefinition section and deferred-scope edits;
- `tools/data_lab/data_lab_checks.gd`, `valid_upgrade()`;
- `tools/data_lab/validate_data_lab.gd`: `_case_upgrade_definition_contract`, `_case_upgrade_tres_round_trip` and helpers (diff of about 350 lines);
- `tools/data_lab/README.md`;
- `docs/GAME_DESIGN.md:179-185` (Upgrades);
- `schemas/handling_config_v1_1.schema.json:594+` and `tools/car_recipe_schema/validate_car_recipe.py:1495-1560` (for P1).
- `src/laboratory/drive_lab.gd`:
  - header 96–115;
  - state 262–286;
  - `retire_wall_event_scope`/`_retire_wall_policy` 834–881;
  - telemetry 905–955;
  - `publish_wall_event` 1001–1041;
  - `_advance_wall_policy` 1052–1120;
  - `_wall_policy_witness_fields` 1123–1150;
  - `_publish_wall_event_id` 1153–1183;
  - commit path ~1375–1395;
  - `configure`/`_reset_run_state`/`restore_drive_snapshot`.
- `tools/drive_lab/drive_lab_driver.gd`: diff 3d57453..73ea89b (new case 3713–3836 and added refusal/withheld checks);
- `tools/drive_lab/README.md` M1.8 section;
- `src/simulation/wall_contact_policy.gd` header, constants and API (unchanged in this range).
- `src/course/road_strip_baker.gd` 1–931 (full);
- `src/course/road_transport_frame.gd` `FrameTable` 133–230;
- `tools/road_strip_lab/*` (full).
- `tools/road_sampling_lab/road_sampling_checks.gd` diff, 1065–1177;
- `tools/road_sampling_lab/README.md` diff;
- `src/course/road_arc_sampler.gd` 430–460 (the guard) and 1420–1437. `git diff bf4b2d5 9f9ef37` shows no runtime arc change.

## Ranked findings

### S1. Medium (slice 3; gates M2.1 integration and drivability): Jolt ray queries miss at exact chunk seams even though the seam rows are bit-exact

**Reproduction:** `private/build/_opus_probe/seam_probe.gd`.

1. Build the real banked-bend pipeline at 2 m spacing.
2. Bake with `max_segments_per_chunk: 1`, giving one `StaticBody3D` and `ConcavePolygonShape3D` per segment.
3. Cast downward rays with `hit_back_faces=false` exactly on each interior frame row, at 17 lateral fractions from −0.4 to 0.4 of the width.

Results:

| Bake | Rays along frame up | World-vertical rays |
|---|---|---|
| 1-segment chunks (every row is a chunk seam) | **80 of 391 miss** | **83 of 391 miss** |
| Single chunk (`k=1024`) | 0 of 391 miss | 1 of 391 misses |

The tracked lab's first probe agrees: 25/33 seam rays hit at chunk size 2. Moving the rays 1 mm forward hits 33/33.

Rays offset ±1e-6 m along `forward` still miss in both bakes: 26 to 45 of 391 for 1-segment chunks. On the flat straight, the same offset misses 17 of 119 even inside one shape. So Jolt's ray test leaves a micrometre-scale band around edges. Chunk seams make it much worse at the exact boundary.

**Contact is not affected.** 69 small spheres driven into seam rows at 3 m/s did not fall through, for either chunking (`drop_probe.gd`, second run).

**Why it matters:**

- `src/simulation/ground_support_probe.gd:364` is ray-based, with five `intersect_ray` calls per step.
- The baker's documentation says the seam is "duplicated bit-exactly", which is true but does not make the seam watertight for the shipped physics backend.
- The tracked lab avoids seam positions: its rays are at z = −5 and −15, while the seam is at z = −10.

**Fix direction (before scene integration or drivability):**

1. Add a tracked seam-ray regression on a non-axis-aligned bake.
2. Measure the ground-support probe's tolerance to single-ray misses, then choose one remedy:
   - merge each collision region into one shape;
   - overlap chunks by one segment;
   - make the support probe robust to a single missed ray.
3. Keep the claim at "vertex-exact", not "physically seamless", until one of these is proven.

This is not a defect within the provisional strip's stated contract, so slice 3 is not CHANGES REQUIRED. It is the main open risk for M2.1.

### S2. Low (slice 3): the flip guard is a sign test only, so a near-vertical "road" triangle is accepted

`_check_triangle` refuses only when `alignment >= 0.0` (`road_strip_baker.gd:814`). It compares against the preceding frame's `up` only.

**Counterexample** (in `strip_probe.gd`):

1. Take the straight table.
2. Move frame 1 to `frame0.position + forward*0.01 + (0, 50, 0)`, keeping `up = +Y`.
3. Build the table through the public `FrameTable.make`.
4. Bake: the result is `ok=true`, with near-vertical triangles whose normals are almost perpendicular to `up`.

The transport-frame builder cannot emit this, but the baker states that it revalidates defensively and `FrameTable.make` is public.

**Fix direction:** refuse when `-normal.normalized().dot(up)` falls below a documented cosine, for example about cos 60° to 80°. Check against both rows' `up`. Optionally also check that consecutive positions advance along `forward`.

### S3. Low / informational (slice 3): shading normals can diverge from geometric normals by about 39° on an accepted pipeline fixture

The rapid-grade fixture at 0.2 m spacing bakes successfully. However, the first and last segments have a geometric triangle normal at only 0.774 and 0.81 cosine (about 39° and 36°) to the frame `up` used as the vertex normal:

| Frame | Forward | Chord direction |
|---|---|---|
| 0 | (0, 0, −1) | (0, 0.889, −0.458) |
| 34 | (0, 0, −1) | — |

The cause is the fixture's near-vertical transport at the knots, not the baker. Physics uses the true triangles; only lighting uses the frame normals. Drivability needs a curvature-to-spacing or normal-deviation gate before M2.1 acceptance. The baker could report the maximum geometric/shading deviation in its summary.

### U1. Low residual (slice 1): `.tres` loading silently coerces typed fields before `validate()` runs

Hand-authored `.tres` files (`upg_probe.gd`) load as **valid** records:

| Authored value | Loaded as |
|---|---|
| `level = 1.7` | level 1 |
| `level = "2"` | level 2 |
| `category = 1.9` | TIRES |

An unknown `bogus_multiplier = 9.0` property is silently dropped. `category = -3` is correctly diagnosed.

`validate()` itself never repairs anything, as documented, but the Godot loader does. This residual is shared by every typed M0.2 resource and was not introduced here.

**Fix direction:** the pending `.tres` artifact writer and validator (listed under "Systems" in `src/data/README.md`) should strictly check the raw text of authored or baked upgrade resources. Until then, say in the README that loader coercion happens before validation.

### W1. Low (slice 2): tracked coverage omits renewal, retirement-generation equality and suppressed-tick retry

The production behaviour is correct. My private real-Jolt case (`opus_policy_probe`, 8/8) observed:

- **Onset:** `drive_lab.wall.1.0.0`, episode key `1:0`; ledger and policy generation are both 1.
- **Grind:** 60 ticks after onset gave 60 `suppress_repeat` decisions.
- **Suppressed-tick retry:** `publish_wall_event(suppressed_result)` returns `false`. Policy state, ledger count and digest are unchanged, `identity_tick_slots=0`, the refused counter is unchanged and the diagnostic is empty.
- **Stale retry:** retrying the onset witness after later ticks is refused.
- **Renewal:** after braking into reverse with 61 witness-free ticks, a re-hit gives a new `publish_onset` with `drive_lab.wall.1.1.0` and key `1:1`.
- **Retirement:** `configure()` sets ledger generation 2, policy generation 2, ledger count 0 and per-scope counters to zero. Lifetime counters are preserved (`published_events` 2).
- **Post-retirement:** the next onset is `drive_lab.wall.2.0.0`.

The tracked `wall_policy_integration` case covers only onset, producer-derived fields, exact retry, a no-witness tick and the first suppressed tick. It defines `WALL_POLICY_SEPARATION_GAP_M` and `WALL_POLICY_REVERSE_MAX_TICKS` (`drive_lab_driver.gd:130-131`) but never uses them, which looks like a dropped renewed-episode regression. It never reads `policy_scope_generation`, and it never retries a suppressed tick.

**Fix direction:** add those three assertions, or delete the dead constants.

### W2. Low (slice 2): policy-published but ledger-refused ticks leave counters inconsistent

`_advance_wall_policy` stores the new policy state, which counts `published_events` and consumes the ID, before `_publish_wall_event_id` runs (`drive_lab.gd:1105-1117`). If the producer or ledger then refuses, the diagnostic is recorded and a retry correctly returns `false`. However, the policy's counters and the ledger disagree by one, and the consumed ID is never used.

This is unreachable with today's unique IDs and a producer result that already passed for the same witness. A one-line note in the telemetry documentation, or a `policy_publish_failed` counter, would make it explicit. Optional.

### A-items (slice 4), status

- **A1 fixed.** `_case_global_station_advance_guard` uses a 2^29 m prefix span and a 2^-26 m second span at the default options and spacing 15. It requires:
  - `table_inconsistent`;
  - `span_index` 1 and section `lab.sampling.straight.b`;
  - start and end stations both equal to 2^29;
  - a positive local length within 1e-4 relative of 2^-26;
  - the guard's error-message substring.
  
  **Mutation:** disabling `if total_length <= span_start` in a private copy makes this case alone fail, with 8 failures (the code changes to `sample_cap_exceeded`). The other 10 cases still pass. The 2^53 fixture still asserts `precision_unreachable`, and its comment is corrected.

  Optional strengthening: with the guard removed, the same source at spacing 1e6 or 1e9 is **accepted**, and even builds an OPEN frame table (`guard_probe.gd` on the mutant). The current guarded source refuses all three spacings. A second assertion at a large spacing would prove the guard is the only defence against a silently corrupted table, not just the first refusal.

  Nit: the comments say "below one float64 ulp of the chained station". The operative bound is half an ulp: 2^-24 at 2^29, and 2^-26 is well below it.
- **A2 fixed.** The README option table now says "per span". New text states that `Table.length_error_estimate_m` sums per-span estimates, bounded by span_count × tolerance plus rounding, and that the floor uses each span's own chord.
- **A3 partly addressed (optional).** The README now says precision-limited requests may surface as `subdivision_cap_exceeded` or `table_node_cap_exceeded`. The other half is not documented: the floor check runs before the derivative-degeneracy check, so a huge degenerate span reports `precision_unreachable`. That was optional.

## Slice notes (verified, no finding)

**Slice 1:**
- Prices are `[0, 800, 1600]`, incremental, totalling 7200.
- Effects at level L:
  - Engine: 1+0.03L and 1+0.015L, so 6%/3% at L=2 matches the design's "3%/6%".
  - Tires: 1+0.05L, used both as the multiplier and as the drift-exit divisor. There are no drift-state, entry or slip keys.
  - Chassis: 1+0.04L and 1−0.05L.
- Nothing is compounded.
- Out-of-domain category or level gives an empty summary plus a diagnostic. Identity diagnostics are inherited.
- `car_id` uses the stable-ID grammar.
- The `.tres` round trip covers non-default Tires 2, Chassis 1 and Engine 0.
- The record makes no claims about garage, purchase or save.

**Slice 2:**
- The policy advances exactly once per COMMITTED tick, after the gearbox/`CarState` pair is published (`drive_lab.gd:1392`), witness or not.
- Adapter refusals, stale-pose blocks and post-commit gearbox failures never reach it (tracked checks, which pass).
- Inputs come only from `WallImpactProducer`: severity, `contact_normal_world_m` and region. The tracked oracle compares them.
- A suppressed tick allocates no ID or ledger entry.
- `publish_wall_event` never evaluates the policy.
- Retirement keeps policy and ledger generations equal.
- No body, motor or gearbox state is touched.

**Slice 3:**
- Winding checks out: forward −Z, right +X and up +Y give a cross product of (0, −2hw·d, 0), so Godot's clockwise front face is on top, and Jolt's one-sided collision agrees (down hits, up misses).
- Chunk ownership, segment metadata on half-open intervals, UVs and float64 stations are correct.
- All validation runs before the first `ArrayMesh` is created.
- Option keys work as both `String` and `StringName`.
- `CLOSED_LOOP_UNSUPPORTED` is unreachable today (`FrameTable.closed` is always false), so the guard is future-facing.
- Optional: UV `y` is unscaled metres in float32. Multi-kilometre courses may need a per-chunk UV origin for mediump fragment precision on GL Compatibility. This is unverified headless.

## Plan mismatches vs optional follow-ups

- **P1 (plan-level, outside slice 1's files): two sources of truth for upgrade effects.** `UpgradeDefinition` hard-codes the design coefficients and says "an upgrade record cannot carry an invented multiplier".

  The existing car-recipe contract works differently. It is defined by `schemas/handling_config_v1_1.schema.json` `upgrades.*` and `tools/car_recipe_schema/validate_car_recipe.py:1495-1560`, which require only a minimum of 1 or a 0–1 range. Its accepted fixture `tools/car_recipe_bake/fixtures/positive/finite.json` authors acceleration factors `[1.0, 1.1, 1.2]` and absolute `impact_speed_loss_factors` `[0.2, 0.15, 0.1]`, both of which differ from `docs/GAME_DESIGN.md`.

  Reconcile this before M6.2 upgrade wiring: the recipe should either validate equality with the design formulas or drop the authored arrays. This is not a defect in the candidate slice.
- **Must gate later work:** S1 (seam/ray watertightness with the real ground-support probe), S3 (normal deviation and drivability).
- **Optional:** S2, U1 (README note now; strict `.tres` check with the writer), W1, W2, the large-spacing A1 assertion, the half-ulp wording and the A3 ordering note.

## Remaining whole-milestone gates (not closed by this checkpoint)

- **M0.2:** production car and upgrade content, per-car loadout and equip state, purchases and credits, garage display of actual effects, save integration, P1 reconciliation, the `.tres` artifact writer and strict authored-file validation, and boot/menu/game scenes per PLAN M0.2.
- **M1.8:** calibrated contact identity and the corner policy (the 35° normal constant is uncalibrated), oblique, corner and multi-bay contacts, a cosmetic consumer (presentation, sound, damage), car-car production and pairing, a coordinator event stream, and multi-car scope.
- **M2.1:**
  - shoulders, barriers, thickness, skirts, end caps and LODs;
  - materials, and visual verification of culling and shading on a real renderer;
  - closed-loop residual-roll closure and seam;
  - scene integration;
  - S1 seam/ray robustness with the actual ground-support probe;
  - drivability, clearance and car tests on real courses, plus curvature/spacing gates (S3);
  - gates, AI samples and minimap.
- **Arc sampler:** any remaining items from the earlier exact-bf4 reports (for example H1 and O1) are outside this checkpoint.
- **All of these:** no GUI, audio, controller, platform, export or rights conclusion comes from these headless runs.

## Private artefacts

- **Logs:** `private/logs/*.log`
- **Probes:** `private/build/_opus_probe/`
- **Wrapper:** `private/run.sh`
- **Untouched extraction:** `private/verify`

I deleted the mutant copy and the data-lab stage directory after use. All of these are ignored under `/work/`.
