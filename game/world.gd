extends Node2D

const MAP_SIZE := Vector2(902, 566)
const START := Vector2(458, 315)
const DESK := Vector2(458, 264)
const ROOM_NUMBERS := [101, 102, 103, 104, 105, 106]
const TASK_COLORS := [Color("#f4bd75"), Color("#92c2b0"), Color("#f9e0aa"), Color("#ed9d81")]
const GOLD := Color("#e5b874")
const READY := Color("#c6d49a")
const SHADOW := Color("#291d16")
const FONT = preload("res://assets/Arabic.ttf")
const HOTEL = preload("res://assets/hotel-floor.png")
const WORKER = preload("res://assets/worker.png")
const JINN = preload("res://assets/jinn.png")
const FRAME := Vector2(128, 128)

var game: Node2D


static func room_rect(index: int) -> Rect2:
	return Rect2(21 + (index % 3) * 293, 23 if index < 3 else 348, 274, 190)


static func station(index: int, task: int) -> Vector2:
	var room := room_rect(index)
	var facing_y := 139.0 if index < 3 else 86.0
	match task:
		0:
			return room.position + Vector2(79, facing_y)
		1:
			return room.position + Vector2(165, facing_y)
		2:
			return room.position + Vector2(70, 70 if index < 3 else 132)
		_:
			return room.position + Vector2(227, 70 if index < 3 else 132)


static func door(index: int) -> Vector2:
	var room := room_rect(index)
	return Vector2(room.get_center().x, room.end.y if index < 3 else room.position.y)


static func floor_contains(point: Vector2, active_rooms: int) -> bool:
	if Rect2(24, 219, 846, 123).has_point(point):
		return not Rect2(402, 244, 112, 36).has_point(point)
	for index in active_rooms:
		var room := room_rect(index)
		if room.grow(-9).has_point(point):
			var bed := Rect2(room.position + Vector2(25, 78 if index < 3 else 139), Vector2(89, 41))
			var cabinet := Rect2(room.position + Vector2(208, 84 if index < 3 else 146), Vector2(43, 23))
			return not (bed.has_point(point) or cabinet.has_point(point))
		if Rect2(door(index) - Vector2(28, 22), Vector2(56, 44)).has_point(point):
			return true
	return false


func _draw() -> void:
	draw_texture_rect(HOTEL, Rect2(Vector2.ZERO, MAP_SIZE), false)
	for index in 6:
		draw_room_state(index)
	draw_plate(Vector2(416, 222), "الاستقبال", 84, GOLD)
	if game.all_done():
		draw_circle(DESK + Vector2(0, 34), 10 + sin(game.elapsed * 5.0) * 3.0, READY, false, 2)
	if game.haunt_flash > 0.0:
		var flash: float = game.haunt_flash
		draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.57, 0.28, 0.2, flash * 0.13))
		draw_rect(Rect2(Vector2(3, 3), MAP_SIZE - Vector2(6, 6)), Color(0.94, 0.55, 0.35, flash * 0.7), false, 3)
	if game.ghost_time > 0.0:
		draw_ghost()
	draw_worker()
	for spark in game.sparks:
		var tint: Color = spark.color
		tint.a = minf(spark.life * 2.0, 1.0)
		draw_circle(spark.pos, 2, tint)


func draw_room_state(index: int) -> void:
	var room := room_rect(index)
	if index >= game.active_rooms:
		draw_rect(room.grow(-4), Color(0.085, 0.063, 0.043, 0.71))
		var center := door(index)
		var closed := Rect2(center - Vector2(28, 7), Vector2(56, 14))
		draw_rect(closed, Color("#4d3829"))
		draw_rect(closed, Color("#826045"), false)
		for offset in range(-24, 25, 8):
			draw_line(center + Vector2(offset, -6), center + Vector2(offset, 6), Color("#735439"))
		draw_plate(room.position + Vector2(52, 5), str(ROOM_NUMBERS[index]), 45, Color("#9d825b"))
		return
	draw_plate(room.position + Vector2(52, 5), str(ROOM_NUMBERS[index]), 45, GOLD)
	if game.room_done(index):
		var badge := room.position + Vector2(252, 16)
		draw_circle(badge, 8, Color("#404b2b"))
		draw_polyline(PackedVector2Array([badge + Vector2(-4, 0), badge + Vector2(-1, 3), badge + Vector2(4, -3)]), READY, 1.7)
		return
	for task in 4:
		if game.rooms[index][task] > 0:
			draw_task(index, task)


func draw_task(index: int, task: int) -> void:
	var pos := station(index, task)
	var color: Color = TASK_COLORS[task]
	match task:
		0:
			for offset in [Vector2(-6, 1), Vector2(8, 7), Vector2(1, -6), Vector2(12, -3), Vector2(-10, 6)]:
				draw_circle(pos + offset, 3, Color("#a57950"))
				draw_circle(pos + offset - Vector2(0, 1), 1, Color("#d3a772"))
		1:
			draw_set_transform(pos, 0, Vector2(1.6, 0.65))
			draw_circle(Vector2.ZERO, 12, Color(0.20, 0.53, 0.58, 0.68))
			draw_arc(Vector2(1, 0), 9, 0.2, 1.9, 12, color, 1.4, true)
			draw_set_transform(Vector2.ZERO)
		2:
			var bed := pos + Vector2(0, 22)
			draw_polyline(PackedVector2Array([bed + Vector2(-5, 1), bed + Vector2(4, -3), bed + Vector2(9, 1), bed + Vector2(17, -2)]), Color("#6b4733"), 3)
		3:
			var cabinet := pos + Vector2(0, 23)
			draw_polyline(PackedVector2Array([cabinet + Vector2(4, -9), cabinet + Vector2(-3, -3), cabinet + Vector2(5, 4), cabinet + Vector2(-2, 11)]), color, 2)
	var ping := pos + Vector2(0, -12 + sin(game.elapsed * 3.7 + index) * 2)
	var selected: bool = game.target.x == index and game.target.y == task
	draw_set_transform(ping, 0, Vector2(scale.y / scale.x, 1))
	draw_circle(Vector2.ZERO, 14 if selected else 11, SHADOW)
	draw_circle(Vector2.ZERO, 13 if selected else 10, color, false, 1.5)
	draw_task_symbol(task, color)
	draw_set_transform(Vector2.ZERO)


func draw_task_symbol(task: int, color: Color) -> void:
	match task:
		0:
			draw_line(Vector2(3, -6), Vector2(-2, 1), color, 2)
			draw_colored_polygon(PackedVector2Array([Vector2(-1, -1), Vector2(3, 2), Vector2(1, 6), Vector2(-6, 2)]), color)
		1:
			draw_colored_polygon(PackedVector2Array([Vector2(0, -6), Vector2(4, 0), Vector2(4, 4), Vector2(0, 6), Vector2(-4, 4), Vector2(-4, 0)]), color)
		2:
			draw_rect(Rect2(-6, -3, 12, 7), color)
			draw_line(Vector2(-2, -3), Vector2(-2, 4), SHADOW)
		3:
			draw_line(Vector2(-4, 5), Vector2(3, -4), color, 2)
			draw_line(Vector2(0, -5), Vector2(6, 0), color, 3)


func draw_worker() -> void:
	var pos: Vector2 = game.player
	var phase := int(game.elapsed * 8.0) % 2 if game.walking else 0
	var region := Rect2(Vector2(game.facing, phase) * FRAME, FRAME)
	draw_set_transform(pos, 0, Vector2(scale.y / scale.x, 0.52))
	draw_circle(Vector2(0, 3), 13, Color(0.10, 0.07, 0.05, 0.52))
	draw_set_transform(pos, 0, Vector2(scale.y / scale.x, 1))
	draw_texture_rect_region(WORKER, Rect2(-31, -44, 62, 62), region)
	draw_set_transform(Vector2.ZERO)


func draw_ghost() -> void:
	var pos: Vector2 = game.ghost_position + Vector2(sin(game.elapsed * 5.0) * 9, sin(game.elapsed * 6.0) * 7)
	var opacity: float = clampf(game.ghost_time, 0.0, 1.0)
	draw_set_transform(pos, 0, Vector2(scale.y / scale.x, 1))
	draw_circle(Vector2.ZERO, 28, Color(0.68, 0.71, 0.52, opacity * 0.17))
	draw_texture_rect(JINN, Rect2(-44, -61, 88, 88), false, Color(1, 1, 0.91, opacity * 0.89))
	draw_set_transform(Vector2.ZERO)


func draw_plate(pos: Vector2, value: String, width: float, color: Color) -> void:
	var rect := Rect2(pos, Vector2(width, 16))
	draw_rect(rect, SHADOW)
	draw_rect(rect, color.darkened(0.28), false)
	var text_width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(FONT, pos + Vector2((width - text_width) / 2, 12), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
