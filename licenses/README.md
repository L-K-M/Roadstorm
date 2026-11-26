# Roadstorm Racer! license scope and notices

Initial M0.3 inventory, prepared 2026-11-26 from input revision
`0ea596a4fa85ade19375e130313f020ed6010619`; revised 2026-11-26 by audit job
`a67680d9-2923-4992-a350-5804f0fcc193` (StepFun `step-5-preview` through Pi),
which aligned the authority-basis statements with the plan's standing-record
requirement. This is a project rights document, not legal advice. Open and
unverified items are consolidated in
[`provenance/OPEN_ITEMS.md`](../provenance/OPEN_ITEMS.md).

## Scope rule

License by **material purpose** with explicit manifest scope, never by a
blanket folder rule and never by describing an exported executable as wholly
public domain. Third-party material keeps its own terms wherever it is located.

| Material | Treatment |
| --- | --- |
| Original code, tools, tests, text definitions, documentation | Unlicense, retaining the existing root [`LICENSE`](../LICENSE) verbatim |
| Original meshes, materials, textures, UI art, font glyphs, music, effects | CC0-1.0, with editable sources/recipes retained |
| Original learned rival weights and authored training datasets | CC0-1.0 to the extent applicable rights exist, with model/data provenance |
| Godot runtime and bundled components | Their original MIT/Expat and component licenses; exact required notices retained |
| Development tools/libraries | Their original licenses, recorded separately; notices included when redistributing relevant code/binaries |
| Exceptional external creative input | Only verified item-level CC0 accepted by the asset policy; anything else needs its verified original terms and an explicit scope decision |

### Explicit overrides

These resolve ambiguities between executable and creative material:

- Executable generators, tests, schemas, and game/event definitions remain
  **Unlicense** even when they live beside creative assets.
- Original editable scores, glyph/mesh artwork sources, their creative
  outputs, trained weights, and authored datasets use **CC0-1.0**.
- Third-party notices and marks retain their own terms wherever located. They
  are not re-licensed by this document or by the project's Unlicense/CC0
  dedications.

## Unlicense preservation

The root [`LICENSE`](../LICENSE) is retained unchanged and continues to govern
original software, scripts, structured definitions, and documentation. Its
SHA-256 at preparation was:

```text
6b0382b16279f26ff69014300541967a356a666eb0b91b422f6862f6b7dad17e  LICENSE
```

Do not replace, edit, or supersede it. `git diff -- LICENSE` is empty relative
to input revision `0ea596a4`. It is the project's software public-domain
dedication for material a contributor is authorized to dedicate; it is not a
grant of third-party component rights and it is not itself the dedication
authority record for agent-produced output. That standing owner/operator basis
is recorded in
[`provenance/OWNER_AUTHORITY.md`](../provenance/OWNER_AUTHORITY.md).

## CC0 asset notice

For original Roadstorm Racer! game art, audio, learned model weights, and
authored datasets, the intended treatment is:

> To the extent that applicable rights exist and can be waived, the
> contributor(s) who control them dedicate the original game art, audio,
> learned model artifacts, and authored datasets to the public domain under
> the Creative Commons CC0 1.0 Universal Public Domain Dedication,
> <https://creativecommons.org/publicdomain/zero/1.0/>. This dedication covers
> only rights the dedicator controls. It is not a warranty of originality or
> freedom from third-party claims, and it does not resolve trademark, privacy,
> or publicity rights.

A verbatim copy of the official CC0 1.0 legal code retrieved 2026-11-26 is
stored at [`licenses/CC0-1.0-legalcode.txt`](CC0-1.0-legalcode.txt):

```text
a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499  licenses/CC0-1.0-legalcode.txt
```

The full deed is <https://creativecommons.org/publicdomain/zero/1.0/deed>.
CC0 dedication requires an authorized affirmer/contributor; AI generation
alone does not establish copyrightability, originality, or dedication
authority. Where no copyright arises, record that legal-basis assessment
without inventing ownership.

## Third-party notices

### Godot Engine and export templates

The project pins Godot 4.7.2 Standard in PLAN M0.1. The observed host runtime
is:

- `godot --version`: `4.7.2.stable.official.ed1daf0bf`
- Matching upstream tag commit:
  `ed1daf0bf001b61586d9930840f2f1394092c079` (`refs/tags/4.7.2-stable`)
- Editor binary SHA-256:
  `c7cccbf8fb143e34e02fd6521e09be2c2b974f0d5db080b19071c9c570718ccf`
- Export templates present locally: `4.7.2.stable` (macOS `.zip`, Windows
  x86-64 `.exe`, Linux x86-64, plus debug variants)

Extracted at that pinned commit and stored here:

- [`GODOT-LICENSE-MIT.txt`](GODOT-LICENSE-MIT.txt) — engine MIT/Expat license;
  SHA-256 `b0435e3b3e4e55238f05f4b306f30524a1b2e20147810d436eaa554fa6855c80`.
- [`GODOT-COPYRIGHT-INVENTORY.txt`](GODOT-COPYRIGHT-INVENTORY.txt) — the
  engine's exhaustive copyright/license inventory and bundled license texts;
  SHA-256 `cb1980c88089573bcacd7221d777c689bb8bbd778799f24c27fca0fe5f774d6d`.

Status: **initial extraction complete, per-build reconciliation open.** The
inventory documents the source tree at the pinned commit, including components
that may be excluded from a particular export template or platform. M8.6/T15
must reconcile the exact contents of each shipped package against this
inventory and the actual export templates before notices are called complete.

Notable inventory entries that affect release handling:

- Godot's `misc/logo/*` marks are **CC-BY-4.0**, not CC0 and not part of the
  original-asset claim. Do not ship or display a Godot logo unless the press-kit
  use and attribution evidence is recorded.
- Engine-bundled fonts include Apache-2.0 (`Droid Sans`) and OFL-1.1 (`Inter`,
  `JetBrains Mono`, `Noto Sans`, `Open Sans`, `Vazirmatn`). An original UI font
  does not remove engine-bundled font data; applicable font notices must ship
  if that data is exported.

### Development tools

Python, Git, ffmpeg, and the host compiler are development/test infrastructure,
not original project material and not necessarily distribution dependencies.
Their versions, license classifications, notice locations, and open gaps are
in [`provenance/DEPENDENCIES.md`](../provenance/DEPENDENCIES.md).

### External creative inputs

None are currently selected. The candidate sources listed in
[`docs/ASSET_PRODUCTION.md`](../docs/ASSET_PRODUCTION.md) are candidates only,
not adopted dependencies. Any future external creative input requires verified
item-level CC0 evidence (or an explicit scope decision for other terms) and a
manifest record before inclusion.

## Evidence requirements

Every project-authored work item must carry enough provenance to connect the
output to its source recipe, authoring route, and rights basis. Required fields
and record conventions are in
[`provenance/MANIFEST_CONTRACT.md`](../provenance/MANIFEST_CONTRACT.md).

Never set missing facts to an invented author, model, rights holder, or
signature. Unknown legal origin blocks shipping affected material even when
nonlegal authoring metadata is incomplete. Provider/account terms and the
standing owner/contributor authority basis are registered separately in
[`provenance/PROVIDER_TERMS.md`](../provenance/PROVIDER_TERMS.md) and
[`provenance/OWNER_AUTHORITY.md`](../provenance/OWNER_AUTHORITY.md); the
standing authority basis is recorded, while the per-route account/terms
evidence behind it remains open (OI-01 residue, OI-02, OI-03).

## Release description

Use this statement and do not expand it:

> “Original Roadstorm Racer! source is released under the Unlicense. Original
> game art, audio, and learned model artifacts are dedicated under CC0. Engine
> and dependency notices are included separately.”

## Offline Licenses screen

The later in-game Licenses screen (M6.5/M9.1) must work offline and include the
original-project statement, the CC0 notice, the pinned Godot notice, and the
relevant dependency texts. That screen is not built yet; these files are the
source material for it.

## Status

Initial M0.3 inventory: original scope documented, Godot notices extracted,
Unlicense preserved. This is not license acceptance or closing of M0.3. See
[`provenance/OPEN_ITEMS.md`](../provenance/OPEN_ITEMS.md) for unresolved
provider-term/account evidence, per-build-notice, tool-notice, and screening
items.
