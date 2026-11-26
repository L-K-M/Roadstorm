# Development and runtime dependency inventory

Initial M0.3 inventory, prepared 2026-11-26 from input revision
`0ea596a4fa85ade19375e130313f020ed6010619`. This record separates
**distribution/runtime dependencies** from **available host development tools**
and from **candidate but unadopted components**. Version strings below are
observed on this machine; formal pin approval and a checksum manifest belong to
M0.1, which was still in progress at preparation time.

Creative assets/models are tracked separately: the baseline has no external
creative inputs yet, and `assets/manifest.json` does not exist until the asset
pipeline lands (M2.6+). See [`../licenses/README.md`](../licenses/README.md) for
the license scope and extracted Godot notices.

## Runtime / distribution dependencies

| ID | Component | Observed version / source | Role | License | Notice status |
| --- | --- | --- | --- | --- | --- |
| D1 | Godot Engine 4.7.2 Standard (editor) | `4.7.2.stable.official.ed1daf0bf`; commit `ed1daf0bf001b61586d9930840f2f1394092c079` (`refs/tags/4.7.2-stable`); `/Applications/Godot.app/Contents/MacOS/Godot`, universal x86_64 + arm64 | Runtime/editor; project pin target per PLAN M0.1 | MIT/Expat plus bundled component licenses | Extracted: `../licenses/GODOT-LICENSE-MIT.txt`, `../licenses/GODOT-COPYRIGHT-INVENTORY.txt`; per-build reconciliation open |
| D2 | Godot export templates 4.7.2.stable | Local export-template directory `.../export_templates/4.7.2.stable/`; `version.txt` = `4.7.2.stable`; macOS `.zip`, Windows `windows_release_x86_64.exe`, Linux `linux_release.x86_64`, plus debug variants | Native export templates for required desktop targets | Same engine/component terms as D1 | Source notices apply; actual shipped template contents must be reconciled per package at M8.6/T15 |

Evidence for D1/D2:

```text
godot --version                     -> 4.7.2.stable.official.ed1daf0bf
git ls-remote ... refs/tags/4.7.2-stable
                                    -> ed1daf0bf001b61586d9930840f2f1394092c079
cat export_templates/.../version.txt-> 4.7.2.stable

sha256 /Applications/Godot.app/Contents/MacOS/Godot
  c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf
sha256 .../macos.zip
  88df5e2e6fee99088699be66e6d42e4da4fb0c5619d054297d755a49558a4792
sha256 .../windows_release_x86_64.exe
  d34d36f3be1a6c49c56525ae86469b92e4f417ddf0b43cf00dd80c385c4b0562
sha256 .../linux_release.x86_64
  d9f79ab89b5ae369aeed11c6052d402e8218cd503bf85b4a235f9c30c46a7c63
```

The installed editor binary was also searched for embedded notice data from
the inventory. `rg -a -l` matched the Godot MIT copyright line (`Copyright (c)
2014-present Godot Engine contributors (see AUTHORS.md)`), the Jolt physics
copyright (`2021, Jorrit Rouwe`), and the Inter font copyright (`The Inter
Project Authors`). This corroborates that the extracted notices correspond to
components in the installed runtime; it does not replace the per-build/package
reconciliation in OI-04.

D3 — Built-in Jolt Physics 3D backend: part of Godot 4.7.2, no separate binary or
pin. Source inventory entry `thirdparty/jolt_physics/*`: copyright `2021, Jorrit
Rouwe`, license `Expat` (MIT). Covered by D1's extracted inventory; no separate
notice file is currently stored.

D4 — Python 3.15.2: observed at `/opt/homebrew/opt/python@3.15/bin/python3.15`,
built with Apple Clang 21.0.0. Planned role is asset-generation scripting
(PLAN M0.1), but project scripts are not written yet, so this is an available
tool, not an adopted pin. License: Python Software Foundation License Agreement
plus additional bundled-component licenses. Local notice:
`/opt/homebrew/opt/python@3.15/Frameworks/Python.framework/Versions/3.15/lib/python3.15/LICENSE.txt`,
SHA-256 `b0e25a78cffb43f4d92de8b61ccfa1f1f98ecbc22330b54b5251e7b6ba010231`.
Notice copy into `licenses/` is pending; include if any relevant Python
code/binary is redistributed.

## Available host development tools (not adopted project dependencies)

| ID | Component | Observed version | Role | License classification | Notice status |
| --- | --- | --- | --- | --- | --- |
| D5 | Git (Apple Git) | `2.54.0` | Version control | GPL-2.0 for the Git project; verify build-specific terms | No local notice text found; needed only if Git code/binaries are redistributed |
| D6 | FFmpeg | `9.0.2_1` Homebrew build, configuration includes `--enable-gpl` and `--enable-version3` | Optional audio encoding tool; not chosen or pinned by any project script | Build appears GPL-3.0-or-later with additional LGPL component notices; effective terms depend on enabled libraries | Local notices: `COPYING.GPLv3` SHA-256 `8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903`, `COPYING.LGPLv3` SHA-256 `da7eabb7bafdf7d3ae5e9f223aa5bdc1eece45ac569dc21b3b037520b4464768`; do not ship without re-verifying configuration |
| D7 | macOS / Apple toolchain | macOS `27.0.1`; Apple clang `21.0.0` | Host OS and compiler for development/testing | Proprietary Apple terms | Not redistributed; target-platform claims need real per-OS tests |

## Candidate / not adopted

| ID | Component | Status |
| --- | --- | --- |
| D8 | Learned-opponent training stack (for example PyTorch, Stable Baselines3, Gymnasium mentioned in planning/review material) | **Not adopted or pinned.** No version, license record, compute budget approval, or model provenance exists yet. M4B must pin versions/licenses before use. |
| D9 | Blender or other optional content tools | **Not adopted.** TECHNICAL_DESIGN permits an original scripted Blender tool only if it solves a measured production problem; its version/license would then enter this inventory. |
| D10 | External creative packs/fonts/samples/datasets (Kenney, Poly Haven, Freesound are candidate examples only) | **None selected or downloaded.** Baseline policy accepts only verified item-level CC0 creative input, with explicit scope decision for any exception. Any future input needs provenance and rights records before inclusion. |

## Engine-bundled fonts/data

The extracted Godot inventory identifies bundled font data that may remain in
exports even when the game uses an original UI font:

- Apache-2.0: `thirdparty/fonts/DroidSans*.woff2`.
- OFL-1.1: `Inter*.woff2`, `JetBrainsMono_Regular.woff2`, `NotoSans*.woff2`,
  `OpenSans*.woff2`, `Vazirmatn*.woff2`.

An original UI font does not remove engine-bundled font data. Applicable font
notices must ship if those resources are exported. This is part of the open
per-build reconciliation item below.

## Open gaps

- **OI-09:** M0.1 has not yet formally approved a pinned runtime/download record
  with canonical source URLs and checksums. The hashes above are observed
  evidence, not an approved pin.
- **OI-04:** Exact third-party component list per exported template/platform is
  not reconciled against `GODOT-COPYRIGHT-INVENTORY.txt`. Source-tree inventory
  can include platform-specific components not present in a given build.
- **OI-05:** Development-tool notice texts are recorded by location/hash but not
  copied into `licenses/` because none of those tools is currently being
  redistributed. Copy them if redistribution becomes relevant.
- **OI-06:** Training-stack versions and licenses are unpinned.
- **No external creative input** has been accepted, so no creative-input terms
  are currently unknown. That changes if any external input is proposed; intake
  must happen before inclusion.
