extends SceneTree
## Headless entry point for the bounded open road-frame laboratory.
##
## Prints ROAD_FRAME_LAB_CASE per case, ROAD_FRAME_LAB_SUMMARY and
## CHECKS_TOTAL/CHECKS_FAILED, then exits 0/1. This validates only the frame
## transport slice; it is not course geometry acceptance.

const ChecksScript = preload(
	"res://tools/road_frame_lab/road_frame_checks.gd"
)


func _initialize() -> void:
	var checks := ChecksScript.new()
	var summary: Dictionary = checks.run_all()

	print("ROAD_FRAME_LAB_SUMMARY ", JSON.stringify(summary))
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
		push_error("cannot write road frame summary to %s" % path)
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()
	print("ROAD_FRAME_SUMMARY_WRITTEN ", path)
