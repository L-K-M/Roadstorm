# Provider-terms intake — `openai-codex-sol` (native OpenAI Codex)

Bounded evidence for the `openai-codex-sol` authoring route. This file records
what public official primary-source pages state on the retrieval dates below.
It is **not** legal advice and does **not** resolve the intake: see "Status"
and "Unknowns".

Prepared 2026-11-27 from input revision
`d27c8fbd8b5a7d10e02ad259a5ed0035b22f5233`. Route/model as observed in the
register: native OpenAI Codex, self-reported model `gpt-6.2-sol`. No credential,
account configuration, private identifier, or personal data was inspected.

## Retrieval evidence

All fetches were plain HTTPS GETs (`curl -sS -L --max-time 120`) on
2026-11-27. The server sent no `ETag` on these responses; "none sent" means the
header was absent.

| Document | Primary URL | HTTP / bytes | Server `Date` | Raw snapshot (SHA-256) | Derived text (SHA-256) |
| --- | --- | --- | --- | --- | --- |
| Codex product page | https://openai.com/codex/ | 200 / 605439 | Fri, 27 Nov 2026 01:05:15 GMT | `codex-product.20261127T010515Z.html` `413c1700a7dfc4a1a7c03dbd1a4bcdafd1696a8d8efcdcc888b4d1e192c6282f` | `…txt` `8c6efc9ca542a07e263053feafd6c0ad9fdc9c174464676e95e32d11c9a360ba` |
| Europe Terms of Use (consumer) | https://openai.com/policies/terms-of-use/ | 200 / 436011 | Fri, 27 Nov 2026 01:05:15 GMT | `terms-of-use-eu.20261127T010515Z.html` `29ce972e801ded46afc174444b2d0f3654d01610e115cb5f9973c62a9c99883b` | `…txt` `5b98fb8c583996bfaecc975c215cb2cb9d933e75726c2c91c444293157b5f741` |
| Terms of Use (rest of world, consumer) | https://openai.com/policies/row-terms-of-use/ | 200 / 414218 | Fri, 27 Nov 2026 01:05:15 GMT | `terms-of-use-row.20261127T010515Z.html` `8f6048df59c017cff6314297888e636558e064f88370511170d95c36d0308736` | `…txt` `54055024b58342eac55284f18e7057674b93762c90f16a278fbe9c11614e85af` |
| Service terms | https://openai.com/policies/service-terms/ | 200 / 410718 | Fri, 27 Nov 2026 01:05:15 GMT | `service-terms.20261127T010515Z.html` `d3c5afc77d72aa9c15cc9b32cf9ba9660336d44b327216e074d274ec34195527` | `…txt` `49d94a946b15a82cbc4d208aab31aad6df5658123a977eae27142ee9bfc54368` |
| OpenAI Services Agreement (business/API) | https://openai.com/policies/services-agreement/ | 200 / 542525 | Fri, 27 Nov 2026 01:05:16 GMT | `services-agreement.20261127T010515Z.html` `d73287b43cd85cd11b273462337b62d3320c362164c923a0507383ee813c42bc` | `…txt` `c3f4df46669cd1ef369f34a2f392163866984c51494dc986b58ee3d645e70e7d` |
| Usage policies | https://openai.com/policies/usage-policies/ | 200 / 388053 | Fri, 27 Nov 2026 01:05:16 GMT | `usage-policies.20261127T010516Z.html` `92c1b041902aff7e3c490caa52aa40f7d7ddf64a2c194bce6a48e5aae7b617e7` | `…txt` `3eab67e0cec7e60693c60b46e87f2bfb111eb7d509bde0721245b86ebb4b3c24` |
| Sharing & publication policy | https://openai.com/policies/sharing-publication-policy/ | 200 / 334516 | Fri, 27 Nov 2026 01:05:16 GMT | `sharing-publication-policy.20261127T010516Z.html` `140e19c91bafa991247a3d03275e01d6d6f68e84e8934dc25df17284c9001631` | `…txt` `184dde8a4af3ad068e0e46ce716e00ab58a7971034223be2049d850133438b06` |

Derived text is a convenience copy (stdlib-style HTML→text); the raw HTML
snapshot + its SHA-256 is the authoritative captured artifact.

## Document identity and version (as printed)

- **Codex product page**: marketing/product page; states "Codex is included in
  your ChatGPT plan" and lists Plus, Pro, and Business plans. Footer links the
  Terms of Use and Privacy Policy. It is product evidence, not itself a terms
  document.
- **Europe Terms of Use**: "Updated: January 16, 2026"; applies if the user
  resides in the EEA, Switzerland, or UK; contract with OpenAI Ireland Ltd
  (EEA/Switzerland) or OpenAI OpCo, LLC (UK). States: "Our Business Terms govern
  use of ChatGPT Enterprise, our APIs, and our other services for businesses
  and developers."
- **Terms of Use (ROW)**: "Published: January 1, 2026", "Effective: January 1,
  2026"; applies outside the EEA/Switzerland/UK; contract with OpenAI OpCo,
  LLC. Same Business Terms carve-out.
- **Service terms**: "Updated: November 13, 2026"; governs use of the Services;
  includes §4 "Codex and Code Generation."
- **OpenAI Services Agreement**: "Updated: December 1, 2025", "Effective:
  January 1, 2026"; states it "only applies to use of OpenAI's APIs, ChatGPT
  Enterprise, ChatGPT Business, ChatGPT for Clinicians, and other services for
  customers who are businesses and developers, and does not apply to OpenAI
  services used by consumers or individuals unless specified above." The
  "Business Terms" links in the ToU point to `https://openai.com/policies/business-terms/`,
  which redirects to the Services Agreement URL captured here.
- **Usage policies**: "Effective: November 20, 2026".
- **Sharing & publication policy**: "Updated: November 14, 2022".

## Which instrument applies to this route (per the official pages)

The Codex product page presents Codex as included in ChatGPT plans and links the
general Terms of Use; it does not publish a separate Codex-only terms document.
The applicable instrument therefore depends on whether the actual route is a
consumer ChatGPT/Codex plan or an API/business/enterprise route:

- Consumer plan → Terms of Use (EU or ROW variant), incorporating the Service
  Terms and Usage Policies.
- API / ChatGPT Business / Enterprise → OpenAI Services Agreement (linked as
  "Business Terms"), plus Service Terms and Usage Policies.

No dedicated Codex-only terms page was located at `openai.com/policies/`.

## Clauses bearing on input and output rights

- **Terms of Use (both variants), "Ownership of content"**: "As between you and
  OpenAI, and to the extent permitted by applicable law, you (a) retain your
  ownership rights in Input and (b) own the Output. We hereby assign to you all
  our right, title, and interest, if any, in and to Output."
- **Services Agreement §4.1**: "As between Customer and OpenAI, to the extent
  permitted by applicable law, Customer: (a) retains all ownership rights in
  Input; and (b) owns all Output. OpenAI hereby assigns to Customer all OpenAI's
  right, title, and interest, if any, in and to Output."
- **Input-rights basis**: user/customer represents and warrants it has all
  rights, licences, and permissions needed to provide Input (ToU "Your content";
  Services Agreement §4.3).

## Provider use, licences, and training

- **Terms of Use, "Our use of content"** (Europe wording quoted; the ROW
  variant uses substantially the same sentence): "We can use your Content
  worldwide to provide, maintain, develop, and improve our Services, comply with
  applicable law, enforce our terms and policies and keep our Services safe."
  Both variants offer an account-level opt-out from training use ("If you do not
  want us to use your Content to train our models, you have the option to opt
  out…"). This is a **default provider use licence with an opt-out**.
- **Services Agreement §4.2**: "OpenAI will only use Customer Content as
  necessary to provide Customer with the Services, comply with applicable law,
  enforce the OpenAI Policies, and prevent abuse. OpenAI will not use Customer
  Content to develop or improve the Services, unless Customer explicitly agrees
  to such use." §9.2 grants only limited rights reasonably necessary to deliver
  the Services; §9.3 makes Feedback usable without restriction.

## Distribution, AI labels, and conditions

- **Ownership/distribution**: neither the ToU nor the Services Agreement
  contains an express general-purpose prohibition on redistributing an owned
  Output. Conditions attach to *use*.
- **Misrepresentation / AI label**: ToU prohibits "Representing that Output was
  human-generated when it was not" (EU) / "Represent that Output was
  human-generated when it was not" (ROW).
- **Sharing & publication policy**: when posting prompts/completions or
  livestreaming, "Manually review each generation before sharing", "Attribute
  the content to your name or your company", and "Indicate that the content is
  AI-generated in a way no user could reasonably miss or misunderstand."
- **Service Terms §4 (Codex and Code Generation)**: "Output generated by code
  generation features of our Services, including OpenAI Codex, may be subject to
  third party licenses, including, without limitation, open source licenses."
- **Competing-model restrictions**: ToU prohibits "Using Output to develop
  models that compete with OpenAI"; Services Agreement §3.3(e) prohibits using
  Output to develop competing AI models except for a Permitted Exception.
- **Accuracy condition**: ToU requires evaluating Output for accuracy and
  appropriateness, including human review, before using or sharing Output.

## Dedication-compatibility observations (not a determination)

- Both families assign the provider's rights in Outputs to the user/customer and
  keep Input rights with the user/customer, which is the ownership fact a
  public-domain dedication would rely on.
- The consumer family permits default provider use/improvement (with an opt-out)
  and imposes an anti-misrepresentation duty on sharing; the business/API family
  limits provider use and contains no broad default improvement licence, but
  adds Customer obligations/restrictions and the Service Terms' third-party
  licence caveat for code output. Whether either family is compatible with
  dedicating affected project material to the public domain is **unresolved**
  and is an owner/legal question, not one this intake can close.

## Cross-route comparison (with `claude-code-opus`)

| Dimension | `openai-codex-sol` (native OpenAI Codex) | `claude-code-opus` (Claude Code) |
| --- | --- | --- |
| Public instruments located | Consumer ToS (EEA/CH/UK and ROW variants); Service Terms (incl. Codex §4); Services Agreement (API/Enterprise/Business); Usage Policies; Sharing & Publication Policy | Claude Code legal page maps route to Consumer ToS (Free/Pro/Max/Ultra) or Commercial ToS (Team/Enterprise/API); plus AUP |
| Output ownership | ToU §Content and Services Agreement §4.1: user/customer owns Output; provider assigns any rights; Inputs stay with user/customer | Consumer §4 / Commercial §B: user/customer owns Outputs; provider assigns any rights; Inputs stay with user/customer |
| Provider use of content | Consumer ToU: Content usable to provide/maintain/develop/improve services; account opt-out for training. Services Agreement §4.2: only as necessary to provide; no develop/improve unless explicitly agreed | Consumer: Materials usable to improve services and train models unless account opt-out (two carve-outs remain). Commercial: no training on Customer Content; no broad default improvement licence found |
| Distribution limits | No express general redistribution ban found; must not represent Output as human-generated; must evaluate before sharing; code-generation Output may carry third-party licences (Service Terms §4) | No express general redistribution ban found; use-based conditions (non-commercial-only in consumer terms; no competing-model use; AUP limits) |
| AI-label/disclosure conditions | ToU prohibits misrepresenting Output as human-generated; Sharing & Publication Policy requires indicating AI-generated status when sharing; Service Terms §4 flags third-party-licence condition for code output | AUP context-specific duties (high-risk advice/decision; consumer-facing chatbot disclosure); no blanket label clause found |
| Account facts still unknown | ChatGPT consumer plan vs API/business/enterprise route; jurisdiction; which regional ToU applies; model/version mapping of `gpt-6.2-sol` | Plan/subscription vs API key; jurisdiction; whether EEA/CH consumer terms or another region's terms apply; model/version mapping of `claude-opus-5-5` |

## Unknowns / limitations

- **Account/route type unknown.** Native OpenAI Codex may be used through a
  consumer ChatGPT plan or an API/business/enterprise route; those map to
  different instruments. This job did not inspect the local auth/account
  configuration, per the privacy boundary.
- **Jurisdiction unknown.** Which regional ToU (Europe vs ROW) applies to the
  actual account is unknown.
- **Model version unknown.** `gpt-6.2-sol` is an observed local model ID, not
  verified against a published OpenAI model/version. The Codex page mentions a
  "GPT-6.2" research index entry but publishes no terms tied to it.
- Documents incorporated by reference but **not retrieved here**: Privacy
  Policy, Data Processing Addendum, Brand Guidelines, Service Credit Terms,
  Businesses in ChatGPT terms, and any Order Form/enterprise agreement. Their
  contents are not summarized.
- Captured snapshots are single point-in-time fetches; re-verify on any
  route/terms change. The comparison is factual only and is not a legal
  determination.

## Status

**OPEN / BLOCKING — documents located and quoted; applicability unresolved.**
Which instrument family governs the actual route (consumer plan vs API/business),
the account type, jurisdiction, and terms version accepted are unknown. Do not
treat `openai-codex-sol` outputs as cleared for shipping/dedication until the
owner/authorized reviewer resolves these and links the instrument in
[`../OWNER_AUTHORITY.md`](../OWNER_AUTHORITY.md).
