extends Node2D

const Rules = preload("res://game/settings.gd")
const MAP_SIZE := Vector2(902, 566)
const START := Vector2(458, 315)
const DESK := Vector2(458, 264)
const ROOM_NUMBERS := [101, 102, 103, 104, 105, 106]
const ROOM_RECTS := [
	Rect2(21, 23, 274, 190), Rect2(314, 23, 274, 190), Rect2(607, 23, 274, 190),
	Rect2(21, 348, 274, 190), Rect2(314, 348, 274, 190), Rect2(607, 348, 274, 190),
]
const SLOT_CENTERS := [Vector2(60, 55), Vector2(211, 55), Vector2(60, 100), Vector2(211, 100), Vector2(60, 149), Vector2(211, 149)]
const FURNITURE_DRAW_SIZE := [103.0, 94.0, 69.0, 99.0, 54.0, 93.0, 83.0]
const GOLD := Color("#e5b874")
const READY := Color("#c6d49a")
const SHADOW := Color("#291d16")
const FONT = preload("res://assets/Arabic.ttf")
const HOTEL = preload("res://assets/hotel-floor.png")
const WORKER = preload("res://assets/worker.png")
const JINN = preload("res://assets/jinn.png")
const FURNITURE = preload("res://assets/furniture.png")
const GUESTS = preload("res://assets/guests.png")
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
	var room := room_at(game.player)
	if not game.business.is_open(room):
		room = -1
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
	if not is_equal_approx(scale.x, next_zoom):
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


static func room_at(point: Vector2) -> int:
	for index in ROOM_RECTS.size():
		if ROOM_RECTS[index].has_point(point):
			return index
	return -1


static func door(index: int) -> Vector2:
	var room := room_rect(index)
	return Vector2(room.get_center().x, room.end.y if index < 3 else room.position.y)


static func slot_center(index: int, slot: int) -> Vector2:
	if slot < 0 or slot >= SLOT_CENTERS.size():
		return room_rect(index).get_center()
	return room_rect(index).position + Vector2(SLOT_CENTERS[slot])


static func furniture_bounds(index: int, slot: int, item: int) -> Rect2:
	var kind := Rules.item_kind(item)
	if kind < 0:
		return Rect2()
	var footprint: Vector2 = Rules.ITEM_FOOTPRINTS[kind]
	return Rect2(slot_center(index, slot) - footprint * 0.5, footprint)


static func floor_contains(point: Vector2, business: RefCounted) -> bool:
	if not point.is_finite() or not is_instance_valid(business):
		return false
	if Rect2(24, 219, 846, 123).has_point(point):
		return not Rect2(402, 244, 112, 36).grow(4).has_point(point)
	for index in ROOM_RECTS.size():
		if not business.is_open(index):
			continue
		var room := room_rect(index)
		if room.grow(-10).has_point(point):
			for slot in Rules.SLOT_COUNT:
				var footprint := furniture_bounds(index, slot, business.slot_item(index, slot))
				if footprint.has_area() and footprint.grow(4).has_point(point):
					return false
			return true
		if Rect2(door(index) - Vector2(26, 20), Vector2(52, 40)).has_point(point):
			return true
	return false


func _draw() -> void:
	draw_texture_rect(HOTEL, Rect2(Vector2.ZERO, MAP_SIZE), false)
	if not is_instance_valid(game):
		return
	var business: RefCounted = game.business
	if not is_instance_valid(business):
		return
	for index in ROOM_RECTS.size():
		draw_room_state(index)
	draw_plate(Vector2(416, 222), "الاستقبال", 84, GOLD)
	for index in business.waiting.size():
		draw_guest(Vector2(510 + index * 31, 311), business.waiting[index].look)
	if business.employee:
		var position_in_hotel := Vector2(369, 309)
		if business.is_open(business.cleaner_room):
			position_in_hotel = room_rect(business.cleaner_room).get_center() + Vector2(0, 35)
		draw_texture_rect_region(WORKER, Rect2(position_in_hotel - Vector2(24, 33), Vector2(48, 48)), Rect2(Vector2.ZERO, FRAME), Color("#bbcb92"))


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
	var business: RefCounted = game.business
	if not business.is_open(index):
		var center := door(index)
		var closed := Rect2(center - Vector2(28, 7), Vector2(56, 14))
		draw_rect(closed, Color("#4d3829"))
		draw_rect(closed, Color("#826045"), false)
		return
	draw_plate(room.position + Vector2(52, 5), str(ROOM_NUMBERS[index]), 45, GOLD)
	var state: Dictionary = business.rooms[index]
	var center := room.get_center()
	if state.clean < Rules.CLEANING_THRESHOLD:
		for offset in [-11, 2, 14]:
			draw_circle(center + Vector2(offset, 47 + offset * 0.25), 3, Color("#b3996e"))
	if state.incident == Rules.Task.LEAK:
		draw_set_transform(center + Vector2(0, 37), 0.0, Vector2(1.65, 0.62))
		draw_circle(Vector2.ZERO, 12, Color(0.26, 0.56, 0.58, 0.78))
		draw_set_transform(Vector2.ZERO)
	for slot in Rules.SLOT_COUNT:
		var item: int = business.slot_item(index, slot)
		var spot := slot_center(index, slot)
		if item < 1:
			draw_rect(Rect2(spot - Vector2(29, 17), Vector2(58, 34)), Color(0.93, 0.76, 0.57, 0.18), false, 1)
			continue
		var item_size: float = FURNITURE_DRAW_SIZE[Rules.item_kind(item)]
		var tile := item - 1
		var region := Rect2(Vector2(tile % 4, tile >> 2) * FRAME, FRAME)
		var broken: bool = business.broken_at(index, slot)
		draw_texture_rect_region(FURNITURE, Rect2(spot - Vector2.ONE * item_size * 0.5, Vector2.ONE * item_size), region, Color("#d4987c") if broken else Color.WHITE)
		if broken:
			draw_line(spot + Vector2(-8, -3), spot + Vector2(4, 0), Color("#e28f70"), 2)
			draw_line(spot + Vector2(4, 0), spot + Vector2(-2, 9), Color("#e28f70"), 2)
	if not state.guest.is_empty():
		draw_guest(center + Vector2(0, -27), state.guest.look)
		if state.request >= 0 or state.incident >= 0:
			draw_circle(center + Vector2(11, -57), 5, GOLD)


func draw_guest(at: Vector2, look: int) -> void:
	var source := Rect2(Vector2(clampi(look, 0, 3), 0) * FRAME, FRAME)
	draw_texture_rect_region(GUESTS, Rect2(at - Vector2(25, 34), Vector2(50, 50)), source)


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
