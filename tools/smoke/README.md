# Boot smoke test

Original headless check for the M0 shell (`project.godot`, `scenes/`, `src/boot/`).
It is a placeholder-shell check only: it does not exercise any gameplay, because
no gameplay exists yet.

## Run

From the repository root, with the pinned Godot 4.7.2 Standard binary:

```sh
godot --headless --path . --script res://tools/smoke/boot_smoke.gd
```

Expected result: `PASS` and exit code `0`.

## Prove the failing path exits nonzero

```sh
godot --headless --path . --script res://tools/smoke/boot_smoke.gd -- --expect-failure
echo $?   # 1
```

The `--expect-failure` user flag makes the check fail deliberately so a
coordinator or CI can confirm that a failing check returns a failing exit code
(PLAN.md M0.4).

## What it checks

- Engine is Godot 4.7.2 (the version pinned in M0.1).
- Project settings: boot scene is the main scene, renderer is
  `gl_compatibility` (provisional until M3), physics runs at 60 ticks/second.
- `scenes/boot.tscn`, `scenes/main_menu.tscn` and `scenes/game.tscn` exist and
  instantiate without script errors.
- The boot scene hands off to the menu, and the placeholder race scene loads.

## Limitations

- Headless execution uses the dummy display/audio drivers; it cannot verify
  windowed rendering, audio output or input devices.
- Exit-code detection relies on observable behavior (handoff completing). A
  script error that still leaves the shell running would surface as a timeout
  failure rather than a direct error report.
