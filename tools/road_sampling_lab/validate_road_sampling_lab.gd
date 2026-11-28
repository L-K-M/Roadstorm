extends SceneTree
## Headless entry point for the bounded road arc-sampling laboratory.
##
## Prints ROAD_SAMPLING_LAB_CASE per case, ROAD_SAMPLING_LAB_SUMMARY and
## CHECKS_TOTAL/CHECKS_FAILED, then exits 0/1. This validates only the sampling
## table slice; it is not course geometry acceptance.

const ChecksScript = preload(
	"res://tools/road_sampling_lab/road_sampling_checks.gd"
)


func _initialize() -> void:
	var checks := ChecksScript.new()
	var summary: Dictionary = checks.run_all()

	print("ROAD_SAMPLING_LAB_SUMMARY ", JSON.stringify(summary))
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
		push_error("cannot write road sampling summary to %s" % path)
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()
	print("ROAD_SAMPLING_SUMMARY_WRITTEN ", path)
