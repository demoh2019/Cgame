@tool
extends RefCounted

# The CLI is invoked directly (never through a shell) and only with
# arguments constructed by the addon, not arguments supplied by the model.
const MAX_LOG_BYTES := 24576
const TIMEOUT_MSEC := 90000


static func command_arguments(project_dir: String, log_path: String) -> PackedStringArray:
	return PackedStringArray([
		"--headless",
		"--recovery-mode",
		"--path", project_dir,
		"--log-file", log_path,
		"--import"
	])


static func log_file_path() -> String:
	return ProjectSettings.globalize_path("user://ai_game_builder/diagnostics/check_%d.log" % Time.get_ticks_usec())


static func read_log(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return ""
	var count := mini(handle.get_length(), MAX_LOG_BYTES)
	if handle.get_length() > count:
		handle.seek(handle.get_length() - count)
	return handle.get_buffer(count).get_string_from_utf8()


static func has_errors(log_text: String) -> bool:
	var lower := log_text.to_lower()
	return lower.contains("error:") or lower.contains("parse error") or lower.contains("script error") or lower.contains("failed to load") or lower.contains("could not parse")


static func result_label(exit_code: int, timed_out: bool, log_text: String) -> String:
	if timed_out:
		return "Headless validation timed out; the child process was stopped. Review the captured log."
	if exit_code != 0 and exit_code != -1:
		return "Godot import exited with code %d. Review diagnostics; nothing was sent to AI." % exit_code
	if has_errors(log_text):
		return "Godot reported errors. Review diagnostics, then request a repair if desired."
	if log_text.is_empty():
		return "Godot finished, but no log was captured. Validation is inconclusive."
	return "Godot import finished without recognized errors. This is not a gameplay test or a proof of correctness."
