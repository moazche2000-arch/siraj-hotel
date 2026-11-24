extends Control

const Updates = preload("res://startup/content_updater.gd")
const GAME_SCENE := "res://game/hotel.tscn"

var status: Label


func _ready() -> void:
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
		updater.downloading.connect(func(): status.text = "جارٍ تنزيل تحديث اللعبة…")
		await updater.refresh_cache()
		var revision := updater.mount_cached()
		if revision > 0:
			get_tree().set_meta(Updates.BOOT_META, revision)
	var scene := ResourceLoader.load(GAME_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	if scene is PackedScene:
		get_tree().change_scene_to_packed(scene)
		return
	if not is_instance_valid(status):
		build_status()
	status.text = "تعذّر فتح اللعبة. اقفلها وافتحها مرة ثانية لاستعادة آخر نسخة."
