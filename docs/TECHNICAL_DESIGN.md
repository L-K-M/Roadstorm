# Roadstorm Racer! technical design

Build a native Godot project with text-based source resources, a shared fixed-tick race simulation, reproducible content generation, and automated inspection tools. The proposed engine is Godot 4.7.2 Standard with typed GDScript and matching export templates. Pin exact binaries, checksums, the built-in Jolt 3D backend and its settings in M0; a backend change is a handling revision. Do not track a moving stable download. The official [release archive](https://godotengine.org/download/archive/) is the version authority. Common fixtures, reference drivers, metric definitions and tolerances are specified in [BENCHMARKS.md](BENCHMARKS.md).

## Platform and rendering baseline

Proposed support targets are Apple Silicon macOS 14 or later, Windows 11 x86-64, and Ubuntu 24.04 x86-64. These are product test targets, not verified minimum requirements. Intel Mac, other Linux distributions, browser, mobile, and console exports are outside the initial platform commitment. Native tests on each OS are required before a supported-platform claim.

Start with Compatibility rendering: simple directional lighting, vertex colors, limited shadows, optional MSAA, restrained transparency, and no expensive screen-space effects. M0's choice is provisional; M3 locks it after representative one/four-view comparisons with Mobile on available target hardware. Choose from measured frame times and visual needs, following Godot's [renderer documentation](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html); API age alone does not determine performance.

Target 1920×1080 output at 60 FPS for both one and four players. Scale 3D independently from the native-resolution interface. Offer 100%, 85%, and 70% 3D resolution presets, shadow/effects settings, windowed/fullscreen modes, VSync, and a frame limiter. Keep the default playable and readable; low-resolution presentation is optional.

## Project layout

```text
project.godot
scenes/                 boot, menus, race, laboratory, capture stages
src/app/                boot, transitions, profile and settings services
src/input/              device routing, normalized commands, remapping
src/simulation/         motor, contacts, surfaces, progress, race rules
src/ai/                 classic tactics, shared follower, learned policy inference
src/presentation/       cameras, HUD, effects, shared audio director
src/data/               typed resources, schema validation, stable IDs
content/cars/           source definitions and handling configurations
content/tracks/         authored route, scenery, event and audio recipes
content/events/         cups, arcade timing, medals, reward/unlock definitions
assets/source/          original geometry, SVG, sound and score recipes
assets/generated/       baked meshes, graphics, audio, previews and LODs
assets/manifest.json     provenance and technical metadata
models/                 original trained policy weights and model cards
tools/                  bake, validate, capture, synthesize and package entry points
training/               environment bridge, original datasets, training/evaluation tools
tests/                  original headless runner, fixtures and integration scenarios
licenses/               CC0 asset notice and exact dependency notices
provenance/             authoring records, third-party evidence if ever needed
docs/                   design, status, decisions, setup, controls and release notes
```

Keep generated files clearly separate from editable sources. Commit final assets required for a normal checkout to run; a player/build user should not need to retrain a model or synthesize the soundtrack. Retain recipes and documented regeneration commands. Ignore `.godot/`, local build caches, credentials, temporary captures, and ordinary save data. Keep only useful bounded review evidence in source control; large release captures belong in release artifacts.

## Runtime ownership

| Component | Owns | Must not own |
| --- | --- | --- |
| App | Boot, navigation, settings, active profile, scene lifetime | Race physics or award arithmetic |
| RaceSession | Event definition, participants, state machine, timers, result snapshot | View-specific effects |
| RaceWorld | One track, all car states, static collision, shared scenery state | Duplicate per-camera simulation |
| InputRouter | Physical devices, player slots, normalized commands | Global controller actions applied to every car |
| SimulationCoordinator | One logical tick, clocks, shared snapshots, phase ordering, training tick budget and reset | Independent car-owned clocks or progress updates before contacts |
| ObservationBuilder | Versioned local sensors, delayed traffic/history, masks and normalization | Future player inputs or privileged physical limits |
| TacticalPlanner | Classic rules or learned intent using the same schema | Directly moving a body or bypassing difficulty/safety |
| SafetyLayer and PathFollower | Current-hazard checks and legal intent-to-command conversion | Hidden catch-up or unreported repair of unsafe policy decisions |
| Driver | Human input or AI decisions converted to commands | A separate set of physical rules |
| ArcadeMotor | Vehicle movement, grip/drift, grounding, surface response | Currency, UI, or scene transitions |
| ContactResolver | Stable pair contacts, bounded response and immunity | Hidden advantages for AI |
| CourseProgress | Valid gates, route-local position, recovery anchors, lap timing | Nearest-road teleportation |
| SaveService | Versioned snapshots, transactions, backups and migrations | Loading executable code from saves |
| Audio/Presentation directors | Playback, effects, cameras and HUDs from events | Changing speed, rank, race RNG decisions or rewards |
| CosmeticDamage/VisualDebris directors | Part visibility/looseness, one-shot detachment, pooled visual motion, sparks and debris cues from committed impacts | Changing car contact hull/mass/handling, race RNG/progress, AI observations or physical contact response |

Use a `DriverCommand` structure with steer in [-1,1], throttle/brake/handbrake in [0,1], reset request, and relevant edge-triggered actions. Commands are sampled once per physics tick. A controller or either AI family supplies the same structure. Special learned opponents are specified separately in [OPPONENT_AI.md](OPPONENT_AI.md).

### Fixed tick and movement ownership

M0 proves a minimal tick/reset/query harness before the full motor depends on it. Interactive and headless execution call the same coordinator with `dt = 1/60`; only it advances clocks, RNG, contacts, gates and events. Nonterminal training steps consume twelve logical ticks; termination/truncation stops early and returns elapsed ticks. Waiting consumes zero. Demonstrate query/physics fidelity before acceleration; calling a motor function twelve times alone does not prove twelve correct world steps.

Tick order is: snapshot poses/velocities and commands; update support/surface state and sensor histories; plan due tactics and current safety; integrate proposed world-constrained trajectories; resolve relative swept car pairs; apply bounded world-safe correction and final movement; evaluate accepted swept gate crossings; commit car/progress state and events. Record piecewise accepted motion through world contacts, rather than a straight chord through a wall. Resets, overlap corrections and depenetration do not earn progress. Observations and ranking use the committed state, not partially updated neighbors.

Construct speculative trajectories with nonmutating `test_move`/body-motion queries from explicit simulated transforms, keeping real bodies at the tick-start snapshot during planning/contact solving. Use `CharacterBody3D.move_and_collide()` with explicit displacement only in the final movement phase, once for each accepted path segment; do not integrate velocity a second time or expose provisional body poses. Record any discrepancy between predicted and committed world motion. Do not mix `move_and_slide()` velocity mutation/floor snapping with custom adhesion. Disable automatic snap/platform motion and interpolate only the visual child. One coordinator owns velocity/transform writes. M1 proves the API choice before dependent work; alternatives require a recorded decision and equivalent checks. See [PhysicsBody3D motion queries](https://docs.godotengine.org/en/stable/classes/class_physicsbody3d.html) and [CharacterBody3D](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html).

Publish typed events such as countdown changed, drift began, impact occurred, gate crossed, lap completed, participant finished, and result committed. Consumers may draw or play sounds but cannot mutate the originating race result. Use scoped event connections and explicit teardown to prevent duplicate listeners after rematches.

Committed impact events carry a unique event ID per (physical contact, primary car) perspective and may share a contact ID across the two car perspectives. Each record carries the car IDs, world and primary-car-local contact points, world contact normal, contact-induced velocity-change severity and post-contact velocity. Cosmetic damage consumes those events after simulation commit, coalesces repeats and selects a configured attachment region. Use separate cosmetic state/RNG and event IDs; toggling effects cannot consume race randomness or alter contact classification. Car reset/grid events restore visual parts without changing the intact motor/collision resources.

Visual debris is a pooled mesh with lightweight velocity/spin/gravity/friction and read-only static-world shape/ray queries. It registers no active physics body or collision shape in the authoritative world. Queries use only road/terrain/barrier layers, excluding racers, gates, other debris and AI sensors. Bound casts/substeps and use a simple resting/slide fallback for difficult geometry; a cosmetic query failure cannot delay a race tick. Cap globally at 24 pieces, six seconds each, 128 sparks and four prioritized sliding emitters; recycle/skip on saturation as specified in GAME_DESIGN. The same shared meshes render in all active views. Freeze/clear them on pause/scene teardown, and disable their work in headless training without changing simulation results.

## Movement and contacts

Use a custom arcade motor around `CharacterBody3D`, world sweeps, and ground probes. This is a tuning choice for forgiving drift. Godot's [VehicleBody3D documentation](https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html) notes limitations; its built-in vehicle behavior is not the required handling specification.

Start at 60 fixed physics ticks per second and interpolate the visual transform. State includes world velocity, road-plane forward/lateral velocity, heading, yaw response, surface, support normal, grounded/airborne state, drift timer, surge cooldown, drafting target/eligibility/fade, contact state, and valid progress. Apply acceleration and drag along the support plane, then controlled yaw and lateral damping according to grip/drift state. All tunable values live in versioned car/surface resources.

The handling contract includes acceleration versus speed, braking acceleration, aerodynamic/rolling drag, grip/drift yaw gain, lateral damping in 1/s, entry/exit blend seconds, airborne gravity/adhesion bounds, surface modifiers and contact caps. M1 records exact coefficients and measured envelopes before closure; the garage's 1–5 scores summarize them and never become physical multipliers. Upgrades multiply named stock parameters as specified in the game design. Surface IDs come from route-local metadata or explicit surface collision bodies, not backend-specific triangle face indices; verify transitions under [Jolt's query behavior](https://docs.godotengine.org/en/stable/tutorials/physics/using_jolt_physics.html).

Use a central support probe plus four footprint probes, bounded normal smoothing, and bounded ground attraction. Disable attraction during intended airtime; never pull the car through a bridge or onto a ceiling. Visual suspension, pitch, roll, wheel rotation, and steering animate child nodes. They do not rotate the collision body into unstable poses.

World collision uses sweeps against thickened road/barrier geometry rather than relying on final-position overlap. At approximately 65 m/s a car travels more than a meter per tick; maximum-speed narrow barriers and oblique impacts require dedicated tests. Use bounded movement subdivisions where necessary, with a strict work cap; measure before increasing the global tick rate.

Treat vehicle-to-vehicle response as one coordinated system. Car bodies collide with the static world, and their Godot collision masks exclude ordinary car-to-car physical response because the custom resolver owns it. Evaluate relative swept hull motion from one shared tick-start snapshot, rather than endpoint overlaps or independently moving each car against stationary rivals. Apply bounded mass-weighted speed/deflection responses in stable participant order and correct overlap while rechecking world collision. Avoid applying a second engine response to the same contact. Prototype this in the laboratory before full racing. Prevent vertical launching and cap positional correction; recovery handles invalid states.

Initial solver budget: at most four contact-response iterations and two overlap-correction passes per tick; limit each correction to 0.25 m and total correction to 0.5 m. If unresolved, remove inward relative velocity, log saturation and use safe recovery rather than tunneling through a wall or applying an unbounded impulse. M1 validates/tunes these initial limits against narrow squeezes, pileups and maximum-speed approaches.

Fixed ticks and seeded decisions make tests more repeatable, but do not promise cross-platform deterministic Godot physics. Use tolerances for simulation regressions, exact checks for pure rules/math, and sampled-transform ghosts. See Godot's [physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html) and [physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html).

## Content contracts

Use stable semantic IDs that do not change with display names. Definitions have schema versions and explicit dependencies. Runtime resources are typed; editable source recipes can be JSON/text plus original scripts. Validate every numeric range and referenced asset before baking.

| Definition | Required information |
| --- | --- |
| Car | ID/version, source mesh and LODs, dimensions, intact mass/contact proxy, handling, engine/paints/icon/upgrades, detachable-part IDs/meshes/LODs, attachment transforms/impact regions and cosmetic thresholds |
| Track | ID/revision, spline controls, width/bank/elevation, surfaces, barriers, grid, ordered gates, sectors, safe anchors, AI lines/speed hints, scenery/audio triggers, bounds, lighting |
| Event | ID, mode, track order, laps, AI roster/difficulty/families, configuration rules, time limits, reward table, unlock dependencies |
| Upgrade | ID, car/category, level, price, additive/multiplicative effects, caps and display text |
| AI profile | Family, difficulty, personality, legal planning bounds, policy/model revision when learned |
| Ghost | Track and handling revisions, car/configuration, assists, sampling rate, sample data, lap time, validity/hash |
| Model | Architecture/schema, numeric weights, normalization, training/data revisions, evaluation report, license and provenance |
| AIObservation/TacticalIntent | Version, ordered shape/fields, road frame, masks, observation age, normalization/action decoding, personality/difficulty and reset defaults; defined before M4.2 in OPPONENT_AI |
| ReferenceRun/Scenario | Fixture and driver revisions, initial state/commands/history, seeds, car/loadout/assist/track/handling hashes, measured traces, eligibility and metric version |

Car units are meters/kg/seconds, local +Y up and -Z forward, with origin at the ground projection of the axle midpoint; wheel pivots are local axle centers. Each car declares length/width/height, wheelbase, mass, ground clearance and jump envelope. Initial envelopes are 3.6–4.8 m long, 1.7–2.2 m wide, 1.0–1.8 m high; validate every actual model, especially Thunderbrick. Use one simplified rounded-box/convex hull derived from those dimensions, with a documented roof/underside; rendering detail cannot change contact secretly. Road/grid/clearance validation uses the largest actual envelopes, not the average car.

### Track compiler

An authored centerline is resampled by arc length. Use a stable transported road frame rather than a world-up cross product that flips at vertical changes. Interpolate width, banking, and surface transitions smoothly. Generate the road strip, shoulders, terrain skirts, barriers, collision, AI samples, gates, safe anchors, and minimap from shared samples. Split long meshes into spatial chunks with LODs. Build collision from simplified matching geometry and inspect seams.

A closed loop may retain residual frame roll. Measure it at closure, distribute its correction by arc length, then apply authored banking. Validate closing position/tangent/width/bank and matching render/collision normals. Tag required road-rhythm features and landmarks with route intervals; T09 checks the geometric course contract and captures support an independent rhythm/readability review.

Constrain normal road grade to an initial 12% target, banking to approximately ±12 degrees, and rapid curvature/width changes to reviewed limits. Short exceptions require explicit metadata and laboratory validation. Validate curvature, available stopping distance, jump landing space, road clearance, self-intersections, route continuity, eight-car grid space, barrier placement, and legal recovery areas. Self-crossings are allowed only when annotated as an overpass with sufficient vertical clearance.

Scenery recipes place props with exclusion volumes around the route, readable sightlines before turns, and shared progress-triggered animation. Use partitioned `MultiMesh` groups for repeated trees, spectators, rocks, and flags. Generate road/prop geometry during development/build, not every race. Godot documents [procedural geometry](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/index.html); the source recipes and validator are original project tools.

Progress projection searches a bounded neighborhood of the previous valid route sample and required gate. A separate recovery query can search more widely only to return the car behind its last valid progress. Ordered swept gates are authoritative for laps; a nearest-point query cannot skip a hairpin, overpass, or sector. Keep physical distance and validated race progress distinct.

Place validation gates at most 100 m apart and additionally before/after shortcuts, hairpins, jumps and route crossings. Their route/height-bounded spans cover legal road and runoff to recovery boundaries; timing gates are a separate subset. Grid layout is two columns by four rows, initially 3.2 m column-center spacing and 7 m row spacing, on a sufficiently wide straight with no gate inside a car. Save seeded participant order and grid-rule revision. Safe anchors are checked for static and car occupancy; search farther backward or hold the car harmlessly for a clear placement if blocked. Never move it forward to solve occupancy.

### Asset generation

Prefer original GDScript mesh-baking tools, SVG generators, and Python synthesis/composition scripts with pinned versions and seeds. Emit engine-native mesh/scene resources or validated interchange formats; document the chosen format in M0/M2. No Blender dependency is needed for the baseline, although an original scripted Blender tool can be added if it solves a measured production problem. Retain its version and license in the tool inventory if used.

Every generated asset references a source recipe and manifest record. Exact normalized hashes apply on one pinned canonical build image/architecture; other hosts compare declared semantic/numeric geometry/audio tolerances unless binary equivalence is demonstrated. Keep stable resource IDs through the chosen importer. Changed recipes trigger regeneration of dependencies plus a rotating CI sample; fully regenerate the deterministic asset set at release. Frozen remote-service outputs and statistically reproducible training are separate provenance classes. A generator change also triggers contact-sheet review and relevant performance tests.

## Split-screen and audio

One `World3D` contains the simulation. Each local player gets a `SubViewport`, `Camera3D`, and panel-specific HUD state. Explicitly share the world, disable unused viewports, and avoid an extra active root 3D camera. Native-resolution UI overlays the scaled 3D images. Godot's [viewport documentation](https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html) describes shared worlds and multiple cameras; it does not automatically implement player/device ownership.

At 100% scale four-player 1080p output uses four 960×540 3D panels. Rear view reorients the existing slot camera while held; it does not add another viewport. M3 records per-player-count LOD distance, prop density, shadow and effects presets to satisfy aggregate budgets; changes are presentation-only. Do not assume four solo maximum-detail views fit the four-view cap merely because each has fewer pixels.

Route raw input by device ID to a stable player slot. Keyboard occupies at most one slot. Associate bindings/deadzones with device profiles and confirm explicit reassignment after disconnect. Reset held commands on focus loss, pause, reassignment, or reconnect. Menus distinguish host event controls from each slot's local car selection. Test real controllers in addition to synthetic events; see [Godot controller support](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html).

Use one explicit shared audio output. Disable automatic positional/listener audio for race viewports and play chosen logical sources once through nonpositional players. `AudioDirector` computes virtual listeners from every local camera/car, attenuation and relevance per listener, then combines normalized gains and weighted stereo pan without privileging the host. Local engines have reserved gain; distant ambience uses the strongest relevant listener rather than summing four identical copies. Smooth layout/listener changes over 0.25 seconds; mono sets pan to zero. This is a chosen shared downmix, not a claim that Godot has only one global viewport listener.

Initial total allocation, including crossfades: local engines 8 (two per human), nearby rival engines 4, local tire blends 4, environment 4, music 2, impact/landing transients 6, UI/essential cues 4 = 32 voices. Select/blend one tire state per local car; virtualize extra distant tires. Idle/load/coast are asset variants, not three mandatory simultaneous loops. Fade/cull low-priority ambience/rivals before stealing local-engine or essential-cue reservations. Count music transitions and transient peaks; coalesce checkpoint cues shared by several players. Profile decoder/voice cost and final mix rather than treating the inventory as a simultaneous-playback requirement. Pre-render expensive synthesis.

Bumper knocks/rattles/sliding share the six contact/transient voices; at most one continuing debris scrape has priority at a time, chosen by visibility/relevance. Retiring or stealing its voice fades it cleanly. Cosmetic sounds cannot displace reserved player engines or essential cues, or silently increase the total voice count.

Global pause halts simulation time, race deadlines, and gameplay-triggered animations. Menu sound remains functional. Music may duck or pause according to one consistent setting. No cue depends on a particular camera being active.

## Persistence and records

Store user data in the platform's Godot user-data directory, never in the checkout. Use validated JSON or another nonexecutable format, with schema version, profile ID, credits, unlocked cars, purchased/equipped levels, cup state, records, settings, and applied reward transaction IDs. Clamp only recoverable invalid settings; treat inconsistent progression as a recoverable error, not permission to invent purchases.

Save to a temporary file, flush/close, validate, then replace the primary file and retain the last good backup using the safest target-platform sequence. Test interruption between each step. Include a checksum for accidental corruption, not as a security claim. Keep a recovery screen that can restore a backup or create a new profile without silently destroying evidence.

An immutable event result has a unique event-instance ID. A single transaction updates credits, unlocks, and cup progression; retries/reopened results cannot apply it again. Bound the retained transaction history through archived cup/event state without reintroducing duplicate awards. Test resuming a cup on both sides of the commit boundary.

Allocate the event ID before GO and use one save writer with monotonically increasing profile generations. Journal the committed result/applied-ID state and validate primary, temporary and backup generations at startup. A result is acknowledged as saved only after the selected platform replacement protocol succeeds. If saving fails, retain the pending result, show retry/export options, and do not launch another credit-paying event until resolved. A crash before durable acknowledgement may lose that attempt; do not promise exact-once rewards for a result never persisted. Flush/close alone is not a portable guarantee of power-loss durability; test the actual replace/recovery protocol on each target OS. See [FileAccess](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html).

Each snapshot is self-contained: generation, profile ID, complete state, committed results/applied IDs and checksum agree. On startup choose the highest fully valid generation among primary/temp/backup, including a complete newer temp, and promote it through the tested replacement protocol before further writes. Identical same-generation payloads prefer primary, then temp, then backup. Conflicting valid payloads at one generation are quarantined; retain the latest unambiguous older snapshot for read-only recovery and require an explicit selection before resuming writes. Never silently choose conflicting credits/unlocks. Across game instances, acquire an exclusive per-profile lock via atomic lock-directory creation; a contested profile is read-only/unavailable. Reclaim a stale lock only after verifying its owning process/session ended.

| Interruption point | Required startup outcome |
| --- | --- |
| Temp incomplete/invalid | Ignore/quarantine it and use the highest valid older snapshot |
| New temp complete before replacement | Promote its complete generation; its result/applied ID is recovered once even if the earlier UI never acknowledged it |
| Replacement complete | Use the highest complete primary/temp/backup generation; never reapply an included result |
| Same-generation conflicting payloads | Preserve evidence, use unambiguous read-only recovery and request explicit resolution |

This specifies process-interruption behavior under tested filesystem assumptions, not immunity to every hardware/power-loss failure. Exercise every boundary and multiple-instance lock in T07.

Record ghosts at an initial 20 Hz with interpolated transforms, wheel/drift state, and bounded duration. Cap stored bests, validate file sizes and values, and archive incompatible revisions. Local records are convenience features, not tamper-proof competition infrastructure.

## Performance budgets

Provisional reference profiles: an Apple M1 with 8 GB memory and a Windows/Linux machine around a GTX 1650-class GPU. Record actual available hardware in M0. These examples are test planning, not proven minimum specifications.

| Measure | Initial release gate and method |
| --- | --- |
| Frame times | 60 FPS target; p95 ≤16.7 ms, p99 ≤25 ms after warm-up on each recorded reference profile at default 1080p settings |
| Hitches | No repeatable >50 ms gameplay spikes after warm-up; report loading separately |
| Simulation | Eight cars, both AI families, contacts, and scene triggers remain within a provisional 4 ms CPU budget; learned inference within 0.5 ms total per decision update |
| Geometry | Initial ≤350k visible triangles/250 draw calls in one view; ≤900k triangles/650 draw calls aggregated across four views; revise only from measurements |
| Memory | Target ≤1.5 GB resident process memory during ordinary play and no unbounded growth across rematches |
| Loading | Target ≤10 seconds to a course on the reference SSD; no geometry/audio generation during the race |
| Input | Command sampling to simulation response within two physics ticks; this is not an end-to-end display latency measurement |
| Package | Initial compressed distribution target <500 MB per platform; retain sources separately if needed |

Measure multiple laps on every course with cameras pointing at different scenery, not four copies of the same view. Capture CPU/GPU timing where supported, frame-time distributions, memory, car/AI load, voice counts, and draw calls. Shader warm-up and resource loading happen before GO. Reduce duplicated rendering, shadows, distant props, transparency, and effects before changing handling or dropping simulation rate. A headless training run is not a rendering benchmark.

The simulation and inference units/scheduling and capture protocol are defined in [BENCHMARKS.md](BENCHMARKS.md#performance-and-compute-evidence). Geometry totals are summed per output frame across active views; repeated geometry counts again. Solo and four-view limits are independent caps, not a promise that four solo maxima fit. Record shadows/overdraw separately and never substitute triangle budgets for measured frame times.

## Verification matrix

Implement a small original `SceneTree` headless test runner with assertions and nonzero failure exits. Avoid a mandatory test framework dependency. Use exact checks for pure rules and tolerances plus telemetry for physical scenarios. Godot supports headless scripts and exports through its [command-line interface](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html).

| ID | Coverage | Evidence and gate |
| --- | --- | --- |
| T01 | Clean import, typed scripts, resources, source/generated references | Clean-checkout CI pass; changed recipe dependencies/rotating sample regenerated on canonical tooling; no missing resource or script errors |
| T02 | Steering/drift/drafting math, cooldowns, surfaces, speed/upgrade caps | Boundary tests, no invalid state, no weave/donut/wall farming; equal human/AI wake rules |
| T03 | Driving at 30/60/120 rendered FPS | Fixed-tick scenario results within documented position/time tolerance; no frame-rate reward changes |
| T04 | Maximum-speed wall/car contacts, jumps, slopes, landing, recovery | No tunneling, launches, nonfinite states, or forward-progress reset exploits |
| T05 | Gates, reverse/duplicate crossings, overpasses, laps, ties, DNF | Exact expected results from constructed scenarios |
| T06 | Cups, rewards, purchases, loadouts, unlock graph | All twelve reachable; no negative balance or duplicate award; price/effect caps hold |
| T07 | Save interruption, corrupt/oversize data, migrations, backup | Recovery retains last good state; no silent destructive reset |
| T08 | Player routing, join/leave, focus, reconnect, remapping | Synthetic scenarios plus actual four-pad and keyboard-plus-three-pad sessions |
| T09 | Track bake, closed-loop frame, gates, bounds, clearance, grid, anchors and road-rhythm contract | Six courses validate; required features mapped to route intervals; deliberately broken fixtures fail |
| T10 | AI legality and learned-policy safety | Shared physical limits, no nonfinite/out-of-range outputs, no hidden catch-up; separate evaluation report |
| T11 | Race endurance and fair pacing | At release, 100 seeds × six tracks × three difficulties with a rotating mixed roster and finish deadlines disabled; ≥99% AI entry completion, no deadlock; separately test deadline DNFs across reference human pace ranges; nightly subsets during development |
| T12 | Car/course/preset compatibility | Each of 12 cars on six courses at stock and maximum upgrades completes a clean run; pairwise layout/difficulty/assistance cases supplement this matrix |
| T13 | UI and experience | Screenshots/footage at every layout/text scale, controller-only flows, drift and course review, audio previews |
| T14 | Performance and endurance | Every course/layout benchmark plus a two-hour mixed-mode session; no progressive resource leak |
| T15 | Provenance, rights, package contents, offline notices | All shipped paths accounted for; exact runtime/dependency notices present |
| T16 | Native platform distribution | Launch/join/race/save/relaunch offline on each supported OS, release checksum and build ID captured |
| T17 | Cosmetic damage/debris isolation | Correct struck-part detachment/repair, global pool/particle/voice caps, pause/teardown and four-view stress; FX on/off uses identical commands/race RNG, exact rule/reward events and existing same-host trajectory tolerances |

Run fast checks on changes; run relevant scenarios when their systems or assets change. Full endurance/evaluation batches belong at milestone and release gates. Seeded tests aid reproduction but do not guarantee identical physics on different machines. Record engine, platform, content, handling, and model revisions with failures.

Provide deterministic capture scripts for track flythroughs, car turntables, HUD layouts, representative bot races, and audio previews. Independent LLM review should inspect motion, contact behavior, line readability, and sound where the available review tools support it. A numerical score is not a substitute for perception. Document unverified aspects clearly.

## Packaging and operations

Export native packages using pinned templates. Linux and Windows x86-64 and macOS Apple Silicon are the required builds; a universal Mac package can be added only with Intel testing. Include version, build/commit identifier when available, settings defaults, controls, Unlicense, asset CC0 notice, full engine/dependency notices, and known issues.

Use target-OS smoke tests; successful cross-export does not establish that the package launches. macOS Developer ID signing/notarization needs owner-supplied credentials. Without them, use Godot's built-in ad-hoc signing and label the package ad-hoc signed and unnotarized; test an actually downloaded/quarantined package and document its launch path. Follow the [macOS export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html). Keep credentials out of code, captures, and build logs. Do not advertise an unnotarized package as notarized.

The baseline has no telemetry upload, account system, model download, remote inference, ads, or paid content. Store only local gameplay records and diagnostic data, expose a local reset/delete option, and rotate logs. Releasing a patch requires the same relevant save/ghost/model compatibility checks as the initial build.
