# Roadstorm Racer! asset production and licensing

Produce original game assets through LLM-authored source recipes and generation tools. This makes the flat-shaded art style practical, keeps the whole production process available in source form, and supports the project's Unlicense/public-domain goal. No commercial sample libraries, ripped assets, downloaded pretrained models, or external creative asset packs are required for the baseline.

## License scope

Retain the existing root `LICENSE` unchanged for original software, scripts, structured game definitions, and documentation. The [Unlicense](https://unlicense.org/) provides the project's software public-domain dedication. During M0, add an explicit scope document and CC0-1.0 notice for original game art, audio, model weights, and authored datasets. CC0 is a public-domain dedication for creative material to the extent rights can be waived; see the [CC0 deed](https://creativecommons.org/publicdomain/zero/1.0/) and [legal code](https://creativecommons.org/publicdomain/zero/1.0/legalcode).

| Material | Target treatment |
| --- | --- |
| Original code, tools, tests, text definitions, docs | Unlicense, retaining the existing root text |
| Original meshes, materials, textures, UI art, font glyphs, music, effects | CC0-1.0 with retained editable sources/recipes |
| Original learned rival weights and authored training datasets | CC0-1.0 to the extent applicable rights exist, with model/data provenance |
| Godot runtime and bundled components | Their original MIT and other component licenses; exact required notices retained |
| Development tools/libraries | Their original licenses, recorded separately; notices included when redistributing relevant code/binaries |
| Any exceptional external creative input | Its verified original terms; only explicit CC0 accepted by this asset policy |

License by material purpose with explicit manifest scope, not by a blanket folder rule. Executable generators, tests, schemas and game/event definitions remain Unlicense; original editable scores, glyph/mesh artwork sources and their creative outputs use CC0, as do original weights/datasets. List those overrides in the scope document so a JSON score is not confused with executable configuration. Third-party notices/marks retain their terms wherever located.

Godot permits games under other licenses but its runtime and bundled components retain their own terms. Ship exact notices from the pinned engine/export-template version in the source and distribution, and make them readable offline in Licenses. Use the engine's license information and its matching copyright inventory to avoid stale attribution. See [Godot license](https://godotengine.org/license/) and [compliance guide](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html).

The release description should say: “Original Roadstorm Racer! source is released under the Unlicense. Original game art, audio, and learned model artifacts are dedicated under CC0. Engine and dependency notices are included separately.” Do not describe the entire exported executable as wholly public domain.

Licensing can dedicate only rights held by the relevant contributor. AI generation alone does not establish copyrightability, uniqueness, or freedom from third-party claims. Preserve source and provider records rather than promising universal clearance. CC0 does not resolve trademark, privacy, or publicity rights; the chosen product/car names remain working names until appropriately checked. Existing naming preferences are not a completed trademark search.

## Authorship and contribution records

Every new project-specific source asset is authored by an LLM or an LLM-written generator. Humans may direct, review, playtest, provide credentials, and choose releases. Existing software infrastructure is identified separately. The baseline's creative content should be wholly original to this production, not merely an LLM-selected collection of stock packs.

Record the agent/provider/model/date when available, the task/prompt reference, original inputs, generator version, seed, output hash, and reviewer. Do not fabricate model metadata or retain private reasoning, credentials, personal files, or API keys in provenance. A clean build uses committed approved artifacts, so an unavailable model provider cannot stop players from building or playing.

Contributions include an explicit statement accepting the relevant Unlicense/CC0 dedication for rights the contributor controls. Keep it with the contribution record; do not have an agent sign as a person or claim rights on their behalf. The [Unlicense contribution guidance](https://unlicense.org/#unlicensing-contributions) recommends explicit dedication for substantial contributions. No additional approval loop is needed for routine asset generation within this established policy.

M0 establishes the dedication authority once: a record from the authorized repository owner/operator identifying the basis on which applicable rights in configured agent outputs are dedicated, and which authoring accounts/routes it covers. Reference that standing record in task/commit provenance; do not require an agent to invent a human signature for every generated file. New external contributors need their own applicable authority record. The GitHub handle is an organizational reference, not proof of a person's legal identity or employer authority. Where no copyright arises, record the legal-basis assessment without inventing ownership.

Use the existing license and owner instructions where they already establish intent/authorization; record the basis rather than requesting repeated approval for routine contributions. Only actual gaps in rights or terms need resolution before affected material ships.

Provider-terms intake covers **all** LLM-produced material, including software, docs, tests, recipes, scores and training tools, not only remote media generation. A reusable record identifies the applicable provider/service/account or route terms, version/date, input-rights basis and output redistribution/dedication compatibility. Each authoring record references it. Unknown model branding can remain unknown when the service/legal basis is known; unknown or incompatible legal origin blocks inclusion. Keep private identifiers/credentials out of the public record. Resolve an actual rights uncertainty before shipping affected material rather than retroactively asserting a waiver.

## Art direction

Use original faceted geometry, strong silhouettes, broad color regions, small material counts, and deliberate environmental palettes. Avoid tracing commercial car bodies or copying distinctive track sequences. The reference games inform speed, road rhythm, and spectacle rather than supplying shapes, logos, maps, recordings, or code.

Start with a shared palette of approximately 32 base colors, then define a controlled palette per environment. Use vertex colors and original simple atlases up to 256×256 for road markings, windows, signs, and decals. Reserve a 512×512 atlas only for a measured need. No photo texture is necessary. Original geometric badges and sponsors avoid real brand references.

Suggested geometric budgets: cars about 1,500–3,000 triangles at close range, 600–1,000 at medium range, and 150–300 at distance; common props about 50–800 close-range triangles; landmark structures budgeted individually within the course's visible-geometry cap. Limit car material slots to about four. These are authoring targets, subordinate to measured aggregate performance.

Lighting uses a single sun, ambient color, simple fog, limited contact shadows, and authored palette shifts in tunnels. Waterfalls use opaque/faceted water strips and bounded particles; foliage and spectator groups avoid large transparent overdraw. Optional dither/low-resolution effects must preserve road readability.

## Launch asset inventory

| Category | Required production set |
| --- | --- |
| Twelve cars | Body/wheels/windows, three LODs, intact contact proxy, four paints/decals, thumbnail/handling/engine definitions, separate front/rear bumpers and optional wing with attachment/impact regions and damage LODs |
| Common road kit | Asphalt/gravel/shoulder profiles, markings, curbs, guardrails, barriers, arrows, gate structures, start/finish pieces, road signs |
| Common environment kit | Rocks/cliffs, terrain profiles, several tree shapes, bushes, buildings, fences, lamps, original flags and geometric spectator groups |
| Six environment kits | Beach/marina/village; alpine/cable-car/viaduct; forest/lake/timber; canyon/wind-farm/railway; metro/port/suspension-bridge; dam/tunnel/turbine-ridge |
| Landmark animation | Plane, helicopter, cable cars, freight train, ship/cranes, turning turbines, flowing waterfalls, flags/spectators; shared deterministic trigger definitions |
| Six course bundles | Road/terrain/collision chunks, barriers, scenery, lighting, gates, grid, AI metadata, safe anchors, minimap, preview and audio zones |
| UI and type | Original logo, geometric alphabet/numerals and required punctuation, HUD/menu icons, player symbols, original controller prompts, car/course cards, reward graphics |
| Effects | Tire smoke/dust, bounded sliding-debris sparks, landing dust, loose/detached bumper states, drift feedback, speed accents, transitions and reset-immunity cue |
| Sound | Four engine families with idle/load/coast variants; approximately 40 reusable tire/contact/UI/environment layers |
| Music | Six original race themes, one menu/garage theme, one results theme, original start/finish/reward stingers |
| Learned opponents | Two approved tactical styles, source training configurations, original observation datasets, inference weights and model cards |
| Release material | App icon, cover art from original game geometry, actual gameplay screenshots, captured trailer, control/accessibility text |

Expect approximately 50–70 distinct reusable prop designs across the common and six environment kits. Reuse is desirable, but silhouettes/palettes and landmark arrangements must distinguish the courses. A fixed asset count cannot substitute for an effective scene.

## Geometry and graphics workflow

1. Write a short asset brief: purpose, silhouette, palette, scale, views, triangle/material budget, collision behavior, animations, and where it appears.
2. Author a structured recipe and original generation script. Cars use parameterized body sections, roof/cabin proportions, wheel arches, lights, spoilers, and decorative features; props use a shared geometric vocabulary without sharing every silhouette.
3. Bake engine-ready mesh resources and scene assemblies, LODs, simplified contact proxies, and materials. Specify coordinate system, origin, forward direction, wheel pivot locations, and units consistently. Validate normals, winding, seams, bounds, finite values, and material references.
4. Generate contact sheets and a turntable at standardized lighting. Render a car at both garage size and the size it occupies in a split-screen view. Review silhouette and readability, not only triangle count.
5. Integrate into a representative course, profile the result, review motion/collision, and record the approved output hash. A geometry change invalidates its prior review where relevant.

Course generation follows the technical track compiler: a manually authored-by-agent route recipe becomes shared render/collision/AI/recovery geometry. Keep scenic objects outside driving-space exclusion volumes. Animation uses simple transforms, paths, and shader/mesh changes, with no imported motion clips required.

Car generators emit front/rear bumpers as separate reusable mesh children and an optional third trim/wing slot. Give each a stable part ID, local attachment transform/impact region, intact/loose/detached presentation data, matching paint and simple closed mounting surfaces so removal does not expose an empty shell. Include parts in the car's ordinary triangle/material/LOD budget; detached versions use at most 200 triangles each. Reuse original materials without per-impact texture generation. Render damage-state turntables and sliding/sparking previews in the three-starter M5 proof, then complete all twelve in M7. Keep the intact contact hull/mass independent of visible part removal.

Generate icons and the logo from original SVG/polygon recipes. Render car/course thumbnails from actual approved scenes. Prefer an original outline font generated from authored geometric glyphs; purpose-built raster atlases at native required sizes are also acceptable if the same readability tests pass. Include glyph source/generator and any font-building tool in the development inventory. Test every HUD/menu at 100/125/150% and every split layout; bitmap resampling is not automatically a failed accessibility gate, and outline format alone is not proof of readable type.

Do not use `SystemFont` or an uncontrolled system fallback for shipped strings. Explicitly choose fonts rather than silently relying on the engine default. Derive exact fallback/bundled-font notices from the pinned engine/templates and actual export inventory; an original UI font does not itself remove engine-bundled font data. English coverage includes the chosen case style, digits, every displayed punctuation/units symbol and controller glyph; run a missing-glyph check over all strings.

## Effects and engine sound

Use LLM-authored synthesis tools with oscillators, envelopes, filtered deterministic noise, modulation, and simple wave shaping. Generate masters at 48 kHz PCM and retain recipes; choose WAV for short effects and loop-friendly compressed formats for longer music/environment assets after measuring decoder cost. Record encoder versions and licenses. No external samples, soundfonts, song stems, or voice recordings are required.

Four engine families can cover light/high-rev, rally/raspy, muscle/low, and exotic/smooth characters. Produce idle, load, and coast loops for each, with clean loop points and crossfades. Map RPM and throttle to bounded pitch/layer changes, add short generated shift transients, and keep movement physics independent of the audio estimate. Avoid obvious pitch jumps or four identical engines masking one another.

Tire layers cover asphalt scrub, sustained slip, gravel, and soft shoulders. Contacts include light scrape, stronger wall/car impact, curb, and landing. UI/gameplay cues include navigation, confirm/back, join/ready, countdown/GO, checkpoint, finish, unlock/purchase, invalid action, and reset. Environmental layers include surf, wind, forest, waterfall, helicopter, plane, turbine, train/ship, and abstract crowd noise. Use synthetic, nonverbal crowd sound rather than identifiable voices.

Synthesize original loose-bumper rattle, detachment clank and sliding-metal scrape from the existing oscillator/noise tools. Record their sources in the same CC0 manifest and test the debris-priority mix under four-player load; these sounds share the existing contact/transient reservation.

Initial asset gates: finite sample values; no clipping; true peak no higher than about -1 dBTP for final mastered tracks; music around -18 to -14 LUFS integrated before game-bus balancing; no DC offset; appropriate fade-in/out; and no audible loop discontinuity. Meter the final four-player mix as well as isolated assets. Use a final limiter for accidental peaks, not as a substitute for gain staging. Keep useful warnings audible without harsh transient overload. Audio perception requires review beyond waveform checks.

## Original music workflow

Store each composition as a symbolic score with tempo, meter, note pitches/durations, velocity, instruments, arrangement, loop regions, and transitions. A 60–120-second race loop can contain an intro, two contrasting sections, a short break, and a seamless return. Use general early-arcade vocabulary—bright synth leads, bass, percussion, harmonized motifs—without requesting a melody or arrangement from a named soundtrack.

Generate instruments from original oscillator/noise recipes. Percussion, synth/brass/guitar-like timbres, and effects use no recorded instruments or third-party soundfonts. Render stereo masters and runtime encodings from the same score. A small final-lap intensity layer may be added only if it loops and mixes reliably; do not make an adaptive soundtrack engine a prerequisite.

Review the score, note distribution, dynamics, loop transition, instrumentation balance, and actual in-game mix. Every shipped theme and effect family requires an actual listening record from a capable independent agent or a human reviewer, as defined in [BENCHMARKS.md](BENCHMARKS.md#perceptual-and-production-review). If available tools cannot hear it, retain a preview and keep perceptual approval open; spectral statistics do not establish musical quality. Test engine/music loop seams and decoder cost in Godot, rather than assuming every compressed format has sample-accurate seeking. Keep symbolic sources for revisions. Actual sound/voice counts derive from the approved manifest and shared-mix allocation, not the approximate inventory target.

## External material policy

The baseline uses original generated creative content. Do not import stock packs, fonts, samples or datasets as a shortcut to passing its production proof. If an external creative input is proposed, record its specific need, provenance and effect on the original-content claim; a change to agreed authorship scope needs an explicit scope decision. Only verified item-level CC0 evidence is compatible with this creative-asset policy. “Free,” “royalty free,” or commercial-use permission does not establish public-domain status or source redistribution rights. Engine/build infrastructure remains a separately licensed category, not a creative-asset exception.

Potential sources are candidates, not assets selected for the game:

- [Kenney support and asset terms](https://kenney.nl/support): asset pages generally provide CC0 game assets; verify the included license of the specific download. Kenney's logo is not a free game asset.
- [Poly Haven license](https://polyhaven.com/license): its asset files are CC0; site text, logos, example renders, and other site material have separate scope. Photorealistic packs are usually unnecessary for this art direction.
- [Freesound licensing FAQ](https://freesound.org/help/faq/): licenses differ per upload. Consider only an explicitly CC0 file, retain its page/license evidence, and inspect it for recognizable speech/music or suspicious third-party recordings. Reject attribution-required, noncommercial, Sampling+, ambiguous, or missing terms for this asset policy.

Do not download creative packs preemptively. An asset's license label is evidence, not a guarantee that its uploader held every right. Keep external inputs out of the baseline unless a specific production need justifies them.

Remote image/audio/model generation is also optional rather than a build dependency. Before using it, record the actual provider/account terms applicable to the generation, rights to the inputs, output/source redistribution permissions, and date. Retain the original output and prompt reference; a prompt/seed does not guarantee identical regeneration. Do not assume one provider's ownership terms apply to another provider, or that output ownership is a third-party-rights warranty.

## Manifest and provenance contract

`assets/manifest.json` accounts for every shipped creative asset and model artifact. Repeated generated families may share a recipe/license record, but each output path and hash remains discoverable. Use a separate development/runtime dependency inventory so code dependencies do not masquerade as game art.

| Field group | Required data |
| --- | --- |
| Identity | Stable asset ID, category, schema/revision, source paths, generated/export paths, SHA-256 hashes |
| Origin | `llm_script_generated`, `service_generated`, or `external_cc0`; authoring task/agent/provider/model/date when known |
| Generation | Generator version, recipe, seed, input asset IDs, exact regeneration command, tool/encoder versions |
| Technical | Dimensions, triangle/material counts, LODs, duration, sample rate/channels, loop settings, model dimensions as applicable |
| Rights | Exact license/SPDX identifier, rights holder/contributor record, upstream URL/date/evidence if external, applicable service terms if used |
| Review | Technical check results, visual/audio/model review, reviewer, approval revision, limitations and release inclusion |
| Lineage | Modifications, upstream inputs and their licenses, superseded outputs, dependency references |

Never set missing facts to an invented author or model. Mark unknown metadata explicitly; unknown legal origin blocks shipping even when nonlegal authoring metadata can be incomplete. Commit original source recipes and approved outputs, with review previews and evidence stored at practical sizes. Asset IDs survive renaming and regeneration.

Rights records link to the owner/contributor authority instrument and applicable authoring-service terms; code/task provenance has the same coverage outside the asset manifest. Lineage traverses all upstream inputs, including glyphs, synth instruments, samples, model weights and training data. Reproducibility class is `canonical_deterministic`, `statistical_training`, or `frozen_service_output`; only the first promises exact normalized hashes on its pinned canonical build image. Other hosts use measured semantic/numeric tolerances unless byte equivalence is demonstrated. CI regenerates changed dependencies and a rotating sample; release rebuilds the complete deterministic set.

## Release rights gate

The package validator compares export contents with manifests and the dependency inventory. Block release for unknown origins, missing source recipes for first-party generated assets, missing hashes, unregistered fonts/samples/models/plugins, unapproved outputs, disallowed creative licenses, absent notices, or private credentials in artifacts.

Verify that the in-game Licenses screen works offline and includes the original-project statement, CC0 notice, pinned Godot notice, and relevant dependency texts. Include the same notices in distributed source/build archives. The owner/contributor records must cover rights that exist in their contributions; an agent cannot create legal authority through a generated sentence.

Schedule preliminary title/car/rival-name screening before finished badges/cards in M5, refresh before M7 content lock, and confirm at M9. Record jurisdictions, primary registries/store searches, date, evidence and limitations; screening is not a worldwide clearance guarantee. Existing real products sharing a common working name do not alone establish infringement. Keep stable IDs so an identified conflict can be renamed cheaply.

Prefer original game branding and audit the actual export for default icons/splashes/fonts. If an engine/tool mark is deliberately used, retain its applicable branding/license evidence and avoid implying endorsement. Godot's [official press kit](https://godotengine.org/press/) already permits specified logo uses under CC BY 4.0; bespoke permission is not automatically required. Such a logo is outside the original-CC0 creative claim. No optional third-party logo is needed for this game's branding.

Release the original scores, synth/geometry programs, track/car recipes, approved trained weights, training/evaluation configuration, and build instructions alongside final assets. A public-domain game should be useful to remix, not just free to run.
