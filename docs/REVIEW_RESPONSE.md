# Roadstorm Racer! responses to the initial plan reviews

Reconciled on 26 November 2026. All ten reports pulled through commit `25d6520` were considered, including their 104 numbered findings, overlapping experiments, cross-document notes and optional recommendations. They reviewed planning baseline `206edf5`; the reports remain unchanged as historical evidence.

This revision changes the plan, not the game. No handling, rendering, training, listening, controller or platform experiment has been performed by this reconciliation. New coefficients, budgets and thresholds are initial implementation contracts to validate, not measured results.

## Main decisions

- Keep six courses, twelve cars, five modes, four local players, original LLM-produced content and both opponent families. Two genuinely learned Roadstormer styles remain required for integrated slice/release acceptance.
- Add [BENCHMARKS.md](BENCHMARKS.md) as the common source for calibration drivers, fixtures, reference records, metric units/tolerances, contact/style definitions and experience evidence.
- Define Classic/learned AI interfaces before Classic implementation; add a concrete 64-feature/four-action actor contract, difficulty semantics, cloning baseline and realized-maneuver evaluation.
- Prove exact stepping early, start the learning pilot in late M4, allow independent slice preparation in parallel, and cap pilot/final/revision compute. Freeze handling before accepted slice training and before final model evaluation; compatible later changes need evidence rather than automatic retraining.
- Resolve race endings, finished-car collision, grids, checkpoint recovery, ties, cup withdrawal, settings ownership, timers, records and save acknowledgement boundaries.
- Specify one shared audio downmix and 32-voice allocation, actual split-screen dimensions and player-count budgets, font scaling proof, canonical regeneration and provider/authority provenance for all generated material.

The disputed suggestions were evaluated individually. No review vote count substitutes for a technical or product decision.

## Disposition key

**Accepted** means the gap is addressed by a concrete rule, scheduled experiment or required artifact. It does not mean the experiment passed. **Partial** means the underlying concern was useful but the proposed remedy, claimed contradiction or extra scope was not adopted. **Clarified** means the baseline already covered the behavior and the revision makes it explicit. Finding numbers below are those within each linked source report.

## Review 2506a658

Source: [2506a658-428a-4846-ad5d-f0a1c9af0ded.md](../review/2506a658-428a-4846-ad5d-f0a1c9af0ded.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| F1 reference pace | Partial | CalibrationDriver and versioned five-run records now anchor pace/timers/medals. A global optimizer and mandatory human-derived ratios are unnecessary new dependencies. |
| F2 learning critical path/freeze | Partial | Early pilot, parallel preparation, finite allocations and freeze/compatibility chain added. Keep both learned styles in accepted M5; compatibility was already permitted. |
| F3 hierarchy/difficulty | Accepted | Shared schema precedes M4.2; Classic intents, delayed traffic, current safety, difficulty conditioning and Box decoding are explicit. |
| F4 drift reward/parity | Partial | Replace ambiguous acceleration percentage with a bounded speed-increment candidate; measure several corners/laps. Do not impose unvalidated ±1%/±2% equality across all styles/cars. |
| F5 race ends/gates/grid/ties | Accepted | Exact deadline/cooldown/grid/gate/timestamp rules replace ambiguous prose, including continued AI racing while waiting for humans. |
| F6 code/provider authority | Accepted | All generated code/recipes/docs/tools reference applicable provider terms and an actual standing owner/contributor authority basis. |
| F7 subjective gates | Partial | Capability-labeled motion/play/listening evidence and review checkpoints added. No new mandatory multi-person human testing programme; unknown experience quality stays open. |
| F8 player settings/AI assists | Accepted | Device/slot/room/profile ownership and Standard AI/reference assists defined. |
| F9 backend/surfaces | Accepted | Pin built-in Jolt/settings; derive surfaces from explicit metadata rather than triangle indices. |
| F10 spectacle ownership | Partial | Shared human-zone trigger coalescing/replay and tracking target defined; no per-camera worlds or guarantee of identical one-shot visibility. |
| F11 reproducibility | Accepted | Canonical-host normalized hashes separated from cross-host tolerances, frozen service outputs and statistical training. |
| F12 drafting | Partial | Add motor state and measurable draft fixture; retain provisional subtle effect until measured rather than declaring it inert. |
| F13 budget units | Accepted | Define per-tick CPU and combined/per-call inference units, p99 and staggered scheduling. |
| F14 hardware gate | Accepted | Split M3 technical and physical evidence; independent M4 work may continue, actual controller verification still blocks integrated M5. |
| F15 lap targets | Partial | Per-course authoring bands and measured reference traces replace an ambiguous shared low endpoint. Provisional lengths may change; three career laps remain. |
| F16 names | Partial | Move screening before named art and refresh later. Existing products sharing common working words do not automatically establish infringement or compel renaming. |

## Review 386eb383

Source: [386eb383-4237-4b9b-9588-e718fb2f1c58.md](../review/386eb383-4237-4b9b-9588-e718fb2f1c58.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| F1 tactical contract | Accepted | Versioned field order, frames, masks, action decode and reset behavior now precede Classic demonstrations. |
| F2 useful style diversity | Partial | Add realized-maneuver labels, matched windows, cloning-only comparison and independent review. Style shaping/holdouts already existed; retain them. |
| F3 undefined metrics | Accepted | Shared fixtures, numeric/parity tolerances, counts, contact rates and denominators are explicit. |
| F4 cup thresholds | Clarified | Define podium/victory/race wins and Storm Tour standings award; retain existing valid-finish completion rule. |
| F5 finish policies | Accepted | Standard/wait/hard-cap and physical-car outcomes specified without artificial human promotion. |
| F6 late feasibility | Accepted | Exact-tick probe moves to M0; bounded learning spike starts with a minimal late-M4 teacher. |
| F7 reaction cadence | Accepted | Delayed 60 Hz traffic/history plus 5 Hz phase latency; current hazard safety remains immediate. |
| F8 drift farming | Accepted | Numeric turn/time/progress/contact/rearm rules, per-turn cap and score-to-credit formula added. |
| F9 gates/benchmark fixture | Accepted | Define route-bound gates, maximum spacing, miss feedback/recovery and immutable handling fixtures. |
| F10 humans-only field | Partial | Explicitly zero AI and no rewards. Reject inserting AI/Roadstormers into a humans-only event. |
| F11 medal car | Accepted | Name the balanced starter by stable ID; stock Standard medal session and separate other-configuration records. |

## Review 6a45bc14

Source: [6a45bc14-7ad8-495e-b420-e5b4ddba25c2.md](../review/6a45bc14-7ad8-495e-b420-e5b4ddba25c2.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 simulator proof | Accepted | M0 probe owns tick/clock/reset/terminal behavior; acceleration requires fidelity evidence. |
| 2 movement/progress ordering | Accepted | Shared snapshot, world trajectories, pair sweeps, bounded correction, accepted motion and gates have one owner/order. |
| 3 Roadstormer comparison | Accepted | Concrete shared schemas and matched Classic/cloning-only/two-style comparison; humans enter at commands, not AI following. |
| 4 termination/ties/withdrawal | Accepted | Explicit race deadlines/cooldown, microsecond ranking, slot withdrawal and host succession rules. |
| 5 persistence/records | Accepted | Event IDs before GO, one writer/generations, durable acknowledgement, pending-save failures and complete record keys. No promise to recover an unpersisted finish. |
| 6 render/input/mix gates | Accepted | Provisional renderer until M3, exact panel dimensions, virtual-listener downmix, native input evidence and truthful ad-hoc Mac packaging. |
| 7 production scale | Accepted | Second contrasting bundle includes source edit/regeneration, music/font/mix proof and measured authoring/review effort before bulk work. |
| 8 rights/lineage | Accepted | Extend legal-basis evidence to code and every upstream creative/model input; preserve original-content baseline and honest exceptions. |

## Review 737d6d48

Source: [737d6d48-fe22-465c-8b75-d71aae3c7e09.md](../review/737d6d48-fe22-465c-8b75-d71aae3c7e09.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 bounded flagship feature | Partial | Add total allocations and diagnosed next decisions. Reject automatic Classic-only release or deferring required Roadstormers. |
| 2 shared versioned contracts | Accepted | Explicit schema before M4.2, model/data versions and validation fixtures. |
| 3 length/lap tension | Partial | Measure per-course targets and adjust graybox geometry. The original range did not require 60 seconds on every course. |
| 4 render counters | Accepted | Sum submissions over active views, record shadow/overdraw separately and freeze player-count presets from measurements. |
| 5 learned pace | Partial | Define learned/Classic time ratio 0.90–1.10 with matched conditions and traffic metrics. Do not adopt arbitrary ±3% before a pilot. |
| 6 coding-provider terms | Accepted | Reusable legal-basis records cover all agent outputs and inputs. |
| 7 movement handoff | Accepted | One explicit movement API/coordinator, swept intermediate trajectories and bounded saturation handling. |
| 8 difference rubric | Accepted | Matched realized choices, blinded independent review, counts/uncertainty and adjudication. |
| 9 course feature validator | Accepted | Tag required road-rhythm/landmark intervals and combine geometric validation with captured readability review. |
| 10 minor rule gaps | Accepted | Numeric drift suppression, exact race ties, cup-result unlock terminology and zero-AI exhibition are explicit. |

## Review 82923d41

Source: [82923d41-d525-4f2f-9008-8c6bde4369d7.md](../review/82923d41-d525-4f2f-9008-8c6bde4369d7.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 lap/top-speed band | Partial | Per-course measured bands/physical lower-bound sanity check. No compulsory 80%-of-top-speed validator; that proposed bound is arbitrary. |
| 2 listener ownership | Partial | Adopt manual virtual-listener downmix and disable automatic race-view positional audio. Reject the inaccurate one-global-listener explanation and host-centered remedy. |
| 3 voice cap | Partial | Allocate all 32 voices including music/crossfades/transients; asset inventory does not imply every layer must play simultaneously. |
| 4 reaction delay | Accepted | Delay discretionary traffic/history on fixed ticks, report added tactical cadence and preserve immediate safety. |
| 5 reference driver | Accepted | CalibrationDriver artifacts define actual configuration and speed-profile percentages. |
| 6 learned gates/critical path | Partial | Bound training and overlap preparation; keep two styles for accepted slice rather than accept an unfinished second style. |
| 7 font scaling | Partial | Require native-size scale/coverage proof; prefer outline glyphs but allow suitable atlases. Bitmap fonts are not categorically incompatible with 150% scaling. |
| 8 name review | Accepted | Owned early screening, content-lock refresh and final check with limits/stable IDs; no compulsory fallback title. |
| 9 Rush timing | Partial | Per-selected-car standing starts, five-run sector records and measured mistake margins. No unsupported claim that 2% is necessarily below variance. |
| 10 tire upgrade | Accepted | Name lateral damping/exit-blend parameters and additive-to-stock formulas without changing sustained drift. |
| 11 economy reference | Accepted | Expected 975 credits under explicit placement/style assumptions; 7.38 expected finishes, with best/base-only cases and rounding examples. |
| 12 keyboard sharing | Clarified | One keyboard slot is deliberate; WASD/arrows are alternatives. No added shared-keyboard mode. |
| 13 quality/listening | Accepted | Capability-based look/listen/control rubric; actual listening coverage is required, meters are insufficient. |
| 14 recipe/output drift | Accepted | Changed dependency/rotating CI regeneration and full canonical release rebuild. |
| 15 default font | Partial | Inventory actual pinned templates/export fonts. Do not hardcode an unverified font name or assume overriding UI removes bundled data. |
| 16 four-view budgets | Accepted | Player-count LOD/effects and summed submissions; no silent assumption that four solo-detail maxima fit. |
| 17 logo permission | Partial | Retain applicable branding/license evidence if used. Godot's press kit already licenses specified logo uses; no blanket bespoke-permission rule. |
| 18 movement API | Accepted | Initial explicit-displacement move_and_collide contract, custom response/adhesion ownership and early proof. |

## Review 84f146b5

Source: [84f146b5-54df-4256-a229-ec14c0a834e7.md](../review/84f146b5-54df-4256-a229-ec14c0a834e7.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 Roadstormer contingency | Partial | Stop/review budgeted experiments, revise compliant approaches, keep required feature and its gate open. |
| 2 four-view risk | Accepted | Representative measured gate retained. Correct experiment to one 1080p output split into 960×540 quadrants, not four 1080p targets. |
| 3 low lap endpoint | Partial | Replace shared aspiration with measured per-course targets; not a proof that the entire old band was impossible. |
| 4 grid order | Accepted | Seeded Quick Race permutation, saved career rotation and exact grid geometry. |
| 5 learning details | Accepted | Versioned features/actions/reward recipe, demonstration coverage, terminations and before-run caps. |
| 6 names/listening | Accepted | Early screening tasks and actual per-theme/family listening records. |

## Review 973757bc

Source: [973757bc-5a9b-492b-b9aa-9926f7c5d33c.md](../review/973757bc-5a9b-492b-b9aa-9926f7c5d33c.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 mechanical handling | Accepted | Typed parameter units/envelopes, exact upgrade equations and immutable comparison fixtures. |
| 2 difficulty reference | Accepted | Calibration records, explicit desired-speed fraction, delayed observations and conditioned policy. |
| 3 training contract | Accepted | 64 features/four Box actions, normalization, history, reward recipe, BC/PPO stages and actor budget. |
| 4 scoreable acceptance | Accepted | Contact thresholds/allowance, semantic matching/counts, interventions and uncertainty. |
| 5 evaluation cost | Accepted | Worker/memory/throughput/fidelity probe, resumable T11 shards and projected/actual core-hours. |
| 6 drift economy | Accepted | Turn IDs, time/progress/contact qualification, score cap/conversion and exact lap scaling. Career stays three laps. |
| 7 audio ownership | Accepted | Virtual listeners, normalized shared output, voice reservations/stealing and mono/layout changes. |
| 8 rights chain | Partial | Authority/provider links strengthened; baseline already required rights-holder/contribution records. Do not invent a signer or presume copyrightability. |
| 9 rounded ties | Accepted | Unrounded internal race timing controls place; rounded equality is a close finish, not a shared award. |
| 10 name schedule | Accepted | Check before expensive named media, refresh at content lock/release. |

## Review acd5167d

Source: [acd5167d-f35b-4334-a04b-3f97bc1db9c6.md](../review/acd5167d-f35b-4334-a04b-3f97bc1db9c6.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 contract scheduled late | Accepted | M0/M2 schema ownership, M4 Classic compliance, M4B ratification. |
| 2 reference ownership | Accepted | M1 calibration tool/M4 reference artifacts with dependency revisions. |
| 3 lap range | Partial | Adopt per-course evidence; reject the stronger claim that a shared range requires its lower endpoint everywhere. |
| 4 cadence | Partial | A seven-tick observation age is representable; publish its additional phase latency rather than conflate it with end-to-end reaction. |
| 5 handling freeze | Accepted | Freeze starter slice handling and launch candidate before final evaluation; later changes require compatibility proof/retraining where needed. |
| 6 drafting | Accepted | Include eligibility/fade in motor state and boundary/equal-treatment fixtures. |

## Review baddc856

Source: [baddc856-cf9f-4c90-922a-3c23a75f00f4.md](../review/baddc856-cf9f-4c90-922a-3c23a75f00f4.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 matched metrics | Accepted | Fixed warm-up/matching, realized semantic labels, contact rates and per-intent/per-tick intervention denominators. |
| 2 programme budget | Partial | Extend already-capped pilots with cumulative allocations, machine/worker limits and a diagnosed next decision; no default post-release deferral. |
| 3 training before tuning | Accepted | M7 candidates are provisional; M8.1 freezes before final training and evaluation. |
| 4 imperceptible drift | Partial | Explicit speed-increment candidates and scoring; reject an unmeasured claim of no reward or compulsory boost size. |
| 5 benchmark/evaluator | Accepted | Fixtures, run eligibility, tolerances and capability-labeled experience evidence. |
| 6 lap low endpoint | Partial | Per-course measured targets, preserving provisional route flexibility. |
| 7 renderer/rear view | Accepted | M3 locks measured renderer; rear view reorients an existing camera and is stress-tested. |
| 8 Rush eligibility | Accepted | Stock-only per-car references, sector allowances and keyed records. |
| 9 local session | Accepted | Host succession, room/device/slot ownership, explicit reset time and DNF-versus-withdrawal. |
| 10 rights/engine details | Accepted | Material-specific overrides, all-authoring terms, actual export notices, original branding, truthful ad-hoc Mac package. |
| 11 training details | Accepted | Before-run learning configuration, supported action encoding, actor-only count and declared parity corpus/tolerance. |
| 12 loop frame closure | Accepted | Measure/distribute residual roll then apply bank; validate seam. Residual roll is possible, not inevitable on every loop. |
| 13 human-like traffic | Accepted | Add delayed/noisy legal proxy scenarios to curriculum/held-out tests; do not call proxies proof of human interaction. |

Its additional inventory/surface cross-document notes are folded into manifest-derived sound counts and explicit per-car surface-response data. Other cross-document items duplicate the changes above.

## Review eb571c59

Source: [eb571c59-5660-449a-ac44-73dd2a6b61cb.md](../review/eb571c59-5660-449a-ac44-73dd2a6b61cb.md).

| Finding | Disposition | Decision |
| --- | --- | --- |
| 1 geometry contradiction | Partial | Solo/four-view maxima are independent caps, not inherently contradictory. Clarify aggregate measurement/player-count detail; preserve actual frame-time gate. |
| 2 dimensions/grid | Partial | Define car envelopes/axes/contact proxy and two-column/four-row grid. Eight cars do not need to fit abreast. |
| 3 learned scope/style | Accepted | Concrete conditioned actor, BC comparison, reward/semantic gates and bounded experiments preserve genuine learning. |
| 4 missing rights holder | Partial | The field already existed; add actual authority/provider linkage without fabricating ownership. |
| 5 DNF/withdrawal | Partial | Clarify distinct events: race DNF, in-race retirement and cup withdrawal/next-event conversion. |
| 6 Rush extensions | Accepted | Explicit four-sector budgets, one-time ordered extensions and exact-zero crossing precedence. |

## Experiments and optional suggestions

The reviewers' experiments are consolidated into five packages scheduled in PLAN: early simulator fidelity/throughput; handling/progress/calibration; bounded learning/style; representative split-screen/input/audio/font stress; and first/second production/rights proofs. Final tests retain their own evidence. Competing proposed hour/step/percentage caps were not treated as measurements; the plan now chooses explicit initial caps and requires preregistration before running them.

Adopt low-cost source/capture checks, color-perception review, generated license inventories, sample audits and useful revision-cost tracking. Do not add a global line optimizer, mandatory silhouette-overlap scoring, compulsory fallback title, extra keyboard players, external creative packs/fonts, smaller launch content, a single learned style, or post-release Roadstormers by default. Those are either unsupported remedies or scope changes. A surrogate training simulator is only a future measured-bottleneck experiment; Godot remains authoritative for acceptance.

## Evidence still required

The plan can guide M0, but learned style quality, local training throughput, motor/contact stability, four-view frame times, actual gamepad ownership, music/art appeal and target-platform packaging remain unproven until their assigned gates run. No review or document-only reconciliation establishes those outcomes. All requested product commitments remain in scope.
