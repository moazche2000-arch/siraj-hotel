extends Node2D

const MAP_SIZE := Vector2(902, 566)
const START := Vector2(458, 315)
const DESK := Vector2(458, 264)
const ROOM_NUMBERS := [101, 102, 103, 104, 105, 106]
const ROOM_COLORS := [
	Color("#78513a"), Color("#626341"), Color("#725637"),
	Color("#68533a"), Color("#6c4a3b"), Color("#686143"),
]
const TASK_COLORS := [Color("#f4bd75"), Color("#92c2b0"), Color("#f9e0aa"), Color("#ed9d81")]
const GOLD := Color("#e5b874")
const TEAL := Color("#b9ca93")
const MUTED := Color("#8e775c")
const WOOD := Color("#603b28")
const INLAY := Color("#be8b53")
const SHADOW := Color("#291d16")
const Arabic = preload("res://assets/Arabic.ttf")

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
	draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), SHADOW)
	draw_rect(Rect2(Vector2(2, 2), MAP_SIZE - Vector2(4, 4)), Color("#715536"), false, 2)
	draw_rect(Rect2(Vector2(6, 6), MAP_SIZE - Vector2(12, 12)), Color("#4a3523"), false)
	block(Rect2(16, 212, 861, 138), "#3c3024")
	for row in 5:
		for column in 33:
			var origin := Vector2(18 + column * 26, 215 + row * 26)
			var tile := Rect2(origin, Vector2(25, 25))
			var shade := 0.78 + float((column * 17 + row * 11) % 7) * 0.026
			draw_rect(tile, Color("#95714d").darkened(1.0 - shade))
			var fleck := Color("#5d4a34") if (column + row) % 2 == 0 else Color("#c4a170")
			draw_diamond(origin + Vector2(12, 12), Vector2(6, 6), fleck)
			draw_rect(Rect2(origin + Vector2(1, 1), Vector2(23, 23)), Color("#b39164"), false)
	runner(Rect2(30, 282, 842, 40), Color("#773c2c"))
	block(Rect2(16, 214, 861, 5), "#47301f")
	block(Rect2(16, 342, 861, 6), "#47301f")
	for x in range(27, 880, 15):
		draw_diamond(Vector2(x, 13), Vector2(4, 3), Color("#815d3d"))
		draw_diamond(Vector2(x, 551), Vector2(4, 3), Color("#815d3d"))
	for index in 6:
		draw_room(index)
	draw_reception()
	if game.haunt_flash > 0.0:
		var flash: float = game.haunt_flash
		draw_rect(Rect2(Vector2.ZERO, MAP_SIZE), Color(0.57, 0.28, 0.2, flash * 0.13))
		draw_rect(Rect2(Vector2(3, 3), MAP_SIZE - Vector2(6, 6)), Color(0.94, 0.55, 0.35, flash * 0.7), false, 3.0)
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
	draw_rect(room.grow(3), Color("#17120e"))
	draw_rect(room, Color("#a77c51"))
	var inside := room.grow(-5)
	draw_rect(inside, color.darkened(0.3))
	for row in 9:
		for column in 8:
			var variation := float((column * 7 + row * 13 + index * 19) % 9) * 0.023
			var tile := Rect2(inside.position + Vector2(column * 33, row * 20), Vector2(32, 19))
			draw_rect(tile, color.darkened(0.06 + variation))
			if (column + 2 * row + index) % 3 == 0:
				draw_line(tile.position + Vector2(4, 11), tile.position + Vector2(26, 11), color.lightened(0.08))
	draw_rect(Rect2(room.position, Vector2(room.size.x, 35)), Color("#b78d62"))
	draw_rect(Rect2(room.position + Vector2(0, 27), Vector2(room.size.x, 9)), WOOD)
	draw_line(room.position + Vector2(0, 27), room.position + Vector2(room.size.x, 27), INLAY.lightened(0.25), 2.0)
	for x in range(8, 270, 14):
		var crest := room.position + Vector2(x, 22)
		draw_diamond(crest, Vector2(3, 3), Color("#79583c"))
		draw_rect(Rect2(crest - Vector2(1, 1), Vector2(2, 2)), Color("#e0b882"))
	var center := door(index)
	var door_color := Color("#92744c") if active else Color("#4c3325")
	draw_rect(Rect2(center - Vector2(29, 9), Vector2(58, 18)), door_color)
	draw_rect(Rect2(center - Vector2(29, 9), Vector2(58, 18)), INLAY if active else MUTED.darkened(0.45), false, 2)
	for offset in [-29, 25]:
		draw_rect(Rect2(center + Vector2(offset, -12), Vector2(5, 24)), WOOD)
	if not active:
		for offset in range(-23, 24, 7):
			draw_line(center + Vector2(offset, -6), center + Vector2(offset, 6), Color("#79583f"))
	var rug_y := 110.0 if index < 3 else 60.0
	var rug_color := Color("#74443b") if index % 2 == 0 else Color("#4d5d45")
	runner(Rect2(room.position + Vector2(110, rug_y), Vector2(93, 54)), rug_color)
	draw_bed(index)
	draw_cabinet(index)
	draw_plant(room.position + Vector2(249, 146 if index < 3 else 104))
	draw_window(room.position + Vector2(139, 42))
	for offset in [29, 244]:
		draw_sconce(room.position + Vector2(offset, 42), active)
	if not active:
		draw_rect(room, Color(0.09, 0.066, 0.05, 0.60))
	num_plate(room.position + Vector2(55, 4), str(ROOM_NUMBERS[index]), active)
	if not active:
		return
	var tasks: Array = game.rooms[index]
	for task in 4:
		if tasks[task] > 0:
			draw_task(index, task)
	if game.room_done(index):
		var badge := room.position + Vector2(250, 15)
		draw_circle(badge, 7, Color("#404b2b"))
		draw_polyline(PackedVector2Array([badge + Vector2(-3, 0), badge + Vector2(-1, 2), badge + Vector2(3, -3)]), TEAL, 1.5)


func draw_window(pos: Vector2) -> void:
	draw_arch(Rect2(pos - Vector2(33, 27), Vector2(66, 48)), Color("#ce9e68"))
	draw_arch(Rect2(pos - Vector2(29, 24), Vector2(58, 43)), WOOD)
	draw_arch(Rect2(pos - Vector2(25, 20), Vector2(50, 36)), Color("#3b4a40"))
	for y in [-3, 3, 9]:
		draw_line(pos + Vector2(-23, y), pos + Vector2(23, y), Color("#8c704b"), 1)
	for x in [-16, -8, 0, 8, 16]:
		draw_line(pos + Vector2(x, -6), pos + Vector2(x, 16), Color("#96794e"), 1)
		draw_diamond(pos + Vector2(x, 3), Vector2(3, 3), Color("#c99a5e"))
	for x in [-33, 25]:
		draw_colored_polygon(PackedVector2Array([pos + Vector2(x, -5), pos + Vector2(x + 8, -5), pos + Vector2(x + 6, 17), pos + Vector2(x - 1, 17)]), Color("#80483a"))
	draw_rect(Rect2(pos + Vector2(-34, 17), Vector2(68, 5)), INLAY)
	draw_line(pos + Vector2(-34, 22), pos + Vector2(34, 22), SHADOW, 2)


func draw_arch(rect: Rect2, color: Color) -> void:
	var radius := rect.size.x * 0.5
	var rise := minf(radius * 0.68, rect.size.y * 0.7)
	var center := rect.position + Vector2(radius, rise)
	var points := PackedVector2Array()
	for side in range(9):
		var angle := PI + float(side) * PI / 8.0
		var arch_point := Vector2(cos(angle) * radius, sin(angle) * rise)
		points.append((center + arch_point).round())
	points.append(rect.end)
	points.append(Vector2(rect.position.x, rect.end.y))
	draw_colored_polygon(points, color)


func draw_sconce(pos: Vector2, lit: bool) -> void:
	if lit:
		draw_glow(pos, 42, Color("#eda853"), 0.11)
	draw_rect(Rect2(pos - Vector2(2, 3), Vector2(4, 11)), Color("#6a442d"))
	var shade := PackedVector2Array([pos + Vector2(-6, -9), pos + Vector2(6, -9), pos + Vector2(9, 2), pos + Vector2(-9, 2)])
	draw_colored_polygon(shade, GOLD if lit else MUTED)
	draw_line(pos + Vector2(-8, 3), pos + Vector2(8, 3), INLAY, 2)


func draw_bed(index: int) -> void:
	var pos := station(index, 2) + Vector2(-43, 5)
	draw_rect(Rect2(pos + Vector2(2, 5), Vector2(87, 44)), SHADOW)
	draw_rect(Rect2(pos, Vector2(86, 43)), WOOD)
	draw_rect(Rect2(pos + Vector2(4, 3), Vector2(76, 35)), Color("#c1a77e"))
	draw_rect(Rect2(pos + Vector2(8, 7), Vector2(21, 16)), Color("#e2dac2"))
	draw_rect(Rect2(pos + Vector2(8, 24), Vector2(21, 8)), Color("#cdc3aa"))
	var dirty: bool = game.rooms[index][2] > 0
	var linen := Color("#9b7559") if dirty else Color("#73805c")
	draw_rect(Rect2(pos + Vector2(32, 5), Vector2(45, 31)), linen)
	draw_rect(Rect2(pos + Vector2(34, 7), Vector2(41, 4)), linen.lightened(0.25))
	for x in [38, 48, 58, 68]:
		draw_diamond(pos + Vector2(x, 21), Vector2(3, 5), linen.lightened(0.36))
	draw_line(pos + Vector2(71, 9), pos + Vector2(71, 33), Color("#d2c09a"), 2)
	if dirty:
		draw_line(pos + Vector2(39, 25), pos + Vector2(52, 19), Color("#54414b"), 2)
		draw_line(pos + Vector2(50, 28), pos + Vector2(62, 28), Color("#54414b"), 2)
	draw_rect(Rect2(pos - Vector2(3, 1), Vector2(7, 44)), WOOD)
	draw_line(pos + Vector2(0, 2), pos + Vector2(0, 40), INLAY, 2)


func draw_cabinet(index: int) -> void:
	var pos := station(index, 3) + Vector2(-19, 14)
	draw_rect(Rect2(pos + Vector2(3, 4), Vector2(45, 25)), SHADOW)
	draw_rect(Rect2(pos, Vector2(44, 24)), Color("#6f4b3a"))
	draw_rect(Rect2(pos + Vector2(3, 2), Vector2(38, 5)), Color("#a77452"))
	draw_line(pos + Vector2(1, 13), pos + Vector2(42, 13), SHADOW)
	draw_rect(Rect2(pos + Vector2(18, 10), Vector2(8, 2)), GOLD.darkened(0.21))
	draw_rect(Rect2(pos + Vector2(18, 17), Vector2(8, 2)), GOLD.darkened(0.21))
	if game.rooms[index][3] > 0:
		draw_polyline(PackedVector2Array([pos + Vector2(28, 2), pos + Vector2(21, 9), pos + Vector2(29, 15), pos + Vector2(23, 24)]), TASK_COLORS[3], 2)
	else:
		var radio := Rect2(pos + Vector2(11, -6), Vector2(22, 10))
		draw_rect(radio, Color("#3d2f20"))
		draw_rect(radio.grow(-1), Color("#ae864f"))
		for offset in range(3, 15, 3):
			draw_line(radio.position + Vector2(offset, 2), radio.position + Vector2(offset, 7), Color("#624d36"))
		draw_circle(radio.position + Vector2(18, 5), 2, Color("#debb79"))


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
	draw_set_transform(ping, 0.0, Vector2(scale.y / scale.x, 1.0))
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


func draw_reception() -> void:
	var pos := DESK - Vector2(55, 18)
	draw_glow(DESK, 88, GOLD, 0.10)
	draw_rect(Rect2(pos + Vector2(3, 7), Vector2(110, 34)), SHADOW)
	draw_rect(Rect2(pos, Vector2(110, 31)), WOOD)
	draw_rect(Rect2(pos + Vector2(3, 2), Vector2(104, 16)), Color("#a2734b"))
	draw_line(pos + Vector2(3, 19), pos + Vector2(107, 19), INLAY, 2)
	for x in [10, 29, 48, 67, 86]:
		draw_rect(Rect2(pos + Vector2(x, 22), Vector2(14, 7)), Color("#906240"), false)
		draw_diamond(pos + Vector2(x + 7, 25), Vector2(3, 2), INLAY)
	draw_rect(Rect2(pos + Vector2(42, 5), Vector2(23, 11)), Color("#e2c798"))
	draw_line(pos + Vector2(53, 5), pos + Vector2(53, 15), Color("#876748"))
	for offset in [8, 11, 14]:
		draw_line(pos + Vector2(45, offset), pos + Vector2(50, offset), Color("#af885d"))
	draw_circle(pos + Vector2(88, 10), 5, GOLD)
	draw_line(pos + Vector2(81, 14), pos + Vector2(95, 14), GOLD.lightened(0.2), 2)
	draw_rect(Rect2(pos + Vector2(13, 8), Vector2(17, 8)), Color("#443221"))
	draw_line(pos + Vector2(12, 7), pos + Vector2(31, 7), Color("#67452d"), 3)
	draw_circle(pos + Vector2(21, 11), 2, INLAY)
	for plant_pos in [Vector2(52, 245), Vector2(850, 245), Vector2(47, 332), Vector2(854, 332)]:
		draw_plant(plant_pos)
	draw_arch(Rect2(414, 220, 88, 25), Color("#c89a62"))
	draw_rect(Rect2(417, 226, 82, 18), WOOD)
	num_plate(Vector2(420, 227), "الاستقبال", true, 76)
	for stamp in [Vector2(374, 250), Vector2(541, 250)]:
		draw_circle(stamp, 12, WOOD)
		draw_circle(stamp, 9, Color("#b48657"))
		draw_circle(stamp, 7, Color("#ddbf89"))
		draw_line(stamp, stamp + Vector2(0, -5), SHADOW)
		draw_line(stamp, stamp + Vector2(4, 1), SHADOW)
	if game.all_done():
		draw_circle(DESK + Vector2(0, 34), 10 + sin(game.elapsed * 5.0) * 3.0, TEAL, false, 2)


func draw_worker() -> void:
	var pos: Vector2 = game.player.round()
	if game.walking:
		pos.y += roundf(sin(game.elapsed * 13.0) * 2.0)
	draw_set_transform(pos, 0.0, Vector2(scale.y / scale.x, 1.0))
	pos = Vector2.ZERO
	draw_glow(pos, 45, Color("#eac78c"), 0.10)
	draw_rect(Rect2(pos + Vector2(-12, 4), Vector2(24, 8)), SHADOW)
	draw_rect(Rect2(pos - Vector2(8, 0), Vector2(6, 10)), Color("#3f2c20"))
	draw_rect(Rect2(pos + Vector2(2, 0), Vector2(6, 10)), Color("#3f2c20"))
	draw_rect(Rect2(pos - Vector2(11, 10), Vector2(22, 15)), Color("#854b36"))
	draw_rect(Rect2(pos - Vector2(6, 7), Vector2(12, 12)), Color("#e1c391"))
	draw_rect(Rect2(pos - Vector2(6, 16), Vector2(12, 9)), Color("#c78968"))
	draw_rect(Rect2(pos - Vector2(8, 19), Vector2(16, 5)), Color("#d5ab72"))
	draw_rect(Rect2(pos + Vector2(-3, -14), Vector2(2, 2)), Color("#493b42"))
	draw_rect(Rect2(pos + Vector2(3, -14), Vector2(2, 2)), Color("#493b42"))
	var tool_pos := pos + Vector2(13 if game.facing > 0 else -13, 0)
	draw_line(tool_pos + Vector2(-2, -12), tool_pos + Vector2(3, 9), Color("#d1a171"), 2)
	draw_rect(Rect2(tool_pos + Vector2(0, 5), Vector2(9, 6)), Color("#b47b53"))
	if game.task_progress > 0.0:
		draw_rect(Rect2(pos + Vector2(-17, -29), Vector2(34, 4)), SHADOW)
		draw_rect(Rect2(pos + Vector2(-17, -29), Vector2(34 * game.task_progress, 4)), TEAL)
	draw_set_transform(Vector2.ZERO)


func draw_ghost() -> void:
	var pos: Vector2 = game.ghost_position + Vector2(sin(game.elapsed * 5.0) * 9, sin(game.elapsed * 6.0) * 7)
	var opacity: float = clampf(game.ghost_time, 0.0, 1.0)
	draw_glow(pos, 69, Color("#b4b487"), 0.16 * opacity)
	var outline := PackedVector2Array([
		pos + Vector2(-25, 17), pos + Vector2(-20, -11), pos + Vector2(-13, -25), pos + Vector2(0, -31),
		pos + Vector2(14, -27), pos + Vector2(22, -14), pos + Vector2(25, 14), pos + Vector2(13, 10),
		pos + Vector2(5, 30), pos + Vector2(-4, 16), pos + Vector2(-14, 27), pos + Vector2(-16, 12),
	])
	draw_colored_polygon(outline, Color(0.78, 0.75, 0.58, 0.62 * opacity))
	for offset in [-7, 7]:
		draw_rect(Rect2(pos + Vector2(offset - 2, -13), Vector2(5, 5)), Color(1.0, 0.85, 0.77, opacity))


func runner(rect: Rect2, color: Color) -> void:
	draw_rect(rect, color.darkened(0.36))
	draw_rect(rect.grow(-2), INLAY)
	draw_rect(rect.grow(-4), color)
	draw_rect(rect.grow(-6), color.lightened(0.28), false)
	for offset in range(14, int(rect.size.x) - 12, 24):
		var center := rect.position + Vector2(offset, rect.size.y / 2.0)
		draw_diamond(center, Vector2(10, 11), color.lightened(0.28))
		draw_diamond(center, Vector2(7, 8), color.darkened(0.18))
		draw_diamond(center, Vector2(3, 3), INLAY)
	for offset in range(3, int(rect.size.x) - 2, 6):
		draw_rect(Rect2(rect.position + Vector2(offset, 1), Vector2(2, 3)), Color("#bc975f"))
		draw_rect(Rect2(rect.position + Vector2(offset, rect.size.y - 4), Vector2(2, 3)), Color("#bc975f"))


func draw_diamond(pos: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array([pos - Vector2(radius.x, 0), pos - Vector2(0, radius.y), pos + Vector2(radius.x, 0), pos + Vector2(0, radius.y)])
	draw_colored_polygon(points, color)


func draw_plant(pos: Vector2) -> void:
	draw_rect(Rect2(pos - Vector2(6, 0), Vector2(12, 9)), Color("#714a3b"))
	draw_rect(Rect2(pos - Vector2(7, 2), Vector2(14, 3)), Color("#a17152"))
	draw_circle(pos - Vector2(0, 10), 7, Color("#53613d"))
	draw_circle(pos - Vector2(6, 6), 5, Color("#74774a"))
	draw_circle(pos + Vector2(5, -7), 5, Color("#858451"))


func num_plate(pos: Vector2, value: String, lit: bool, width: float = 54) -> void:
	draw_rect(Rect2(pos, Vector2(width, 15)), SHADOW)
	draw_rect(Rect2(pos, Vector2(width, 15)), INLAY if lit else MUTED.darkened(0.3), false)
	var font := Arabic
	var size := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
	draw_string(font, pos + Vector2((width - size.x) / 2.0, 11), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, GOLD if lit else MUTED)


func draw_glow(pos: Vector2, radius: float, color: Color, strength: float) -> void:
	for layer in range(7, 0, -1):
		var tint := color
		tint.a = strength * (1.0 - float(layer) / 9.0)
		draw_circle(pos, radius * float(layer) / 7.0, tint)


func block(rect: Rect2, color: String) -> void:
	draw_rect(rect, Color(color))
