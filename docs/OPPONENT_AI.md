# Roadstorm Racer! opponent AI

Version 1.0 has two opponent families. Classic Racers use authored racing and tactical rules. Roadstormers use an original learned tactical policy, trained offline, to choose more varied responses to nearby drivers. Both families use the same low-level driving controller, command format, vehicle resources, collisions, and race rules as human players.

Roadstormers are a required part of the updated launch scope. Their presence must produce observable tactical differences without relying on hidden performance advantages. If learning does not meet its evaluation gate, continue the training/design milestone rather than relabeling a scripted personality as learned AI.

## Mixed fields and player experience

Default eight-car fields contain two Roadstormers and enough Classic Racers to fill the remaining AI slots. With one human this means five Classic Racers and two Roadstormers; with four humans it means two of each. A clearly labeled Classic Only event setting is available for comparison and preference. Identify Roadstormers by a small roster/HUD badge and a readable introduction, not an intrusive effect.

Start with two recognizable learned styles. **Surge** seeks sustained pressure and commits to a pass when space opens. **Switch** is patient on entry and looks for a safe change of line or corner-exit cutback. Neither may bait contact, brake-check, swerve repeatedly, or intentionally ram. Names are working character labels. Their cars remain ordinary roster cars with ordinary upgrades.

These rivals respond to the recent race situation rather than becoming faster when behind. A rival may notice that an outside lane repeatedly closes, wait behind, and try the other side at the next useful opening. It does not read a player's future inputs, access private data, or change its own physical limits. No continuous on-device training or persistent player profiling is required; the learned weights are fixed for a released model revision.

## Architecture

Use a hierarchical controller so learning focuses on interesting race decisions rather than rediscovering basic steering.

1. The observation builder constructs normalized local features from the shared legal AI sensor contract.
2. A Classic planner or Storm policy produces a `TacticalIntent`: preferred lane/offset, target pace within the safe envelope, follow/pass commitment, and drift preference.
3. A common safety layer constrains the intent to the road, available passing room, reaction delay, contact rules, and physical capability.
4. The shared path follower converts the intent into steering, throttle, brake, handbrake, and reset requests.
5. The ordinary car motor executes commands. Telemetry records the policy proposal, safety corrections, and resulting behavior.

Run tactical decisions initially at 5 Hz and low-level following and immediate collision/road safety at every 60 Hz simulation tick. A held tactical intent never suspends hazard checks for 0.2 seconds. Interpolate intents and hold a short commitment window to prevent jitter and lane weaving. Observations include upcoming curvature/grade/width/surface, own speed/slip/ground state, nearby cars' relative position and velocity, legal lane occupancy, and a short recent history of pass attempts and contacts. Define and version the exact feature list before training. No global leaderboard position is needed to alter performance.

Use a small multilayer perceptron with approximately two 32-unit hidden layers and a bounded output head. Flatten a short history or include derived history features; do not begin with a large language model or a large recurrent network. Target fewer than 10,000 parameters and measure actual cost. A personality input or two independently trained checkpoints provides the two styles. A deterministic release inference mode selects actions from the current observations; seeded exploration is training-only unless a reviewed stochastic style option is added later.

Export numeric weights, normalization constants, schema, architecture, and checksums into a simple versioned format. Implement the small inference operation in original GDScript; compare its outputs against the training implementation over a held-out observation corpus. This avoids a runtime Python, PyTorch, ONNX, or cloud-service dependency. Runtime weights ship inside the game; playing never downloads a model.

The model file contains data, never executable expressions. Validate dimensions, finite values, magnitude limits, version, and hash before loading. Invalid output or missing weights triggers a visible diagnostic and safe Classic control for that participant so a race can continue. That fault-handling path does not satisfy the requirement to ship working Roadstormers.

## Training approach

All training/environment code, scenario definitions, reward rules, and evaluation tools are written by LLM agents. Train small policies from random initialization on project-owned simulation data. Do not import pretrained driving weights, scraped play videos, commercial racing traces, or third-party datasets.

Use imitation learning on demonstrations generated by the project's Classic drivers to initialize basic safe tactical choices. Then improve the tactical policy with reinforcement learning, initially PPO, using the actual Godot simulation as the environment. Pin Stable Baselines3, PyTorch, and Gymnasium as development-only tools. Their official [PPO documentation](https://stable-baselines3.readthedocs.io/en/master/modules/ppo.html) describes the algorithm/tool interface; the game's training environment and policy export remain original project work.

Python manages training; a headless Godot process exposes reset/step/observation/reward messages through a local-only batched bridge. One initial decision step advances exactly twelve 60 Hz physics ticks, matching 5 Hz tactics, then freezes logical simulation and reward clocks while waiting for the trainer. Do not allow the engine to free-run during Python optimization or IPC delay. Reset restores all participants, velocities, gates, timers, random state, policy history, contact/recovery state, queued events, and episode counters. Test exact tick advancement and reset completeness before training.

Keep the bridge disabled in shipped builds, bound message sizes, and bind only to the local machine. No network game service is involved. Follow the [Gymnasium environment contract](https://gymnasium.farama.org/api/env/) and test episode termination versus time-limit truncation. Run the framework's environment checker. If using vector environments, adapt SB3's distinct reset/terminal-observation semantics explicitly; see its [custom environment](https://stable-baselines3.readthedocs.io/en/master/guide/custom_env.html) and [vector environment](https://stable-baselines3.readthedocs.io/en/master/guide/vec_envs.html) guides.

Behavioral cloning requires original supervised-training code and an explicit shape-checked transfer into the matching PPO actor, with a newly initialized critic/optimizer. Export only the approved actor, preserving normalization, layer order, activations, action clipping/scaling, and personality/history inputs. The [SB3 export guide](https://stable-baselines3.readthedocs.io/en/master/guide/export.html) explains why deployment must preserve policy preprocessing and postprocessing rather than copying weights alone.

Prototype training throughput first. Benchmark 10,000–100,000 decision steps, then estimate and cap both step count and wall time for a learning pilot from measured throughput. Stop at whichever cap is reached first and review the learning curve before increasing the budget. Run independent headless environments and batch simulation ticks per bridge message. GPU training is optional for a model this small; environment stepping may dominate. If throughput is poor, optimize batching and scenario length before increasing model size or buying compute. Do not require a paid training service for a normal game build.

Curriculum order: follow safely → pass a slower car on a wide straight → two-lane corner approach → narrow-section patience → defensive but legal placement → multi-car traffic → mixed surfaces/crests → complete races. Start with one trainable car per environment and frozen Classic/prior-checkpoint opponents, keeping the PPO problem single-agent. Rotate the trainable slot and opponent mix between episodes; simultaneous multi-agent learning is outside the baseline. Randomize stock cars, legal upgrade bands, initial gaps, opponent personalities, and course conditions already present in the game.

Reward valid forward progress and successful clean passes; penalize collisions, excessive risk, unnecessary resets, off-road travel, oscillation, and blocking violations. Use completion/position only as bounded race objectives. Do not reward raw speed, drift duration, or contact in ways that permit gate-skipping, wall riding, donuts, or bullying. Give each style modestly different risk/patience objectives while preserving the same hard safety rules. Log reward components to detect exploits.

Keep training, validation, and final evaluation seeds/scenarios separate. Use synthetic training segments plus Riviera initially. Reserve complete unfamiliar layouts for generalization checks, then validate every launch course without tuning on the final test seeds. A simulator/handling revision invalidates affected training/evaluation results and requires retraining or demonstrated compatibility.

## Model and data rights

Treat original weights, scenario recipes, and authored datasets as first-party material: release software/training code under the Unlicense and original model/data artifacts under CC0 to the extent the project holds applicable rights. Keep their complete source and training records. Training-library licenses remain separate and are listed in the development dependency inventory; do not copy their source or notices into a new public-domain claim.

Record training-library versions, hyperparameters, observation/action schemas, reward revision, simulator/content revisions, seed list, hardware, step count, elapsed time, dataset/checkpoint hashes, authoring records, and evaluation results in a model card. Exact retraining results are not guaranteed across hardware/toolchain versions; ship the approved checkpoint and document statistical reproducibility rather than promising bit-identical learned weights. See [PyTorch reproducibility guidance](https://docs.pytorch.org/docs/stable/notes/randomness.html).

## Implementation and acceptance

Add **M4B learned rivals** after traditional racing M4 and before the vertical slice M5. Deliver the bridge, training pilot, original demonstrations, policy trainer/exporter, GDScript inference, safety guard, two styles, model cards, and evaluation tools. The slice needs a working small learned rival on Riviera, not a placeholder. During M7, retrain/evaluate for the full roster and six courses; M8 closes the full learned-AI gate.

| Gate | Required evidence |
| --- | --- |
| Correct inference | Training/exported GDScript outputs agree within a declared numeric tolerance on at least 10,000 diverse observations |
| Safe fallback | Invalid/missing weights, NaNs, and out-of-range inference cannot crash a release race or bypass limits; bridge failures terminate/restart a training worker and are logged, never becoming a release runtime dependency |
| Fairness | Same motor/configuration envelope; no privileged grip/speed, position-based catch-up, repeated blocking or progress shortcut |
| Completion | At least 99% AI-entry completion in held-out evaluation races with finish deadlines disabled; recurrent segment failures block acceptance; separately report deadline DNFs against reference player pace |
| Contact behavior | Heavy-contact rate no worse than the matched Classic baseline by more than 10%, with a small absolute allowance defined before evaluation when the baseline is near zero |
| Useful pace | Clean mixed-course lap pace within approximately 10% of the matched Classic driver, without achieving it by violating safety |
| Behavioral distinction | Report Classic–Surge, Classic–Switch, and Surge–Switch separately on at least 200 matched opportunity windows per pair across six scenario families; target ≥25% meaningful differences for each pair in pass/follow, passing side, commit/wait, or drift entry; raw numeric differences do not count |
| Style and counterplay | Independent review identifies pressure versus patient-cutback behavior across multiple races; choices are readable and neither style wins through repeated contact |
| Runtime cost | Both learned rivals together fit the provisional 0.5 ms tactical-update budget, including observation assembly; immediate per-tick safety is measured separately inside the shared 4 ms simulation budget |
| Safety interventions | Emergency replacements <1% and material road/collision corrections <5% of final held-out proposals; separately report category, magnitude, and opportunity-window results so safe raw policy decisions explain the observed behavior |
| Reproducibility | A clean checkout loads the shipped checkpoint without training; another agent can run the documented evaluation and a small retraining experiment |

The behavioral-difference threshold detects an inert copy of the baseline; it does not prove interesting play by itself. Measure pass success, following duration, lane changes, blocked opportunities, contacts, resets, safety interventions, finish rates, and lap times on the same scenarios and car settings. Inspect full clips rather than selecting only a successful pass. Publish comparison results and limitations with the model card.

Predefine intervention categories before evaluation. Ordinary numeric action scaling is not a safety intervention. Changing a proposed lane by more than 0.1 car width or pace by more than 5% for road/collision safety counts as a material correction; emergency substitution/reset is a separate category. Normal low-level path tracking is reported separately from overriding a tactical decision. Include deliberate unsafe-proposal tests and correction magnitudes so constant guard repair cannot masquerade as learned competence. Define the six or more comparison scenario families and category thresholds before seeing the final results.

Use at least three training seeds and select a checkpoint through validation results before final held-out evaluation. Preserve one whole launch course plus unseen challenge layouts outside training, and test every course at release. This follows the separation of training and evaluation emphasized by [SB3's reinforcement learning guidance](https://stable-baselines3.readthedocs.io/en/master/guide/rl_tips.html). Record the selected checkpoint even when another seed performs differently; a cherry-picked clip is not the evaluation set.

A live cloud LLM opponent can be explored after release if desired. It is outside this implementation because the launch design requires offline play, predictable latency, a small runtime, and reproducible evaluation. The learned tactical policy provides a concrete modern-AI path within those requirements.
