# Driving Lab practice flow

`run_practice_flow_lab.sh` copies the project to an ignored private scratch
directory, checks the pinned Godot 4.7.2 build, imports the copy, runs the
headless practice-flow validator, and verifies that its deliberate failing
check exits nonzero. Engine error lines fail the run even if Godot exits zero.

Every engine call is serialized on a shared Godot test lock with
`/usr/bin/lockf -k`, defaulting to `work/agents/coordinator/godot-test.lock`
in the live repository and to a private lock inside the run's own scratch for a
plain source archive; `--lock FILE` or `ROADSTORM_GODOT_LOCK` overrides it.
`--timeout` is clamped to 120 s. The runner owns that lock, so do not wrap it
in an outer `lockf` on the same path. HUP, INT and TERM reap the runner's own
engine children, remove the scratch and exit 143 instead of falling through
into the interrupted control flow.

From the repository root:

```sh
tools/practice_flow_lab/run_practice_flow_lab.sh \
  --godot work/agents/coordinator/toolchain-m01/prefix/editor/Godot.app/Contents/MacOS/Godot
```

The validator enters the graybox Driving Lab from the boot menu, delivers
synthetic keyboard input through Godot, observes finite motion and committed
ticks, returns to the menu twice, checks camera and HUD teardown, and checks
that a forced laboratory halt appears on the game overlay. The camera rig is
attached to the root viewport, so teardown checks inspect the full scene tree.
While practice runs it also asserts the committed overlay ownership: exactly
the DriveLab HUD layer and the game's GameOverlay layer under the root viewport,
by instance identity, and after each return that the HUD layer instance itself
is freed and no root-wide CanvasLayer survives. `--inject-root-hud` is the
mutation control for those checks: it parks an extra CanvasLayer on the root
during the first entry, which must fail both the active-ownership and the
teardown checks.

This is a structural and headless behavior check. It does not establish
handling quality, physical device input, rendered readability, split-screen,
race flow, or any M0/M1/M5 milestone acceptance.
