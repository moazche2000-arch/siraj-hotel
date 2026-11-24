extends Control

signal changed(progress: float, feedback: String)
signal completed

const Rules = preload("res://game/settings.gd")
const Task = Rules.Task
const FRAME := Vector2(638, 196)
const WOOD := Color("#795237")
const BRASS := Color("#d8ae71")
const INK := Color("#f0d8ad")
const DARK := Color("#2a2019")
const CLEAN := Color("#bdcb93")
const RAIL := Rect2(82, 140, 474, 19)
const SEARCH_POSITIONS := [Vector2(85, 104), Vector2(202, 80), Vector2(319, 108), Vector2(436, 80), Vector2(553, 104)]
const NO_POINTER := -2
const MOUSE_POINTER := -1

enum Mode { SWEEP, MOP, TIMED, SEQUENCE, SEARCH }

var mode := Mode.SWEEP
var task := Task.CLEAN
var day := 1
var intensity := 1.0
var cart := false
var steps := 0
var goal := 3
var missed := 0
var elapsed := 0.0
var period := 2.0
var zone := 0.45
var targets := PackedVector2Array()
var remaining := PackedFloat32Array()
var initial_work := 1.0
var hidden_key := 0
var searched := 0
var done := false
var pointer := NO_POINTER
var brush := Vector2.ZERO
var indicator: ColorRect
var rng := RandomNumberGenerator.new()


func setup(kind: int, game_day: int, cleanliness: float, upgraded: bool, seed_value: int) -> void:
	if kind < 0 or kind >= Rules.TASK_NAMES.size():
		push_warning("Ignored an invalid hotel workbench task.")
		done = true
		return
	task = kind
	day = maxi(1, game_day)
	intensity = clampf((100.0 - cleanliness) / 100.0, 0.0, 1.0)
	cart = upgraded
	rng.seed = seed_value
	match task:
		Task.CLEAN:
			configure_cleaning(Mode.SWEEP)
		Task.REPAIR, Task.LEAK, Task.BANISH:
			mode = Mode.TIMED
			goal = mini(4, (3 if task == Task.BANISH else 2) + int(day >= 4))
			period = rng.randf_range(1.65, 2.4) if task == Task.BANISH else rng.randf_range(2.1, 2.8)
			zone = rng.randf_range(0.24, 0.76)
		Task.BULB, Task.CALM:
			mode = Mode.SEQUENCE
			goal = 3
		Task.KEY:
			mode = Mode.SEARCH
			hidden_key = rng.randi_range(0, SEARCH_POSITIONS.size() - 1)
	mouse_filter = Control.MOUSE_FILTER_STOP if mode <= Mode.MOP or mode == Mode.SEARCH else Control.MOUSE_FILTER_IGNORE


func configure_cleaning(stage: int) -> void:
	mode = stage
	goal = clampi(3 + roundi(intensity * 3.0) + int(day >= 5) - int(cart), 2, 6)
	steps = 0
	targets.resize(goal)
	remaining.resize(goal)
	initial_work = 0.0
	for index in goal:
		targets[index] = Vector2(44 + (index + 0.5) * (FRAME.x - 88) / goal + rng.randf_range(-13, 13), rng.randf_range(49, 147))
		var wetness := lerpf(33.0, 82.0, intensity) * (0.64 if cart else 1.0)
		remaining[index] = 1.0 if stage == Mode.SWEEP else wetness * rng.randf_range(0.83, 1.17)
		initial_work += remaining[index]


func _ready() -> void:
	set_process(mode == Mode.TIMED and not done)
	if mode == Mode.TIMED and not done:
		indicator = ColorRect.new()
		indicator.color = INK
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		indicator.size = Vector2(6, 35)
		add_child(indicator)
		update_indicator()


func _process(delta: float) -> void:
	if not done and is_visible_in_tree() and is_finite(delta):
		elapsed = fposmod(elapsed + minf(delta, 0.1), period)
		update_indicator()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_VISIBILITY_CHANGED:
			cancel_stroke()


func _gui_input(event: InputEvent) -> void:
	if done:
		return
	if event is InputEventScreenTouch:
		handle_pointer(event.index, event.position, event.pressed and not event.canceled)
		accept_event()
	elif event is InputEventScreenDrag:
		move_brush(event.index, event.position)
		accept_event()
	elif event.device != InputEvent.DEVICE_ID_EMULATION and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		handle_pointer(MOUSE_POINTER, event.position, event.pressed)
		accept_event()
	elif event.device != InputEvent.DEVICE_ID_EMULATION and event is InputEventMouseMotion and pointer == MOUSE_POINTER:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			move_brush(MOUSE_POINTER, event.position)
		else:
			cancel_stroke()
		accept_event()


func handle_pointer(index: int, point: Vector2, pressed: bool) -> void:
	if not pressed:
		if pointer == index:
			cancel_stroke()
	elif pointer == NO_POINTER and point.is_finite():
		if mode == Mode.SEARCH:
			search(point)
		elif mode <= Mode.MOP:
			pointer = index
			brush = point
			queue_redraw()


func move_brush(index: int, point: Vector2) -> void:
	if pointer != index or mode > Mode.MOP:
		return
	if not point.is_finite():
		cancel_stroke()
		return
	stroke(brush, point)
	brush = point


func cancel_stroke() -> void:
	if pointer != NO_POINTER:
		pointer = NO_POINTER
		queue_redraw()


func stroke(from: Vector2, to: Vector2) -> void:
	var gap := from.distance_to(to)
	if done or mode > Mode.MOP or not is_finite(gap) or gap < 0.01:
		return
	var width := 32.0 if mode == Mode.SWEEP else 36.0
	var count := clampi(ceili(minf(gap, 1024.0) / 8.0), 1, 128)
	for index in targets.size():
		if remaining[index] <= 0.0:
			continue
		if mode == Mode.SWEEP:
			if targets[index].distance_to(Geometry2D.get_closest_point_to_segment(targets[index], from, to)) < width:
				remaining[index] = 0.0
		else:
			for sample in count:
				var point := from.lerp(to, (sample + 0.5) / count)
				if targets[index].distance_to(point) < width:
					remaining[index] = maxf(0.0, remaining[index] - gap / count * 0.65)
		if remaining[index] <= 0.0:
			steps += 1
	if steps >= goal:
		if mode == Mode.SWEEP:
			cancel_stroke()
			configure_cleaning(Mode.MOP)
			changed.emit(0.5, "الآن امسح الأرض ذهابًا وإيابًا.")
		else:
			complete()
	else:
		var work_left := 0.0
		for amount in remaining:
			work_left += amount
		var progress := 0.5 * (1.0 - work_left / maxf(initial_work, 1.0)) + (0.5 if mode == Mode.MOP else 0.0)
		changed.emit(progress, "%d من %d" % [steps, goal])
	queue_redraw()


func sequence_labels() -> PackedStringArray:
	if task == Task.BULB:
		return PackedStringArray(["أطفئ الكهرباء", "بدّل اللمبة", "شغّل الكهرباء"])
	return PackedStringArray(["اسمع الضيف", "طمّنه", "اعرض مساعدتك"])


func choose(action: int) -> void:
	if done or mode != Mode.SEQUENCE:
		return
	if action != steps:
		changed.emit(float(steps) / goal, "الخطوة التالية · " + sequence_labels()[steps])
		return
	steps += 1
	if steps >= goal:
		complete()
	else:
		changed.emit(float(steps) / goal, "الخطوة التالية · " + sequence_labels()[steps])
		queue_redraw()


func confirm_timing() -> void:
	if done or mode != Mode.TIMED:
		return
	if absf(needle() - zone) > tolerance():
		missed += 1
		changed.emit(float(steps) / goal, "اضغط لما يدخل المؤشر الجزء النحاسي.")
		queue_redraw()
		return
	steps += 1
	if steps >= goal:
		complete()
	else:
		elapsed = 0.0
		missed = 0
		zone = rng.randf_range(0.23, 0.77)
		changed.emit(float(steps) / goal, "%d من %d" % [steps, goal])
		queue_redraw()


func search(point: Vector2) -> void:
	for index in SEARCH_POSITIONS.size():
		if point.distance_to(SEARCH_POSITIONS[index]) >= 37.0 or (searched & (1 << index)) != 0:
			continue
		searched |= 1 << index
		if index == hidden_key:
			complete()
		else:
			steps += 1
			var hint := "المفتاح على اليمين." if hidden_key > index else "المفتاح على اليسار."
			changed.emit(steps / 5.0, hint)
			queue_redraw()
		return


func needle() -> float:
	return 0.5 - cos(elapsed * TAU / period) * 0.46


func tolerance() -> float:
	return maxf(0.085, 0.155 - day * 0.004) + minf(0.12, missed * 0.025)


func update_indicator() -> void:
	if is_instance_valid(indicator):
		indicator.position = RAIL.position + Vector2(RAIL.size.x * needle() - 3.0, -8)


func complete() -> void:
	done = true
	cancel_stroke()
	set_process(false)
	if is_instance_valid(indicator):
		indicator.hide()
	queue_redraw()
	changed.emit(1.0, "تمت المهمة.")
	completed.emit.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, FRAME), DARK)
	draw_rect(Rect2(Vector2.ZERO, FRAME), BRASS.darkened(0.46), false, 1.5)
	match mode:
		Mode.SWEEP, Mode.MOP:
			draw_cleaning()
		Mode.TIMED:
			draw_timing()
		Mode.SEQUENCE:
			for index in goal:
				var center := Vector2(169 + index * 150, 98)
				draw_circle(center, 36, WOOD)
				draw_circle(center, 31, CLEAN if index < steps else BRASS.darkened(0.32), false, 3)
				draw_string(ThemeDB.fallback_font, center + Vector2(-7, 7), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
		Mode.SEARCH:
			for index in SEARCH_POSITIONS.size():
				var pos: Vector2 = SEARCH_POSITIONS[index]
				var opened := (searched & (1 << index)) != 0
				draw_rect(Rect2(pos - Vector2(34, 26), Vector2(68, 52)), WOOD.darkened(0.40) if opened else WOOD)
				draw_rect(Rect2(pos - Vector2(34, 26), Vector2(68, 52)), BRASS, false, 1.5)
				draw_circle(pos, 6, CLEAN if opened and index == hidden_key else BRASS, not opened)


func draw_cleaning() -> void:
	for row in 4:
		for column in 12:
			var tint := WOOD.lightened(0.15) if (row + column) % 2 else WOOD
			draw_rect(Rect2(7 + column * 52, 6 + row * 46, 51, 45), tint)
	for index in targets.size():
		var at := targets[index]
		if remaining[index] <= 0.0:
			draw_circle(at, 7, CLEAN, false, 2)
		elif mode == Mode.SWEEP:
			for fleck in 7:
				draw_circle(at + Vector2.from_angle(fleck * 2.2) * (6 + fleck * 2), 3, BRASS)
		else:
			var radius := 11.0 + minf(20.0, remaining[index] / 4.0)
			draw_set_transform(at, 0, Vector2(1.2, 0.66))
			draw_circle(Vector2.ZERO, radius, Color("#5c9f9d"))
			draw_arc(Vector2.ZERO, radius * 0.7, 0.3, 2.0, 12, Color("#c0e2d2"), 2)
			draw_set_transform(Vector2.ZERO)
	if pointer != NO_POINTER:
		draw_circle(brush, 31, Color(BRASS, 0.65), false, 2)
		draw_line(brush, brush + Vector2(28, -30), INK, 4)


func draw_timing() -> void:
	draw_rect(Rect2(54, 26, 530, 89), WOOD)
	for index in goal:
		var center := Vector2(FRAME.x * 0.5 + (index - (goal - 1) / 2.0) * 85, 70)
		draw_circle(center, 24, DARK)
		draw_circle(center, 19, CLEAN if index < steps else BRASS)
		draw_line(center - Vector2(9, 0), center + Vector2(9, 0), DARK, 3)
	draw_rect(RAIL, Color.BLACK)
	var start := RAIL.position + Vector2(RAIL.size.x * (zone - tolerance()), 0)
	draw_rect(Rect2(start, Vector2(RAIL.size.x * tolerance() * 2.0, RAIL.size.y)), BRASS)
