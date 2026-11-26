# Boot smoke test

Headless check for the M0 shell (`project.godot`, `scenes/`, `src/boot/`).
It is a placeholder-shell check only: it does not exercise any gameplay, because
no gameplay exists yet.

## Run

From the repository root, with the pinned Godot 4.7.2 Standard binary:

```sh
tools/smoke/run_boot_smoke.sh
```

`run_boot_smoke.sh` is the supported entry point. It:

1. checks that the Godot binary is the exact pinned official build
   (`godot --version`, compared against the version string recorded in
   `tools/toolchain/pin/engine.txt`);
2. runs the check headless and captures stdout and stderr;
3. fails if the check exits nonzero **or** if the engine reported a script
   error in its output.

Expected result: `PASS` and exit code `0`. Exit codes: `0` = passed,
`1` = a check failed, `2` = the wrapper could not run. `GODOT_BIN` selects the
binary, `--project <dir>` checks another checkout or snapshot, and any other
argument (for example `--expect-failure`) is forwarded to the smoke script.

The underlying script can also be run directly:

```sh
godot --headless --path . --script res://tools/smoke/boot_smoke.gd
```

A direct run misses runtime script errors (see Limitations), so prefer the
wrapper.

## Prove the failing path exits nonzero

```sh
tools/smoke/run_boot_smoke.sh --expect-failure
echo $?   # 1
```

The `--expect-failure` user flag makes the check fail deliberately so a
coordinator or CI can confirm that a failing check returns a failing exit code
(PLAN.md M0.4).

## Fault injection

`tools/smoke/fault_injection.sh` goes further: it copies the checkout into an
isolated snapshot, injects a fault into the copy, and verifies that the check
exits nonzero:

```sh
tools/smoke/fault_injection.sh
```

| Case | Injected fault | Expected |
| --- | --- | --- |
| clean | none | pass (exit 0) |
| control | `--expect-failure` | fail (exit 1) |
| parse error | invalid GDScript appended to `src/boot/game.gd` | fail |
| runtime error | null dereference in `game.gd::_ready` | fail |
| runtime error | null dereference in `main_menu.gd::_ready` | fail |
| detached script | `game.tscn` points at a script that does not exist | fail |

Every case runs in a private temporary directory: a snapshot copy of the
checkout (no `.git`, no `.godot`, no `work/`) with its own `HOME` and
`TMPDIR`, so the engine cache never touches the live tree. The live sources,
scenes and scripts are never edited; the harness verifies that with checksums
of `src/boot/` and `scenes/` before and after, and fails if a `.godot` cache
directory appears in the checkout. Exit codes: `0` = every case behaved as
expected, `1` = a case misbehaved, `2` = the harness could not run.

## What it checks

- Engine is the exact pinned official Godot 4.7.2 build: version, release
  status, build flavour and commit hash (mirrored from
  `tools/toolchain/pin/engine.txt`; `tools/toolchain/verify.sh` independently
  pins the installed binary digest and the export templates).
- Project settings: boot scene is the main scene, renderer is
  `gl_compatibility` (provisional until M3), physics runs at 60 ticks/second.
- `scenes/boot.tscn`, `scenes/main_menu.tscn` and `scenes/game.tscn` exist,
  load and instantiate, and every script attached to them is loadable
  (`can_instantiate()`), so a parse error or a detached script fails.
- The menu's quit button has its `pressed` signal connected: the observable
  side effect of `main_menu.gd::_ready` completing.
- The boot scene hands off to the menu, and the placeholder race scene loads.

## Limitations

- Headless execution uses the dummy display/audio drivers; it cannot verify
  windowed rendering, audio output or input devices.
- A runtime script error (an exception thrown from a script that still parses)
  is invisible from inside the engine process. The wrapper detects it by
  scanning the engine output for `SCRIPT ERROR`, `Failed to load script`,
  `Parse Error`, `ERROR:` and `USER ERROR:` lines. That pattern list is a
  heuristic, which is why the wrapper is the supported entry point.
- The wrapper pins the engine by its `--version` string only. It does not
  verify the binary's digest or the export templates; that is
  `tools/toolchain/verify.sh`'s job.
- `Engine.get_version_info()["string"]` is not the same text as
  `godot --version` (it reads `4.7.2-stable (official)`), so the in-script
  check compares status, build and commit hash instead of that string.
