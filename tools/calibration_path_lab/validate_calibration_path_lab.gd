extends SceneTree
## Headless entry point for the M1.7 calibration-path conversion laboratory.
##
## Run from an isolated scratch project after a headless import:
##   godot --headless --fixed-fps 60 --path <scratch> \
##       --script res://tools/calibration_path_lab/validate_calibration_path_lab.gd \
##       -- --summary-out <scratch>/calibration_path_summary.json
##
## Prints CALIBRATION_PATH_LAB_CASE per case, CALIBRATION_PATH_LAB_SUMMARY and
## CHECKS_TOTAL/CHECKS_FAILED, then exits 0/1.

const ChecksScript = preload(
	"res://tools/calibration_path_lab/calibration_path_lab_checks.gd"
)
const SourceScript = preload("res://tools/calibration_path_lab/calibration_path_source.gd")


func _initialize() -> void:
	var checks := ChecksScript.new()
	var summary: Dictionary = checks.run_all()

	var built := SourceScript.build()
	if bool(built["ok"]):
		summary["path_summary"] = built["summary"]
	else:
		summary["conversion_error"] = String(built["error"])

	print("CALIBRATION_PATH_LAB_SUMMARY ", JSON.stringify(summary))
	print("CHECKS_TOTAL=", summary.checks, " CHECKS_FAILED=", summary.checks_failed)

	var out_path := _summary_out_path()
	if not out_path.is_empty() and bool(summary["pass"]):
		_write_summary(out_path, summary)

	quit(0 if summary.pass else 1)


func _summary_out_path() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--summary-out="):
			return arg.substr("--summary-out=".length())
		if arg == "--summary-out":
			continue
	return ""


func _write_summary(path: String, summary: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write calibration path summary to %s" % path)
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()
	print("CALIBRATION_PATH_SUMMARY_WRITTEN ", path)
