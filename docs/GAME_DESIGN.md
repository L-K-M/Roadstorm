# Roadstorm Racer! game design

Roadstorm Racer! is a welcoming arcade racer with depth in steering, line choice, and controlled slides. Short sessions should produce memorable moments: drifting beside the sea, overtaking across a viaduct, and battling friends through a narrow village. Everything below is the proposed 1.0 design. Measurements are starting tuning targets; preserve the intended behavior when adjusting them.

## Driving experience

### Controls and assistance

Use automatic transmission, with visible gears and audible shifts. Controller defaults: left stick steering, right trigger accelerate, left trigger brake/reverse, south face button handbrake, west face button camera, north face button reset, right shoulder rear view, and Menu pause. Keyboard defaults: WASD or arrows to drive, Space handbrake, C camera, R reset, Shift rear view, Escape pause. All gameplay bindings can be remapped; prompts follow the active device. Mouse use is optional in menus.

Braking becomes reverse only below 1 m/s after a 0.3-second hold; reversing never initiates at road speed. Digital steering ramps smoothly to avoid instant full lock. Steering sensitivity and stick deadzone are adjustable per device. Auto-accelerate, easier drift initiation, and gentle stability assistance are available without blocking career rewards. Informational tutorial prompts can be dismissed or replayed.

The default drift assist stabilizes a slide; it does not steer along the racing line. An optional stronger stability setting limits extreme yaw. Save these settings with Time Attack records so comparisons remain meaningful. No automatic braking assist is required for 1.0.

WASD and arrows are alternative bindings for one keyboard player; shared-keyboard multiplayer is outside baseline support. Bindings/deadzones belong to a device preset; assists, steering smoothing, camera/FOV and HUD preferences belong to the player slot. The host may save those presets in the active local profile; guests start from defaults and can adjust them in the lobby. Device reassignment preserves the slot's gameplay/camera settings. AI and calibration drivers use Standard assists, exposed to humans too, with no extra stabilization unavailable to players.

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

A clean drift through the benchmark sweeping corner should be within 5% of the elapsed time of an effective grip line. Compare additional corner classes and mixed laps using [the handling fixtures](BENCHMARKS.md#handling-fixtures). Drifting earns readable tire feedback, style score, and a small automatic exit surge. Initial surge candidate: add at most 1 m/s of forward speed smoothly over 0.5 seconds, capped at the car's ordinary upgraded top speed, with a 2-second cooldown and no stacking. M1 compares 0.5/1/1.5 m/s candidates and retains the smallest useful result that preserves grip competitiveness. This replaces an ambiguous percentage of unspecified acceleration; none of the candidates is already validated. Do not add an unrestricted boost button or required boost-management system.

Qualifying drift requires a tagged signed turn zone, speed ≥12 m/s, slip 12–40 degrees in the matching turn direction, at least 0.6 seconds grounded, ≥10 m valid forward progress and ≥8 degrees course-heading change. Accrue 20 style points per qualifying second, capped at 80 per turn ID per lap; stop/rearm across contact, reset or loss of eligibility. A successful clean exit may grant one surge per turn ID/lap. Wall/car contact cancels the active attempt, and immunity or recovery suppresses new style/surge until 10 m valid travel and 0.5 seconds contact-free. Earlier valid points are retained. Style credits are `min(100, floor(style_points / 10))` before race-length scaling. Version these initial constants with handling data and test their boundaries.

Straight-road weaving, donuts, reversing, wall grinding and repeated resets yield no surge or style credits. Style rewards are optional for winning/progression; useful grip driving remains competitive.

### Speed and surfaces

Use meters, seconds, and meters per second internally. The HUD converts to km/h or mph. Target stock top speeds of approximately 205–235 km/h, depending on car identity, rather than using exaggerated HUD numbers disconnected from the simulation. Tune perceived speed through road proportions, near scenery, engine pitch, and camera motion.

Asphalt is the baseline. Gravel gently reduces lateral grip and makes slides broader; it does not secretly punish drift. Short gravel sectors should remain competitive for every car. Dirt shoulders slow a car progressively and encourage a return to the road. Sand/grass beyond the shoulder impose stronger drag. Waterfall spray, rain decoration, and road paint do not introduce hidden friction changes. Communicate every handling-relevant surface with color, geometry, and tire sound.

No permanent mechanical damage, tire wear, fuel, repair bills, or manual tuning minigame. Contact can loosen/detach cosmetic parts as specified below.

### Contact and recovery

Side contact nudges both cars and produces modest speed loss. Wall brushes scrub speed without gluing the car to a barrier. A major impact reduces forward speed, applies a bounded deflection, and returns control promptly; no prolonged crash movie. Prevent cars from riding on top of one another or launching into the sky.

Small jumps and crests are part of the road design. Landings preserve a usable forward direction, with visual suspension movement separated from collision. Reset after an explicit one-second hold, falling out of bounds, or remaining immobile away from valid road for three seconds. Flipped/invalid poses auto-recover. Practice also exposes an immediate reset action in its pause menu.

Reset to the last unoccupied safe route anchor at or behind valid progress, at no more than 10 m/s, with 1.5 seconds of visibly indicated car-contact immunity. Keep terrain and barrier collision active. If an anchor is blocked, search farther backward or hold the car harmlessly until clear. At immunity expiry, resolve overlap through safe placement before enabling contact; never release a large overlap impulse. The one-second reset hold consumes ordinary race time; there is no extra hidden time penalty. Reset never skips a checkpoint or advances rank unfairly. Suppression during recovery applies to new drift style/surge, not previously earned race/cup payouts.

### Cosmetic impact damage

Front and rear bumpers can loosen, rattle and detach after contact. A rear wing or comparable trim piece may be a third detachable slot on cars that have one. Use at most three slots per car; wheels, doors and major body deformation are outside this simple model. Impact locations select the affected part rather than making an unrelated bumper pop off.

Each part has intact, loose and detached visual states. Initial tuning: a contact-induced velocity change of at least 2 m/s loosens the struck part; at least 5 m/s in one hit, or 8 m/s accumulated across that part's hits, detaches it. These are cosmetic thresholds to validate in M5, not another collision-response calculation. Coalesce one physical contact's repeated notifications and detach at most one part per impact, with a 0.5-second per-car effect cooldown. Repeated wall grinding cannot spawn an unlimited stream of copies.

A detached bumper inherits the car's committed motion, bounces/tumbles briefly, then slides along the road with short metal sparks and a synthesized scrape. Debris interacts visually with the static road/terrain; racers drive through it. It never blocks a car, changes a surface, advances a gate, becomes an AI obstacle or adds a second impact impulse. Part removal never changes car mass, collision hull, grip, acceleration, steering or top speed. Ordinary impact speed loss still applies once, as already specified.

Share a pool of at most 24 debris pieces across the race and all cameras, with six-second lifetimes and a final one-second fade. At capacity recycle the oldest off-screen piece; if every piece is visible, skip the new fragment while still showing the car's correct detached state. Cap global spark particles at 128 and prioritize at most four visible sliding sources. Fade pieces that leave all views; no per-camera copies. Existing effects/audio budgets include this feature.

Start each grid, restarted session and manual/automatic recovery with repaired visual parts. Hide restoration in the recovery fade; earlier debris simply expires. Time Attack/Arcade Rush otherwise keep the current session's cosmetic state until restart/recovery. No garage repair cost, damage-based reward, performance penalty or persistent damage save. Offer reduced sparks and a cosmetic-effects toggle for comfort/performance; the car and race follow identical rules in every setting.

### Drafting

Following a rival within approximately 5–20 meters and a narrow forward cone for 0.7 seconds gives up to 2% drag reduction, fading within 0.5 seconds after leaving the wake. It cannot stack or exceed the normal maximum-speed allowance. AI and players use identical drafting. The cue is subtle; racing must still work without understanding this mechanic.

Initial cone is ±10 degrees of the leader's rear direction with lateral separation ≤1.5 m. The motor records wake eligibility/fade and tests the closing-distance effect. Tune the provisional drag reduction only after the drafting fixture; do not assume a numerical percentage is perceptible or remove the mechanic from an untested estimate.

## Race rules and modes

### Standard race

Eight participants: one to four humans and enough AI to fill the field. Career races use three laps; tune provisional route lengths and per-course pace for roughly three to five minutes. Quick Race offers one, three, or five laps. Optional humans-only Quick Race is a two-to-four-player exhibition with zero AI, including zero Roadstormers, and no career rewards. Local Cups and career use eight participants.

The flow is loading → grid introduction → 3/2/1/GO → racing → finishing → results. Countdown steering is allowed; acceleration takes effect at GO, without a false-start penalty. Standard grids have two columns and four rows. Quick Race/exhibition uses a seeded permutation of participant IDs; career rotates the human's row by cup seed and event index, with the seven AI assigned by a saved seeded order. Store the resolved grid and rule revision. Arcade Rush has one standing-start slot; Time Attack uses a run-up. No qualifying grind is required.

Progress requires legal swept forward crossings of every ordered validation gate. Rank valid finishers by unrounded crossing time, then unfinished cars by completed laps, valid gate and segment progress. Interpolate the crossing within the accepted tick trajectory and store integer microseconds; exact internal time equality uses participant ID for distinct race places/points. Equal rounded display times are a close finish, not a shared competitive tie; show more precision if needed. Crossing an overpass, correcting an overlap or resetting cannot advance gates. Wrong-way warnings appear after sustained reverse course motion, not during a momentary spin.

Gates span the full legal route/runoff corridor with route/height constraints; they are at most 100 m apart and surround shortcut-sensitive sections. Beyond a required missed gate by 10 m, show a clear warning; beyond 30 m or two seconds, auto-reset to its preceding anchor. A legal jump cannot silently miss an undersized gate. Timing gates and scenic trigger zones are separate from the validation sequence.

After the first finisher, Standard Finish waits 45 seconds; remaining cars receive DNF ordered by valid progress. Wait for Humans, the Rookie solo Career default, lets **all** unfinished AI and humans keep racing until the last active human finishes or 300 seconds after the first finish. If humans finish before remaining AI, allow those AI until the later of the standard 45-second deadline or the last-human finish; then classify unfinished entries DNF. Do not retire AI early while a slow human can still improve rank. Show the active deadline.

An independent GO-based safety cap is `max(600 seconds, 3 * authored reference event duration)`, covering events in which nobody finishes; show a warning 30 seconds before it expires. At that cap classify remaining entries DNF. The mechanical harness replaces these production policies with its own documented timeout. Production deadline DNFs remain separate from mechanical reliability metrics.

On finish, hand the physical car to a short noncolliding cooldown drive, then remove it after three seconds; keep its result data. On retirement/withdrawal remove collision immediately and fade it out. A finished human's panel becomes a spectator view and cannot interfere. A voluntary in-race withdrawal retires that attempt; cup-slot conversion to AI takes effect at the next event. In humans-only Quick Race never introduce AI; if fewer than two participating slots remain because of withdrawal, end the exhibition explicitly. Normal finishing does not remove a participating slot or prematurely stop a two-player race. All-terminal participants transition directly to results.

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

Arcade Rush is stock-only, with no other cars. Use three intermediate timing gates plus the finish, and the selected stock car's standing-start reference splits from [BENCHMARKS.md](BENCHMARKS.md#reference-driver-and-records). Initial factors are 1.20/1.10/1.02 for Rookie/Racer/Expert. For each of four sectors set budget `b_i = factor * reference_sector_seconds + measured_mistake_margin_i`, rounding to milliseconds. Initial time is `b_0`; each valid ordered intermediate crossing adds the next budget once. Record final budgets in Event data. Rookie's measured margin must permit one brief mistake; Expert's margin must account for observed run variance rather than blindly applying 2%.

Process swept timing-gate crossings before expiry at the same timestamp, so exactly reaching zero on a valid crossing succeeds. A reverse/repeated/skipped gate grants nothing. Reset consumes time normally. Pause freezes the timer; expiry ends the attempt visibly. Record successful finish time/style keyed by car, difficulty, assists, course/handling, timer/Event-rule and style-scoring revisions. Timer/difficulty/assist changes start a new attempt. Upgrades are disabled. This mode grants no credits.

Time Attack starts with a run-up before the finish line. A lap is invalid if any ordered validation gate is missed or reset is used; a reset begins a fresh run-up. Car/loadout/assist changes require a new session and invalidate the active lap. Store car ID, configuration hash, assists, course revision, and handling revision. Record transforms for the local ghost; do not assume input replay recreates physics exactly. Standard medal sessions use `car.balanced_starter` (working name Comet), stock 0/0/0 and Standard assists, with thresholds defined by the reference contract. Other stock cars, garage presets and assist combinations receive separately keyed records. No global leaderboard or account.

## Fair and assertive opponents

Two families share the field: authored **Classic Racers** and learned **Roadstormers**. Default eight-car races include two Roadstormers; the remaining AI slots are Classic Racers. A Classic Only setting is available. Surge learns pressure-oriented passing decisions; Switch learns patient line changes and corner-exit cutbacks. Both execute through the same low-level controller and physical limits. See [the opponent AI specification](OPPONENT_AI.md) for training, offline inference, safety, and evaluation requirements.

AI receives the same normalized driving commands and vehicle limits as a player. It can know course geometry, racing lines, and speed hints; it observes nearby vehicles through bounded local queries. It cannot know future human inputs. No secret grip, acceleration, top-speed multiplier, position-dependent catch-up, teleportation, or offscreen shortcut.

An opponent plans a target lane and speed ahead, brakes before hazards, initiates drift through the same interface, and chooses an overtaking side when there is space. It may hold one defensible line; it may not repeatedly swerve across an approaching car, brake-check, deliberately ram, or block a landing zone. Once substantially alongside, it leaves roughly one vehicle width plus a safety margin. Narrow sections use a temporary follow behavior when two cars cannot safely pass.

| Difficulty | Starting tuning targets | Intended behavior |
| --- | --- | --- |
| Rookie | 85–90% of calibration speed profile; traffic observation age 18 ticks (300 ms) | Early braking, visible openings, occasional gentle line errors |
| Racer | 93–98% of profile; observation age 12 ticks (200 ms) | Confident drift lines and assertive but readable overtakes |
| Expert | 98–100% of profile; observation age 7 ticks (about 117 ms) | Efficient lines, fewer mistakes; same vehicle envelope |

The percentages scale the versioned CalibrationDriver speed profile, never physical capability or guaranteed lap times. Traffic observation ages apply at 60 Hz to discretionary tactics and derived occupancy/history; 5 Hz planning adds another 0–200 ms of phase latency. Current emergency road/contact safety is undelayed for both AI families. Record observed end-to-intent latency instead of claiming an exact 117 ms reaction. Roadstormer difficulty is an explicit training input decoded into the same planning envelope before intervention counting. Four seeded Classic personalities and the two learned styles change decisions, not available grip or speed.

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

Measure a separate stock-reference lap band before final art for each route. Initial authoring aims are Riviera 75–95 s, Alpine 85–100 s, Emerald 75–95 s, Canyon 80–100 s, Metro 80–100 s and Stormpeak 90–100 s. Kilometer figures above are provisional: shorten/reshape a graybox where measured pace cannot support a three-lap race around three to five minutes while retaining its road rhythm and landmarks. A 60-second lap is not required on every course, and `length / top_speed` is only a physical lower bound, not a target lap. Commit final lengths/bands with the reference traces.

Course widths generally range from 9 to 20 meters, with 8-meter short squeezes only after testing two-wide passage using actual car envelopes. Hairpin radii start around 28 meters and sweepers around 100 meters, subject to handling validation. Avoid blind mandatory braking immediately after a jump.

### Course acceptance contract

Each route contains at least two broad sweepers, two tight/medium turning sequences, one useful acceleration straight, two meaningful width transitions, a sustained climb/descent, and a crest or compression. Vary these patterns rather than repeating a generated template. Include three major scenic set pieces and smaller visual changes about every 5–10 seconds of travel.

Place braking warnings before the decision point; use chevrons, road edges, barriers, terrain shape, and contrast. A landmark cannot obscure the next important turn. Give difficult corners a forgiving exit and broad starts enough room for eight cars. Keep road-edge readability consistent across palettes, including reduced color perception.

Animated planes, helicopters, cable cars, trains, ships, turbines, waterfalls, flags, and simple geometric spectators are scenery. They are never unpredictable collision hazards. Trigger a spectacle from valid route progress with a cooldown so it is visible at racing speed and does not flicker or restart per camera. The simulation owns its shared state; cameras only render it. High scenery and road collision require sufficient clearance for the tallest car and jumps.

Course metadata distinguishes continuous race-clock animation, replayable zone events and tracking subjects. Any valid human zone entry may request a spectacle once per lap; coalesce entries within two seconds and queue at most one replay after completion/cooldown for trailing humans. A tracking helicopter follows the leading human currently in its zone. Do not tie every event to player 1 or permanently deny trailing players a trigger. All cameras see the same shared world event.

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

For level `L` in 0/1/2, Engine multiplies the stock acceleration curve by `1 + 0.03L` and top-speed cap by `1 + 0.015L`; Tires multiplies grip-state lateral damping (1/s) by `1 + 0.05L` and divides drift-exit blend seconds by the same factor; Chassis multiplies steering yaw-response gain by `1 + 0.04L` and impact speed-loss factor by `1 - 0.05L`. These are additive-to-stock formulas, not compounded per purchase. Tires do not alter drift-state lateral damping, entry threshold, or target slip range. Maximum speed/acceleration increases are 3%/6%. Check stock/max identity in the fixtures and show actual effects in the garage. Per-car surface-response modifiers, where used for gravel identity, are explicit in its handling resource and available equally to human/AI drivers.

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

Career availability gates in the table apply only to solo Career. All four Local Cup schedules are available immediately. At Local Cup start snapshot Stock or Garage mode: Stock offers all twelve loaners at 0/0/0 for humans/AI; Garage offers the host's currently unlocked pool and saved per-car loadouts to everyone, with AI assigned from that same pool. Freeze that snapshot, AI assignments and difficulty for the cup. Humans may select a different car/loadout only within the snapshot between rounds; no purchases or new host-profile changes alter a cup in progress. Career AI use the fixed upgrade presets below; Local Cup AI use its Stock/Garage snapshot instead.

Career AI upgrade levels (Engine/Tires/Chassis) are Coastal 0/0/0, Highlands 1/0/0, Skyline 1/1/1, and Storm Tour 2/1/1. Tune Rookie so stock starters can still complete and win through good driving; purchases provide a modest real benefit. Cup difficulty and AI family preference stay fixed until a new cup starts. Resolve tied points by wins, then final-event finish, then earlier event finishes from latest to earliest. If all competitive results are identical, display a shared cup place; participant ID orders the screen only. Podium/victory thresholds use the shared place where relevant.

Podium means final cup place ≤3; victory means final cup place 1, including the defined shared place. Wins in tie-breaking are individual race wins. Thunderbrick requires Storm Tour standings victory, not merely winning the final race. For cup tie-break comparison, DNF is worse than every valid finish and uses sentinel place 9; race DNF progress classification does not secretly become a finish or award points. A Local Cup race DNF leaves its human active for the next grid; explicit withdrawal from the cup converts that fixed slot to AI for subsequent events and retains its standings. Solo Career DNF/withdrawal leaves the current event pending as above.

Each completed standard three-lap solo Quick Race or Career race awards 800 base credits, plus 400/300/200/100 for first through fourth, plus up to 100 for varied controlled drifting. Scale the entire Quick Race reward by selected laps divided by three, rounding once after summing, so one-lap farming does not pay a full three-lap reward. Finish lower and still receive the scaled base; DNF/abandon grants none. Repeated completed events pay normally. Practice, Time Attack, Arcade Rush, and multiplayer exhibition grant no credits. A standard three-lap finish buys the first upgrade; about eight ordinary standard finishes buy all upgrades on a favorite car. Check the shortest legal event's credits per minute when tuning. Currency cannot buy cup points or bypass driving achievements. Paint schemes are free once the car unlocks, keeping the economy focused on upgrades.

Round the final scaled credit total to nearest integer with half values rounded up. Example: eighth with 50 style credits earns 850 for three laps, 283 for one and 1,417 for five. Economy reference assumes uniform finish positions 1–8 and 50 style credits: expected 975 per three-lap finish, so 7,200 / 975 ≈7.38 finishes. Base-only takes nine finishes; maximum 1,300 takes six. Report measured course/difficulty credits per minute rather than treating eight as a universal result.

Save cup progress after every completed race, resume at the next grid, and apply the race reward exactly once. A retry creates a new event instance. Target a first cup in roughly ten minutes and a complete collection within a few hours of replay and improvement on an accessible difficulty; verify the actual pacing in M6/M8 rather than padding it with grind.

## Presentation and audio

Favor clear car silhouettes, faceted geometry, saturated environments, limited materials, and a strong distant horizon. Use vertex colors and small generated texture atlases. Soft fog, simple lighting, contact shadows, wheel motion, restrained smoke, and sparks provide speed cues. Optional low-resolution 3D rendering and ordered dithering can evoke older hardware, while text stays crisp. No mandatory screen blur, camera shake, or flashing lightning.

Each player can choose chase, near chase, or hood camera. Chase cameras look into corners, avoid walls, and stabilize the horizon. Provide adjustable FOV, shake, and drift camera rotation; rear view is momentary. Do not add camera motion that hides road direction during a drift.

Rear view changes that player's existing camera direction, with no additional 3D viewport or picture-in-picture rendering. Global graphics/audio output settings belong to the room; camera motion/FOV and racing assists belong to each slot. Host controls menu text defaults, while each racing HUD respects its own requested scale within the tested layout limits.

Use original synthesizer compositions: six loopable race themes, one menu/garage theme, one results theme, and short transition/reward stingers. Engine families, tires, impacts, landings, UI, and environmental layers are generated from oscillators and noise. No sampled songs, real driver voices, or imitation celebrity announcer. Text and tones communicate start, checkpoints, finish, and rewards. Separate music, vehicle, environment, and UI volume controls; a mono output option and reduced-dynamic-range mix support varied setups.

## Local multiplayer interface

Attract/title → mode/profile → join → course/cup and difficulty → car/configuration → ready → race. A player presses a join button on an unclaimed device, then selects independently. Only the host controls shared event settings; all players can review them. Joining/leaving happens in the lobby, not halfway through a live race.

The initiating slot is host. In the lobby, transfer hosting explicitly to another active slot; if the host leaves, choose the lowest remaining slot after a visible notice. During a race any player may pause; a disconnect pauses globally and preserves ownership until reconnect/reassign/withdrawal. If the host withdraws, transfer menu authority to the lowest active human without changing the selected progression profile or fixed cup roster. If the last human leaves, end the event without exhibition rewards and preserve only previously committed career results.

One player fills the screen. Two players choose horizontal or vertical halves. Three players use a 2×2 grid with standings/minimap in the spare panel. Four use all quadrants. There is no fifth 3D camera. A global HUD layer draws each player's native-resolution UI over its 3D view.

Each panel shows position, lap, speed/units, time, drift cue, turn warning, and player marker; the shared map can simplify when space is limited. At 1080p, target at least 20-pixel essential labels and 32-pixel speed numerals within each quadrant, scalable to 150%. Menus target 24-pixel body text at 1080p. Test long labels and all scales for clipping. Use symbols/numbers as well as color.

Pause or device disconnect pauses everyone and names the affected slot. Offer reconnect, explicit reassignment or retirement of the current attempt; a Local Cup withdrawal may convert the slot to AI at the next event. Retain ownership until a choice is made; never silently attach a new controller. Focus loss pauses and releases held input. Reconnection requires fresh button states to avoid stuck acceleration.

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
