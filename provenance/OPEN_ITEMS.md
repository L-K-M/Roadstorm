# Open and unverified items

Consolidated initial M0.3 status, prepared 2026-11-26 from input revision
`0ea596a4fa85ade19375e130313f020ed6010619`. Revised 2026-11-26 by audit job
`a67680d9-2923-4992-a350-5804f0fcc193` (StepFun `step-5-preview` through Pi):
OI-01 was re-scoped to the plan's actual requirement and OI-11 was added.
Reconciled 2026-11-27 by job `42e44973-c074-4141-aac7-9e7f0524a9e1` (StepFun 5
Preview through Pi): OI-07 and OI-09 were sharpened to match committed
artifacts and policy, and OI-12 was added for reviewer/checkpoint route terms
and the review-report material-scope question. These items are unresolved and
must not be treated as closed by agent-authored text or a successful local
command.

| ID | Item | Why open | Blocks | Close condition |
| --- | --- | --- | --- | --- |
| OI-01 | Owner/contributor dedication authority basis | The standing basis is now recorded from user-supplied plan/instructions in [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md); the plan requires that standing record, not a signed instrument. Residue: per-route account/ownership and provider-terms compatibility (OI-02/OI-03); the legal-basis assessment where no copyright arises; external-contributor records; no legal review performed | Shipping affected material until OI-02/OI-03 resolve; M0 acceptance "no dependency or creative input has unknown terms"; T15 public-domain claims for agent-authored output | [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md) remains the standing record; each route's [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md) entry reaches VERIFIED / COMPATIBLE-WITH-CONDITIONS; each new external contributor adds their own record |
| OI-02 | LongCat provider terms (`pi-longcat`, `longcat/LongCat-2.5`) | The owner confirmed standard public terms and no custom agreement on 2026-11-27; an official public snapshot and input/output clauses are recorded. The accepted revision, incorporated documents, AI-labeling obligations, and output redistribution/dedication compatibility are not verified. | Shipping affected code/docs/assets until resolved; M0 acceptance “no dependency or creative input has unknown terms” | Register entry marked `VERIFIED`/`COMPATIBLE-WITH-CONDITIONS` after the remaining conditions are resolved |
| OI-03 | StepFun provider terms (`pi-stepfun`, `step-5-preview`) | The owner confirmed standard public terms and no custom agreement on 2026-11-27; an official public snapshot and input/output clauses are recorded. Endpoint applicability, accepted revision, incorporated documents, AI-labeling obligations, and output redistribution/dedication compatibility remain unverified. | Shipping affected material until resolved | Same as OI-02 |
| OI-04 | Per-build engine/export-template notice reconciliation | Extracted `GODOT-COPYRIGHT-INVENTORY.txt` covers the source tree at the pinned commit, not the exact component set of each export template/platform | Final third-party notices, offline Licenses screen completeness, T15 package audit | Reconcile actual export contents/templates against inventory; record inclusions/exclusions per platform |
| OI-05 | Development-tool notice copies | Python/Git/FFmpeg license texts are located by path/hash but not copied into `licenses/`; no relevant tool is currently redistributed | Distribution only if those code/binaries become package inputs | Pin tools and copy required notices when redistribution becomes relevant |
| OI-06 | Training-stack versions and licenses | Learned-opponent training framework is not adopted/pinned; planning/review material mentions candidate frameworks without a decision | M4B start; any model provenance | Pin versions, record licenses/notices, pin compute budget and data/model provenance |
| OI-07 | External creative inputs | None selected; the baseline must remain original LLM-produced content. Open policy boundary: [`docs/ASSET_PRODUCTION.md`](../docs/ASSET_PRODUCTION.md) states that only verified item-level CC0 is compatible with the creative-asset policy, while these records describe a possible explicit-scope-decision exception; whether any non-CC0 external creative input can ever be admitted (and on what terms) is an unresolved policy decision, not settled here | Release if any external input is proposed without evidence | A recorded policy decision on the CC0-only vs. scope-decision boundary, plus item-level CC0 evidence (or approved exception terms) and manifest lineage before any inclusion |
| OI-08 | Trademark/privacy/publicity screening | Working title/car/rival names and product marks have not been screened; CC0 does not resolve these rights | M5.8 preliminary screening, M9.6 final confirmation | Recorded jurisdiction/registry searches with date, evidence, limitations; unresolved risks stay visible |
| OI-09 | Formal runtime pin approval | A pinned-runtime record now exists (`tools/toolchain/pin/engine.txt` + `checksums.txt`: canonical editor/template/checksum URLs, observed SHA-256 digests, `upstream_verified=yes`; `docs/TOOLCHAIN.md`); what remains open is formal M0.1 milestone sign-off approving that record as the project pin, not the absence of a pin record | M0.1 close; reproducible clean-checkout setup | M0.1 records approved version, source, checksums, verification procedure, and change rule |
| OI-10 | Engine-bundled font/mark notices in exports | Inventory shows Apache-2.0/OFL-1.1 fonts and CC-BY-4.0 logo assets; whether they ship in a given export and which notices are required is unresolved | Final offline Licenses screen/package audit | Package contents audit and notice copy step at M8.6/T15 |
| OI-11 | StepFun route notation in [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md) | The register describes the Pi StepFun route as "invoked as `stepfun/step-5-preview` through Pi", a spelling that is ambiguous with the OpenRouter model ID of the same name; the observed route is Pi provider `stepfun`, model `step-5-preview` (session evidence for jobs `9390c59e`, `a04dc96f`, `a67680d9`). That file is owned by the provider-terms job and was not corrected here | Nothing directly; risks registering the wrong route's terms | The provider-terms job rewrites the row as "pi provider `stepfun`, model `step-5-preview`" and keeps the OpenRouter alternative (`openrouter` / `stepfun/step-5-preview`) distinct |
| OI-12 | Reviewer/checkpoint route terms and review-report material scope | Committed `review/` reports were produced by routes (Devin `swe-2-1-max`, OpenCode `zai-coding-plan/glm-5.4`, Mistral Large 4 via Pi, Claude Opus 5.5 as a Claude Code agent and via provider `venice`, OpenAI Codex `gpt-6.2-sol`, and Codex plan-review agents of unknown model) whose provider/account terms are not captured or verified; each is registered in [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md) as UNKNOWN/BLOCKING. Whether review reports count as dedicated "project material" for the register's shipping scope (vs. review evidence) is itself an open policy decision | Treating any affected review output as cleared project material; T15 public-domain claims for that output | Each reviewer route's terms captured and marked VERIFIED / COMPATIBLE-WITH-CONDITIONS, plus an explicit recorded decision on review-report material scope |

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
