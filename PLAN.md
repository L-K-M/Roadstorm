# Roadstorm Racer! implementation plan

Planning baseline: 26 November 2026, revised after ten independent reviews. Status: ready for implementation; no game milestones completed. This plan and its five companion specifications define the proposed 1.0 game. Numerical handling, economy, and performance figures remain initial targets to validate, not claims about a build. [Review responses](docs/REVIEW_RESPONSE.md) record the adopted changes and disputed recommendations.

Build an original desktop arcade racer that makes a short race feel like a journey: an inviting drift through a coastal bend, a mountain climb into a waterfall reveal, and close racing with friends. Prove the driving and four-player experience early, then use reproducible production tools to expand the game.

## Product commitments

| Area | Version 1.0 commitment |
| --- | --- |
| Driving | Forgiving, expressive grip and drift handling; automatic transmission; readable bumps, jumps, and fast recovery |
| Cosmetic damage | Impact-loosened/detached bumpers, sliding/tumbling debris and sparks; handling stays governed by the intact car configuration |
| Racing | Standard eight-car fields with two learned Roadstormers by default; three difficulties and shared limits; optional humans-only Quick Race has zero AI |
| Local play | One to four players; four gamepads or keyboard plus three gamepads; a single shared simulation |
| Courses | Six original authored circuits with elevation, changing width, varied corner rhythm, and animated landmarks |
| Vehicles | Twelve fictional cars with distinct silhouettes and handling; three starters and nine deterministic unlocks |
| Progression | Three regional cups and a final six-race tour; credits and six optional upgrade purchases per car |
| Modes | Quick Race, Championship, Time Attack, Arcade Rush, and Practice |
| Presentation | Flat-shaded low-polygon geometry, strong palettes, simple generated textures, original synth music and effects |
| Platforms | Native macOS on Apple Silicon, Windows x86-64, and Linux x86-64; keyboard and gamepad menus |
| Distribution | Offline play, portable source and build instructions, no account or online service requirement |
| Rights | Original code under the Unlicense; original art/audio dedicated under CC0; complete third-party notices |
| Authorship | Every new project-specific script, asset recipe, composition, design, and test produced by LLM agents |

The gameplay specification is in [GAME_DESIGN.md](docs/GAME_DESIGN.md). Engineering decisions/tests are in [TECHNICAL_DESIGN.md](docs/TECHNICAL_DESIGN.md); shared references, fixtures, metrics and tolerances are in [BENCHMARKS.md](docs/BENCHMARKS.md). Traditional and learned rivals are specified in [OPPONENT_AI.md](docs/OPPONENT_AI.md). Asset production and rights are in [ASSET_PRODUCTION.md](docs/ASSET_PRODUCTION.md). A change affecting shared rules updates all affected documents together.

### Meaning of LLM production

Agents write the game, author the source recipes, generate the assets, compose the music, inspect results, and fix defects. Procedural assets produced by LLM-written programs count as project-specific LLM production. Godot, operating systems, compilers, and build tools are existing infrastructure; rebuilding that infrastructure is outside the project.

People may direct the work, provide credentials, play the game, report observations, and make release decisions. No manual modeling, coding, composing, or editing is required by the production plan. Keep an authoring record instead of claiming that generated material has guaranteed originality or copyright status. The baseline uses no downloaded creative asset packs or sampled music.

### Scope boundaries

Version 1.0 includes finished courses and simple cosmetic part damage. Defer online multiplayer, rollback networking, mobile and console ports, steering-wheel force feedback, VR, a working-instrument cockpit, licensed vehicles, pedestrians, traffic simulation, combat, police pursuits, mechanical damage/repair economy, complex tuning, dynamic weather physics, a public mod editor, and a photo/video editor. Reverse courses and route branches can follow after release. Cosmetic bumpers/debris do not add damage-dependent handling.

## Delivery principles

1. Finish one useful experience at a time. Each milestone produces a runnable build, evidence, and an updated status record.
2. Do not expand content until the handling, production pipeline, and four-camera cost have passed their gates.
3. Keep the simulation independent from cameras, sound, UI, and scenery animation. An audiovisual improvement cannot change a race result.
4. Use structured text and generation scripts as the source of truth. Generated meshes, audio, previews, and distribution files must have traceable inputs.
5. Treat licensing and accessibility as production requirements from the first asset and menu.
6. Separate automatic verification from experience review. A successful bot race cannot establish that a drift is enjoyable or a soundtrack sounds good.

## Milestone dependencies

M0 establishes tools and proves tick/reset control; M1 proves the car and handling fixtures; M2 proves course tools and the shared AI contracts. M3 has separate simulation/rendering and physical-controller evidence. M4 may proceed after M3's technical gate while missing hardware checks remain open. Its late-stage teacher enables a bounded learning feasibility spike. M4B completes two learned styles alongside independent M5 art/audio/menu preparation; integrated M5 acceptance still requires both learned styles and actual controller verification. M6 and M7 then proceed against frozen interfaces. M7 prepares training candidates; M8.1 balances/freezes launch handling before M8.7 final training and evaluation. M9 packages/releases.

The numbers are work order, not calendar promises. M1, M3, M4B, and M5 are deliberate decision gates: resolve their failures before committing to bulk content. Record effort after each completed milestone to estimate the remaining work from actual project experience.

## M0 establish the project

**Result:** a reproducible empty game shell with clear rights and reliable checks. Dependency: none.

- [x] M0.1 Pin Godot 4.7.2 Standard, matching templates, built-in Jolt/settings and asset-generation Python, with checksums. Verify before installation; update only through a recorded regression decision. The [official archive](https://godotengine.org/download/archive/) is the version authority. Scoped decision and verify-before-private-install evidence: [M0.1 pin decision](docs/evidence/m01-pin-decision-20261127.md).
- [ ] M0.2 Create `project.godot`, a boot scene, game/menu scenes, typed resource schemas, the planned directory structure, and ignore rules for caches and local credentials.
- [ ] M0.3 Preserve the Unlicense; add explicit material-specific CC0 scope, owner/contributor authority basis, provider-terms intake for all LLM-authored work, dependency inventory and provenance manifests. Extract actual pinned-runtime notices; never invent signatures or rights holders.
- [ ] M0.4 Build original command-line import, test, content-validation, capture, and export entry points. A deliberately failing test must return a failing exit code.
- [ ] M0.5 Add CI for resource/script checks, tests, asset validation, and native export preparation. CI must run from a clean checkout without editor interactions or generation-service accounts.
- [ ] M0.6 Record machines/OS/controllers, provisional renderer and capture methods. Inventory visual/audio/control review capabilities; make M3's representative tests authoritative for renderer selection.
- [ ] M0.7 Establish `docs/STATUS.md`, an evidence directory, decision records, and task ownership for collaborating agents.
- [ ] M0.8 Build a minimal coordinator/query/reset probe: twelve logical ticks per nonterminal training-style request, early stop with elapsed-tick count on termination/truncation, zero advancement while waiting, complete reset and measured accelerated-versus-real-time fidelity before the motor depends on it.
- [ ] M0.9 Create versioned handling/AI/reference/scenario schemas and fixture configurations from BENCHMARKS; schema definitions do not require a working AI implementation yet.

**Acceptance:** a second agent can follow the setup guide, import, run the boot scene, execute a passing and a failing check, and export a desktop smoke build. The license inventory identifies the runtime separately from original project material. No dependency or creative input has unknown terms. Record missing target hardware explicitly; an untested platform does not become verified through a successful export.

## M1 prove the driving

**Result:** a driving laboratory worth iterating on. Dependency: M0.

- [ ] M1.1 Implement the custom motor and normalized commands using the coordinator/movement API contract; record acceleration/drag/grip/drift/surface parameters and dimension/contact envelopes, then implement controls, gears and reset.
- [ ] M1.2 Build graybox straights, broad sweepers, hairpins, a bank, a crest, a jump, a compression, walls, gravel, shoulders, and a recovery zone.
- [ ] M1.3 Add explicit drift entry, sustain, transition, exit, and capped exit surge; expose tuning resources and telemetry.
- [ ] M1.4 Implement bounded ground adhesion, swept movement, landing recovery, gentle side contact, and strong-impact response. Presentation suspension cannot throw the simulation body.
- [ ] M1.5 Add chase/near/hood cameras, rear view, speed readout, drift cues, and basic synthesized engine/tire feedback.
- [ ] M1.6 Capture keyboard and controller runs, telemetry traces, and a handling comparison report using the three starter configurations.
- [ ] M1.7 Build CalibrationDriver and immutable sweeper/hairpin/esses/surface/contact/drafting fixtures; compare surge candidates and stock/max loadouts with the declared tolerances. Offer a play/feedback checkpoint without requiring manual implementation.
- [ ] M1.8 Publish committed impact events with contact region, severity and imparted motion for later cosmetic damage; presentation never feeds a second contact impulse into the motor.

**Acceptance:** the Standard-assisted fixture driver repeatedly enters/recovers a 12–40 degree drift and retains useful speed/control. Grip/drift comparison passes the 5% sweeper target and reports other corner classes/mixed laps; surge/drafting have measured effects. Contacts, crests, reverse and resets pass without tunneling/nonfinite/stuck states. The 30/60/120 FPS trace meets BENCHMARKS tolerances. Capability-labeled independent motion/control review records the experience limits; bot completion alone cannot certify fun.

## M2 build the course and geometry pipeline

**Result:** source data can reliably become a driveable, scenic course. Dependency: M1.

- [ ] M2.1 Implement the road spline format, arc-length samples, variable width, grade, banking, surfaces, shoulders, barriers, and chunked mesh/collision baking.
- [ ] M2.2 Generate ordered checkpoint gates, start grid, sector timing, progress samples, reset anchors, and AI line/speed hints from the same road definition.
- [ ] M2.3 Implement validation for seams, discontinuities, unsafe gaps, overhead clearance, illegal intersections, invalid reset points, and scenery in driving space.
- [ ] M2.4 Build reusable original road, terrain, tunnel, bridge, tree, cliff, sign, and barrier generators with LOD and instancing support.
- [ ] M2.5 Author the full Riviera Run route in graybox, with all its elevation and width changes, three landmark placements, and complete recovery boundaries.
- [ ] M2.6 Add automated course flythroughs, minimaps, car turntables, contact sheets, and asset manifest generation.
- [ ] M2.7 Validate closed-loop frame closure, actual car/grid/clearance envelopes, gate/runoff legality and tagged course-rhythm features; ratify shared observation/intent schemas before M4.2.

**Acceptance:** Riviera laps have no seam or progress jumps; overpass and blocked-anchor fixtures pass. Broken geometry/course-contract fixtures fail validation. Another agent generates an alternate loop without changing generator code. Canonical-toolchain regeneration matches normalized hashes; cross-host semantic tolerances are separate. Record measured Riviera lap/reference splits before final art.

## M3 prove four local players

**Result:** four independent players race in one world at the provisional performance target. Dependencies: M1 and M2.

- [ ] M3.1 Implement device-to-player ownership, joining, readying, car selection, leaving, remapping, per-device deadzones, and persistent preferred controls.
- [ ] M3.2 Render one shared world through one to four viewports. Implement all split layouts, native-resolution HUD overlays, and a nonrendered spare quadrant for three players.
- [ ] M3.3 Add global pause, disconnect/reconnect/reassign handling, focus loss and current-attempt retirement; explicit Local Cup withdrawal converts its slot to AI only at the next event.
- [ ] M3.4 Run eight cars on representative route sections with provisional drivers. Stress scenery, the pooled cosmetic-debris/spark limits using proxy fragments, and shared audio mixing within the existing frame/voice budgets.
- [ ] M3.5 Measure the worst four-camera scene and remove duplicate rendering, simulation, assets, or audio work. Freeze a documented rendering budget.

**Acceptance has two records:** technical simulation/rendering/audio/routing must pass representative eight-car/four-view frame-time and mix gates, locking renderer/player-count presets. Actual-device verification must pass four gamepads and keyboard-plus-three-gamepad ownership/reconnect/remapping. Synthetic inputs cannot replace hardware. M4 and independent work may start after the technical record passes; missing physical evidence keeps that portion open and blocks integrated M5 acceptance/release. All layouts remain readable at 1080p including 150% HUD scale and held rear view.

## M4 complete racing and traditional opponents

**Result:** a complete, replayable race from grid to results. Dependencies: M2 and M3's technical gate; physical controller evidence may complete in parallel before M5 acceptance.

- [ ] M4.1 Implement the race state machine, countdown, validated laps, ranking, finish deadlines, ties, DNF, restart, and results.
- [ ] M4.2 Implement Classic planning through the shared AIObservation → TacticalIntent → safety/follower → DriverCommand interface from the start, including drift/drafting/overtake/recovery decisions and demonstration telemetry.
- [ ] M4.3 Publish five-run calibration references and tune three difficulties/four Classic personalities against their desired speed profiles, perception ages and unchanged physical limits.
- [ ] M4.4 Complete paired vehicle contacts, respawn immunity, wrong-way warnings, stuck detection, and shortcut protection.
- [ ] M4.5 Add a seeded race harness with contact, recovery, progress, pacing, and input telemetry; add diagnostic replay captures.
- [ ] M4.6 As soon as a stable teacher exists, run the bounded bridge/actor/learning spike in parallel with late M4 and M5 preparation. Measure throughput, inference cost and actual cloned-versus-learned behavior before extended training; estimate T11's wall/core-hour cost.

**Acceptance:** at least 100 seeded races per difficulty on the slice route complete without race-state deadlocks. With finish deadlines disabled for mechanical evaluation, at least 99% of AI entries finish, and no route point repeatedly requires a recovery. Separately measure legitimate deadline DNFs against reference player paces. Dedicated blocking, narrow-pass, jump, and collision scenarios show no deliberate ramming, hidden speed changes, or teleporting catch-up. Test skipped gates, reverse crossings, resets, simultaneous finishes, pause, and abandonment. Review close-racing footage from both player and overhead cameras.

## M4B train learned Roadstormers

**Result:** two special opponent styles use a small original learned tactical policy during races. Feasibility starts in late M4; accepted slice training uses frozen starter handling and M4's contracts. Independent M5 preparation can overlap. Full design/budgets: [OPPONENT_AI.md](docs/OPPONENT_AI.md).

- [ ] M4B.1 Ratify the already-defined shared schema, learning/reward/difficulty/style configuration, safety metrics and matched scenarios; freeze starter handling and collect balanced original intent demonstrations.
- [ ] M4B.2 Build and validate a local-only headless Godot training bridge with explicit step/reset/timeout/shutdown semantics, then measure its throughput before a long run.
- [ ] M4B.3 Pin the development-only learning toolchain; implement behavioral cloning followed by PPO training from original simulation data and random initial weights.
- [ ] M4B.4 Export a small policy's numeric weights and normalization; implement original GDScript inference and verify parity with the training implementation.
- [ ] M4B.5 Produce pressure-oriented Surge and patient-cutback Switch styles, with shared low-level control, difficulty settings, and physical limits.
- [ ] M4B.6 Add mixed fields, roster identification, Classic Only preference, policy safety/failure handling, model cards, and repeatable evaluation scenarios.
- [ ] M4B.7 Evaluate held-out situations against matched Classic baselines, review full-race clips, and record training cost and remaining generalization risks.
- [ ] M4B.8 Respect the three-iteration pilot and cumulative compute caps; publish learning curves/failures and a concrete next decision at exhaustion. Do not hide failure behind endless retraining or remove required Roadstormers.

**Acceptance:** real learned inference is active for two rivals on Riviera; no runtime cloud/model service is needed. Exported inference passes numerical parity tests, safety failures cannot corrupt racing, and learned rivals pass the slice completion/contact/pace criteria. Both styles show readable tactical differences in held-out traffic scenarios. A safe Classic fallback keeps an exceptional faulty race playable, but does not close this feature. Full six-course generalization and release model acceptance remain required in M7/M8.

## M5 finish the vertical slice

**Result:** a small version of the intended finished game. Preparation depends on M1–M4's relevant interfaces; integrated acceptance additionally requires M4B and M3 physical-device evidence.

- [ ] M5.1 Finish Riviera Run's beach, village, marina, tunnel, lighting, road signage, flyover, and scenery animation.
- [ ] M5.2 Finish the three starter cars' visuals, LODs, paints, thumbnails and engine families against frozen slice handling; physics changes reopen affected AI/handling evidence.
- [ ] M5.3 Finish menu → join → select → race → results → rematch flow, a short playable driving tutorial, basic settings, and a real save round trip.
- [ ] M5.4 Finish the first original race composition, menu/results themes, tires, contacts, environmental audio, and a balanced four-player mix.
- [ ] M5.5 Complete original HUD typography, player markers, drift feedback, minimap, transition effects, and accessible readability settings.
- [ ] M5.6 Have an agent other than each feature's implementer review the integrated build, footage, audio previews, performance evidence, and provenance.
- [ ] M5.7 Demonstrate the mixed field of Classic Racers and Roadstormers and a comparison race with Classic Only, including readable rival identities and both learned styles.
- [ ] M5.8 Complete preliminary title/car/rival-name screening before final badges/cards, and a capability-verified look/listen/rights package proof. Keep screening limitations and any unresolved experience review explicit.
- [ ] M5.9 Finish cosmetic damage on all three starter cars: detachable front/rear bumpers, optional rear wing, shared sliding/tumbling debris, sparks and synthesized rattles/scrapes. Verify repair-on-reset/new-grid, pool saturation, four-player readability and authoritative-state isolation before extending it to all cars.

**Acceptance:** single-player and four-player sessions work from a fresh launch without developer intervention. The slice meets the handling, fairness, visual, audio, and performance criteria. Every asset has a source recipe and approved record. A reviewer can explain each car's handling identity and recognize at least three distinct Riviera landmarks. Record unresolved subjective feedback honestly; do not expand content to conceal a weak driving model.

## M6 implement modes and progression

**Result:** the complete game structure works with temporary references to future content. Dependency: M5; can overlap M7 asset authoring.

- [ ] M6.1 Implement all five modes, configurable Quick Race, solo career cups, local exhibition cups, Arcade Rush checkpoints, Time Attack records, and sampled ghosts.
- [ ] M6.2 Implement twelve cars, defined cup-result unlocks, deterministic style/credit rewards and upgrade formulas, reversible loadouts, paints and stock medal sessions.
- [ ] M6.3 Implement four local profile slots/guest, explicit room/device/player settings ownership and host succession; rewards belong only to the selected solo Career/solo Quick Race profile, never local exhibition.
- [ ] M6.4 Add one-writer versioned saves, event IDs allocated before GO, monotonic generations, tested replacement/backups/recovery, write-failure handling and reward acknowledgement boundaries.
- [ ] M6.5 Complete settings, tutorial prompts, progress explanations, medal targets, garage stat comparisons, licenses, and controller-only navigation.
- [ ] M6.6 Run economy simulations and interruption tests; document expected unlock and upgrade pacing.

**Acceptance:** the unlock graph reaches twelve cars, permits recovery from poor results and never spends upgrade credits to access a car. One standard finish buys an upgrade; the documented economy reference takes roughly eight. Short/long Quick Race rewards scale with laps. Durably acknowledged results survive interruption and cannot apply twice; a pre-acknowledgement interrupted attempt may require replay. Startup recovery follows the deterministic generation/conflict rules and preserves the last usable copy. Exhibition loaners never change career records; incompatible records/ghosts are separated.

## M7 produce the full content

**Result:** all launch courses, cars, music, effects, and events are finished. Dependency: M5, with mode integration from M6.

- [ ] M7.1 Prove a second contrasting course/car/music/HUD/mix bundle, including source edits and full regeneration; record production/review effort before scaling. Then finish Alpine/Emerald and three cars with the established tools.
- [ ] M7.2 Produce Canyon Voltage and Metro Sunset, plus three cars. Reuse shared props while preserving unique silhouettes, palettes, and road rhythms.
- [ ] M7.3 Produce Stormpeak Finale and the final three cars. Reserve the hardest sequences for the finale while retaining forgiving recovery space.
- [ ] M7.4 Finish six race themes, all environment kits, animated spectacles, final previews/minimaps, paint sets, effects, and release graphics.
- [ ] M7.5 Populate the exact championship schedule, car unlock awards, per-course Arcade Rush timing, and stock Time Attack medals.
- [ ] M7.6 Validate the full car/course matrix at stock and maximum upgrades, targeted intermediate upgrade boundaries, pairwise layout/difficulty/assistance combinations, and curated stress cases; perform separate art, audio, route-readability, and rights reviews.
- [ ] M7.7 Prepare expanded training data and provisional checkpoints, preserving whole-course/seed holdouts; estimate bounded final-training cost. These are candidate models until M8.1 handling freeze and M8.7 acceptance.
- [ ] M7.8 Complete detachable bumper assets, attachment/impact regions and damage LODs for all twelve cars; validate appearance, pooled debris/mix cost and identical gameplay behavior with cosmetic damage enabled/disabled.

**Acceptance:** six distinct circuits and twelve finished cars exist; no required content is a placeholder. Each course passes its track contract and has three major set pieces. All modes reference valid content. Every course supports stock starter cars and eight-car fields; narrow sections do not force unavoidable collisions. The complete shipped asset set passes the manifest/license check. Performance is rechecked as each course lands rather than deferred to the end.

## M8 balance and validate the complete game

**Result:** a release candidate with evidence against the full specification. Dependencies: M6 and M7.

- [ ] M8.1 Tune parity, drift/grip, upgrades, AI/cup pace, rewards and per-car Arcade Rush budgets; publish references and freeze the launch motor/car/surface/course candidate before final model training/evaluation.
- [ ] M8.2 Finish accessibility checks, remapping edge cases, four-player HUD readability, camera comfort, audio headroom, and complete menu flows.
- [ ] M8.3 Profile each course at one, two, three, and four players; reduce excess draw calls, overdraw, memory, physics work, and audio voices.
- [ ] M8.4 Run the release verification matrix, long-session tests, save corruption/migration cases, content regeneration, offline play, and clean-machine tests on each supported OS.
- [ ] M8.5 Resolve all crash, progress-loss, controller-blocking, rules, and licensing defects. Record any remaining low-severity limitations and the exact tested configuration.
- [ ] M8.6 Audit all project-authored work for its source record and all third-party components for applicable notices, including fonts, encoders, plugins, and export templates.
- [ ] M8.7 Within the declared final allocation, train or demonstrate compatibility on the frozen candidate; close course/difficulty completion, contact/pace, intervention, useful style and four-view inference gates. Later physical changes reopen compatibility and only necessary bounded retraining.

**Acceptance:** all blocking verification cases pass, the performance gates hold on recorded hardware, and a two-hour mixed-mode session shows no progressive memory growth or loss of input. No unresolved issue can corrupt progression, invalidate race results, or prevent a supported input configuration from playing. LLM visual/audio review and any available player feedback are recorded separately from automatic checks. If there has been no independent human playtest, report that limitation without calling bot results proof of enjoyment.

## M9 package and release

**Result:** downloadable desktop builds and a reproducible public source/asset package. Dependency: M8.

- [ ] M9.1 Generate native release exports with a version/build identifier, checksums, correct icons, full notices, and offline license screens.
- [ ] M9.2 Verify macOS Apple Silicon, Windows x86-64, and Linux x86-64 packages on their target operating systems using the stated supported versions.
- [ ] M9.3 Use Developer ID signing/notarization when credentials are available; otherwise use built-in ad-hoc signing and label the package unnotarized. Test a downloaded/quarantined package, document launch steps and keep secrets outside the repo.
- [ ] M9.4 Publish source recipes, generation instructions, dependency versions, asset provenance, control guide, accessibility guide, known issues, and release notes with the builds.
- [ ] M9.5 Generate screenshots and a short trailer from actual gameplay; show local split-screen and representative courses. No images should depict absent game features.
- [ ] M9.6 Confirm the final product title and release destination with the owner if those have changed. The chosen working title is Roadstorm Racer!; public-domain dedication is not trademark clearance.
- [ ] M9.7 Prepare the complete release artifact and review report, then publish when publication is authorized. Building and verifying packages does not require an intermediate permission request.

**Acceptance:** a fresh user can download, launch, join, race, save, restart, and access licenses offline. Distribution archives include only intended files and required notices. Every public platform claim has corresponding test evidence. The release statement correctly distinguishes original public-domain material from the engine and dependencies.

## How agents execute the plan

At each milestone, a coordinating agent chooses dependency-ready tasks and assigns exclusive file ownership in the shared checkout. Do not create a branch/worktree per agent. Serialize overlapping edits/shared integration and keep central scenes/schemas/settings under one integrator. Commit owned ready paths with `--only`, preserve others' staged work and never rewrite shared history as a shortcut. [plan/IMPLEMENTATION.md](plan/IMPLEMENTATION.md) defines end-to-end execution, primary Step 5 Preview/Longcat workers through pi, quota-available free/GLM/SWE workers (SWE through local Devin), and mandatory independent **Opus 5.5 plus GPT-6.2 Sol** implementation reviews at regular checkpoints. Each worker/reviewer stays in its own chat without nested subagents. REVIEW_PROMPT applies to independent plan reviews, not the implementation assignment.

| Agent responsibility | Typical independent work | Review evidence |
| --- | --- | --- |
| Integration | Shared schemas, scene wiring, milestone build, status and decisions | Clean import, complete flows, regression report |
| Driving and racing | Motor, classic AI, learned-policy training/inference, contacts, timing, ranking, ghosts | Telemetry, model cards, held-out evaluation, scenario checks, race captures |
| Content and presentation | Course/car recipes, props, UI, cameras, effects | Flythroughs, turntables, contact sheets, budgets |
| Audio and rights | Synthesizers, original scores, mix, manifests and notices | Audio previews, meter reports, source/rights audit |
| Independent reviewer | Failure cases, visual/audio review, platform checks | Findings with reproduction steps and retest results |

Roles can be performed sequentially when fewer agents are available. A reviewer should not merely reread an implementer's claimed success. Reproduce the behavior from the build and source inputs. Changes affecting a shared contract land before dependent implementation; content recipes can then be produced independently.

Each task record includes its milestone/task ID, scope, input versions, changed files, regeneration commands, tests, capture/evidence paths, limitations, and review result. Record model/provider/date when available; never invent missing model metadata. Keep prompts and useful structured summaries rather than secrets or private reasoning. Generated assets reference their recipe and content hash. Model training additionally records compute usage and the approved checkpoint, and never creates an open-ended paid-compute dependency.

The coordinator closes a milestone only after its checks and experiential reviews pass. Update `docs/STATUS.md` with completed tasks, open defects, the current runnable build, measured performance, and the next task. A milestone may remain open while unrelated tooling progresses. Do not replace a failed gate with a larger batch of generated content.

## Risks and decision gates

Five consolidated feasibility packages cover the reviewers' overlapping proposals: M0/M1 exact-tick/reset/query/throughput probe; M1/M2 handling/contact/progress/reference fixtures; late M4/M4B bounded learning/semantic-style comparison; M3 four-view/controller/audio/font stress; M5/M7 first/second production and rights dry runs. Record inputs, maximum work/compute, pass criteria and the decision each unlocks before execution. None has been run by this planning revision.

| Risk | Early evidence | Required response |
| --- | --- | --- |
| Drifting is technically stable but uninteresting | M1 grip/drift comparison, keyboard/controller captures, reviewer feedback | Refine handling and feedback before course expansion |
| Four cameras exceed budget | M3 representative stress scene and target-hardware measurements | Reduce rendering/scenery cost and choose the measured renderer before bulk assets |
| Learned rivals exploit rewards or duplicate Classic behavior | M4B held-out tactical tests, safety interventions, full-race comparison | Revise observations/reward/curriculum and retrain; keep the gate open |
| Training is too slow on local hardware | M4B measured pilot throughput and bounded experiment | Batch/parallelize environments and simplify the model/scenarios before increasing compute |
| Procedural content feels repetitive | Second-course proof and independent silhouette/route review | Revise source recipes and scene composition, not just random seeds |
| Audio passes meters but sounds poor | M5 preview and in-game four-player review | Revise composition, timbre, loops, and mix before the full soundtrack |
| Target hardware, controllers, or signing credentials are unavailable | M0 inventory and M3/M9 checks | Complete independent work, retain unverified status, and request only the missing resource when needed |
| A creative input cannot be dedicated or redistributed | Manifest validation at intake | Replace it with an original generated asset; do not carry an unknown license to release |

The user can change scope at any time. Record scope changes with their effects on content, tests, and milestone dependencies; do not silently remove a requested feature to mark a milestone complete.

## Project completion criteria

The project is complete when M0–M9 meet their acceptance gates, the game matches the linked specifications, and the release package is available at the authorized destination. Source availability, reproducible asset generation, and accurate license notices are part of the deliverable. No online service, paid asset subscription, or remote generative service is required to build or play the baseline game.
