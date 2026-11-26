# Owner/contributor authority basis

Status: **RECORDED — standing basis supplied by the repository
owner/operator; per-route account/provider-terms evidence still open
([`OPEN_ITEMS.md`](OPEN_ITEMS.md) OI-02/OI-03).** This file is the standing
record required by [`PLAN.md`](../PLAN.md) M0.3 and
[`docs/ASSET_PRODUCTION.md`](../docs/ASSET_PRODUCTION.md). It records
authorization and dedication intent the user supplied. It creates no rights,
and it asserts no identity, signature, or legal conclusion.

## What the plan requires

PLAN.md M0.3 requires an "owner/contributor authority basis" and instructs:
"never invent signatures or rights holders." ASSET_PRODUCTION.md states the
requirement precisely:

> M0 establishes the dedication authority once: a record from the authorized
> repository owner/operator identifying the basis on which applicable rights in
> configured agent outputs are dedicated, and which authoring accounts/routes
> it covers. Reference that standing record in task/commit provenance; do not
> require an agent to invent a human signature for every generated file.

> Use the existing license and owner instructions where they already establish
> intent/authorization; record the basis rather than requesting repeated
> approval for routine contributions. Only actual gaps in rights or terms need
> resolution before shipping affected material.

The plan therefore requires a **standing record of the basis and of the
covered authoring accounts/routes**. It does not prescribe a signed legal
instrument, named-signer or identity fields, a legal entity, a jurisdiction, a
legal review, or an approval ceremony, and an agent must not fabricate any of
those. The initial revision of this file (job 00b1219c) demanded an "executed
dedication-authority instrument" with signer name/role, legal entity,
execution date, and jurisdiction, and treated the item as OPEN with no basis
found. That was a stricter requirement than the plan; it is corrected by this
revision (job a67680d9) without deleting the historical record, which remains
in the audit trail below and in [`TASK_M0.3_RIGHTS.md`](TASK_M0.3_RIGHTS.md).

## Basis supplied by the owner/operator (recorded)

The repository owner/operator supplied the following authorization and
dedication intent through user-authored project instructions and standing
direction to the agents:

| Source | What it establishes |
| --- | --- |
| [`PLAN.md`](../PLAN.md) product commitments | Rights: "Original code under the Unlicense; original art/audio dedicated under CC0; complete third-party notices." Authorship: "Every new project-specific script, asset recipe, composition, design, and test produced by LLM agents." |
| [`docs/ASSET_PRODUCTION.md`](../docs/ASSET_PRODUCTION.md) | The dedication policy itself — Unlicense for original software/scripts/structured definitions/docs; CC0-1.0 for original art/audio/model weights/datasets, each to the extent applicable rights exist — and the direction to treat existing owner instructions as the authorization basis |
| Standing user instructions and per-job task assignments in the agent environment | Operational authorization for the configured agent routes to author, test, and review project material. PLAN.md: "People may direct the work, provide credentials, play the game, and make release decisions." |
| Root [`LICENSE`](../LICENSE) (Unlicense) | The project's existing software public-domain dedication, retained unchanged (SHA-256 recorded in [`../licenses/README.md`](../licenses/README.md)) |

Dedication intent recorded: original code, tools, tests, schemas, text
definitions, and documentation are dedicated under the Unlicense; original art,
audio, learned model weights, and authored training datasets are dedicated
under CC0-1.0 — in each case only to the extent applicable rights exist and are
controlled by the relevant contributor. This matches the material-specific
scope in [`../licenses/README.md`](../licenses/README.md).

Covered authoring accounts/routes: the configured LLM agent routes in the
project environment. Observed to have produced project material: `pi-longcat`
(LongCat 2.5 through the local Pi harness) and `pi-stepfun` (StepFun
`step-5-preview` through the local Pi harness), registered in
[`PROVIDER_TERMS.md`](PROVIDER_TERMS.md). Any other configured route needs its
own register entry there before first use; this standing record covers the
configured agent routes as a class. Separately, the independent checkpoint and
plan reviewers' routes (Devin `swe-2-1-max`, OpenCode `zai-coding-plan/glm-5.4`,
Mistral Large 4 via Pi, Claude Opus 5.5 as a Claude Code agent and via provider
`venice`, and OpenAI Codex `gpt-6.2-sol`) have also authored committed review
reports; those routes are registered in
[`PROVIDER_TERMS.md`](PROVIDER_TERMS.md) with terms UNKNOWN/BLOCKING, and
whether such review reports count as dedicated "project material" (rather than
review evidence) is an open policy question recorded as OI-12. This record
does not assert that any reviewer route's terms are cleared.

## What this record does not establish

- **No identity or entity is asserted.** No personal name, legal entity,
  organization, employer, or jurisdiction is recorded, because none was
  supplied in a form this record can verify. Per ASSET_PRODUCTION.md, a GitHub
  handle or account name is an organizational reference, not proof of a
  person's legal identity or employer authority.
- **No signature or execution ceremony.** Nothing here is signed, and the plan
  requires none. This file was written by an LLM agent; an agent cannot sign as
  a person or claim rights on a person's behalf.
- **No legal conclusions.** This record does not determine whether copyright
  subsists in any agent output, whether any output is original, whether it is
  free of third-party claims, or whether any dedication is effective in any
  jurisdiction. Where no copyright arises, that legal-basis assessment stays
  unrecorded rather than being filled with an invented ownership claim.
- **No rights are created or transferred.** Licensing can dedicate only rights
  held by the relevant contributor; AI generation alone does not establish
  copyrightability, originality, freedom from third-party claims, or dedication
  authority.

## What remains genuinely open

| # | Open item | Why it cannot be closed from repository records |
| --- | --- | --- |
| 1 | Per-route account/ownership and provider-terms compatibility with dedication (OI-02 LongCat, OI-03 StepFun) | The user's rights in each route's outputs depend on that provider's account terms; the register entries are located and quoted but unverified |
| 2 | Legal-basis assessment where no copyright arises in a jurisdiction | Requires a legal determination this record does not make |
| 3 | External contributors' own authority records | None exist yet; each new external contributor needs their own record before their material ships |
| 4 | Legal review | None has been performed; this file is not legal advice |

## Consequences

- The standing basis for the Unlicense/CC0 dedications of agent-authored
  project material is recorded above. Routine asset generation within this
  established policy needs no repeated approval loop (ASSET_PRODUCTION.md).
- Affected material still must not ship while OI-02/OI-03 are unresolved:
  provider account/route terms and their compatibility with public-domain
  dedication are unverified, and unknown or incompatible legal origin blocks
  inclusion of affected material.
- Release gate T15, the release statement, and any public-domain claim for
  agent-produced material remain conditioned on the provider-terms register
  being resolved, plus the other items in [`OPEN_ITEMS.md`](OPEN_ITEMS.md).
- Task and commit provenance references this standing record instead of
  repeating it per file.

## Audit trail

- 2026-11-26, job `00b1219c-b656-45e1-b2ad-84f26776eb36` (LongCat 2.5 through
  Pi): initial inventory; recorded the requirement but demanded a signed,
  executed instrument and reported the item OPEN with no basis found —
  stricter than the plan.
- 2026-11-26, job `a67680d9-2923-4992-a350-5804f0fcc193` (StepFun
  `step-5-preview` through Pi): accuracy audit; aligned this record with the
  plan's actual requirement and recorded the user-supplied authorization and
  dedication intent above, without inventing identity, signature, legal
  conclusions, or rights. See [`TASK_M0.3_RIGHTS.md`](TASK_M0.3_RIGHTS.md).
- 2026-11-27, job `42e44973-c074-4141-aac7-9e7f0524a9e1` (StepFun 5 Preview
  through Pi): provenance reconciliation; left the user-supplied standing
  basis above unchanged, and recorded that reviewer/checkpoint routes also
  authored committed review reports (registered in
  [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md), terms open; scope question OI-12).
  No identity, signature, or legal fact was added.
