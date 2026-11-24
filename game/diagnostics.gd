extends Logger

const META := &"siraj_diagnostics"
const SCRIPT_PATH := "res://game/diagnostics.gd"
const LOG_PATH := "user://siraj-errors.json"
const MAX_ENTRIES := 20
const MAX_ENTRY_LENGTH := 550
const EXIT_REASONS := {
	0: "unknown", 1: "self exit", 2: "signal", 3: "low memory",
	4: "Java crash", 5: "native crash", 6: "ANR", 7: "initialization failure",
	8: "permission change", 9: "excessive resource usage", 10: "user or system request",
	11: "user stopped", 12: "dependency died", 13: "other", 14: "freezer",
}

var records := PackedStringArray()
var last_exit_time := 0
var mutex := Mutex.new()
var flush_pending := false
var writing := false
var last_message := ""
var last_message_time := -2000


static func install(tree: SceneTree) -> Logger:
	if tree.has_meta(META):
		return tree.get_meta(META)
	var script := load(SCRIPT_PATH) as Script
	var logger: Logger = script.new()
	logger.load_history()
	tree.set_meta(META, logger)
	OS.add_logger(logger)
	logger.capture_android_exits.call_deferred()
	return logger


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var source := "%s:%d %s" % [file.get_file(), line, function]
	if not script_backtraces.is_empty() and not script_backtraces[0].is_empty():
		var trace := script_backtraces[0]
		source = "%s:%d %s" % [trace.get_frame_file(0).get_file(), trace.get_frame_line(0), trace.get_frame_function(0)]
	var level := "warning" if error_type == Logger.ERROR_TYPE_WARNING else "error"
	append("%s | %s | %s" % [level, source, rationale if not rationale.is_empty() else code])


func append(message: String) -> void:
	var brief := message.replace("\r", " ").replace("\n", " ").left(MAX_ENTRY_LENGTH)
	var now := Time.get_ticks_msec()
	mutex.lock()
	if not writing and (brief != last_message or now - last_message_time >= 2000):
		last_message = brief
		last_message_time = now
		records.append("%s | %s" % [Time.get_datetime_string_from_system(), brief])
		if records.size() > MAX_ENTRIES:
			records.remove_at(0)
		if not flush_pending:
			flush_pending = true
			flush.call_deferred()
	mutex.unlock()


func text() -> String:
	mutex.lock()
	var result := "\n".join(records)
	mutex.unlock()
	return result


func load_history() -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ)
	if file == null or file.get_length() > 48 * 1024:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return
	var saved: Variant = json.data.get("entries")
	if saved is Array:
		for index in range(maxi(0, saved.size() - MAX_ENTRIES), saved.size()):
			if saved[index] is String:
				records.append(saved[index].left(MAX_ENTRY_LENGTH + 24))
	var saved_time: Variant = json.data.get("last_android_exit")
	if (saved_time is int or saved_time is float) and saved_time >= 0 and saved_time < 9999999999999:
		last_exit_time = int(saved_time)


func flush() -> void:
	mutex.lock()
	if not flush_pending:
		mutex.unlock()
		return
	flush_pending = false
	writing = true
	var snapshot := records.duplicate()
	mutex.unlock()
	var temporary := LOG_PATH + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"entries": Array(snapshot), "last_android_exit": last_exit_time}))
		file.flush()
		var written := file.get_error() == OK
		file.close()
		if written:
			DirAccess.rename_absolute(temporary, LOG_PATH)
	mutex.lock()
	writing = false
	mutex.unlock()


func capture_android_exits() -> void:
	if not Engine.has_singleton("AndroidRuntime") or not Engine.has_singleton("JavaClassWrapper"):
		return
	var java := Engine.get_singleton("JavaClassWrapper")
	var version = java.wrap("android.os.Build$VERSION")
	if version == null or version.SDK_INT < 30:
		return
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	if activity == null:
		return
	var manager = activity.getSystemService("activity")
	if manager == null or java.get_exception() != null:
		return
	var exits = manager.getHistoricalProcessExitReasons(activity.getPackageName(), 0, 5)
	if exits == null or java.get_exception() != null:
		push_warning("Android did not return application exit history.")
		return
	for index in range(mini(exits.size(), 5) - 1, -1, -1):
		var entry = exits.get(index)
		if entry == null:
			continue
		var timestamp: int = entry.getTimestamp()
		if timestamp <= last_exit_time:
			continue
		var reason: int = entry.getReason()
		var when := Time.get_datetime_string_from_unix_time(int(timestamp / 1000.0))
		var description = entry.getDescription()
		last_exit_time = timestamp
		append("Android exit %s UTC | %s (%d) | %s" % [when, EXIT_REASONS.get(reason, "system reason"), reason, str(description) if description != null else ""])
