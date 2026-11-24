extends Control

signal changed(progress: float, feedback: String)
signal completed

const FRAME := Vector2(604, 196)
const WOOD := Color("#715034")
const BRASS := Color("#d5ac72")
const LINEN := Color("#e1c492")
const CLEAN := Color("#a7c59b")
const DARK := Color("#231a12")
const REPAIR_CENTERS := [0.37, 0.66, 0.26]
const REPAIR_RAIL := Rect2(92, 142, 420, 19)
const LINEN_HINTS := ["ابدأ بإزالة الشراشف القديمة.", "الآن افرش الشراشف النظيفة.", "باقي ترتيب المخدة."]
const NO_POINTER := -2
const MOUSE_POINTER := -1

var kind := 0
var targets: Array[Vector2] = []
var remaining: Array[float] = []
var workload := 1.0
var steps := 0
var goal := 3
var missed := 0
var brush_down := false
var pointer := NO_POINTER
var brush := Vector2.ZERO
var clock := 0.0
var done := false
var repair_indicator: ColorRect


func setup(task: Vector2i, shift: int, upgraded: bool) -> void:
	if task.y < 0 or task.y > 3:
		push_warning("The workbench received an invalid task: %s" % task)
		done = true
		return
	kind = task.y
	custom_minimum_size = FRAME
	mouse_filter = Control.MOUSE_FILTER_STOP if kind <= 1 else Control.MOUSE_FILTER_IGNORE
	if kind <= 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = (task.x + 1) * 521 + task.y * 79 + shift * 3943
		goal = (4 if kind == 0 else 3) + int(shift >= 4) - int(upgraded)
		var wetness := (44.0 if upgraded else 71.0) if kind == 1 else 1.0
		workload = goal * wetness
		for mark in goal:
			var x := (mark + 0.5) * (FRAME.x - 76) / goal + 38 + rng.randf_range(-13, 13)
			targets.append(Vector2(x, rng.randf_range(53, FRAME.y - 48)))
			remaining.append(wetness)
	elif kind == 2:
		goal = 2 if upgraded else 3
	else:
		goal = 3 if shift >= 4 else 2


func _ready() -> void:
	if kind == 3 and not done:
		repair_indicator = ColorRect.new()
		repair_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		repair_indicator.color = Color("#f4d49a")
		repair_indicator.size = Vector2(6, 33)
		add_child(repair_indicator)
		update_repair_indicator()


func _process(delta: float) -> void:
	if kind == 3 and not done and is_visible_in_tree():
		clock = fposmod(clock + minf(delta, 0.1), 2.3)
		update_repair_indicator()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_VISIBILITY_CHANGED:
			cancel_stroke()


func _gui_input(event: InputEvent) -> void:
	if done or kind > 1:
		return
	if event is InputEventScreenTouch:
		update_pointer(event.index, event.position, event.pressed and not event.canceled)
		accept_event()
	elif event is InputEventScreenDrag:
		move_brush(event.index, event.position)
		accept_event()
	elif event.device == InputEvent.DEVICE_ID_EMULATION:
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		update_pointer(MOUSE_POINTER, event.position, event.pressed)
		accept_event()
	elif event is InputEventMouseMotion and pointer == MOUSE_POINTER:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			move_brush(MOUSE_POINTER, event.position)
		else:
			cancel_stroke()
		accept_event()


func update_pointer(index: int, point: Vector2, pressed: bool) -> void:
	if not pressed:
		if pointer == index:
			cancel_stroke()
	elif pointer == NO_POINTER and point.is_finite():
		pointer = index
		brush_down = true
		brush = point
		queue_redraw()


func move_brush(index: int, point: Vector2) -> void:
	if pointer != index:
		return
	if not point.is_finite():
		cancel_stroke()
		return
	stroke(brush, point)
	brush = point


func cancel_stroke() -> void:
	if brush_down:
		pointer = NO_POINTER
		brush_down = false
		queue_redraw()


func stroke(from: Vector2, to: Vector2) -> void:
	var span := to - from
	var distance := span.length()
	if done or not is_finite(distance) or distance <= 0.01 or workload <= 0.0:
		return
	var samples := clampi(ceili(minf(distance, 1024.0) / 8.0), 1, 128)
	var sample_distance := distance / samples
	for mark in targets.size():
		if remaining[mark] <= 0.0:
			continue
		var center := targets[mark]
		if kind == 0:
			if center.distance_to(Geometry2D.get_closest_point_to_segment(center, from, to)) < 31.0:
				remaining[mark] = 0.0
				steps += 1
		else:
			for sample in samples:
				var location := from + span * ((sample + 0.5) / samples)
				if center.distance_to(location) < 37.0:
					remaining[mark] = maxf(0.0, remaining[mark] - sample_distance * 0.65)
			if remaining[mark] == 0.0:
				steps += 1
	var left := 0.0
	for amount in remaining:
		left += amount
	update_work(1.0 - left / workload)


func choose_linen(action: int) -> void:
	if done or kind != 2 or steps < 0 or steps >= goal or steps >= LINEN_HINTS.size():
		return
	if action != steps:
		changed.emit(float(steps) / goal, LINEN_HINTS[steps])
		return
	steps += 1
	update_work(float(steps) / goal)


func tighten() -> void:
	if done or kind != 3 or steps < 0 or steps >= goal or steps >= REPAIR_CENTERS.size():
		return
	if absf(needle() - REPAIR_CENTERS[steps]) > tolerance():
		missed += 1
		changed.emit(float(steps) / goal, "اضغط لما يدخل المؤشر المنطقة النحاسية.")
		queue_redraw()
		return
	steps += 1
	clock = 0.0
	missed = 0
	update_work(float(steps) / goal)


func needle() -> float:
	return 0.5 - cos(clock * TAU / 2.3) * 0.46


func update_repair_indicator() -> void:
	if is_instance_valid(repair_indicator):
		repair_indicator.visible = not done
		repair_indicator.position = REPAIR_RAIL.position + Vector2(REPAIR_RAIL.size.x * needle() - 3.0, -7)


func tolerance() -> float:
	return 0.145 + minf(0.10, missed * 0.025)


func update_work(progress: float) -> void:
	queue_redraw()
	done = steps >= goal
	update_repair_indicator()
	var caption := "%d من %d" % [steps, goal]
	if done:
		caption = "تمت المهمة"
	changed.emit(progress, caption)
	if done:
		completed.emit.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, FRAME), Color("#37291d"))
	draw_rect(Rect2(Vector2.ZERO, FRAME), Color("#836344"), false, 2)
	match kind:
		0, 1:
			draw_floor()
		2:
			draw_bed()
		3:
			draw_repair()


func draw_floor() -> void:
	for row in 4:
		for column in 12:
			var tint := WOOD.lightened(0.07) if (row + column) % 2 == 0 else WOOD
			draw_rect(Rect2(5 + column * 49.5, 5 + row * 46.7, 47.5, 45), tint)
	for index in targets.size():
		var center := targets[index]
		if remaining[index] <= 0.0:
			draw_circle(center, 6, Color("#adba86"), false, 1.5, true)
			continue
		if kind == 0:
			for speck in 9:
				var angle := speck * 2.4 + index
				var offset := Vector2.from_angle(angle) * (5 + speck * 1.8)
				draw_circle(center + offset, 3 + speck % 3, BRASS.darkened(0.13), true, -1, true)
		else:
			var wet := remaining[index] / (workload / goal)
			draw_set_transform(center, 0, Vector2(1.26, 0.69))
			draw_circle(Vector2.ZERO, 11 + 22 * wet, Color(0.29, 0.60, 0.59, 0.34 + wet * 0.4), true, -1, true)
			draw_arc(Vector2(3, 1), 8 + 17 * wet, 2.9, 4.5, 18, Color("#b4d4bd"), 2, true)
			draw_set_transform(Vector2.ZERO)
	if brush_down:
		var radius := 31.0 if kind == 0 else 37.0
		draw_circle(brush, radius, Color(BRASS, 0.3), false, 2, true)
		draw_line(brush + Vector2(0, 1), brush + Vector2(26, -26), LINEN, 4, true)
		draw_line(brush + Vector2(-12, -2), brush + Vector2(9, 12), BRASS, 10, true)


func draw_bed() -> void:
	var platform := Rect2(126, 30, 352, 138)
	draw_rect(platform.grow(8), DARK)
	draw_rect(platform, WOOD)
	draw_rect(platform.grow(-10), LINEN.darkened(0.18))
	if steps == 0:
		draw_rect(Rect2(238, 46, 215, 105), Color("#95735a"))
		draw_polyline(PackedVector2Array([Vector2(258, 116), Vector2(315, 82), Vector2(349, 105), Vector2(422, 68)]), Color("#684736"), 7, true)
	if steps >= 2:
		draw_rect(Rect2(238, 46, 215, 105), Color("#ddd1ac"))
		var seam := Color("#ac895c")
		draw_rect(Rect2(254, 55, 179, 85), seam, false, 2)
		for x in range(269, 435, 25):
			draw_circle(Vector2(x, 100), 5, seam, true, -1, true)
	var pillow_y := 62.0 if done else 83.0
	draw_rect(Rect2(155, pillow_y, 55, 68), Color("#f4e0b6"))
	draw_rect(Rect2(160, pillow_y + 6, 45, 55), Color("#b69c76"), false, 2)


func draw_repair() -> void:
	draw_rect(Rect2(78, 22, 448, 94), WOOD)
	draw_rect(Rect2(86, 30, 432, 78), Color("#a2734b"), false, 2)
	for bolt in goal:
		var center := Vector2(FRAME.x / 2.0 + (bolt - (goal - 1) / 2.0) * 111, 68)
		var tint := CLEAN if bolt < steps else BRASS if bolt == steps else BRASS.darkened(0.45)
		draw_circle(center, 23, DARK, true, -1, true)
		draw_circle(center, 18, tint, true, -1, true)
		draw_line(center - Vector2(9, 0), center + Vector2(9, 0), DARK, 3, true)
		draw_line(center - Vector2(0, 9), center + Vector2(0, 9), DARK, 3, true)
	if done or steps < 0 or steps >= REPAIR_CENTERS.size():
		return
	var rail := REPAIR_RAIL
	draw_rect(rail, DARK)
	var zone_start: float = REPAIR_CENTERS[steps] - tolerance()
	draw_rect(Rect2(rail.position + Vector2(rail.size.x * zone_start, 0), Vector2(rail.size.x * tolerance() * 2.0, rail.size.y)), BRASS)
