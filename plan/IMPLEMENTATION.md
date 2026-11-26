# Roadstorm Racer! end-to-end implementation

Implement the complete Roadstorm Racer! plan, from the current checkout through the finished, verified desktop game and release artifacts. Start by pulling safely. Continue through all milestones without stopping to ask whether to proceed. Your primary role is to coordinate implementation subagents; they should perform almost all coding, content generation, testing and fixes.

This is an execution prompt. Reading it in an implementation session means begin the work, not propose another plan or merely describe what could be built. Respect actual tool/account limits and report genuine external blockers honestly; never manufacture evidence or silently reduce scope to claim completion.

## Read and establish the run

1. Confirm the repository root, current branch, working/staged changes and any active coordinator/workers. Preserve existing work. Use the shared `main` checkout; do not create branches, worktrees or additional clones. If another branch or detached HEAD is checked out, do not pull main into it or switch shared state silently; record the actual checkout blocker before any implementation writers start.
2. Verify `work/agents/` is ignored with `git check-ignore` before writing prompts/sessions/logs; this repository includes a `/work/` ignore rule. Preserve existing ignore rules if repairs are necessary. Atomically acquire one `work/agents/coordinator.lock` directory before Git mutations or dispatch, recording a run UUID, actual supervising session/process identity and checkpoints. Do not infer a lock is abandoned merely from age. Resume/handoff the known owner explicitly or preserve an active/uncertain lock rather than launch a second coordinator.
3. Once holding the lease on `main`, pull with `git pull --ff-only origin main` before starting workers when safe. Do not stash, reset, rebase, merge or overwrite changes to make it succeed. If real divergence/ownership conflicts prevent synchronization, record them and complete independent work that remains possible; do not pretend the pull succeeded.
4. Read [PLAN.md](../PLAN.md), [GAME_DESIGN.md](../docs/GAME_DESIGN.md), [TECHNICAL_DESIGN.md](../docs/TECHNICAL_DESIGN.md), [OPPONENT_AI.md](../docs/OPPONENT_AI.md), [ASSET_PRODUCTION.md](../docs/ASSET_PRODUCTION.md), [BENCHMARKS.md](../docs/BENCHMARKS.md), [REVIEW_RESPONSE.md](../docs/REVIEW_RESPONSE.md), [README.md](../README.md), the license, and applicable repository instructions. Treat initial `review/` reports as historical evidence. [REVIEW_PROMPT.md](../REVIEW_PROMPT.md) is for independent plan reviewers; its review-only assignment does not replace this implementation assignment.
5. Inspect what is implemented and verified. Resume from evidence rather than assuming M0 or trusting checkboxes. Establish exclusive ownership, local tracking and durable `docs/STATUS.md`; checkpoint completed work and exact next dispatch for context resets/handoffs. Do not restart completed work or duplicate recorded running workers.
6. Discover installed model tools, exact IDs, authentication readiness and available quota. Record routes/limits without credentials, then dispatch the smallest dependency-ready implementation jobs immediately.

The full product scope remains required: six original courses, twelve fictional cars, five modes, four-player local split-screen, forgiving competitive drifting, upgrades/unlocks, fair Classic Racers, two learned Roadstormer styles, original art/music/effects, cosmetic detachable bumpers/debris, public-domain first-party material and separately preserved dependency notices. A tutorial, graybox, vertical slice or scripted substitute for a learned rival is an intermediate result.

## Coordinator and worker responsibilities

Spend your effort on decomposition, assignment, monitoring, interface decisions, integration, evidence, review and continuity. Delegate substantial code, asset tools, compositions, course/car data, tests and repairs. Do not quietly become the main implementer when a worker struggles; tighten the task, supply evidence, choose another permitted worker, or split it into smaller jobs. Small coordination/status edits and Git/integration commands are appropriate coordinator work.

Start with two or three implementation workers; normally keep at most four child model processes active, including reviewers. Adjust only from measured resource/quota constraints. Do not leave an available useful slot idle merely to narrate a plan. Pause model-heavy work when training/render tests need the same machine resources.

Workers and reviewers must not spawn further agents or create chats, branches, worktrees or clones. The coordinator alone owns the worker tree and task registry. Every job has:

- Unique ID, explicit role, actual provider/model/session/process identity and available capabilities.
- Current input revision, relevant specifications and interface/schema versions.
- Exclusive file ownership, including newly generated/renamed/deleted files and directories.
- A bounded deliverable, acceptance checks, resource limits and dependency assumptions.
- Local task/session/log paths, last activity, status and a route for reporting blockers.

For each worker task, explicitly say: implement the requested result now; stay inside owned paths; preserve other work; do not spawn agents, mutate Git or change the product scope; run relevant checks; report changed files, commands/results, artifact paths, limitations and remaining defects. A worker's summary is a claim to verify, not proof of completion.

Keep `project.godot`, central scenes, shared schemas, canonical bakes and integration wiring under one assigned integrator at a time. Do not let parallel editors/importers rewrite shared generated resources. Resolve interface changes before dependent workers implement against them. Stop or reassign workers that overlap ownership, repeatedly fail, or make no measurable progress; retain their useful artifacts.

## Model routing

Use **Step 5 Preview and Longcat 2.5 via pi as the primary implementation pool**. Use available free models for suitable jobs, and **GLM 5.4 via pi plus SWE 2.1 via the Devin CLI when their quota is available**. Reserve **Opus 5.5 and GPT-6.2 Sol for independent reviews** rather than making them the default code writers.

Choose by task and capability: implementation/debugging, content/data generation, regression checks, image inspection and audio review need different tools. A text-only worker cannot approve unheard music or unseen imagery. Keep the actual job/model record; do not relabel the coordinator's own work as a delegated model's output.

The following routes were observed locally on 26 November 2026. They are discovery examples, not promises of future access, free pricing or remaining quota. Recheck at startup and after availability changes.

| Role | Observed route examples |
| --- | --- |
| Step 5 Preview worker | pi provider `stepfun`, model `step-5-preview`; alternatively provider `openrouter`, model `stepfun/step-5-preview` |
| Longcat 2.5 worker | pi provider `longcat`, model `LongCat-2.5`; or provider `opencode`, model `longcat-2.5-free` |
| Other free worker | Current configured pi free routes with suitable capabilities and verified applicable terms/limits |
| GLM 5.4 worker | pi provider `zai`, model `glm-5.4`, when account quota is available |
| SWE 2.1 worker | Local Devin CLI, bare model UID `swe-2-1` or an available reasoning variant such as `swe-2-1-high` |
| Opus 5.5 reviewer | pi provider `venice` or `opencode`, model `claude-opus-5-5`; or provider `openrouter`, model `anthropic/claude-opus-5.5` |
| GPT-6.2 Sol reviewer | pi provider `openai-codex` or `opencode`, model `gpt-6.2-sol`; or provider `openrouter`, model `openai/gpt-6.2-sol` |

Use exact IDs rather than floating aliases. A native agent API exposing the exact requested reviewer is also acceptable when its actual identity is recorded. SWE 2.1 does **not** need a pi entry: use Devin's local CLI. Prefer bare SWE variants under available account quota; do not silently choose paid `-lightning` variants or Fusion/sidekick bundles. One Fusion session is not two independent model reviews.

Discover tools through their actual help/catalog rather than guessing flags:

```sh
pi --help
pi --list-models
pi auth check --provider stepfun --model step-5-preview --json --no-refresh
devin --help
devin --process-model in-process models list
devin --process-model in-process auth status
```

Authentication readiness, catalog presence, pricing and remaining quota are different facts. Use existing provider/CLI usage signals or explicit quota errors; do not invent a quota endpoint or assume a model is usable because it is listed. Never print credentials, use credential-emitting auth options, copy secret configuration into logs, buy credits/subscriptions or create accounts. Use the configured authorized routes; respect their terms and budgets.

On transient rate limits, use bounded backoff and record retry timing. On exhausted quota/authentication failure, stop that route, record the cause and choose another eligible worker without repeatedly hammering it. Check later when its limit resets. If no preferred worker is available, use an authorized suitable free/GLM/SWE route and record the substitution. Required Opus/Sol review identities may not be silently substituted.

## Launch pi and Devin jobs with isolated sessions

All children work in the same repository, but each needs its own conversation/session and logs. Use ignored `work/agents/<uuid>/` job directories. Never use unqualified `--continue` or interactive resume selection in the shared directory: it can attach the wrong worker's session. Resume by the recorded explicit session ID/path only.

Write a complete `task.md` before launching. These are noninteractive invocation shapes verified against the local CLI help; adapt only after checking installed help:

```sh
# Run from the repository root. Generate a fresh UUID for each new job.
job_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
job_dir="$PWD/work/agents/$job_id"
mkdir -p "$job_dir"
# Write $job_dir/task.md with role, scope, ownership, inputs and checks first.

pi --provider stepfun --model step-5-preview \
  --print --mode json --session-id "$job_id" \
  --session-dir "$job_dir/sessions" \
  @"$job_dir/task.md" > "$job_dir/events.jsonl" 2> "$job_dir/stderr.log"

# Alternative job: SWE 2.1 through local Devin, using a fresh job directory.
devin --process-model in-process --model swe-2-1-high \
  --prompt-file "$job_dir/task.md" --export "$job_dir/devin-session-export" \
  --print > "$job_dir/devin-output.log" 2> "$job_dir/stderr.log"
```

These are alternative launches, not two workers owning one task/directory. Keep Devin local, not `--cloud`, so it operates on the shared checkout. Respect configured permissions/workspace trust; resolve real permission failures rather than disabling checks blindly. Record Devin's actual session ID for explicit resume.

Use the environment's supervised asynchronous process/job tools to run workers concurrently. Track completion and read incremental output; do not detach forgotten jobs or end the coordinator turn immediately after dispatch. A running process or a model saying “done” is not a successful integrated deliverable. Keep raw sessions/reasoning/logs private and ignored. Publish concise task/model/provenance/evidence summaries in `docs/STATUS.md`, `docs/IMPLEMENTATION_LOG.md` and the required manifests; do not commit raw sessions or credentials.

## Implement, integrate, verify and continue

1. Choose dependency-ready work from PLAN. Dispatch small independent jobs, including test/content tooling where useful. Start M0 infrastructure rather than writing a new speculative master plan.
2. Collect artifacts and check actual diffs, ownership, imports, behavior and meaningful tests. Run the checks appropriate to the changed system. Do not repeatedly rerun unrelated expensive suites without a reason.
3. Integrate coherent ready batches. Workers/reviewers do not stage, commit, pull or push. The coordinator, or one explicitly designated integrator, serializes Git changes, commits only ready owned paths with `git commit --only -- <paths>`, preserves other staged work and pushes normal updates to `origin/main`. Retry brief lock contention; never delete an active lock, force-push or rewrite shared history to resolve it.
4. Keep tests tied to the actual candidate. For full executable checks, briefly freeze writers to relevant dependency paths or export the candidate commit into an ignored immutable source snapshot/build directory. Such an export is not another Git clone/worktree. Reading `git show` while testing a changing live tree does not prove the candidate passed.
5. At each checkpoint obtain both reviews below, fix supported blockers/major defects through workers, rerun affected checks and obtain scoped rechecks on the corrected candidate. Record accepted/rejected recommendations with evidence; do not blindly implement unsupported reviewer suggestions or reduce requested scope.
6. Update milestone status, file ownership, evidence, model/compute use and next jobs. Then continue immediately. Do not stop after a successful prototype, milestone, review or commit to ask “shall I continue?”

Honor the plan's early handling/four-camera/simulator gates, starter and launch handling freezes, bounded learning allocations, complete save semantics, real controller/platform checks and original asset/model provenance. Cosmetic debris is presentation-only. Both Roadstormer styles must use actual learned inference; a Classic fallback is fault recovery, not completion of learning.

## Mandatory independent Opus 5.5 and GPT-6.2 Sol reviews

Every checkpoint has **two separate reviews**: one by **Opus 5.5**, one by **GPT-6.2 Sol**. Neither reviewer's implementation contribution replaces its review. Neither may delegate, consult the other's current report before submitting, edit game/source/assets, or mutate Git. They may write only their assigned unique report and run scoped checks with outputs in ignored work directories.

Request both reviews:

- At every milestone's acceptance checkpoint, including M0, M4B and final M9 readiness.
- Within a long milestone after five completed implementation jobs or 60 minutes of substantive changed work, whichever comes first.
- Before closing critical handling, simulation/AI schema, four-player rendering, save/economy, license/provenance or launch-handling/model freezes, and after fixes that reopen them.

Coalesce checkpoints when one pair covers several due triggers. Do not spend review quota re-reviewing unchanged code while only waiting for a long training/render run. Independent jobs may continue outside the reviewed ownership/dependency scope while the pair runs.

Give both reviewers the same immutable candidate SHA, changed paths/base SHA, relevant contracts, actual results/captures and open issues. Each inspects that exact source through `git show` or its own export of the SHA. Executable tests/imports run in **separate per-reviewer immutable-source/build directories**, with isolated `.godot`/import caches and output paths, not the concurrently edited checkout or each other's cache. Exports are plain snapshots, not Git clones/worktrees. Supply the source SHA to build tools explicitly where needed. Require independent verification and record exactly which source state each check used. No audio/gamepad/platform/visual approval without actual capability/evidence.

Each reviewer writes one new file, for example:

```text
review/implementation/<checkpoint>-opus-5-5-<uuid>.md
review/implementation/<checkpoint>-gpt-6-2-sol-<uuid>.md
```

The report records actual model/provider, date, candidate SHA/scope, files inspected, commands actually run and outcomes, artifacts/capability limits, ranked actionable findings with verified file/line references, and a verdict: **pass**, **changes required**, or **not verified**. Distinguish implementation defects, plan mismatches, optional improvements and missing evidence. Never fabricate model identity, execution or agreement.

Consolidate the two reports into tracked fixes/decisions. Use experiments for disputed technical claims rather than vote counting or endless debate. Close relevant supported blockers/major defects and evidence gaps before accepting the gate; a scoped follow-up from both reviewers must cover the final affected candidate. Preserve original reports and record recheck SHAs. Minor nonblocking issues may remain only with an explicit documented disposition consistent with the plan.

If one reviewer is temporarily unavailable, queue that required review, keep the checkpoint open and progress unrelated work. Do not substitute another model while labeling it Opus/Sol, and do not call a single-model checkpoint dual-reviewed. If unavailable review access ultimately blocks all remaining progress, report the exact missing route/quota and completed work.

## Persistence, blockers and completion

Maintain durable status after each coherent batch and before context/session limits: current revision, completed/open milestone gates, runnable build, worker sessions/file ownership, outstanding reviews/findings, measured evidence, compute allocations, blockers and the exact next dispatch. After compaction/handoff read that state and inspect running jobs before launching replacements. Do not create cron jobs/automations to simulate progress or leave orphan workers.

Release or hand off the coordinator lease explicitly only after reconciling owned workers/jobs. For final review, freeze a `release_source_sha` and the source/configuration/asset/tool input manifest used by the packages. A later review/status-only commit may add reports/ledgers, but verify that all release inputs remain identical and link both SHAs. Do not rebuild against an unreviewed HEAD or let an automatic version stamp silently change package inputs; any source/runtime input change reopens the affected checks/reviews. The final repository SHA and reviewed release source SHA may differ only by this recorded evidence-only follow-up.

Use judgment for routine choices and reversible work. User authorization covers implementing the agreed scope, pinned development tools, local builds/tests/generation within documented budgets, regular named-model reviews, source commits/pushes and the repository's authorized release workflow. Preserve the existing first-party Unlicense/CC0 intent and actual dependency terms. Do not invent contributor signatures, obtain new paid services, publish to unrelated services or change the product scope.

Hardware, audio-capable review, provider quota, credentials or a failed bounded learning experiment may be genuine constraints. Finish independent work, prepare concrete evidence/artifacts and try compliant alternatives within the plan. Ask for only the missing resource/decision once it actually prevents further useful progress. Never mark unavailable checks passed, lower thresholds afterward, relabel scripts as learned AI or remove required features to get to “done.”

Finish only when M0–M9, including M4B, meet their required gates; the full game/content and original source/generators/model artifacts exist; relevant tests and perceptual/hardware/platform reviews are real; both named reviewers have covered the final candidate; saves/provenance/notices are complete; and release packages/source are verified and published through the existing authorized repository workflow where access permits. Prepare all release work before reporting a genuine final publication/access blocker.

The final response should give the playable build/release and source links, final commit/version, concise implemented scope, both final review references, verification results and any actual unresolved limitations. Do not present a partly implemented game as the end-to-end result. Begin with the safe pull, inspect the current state, and dispatch the first implementation jobs now.
