# M0 CI/export failure-path and suite-integration checkpoint: independent review (Opus 5.5)

| field | value |
| --- | --- |
| reviewer model | Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, run through Claude Code |
| date | 2026-11-27 |
| candidate | `675ec1c0ba63ed293b4c6fa0e75609b8276ecc16` ("Harden export evidence and run contract suites in CI") |
| base | `5f69dd257c7c2dad5a731233aa4b38637c2672d6` |
| scope | `.github/workflows/ci.yml`, `tools/ci/**` (`ci.sh`, `lib/common.sh`, `tests/run_tests.sh`, `README.md`), checked against PLAN.md M0.4-M0.5 and plan/IMPLEMENTATION.md (candidate isolation, source-SHA provenance) |
| child agents / helpers | none |
| Sol current report / other workers' outputs | not consulted |
| verdict | **changes required** (one documentation/coverage defect at important severity; no correctness defect found in the changed runtime paths). Execution: **not verified by this reviewer**, see "Execution" below. |

## Execution: what I did and did not run

My permission layer blocked every command that would have executed the
candidate. Each of the following returned "This command requires approval" and
**did not run**:

- `godot --version` (engine discovery)
- `mktemp -d` and `mktemp -d .../work/opus55-review-675ec1c.XXXXXX` (my private snapshot/build directory)
- `actionlint .github/workflows/ci.yml`
- `sh -n tools/ci/ci.sh`
- `shellcheck -s sh -S warning` on `ci.sh`, `lib/common.sh`, `tests/run_tests.sh`
- `gh run view 45934306464 --json headSha,conclusion,jobs`

So I created **no snapshot**, ran **no suites** (none of the five contract
suites and not `tools/ci/tests/run_tests.sh`), ran **no actionlint**, and did
**not** inspect GitHub run 45934306464. I cannot confirm the coordinator's
five-suite and actionlint results or the four green jobs. Nothing was written
to installed templates, user files, the checkout's `.godot/` or Git.

The commands that did run were read-only:

- `git rev-parse HEAD` returned `675ec1c0ba63ed293b4c6fa0e75609b8276ecc16`, and
  `git status --porcelain -- tools/ci .github` was empty, so the working-tree
  copies of the reviewed paths are byte-identical to the candidate. (Other
  paths are modified locally, including `tools/python_pin/tests/test_verify.sh`
  and `verify.sh`. I did not use them; any execution must use an export of the
  SHA, not this tree.)
- `git diff --stat` and `git diff` base..candidate for the five changed files
  (536 insertions, 46 deletions).
- `git show 675ec1c:` for `tools/ci/README.md` and `docs/PYTHON_TOOLCHAIN.md`,
  and `git grep` at `675ec1c` in `PLAN.md`, `plan/IMPLEMENTATION.md`, `ci.sh`
  and `ci.yml`.
- `which` found `godot`, `actionlint`, `shellcheck`, `python3` and `bash` under
  `/opt/homebrew/bin`. They are installed but I could not run them.
- I read `tools/export_smoke/lib/pack_inventory.py` `cmd_check` (lines
  562-704) to see how it reports failures.

Everything below comes from static reading.

## Findings

### F1 (important, test-coverage/docs): the new export failure-path cases never run in hosted CI, but the README says they do

- `tools/ci/README.md:173-177` says the template-dependent cases "only run
  where those templates exist -- on CI that is the export job after its
  verified installation". The README also says (lines 169-171) that the suite
  "proves" the stale-output refusal and the single failing verdict.
- In fact `tools/ci/tests/run_tests.sh` runs only through
  `ci_tooling_selftest`, and `validate` is its only caller (`tools/ci/ci.sh:892`).
  `validate` runs only in the `checks` job (`.github/workflows/ci.yml:112`),
  and that job installs no export templates. The `export-preparation` job
  (`ci.yml:229-396`) installs templates but runs only `export --check` and
  `export --export`. Neither runs the self-test.
- So every case behind `run_tests.sh:2081-2087` (templates required) is
  skipped on GitHub, and the job still passes with only a "note: ... skipped"
  log line. That covers all of this commit's main export fault-path evidence:
  - R2: refusing an existing main file, a lone sidecar, or a dangling symlink
  - the Sol 8c6c928 corrupted-`.pck` fault injection
  - "exactly one failing verdict"
  - "no stale passing inventory report"
  - the source SHA in the inventory filename

  The green run 45934306464 therefore cannot be evidence for any of them. Only
  a local run on a host with the pinned 4.7.2 templates can be.
- Failure scenario: a later edit moves `ci_ok "export: $_pass_msg"` back above
  the inventory check (`ci.sh:1991`), or drops the stale-output refusal
  (`ci.sh:1855-1865`). Every hosted job stays green. The README tells the next
  reviewer that hosted CI covers these cases, so nobody re-runs them locally.
- Fix, either:
  - run `sh tools/ci/tests/run_tests.sh` (or `ci.sh validate`) in the
    `export-preparation` job after `install-templates`, with `GODOT_BIN` set.
    The suite already copies the templates into its private `REALHOME`, so it
    does not touch the installed tree. Or
  - correct README lines 169-177 to say these cases run only locally, and add
    a self-test or workflow case that fails when the export job does not run
    them.

### F2 (nit, test-quality): the "no stale passing inventory report" case passes only because of the kind of corruption injected

- `run_tests.sh:2380-2389` asserts that
  `export-package-inventory-linux-x86-64.txt` is absent or empty after the
  corrupt run. That holds only because the injected bytes (`corrupt pack`)
  make `parse_pck` fail, and `pack_inventory.py:633-634` then `die(1)`s before
  `write_report` (`:658-659`).
- A parseable pack with an MD5 or policy failure writes a **FAIL** report at
  that path. The case then reports `no`, even though the behaviour it is named
  for (no stale PASS report) is correct.
- Assert instead that the file has no `PASS` verdict.
- Related nit: when the inventory `die`s, its message goes only to the job
  console (`ci.sh:1978-1983`). The uploaded `reports/` holds only
  `reason=pack-inventory inventory_rc=N`, with no inventory report and no
  reason text. Write `$_inv_out` into the run report or into a log under
  `$CI_OUT/logs` so the uploaded evidence names the reason.

### F3 (nit, test-quality): workflow structure checks read to end of file, not to the end of the job

- `run_tests.sh:1984` reads from `Upload built packages` to EOF and
  `run_tests.sh:2000` reads from `contract-suites:` to EOF. The export-block
  check that follows reads from `export-preparation:` to EOF.
- The `if: success()` check therefore matches any later `if: success()` in
  the file. A regression back to `if: always()` on the package upload would
  still pass once a later step or job uses `success()`.
- The contract-suites "no `ci.sh`" check fails on any job added after it that
  calls `ci.sh`, even though nothing is wrong.
- Fix: stop each block at the next step or job header (`/^      - name:/` and
  `/^  [a-z-]+:$/`).

### F4 (nit, docs accuracy)

- `tools/ci/README.md:433` still says export-preparation is "skipped until
  `export_presets.cfg` exists". `ci.yml:221-228` says the job has no condition
  and always runs.
- `README.md:117` says report filenames "carry a per-process id", and the
  comment at `run_tests.sh:892-895` says "named per process (PID)". The
  implementation (`lib/common.sh:1021-1038`) uses a `mktemp` random suffix.
  Only the no-`mktemp` fallback (`:1040-1048`) uses `$$`. That fallback is
  untested, and its `-e` probe followed by `>` is not atomic, and subshells
  share `$$`, so it would not meet the stated same-second guarantee. It
  matters only on hosts without `mktemp`.

### F5 (nit, provenance)

- `ci.yml:182` (`capture --check`) is the only `ci.sh` call in `checks` without
  `--source-sha`, so its report records `source-sha: not recorded`
  (`lib/common.sh:1055`). plan/IMPLEMENTATION.md asks for the source SHA to be
  supplied to build tools explicitly.
- On `pull_request` events, `github.sha` is the synthetic merge commit, not the
  PR head. Reports and the inventory filename tag (`ci.sh:1971-1973`, cut to 12
  characters) name that merge commit. This is consistent with what was checked
  out, but reviewers given an immutable head SHA should know it will not match.
- The contract-suites job uses the runner's unpinned `python3`. Its version is
  printed to the log (`ci.yml:419`) but not added to the step summary.

### F6 (pre-existing, nit, concurrency/permissions; not changed by this commit)

- `ci.yml:33-35` uses `cancel-in-progress: true` for every ref, including
  `push` to `main`. A quick second push cancels the first commit's run, so a
  superseded `main` commit can end up with no completed CI evidence. Consider
  `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`.
- There is no top-level `permissions:` block, and `actions/checkout` keeps the
  token in `.git/config` while the new contract-suites job runs repository
  scripts. `permissions: contents: read` would be the least-privilege default.

## Changes checked and found correct (static)

- **Fail-closed tracked-output check**
  - `ci_tracked_output_paths` (`lib/common.sh:1184-1204`) now captures the
    real `git ls-files` status in a command substitution and returns it
    instead of piping it away.
  - `ci_tooling_selfcheck` (`ci.sh:934-948`) reads that status correctly:
    under POSIX sh, an assignment-only command's status is the substitution's.
  - A corrupt index, a dubious-ownership refusal, or a broken `.git` file
    pointer therefore fails `validate`.
  - The new case (`run_tests.sh` around 766-778) corrupts only its private
    throwaway repository.
  - Remaining limitation: a snapshot export with no `.git` skips this check by
    design.
- **PASS emitted after the inventory**
  - `ci_export_build` now builds `_pass_msg`/`_pass_fields` and emits
    `ci_ok`/`export result=pass` only after the inventory returns 0
    (`ci.sh:1987-1993`).
  - Every failure path before that writes exactly one `result=fail` line.
- **Stale output refusal** (`ci.sh:1839-1865`)
  - The sidecar path is derived from the basename before the engine runs.
  - Main and sidecar are each tested with `-e || -L`, so dangling symlinks are
    caught.
  - The refusal runs before `ci_prepared_copy` and the engine, and nothing is
    deleted.
  - On hosted CI, `actions/checkout`'s default clean removes `build/` and
    `tools/ci/out/`, so a re-run does not trip it.
  - The only side effect on a refused run is the earlier `mkdir -p` of the
    output's parent directory (`ci.sh:1805`).
- **Report uniqueness** (`lib/common.sh:1013-1057`)
  - `mktemp` followed by `mv` gives distinct names for concurrent processes
    and for repeated calls in one process.
  - The preset rename (`ci.sh:1829-1837`) now refuses to `mv` onto an existing
    name.
  - Residual risk is negligible: `mv` would overwrite if two processes in the
    same second drew the same 6-character suffix after the first temp file had
    already been renamed away.
- **Package upload gating**
  - `if: success()` on `Upload built packages` (`ci.yml:389-396`), while logs
    and reports still upload under `always()`.
  - The build loop (`ci.yml:338-361`) runs under `set -euo pipefail`. A failing
    `ci.sh export` in the `while` body exits the pipeline subshell, and
    pipefail fails the step, so later presets do not run and nothing is
    uploaded.
  - Godot's stdin is `/dev/null`: it runs as an asynchronous list in
    non-interactive sh (`lib/common.sh:127-129`), so it cannot consume the
    preset list from the pipe.
- **Contract-suites job** (`ci.yml:404-474`)
  - Separate job; needs no editor, templates or accounts.
  - Explicit `bash`/`python3` prerequisite checks.
  - Private `TMPDIR`/`HOME`/`XDG_*` under `$RUNNER_TEMP`, and
    `PYTHONDONTWRITEBYTECODE=1`.
  - All five suites run even after a failure (`set -uo pipefail`, no `-e`).
  - In the `else` branch, `_rc=$?` correctly reads the `if` condition's
    status.
  - A missing suite is an error, not a skip, and any failure exits 1 with a
    per-suite PASS/FAIL summary.
  - Not verified: that the suites actually write nothing into the checkout.
    That needs execution.
- **Preset-name matching**
  - `grep -Fqx --` (`ci.sh:1813`) stops a preset name containing regex
    metacharacters, or starting with `-`, from matching the wrong preset.

## Limitations

- Static review only. Nothing was executed: no engine, no suites, no
  actionlint, no shellcheck, no snapshot. The permission layer blocked these
  commands. I did not route around it, and I am not claiming any execution.
- I did not inspect GitHub run 45934306464 or its logs and artifacts.
- I did not review `tools/ci/scripts/*`, `tools/ci/pin/engine.txt`, or the
  internals of the five contract suites. They were unchanged or out of scope
  except where cited.

## Verdict

**Changes required** for F1. The runtime changes in `ci.sh` and `lib/common.sh`
look correct on reading. But the commit's headline export fault-path proofs
never run in the CI it describes, and the README says they do. Either run the
self-test in the export job after the verified template installation, or
correct the coverage claim and record local engine-backed evidence for this
exact SHA. F2-F5 are non-blocking nits; F6 predates this commit.

Execution status: **not verified** by this reviewer (see "Execution").
