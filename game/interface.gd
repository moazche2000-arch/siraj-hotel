extends Control

const Arabic = preload("res://assets/Arabic.ttf")
const World = preload("res://game/world.gd")
const Workbench = preload("res://game/workbench.gd")
const BG := Color("#17120e")
const PANEL := Color("#291f16")
const CARD := Color("#382b1f")
const LINE := Color("#675138")
const INK := Color("#f1dfbf")
const SUB := Color("#bfac8e")
const GOLD := Color("#d8aa69")
const TEAL := Color("#bbcb92")
const PINK := Color("#efaa91")
const RTL := Control.TEXT_DIRECTION_RTL
const MAP_ORIGIN := Vector2(10, 49)
const MAP_HEIGHT := 627.0
const DIARY_WIDTH := 176.0

var game: Node2D
var ui_theme: Theme
var hud: Control
var needs_rotation := false
var layout_in_progress := false
var rotate_screen: ColorRect
var rotate_note: Label
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
var modal_card: Panel
var modal_kind := ""
var chore_board: Control
var diagnostics_return := "welcome"
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
	var landscape := Vector2i(width, 720)
	var layout := landscape
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
	hud.size = layout
	hud.position = Vector2.ZERO
	gesture_buttons.clear()
	room_boxes.clear()
	room_statuses.clear()
	room_dots.clear()
	build_landscape(layout.x)
	aura = line(Rect2(0, 0, layout.x, 3), Color.TRANSPARENT)
	refresh()


func build_landscape(width: float) -> void:
	var diary_x := width - DIARY_WIDTH - 10.0
	var map_size := Vector2(diary_x - MAP_ORIGIN.x - 8.0, MAP_HEIGHT)
	game.map_view.position = MAP_ORIGIN
	game.map_view.size = map_size
	game.world.configure_camera(map_size)
	line(Rect2(10, 44, width - 20, 1), LINE)
	label(hud, Rect2(14, 4, 170, 34), "١٩٧٨  ·  الطابق الأرضي", 15, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	label(hud, Rect2(diary_x - 280, 2, 272, 40), "فندق السِّراج", 30, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	build_menu(Rect2(diary_x, 5, 91, 36), Rect2(diary_x + 97, 5, 79, 36))
	panel(hud, Rect2(diary_x, MAP_ORIGIN.y, DIARY_WIDTH, MAP_HEIGHT), PANEL)
	var x := diary_x + 10
	var inside := DIARY_WIDTH - 20
	label(hud, Rect2(x, 63, inside, 35), "دفتر الوردية", 21, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
	shift_label = label(hud, Rect2(x, 104, inside, 28), "", 15, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	shift_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	shift_badge = label(hud, Rect2(x, 133, inside, 22), "", 12, SUB)
	line(Rect2(x, 161, inside, 1), LINE)
	task_line = label(hud, Rect2(x, 171, inside, 26), "", 14, INK)
	build_progress(Rect2(x, 205, inside, 4))
	build_rooms(Vector2(x, 224), Vector2(75, 42), Vector2(6, 6))
	line(Rect2(x, 374, inside, 1), LINE)
	balance_label = label(hud, Rect2(x, 381, inside, 34), "", 17, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
	profit_label = label(hud, Rect2(x, 414, inside, 24), "", 13, TEAL)
	build_event(Rect2(x, 449, inside, 110), 13)
	build_shop(Rect2(x, 622, inside, 40))
	line(Rect2(10, 680, width - 20, 1), LINE)
	label(hud, Rect2(14, 683, 245, 32), "اسحب وثبّت إصبعك للمشي", 15, GOLD, HORIZONTAL_ALIGNMENT_LEFT)
	task_hint = label(hud, Rect2(262, 683, diary_x - 441, 32), "", 15, INK)
	build_action(Rect2(diary_x - 169, 684, 161, 31), 15)


func show_rotation_prompt() -> void:
	if not needs_rotation:
		if is_instance_valid(rotate_screen):
			rotate_screen.hide()
		return
	if not is_instance_valid(rotate_screen):
		rotate_screen = ColorRect.new()
		rotate_screen.layout_direction = Control.LAYOUT_DIRECTION_LTR
		rotate_screen.color = BG
		rotate_screen.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(rotate_screen)
		rotate_screen.position = Vector2.ZERO
		rotate_note = label(rotate_screen, Rect2(0, 0, 560, 100), "لفّ جوالك بالعرض عشان تلعب", 32, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	rotate_screen.size = size
	rotate_note.position = (size - rotate_note.size) * 0.5
	move_child(rotate_screen, -1)
	rotate_screen.show()


func build_menu(sound_rect: Rect2, pause_rect: Rect2) -> void:
	sound_button = button(hud, sound_rect, "الصوت", false)
	sound_button.pressed.connect(game.toggle_sound)
	var pause_button := button(hud, pause_rect, "إيقاف", false)
	pause_button.pressed.connect(show_pause)
	for item in [sound_button, pause_button]:
		item.add_theme_font_size_override("font_size", 14)
		gesture_buttons.append(item)


func build_progress(rect: Rect2) -> void:
	progress_track = rect
	line(rect, LINE)
	progress = line(rect, TEAL)


func build_rooms(origin: Vector2, card: Vector2, gap: Vector2) -> void:
	for index in 6:
		var column := 1 - index % 2
		var row := floori(index / 2.0)
		var box := panel(hud, Rect2(origin + Vector2(column, row) * (card + gap), card), CARD)
		room_boxes.append(box)
		var room_code := label(box, Rect2(4, 1, card.x - 12, 22), str(World.ROOM_NUMBERS[index]), 13, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
		room_code.text_direction = Control.TEXT_DIRECTION_LTR
		room_statuses.append(label(box, Rect2(4, 23, card.x - 12, 15), "", 10, SUB))
		var dots: Array[Label] = []
		for task in 4:
			var dot := label(box, Rect2(6 + task * 8, 2, 8, 19), "•", 11, World.TASK_COLORS[task], HORIZONTAL_ALIGNMENT_CENTER)
			dots.append(dot)
		room_dots.append(dots)


func build_event(rect: Rect2, font_size: int) -> void:
	event_panel = panel(hud, rect, Color("#32271b"))
	var heading_height := 28
	label(event_panel, Rect2(12, 2, rect.size.x - 24, heading_height), "سجل الوردية", font_size - 1, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
	event_text = label(event_panel, Rect2(12, heading_height + 2, rect.size.x - 24, rect.size.y - heading_height - 8), "", font_size, INK)
	event_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func build_shop(rect: Rect2) -> void:
	shop_button = button(hud, rect, "تطويرات الفندق", false)
	shop_button.add_theme_font_size_override("font_size", 13)
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
	if not is_instance_valid(task_line) or room_boxes.size() != World.ROOM_NUMBERS.size():
		return
	shift_label.text = "%02d  /  %s" % [game.shift, game.shift_name()]
	shift_badge.text = "مالك الفندق" if game.is_owner() else "موظف خدمة الغرف"
	balance_label.text = "الرصيد  %d ر.س" % game.money
	profit_label.text = "الأرباح  %d ر.س" % game.total_profit if game.is_owner() else ""
	sound_button.text = "صوت مغلق" if game.muted else "الصوت"
	shop_button.disabled = not game.is_owner()
	shop_button.text = "تطويرات الفندق" if game.is_owner() else "التطويرات مغلقة"
	var clean: int = game.clean_room_count()
	task_line.text = "%d من %d غرف جاهزة" % [clean, game.active_rooms]
	var remaining: int = game.remaining_tasks()
	var completion := 1.0 - float(remaining) / maxf(game.task_total, 1)
	progress.size.x = maxf(1, completion * progress_track.size.x)
	progress.position.x = progress_track.end.x - progress.size.x
	for index in 6:
		var active: bool = game.is_room_open(index)
		var ready: bool = active and game.room_done(index)
		room_boxes[index].add_theme_stylebox_override("panel", box_style(Color("#343720") if ready else CARD if active else Color("#241c15"), Color("#656644") if ready else LINE))
		room_statuses[index].text = "جاهزة" if ready else "تحتاج تنظيف" if active else "مغلقة"
		room_statuses[index].modulate = TEAL if ready else Color.WHITE
		for work in 4:
			room_dots[index][work].visible = active and game.task_count(index, work) > 0
	refresh_live()
	update_flash()


func refresh_live() -> void:
	if not is_instance_valid(task_hint) or not is_instance_valid(job_button) or not is_instance_valid(event_text):
		return
	var target: Vector2i = game.target
	var message := "اقترب من علامة المهمة، ثم المس الشاشة."
	var button_text := "تفاعل"
	if target == Vector2i(-2, -2):
		message = "دفتر الوردية جاهز للتسليم."
		button_text = "إنهاء الوردية"
	elif game.task_count(target.x, target.y) > 0:
		message = "%s  /  غرفة %d" % [game.TASK_NAMES[target.y], World.ROOM_NUMBERS[target.x]]
		button_text = game.TASK_NAMES[target.y]
	elif game.all_done():
		message = "كل الغرف جاهزة. ارجع إلى مكتب الاستقبال في وسط الممر."
	set_text(task_hint, message)
	set_text(job_button, button_text)
	job_button.disabled = target != Vector2i(-2, -2) and game.task_count(target.x, target.y) <= 0
	var news := "الممر هادئ الآن." if game.shift > 1 else "ابدأ بالغرفتين 101 و102."
	if game.notice_time > 0.0:
		news = game.notice
	set_text(event_text, news)


func update_flash() -> void:
	if not is_instance_valid(aura) or not is_instance_valid(event_text):
		return
	aura.color = Color(0.83, 0.45, 0.27, game.haunt_flash * 0.8)
	event_text.modulate = PINK if game.haunt_flash > 0.0 else Color.WHITE


func set_text(control: Control, value: String) -> void:
	if control.text != value:
		control.text = value


func can_resume() -> bool:
	return modal_kind in ["pause", "shop", "chore"]


func show_welcome() -> void:
	var card := open_dialog("welcome", Rect2(299, 185, 682, 448))
	label(card, Rect2(42, 21, 598, 30), "فندق السِّراج", 17, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)
	label(card, Rect2(42, 61, 598, 74), "مناوبة بعد منتصف الليل", 41, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	multiline(card, Rect2(66, 142, 550, 86), "عام ١٩٧٨. تعيّنت عامل خدمة غرف في فندق السِّراج. جهّز الغرف وسلّم الوردية عند الاستقبال. وإذا سمعت أثاثًا ينكسر في غرفة فاضية… راجع دفتر الوردية.", 17, SUB)
	var keys := panel(card, Rect2(52, 246, 578, 69), Color("#382a1b"))
	label(keys, Rect2(20, 5, 538, 29), "اسحب باتجاه المشي وخلّ إصبعك على الشاشة.", 18, INK, HORIZONTAL_ALIGNMENT_CENTER)
	label(keys, Rect2(20, 33, 538, 27), "ارفع إصبعك للتوقف. اقترب من المهمة والمس الشاشة.", 15, SUB, HORIZONTAL_ALIGNMENT_CENTER)
	var start := button(card, Rect2(179, 342, 324, 59), "تابع الوردية" if game.has_save else "ابدأ أول وردية", true)
	start.pressed.connect(game.resume)
	start.grab_focus()
	var log_button := button(card, Rect2(244, 406, 194, 32), "سجل الأخطاء", false)
	log_button.pressed.connect(show_diagnostics.bind("welcome"))


func show_chore(work: Vector2i) -> void:
	if game.task_count(work.x, work.y) <= 0 or not World.has_task_station(work.x, work.y):
		push_warning("Ignored a request to open an unavailable chore: %s" % work)
		return
	var card := open_dialog("chore", Rect2(0, 0, 670, 454))
	var headings := [
		"مرّر المكنسة فوق أكوام الغبار.",
		"حرّك الممسحة ذهابًا وإيابًا فوق كل بقعة حتى تجف.",
		"شيل القديم، افرش النظيف، ثم رتّب المخدة.",
		"شدّ المسامير لما يدخل المؤشر في المنطقة النحاسية.",
	]
	if work.y == 2 and game.upgrades[0]:
		headings[2] = "شيل الشراشف القديمة، ثم افرش الطقم الجاهز."
	label(card, Rect2(33, 16, 604, 42), "%s  ·  غرفة %d" % [game.TASK_NAMES[work.y], World.ROOM_NUMBERS[work.x]], 27, GOLD, HORIZONTAL_ALIGNMENT_RIGHT, true)
	label(card, Rect2(33, 63, 604, 37), headings[work.y], 18, INK, HORIZONTAL_ALIGNMENT_RIGHT)
	var board := Workbench.new()
	board.layout_direction = Control.LAYOUT_DIRECTION_LTR
	board.setup(work, game.shift, game.upgrades[0])
	card.add_child(board)
	board.size = Workbench.FRAME
	board.position = Vector2(33, 111)
	chore_board = board
	var meter := panel(card, Rect2(33, 318, 604, 5), CARD)
	var fill := ColorRect.new()
	fill.color = TEAL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_child(fill)
	fill.size = Vector2(0, 5)
	var status := label(card, Rect2(33, 329, 604, 28), "0 من %d" % board.goal, 16, SUB)
	board.changed.connect(func(progress: float, feedback: String):
		if is_instance_valid(board) and chore_board == board and is_instance_valid(status) and is_instance_valid(fill):
			status.text = feedback
			fill.size.x = 604 * progress
			fill.position.x = 604 - fill.size.x
	)
	board.completed.connect(func():
		if modal_kind == "chore" and is_instance_valid(board) and chore_board == board:
			game.complete_task(work)
	, CONNECT_ONE_SHOT)
	var back := button(card, Rect2(33, 377, 126, 50), "ارجع للغرفة", false)
	back.pressed.connect(game.resume)
	if work.y == 2:
		var actions := ["شيل القديم", "افرش النظيف", "رتّب المخدة"]
		for index in board.goal:
			var action := (index + 1) % board.goal
			var choice := button(card, Rect2(190 + index * 150, 377, 142, 50), actions[action], true)
			choice.pressed.connect(board.choose_linen.bind(action))
	elif work.y == 3:
		var tighten := button(card, Rect2(423, 377, 214, 50), "شدّ المسمار", true)
		tighten.pressed.connect(board.tighten)


func show_pause(from_diagnostics: bool = false) -> void:
	if game.paused and not from_diagnostics:
		return
	var card := open_dialog("pause", Rect2(411, 263, 458, 271))
	label(card, Rect2(30, 22, 398, 68), "الوردية متوقفة", 35, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	multiline(card, Rect2(37, 105, 384, 43), "تقدّمك ينحفظ عند كل مهمة تنهيها.", 15, SUB)
	var resume_button := button(card, Rect2(194, 172, 228, 54), "تابع الوردية", true)
	resume_button.pressed.connect(game.resume)
	resume_button.grab_focus()
	var log_button := button(card, Rect2(36, 172, 140, 54), "سجل الأخطاء", false)
	log_button.pressed.connect(show_diagnostics.bind("pause"))


func show_diagnostics(previous_dialog: String) -> void:
	diagnostics_return = previous_dialog
	var card := open_dialog("diagnostics", Rect2(0, 0, 780, 466))
	label(card, Rect2(36, 22, 708, 52), "سجل الأخطاء", 31, INK, HORIZONTAL_ALIGNMENT_RIGHT, true)
	var state := label(card, Rect2(36, 76, 708, 34), "آخر ٢٠ حدثًا محفوظة على هذا الجهاز.", 17, SUB)
	var log_text: String = game.diagnostics.text() if is_instance_valid(game.diagnostics) else ""
	var log_view := TextEdit.new()
	log_view.editable = false
	log_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	log_view.text_direction = Control.TEXT_DIRECTION_AUTO
	log_view.text = log_text if not log_text.is_empty() else "ما فيه أخطاء مسجّلة."
	log_view.add_theme_font_size_override("font_size", 17)
	card.add_child(log_view)
	log_view.position = Vector2(36, 114)
	log_view.size = Vector2(708, 263)
	var copy := button(card, Rect2(556, 397, 188, 48), "نسخ السجل", true)
	copy.disabled = log_text.is_empty() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(log_text)
		state.text = "تم نسخ السجل."
	)
	var back := button(card, Rect2(36, 397, 152, 48), "رجوع", false)
	back.pressed.connect(close_diagnostics)


func close_diagnostics() -> void:
	if modal_kind != "diagnostics":
		return
	if diagnostics_return == "pause":
		show_pause(true)
	else:
		show_welcome()


func show_summary(finished: int, earned: int, proceeds: int, costs: int) -> void:
	var card := open_dialog("summary", Rect2(305, 175, 670, 454))
	var handover := finished == 3
	label(card, Rect2(48, 23, 574, 29), "تسليم الوردية %02d" % finished, 16, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true)
	label(card, Rect2(42, 56, 586, 68), "المفتاح صار لك" if handover else "انتهت الوردية", 40, INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	var story := ["المدير: شغل مرتب. بكرة بنفتح لك غرفة زيادة. إذا دقّ جرس الاستقبال لحاله، خلك قريب من الممر.", "المدير: سمعت الكسر من مكتبي. قدرت تجهّز الغرف رغم كل اللي صار. خلّ المفتاح معك الليلة.", "المدير: قدّمت استقالتي. الفندق صار باسمك وهذا مفتاحه. من الليلة دخل الغرف ومصاريفه عندك، وأنا متأكد إنك قدّها."]
	var message: String = story[finished - 1] if finished <= 3 else "الضيوف استلموا غرفهم. دخل الغرف بعد خصم المصاريف دخل رصيدك."
	multiline(card, Rect2(58, 134, 554, 105), message, 17, SUB)
	var finance := panel(card, Rect2(47, 249, 576, 75), Color("#353420"))
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
	shade.color = Color(0.057, 0.041, 0.022, 0.84)
	shade.layout_direction = Control.LAYOUT_DIRECTION_LTR
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.size = size
	shade.position = Vector2.ZERO
	modal = shade
	shade.visible = not needs_rotation
	var card := panel(shade, rect, Color("#2d2116"), Color("#8b6f4c"))
	modal_card = card
	line(Rect2(48, 0, rect.size.x - 96, 2), GOLD, card)
	position_dialog()
	return card


func position_dialog() -> void:
	if not is_instance_valid(modal) or not is_instance_valid(modal_card):
		return
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


func line(rect: Rect2, color: Color, parent: Control = null) -> ColorRect:
	var item := ColorRect.new()
	item.layout_direction = Control.LAYOUT_DIRECTION_LTR
	item.color = color
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(hud if parent == null else parent).add_child(item)
	item.size = rect.size
	item.position = rect.position
	return item


func box_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style
