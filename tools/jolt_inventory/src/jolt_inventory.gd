extends SceneTree
## Headless Jolt settings inventory for the Roadstorm M0.1 evidence record
## (docs/evidence/jolt-settings.md).
##
## Why it exists: Opus review finding R3 (residual of finding 5) in
## review/implementation/m0-five-jobs-opus-recheck-929c4082-0280-464e-830a-00dd35c164e1.md
## notes that the game project pins `physics/3d/physics_engine="Jolt Physics"`
## but leaves Jolt's own `physics/jolt_physics_3d/*` settings unrecorded. This
## script records them: the engine build, the host, and the effective value of
## every Jolt setting, without pinning or changing any of them.
##
## It only READS ProjectSettings. It writes no setting, instantiates no
## physics world and touches no scene. run_inventory.sh runs it inside a
## throwaway project in a temporary directory, so the game project is never
## opened by the engine.
##
## Termination: the script always exits through quit() - from _initialize() on
## the normal path, and after a single frame from _process() if that path were
## ever bypassed, so no engine command can be left hanging.
##
## Usage (normally through run_inventory.sh):
##   godot --headless --path <project> --script res://src/jolt_inventory.gd \
##       -- label=<tag> [out=<absolute-json-path>]
##
## Output: stable `key value` lines, one per setting, plus a single
## `JOLT_INVENTORY_JSON` line carrying the same data as JSON. Exit code 0 means
## the inventory was read completely, 1 means at least one problem was recorded.

## Every Jolt setting registered by the engine starts with this prefix. The
## count is build-specific: 32 on the pinned 4.7.2 official build.
const PREFIX := "physics/jolt_physics_3d/"

## Physics settings that select and pace the simulation. Recorded next to the
## Jolt block because they decide which backend the block applies to and how
## often it steps.
const CONTEXT_SETTINGS: Array[String] = [
	"physics/3d/physics_engine",
	"physics/common/physics_ticks_per_second",
	"physics/common/physics_interpolation",
	"physics/3d/default_gravity",
]

const TYPE_NAMES := {
	TYPE_BOOL: "bool",
	TYPE_INT: "int",
	TYPE_FLOAT: "float",
	TYPE_STRING: "String",
	TYPE_STRING_NAME: "StringName",
	TYPE_NODE_PATH: "NodePath",
	TYPE_ARRAY: "Array",
	TYPE_DICTIONARY: "Dictionary",
}

var _label := "local"
var _out_path := ""


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	var problems: Array[String] = []
	var settings := _collect_settings(problems)
	var report := _build_report(settings, problems)
	for line in _format_report(report):
		print(line)
	if _out_path != "":
		_write_json(report, problems)
	quit(1 if not problems.is_empty() else 0)


## Safety net: a SceneTree script that returns from _initialize() without
## quitting keeps the engine running forever. Returning true here ends the
## main loop after the first processed frame if that ever happens.
func _process(_delta: float) -> bool:
	return true


func _parse_args(args: Array) -> void:
	for arg in args:
		var text := String(arg)
		if text.begins_with("label="):
			_label = text.substr(6)
		elif text.begins_with("out="):
			_out_path = text.substr(4)
		else:
			print("jolt_inventory: ignoring unknown argument '", text, "'")


func _collect_settings(problems: Array[String]) -> Array:
	var settings: Array = []
	for property_info in ProjectSettings.get_property_list():
		var name := String(property_info.get("name", ""))
		if not name.begins_with(PREFIX):
			continue
		if not ProjectSettings.has_setting(name):
			problems.append("setting listed in the property list but not readable: " + name)
			continue
		var value: Variant = ProjectSettings.get_setting(name)
		var type_id := int(property_info.get("type", -1))
		settings.append({
			"name": name,
			"type": TYPE_NAMES.get(type_id, "type_" + str(type_id)),
			# str() prints a float with its full float32 round-trip precision
			# (0.01999999955297, not 0.02), which is what an evidence record
			# needs; ints and bools print exactly.
			"value": str(value),
			"hint_string": String(property_info.get("hint_string", "")),
		})
	if settings.is_empty():
		problems.append("no " + PREFIX + "* settings found; this build has no Jolt settings to record")
	settings.sort_custom(_compare_by_name)
	return settings


func _compare_by_name(a: Variant, b: Variant) -> bool:
	return String(a["name"]) < String(b["name"])


func _build_report(settings: Array, problems: Array) -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	var context := {}
	for name in CONTEXT_SETTINGS:
		if ProjectSettings.has_setting(name):
			context[name] = str(ProjectSettings.get_setting(name))
		else:
			problems.append("context setting not readable: " + name)
			context[name] = "<missing>"
	return {
		"schema": "roadstorm.jolt_inventory.v1",
		"label": _label,
		"engine": {
			"version_string": str(version.get("string", "")),
			"major": int(version.get("major", -1)),
			"minor": int(version.get("minor", -1)),
			"patch": int(version.get("patch", -1)),
			"status": str(version.get("status", "")),
			"build": str(version.get("build", "")),
			"commit": str(version.get("hash", "")),
		},
		"host": {
			"os": OS.get_name(),
			"os_version": OS.get_version(),
			"processor": OS.get_processor_name(),
			"processor_count": OS.get_processor_count(),
			"model": OS.get_model_name(),
			"display_driver": DisplayServer.get_name(),
		},
		"context_settings": context,
		"setting_count": settings.size(),
		"settings": settings,
		"problems": problems,
	}


func _format_report(report: Dictionary) -> Array:
	var lines: Array = []
	lines.append("JOLT_INVENTORY_SCHEMA " + str(report["schema"]))
	lines.append("label " + str(report["label"]))
	var engine: Dictionary = report["engine"]
	lines.append("engine_version " + str(engine["version_string"]))
	lines.append("engine_version_info %d.%d.%d %s %s" % [engine["major"], engine["minor"], engine["patch"], engine["status"], engine["build"]])
	lines.append("engine_commit " + str(engine["commit"]))
	var host: Dictionary = report["host"]
	lines.append("os %s %s" % [host["os"], host["os_version"]])
	lines.append("processor %s x%d" % [host["processor"], host["processor_count"]])
	lines.append("model " + str(host["model"]))
	lines.append("display_driver " + str(host["display_driver"]))
	for name in CONTEXT_SETTINGS:
		lines.append("context_setting " + name + " " + str(report["context_settings"][name]))
	lines.append("setting_count " + str(report["setting_count"]))
	for setting in report["settings"]:
		lines.append("setting %s %s %s %s" % [setting["name"], setting["type"], setting["value"], setting["hint_string"]])
	for problem in report["problems"]:
		lines.append("problem " + str(problem))
	lines.append("JOLT_INVENTORY_JSON " + JSON.stringify(report))
	return lines


func _write_json(report: Dictionary, problems: Array) -> void:
	var file := FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		problems.append("could not write JSON report to " + _out_path)
		print("problem could not write JSON report to ", _out_path)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.store_string("\n")
	file.close()
	print("json_written " + _out_path)
