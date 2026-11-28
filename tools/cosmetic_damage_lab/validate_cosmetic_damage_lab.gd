extends SceneTree
## Headless entry point for the cosmetic damage lab.

const ChecksScript := preload("res://tools/cosmetic_damage_lab/cosmetic_damage_lab_checks.gd")

func _initialize() -> void:
	var checks := ChecksScript.new()
	var summary: Dictionary = checks.run_all()

	print("COSMETIC_DAMAGE_LAB_SUMMARY ", JSON.stringify(summary))
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
		push_error("cannot write summary to %s" % path)
		return
	file.store_string(JSON.stringify(summary, "  ", false, true))
	file.close()
	print("COSMETIC_DAMAGE_SUMMARY_WRITTEN ", path)
