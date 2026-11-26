# Roadstorm Racer! benchmarks and acceptance contracts

These contracts turn the initial design targets into repeatable implementation checks. They are planned procedures, not completed experiments. M0 creates the versioned fixture/configuration files; M1 and M4 populate measured references. Change a threshold through a recorded decision before evaluating a candidate, never retrospectively to make that candidate pass.

## Reference driver and records

`CalibrationDriver` is a fixed, versioned, traffic-free path follower with no tactical planner, learning, difficulty scaling, or random mistakes. It uses the ordinary motor, stock car parameters, Standard drift/stability assists, an authored line, and a conservative speed profile calibrated against measured acceleration/braking/turning envelopes. It need not be globally optimal. Sharing low-level following code with AI is allowed; using an evaluated AI difficulty as its own reference is not.

The balanced starter is `car.balanced_starter`, currently displayed as Comet. Stable IDs survive name changes. For each car/course revision, record five clean flying laps and five clean standing-start single laps after warm-up. Retain median, min/max, individual times, sector splits, speed samples, car/loadout/assist hashes, line/controller version, engine/backend/handling/course revisions, platform, and seeds. Reject runs with contacts, reset, missed gates, invalid progress, or numerical errors. Reference records are regenerated when those dependencies change.

AI pace percentages scale desired speeds in that reference profile, not engine power or promised lap-time percentages. Record achieved lap distributions separately. Match an evaluated Roadstormer and Classic by car, loadout, difficulty, assists, initial scenario and reference revision. Human observations, when available, calibrate accessibility separately; never label a calibration bot a representative new player.

Stock medal sessions use the balanced starter, levels 0/0/0, and Standard assists. Initial Bronze/Silver/Gold thresholds are 1.25/1.12/1.05 times its measured flying-lap median; tune after captured play and record the final values. Other car/loadout/assist combinations retain separate records rather than silently competing for this standard medal. Arcade Rush uses standing-start references for the selected stock car and its sector times, as specified in the game design.

## Handling fixtures

Each fixture has immutable source geometry, initial pose/velocity, command schedule or controller revision, timing gates, surface, expected events, and a content hash. Start with these fixtures, then add regressions only for meaningful new concerns:

| Fixture | Geometry and comparison |
| --- | --- |
| Straight | 500 m asphalt; standing and 30 m/s rolling starts; acceleration, braking, top speed, reverse |
| Sweeper | 90-degree turn, 120 m centerline radius, 12 m width; 30 m/s entry; 50 m approach/exit |
| Hairpin | 180 degrees, 30 m radius; 18 m/s entry; 12 m width |
| Esses | Two opposite 60-degree arcs, 65 m radius; 25 m/s entry; transition and recovery |
| Gravel | Sweeper with an 80 m gravel sector and matching asphalt control run |
| Grounding | 12% climb/descent, bank ±12 degrees, crest/compression, short jump with a safe landing |
| Contact | Maximum-speed frontal/oblique walls, head-on/rear-end/side pairs, four-car squeeze, blocked reset, correction-limit saturation |
| Draft | Equal stock cars, 500 m straight, initial gaps 4/5/10/20/21 m and outside-cone controls |

Use all three starters at stock and maximum upgrades for handling comparisons. Scripted grip and drift controllers receive the same entry conditions; optimize each through a bounded documented tuning pass rather than deliberately slowing one. Obtain at least ten clean paired runs per relevant corner fixture. Keep the initial sweeper target within 5% in elapsed time; report hairpin/esses/gravel deltas and a mixed-loop target within 3%. These are tuning aims, with any intended course/style specialization documented. A single sweeper cannot establish whole-game parity.

Report the stock car spread as `(slowest median - fastest median) / fastest median`, initially at most 5% over an equal-weight mixed-course benchmark. Also report each course and handling difficulty. Do not interpret this as a required identical time on every course or impose tighter untested percentages that erase useful car identities.

Record surge-on/off exit speed at 0.5/1/2 seconds and elapsed time over the next 100 m. Record drafting-on/off closing distance and overtaking opportunity. Choose final magnitudes from these measurements and perceptual review; an untested calculation cannot establish whether either mechanic is satisfying.

### Numerical comparisons

On one pinned host/backend, replay a fixed 20-second, traffic-free command trace at 30/60/120 rendered FPS. Initial maximum endpoint differences: 0.10 m position, 0.10 m/s speed, 1 degree heading, and one physics tick for gate time. Exact discrete rules, rewards, and event counts must match. Cross-platform physics checks use invariants and documented tolerances, not byte-identical state hashes. Chaotic full-race trajectories are not subject to endpoint-equality tests.

The initial Python/GDScript actor parity gate is maximum absolute continuous-output error ≤1e-4 over at least 10,000 observations, plus identical decoded categorical actions outside a 1e-3 threshold boundary band. Include extremes, masks, invalid-input rejection, normalization, difficulty/style inputs and clipping. Threshold-boundary cases are reported separately and must not cause unsafe outputs.

## Racing and progress fixtures

Assert exact outcomes for normal/skipped/reversed/duplicate gates, finish crossings within a tick, displayed-time equality, exact internal ties, overpasses, wide runoff, jump landings, reset/depenetration across a gate, blocked anchors, immunity expiry, finished-car removal, both deadline policies, last-human departure, cup DNF versus withdrawal, and Arcade Rush gate/expiry boundaries.

Telemetry distinguishes accepted swept motion, positional correction, reset, and route-local projection. Only legal swept motion crosses gates. All ordered validation gates are required in Time Attack. Test shared settings/device ownership separately from profile rewards. Seeded grids and cup rosters must survive a save/restart exactly.

## AI metrics

A heavy contact is a car-car contact whose resolver impulse changes either car's road-plane velocity by at least 3 m/s, or causes a reset within two seconds. Coalesce repeated contacts for the same pair within 0.5 seconds. Report heavy contacts per participant-race and per 100 km, plus wall contacts separately. These are observable severity measures, not proof of intent or blame.

For a matched comparison, the learned rate must be ≤`Classic rate + max(0.1 * Classic rate, 0.05 heavy contacts per participant-race)`. Keep the absolute allowance visible rather than hiding a near-zero denominator. Report rates/counts and 95% intervals by whole independent race/scenario seed, difficulty, course and model; repeated windows within one race are not independent samples.

Completion means a legal finish before an evaluation timeout of `max(3 * reference event time, reference event time + 300 seconds)`, with production finish deadlines disabled. Target ≥99% aggregate AI entries and separately ≥99% for each of Surge and Switch on each course/difficulty, using that style's own starts. Persistent replacement by Classic counts as a learned failure, not a successful learned finish; ordinary bounded hazard correction is accounted separately. Show raw counts/uncertainty and every failed case. Three or more resets at one route interval across the 100-seed course/difficulty batch require diagnosis even if pooled reliability passes. Production deadline DNFs are separate.

Define clean pace ratio as `learned median lap time / matched Classic median lap time`. Initially require 0.90–1.10, report both faster and slower violations, and investigate traffic outcomes separately. Do not quietly tighten this to an unproved ±3% or interpret a faster bot as automatically interesting.

### Tactical comparison

Use at least six families: slower-lead straight pass, open two-lane corner entry, narrow-section patience, legal defended line/cutback, multi-car merge, and delayed/noisy human-like proxy behavior. Proxies make late brakes, hesitate, wander within legal bounds, or change lanes unexpectedly; they are original scripted test drivers, not evidence of real human interaction.

An opportunity window begins from a recorded scenario seed after a fixed two-second history warm-up and lasts up to three seconds or until the encounter ends. Compare Classic, cloning-only, Surge, and Switch from matched initial states and histories. Allow at most 0.10 m/0.10 m/s handover differences; use stored scenario snapshots if measured repeatability needs them. Exclude invalid windows with a documented reason before counting results; report excluded counts.

Label realized choices: follow versus attempt, left/right pass, commit within 0.6 seconds versus wait, and drift-entry timing category. A pass attempt requires at least one car length of legal relative progress or a sustained safe alongside position for 0.5 seconds. Lane jitter, idle delay, oscillation, or an unsafe proposal repaired by the guard cannot count as useful difference. Record completed clean passes, lost opportunities, pressure duration, contacts and pace as well as labels.

At final acceptance use at least 200 matched windows per pair across the six families, separately reporting Classic–Surge, Classic–Switch, and Surge–Switch. Target ≥25% differences in the preregistered semantic categories, with counts and uncertainty. A separate useful-maneuver/pace review must pass; maximizing disagreement alone is insufficient. Two independent reviewers inspect blinded captures and label style/readability, record agreement, and resolve disagreements with evidence. They may work sequentially. No mandatory human authorship or arbitrary questionnaire score is introduced.

Count emergency replacements and material road/collision corrections per proposed 5 Hz intent. One intent corrected on several 60 Hz ticks counts once, with tick-level exposure also reported. Material means safety-caused lane change >0.1 car width or absolute speed-target change `abs(safe - proposed) / max(proposed, 1 m/s) > 0.05`, in either direction. Decode difficulty before counting; ordinary scaling/path tracking are separate. Report magnitudes and raw-policy behavior so guard-dominated driving cannot pass unnoticed.

## Performance and compute evidence

Record hardware/OS/driver, engine/backend, renderer, player layout, 3D scale, VSync/frame cap, active views, content/model revisions, CPU/GPU time availability, presented frame intervals, physics tick time, memory, geometry submissions, voices, and rear-view state. Warm up one lap and capture at least three timed laps on each tested course/layout. Use four divergent camera locations at the busiest sections; four identical camera positions do not establish coverage.

Physics budget is CPU wall time per 60 Hz logical tick, including all eight cars, pair contacts, per-tick safety and scenery triggers: initial p99 ≤4 ms. Tactical observation/inference/decoding for both Roadstormers combined is initially ≤0.5 ms per 12-tick decision cycle, with per-call and worst-tick p99 also reported. Stagger their decisions at ticks 0 and 6 of that cycle. Do not report only an amortized per-frame average.

Triangle/draw totals sum submissions across active views, including repeated objects, with shadow work and overdraw recorded separately. Four-player 1080p means four 960×540 panels at 100% 3D scale, not four full 1080p targets. Neither fewer pixels nor a triangle count guarantees frame time.

Before long bot or training batches, measure logical seconds and decision steps per wall/core-second at 1/2/4 workers, peak memory and parity against real-time execution. Estimate T11's full 1,800-race matrix and publish worker/core-hour budgets, actual use, resumable shard IDs, and incomplete cases. Routine changes run affected fixtures plus a small rotating subset; full matrices remain milestone/release evidence. No fixed acceleration factor is assumed.

## Perceptual and production review

M0 records which available reviewers/tools can inspect motion, hear audio, operate a controller and assess a live build. An agent without audio input cannot approve music by reading a waveform. Every shipped theme and effect family needs an actual listening record by a capable agent or a human reviewer; absent coverage leaves that quality gate open. Human feedback/review is compatible with LLM-produced content and is not manual content authorship.

For each slice/content bundle, inspect: car identity at race distance; three recognizable landmarks; upcoming-turn visibility; road-edge contrast including common color-perception simulations; drift control/readability; essential cues under four-engine load; clicks/harshness/loop continuity; and mix comfort. Record captures, reviewer capability, observations and revisions. Offer owner play/listening checkpoints at M1/M3/M5/M8 without requiring the owner to implement anything. If no independent human play occurs, retain that explicit experience-validation limitation.

The second production proof at M7.1 must generate a different route/biome, contrasting cars, a contrasting theme, complete HUD/font proof and a four-player mix; change a source recipe and regenerate it. Record authoring, review and revision effort before projecting the cost of the remaining content. Technical checks and an attractive isolated screenshot do not close this proof.
