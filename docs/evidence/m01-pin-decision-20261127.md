# M0.1 technical pin decision (scoped)

Date: 2026-11-27. Host: `mac-studio-2026-32-1.home` (macOS 27.0.1, arm64).
Checkout: `/Volumes/PaseoData/TrueNAS/paseo-home/workspace/Roadstorm`.

Decision: **approved for M0.1's scoped technical pin** after the coordinator's
independent check, using the read-only audit
`work/agents/78c4da63-ed43-4b99-bc4b-940309811cfe/REPORT.md` §5 **Option A**
(record-only closure), refined by the newer private-prefix
verify-before-extract record
[`docs/evidence/m01-private-verify-install-20261127.md`](m01-private-verify-install-20261127.md),
the pin files under `tools/toolchain/pin/`, `tools/ci/pin/engine.txt`,
`tools/python_pin/pin/`, and the committed evidence records. It is **not** M0
acceptance and makes no licensing, rights or provider-terms conclusion.
Provenance: prepared by the M0.1 pin-decision documentation job (LongCat 2.5
through Pi); no helper, subagent, Git mutation, download, install or system
change; the only file written is this record.

## Approved pins

Only the following are approved as project pins. Values below are quoted from
the named pin/evidence files; no digest or URL is newly invented here.

1. **Engine: Godot 4.7.2 Standard (official).** Exact `--version` string
   `4.7.2.stable.official.ed1daf0bf`, commit `ed1daf0bf`; matching export
   templates `4.7.2.stable`. Pin data: `tools/toolchain/pin/engine.txt`,
   `tools/toolchain/pin/checksums.txt`; CI fallback `tools/ci/pin/engine.txt`.
   Sources: [macOS editor ZIP](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_macos.universal.zip),
   [export templates TPZ](https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz),
   publisher [SHA512-SUMS.txt](https://github.com/godotengine/godot/releases/download/4.7.2-stable/SHA512-SUMS.txt).
   Publisher SHA-512 digests: editor
   `38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca`;
   templates
   `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`.
   Selected local member digests (editor `c7cccbf8…`, `version.txt`
   `38885c88…`, target templates `88df5e2e…` / `d34d36f3…` / `d9f79ab8…`,
   macOS template binary `6135ad13…`) are recorded in
   `tools/toolchain/pin/checksums.txt`; the CI fallback Linux editor ZIP has
   publisher SHA-512
   `9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65`
   (`tools/ci/pin/engine.txt`).
   The Godot evidence is publisher checksum agreement over HTTPS origin; **no
   cryptographic signature over the Godot archives is recorded**. Apple
   notarization of the installed `.app` is a separate platform-reported fact
   (`Prehensile Tales B.V. (6K46PWY5DM)`), not a byte-tie beyond selected files.
2. **Export templates: Godot 4.7.2 standard templates.** Same release as the
   editor; `4.7.2.stable/version.txt` reports `4.7.2.stable`. Non-target
   templates are present but not verified.
3. **Physics: built-in Jolt, explicitly selected, with an effective settings
   inventory.** The pinned editor contains the built-in Jolt module;
   `project.godot` sets `physics/3d/physics_engine="Jolt Physics"` (and
   `common/physics_interpolation=true`, `common/physics_ticks_per_second=60`).
   The pinned build registers 32 `physics/jolt_physics_3d/*` settings; the
   project overrides none, so all run at the engine defaults of this build.
   Record: [`docs/evidence/jolt-settings.md`](jolt-settings.md) and
   `tools/jolt_inventory/**`. This is a settings record, not a handling freeze;
   backend identity is inferred from the setting plus a contrast run, not
   directly observed by GDScript.
4. **Asset-generation Python: CPython 3.15.2 exact, from python.org.**
   Authority: [release page](https://www.python.org/downloads/release/python-3152/)
   and [FTP directory](https://www.python.org/ftp/python/3.15.2/); pin data
   `tools/python_pin/pin/python.txt`. Published SHA-256 (all four matched
   downloaded bytes on 2026-11-27; every `.sigstore` bundle verified against
   `hugo@python.org` via `https://github.com/login/oauth`, with wrong-identity,
   wrong-issuer and tampered-artifact negative controls failing):

   | Pinned artifact | Role | Published SHA-256 |
   | --- | --- | --- |
   | `python-3.15.2-macos11.pkg` | target installer (macOS universal2) | `2c6104475535b720b45774c68b0dfc9fcca2235353cf9ff81e05488f89845396` |
   | `python-3.15.2-amd64.exe` | target installer (Windows x86-64) | `06e225a228191b0f4d1dcf6905fbb21bf9f6970d13a2ec63137ab9bee76f15aa` |
   | `Python-3.15.2.tar.xz` | source archive (xz) | `8b5536d280142ecf6cdfe15d12a21ba1c65e300bbf7b28a8d0cdb849575797de` |
   | `Python-3.15.2.tgz` | source archive (gzip) | `f74e1db0eabd651cd01e4e2a00201bd41866abe74869ab716f9bf33cbbaa0943` |

   Sigstore bundle digests are recorded in `tools/python_pin/pin/python.txt`.
   The macOS and Windows items authenticate installer bytes only; the tarballs
   tie the source of record, not any separately built interpreter.

Nothing else is approved by this decision: not renderer selection, export
presets, target platforms, CI interpreter wiring, or full-bundle integrity.

## Verification ordering and host disposition

Private-prefix verify-before-extract (newer than the audit):

* Editor ZIP SHA-512 matched the publisher sums **before** `ditto -x -k`
  extraction.
* Export-template TPZ SHA-512 matched **before** `ci.sh install-templates`;
  that command independently re-computes the pinned digest and refuses to
  extract on mismatch.
* Python `.pkg` SHA-256 and its Sigstore bundle were checked (offline `OK`)
  **before** `pkgutil --expand-full`.
* All private copies stayed under ignored `work/agents/` prefixes; no persistent
  PATH, system environment, installer or system location was changed. The headless
  CI run used a `git archive` snapshot of commit `1e99b2d4…`, not the current
  checkout HEAD.

Pre-existing host installations were **not** verified before they originally
occurred and are not retroactively covered. The audit records the Homebrew cask
receipt at `2026-11-05T20:52:26Z`, the host template directory created
`2026-11-05`, and the Homebrew Python receipt at `2026-11-06T11:13:29Z`; all
predate the 2026-11-26/27 artifact verification. (An earlier file birth/mtime
on the `.app` bundle is not an install event.) Those host copies are accepted
**solely as a local drift baseline**: their recorded local digests let later
runs detect change, and **no publisher-authentication claim is made** for them.
The private editor binary happens to equal the host binary because both derive
from the same official archive member; that equality does not move the host
install time earlier.

Future clean installs must verify first: Godot archives against the publisher
SHA-512 sums before extraction; Python artifacts against the published SHA-256
and Sigstore evidence before installation. A digest mismatch means stop; do
not extract or install.

## Change control

Any change to an approved version, digest or source URL requires a recorded
regression decision (PLAN.md M0.1): the reason, the new exact version and
digests, and the verification status, with the pin file and the narrative
record updated together, followed by re-running
`tools/toolchain/verify.sh` / `tools/python_pin/verify.sh` and the applicable
CI gate. Do not track a moving "latest stable" pointer. An `--archive` digest
match alone is not authentication, and artifact checks never authenticate an
installed interpreter.

## Scope limits and open items

* **Selected files, not the full bundle.** Only the editor binary,
  `version.txt` and the three target templates were compared with the verified
  archives. Other bundle files and non-target templates are unverified;
  full-bundle verification remains undone.
* **Platform launches.** On this host only the private macOS editor ran
  headless (version probe and CI), and the macOS template's internal binary
  printed the pinned version. Windows/Linux template binaries were inspected by
  embedded strings only; no exported game was launched. Target-platform
  execution remains unverified.
* **R7 warning.** The intermittent `Jolt Physics job system exceeded the
  maximum number of jobs …` warning remains unresolved: not reproduced in
  later attempts, no diagnosis, frequency estimate or fix, and it is emitted at
  most once per process. It stays open and tracked; it does not block this pin
  decision but is not closed by it.
* **Python Linux x86-64.** python.org publishes no Linux binary; the
  authenticated tarballs are the source of record. A Linux interpreter at this
  pin would be locally built and cannot be compared with any publisher binary
  digest. No Linux build or launch was attempted.
* **Homebrew channel.** Distributor checksum agreement only; the Homebrew API
  JWS was not cryptographically verified and the installed framework bundle
  signature/resource-sealing question is open.
  `homebrew_channel_fully_verified=no`;
  `installed_interpreter_publisher_authenticated=no`.
* **CI and scripts.** `tools/ci` verifies engine and templates before
  extraction; the Python pin is not yet wired into CI or project scripts,
  which is a separate decision for those owners.
* **Audit wording issues.** The four stale/ambiguous status sentences listed in
  audit §3 were corrected in `56fe4c1`. The later private-prefix evidence is
  recorded separately. No version or digest changed in that editorial repair.

## What this decision does not settle

This is the M0.1 technical pin decision only. It is not M0 acceptance. The
remaining work includes the final second-agent setup/import/boot/pass-fail/
export smoke exercise, runtime-versus-original license separation, unknown dependency and
creative terms, and explicit missing-hardware recording remain open. It makes
no legal conclusion and does not resolve licensing, notice,
owner/contributor-authority, CC0/Unlicense, or provider-terms questions
(including OI-01/OI-02/OI-03/OI-12); those belong to their owners.

## Signoff and verification

**M0.1 is complete as the scoped technical pin decision above.** The coordinator
independently compared this record's versions, URLs and artifact digests against
`tools/toolchain/pin/engine.txt`, `tools/ci/pin/engine.txt` and
`tools/python_pin/pin/python.txt`; all checked values matched. On 2026-11-27,
`tools/toolchain/verify.sh --deep` passed against the recorded local engine
digests and selected templates, and `tools/python_pin/verify.sh` passed with its
explicit local-drift and unauthenticated-Homebrew warning. Logs are under
ignored `work/agents/coordinator/m01-signoff/`. The independent private-prefix
checks and test are recorded in
[`m01-private-verify-install-20261127.md`](m01-private-verify-install-20261127.md).
Completing M0.1 on this basis does not close R7, does
not verify the full Godot bundle or any target-platform launch, and does not
close M0. No version or digest change is warranted.
