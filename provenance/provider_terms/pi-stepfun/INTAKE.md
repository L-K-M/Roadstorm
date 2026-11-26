# Provider-terms intake — `pi-stepfun` (StepFun 阶跃星辰)

Bounded evidence for the `pi-stepfun` authoring route. This file records what a
public primary-source page states on the retrieval date below. It is **not**
legal advice and does **not** resolve the intake: see "Status" and "Unknowns".
The agreement is in Chinese; quotations are given in the original with an
English gloss. Glosses are the recorder's paraphrase, not an official
translation.

## Retrieval evidence

| Field | Value |
| --- | --- |
| Route ID | `pi-stepfun` |
| Primary source URL | https://platform.stepfun.com/legal/user-agreement.html |
| Final URL (after redirects) | https://platform.stepfun.com/legal/user-agreement.html (0 redirects) |
| Retrieval date/time (UTC) | 2026-11-26 21:46:53 |
| HTTP status / content-type | 200 / `text/html; charset=UTF-8` |
| Body size | 208680 bytes |
| Server `Date` header | Thu, 26 Nov 2026 21:48:01 GMT |
| `Last-Modified` header | Wed, 25 Nov 2026 10:24:14 GMT |
| Server `ETag` | `W/"32f28-1a2123c0be1"` (server: nginx) |
| Raw snapshot | `user-agreement.20261126T214653Z.html` |
| Raw SHA-256 | `fb3e3705fb0c8d77c09696424fa93ed0091ec39c77ab7fd2bda403f2e72259ba` |
| Derived text | `user-agreement.20261126T214653Z.txt` (stdlib HTML→text of the snapshot) |
| Derived text SHA-256 | `56c4dd406c3f3b50191b48055473ae15f1fd7728bfb2327e3c2fd9ff69cfdcb7` |

Derived text is a convenience copy for quoting; the raw HTML snapshot + its
SHA-256 is the authoritative captured artifact.

## Document identity (as printed on the page)

- Title: **"StepFun开放平台用户协议"** (StepFun Open Platform User Agreement).
- Stated operator: **上海阶跃星辰智能科技股份有限公司** (Shanghai Jieyue Xingchen
  / StepFun).
- **Stated effective date: "最新版本生效日期：2026年4月8日"** (latest version
  effective 2026-04-08). This is the version anchor printed on the page; the
  page was `Last-Modified` 2026-11-25 by the server.
- Governing law / venue (§9): **PRC mainland law**; disputes to the people's
  court at the company's domicile (litigation, not arbitration).

## Clauses bearing on input rights

- §2.1.3: "在法律允许的范围，您或您的最终用户基于本服务输入的文字、图片、音频、
  视频等内容（输入内容）的全部权利均仅归您或原作者所有，输入内容均不会因上传、
  发布等行为发生知识产权等权利的转移。" — Within the scope permitted by law,
  all rights in input content remain with you or the original author; uploading
  does not transfer IP. (Input rights stay with the user/original author.)

## Clauses bearing on output rights

- §5.2: "对于您使用本平台提供的相关生成式人工智能服务而输出的内容，在适用法律
  允许的范围内，输出的内容的知识产权及产生的其他财产权益（如有）归属于您或适用
  法律规定的权利人。" — Within the scope permitted by law, IP and other property
  interests (if any) in the generative-AI output belong to you or the rights
  holder prescribed by law.
- §5.1: the Platform/service IP itself is owned by StepFun and affiliates.
- §5.4: "本平台运行过程中所产生的一切数据由我们享有合法权利" — except as
  otherwise provided by law/agreement, data generated in the course of platform
  operation is legally owned by StepFun.

## Conditions on Input/Output (license grants and labeling)

- §5.3: "对于您发布上传或传输的内容，您授予我们一项免费且无需标注个人身份的、
  在法律允许范围内合理且最大程度的许可使用（包括但不限于存储、使用、复制、修订、
  编辑等）的权利，以为实现本协议目的、提升大模型服务体验进行使用。" — You grant
  StepFun a free, no-attribution, reasonable-and-maximal (within law) license to
  store/use/copy/revise/edit content you upload/publish/transmit, to fulfil the
  agreement and improve the large-model service experience. **Broad provider
  license by default.**
- §6.5: you authorize StepFun to use/process data you generate via the service
  to provide, diagnose, improve, optimize, and upgrade the service (with stated
  reasonable security/confidentiality measures).
- §2.2.4: StepFun adds explicit labels and implicit (file-metadata) labels to
  AI-generated content; users must keep labels accurate and intact when
  disseminating and must not delete, alter, fabricate, or conceal them.
  **Condition on redistribution of outputs.**
- §2.2.3(3): prohibited to use the service/outputs to develop or train competing
  models or services.

## Dedication-compatibility observations (not a determination)

- §5.2 assigns output IP/property interests to the user "within the scope
  permitted by law," which is the clause a public-domain dedication would rely
  on; §2.1.3 keeps input rights with the user/original author.
- However §5.3 and §6.5 grant StepFun broad default licenses over
  uploaded/transmitted content and generated data (including to "improve the
  large-model service"), and §2.2.4 imposes AI-labeling duties on
  redistribution. Whether these are compatible with a clean public-domain
  dedication of the affected material is **unresolved** and is an owner/legal
  question, not one this intake can close.

## Applicability to the actual Pi route

- Subject-matter match is plausible: the agreement covers "本平台" (the open
  platform) and "模型及API技术服务" (model and API technical services); the
  route `step-5-preview` is invoked as an API route (base URL
  `https://api.stepfun.ai/step_plan/v1`, per non-secret provider metadata).
- **Not confirmed for the account:** whether the specific "Step Plan"
  (`step_plan`) endpoint and the specific account are governed by *this* user
  agreement versus a separate Step Plan / service-level agreement, and which
  version the account accepted. The account/auth file contains credentials and
  was **not** inspected (per privacy boundary).

## Unknowns / limitations

- The page incorporates by reference documents **not retrieved here**: the
  "服务规则" (service rules, preamble), 《开放平台管理规则及公约》 (Open Platform
  Management Rules and Convention, §2.2.10), and 《StepFun开放平台隐私政策》
  (Privacy Policy, §6.1).
- Account acceptance, account type (individual vs enterprise), plan, legal
  entity, and the governing endpoint-specific agreement for the actual route are
  all **unknown** without inspecting the (forbidden) account configuration.
- Governing law is PRC; interaction with the project's dedication intent is a
  legal question outside this record.
- Glosses are the recorder's paraphrase of Chinese originals, not an official
  translation; the authoritative text is the captured snapshot.
- A single fetch is one point-in-time capture; re-verify on any route/terms
  change.

## Status

**OPEN / BLOCKING — document located and quoted, conditions unresolved.**
Applicability to the specific account/endpoint, terms version acceptance, and
the §5.3/§6.5 default licenses' compatibility with public-domain dedication are
not established. Do not treat `pi-stepfun` outputs as cleared for
shipping/dedication until the owner/authorized reviewer resolves these and links
the instrument in [`../OWNER_AUTHORITY.md`](../OWNER_AUTHORITY.md).
