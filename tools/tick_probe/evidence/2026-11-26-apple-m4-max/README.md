# Recorded probe evidence — 26 November 2026, Apple M4 Max, macOS

> **SUPERSEDED (backend correction, same day).** These runs were made with no
> `physics/3d/physics_engine` setting, i.e. backend `DEFAULT`, which the
> contrast run in `../2026-11-26-apple-m4-max-jolt/` shows behaved as
> GodotPhysics3D on this build. The project now pins Jolt Physics, and every
> measured result here has been re-recorded under Jolt in
> `../2026-11-26-apple-m4-max-jolt/`. Keep this directory only as the record
> of the pre-pin (GodotPhysics3D/DEFAULT) measurements; do not cite it as Jolt
> evidence.

Commands run from the repository root with Godot 4.7.2-stable (official) on
`PATH`:

```sh
godot --headless --fixed-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural
godot --headless --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural
godot --headless --max-fps 60 --path tools/tick_probe \
    --script res://src/tick_probe.gd -- mode=structural
python3 tools/tick_probe/compare_modes.py
```

Each `structural-*.json` is the complete `PROBE_RESULT` payload for that pacing
mode; each `.checks.txt` is the matching `CHECKS_TOTAL=... CHECKS_FAILED=...`
summary. `compare-modes.txt` is the full accelerated-versus-real-time
comparison output.

All three structural runs: 57/57 checks passed, exit code 0. The comparison
passed with identical final positions in both pacing modes. Wall-clock numbers
are specific to this host and run; the structural checks are the stable gate.
