# Roadstorm Racer! implementation plan

Planning baseline: 26 November 2026. Status: ready for implementation; no milestones completed. This plan and its four companion specifications define the proposed 1.0 game. Numerical handling, economy, and performance figures are initial targets to validate in the playable milestones, rather than claims about an existing build.

Build an original desktop arcade racer that makes a short race feel like a journey: an inviting drift through a coastal bend, a mountain climb into a waterfall reveal, and close racing with friends. Prove the driving and four-player experience early, then use reproducible production tools to expand the game.

## Product commitments

| Area | Version 1.0 commitment |
| --- | --- |
| Driving | Forgiving, expressive grip and drift handling; automatic transmission; readable bumps, jumps, and fast recovery |
| Racing | Eight-car fields; traditional racers plus two learned Roadstormers by default; three difficulties and shared physical limits |
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

The gameplay specification is in [GAME_DESIGN.md](docs/GAME_DESIGN.md). Engineering decisions and tests are in [TECHNICAL_DESIGN.md](docs/TECHNICAL_DESIGN.md). Traditional and learned rivals are specified in [OPPONENT_AI.md](docs/OPPONENT_AI.md). The complete asset inventory, generation process, and licensing gates are in [ASSET_PRODUCTION.md](docs/ASSET_PRODUCTION.md). Those documents resolve details behind this roadmap; a change affecting their shared counts or rules must update all affected documents together.

### Meaning of LLM production

Agents write the game, author the source recipes, generate the assets, compose the music, inspect results, and fix defects. Procedural assets produced by LLM-written programs count as project-specific LLM production. Godot, operating systems, compilers, and build tools are existing infrastructure; rebuilding that infrastructure is outside the project.

People may direct the work, provide credentials, play the game, report observations, and make release decisions. No manual modeling, coding, composing, or editing is required by the production plan. Keep an authoring record instead of claiming that generated material has guaranteed originality or copyright status. The baseline uses no downloaded creative asset packs or sampled music.

### Scope boundaries

Version 1.0 includes finished courses rather than endless random roads. Defer online multiplayer, rollback networking, mobile and console ports, steering-wheel force feedback, VR, a cockpit with working instruments, licensed vehicles, pedestrians, traffic simulation, combat, police pursuits, vehicle damage, complex tuning, dynamic weather physics, a public mod editor, and a photo/video editor. Reverse courses and route branches can follow after release. These omissions keep four-player racing and the six-course campaign achievable without sacrificing their quality.

## Delivery principles

1. Finish one useful experience at a time. Each milestone produces a runnable build, evidence, and an updated status record.
2. Do not expand content until the handling, production pipeline, and four-camera cost have passed their gates.
3. Keep the simulation independent from cameras, sound, UI, and scenery animation. An audiovisual improvement cannot change a race result.
4. Use structured text and generation scripts as the source of truth. Generated meshes, audio, previews, and distribution files must have traceable inputs.
5. Treat licensing and accessibility as production requirements from the first asset and menu.
6. Separate automatic verification from experience review. A successful bot race cannot establish that a drift is enjoyable or a soundtrack sounds good.

## Milestone dependencies

M0 establishes the tools. M1 proves the car. M2 proves the course tools. M3 proves four local players and performance. M4 completes racing rules and traditional opponents. M4B trains and proves learned rivals. M5 combines them into a polished vertical slice. After M5, M6 systems work and M7 content production can proceed in parallel against frozen interfaces. M8 validates the complete game. M9 packages and releases it.

The numbers are work order, not calendar promises. M1, M3, M4B, and M5 are deliberate decision gates: resolve their failures before committing to bulk content. Record effort after each completed milestone to estimate the remaining work from actual project experience.

## M0 establish the project

**Result:** a reproducible empty game shell with clear rights and reliable checks. Dependency: none.

- [ ] M0.1 Pin Godot 4.7.2 Standard, matching export templates, and the asset-generation Python version, with checksums and installation instructions. Verify the chosen release before installing; update the pinned version through a recorded decision if necessary. The official [release archive](https://godotengine.org/download/archive/) lists 4.7.2 as stable at this planning baseline.
- [ ] M0.2 Create `project.godot`, a boot scene, game/menu scenes, typed resource schemas, the planned directory structure, and ignore rules for caches and local credentials.
- [ ] M0.3 Preserve the existing Unlicense; add the explicit asset CC0 notice and scope, contribution instructions, dependency inventory, and empty asset/provenance manifests. Extract notices from the pinned runtime.
- [ ] M0.4 Build original command-line import, test, content-validation, capture, and export entry points. A deliberately failing test must return a failing exit code.
- [ ] M0.5 Add CI for resource/script checks, tests, asset validation, and native export preparation. CI must run from a clean checkout without editor interactions or generation-service accounts.
- [ ] M0.6 Select and record reference machines, OS versions, controller models, baseline renderer, and performance capture method. Compare Compatibility and Mobile rendering before locking the baseline.
- [ ] M0.7 Establish `docs/STATUS.md`, an evidence directory, decision records, and task ownership for collaborating agents.

**Acceptance:** a second agent can follow the setup guide, import, run the boot scene, execute a passing and a failing check, and export a desktop smoke build. The license inventory identifies the runtime separately from original project material. No dependency or creative input has unknown terms. Record missing target hardware explicitly; an untested platform does not become verified through a successful export.

## M1 prove the driving

**Result:** a driving laboratory worth iterating on. Dependency: M0.

- [ ] M1.1 Implement a custom arcade motor, normalized driver commands, keyboard/gamepad steering, acceleration, braking, reverse, automatic gears, handbrake, and reset.
- [ ] M1.2 Build graybox straights, broad sweepers, hairpins, a bank, a crest, a jump, a compression, walls, gravel, shoulders, and a recovery zone.
- [ ] M1.3 Add explicit drift entry, sustain, transition, exit, and capped exit surge; expose tuning resources and telemetry.
- [ ] M1.4 Implement bounded ground adhesion, swept movement, landing recovery, gentle side contact, and strong-impact response. Presentation suspension cannot throw the simulation body.
- [ ] M1.5 Add chase/near/hood cameras, rear view, speed readout, drift cues, and basic synthesized engine/tire feedback.
- [ ] M1.6 Capture keyboard and controller runs, telemetry traces, and a handling comparison report using the three starter configurations.

**Acceptance:** a standard assisted driver can repeatedly enter and recover a 12–40 degree drift, retain useful corner speed, and resume control after contact. A clean drift and a clean grip line through the benchmark sweeper are within 5% of each other's elapsed time after tuning. Extreme steering and countersteering do not produce uncontrolled oscillation. The car passes maximum-speed wall, crest, jump, reverse, and reset tests without tunneling, nonfinite values, or persistent stuck states. At 30, 60, and 120 rendered FPS the fixed-tick benchmark results remain within the documented tolerance. Review captured driving; metrics alone cannot close this milestone.

## M2 build the course and geometry pipeline

**Result:** source data can reliably become a driveable, scenic course. Dependency: M1.

- [ ] M2.1 Implement the road spline format, arc-length samples, variable width, grade, banking, surfaces, shoulders, barriers, and chunked mesh/collision baking.
- [ ] M2.2 Generate ordered checkpoint gates, start grid, sector timing, progress samples, reset anchors, and AI line/speed hints from the same road definition.
- [ ] M2.3 Implement validation for seams, discontinuities, unsafe gaps, overhead clearance, illegal intersections, invalid reset points, and scenery in driving space.
- [ ] M2.4 Build reusable original road, terrain, tunnel, bridge, tree, cliff, sign, and barrier generators with LOD and instancing support.
- [ ] M2.5 Author the full Riviera Run route in graybox, with all its elevation and width changes, three landmark placements, and complete recovery boundaries.
- [ ] M2.6 Add automated course flythroughs, minimaps, car turntables, contact sheets, and asset manifest generation.

**Acceptance:** the car completes repeated Riviera laps without a collision seam or progress jump. An overpass test never attaches the car to the wrong route segment. Course validation intentionally rejects broken fixtures. A second agent generates a small alternate test loop from documented inputs without editing generator code. A clean regeneration produces matching normalized outputs and hashes under the pinned toolchain.

## M3 prove four local players

**Result:** four independent players race in one world at the provisional performance target. Dependencies: M1 and M2.

- [ ] M3.1 Implement device-to-player ownership, joining, readying, car selection, leaving, remapping, per-device deadzones, and persistent preferred controls.
- [ ] M3.2 Render one shared world through one to four viewports. Implement all split layouts, native-resolution HUD overlays, and a nonrendered spare quadrant for three players.
- [ ] M3.3 Add global pause, disconnect/reconnect/reassign handling, focus loss behavior, and safe conversion of a withdrawn participant to AI.
- [ ] M3.4 Run eight cars on representative route sections with provisional scripted drivers. Add scenery stress scenes, bounded particles, and shared audio mixing.
- [ ] M3.5 Measure the worst four-camera scene and remove duplicate rendering, simulation, assets, or audio work. Freeze a documented rendering budget.

**Acceptance:** four actual gamepads and keyboard-plus-three-gamepad sessions independently steer the correct cars; no device silently moves between players. A reconnect preserves slot ownership. Every layout remains usable at 1920×1080. With eight cars and representative scenery, the recorded reference machine meets the 60 FPS target and frame-time gates in the technical specification. Synthetic inputs verify routing logic but do not replace hardware verification. If hardware is unavailable, keep this gate open and continue independent tooling rather than claiming completion.

## M4 complete racing and traditional opponents

**Result:** a complete, replayable race from grid to results. Dependencies: M2 and M3.

- [ ] M4.1 Implement the race state machine, countdown, validated laps, ranking, finish deadlines, ties, DNF, restart, and results.
- [ ] M4.2 Implement AI planning, speed selection, drift decisions, drafting, legal overtakes, defending, mistakes, and safe recovery through the player command interface.
- [ ] M4.3 Tune Rookie, Racer, and Expert profiles and four opponent personalities using the same car resources and physical limits as humans.
- [ ] M4.4 Complete paired vehicle contacts, respawn immunity, wrong-way warnings, stuck detection, and shortcut protection.
- [ ] M4.5 Add a seeded race harness with contact, recovery, progress, pacing, and input telemetry; add diagnostic replay captures.

**Acceptance:** at least 100 seeded races per difficulty on the slice route complete without race-state deadlocks. With finish deadlines disabled for mechanical evaluation, at least 99% of AI entries finish, and no route point repeatedly requires a recovery. Separately measure legitimate deadline DNFs against reference player paces. Dedicated blocking, narrow-pass, jump, and collision scenarios show no deliberate ramming, hidden speed changes, or teleporting catch-up. Test skipped gates, reverse crossings, resets, simultaneous finishes, pause, and abandonment. Review close-racing footage from both player and overhead cameras.

## M4B train learned Roadstormers

**Result:** two special opponent styles use a small original learned tactical policy during real races. Dependency: M4 and stable handling/content revisions. Full design: [OPPONENT_AI.md](docs/OPPONENT_AI.md).

- [ ] M4B.1 Freeze the shared observation/intent contract and safety constraints. Instrument Classic drivers to generate original tactical demonstrations.
- [ ] M4B.2 Build and validate a local-only headless Godot training bridge with explicit step/reset/timeout/shutdown semantics, then measure its throughput before a long run.
- [ ] M4B.3 Pin the development-only learning toolchain; implement behavioral cloning followed by PPO training from original simulation data and random initial weights.
- [ ] M4B.4 Export a small policy's numeric weights and normalization; implement original GDScript inference and verify parity with the training implementation.
- [ ] M4B.5 Produce pressure-oriented Surge and patient-cutback Switch styles, with shared low-level control, difficulty settings, and physical limits.
- [ ] M4B.6 Add mixed fields, roster identification, Classic Only preference, policy safety/failure handling, model cards, and repeatable evaluation scenarios.
- [ ] M4B.7 Evaluate held-out situations against matched Classic baselines, review full-race clips, and record training cost and remaining generalization risks.

**Acceptance:** real learned inference is active for two rivals on Riviera; no runtime cloud/model service is needed. Exported inference passes numerical parity tests, safety failures cannot corrupt racing, and learned rivals pass the slice completion/contact/pace criteria. Both styles show readable tactical differences in held-out traffic scenarios. A safe Classic fallback keeps an exceptional faulty race playable, but does not close this feature. Full six-course generalization and release model acceptance remain required in M7/M8.

## M5 finish the vertical slice

**Result:** a small version of the intended finished game. Dependencies: M1 through M4 and M4B.

- [ ] M5.1 Finish Riviera Run's beach, village, marina, tunnel, lighting, road signage, flyover, and scenery animation.
- [ ] M5.2 Finish the three starter cars with distinct handling, LODs, paint options, thumbnails, and engine families.
- [ ] M5.3 Finish menu → join → select → race → results → rematch flow, a short playable driving tutorial, basic settings, and a real save round trip.
- [ ] M5.4 Finish the first original race composition, menu/results themes, tires, contacts, environmental audio, and a balanced four-player mix.
- [ ] M5.5 Complete original HUD typography, player markers, drift feedback, minimap, transition effects, and accessible readability settings.
- [ ] M5.6 Have an agent other than each feature's implementer review the integrated build, footage, audio previews, performance evidence, and provenance.
- [ ] M5.7 Demonstrate the mixed field of Classic Racers and Roadstormers and a comparison race with Classic Only, including readable rival identities and both learned styles.

**Acceptance:** single-player and four-player sessions work from a fresh launch without developer intervention. The slice meets the handling, fairness, visual, audio, and performance criteria. Every asset has a source recipe and approved record. A reviewer can explain each car's handling identity and recognize at least three distinct Riviera landmarks. Record unresolved subjective feedback honestly; do not expand content to conceal a weak driving model.

## M6 implement modes and progression

**Result:** the complete game structure works with temporary references to future content. Dependency: M5; can overlap M7 asset authoring.

- [ ] M6.1 Implement all five modes, configurable Quick Race, solo career cups, local exhibition cups, Arcade Rush checkpoints, Time Attack records, and sampled ghosts.
- [ ] M6.2 Implement the twelve-car collection, achievement unlocks, credit rewards, purchases, reversible upgrade loadouts, and paint selection.
- [ ] M6.3 Implement four local profile slots plus a temporary guest profile; keep career rewards scoped to the selected host profile.
- [ ] M6.4 Add versioned saves, atomic replacement, backups, validation, migration, and reward transactions that apply once per event instance.
- [ ] M6.5 Complete settings, tutorial prompts, progress explanations, medal targets, garage stat comparisons, licenses, and controller-only navigation.
- [ ] M6.6 Run economy simulations and interruption tests; document expected unlock and upgrade pacing.

**Acceptance:** the designed unlock graph reaches exactly twelve cars, permits recovery from poor results, and never requires spending upgrade credits to access a car. One standard three-lap finish buys a first upgrade; roughly eight typical standard finishes upgrade a favorite fully. Short/long Quick Race rewards scale with laps. Crashing during reward/save operations grants each valid reward once. Corrupt or old saves recover safely without silently overwriting the last usable copy. Local exhibition offers stock loaners and never contaminates solo career records. Records and ghosts reject incompatible handling/course versions.

## M7 produce the full content

**Result:** all launch courses, cars, music, effects, and events are finished. Dependency: M5, with mode integration from M6.

- [ ] M7.1 Produce Alpine Switchback and Emerald Rally, plus three cars, using the existing production tools. Validate the second course before generating the rest.
- [ ] M7.2 Produce Canyon Voltage and Metro Sunset, plus three cars. Reuse shared props while preserving unique silhouettes, palettes, and road rhythms.
- [ ] M7.3 Produce Stormpeak Finale and the final three cars. Reserve the hardest sequences for the finale while retaining forgiving recovery space.
- [ ] M7.4 Finish six race themes, all environment kits, animated spectacles, final previews/minimaps, paint sets, effects, and release graphics.
- [ ] M7.5 Populate the exact championship schedule, car unlock awards, per-course Arcade Rush timing, and stock Time Attack medals.
- [ ] M7.6 Validate the full car/course matrix at stock and maximum upgrades, targeted intermediate upgrade boundaries, pairwise layout/difficulty/assistance combinations, and curated stress cases; perform separate art, audio, route-readability, and rights reviews.
- [ ] M7.7 Train/evaluate the learned rivals against the expanded roster and courses, retain held-out layouts/seeds, and ship approved original checkpoints with full model/data provenance.

**Acceptance:** six distinct circuits and twelve finished cars exist; no required content is a placeholder. Each course passes its track contract and has three major set pieces. All modes reference valid content. Every course supports stock starter cars and eight-car fields; narrow sections do not force unavoidable collisions. The complete shipped asset set passes the manifest/license check. Performance is rechecked as each course lands rather than deferred to the end.

## M8 balance and validate the complete game

**Result:** a release candidate with evidence against the full specification. Dependencies: M6 and M7.

- [ ] M8.1 Tune car parity, drift versus grip, upgrades, AI pace/aggression, cup difficulty, rewards, and Arcade Rush extensions from telemetry and observed play.
- [ ] M8.2 Finish accessibility checks, remapping edge cases, four-player HUD readability, camera comfort, audio headroom, and complete menu flows.
- [ ] M8.3 Profile each course at one, two, three, and four players; reduce excess draw calls, overdraw, memory, physics work, and audio voices.
- [ ] M8.4 Run the release verification matrix, long-session tests, save corruption/migration cases, content regeneration, offline play, and clean-machine tests on each supported OS.
- [ ] M8.5 Resolve all crash, progress-loss, controller-blocking, rules, and licensing defects. Record any remaining low-severity limitations and the exact tested configuration.
- [ ] M8.6 Audit all project-authored work for its source record and all third-party components for applicable notices, including fonts, encoders, plugins, and export templates.
- [ ] M8.7 Close the full learned-AI evaluation gate: course-level completion, fair contacts and pace, low safety-intervention rate, recognizable tactical styles, and inference cost with four viewports.

**Acceptance:** all blocking verification cases pass, the performance gates hold on recorded hardware, and a two-hour mixed-mode session shows no progressive memory growth or loss of input. No unresolved issue can corrupt progression, invalidate race results, or prevent a supported input configuration from playing. LLM visual/audio review and any available player feedback are recorded separately from automatic checks. If there has been no independent human playtest, report that limitation without calling bot results proof of enjoyment.

## M9 package and release

**Result:** downloadable desktop builds and a reproducible public source/asset package. Dependency: M8.

- [ ] M9.1 Generate native release exports with a version/build identifier, checksums, correct icons, full notices, and offline license screens.
- [ ] M9.2 Verify macOS Apple Silicon, Windows x86-64, and Linux x86-64 packages on their target operating systems using the stated supported versions.
- [ ] M9.3 Sign/notarize macOS distribution when owner credentials are available. Keep secrets outside the repository. If unavailable, label the unsigned build accurately and document its installation steps; do not advertise it as notarized.
- [ ] M9.4 Publish source recipes, generation instructions, dependency versions, asset provenance, control guide, accessibility guide, known issues, and release notes with the builds.
- [ ] M9.5 Generate screenshots and a short trailer from actual gameplay; show local split-screen and representative courses. No images should depict absent game features.
- [ ] M9.6 Confirm the final product title and release destination with the owner if those have changed. The chosen working title is Roadstorm Racer!; public-domain dedication is not trademark clearance.
- [ ] M9.7 Prepare the complete release artifact and review report, then publish when publication is authorized. Building and verifying packages does not require an intermediate permission request.

**Acceptance:** a fresh user can download, launch, join, race, save, restart, and access licenses offline. Distribution archives include only intended files and required notices. Every public platform claim has corresponding test evidence. The release statement correctly distinguishes original public-domain material from the engine and dependencies.

## How agents execute the plan

At each milestone, a coordinating agent chooses the smallest dependency-ready task, describes its observable result, and assigns exclusive ownership of the affected files. Work in isolated branches/worktrees when parallel changes would overlap. Keep central scenes, resource schemas, and project settings under one integrator's ownership.

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
