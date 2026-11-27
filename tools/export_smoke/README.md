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
| Launch the macOS package on this Apple Silicon host (headless, plus a bounded windowed probe with `--launch-probe full`) | Claim a notarized or Developer-ID-signed release; the package is ad-hoc signed and UNNOTARIZED |
| Checksum **every** produced package component, including the `.pck` (sidecar for Windows/Linux, embedded in the `.app` for macOS) and, for macOS, every file inside the bundle | Verify the code signature chain, notarization, or Developer ID identity |
| Re-read the `res://` tree inside each produced `.pck` and prove that no development-only path is packaged and that every required runtime resource still is | Verify that the package launches on its target OS (only macOS is launched, and only as this tool launches it) |
| Verify every pack entry's MD-5 against the bytes stored for it, and that the pack's own file table is self-consistent | Verify gameplay, final M0 content, or the M9 release notices (`licenses/` and `provenance/` are not packed today: Godot packs only recognised resource types) |
| Record the candidate digest and every artifact's SHA-256 | Claim that the excluded development tooling still works |

## Files

| Path | Purpose |
| --- | --- |
| `run_export_smoke.sh` | Entry point: frozen snapshot → export requested platforms → package inventory/checksum check → (macOS) launch → report, per-platform inventories and `SHA256SUMS.txt`. |
| `launch_macos_app.sh` | Reusable macOS launch test for an exported `.app`/`.zip`: reports the code signature, runs a headless launch (validates the ad-hoc signature on exec and boots the shell) and — unless `--skip-windowed` — a bounded windowed launch with a screenshot, then terminates what it launched. |
| `lib/pack_inventory.py` | Package inventory and checksum tool. `list` prints and verifies a `.pck`; `check` enumerates and checksums every component of a produced package, parses and MD-5-verifies the pack's `res://` tree, applies the E4 content policy, and writes a report, JSON and `SHA256SUMS` lines. |
| `lib/common.sh` | Shared helpers: Godot discovery, pinned-version read, portable bounded-run, sha256, and the frozen-snapshot builder. |

## Usage

```sh
# All three targets from the current committed candidate.
tools/export_smoke/run_export_smoke.sh --out work/agents/<id>/outputs

# A single target (use a --out that does not exist yet; omit --out for a
# unique fresh directory per run):
tools/export_smoke/run_export_smoke.sh --platform Linux --out work/agents/<id>/outputs-linux

# Launch-test an already-exported macOS package:
tools/export_smoke/launch_macos_app.sh --app /path/Roadstorm-macOS-universal.zip --out /tmp/rs-mac

# Headless launch only (no window is ever opened):
tools/export_smoke/launch_macos_app.sh --app /path/Roadstorm-macOS-universal.zip --skip-windowed

# Inspect or verify a pack by hand:
tools/export_smoke/lib/pack_inventory.py list --pck /tmp/rs-linux/Roadstorm-Linux-x86_64.pck
tools/export_smoke/lib/pack_inventory.py check --platform Linux \
    --main /tmp/rs-linux/Roadstorm-Linux-x86_64 --pck /tmp/rs-linux/Roadstorm-Linux-x86_64.pck
```

`--out` must NOT already exist (directory, file or symlink, dangling or not):
it is reserved with an exclusive `mkdir`, so an existing output tree is never
truncated or replaced. Without `--out`, each invocation reserves a unique
fresh directory under `<project>/work/agents/export-smoke/outputs/`
(`run.XXXXXX`), so ordinary repeated runs never collide. The runner resolves one
immutable commit SHA before archiving; the report's `head_commit`,
`head_tree`, `archive_sha256` and `presets_sha256` all describe the exact bytes
that were extracted and exported. The presets are captured from
`<head_commit>:export_presets.cfg` with `git show`; the live working-tree copy
is never read or overlaid (the report adds `presets_source=head-commit` and
`presets_live_matches_commit=true|false` for diagnosis).

Environment: `GODOT_BIN`, `OUT_DIR`, `NO_COLOR`. Exit codes: `0` = every
requested platform exported (and macOS launched), `1` = a platform was
blocked/failed **or a package inventory check failed**, `2` = the tool could
not run. The engine must be the pinned `4.7.2.stable.official.ed1daf0bf`.

## Packaging checks (Opus recheck 4803d848 findings E3 and E4)

**E4 — development-only tooling is excluded, and the exclusion is verified.**
`export_presets.cfg` sets an `exclude_filter` on all three presets:
`tools/*,fixtures/*,schemas/*,docs/*,plan/*,review/*,work/*,.github/*,tests/*,*.py,*.sh,assets/manifest.json`.
`export_filter="all_resources"` otherwise packs every resource Godot recognises
under `res://`, which shipped the CI/smoke/probe scripts, the test fixtures, the
contract schemas and the asset registry. Runtime dependencies are deliberately
**not** excluded: `scenes/`, `src/`, `assets/` (art and other shipped content),
`project.godot` and the bundle metadata stay in. Only `assets/manifest.json` is
excluded from `assets/`: it is the registry maintained by
`tools/asset_manifest`, and no script or scene reads it.

**E3 — every produced component is checksummed, including the `.pck`.** For
Linux and Windows the game content lives entirely in the sidecar `.pck`; the
Linux main binary is byte-identical to the pinned stock template
(`tools/toolchain/pin/checksums.txt`), so its digest says nothing about the
game. For macOS the `.pck` is embedded in the `.app`, so every file of the
bundle is checksummed too. An empty component fails the run.

`lib/pack_inventory.py check` is what turns those statements into evidence. For
each exported package it:

1. enumerates **every** component (the distributed archive/executable, the
   sidecar `.pck`, and for macOS all seven `.app` files) and records its size
   and SHA-256, failing on an empty component;
2. parses the `.pck` header and file table, and verifies **every** entry's
   stored MD-5 against the bytes stored for it (a self-consistency check that
   needs no external reference);
3. fails if any development-only path is inside the package, or if any required
   runtime resource (`project.binary`, the three `scenes/*.tscn.remap`, the
   three `src/boot/*.gdc`, `.godot/global_script_class_cache.cfg`,
   `.godot/uid_cache.bin` and at least one `.godot/exported/*.scn`) is missing —
   so an over-broad exclude filter cannot silently ship a package that cannot
   boot. `REQUIRED_RUNTIME` in the tool is a floor: update it when the project's
   runtime resources change;
4. with `--snapshot` (which `run_export_smoke.sh` always passes) compares every
   pack entry that is not engine-generated (`.remap`, `.gdc`, `project.binary`,
   the `.godot` caches) byte-for-byte against the frozen candidate, so a
   packaged source file cannot differ from the candidate it claims to come
   from.

Outputs per platform: `package-inventory-<platform>.txt` (human-readable, with
the full `res://` tree and the explicit "what this verifies / does NOT verify"
list), `package-inventory-<platform>.json` (machine-readable), and
`SHA256SUMS.txt`. Note that the macOS `.app` component paths in `SHA256SUMS.txt`
are relative to the extracted bundle, so `shasum -c SHA256SUMS.txt` only
verifies the top-level artifacts.

Before this check existed, a Linux export could leave a **0-byte** main binary
and still be reported as `EXPORTED`: the runner only checked that the output
file existed. The inventory check now fails on an empty component, which is how
that case was found on 2026-11-27.

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

The coordinator subsequently enabled this setting; the new committed candidate
requires a fresh non-diagnostic export and launch check. Job
`f463de0e-9510-4c7e-b6c8-57e03afc98d6` ran exactly that on candidate `f9779b57`
(2026-11-27): all three platforms exported without the diagnostic flag, all
three package inventory checks passed, and the macOS package launched headless
(exit 0, boot→menu handoff). Its evidence is under
`work/agents/f463de0e-9510-4c7e-b6c8-57e03afc98d6/run2/`.

## Failure evidence and cleanup

No recursive deletion is ever performed through a mutable pathname, because a
concurrent replacement of that path could delete a foreign tree. Exclusive
files are opened once with `O_CREAT|O_EXCL|O_WRONLY` and written through that
descriptor, so they are never followed or truncated either. Runs therefore
leave, for inspection: the private staging directory
(`<out>/.candidate-snapshot.stage.*`, containing the archived candidate plus
listing/error/digest text), the partial snapshot on failure, the evidence
file `<out>/.candidate-snapshot.archive-sha256`, the candidate-digest input
`<out>/.candidate-digest-input`, and a possible partial preset copy inside a
failed snapshot. Successful runs retain their staging copy too. Bounded cost:
about one `git archive HEAD` per run plus a few kilobytes.

Safe manual cleanup after review (only inside an output directory you own):

```sh
rm -rf "<out>/.candidate-snapshot.stage."*
rm -f  "<out>/.candidate-snapshot.archive-sha256" \
       "<out>/.candidate-digest-input"
```

Residual same-UID adversary limits, stated precisely: initial exclusive
creates and the archive capture/listing copies are descriptor-based. Child
stdout appended to export logs (`>>`), and external tools that take path
arguments (`pack_inventory.py`, `codesign`, `screencapture`, the launch
helper), reopen paths by name, so a concurrent process able to replace those
names inside the reserved directory after creation could redirect those
particular writes. No removal, follow or truncation of a replaced path occurs;
the snapshot itself stays confined to the reserved inode and the tool fails
closed on every identity change it can observe.

## Rules this directory keeps

1. **Frozen candidate only.** `git archive HEAD` plus the owned presets; never a
   working-tree copy that could include another job's uncommitted files.
2. **No platform claim without a launch.** Windows/Linux are cross-exports and
   are labelled as not launched.
3. **Ad-hoc, not notarized.** No Developer ID/notarization credentials exist;
   the package is labelled ad-hoc signed and unnotarized (PLAN.md M9.3).
4. **Every process is bounded** (default 120 s) and any GUI app this tool
   launches is terminated before it returns (desktop hygiene). The default
   launch probe is `headless`; `--launch-probe full` is opt-in.
5. **No installs, no downloads, no git mutations, no publishing.**
6. **Package content is checked, not assumed.** The exclude filter lives in the
   presets, but `lib/pack_inventory.py` re-reads what actually landed in each
   `.pck`; a package with development-only content, a missing runtime resource,
   an unverified pack entry or an empty component fails the run.
