extends Control

const Arabic = preload("res://assets/Arabic.ttf")
const World = preload("res://game/world.gd")
const Workbench = preload("res://game/workbench.gd")
const Rules = preload("res://game/settings.gd")
const Task = Rules.Task
const Card := Color("#382b1f")
const PanelColor := Color("#291f16")
const Background := Color("#17120e")
const Line := Color("#675138")
const Ink := Color("#f1dfbf")
const Sub := Color("#c1ae91")
const Gold := Color("#d8aa69")
const Teal := Color("#bacb93")
const Pink := Color("#e7a981")
const MAP_ORIGIN := Vector2(10, 50)
const DIARY_WIDTH := 228.0
const MAP_HEIGHT := 625.0

var game: Node2D
var hud: Control
var needs_rotation := false
var layout_in_progress := false
var rotate_screen: ColorRect
var rotate_note: Label
var gesture_buttons: Array[Button] = []
var room_buttons: Array[Button] = []
var furniture_icons: Array[AtlasTexture] = []
var guest_icons: Array[AtlasTexture] = []
var day_label: Label
var balance_label: Label
var reputation_label: Label
var sound_button: Button
var arrival_button: Button
var action_button: Button
var action_hint: Label
var notice_label: Label
var clock_fill: ColorRect
var flash: ColorRect
var modal: Control
var modal_card: Panel
var modal_kind := ""
var chore_board: Control
var diagnostics_return := "welcome"


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var text_font := FontVariation.new()
	text_font.base_font = Arabic
	text_font.spacing_top = -8
	text_font.spacing_bottom = -8
	theme = Theme.new()
	theme.default_font = text_font
	theme.default_font_size = 17
	for index in Rules.ITEM_PRICES.size():
		furniture_icons.append(atlas_icon(World.FURNITURE, index))
	for index in 4:
		guest_icons.append(atlas_icon(World.GUESTS, index))
	get_window().size_changed.connect(update_layout)
	update_layout()


func _exit_tree() -> void:
	var window := get_window()
	if is_instance_valid(window) and window.size_changed.is_connected(update_layout):
		window.size_changed.disconnect(update_layout)


func update_layout() -> void:
	if layout_in_progress or not is_instance_valid(game) or not is_instance_valid(game.map_view):
		return
	var screen := get_window().size
	if screen.x <= 0 or screen.y <= 0:
		if is_instance_valid(hud):
			return
		screen = Vector2i(1280, 720)
	layout_in_progress = true
	needs_rotation = screen.x < screen.y
	var width := clampi(roundi(720.0 * screen.x / screen.y), 1080, 1820)
	var layout := Vector2i(width, 720)
	if needs_rotation:
		layout = Vector2i(600, clampi(roundi(600.0 * screen.y / screen.x), 840, 1600))
	game.cancel_input()
	size = Vector2(layout)
	if get_window().content_scale_size != layout:
		get_window().content_scale_size = layout
	if not is_instance_valid(hud) or (not needs_rotation and hud.size != size):
		build_hud(Vector2(1280, 720) if needs_rotation else size)
	hud.visible = not needs_rotation
	game.map_view.visible = not needs_rotation
	if is_instance_valid(modal):
		modal.visible = not needs_rotation
		position_dialog()
	show_rotation_prompt()
	layout_in_progress = false


func build_hud(layout: Vector2) -> void:
	if is_instance_valid(hud):
		hud.hide()
		hud.queue_free()
	hud = Control.new()
	hud.layout_direction = Control.LAYOUT_DIRECTION_LTR
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	move_child(hud, 0)
	hud.position = Vector2.ZERO
	hud.size = layout
	gesture_buttons.clear()
	room_buttons.clear()
	var side := layout.x - DIARY_WIDTH - 10.0
	var map_size := Vector2(side - MAP_ORIGIN.x - 8.0, MAP_HEIGHT)
	game.map_view.position = MAP_ORIGIN
	game.map_view.size = map_size
	game.world.configure_camera(map_size)
	var x := side + 11
	var inside := DIARY_WIDTH - 22
	line(hud, Rect2(10, 43, layout.x - 20, 1), Line)
	label(hud, Rect2(14, 4, 195, 34), "١٩٧٨  ·  الطابق الأرضي", 15, Gold, HORIZONTAL_ALIGNMENT_LEFT)
	label(hud, Rect2(side - 279, 0, 270, 41), "فندق السِّراج", 30, Ink)
	sound_button = hud_button(Rect2(side, 4, 105, 34), "الصوت", game.toggle_sound)
	hud_button(Rect2(side + 113, 4, 115, 34), "إيقاف", show_pause)
	panel(hud, Rect2(side, MAP_ORIGIN.y, DIARY_WIDTH, MAP_HEIGHT), PanelColor)
	label(hud, Rect2(x, 60, inside, 34), "دفتر الأعمال", 25, Gold)
	day_label = label(hud, Rect2(x, 100, inside, 28), "", 17, Ink)
	balance_label = label(hud, Rect2(x, 130, inside, 26), "", 17, Gold)
	reputation_label = label(hud, Rect2(x, 155, inside, 26), "", 15, Teal)
	line(hud, Rect2(x, 187, inside, 4), Line)
	clock_fill = line(hud, Rect2(x + inside, 187, 0, 4), Teal)
	for index in Rules.ROOM_COUNT:
		var room_button := hud_button(Rect2(x, 200 + index * 44, inside, 40), "", show_room.bind(index))
		room_button.add_theme_font_size_override("font_size", 15)
		room_buttons.append(room_button)
	var news := panel(hud, Rect2(x, 470, inside, 104), Card)
	label(news, Rect2(10, 2, inside - 20, 23), "آخر حدث", 13, Gold)
	notice_label = multiline(news, Rect2(10, 27, inside - 20, 68), "", 14, Ink)
	arrival_button = hud_button(Rect2(x, 582, inside, 35), "الاستقبال", show_reception)
	hud_button(Rect2(x, 625, inside, 35), "التطويرات والفريق", show_shop)
	line(hud, Rect2(10, 680, layout.x - 20, 1), Line)
	label(hud, Rect2(13, 683, 237, 32), "اسحب وثبّت إصبعك للمشي", 15, Gold, HORIZONTAL_ALIGNMENT_LEFT)
	action_hint = label(hud, Rect2(250, 683, side - 456, 32), "", 15, Ink)
	action_button = hud_button(Rect2(side - 181, 683, 173, 33), "تفاعل", game.tap_interact, true)
	flash = line(hud, Rect2(0, 0, layout.x, 3), Color.TRANSPARENT)
	refresh()


func hud_button(rect: Rect2, text: String, action: Callable, primary: bool = false) -> Button:
	var result := button(hud, rect, text, primary)
	result.pressed.connect(action)
	gesture_buttons.append(result)
	return result


func show_rotation_prompt() -> void:
	if not needs_rotation:
		if is_instance_valid(rotate_screen):
			rotate_screen.hide()
		return
	if not is_instance_valid(rotate_screen):
		rotate_screen = line(self, Rect2(Vector2.ZERO, size), Background)
		rotate_screen.mouse_filter = Control.MOUSE_FILTER_STOP
		rotate_note = label(rotate_screen, Rect2(0, 0, 560, 100), "لفّ جوالك بالعرض عشان تلعب", 32, Ink, HORIZONTAL_ALIGNMENT_CENTER)
	rotate_screen.size = size
	rotate_note.position = (size - rotate_note.size) / 2.0
	move_child(rotate_screen, -1)
	rotate_screen.show()


func blocks_gesture_at(point: Vector2) -> bool:
	for item in gesture_buttons:
		if is_instance_valid(item) and item.is_visible_in_tree() and item.get_global_rect().has_point(point):
			return true
	return false


func refresh() -> void:
	if not is_instance_valid(day_label) or not is_instance_valid(game.business):
		return
	var model: RefCounted = game.business
	var remaining := maxi(0, Rules.DAY_SECONDS - int(model.second))
	set_text(day_label, "اليوم %d  ·  %d ثانية" % [model.day, remaining])
	set_text(balance_label, "الرصيد  %d ر.س" % model.cash)
	set_text(reputation_label, "السمعة  %d / ١٠٠" % model.reputation)
	var amount := (DIARY_WIDTH - 22) * clampf(float(model.second) / maxi(1, Rules.DAY_SECONDS), 0.0, 1.0)
	var right := hud.size.x - 21
	clock_fill.size.x = amount
	clock_fill.position.x = right - amount
	for index in room_buttons.size():
		var status := "مغلقة · %d ر.س" % Rules.ROOM_PRICES[index]
		if model.is_open(index):
			var room: Dictionary = model.rooms[index]
			var count: int = model.remaining_nights(index)
			status = "مشغولة · %d ل" % count if count > 0 else "فاضية"
			if room.clean < Rules.CLEANING_THRESHOLD:
				status += " · تنظيف"
			elif room.incident >= 0 or room.request >= 0 or room.broken != 0:
				status += " · تحتاج خدمة"
		set_text(room_buttons[index], "%d   %s" % [101 + index, status])
	set_text(arrival_button, "الاستقبال  ·  %d ينتظرون" % model.waiting.size() if not model.waiting.is_empty() else "الاستقبال")
	set_text(sound_button, "صوت مغلق" if game.muted else "الصوت")
	set_text(notice_label, game.notice if not game.notice.is_empty() else "جهّز سريرًا للغرفة ١٠١ واستقبل أول ضيف.")
	refresh_action()
	update_flash()


func refresh_action() -> void:
	if not is_instance_valid(action_button):
		return
	action_button.disabled = game.target == game.NO_TARGET
	if game.target >= 0:
		set_text(action_hint, "خانات الأثاث والمهام في دفتر الغرفة.")
		set_text(action_button, "إدارة الغرفة %d" % (101 + game.target))
	elif game.target == game.RECEPTION:
		set_text(action_hint, "استقبل الضيوف واختر لهم غرفة جاهزة.")
		set_text(action_button, "فتح الاستقبال")
	else:
		set_text(action_hint, "اقترب من غرفة أو من مكتب الاستقبال.")
		set_text(action_button, "تفاعل")


func update_flash() -> void:
	if is_instance_valid(flash):
		flash.color = Color(0.83, 0.45, 0.27, game.haunt_flash * 0.8)


func can_resume() -> bool:
	return modal_kind in ["pause", "room", "furniture", "reception", "shop", "chore"]


func show_welcome() -> void:
	var card := open_dialog("welcome", Vector2(680, 434))
	label(card, Rect2(34, 30, 612, 38), "فندق السِّراج  ·  ١٩٧٨", 23, Gold, HORIZONTAL_ALIGNMENT_CENTER)
	label(card, Rect2(32, 81, 616, 62), "المفتاح صار لك", 44, Ink, HORIZONTAL_ALIGNMENT_CENTER)
	multiline(card, Rect2(58, 154, 564, 103), "تبدأ مالكًا للفندق. جهّز الغرفة ١٠١ بسرير من متجر الأثاث، واستقبل المسافرين وسكّنهم. راقب النظافة وخذ حساب كل يوم من دفتر الأعمال.", 21, Sub)
	var start := button(card, Rect2(177, 279, 326, 58), "تابع إدارة الفندق" if game.has_save else "افتح الفندق", true)
	start.pressed.connect(game.resume)
	start.grab_focus()
	button(card, Rect2(249, 356, 182, 40), "سجل الأخطاء", false).pressed.connect(show_diagnostics.bind("welcome"))


func show_room(index: int) -> void:
	var model: RefCounted = game.business
	if not model.valid_room(index):
		return
	if not model.is_open(index):
		show_locked_room(index)
		return
	var state: Dictionary = model.rooms[index]
	var card := open_dialog("room", Vector2(842, 518))
	label(card, Rect2(30, 18, 782, 52), "الغرفة %d" % (101 + index), 31, Ink)
	var detail := "النظافة %d%%   ·   الراحة %d   ·   الجاذبية %d   ·   الإيجار %d ر.س / ليلة" % [roundi(state.clean), model.comfort(index), model.appeal(index), model.nightly_rate(index)]
	label(card, Rect2(28, 76, 786, 26), detail, 17, Gold)
	var occupancy := "غرفة فاضية" if state.guest.is_empty() else "%s  ·  متبقّي %d ليلة" % [model.guest_name(state.guest), model.remaining_nights(index)]
	if state.request >= 0:
		occupancy += "   |   %s · %d ثانية · مكافأة %d ر.س" % [model.request_name(index), state.deadline, Rules.REQUEST_REWARDS[state.request]]
	label(card, Rect2(28, 104, 786, 27), occupancy, 15, Sub)
	label(card, Rect2(29, 139, 516, 25), "خانات الأثاث", 17, Gold)
	for slot in Rules.SLOT_COUNT:
		var x := 27 + (slot % 3) * 174
		var y := 175 + int(slot / 3.0) * 124
		var item: int = model.slot_item(index, slot)
		var cell := panel(card, Rect2(x, y, 162, 113), Card)
		if item > 0:
			icon(cell, Rect2(46, 1, 70, 62), furniture_icons[item - 1], Pink if model.broken_at(index, slot) else Color.WHITE)
		else:
			label(cell, Rect2(10, 6, 142, 54), "خانة %d" % (slot + 1), 18, Sub, HORIZONTAL_ALIGNMENT_CENTER)
		var name := Rules.item_name(item)
		if model.broken_at(index, slot):
			name += " · مكسور"
		var choose := button(cell, Rect2(6, 65, 150, 41), name if item > 0 else "شراء ووضع قطعة", item < 1)
		choose.pressed.connect(show_furniture.bind(index, slot))
	var at_room := World.room_at(game.player) == index
	label(card, Rect2(563, 139, 251, 25), "مهام الغرفة", 17, Gold)
	var y_job := 174
	if model.can_do_task(index, Task.CLEAN):
		room_job(card, y_job, index, Task.CLEAN, -1, at_room)
		y_job += 41
	for slot in Rules.SLOT_COUNT:
		if model.can_do_task(index, Task.REPAIR, slot):
			room_job(card, y_job, index, Task.REPAIR, slot, at_room)
			y_job += 41
			break
	if state.incident >= 0:
		room_job(card, y_job, index, state.incident, -1, at_room)
		y_job += 41
		if state.incident == Task.CALM:
			room_job(card, y_job, index, Task.BANISH, -1, at_room)
			y_job += 41
	if y_job == 174:
		multiline(card, Rect2(563, y_job + 5, 251, 53), "الغرفة هادئة حاليًا.", 16, Sub)
	elif not at_room:
		multiline(card, Rect2(563, y_job + 5, 251, 50), "ادخل الغرفة لتنفيذ المهام.", 15, Sub)
	button(card, Rect2(28, 454, 167, 44), "رجوع للفندق", false).pressed.connect(game.resume)


func room_job(card: Control, y: float, room: int, kind: int, slot: int, in_room: bool) -> void:
	if kind < 0 or kind >= Rules.TASK_NAMES.size():
		return
	var title: String = Rules.TASK_NAMES[kind]
	if slot >= 0:
		title = "إصلاح · " + Rules.ITEM_NAMES[Rules.item_kind(game.business.slot_item(room, slot))]
	var job := button(card, Rect2(562, y, 250, 36), title, false)
	job.disabled = not in_room
	job.pressed.connect(game.start_task.bind(room, kind, slot))


func show_locked_room(index: int) -> void:
	var card := open_dialog("room", Vector2(530, 316))
	label(card, Rect2(32, 23, 466, 54), "شراء الغرفة %d" % (101 + index), 29, Ink)
	multiline(card, Rect2(32, 95, 466, 74), "الغرفة تُفتح فارغة. أثّثها بسرير لتقدر تسكّن فيها ضيفًا.", 19, Sub)
	var purchase := button(card, Rect2(240, 206, 258, 52), "افتح الغرفة · %d ر.س" % Rules.ROOM_PRICES[index], true)
	purchase.disabled = game.business.cash < Rules.ROOM_PRICES[index]
	purchase.pressed.connect(func():
		if game.buy_room(index):
			show_room(index)
	)
	button(card, Rect2(32, 206, 157, 52), "رجوع", false).pressed.connect(game.resume)


func show_furniture(room: int, slot: int, kind: int = -1) -> void:
	var model: RefCounted = game.business
	if not model.is_open(room) or slot < 0 or slot >= Rules.SLOT_COUNT:
		return
	if kind < 0:
		kind = maxi(0, Rules.item_kind(model.slot_item(room, slot)))
	var card := open_dialog("furniture", Vector2(796, 526))
	label(card, Rect2(30, 19, 736, 51), "متجر الأثاث · الغرفة %d" % (101 + room), 30, Ink)
	label(card, Rect2(30, 72, 736, 30), "الخانة %d  ·  الرصيد %d ر.س" % [slot + 1, model.cash], 16, Gold)
	for index in Rules.ITEM_NAMES.size():
		var option := button(card, Rect2(30 + index * 106, 110, 98, 39), Rules.ITEM_NAMES[index], index == kind)
		option.pressed.connect(show_furniture.bind(room, slot, index))
	var feedback := label(card, Rect2(220, 454, 546, 45), "", 16, Pink)
	for quality in 2:
		var item := kind * 2 + quality + 1
		var x := 32 + quality * 373
		var quality_card := panel(card, Rect2(x, 173, 356, 260), Card)
		icon(quality_card, Rect2(104, 2, 148, 132), furniture_icons[item - 1])
		label(quality_card, Rect2(14, 131, 328, 34), Rules.item_name(item), 20, Ink, HORIZONTAL_ALIGNMENT_CENTER)
		label(quality_card, Rect2(14, 168, 328, 31), "راحة +%d  ·  %d ر.س" % [Rules.ITEM_COMFORT[item - 1], Rules.ITEM_PRICES[item - 1]], 16, Gold, HORIZONTAL_ALIGNMENT_CENTER)
		var buy := button(quality_card, Rect2(56, 205, 244, 42), "شراء ووضع" if model.slot_item(room, slot) == 0 else "استبدال القطعة", true)
		buy.disabled = not model.can_place(room, slot, item)
		buy.pressed.connect(func():
			if game.buy_item(room, slot, item):
				show_room(room)
			else:
				feedback.text = "ابتعد عن مكان القطعة وتأكد من الرصيد وحالة الغرفة."
		)
	button(card, Rect2(31, 456, 166, 43), "رجوع للغرفة", false).pressed.connect(show_room.bind(room))


func show_reception(selected: int = -1) -> void:
	var model: RefCounted = game.business
	var guest: Dictionary = model.get_waiting(selected)
	if guest.is_empty() and not model.waiting.is_empty():
		guest = model.waiting[0]
	var card := open_dialog("reception", Vector2(816, 502))
	label(card, Rect2(29, 20, 758, 53), "مكتب الاستقبال", 31, Ink)
	button(card, Rect2(29, 437, 166, 46), "رجوع للفندق", false).pressed.connect(game.resume)
	if guest.is_empty():
		multiline(card, Rect2(135, 159, 546, 100), "المكتب فاضي الآن. الضيوف يوصلون مع مرور الوقت، وتزيد الطلبات كلما تحسّنت سمعة الفندق.", 22, Sub)
		return
	var selected_id: int = guest.id
	for index in model.waiting.size():
		var item: Dictionary = model.waiting[index]
		var choose := button(card, Rect2(30, 97 + index * 72, 217, 61), model.guest_name(item), item.id == selected_id)
		choose.pressed.connect(show_reception.bind(item.id))
	var reject := button(card, Rect2(30, 326, 217, 45), "اعتذر للضيف", false)
	reject.pressed.connect(func():
		if game.turn_away(selected_id):
			show_reception()
	)
	icon(card, Rect2(268, 86, 99, 102), guest_icons[guest.look])
	label(card, Rect2(369, 92, 415, 45), model.guest_name(guest), 24, Gold)
	label(card, Rect2(372, 135, 412, 28), "%s  ·  %s" % [Rules.GUEST_TIERS[guest.quality], Rules.PREFERENCES[guest.preference]], 15, Sub)
	label(card, Rect2(372, 160, 412, 26), "%d ليالٍ  ·  حتى %d ر.س/ليلة" % [guest.nights, guest.budget], 15, Sub)
	label(card, Rect2(277, 190, 506, 28), "اختر غرفة فاضية فيها سرير صالح", 16, Ink)
	for index in Rules.ROOM_COUNT:
		var y := 230 + int(index / 2.0) * 55
		var x := 277 + (index % 2) * 255
		var available: bool = model.can_book(index)
		var text := "%d  ·  %d ر.س/ليلة" % [101 + index, mini(model.nightly_rate(index), guest.budget)] if available else "%d  ·  غير متاحة" % (101 + index)
		var assign := button(card, Rect2(x, y, 242, 47), text, available)
		assign.disabled = not available
		assign.pressed.connect(func():
			if game.check_in(selected_id, index):
				show_reception()
		)


func show_shop() -> void:
	var model: RefCounted = game.business
	var card := open_dialog("shop", Vector2(744, 524))
	label(card, Rect2(28, 17, 688, 55), "التطويرات والفريق", 31, Ink)
	label(card, Rect2(28, 75, 688, 31), "الرصيد %d ر.س" % model.cash, 19, Gold)
	var descriptions := ["تقلّل عدد البقع وتسرّع التنظيف اليدوي.", "تحمي الأثاث من كسر الجن.", "ترفع سعر الإيجار ١٢ ر.س لكل ليلة."]
	for index in Rules.UPGRADE_NAMES.size():
		var box := panel(card, Rect2(26, 111 + index * 74, 692, 64), Card)
		label(box, Rect2(170, 3, 508, 29), Rules.UPGRADE_NAMES[index], 18, Ink)
		label(box, Rect2(170, 34, 508, 24), descriptions[index], 15, Sub)
		var price: int = Rules.UPGRADE_PRICES[index]
		var item := button(box, Rect2(12, 12, 145, 40), "تم الشراء" if model.upgrades[index] else "%d ر.س" % price, false)
		item.disabled = model.upgrades[index] or model.cash < price
		item.pressed.connect(func():
			if game.buy_upgrade(index):
				show_shop()
		)
	var hire := button(card, Rect2(27, 352, 184, 42), "إنهاء التوظيف" if model.employee else "وظّف عامل تنظيف", not model.employee)
	hire.disabled = not model.employee and model.wage_day != model.day and model.cash < Rules.CLEANER_WAGE
	hire.pressed.connect(func():
		if game.change_cleaner(not model.employee):
			show_shop()
	)
	label(card, Rect2(228, 344, 485, 32), "عامل تنظيف  ·  %d ر.س يوميًا" % Rules.CLEANER_WAGE, 19, Gold)
	label(card, Rect2(228, 372, 485, 33), "ينظّف أكثر الغرف اتساخًا على دفعات." if model.employee else "يساعدك على رفع النظافة تلقائيًا خلال اليوم.", 15, Sub)
	button(card, Rect2(27, 443, 166, 45), "رجوع للفندق", false).pressed.connect(game.resume)


func show_chore(room: int, kind: int, slot: int) -> void:
	if not game.business.can_do_task(room, kind, slot):
		return
	var card := open_dialog("chore", Vector2(710, 482))
	label(card, Rect2(35, 17, 638, 53), "%s  ·  الغرفة %d" % [Rules.TASK_NAMES[kind], 101 + room], 27, Ink)
	var instructions := [
		"اكنس الغبار، ثم امسح البقع بالسحب.",
		"ثبّت القطعة عند وصول المؤشر للجزء النحاسي.",
		"اقفل الصمام تدريجيًا لما يدخل المؤشر المنطقة النحاسية.",
		"أطفئ الكهرباء، وبدّل اللمبة، ثم شغّلها.",
		"اسمع كلام الضيف، ثم طمّنه واعرض مساعدتك.",
		"ثبّت الفانوس في توقيت الوميض حتى يبتعد الجن.",
		"فتّش الصناديق واتبع التلميح حتى تلقى المفتاح.",
	]
	label(card, Rect2(35, 74, 638, 29), instructions[kind], 16, Sub)
	var board := Workbench.new()
	var state: Dictionary = game.business.rooms[room]
	var seed_value := int(game.business.day) * 5381 + int(game.business.second) * 521 + room * 109 + kind * 47 + int(game.business.event_revision)
	board.setup(kind, game.business.day, state.clean, game.business.upgrades[0], seed_value)
	card.add_child(board)
	board.position = Vector2(35, 112)
	board.size = Workbench.FRAME
	chore_board = board
	var meter := line(card, Rect2(35, 321, 638, 4), Line)
	var fill := line(meter, Rect2(638, 0, 0, 4), Teal)
	var status := label(card, Rect2(35, 335, 638, 28), "", 16, Gold)
	board.changed.connect(func(progress: float, text: String):
		if chore_board == board and is_instance_valid(status) and is_instance_valid(fill):
			status.text = text
			fill.size.x = 638 * progress
			fill.position.x = 638 - fill.size.x
	)
	var on_completed := func():
		if modal_kind == "chore" and is_instance_valid(board) and chore_board == board:
			game.complete_task(room, kind, slot)
	board.completed.connect(on_completed, CONNECT_ONE_SHOT)
	button(card, Rect2(35, 405, 133, 48), "رجوع للغرفة", false).pressed.connect(show_room.bind(room))
	if board.mode == Workbench.Mode.TIMED:
		button(card, Rect2(439, 405, 234, 48), "ثبّت", true).pressed.connect(board.confirm_timing)
	elif board.mode == Workbench.Mode.SEQUENCE:
		var labels: PackedStringArray = board.sequence_labels()
		for index in labels.size():
			var action := (index + seed_value % labels.size()) % labels.size()
			button(card, Rect2(179 + index * 166, 405, 158, 48), labels[action], true).pressed.connect(board.choose.bind(action))


func show_summary() -> void:
	var report: Dictionary = game.business.pending_report
	if report.is_empty():
		game.resume()
		return
	var card := open_dialog("summary", Vector2(710, 522))
	label(card, Rect2(31, 20, 648, 69), "حساب اليوم %d" % report.day, 40, Ink, HORIZONTAL_ALIGNMENT_CENTER)
	for index in 3:
		var box := panel(card, Rect2(31 + index * 219, 100, 210, 89), Card)
		var titles := ["المصاريف", "الدخل", "صافي الربح"]
		var values := [report.expenses, report.income, report.net]
		label(box, Rect2(8, 7, 194, 27), titles[index], 16, Sub, HORIZONTAL_ALIGNMENT_CENTER)
		label(box, Rect2(8, 40, 194, 32), "%d ر.س" % values[index], 21, Gold if index < 2 else Teal, HORIZONTAL_ALIGNMENT_CENTER)
	label(card, Rect2(31, 207, 648, 32), "تقييمات المغادرين · %d" % report.visitors, 20, Gold)
	var reviews := TextEdit.new()
	reviews.editable = false
	reviews.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	reviews.text = report.reviews if not report.reviews.is_empty() else "الضيوف يدفعون عند انتهاء إقامتهم."
	card.add_child(reviews)
	reviews.position = Vector2(31, 246)
	reviews.size = Vector2(648, 163)
	button(card, Rect2(239, 430, 232, 55), "ابدأ اليوم التالي", true).pressed.connect(game.acknowledge_day)


func show_pause(from_diagnostics: bool = false) -> void:
	if game.paused and not from_diagnostics:
		return
	var card := open_dialog("pause", Vector2(493, 259))
	label(card, Rect2(30, 33, 433, 60), "الفندق متوقف مؤقتًا", 30, Ink, HORIZONTAL_ALIGNMENT_CENTER)
	button(card, Rect2(240, 145, 219, 54), "تابع إدارة الفندق", true).pressed.connect(game.resume)
	button(card, Rect2(34, 145, 187, 54), "سجل الأخطاء", false).pressed.connect(show_diagnostics.bind("pause"))


func show_diagnostics(from: String) -> void:
	diagnostics_return = from
	var card := open_dialog("diagnostics", Vector2(780, 466))
	label(card, Rect2(36, 22, 708, 52), "سجل الأخطاء", 31, Ink)
	var state := label(card, Rect2(36, 76, 708, 34), "آخر ٢٠ حدثًا محفوظة على الجهاز.", 17, Sub)
	var contents: String = game.diagnostics.text() if is_instance_valid(game.diagnostics) else ""
	var viewer := TextEdit.new()
	viewer.editable = false
	viewer.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	viewer.text = contents if not contents.is_empty() else "ما فيه أخطاء مسجّلة."
	card.add_child(viewer)
	viewer.position = Vector2(36, 114)
	viewer.size = Vector2(708, 263)
	var copy := button(card, Rect2(553, 397, 191, 49), "نسخ السجل", true)
	copy.disabled = contents.is_empty() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(contents)
		state.text = "تم نسخ السجل."
	)
	button(card, Rect2(36, 397, 152, 49), "رجوع", false).pressed.connect(close_diagnostics)


func close_diagnostics() -> void:
	if modal_kind == "diagnostics":
		if diagnostics_return == "pause":
			show_pause(true)
		else:
			show_welcome()


func open_dialog(kind: String, dimensions: Vector2) -> Panel:
	close_dialog()
	game.paused = true
	modal_kind = kind
	modal = ColorRect.new()
	modal.color = Color(0.057, 0.041, 0.022, 0.84)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal)
	modal.visible = not needs_rotation
	modal_card = panel(modal, Rect2(Vector2.ZERO, dimensions), Color("#2e2218"))
	line(modal_card, Rect2(43, 0, dimensions.x - 86, 2), Gold)
	position_dialog()
	return modal_card


func position_dialog() -> void:
	if is_instance_valid(modal) and is_instance_valid(modal_card):
		modal.size = size
		modal_card.position = (size - modal_card.size) / 2.0


func close_dialog() -> void:
	game.cancel_input()
	if is_instance_valid(modal):
		modal.hide()
		modal.queue_free()
	modal = null
	modal_card = null
	chore_board = null
	modal_kind = ""


func set_text(control: Control, value: String) -> void:
	if is_instance_valid(control) and control.text != value:
		control.text = value


func label(parent: Control, rect: Rect2, value: String, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var item := Label.new()
	item.text_direction = Control.TEXT_DIRECTION_RTL
	item.horizontal_alignment = alignment
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item.text = value
	place(parent, item, rect)
	return item


func multiline(parent: Control, rect: Rect2, value: String, font_size: int, color: Color) -> Label:
	var item := label(parent, rect, value, font_size, color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item


func button(parent: Control, rect: Rect2, value: String, primary: bool) -> Button:
	var item := Button.new()
	item.text_direction = Control.TEXT_DIRECTION_RTL
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item.text = value
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var fill := Gold if primary else Card
	var ink := Background if primary else Ink
	item.add_theme_stylebox_override("normal", box_style(fill, Line))
	item.add_theme_stylebox_override("hover", box_style(fill.lightened(0.12), Gold))
	item.add_theme_stylebox_override("pressed", box_style(fill.darkened(0.15), Gold))
	item.add_theme_stylebox_override("disabled", box_style(PanelColor, Line.darkened(0.18)))
	item.add_theme_stylebox_override("focus", box_style(Color.TRANSPARENT, Teal))
	item.add_theme_color_override("font_color", ink)
	item.add_theme_color_override("font_hover_color", ink)
	item.add_theme_color_override("font_pressed_color", ink)
	item.add_theme_color_override("font_focus_color", ink)
	item.add_theme_color_override("font_disabled_color", Sub.darkened(0.3))
	item.add_theme_font_size_override("font_size", 16)
	place(parent, item, rect)
	return item


func panel(parent: Control, rect: Rect2, fill: Color) -> Panel:
	var item := Panel.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_stylebox_override("panel", box_style(fill, Line))
	place(parent, item, rect)
	return item


func line(parent: Control, rect: Rect2, color: Color) -> ColorRect:
	var item := ColorRect.new()
	item.color = color
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(parent, item, rect)
	return item


func icon(parent: Control, rect: Rect2, texture: Texture2D, tint: Color = Color.WHITE) -> void:
	var item := TextureRect.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.texture = texture
	item.modulate = tint
	place(parent, item, rect)


func atlas_icon(texture: Texture2D, index: int) -> AtlasTexture:
	var item := AtlasTexture.new()
	item.atlas = texture
	item.region = Rect2(Vector2(index % 4, index >> 2) * World.FRAME, World.FRAME)
	item.filter_clip = true
	return item


func place(parent: Control, item: Control, rect: Rect2) -> void:
	parent.add_child(item)
	item.position = rect.position
	item.size = rect.size


func box_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style
