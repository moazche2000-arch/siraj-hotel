extends Node2D

const START := Vector2(458, 315)
const DESK := Vector2(458, 264)
const ROOM_NUMBERS := [101, 102, 103, 104, 105, 106]
const ROOM_COLORS := [
	Color("#684f4a"), Color("#455b5c"), Color("#554c61"),
	Color("#62554b"), Color("#45565e"), Color("#634e54"),
]
const TASK_COLORS := [Color("#e4a363"), Color("#75d7ca"), Color("#f7df9b"), Color("#ed8bb2")]
const GOLD := Color("#ecc37c")
const TEAL := Color("#8fe2cf")
const MUTED := Color("#60737c")

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
		return not Rect2(405, 244, 104, 36).has_point(point)
	for index in active_rooms:
		var room := room_rect(index)
		if room.grow(-9).has_point(point):
			if Rect2(room.position + Vector2(29, 81 if index < 3 else 142), Vector2(67, 40)).has_point(point):
				return false
			return true
		if Rect2(door(index) - Vector2(28, 22), Vector2(56, 44)).has_point(point):
			return true
	return false


func _draw() -> void:
	block(Rect2(0, 0, 902, 566), "#101b25")
	draw_rect(Rect2(0, 0, 902, 566), Color("#35414b"), false)
	block(Rect2(18, 213, 860, 135), "#293540")
	for row in 6:
		for column in 39:
			var tile := Rect2(21 + column * 22, 216 + row * 22, 21, 21)
			var shade := 0.13 + float((column * 17 + row * 11) % 7) * 0.005
			draw_rect(tile, Color(shade, shade + 0.035, shade + 0.058))
	runner(Rect2(31, 282, 840, 39), Color("#673f4b"))
	block(Rect2(18, 214, 860, 5), "#171f2a")
	block(Rect2(18, 342, 860, 6), "#171f2a")
	for index in 6:
		draw_room(index)
	draw_reception()
	if game.haunt_flash > 0.0:
		var flash: float = game.haunt_flash
		draw_rect(Rect2(0, 0, 902, 566), Color(0.65, 0.15, 0.49, flash * 0.12))
		draw_rect(Rect2(3, 3, 895, 560), Color(1.0, 0.44, 0.68, flash * 0.7), false, 3.0)
	if game.ghost_time > 0.0:
		draw_ghost()
	draw_worker()
	for spark in game.sparks:
		var tint: Color = spark.color
		tint.a = minf(spark.life * 2.0, 1.0)
		draw_rect(Rect2(spark.pos, Vector2(3, 3)), tint)


func draw_room(index: int) -> void:
	var room := room_rect(index)
	var active: bool = index < game.active_rooms
	var color: Color = ROOM_COLORS[index]
	draw_rect(room.grow(3), Color("#0c131d"))
	draw_rect(room, Color("#5a5050"))
	var inside := Rect2(room.position + Vector2(5, 5), room.size - Vector2(10, 10))
	draw_rect(inside, color.darkened(0.52))
	for row in 8:
		for column in 12:
			var variation := float((column * 7 + row * 13 + index * 19) % 9) * 0.013
			var tile := Rect2(inside.position + Vector2(column * 22, row * 22), Vector2(21, 21))
			draw_rect(tile, color.darkened(0.37 + variation))
			if (column + 2 * row + index) % 4 == 0:
				draw_line(tile.position + Vector2(3, 11), tile.position + Vector2(14, 11), color.darkened(0.25))
	block(Rect2(room.position, Vector2(room.size.x, 26)), "#26232d")
	draw_line(room.position + Vector2(0, 24), room.position + Vector2(room.size.x, 24), Color("#7a6256"), 2.0)
	var center := door(index)
	var door_color := Color("#263f43") if active else Color("#171d25")
	draw_rect(Rect2(center - Vector2(29, 9), Vector2(58, 18)), door_color)
	draw_rect(Rect2(center - Vector2(29, 9), Vector2(58, 18)), Color("#83715f") if active else MUTED.darkened(0.45), false)
	if not active:
		draw_line(center - Vector2(21, 0), center + Vector2(21, 0), MUTED.darkened(0.25), 2.0)
	for offset in [25, 247]:
		var lamp := room.position + Vector2(offset, 20)
		if active:
			draw_glow(lamp, 44, Color("#d88e52"), 0.085)
		draw_rect(Rect2(lamp - Vector2(5, 2), Vector2(10, 6)), GOLD if active else MUTED)
	var rug_y := 110.0 if index < 3 else 60.0
	runner(Rect2(room.position + Vector2(111, rug_y), Vector2(83, 55)), color.lightened(0.09))
	draw_bed(index)
	draw_cabinet(index)
	draw_plant(room.position + Vector2(249, 146 if index < 3 else 104))
	draw_window(room.position + Vector2(139, 26))
	if not active:
		draw_rect(room, Color(0.03, 0.06, 0.1, 0.63))
	num_plate(room.position + Vector2(110, 5), str(ROOM_NUMBERS[index]), active)
	if not active:
		return
	var tasks: Array = game.rooms[index]
	for task in 4:
		if tasks[task] > 0:
			draw_task(index, task)
	if game.room_done(index):
		var badge := room.position + Vector2(250, 15)
		draw_circle(badge, 7, Color("#274640"))
		draw_polyline(PackedVector2Array([badge + Vector2(-3, 0), badge + Vector2(-1, 2), badge + Vector2(3, -3)]), TEAL, 1.5)


func draw_window(pos: Vector2) -> void:
	draw_rect(Rect2(pos - Vector2(31, 12), Vector2(62, 29)), Color("#1c202d"))
	draw_rect(Rect2(pos - Vector2(25, 9), Vector2(50, 19)), Color("#283f55"))
	draw_rect(Rect2(pos - Vector2(22, 6), Vector2(44, 13)), Color("#37526b"))
	draw_line(pos - Vector2(0, 8), pos + Vector2(0, 10), Color("#182433"), 3)
	draw_line(pos - Vector2(25, 0), pos + Vector2(25, 0), Color("#182433"), 2)
	for offset in [-30, 26]:
		draw_rect(Rect2(pos + Vector2(offset, -11), Vector2(5, 26)), Color("#875b61"))
	draw_line(pos + Vector2(-31, 13), pos + Vector2(31, 13), Color("#685550"), 3)


func draw_bed(index: int) -> void:
	var pos := station(index, 2) + Vector2(-43, 5)
	draw_rect(Rect2(pos + Vector2(2, 5), Vector2(87, 44)), Color("#1f2028"))
	draw_rect(Rect2(pos, Vector2(86, 43)), Color("#32292d"))
	draw_rect(Rect2(pos + Vector2(4, 3), Vector2(76, 35)), Color("#b3a798"))
	draw_rect(Rect2(pos + Vector2(8, 7), Vector2(21, 16)), Color("#e2dac2"))
	draw_rect(Rect2(pos + Vector2(8, 24), Vector2(21, 8)), Color("#cdc3aa"))
	var dirty: bool = game.rooms[index][2] > 0
	draw_rect(Rect2(pos + Vector2(32, 5), Vector2(45, 31)), Color("#7e686d") if dirty else Color("#587a78"))
	draw_rect(Rect2(pos + Vector2(34, 7), Vector2(41, 4)), Color("#b28a89") if dirty else Color("#8eaaa1"))
	draw_line(pos + Vector2(68, 9), pos + Vector2(68, 33), Color("#d2c5a2"), 2)
	if dirty:
		draw_line(pos + Vector2(39, 25), pos + Vector2(52, 19), Color("#54414b"), 2)
		draw_line(pos + Vector2(50, 28), pos + Vector2(62, 28), Color("#54414b"), 2)
	draw_rect(Rect2(pos - Vector2(3, 1), Vector2(7, 44)), Color("#513d38"))


func draw_cabinet(index: int) -> void:
	var pos := station(index, 3) + Vector2(-19, 14)
	draw_rect(Rect2(pos + Vector2(3, 4), Vector2(45, 25)), Color("#25232a"))
	draw_rect(Rect2(pos, Vector2(44, 24)), Color("#6f4b3a"))
	draw_rect(Rect2(pos + Vector2(3, 2), Vector2(38, 5)), Color("#a77452"))
	draw_line(pos + Vector2(1, 13), pos + Vector2(42, 13), Color("#3c3033"))
	draw_rect(Rect2(pos + Vector2(18, 10), Vector2(8, 2)), GOLD.darkened(0.21))
	draw_rect(Rect2(pos + Vector2(18, 17), Vector2(8, 2)), GOLD.darkened(0.21))
	if game.rooms[index][3] > 0:
		draw_polyline(PackedVector2Array([pos + Vector2(28, 2), pos + Vector2(21, 9), pos + Vector2(29, 15), pos + Vector2(23, 24)]), Color("#f29cb5"), 2)


func draw_task(index: int, task: int) -> void:
	var pos := station(index, task)
	var color: Color = TASK_COLORS[task]
	if task == 0:
		for offset in [Vector2(-6, 1), Vector2(8, 7), Vector2(1, -6)]:
			draw_rect(Rect2(pos + offset, Vector2(5, 4)), Color("#a87757"))
	elif task == 1:
		draw_set_transform(pos, 0, Vector2(1.65, 0.6))
		draw_circle(Vector2.ZERO, 12, Color("#3c6e72"))
		draw_circle(Vector2(-2, 0), 7, Color("#568e91"))
		draw_set_transform(Vector2.ZERO)
	var ping := pos + Vector2(0, -12 + sin(game.elapsed * 3.7 + index) * 2)
	var selected: bool = game.target.x == index and game.target.y == task
	draw_circle(ping, 14 if selected else 11, Color("#171c2a"))
	draw_circle(ping, 13 if selected else 10, color, false, 1.5)
	draw_string(ThemeDB.fallback_font, ping + Vector2(-3.7, 4.5), ["B", "M", "L", "R"][task], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)


func draw_reception() -> void:
	var pos := DESK - Vector2(55, 18)
	draw_glow(DESK, 90, GOLD, 0.07)
	draw_rect(Rect2(pos + Vector2(3, 7), Vector2(110, 34)), Color("#151922"))
	draw_rect(Rect2(pos, Vector2(110, 31)), Color("#654837"))
	draw_rect(Rect2(pos + Vector2(3, 2), Vector2(104, 16)), Color("#996c46"))
	draw_line(pos + Vector2(4, 19), pos + Vector2(106, 19), Color("#c08c5d"), 2)
	draw_rect(Rect2(pos + Vector2(25, 6), Vector2(18, 10)), Color("#e2c798"))
	draw_line(pos + Vector2(34, 6), pos + Vector2(34, 15), Color("#876748"))
	draw_circle(pos + Vector2(78, 11), 5, GOLD)
	draw_line(pos + Vector2(72, 14), pos + Vector2(84, 14), GOLD.lightened(0.2), 2)
	for plant_pos in [Vector2(52, 245), Vector2(850, 245), Vector2(47, 332), Vector2(854, 332)]:
		draw_plant(plant_pos)
	num_plate(Vector2(419, 225), "RECEPTION", true, 78)
	if game.all_done():
		draw_circle(DESK + Vector2(0, 34), 10 + sin(game.elapsed * 5.0) * 3.0, TEAL, false, 2)


func draw_worker() -> void:
	var pos: Vector2 = game.player.round()
	if game.walking:
		pos.y += roundf(sin(game.elapsed * 24.0) * 2.0)
	draw_glow(pos, 52, Color("#eac78c"), 0.07)
	draw_rect(Rect2(pos + Vector2(-12, 4), Vector2(24, 8)), Color("#141d25"))
	draw_rect(Rect2(pos - Vector2(8, 0), Vector2(6, 10)), Color("#243344"))
	draw_rect(Rect2(pos + Vector2(2, 0), Vector2(6, 10)), Color("#243344"))
	draw_rect(Rect2(pos - Vector2(10, 9), Vector2(20, 13)), Color("#4a9c90"))
	draw_rect(Rect2(pos - Vector2(5, 7), Vector2(10, 11)), Color("#a7c5ad"))
	draw_rect(Rect2(pos - Vector2(6, 16), Vector2(12, 9)), Color("#c78968"))
	draw_rect(Rect2(pos - Vector2(8, 19), Vector2(16, 5)), Color("#f4cd86"))
	draw_rect(Rect2(pos + Vector2(-3, -14), Vector2(2, 2)), Color("#493b42"))
	draw_rect(Rect2(pos + Vector2(3, -14), Vector2(2, 2)), Color("#493b42"))
	var tool_pos := pos + Vector2(13 if game.facing > 0 else -13, 0)
	draw_line(tool_pos + Vector2(-2, -12), tool_pos + Vector2(3, 9), Color("#d1a171"), 2)
	draw_rect(Rect2(tool_pos + Vector2(0, 5), Vector2(9, 6)), Color("#b47b53"))
	if game.task_progress > 0.0:
		draw_rect(Rect2(pos + Vector2(-17, -29), Vector2(34, 4)), Color("#181f2a"))
		draw_rect(Rect2(pos + Vector2(-17, -29), Vector2(34 * game.task_progress, 4)), TEAL)


func draw_ghost() -> void:
	var pos: Vector2 = game.ghost_position + Vector2(sin(game.elapsed * 5.0) * 9, sin(game.elapsed * 6.0) * 7)
	var opacity: float = clampf(game.ghost_time, 0.0, 1.0)
	draw_glow(pos, 69, Color("#e481c0"), 0.16 * opacity)
	var outline := PackedVector2Array([
		pos + Vector2(-25, 17), pos + Vector2(-20, -11), pos + Vector2(-13, -25), pos + Vector2(0, -31),
		pos + Vector2(14, -27), pos + Vector2(22, -14), pos + Vector2(25, 14), pos + Vector2(13, 10),
		pos + Vector2(5, 30), pos + Vector2(-4, 16), pos + Vector2(-14, 27), pos + Vector2(-16, 12),
	])
	draw_colored_polygon(outline, Color(0.7, 0.46, 0.74, 0.62 * opacity))
	for offset in [-7, 7]:
		draw_rect(Rect2(pos + Vector2(offset - 2, -13), Vector2(5, 5)), Color(1.0, 0.85, 0.77, opacity))


func runner(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color.darkened(0.24))
	draw_rect(rect.grow(-3), color)
	draw_rect(rect.grow(-5), color.lightened(0.22), false)
	for offset in range(13, int(rect.size.x) - 8, 23):
		var center := rect.position + Vector2(offset, rect.size.y / 2.0)
		var diamond := PackedVector2Array([center + Vector2(-7, 0), center + Vector2(0, -7), center + Vector2(7, 0), center + Vector2(0, 7), center + Vector2(-7, 0)])
		draw_polyline(diamond, color.lightened(0.18), 1.0)


func draw_plant(pos: Vector2) -> void:
	draw_rect(Rect2(pos - Vector2(6, 0), Vector2(12, 9)), Color("#714a3b"))
	draw_rect(Rect2(pos - Vector2(7, 2), Vector2(14, 3)), Color("#a17152"))
	draw_circle(pos - Vector2(0, 10), 7, Color("#42665b"))
	draw_circle(pos - Vector2(6, 6), 5, Color("#547363"))
	draw_circle(pos + Vector2(5, -7), 5, Color("#67836a"))


func num_plate(pos: Vector2, value: String, lit: bool, width: float = 54) -> void:
	draw_rect(Rect2(pos, Vector2(width, 15)), Color("#151b26"))
	draw_rect(Rect2(pos, Vector2(width, 15)), Color("#675649") if lit else Color("#293645"), false)
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(font, pos + Vector2((width - size.x) / 2.0, 11), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GOLD if lit else MUTED)


func draw_glow(pos: Vector2, radius: float, color: Color, strength: float) -> void:
	for layer in range(7, 0, -1):
		var tint := color
		tint.a = strength * (1.0 - float(layer) / 9.0)
		draw_circle(pos, radius * float(layer) / 7.0, tint)


func block(rect: Rect2, color: String) -> void:
	draw_rect(rect, Color(color))
