extends RefCounted

const PATH := "user://hotel-%d.json"
const VERSION := 2
const ROOM_COUNT := 6
const TASK_COUNT := 4
const MAX_FILE_BYTES := 16 * 1024
const MAX_TASKS_PER_STATION := 64
const MAX_INTEGER := 2147483647
const MAX_REVISION := 9007199254740991
const MAX_HAUNT_MARKS := (1 << (ROOM_COUNT * TASK_COUNT)) - 1


static func load_latest() -> Dictionary:
	var complete := {}
	var partial := {}
	var future_version := false
	for slot in 2:
		var path := PATH % slot
		if not FileAccess.file_exists(path):
			continue
		var entry := read_slot(path)
		if entry.is_empty():
			continue
		if entry.version > VERSION:
			future_version = true
			continue
		entry.slot = slot
		if entry.complete:
			if complete.is_empty() or entry.revision > complete.revision:
				complete = entry
		elif partial.is_empty() or entry.revision > partial.revision:
			partial = entry
	var selected := complete if not complete.is_empty() else partial
	if selected.is_empty():
		return {"future": future_version}
	selected.future = future_version
	if not selected.complete:
		push_warning("The save is incomplete. Missing fields were restored to defaults.")
	return selected


static func read_slot(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		push_warning("Save %s cannot be read or exceeds its size limit." % path.get_file())
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_warning("Save %s is invalid JSON near line %d." % [path.get_file(), json.get_error_line()])
		return {}
	var data: Dictionary = json.data
	var version := integer(data.get("version", 0), -1)
	if version > VERSION:
		push_warning("Save %s uses a newer format and was preserved." % path.get_file())
		return {"version": version}
	var revision := integer(data.get("revision"), -1, MAX_REVISION)
	if version < 0 or revision < 1:
		push_warning("Save %s is missing a valid revision or format version." % path.get_file())
		return {}
	var complete := has_management_state(data) if version == VERSION else has_complete_state(data)
	if not complete:
		push_warning("Save %s has missing or invalid fields." % path.get_file())
	return {"version": version, "revision": revision, "complete": complete, "data": data}


static func has_management_state(data: Dictionary) -> bool:
	if integer(data.get("day"), 0) < 1 or not data.get("muted") is bool or not data.get("employee") is bool:
		return false
	if signed_integer(data.get("cash"), -MAX_INTEGER) == -MAX_INTEGER:
		return false
	var rooms: Variant = data.get("rooms")
	var waiting: Variant = data.get("waiting")
	var upgrades: Variant = data.get("upgrades")
	if not rooms is Array or rooms.size() != ROOM_COUNT or not waiting is Array or waiting.size() > 3:
		return false
	if not upgrades is Array or upgrades.size() != 3:
		return false
	for room: Variant in rooms:
		if not room is Dictionary or not room.get("open") is bool or not room.get("guest") is Dictionary:
			return false
		var items: Variant = room.get("items")
		if not items is Array or items.size() != 6:
			return false
		for item: Variant in items:
			if integer(item, -1, 14) < 0:
				return false
	return true


static func has_complete_state(data: Dictionary) -> bool:
	if integer(data.get("shift"), 0) < 1 or not data.get("muted") is bool:
		return false
	for field in ["money", "profit", "haunt_count", "task_total"]:
		if integer(data.get(field), -1) < 0:
			return false
	var rooms: Variant = data.get("rooms")
	if not rooms is Array or rooms.size() != ROOM_COUNT:
		return false
	for room: Variant in rooms:
		if not room is Array or room.size() != TASK_COUNT:
			return false
		for pending: Variant in room:
			if integer(pending, -1, MAX_TASKS_PER_STATION) < 0:
				return false
	var upgrades: Variant = data.get("upgrades")
	return upgrades is Array and upgrades.size() == 3 and upgrades.all(func(value): return value is bool)


static func integer(value: Variant, fallback: int, maximum: int = MAX_INTEGER) -> int:
	if (value is int or value is float) and value >= 0 and value <= maximum and int(value) == value:
		return int(value)
	return fallback


static func signed_integer(value: Variant, fallback: int) -> int:
	if (value is int or value is float) and value >= -MAX_INTEGER and value <= MAX_INTEGER and int(value) == value:
		return int(value)
	return fallback


static func number(value: Variant, fallback: float, maximum: float) -> float:
	if (value is int or value is float) and is_finite(value):
		return clampf(value, 0.0, maximum)
	return fallback


static func write_slot(slot: int, state: Dictionary) -> Error:
	var path := PATH % slot
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(state))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		return result
	return DirAccess.rename_absolute(temporary, path)
