# M1.5 speed and drift HUD laboratory

`src/presentation/speed_hud.gd` is a presentation-only `SpeedHud` `Control`
for one eventual local player slot, plus `scenes/ui/speed_hud.tscn`. This
directory contains its headless Godot 4.7.2 validation entry point and bounded
isolated runner. The component is an M1.5 slice, not an integrated race HUD.

## Files

| Path | Role |
| --- | --- |
| `src/presentation/speed_hud.gd` | owned component: speed readout, reverse text cue, five-phase drift cue, qualifying flag forwarding, per-slot scale |
| `scenes/ui/speed_hud.tscn` | standalone scene: panel, labels and owned script |
| `tools/hud_lab/validate_speed_hud.gd` | headless `SceneTree` validation entry point |
| `tools/hud_lab/run_validation.sh` | pinned-engine wrapper that stages an isolated copy, imports resources, bounds every Godot run, and runs the pass plus deliberate-failure cases |

## Component behaviour

Call `update(state, cue, units)` once per display refresh with a committed
`CarState`, a small `DriftCue` telemetry record (`phase`, `qualifying`,
`slip_deg`) and `SpeedUnit.KM_H` or `SpeedUnit.MPH`. Validation happens before
any widget mutation, so nonfinite state/telemetry, a null record, or an invalid
phase/unit returns false and leaves the previous display untouched. The numeral
is the absolute road-plane speed converted from m/s; `REVERSE` appears from a
small forward-component deadband. Drift text distinguishes grip, entry,
sustained, recovery and airborne, and slip degrees are shown for the three
contact phases. Color and shape duplicate the text cue; no score, points or
reward wording exists. `QUALIFYING DRIFT` forwards the supplier's eligibility
flag only during a sustained drift, so airborne never claims qualification.

The scene instantiates once per player viewport; there is no autoload or global
state. Labels are created once and only their text/visibility changes per
update. All positions, sizes, font sizes and colors are provisional authored
values subject to visual/contrast review; the base layout targets a 960x540
panel (40 px numerals, 20-22 px labels) and `set_hud_scale()` scales it.

Unimplemented seams, explicitly not claimed: race/panel integration,
split-screen cost, localization, accessibility settings beyond redundant text,
art, audio, controller input and M1.5/M1 acceptance.

## Run

From the repository root, with the pinned Godot 4.7.2 binary:

```sh
mkdir -p work/agents/<job-id>/scratch-hud-lab work/agents/<job-id>/logs
tools/hud_lab/run_validation.sh \
    --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot \
    --private-dir work/agents/<job-id>/scratch-hud-lab/private \
    --log work/agents/<job-id>/logs/hud-lab-run.log \
    --timeout 120
```

The runner checks the engine against `tools/toolchain/pin/engine.txt`, stages a
fresh private copy (excluding `.git`, `.godot`, `work` and Python caches),
redirects XDG/TMP caches into scratch, then runs, all under `timeout`:

1. `godot --headless --path <private> --import`;
2. `godot --headless --fixed-fps 60 --path <private> --script res://tools/hud_lab/validate_speed_hud.gd` (pass case);
3. the same script with `-- --expect-failure` (deliberate-failure proof).

It fails if any invocation logs `SCRIPT ERROR`, `Parse Error`, `ERROR:` or
`USER ERROR:`, if `CHECKS_TOTAL` is absent, if the pass case exits nonzero or
reports failures, or if the deliberate-failure case exits zero without
reporting a failure. An explicit `--private-dir` is create-only and refused if
it already exists; its parent must already exist. Omit it for an auto-cleaned
temporary copy. Direct invocation after an import is also possible:

```sh
godot --headless --fixed-fps 60 --path <isolated-project> \
    --script res://tools/hud_lab/validate_speed_hud.gd
```

Exit code 0 means every check passed; exit 1 means at least one check failed;
exit 2 means the runner refused unsafe input or could not execute the pinned
engine. The validator prints one machine-readable `HUD_RESULT <json>` line and
`CHECKS_TOTAL=<n> CHECKS_FAILED=<n>`.

## Scope limits

- Headless dummy display/audio drivers: no rendering, visual readability,
  contrast or device/controller verification.
- No `SubViewport` attachment, split-screen exercise or four-player
  performance claim.
- No integrated race wiring, audio, localization or settings persistence.
- Provisional sizing/color choices are documented in the component and were
  only checked structurally at 960x540 and 100%/150% scale.
- No M1.5 or full M1 acceptance claim; the coordinator integrates and judges
  the component.
