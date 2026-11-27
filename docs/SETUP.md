# Setup guide for a second developer (PLAN.md M0 acceptance)

This guide takes a second developer from a clean checkout of commit
`04015cada50ee6c24c36e51378807b8aaa32d38f` ("Fix native Windows manifest test
portability", tree `d7b82cf5ebd480348ce2a11038200d6301a4cf72`) through the pinned
toolchain, a headless import, a passing boot check, a deliberately failing check,
and a desktop cross-export smoke build.

It describes **committed state only**. Other owners may have uncommitted CI,
export-smoke or tick-probe edits in the shared checkout; those are not part of
this baseline. [STATUS.md](STATUS.md) is the fast-moving record and is
authoritative for open gates, review verdicts and recent runs.

**No milestone is accepted.** M0 is in progress. This exercise verifies the
tooling and an honest placeholder shell, not gameplay and not final M0. A green
local run is not M0 acceptance.

## 1. Prerequisites

| Need | Exact requirement |
| --- | --- |
| Engine | Godot **4.7.2 Standard**; `godot --headless --version` prints `4.7.2.stable.official.ed1daf0bf` |
| Export templates | `4.7.2.stable` in the engine's own user-data directory, not `$GODOT_TEMPLATES_DIR` |
| 3D physics | built-in **Jolt**, set explicitly as `physics/3d/physics_engine="Jolt Physics"` in `project.godot` (`DEFAULT` is not accepted) |
| Renderer | `gl_compatibility`, provisional until M3 |
| Asset Python | CPython **3.15.2** exact for asset generation |
| Shell / tools | POSIX `/bin/sh` (dash-compatible), `tar`, `grep`, `sed`, `awk`, `find`, `sort`, `head`, `dirname`, `mktemp`, `date`, `uname`, and `shasum` or `sha256sum` |
| Optional | `curl` and `unzip` for downloads/install, `ffprobe` to verify capture resolution |
| Python 3 | Not required by `tools/ci/**` itself. `tools/ci/scripts/runtime_error_gate.sh` needs `python3` and exits 2 without it; the contract suites need `bash` and `python3` |

Exit codes are the same across the project tooling: `0` passed, `1` a check
failed, `2` the command could not run. A check that cannot run is never reported
as a pass.

Host limits: the only launch evidence is Apple Silicon macOS (macOS 27.0.1, M4
Max); see [MACHINE_INVENTORY.md](MACHINE_INVENTORY.md). There is no Windows or
Linux host, so those packages are cross-exports only. No gamepad or audio-input
device is available here.

The version authority is the official archive at
<https://godotengine.org/download/archive/>; the pinned release is the GitHub
tag `4.7.2-stable`. Do not track a moving "stable" download.

## 2. Get the code and install the pin

```sh
git clone <repository-url> Roadstorm && cd Roadstorm
git checkout 04015cada50ee6c24c36e51378807b8aaa32d38f
git rev-parse HEAD^{tree}          # d7b82cf5ebd480348ce2a11038200d6301a4cf72
```

Verify the installed editor and templates:

```sh
godot --headless --version         # expect 4.7.2.stable.official.ed1daf0bf
tools/toolchain/verify.sh           # version + local digests + templates
tools/toolchain/verify.sh --deep   # also runs the macOS template binary and checks Jolt strings
tools/python_pin/verify.sh         # local interpreter(s) vs the pin
tools/ci/ci.sh pin                 # every pinned fact as key=value lines
tools/ci/ci.sh version             # pinned vs detected engine version
```

Install the editor either with Homebrew cask `godot` 4.7.2 (which fetches the
official macOS asset) or from the official archive named in
`tools/toolchain/pin/engine.txt`. Do not install the Mono editor. Set
`GODOT_BIN=/path/to/godot` when the editor is not on `PATH`; `ci.sh` also takes
`--godot <path>`, and `tools/smoke/run_boot_smoke.sh` accepts
`--project <dir>` for another checkout or snapshot. Verify a
downloaded archive before extraction: `ci.sh verify-engine --archive <file>`
checks the pinned Linux x86-64 release archive against the publisher digest;
the macOS editor ZIP's publisher SHA-512 is recorded in
[docs/evidence/godot-4.7.2-archive-verification.md](evidence/godot-4.7.2-archive-verification.md).

Install the export templates where the engine reads them. The archive digest is
verified before extraction, the payload is located by its `version.txt`, the
staged tree is checked against this project's presets, and an existing
`<dest>/<version>.stable` is refused, never replaced:

```sh
# Private scratch directory; mktemp -d makes the download target unique.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/roadstorm-setup.XXXXXX")"
archive="$scratch/godot-export-templates.tpz"
curl -fsSL --retry 3 --connect-timeout 30 --max-time 1800 \
  -o "$archive" "$(tools/ci/ci.sh pin --field templates_url)"

tools/ci/ci.sh verify-templates --archive "$archive"
tools/ci/ci.sh install-templates --archive "$archive" \
  --dest "$HOME/Library/Application Support/Godot/export_templates" --mode release
tools/ci/ci.sh verify-templates \
  --dir "$HOME/Library/Application Support/Godot/export_templates" --mode release
```

On Linux use `--dest "$HOME/.local/share/godot/export_templates"`.
`install-templates` resolves no engine, so it runs on a host with no Godot
installed.

Python provenance: the four python.org 3.15.2 artifacts were digest-matched and
Sigstore-verified on 2026-11-27; that authenticates publisher artifact bytes
only. The locally installed Homebrew 3.15.2 is not publisher-authenticated.
`tools/python_pin/pin/python.txt` keeps the two scopes apart in dated fields;
see [PYTHON_TOOLCHAIN_EVIDENCE.md](PYTHON_TOOLCHAIN_EVIDENCE.md).

## 3. Import

```sh
tools/ci/ci.sh import            # headless --import of tools/ci/out/project-copy/
```

Direct engine use also works but writes the gitignored `.godot/` cache into the
checkout:

```sh
godot --headless --path . --import
```

Every engine run is gated on its captured log: the pinned engine exits 0 even
when a script fails to compile, so the tooling fails the run when the log
contains error shapes such as `ERROR:`, `SCRIPT ERROR:`, `FATAL:`,
`USER ERROR:` or `Parse Error`. Logs and one report per run land under
`tools/ci/out/` (gitignored).

Useful neighbours: `tools/ci/ci.sh doctor` (machine/engine report;
`--display` records the real GPU on a machine with a display) and
`tools/ci/ci.sh capture --check` (capture readiness, report only).

## 4. Boot check, passing test and deliberate failure

```sh
tools/ci/ci.sh validate           # pin, settings, resource/script scan, self-tests, contracts
tools/ci/ci.sh test               # discovered headless checks + exit-code proof
tools/ci/ci.sh test --list        # what would run
tools/ci/ci.sh all                # import + validate + test (the CI check set)
tools/smoke/run_boot_smoke.sh     # the supported boot smoke entry point
```

`tools/smoke/run_boot_smoke.sh` is the supported wrapper: it checks the exact
pinned version, runs `res://tools/smoke/boot_smoke.gd` headless, and fails if
the check exits nonzero **or** the engine log reports a script error. At this
baseline `test` discovers exactly one check
(`res://tools/smoke/boot_smoke.gd`); `tests/` does not exist yet, and the
tooling reports that instead of inventing a pass. `validate` also prints the
content-contract inventory, which is an **inventory, not validation**:
game-content validation (T09/T15) is not implemented.

PLAN.md M0.4 requires a deliberately failing test to return a failing exit code.
Two ways to see it:

```sh
tools/smoke/run_boot_smoke.sh --expect-failure
echo $?        # 1
```

Inside `ci.sh test`, the exit-code proof runs on **every** invocation:
`tools/ci/scripts/expect_failure_probe.gd` exits `3`, and
`tools/smoke/boot_smoke.gd -- --expect-failure` exits `1`; the run fails if
either exits 0. Each discovered check is judged on its exit status **and** on
its captured engine log, so a runtime error that leaves the engine running
(exit 0) fails the check.

`tools/smoke/fault_injection.sh` injects eight isolated faults into throwaway
snapshot copies (clean, control, parse error, two runtime errors, detached
script, absent physics setting, misspelled physics setting) and verifies each
expected exit status. `tools/ci/scripts/runtime_error_gate.sh` proves the
log-based gate with missing-key, `push_error()`, `push_warning()` and Jolt
warning cases. Both run only in private temporary directories and verify the
live tree is unchanged.

Other committed checks worth knowing:

```sh
tools/asset_manifest/run_tests.sh
python3 tools/asset_manifest/validate_manifest.py
tools/ci/tests/run_tests.sh
```

## 5. Desktop cross-export

Preparation and a single local package through `ci.sh`:

```sh
tools/ci/ci.sh export --check
tools/ci/ci.sh export --list-presets
tools/ci/ci.sh export --export "Linux x86-64" --out build/Roadstorm-Linux-x86_64
```

`--export` takes the preset **name**, not the platform value. A relative
`--out` is resolved against the caller's working directory. An existing main
output or sidecar `.pck` is refused, never overwritten; overlapping destinations
are serialized with advisory locks. The exported package is checked by
`tools/export_smoke/lib/pack_inventory.py` before `ci.sh` reports success.

| Preset | Name (`--export` argument) | `platform=` in `export_presets.cfg` |
| --- | --- | --- |
| `preset.0` | `macOS Apple Silicon` | `macOS` |
| `preset.1` | `Windows x86-64` | `Windows Desktop` |
| `preset.2` | `Linux x86-64` | `Linux` |

The export smoke wrapper builds from a **frozen** candidate (`git archive HEAD`
plus only the owned `export_presets.cfg`), exports the requested platforms,
checksums every component including the `.pck`, re-reads the packaged `res://`
tree, and launches the macOS package on this host when macOS is requested:

```sh
# All three committed desktop targets; --out must not already exist.
tools/export_smoke/run_export_smoke.sh --out work/agents/<id>/outputs

# A single target:
tools/export_smoke/run_export_smoke.sh --platform Linux --out work/agents/<id>/linux

# Headless macOS launch only, for an already-exported package:
tools/export_smoke/launch_macos_app.sh --app /path/Roadstorm-macOS-universal.zip \
  --out /tmp/rs-mac --skip-windowed
```

Without `--out`, the runner reserves a fresh directory under
`work/agents/export-smoke/outputs/run.XXXXXX`. Exit codes: `0` every requested
platform exported (macOS launched), `1` a platform blocked/failed or an
inventory check failed, `2` the tool could not run. The engine must be the
pinned version string.

### Local cross-export is not a target launch

| Action | What it proves | What it does not prove |
| --- | --- | --- |
| `ci.sh export` / `run_export_smoke.sh` for Windows or Linux | The preset and templates produce a byte-checksummed package with a complete `.pck` | Anything about running on Windows or Linux. No target host exists; neither package is launched anywhere. A successful export never verifies a platform (M0/M9.2). |
| `run_export_smoke.sh` macOS package | The package inventory and checksums pass, and on this host the package launches | A verified release. The package is ad-hoc signed and **unnotarized**; Gatekeeper rejects it. Intel/x86_64 slice is untested. |
| `--launch-probe full` | Additionally opens the GUI briefly and takes a screenshot | Nothing about target hardware. It is opt-in and needs the machine's desktop coordination. The default probe is `headless` and opens no window. |

`--diagnostic-enable-etc2-astc` patches only the throwaway snapshot copy to work
around the universal/arm64 macOS `import_etc2_astc` refusal on older snapshots;
it is diagnostic only and never modifies the tracked `project.godot`. The
committed `project.godot` sets `rendering/textures/vram_compression/import_etc2_astc=true`,
so a normal export works without the flag.

## 6. Licenses and rights

- Root [LICENSE](../LICENSE) is the Unlicense and is retained unchanged; it
  covers original code, tools, tests, schemas and documentation.
- Original art, audio and learned-model material is intended to be CC0-1.0;
  see [licenses/README.md](../licenses/README.md).
- Godot runtime and bundled components keep their own MIT/Expat and component
  notices; the extracted inventory is in `licenses/`.
- `assets/manifest.json` is currently an **empty registry**. No creative asset
  or learned model has been produced or cleared.
- **Provider/account terms remain unknown.**
  [provenance/PROVIDER_TERMS.md](../provenance/PROVIDER_TERMS.md) registers the
  observed authoring and reviewer routes as OPEN/BLOCKING;
  [provenance/OPEN_ITEMS.md](../provenance/OPEN_ITEMS.md) lists OI-01 through
  OI-12. Do not treat a provider document or a successful local check as rights
  clearance, and never invent signatures or rights holders.

## 7. Open gates at this revision

Read [STATUS.md](STATUS.md) for the current detail. The points a second
developer must not mistake for completion:

- **M0 is a placeholder shell.** `project.godot`, `scenes/` and `src/boot/` are
  an empty boot/menu/game shell: no track, car, motor, AI, menu system or
  gameplay. `schemas/` and `fixtures/` are provisional contracts with no broad
  schema freeze. `gl_compatibility` is provisional until M3. Capture is AVI-only. There is no
  controller, audio-input or target-platform perceptual evidence.
- **Native Windows manifest gate: hosted rerun pending.** The new
  [.github/workflows/manifest-windows.yml](../.github/workflows/manifest-windows.yml)
  runs the guarded-open tests on `windows-latest`; the POSIX implementation
  needs flags Windows lacks, so real-host execution is the only acceptance
  path. The committed baseline records no accepted Windows-host result; a
  hosted rerun/review is still pending. See STATUS.md for the latest attempt.
- **Current CI still has reviewed locking blockers.** Both exact-SHA reviews of
  `482069e` returned changes required:
  [Sol](../review/implementation/m0-ci-gpt-6-2-sol-482069e.md) and
  [Opus](../review/implementation/m0-ci-opus-5-5-482069e.md). Findings include
  export/lock namespace collision, concurrent exports sharing one scratch/log
  workspace, report overwrite, a silent Linux `flock` timeout, lock descriptors
  inherited by orphaned children, and a deleted failure-log printer. Fixes are
  uncommitted working-tree drafts; do not assume they landed.
- **Tick acceptance has an Opus major follow-up.** Sol passed the exact
  `1295892` probe; an independent Opus review returned changes required with a
  major finding: a request begun by a later physics callback can synchronously
  unpause the tree and admit one unaccounted physics-server step. M0.8 is open
  and the coordinator API must not be relied on for motor integration yet.
  See STATUS.md.
- **No M0 acceptance claim.** The plan requires both named reviewers on the
  final candidate, clean-checkout CI, and the rights/target-hardware gates.
  None is closed.

## 8. Rules a second developer must keep

1. **Own your paths.** Read the per-path ownership in
   [PLAN.md](../PLAN.md); do not edit another job's files.
2. **No installs, downloads or Git mutation from the check tooling.** The
   checks read local files; CI downloads official assets and verifies the
   publisher digest before extraction and execution (PLAN.md M0.1).
3. **A missing tool is a failure, not a pass.** Never weaken a check to make a
   run green; change a value deliberately and update the check in the same
   change.
4. **Never invent a digest.** Unknown fields stay empty and are reported as
   `NOT RECORDED`.
5. **An export is not a launch.** A local package, a digest match and a version
   string do not verify a target platform.
6. **Keep outputs in gitignored paths** (`work/`, `tools/ci/out/`, `build/`,
   `.godot/`, `dist/`, `captures/tmp/`, `saves/`) and write nothing arbitrary
   under source directories or user home.

## 9. What this revision checked

Documentation reconciliation only. Committed help and source at `04015ca`
were read with `git show 04015ca:<path>` and from a scratch `git archive HEAD`
extraction under this job's ignored directory; `tools/ci/ci.sh --help`,
`commands` and `pin` were run read-only from that extraction and their option
names checked against the committed parsing. **No** install, import, export,
capture, launch or download was run, and no GUI, template, installed tool or
Git state was mutated. This is not M0 acceptance; a refresh is needed after
the open CI, export-smoke, tick and Windows items above land.

Remaining second-developer exercise: follow this guide end-to-end from a clean
checkout of `04015ca`, record the actual exit codes and artifacts under ignored
paths, and report any command, option or path drift. Do not close M0 from local
green checks.
