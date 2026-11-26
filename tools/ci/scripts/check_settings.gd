extends SceneTree
## Original headless project-settings check for the M0 command tooling.
##
## Run by `tools/ci/ci.sh validate`. It asserts the project-level invariants
## that docs/TECHNICAL_DESIGN.md states for the shell, so a change that breaks
## them fails a check instead of silently altering the simulation contract.
##
## Every expectation below is quoted from the specification in the comments.
## If a milestone deliberately changes one of them, update this check in the
## same change and record the decision; do not weaken it to make CI green.
##
## Usage:
##   godot --headless --path <project> --script res://tools/ci/scripts/check_settings.gd -- <major>.<minor>
##
## Output lines:
##   [ci-settings] key=<setting> result=ok|fail detail=<...>
##   [ci-settings] summary fails=<n>
## Exit code: 0 = pass, 1 = fail.

## "Start at 60 fixed physics ticks per second and interpolate the visual
## transform." (docs/TECHNICAL_DESIGN.md, Fixed tick and movement ownership)
const EXPECTED_TICKS := 60
## "Target 1920x1080 output at 60 FPS" (docs/TECHNICAL_DESIGN.md,
## Platform and rendering baseline).
const EXPECTED_WIDTH := 1920
const EXPECTED_HEIGHT := 1080
## "Start with Compatibility rendering" (provisional until M3 locks it).
const ALLOWED_RENDERERS: PackedStringArray = ["gl_compatibility", "mobile", "forward_plus"]

var _failures: int = 0
var _expected_features: String = ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_expected_features = args[0]
	_check("application/config/name", _nonempty("application/config/name"), str(ProjectSettings.get_setting("application/config/name", "")))
	_check("application/run/main_scene", _main_scene_ok(), str(ProjectSettings.get_setting("application/run/main_scene", "")))
	_check("application/config/features", _features_ok(), str(ProjectSettings.get_setting("application/config/features", [])))
	_check("rendering/renderer/rendering_method", _renderer_ok(), str(ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")))
	_check("physics/common/physics_ticks_per_second", _ticks_ok(), str(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)))
	_check("physics/common/physics_interpolation", _interpolation_ok(), str(ProjectSettings.get_setting("physics/common/physics_interpolation", false)))
	_check("display/window/size/viewport_width", _width_ok(), str(ProjectSettings.get_setting("display/window/size/viewport_width", 0)))
	_check("display/window/size/viewport_height", _height_ok(), str(ProjectSettings.get_setting("display/window/size/viewport_height", 0)))

	print("[ci-settings] summary fails=%d" % _failures)
	if _failures > 0:
		printerr("[ci-settings] RESULT: FAIL (%d setting check(s))" % _failures)
		quit(1)
		return
	print("[ci-settings] RESULT: PASS")
	quit(0)
	return


func _check(key: String, ok: bool, value: String) -> void:
	if ok:
		print("[ci-settings] key=%s result=ok value=%s" % [key, value])
	else:
		_failures += 1
		printerr("[ci-settings] key=%s result=fail value=%s" % [key, value])


func _nonempty(key: String) -> bool:
	var value: String = ProjectSettings.get_setting(key, "")
	return not value.strip_edges().is_empty()


func _main_scene_ok() -> bool:
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if path.is_empty():
		return false
	return ResourceLoader.exists(path)


func _features_ok() -> bool:
	var features: PackedStringArray = ProjectSettings.get_setting("application/config/features", [])
	if _expected_features.is_empty():
		return features.size() > 0
	return _expected_features in features


func _renderer_ok() -> bool:
	var renderer: String = ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")
	return renderer in ALLOWED_RENDERERS


func _ticks_ok() -> bool:
	return int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)) == EXPECTED_TICKS


func _interpolation_ok() -> bool:
	return bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))


func _width_ok() -> bool:
	return int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) == EXPECTED_WIDTH


func _height_ok() -> bool:
	return int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) == EXPECTED_HEIGHT
