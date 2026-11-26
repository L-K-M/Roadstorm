# Provider-terms intake

Status: **OPEN — no provider/service terms entry has been verified.** On
2026-11-26 the two observed routes below had their official primary-source
terms located and captured as bounded snapshots, but locating a document is not
verification: account/version applicability and output-dedication compatibility
remain unresolved, so both rows stay OPEN/BLOCKING. This register covers all
LLM-produced project material, including software, docs, tests, recipes,
scores, and training tools, not only remote media generation.

Rule: identify the applicable provider/service/account or route terms,
version/date, input-rights basis, and output redistribution/dedication
compatibility before the provider's first use. Unknown or incompatible legal
origin blocks inclusion of affected material. Do not assume one provider's
terms apply to another. Keep private identifiers and credentials out of this
public record.

Prepared 2026-11-26 from input revision
`0ea596a4fa85ade19375e130313f020ed6010619`.

## Observed authoring routes

| Route ID | Service / API route | Model(s) observed | Terms document, version, date | Input-rights basis | Output redistribution / dedication compatibility | Verification |
| --- | --- | --- | --- | --- | --- | --- |
| `pi-longcat` | LongCat (Meituan); base URL `https://api.longcat.chat/openai/v1`; accessed through the local Pi harness | `longcat/LongCat-2.5` | LongCat AI Platform Terms of Use (part of LongCat AI User Service Agreement); operator Beijing Kuxun Interactive Technology Co., Ltd.; **no printed version/date**; retrieved 2026-11-26 — [intake](provider_terms/pi-longcat/INTAKE.md) | §3.9/§4.2: user warrants rights to submit; user retains IP in Input and Output (§4.2, subject to law + agreement) | §4.2 user retains output IP, **but** §4.3 grants LongCat a free/worldwide/transferable/sublicensable license to Input+Output by default (training/improvement excluded only via enterprise/written arrangement); §3.3 AI-labeling on distribution. **Conditions unresolved.** | **OPEN / BLOCKING** — document located & quoted; account version + dedication compatibility unresolved |
| `pi-stepfun` | StepFun (Step Plan); base URL `https://api.stepfun.ai/step_plan/v1`; invoked through Pi with `--provider stepfun --model step-5-preview` | `step-5-preview` | StepFun开放平台用户协议 (Open Platform User Agreement); operator 上海阶跃星辰智能科技; stated effective 2026-04-08; retrieved 2026-11-26 — [intake](provider_terms/pi-stepfun/INTAKE.md) | §2.1.3: input rights remain with you/original author; §5.2 output IP belongs to you/rights-holder under law (within law) | §5.2 assigns output IP to user, **but** §5.3 + §6.5 grant StepFun broad default licenses over uploaded content/data (incl. "improve the large-model service"); §2.2.4 AI-labeling on redistribution. **Conditions unresolved.** | **OPEN / BLOCKING** — document located & quoted; account/endpoint + dedication compatibility unresolved |

Observed task references at preparation time:

- `pi-longcat`: jobs `00b1219c-b656-45e1-b2ad-84f26776eb36` (this rights job),
  `c0a9220f-157c-4641-8c7a-82b3b64b6aa2` (schemas), and the M0 tick-probe job
  described as LongCat 2.5. Job/task text is evidence of the route used, not of
  terms.
- `pi-stepfun`: job `9390c59e-cae3-4e4e-baba-d86618c7a2ed` (M0 shell).

The local service names and base URLs come from the environment's non-secret
Pi provider metadata. They are not license terms. Account type, plan, legal
entity, and terms version are deliberately not inferred. The local auth file
contains credentials and was not copied or inspected for content.

## Candidate routes not yet adopted for project output

The session environment also advertises other authoring routes (for example
Zai coding-plan models through OpenCode, Mistral through Vibe, Venice models,
Devin SWE, Cline, Command Code, and OpenRouter free routes). None is recorded
as having produced repository material yet. Each must receive its own register
entry before first use. In particular, the mandatory independent checkpoint
reviewers required by [`PLAN.md`](../PLAN.md) must have their actual
provider/account route and output terms registered before their review output
is treated as project material.

## Intake procedure

For each new provider/service/account or route used to produce project
material:

1. Create a register row before or at first use, with the route and model ID.
2. Capture the applicable official terms URL, document/version, and retrieval
   date. Store a bounded snapshot under
   `provenance/provider_terms/<route-id>/` with its SHA-256; link it here.
3. Record the input-rights basis: who supplies prompts/data and what rights
   apply to those inputs.
4. Record output ownership/redistribution permission and whether public-domain
   dedication (Unlicense/CC0) by the owner/operator is compatible with those
   terms.
5. Mark the entry `VERIFIED`, `COMPATIBLE-WITH-CONDITIONS`, or
   `UNKNOWN/BLOCKING`. Re-review when the provider terms or route version
   changes.
6. Link every affected authoring record to this register entry and to the
   authority instrument in [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md).
7. Never store API keys, tokens, passwords, or personal identifiers here.

An agent cannot execute these records on a person's behalf. Provider terms may
grant or restrict the user's rights independently of the project's dedication
intent; silence or ambiguity must be resolved before affected material ships.

## Entry template

```text
Route ID:            <provider-or-cli>/<service-or-model-route>
Service/account:     <official service name>; account type/plan if legally relevant
Model(s):            <model ID(s)>
Terms source:        <official URL>
Terms version/date:  <version or document date>; retrieved <YYYY-MM-DD>
Snapshot:            provenance/provider_terms/<route-id>/<file>  sha256:<hash>
Input-rights basis:  <who supplied inputs; licensed/owned/public domain/unknown>
Output rights:       <ownership and redistribution permissions>
Dedication check:    <compatible / conditions / incompatible / unknown>
Verification:        <verified / unknown-blocking>
```

## Primary-source retrieval and bounded snapshots (2026-11-26)

The official terms for both observed routes were retrieved once on 2026-11-26
(~21:46 UTC) and stored as bounded snapshots under
`provenance/provider_terms/<route-id>/` with SHA-256. Per-route notes quote the
operative input/output clauses and list unknowns. Retrieving and quoting a
document does **not** verify account applicability or dedication compatibility;
both intake items remain OPEN.

| Route | Primary source | Retrieval (UTC) | HTTP / bytes | Server `Date` / `ETag` | Raw snapshot | Raw SHA-256 |
| --- | --- | --- | --- | --- | --- | --- |
| `pi-longcat` | https://longcat.chat/platform/private/ | 2026-11-26 21:46:53 | 200 / 74419 | 2026-11-26 21:48:00 GMT / `"a8cd11297a9a9c7b13898560f117bfb1"` | [`private.20261126T214653Z.html`](provider_terms/pi-longcat/private.20261126T214653Z.html) | `5d71fd8d9bee5aa97587234ffd657ec5c5b5093adc35fc795592477620e0670d` |
| `pi-stepfun` | https://platform.stepfun.com/legal/user-agreement.html | 2026-11-26 21:46:53 | 200 / 208680 | 2026-11-26 21:48:01 GMT / `W/"32f28-1a2123c0be1"` (Last-Modified 2026-11-25 10:24:14 GMT) | [`user-agreement.20261126T214653Z.html`](provider_terms/pi-stepfun/user-agreement.20261126T214653Z.html) | `fb3e3705fb0c8d77c09696424fa93ed0091ec39c77ab7fd2bda403f2e72259ba` |

Each route directory also holds a stdlib HTML→text extraction of its snapshot
(for quoting) and an `INTAKE.md`:

- [`provider_terms/pi-longcat/INTAKE.md`](provider_terms/pi-longcat/INTAKE.md)
  (text SHA-256 `6413137fcf43bab70e936df5dca98e93d658e5af35bd82f144813f565a958867`)
- [`provider_terms/pi-stepfun/INTAKE.md`](provider_terms/pi-stepfun/INTAKE.md)
  (text SHA-256 `56c4dd406c3f3b50191b48055473ae15f1fd7728bfb2327e3c2fd9ff69cfdcb7`)

These captures are one point-in-time evidence of the public pages; they do not
close OI-02/OI-03 and are not legal determinations.
