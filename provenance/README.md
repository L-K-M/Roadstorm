# Roadstorm Racer! provenance records

This directory is the initial M0.3 provenance inventory for project-authored
material: owner/contributor authority, provider-terms intake, dependency
inventory, record contracts, and open items. It does not create legal rights,
dedication authority, or signatures; agents cannot sign for a person.

Prepared 2026-11-26 from input revision
`0ea596a4fa85ade19375e130313f020ed6010619`. Reconciled 2026-11-27 by job
`42e44973-c074-4141-aac7-9e7f0524a9e1` (StepFun 5 Preview through Pi): corrected
supported factual contradictions in the owned records — owner/contributor
authority is a recorded standing basis, not a signed instrument; the observed
reviewer/checkpoint routes are registered with terms open; the empty asset
manifest and the existing toolchain pin are presented accurately; and
historical hashes are kept distinct from re-recorded current hashes. See
[`TASK_M0.3_RIGHTS.md`](TASK_M0.3_RIGHTS.md) for the full reconciliation.

## Record index

| Record | Purpose | Status |
| --- | --- | --- |
| [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md) | Standing owner/contributor dedication authority record | **RECORDED** — standing basis recorded; per-route provider/account evidence open (OI-02/OI-03) |
| [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md) | Provider/service/account terms intake for all LLM-authored material | **OPEN** — every registered route (authoring and reviewer/checkpoint) unverified |
| [`DEPENDENCIES.md`](DEPENDENCIES.md) | Development/runtime dependency inventory with notices | **PARTIAL** — Godot notices extracted; tool/training gaps open |
| [`MANIFEST_CONTRACT.md`](MANIFEST_CONTRACT.md) | Required provenance fields, classes, and storage conventions | Active initial contract |
| [`TASK_M0.3_RIGHTS.md`](TASK_M0.3_RIGHTS.md) | Task record for this M0.3 inventory job | Complete as an initial inventory, not M0 acceptance |
| [`OPEN_ITEMS.md`](OPEN_ITEMS.md) | Consolidated unresolved blockers/gaps | Open |
| `assets/manifest.json` | Creative asset/model provenance and technical metadata | Empty initial registry exists (`registry_status: "empty"`, prepared 2026-11-26); no assets yet; populated at M2.6+ |
| `models/**`, `training/**` (future) | Learned model cards, datasets, training/evaluation records | Not started; M4B/M7 |

The license-scope document and third-party notice artifacts live in
[`licenses/`](../licenses/README.md), not here.

## Conventions

- One bounded record per subject; add dated files under this directory for
  provider snapshots, task records, or review evidence. Do not store raw
  private sessions, credentials, API keys, personal files, or secrets here.
- Record agent/provider/model/date when known. Never invent missing author or
  model metadata. Mark unknowns explicitly.
- Unknown or incompatible legal origin blocks inclusion of affected material.
  Unknown nonlegal authoring metadata may be recorded as unknown without
  blocking by itself.
- An agent-generated statement is not a dedication. The dedication basis is the
  standing owner/operator record in
  [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md); the plan requires that standing
  record, not a signed instrument, and an agent must not invent a signature.
- New external contributors and new authoring providers/routes need their own
  authority/provider records before affected material ships.
- Recommended commit trailer (enforcement belongs to later CI, M0.5):

  ```text
  Provenance: task=M0.3; provider=<route>; model=<model-or-unknown>; date=YYYY-MM-DD
  ```

## Privacy boundary

Local harness configuration such as `/Volumes/PaseoData/TrueNAS/paseo-home/.pi/agent/auth.json`
may contain credentials. Never copy, quote, log, or commit it. Provider entries
record only non-secret service names, API base URLs, model IDs, and public
terms references.
