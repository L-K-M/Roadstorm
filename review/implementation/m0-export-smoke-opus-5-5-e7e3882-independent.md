# M0 export-smoke repair — independent review (Claude Opus 5.5)

- Reviewer: Claude Opus 5.5 (`claude-opus-5-5`), Anthropic, via Claude Code. No helpers or subagents.
- Candidate: `e7e38823f3b8807cfa606d96d00156ce23f1b53a` ("Preserve smoke export outputs and bind frozen source")
- Base: `6cc0058af4680f8ac04409974888c8b12e053e01`
- Scope: `tools/export_smoke/lib/common.sh`, `tools/export_smoke/run_export_smoke.sh`, `tools/export_smoke/tests/test_common.sh` (+310/+68/+517 lines vs base)
- I did not read any other current export-smoke review.

## Checks actually performed

- I resolved both SHAs and confirmed that `6cc0058..e7e3882` is the single commit and that it touches only the three scoped files (`git diff --stat`).
- I read the exact Git objects with `git show e7e3882:<path>` for all three files, plus `git diff 6cc0058 e7e3882` for the runner. I did not use working-tree copies.
- Context reads at `e7e3882`: `git grep` for `es_candidate_digest`, the default output path and runner references; the README usage section; `git ls-files -s export_presets.cfg` (mode `100644`, a regular file); the head of `tools/toolchain/pin/engine.txt`; and the output handling in `launch_macos_app.sh`.
- **I could not run anything.** In this session, `mktemp -d`, both under `/tmp` and under the default TMPDIR, needed approval and was not approved, so I could not build an isolated private snapshot. I did not run the test suite, shellcheck, or sh/dash myself. The coordinator's 125/125 run is the only execution evidence, and I did not reproduce it. Everything below comes from reading the code.
- I made no Git, source, GUI or shared-file writes. The only file I wrote is this one.

## Assessment by requirement

| Area | Result |
| --- | --- |
| Fail-closed archive/extraction | **Good.** `git archive` writes to a real file in a private stage, and its exit status is checked on its own, so the old pipeline that masked failures is gone. tar's status is checked separately. A missing or empty `project.godot`, a non-Git source, a missing project, and snapshot == project all return nonzero. Each failure path prints the stage name and the first 5 lines of stderr. |
| Single immutable SHA/tree/digest under HEAD movement | **Good for SHA/tree/archive.** `es_resolve_head` reads HEAD exactly once and checks it is a 40-hex value. The tree comes from `$SRC_SHA^{tree}`. The archive is built with `git archive $SRC_SHA` after `^{commit}` verification. The archive digest is hashed from the exact tar file that was extracted, and nothing re-runs `git archive`. **Gap:** the presets component of `candidate_digest` is still read from the live working tree (finding 1). |
| No-clobber output, symlinks | **Good.** The runner reserves `--out` itself with a plain (non `-p`) `mkdir` after resolving the parent with `pwd -P`, so any existing path is refused before anything is written: directory, file, symlink or dangling symlink. Inside `es_make_frozen_snapshot` the destination is also reserved with an exclusive `mkdir`, and its dev:inode identity is checked again before extraction and before success. The stat probe correctly avoids GNU `stat -f`. One narrow write-through remains (finding 3). The digest file is not created exclusively (finding 4). |
| Cleanup safety | **Good.** Only the mktemp stage is deleted, only while it is still a non-symlink directory whose identity matches, and nothing is deleted when identity is unknown. Reservations and `--out` are never deleted on failure, and the "left in place" NOTE is printed. If the identity changed concurrently, the reservation is left alone. The runner removes `.candidate-snapshot.archive-sha256` only when its contents still match. |
| Test harness preservation | **Good.** The suite works in a unique mktemp child of `EXPORT_SMOKE_TEST_WORK` or TMPDIR and removes it only if the dev:inode identity matches. It snapshots the parent's entries before and after (#13) and uses PATH shims instead of touching the installed git or tar. The first runner case in #17 runs against the real checkout, but it is read-only there (`rev-parse`), and the runner refuses at the `mkdir` of the pre-populated private `--out`. |
| Ordinary export path | **Works for a fresh `--out`. Repeat runs now fail** (finding 2). |

## Ranked findings

### 1. Medium — `presets_sha256` / `candidate_digest` hash the live working-tree presets, not the copy that was exported
`run_export_smoke.sh`: `PRESETS_SHA="$(es_sha256 "$PROJECT_DIR/export_presets.cfg")"` runs after `es_make_frozen_snapshot` has already copied that file into `$SNAP`. If another job edits `export_presets.cfg` between the `cp` and the hash, the report's `presets_sha256` and `candidate_digest` describe bytes that were never exported. `presets_exclude_filter` and `pack_inventory.py --snapshot` do read the snapshot copy, so the report can contradict itself. This weakens the "single immutable digest" claim. A related problem: when the working-tree file is missing, `es_sha256` prints nothing (or `NO_SHA256_UTILITY`), and the run continues with an invalid digest instead of failing closed. `CANDIDATE_SHA` also calls `shasum` directly with no fallback.
**Fix:** hash `"$SNAP/export_presets.cfg"`, require `es_is_hex_sha256`, and compute the candidate digest with `es_sha256` on a file. Add a test that edits the working-tree presets after the snapshot is built.

### 2. Medium (usability/ordinary path) — fixed default `--out` makes every second run fail with exit 2, and the docs were not updated
Without `--out`, the runner uses `$PROJECT_DIR/work/agents/export-smoke/outputs`. After the first run, every later run without `--out` dies with "output destination already exists". The README examples (`--out /tmp/rs-linux`, `--out work/agents/<id>/outputs`) give fixed paths, and the README does not say that `--out` must not already exist. Refusing is the right safe behaviour, but this is an undocumented contract change. Also, any `mkdir` failure (for example EACCES on the parent) is reported as "already exists".
**Fix:** either default to a unique name (for example `outputs.<UTC timestamp>.XXXXXX` via `mktemp -d`) or document the fresh-`--out` requirement in the README and `--help`. Report non-existence failures separately.

### 3. Low — the presets overlay can write through a tracked symlink outside the snapshot
`cp "$_proj_abs/export_presets.cfg" "$_snap_abs/export_presets.cfg"` follows the destination if the archived commit stores `export_presets.cfg` as a symlink. tar extracts it as a symlink, so a relative target such as `../x` makes `cp` write outside the reserved snapshot. Today the file is mode `100644`, so this cannot happen at `e7e3882`. Still, it is the one path where the "never written through a symlink" property depends on repository content.
**Fix:** before copying, fail closed if `[ -L "$_snap_abs/export_presets.cfg" ]` (or if any component of the destination is a symlink), or `rm -f` the extracted entry first.

### 4. Low — the archive-digest file is "check then `>`", not an exclusive create
`[ -e ] || [ -L ]` is followed by `printf >"$_digest_file"`. A path created in between, including a symlink, is followed and truncated. In the runner this is mitigated, because the file lives in the freshly reserved `--out`. As a library function that takes caller paths, though, it does not deliver the "created, never truncated" promise in its own comment.
**Fix:** `( set -C; printf '%s\n' "$_digest" >"$_digest_file" )`, or write inside the stage and `ln` (no `-f`) into place.

### 5. Nit — case-pattern typo in the runner
`"""."|"..")` concatenates to `"."|".."`, which drops the intended empty-basename alternative (common.sh correctly has `""|"."|".."`). The empty case is practically unreachable because OUT_DIR always has a default, and `/` fails at `mkdir`, but the pattern should be `""|"."|"..")`.

### 6. Nit — stale wording and a dead helper
- The archive failure message still says "git archive HEAD failed" when a pinned SHA was archived. The test asserts that exact text, so update both.
- `es_candidate_digest` is unused, still runs `git archive HEAD` up to three times, and contradicts the new "no second `git archive`" contract. Remove it.

### 7. Nit — `PROJECT_DIR` pointing at a subdirectory of a repository
With the `PROJECT_DIR` env override pointing at a repository subdirectory, `git archive` run from that subdirectory archives only it, but `head_tree` reports the root tree. This only happens through the override. Consider requiring `git rev-parse --show-prefix` to be empty.

### 8. Test-suite observations (no blocking defects)
- Coverage gaps: findings 1–4. HEAD movement is tested only sequentially against the library (#16), not while the runner is running. That is acceptable because the runner never re-reads HEAD, which I checked in the code.
- `assert_absent "dirty tracked content excluded" "$SNAP1/src/main.gd.dirty"` passes no matter what, because the real check is the `file_eq "tracked"` assertion next to it.
- Fragile coupling: the fake godot prints the *real* checkout's pin, while the runner with `PROJECT_DIR=$REPO` falls back to the hard-coded constant. If the pin and the constant ever diverge, the "exit 1" runner test turns into exit 2.

### Pre-existing (out of scope, noted only)
`es_run_bounded` maps every status from 124 to 137 to "timeout", including 126 and 127 (command not executable or not found). `launch_macos_app.sh` still `mkdir -p`s its `--out` and writes fixed names into it. That is safe when the runner calls it, because `--out` is fresh then, but not when it is called on its own.

## Limitations

- This is a static review only. I ran no tests, shells (sh/dash/bash) or shellcheck, because private temp-dir creation was blocked in this session. Real behaviour on GNU vs BSD `stat`/`tar` and dash quirks is inferred from the code, not observed.
- I reviewed only the three scoped files. `pack_inventory.py`, `launch_macos_app.sh` and the presets content were read only for context.
- I did not check real Godot export or launch behaviour.

## Verdict

**Conditional pass.** The repair meets its core safety goals: archive and extraction fail closed, the SHA, tree and archive digest are bound to one commit, existing outputs, symlinks and the harness parent are preserved, and cleanup is conservative. Fix finding 1 (hash the snapshot's presets and fail closed on an invalid digest) before anyone cites `presets_sha256` or `candidate_digest` as M0 evidence. Fix or document finding 2 before ordinary reruns are expected to work. Findings 3–8 are low or nit and do not block.
