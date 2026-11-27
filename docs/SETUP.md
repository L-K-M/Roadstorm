# Setup guide for a second developer (PLAN.md M0 acceptance)

This guide takes a second developer from a clean checkout of commit
`a5ba7a41f836e9ac451c3e0348015128a8cb2c8e` ("Expose selected ground-hit identity
for later eligibility checks", tree
`4daf9b0f854802de0bcc8db04a1859cf75773ed8`) through the pinned editor and
templates, a headless import, a passing boot check, a deliberately failing check,
the content/asset contracts, and one real desktop smoke export with an honest
launch distinction.

It describes **committed state only**. Other workers may have uncommitted body,
audio or gearbox edits in the shared checkout; those are not part of this
baseline. [STATUS.md](STATUS.md) is the fast-moving record and is authoritative
for open gates, review verdicts and recent runs.

**M0 is not accepted.** Scoped checkpoint decisions exist for the M0.1 pin,
M0.5 CI, the M0.6/M0.7 foundation records, the M0.8 minimal probe and the M0.9
definition-only schemas, but M0.2, M0.3 and M0.4 overall acceptance and whole-M0
acceptance remain open. This exercise verifies the tooling and committed
component laboratories, not gameplay and not final M0. A green local run is not
M0 acceptance.

## 1. Prerequisites

| Need | Exact requirement |
| --- | --- |
| Engine | Godot **4.7.2 Standard**; `godot --headless --version` prints `4.7.2.stable.official.ed1daf0bf` |
| Export templates | `4.7.2.stable` in the engine's own user-data directory, not `$GODOT_TEMPLATES_DIR` |
| 3D physics | built-in **Jolt**, set explicitly as `physics/3d/physics_engine="Jolt Physics"` in `project.godot` (`DEFAULT` is not accepted) |
| Renderer | `gl_compatibility`, provisional until M3 |
| Asset Python | CPython **3.15.2** exact for asset generation |
| Shell / tools | POSIX `/bin/sh` (dash-compatible), `tar`, `grep`, `sed`, `awk`, `find`, `sort`, `head`, `dirname`, `mktemp`, `date`, `uname`, and `shasum` or `sha256sum` |
| Python 3 | Required by `tools/ci/**`: report hard-link publication and the export package inventory call `python3`. `tools/ci/scripts/runtime_error_gate.sh`, the contract suites and the asset-manifest tooling also need it. Without a usable interpreter these checks fail closed; they do not skip |
| Optional | `curl` and `unzip` for downloads/install, `ffprobe` to verify capture resolution |

Exit codes are the same across the project tooling: `0` passed, `1` a check
failed, `2` the command could not run. A check that cannot run is never reported
as a pass.

Host limits: the only launch evidence in committed records is Apple Silicon
macOS (macOS 27.0.1, M4 Max); see
[MACHINE_INVENTORY.md](MACHINE_INVENTORY.md). A mode-1 ad-hoc macOS placeholder
package was exported and launched headless on `d4501e3` (exit 0, reached the
placeholder menu; Gatekeeper rejected the unnotarized bundle), and an earlier
windowed mode-3 smoke ran from `7b27c2f`. Neither is a release, an Intel-slice
test, or a Windows or Linux launch. Hosted Ubuntu CI has built all three desktop
presets but never launched Windows or Linux. No gamepad or audio-input device is
available here, and no launch evidence exists for `a5ba7a4` itself.

The version authority is the official archive at
<https://godotengine.org/download/archive/>; the pinned release is the GitHub
tag `4.7.2-stable`. Do not track a moving "stable" download.

## 2. Get the code and install the pin

```sh
git clone https://github.com/L-K-M/Roadstorm.git Roadstorm && cd Roadstorm
git checkout a5ba7a41f836e9ac451c3e0348015128a8cb2c8e
git rev-parse HEAD^{tree}          # 4daf9b0f854802de0bcc8db04a1859cf75773ed8
```

Start from a clean tree. Do not carry another worker's uncommitted edits into
this exercise; the immutable source is the commit above.

Verify the installed editor and templates. These commands read local files and
installed binaries only; they do not download anything:

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
`tools/toolchain/pin/engine.txt`. Do not install the Mono editor. Do not delete,
reinstall over, or reset an existing Godot installation just to follow this
guide: verify what is already installed first, and keep a working local
toolchain untouched unless you intend to change it through the project's
recorded regression process.

Set `GODOT_BIN=/path/to/godot` when the editor is not on `PATH`; `ci.sh` also
takes `--godot <path>`, and `tools/smoke/run_boot_smoke.sh` accepts
`--project <dir>` for another checkout or snapshot. For the pinned **Linux
x86-64 editor ZIP**, `ci.sh verify-engine --archive <file>` checks the publisher
digest before extraction, and `--binary <file>` checks the extracted editor.
The macOS editor ZIP and export-template TPZ publisher SHA-512 values are recorded in
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
installed. Remove an existing `<dest>/<version>.stable` explicitly only if you
intentionally want to replace an installed template tree; never script a
delete-and-reinstall.

Python provenance: the four python.org 3.15.2 artifacts were digest-matched and
Sigstore-verified on 2026-11-27; that authenticates publisher artifact bytes
only. The locally installed Homebrew 3.15.2 is a separate local build: its
version plus the recorded local SHA-256 detect drift, but neither is publisher
authentication. The Homebrew API JWS is unverified and a framework
bundle-signature question remains open. `tools/python_pin/pin/python.txt` keeps
these scopes apart in dated fields; see
[PYTHON_TOOLCHAIN_EVIDENCE.md](PYTHON_TOOLCHAIN_EVIDENCE.md). To verify a
downloaded official artifact, use `tools/python_pin/verify.sh --archive <file>`.

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
`USER ERROR:`, `Parse Error` or `Failed to load script`. Logs and one report per
run land under `tools/ci/out/` (gitignored).

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
baseline `test --list` discovers two checks,
`res://tests/handling/pure_motor_entry.gd` and
`res://tools/smoke/boot_smoke.gd`; `tests/` now exists but is not a broad
integration suite yet. The tooling reports exactly what it discovers and never
invents a pass.

`validate` also prints the content-contract inventory from
`tools/ci/contracts.list`. That inventory is **not validation**: game-content
validation (T09/T15) is not implemented. Entries marked `pending` warn by
default and fail under `validate --strict-contracts`.

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
schemas/handling/run_tests.sh
fixtures/observation/run_tests.sh
fixtures/intent/run_tests.sh
fixtures/scenario/run_tests.sh
sh tools/python_pin/tests/test_verify.sh
```

### Content and asset contracts

- `assets/manifest.json` is an **empty registry**. Running
  `python3 tools/asset_manifest/validate_manifest.py` validates that empty
  registry and `--check-hashes` succeeds on it, but an empty manifest is not
  evidence that any creative asset, course content or learned model exists or is
  cleared. The registry contract is
  [provenance/MANIFEST_CONTRACT.md](../provenance/MANIFEST_CONTRACT.md).
- `schemas/` and `fixtures/` hold the M0.9 definition-only handling, observation,
  intent and scenario contracts. Their suites check JSON structure and fixture
  consistency only; they do not prove runtime AI, physical placement, measured
  references or handling behavior.
- `tools/ci/contracts.list` lists planned content paths. `validate` reports
  which exist; absence is reported, not validated.

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
with the presets from that same commit), exports the requested platforms,
checksums every component including the `.pck`, re-reads the packaged `res://`
tree, and launches the macOS package on this host when macOS is requested:

```sh
# All three committed desktop targets; the runner creates a unique ignored output.
tools/export_smoke/run_export_smoke.sh

# A single target:
tools/export_smoke/run_export_smoke.sh --platform Linux

# Headless macOS launch only, for an already-exported package:
tools/export_smoke/launch_macos_app.sh --app /path/Roadstorm-macOS-universal.zip \
  --out /tmp/rs-mac --skip-windowed
```

Without `--out`, the runner reserves a fresh directory under
`work/agents/export-smoke/outputs/run.XXXXXX`. An explicit `--out` must not
already exist as a directory, file or symlink; the runner refuses it rather than
truncating anything. Exit codes: `0` every requested platform exported (macOS
launched), `1` a platform blocked/failed or an inventory check failed, `2` the
tool could not run. The engine must be the pinned version string.

### Local cross-export is not a target launch

| Action | What it proves | What it does not prove |
| --- | --- | --- |
| `ci.sh export` / `run_export_smoke.sh` for Windows or Linux | The preset and templates produce a byte-checksummed package with a complete `.pck` | Anything about running on Windows or Linux. No target host exists; neither package is launched anywhere. A successful export never verifies a platform (M0/M9.2). |
| `run_export_smoke.sh` macOS package | The package inventory and checksums pass, and on this host the package launches under the bounded harness | A verified release. The package is ad-hoc signed and **unnotarized**; Gatekeeper rejects it. The default probe is `headless` and opens no window. Intel/x86_64 slice is untested. |
| `--launch-probe full` | Additionally opens the GUI briefly and takes a screenshot | Nothing about target hardware. It is opt-in and needs the machine's desktop coordination. |

`--diagnostic-enable-etc2-astc` patches only the throwaway snapshot copy to work
around the universal/arm64 macOS `import_etc2_astc` refusal on older snapshots;
it is diagnostic only and never modifies the tracked `project.godot`. The
committed `project.godot` sets
`rendering/textures/vram_compression/import_etc2_astc=true`, so a normal export
works without the flag.

Treat the runner's macOS result as a local shell smoke of the placeholder build,
not as target-OS verification, signing/notarization clearance, gameplay or M0
acceptance. Prior committed evidence records a mode-1 ad-hoc headless launch on
`d4501e3` and an earlier windowed mode-3 smoke on `7b27c2f`; no launch evidence
is recorded for `a5ba7a4` itself, so the second developer's fresh run supplies
the current local evidence.

## 6. Licenses and rights

- Root [LICENSE](../LICENSE) is the Unlicense and is retained unchanged; it
  covers original code, tools, tests, schemas and documentation.
- Original art, audio and learned-model material is intended to be CC0-1.0;
  see [licenses/README.md](../licenses/README.md).
- Godot runtime and bundled components keep their own MIT/Expat and component
  notices; the extracted inventory is in `licenses/`.
- `assets/manifest.json` is currently an **empty registry**. No creative asset
  or learned model has been produced or cleared.
- **Provider/account terms are not fully resolved.** The owner confirmed on
  2026-11-27 that both Pi authoring routes use standard public provider
  agreements, with no enterprise or custom agreement identified. That
  establishes the agreement type only. The accepted revision, incorporated
  documents, AI-labeling duties and output-dedication compatibility remain
  unresolved. LongCat's general terms contain non-commercial-use language, and
  StepFun's open-platform agreement §1.1.6 restricts commercial use of generated
  outputs; both grant the provider broad default licenses. Neither route is
  cleared for release. [provenance/PROVIDER_TERMS.md](../provenance/PROVIDER_TERMS.md)
  registers the observed authoring and reviewer routes as OPEN/BLOCKING;
  [provenance/OPEN_ITEMS.md](../provenance/OPEN_ITEMS.md) lists OI-01 through
  OI-12, with OI-02/OI-03 as the output-rights blockers. The owner's direction
  to continue development is not a provider waiver. Do not treat a provider
  document or a successful local check as rights clearance, and never invent
  signatures or rights holders.

## 7. Open gates at this revision

Read [STATUS.md](STATUS.md) for the current detail. The points a second
developer must not mistake for completion:

- **M0 is not accepted as a whole.** The base boot/menu/game shell
  (`scenes/boot.tscn`, `scenes/main_menu.tscn`, `scenes/game.tscn`) plus
  committed M1 component laboratories and a one-car straight-bay DriveLab exist.
  They prove isolated components (motor kernel, body adapter, ground support,
  drift phase, camera/HUD, input, audio synthesis/playback) under pinned
  Godot/Jolt in headless labs. They do not provide an integrated drivable race,
  course/track content, AI opponents, a complete menu/progression system, or
  handling acceptance. There is no gameplay, controller, audio-input or
  target-platform perceptual evidence.
- **M0.2 is not accepted as a whole.** The shell, directory structure, ignore
  rules and typed schemas exist in part; the milestone gate remains open.
- **M0.3 is not accepted.** Provider/output rights OI-02/OI-03 are open, the
  asset registry is empty, and dependency-notice reconciliation and other
  provenance items remain open.
- **M0.4 overall acceptance is not claimed.** The CLI import, validate, test and
  export entry points exist and scoped checks pass, but content validation
  (T09/T15) is not implemented and capture is limited; the overall CLI gate
  remains open.
- **Native Windows manifest: bounded hosted pass, real-host limits remain.**
  Hosted `manifest-windows` run `46041591750` succeeded on exact pushed `65285be`
  (14 native guarded-open tests and both critical controls passed, plus the
  shipped empty-registry hash check). No file under `tools/asset_manifest`,
  `.github/workflows/manifest-windows.yml`, `assets/manifest.json` or
  `provenance/PROVIDER_TERMS.md` changed between `65285be` and this baseline.
  Reviewers still note that Windows lacks the Unix `O_NOFOLLOW`/`O_NONBLOCK`
  flags the guarded readers require, so populated `--check-hashes` and anchored
  register reads fail closed there with misleading diagnostics until a safe
  Windows path is implemented and tested on a real host. This is bounded tooling
  evidence, not a game launch or M0 signoff.
- **CI: scoped M0.5 accepted, whole M0 open.** Scoped M0.5 CI was accepted on
  exact `b679f58` after independent exact-SHA Opus 5.5 and GPT-6.2 Sol rechecks
  and hosted run `46068220462`, which passed all four clean-checkout jobs; the
  low residuals are documented in
  [docs/evidence/m05-ci-decision-20261127.md](evidence/m05-ci-decision-20261127.md).
  No CI, workflow or export-smoke file changed between `b679f58` and this
  baseline. That is a scoped CI/export-preparation pass, not target-OS launch
  evidence or whole-M0 acceptance, and no hosted run for `a5ba7a4` itself is
  recorded here.
- **M0.8: minimal probe accepted, integration limits remain.** The M0.8 minimal
  tick/query/reset probe was accepted on exact `da021e0` with passing exact-SHA
  reviews ([Opus 5.5](../review/implementation/m0-tick-opus-5-5-da021e0.md),
  [GPT-6.2 Sol](../review/implementation/m0-tick-gpt-6-2-sol-da021e0.md)) and is
  recorded in
  [docs/evidence/m08-probe-decision-20261127.md](evidence/m08-probe-decision-20261127.md).
  It is a one-car headless probe with documented idle/publication windows, not
  the M1 motor, a production training bridge, a multi-car simulator or a
  contact-fidelity guarantee.
- **No M0 acceptance claim.** The plan requires both named reviewers on the
  final candidate, clean-checkout CI, and the rights/target-hardware gates.
  None is closed.

## 8. Rules a second developer must keep

1. **Own your paths.** Read the per-path ownership in
   [PLAN.md](../PLAN.md); do not edit another job's files.
2. **No installs, downloads or Git mutation from the check tooling.** The
   checks read local files; CI downloads official assets and verifies the
   publisher digest before extraction and execution (PLAN.md M0.1). Do not
   reinstall or delete an existing editor/template tree just to follow this
   guide.
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

Documentation reconciliation only. Committed source at `a5ba7a4` was read from
a scratch `git archive a5ba7a4` extraction under this job's ignored directory,
with `git log`/`git show` used for commit metadata. Bounded commands run there
(no install, download, export, capture or GUI launch): `tools/ci/ci.sh --help`,
`pin`, `version`, `test --list`, `test`, `validate`, `export --list-presets` and
`export --check`; `tools/toolchain/verify.sh` and `--deep`;
`tools/python_pin/verify.sh` and `tests/test_verify.sh`;
`tools/smoke/run_boot_smoke.sh`, `--expect-failure` and `fault_injection.sh`
(8/8 cases); the four contract suites; `python3
tools/asset_manifest/validate_manifest.py`; and `tools/asset_manifest/run_tests.sh`.
Engine-backed checks ran headless against throwaway scratch copies. **No**
install, download, export, capture or GUI launch was run, and no Git state was
mutated. This is not M0 acceptance.

Remaining second-developer exercise: follow this guide end-to-end from a clean
checkout of `a5ba7a4`, record the actual exit codes and artifacts under ignored
paths, and report any command, option or path drift. Do not close M0 from local
green checks.
