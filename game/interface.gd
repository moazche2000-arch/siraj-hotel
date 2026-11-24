extends Control

const Arabic = preload("res://assets/Arabic.ttf")
const World = preload("res://game/world.gd")
const BG := Color("#0d151e")
const PANEL := Color("#14212c")
const CARD := Color("#1a2a36")
const LINE := Color("#334755")
const INK := Color("#f3ead9")
const SUB := Color("#9bafb6")
const GOLD := Color("#edc583")
const TEAL := Color("#91dac7")
const PINK := Color("#eea6c5")
const RTL := Control.TEXT_DIRECTION_RTL

var game: Node2D
var ui_theme: Theme
var hud: Control
var portrait := false
var gesture_buttons: Array[Button] = []
var shift_label: Label
var shift_badge: Label
var balance_label: Label
var profit_label: Label
var sound_button: Button
var shop_button: Button
var task_line: Label
var task_hint: Label
var progress: ColorRect
var progress_track: Rect2
var event_text: Label
var event_panel: Panel
var job_button: Button
var room_boxes: Array[Panel] = []
var room_statuses: Array[Label] = []
var room_dots: Array[Array] = []
var modal: Control
var modal_kind := ""
var aura: ColorRect


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_LTR
	position = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var regular := FontVariation.new()
	regular.base_font = Arabic
	regular.spacing_top = -8
	regular.spacing_bottom = -8
	var bold := FontVariation.new()
	bold.base_font = Arabic
	bold.variation_opentype = {"weight": 750}
	bold.spacing_top = -8
	bold.spacing_bottom = -8
	ui_theme = Theme.new()
	ui_theme.default_font = regular
	ui_theme.default_font_size = 16
	ui_theme.set_font("font", "Button", bold)
	theme = ui_theme
	get_window().size_changed.connect(update_layout)
	update_layout()


func update_layout() -> void:
	var screen := get_window().size
	if screen.x <= 0 or screen.y <= 0:
		return
	portrait = screen.x < screen.y
	var layout := Vector2i(1280, 800)
	if portrait:
		layout = Vector2i(940, clampi(roundi(940.0 * screen.y / screen.x), 1470, 2130))
	if size == Vector2(layout):
		return
	game.clear_gesture()
	size = Vector2(layout)
	if get_window().content_scale_size != layout:
		get_window().content_scale_size = layout
	game.world.position = Vector2(19, 173) if portrait else Vector2(26, 142)
	if is_instance_valid(hud):
		remove_child(hud)
		hud.queue_free()
	hud = Control.new()
	hud.layout_direction = Control.LAYOUT_DIRECTION_LTR
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	move_child(hud, 0)
	hud.size = size
	hud.position = Vector2.ZERO
	gesture_buttons.clear()
	room_boxes.clear()
	room_statuses.clear()
	room_dots.clear()
	if portrait:
		build_portrait()
	else:
		build_landscape()
	aura = line(Rect2(0, 0, size.x, 3), Color.TRANSPARENT)
	refresh()
	position_dialog()


func build_landscape() -> void:
	line(Rect2(26, 25, 1228, 1), LINE)
	line(Rect2(26, 113, 1228, 1), LINE)
	line(Rect2(26, 25, 122, 2), GOLD)
	label(hud, Rect2(916, 33, 338, 52), "فندق السِّراج", 36, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	label(hud, Rect2(1137, 89, 117, 17), "الوردية الليلية", 13, GOLD)
	label(hud, Rect2(25, 34, 168, 22), "الوردية الحالية", 14, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	shift_label = label(hud, Rect2(26, 54, 278, 38), "", 22, INK, HORIZONTAL_ALIGNMENT_LEFT, true)
	shift_badge = label(hud, Rect2(26, 90, 236, 18), "", 12, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	line(Rect2(301, 44, 1, 56), LINE)
	label(hud, Rect2(330, 34, 140, 22), "رصيدك", 14, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	balance_label = label(hud, Rect2(330, 55, 200, 38), "", 24, GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	profit_label = label(hud, Rect2(548, 57, 210, 27), "", 15, TEAL, HORIZONTAL_ALIGNMENT_LEFT)
	build_menu(Rect2(754, 48, 104, 44), Rect2(868, 48, 72, 44))
	label(hud, Rect2(687, 116, 241, 24), "مخطط الفندق", 14, GOLD)
	label(hud, Rect2(26, 116, 210, 24), "الطابق الأرضي", 13, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	panel(hud, Rect2(949, 142, 305, 566), PANEL)
	label(hud, Rect2(970, 152, 263, 36), "دفتر الوردية", 24, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	task_line = label(hud, Rect2(970, 195, 263, 26), "", 15, SUB)
	build_progress(Rect2(972, 231, 258, 5))
	build_rooms(Vector2(970, 255), Vector2(126, 50), Vector2(9, 8), 2)
	label(hud, Rect2(970, 440, 262, 24), "مهام الغرف", 15, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
	for index in 4:
		var x := 970 + index % 2 * 134
		var y := 471 + floori(index / 2.0) * 27
		var key := label(hud, Rect2(x + 107, y + 3, 18, 18), ["B", "M", "L", "R"][index], 11, World.TASK_COLORS[index], HORIZONTAL_ALIGNMENT_CENTER, true)
		key.text_direction = Control.TEXT_DIRECTION_LTR
		label(hud, Rect2(x, y, 102, 23), game.TASK_NAMES[index], 12, SUB)
	build_event(Rect2(970, 537, 263, 83), 13)
	build_shop(Rect2(970, 639, 263, 48))
	line(Rect2(26, 725, 1228, 1), LINE)
	label(hud, Rect2(26, 739, 350, 44), "اسحب على الشاشة لتحرّك الشخصية", 17, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	task_hint = label(hud, Rect2(399, 739, 586, 44), "", 17, INK)
	build_action(Rect2(1005, 739, 249, 48), 16)


func build_portrait() -> void:
	line(Rect2(19, 23, 902, 2), LINE)
	line(Rect2(786, 23, 135, 3), GOLD)
	label(hud, Rect2(447, 30, 474, 68), "فندق السِّراج", 51, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	shift_label = label(hud, Rect2(445, 100, 476, 44), "", 32, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	shift_badge = label(hud, Rect2(445, 143, 476, 26), "", 22, GOLD)
	balance_label = label(hud, Rect2(19, 113, 170, 48), "", 32, GOLD, HORIZONTAL_ALIGNMENT_LEFT, true)
	profit_label = label(hud, Rect2(205, 119, 222, 37), "", 21, TEAL, HORIZONTAL_ALIGNMENT_LEFT)
	build_menu(Rect2(19, 43, 164, 65), Rect2(198, 43, 137, 65))
	var extra := size.y - 1470.0
	var action_y := 755.0 + minf(extra * 0.32, 185.0)
	label(hud, Rect2(19, 744, 902, 51), "اسحب على الشاشة لتحرّك الشخصية", 28, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)
	task_hint = label(hud, Rect2(19, action_y + 43, 902, 47), "", 26, INK, HORIZONTAL_ALIGNMENT_CENTER)
	build_action(Rect2(19, action_y + 99, 902, 92), 33)
	var board_y := action_y + 213.0
	var event_height := minf(150.0, 91.0 + extra * 0.2)
	panel(hud, Rect2(19, board_y, 902, 361 + event_height), PANEL)
	label(hud, Rect2(41, board_y + 12, 858, 48), "دفتر الوردية", 34, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	task_line = label(hud, Rect2(41, board_y + 13, 396, 47), "", 25, SUB, HORIZONTAL_ALIGNMENT_LEFT)
	build_progress(Rect2(41, board_y + 70, 858, 6))
	build_rooms(Vector2(41, board_y + 93), Vector2(274, 70), Vector2(18, 10), 3)
	build_event(Rect2(41, board_y + 260, 858, event_height), 25)
	build_shop(Rect2(41, board_y + 272 + event_height, 858, 72))


func build_menu(sound_rect: Rect2, pause_rect: Rect2) -> void:
	sound_button = button(hud, sound_rect, "الصوت", false)
	sound_button.pressed.connect(game.toggle_sound)
	var pause_button := button(hud, pause_rect, "إيقاف", false)
	pause_button.pressed.connect(show_pause)
	for item in [sound_button, pause_button]:
		item.add_theme_font_size_override("font_size", 26 if portrait else 14)
		gesture_buttons.append(item)


func build_progress(rect: Rect2) -> void:
	progress_track = rect
	line(rect, LINE)
	progress = line(rect, TEAL)


func build_rooms(origin: Vector2, card: Vector2, gap: Vector2, columns: int) -> void:
	for index in 6:
		var column := columns - 1 - index % columns
		var row := floori(float(index) / columns)
		var box := panel(hud, Rect2(origin + Vector2(column, row) * (card + gap), card), CARD)
		room_boxes.append(box)
		var room_code := label(box, Rect2(63, 3, card.x - 75, card.y * 0.45), str(World.ROOM_NUMBERS[index]), 25 if portrait else 14, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
		room_code.text_direction = Control.TEXT_DIRECTION_LTR
		room_statuses.append(label(box, Rect2(46, card.y * 0.48, card.x - 58, card.y * 0.39), "", 21 if portrait else 11, SUB))
		var dots: Array[Label] = []
		for task in 4:
			var width := 26.0 if portrait else 11.0
			var dot := label(box, Rect2(8 + task * width, card.y * 0.27, width, card.y * 0.4), ["B", "M", "L", "R"][task], 16 if portrait else 8, World.TASK_COLORS[task], HORIZONTAL_ALIGNMENT_CENTER)
			dots.append(dot)
		room_dots.append(dots)


func build_event(rect: Rect2, font_size: int) -> void:
	event_panel = panel(hud, rect, Color("#172631"))
	var heading_height := 37 if portrait else 25
	label(event_panel, Rect2(12, 2, rect.size.x - 24, heading_height), "سجل الوردية", font_size - 1, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
	event_text = label(event_panel, Rect2(12, heading_height + 2, rect.size.x - 24, rect.size.y - heading_height - 8), "", font_size, INK)
	event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func build_shop(rect: Rect2) -> void:
	shop_button = button(hud, rect, "تطويرات الفندق", false)
	shop_button.add_theme_font_size_override("font_size", 26 if portrait else 14)
	shop_button.pressed.connect(show_shop)
	gesture_buttons.append(shop_button)


func build_action(rect: Rect2, font_size: int) -> void:
	job_button = button(hud, rect, "تفاعل", true)
	job_button.add_theme_font_size_override("font_size", font_size)
	job_button.pressed.connect(game.tap_interact)
	gesture_buttons.append(job_button)


func blocks_gesture_at(point: Vector2) -> bool:
	for item in gesture_buttons:
		if item.is_visible_in_tree() and not item.disabled and item.get_global_rect().has_point(point):
			return true
	return false


func refresh() -> void:
	shift_label.text = "%02d  /  %s" % [game.shift, game.shift_name()]
	shift_badge.text = "مالك الفندق" if game.is_owner() else "موظف خدمة الغرف"
	balance_label.text = "%d ر.س" % game.money
	profit_label.text = "صافي الأرباح  %d ر.س" % game.total_profit if game.is_owner() else ""
	sound_button.text = "صوت مغلق" if game.muted else "الصوت"
	shop_button.disabled = not game.is_owner()
	shop_button.text = "تطويرات الفندق" if game.is_owner() else "التطويرات تفتح بعد استلام الفندق"
	var clean: int = game.clean_room_count()
	task_line.text = "%d من %d غرف جاهزة" % [clean, game.active_rooms]
	var remaining: int = game.remaining_tasks()
	var completion := 1.0 - float(remaining) / maxf(game.task_total, 1)
	progress.size.x = maxf(1, completion * progress_track.size.x)
	progress.position.x = progress_track.end.x - progress.size.x
	for index in 6:
		var active: bool = index < game.active_rooms
		var ready: bool = active and game.room_done(index)
		room_boxes[index].add_theme_stylebox_override("panel", box_style(Color("#203b3b") if ready else CARD if active else Color("#15212a"), Color("#46685e") if ready else LINE))
		room_statuses[index].text = "جاهزة" if ready else "قيد العمل" if active else "مغلقة"
		room_statuses[index].modulate = TEAL if ready else Color.WHITE
		for work in 4:
			room_dots[index][work].visible = active and game.rooms[index][work] > 0
	refresh_live()


func refresh_live() -> void:
	var target: Vector2i = game.target
	var message := "اقترب من علامة المهمة، ثم المس الشاشة."
	var button_text := "تفاعل"
	if target == Vector2i(-2, -2):
		message = "دفتر الوردية جاهز للتسليم."
		button_text = "إنهاء الوردية"
	elif target.x >= 0:
		message = "%s  /  غرفة %d" % [game.TASK_NAMES[target.y], World.ROOM_NUMBERS[target.x]]
		button_text = game.TASK_NAMES[target.y]
	elif game.all_done():
		message = "كل الغرف جاهزة. ارجع إلى مكتب الاستقبال في وسط الممر."
	set_text(task_hint, message)
	set_text(job_button, button_text)
	job_button.disabled = target.x == -1
	var news := "الممر هادئ الآن." if game.shift > 1 else "ابدأ بالغرفتين 101 و102."
	if game.notice_time > 0.0:
		news = game.notice
	set_text(event_text, news)
	event_text.modulate = PINK if game.haunt_flash > 0.0 else Color.WHITE


func animate(_delta: float) -> void:
	aura.color = Color(0.83, 0.43, 0.63, game.haunt_flash * 0.8)


func set_text(control: Control, value: String) -> void:
	if control.text != value:
		control.text = value


func can_resume() -> bool:
	return modal_kind in ["pause", "shop"]


func show_welcome() -> void:
	var card := open_dialog("welcome", Rect2(299, 185, 682, 448))
	label(card, Rect2(42, 21, 598, 30), "فندق السِّراج", 17, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)
	label(card, Rect2(42, 61, 598, 74), "مناوبة بعد منتصف الليل", 41, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	multiline(card, Rect2(66, 142, 550, 86), "تعيّنت عامل خدمة غرف في فندق قديم. جهّز الغرف وسلّم الوردية عند الاستقبال. وإذا سمعت أثاثًا ينكسر في غرفة فاضية… راجع دفتر الوردية.", 17, SUB)
	var keys := panel(card, Rect2(52, 246, 578, 69), Color("#1c2b34"))
	label(keys, Rect2(20, 5, 538, 29), "اسحب بإصبعك في الاتجاه اللي تبغى تتحرك فيه.", 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	label(keys, Rect2(20, 33, 538, 27), "اقترب من المهمة والمس الشاشة. تقدّمك ينحفظ تلقائيًا.", 15, SUB, HORIZONTAL_ALIGNMENT_CENTER)
	var start := button(card, Rect2(179, 342, 324, 59), "تابع الوردية" if game.has_save else "ابدأ أول وردية", true)
	start.pressed.connect(game.resume)
	start.grab_focus()


func show_pause() -> void:
	if game.paused:
		return
	var card := open_dialog("pause", Rect2(411, 263, 458, 271))
	label(card, Rect2(30, 22, 398, 68), "الوردية متوقفة", 35, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	multiline(card, Rect2(37, 105, 384, 43), "تقدّمك ينحفظ عند كل مهمة تنهيها.", 15, SUB)
	var resume_button := button(card, Rect2(94, 172, 270, 54), "تابع الوردية", true)
	resume_button.pressed.connect(game.resume)
	resume_button.grab_focus()


func show_summary(finished: int, earned: int, proceeds: int, costs: int) -> void:
	var card := open_dialog("summary", Rect2(305, 175, 670, 454))
	var handover := finished == 3
	label(card, Rect2(48, 23, 574, 29), "تسليم الوردية %02d" % finished, 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)
	label(card, Rect2(42, 56, 586, 68), "المفتاح صار لك" if handover else "انتهت الوردية", 40, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	var story := ["المدير: شغل مرتب. بكرة بنفتح لك غرفة زيادة. إذا دقّ جرس الاستقبال لحاله، خلك قريب من الممر.", "المدير: سمعت الكسر من مكتبي. قدرت تجهّز الغرف رغم كل اللي صار. خلّ المفتاح معك الليلة.", "المدير: قدّمت استقالتي. الفندق صار باسمك وهذا مفتاحه. من الليلة دخل الغرف ومصاريفه عندك، وأنا متأكد إنك قدّها."]
	var message: String = story[finished - 1] if finished <= 3 else "الضيوف استلموا غرفهم. دخل الغرف بعد خصم المصاريف دخل رصيدك."
	multiline(card, Rect2(58, 134, 554, 105), message, 17, SUB)
	var finance := panel(card, Rect2(47, 249, 576, 75), Color("#1e3238"))
	var earnings := "راتب الوردية  +%d ر.س" % earned
	if proceeds > 0:
		earnings = "الدخل %d  ·  المصاريف %d  ·  صافي الربح +%d ر.س" % [proceeds, costs, earned]
	label(finance, Rect2(12, 14, 552, 43), earnings, 18, TEAL, HORIZONTAL_ALIGNMENT_CENTER, true)
	var next := button(card, Rect2(179, 350, 312, 57), "استلم الفندق" if handover else "ابدأ الوردية التالية", true)
	next.pressed.connect(game.resume)
	next.grab_focus()


func show_shop() -> void:
	if not game.is_owner() or (game.paused and modal_kind != "shop"):
		return
	var card := open_dialog("shop", Rect2(330, 143, 620, 514))
	label(card, Rect2(36, 17, 548, 54), "تطويرات الفندق", 33, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	label(card, Rect2(36, 76, 548, 35), "رصيدك  %d ر.س" % game.money, 17, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var details := ["تنجز الكنس والمسح وتبديل الشراشف أسرع.", "تمنع الجن من كسر الأثاث خلال الوردية.", "ترفع دخل الليلة 12 ر.س عن كل غرفة."]
	for index in 3:
		var row := panel(card, Rect2(29, 127 + index * 89, 562, 75), CARD)
		label(row, Rect2(162, 5, 381, 32), game.UPGRADE_NAMES[index], 18, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
		label(row, Rect2(154, 38, 389, 25), details[index], 13, SUB)
		var bought: bool = game.upgrades[index]
		var cost: int = game.UPGRADE_COSTS[index]
		var buy := button(row, Rect2(14, 16, 116, 43), "تم الشراء" if bought else "%d ر.س" % cost, false)
		buy.disabled = bought or game.money < cost
		buy.pressed.connect(game.buy_upgrade.bind(index))
	var back := button(card, Rect2(176, 424, 268, 53), "ارجع للوردية", true)
	back.pressed.connect(game.resume)
	back.grab_focus()


func open_dialog(kind: String, rect: Rect2) -> Panel:
	close_dialog()
	game.paused = true
	game.reset_interaction()
	modal_kind = kind
	var shade := ColorRect.new()
	shade.color = Color(0.032, 0.061, 0.094, 0.89)
	shade.layout_direction = Control.LAYOUT_DIRECTION_LTR
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.size = size
	shade.position = Vector2.ZERO
	modal = shade
	var card := panel(shade, rect, Color("#14232e"), Color("#78664e"))
	var accent := line(Rect2(0, 0, rect.size.x - 96, 2), GOLD)
	hud.remove_child(accent)
	card.add_child(accent)
	accent.position = Vector2(48, 0)
	position_dialog()
	return card


func position_dialog() -> void:
	if not is_instance_valid(modal):
		return
	modal.size = size
	var card: Panel = modal.get_child(0)
	card.scale = Vector2.ONE * (1.28 if portrait else 1.0)
	card.position = (size - card.size * card.scale) / 2.0


func close_dialog() -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
		modal = null
	modal_kind = ""


func multiline(parent: Control, rect: Rect2, value: String, font_size: int, color: Color) -> Label:
	var item := label(parent, rect, "", font_size, color, HORIZONTAL_ALIGNMENT_CENTER)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.text = value
	return item


func label(parent: Control, rect: Rect2, value: String, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT, bold: bool = false) -> Label:
	var item := Label.new()
	item.layout_direction = Control.LAYOUT_DIRECTION_LTR
	item.text_direction = RTL
	item.horizontal_alignment = alignment
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	item.add_theme_font_size_override("font_size", font_size)
	item.add_theme_color_override("font_color", color)
	if bold:
		item.add_theme_font_override("font", ui_theme.get_font("font", "Button"))
	item.text = value
	parent.add_child(item)
	item.size = rect.size
	item.position = rect.position
	return item


func button(parent: Control, rect: Rect2, value: String, primary: bool) -> Button:
	var item := Button.new()
	item.layout_direction = Control.LAYOUT_DIRECTION_LTR
	item.text = value
	item.text_direction = RTL
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := GOLD if primary else CARD
	var border := GOLD.darkened(0.16) if primary else LINE
	var ink := BG if primary else INK
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill := normal
		match state:
			"hover": fill = normal.lightened(0.16)
			"pressed": fill = normal.darkened(0.13)
			"disabled": fill = normal.darkened(0.48) if primary else PANEL
			"focus": fill = Color.TRANSPARENT
		item.add_theme_stylebox_override(state, box_style(fill, TEAL if state == "focus" else border))
	item.add_theme_font_size_override("font_size", 14)
	item.add_theme_color_override("font_color", ink)
	item.add_theme_color_override("font_hover_color", ink)
	item.add_theme_color_override("font_pressed_color", ink)
	item.add_theme_color_override("font_focus_color", ink)
	item.add_theme_color_override("font_disabled_color", SUB.darkened(0.33))
	parent.add_child(item)
	item.size = rect.size
	item.position = rect.position
	return item


func panel(parent: Control, rect: Rect2, fill: Color, border: Color = LINE) -> Panel:
	var item := Panel.new()
	item.layout_direction = Control.LAYOUT_DIRECTION_LTR
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.add_theme_stylebox_override("panel", box_style(fill, border))
	parent.add_child(item)
	item.size = rect.size
	item.position = rect.position
	return item


func line(rect: Rect2, color: Color) -> ColorRect:
	var item := ColorRect.new()
	item.layout_direction = Control.LAYOUT_DIRECTION_LTR
	item.color = color
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(item)
	item.size = rect.size
	item.position = rect.position
	return item


func box_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style
