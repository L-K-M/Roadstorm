# Provenance manifest contract

Initial M0.3 contract for project-authored material. It implements the task
record and provenance requirements in [`../PLAN.md`](../PLAN.md),
[`../docs/ASSET_PRODUCTION.md`](../docs/ASSET_PRODUCTION.md), and
[`../docs/TECHNICAL_DESIGN.md`](../docs/TECHNICAL_DESIGN.md). This is a record
format, not a legal dedication.

## Applies to

- Every new project-specific script, tool, test, schema, recipe, composition,
  design document, dataset, trained model, generated asset, and build/package
  input produced for Roadstorm Racer!, whether authored by an LLM directly or
  by an LLM-written generator.
- Every authoring route/provider/model used for such material, recorded in
  [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md).
- The owner/contributor authority instrument in
  [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md).

Godot, operating systems, compilers, and other existing infrastructure remain
a separate category under [`DEPENDENCIES.md`](DEPENDENCIES.md).

## Task-level record fields

Each task/commit that produces project material must record:

| Field | Requirement |
| --- | --- |
| Milestone/task ID | Stable ID, e.g. `M0.3` |
| Scope | Bounded files/behaviors covered; owned paths |
| Input revisions | Repository revision(s) and relevant fixture/config versions |
| Changed files | Paths added/modified; hashes where meaningful |
| Regeneration | Exact commands/versions/seeds to reproduce generated output |
| Authoring route | Provider/service/account route and model ID when known |
| Date | Preparation/review date |
| Reviewer | Independent reviewer/review result when required |
| Limitations | Unverified, unresolved, or explicitly out-of-scope items |

Model/provider/date may be unknown; record `unknown` rather than inventing it.
Never include credentials, private reasoning, personal files, or API keys.

Recommended commit trailer (enforcement belongs to later CI, M0.5):

```text
Provenance: task=<ID>; provider=<route>; model=<model-or-unknown>; date=YYYY-MM-DD
```

## Creative asset and model manifest fields

`assets/manifest.json` (not yet created; first needed with the asset pipeline)
must account for every shipped creative asset and model artifact. Repeated
families may share a recipe/license record, but each output path and hash stays
discoverable.

| Field group | Required data |
| --- | --- |
| Identity | Stable asset ID, category, schema/revision, source paths, generated/export paths, SHA-256 hashes |
| Origin | `llm_script_generated`, `service_generated`, or `external_cc0`; authoring task/agent/provider/model/date when known |
| Generation | Generator version, recipe, seed, input asset IDs, exact regeneration command, tool/encoder versions |
| Technical | Dimensions, triangle/material counts, LODs, duration, sample rate/channels, loop settings, model dimensions as applicable |
| Rights | Exact license/SPDX identifier, rights holder/contributor record, upstream URL/date/evidence if external, applicable service terms if used |
| Review | Technical check results, visual/audio/model review, reviewer, approval revision, limitations and release inclusion |
| Lineage | Modifications, upstream inputs and their licenses, superseded outputs, dependency references |

Rules:

- Use a separate development/runtime dependency inventory so code dependencies
  do not masquerade as game art. That is [`DEPENDENCIES.md`](DEPENDENCIES.md).
- Never set missing facts to an invented author or model. Mark unknown metadata
  explicitly.
- Unknown legal origin blocks shipping, even when nonlegal authoring metadata is
  incomplete.
- Asset IDs survive renaming and regeneration.
- Commit original source recipes and approved outputs; keep review previews and
  evidence at practical sizes.
- Rights records link to [`OWNER_AUTHORITY.md`](OWNER_AUTHORITY.md) and the
  applicable entry in [`PROVIDER_TERMS.md`](PROVIDER_TERMS.md).

## Reproducibility classes

| Class | Meaning |
| --- | --- |
| `canonical_deterministic` | Exact normalized hashes promised on one pinned canonical build image/architecture |
| `statistical_training` | Statistically reproducible training; cross-host use measured semantic/numeric tolerances unless byte equivalence is demonstrated |
| `frozen_service_output` | Frozen remote-service output; retain the original output/prompt reference and verified redistribution/dedication permissions |

Only `canonical_deterministic` promises exact normalized hashes. Other hosts
compare declared semantic/numeric tolerances unless byte equivalence is shown.

## Storage conventions

```text
licenses/                    scope, CC0 notice, third-party notices
provenance/
  OWNER_AUTHORITY.md         standing dedication authority instrument
  PROVIDER_TERMS.md          provider/service/account terms register
  DEPENDENCIES.md            dev/runtime dependency inventory
  MANIFEST_CONTRACT.md       this file
  OPEN_ITEMS.md              consolidated open/unverified items
  provider_terms/<route>/    bounded snapshots of official provider terms (future)
  TASK_*.md                  task-level records
assets/manifest.json         future creative asset/model manifest
models/**, training/**       future model cards, datasets, training/evaluation records
```

Large release captures belong in release artifacts, not source control. Keep
only useful bounded review evidence here.

## Closing condition for provenance

A task or asset may close its provenance record only when its required fields
are present or explicitly marked unknown, its legal origin is resolved, and its
review limitations are recorded. Agent text cannot substitute for the owner
authority instrument or verified provider terms.
