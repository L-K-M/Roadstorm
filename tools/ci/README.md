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
| Godot editor | **4.7.2 Standard**, the version pinned in `pin/engine.txt` (PLAN.md M0.1). Found via `$GODOT_BIN`, then `godot`/`godot4`/`Godot` on `PATH`, then common install locations. |
| Shell | Any POSIX `/bin/sh` (dash, bash, ash, busybox). No bashisms; verified under `dash`. |
| Everything else | `tar`, `grep`, `sed`, `awk`, `find`, `sort`, `head`, `date`, `uname`. Python is **not** required by this tooling. |

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

Every engine run happens in `tools/ci/out/project-copy/`, a fresh copy of the
project, so:

- the shared checkout's `.godot/` import cache is never written by CI tooling;
- an independent reviewer can point the same commands at an immutable source
  snapshot with `--project <dir>` and get an isolated cache and output path
  (plan/IMPLEMENTATION.md requires exactly that for review checkpoints);
- `--in-place` opts out and runs the engine against the project itself. It
  warns, because it writes `.godot/`.

The copy is refreshed whenever the tooling itself changes (content fingerprint),
so `--reuse-copy` cannot run a stale copy of these scripts. The tooling is also
overlaid into the copy, so a project snapshot that carries an older or missing
`tools/ci/` still runs the code that is actually being tested.

`tools/ci/out/` is gitignored by `tools/ci/out/.gitignore` and holds only local
scratch: engine logs (`logs/`), one report per run (`reports/`), project copies,
captures and exports. `validate` checks that nothing under it is tracked.

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
| `export --export <preset> --out <file> [--mode release|debug]` | Builds one preset into a local file. | presets are missing, the preset is unknown, the export fails, or no file is produced. |
| `verify-engine --archive <file> [--binary <file>]` | Compares a downloaded release archive, and optionally the extracted editor binary, against the pinned publisher digest in `pin/engine.txt`. Resolves no engine, so it also runs on a host with none installed. | a digest does not match, a pinned digest is missing, or the file cannot be read (exit 1, before anything is extracted or executed). |
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
   present, and nothing under `tools/ci/out` is tracked by Git.
5. **Tooling self-test** (`tests/run_tests.sh`): the tooling's own shell layer —
   pin parsing, digest comparison, the capture viewport override, the
   recorded-resolution probe and the argument validation. Hermetic: no network,
   no engine, no display, no Git. Both directions are covered, so a check that
   stops checking fails the suite instead of passing silently.
5. **Content-contract inventory** (`contracts.list`): reports which planned
   content paths exist. This is an **inventory, not validation** — content
   validation (T09/T15) is not implemented and is not claimed. Entries marked
   `required` must exist; `pending` entries are warnings until
   `validate --strict-contracts` is used at a milestone gate.

Every engine invocation is additionally gated on its captured log: the pinned
engine **exits 0** even when a script fails to compile or a scene references a
missing resource, so `ci_log_gate` fails the run when the log contains
`ERROR:`/`SCRIPT ERROR:`/`FATAL:` lines. That behaviour was measured against
4.7.2 while building this tooling.

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

**There is no `export_presets.cfg` in this checkout**, so `export --check` fails
with the remediation text, and `export --list-presets`/`--export` refuse to run.
That is deliberate: native export preparation is not implemented yet
(PLAN.md M0.5/M9.1), and this tooling will not claim an export it cannot
perform. Add the presets, then re-run the check.

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
  `doctor`, `import`, `validate` (which includes the tooling self-test), `test`,
  asset manifest validation, and a report-only `capture --check` (a GitHub-hosted
  runner has no display). Logs and reports are uploaded as an artifact.
- **content-contracts** — non-blocking inventory of planned content paths, with
  the strict result written to the run summary. It is not a validation and is
  labelled as such in the job name and output.
- **export-preparation** — skipped until `export_presets.cfg` exists (there is
  nothing to prepare without it); when presets land it runs `export --check` and
  builds each declared preset with a platform-appropriate output extension.

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
                        scratch copy, log gating, reports)
  pin/engine.txt        fallback engine pin (the M0.1 record wins when present)
  contracts.list        planned content paths for the inventory
  tests/
    run_tests.sh          hermetic self-test for the tooling's shell layer
  scripts/
    check_settings.gd     project-settings invariants
    scan_project.gd       resource/script scan
    environment_report.gd machine/engine/device report
    expect_failure_probe.gd  deliberate failure for the exit-code proof
  out/                  gitignored local scratch (logs, reports, copies, output)
```
