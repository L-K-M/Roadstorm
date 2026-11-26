# Open and unverified items

Consolidated initial M0.3 status, prepared 2026-11-26 from input revision
`0ea596a4fa85ade19375e130313f020ed6010619`. Revised 2026-11-26 by audit job
`a67680d9-2923-4992-a350-5804f0fcc193` (StepFun `step-5-preview` through Pi):
OI-01 was re-scoped to the plan's actual requirement and OI-11 was added.
These items are unresolved and must not be treated as closed by agent-authored
text or a successful local command.

| ID | Item | Why open | Blocks | Close condition |
| --- | --- | --- | --- | --- |
| OI-01 | Owner/contributor dedication authority basis | The standing basis is now recorded from user-supplied plan/instructions in [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md); the plan requires that standing record, not a signed instrument. Residue: per-route account/ownership and provider-terms compatibility (OI-02/OI-03); the legal-basis assessment where no copyright arises; external-contributor records; no legal review performed | Shipping affected material until OI-02/OI-03 resolve; M0 acceptance "no dependency or creative input has unknown terms"; T15 public-domain claims for agent-authored output | [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md) remains the standing record; each route's [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md) entry reaches VERIFIED / COMPATIBLE-WITH-CONDITIONS; each new external contributor adds their own record |
| OI-02 | LongCat provider terms (`pi-longcat`, `longcat/LongCat-2.5`) | Official terms URL/version/date, input-rights basis, and output redistribution/dedication compatibility not recorded or verified | Shipping affected code/docs/assets until resolved; M0 acceptance “no dependency or creative input has unknown terms” | Register entry marked `VERIFIED`/`COMPATIBLE-WITH-CONDITIONS` with bounded snapshot and hash |
| OI-03 | StepFun provider terms (`pi-stepfun`, `step-5-preview`) | Same as OI-02 for the observed StepFun route | Shipping affected material until resolved | Same as OI-02 |
| OI-04 | Per-build engine/export-template notice reconciliation | Extracted `GODOT-COPYRIGHT-INVENTORY.txt` covers the source tree at the pinned commit, not the exact component set of each export template/platform | Final third-party notices, offline Licenses screen completeness, T15 package audit | Reconcile actual export contents/templates against inventory; record inclusions/exclusions per platform |
| OI-05 | Development-tool notice copies | Python/Git/FFmpeg license texts are located by path/hash but not copied into `licenses/`; no relevant tool is currently redistributed | Distribution only if those code/binaries become package inputs | Pin tools and copy required notices when redistribution becomes relevant |
| OI-06 | Training-stack versions and licenses | Learned-opponent training framework is not adopted/pinned; planning/review material mentions candidate frameworks without a decision | M4B start; any model provenance | Pin versions, record licenses/notices, pin compute budget and data/model provenance |
| OI-07 | External creative inputs | None selected; baseline must remain original LLM-produced content unless an explicit scope decision accepts verified item-level CC0 | Release if any external input is proposed without evidence | Item-level CC0 evidence (or approved exception terms + scope decision) and manifest lineage before inclusion |
| OI-08 | Trademark/privacy/publicity screening | Working title/car/rival names and product marks have not been screened; CC0 does not resolve these rights | M5.8 preliminary screening, M9.6 final confirmation | Recorded jurisdiction/registry searches with date, evidence, limitations; unresolved risks stay visible |
| OI-09 | Formal runtime pin approval | Godot 4.7.2 and export templates were observed and hashed, but M0.1 has not yet approved canonical download URLs/checksums as the project pin | M0.1 close; reproducible clean-checkout setup | M0.1 records approved version, source, checksums, verification procedure, and change rule |
| OI-10 | Engine-bundled font/mark notices in exports | Inventory shows Apache-2.0/OFL-1.1 fonts and CC-BY-4.0 logo assets; whether they ship in a given export and which notices are required is unresolved | Final offline Licenses screen/package audit | Package contents audit and notice copy step at M8.6/T15 |
| OI-11 | StepFun route notation in [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md) | The register describes the Pi StepFun route as "invoked as `stepfun/step-5-preview` through Pi", a spelling that is ambiguous with the OpenRouter model ID of the same name; the observed route is Pi provider `stepfun`, model `step-5-preview` (session evidence for jobs `9390c59e`, `a04dc96f`, `a67680d9`). That file is owned by the provider-terms job and was not corrected here | Nothing directly; risks registering the wrong route's terms | The provider-terms job rewrites the row as "pi provider `stepfun`, model `step-5-preview`" and keeps the OpenRouter alternative (`openrouter` / `stepfun/step-5-preview`) distinct |

## Not open

- Root Unlicense preservation: `LICENSE` is unchanged relative to input revision
  `0ea596a4` and its SHA-256 is recorded in
  [`../licenses/README.md`](../licenses/README.md).
- Owner/operator standing authority basis: recorded from user-supplied
  instructions (see OI-01 for the residue). The earlier framing — "no executed
  dedication-authority instrument has been found", with signer identity, legal
  entity, execution date, and jurisdiction required — was stricter than
  [`PLAN.md`](../PLAN.md) M0.3 and
  [`docs/ASSET_PRODUCTION.md`](../docs/ASSET_PRODUCTION.md) and was corrected by
  job `a67680d9` without inventing identity, signature, or legal conclusions.
- Godot source license/inventory extraction at commit
  `ed1daf0bf001b61586d9930840f2f1394092c079`: complete as an initial source-tree
  extraction (see OI-04 for per-build reconciliation).
- External creative packs/samples/datasets: none downloaded or selected. Any
  future input starts as OI-07 and must pass intake.

**OI-11 disposition:** corrected by the coordinator to record the actual Pi `--provider stepfun --model step-5-preview` invocation. This resolves the notation only; OI-03 account terms remain open.
