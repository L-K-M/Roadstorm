# M1 interim components and M0.2 resource recheck: Opus 5.5

Review date: 2026-11-28 CET. Verified runtime identity: first-party Claude CLI JSON modelUsage: claude-opus-5-5, provider firstParty, is_error=false, exit 0. Independent read-only review on its own immutable plain source archive; no source or Git edits.

Candidate source: `d910c725f12e4762fa5480aca6f8a00a2ceb6200` (tree `177f49a32d555199931af42ba99f7e2275ee09fa`); base `8f02cc940cf835b9ce63cdae17cd71d4acf3050a`. Both named reviewers received the same evidence packet in separate archive directories and did not read each other's current report.

Coordinator follow-up: exact-candidate [hosted CI run 46080953847](https://github.com/L-K-M/Roadstorm/actions/runs/46080953847) completed all four jobs successfully after the reviewers' evidence packets froze. The reports below correctly say export preparation was pending at freeze. Export preparation is not a target-OS launch. No whole M0/M1 or rights gate is closed.

---

# Roadstorm checkpoint review: Opus 5.5 on candidate `d910c72`

**Scope:** combined interim check of the new M1 components and a recheck of the provisional M0.2 typed resources. This is **not** M0 or M1 milestone acceptance.

## Verdicts

| Slice | Verdict |
|---|---|
| (a) Repaired provisional M0.2 resource slice | **pass** (provisional; non-blocking F6 below) |
| (b1) New M1 gearbox canonical state, restore and mirror | **pass** (non-blocking F2, F3) |
| (b2) New M1 impact event, builder and ledger contract | **changes required** (F1 only; small fix) |

**Summary:**
- All seven M0.2 repairs requested at `8f02cc9` are present in code and have their own checks.
- The DriveLab tire oracle now uses the component's geometric definition.
- The gearbox restore and mirror semantics are sound.
- The impact contract contradicts itself on what `event_id` identifies. If an integrator follows it as written, the second car's record in every car-to-car contact is silently dropped as a "duplicate".

## Identity

- **Candidate:** `d910c725f12e4762fa5480aca6f8a00a2ceb6200`
- **Tree:** `177f49a32d555199931af42ba99f7e2275ee09fa`
- **Base:** `8f02cc940cf835b9ce63cdae17cd71d4acf3050a`
- All three come from `evidence/identity.txt`. I did not run Git commands to recompute them.
- **Reviewer:** Claude Opus 5.5, model ID `claude-opus-5-5`, Anthropic, in the Claude Code CLI (Claude Agent SDK). This comes from the session's own model metadata; I had no other CLI routing data to check it against.
- **Date:** 2026-11-28.
- **How I worked:**
  - Read-only plan-mode session. No helpers or subagents.
  - I wrote nothing in `./source` and changed no Git state.
  - I did not read the live checkout or the other current reviewer's report.

## Files inspected

**Evidence packet:** `identity.txt`, `change-list.txt`, `checks.md`, `checks.sha256`, `checks/{data,drive,gear,impact}.log`, `hosted.md`, `diff.patch` (all 3,566 lines) and `../prompt.md`.

**Source:**
- `review/implementation/m1-m02-interim-opus-5-5-8f02cc9.md`. I did not open the Sol 8f02cc9 report; I took Sol's prior findings from the prompt and from `docs/STATUS.md:602`.
- `docs/evidence/m02-typed-runtime-mapping-20261127.md`
- `docs/STATUS.md:595–602`, `docs/IMPLEMENTATION_LOG.md:38`
- `PLAN.md:79`, `docs/TECHNICAL_DESIGN.md:73`
- `src/data/{car_definition,definition_identity,handling_definition}.gd` and `src/data/README.md`
- `src/simulation/{automatic_gearbox,car_state,impact_event}.gd`
- `src/audio/vehicle_feedback_synth.gd:697`
- `tools/data_lab/{validate_data_lab.gd,data_lab_checks.gd,run_validation.sh,README.md}`
- `tools/drive_lab/drive_lab_driver.gd:1800–2010, 2224`
- The `tools/gear_lab/*` and `tools/impact_lab/*` diffs
- A grep of every `gear_index` consumer

## Commands actually run

- `cat`, `sed`, `grep` and `wc` on the files above.
- `shasum -a 256 checks/*`: all four hashes match `checks.sha256`.
- `grep` on the logs for case, summary, mutant and intentional-failure lines.

I did **not** run Godot, the lab runners, Python or CI. The session was read-only, and the runners write staged copies. Every pass/fail count below is coordinator evidence, not my own execution.

## Supplied evidence assessed

| Log | What it shows | Gaps |
|---|---|---|
| `impact.log` | 11 cases / 183 checks, 0 failed; deliberate-failure probe rc=3 with its marker | |
| `drive.log` | 14 cases / 1,456 checks; bad-config 99/99; deliberate-failure probe rc=3 | The backward-coast measurements are present (raw slip 180°, oracle 0°, player −80 dB, old formula −23.6 dB). The claimed "old oracle mutant failed 11" run is **not** in the packet. |
| `gear.log` | 9 cases / 3,112 checks (`custom_config_boundaries` appears only in the JSON summary); `INTENTIONAL_FAILURE_PROOF` with three probes, including invalid-restore and null-mirror | Pure motor 17/5,309 is in coordinator private evidence and not in the packet. |
| `data.log` | 12 cases / 254 checks, 0 failed | Validator output only. It contains **no** deliberate-failure run, no direct-sentinel run and none of the "seven worker mutant controls" that `checks.md` claims. Those rest on coordinator attestation. |
| `hosted.md` | Run 46080953847 was partly complete at freeze; export preparation was still running | **Not** a CI pass. |

**Capability limits:**
- Everything above is headless, on macOS only.
- No listening, rendered-frame, controller, multi-player, Linux or Windows launch checks were performed by me or shown in the packet.

## Prior-finding disposition

| Prior finding | Status | Evidence |
|---|---|---|
| Opus F1 / Sol: out-of-range enums | **Closed** | `definition_identity.gd:71` (status), `car_definition.gd:87` (shape) and `car_definition.gd:168` (completeness) check against `Enum.values()`. `status_name()` returns `INVALID` instead of indexing out of bounds. `enum_domain_controls` covers direct negative and over-range values and a hand-written `.tres` holding 99. |
| Opus F2: attribution of nested handling diagnostics | **Closed** | `_referenced_handling_diagnostics` (`car_definition.gd:200`) prefixes identity diagnostics with `handling.`. Handling's physical paths already start with `handling.` (`handling_definition.gd:75–81`), so nothing is doubled. |
| Opus F3: nullable/unknown source mapping | **Closed as a decision** | The mapping doc and README say a baker must refuse to emit when a value is null or unknown. Handling ID is `<car_id>.handling`. Enforcement gap: F6. |
| Opus F4 / Sol: final-LF identity grammar | **Closed** | `_matches` (`definition_id_identity.gd`, last function) requires a match spanning `[0, len)`. With `$` stopping before a final `\n`, the match ends at `len−1`, so it is rejected. An embedded `\n` can never match. This is reasoning only; I did not run Godot or Python. |
| Opus F5: required deferred declaration | **Closed** | `_validate_deferred_declaration` (`car_definition.gd:214`) requires every v1 path exactly once and reports blank and duplicate entries. `["todo"]` fails. Nit F7a. |
| Sol: full round trip of the referenced handling | **Closed** | `_assert_same_handling` runs on the reloaded referenced handling, with altered-ID and altered-curve controls. Non-default contact fields are now in the fixture. |
| Sol: scratch safety for fixed basenames | **Closed** | Atomic `make_dir_absolute` gives each run a unique reserved directory (retrying on `ERR_ALREADY_EXISTS`). Cleanup touches only reserved paths. The runner seeds sentinels with noclobber. A direct run fails loudly. Nit F7c. |
| Opus F6: DriveLab tire oracle | **Closed** | `drive_lab_driver.gd:2224` is identical to `vehicle_feedback_synth.gd:697`. The backward-coast case reaches the previously divergent state (latch clear, raw slip 180°). |
| Earlier Opus F4: `gear_index` and cooldown | **Resolved by design** | `CarState.gear_index` defaults to 1. `GearboxState` is canonical. Restore and mirror are tested. No other code reads `gear_index` (the grep found only motor copy tests). |

## Findings, most severe first

### F1. Medium (M1.8 impact contract): `event_id` is defined per physical contact, but each record covers one primary car, so car-to-car contacts lose a record

- **Where:**
  - `impact_event.gd:82`: "Stable unique identity of this physical contact."
  - `impact_event.gd:341–347`: the ledger coalesces on ID.
  - `impact_event.gd:279`: the ledger doc says "first retained event wins".
  - `TECHNICAL_DESIGN.md:73`: "unique contact/event ID".
- **Why it breaks:**
  - Region, local point, severity and imparted motion all describe only the primary car.
  - A car-to-car contact therefore needs two records: (A, other B) and (B, other A).
  - If both carry the documented per-contact ID, B's record comes back `COALESCED` and is never retained.
  - Nothing distinguishes a coalesced *conflicting* record from a true repeat.
- **Test evidence:** `_case_duplicate_event_id` (`impact_lab_driver.gd:185`) asserts exactly this. A same-ID record with severity 9.5 is silently coalesced, and the first record wins.
- **Reproduction:**
  1. Build two valid events with the same `event_id` and tick: one with primary `a` / other `b`, one with primary `b` / other `a`.
  2. Publish both.
  3. The second returns `is_coalesced()`, `event_count() == 1`, and `b` has no damage record.
- **Fix:**
  - Define `event_id` per (contact, primary car). Optionally add a separate `contact_id` that links the two records.
  - Treat a same-ID record whose content differs as a distinct outcome (`CONFLICT` refused, or at least a distinct reason and counter). Coalesce only exact repeats.
  - Add a two-perspective car-to-car test and a conflicting-duplicate test.

### F2. Low (gearbox): restore and mirror are documented as one atomic step but are two separate fallible calls

- **Where:** `automatic_gearbox.gd:63` and `car_state.gd:19–27` say "repair the mirror as one explicit atomic step". `restore_state` (`:279`) commits immediately, and `mirror_gear` (`:299`) can then return `null`.
- **Reproduction:** `restore_state(valid)` returns true, then `mirror_gear(car_with_nan)` returns `null`. The gearbox has been restored, but no repaired `CarState` exists.
- **Fix:** add `restore_and_mirror(state, car_state) -> CarState` that validates both inputs before mutating anything, or reword the documentation to make the caller responsible for ordering.

### F3. Low (gearbox, documentation): `propose()` commits state, so "stale/foreign proposal" protection is narrower than it reads

- **Where:** `propose()` mutates `_state` (`:383–388`). The "no proposal enters this API" argument (`:62–68, 291–296`) is true but does not cover the real risk.
- **The real risk:** if an integrator calls `propose()` and then abandons that tick, the canonical gear and dwell are ahead of the committed `CarState`.
- **No identity binding:** `mirror_gear` stamps this gearbox's gear onto *any* finite `CarState`, including another car's.
- **Fix:** document that `propose()` is a commit step, to be called only once per committed tick and only on that car's committed record. An optional evaluate/commit split is up to you.

### F4. Low (impact, overstated claims)

- **`committed` is a caller's assertion, not proof of authority.** `committed` (`:105`) says "True only for records built from an authoritative committed source". In fact it is `Builder.source_committed` (`:239`) or a public field that any caller can set.
- **The severity test cannot catch a wrong derivation.** `_case_contact_only_severity` (`impact_lab_driver.gd:342`) computes the oracle locally and checks that the builder passes the value through. It cannot detect a motor-derived severity, so "distinction" overstates what it tests.
- **Fix:** reword both as caller obligations, and move the derivation check to the future integration test.

### F5. Low (ledger domain edges)

- **No forward or current-tick bound.** A stray far-future tick (for example `1<<40`) is accepted. It then holds one of the `max_retained_ticks` slots indefinitely, because pruning always removes the oldest tick.
- **Constructor clamping can be bypassed.** `per_tick_capacity` and `max_retained_ticks` (`:307–308`) are public and mutable. Setting `max_retained_ticks = 0` after construction makes a later `publish` report `PUBLISHED` while pruning the record immediately.
- **Fix:** make both settings private and read-only after `_init`. Optionally refuse ticks above a caller-supplied current tick.

### F6. Low (M0.2): the derived handling-identity rule is not enforced, and the fixture contradicts it

- **The rule:** handling ID `<car_id>.handling`, with the car's revision, schema and status.
- **Not enforced:** `CarDefinition.validate_car` does not check it.
- **Fixture conflict:** `data_lab_checks.gd:64` uses `example.data_lab.handling` for car `example.data_lab.car` (`:92`), where the rule gives `example.data_lab.car.handling`.
- **Fix:** either validate the derivation, or state explicitly that it applies only to baker output and align the fixture. Not blocking for a provisional slice.

### F7. Nits

- **a.** `strip_edges()` at `car_definition.gd:218` accepts `"  body.mesh "` as declaring `body.mesh`. That is a small repair of authored content, against the README's "never partially repairs".
- **b.** `DefinitionIdentity._enum_value_names` is underscore-private but called from `CarDefinition`.
- **c.** `_remove_directory_tree` (`validate_data_lab.gd:1251–1268`) has two edge cases:
  - `current_is_dir()` would recurse into a symlinked directory placed inside a reservation.
  - Hidden entries are not listed, so cleanup can leave a directory behind. The `dir_exists` check would at least fail loudly.
- **d.** `impact_lab_driver.gd:463` asserts that `motor_body_adapter.gd` does not contain `wall_contact_point`. It will fail by design when the wall-point job lands, so it is a tripwire that must be updated in that change.
- **e.** `TECHNICAL_DESIGN.md:73` says "road/local contact point", but the record carries world and local points.

## Safety and integrity observations

- **No false-success harness.** Each new runner stages a private `mktemp` copy, strips `.godot`, and requires a deliberate-failure marker.
- **Scoped cleanup.** The impact runner's `rm -rf` is limited to its own `$stage`.
- **Gearbox restore validation** rejects config-mismatched gear and dwell values and NaN or INF. Every state that `propose()` can produce is restorable: cooldown is exactly `_min_shift_dwell_s` or decremented toward 0, and rpm is clamped.
- **Impact builder:**
  - Defaults are deliberately invalid (NaN severity, zero normal, uncommitted).
  - `NORMALIZE` refuses zero and nonfinite normals.
  - Region range is checked.
  - The ledger stores and returns copies.

## Remaining M0 and M1 gates (open; not defects of this candidate)

- **M1 integration:**
  - the wall-contact-point adapter seam;
  - the one-car gearbox/`CarState` integrator. Both jobs are unreviewed and absent from this candidate.
  - the impact producer and the cosmetic consumer;
  - impact event-ID allocation (F1).
- **M1 behaviour:**
  - support adhesion and landing;
  - floor- and ramp-aware orientation;
  - multi-wall corners;
  - scrape feel;
  - reset placement;
  - drift, surge, drafting and gear calibration.
- **Verification:**
  - real controllers;
  - rendered frame traces;
  - listening tests;
  - Linux and Windows launches;
  - final hosted CI on `d910c72`.
- **M0.2:**
  - the importer/baker and its conversion tests;
  - content hashes and provenance;
  - the track, event, upgrade, AI, ghost and scenario resources;
  - every field in `DEFERRED_FIELDS_V1`.
- **M0.3:** output-rights items OI-02 and OI-03.
- **Whole milestones:** M0 and M1 acceptance remain open.

## Recommended fixes

- **Required before the impact contract is integrated (F1):**
  - Redefine `event_id` as per (contact, primary car).
  - Make conflicting duplicates a distinct refused or flagged outcome.
  - Add a two-perspective car-to-car test and a conflicting-duplicate test.
- **Optional, low risk:**
  - F2: add a combined restore-and-mirror call.
  - F4: reword the `committed` and severity-test claims.
  - F5: make the ledger configuration read-only after construction.
  - F6: enforce the handling-ID derivation or scope it to baker output and align the fixture.