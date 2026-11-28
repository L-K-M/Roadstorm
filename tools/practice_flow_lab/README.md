# Driving Lab practice flow

`run_practice_flow_lab.sh` copies the project to an ignored private scratch
directory, checks the pinned Godot 4.7.2 build, imports the copy, runs the
headless practice-flow validator, and verifies that its deliberate failing
check exits nonzero. Engine error lines fail the run even if Godot exits zero.

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

This is a structural and headless behavior check. It does not establish
handling quality, physical device input, rendered readability, split-screen,
race flow, or any M0/M1/M5 milestone acceptance.
