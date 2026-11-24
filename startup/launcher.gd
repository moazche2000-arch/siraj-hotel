extends Control

const Updates = preload("res://startup/content_updater.gd")
const Diagnostics = preload("res://game/diagnostics.gd")
const GAME_SCENE := "res://game/hotel.tscn"

var status: Label
var diagnostics: Logger


func _ready() -> void:
	diagnostics = Diagnostics.install(get_tree())
	if OS.has_feature("android"):
		build_status()
	launch.call_deferred()


func build_status() -> void:
	status = Label.new()
	status.text = "جارٍ فتح فندق السِّراج…"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.text_direction = Control.TEXT_DIRECTION_RTL
	status.add_theme_font_override("font", preload("res://assets/Arabic.ttf"))
	status.add_theme_font_size_override("font_size", 31)
	status.add_theme_color_override("font_color", Color("#e5b874"))
	add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func launch() -> void:
	if OS.has_feature("android"):
		var updater := Updates.new()
		add_child(updater)
		updater.downloading.connect(func():
			if is_instance_valid(status):
				status.text = "جارٍ تنزيل تحديث اللعبة…"
		)
		await updater.refresh_cache()
		if not is_inside_tree():
			return
		var revision := updater.mount_cached()
		if revision > 0:
			get_tree().set_meta(Updates.BOOT_META, revision)
	var scene := ResourceLoader.load(GAME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if scene != null and scene.can_instantiate():
		var result := get_tree().change_scene_to_packed(scene)
		if result == OK:
			return
		push_error("Changing to the hotel scene failed: %s" % error_string(result))
	else:
		push_error("The hotel scene is missing or cannot be instantiated.")
	if not is_instance_valid(status):
		build_status()
	status.text = "تعذّر فتح اللعبة. اقفلها وافتحها مرة ثانية لاستعادة آخر نسخة."
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		var copy := Button.new()
		copy.text = "نسخ سجل الأخطاء"
		copy.add_theme_font_override("font", preload("res://assets/Arabic.ttf"))
		add_child(copy)
		copy.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		copy.offset_left = -115
		copy.offset_right = 115
		copy.offset_top = 35
		copy.offset_bottom = 84
		copy.pressed.connect(func():
			DisplayServer.clipboard_set(diagnostics.text())
			copy.text = "تم نسخ السجل"
		)
