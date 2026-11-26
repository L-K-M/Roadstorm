# Roadstorm Racer! technical design

Build a native Godot project with text-based source resources, a shared fixed-tick race simulation, reproducible content generation, and automated inspection tools. The proposed engine is Godot 4.7.2 Standard with typed GDScript and matching export templates. Pin exact binaries and checksums in M0; do not track an automatically moving stable download. The official [release archive](https://godotengine.org/download/archive/) is the version authority.

## Platform and rendering baseline

Proposed support targets are Apple Silicon macOS 14 or later, Windows 11 x86-64, and Ubuntu 24.04 x86-64. These are product test targets, not verified minimum requirements. Intel Mac, other Linux distributions, browser, mobile, and console exports are outside the initial platform commitment. Native tests on each OS are required before a supported-platform claim.

Start with Compatibility rendering: simple directional lighting, vertex colors, limited shadows, optional MSAA, restrained transparency, and no expensive screen-space effects. Benchmark Mobile rendering on the reference Mac before locking the choice. Choose from measured frame times and visual needs, following Godot's [renderer documentation](https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html); API age alone does not determine performance.

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
| Driver | Human input or AI decisions converted to commands | A separate set of physical rules |
| ArcadeMotor | Vehicle movement, grip/drift, grounding, surface response | Currency, UI, or scene transitions |
| ContactResolver | Stable pair contacts, bounded response and immunity | Hidden advantages for AI |
| CourseProgress | Valid gates, route-local position, recovery anchors, lap timing | Nearest-road teleportation |
| SaveService | Versioned snapshots, transactions, backups and migrations | Loading executable code from saves |
| Audio/Presentation directors | Playback, effects, cameras and HUDs from events | Changing speed, rank, random decisions or rewards |

Use a `DriverCommand` structure with steer in [-1,1], throttle/brake/handbrake in [0,1], reset request, and relevant edge-triggered actions. Commands are sampled once per physics tick. A controller or either AI family supplies the same structure. Special learned opponents are specified separately in [OPPONENT_AI.md](OPPONENT_AI.md).

Publish typed events such as countdown changed, drift began, impact occurred, gate crossed, lap completed, participant finished, and result committed. Consumers may draw or play sounds but cannot mutate the originating race result. Use scoped event connections and explicit teardown to prevent duplicate listeners after rematches.

## Movement and contacts

Use a custom arcade motor around `CharacterBody3D`, world sweeps, and ground probes. This is a tuning choice for forgiving drift. Godot's [VehicleBody3D documentation](https://docs.godotengine.org/en/stable/classes/class_vehiclebody3d.html) notes limitations; its built-in vehicle behavior is not the required handling specification.

Start at 60 fixed physics ticks per second and interpolate the visual transform. State includes world velocity, road-plane forward/lateral velocity, heading, yaw response, surface, support normal, grounded/airborne state, drift timer, surge cooldown, contact state, and valid progress. Apply acceleration and drag along the support plane, then controlled yaw and lateral damping according to grip/drift state. All tunable values live in versioned car/surface resources.

Use a central support probe plus four footprint probes, bounded normal smoothing, and bounded ground attraction. Disable attraction during intended airtime; never pull the car through a bridge or onto a ceiling. Visual suspension, pitch, roll, wheel rotation, and steering animate child nodes. They do not rotate the collision body into unstable poses.

World collision uses sweeps against thickened road/barrier geometry rather than relying on final-position overlap. At approximately 65 m/s a car travels more than a meter per tick; maximum-speed narrow barriers and oblique impacts require dedicated tests. Use bounded movement subdivisions where necessary, with a strict work cap; measure before increasing the global tick rate.

Treat vehicle-to-vehicle response as one coordinated system. Car bodies collide with the static world, and their Godot collision masks exclude ordinary car-to-car physical response because the custom resolver owns it. Evaluate relative swept hull motion from one shared tick-start snapshot, rather than endpoint overlaps or independently moving each car against stationary rivals. Apply bounded mass-weighted speed/deflection responses in stable participant order and correct overlap while rechecking world collision. Avoid applying a second engine response to the same contact. Prototype this in the laboratory before full racing. Prevent vertical launching and cap positional correction; recovery handles invalid states.

Fixed ticks and seeded decisions make tests more repeatable, but do not promise cross-platform deterministic Godot physics. Use tolerances for simulation regressions, exact checks for pure rules/math, and sampled-transform ghosts. See Godot's [physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html) and [physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html).

## Content contracts

Use stable semantic IDs that do not change with display names. Definitions have schema versions and explicit dependencies. Runtime resources are typed; editable source recipes can be JSON/text plus original scripts. Validate every numeric range and referenced asset before baking.

| Definition | Required information |
| --- | --- |
| Car | ID/version, source mesh and LODs, dimensions, mass/contact proxy, stock handling, engine family, paints, icon, upgrade applicability |
| Track | ID/revision, spline controls, width/bank/elevation, surfaces, barriers, grid, ordered gates, sectors, safe anchors, AI lines/speed hints, scenery/audio triggers, bounds, lighting |
| Event | ID, mode, track order, laps, AI roster/difficulty/families, configuration rules, time limits, reward table, unlock dependencies |
| Upgrade | ID, car/category, level, price, additive/multiplicative effects, caps and display text |
| AI profile | Family, difficulty, personality, legal planning bounds, policy/model revision when learned |
| Ghost | Track and handling revisions, car/configuration, assists, sampling rate, sample data, lap time, validity/hash |
| Model | Architecture/schema, numeric weights, normalization, training/data revisions, evaluation report, license and provenance |

### Track compiler

An authored centerline is resampled by arc length. Use a stable transported road frame rather than a world-up cross product that flips at vertical changes. Interpolate width, banking, and surface transitions smoothly. Generate the road strip, shoulders, terrain skirts, barriers, collision, AI samples, gates, safe anchors, and minimap from shared samples. Split long meshes into spatial chunks with LODs. Build collision from simplified matching geometry and inspect seams.

Constrain normal road grade to an initial 12% target, banking to approximately ±12 degrees, and rapid curvature/width changes to reviewed limits. Short exceptions require explicit metadata and laboratory validation. Validate curvature, available stopping distance, jump landing space, road clearance, self-intersections, route continuity, eight-car grid space, barrier placement, and legal recovery areas. Self-crossings are allowed only when annotated as an overpass with sufficient vertical clearance.

Scenery recipes place props with exclusion volumes around the route, readable sightlines before turns, and shared progress-triggered animation. Use partitioned `MultiMesh` groups for repeated trees, spectators, rocks, and flags. Generate road/prop geometry during development/build, not every race. Godot documents [procedural geometry](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/index.html); the source recipes and validator are original project tools.

Progress projection searches a bounded neighborhood of the previous valid route sample and required gate. A separate recovery query can search more widely only to return the car behind its last valid progress. Ordered swept gates are authoritative for laps; a nearest-point query cannot skip a hairpin, overpass, or sector. Keep physical distance and validated race progress distinct.

### Asset generation

Prefer original GDScript mesh-baking tools, SVG generators, and Python synthesis/composition scripts with pinned versions and seeds. Emit engine-native mesh/scene resources or validated interchange formats; document the chosen format in M0/M2. No Blender dependency is needed for the baseline, although an original scripted Blender tool can be added if it solves a measured production problem. Retain its version and license in the tool inventory if used.

Every generated asset references a source recipe and manifest record. Regeneration should produce identical normalized content under the pinned toolchain; disregard unavoidable timestamps only through a documented normalization step. A generator change triggers dependent assets, contact-sheet review, and relevant performance tests.

## Split-screen and audio

One `World3D` contains the simulation. Each local player gets a `SubViewport`, `Camera3D`, and panel-specific HUD state. Explicitly share the world, disable unused viewports, and avoid an extra active root 3D camera. Native-resolution UI overlays the scaled 3D images. Godot's [viewport documentation](https://docs.godotengine.org/en/stable/tutorials/rendering/viewports.html) describes shared worlds and multiple cameras; it does not automatically implement player/device ownership.

Route raw input by device ID to a stable player slot. Keyboard occupies at most one slot. Associate bindings/deadzones with device profiles and confirm explicit reassignment after disconnect. Reset held commands on focus loss, pause, reassignment, or reconnect. Menus distinguish host event controls from each slot's local car selection. Test real controllers in addition to synthetic events; see [Godot controller support](https://docs.godotengine.org/en/stable/tutorials/inputs/controllers_gamepads_joysticks.html).

Use one music/UI mix and an original shared sound-priority system, rather than four full independent listener mixes. Prioritize each local engine, strongest nearby rivals, important cues, and nearest relevant scenery. Compute bounded weights from player listeners, cap total voices, normalize accumulation, and limit environmental loops. Start with a 32-voice budget and four engine families; profile decoder/voice cost. Pre-render most synth loops rather than running expensive real-time synthesis per camera.

Global pause halts simulation time, race deadlines, and gameplay-triggered animations. Menu sound remains functional. Music may duck or pause according to one consistent setting. No cue depends on a particular camera being active.

## Persistence and records

Store user data in the platform's Godot user-data directory, never in the checkout. Use validated JSON or another nonexecutable format, with schema version, profile ID, credits, unlocked cars, purchased/equipped levels, cup state, records, settings, and applied reward transaction IDs. Clamp only recoverable invalid settings; treat inconsistent progression as a recoverable error, not permission to invent purchases.

Save to a temporary file, flush/close, validate, then replace the primary file and retain the last good backup using the safest target-platform sequence. Test interruption between each step. Include a checksum for accidental corruption, not as a security claim. Keep a recovery screen that can restore a backup or create a new profile without silently destroying evidence.

An immutable event result has a unique event-instance ID. A single transaction updates credits, unlocks, and cup progression; retries/reopened results cannot apply it again. Bound the retained transaction history through archived cup/event state without reintroducing duplicate awards. Test resuming a cup on both sides of the commit boundary.

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

## Verification matrix

Implement a small original `SceneTree` headless test runner with assertions and nonzero failure exits. Avoid a mandatory test framework dependency. Use exact checks for pure rules and tolerances plus telemetry for physical scenarios. Godot supports headless scripts and exports through its [command-line interface](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html).

| ID | Coverage | Evidence and gate |
| --- | --- | --- |
| T01 | Clean import, typed scripts, resources, source/generated references | Clean-checkout CI pass, no missing resource or script errors |
| T02 | Steering/drift math, cooldowns, surfaces, speed/upgrade caps | Boundary tests, no invalid state, no weave/donut/wall farming |
| T03 | Driving at 30/60/120 rendered FPS | Fixed-tick scenario results within documented position/time tolerance; no frame-rate reward changes |
| T04 | Maximum-speed wall/car contacts, jumps, slopes, landing, recovery | No tunneling, launches, nonfinite states, or forward-progress reset exploits |
| T05 | Gates, reverse/duplicate crossings, overpasses, laps, ties, DNF | Exact expected results from constructed scenarios |
| T06 | Cups, rewards, purchases, loadouts, unlock graph | All twelve reachable; no negative balance or duplicate award; price/effect caps hold |
| T07 | Save interruption, corrupt/oversize data, migrations, backup | Recovery retains last good state; no silent destructive reset |
| T08 | Player routing, join/leave, focus, reconnect, remapping | Synthetic scenarios plus actual four-pad and keyboard-plus-three-pad sessions |
| T09 | Track bake, seams, bounds, clearance, anchors, generated assets | Six courses validate; deliberately broken fixtures fail |
| T10 | AI legality and learned-policy safety | Shared physical limits, no nonfinite/out-of-range outputs, no hidden catch-up; separate evaluation report |
| T11 | Race endurance and fair pacing | At release, 100 seeds × six tracks × three difficulties with a rotating mixed roster and finish deadlines disabled; ≥99% AI entry completion, no deadlock; separately test deadline DNFs across reference human pace ranges; nightly subsets during development |
| T12 | Car/course/preset compatibility | Each of 12 cars on six courses at stock and maximum upgrades completes a clean run; pairwise layout/difficulty/assistance cases supplement this matrix |
| T13 | UI and experience | Screenshots/footage at every layout/text scale, controller-only flows, drift and course review, audio previews |
| T14 | Performance and endurance | Every course/layout benchmark plus a two-hour mixed-mode session; no progressive resource leak |
| T15 | Provenance, rights, package contents, offline notices | All shipped paths accounted for; exact runtime/dependency notices present |
| T16 | Native platform distribution | Launch/join/race/save/relaunch offline on each supported OS, release checksum and build ID captured |

Run fast checks on changes; run relevant scenarios when their systems or assets change. Full endurance/evaluation batches belong at milestone and release gates. Seeded tests aid reproduction but do not guarantee identical physics on different machines. Record engine, platform, content, handling, and model revisions with failures.

Provide deterministic capture scripts for track flythroughs, car turntables, HUD layouts, representative bot races, and audio previews. Independent LLM review should inspect motion, contact behavior, line readability, and sound where the available review tools support it. A numerical score is not a substitute for perception. Document unverified aspects clearly.

## Packaging and operations

Export native packages using pinned templates. Linux and Windows x86-64 and macOS Apple Silicon are the required builds; a universal Mac package can be added only with Intel testing. Include version, build/commit identifier when available, settings defaults, controls, Unlicense, asset CC0 notice, full engine/dependency notices, and known issues.

Use target-OS smoke tests; successful cross-export does not establish that the package launches. macOS signing/notarization needs owner-supplied credentials for a notarized release; follow the [macOS export guide](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html). Keep credentials out of code, captures, and build logs. Publish unsigned packages only with accurate labeling and installation guidance.

The baseline has no telemetry upload, account system, model download, remote inference, ads, or paid content. Store only local gameplay records and diagnostic data, expose a local reset/delete option, and rotate logs. Releasing a patch requires the same relevant save/ghost/model compatibility checks as the initial build.
