extends Node

signal downloading

const Trust = preload("res://startup/trusted_key.gd")
const BASE_REVISION := 7
const PROTOCOL := 1
const DIRECTORY := "user://siraj-content"
const BOOT_META := "siraj_content_revision"
const RELEASES := "https://github.com/moazche2000-arch/siraj-hotel/releases/"
const MANIFEST_NAME := "siraj-update.json"
const PACK_NAME := "siraj-game.pck"
const MAX_MANIFEST_BYTES := 8192
const MAX_PACK_BYTES := 48 * 1024 * 1024

var directory := DIRECTORY


func refresh_cache() -> void:
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return
	recover_interrupted_boot()
	var cached := best_cached()
	var last_rejected := read_revision(directory.path_join("rejected"))
	var current := maxi(maxi(BASE_REVISION, cached.get("revision", 0)), last_rejected)
	var response := await fetch(RELEASES + "latest/download/" + MANIFEST_NAME, 2.5, MAX_MANIFEST_BYTES)
	var release := verify_manifest(response)
	if release.is_empty() or release.revision <= current:
		return
	downloading.emit()
	var temporary := directory.path_join("download.pck")
	DirAccess.remove_absolute(temporary)
	var result := await fetch(RELEASES + "download/" + release.tag + "/" + PACK_NAME, 9.0, release.pack_bytes, temporary)
	if not result.is_empty() and pack_matches(temporary, release):
		install_pack(temporary, response, 1 - int(cached.get("slot", 1)))
	DirAccess.remove_absolute(temporary)


func fetch(url: String, seconds: float, limit: int, destination: String = "") -> PackedByteArray:
	var request := HTTPRequest.new()
	request.timeout = seconds
	request.body_size_limit = limit
	request.max_redirects = 4
	request.download_file = destination
	add_child(request)
	var started := request.request(url, PackedStringArray(["Cache-Control: no-cache"]))
	if started != OK:
		request.queue_free()
		return PackedByteArray()
	var result: Array = await request.request_completed
	request.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		return PackedByteArray()
	return result[3] if destination.is_empty() else PackedByteArray([1])


func verify_manifest(raw: PackedByteArray) -> Dictionary:
	if raw.is_empty() or raw.size() > MAX_MANIFEST_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(raw.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}
	var envelope: Dictionary = json.data
	var payload: Variant = envelope.get("payload")
	var signature: Variant = envelope.get("signature")
	if not payload is String or not signature is String:
		return {}
	var bytes := Marshalls.base64_to_raw(payload)
	var signed := Marshalls.base64_to_raw(signature)
	var key := CryptoKey.new()
	if key.load_from_string(Trust.PUBLIC_KEY, true) != OK:
		return {}
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	if not Crypto.new().verify(HashingContext.HASH_SHA256, hashing.finish(), signed, key):
		return {}
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {}
	var fields: Dictionary = json.data
	if fields.get("protocol") != PROTOCOL:
		return {}
	var revision: Variant = fields.get("revision")
	var pack_bytes: Variant = fields.get("pack_bytes")
	var tag: Variant = fields.get("tag")
	var checksum: Variant = fields.get("sha256")
	if not whole_number(revision, 1, 2147483647) or not whole_number(pack_bytes, 1, MAX_PACK_BYTES):
		return {}
	if not tag is String or not valid_tag(tag):
		return {}
	if not checksum is String or checksum.length() != 64 or not checksum.is_valid_hex_number(false):
		return {}
	return {"revision": int(revision), "pack_bytes": int(pack_bytes), "tag": tag, "sha256": checksum}


func whole_number(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is float or value is int) and value >= minimum and value <= maximum and int(value) == value


func valid_tag(tag: String) -> bool:
	var semver := RegEx.new()
	semver.compile("^v[0-9]{1,5}\\.[0-9]{1,5}\\.[0-9]{1,5}$")
	return tag.length() <= 18 and semver.search(tag) != null


func pack_matches(path: String, release: Dictionary) -> bool:
	var pack := FileAccess.open(path, FileAccess.READ)
	if pack == null or pack.get_length() != release.pack_bytes:
		return false
	pack.close()
	return FileAccess.get_sha256(path).nocasecmp_to(release.sha256) == 0


func install_pack(temporary: String, raw: PackedByteArray, slot: int) -> bool:
	var metadata := manifest_path(slot)
	var pending := metadata + ".tmp"
	var file := FileAccess.open(pending, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(raw)
	file.flush()
	var saved := file.get_error() == OK
	file.close()
	if not saved:
		return false
	DirAccess.remove_absolute(metadata)
	DirAccess.remove_absolute(pack_path(slot))
	if DirAccess.rename_absolute(temporary, pack_path(slot)) != OK:
		return false
	return DirAccess.rename_absolute(pending, metadata) == OK


func best_cached() -> Dictionary:
	var best := {}
	var rejected := read_revision(directory.path_join("rejected"))
	var pending := read_revision(directory.path_join("booting"))
	var healthy := read_revision(directory.path_join("healthy"))
	for slot in 2:
		var file := FileAccess.open(manifest_path(slot), FileAccess.READ)
		if file == null or file.get_length() > MAX_MANIFEST_BYTES:
			continue
		var entry := verify_manifest(file.get_buffer(file.get_length()))
		if entry.is_empty() or entry.revision <= BASE_REVISION or entry.revision == rejected:
			continue
		if entry.revision == pending and entry.revision != healthy:
			continue
		if entry.revision <= int(best.get("revision", 0)) or not pack_matches(pack_path(slot), entry):
			continue
		entry.slot = slot
		best = entry
	return best


func recover_interrupted_boot() -> void:
	var pending := directory.path_join("booting")
	var revision := read_revision(pending)
	if revision <= 0:
		return
	var confirmed := read_revision(directory.path_join("healthy"))
	if revision == confirmed or write_revision(directory.path_join("rejected"), revision):
		DirAccess.remove_absolute(pending)


func mount_cached() -> int:
	var release := best_cached()
	if release.is_empty():
		return 0
	var revision: int = release.revision
	var pending := directory.path_join("booting")
	if read_revision(directory.path_join("healthy")) != revision and not write_revision(pending, revision):
		return 0
	if ProjectSettings.load_resource_pack(pack_path(release.slot), true):
		return revision
	write_revision(directory.path_join("rejected"), revision)
	DirAccess.remove_absolute(pending)
	return 0


static func confirm_startup(revision: int, path: String = DIRECTORY) -> void:
	if write_revision(path.path_join("healthy"), revision):
		DirAccess.remove_absolute(path.path_join("booting"))


static func read_revision(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 12:
		return 0
	var value := file.get_as_text()
	return int(value) if value.is_valid_int() else 0


static func write_revision(path: String, revision: int) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(str(revision))
	file.flush()
	return file.get_error() == OK


func manifest_path(slot: int) -> String:
	return directory.path_join("manifest-%d.json" % slot)


func pack_path(slot: int) -> String:
	return directory.path_join("content-%d.pck" % slot)
