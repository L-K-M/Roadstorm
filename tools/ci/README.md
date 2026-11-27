# tools/ci — command-line entry points and CI

Original project code under the Unlicense. **Ownership: `tools/ci/**` only** (see
PLAN.md "How agents execute the plan"). Nothing here writes to the shared Godot
project or its `.godot/` import cache, and nothing here mutates Git.

This directory implements PLAN.md **M0.4** (original command-line import, test,
content-validation, capture and export entry points, where a deliberately failing
test must return a failing exit code), the CI half of **M0.5**, and the
release-artifact half of **M0.1** (`ci.sh verify-engine` and
`ci.sh pin`: pin the official archive and verify it *before* installation).

```sh
tools/ci/ci.sh --help
tools/ci/ci.sh commands
```

## Requirements

| Requirement | Detail |
| --- | --- |
| Godot editor | **4.7.2 Standard**, the version pinned in `pin/engine.txt` (PLAN.md M0.1). Found via `$GODOT_BIN`, then `godot`/`godot4`/`Godot` on `PATH`, then common install locations. Not needed by `verify-engine`, `verify-templates` or `install-templates`. |
| Shell | Any POSIX `/bin/sh` (dash, bash, ash, busybox). No bashisms; verified under `dash`. |
| Everything else | `tar`, `grep`, `sed`, `awk`, `find`, `sort`, `head`, `dirname`, `mktemp`, `date`, `uname`; `unzip` for `install-templates` (the workflow also uses it to unpack the editor archive). |
| Python 3 | Needed by `ci.sh` for exact-destination report hard links (`link(2)` via `os.link`) and by the export package inventory. On Linux, GNU coreutils/busybox `ln -T` is used when Python 3 is absent; without either, report reservation/publication fails closed immediately (one attempt, not a retry loop) rather than falling back to a non-exact operation. `scripts/runtime_error_gate.sh` also uses `python3` to inject the GDScript faults into its snapshot copies (the same dependency `tools/smoke/fault_injection.sh` and `tools/asset_manifest/` already have). |

Set `GODOT_BIN=/path/to/godot` when the engine is not on `PATH`. Set
`GODOT_TEMPLATES_DIR` when the export templates live outside the usual Godot
user-data directory. `NO_COLOR=1` disables colour.

## The engine pin and the release artifact (PLAN.md M0.1)

Two pin files, two jobs:

| File | Owner | Pins |
| --- | --- | --- |
| `tools/toolchain/pin/engine.txt` | `tools/toolchain/**` | the **installed** toolchain: version, official sources, locally observed digests, upstream-verification status. Authoritative for the version. |
| `tools/ci/pin/engine.txt` | `tools/ci/**` | the **release artifact** CI downloads: the official URL and the pinned publisher digests. |

Why both: a digest recorded on one host for an *installed* file is not a portable
expectation for another host, so those stay local. A digest of a *published
release archive* is different — the publisher publishes it and every host
downloads the same bytes — so that is what CI must refuse to extract or run when
it does not match. `ci_pin_load` reads the version from the toolchain record when
the project carries it (so the two cannot drift) and always reads the release
artifact block from this directory's own pin.

Recorded on 2026-11-26 for the pinned tag `4.7.2-stable`: the publisher's
`SHA512-SUMS.txt` was fetched, and its line for
`Godot_v4.7.2-stable_linux.x86_64.zip` is the pinned `release_archive_sha512`.
The same checksum file also carries the two digests recorded in
`docs/evidence/godot-4.7.2-archive-verification.md`, which confirms it is the
publisher's file for this tag rather than a mirror. The archive was then
downloaded from the official URL and hashed locally; the digest matched, and the
archive's SHA-256 and the extracted binary's SHA-256 are recorded as local
observations of that verified download.

Scope: the Linux x86_64 editor ZIP and the editor binary inside it. Other release
assets are covered by the M0.1 record in `tools/toolchain/pin/`. No target
platform was launched — a verified download is not a working build.

```sh
tools/ci/ci.sh pin                       # every pinned fact, as key=value lines
tools/ci/ci.sh pin --field release_archive_sha512
tools/ci/ci.sh verify-engine --archive <downloaded.zip>   # before extraction
tools/ci/ci.sh verify-engine --binary  <extracted binary>  # before execution
```

`verify-engine` resolves no engine, so it also runs on a host with no Godot
installed — which is exactly the state of a clean CI runner before the pinned
editor has been downloaded.

## The scratch copy

Engine runs use a fresh scratch project copy. Ordinary commands use
`tools/ci/out/project-copy/`; each export attempt uses a private
`tools/ci/out/attempts/<slug>-<attempt>/project-copy/` and matching
`tools/ci/out/logs/<slug>-<attempt>/` directory, so concurrent exports that
share one CI_OUT never delete/rebuild another's copy or truncate its engine
logs. This exists so:

- the shared checkout's `.godot/` import cache is never written by CI tooling;
- an independent reviewer can point the same commands at an immutable source
  snapshot with `--project <dir>` and get an isolated cache and output path
  (plan/IMPLEMENTATION.md requires exactly that for review checkpoints);
- `--in-place` opts out and runs the engine against the project itself. It
  warns, because it writes `.godot/`.

The copy excludes `.git/`, `.godot/`, `work/` and `./build/` (root CI export
output). Excluding `./build/` matters when several presets are built in one job:
without it each preset's scratch input would contain the packages built for
earlier presets, and `tools/ci/out/project-copy/` would carry them into every
upload of that directory.

Each export attempt's scratch copy keeps its tooling fingerprint at `<attempt project-copy>/.ci-tools-fingerprint`; two attempts sharing one CI_OUT therefore make independent reuse decisions. The copy is refreshed whenever the tooling itself changes (content fingerprint),
so `--reuse-copy` cannot run a stale copy of these scripts. The tooling is also
overlaid into the copy, so a project snapshot that carries an older or missing
`tools/ci/` still runs the code that is actually being tested.

`tools/ci/out/` is gitignored by `tools/ci/out/.gitignore` and holds only local
scratch: engine logs (`logs/`), one report per run (`reports/`; the
preset-specific name is a hard-link alias of the same per-attempt inode),
project copies, captures and exports. `validate` checks that no build output under it is
tracked; the directory's own `.gitignore` sentinel (the exact path
`tools/ci/out/.gitignore`) is the intended exception, and every other tracked
path there still fails.

## Commands

| Command | Purpose | Fails when |
| --- | --- | --- |
| `doctor [--display]` | Machine/engine/tooling report: engine version, sha256 of the binary, OS, CPU count, template directory, renderer, audio devices, connected gamepads, user-data paths (PLAN.md M0.6). `--display` runs with a real display driver to record the actual GPU. | the engine does not match the pin, or the runtime report errors. |
| `import [--in-place]` | Headless `--import` of the scratch copy (T01). | the engine exits nonzero, the log contains engine errors, or no `.godot/` cache is produced. |
| `validate` | Engine pin, project settings, resource/script scan, tooling self-check, tooling self-test, content-contract inventory (T01). | any of those fail. |
| `test [--list] [--filter S] [--require-tests]` | Runs the discovered headless checks and the exit-code proof (M0.4). | a check exits nonzero, no checks are discovered with `--require-tests`, or the exit-code proof fails. |
| `capture --check` | Capture readiness report: display availability, the project viewport size, `ffprobe` availability and available scenes. | the engine does not match the pin. |
| `capture --list` | Lists scenes usable as capture targets. | — |
| `capture --probe` | Runs a short deterministic capture of the first available scene to prove the pipeline. | the capture fails, produces no file, or records a resolution other than the requested one. |
| `capture --target <res://…> [--frames N] [--fps F] [--resolution WxH] [--name N]` | Deterministic AVI capture of one scene at a requested resolution. | the target does not exist, there is no display, an argument is malformed, the capture fails, or the recorded resolution differs from the requested one. |
| `export --check` | Export preparation: pin, installed export templates for the three required platforms, and `export_presets.cfg` coverage. | templates are missing, or presets are missing/incomplete. |
| `export --list-presets [names]` | Lists the declared export presets (`preset.N`, name, platform). | there is no `export_presets.cfg`. |
| `export --export <preset> --out <file> [--mode release|debug]` | Builds one preset into a local file. A relative `--out` is resolved against the caller's working directory (not Godot's `--path` scratch copy) before the engine sees it, using filesystem semantics (`..` after a symlink follows the target's parent). Destinations inside the reserved `.ci-lock` namespace are rejected case-insensitively before any Godot invocation (including the `--version` probe), because an output ending in `.ci-lock` would itself be another invocation's lock file; the main and derived sidecar paths are checked separately. The early guard mirrors `cmd_export` (subcommand first, then `--mode debug`/`--mode=debug`, then preset/`--out`), so every valid reserved destination is refused before any Godot invocation; an output path containing a literal newline is rejected outright rather than serialized through line-delimited request fields. The canonical checks run again on both the outer and direct `__export-inner` paths. An existing main output or sidecar `.pck` at that path is **refused**, never deleted, overwritten or silently reused as evidence for a new run. Overlapping main/sidecar destinations are serialized by persistent advisory lock FILES (`<destination>.ci-lock`). Locks are taken on descriptors held by the exporting shell itself via `flock` fd mode on Linux or `lockf` fd mode on macOS/BSD. The actual engine/writer child deliberately keeps those descriptors open: if the exporting shell is killed or signalled while Godot is still writing, the writer itself holds the destination lock until it exits, so a second export cannot enter beside a live writer. The timeout watchdog, by contrast, closes its inherited descriptors before sleeping, so an orphaned watchdog cannot prolong a finished export. A non-writing descendant spawned by the engine can conservatively keep the lock alive until it exits; that liveness limit is inherent to advisory locks tied to process trees. A live owner produces ci.sh's own structured verdict (`reason=lock-timeout`, `timed out after Ns waiting for lock ...`) rather than depending on tool-specific stderr; waits default to 900s (`CI_EXPORT_LOCK_WAIT`) and then fail closed. Lock-file bytes are never written, truncated or deleted by this tool; a pre-existing regular file at a lock path is preserved and merely locked. Keep lock files in place while any export may be active: removing or replacing one during a run can let another invocation lock a new inode and enter concurrently. A pre-existing symlink or non-regular path at the lock name is refused, never followed or removed. Each preset gets its own `export-<slug>-N-*.log` names; every run has a unique per-attempt id (mktemp-derived) shared by its report and its inventory report, so evidence cannot be confused across attempts. Report identities are reserved exclusively: a uniquely created temporary body is hard-linked into the final report name at the exact destination, atomically (`link(2)` through Python `os.link`, or `ln -T` on Linux). A regular file, dangling symlink, directory or symlink-to-directory occupant is refused without writing through or into it. The preset-specific report rename uses the same create-only hard-link publication (`ci_publish_report_exclusive`); if it cannot publish, or the attempt's report source is empty/missing/not a regular file, or the attempt id is empty, the export aborts before the engine writes. When the source still exists it records a structured `reason=report-publication-failed` verdict in the attempt's existing report. The identity is captured from a read descriptor held on the private temporary body before publication, and both the descriptor and the attempt id are handed to the nested worker; the held descriptor pins the inode so a later unlink-and-recreate replacement cannot reuse it. The reserved report must carry the attempt id as its exact first line. Every export verdict append is bound to that dev/inode via an isolated Python helper that opens `O_WRONLY|O_APPEND` without `O_CREAT`; a missing, deleted or same-header swapped report fails closed instead of being recreated or written through. On a host without usable Python the descriptor can still be held, but verdict lines cannot be appended: exports fail closed with the diagnostic on stderr rather than recreating an unlinked report, while `pin` continues to reserve reports through GNU/busybox `ln -T`. A hostile path swap after the final append is checked once more before any success line; only a narrow swap between the last check and the write itself remains inherently racy. The package-inventory interpreter is probed with `-I` (and the real checker runs with the same flag), before locks, scratch preparation or any writer. Inventory identities are never pre-created or pre-checked by this wrapper: the checker creates its `--report` exclusively with `O_EXCL`, and the wrapper validates that attributable PASS evidence afterward, so an occupied path fails closed and a checker that dies or loses the reservation can never borrow an earlier PASS. The inventory report name also includes the source SHA when `--source-sha` is supplied. The actual report header carries `attempt-id:` and the full `source-sha:` value; failure paths record their distinct verdict and print the report location. `tools/export_smoke/lib/pack_inventory.py check` re-reads the produced package; `PASS`/`export result=pass` are emitted only after the inventory succeeds, so a rejected package has exactly one failing verdict. On failure the full captured engine log is printed via `ci_print_export_failure_log`, because Godot's configuration-error reasons are multi-line and indented; both nonzero-exit and exit-0-but-engine-error paths print the complete indented transcript. | presets are missing, the preset is unknown, the output or sidecar already exists, the destination is inside the reserved `.ci-lock` namespace, the destination lock is held (wait timeout), neither `flock(1)` nor `lockf(1)` is available, the preset-specific report cannot be published exclusively, the report source lacks the exact first-line attempt header or its inode cannot be bound, python3 is missing or unusable for the package inventory, the lock path is a symlink/non-regular pre-existing path, the export fails, no file is produced, the pack-inventory check fails, or python3/the inventory tool is unavailable. |
| `verify-engine --archive <file> [--binary <file>]` | Compares a downloaded release archive, and optionally the extracted editor binary, against the pinned publisher digest in `pin/engine.txt`. Resolves no engine, so it also runs on a host with none installed. | a digest does not match, a pinned digest is missing, or the file cannot be read (exit 1, before anything is extracted or executed). |
| `install-templates --archive <file> --dest <dir> [--mode release\|debug]` | Verifies the export-template archive against the pinned publisher digest BEFORE extraction, locates its payload by `version.txt` (the official `.tpz` packages `templates/*` at the archive root, not a `<version>.stable/` directory), validates that version, checks the staged tree against this project's presets, and only then installs it as `<dir>/<version>.stable`. Refuses to replace an existing target directory rather than deleting an installed template tree; remove it explicitly to reinstall. Resolves no engine. | the digest does not match, `<dir>/<version>.stable` already exists, `version.txt` is missing or names another version, the required template files are absent/empty, or the destination cannot be written. Nothing is placed in or removed from `<dir>` on failure. |
| `pin [--field <name>]` | Prints the pinned engine facts (tag, version, official URLs, pinned digests) as `key=value` lines. One source of truth for the workflow. | a requested digest field is not recorded. |
| `all` | `import` + `validate` + `test` on one shared scratch copy. This is the CI check set. | any of them fail. |
| `version` | Prints the pinned and detected engine versions. | — |

Global options: `--project`, `--godot`, `--out`, `--in-place`, `--reuse-copy`,
`--strict-contracts`, `--timeout`, `--source-sha`, `--no-color`, `--help`.

**Exit codes.** `0` = passed, `1` = a check failed, `2` = the command could not
run at all (usage error, missing tool, bad path). A check that cannot run is
never reported as a pass.

## What each check actually verifies

`validate` runs three engine-backed checks plus two local ones:

1. **Engine pin** (`pin/engine.txt`, or the M0.1 record in
   `tools/toolchain/pin/engine.txt` when the project has it — the toolchain file
   wins so the two cannot drift apart): the installed engine's major/minor/patch
   must match; the pinned build string and upstream-verification status are
   reported; installed export templates must match the pinned version.
2. **Project settings** (`scripts/check_settings.gd`): the main scene exists,
   `application/config/features` matches the pinned major.minor, the renderer is
   one of the allowed methods, physics runs at 60 ticks/second with
   interpolation on, and the window target is 1920×1080 — the invariants stated
   in docs/TECHNICAL_DESIGN.md. Change a value deliberately and update the check
   in the same change; do not weaken it to make CI green.
3. **Resource and script scan** (`scripts/scan_project.gd`): every `.gd` under
   `res://` compiles (reloaded and checked, because `load()` returns a GDScript
   object even for a script that fails to parse), every `.tscn`/`.tres` loads
   and every scene instantiates, every declared `[ext_resource]` path exists, no
   two scripts declare the same global `class_name`, and every script has a
   `.uid` sidecar (warning). Directories that contain their own `project.godot`
   are skipped and reported, because the engine does not import them into this
   project either.
4. **Tooling self-check**: the entry points are executable, the data files are
   present, and no build output under `tools/ci/out` is tracked by Git (the
   directory's own `.gitignore` sentinel is the intended exception).
5. **Tooling self-test** (`tests/run_tests.sh`): the tooling's own shell layer —
   pin parsing, digest comparison, the capture viewport override, the
   recorded-resolution probe, the argument validation, and the engine-log gates
   (error shapes, warning counting, the accepted-warning list, the strict and
   Jolt warning behaviour). Hermetic: no network and no display; the
   engine-backed export cases run only when a matching Godot and the pinned
   templates are installed, and every other case uses synthetic fixtures. The
   tracked-output cases create their own throwaway Git repository and index in
   the private temporary directory rather than reading the checkout's index.
   Both directions are covered, so a check that stops checking fails the suite
   instead of passing silently.

   The suite also proves same-second report names stay distinct, an existing
   output/sidecar/dangling symlink is refused byte-for-byte rather than reused,
   a rejected package leaves exactly one failing verdict, and overlapping
   destination invocations serialize instead of claiming each other's bytes.

   Hosted coverage: `ci_tooling_selftest` forwards `GODOT_BIN`, so the runner's
   digest-verified editor is used for the engine-backed `export --check` cases.
   The export job additionally runs the full self-test after its verified
   template installation and FAILS if the template-dependent sidecar,
   relative-path, symlink, refusal or corrupted-package cases would skip.
   `actionlint` and `ffmpeg` are not installed on the runner, so the workflow
   lint case and the positive capture probe skip there; both run locally.
5. **Content-contract inventory** (`contracts.list`): reports which planned
   content paths exist. This is an **inventory, not validation** — content
   validation (T09/T15) is not implemented and is not claimed. Entries marked
   `required` must exist; `pending` entries are warnings until
   `validate --strict-contracts` is used at a milestone gate.

Every engine invocation is additionally gated on its captured log: the pinned
engine **exits 0** even when a script fails to compile or a scene references a
missing resource, so `ci_log_gate` fails the run when the log contains
`ERROR:`/`SCRIPT ERROR:`/`FATAL:`/`USER ERROR:` lines, or one starting with
`Failed to load script` or `Parse Error`. That behaviour was measured against
4.7.2 while building this tooling; the extra shapes were added for parity with
the supported smoke wrapper (finding N1).

### The `test` stage judges the log as well as the exit code

`ci_run_one_test` uses three independent signals, because the pinned engine
exits 0 for a script that throws at runtime — an exception inside `_ready()`
leaves the shell running, so the exit status alone reports a pass. That is Opus
recheck finding N1: CI ran `tools/smoke/boot_smoke.gd` directly with `--script`,
judged only the exit status, and passed a tree where the supported wrapper
`tools/smoke/run_boot_smoke.sh` failed.

1. **the exit status** — as before;
2. **engine error lines in the captured log**, using the same shapes the wrapper
   documents (`SCRIPT ERROR`, `Failed to load script`, `Parse Error`, `ERROR:`,
   `USER ERROR:`). A check that exits 0 while the engine reported an error line
   fails with `reason=engine-errors`;
3. **Jolt physics warnings**, which mean the physics step ignored contacts or
   fell back to a slower allocator — see *Engine warnings* below.

`tools/ci/scripts/runtime_error_gate.sh` proves these signals on every run: it
injects a missing dictionary key, a `push_error()` and a Jolt warning into
throwaway snapshot copies and requires `ci.sh test` to exit nonzero for each.
See *The runtime-error gate* below.

There is deliberately **no allow-list for error lines**: an engine error line
fails the check, because the shapes it matches are the ones the supported
wrapper fails on and none of them is expected output from a healthy run. A
warning is a different matter — see the next section.

The exit-code proof is unchanged and still runs on every pass: a deliberately
failing probe must exit nonzero (PLAN.md M0.4).

### Engine warnings

`WARNING:` lines are **surfaced and counted on every run** — printed, never
filtered — because the open R7 item is exactly a warning that used to pass
unnoticed. Three levels:

| situation | behaviour |
| --- | --- |
| any warning | printed, and counted in the report as `warnings=` / `unexpected_warnings=` |
| a warning the project has accepted, listed in `tools/ci/warnings.allow` | printed and labelled `(N accepted in warnings.allow)`; never fatal, even with `--strict-warnings` |
| an unexpected warning | not fatal by default; fatal with `--strict-warnings` (or `CI_STRICT_WARNINGS=1`) |
| a warning matching one of the five pinned-engine **Jolt physics** messages | **fatal**: every one means contacts were ignored or a slower allocator was used, so a run that printed one is not a clean pass. A warning that merely mentions "jolt" (for example a nested-project path such as `res://tools/jolt_inventory`) is reported, not failed |

Strict warnings are opt-in because a warning is not an error, and failing a check
for a warning the project has not decided about would be failing for the wrong
reason. The acceptance list is the supported escape hatch, and it records the
decision instead of hiding the output.

## Test discovery

`test` discovers headless checks in `tests/**` and `tools/smoke/**` (every
`.gd` file), in sorted order, and runs each with
`godot --headless --path <scratch copy> --script res://…`.

A test is a `SceneTree` script that prints its own result and calls `quit(0)` on
success or `quit(nonzero)` on failure — the same shape as the existing
`tools/smoke/boot_smoke.gd`. Optional directives in the first 30 lines:

```gdscript
## ci-runner: scene     # run with --scene instead of --script (default: script)
## ci-timeout: 60       # per-check wall-clock limit in seconds
```

`tests/` does not exist yet, so `test` currently runs the existing smoke runner
and reports that no further checks are discovered. It never invents a pass.

### The runtime-error gate

`tools/ci/scripts/runtime_error_gate.sh` is the regression proof for these
signals, and for the warning handling. It is engine-backed but needs no
network, no Git and no display, and it runs entirely against throwaway snapshot
copies of the checkout (no `.git`, no `.godot`, no `work/`, no previous
`tools/ci/out`) in a private temporary directory with its own `HOME`, `TMPDIR`
and XDG tree. Every case checks the **actual exit status** of `ci.sh test`, and
the failure reason is asserted too, so a case cannot pass for an unrelated
reason:

| case | injected defect | expected `ci.sh test` exit |
| --- | --- | --- |
| clean snapshot | — | 0, and the exit-code proof still ran |
| missing dictionary key in `_ready()` | `get_node_or_null("NoSuchNode")["missing_key"]` | 1 |
| `push_error()` in `_ready()` | `push_error("…")` | 1 |
| `push_warning()` in `_ready()` | `push_warning("…")` | 0, **and the warning is printed** |
| `push_warning()` with `--strict-warnings` | `push_warning("…")` | 1 |
| a Jolt physics warning | the real `Jolt Physics job system exceeded …` message | 1 |

Both injected runtime errors are deliberate: the script still parses, the scene
still loads, the boot handoff still completes and the engine exits 0, so only
the log shows them. The `push_warning()` cases are the negative control — they
show the gate fails on engine errors rather than on any stderr output.

Isolation is verified, not assumed: fingerprints of `src/boot/`, `scenes/` and
`project.godot` are taken before and after, and the harness fails if anything in
the live checkout changed or if a `.godot/` cache appeared in it. Runs are
bounded twice over — `--timeout` per engine invocation and a wall-clock watchdog
per case.

```sh
tools/ci/scripts/runtime_error_gate.sh
GODOT_BIN=/path/to/godot tools/ci/scripts/runtime_error_gate.sh
GATE_TARGET_SCRIPT=src/boot/main_menu.gd tools/ci/scripts/runtime_error_gate.sh
GATE_TIMEOUT=180 GATE_CASE_TIMEOUT=1200 tools/ci/scripts/runtime_error_gate.sh
```

Exit codes: 0 = every case behaved as expected, 1 = a case misbehaved, 2 = the
harness could not run.

### The exit-code proof

PLAN.md M0.4 requires that a deliberately failing test returns a failing exit
code. `test` proves this on every run by executing
`scripts/expect_failure_probe.gd`, which exits `3`, and requiring a nonzero
status. It also runs `tools/smoke/boot_smoke.gd -- --expect-failure` when that
file still advertises the flag. If a failing check ever exits `0`, `test` fails
with an explicit message instead of reporting success.

## Capture

`capture` drives Godot's movie writer deterministically:
`--write-movie <file> --fixed-fps <fps> --quit-after <frames> --resolution WxH`
(`--write-movie` forces fixed FPS; `--quit-after` bounds the run). Output goes to
`tools/ci/out/captures/<name>-<UTC timestamp>.avi`.

Verified here: a 6-frame 640×360 capture of `res://scenes/boot.tscn` produced a
283 KB AVI. PNG sequence output was **not** reproduced with the pinned editor and
is deliberately not offered.

### The requested resolution is the recorded resolution

Measured against the pinned engine (4.7.2.stable): Godot's movie writer records
the **project viewport size**, while `--resolution` only requests a *window* size.
Passing `--resolution 960x540` alone therefore still records a 1920×1080 movie —
exactly the defect recorded in `docs/MACHINE_INVENTORY.md` (§8 checks 13–14,
§10 item 9).

`capture` now closes that gap instead of only reporting it:

1. it reads the scratch copy's viewport size and, when it differs from the
   requested resolution, rewrites `window/size/viewport_width|height` in the
   **scratch copy's** `project.godot` — the shared checkout is never touched;
2. it records the movie;
3. it probes the recorded stream with `ffprobe` and **fails** when the recorded
   size is not the requested size. Without `ffprobe` the size is reported as
   *unverified* rather than assumed correct.

Verified here with the pinned engine on this host: `--resolution 960x540` records
a 960×540 AVI (581,820 bytes, 20 frames), `--resolution 640x360` records
640×360, and `--resolution 1920x1080` records 1920×1080 with no override.
Disabling the viewport override makes the check fail with
`capture recorded 1920x1080 but 960x540 was requested`.

`--frames 0` is rejected: `--quit-after 0` tells Godot never to quit, which would
turn a bounded probe into an unbounded one.

No capture stage is authored yet (PLAN.md M2.6/M5.5), so `--target` must name an
existing scene; `capture --list` shows them. Capture needs a rendering display
driver: on Linux it requires `DISPLAY` or `WAYLAND_DISPLAY`, and
`capture --check` reports the limitation instead of claiming a capture.

## Export preparation

`export --check` verifies the pin, the installed export templates for the three
required platforms (macOS Apple Silicon, Windows x86-64, Linux x86-64 per
docs/TECHNICAL_DESIGN.md), and that `export_presets.cfg` declares a preset for
each of them.

The requirement names are the plan's; the preset values are Godot's, and they
differ: the Windows desktop target is `platform="Windows Desktop"` in
`export_presets.cfg`, not `platform="Windows"` ("Windows" names the template
files and the platform list). `ci_preset_platform_for` in `lib/common.sh` holds
that mapping, so a covered target is never reported as missing — and a preset
written with a value Godot does not use (`platform="Windows"`, a missing
`platform=` line, a dropped preset) still fails the check. The mapping and the
coverage decision are pinned by regression cases in `tests/run_tests.sh`.

The presets in this checkout are honest M0 placeholders: ad-hoc signed,
unnotarized, and cross-exported (only the macOS package is launched here).
`export --check` passing means the presets and templates are in place, nothing
more.

A successful `--export` produces a **local package**, not a verified release:
launching it on each target OS (M9.2) and signing/notarization (M9.3) are
separate steps that this tooling does not perform.

## What this tooling does not do

Stated plainly, so nothing here is mistaken for a completed gate:

- **No content validation.** Course geometry, asset provenance, license notices
  and manifest completeness (T09/T15) are not implemented. `validate` reports an
  inventory of planned paths only.
- **No gameplay, race, AI or performance testing.** There is no motor, track, AI
  or race content to test yet (M1+).
- **No release export verification.** Templates and presets can be checked and a
  package can be built; nothing here launches a package on Windows or Linux.
- **No headless rendering, audio or input verification.** Headless runs use the
  dummy display/audio drivers; `doctor --display` records the real GPU on a
  machine with a display, and real controllers still require a human session
  (M3).
- **No cross-platform physics determinism.** Seeded checks help reproduction;
  docs/TECHNICAL_DESIGN.md requires tolerances rather than exact cross-host
  equality.
- **No download or install by the checks themselves.** `ci.sh` reads local files;
  it never fetches an engine. The CI workflow downloads the official release
  asset on runners that do not provide `GODOT_BIN`, and `ci.sh verify-engine`
  compares that archive against the pinned publisher digest **before** extraction
  and the extracted binary **before** execution (PLAN.md M0.1). The pinned
  version, the official URL and the digests live in `tools/ci/pin/engine.txt`
  (`ci.sh pin`); the installed-toolchain digests stay in `tools/toolchain/pin/`,
  because a digest recorded on one host for an installed file is not a portable
  expectation, while a published release archive is.

## Relationship to the other tooling

| Path | Owner | Relationship |
| --- | --- | --- |
| `tools/smoke/` | shell job (M0.2/M0.4) | The existing headless boot smoke runner. `ci.sh test` runs it and its `--expect-failure` flag. |
| `tools/toolchain/` | M0.1 inventory | Authoritative engine **version** pin, local installed-file digests and `verify.sh`. `ci.sh` reads its version fields when present and never re-records its digests; the release-artifact block always comes from `tools/ci/pin/engine.txt`. |
| `tools/asset_manifest/` | provenance job | Asset manifest validator. CI runs `validate_manifest.py` as the asset-validation step; its own suite is `run_tests.sh`. |
| `tools/tick_probe/` | M0.8 feasibility | A separate nested Godot project (`tools/tick_probe/project.godot`). The engine does not import it into this project, so the scan skips and reports it. |

## CI

`.github/workflows/ci.yml` runs on pushes to `main`, pull requests and manual
dispatches, from a clean checkout with no editor interaction and no
generation-service account:

- **checks** — resolve the pinned engine (`GODOT_BIN` when the runner has one,
  otherwise the official release asset for the pinned tag, **verified against the
  pinned publisher digest before extraction and before execution**), then
  `doctor`, `import`, `validate` (which includes the tooling self-test), `test`
  (exit-code proof **and** the engine-error gate), the runtime-error gate
  regression, a warning watch that surfaces every `WARNING:` line in the run
  summary and fails on a Jolt physics warning, asset manifest validation, and a
  report-only `capture --check` (a GitHub-hosted runner has no display). Logs and
  reports are uploaded as an artifact.
- **content-contracts** — non-blocking inventory of planned content paths, with
  the strict result written to the run summary. It is not a validation and is
  labelled as such in the job name and output.
- **export-preparation** — always runs (there is no job-level condition); if
  `export_presets.cfg` is absent, `export --check` fails clearly. Otherwise it
  prepares and verifies templates, runs `export --check`, runs the tooling
  self-test against the installed templates, and builds each declared preset
  with a platform-appropriate output extension.
  Logs and per-preset reports/inventories upload under `if: always()`; the
  built-package artifact uploads only when every prior step succeeded, so a
  failed or inventory-rejected build cannot be published as a successful set.
- **contract-suites** — a separate headless job that runs the standard-library
  contract suites on the exact checked-out candidate: `schemas/handling`,
  `fixtures/{observation,intent,scenario}` and `tools/python_pin/tests`. It
  needs no Godot editor, templates or generation-service accounts; `bash`
  and `python3` are prerequisites with explicit failures if absent. Each suite
  runs with private `TMPDIR`/`HOME`/`XDG_*` roots and bytecode writing off, a
  missing suite is an error rather than a skip, and any nonzero suite status
  fails the job (all suites still run, with per-suite PASS/FAIL labels in the
  step summary).

Provenance: `--source-sha` is recorded in every run report and in export
inventory filenames. In CI it is `github.sha`, which on `pull_request` is
Actions' synthetic merge commit -- the exact tree that was checked out and
tested, but not necessarily the PR head SHA.

The pinned engine version is `4.7.2-stable`; the official archive at
<https://godotengine.org/download/archive/> is the version authority. The URL, the
tag and the pinned digests are read from `tools/ci/pin/engine.txt` through
`ci.sh pin`, so this workflow never carries a second copy of them.

Reproduce the workflow's engine verification locally:

```sh
curl -fsSL -o /tmp/godot.zip "$(tools/ci/ci.sh pin --field release_archive_url)"
tools/ci/ci.sh verify-engine --archive /tmp/godot.zip                        # before extraction
unzip -q /tmp/godot.zip -d /tmp/godot
tools/ci/ci.sh verify-engine --binary /tmp/godot/Godot_v4.7.2-stable_linux.x86_64  # before execution
```

## Layout

```text
tools/ci/
  ci.sh                 entry point and command implementations
  lib/common.sh         POSIX shell helpers (logging, Godot discovery, pin,
                        scratch copy, log gating, warnings, reports)
  pin/engine.txt        fallback engine pin (the M0.1 record wins when present)
  warnings.allow        engine warnings the project has accepted (still printed)
  contracts.list        planned content paths for the inventory
  tests/
    run_tests.sh          hermetic self-test for the tooling's shell layer
  scripts/
    check_settings.gd     project-settings invariants
    scan_project.gd       resource/script scan
    environment_report.gd machine/engine/device report
    expect_failure_probe.gd  deliberate failure for the exit-code proof
    runtime_error_gate.sh runtime-error and warning regression for `ci.sh test`
  out/                  gitignored local scratch (logs, reports, copies, output)
```
