extends Node2D

const Rules = preload("res://game/settings.gd")
const MAP_SIZE := Vector2(902, 566)
const START := Vector2(329, 276)
const DESK := Vector2(458, 264)
const CORRIDOR := -1
const RECEPTION := -2
const CORRIDOR_RECT := Rect2(21, 213, 860, 135)
const RECEPTION_RECT := Rect2(376, 220, 178, 96)
const AT_RECEPTION := Rect2(392, 275, 134, 60)
const CORRIDOR_SECTIONS := [
	Rect2(21, 213, 860, 7), Rect2(21, 220, 355, 96),
	Rect2(554, 220, 327, 96), Rect2(21, 316, 860, 32),
]
const DUST_OFFSETS := [-11, 2, 14]
const ROOM_NUMBERS := [101, 102, 103, 104, 105, 106]
const ROOM_RECTS := [
	Rect2(21, 23, 274, 190), Rect2(314, 23, 274, 190), Rect2(607, 23, 274, 190),
	Rect2(21, 348, 274, 190), Rect2(314, 348, 274, 190), Rect2(607, 348, 274, 190),
]
const SLOT_CENTERS := [Vector2(60, 55), Vector2(211, 55), Vector2(60, 100), Vector2(211, 100), Vector2(60, 149), Vector2(211, 149)]
const FURNITURE_DRAW_SIZE := [103.0, 94.0, 69.0, 99.0, 54.0, 93.0, 83.0]
const GOLD := Color("#e5b874")
const SHADOW := Color("#291d16")
const FONT = preload("res://assets/Arabic.ttf")
const HOTEL = preload("res://assets/hotel-floor.png")
const WORKER = preload("res://assets/worker.png")
const JINN = preload("res://assets/jinn.png")
const FURNITURE = preload("res://assets/furniture.png")
const GUESTS = preload("res://assets/guests.png")
const FRAME := Vector2(128, 128)

var game: Node2D
var view_size := Vector2.ZERO
var actors := Node2D.new()
var last_actor_position := Vector2.INF
var last_actor_frame := -1
var current_region := CORRIDOR
var region_bounds := CORRIDOR_RECT
var fade_elapsed := Rules.CAMERA_FADE_SECONDS


func _ready() -> void:
	actors.draw.connect(draw_actors)
	add_child(actors)


func configure_camera(view: Vector2) -> void:
	if not view.is_finite() or view.x <= 0.0 or view.y <= 0.0:
		push_warning("Camera ignored an invalid viewport size.")
		return
	view_size = view
	follow_player(0.0, true)


func follow_player(delta: float, snap: bool = false) -> void:
	if view_size == Vector2.ZERO or not is_instance_valid(game) or not game.player.is_finite():
		return
	var requested := region_at(game.player, game.business)
	var changed := false
	var duration := maxf(Rules.CAMERA_FADE_SECONDS, 0.02)
	if snap:
		changed = activate_region(requested)
		fade_elapsed = duration
		set_fade(0.0)
	else:
		if requested != current_region and fade_elapsed >= duration:
			fade_elapsed = 0.0
		if fade_elapsed < duration:
			var previous := fade_elapsed
			fade_elapsed = minf(fade_elapsed + maxf(delta, 0.0), duration)
			var middle := duration * 0.5
			if previous < middle and fade_elapsed >= middle:
				changed = activate_region(requested)
			set_fade(1.0 if changed else 1.0 - absf(fade_elapsed / middle - 1.0))

	var zoom := maxf(0.25, Rules.CAMERA_ZOOM)
	if current_region != CORRIDOR:
		var inset := (view_size - Vector2.ONE * Rules.CAMERA_ROOM_MARGIN * 2.0).max(Vector2.ONE)
		zoom = minf(zoom * Rules.ROOM_CAMERA_MULTIPLIER, minf(inset.x / region_bounds.size.x, inset.y / region_bounds.size.y))
	var player_offset: Vector2 = view_size * 0.5 - game.player * zoom
	var desired := clamp_camera(player_offset, zoom)
	var next_position := desired
	if not (snap or changed) and position.distance_squared_to(desired) >= 0.12:
		next_position = clamp_camera(position.lerp(desired, 1.0 - exp(-Rules.CAMERA_FOLLOW_SPEED * maxf(delta, 0.0))), zoom)
	if not is_equal_approx(scale.x, zoom):
		scale = Vector2.ONE * zoom
	if position != next_position:
		position = next_position


func activate_region(region: int) -> bool:
	if current_region == region:
		return false
	current_region = region
	region_bounds = rect_for_region(region)
	queue_redraw()
	actors.queue_redraw()
	return true


func set_fade(alpha: float) -> void:
	if is_instance_valid(game.map_fade):
		game.map_fade.visible = alpha > 0.0
		if alpha > 0.0:
			game.map_fade.color = Color(0.06, 0.04, 0.03, clampf(alpha, 0.0, 1.0))


func clamp_camera(offset: Vector2, zoom: float) -> Vector2:
	var high := -region_bounds.position * zoom
	var low := view_size - region_bounds.end * zoom
	return Vector2(
		clampf(offset.x, low.x, high.x) if low.x <= high.x else (low.x + high.x) * 0.5,
		clampf(offset.y, low.y, high.y) if low.y <= high.y else (low.y + high.y) * 0.5,
	)


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


static func region_at(point: Vector2, business: RefCounted) -> int:
	if point.is_finite() and is_instance_valid(business):
		var room := room_at(point)
		if business.is_open(room):
			return room
		if RECEPTION_RECT.has_point(point):
			return RECEPTION
	return CORRIDOR


static func rect_for_region(region: int) -> Rect2:
	if region == RECEPTION:
		return RECEPTION_RECT
	var room := room_rect(region)
	return room if room.has_area() else CORRIDOR_RECT


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
	if not is_instance_valid(game):
		return
	var business: RefCounted = game.business
	if not is_instance_valid(business):
		return
	if current_region == CORRIDOR:
		draw_corridor(business)
	else:
		draw_floor_region(region_bounds)
		if current_region == RECEPTION:
			draw_plate(DESK - Vector2(43, 40), "الاستقبال", 86, GOLD)
			for index in business.waiting.size():
				draw_guest(Vector2(408 + index * 49, 301), business.waiting[index].look)
		elif business.is_open(current_region):
			draw_room_state(current_region)
	if business.employee:
		var position_in_hotel := Vector2(369, 309)
		if business.is_open(business.cleaner_room):
			position_in_hotel = room_rect(business.cleaner_room).get_center() + Vector2(0, 35)
		if contains_visible(position_in_hotel):
			draw_cropped_sprite(self, WORKER, Rect2(position_in_hotel - Vector2(24, 33), Vector2(48, 48)), Rect2(Vector2.ZERO, FRAME), Color("#bbcb92"))


func draw_floor_region(bounds: Rect2) -> void:
	var ratio := HOTEL.get_size() / MAP_SIZE
	draw_texture_rect_region(HOTEL, bounds, Rect2(bounds.position * ratio, bounds.size * ratio))


func draw_corridor(business: RefCounted) -> void:
	for section in CORRIDOR_SECTIONS:
		draw_floor_region(section)
	draw_plate(Vector2(288, 302), "الاستقبال  ‹", 84, GOLD)
	for index in ROOM_RECTS.size():
		var at := door(index)
		var door_label := Vector2(at.x - 19, at.y + (3 if index < 3 else -19))
		draw_plate(door_label, str(ROOM_NUMBERS[index]), 38, GOLD if business.is_open(index) else Color("#9d825b"))


func contains_visible(point: Vector2) -> bool:
	return region_bounds.has_point(point) and (current_region != CORRIDOR or not RECEPTION_RECT.has_point(point))


func draw_cropped_sprite(layer: CanvasItem, texture: Texture2D, target: Rect2, source: Rect2, tint: Color) -> void:
	if current_region == CORRIDOR:
		for section in CORRIDOR_SECTIONS:
			paint_sprite(layer, texture, target, source, tint, target.intersection(section))
		return
	paint_sprite(layer, texture, target, source, tint, target.intersection(region_bounds))


func paint_sprite(layer: CanvasItem, texture: Texture2D, target: Rect2, source: Rect2, tint: Color, visible: Rect2) -> void:
	if not visible.has_area():
		return
	var ratio := source.size / target.size
	var clipped_source := Rect2(source.position + (visible.position - target.position) * ratio, visible.size * ratio)
	layer.draw_texture_rect_region(texture, visible, clipped_source, tint)


func draw_actors() -> void:
	if not is_instance_valid(game):
		return
	if game.haunt_flash > 0.0 and contains_visible(game.ghost_position):
		var flash: float = game.haunt_flash
		actors.draw_rect(region_bounds, Color(0.57, 0.28, 0.2, flash * 0.13))
	if game.ghost_time > 0.0 and contains_visible(game.ghost_position):
		draw_ghost()
	if contains_visible(game.player):
		draw_worker()
	for index in game.spark_count:
		var at: Vector2 = game.spark_positions[index]
		if contains_visible(at):
			var tint: Color = game.spark_colors[index]
			tint.a = minf(game.spark_lifetimes[index] * 2.0, 1.0)
			actors.draw_circle(at, 2, tint)


func draw_room_state(index: int) -> void:
	var room := room_rect(index)
	var business: RefCounted = game.business
	draw_plate(room.position + Vector2(52, 5), str(ROOM_NUMBERS[index]), 45, GOLD)
	var state: Dictionary = business.rooms[index]
	var center := room.get_center()
	if state.clean < Rules.CLEANING_THRESHOLD and not business.is_clean_protected(index):
		for offset in DUST_OFFSETS:
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
		draw_cropped_sprite(self, FURNITURE, Rect2(spot - Vector2.ONE * item_size * 0.5, Vector2.ONE * item_size), region, Color("#d4987c") if broken else Color.WHITE)
		if broken:
			draw_line(spot + Vector2(-8, -3), spot + Vector2(4, 0), Color("#e28f70"), 2)
			draw_line(spot + Vector2(4, 0), spot + Vector2(-2, 9), Color("#e28f70"), 2)
	if not state.guest.is_empty():
		draw_guest(center + Vector2(0, -27), state.guest.look)
		if business.task_room == index:
			draw_circle(center + Vector2(11, -57), 5, GOLD)


func draw_guest(at: Vector2, look: int) -> void:
	var source := Rect2(Vector2(clampi(look, 0, 3), 0) * FRAME, FRAME)
	draw_cropped_sprite(self, GUESTS, Rect2(at - Vector2(25, 34), Vector2(50, 50)), source, Color.WHITE)


func worker_frame() -> int:
	var phase := int(game.elapsed * 8.0) % 2 if game.walking else 0
	return phase * 4 + game.facing


func draw_worker() -> void:
	var pos: Vector2 = game.player
	var frame := worker_frame()
	var region := Rect2(Vector2(frame % 4, frame >> 2) * FRAME, FRAME)
	if region_bounds.grow(-14).has_point(pos):
		actors.draw_set_transform(pos, 0, Vector2(1, 0.52))
		actors.draw_circle(Vector2(0, 3), 13, Color(0.10, 0.07, 0.05, 0.52))
		actors.draw_set_transform(Vector2.ZERO)
	draw_cropped_sprite(actors, WORKER, Rect2(pos - Vector2(31, 44), Vector2(62, 62)), region, Color.WHITE)


func draw_ghost() -> void:
	var pos: Vector2 = game.ghost_position + Vector2(sin(game.elapsed * 5.0) * 9, sin(game.elapsed * 6.0) * 7)
	var opacity: float = clampf(game.ghost_time, 0.0, 1.0)
	if region_bounds.grow(-28).has_point(pos):
		actors.draw_circle(pos, 28, Color(0.68, 0.71, 0.52, opacity * 0.17))
	draw_cropped_sprite(actors, JINN, Rect2(pos - Vector2(44, 61), Vector2(88, 88)), Rect2(Vector2.ZERO, JINN.get_size()), Color(1, 1, 0.91, opacity * 0.89))


func draw_plate(pos: Vector2, value: String, width: float, color: Color) -> void:
	var rect := Rect2(pos, Vector2(width, 16))
	draw_rect(rect, SHADOW)
	draw_rect(rect, color.darkened(0.28), false)
	var text_width := FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(FONT, pos + Vector2((width - text_width) / 2, 12), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
