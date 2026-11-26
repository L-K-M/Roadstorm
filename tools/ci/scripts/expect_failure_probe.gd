extends SceneTree
## Deliberately failing probe for the M0 command tooling.
##
## PLAN.md M0.4 requires that "a deliberately failing test must return a
## failing exit code". `tools/ci/ci.sh test` runs this probe on every test pass
## and requires a nonzero exit status, so a broken exit-code path is caught
## instead of every check silently reporting success.
##
## It lives in the tooling (not in tools/smoke/) so the proof does not depend on
## another agent's owned file. Exit code 3 is deliberately distinctive.
##
## Usage:
##   godot --headless --path <project> --script res://tools/ci/scripts/expect_failure_probe.gd
##   echo $?   # 3

func _initialize() -> void:
	printerr("[ci-expect-failure] deliberate failure: proving a failing check exits nonzero")
	quit(3)
	return
