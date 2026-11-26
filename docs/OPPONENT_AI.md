# Roadstorm Racer! opponent AI

Version 1.0 has two opponent families. Classic Racers use authored racing and tactical rules. Roadstormers use an original learned tactical policy, trained offline, to choose more varied responses to nearby drivers. Both families use the same low-level driving controller, command format, vehicle resources, collisions, and race rules as human players.

Roadstormers are required launch scope. Their presence must produce observable tactical differences without hidden performance advantages. A failed learning experiment stops at its resource cap and produces a diagnosis/next-experiment decision; it does not silently turn Roadstormers into scripts or remove them from launch. Independent content preparation may continue while the relevant AI gate remains open.

## Mixed fields and player experience

Default eight-car fields contain two Roadstormers and enough Classic Racers to fill the remaining AI slots. With one human this means five Classic Racers and two Roadstormers; with four humans it means two of each. A clearly labeled Classic Only event setting is available for comparison and preference. Identify Roadstormers by a small roster/HUD badge and a readable introduction, not an intrusive effect.

Humans-only Quick Race is a separate two-to-four-human exhibition with no AI of either family. It never inserts Roadstormers to satisfy the standard-field arithmetic.

Start with two recognizable learned styles. **Surge** seeks sustained pressure and commits to a pass when space opens. **Switch** is patient on entry and looks for a safe change of line or corner-exit cutback. Neither may bait contact, brake-check, swerve repeatedly, or intentionally ram. Names are working character labels. Their cars remain ordinary roster cars with ordinary upgrades.

These rivals respond to the recent race situation rather than becoming faster when behind. A rival may notice that an outside lane repeatedly closes, wait behind, and try the other side at the next useful opening. It does not read a player's future inputs, access private data, or change its own physical limits. No continuous on-device training or persistent player profiling is required; the learned weights are fixed for a released model revision.

Cosmetic bumper/trim damage and visual debris do not enter AI observations, obstacle queries, reward functions or car parameters. Training may disable their presentation entirely; impact penalties still use the original committed physical contact once. Neither family reacts to harmless detached pieces as if they blocked the road.

## Architecture

Use a hierarchical controller so learning focuses on interesting race decisions rather than rediscovering basic steering.

1. The observation builder constructs normalized local features from the shared legal AI sensor contract.
2. A Classic planner or Roadstormer policy produces a `TacticalIntent`: preferred lane/offset, target pace within the safe envelope, follow/pass commitment, and drift preference.
3. A common safety layer constrains the intent to the road, available passing room, contact rules, and physical capability. Discretionary traffic observations have the difficulty-specific age; immediate hazard safety does not wait for that delay.
4. The shared path follower converts the intent into steering, throttle, brake, handbrake, and reset requests.
5. The ordinary car motor executes commands. Telemetry records the policy proposal, safety corrections, and resulting behavior.

Run tactical decisions initially at 5 Hz and low-level following and immediate collision/road safety at every 60 Hz simulation tick. A held tactical intent never suspends hazard checks for 0.2 seconds. Interpolate intents and hold a short commitment window to prevent jitter and lane weaving. Observations include upcoming curvature/grade/width/surface, own speed/slip/ground state, nearby cars' relative position and velocity, legal lane occupancy, and a short recent history of pass attempts and contacts. Define and version the exact feature list before training. No global leaderboard position is needed to alter performance.

Initial actor is one style-conditioned MLP: 64 observations → 32 tanh → 32 tanh → four linear action means, 3,268 parameters. Clip/decode the means using the shared action contract. Train in float32 and compare original GDScript inference numerically. Target fewer than 10,000 actor parameters if an experiment justifies increasing capacity; critic/optimizer parameters are development-only. Personality and difficulty are explicit inputs. Deterministic release inference uses the action mean; stochastic exploration is training-only. No large language model or recurrent network is needed in the runtime.

### Shared schema version 1

The integrator defines the schema in M0/M2; **Classic AI must use it from M4.2 onward**, before demonstrations exist. M4B ratifies a versioned training configuration rather than inventing a second interface. Humans supply `DriverCommand` directly; the AI families share the observation/intent/follower hierarchy.

All features are finite float32 in a fixed 64-element order, with documented clipping to [-1,1] (booleans in 0/1). Route frame is forward tangent, right lateral, up road normal; positive lane offset is right. Preserve feature timestamps and reset history to zero/masked defaults. Neighbor traffic and derived occupancy/history use the same delayed snapshot, preventing a current-position leak around the reaction setting. Ego/road data and the emergency guard remain current.

| Indices | Ordered feature group and initial normalization |
| --- | --- |
| 0–11 | Ego: speed/top-speed, lateral speed/20 m/s, heading error/pi, slip/pi, lane offset/usable half-width, yaw rate/pi rad/s, grounded, drift active, immunity, surge cooldown/2 s, surface grip/2, valid-progress flag |
| 12–26 | At 20/50/100 m ahead, five each: signed curvature ×100 m, grade/0.12, road width/20 m, bank/0.21 rad, surface grip/2 |
| 27–50 | Four neighbors × six: signed route gap/70 m, lateral gap/10 m, relative forward speed/40 m/s, relative lateral speed/20 m/s, width/3 m, presence mask; absent slots zero |
| 51–56 | Own executed normalized lane targets at 0.2/0.6 s ago (each divided by its then-usable half-width), previous pass side (-1/0/1), seconds since last attempt/3, valid forward distance over last 3 s/195 m, recent contact flag |
| 57–59 | Rookie/Racer/Expert one-hot |
| 60–61 | Surge/Switch style one-hot |
| 62–63 | Delayed left/right corridor occupancy fractions at the planned encounter, each clipped 0–1 |

Neighbor candidates are within 70 m ahead or 35 m behind on the valid route neighborhood, sorted by absolute gap then stable participant ID. Do not select a nearby unrelated overpass. Clipping/padding rules and every normalization coefficient ship with the model; unknown schema, zero usable width or nonfinite input produces safe diagnostic fallback.

The recent contact flag covers the prior two seconds ending at the delayed traffic timestamp, as do traffic-derived pass/occupancy history. Own executed lane targets retain their recorded normalized values rather than raw meters clipped to ±1. Current ego controls are available immediately; future/current traffic does not leak through history.

Classic-only observations use style inputs 0/0; their rule personality remains an explicit configuration. Demonstration generation deliberately supplies the target Surge/Switch style label when collecting matching teacher behavior. Do not infer or invent labels after inspecting final held-out results.

The action is one continuous Box vector of four values in [-1,1], supported by the [PPO action-space interface](https://stable-baselines3.readthedocs.io/en/master/modules/ppo.html). It is not a Dict/mixed action space:

| Action | Decoding into TacticalIntent |
| --- | --- |
| 0 | Lateral target times `(road_width - car_width)/2 - 0.5 m`, bounded to the legal corridor |
| 1 | Map `(a+1)/2` into the selected difficulty's desired speed-profile interval, before safety counting |
| 2 | Below -1/3 follow, -1/3 through +1/3 wait/hold, above +1/3 commit to a legal pass; minimum commitment 0.4 s, interrupted by hazards |
| 3 | Drift preference above +0.25, grip below -0.25, retain preference between thresholds; follower still enforces legal entry conditions |

Classic planners emit this same intent, including continuous proposed values and decoded/executed labels. Record the proposed intent, ordinary difficulty decoding, safety changes and final commands separately. Difficulty uses 18/12/7-tick traffic observation ages plus the documented 5 Hz sampling latency. Train/evaluate each difficulty rather than post-hoc slowing an unconditioned policy.

Export numeric weights, normalization constants, schema, architecture, and checksums into a simple versioned format. Implement the small inference operation in original GDScript; compare its outputs against the training implementation over a held-out observation corpus. This avoids a runtime Python, PyTorch, ONNX, or cloud-service dependency. Runtime weights ship inside the game; playing never downloads a model.

The model file contains data, never executable expressions. Validate dimensions, finite values, magnitude limits, version, and hash before loading. Invalid output or missing weights triggers a visible diagnostic and safe Classic control for that participant so a race can continue. That fault-handling path does not satisfy the requirement to ship working Roadstormers.

## Training approach

All training/environment code, scenario definitions, reward rules, and evaluation tools are written by LLM agents. Initialize weights randomly, then train through original behavioral cloning and PPO on project-owned simulation data. Those are successive stages, not contradictory initialization rules. Do not import external pretrained driving weights, scraped play videos, commercial racing traces, or third-party datasets.

Use imitation learning on demonstrations generated by the project's Classic drivers to initialize basic safe tactical choices. Then improve the tactical policy with reinforcement learning, initially PPO, using the actual Godot simulation as the environment. Pin Stable Baselines3, PyTorch, and Gymnasium as development-only tools. Their official [PPO documentation](https://stable-baselines3.readthedocs.io/en/master/modules/ppo.html) describes the algorithm/tool interface; the game's training environment and policy export remain original project work.

Python manages training; a headless Godot process exposes reset/step/observation/reward messages through a local-only batched bridge. A nonterminal decision step advances twelve 60 Hz ticks, matching 5 Hz tactics; terminal/truncated steps stop at the first ending tick and return actual elapsed ticks plus terminal observation. Logical simulation/reward clocks then freeze while waiting for the trainer. Do not free-run during optimization or IPC delay. Reset restores all participants, velocities, gates, timers, RNG, history, contact/recovery, queued events and counters. Test full/early-ending tick budgets and reset completeness before training.

Keep the bridge disabled in shipped builds, bound message sizes, and bind only to the local machine. No network game service is involved. Follow the [Gymnasium environment contract](https://gymnasium.farama.org/api/env/) and test episode termination versus time-limit truncation. Run the framework's environment checker. If using vector environments, adapt SB3's distinct reset/terminal-observation semantics explicitly; see its [custom environment](https://stable-baselines3.readthedocs.io/en/master/guide/custom_env.html) and [vector environment](https://stable-baselines3.readthedocs.io/en/master/guide/vec_envs.html) guides.

Behavioral cloning requires original supervised-training code and an explicit shape-checked transfer into the matching PPO actor, with a newly initialized critic/optimizer. Export only the approved actor, preserving normalization, layer order, activations, action clipping/scaling, and personality/history inputs. The [SB3 export guide](https://stable-baselines3.readthedocs.io/en/master/guide/export.html) explains why deployment must preserve policy preprocessing and postprocessing rather than copying weights alone.

Prototype training throughput first. Benchmark 10,000–100,000 decision steps, then estimate and cap both step count and wall time for a learning pilot from measured throughput. Stop at whichever cap is reached first and review the learning curve before increasing the budget. Run independent headless environments and batch simulation ticks per bridge message. GPU training is optional for a model this small; environment stepping may dominate. If throughput is poor, optimize batching and scenario length before increasing model size or buying compute. Do not require a paid training service for a normal game build.

Curriculum order: follow safely → pass a slower car on a wide straight → two-lane corner approach → narrow-section patience → defensive but legal placement → multi-car traffic → mixed surfaces/crests → complete races. Start with one trainable car per environment and frozen Classic/prior-checkpoint opponents, keeping the PPO problem single-agent. Rotate the trainable slot and opponent mix between episodes; simultaneous multi-agent learning is outside the baseline. Randomize stock cars, legal upgrade bands, initial gaps, opponent personalities, and course conditions already present in the game.

Reward valid forward progress and successful clean passes; penalize collisions, excessive risk, unnecessary resets, off-road travel, oscillation, and blocking violations. Use completion/position only as bounded race objectives. Do not reward raw speed, drift duration, or contact in ways that permit gate-skipping, wall riding, donuts, or bullying. Give each style modestly different risk/patience objectives while preserving the same hard safety rules. Log reward components to detect exploits.

Before training, commit a learning-contract configuration with feature/action/reward versions, at least 20,000 legal demonstration transitions, balanced scenario/difficulty/style coverage, episode seeds, normalization, optimizer/hyperparameters and terminal/truncation rules. Classic-derived demonstrations include varied legal lines and patience settings, not a single identical trajectory. Evaluate cloning-only separately so PPO must demonstrate useful learning beyond its teacher.

Initial per-decision reward recipe is valid signed progress/10 m (clipped to [-1,1.5]), +0.5 per newly completed clean pass, -5 per heavy contact, -1 per lighter contact, -0.2 per off-road decision, -3 per reset and -0.05 per unnecessary lane reversal within 0.5 s; terminal valid finish gives +2. Each pair/lap pass pays once, preventing repeated overtake farming. Surge may add at most +0.5 for a sustained legal pressure-to-pass maneuver; Switch at most +0.5 for a safe delayed cutback after a defended entry. These bonuses require realized progress, not merely outputting a label or waiting. Exact detectors are preregistered with [BENCHMARKS.md](BENCHMARKS.md#tactical-comparison); coefficients are initial experiment settings, not proven optimal values. Revisions create a new reward version before a run.

Terminate an episode on the trainable participant's valid finish or deliberate withdrawal; truncate at the benchmark timeout. Ordinary contact/off-road/reset behavior continues with its penalties so the policy learns recovery. Invalid numerical state or worker failure aborts the episode as a recorded environment error rather than a successful terminal training sample. Stop accumulation at the first terminal tick even if fewer than twelve ticks were consumed. Store the actual elapsed ticks and terminal observation; use them consistently for reward/discount interpretation and evaluation.

Keep training, validation, and final evaluation seeds/scenarios separate. Use synthetic training segments plus Riviera initially. Reserve complete unfamiliar layouts for generalization checks, then validate every launch course without tuning on the final test seeds. A simulator/handling revision invalidates affected training/evaluation results and requires retraining or demonstrated compatibility.

### Experiment budgets and handling freeze

M0/M1 proves tick/reset mechanics. Late M4 starts a bridge/throughput/inference spike as soon as a stable Classic intent teacher exists, in parallel with slice preparation. M4B gets at most three pilot iterations, each ≤500,000 decision steps or eight local-machine hours, whichever comes first, with total ≤24 machine-hours/96 CPU-core-hours. Use at most four workers and record memory/step throughput; smaller measured caps are encouraged. These are ceilings, not success/time estimates and not permission to rent paid compute.

Before production training, preregister the actual machine, worker/thread/memory limits and three-seed matrix from measured throughput. Initial final-training allocation is ≤48 machine-hours/192 core-hours across the three seeds, with per-seed step/wall caps; one diagnosed revision round may use the same allocation. Record cumulative consumption including failed runs. Additional allocation requires a concrete decision with learning curves, failure cases and alternatives; do not launch an unbounded loop. A failure may motivate new demonstrations, reward/curriculum/action changes, or another small learning algorithm. It cannot silently remove Roadstormers or claim a scripted fallback is the feature.

Freeze starter motor/car/surface behavior before accepted M4B slice training; finishing their visual models in M5 does not imply retuning physics. Freeze all launch handling/course candidates after M8.1 balancing and before M8.7 final training/evaluation. M7 training is provisional preparation. Later relevant changes rerun the approved frozen checkpoint's schema/parity/completion/contact/pace/intervention checks; retrain only where compatibility is not demonstrated. Final evidence must match the exact shipped revisions. Holdout data used to tune a model becomes validation data and needs a fresh final holdout.

## Model and data rights

Treat original weights, scenario recipes, and authored datasets as first-party material: release software/training code under the Unlicense and original model/data artifacts under CC0 to the extent the project holds applicable rights. Keep their complete source and training records. Training-library licenses remain separate and are listed in the development dependency inventory; do not copy their source or notices into a new public-domain claim.

Record training-library versions, hyperparameters, observation/action schemas, reward revision, simulator/content revisions, seed list, hardware, step count, elapsed time, dataset/checkpoint hashes, authoring records, and evaluation results in a model card. Exact retraining results are not guaranteed across hardware/toolchain versions; ship the approved checkpoint and document statistical reproducibility rather than promising bit-identical learned weights. See [PyTorch reproducibility guidance](https://docs.pytorch.org/docs/stable/notes/randomness.html).

## Implementation and acceptance

Start the minimal feasibility spike during late M4; finish **M4B learned rivals** alongside independent M5 art/audio/menu preparation. Deliver the bridge, bounded pilot, demonstrations, trainer/exporter, GDScript inference, safety guard, two styles, model cards and evaluation tools. Integrated M5 acceptance still requires both working learned styles on Riviera, not placeholders. M7 prepares expanded data/models; M8.1 freezes the balanced candidate before M8.7 final training/compatibility and held-out evaluation.

| Gate | Required evidence |
| --- | --- |
| Correct inference | BENCHMARKS numerical contract: ≤1e-4 max absolute actor-output error over ≥10,000 observations and decoded-action agreement outside the declared threshold boundary band |
| Safe fallback | Invalid/missing weights, NaNs, and out-of-range inference cannot crash a release race or bypass limits; bridge failures terminate/restart a training worker and are logged, never becoming a release runtime dependency |
| Fairness | Same motor/configuration envelope; no privileged grip/speed, position-based catch-up, repeated blocking or progress shortcut |
| Completion | At least 99% separately for Surge and Switch per course/difficulty, each using its own starts; retain aggregate T11 too. Production finish deadlines are disabled; persistent Classic-fallback episodes count as learned failures. Recurrent segment failures block acceptance. |
| Contact behavior | Heavy contacts are defined/coalesced in BENCHMARKS; rate ≤Classic + max(10% of Classic, 0.05 per participant-race), with raw counts and uncertainty |
| Useful pace | Clean-lap-time ratio learned/Classic in 0.90–1.10 at matched car/loadout/difficulty/assists; report traffic results separately |
| Behavioral distinction | Report Classic–Surge, Classic–Switch, and Surge–Switch separately on at least 200 matched opportunity windows per pair across six scenario families; target ≥25% meaningful differences for each pair in pass/follow, passing side, commit/wait, or drift entry; raw numeric differences do not count |
| Style and counterplay | Independent review identifies pressure versus patient-cutback behavior across multiple races; choices are readable and neither style wins through repeated contact |
| Runtime cost | Both learned rivals together fit the provisional 0.5 ms tactical-update budget, including observation assembly; immediate per-tick safety is measured separately inside the shared 4 ms simulation budget |
| Safety interventions | Emergency replacements <1% and material road/collision corrections <5% of final held-out proposals; separately report category, magnitude, and opportunity-window results so safe raw policy decisions explain the observed behavior |
| Reproducibility | A clean checkout loads the shipped checkpoint without training; another agent can run the documented evaluation and a small retraining experiment |

The behavioral-difference threshold detects an inert copy of the baseline; it does not prove interesting play by itself. Measure pass success, following duration, lane changes, blocked opportunities, contacts, resets, safety interventions, finish rates, and lap times on the same scenarios and car settings. Inspect full clips rather than selecting only a successful pass. Publish comparison results and limitations with the model card.

[BENCHMARKS.md](BENCHMARKS.md#ai-metrics) defines heavy contacts, matching tolerances, six challenge families including noisy human-like proxies, realized-maneuver labels, denominators, independent style review and confidence reporting. The provisional 25% difference is a safeguard against a cloned baseline, not permission to create pointless hesitation or lane noise. Report cloning-only versus PPO improvement, family-level completion and guard intervention exposure. Pilot labels/metrics on about 50 windows before freezing the ≥200-window final set.

Predefine intervention categories before evaluation. Ordinary numeric scaling is not an intervention. A safety-caused lane change >0.1 car width or absolute speed-target change `abs(safe - proposed) / max(proposed, 1 m/s) > 0.05` counts as material, whether speeding up or slowing down; emergency substitution/reset is separate. Report ordinary path tracking separately. Test deliberately unsafe proposals and report correction magnitudes so constant repair cannot masquerade as learned competence. Define scenario families/thresholds before final results.

Use at least three training seeds and select a checkpoint through validation results before final held-out evaluation. Preserve one whole launch course plus unseen challenge layouts outside training, and test every course at release. This follows the separation of training and evaluation emphasized by [SB3's reinforcement learning guidance](https://stable-baselines3.readthedocs.io/en/master/guide/rl_tips.html). Record the selected checkpoint even when another seed performs differently; a cherry-picked clip is not the evaluation set.

A live cloud LLM opponent can be explored after release if desired. It is outside this implementation because the launch design requires offline play, predictable latency, a small runtime, and reproducible evaluation. The learned tactical policy provides a concrete modern-AI path within those requirements.
