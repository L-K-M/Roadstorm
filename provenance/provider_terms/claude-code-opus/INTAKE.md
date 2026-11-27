# Provider-terms intake — `claude-code-opus` (first-party Claude Code CLI)

Bounded evidence for the `claude-code-opus` authoring route. This file records
what public official primary-source pages state on the retrieval dates below.
It is **not** legal advice and does **not** resolve the intake: see "Status"
and "Unknowns".

Prepared 2026-11-27 from input revision
`d27c8fbd8b5a7d10e02ad259a5ed0035b22f5233`. Route/model as observed in the
register: Claude Code CLI, self-reported model `claude-opus-5-5`. No credential,
account configuration, private identifier, or personal data was inspected.

## Retrieval evidence

All fetches were plain HTTPS GETs (`curl -sS -L --max-time 120`) on
2026-11-27. The server sent no `ETag` on these responses; "none sent" below
means the header was absent.

| Document | Primary URL | HTTP / bytes | Server `Date` | `Last-Modified` | Raw snapshot (SHA-256) | Derived text (SHA-256) |
| --- | --- | --- | --- | --- | --- | --- |
| Claude Code Docs — Legal and compliance | https://code.claude.com/docs/en/legal-and-compliance | 200 / 202491 | Fri, 27 Nov 2026 01:05:14 GMT | Thu, 26 Nov 2026 19:10:34 GMT | `code-legal-and-compliance.20261127T010514Z.html` `01098af4bf8d5b5b792607c2f8b4f99675f7dfcff9daeb5ed42d07268b951ef4` | `…txt` `fb2fab63b9c148b6c02077111217429a866be6267a71b8493a42e49708249bfc`; official `.md` alternate `…md` `1a7c59468a71304f19e6ce74c8d23b7d71382b81daa5d1c7afe524cc644d6e16` |
| Consumer Terms of Service | https://www.anthropic.com/legal/consumer-terms | 200 / 600361 | Fri, 27 Nov 2026 01:05:14 GMT | none sent | `consumer-terms.20261127T010514Z.html` `00a5cd91e78750219d73e7587414e07339c5ac5c2762987fbc2288bb14d1745e` | `…txt` `90aa0566d79bcb75ac9a2693c994a49641bd0011c9cff488fa4bda03057419af` |
| Commercial Terms of Service | https://www.anthropic.com/legal/commercial-terms | 200 / 212036 | Fri, 27 Nov 2026 01:05:15 GMT | none sent | `commercial-terms.20261127T010514Z.html` `02b6942c46798e1a88224070acb01bf7c124ddcc00611f09077403413f0b08fb` | `…txt` `1f76e460dd6742d7a483d5368d36c5699fb0506431ddea65d77d08b9188c2e7c` |
| Usage Policy (AUP) | https://www.anthropic.com/legal/aup | 200 / 991182 | Fri, 27 Nov 2026 01:05:15 GMT | none sent | `aup.20261127T010515Z.html` `2c1b07d1a2eaaa88e20ca3ca68ac5245a9e2875425911354d22a64dd659ce987` | `…txt` `ca40590d77ae89b5e5d7cb652c255a1dc5ea52791523cf217f105a18f16d06cf` |

Derived text is a convenience copy (stdlib-style HTML→text, plus the page's own
official Markdown alternate where offered); the raw HTML snapshot + its SHA-256
is the authoritative captured artifact. For the Claude Code docs page, quote
from the `.md` alternate: its `.txt` extraction contains the page's embedded
application JSON as well as prose.

## Document identity and version (as printed)

- **Claude Code Docs — "Legal and compliance"**: official Claude Code documentation
  page. Embedded metadata gives `dateModified` 2026-10-30T17:44:30.688Z; server
  `Last-Modified` 2026-11-26 19:10:34 GMT. It states which terms govern Claude
  Code by plan (see below).
- **Consumer Terms of Service**: printed "Effective Oct 8, 2025", Type
  "Terms", Audience "Individual". The page states it applies to "a consumer who
  is resident in the European Economic Area or Switzerland"; the named
  contracting entity is Anthropic Ireland, Limited.
- **Commercial Terms of Service**: printed "Effective Jun 17, 2025", Audience
  "Business"; "Services under these Terms are not for consumer use."
- **Usage Policy (AUP)**: printed "Effective Nov 12, 2026", Audience "All
  users"; states it applies to anyone submitting inputs, including individuals
  using Claude.ai and Claude Code and developers/businesses using the API.

## Which instrument applies to this route (per the official docs page)

The Claude Code Docs page states:

> Your use of Claude Code is subject to:
> - Commercial Terms of Service - for Team, Enterprise, and Claude API users
> - Consumer Terms of Service - for Free, Pro, Max, and Ultra users

and:

> Claude Code remains governed by Anthropic's standard terms (see the License
> and Commercial agreements sections above) regardless of the platform through
> which it is accessed.

So the applicable instrument turns on the **account/route type**, which this
job did not and cannot determine from public sources.

## Clauses bearing on input and output rights

- **Consumer §4 (Inputs, Outputs, Actions, and Materials)**: "As between you
  and Anthropic, and to the extent permitted by applicable law, you retain any
  right, title, and interest that you have in such Inputs. Subject to your
  compliance with our Terms, we assign to you all our right, title, and
  interest (if any) in Outputs."
- **Commercial §B (Customer Content)**: "As between the parties and to the
  extent permitted by applicable law, Anthropic agrees that Customer (a)
  retains all rights to its Inputs, and (b) owns its Outputs. Anthropic
  disclaims any rights it receives to the Customer Content under these Terms.
  Subject to Customer's compliance with these Terms, Anthropic hereby assigns
  to Customer its right, title and interest (if any) in and to Outputs."
- **Input-rights basis in both**: the user/customer warrants it has the rights
  and permissions needed for its Inputs (Consumer §4; Commercial §L.1).

## Provider use, licences, and training

- **Consumer §4 ("Our use of Materials")**: "We may use Materials to provide,
  maintain, and improve the Services and to develop other products and
  services, including training our models, unless you opt out of training
  through your account settings. Even if you opt out, we will use Materials
  for model training when: (1) you provide Feedback to us regarding any
  Materials, or (2) your Materials are flagged for safety review…"
  ("Materials" = Inputs + Outputs, per §4 definition.) This is a **default
  provider use/training licence with an account-level opt-out**; two carve-outs
  remain even after opt-out.
- **Commercial §B**: "Anthropic may not train models on Customer Content from
  Services." **Commercial §F (Intellectual Property)**: "Except as expressly
  stated in these Terms, these Terms do not grant either party any rights to
  the other's content or intellectual property, by implication or otherwise."
  No broad default training/improvement licence over Customer Content appears in
  the captured Commercial Terms.

## Distribution, AI labels, and conditions

- **Ownership/distribution**: neither captured ToS contains an express
  general-purpose prohibition on redistributing an owned Output. Conditions
  attach to *use* of the Services/Materials.
- **Consumer §11 ("Non-commercial use only")**: "You agree that you will not
  use our Services for any commercial or business purposes and we and our
  Providers have no liability to you for any loss of profit, loss of business,
  business interruption, or loss of business opportunity." This condition is
  printed in the EEA/Switzerland consumer terms.
- **Consumer §3**: prohibited to "develop any products or services that
  compete with our Services, including to develop or train any artificial
  intelligence or machine learning algorithms or models or resell the
  Services."
- **Commercial §D.4 (Use Restrictions)**: no accessing the Services to build a
  competing product/service, including training competing AI models or
  reselling; no reverse engineering.
- **AI disclosure (AUP, context-specific, not a blanket output label rule)**:
  - High-risk advice/decisions: "An individual who receives advice or who is
    the subject of a decision based on a High-risk AI Recommendation must be
    clearly told that AI was used to produce it."
  - Consumer-facing chatbots/agents: "All consumer-facing chatbots or AI agents
    that communicate directly with external users must disclose to users that
    they are interacting with AI rather than a human."
  - No general "label every Output" clause was found in the captured Consumer
    Terms, Commercial Terms, or AUP.

## Dedication-compatibility observations (not a determination)

- Both instruments assign the provider's rights in Outputs to the user/customer
  and keep Input rights with the user/customer, which is the ownership fact a
  public-domain dedication would rely on.
- The consumer route additionally permits provider use of Materials for
  improvement/training by default (subject to account opt-out) and states a
  non-commercial-use-only condition; the commercial route promises no training
  on Customer Content. Whether either instrument is compatible with dedicating
  affected project material to the public domain is **unresolved** and is an
  owner/legal question, not one this intake can close.

## Cross-route comparison (with `openai-codex-sol`)

| Dimension | `claude-code-opus` (Claude Code) | `openai-codex-sol` (native OpenAI Codex) |
| --- | --- | --- |
| Public instruments located | Claude Code legal page maps route to Consumer ToS (Free/Pro/Max/Ultra) or Commercial ToS (Team/Enterprise/API); plus AUP | Consumer ToS (EEA/CH/UK and ROW variants); Service Terms (incl. Codex §4); Services Agreement (API/Enterprise/Business); Usage Policies; Sharing & Publication Policy |
| Output ownership | Consumer §4 / Commercial §B: user/customer owns Outputs; provider assigns any rights it has; Inputs stay with user/customer | ToU §Content and Services Agreement §4.1: user/customer owns Output; provider assigns any rights; Inputs stay with user/customer |
| Provider use of content | Consumer: Materials usable to improve services and train models unless account opt-out (two carve-outs remain). Commercial: no training on Customer Content; no broad default improvement licence found | Consumer ToU: Content usable to provide/maintain/develop/improve services; account opt-out for training. Services Agreement §4.2: only as necessary to provide; no develop/improve unless explicitly agreed |
| Distribution limits | No express general redistribution ban found; use-based conditions (non-commercial-only in consumer terms; no competing-model use; AUP limits) | No express general redistribution ban found; must not represent Output as human-generated; must evaluate before sharing; code-generation Output may carry third-party licences (Service Terms §4) |
| AI-label/disclosure conditions | AUP context-specific duties (high-risk advice/decision; consumer-facing chatbot disclosure); no blanket label clause found | ToU prohibits misrepresenting Output as human-generated; Sharing & Publication Policy requires indicating AI-generated status when sharing; Service Terms §4 flags third-party-licence condition for code output |
| Account facts still unknown | Plan/subscription vs API key; jurisdiction; whether EEA/CH consumer terms or another region's terms apply; model/version mapping of `claude-opus-5-5` | ChatGPT consumer plan vs API/business/enterprise route; jurisdiction; which regional ToU applies; model/version mapping of `gpt-6.2-sol` |

## Unknowns / limitations

- **Account/route type unknown.** The first-party Claude Code CLI can be
  authenticated with a Claude subscription (OAuth) or an Anthropic API key;
  the official docs map those to different terms. This job did not inspect the
  local auth/account configuration, per the privacy boundary.
- **Jurisdiction unknown.** The only consumer ToS page located is the
  EEA/Switzerland version; no separate US or other-region consumer terms page
  was located in Anthropic's official legal index/sitemap. Whether the actual
  user/account is covered by this regional version is unknown.
- **Model version unknown.** `claude-opus-5-5` is an observed local model ID,
  not verified against a published Anthropic model/version.
- Documents incorporated by reference but **not retrieved here**: Anthropic
  Privacy Policy, Data Processing Addendum, Service-Specific Terms, Trademark
  Guidelines, Supported Regions policy. Their contents are not summarized.
- Captured snapshots are single point-in-time fetches; re-verify on any
  route/terms change. The comparison is factual only and is not a legal
  determination.

## Status

**OPEN / BLOCKING — documents located and quoted; applicability unresolved.**
Which instrument governs the actual route (subscription vs API), the account
type/plan, jurisdiction, and terms version accepted are unknown. Do not treat
`claude-code-opus` outputs as cleared for shipping/dedication until the
owner/authorized reviewer resolves these and links the instrument in
[`../OWNER_AUTHORITY.md`](../OWNER_AUTHORITY.md).
