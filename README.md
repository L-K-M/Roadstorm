# Roadstorm Racer!

An original, colorful arcade racer inspired by the energy of early polygonal racing games: generous drifting, memorable roads, lively scenery, assertive opponents, and four-player local split-screen.

The project is at the planning stage. No playable game or build system has been implemented yet.

## Implementation documents

- [Implementation plan and milestones](PLAN.md) — launch scope, delivery order, acceptance gates, agent workflow, and release requirements.
- [Game design](docs/GAME_DESIGN.md) — driving, races, opponents, courses, cars, progression, multiplayer, and accessibility.
- [Technical design](docs/TECHNICAL_DESIGN.md) — engine, architecture, data contracts, content tools, performance, testing, and exports.
- [Opponent AI](docs/OPPONENT_AI.md) — traditional racers, learned Roadstormers, offline training, fairness, and evaluation.
- [Asset production and licensing](docs/ASSET_PRODUCTION.md) — original geometry, graphics, sound, music, provenance, and public-domain policy.

All new project-specific implementation and creative production will be authored by LLM agents. Existing engines and tools remain third-party infrastructure. The planned engine is Godot 4.7.2 with typed GDScript; the first implementation milestone will pin and verify the toolchain.

## License

The existing [LICENSE](LICENSE) is the Unlicense. The production plan retains it for original code, scripts, game data, and documentation, and specifies CC0 for original art and audio. Engine and dependency licenses retain their own terms and notices. See the [asset and licensing plan](docs/ASSET_PRODUCTION.md#license-scope).
