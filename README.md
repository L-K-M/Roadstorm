# Roadstorm Racer!

> [!IMPORTANT]
> LLM disclosure: This codebase was written with substantial help from large language models: AI coding agents working from the [`AGENTS.md`](AGENTS.md) brief in this repo.

**Latest release:** none yet. Packaging and publication are planned for M9.

An original, colorful arcade racer inspired by the energy of early polygonal racing games: generous drifting, memorable roads, lively scenery, assertive opponents, and four-player local split-screen.

Implementation is in progress. A placeholder shell, validation tooling and
desktop smoke exports exist; a playable game and public release are not yet
verified. See [current status](docs/STATUS.md) for measured gates and limits.

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

Project-specific implementation and creative production use LLM agents.
Existing engines and tools remain third-party infrastructure. The development
engine is pinned to Godot 4.7.2 with typed GDScript; the toolchain decision and
its current verification limits are recorded in [M0.1 evidence](docs/evidence/m01-pin-decision-20261127.md).

## Independent plan reviews

Historical plan reviewers followed [REVIEW_PROMPT.md](REVIEW_PROMPT.md).
Implementation checkpoint reviewers follow [plan/IMPLEMENTATION.md](plan/IMPLEMENTATION.md):
they review independently, and the coordinator integrates their reports.

## License

The existing [LICENSE](LICENSE) is the Unlicense. The production plan retains it for original code, scripts, game data, and documentation, and specifies CC0 for original art and audio. Engine and dependency licenses retain their own terms and notices. See the [asset and licensing plan](docs/ASSET_PRODUCTION.md#license-scope).
