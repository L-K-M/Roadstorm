extends SceneTree
## Headless entry point for the M2.1 road-source contract laboratory.
##
## Run from an isolated scratch project after a headless import:
##   godot --headless --fixed-fps 60 --path <scratch> \
##       --script res://tools/road_source_lab/validate_road_source_lab.gd \
##       -- --summary-out <scratch>/road_source_summary.json
##
## Prints ROAD_SOURCE_LAB_CASE per case, ROAD_SOURCE_LAB_SUMMARY and
## CHECKS_TOTAL/CHECKS_FAILED, then exits 0/1. This is a contract check only:
## no mesh, sampling, physics or course artifact is produced.

const ChecksScript = preload(
	"res://tools/road_source_lab/road_source_checks.gd"
)


func _initialize() -> void:
	var checks := ChecksScript.new()
	var summary: Dictionary = checks.run_all()

	print("ROAD_SOURCE_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", summary["checks"], " CHECKS_FAILED=", summary["checks_failed"])

	var out_path := _summary_out_path()
	if not out_path.is_empty() and bool(summary["pass"]):
		_write_summary(out_path, summary)

	quit(0 if bool(summary["pass"]) else 1)


func _summary_out_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--summary-out="):
			return arg.substr("--summary-out=".length())
	return ""


func _write_summary(path: String, summary: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write road source summary to %s" % path)
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()
	print("ROAD_SOURCE_SUMMARY_WRITTEN ", path)
