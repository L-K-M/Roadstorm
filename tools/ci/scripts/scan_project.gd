extends SceneTree
## Original headless resource/script scan for the M0 command tooling.
##
## Run by `tools/ci/ci.sh validate` (verification matrix row T01: "clean import,
## typed scripts, resources, source/generated references ... no missing resource
## or script errors").
##
## Why a script and not just the engine exit code: with the pinned engine a
## scene whose [ext_resource] points at a missing script still *loads and
## instantiates* with exit code 0, printing only "ERROR:" lines to the log.
## Inspecting resources explicitly and reporting structured results is the only
## way to fail clearly instead of falsely passing. The shell wrapper also greps
## the captured engine log for error lines as a second net.
##
## Usage:
##   godot --headless --path <project> --script res://tools/ci/scripts/scan_project.gd -- [res://path/to/skip]
##
## Output lines (parsed by tools/ci/lib/common.sh):
##   [ci-scan] kind=<...> path=<res://...> result=ok|warn|fail detail=<...>
##   [ci-scan] summary files=<n> scripts=<n> scenes=<n> fails=<n> warns=<n>
##
## Exit code: 0 = no failures, 1 = at least one failure.

## Directory names never worth scanning.
var _skip_names: PackedStringArray = [".godot", "imported", "mono", ".import"]
## Full res:// path to skip (the tooling's own scratch output directory).
var _skip_path: String = ""

const SCRIPT_EXT := "gd"
const SCENE_EXT := "tscn"
const RESOURCE_EXTS: PackedStringArray = ["tres", "res"]

var _failures: int = 0
var _warnings: int = 0
## res:// path of this script: it cannot reload itself while it runs.
var _self_path: String = ""
var _files: int = 0
var _scripts: int = 0
var _scenes: int = 0
var _resources: int = 0
var _class_names: Dictionary = {}


func _initialize() -> void:
	_self_path = get_script().resource_path
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and not args[0].begins_with("--"):
		_skip_path = args[0]
		print("[ci-scan] skipping ", _skip_path)

	_scan_dir("res://")
	_summary()


func _summary() -> void:
	print("[ci-scan] summary files=%d scripts=%d scenes=%d resources=%d fails=%d warns=%d" % [
		_files, _scripts, _scenes, _resources, _failures, _warnings,
	])
	if _failures > 0:
		printerr("[ci-scan] RESULT: FAIL (%d failure(s), %d warning(s))" % [_failures, _warnings])
		quit(1)
		return
	print("[ci-scan] RESULT: PASS (%d warning(s))" % _warnings)
	quit(0)
	return


func _scan_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		_fail("directory", path, "cannot open directory")
		return
	if dir.list_dir_begin() != OK:
		_fail("directory", path, "cannot list directory")
		return
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := path.path_join(name)
			if dir.current_is_dir():
				if not _is_skipped(full):
					_scan_dir(full)
			else:
				_scan_file(full)
		name = dir.get_next()
	dir.list_dir_end()


# _is_skipped : directories the engine itself does not import into this project.
# Godot's editor file system skips a directory that contains its own
# project.godot (a nested project), so resources there are not part of this
# project's T01 scope; scanning them would report failures the engine does not
# have. They are reported as notes so nothing is hidden.
func _is_skipped(path: String) -> bool:
	if _skip_path != "" and (path == _skip_path or path.begins_with(_skip_path + "/")):
		return true
	for skip in _skip_names:
		if path.get_file() == skip:
			return true
	if path != "res://" and FileAccess.file_exists(path.path_join("project.godot")):
		print("[ci-scan] kind=nested-project path=%s result=skip detail=contains its own project.godot; not part of this project" % path)
		return true
	return false


func _scan_file(path: String) -> void:
	_files += 1
	var ext := path.get_extension()
	match ext:
		SCRIPT_EXT:
			_scan_script(path)
		SCENE_EXT:
			_scenes += 1
			_scan_scene(path)
		_:
			for candidate in RESOURCE_EXTS:
				if ext == candidate:
					_resources += 1
					_scan_resource(path)
					break


func _scan_script(path: String) -> void:
	_scripts += 1
	var text := FileAccess.get_file_as_string(path)
	if text.strip_edges().is_empty():
		_fail("script", path, "empty or unreadable source")
		return
	var loaded: Resource = load(path)
	if loaded == null or not (loaded is Script):
		_fail("script", path, "failed to load")
		return
	var script: Script = loaded
	# `load()` still returns a GDScript object when compilation fails (verified
	# against the pinned engine), so recompile and check the result. The script
	# currently running cannot reload itself; its own compilation already
	# succeeded by definition.
	var detail := ""
	if script.get_instance_base_type().is_empty():
		detail = "does not compile"
	elif path != _self_path:
		var reload_err: Error = script.reload(false)
		if reload_err != OK:
			detail = "does not compile: %s" % error_string(reload_err)
	if detail != "":
		_fail("script", path, detail)
		return

	var uid_path := path + ".uid"
	if not FileAccess.file_exists(uid_path):
		_warn("script", path, "no .uid sidecar file (Godot 4.4+ expects one per script)")
	else:
		var expected := ResourceUID.text_to_id(FileAccess.get_file_as_string(uid_path).strip_edges())
		if expected == ResourceUID.INVALID_ID:
			_warn("script", path, "unreadable .uid sidecar file")

	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("class_name "):
			var declared := trimmed.substr("class_name ".length()).strip_edges()
			if declared == "":
				_warn("script", path, "empty class_name declaration")
			elif _class_names.has(declared):
				_fail("script", path, "duplicate global class_name '%s' (also in %s)" % [declared, _class_names[declared]])
			else:
				_class_names[declared] = path
			break
	_report("script", path, "ok", "compiles; base=%s" % script.get_instance_base_type())


func _scan_scene(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	# A scene whose [ext_resource] points at a missing file still loads and
	# instantiates with exit code 0, so check the declared paths explicitly.
	if _check_ext_resources("scene", path, text):
		return
	var packed: PackedScene = load(path)
	if packed == null:
		_fail("scene", path, "failed to load")
		return
	var instance: Node = packed.instantiate()
	if instance == null:
		_fail("scene", path, "loaded but instantiate() returned null")
		return
	var root_class := instance.get_class()
	instance.free()
	_report("scene", path, "ok", "root=%s" % root_class)


func _scan_resource(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if _check_ext_resources("resource", path, text):
		return
	var loaded: Resource = load(path)
	if loaded == null:
		_fail("resource", path, "failed to load")
		return
	_report("resource", path, "ok", loaded.get_class())


# _check_ext_resources : returns the number of missing declared dependencies.
func _check_ext_resources(kind: String, path: String, text: String) -> int:
	var missing := 0
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("[ext_resource"):
			continue
		var marker := trimmed.find("path=\"")
		if marker < 0:
			continue
		var rest := trimmed.substr(marker + "path=\"".length())
		var closing := rest.find("\"")
		if closing < 0:
			continue
		var dep := rest.substr(0, closing)
		if dep.begins_with("res://") and not FileAccess.file_exists(dep):
			_fail(kind, path, "ext_resource path does not exist: %s" % dep)
			missing += 1
	return missing


func _report(kind: String, path: String, result: String, detail: String) -> void:
	print("[ci-scan] kind=%s path=%s result=%s detail=%s" % [kind, path, result, detail])


func _warn(kind: String, path: String, detail: String) -> void:
	_warnings += 1
	print("[ci-scan] kind=%s path=%s result=warn detail=%s" % [kind, path, detail])


func _fail(kind: String, path: String, detail: String) -> void:
	_failures += 1
	printerr("[ci-scan] kind=%s path=%s result=fail detail=%s" % [kind, path, detail])
