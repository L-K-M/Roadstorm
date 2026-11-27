# PR #1 bounded review report

Review route: LongCat 2.5 through Pi, run 2026-11-27.

Target: remote PR #1, 11 changed paths, base snapshot at origin/main SHA
`414a7d3404d719c9921f585619f185a458f4bb9d`, parent `dd95fd7`. Reviewed the
patched tree read-only from an immutable export. No Git mutation, fetch,
checkout, merge, tracked-file edit, helper process, or public communication.
One read-only `git ls-remote --tags origin` lookup was issued during
discovery and produced no `v0.1` match; no remote state was changed.

**Verdict: changes required before merge.** Three material findings (R1, R2,
R3) should be resolved first. R4-R7 are recommended hardening, not confirmed
exploits.

## Read-only checks actually run

```sh
bash -n scripts/build.sh && echo build.sh-ok        # pass
bash -n scripts/release.sh && echo release.sh-ok    # pass
bash -n tools/ci/ci.sh && echo ci.sh-ok            # pass
actionlint .github/workflows/ci.yml .github/workflows/zai-code-review.yml  # exit 0
shellcheck -S warning scripts/build.sh scripts/release.sh                   # no findings
# scratch copy, confirms the export is exactly the patched PR tree:
SCRATCH=$(mktemp -d /tmp/pr1review.XXXXXX); cp -a source/. "$SCRATCH"/
(cd "$SCRATCH" && patch -p1 --dry-run -R < ../remote.patch)                # applies cleanly
# installed release engine, read-only config probe:
env RELEASE_APP_NAME='Roadstorm Racer!' RELEASE_KIND=tag-only \
    RELEASE_INVOKED_AS='scripts/release.sh' /opt/homebrew/bin/lkm-release --check
# output included: version: (none yet) (from latest v-tag ...)
```

actionlint was version 1.7.12 (Homebrew). Scratch copy was deleted afterwards.

## Ranked findings

### R1 [High, changes required] New AGENTS.md/CLAUDE.md contradict the plan's shared-main procedure and mandatory reviews

Verified conflicts:

- `AGENTS.md:48` tells agents to use isolated worktrees; `AGENTS.md:59-63`
  says fetch and cut a task branch; `AGENTS.md:145-156` makes a PR and its
  merge the definition of done; `AGENTS.md:202-207` repeats that a task ends
  merged to main through a PR.
- `CLAUDE.md:5-8` mandates PR subscriptions and hourly `send_later`
  self-check-ins; `CLAUDE.md:25-36` tells the agent to declare steady-state,
  call the PR merge-ready, unsubscribe, delete triggers, and ignore later
  automated rounds.
- Against them: `PLAN.md:211` says use the shared checkout and "Do not create
  a branch/worktree per agent"; `plan/IMPLEMENTATION.md:9` says "Use the
  shared `main` checkout; do not create branches, worktrees or additional
  clones"; `plan/IMPLEMENTATION.md:103` makes the coordinator or one
  integrator the only party that commits and pushes to `origin/main`;
  `plan/IMPLEMENTATION.md:110-135` makes independent Opus 5.5 and GPT-6.2 Sol
  checkpoint reviews mandatory; `README.md:30` already says reviewers commit
  and push their report through the existing shared checkout.

Impact: during the implementation run these standing instructions can bypass
the coordinator lock and ownership model, create divergent branches or
worktrees, treat automated PR rounds as the acceptance gate instead of the
required named-model checkpoint reviews, and let CLAUDE.md's steady-state
rule suppress further review. This is a material reliability/process defect,
not merely a wording nit.

Resolution: add an explicit precedence clause to both files, for example:
"For the end-to-end implementation run, plan/IMPLEMENTATION.md and PLAN.md
govern: shared `main` checkout, no branches/worktrees, coordinator-owned
integration and direct pushes, and the mandatory Opus 5.5 plus GPT-6.2 Sol
checkpoint reviews. The generic branch/PR workflow applies only outside that
run." Or remove/scope the branch/PR and steady-state text while
IMPLEMENTATION.md is active. Verify `subscribe_pr_activity`, `send_later`,
and `unsubscribe_pr_activity` exist in the intended harness before requiring
them.

### R2 [Medium, changes required] README claims a release that the repository does not show

- `README.md:6` renders "**Latest release:** v0.1.0" with a Releases link.
- `CHANGELOG.md:7-23` has only `[Unreleased]` and no 0.1.0 section.
- `docs/STATUS.md:3` states "No milestone is complete and no game build is
  verified."
- The installed engine probe reports `version: (none yet)` from the latest
  v-tag, and `git tag -l` in the available clone is empty.
- `README.md:10` still says "No playable game or build system has been
  implemented yet," which this same PR contradicts by adding
  `scripts/build.sh`, CI hardening, and release entry points.

Additional verified mechanism: the installed `lkm-release` 1.1.0 only rewrites
the README `<!-- version -->` marker when `RELEASE_KIND != tag-only`
(`release-tool/lkm-release:571-593`). With `scripts/release.sh` setting
`RELEASE_KIND=tag-only`, even a future tag will not refresh the badge.

Resolution: replace the badge with a true statement such as "No public
release yet; packaging and publication are M9 decisions" until a real tagged
release exists; update the planning-stage sentence to match the delivered
validation/export tooling; decide deliberately whether tag-only releases
should maintain the marker.

### R3 [Medium, changes required] CI checks job uploads the whole scratch output directory

`.github/workflows/ci.yml:188-195` uploads `tools/ci/out/` with
`if-no-files-found: warn`. `tools/ci/lib/common.sh:669` creates
`$CI_OUT/project-copy` as a scratch copy of the candidate project, excluding
only `.git`, `.godot`, `work`, and `build`. The export job's own comment at
`ci.yml:432` correctly says `project-copy` is not evidence, and its upload at
`ci.yml:441-443` narrows to `logs/` and `reports/`. The checks job does not.

Impact: every checks run publishes a full project snapshot as an artifact. A
PR that adds an ignored-by-GitHub file such as `.env` or a local credential
would have it copied into `project-copy` and uploaded. It also bloats
artifacts for no diagnostic reason.

Resolution: change the ci-logs path to the same two directories used by
export-logs (`tools/ci/out/logs/` and `tools/ci/out/reports/`).

### R4 [Medium-Low, recommended] Privileged review workflow residual exposure

Verified mitigations, which are good: the trigger is `pull_request_target`;
the job guard at `.github/workflows/zai-code-review.yml:37-39` requires a
non-draft PR whose head repository equals the base repository; there is no
`actions/checkout`; no PR-controlled string is interpolated into a `run:`
script; the action is pinned to a 40-hex commit at line 62; workflow
permissions are limited to `contents: read`, `pull-requests: write`,
`issues: write` at lines 13-16; job and step timeouts are set (lines 34, 58);
cancelled superseded runs are excluded from failure reporting (line 100).

Residual risks:

- Line 28 routes the job with `vars.ZAI_REVIEW_RUNNER || 'ubuntu-latest'`.
  A mutable repository variable can send this privileged job to a
  self-hosted runner label. Combined with lines 41, 64, 67, and 92, that
  runner receives `ZAI_API_KEY`, `STEPFUN_API_KEY`, and a write-capable
  `GITHUB_TOKEN`.
- The two provider keys and the token are handed to a third-party action.
  The pin prevents later upstream drift, but the code at that commit was not
  audited here and could itself fetch or execute PR content.

Recommendations: name only a dedicated, isolated, ideally ephemeral runner
for this label and document that trust assumption; never point it at a
shared persistent fleet; confirm the pinned action's source does not checkout
or execute the PR head; consider vendoring the small action or splitting the
token so the model action gets only the scope it needs; optionally retry the
comment POST if `gh api` fails transiently.

### R5 [Low, recommended] release.sh execs an unpinned PATH binary

`scripts/release.sh:17-22` resolves `LKM_RELEASE_BIN` or `lkm-release` from
`PATH` and `exec`s it with all arguments. The installed engine (1.1.0)
validates versions, refuses dirty trees, and supports `--check`, so local
behavior is sound, but the stub cannot enforce `RELEASE_KIND=tag-only`
semantics across engine versions, and a substituted PATH binary would run
with the caller's privileges. Resolution: require an absolute path or verify
a checksum, document a minimum engine version, and drop the em dash in the
error text at line 19 to match the repository style rule in `AGENTS.md:73`.

### R6 [Low, recommended] build.sh input validation and check output

`scripts/build.sh:29-31` accepts any `--launch-probe` value although the
usage text says `headless|full`; invalid values fail later inside the export
smoke tool. `scripts/build.sh:38-43` prints `${godot_args[*]}
${ci_args[*]}` unquoted, so the `--check` output is misleading or not
copy-pasteable when a path contains spaces. Resolution: validate the probe
value and print the command with quoted array expansion.

### R7 [Low, recommended] flock `-E 99` assumes util-linux semantics

`tools/ci/ci.sh:1896` passes `-E 99` to `flock`. Current CI uses
ubuntu-latest, where util-linux flock supports it, and the collision risk is
low because the in-tree inner command returns only `CI_OK`/`CI_FAIL`
(`tools/ci/lib/common.sh:19`, values 0/1). Older util-linux, busybox, or BSD
implementations may reject `-E`; macOS here has no `flock` at all and falls
back to `lockf`. Resolution: feature-check `-E` support or document that
hosted Linux is the supported export environment.

## Verified strengths

- Every changed `uses:` reference is pinned to a full commit SHA:
  `ci.yml:46,190,206,239,438,456,474` and `zai-code-review.yml:62`.
- CI adds least-privilege `permissions: contents: read` (`ci.yml:33-34`),
  per-job timeouts (`ci.yml:44,203,237,472`), and limits concurrency
  cancellation to pull requests (`ci.yml:37-38`).
- Export packages are uploaded only on success (`ci.yml:454-461`), while logs
  upload on failure (`ci.yml:436-445`).
- The new `tools/ci/ci.sh` flock handling correctly distinguishes acquisition
  timeout from an inner command failure, and the wrapper converts the
  collision code back to `CI_FAIL`.
- README's LLM disclosure is present and the CHANGELOG entry is scoped to
  `[Unreleased]`.

## Not verifiable from this offline snapshot

- Mapping of the pinned SHAs to the claimed tags (`v7.0.1`, `v7.0.2`, and
  `zai-code-review v0.0.17`). Checking these needs `git ls-remote`, which was
  out of scope.
- Contents and behavior of `L-K-M/zai-code-review@7e2222d...`.
- Remote GitHub releases or tags. Only local clone refs were inspected.

## Suggested merge resolution

Required before merge: R1 precedence/scoping fix, R2 README truth fix, R3
artifact path narrowing. Recommended in the same PR or as an explicitly
disposed follow-up: R4 runner trust and action audit, R5 release binary
pinning, R6 build.sh validation, R7 flock portability note. After R1-R3 are
addressed and the checks above still pass, the merge has no confirmed
security blocker in the reviewed surface.
