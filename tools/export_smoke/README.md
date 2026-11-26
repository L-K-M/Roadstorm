# tools/export_smoke — native export smoke build and macOS launch test

Original project code under the Unlicense. Ownership: `tools/export_smoke/**`
(see PLAN.md "How agents execute the plan"). The export presets themselves are
owned separately as `export_presets.cfg`.

This directory implements the M0/M9 export-smoke path: it builds native smoke
packages for the three committed desktop targets from a **frozen, isolated
source candidate**, then — for macOS only — launches the package. It reports
exactly what it did and refuses to claim anything it did not run.

## What it proves and what it does not

| It does | It does NOT |
| --- | --- |
| Build the candidate from `git archive HEAD` + the owned `export_presets.cfg` only | Copy any concurrent uncommitted file (schemas, fixtures, other jobs' WIP) into the candidate |
| Cross-export Windows x86-64 and Linux x86-64 packages | Launch Windows or Linux packages — no target host exists; a successful export never verifies a platform (M0 acceptance, M9.2) |
| Launch the macOS package on this Apple Silicon host (headless + a bounded windowed probe) | Claim a notarized or Developer-ID-signed release; the package is ad-hoc signed and UNNOTARIZED |
| Record the candidate digest and every artifact's SHA-256 | Claim gameplay, final M0, or a verified platform package |

## Files

| Path | Purpose |
| --- | --- |
| `run_export_smoke.sh` | Entry point: frozen snapshot → export requested platforms → (macOS) launch → report + `SHA256SUMS.txt`. |
| `launch_macos_app.sh` | Reusable macOS launch test for an exported `.app`/`.zip`: reports the code signature, runs a headless launch (validates the ad-hoc signature on exec and boots the shell) and a bounded windowed launch with a screenshot, then terminates what it launched. |
| `lib/common.sh` | Shared helpers: Godot discovery, pinned-version read, portable bounded-run, sha256, and the frozen-snapshot builder. |

## Usage

```sh
# All three targets from the current committed candidate.
tools/export_smoke/run_export_smoke.sh --out work/agents/<id>/outputs

# A single target:
tools/export_smoke/run_export_smoke.sh --platform Linux --out /tmp/rs-linux

# Launch-test an already-exported macOS package:
tools/export_smoke/launch_macos_app.sh --app /path/Roadstorm-macOS-universal.zip --out /tmp/rs-mac
```

Environment: `GODOT_BIN`, `OUT_DIR`, `NO_COLOR`. Exit codes: `0` = every
requested platform exported (and macOS launched), `1` = a platform was
blocked/failed, `2` = the tool could not run. The engine must be the pinned
`4.7.2.stable.official.ed1daf0bf`.

## The macOS `import_etc2_astc` blocker (documented, not hidden)

The pinned official Godot 4.7.2 macOS template exports only a **universal**
binary, and a universal/arm64 macOS export is refused unless Project Setting
`rendering/textures/vram_compression/import_etc2_astc` is `true`. The worker's historical candidate `10d9e51` left it at the engine default (`false`), so that candidate's macOS export was **BLOCKED**:

```
Cannot export for universal or arm64 if ETC2 ASTC texture format is disabled.
Enable it in the Project Settings (Rendering > Textures > VRAM Compression >
Import ETC2 ASTC).
```

That setting lives in the tracked `project.godot`, which is **owned outside
this tool** (integration / M0.2). This tool does not modify it. To prove the
macOS preset is otherwise correct and that the package launches, run the
diagnostic flag, which patches only the throwaway snapshot copy:

```sh
tools/export_smoke/run_export_smoke.sh --diagnostic-enable-etc2-astc --out work/agents/<id>/outputs
```

With that flag the macOS package exports, is verified **ad-hoc signed**, and
launches cleanly on this Apple Silicon host (headless exit 0, boot→menu
handoff, and a windowed screenshot of the placeholder menu). The Intel
(`x86_64`) slice of the universal binary remains **UNTESTED** (no Intel host),
and Intel Mac support is therefore not claimed.

The one-line fix for integration is to add to `project.godot`:

```ini
[rendering]
textures/vram_compression/import_etc2_astc=true
```

The coordinator subsequently enabled this setting; the new committed candidate requires a fresh non-diagnostic export and launch check.

## Rules this directory keeps

1. **Frozen candidate only.** `git archive HEAD` plus the owned presets; never a
   working-tree copy that could include another job's uncommitted files.
2. **No platform claim without a launch.** Windows/Linux are cross-exports and
   are labelled as not launched.
3. **Ad-hoc, not notarized.** No Developer ID/notarization credentials exist;
   the package is labelled ad-hoc signed and unnotarized (PLAN.md M9.3).
4. **Every process is bounded** (default 120 s) and any GUI app this tool
   launches is terminated before it returns (desktop hygiene).
5. **No installs, no downloads, no git mutations, no publishing.**
