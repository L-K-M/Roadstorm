# Roadstorm Racer! game design

Roadstorm Racer! is a welcoming arcade racer with depth in steering, line choice, and controlled slides. Short sessions should produce memorable moments: drifting beside the sea, overtaking across a viaduct, and battling friends through a narrow village. Everything below is the proposed 1.0 design. Measurements are starting tuning targets; preserve the intended behavior when adjusting them.

## Driving experience

### Controls and assistance

Use automatic transmission, with visible gears and audible shifts. Controller defaults: left stick steering, right trigger accelerate, left trigger brake/reverse, south face button handbrake, west face button camera, north face button reset, right shoulder rear view, and Menu pause. Keyboard defaults: WASD or arrows to drive, Space handbrake, C camera, R reset, Shift rear view, Escape pause. All gameplay bindings can be remapped; prompts follow the active device. Mouse use is optional in menus.

Braking becomes reverse only below 1 m/s after a 0.3-second hold; reversing never initiates at road speed. Digital steering ramps smoothly to avoid instant full lock. Steering sensitivity and stick deadzone are adjustable per device. Auto-accelerate, easier drift initiation, and gentle stability assistance are available without blocking career rewards. Informational tutorial prompts can be dismissed or replayed.

The default drift assist stabilizes a slide; it does not steer along the racing line. An optional stronger stability setting limits extreme yaw. Save these settings with Time Attack records so comparisons remain meaningful. No automatic braking assist is required for 1.0.

### Handling and drift

Normal steering should feel immediate at low speed and stable at high speed. Model forward speed, sideways motion, heading, surface grip, and grounding explicitly. Cars have distinct tuning but share the same rules.

| State | Entry and behavior | Exit |
| --- | --- | --- |
| Grip | Ordinary steering; high lateral damping and predictable speed-dependent turning | Intentional drift initiation, airtime, or impact |
| Drift entry | Above 12 m/s, significant steer and a handbrake tap; an assisted brake tap while steering is an alternative | Blend over about 0.2 seconds into sustained drift |
| Sustained drift | Useful slip angle roughly 12–40 degrees; throttle sustains speed; countersteer and steering change angle smoothly | Steering unwind, low speed, a major impact, or loss of ground |
| Recovery | Grip returns over about 0.35 seconds; heading and velocity align without snapping | Return to normal grip |
| Airborne | Preserve momentum, allow limited yaw correction, suppress drift rewards | Stable landing blends back into grip |

The angle is the difference between the car's forward direction and its travel direction on the road plane. Do not require a tiny analog input window to maintain it. Above roughly 50 degrees, default stability assistance gradually reduces further rotation. A player can still lose time through poor entry or a wide line, but routine drifts should not end in spins.

A clean drift through the benchmark sweeping corner should be within 5% of the elapsed time of an effective grip line. Tune this on the same car and upgrade preset. Drifting earns readable tire feedback, style score, and a small automatic exit surge after at least 0.6 seconds of meaningful grounded cornering. Initial surge: up to 4% added acceleration for 0.5 seconds, with a 2-second cooldown, never stackable. Do not give an unrestricted boost button or a required boost-management system.

Qualifying drift requires a real signed course turn, forward progress, speed, and maintained slip angle. Straight-road weaving, donuts, driving backwards, wall contact, and repeated resets yield no surge or style credits. Style rewards are capped and are not needed to win or progress. A clean grip line must remain competitive.

### Speed and surfaces

Use meters, seconds, and meters per second internally. The HUD converts to km/h or mph. Target stock top speeds of approximately 205–235 km/h, depending on car identity, rather than using exaggerated HUD numbers disconnected from the simulation. Tune perceived speed through road proportions, near scenery, engine pitch, and camera motion.

Asphalt is the baseline. Gravel gently reduces lateral grip and makes slides broader; it does not secretly punish drift. Short gravel sectors should remain competitive for every car. Dirt shoulders slow a car progressively and encourage a return to the road. Sand/grass beyond the shoulder impose stronger drag. Waterfall spray, rain decoration, and road paint do not introduce hidden friction changes. Communicate every handling-relevant surface with color, geometry, and tire sound.

No permanent mechanical damage, tire wear, fuel, repair bills, or manual tuning minigame. Cosmetic sparks and body movement communicate contact.

### Contact and recovery

Side contact nudges both cars and produces modest speed loss. Wall brushes scrub speed without gluing the car to a barrier. A major impact reduces forward speed, applies a bounded deflection, and returns control promptly; no prolonged crash movie. Prevent cars from riding on top of one another or launching into the sky.

Small jumps and crests are part of the road design. Landings preserve a usable forward direction, with visual suspension movement separated from collision. Reset after an explicit one-second hold, falling out of bounds, or remaining immobile away from valid road for three seconds. Flipped/invalid poses auto-recover. The manual reset is available immediately in Practice and paused training menus.

Reset to the last safe route anchor at or behind valid progress, at no more than 10 m/s, with 1.5 seconds of visibly indicated car-contact immunity. Keep terrain and barrier collision active. Immunity ends once the car is safely separated or the timer expires; do not materialize inside a rival. Reset adds elapsed time and never skips a checkpoint or advances rank unfairly. Block rewards during immunity and until valid forward motion resumes.

### Drafting

Following a rival within approximately 5–20 meters and a narrow forward cone for 0.7 seconds gives up to 2% drag reduction, fading within 0.5 seconds after leaving the wake. It cannot stack or exceed the normal maximum-speed allowance. AI and players use identical drafting. The cue is subtle; racing must still work without understanding this mechanic.

## Race rules and modes

### Standard race

Eight participants: one to four humans and enough AI to fill the field. Default three laps, with per-course tuning to keep races around three to five minutes. Quick Race offers one, three, or five laps. An optional humans-only local field can contain two to four cars; standard event results and career always use eight.

The flow is loading → grid introduction → 3/2/1/GO → racing → finishing → results. Countdown steering is allowed; acceleration takes effect at GO, without a false-start penalty. Rotate the player's starting row across career events rather than making position depend on grinding qualifications.

Progress requires swept forward crossings of ordered checkpoint gates. Rank by finished status, finish crossing time, completed laps, valid gate index, then continuous progress within that segment. Use participant ID only to order an exact internal tie; show a tie when displayed times coincide. Crossing a nearby overpass or cutting an infield does not advance the valid sequence. Wrong-way warnings appear after sustained reverse course motion, not during a momentary spin.

After the first finisher, show a 45-second finish deadline. Unfinished cars receive DNF and are ordered by valid progress. Hosts may choose to wait for every human; this is the default for Rookie solo Career. In that setting AI retire after 45 seconds and a separate visible five-minute limit after the first finish prevents an abandoned event from hanging. A finished human watches the remaining race through a simple spectator chase view and can see standings. They cannot interfere. Mechanical AI-completion tests disable finish deadlines; production deadline DNFs are measured separately rather than fixed with hidden catch-up.

Pause stops the shared race, timers, and scripted scenery. Host restart or return-to-menu requires a clear in-game confirmation; completing a result screen never applies rewards twice. Abandoning a race awards no completion credits. Leaving a cup preserves completed race results and permits continuation at its next grid.

### Mode definitions

| Mode | Players | Rules and rewards |
| --- | --- | --- |
| Quick Race | 1–4 | Choose course, car, laps, AI difficulty, and stock/garage configuration. Solo finishes earn credits. Multiplayer exhibition uses loaners and grants no career rewards. |
| Championship | 1–4 | Solo Career runs the unlock campaign. Local Cup runs the same schedules as exhibition with loaners and no career changes. |
| Time Attack | 1 | No opponents or contact; a flying-lap session with stock or separately recorded garage presets, local bests, medals, and optional local ghost. No credits. |
| Arcade Rush | 1 | One circuit lap from a standing start against a checkpoint timer; original checkpoint-pressure arcade flavor without separate maps. No AI collisions or career unlock dependencies. |
| Practice | 1 | Free laps, controls tutorial, optional braking/turn hints, instant restart/reset, no timer failure or rewards. |

All six courses are available in Practice, Time Attack, Arcade Rush, and Quick Race. Career gates cup progression, rather than hiding the scenery from casual play. Solo cars use the unlocked collection. Multiplayer exhibition makes all twelve cars available as clearly labeled stock loaners so a new group can play fairly immediately; loaning does not add them to the garage.

Arcade Rush uses three intermediate timing gates and the finish. For each course, measure a clean stock starter run first. Set initial allowance and extensions so total available time is about 120% of that reference on Rookie, 110% on Racer, and 102% on Expert. Rookie must tolerate a brief mistake; the timer cannot require upgrades or exploits. Extensions are earned once in order, pausing does not consume time, and expiry ends the attempt after a short readable cue. Store best finish time and drift score locally; this mode grants no upgrade credits.

Time Attack starts with a run-up before the finish line. A lap is invalid if any required gate is missed or reset is used; a reset begins a fresh run-up. Store car ID, configuration hash, assists, course revision, and handling revision. Record transforms for the local ghost; do not assume input replay recreates physics exactly. Medals are authored per course for a stock balanced starter; garage records occupy separate lists. No global leaderboard or account.

## Fair and assertive opponents

Two families share the field: authored **Classic Racers** and learned **Roadstormers**. Default eight-car races include two Roadstormers; the remaining AI slots are Classic Racers. A Classic Only setting is available. Surge learns pressure-oriented passing decisions; Switch learns patient line changes and corner-exit cutbacks. Both execute through the same low-level controller and physical limits. See [the opponent AI specification](OPPONENT_AI.md) for training, offline inference, safety, and evaluation requirements.

AI receives the same normalized driving commands and vehicle limits as a player. It can know course geometry, racing lines, and speed hints; it observes nearby vehicles through bounded local queries. It cannot know future human inputs. No secret grip, acceleration, top-speed multiplier, position-dependent catch-up, teleportation, or offscreen shortcut.

An opponent plans a target lane and speed ahead, brakes before hazards, initiates drift through the same interface, and chooses an overtaking side when there is space. It may hold one defensible line; it may not repeatedly swerve across an approaching car, brake-check, deliberately ram, or block a landing zone. Once substantially alongside, it leaves roughly one vehicle width plus a safety margin. Narrow sections use a temporary follow behavior when two cars cannot safely pass.

| Difficulty | Starting tuning targets | Intended behavior |
| --- | --- | --- |
| Rookie | 85–90% of validated safe reference pace; approximately 300 ms reaction delay | Early braking, visible openings, occasional gentle line errors |
| Racer | 93–98% reference pace; approximately 200 ms reaction delay | Confident drift lines and assertive but readable overtakes |
| Expert | 100–103% reference pace where physically achievable; approximately 120 ms reaction delay | Later braking, efficient lines, fewer mistakes; same vehicle envelope |

The percentages apply to desired line/speed planning relative to a documented reference driver, never to physical car capability. Tune each course and car; these starting ranges are not promises of equal human difficulty. Four seeded Classic personalities vary preferred line, passing patience, drafting, and drift style; the learned family adds its two trained styles. Personality changes decisions, not available grip or speed.

Recovery detects stalled progress, first attempts a safe reverse/rejoin, then uses the same reset system as a player. It never resets ahead. Log planned maneuvers, commands, contacts, reset count, and lap times. Inspect clips of recurrent collisions. In a clear-course benchmark, average AI resets should be below 0.1 per car per race; repeated failures at one segment block course acceptance. Learned rivals adapt tactical choices to recent nearby behavior, while difficulty and physical capability remain fixed. No position-based adaptive difficulty or comeback assist ships in the baseline.

## Courses

All route shapes and scenery arrangements are original. Familiar arcade qualities guide rhythm and readability; do not recreate commercial tracks. Each course has one fixed time of day and weather presentation. There is no dynamic wet-road model.

| Course | Initial length and road character | Major set pieces and palette |
| --- | --- | --- |
| Riviera Run | About 3.6 km; welcoming coastal sweepers, a village squeeze, cliff climb, tunnel, downhill return | Beach/marina panorama, aircraft crossing above a broad straight, cliff tunnel opening onto the sea; turquoise, cream, coral |
| Alpine Switchback | About 3.9 km; switchback climb, narrow traverse, long downhill esses, viaduct | Waterfall beside the climb, cable cars above the traverse, viaduct framed by snowy peaks; pine, cobalt, pale stone |
| Emerald Rally | About 3.5 km; flowing forest bends, short gravel section, lake crest and compression | Helicopter tracking a broad bend, lakeside timber bridge, forest opening with a distant cascade; emerald, amber, lake blue |
| Canyon Voltage | About 4.1 km; fast open straights, rock cuts, cambered gorge turns, rolling ridge | Animated wind farm, freight train on a high bridge, layered canyon overlook; ochre, red rock, electric teal |
| Metro Sunset | About 3.8 km; broad elevated expressway, tighter docks, long interchange sweep, bridge return | Container cranes and moving ship, suspension bridge, skyline reveal beneath original signs; violet, orange, cyan |
| Stormpeak Finale | About 4.3 km; mixed fast/technical sequences, dam climb, mountain tunnel, descending ridge | Dam spillway, long tunnel burst into distant storm light, turbine ridge and final summit view; slate, gold, saturated blue |

Target 60–95-second laps after measurement and adjustment. Course length is provisional; road rhythm and race duration take priority over hitting an exact distance. Course widths generally range from 9 to 20 meters, with 8-meter short squeezes only after testing passing room. Hairpin radii start around 28 meters and sweepers around 100 meters, subject to handling validation. Avoid blind mandatory braking immediately after a jump.

### Course acceptance contract

Each route contains at least two broad sweepers, two tight/medium turning sequences, one useful acceleration straight, two meaningful width transitions, a sustained climb/descent, and a crest or compression. Vary these patterns rather than repeating a generated template. Include three major scenic set pieces and smaller visual changes about every 5–10 seconds of travel.

Place braking warnings before the decision point; use chevrons, road edges, barriers, terrain shape, and contrast. A landmark cannot obscure the next important turn. Give difficult corners a forgiving exit and broad starts enough room for eight cars. Keep road-edge readability consistent across palettes, including reduced color perception.

Animated planes, helicopters, cable cars, trains, ships, turbines, waterfalls, flags, and simple geometric spectators are scenery. They are never unpredictable collision hazards. Trigger a spectacle from valid route progress with a cooldown so it is visible at racing speed and does not flicker or restart per camera. The simulation owns its shared state; cameras only render it. High scenery and road collision require sufficient clearance for the tallest car and jumps.

Track sources must define road, surface, barrier, grid, gate, recovery, line, speed, scenery, audio, and camera metadata. Render and collision meshes come from the same source. Check seams, route crossings, banking/grade continuity, start-grid space, safe anchors, unreachable scenery, and out-of-bounds recovery before finishing the art.

## Cars and garage

Names below are working content names, not cleared trademarks. Use fictional badges and original proportions rather than traced real vehicle bodies.

Scores are relative 1–5 authoring targets within one shared competitive class, not multipliers. A higher drift score means easier sustained sliding; a higher stability score means easier recovery. Acceleration/top speed trade off with turning and mass. Keep stock pace on a mixed reference course within approximately 5% for competent drivers before adding upgrades.

| Car | Silhouette and character | Acceleration / speed / grip / drift / stability | Unlock |
| --- | --- | --- | --- |
| Sparrow | Compact hatch, light and forgiving | 4 / 2 / 5 / 3 / 5 | Starter |
| Comet | Open roadster with balanced responses | 4 / 3 / 4 / 4 / 4 | Starter |
| Slidewinder | Angular sports coupe, inviting long slides | 3 / 4 / 3 / 5 / 4 | Starter |
| Trailbox | Boxy rally hatch, confident on gravel | 4 / 3 / 4 / 4 / 5 | Coastal Cup completion |
| Longshot | Broad muscle coupe, strong straight-line character | 5 / 4 / 2 / 4 / 3 | Coastal Cup podium |
| Meridian | Long grand tourer, calm fast sweepers | 3 / 5 / 3 / 3 / 5 | Highlands Cup completion |
| Rook | Rally sedan, flexible and planted | 4 / 3 / 5 / 3 / 4 | Highlands Cup podium |
| Sandhammer | Low racing pickup, weighty and playful | 5 / 3 / 3 / 4 / 4 | Skyline Cup completion |
| Prism | Low exotic wedge, sharp and fast | 3 / 5 / 4 / 4 / 3 | Skyline Cup podium |
| Vortex | Rounded mid-engine coupe, precise transitions | 4 / 4 / 4 / 5 / 3 | Storm Tour completion |
| Arrowhead | Prototype-inspired closed coupe, high commitment | 3 / 5 / 5 / 3 / 2 | Storm Tour podium |
| Thunderbrick | Eccentric compact racing van, wide and surprisingly agile | 5 / 3 / 3 / 5 / 4 | Storm Tour victory |

All cars share collision rules and remain usable on every course. Duplicate selections are allowed. Use at least four paint schemes per car and color/pattern player markers independent of paint. No real manufacturer, commercial sponsor, or borrowed logo.

### Upgrades

Each car has Engine, Tires, and Chassis, each with levels 0, 1, and 2. Level 1 costs 800 credits; level 2 costs another 1,600 credits. Fully upgrading one car costs 7,200 credits. Purchased levels can be equipped or unequipped freely; never destroy an earlier configuration.

Initial effects per level: Engine gives +3% acceleration and +1.5% top speed; Tires gives +5% lateral response/recovery rate; Chassis gives +4% steering response and 5% less impact speed loss. Cap aggregate top-speed improvement at 3% and acceleration at 6% under this system. Tires must not prevent drifting or silently turn a drift car into a grip car. Show the actual effect, compare equipped and stock values, and retune any upgrade that harms the intended handling identity.

Local racing defaults to stock loaners with no upgrade bonuses. An explicit Garage Upgrades option permits the host's unlocked cars/configurations for everyone; explain it before readying. Solo Quick Race offers Stock or Garage: AI use stock in Stock mode or the human's equipped three category levels in Garage mode. Local Garage AI use the host's saved configuration for their assigned car, just as a human choosing that car would. Career uses fixed opponent upgrade presets by cup rather than secretly matching the player's purchases. Difficulty never changes physics.

## Career and rewards

Use four local profile slots and a temporary guest profile. A selected profile owns one shared garage, credits, settings, cup records, and local records. Player devices are separate from profiles. Local exhibition never silently writes progression for guests.

| Cup | Events | Availability | Car awards |
| --- | --- | --- | --- |
| Coastal Cup | Riviera Run, Emerald Rally | Open initially | Trailbox on completion, Longshot on podium |
| Highlands Cup | Alpine Switchback, Canyon Voltage | Complete Coastal Cup | Meridian on completion, Rook on podium |
| Skyline Cup | Metro Sunset, Stormpeak Finale | Complete Highlands Cup | Sandhammer on completion, Prism on podium |
| Storm Tour | Riviera, Emerald, Alpine, Canyon, Metro, Stormpeak | Complete all three regional cups | Vortex on completion, Arrowhead on podium, Thunderbrick on victory |

Cup points are 10/8/6/5/4/3/2/1 for finishing places. DNF earns zero points. Solo career completion awards require a valid human finish in every scheduled event; eighth place qualifies. A human DNF/withdrawal leaves the event pending for retry or return to the cup menu, preserving previous completed races and discarding that attempt's cup standings. Local exhibition may advance after DNF normally. Award all earned thresholds together, and only once per profile. Any difficulty qualifies. Retry freely; there is no entry fee or forced consumable.

Fix the eight participant IDs, AI names/families/personalities, assigned AI cars, difficulty, seed, and cumulative points when a cup starts, including its two Roadstormers unless Classic Only is selected. Save the roster and standings with cup progress. The human may change unlocked cars/loadouts between events; AI retain their assigned cars and fixed cup presets. Local Cup fixes its human slots at the start; a withdrawal converts that participant to AI for the remainder rather than admitting a new mid-cup participant.

Career AI upgrade levels (Engine/Tires/Chassis) are Coastal 0/0/0, Highlands 1/0/0, Skyline 1/1/1, and Storm Tour 2/1/1. Tune Rookie so stock starters can still complete and win through good driving; purchases provide a modest real benefit. Cup difficulty and AI family preference stay fixed until a new cup starts. Resolve tied points by wins, then final-event finish, then earlier event finishes from latest to earliest. If all competitive results are identical, display a shared cup place; participant ID orders the screen only. Podium/victory thresholds use the shared place where relevant.

Each completed standard three-lap solo Quick Race or Career race awards 800 base credits, plus 400/300/200/100 for first through fourth, plus up to 100 for varied controlled drifting. Scale the entire Quick Race reward by selected laps divided by three, rounding once after summing, so one-lap farming does not pay a full three-lap reward. Finish lower and still receive the scaled base; DNF/abandon grants none. Repeated completed events pay normally. Training, Time Attack, Arcade Rush, and multiplayer exhibition grant no credits. A standard three-lap finish buys the first upgrade; about eight ordinary standard finishes buy all upgrades on a favorite car. Check the shortest legal event's credits per minute when tuning. Currency cannot buy cup points or bypass driving achievements. Paint schemes are free once the car unlocks, keeping the economy focused on upgrades.

Save cup progress after every completed race, resume at the next grid, and apply the race reward exactly once. A retry creates a new event instance. Target a first cup in roughly ten minutes and a complete collection within a few hours of replay and improvement on an accessible difficulty; verify the actual pacing in M6/M8 rather than padding it with grind.

## Presentation and audio

Favor clear car silhouettes, faceted geometry, saturated environments, limited materials, and a strong distant horizon. Use vertex colors and small generated texture atlases. Soft fog, simple lighting, contact shadows, wheel motion, restrained smoke, and sparks provide speed cues. Optional low-resolution 3D rendering and ordered dithering can evoke older hardware, while text stays crisp. No mandatory screen blur, camera shake, or flashing lightning.

Each player can choose chase, near chase, or hood camera. Chase cameras look into corners, avoid walls, and stabilize the horizon. Provide adjustable FOV, shake, and drift camera rotation; rear view is momentary. Do not add camera motion that hides road direction during a drift.

Use original synthesizer compositions: six loopable race themes, one menu/garage theme, one results theme, and short transition/reward stingers. Engine families, tires, impacts, landings, UI, and environmental layers are generated from oscillators and noise. No sampled songs, real driver voices, or imitation celebrity announcer. Text and tones communicate start, checkpoints, finish, and rewards. Separate music, vehicle, environment, and UI volume controls; a mono output option and reduced-dynamic-range mix support varied setups.

## Local multiplayer interface

Attract/title → mode/profile → join → course/cup and difficulty → car/configuration → ready → race. A player presses a join button on an unclaimed device, then selects independently. Only the host controls shared event settings; all players can review them. Joining/leaving happens in the lobby, not halfway through a live race.

One player fills the screen. Two players choose horizontal or vertical halves. Three players use a 2×2 grid with standings/minimap in the spare panel. Four use all quadrants. There is no fifth 3D camera. A global HUD layer draws each player's native-resolution UI over its 3D view.

Each panel shows position, lap, speed/units, time, drift cue, turn warning, and player marker; the shared map can simplify when space is limited. At 1080p, target at least 20-pixel essential labels and 32-pixel speed numerals within each quadrant, scalable to 150%. Menus target 24-pixel body text at 1080p. Test long labels and all scales for clipping. Use symbols/numbers as well as color.

Pause or device disconnect pauses everyone and names the affected slot. Offer reconnect, explicit reassignment, or withdrawal to AI. Retain the slot until the choice is made; never silently attach a newly connected controller. Window focus loss pauses offline races and releases held input. Reconnection requires fresh button states to avoid stuck acceleration.

## Accessibility and onboarding

The opening tutorial is a short optional Practice sequence: accelerate/brake, take a bend, initiate a drift, recover, and reset. Teach one action at a time and adapt prompts to remapped controls. Offer immediate replay from the menu.

Ship controller and keyboard remapping, deadzones, digital steering smoothing, sensitivity, auto-accelerate, drift/stability assistance, adjustable FOV, horizon stabilization, text scale, high-contrast markers, independent volume buses, mono output, reduced dynamic range, and disable options for camera shake, speed effects, and flashing. Meaningful information never depends solely on color or sound. There is no informational spoken dialogue requiring hearing; provide visible equivalents for every cue.

English is the launch language. Store strings in localization tables from the start and keep layout expandable. Additional languages require their own LLM-authored/reviewed text and original or properly licensed glyph coverage; do not claim support before checking it in the actual UI.

## Experience review checklist

- A new driver understands forward travel, turning, drifting, and recovery without reading a manual.
- A useful drift feels easier to sustain than an accidental spin, with understandable speed consequences.
- Grip driving remains viable and upgrades preserve each car's personality.
- Every course is recognizable from both its road sequence and at least three landmarks.
- Rivals fight for space without repeated bullying or visible special powers.
- Four people can join, read the HUD, finish a race, and rematch using their own controllers.
- Unlocks arrive predictably, and a poor result still permits progression and practice.
- Sound remains intelligible and comfortable with four engines, environmental loops, and music.

Review gameplay captures, telemetry, and audio previews, not just isolated screenshots. If human feedback is available, record observations and have agents implement the changes; this preserves the LLM production goal.
