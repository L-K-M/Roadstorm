# Provider-terms intake — `pi-longcat` (LongCat / Meituan)

Bounded evidence for the `pi-longcat` authoring route. This file records what a
public primary-source page states on the retrieval date below. It is **not**
legal advice and does **not** resolve the intake: see "Status" and "Unknowns".

## Retrieval evidence

| Field | Value |
| --- | --- |
| Route ID | `pi-longcat` |
| Primary source URL | https://longcat.chat/platform/private/ |
| Final URL (after redirects) | https://longcat.chat/platform/private/ (0 redirects) |
| Retrieval date/time (UTC) | 2026-11-26 21:46:53 |
| HTTP status / content-type | 200 / `text/html; charset=utf-8` |
| Body size | 74419 bytes |
| Server `Date` header | Thu, 26 Nov 2026 21:48:00 GMT |
| Server `ETag` | `"a8cd11297a9a9c7b13898560f117bfb1"` |
| `Last-Modified` header | none sent |
| Server header note | `x-computed-uri: /platform/private/index.html` (server: openresty) |
| Raw snapshot | `private.20261126T214653Z.html` |
| Raw SHA-256 | `5d71fd8d9bee5aa97587234ffd657ec5c5b5093adc35fc795592477620e0670d` |
| Derived text | `private.20261126T214653Z.txt` (stdlib HTML→text of the snapshot) |
| Derived text SHA-256 | `6413137fcf43bab70e936df5dca98e93d658e5af35bd82f144813f565a958867` |

Derived text is a convenience copy for quoting; the raw HTML snapshot + its
SHA-256 is the authoritative captured artifact.

## Document identity (as printed on the page)

- Page title: **"LongCat AI Platform Terms of Use | LongCat Platform Policies"**.
- Stated operator: **Beijing Kuxun Interactive Technology Co., Ltd.** and its
  affiliates ("we"/"LongCat"). Contact emails are `@meituan.com`
  (Meituan-affiliated). The page is the **API Platform Terms of Use**, which by
  its own text "constitutes a part of the LongCat AI User Service Agreement" and
  "applies specifically to you as an individual or enterprise developer ... who
  uses the Platform's Application Programming Interfaces (APIs)".
- Governing law (§11.1): **Singapore**. Disputes (§11.2): negotiation, then
  binding **SIAC arbitration**, seat Singapore, English.
- **Version/date:** the page body prints **no** explicit version number or
  "last updated"/effective date. Version is therefore **unknown**.

## Clauses bearing on input rights

- §2.1 (definitions): "the model generates output content (including text,
  tables, and code) as a response based on the information you and your end
  users input (collectively, 'Input')." — Output is stated to include **code**,
  directly relevant to this project's outputs.
- §3.9 (Input Data Responsibility): "By submitting any content, you represent
  and warrant that you have all necessary rights, licenses, and permissions to
  do so, and that such content does not infringe any third party's intellectual
  property rights ... All liabilities arising from your input or improper use of
  outputs shall be borne solely by you."

## Clauses bearing on output rights

- §4.1 (Platform Ownership): "all ownership and intellectual property rights in
  the LongCat model belong to us, including but not limited to model
  parameters, algorithms, code, and framework structure." (Platform keeps the
  model; this does not address the user's own outputs.)
- §4.2 (User Rights in Input and Output): "Subject to applicable law and
  compliance with this Agreement, you retain all intellectual property and other
  rights in your Input and Output content." Caveat in the same clause: "your
  rights in Output content do not extend to content generated for other users."
- §4.5 (Moral Rights Waiver): to the fullest extent permitted by law, you waive
  moral rights in content you submit to the Platform.
- §4.6 (Feedback): feedback grants LongCat an unrestricted, perpetual,
  irrevocable, royalty-free, worldwide, non-exclusive right to use it.

## Conditions on Input/Output (license grants and labeling)

- §4.3 (License Grant to Platform): "you grant us and our affiliates a free,
  worldwide, transferable, sublicensable, and royalty-free license to use your
  Input, Output, and optimization suggestions for purposes including but not
  limited to services optimization, brand promotion, and marketing, to the
  extent permitted by applicable law. Users who require restrictions on the use
  of Input, Output, and optimization suggestions for training or improving
  LongCat AI models may contact us to discuss available enterprise arrangements
  or separate written agreements. Unless otherwise expressly agreed in writing,
  Input, Output, and optimization suggestions may be used for the foregoing
  purposes." — i.e., a **broad provider license applies by default**, with
  training/improvement use excluded only via a separate enterprise/written
  arrangement.
- §3.3 (AI Content Labeling): developer must label AI-generated content when
  distributing it and must not remove explicit/implicit identifiers (metadata,
  watermarks) the Platform embeds.
- §3.10 (Prohibited Uses): includes "Training or fine-tuning competing AI models
  using our service outputs" and reverse-engineering the model.

## Dedication-compatibility observations (not a determination)

- §4.2 states the user **retains** IP in Input and Output "subject to applicable
  law and compliance with this Agreement," which is the clause a public-domain
  dedication (Unlicense/CC0) would rely on.
- However §4.3 grants LongCat a **free, worldwide, transferable, sublicensable**
  license over Input and Output by default (training/improvement use only
  removable via a separate enterprise/written arrangement). Whether that grant is
  compatible with a clean public-domain dedication of the affected material —
  and whether an enterprise/no-training arrangement is in force for the actual
  account — is **unresolved** and is an owner/legal question, not one this
  intake can close.

## Applicability to the actual Pi route

- Subject-matter match is plausible: the page is the API Platform Terms of Use
  and the route `longcat/LongCat-2.5` is an API route (base URL
  `https://api.longcat.chat/openai/v1`, per non-secret provider metadata).
- **Not confirmed for the account:** which terms version the specific account
  accepted, the account type (Individual vs Enterprise — relevant to §4.3), and
  whether any separate written/enterprise arrangement exists. The account/auth
  file contains credentials and was **not** inspected (per privacy boundary).

## Unknowns / limitations

- No printed version number or effective/"last updated" date on the page.
- The page incorporates by reference documents **not retrieved here**: the
  "LongCat AI User Service Agreement" and the "LongCat AI Platform Privacy
  Policy." Conflict rule stated: this Platform Agreement prevails over others.
- Account acceptance, account type, plan, legal entity for the actual route, and
  existence of any training-restriction arrangement are all **unknown** without
  inspecting the (forbidden) account configuration.
- Governing law is Singapore; interaction with PRC/other law and with the
  project's dedication intent is a legal question outside this record.
- A single fetch is one point-in-time capture; re-verify on any route/terms
  change.

## Status

**OPEN / BLOCKING — document located and quoted, conditions unresolved.**
Applicability to the specific account, terms version, and the §4.3 default
license's compatibility with public-domain dedication are not established. Do
not treat `pi-longcat` outputs as cleared for shipping/dedication until the
owner/authorized reviewer resolves these and links the instrument in
[`../OWNER_AUTHORITY.md`](../OWNER_AUTHORITY.md).
