# M0.3 rights and provenance inventory — task record

| Field | Value |
| --- | --- |
| Milestone/task | M0.3 initial rights and provenance inventory |
| Job | rights `00b1219c-b656-45e1-b2ad-84f26776eb36` |
| Role / provider | implementation / LongCat (`longcat/LongCat-2.5`) through Pi |
| Input revision | `0ea596a4fa85ade19375e130313f020ed6010619` |
| Prepared | 2026-11-26 |
| Owned paths | `licenses/**`, `provenance/**` only |

## Delivered

Initial M0.3 inventory documents and extracted notices:

- Material-specific license scope, Unlicense preservation, CC0 notice, evidence
  requirements, third-party notice index, and release statement:
  [`../licenses/README.md`](../licenses/README.md).
- Official CC0 1.0 legal code copy:
  [`../licenses/CC0-1.0-legalcode.txt`](../licenses/CC0-1.0-legalcode.txt).
- Extracted Godot MIT/Expat license and exhaustive copyright/license inventory
  at the pinned commit:
  [`../licenses/GODOT-LICENSE-MIT.txt`](../licenses/GODOT-LICENSE-MIT.txt),
  [`../licenses/GODOT-COPYRIGHT-INVENTORY.txt`](../licenses/GODOT-COPYRIGHT-INVENTORY.txt).
- Provenance index/conventions:
  [`README.md`](README.md).
- Owner/contributor authority record form (status OPEN):
  [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md).
- Provider-terms register for all LLM-authored material (status OPEN for both
  observed routes): [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md).
- Dependency inventory with observed versions, licenses, notices, and gaps:
  [`DEPENDENCIES.md`](DEPENDENCIES.md).
- Provenance manifest contract and record templates:
  [`MANIFEST_CONTRACT.md`](MANIFEST_CONTRACT.md).
- Consolidated open/unverified items: [`OPEN_ITEMS.md`](OPEN_ITEMS.md).

This is an initial inventory, not M0 acceptance. It creates no dedication,
signature, or legal authority.

## Commands and checks run

| Command | Result |
| --- | --- |
| `git rev-parse HEAD` | `0ea596a4fa85ade19375e130313f020ed6010619` |
| `git diff --stat -- LICENSE`; `git status --short LICENSE` | empty / no changes; root Unlicense preserved |
| `shasum -a 256 LICENSE` | `6b0382b16279f26ff69014300541967a356a666eb0b91b422f6862f6b7dad17e` |
| `godot --version` | `4.7.2.stable.official.ed1daf0bf` |
| `git ls-remote https://github.com/godotengine/godot.git refs/tags/4.7.2-stable` | `ed1daf0bf001b61586d9930840f2f1394092c079` — matches runtime commit prefix `ed1daf0bf` |
| `cat .../export_templates/4.7.2.stable/version.txt` | `4.7.2.stable` |
| `lipo -archs /Applications/Godot.app/Contents/MacOS/Godot` | `x86_64 arm64` |
| `shasum -a 256` on editor binary and target export templates | recorded in [`DEPENDENCIES.md`](DEPENDENCIES.md) |
| `python3 --version`; local Python `LICENSE.txt` hash | `3.15.2`; `b0e25a78cffb43f4d92de8b61ccfa1f1f98ecbc22330b54b5251e7b6ba010231` |
| `ffmpeg -version`; local FFmpeg copying hashes | `9.0.2_1`, GPL-configured build; see [`DEPENDENCIES.md`](DEPENDENCIES.md) |
| `git --version`; `sw_vers`; `clang --version` | `2.54.0`; macOS `27.0.1`; Apple clang `21.0.0` |
| `curl` official CC0 legal-code text and Godot `LICENSE.txt`/`COPYRIGHT.txt` at pinned commit | retrieved 2026-11-26; hashes below |
| `find licenses provenance -type f -exec shasum -a 256` | hashes below (task-record self-hash excluded) |
| `rg -a -l` for Godot MIT copyright, Jolt (`2021, Jorrit Rouwe`), and Inter font copyright strings in `/Applications/Godot.app/Contents/MacOS/Godot` | all matched; corroborates that extracted notices correspond to installed-runtime bundled data |
| Secret-pattern scan over created files | no API keys/tokens/credentials found; only the local auth-file path is mentioned |

## Artifacts and hashes

```text
a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499  licenses/CC0-1.0-legalcode.txt
cb1980c88089573bcacd7221d777c689bb8bbd778799f24c27fca0fe5f774d6d  licenses/GODOT-COPYRIGHT-INVENTORY.txt
b0435e3b3e4e55238f05f4b306f30524a1b2e20147810d436eaa554fa6855c80  licenses/GODOT-LICENSE-MIT.txt
62f8ce5bd08e7e3fed0c0744696c5863c9017cf2ee615e386d4fcfdd7933b545  licenses/README.md
c76f974bccd2e7e5cdf0f3a5bda324c997874a70b2d555286e21d86bb83a088d  provenance/DEPENDENCIES.md
e05e629126438cd7a700fc88d172e2f9afe15bdbc6856e6fef85d6c1c27d7aea  provenance/MANIFEST_CONTRACT.md
325abfb82d89a9793d13eea6c50c7f3ddae3281bdb56f4c9a01b509ec57aab62  provenance/OPEN_ITEMS.md
6c62632272ab8e7356d584ddb19c85f0ea0021a821884dc5d391d70286129df1  provenance/OWNER_AUTHORITY.md
7087e09b2c4d017f85f033091dbb061fa609fd3392b977d2a897044f4212286e  provenance/PROVIDER_TERMS.md
13e78b1fa4782fb93d1a61facc7ab6901a4612c1a5ef8422788cd291cb4ee7fd  provenance/README.md
```

This task record's own hash is intentionally excluded because including it would
change the file. The extracted Godot notices and the engine binary/template
hashes are recorded in [`DEPENDENCIES.md`](DEPENDENCIES.md).

## Limitations and defects

- **OI-01:** No executed owner/contributor authority instrument exists. The
  inventory documents the requirement and consequences but cannot close it.
  *(Initial-inventory framing; re-scoped by the a67680d9 audit — the plan
  requires a standing owner/operator record, not a signed instrument. See the
  audit addendum below and OI-01.)*
- **OI-02/OI-03:** LongCat and StepFun terms are unverified. No affected
  material may ship as Unlicense/CC0-backed project output until the register
  entries are verified.
- **OI-04/OI-10:** The extracted Godot inventory is source-tree evidence at the
  pinned commit, not a per-export notice reconciliation. Engine-bundled fonts
  and marks still need package-content verification.
- **OI-05/OI-06/OI-09:** Development-tool notice copies, training-stack pins,
  and formal M0.1 pin approval remain open.
- **Not attempted:** legal advice, trademark searches, signature creation,
  dependency installation/download beyond small public license texts, or
  changes outside `licenses/**` and `provenance/**`.

No implementation defect was found in the preserved root `LICENSE` or in the
observed Godot version correspondence. Concurrent work by other agents in the
shared checkout was left untouched.

## Audit addendum — job `a67680d9-2923-4992-a350-5804f0fcc193` (2026-11-26)

Focused provenance-inventory accuracy audit and correction. The initial
inventory above is preserved unchanged; this addendum records the audit and the
corrections applied to the four files this job owned.

| Field | Value |
| --- | --- |
| Milestone/task | M0.3 rights/provenance inventory — accuracy audit |
| Job | rights-audit `a67680d9-2923-4992-a350-5804f0fcc193` |
| Role / provider | audit / StepFun 5 Preview — pi provider `stepfun`, model `step-5-preview` (session evidence; not the OpenCode `stepfun-ai-step-plan/step-5-preview` route, which produced no repository material) |
| Base revision | `0ea596a4fa85ade19375e130313f020ed6010619` (same input revision as the initial inventory) |
| Owned paths | `provenance/OWNER_AUTHORITY.md`, `provenance/OPEN_ITEMS.md`, `provenance/TASK_M0.3_RIGHTS.md`, `licenses/README.md` only |

### Finding and correction: authority basis stricter than the plan

The initial inventory required an "executed dedication-authority instrument"
with signer name/role, legal entity, execution date, and jurisdiction
(`OWNER_AUTHORITY.md`), and OI-01's close condition depended on a human
executing it. PLAN.md M0.3 and docs/ASSET_PRODUCTION.md require only a standing
record from the authorized owner/operator identifying the dedication basis and
covered authoring accounts/routes; they prescribe no signed instrument,
identity fields, legal review, or approval ceremony, and forbid inventing
signatures or rights holders.

Corrections implemented:

- `provenance/OWNER_AUTHORITY.md` rewritten: records the user-supplied
  authorization and dedication intent truthfully (plan rights/authorship
  commitments, asset-production policy, standing agent instructions and task
  assignments, retained root Unlicense), the covered configured agent routes
  (observed: `pi-longcat`, `pi-stepfun`), and an explicit "does not establish"
  list — no identity/entity, no signature or ceremony, no legal conclusions, no
  rights created. Genuinely missing authority/account-term evidence stays open:
  per-route account/provider-terms compatibility (OI-02/OI-03), the
  no-copyright-arises legal-basis assessment, external-contributor records,
  and legal review. No request for a signature was made and none is needed
  under the plan.
- `provenance/OPEN_ITEMS.md`: OI-01 re-scoped from "no executed instrument
  found" to the recorded standing basis plus its open residue; the "Not open"
  section records the corrected framing; OI-11 added for the StepFun route
  notation defect in `PROVIDER_TERMS.md` (see below).
- `licenses/README.md`: authority-basis references aligned — the root LICENSE
  is not itself the authority record; the standing basis is in
  `OWNER_AUTHORITY.md`; status wording no longer lists "authority" as wholly
  unresolved.

### StepFun route check

No wrong StepFun route exists in this job's owned files: OI-03 and the task
record use `pi-stepfun` / pi provider `stepfun`, model `step-5-preview`, which
matches session evidence for jobs `9390c59e`, `a04dc96f`, and this audit. One
defect was found outside this job's ownership and was **not** corrected:
`provenance/PROVIDER_TERMS.md` describes the route as "invoked as
`stepfun/step-5-preview` through Pi", a spelling ambiguous with the OpenRouter
model ID of the same name; it is recorded as OI-11 for the provider-terms job.
The OpenCode route `stepfun-ai-step-plan/step-5-preview` from the user's
standing notes is a real configured route but has produced no repository
material and is not registered.

### Pre-existing inaccuracies found and left as recorded facts

- The initial hash table lists `provenance/OPEN_ITEMS.md` as `325abfb8…`, but
  the file as received by this audit hashed to `8c4beb9d…`. The cause is not
  determinable from repository records (`provenance/` is untracked in Git; all
  files share one mtime). The content reads as the initial inventory; the
  drift is recorded here rather than silently re-baselined.
- `provenance/PROVIDER_TERMS.md` now hashes to `9327a94e…` versus the recorded
  `7087e09b…`; that file belongs to the provider-terms job (retrieval work
  after the initial inventory) and was not touched here.

### Post-correction hashes (2026-11-26, after this audit's edits)

```text
2bda3b1f35f687962b60a5c4db09187f26bbe02950ccbedcb7c33857bb355255  provenance/OWNER_AUTHORITY.md
0c95aac2cb43e81ea0da8e9af963c8bf8da6b9c00ec95da544ea2e5a594bfc8e  provenance/OPEN_ITEMS.md
97fa23d541d72f3d1f9b873ecacb7cf3520247122fcfd9f7e1ed6cb02450f7dc  licenses/README.md
```

This task record's own hash is intentionally excluded because including it
would change the file. Unchanged files keep the hashes in the initial table
above (`licenses/CC0-1.0-legalcode.txt`, `licenses/GODOT-*.txt`,
`provenance/DEPENDENCIES.md`, `provenance/MANIFEST_CONTRACT.md`,
`provenance/README.md`).

### Unresolved facts after this audit

- OI-02/OI-03: LongCat and StepFun account/route terms and their
  compatibility with public-domain dedication remain unverified; affected
  material must not ship until resolved.
- OI-11: the StepFun route notation in `PROVIDER_TERMS.md` (other job's file).
- The OPEN_ITEMS.md hash drift above is unexplained.
- The owner/operator's legal identity, any employer authority, and the
  no-copyright-arises assessment are deliberately unrecorded; nothing in this
  audit supplies them.

### Authority boundary

This addendum was produced by an LLM agent. It does not execute any
instrument, sign for any person, assign rights, create a dedication, or
provide legal advice. It records authorization and dedication intent the user
supplied, and leaves genuinely missing authority/account-term evidence open.

## Authority boundary

This record was produced by an LLM agent. It does not execute any instrument,
sign for any person, assign rights, or create a dedication. Any future
statement that project material is dedicated rests on the standing
owner/operator authority record in
[`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md) — which the plan requires as a
recorded basis, not a signed human instrument — together with compatible,
verified provider terms referenced by
[`PROVIDER_TERMS.md`](PROVIDER_TERMS.md).

## Reconciliation addendum — job `42e44973-c074-4141-aac7-9e7f0524a9e1` (2026-11-27)

Provenance reconciliation across the files this lineage owns
(`provenance/*.md`, `licenses/README.md`), using the findings of audit job
`b701fff7-4b11-49fc-bfb2-fb63be4af335`, `PLAN.md` M0.3,
[`docs/ASSET_PRODUCTION.md`](../docs/ASSET_PRODUCTION.md), and the committed
`review/` reports. It corrects supported factual contradictions only. It does
not claim rights are cleared, invent any identity/signature/legal fact, inspect
credentials, touch the `provider_terms/` snapshots, or mutate Git, and it adds
no network access.

| Field | Value |
| --- | --- |
| Job | provenance reconciliation `42e44973-c074-4141-aac7-9e7f0524a9e1` |
| Role / provider | reconciliation / StepFun 5 Preview — pi provider `stepfun`, model `step-5-preview` (session evidence) |
| Base revision | `7b27c2f` (working tree matched HEAD for the owned files before edits) |
| Owned paths | `provenance/*.md` and `licenses/README.md` only; `provenance/provider_terms/**` snapshots untouched |

### Corrections applied

- **Authority basis (finding 1).** Removed the residual signed-"instrument"
  requirement wording from the current records: `provenance/README.md` record
  index (OWNER_AUTHORITY now **RECORDED** standing basis, not "OPEN — no
  executed instrument") and its conventions; `provenance/MANIFEST_CONTRACT.md`
  ("applies to", storage block, closing condition); and this file's concluding
  "Authority boundary". The initial-inventory OI-01 bullet is preserved
  verbatim with an added pointer marking it the superseded initial framing.
  `docs/ASSET_PRODUCTION.md:135` ("owner/contributor authority instrument") is
  outside this job's ownership and was **not** edited — see open issues.
- **Reviewer/provider routes (finding 2).** `provenance/PROVIDER_TERMS.md` no
  longer claims no candidate route "has produced repository material yet". It
  now registers the reviewer/checkpoint routes that authored committed
  `review/` reports — `devin-cli`/`swe-2-1-max`, `opencode-zai-glm`/
  `zai-coding-plan/glm-5.4`, `pi-mistral`/`mistral-large-4`,
  `claude-code-opus`/`claude-opus-5-5`, `pi-venice-opus`/`claude-opus-5-5`,
  `openai-codex-sol`/`gpt-6.2-sol`, and `codex-cli-agent` (model unknown) —
  each **UNKNOWN / BLOCKING** (no terms captured). `provenance/OWNER_AUTHORITY.md`
  notes these routes produced committed material without asserting their terms
  are cleared.
- **Asset manifest (finding 3).** Corrected the stale "does not exist / not yet
  created / (future)" claims in `provenance/DEPENDENCIES.md`,
  `provenance/MANIFEST_CONTRACT.md`, and `provenance/README.md` to present the
  existing empty registry (`registry_status: "empty"`, 2026-11-26) accurately.
- **Toolchain pin (finding 4).** `provenance/OPEN_ITEMS.md` OI-09 and
  `provenance/DEPENDENCIES.md` now record that a pin record exists
  (`tools/toolchain/pin/engine.txt` + `checksums.txt`, `upstream_verified=yes`)
  and that only formal M0.1 sign-off remains open.
- **Artifact hashes (finding 5).** Historical hash tables are preserved
  unchanged. Current hashes are re-recorded with a date below, kept distinct
  from the historical values.
- **Tool inventory (finding 6).** `provenance/DEPENDENCIES.md` D4 now reflects
  that tracked project scripts exist (Python is an adopted development tool),
  and D6 now states FFmpeg is referenced only as an optional (skip-if-absent)
  test dependency in `tools/ci/tests/run_tests.sh`.

### Hash drift, historical vs current

The historical tables (the initial inventory's artifact list and the a67680d9
post-correction list) are left as evidence. Two recorded values no longer match
the committed files because those files were edited after that audit and
committed in `7733fb1`: `provenance/OPEN_ITEMS.md` (recorded `0c95aac2…`,
committed `17015a31…`) gained an OI-11 disposition note, and
`provenance/PROVIDER_TERMS.md` (recorded `9327a94e…`, committed
`d8abe531…`) had its StepFun route wording corrected. The provenance files are
tracked in Git, so the a67680d9 addendum's "`provenance/` is untracked …
unexplained" note no longer applies; the drift is attributable to those
post-audit edits. The values below supersede the historical ones only for
identifying the **current** files.

### Re-recorded current hashes (2026-11-27, working tree after this job's edits)

Not committed by this job (no Git mutation performed). This task record's own
hash is excluded, as before.

```text
9d61b31a3fc811ad1f38dfd993a98fd3d232111518506030442b97150c52e0af  licenses/README.md
a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499  licenses/CC0-1.0-legalcode.txt
b0435e3b3e4e55238f05f4b306f30524a1b2e20147810d436eaa554fa6855c80  licenses/GODOT-LICENSE-MIT.txt
cb1980c88089573bcacd7221d777c689bb8bbd778799f24c27fca0fe5f774d6d  licenses/GODOT-COPYRIGHT-INVENTORY.txt
f576d515c465d416fdf68faa67d822e04500d6da30eb9f7d9fd0f0ee35a53d80  provenance/DEPENDENCIES.md
ffc873191ebba7ff3b7634dfbf92053d3832fd540b24bc346670b9899a1634bb  provenance/MANIFEST_CONTRACT.md
baedc4effb3d0f37f4106a9bc4e759c8c191c7035befcbb3662e789e0194e01f  provenance/OPEN_ITEMS.md
74cba72cd9b51d2ca541a038b96c85fc533f36cfb211b9a96d1ef81a3dfcae99  provenance/OWNER_AUTHORITY.md
518139c0abf480c14df7867b50f5287b4d5995653bc13c1f36929d875f8b0428  provenance/PROVIDER_TERMS.md
e646019aa6d473940266e8a1627f51197d21d94de3bf1455c3231a55d27544b1  provenance/README.md
```

The `provenance/provider_terms/**` snapshots and INTAKE files were not touched;
their SHA-256 values remain those recorded in
[`PROVIDER_TERMS.md`](PROVIDER_TERMS.md).

### Open issues after this reconciliation

- **OI-02/OI-03/OI-12:** no authoring or reviewer route's provider/account terms
  are verified; affected material must not ship as cleared project output.
- **Review-report material scope (OI-12):** whether committed review reports
  are dedicated "project material" or only review evidence is an explicit
  policy decision that is not made here.
- **External-input policy boundary (OI-07):** CC0-only vs. an explicit
  scope-decision exception is unresolved.
- **Out-of-ownership residue:** `docs/ASSET_PRODUCTION.md:135` still uses
  "owner/contributor authority instrument"; `docs/ASSET_PRODUCTION.md` external
  licensing characterizations (Kenney/Poly Haven/Freesound, Godot press kit)
  carry no captured evidence. Both are outside this job's owned paths and are
  flagged for the owning job, not edited here.
- No identity, signature, employer authority, or no-copyright-arises legal
  determination is supplied by this reconciliation.

### Authority boundary

This addendum was produced by an LLM agent. It executes no instrument, signs
for no person, assigns no rights, creates no dedication, and gives no legal
advice. It preserves the user-supplied standing authorization in
[`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md) and the existing provider-terms
snapshots unchanged, and it leaves genuinely missing account-term evidence
open.
