# Roadstorm Racer! independent plan review

Independently review the implementation plan for **Roadstorm Racer!**. You are running inside its Git repository and can read the files locally. Your task is to assess and report, not implement the game or rewrite the plan.

Complete the review yourself in this single chat. Do not spawn subagents, delegate work, create additional threads, or consult other agents/models. You may use filesystem, Git, and research tools directly. Form your assessment without reading other reviewers' reports.

## Review baseline

At the start, record `git rev-parse HEAD` once as your reviewed commit and read that exact snapshot, so another concurrent review commit cannot silently change your baseline. The ten initial reviews in `review/` assessed `206edf5eac85da73525dde79a36a4dbc61547e6a`; the current plan incorporates their reconciliation, summarized in `docs/REVIEW_RESPONSE.md`.

Read all of these files:

- `README.md`
- `PLAN.md`
- `docs/GAME_DESIGN.md`
- `docs/TECHNICAL_DESIGN.md`
- `docs/OPPONENT_AI.md`
- `docs/ASSET_PRODUCTION.md`
- `docs/BENCHMARKS.md`
- `LICENSE`

If working files differ from the baseline, inspect the baseline using `git show <baseline-commit>:<path>`. Do not check out the old commit, switch branches, reset files, or overwrite anyone's work. Other agents may be writing and committing reviews concurrently in this same checkout.

## Project intent

Roadstorm Racer! is an original arcade racing game inspired by the colorful, early polygonal experience of Sega Rally, Ridge Racer, Daytona, Cruis'n USA, Virtua Racing, and later OutRun titles. It must have its own vehicles, courses, graphics, music, and identity.

The important qualities are:

- Interesting roads with changing curvature, elevation, width, and rhythm.
- Memorable scenery: beaches, mountains, forests, tunnels, bridges, waterfalls, helicopters, aircraft, and wind turbines.
- Accessible, satisfying drifting that remains competitive with grip driving.
- Aggressive but fair opponents.
- Four-player local split-screen.
- Simple progression, meaningful upgrades, and appealing unlockable fictional cars.
- Colorful, flat-shaded or simply textured graphics with strong performance.

There are two opponent families: traditional **Classic Racers** and special **Roadstormers** using a modern learned approach. The proposed Roadstormers use small, offline-trained tactical policies with shared driving controllers and ordinary physical limits. Their purpose is more interesting, recognizable behavior.

Every new project-specific implementation and creative asset should be produced by LLM agents, including generation scripts, geometry, track definitions, UI, synthesized effects, original compositions, training tools, and tests. Existing engines and development tools are allowed. Humans may direct the work, playtest, and provide feedback.

The target is public-domain availability: Unlicense for original software and CC0 for original creative/model artifacts, with engine and dependency terms preserved separately.

The current proposal uses Godot and GDScript, six circuits, twelve cars, eight-car fields, five modes, and native desktop releases. Assess these implementation and scope choices critically while preserving the user-facing qualities above. Clearly label any recommendation that changes requested scope.

## Review focus

Determine whether an unfamiliar implementation agent could build the intended game from these documents without inventing essential rules.

Examine:

1. **Gameplay completeness and consistency:** handling, drift rewards, contacts, recovery, race results, cups, unlocks, upgrades, economy, multiplayer, accessibility, saves, and records.
2. **Architecture and performance:** vehicle movement, collision ownership, course generation, shared simulation, four-camera rendering, audio mixing, hardware targets, and platform exports.
3. **Roadstormer feasibility:** observations/actions, training data, imitation and reinforcement learning, simulator stepping, compute budget, local inference, safety constraints, generalization, fairness, and meaningful behavioral differences.
4. **LLM production practicality:** whether the proposed tools can produce varied, appealing courses, vehicles, typography, sound, and music, with sufficient review and regeneration processes.
5. **Licensing:** public-domain claims, contributor authority, asset/model provenance, fonts, samples, third-party tools, required notices, and external-asset exceptions.
6. **Milestones and verification:** whether major risks are tested early, dependencies are sensible, acceptance criteria are measurable, and testing cost is proportionate.

Challenge numerical targets and assumptions when warranted. Verify changing technical or licensing claims against primary sources when browsing is available. Distinguish confirmed problems from hypotheses requiring experiments. State verification limitations instead of inventing evidence.

Do not implement features, train models, generate game assets, install dependencies, run costly experiments, or modify planning documents. Propose necessary experiments in the report. Your only repository contribution should be your own review file.

## Report format

Begin with the review ID, reviewer/model if known (otherwise unknown), date, reviewed commit, files actually inspected, and verification limitations. Do not guess model metadata.

### Verdict

Choose **implementable as written**, **implementable after specific revisions**, or **major unresolved feasibility risks**. Briefly explain your confidence.

### Ranked findings

Present the most consequential findings first. For each finding include:

- Severity: blocker, major, or minor.
- File and section, with verified baseline line references where useful.
- The concrete problem, omission, or contradiction.
- A specific failure example or practical consequence.
- Your proposed correction or decision.
- Affected milestones and the verification needed.

Do not invent findings to fill a quota. Distinguish a documented design choice you disagree with from an actual contradiction or missing requirement.

### Feasibility experiments

Propose up to five bounded experiments. Specify inputs, cost limits, pass/fail criteria, and the decision each experiment resolves. These are proposals, not instructions to run them during this review.

### Cross-document consistency

List substantive contradictions or missing shared contracts that could cause implementation agents to build incompatible systems. Reference ranked findings rather than repeating them in full.

### Optional improvements

Separate optional improvements from necessary fixes. Explicitly identify recommendations that change scope.

### Strong decisions to preserve

Identify the plan's strongest choices and explain briefly why they should remain.

Focus on actionable findings. Avoid generic advice, a wholesale rewrite, or treating successful automated tests as proof that the game is fun.

## Submit in the shared checkout

You are authorized to create, commit, and push your review report. Use the existing shared checkout on `main`. **Do not create branches, worktrees, or additional clones.** If the checkout is unexpectedly on another branch, retain your report and explain the publication blocker rather than switching it.

1. Generate a fresh random UUID programmatically, for example with Python's `uuid.uuid4()`. Save the complete report as **`review/<uuid>.md`**, relative to the repository root. Create `review/` if needed. Never reuse an example ID or overwrite an existing file.
2. Modify only your own review file. Do not edit existing reviews, planning documents, this prompt, an index, or repository settings. Preserve unrelated working-tree and staged changes.
3. Stage your new file, then make a file-scoped commit with `--only`. The staging area is shared: a plain `git commit` could include another agent's staged work. Substitute your actual UUID in these commands:

   ```sh
   git add -- "review/<uuid>.md"
   git commit --only -m "Add plan review <uuid>" -- "review/<uuid>.md"
   ```

4. If Git reports a lock or another operation in progress, wait briefly with a small random delay and retry. Never remove another process's lock. If an operation's outcome is uncertain, check your file's history and contents before retrying, so you do not create duplicate commits. Do not run repository-wide formatters or other commands that change shared files.
5. Find your review's commit using its file history, such as `git log -1 --format=%H -- "review/<uuid>.md"`. Do not assume the current `HEAD` is still your commit; another reviewer may already have advanced it.
6. Publish with a normal **`git push origin main`**. A push may also publish other agents' already-committed reviews on the shared branch; that is expected. Another agent may publish your commit first, which also counts as success once remote inclusion is verified.
7. Retry brief push contention from the current shared branch. If rejection persists because of divergence, authentication, permissions, branch protection, or another unresolved condition, retain the report and any successful commit and state the exact blocker. **Do not pull, merge, rebase, reset, stash, amend commits, force-push, or switch branches** to resolve it. Never claim a push succeeded without checking the outcome.

Your final chat response should contain your review's repository-relative path, its commit hash if committed, a GitHub link if verified on the remote, and a one-sentence verdict. If publication is blocked, say so explicitly. The full review belongs in the Markdown file.
