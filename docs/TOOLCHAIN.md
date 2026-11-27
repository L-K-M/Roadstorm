# Toolchain inventory (PLAN.md M0.1)

Status: recorded 2026-11-26 on the development Mac. M0.1 remains open: the installed editor binary and three release template files match publisher-checksummed archives as described below, while the project selects Python 3.15.2 (pin authority python.org) and the built-in Jolt backend locally. All four pinned Python artifacts were digest-matched and Sigstore-verified on 2026-11-27, but the interpreter scripts actually select on this host is an explicitly unauthenticated Homebrew build of that version, not a publisher artifact; all 32 Jolt settings are inventoried (none overridden), with the intermittent job-system warning still open. A headless contrast showed the backend setting changes observed behavior. Full bundle verification and actual platform launches remain unverified.

Ownership: `docs/TOOLCHAIN.md` and `tools/toolchain/**`. Nothing else in the
checkout was touched. Machine/OS/controller inventory for M0.6 is a separate
record and is not duplicated here.

## Pinned toolchain

| Component | Value |
| --- | --- |
| Engine | Godot **4.7.2 Standard** (official build) |
| Exact version string | `4.7.2.stable.official.ed1daf0bf` |
| Editor binary | `/Applications/Godot.app/Contents/MacOS/Godot` (universal arm64 + x86_64) |
| On PATH | `/opt/homebrew/bin/godot` → the same file (symlink) |
| Editor sha256 (local observation) | `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf` |
| Export templates | `4.7.2.stable` in `~/Library/Application Support/Godot/export_templates/` |
| 3D physics backend | built-in **Jolt** (module present in the pinned editor) |
| Renderer (project setting) | `gl_compatibility` — provisional until M3 (unchanged by this record) |
| Host | `mac-studio-2026-32-1.home`, macOS 27.0.1 (26A434), arm64 |

Only one Godot installation was found on this machine: `/Applications/Godot.app`.
No Mono editor, no second copy in `~/Applications`, `/usr/local/bin` or
Homebrew's Caskroom beyond the `godot` cask itself. `godot4` does not exist as a
separate command.

### Export templates (local observations, sha256)

All under `~/Library/Application Support/Godot/export_templates/4.7.2.stable/`:

| File | sha256 | Role |
| --- | --- | --- |
| `version.txt` | `38885c88f75abbc797a1db7559719800279a00cfb9fa8b2e2868a7f6f84bad2e` | reports `4.7.2.stable` |
| `macos.zip` | `88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792` | macOS target (PLAN "Platforms") |
| `windows_release_x86_64.exe` | `d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562` | Windows x86-64 target |
| `linux_release.x86_64` | `d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63` | Linux x86-64 target |
| `macos.zip` → `macos_template.app/Contents/MacOS/godot_macos_release.universal` | `6135ad137facbb26cd73a5f7f7d541d334a84fc81650e870ef075cdd14a129cd` | internal release binary, executed on this host |

`version.txt` is 13 bytes reading `4.7.2.stable`, matching the editor's
`4.7.2.stable` version — the templates and the editor are the same release.
The directory also contains Android, iOS, Web and Windows-arm64 artifacts that
this project does not target; they are recorded as present, not verified.

## What was verified, and how

Every item below is a local, repeatable observation; none of them downloaded
anything.

1. **Editor version, by execution.** `godot --headless --version` prints
   `4.7.2.stable.official.ed1daf0bf`. The banner reads
   `Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org`.
   The `.official.` marker and the commit hash are properties of the version
   string, not proof of provenance.
2. **Template version match.** `export_templates/4.7.2.stable/version.txt`
   reads `4.7.2.stable`; the directory name matches the editor version, so the
   installed templates match the pinned editor.
3. **Template binaries identify as the pinned build.** The macOS template's
   internal release binary was executed on this host and printed
   `4.7.2.stable.official.ed1daf0bf`. The Linux and Windows x86-64 template
   binaries cannot run on an arm64 Mac, so they were checked by searching for
   their embedded version strings: both contain `4.7.2.stable.official`.
4. **Built-in Jolt 3D backend.** The editor binary contains the Jolt module's
   class names (`JoltArea`, `JoltBody`, `JoltBodyActivationListener`, …), and a
   scratch project outside the checkout with
   `physics/3d/physics_engine="Jolt Physics"` was accepted by the engine with
   the setting preserved. Jolt is compiled into this build. Subsequently the project and probe explicitly selected it; a same-host contrast produced differing contact measurements. Direct backend identity is not exposed by the GDScript probe.
5. **Integrity and signature of the app bundle.** `codesign --verify --deep
   --strict` reports `valid on disk` and `satisfies its Designated
   Requirement`; Gatekeeper reports
   `source=Notarized Developer ID`,
   `origin=Developer ID Application: Prehensile Tales B.V. (6K46PWY5DM)`.
   This is what macOS reports about the installed bundle; it is not a statement
   by this project about who Prehensile Tales B.V. is.
6. **Install provenance.** Homebrew's cask `godot` 4.7.2 is installed
   (`/opt/homebrew/Caskroom/godot/4.7.2/Godot.app` → `/Applications/Godot.app`,
   install receipt `installed_on_request: true`), and the Homebrew cask
   metadata cached on this machine
   (`~/Library/Caches/Homebrew/api/internal/packages.arm64_golden_gate.jws.json`)
   records the cask's source asset as
   `Godot_v4.7.2-stable_macos.universal.zip` from the official GitHub release.
   The install receipt records no checksum, so this is provenance of the
   *delivery mechanism*, not a digest comparison.
7. **Local digests.** Every sha256 above was computed with `shasum -a 256` and
   is reproducible on this machine; `tools/toolchain/verify.sh` re-computes and
   compares them on every run so that any later change to the installed files is
   detected.

## Upstream verification — selected files verified

On 2026-11-26 the coordinator verified the official editor ZIP and template TPZ against the publisher's SHA-512 sums, then compared the installed editor binary and three target release templates against their respective verified archive members. See [the evidence record](evidence/godot-4.7.2-archive-verification.md). Other bundle files and templates were not compared, and this does not constitute target-platform testing.

## Exact official sources

The version authority is the [official archive](https://godotengine.org/download/archive/).
The release used for the pin is the GitHub release `4.7.2-stable`:

| Purpose | URL |
| --- | --- |
| macOS editor archive | `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip` |
| Export templates | `https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz` |
| Publisher checksums | `https://github.com/godotengine/godot/releases/download/4.7.2-stable/SHA512-SUMS.txt` |
| Release page | `https://github.com/godotengine/godot/releases/tag/4.7.2-stable` |

The worker initially confirmed these URLs with HTTP `HEAD` requests only (the assets
return `302` to their storage host, the release page returns `200`), and
`https://github.com/godotengine/godot/commit/ed1daf0bf` resolves (`200`), i.e.
the build commit named in the version string exists in the upstream
repository. Subsequent archive content verification is recorded above.

## Unknowns and limitations

* **Selected archive members were compared**, but other editor bundle files and non-target templates have not been checked against the verified archives.
* **Windows and Linux template binaries were not executed** — no compatible
  host here. Their embedded version strings were read instead.
* **The macOS template version probe executed.** No exported game package was tested. Windows x86-64 and Linux x86-64 are
  recorded as present and version-consistent, not as verified targets
  (PLAN.md M0.6/M3: an untested platform does not become verified).
* **The Homebrew cask was the delivery mechanism.** Any future reinstall must
  keep the same source asset, or the pin and this record must change together
  through a regression decision.
* **Code-signing facts are as reported by macOS**, including the signing
  identity `Prehensile Tales B.V. (6K46PWY5DM)`. This record does not
  independently assert anything about that organisation.

## Reproducing this record

```sh
tools/toolchain/verify.sh          # version, local digests, template presence
tools/toolchain/verify.sh --deep   # additionally runs the macOS template binary
                                   # and checks the Jolt module in the editor
tools/toolchain/verify.sh --record out/observed-checksums.txt
```

Exit codes: `0` passed, `1` a check failed, `2` the command could not run. The
recorded pin data is in `tools/toolchain/pin/`; see `tools/toolchain/README.md`
for the rules that keep a local digest from being mistaken for verification.

## Changing the pin

Per PLAN.md M0.1 the pinned engine changes only through a recorded regression
decision: the reason for the change, the new version string and digests, and the
upstream-verification status, recorded here and in
`tools/toolchain/pin/` together. Do not track a moving stable download.
