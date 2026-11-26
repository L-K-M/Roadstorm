# Roadstorm Racer!

An original, colorful arcade racer inspired by the energy of early polygonal racing games: generous drifting, memorable roads, lively scenery, assertive opponents, and four-player local split-screen.

The project is at the planning stage. No playable game or build system has been implemented yet.

## Implementation execution

To start or resume the full build, follow [plan/IMPLEMENTATION.md](plan/IMPLEMENTATION.md). The coordinator delegates mainly to Step 5 Preview/Longcat 2.5 through pi, uses other available free/quota workers including SWE 2.1 through the local Devin CLI, and obtains independent Opus 5.5 and GPT-6.2 Sol reviews at regular checkpoints.

## Implementation documents

- [Implementation plan and milestones](PLAN.md) — launch scope, delivery order, acceptance gates, agent workflow, and release requirements.
- [Game design](docs/GAME_DESIGN.md) — driving, races, opponents, courses, cars, progression, multiplayer, and accessibility.
- [Technical design](docs/TECHNICAL_DESIGN.md) — engine, architecture, data contracts, content tools, performance, testing, and exports.
- [Opponent AI](docs/OPPONENT_AI.md) — traditional racers, learned Roadstormers, offline training, fairness, and evaluation.
- [Asset production and licensing](docs/ASSET_PRODUCTION.md) — original geometry, graphics, sound, music, provenance, and public-domain policy.
- [Benchmarks and acceptance contracts](docs/BENCHMARKS.md) — reference drivers, fixtures, measurable AI/handling gates, performance evidence, and experience review.
- [Review responses](docs/REVIEW_RESPONSE.md) — dispositions of the ten initial reviews and resulting plan changes.

All new project-specific implementation and creative production will be authored by LLM agents. Existing engines and tools remain third-party infrastructure. The planned engine is Godot 4.7.2 with typed GDScript; the first implementation milestone will pin and verify the toolchain.

## Independent plan reviews

Review agents should follow [REVIEW_PROMPT.md](REVIEW_PROMPT.md). Each reviewer works in one chat without subagents, writes a unique `review/<uuid>.md` report, and commits/pushes only that report using the existing shared checkout.

## License

The existing [LICENSE](LICENSE) is the Unlicense. The production plan retains it for original code, scripts, game data, and documentation, and specifies CC0 for original art and audio. Engine and dependency licenses retain their own terms and notices. See the [asset and licensing plan](docs/ASSET_PRODUCTION.md#license-scope).
