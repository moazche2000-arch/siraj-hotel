extends Node2D

const MAP_SIZE := Vector2(902, 566)
const START := Vector2(458, 315)
const DESK := Vector2(458, 264)
const ROOM_NUMBERS := [101, 102, 103, 104, 105, 106]
const ROOM_RECTS := [
	Rect2(21, 23, 274, 190), Rect2(314, 23, 274, 190), Rect2(607, 23, 274, 190),
	Rect2(21, 348, 274, 190), Rect2(314, 348, 274, 190), Rect2(607, 348, 274, 190),
]
const TASK_COUNT := 4
const TASK_COLORS := [Color("#f4bd75"), Color("#92c2b0"), Color("#f9e0aa"), Color("#ed9d81")]
const GOLD := Color("#e5b874")
const READY := Color("#c6d49a")
const SHADOW := Color("#291d16")
const FONT = preload("res://assets/Arabic.ttf")
const HOTEL = preload("res://assets/hotel-floor.png")
const WORKER = preload("res://assets/worker.png")
const JINN = preload("res://assets/jinn.png")
const FRAME := Vector2(128, 128)
const CORRIDOR_ZOOM := 2.2
const CAMERA_FOLLOW_SPEED := 7.0
const ROOM_TRANSITION := 0.4
const ROOM_MARGIN := 12.0

var game: Node2D
var view_size := Vector2.ZERO
var actors := Node2D.new()
var room_mask := Node2D.new()
var last_actor_position := Vector2.INF
var last_actor_frame := -1
var focused_room := -1
var transition_age := ROOM_TRANSITION
var transition_origin := Vector2.ZERO
var transition_zoom := CORRIDOR_ZOOM


func _ready() -> void:
	actors.draw.connect(draw_actors)
	add_child(actors)
	room_mask.draw.connect(draw_room_mask)
	add_child(room_mask)


func configure_camera(view: Vector2) -> void:
	if not view.is_finite() or view.x <= 0.0 or view.y <= 0.0:
		push_warning("Camera ignored an invalid viewport size.")
		return
	view_size = view
	follow_player(0.0, true)


func follow_player(delta: float, snap: bool = false) -> void:
	if view_size == Vector2.ZERO or not is_instance_valid(game) or not game.player.is_finite():
		return
	var room := room_at(game.player, game.active_rooms)
	if focused_room != room:
		focused_room = room
		transition_age = 0.0
		transition_origin = position
		transition_zoom = scale.x
		room_mask.queue_redraw()

	var cover := maxf(view_size.x / MAP_SIZE.x, view_size.y / MAP_SIZE.y)
	var goal_zoom := maxf(CORRIDOR_ZOOM, cover)
	var center: Vector2 = game.player
	if room >= 0:
		var bounds: Rect2 = ROOM_RECTS[room]
		var inset := view_size - Vector2.ONE * ROOM_MARGIN * 2.0
		goal_zoom = maxf(cover, minf(inset.x / bounds.size.x, inset.y / bounds.size.y))
		center = bounds.get_center()
	var goal_position := clamp_camera(view_size * 0.5 - center * goal_zoom, goal_zoom)

	var next_zoom := goal_zoom
	var next_position := goal_position
	if snap:
		transition_age = ROOM_TRANSITION
	elif transition_age < ROOM_TRANSITION:
		transition_age = minf(transition_age + delta, ROOM_TRANSITION)
		var weight := smoothstep(0.0, ROOM_TRANSITION, transition_age)
		next_zoom = lerpf(transition_zoom, goal_zoom, weight)
		next_position = transition_origin.lerp(goal_position, weight)
	elif position.distance_squared_to(goal_position) >= 0.16:
		next_position = position.lerp(goal_position, 1.0 - exp(-CAMERA_FOLLOW_SPEED * delta))
	next_position = clamp_camera(next_position, next_zoom)
	if scale.x != next_zoom:
		scale = Vector2.ONE * next_zoom
	if position != next_position:
		position = next_position


func clamp_camera(offset: Vector2, zoom: float) -> Vector2:
	return offset.clamp((view_size - MAP_SIZE * zoom).min(Vector2.ZERO), Vector2.ZERO)


func update_actors(effects_changed: bool) -> void:
	if not is_instance_valid(game):
		return
	var frame := worker_frame()
	if effects_changed or game.player != last_actor_position or frame != last_actor_frame:
		last_actor_position = game.player
		last_actor_frame = frame
		actors.queue_redraw()


static func room_rect(index: int) -> Rect2:
	return ROOM_RECTS[index] if index >= 0 and index < ROOM_RECTS.size() else Rect2()


static func room_at(point: Vector2, active_rooms: int) -> int:
	for index in clampi(active_rooms, 0, ROOM_RECTS.size()):
		if ROOM_RECTS[index].has_point(point):
			return index
	return -1


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


static func bed_rect(index: int) -> Rect2:
	return Rect2(room_rect(index).position + Vector2(25, 78 if index < 3 else 139), Vector2(89, 41))


static func cabinet_rect(index: int) -> Rect2:
	return Rect2(room_rect(index).position + Vector2(208, 84 if index < 3 else 146), Vector2(43, 23))


static func has_task_station(index: int, task: int) -> bool:
	var room := room_rect(index)
	if not room.has_area() or task < 0 or task >= TASK_COUNT:
		return false
	var point := station(index, task)
	match task:
		2:
			return bed_rect(index).has_point(point + Vector2(0, 22))
		3:
			return cabinet_rect(index).has_point(point + Vector2(0, 23))
		_:
			return room.grow(-9).has_point(point) and not bed_rect(index).has_point(point) and not cabinet_rect(index).has_point(point)


static func floor_contains(point: Vector2, active_rooms: int) -> bool:
	if Rect2(24, 219, 846, 123).has_point(point):
		return not Rect2(402, 244, 112, 36).has_point(point)
	for index in clampi(active_rooms, 0, ROOM_RECTS.size()):
		var room := room_rect(index)
		if room.grow(-9).has_point(point):
			return not (bed_rect(index).has_point(point) or cabinet_rect(index).has_point(point))
		if Rect2(door(index) - Vector2(28, 22), Vector2(56, 44)).has_point(point):
			return true
	return false


func _draw() -> void:
	draw_texture_rect(HOTEL, Rect2(Vector2.ZERO, MAP_SIZE), false)
	if not is_instance_valid(game):
		return
	for index in ROOM_RECTS.size():
		draw_room_state(index)
	draw_plate(Vector2(416, 222), "الاستقبال", 84, GOLD)
	if game.all_done():
		draw_circle(DESK + Vector2(0, 34), 13, READY, false, 2)


func draw_actors() -> void:
	if not is_instance_valid(game):
		return
	if game.haunt_flash > 0.0:
		var flash: float = game.haunt_flash
		actors.draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.57, 0.28, 0.2, flash * 0.13))
	if game.ghost_time > 0.0:
		draw_ghost()
	draw_worker()
	for index in game.spark_count:
		var tint: Color = game.spark_colors[index]
		tint.a = minf(game.spark_lifetimes[index] * 2.0, 1.0)
		actors.draw_circle(game.spark_positions[index], 2, tint)


func draw_room_mask() -> void:
	if focused_room < 0:
		for index in ROOM_RECTS.size():
			var bounds: Rect2 = ROOM_RECTS[index]
			room_mask.draw_rect(bounds, Color.BLACK)
			var label_offset := Vector2(-12, -7 if index < 3 else 17)
			room_mask.draw_string(FONT, door(index) + label_offset, str(ROOM_NUMBERS[index]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, GOLD)
		return
	var visible_room := room_rect(focused_room)
	room_mask.draw_rect(Rect2(0, 0, MAP_SIZE.x, visible_room.position.y), Color.BLACK)
	room_mask.draw_rect(Rect2(0, visible_room.end.y, MAP_SIZE.x, MAP_SIZE.y - visible_room.end.y), Color.BLACK)
	room_mask.draw_rect(Rect2(0, visible_room.position.y, visible_room.position.x, visible_room.size.y), Color.BLACK)
	room_mask.draw_rect(Rect2(visible_room.end.x, visible_room.position.y, MAP_SIZE.x - visible_room.end.x, visible_room.size.y), Color.BLACK)


func draw_room_state(index: int) -> void:
	var room := room_rect(index)
	if not game.is_room_open(index):
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
	for task in TASK_COUNT:
		if game.task_count(index, task) > 0:
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
	var ping := pos + Vector2(0, -12)
	var selected: bool = game.target.x == index and game.target.y == task
	draw_set_transform(ping)
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


func worker_frame() -> int:
	var phase := int(game.elapsed * 8.0) % 2 if game.walking else 0
	return phase * 4 + game.facing


func draw_worker() -> void:
	var pos: Vector2 = game.player
	var frame := worker_frame()
	var region := Rect2(Vector2(frame % 4, frame >> 2) * FRAME, FRAME)
	actors.draw_set_transform(pos, 0, Vector2(1, 0.52))
	actors.draw_circle(Vector2(0, 3), 13, Color(0.10, 0.07, 0.05, 0.52))
	actors.draw_set_transform(pos)
	actors.draw_texture_rect_region(WORKER, Rect2(-31, -44, 62, 62), region)
	actors.draw_set_transform(Vector2.ZERO)


func draw_ghost() -> void:
	var pos: Vector2 = game.ghost_position + Vector2(sin(game.elapsed * 5.0) * 9, sin(game.elapsed * 6.0) * 7)
	var opacity: float = clampf(game.ghost_time, 0.0, 1.0)
	actors.draw_set_transform(pos)
	actors.draw_circle(Vector2.ZERO, 28, Color(0.68, 0.71, 0.52, opacity * 0.17))
	actors.draw_texture_rect(JINN, Rect2(-44, -61, 88, 88), false, Color(1, 1, 0.91, opacity * 0.89))
	actors.draw_set_transform(Vector2.ZERO)


func draw_plate(pos: Vector2, value: String, width: float, color: Color) -> void:
	var rect := Rect2(pos, Vector2(width, 16))
	draw_rect(rect, SHADOW)
	draw_rect(rect, color.darkened(0.28), false)
	var text_width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(FONT, pos + Vector2((width - text_width) / 2, 12), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
