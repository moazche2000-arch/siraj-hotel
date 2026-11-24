extends Node2D

const World = preload("res://game/world.gd")
const Interface = preload("res://game/interface.gd")
const Sound = preload("res://game/sound.gd")
const Updates = preload("res://startup/content_updater.gd")
const ACTIVE_COUNTS := [2, 3, 4, 5, 6]
const SHIFT_NAMES := ["أول وردية", "أصوات بالممر", "آخر ليلة للمدير", "المفتاح صار لك", "الجناح السادس"]
const TASK_NAMES := ["كنس الأرض", "مسح الأرض", "تغيير الشراشف", "إصلاح الأثاث"]
const WAGES := [45, 65, 90]
const SAVE_PATH := "user://hotel-%d.json"
const UPGRADE_NAMES := ["عربة تنظيف أسرع", "أقفال تحمي الأثاث", "تجهيزات للضيوف"]
const UPGRADE_COSTS := [140, 210, 300]
const NO_POINTER := -2
const MOUSE_POINTER := -1
const STICK_DEAD_ZONE := 10.0
const STICK_RADIUS := 53.0
const WALK_SPEED := 122.0

var world: Node2D
var ui: Control
var sound: Node
var player := World.START
var target := Vector2i(-1, -1)
var facing := 0
var walking := false
var elapsed := 0.0
var rooms: Array = []
var active_rooms := 2
var shift := 1
var money := 0
var total_profit := 0
var upgrades := [false, false, false]
var task_total := 0
var haunt_timer := 0.0
var haunt_count := 0
var haunt_limit := 0
var haunt_flash := 0.0
var ghost_time := 0.0
var ghost_position := Vector2.ZERO
var sparks: Array[Dictionary] = []
var notice := ""
var notice_time := 0.0
var paused := true
var muted := false
var save_revision := 0
var has_save := false
var pointer := NO_POINTER
var gesture_origin := Vector2.ZERO
var walk_intent := Vector2.ZERO
var dragging := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	load_game()
	if not has_save:
		start_shift(1)
	world = World.new()
	world.game = self
	add_child(world)
	sound = Sound.new()
	add_child(sound)
	sound.set_muted(muted)
	ui = Interface.new()
	ui.game = self
	add_child(ui)
	ui.show_welcome()
	if get_tree().has_meta(Updates.BOOT_META):
		var revision: int = get_tree().get_meta(Updates.BOOT_META)
		get_tree().remove_meta(Updates.BOOT_META)
		get_tree().create_timer(1.0).timeout.connect(
			func(): Updates.confirm_startup(revision), CONNECT_ONE_SHOT
		)


func _process(delta: float) -> void:
	if ui.needs_rotation:
		return
	elapsed += delta
	world.queue_redraw()
	ui.animate(delta)
	if paused:
		return
	haunt_flash = move_toward(haunt_flash, 0.0, delta * 1.3)
	ghost_time = maxf(0.0, ghost_time - delta)
	notice_time = maxf(0.0, notice_time - delta)
	move_worker(delta)
	target = find_target()
	update_haunting(delta)
	update_sparks(delta)
	ui.refresh_live()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_gesture()


func _unhandled_input(event: InputEvent) -> void:
	if paused or ui.needs_rotation or pointer != NO_POINTER:
		return
	if event is InputEventScreenTouch and event.pressed:
		begin_gesture(event.index, event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			begin_gesture(MOUSE_POINTER, event.position)


func _input(event: InputEvent) -> void:
	if pointer == NO_POINTER or paused:
		return
	if event is InputEventScreenDrag and event.index == pointer:
		drag_gesture(event.position)
	elif event is InputEventScreenTouch and event.index == pointer and not event.pressed:
		end_gesture(event.canceled)
	elif event is InputEventMouseMotion and pointer == MOUSE_POINTER:
		drag_gesture(event.position)
	elif event is InputEventMouseButton and pointer == MOUSE_POINTER:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			end_gesture(false)


func begin_gesture(index: int, point: Vector2) -> void:
	if ui.blocks_gesture_at(point):
		return
	pointer = index
	gesture_origin = point
	walk_intent = Vector2.ZERO
	dragging = false


func drag_gesture(point: Vector2) -> void:
	var offset := point - gesture_origin
	var distance := offset.length()
	if distance <= STICK_DEAD_ZONE:
		walk_intent = Vector2.ZERO
		return
	dragging = true
	var direction := offset / distance
	if distance > STICK_RADIUS:
		gesture_origin = point - direction * STICK_RADIUS
	var strength := clampf((distance - STICK_DEAD_ZONE) / (STICK_RADIUS - STICK_DEAD_ZONE), 0.0, 1.0)
	walk_intent = direction * lerpf(0.32, 1.0, strength)


func end_gesture(canceled: bool) -> void:
	var tap := not dragging and not canceled
	clear_gesture()
	if tap:
		tap_interact()


func clear_gesture() -> void:
	pointer = NO_POINTER
	walk_intent = Vector2.ZERO
	dragging = false


func tap_interact() -> void:
	if paused or ui.needs_rotation:
		return
	target = find_target()
	if target == Vector2i(-2, -2):
		finish_shift()
	elif target.x >= 0:
		ui.show_chore(target)


func _unhandled_key_input(event: InputEvent) -> void:
	if ui.needs_rotation or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if ui.can_resume():
				resume()
			elif not paused:
				ui.show_pause()
		KEY_M:
			toggle_sound()
		KEY_U:
			if is_owner() and not paused:
				ui.show_shop()
		KEY_E, KEY_SPACE, KEY_ENTER:
			tap_interact()


func start_shift(number: int) -> void:
	shift = number
	active_rooms = ACTIVE_COUNTS[mini(shift - 1, ACTIVE_COUNTS.size() - 1)]
	rooms.clear()
	for index in 6:
		if index >= active_rooms:
			rooms.append([0, 0, 0, 0])
			continue
		var dirt := 2 if shift >= 4 and index % 3 == (shift - 4) % 3 else 1
		var spill := int(shift >= 2 or index == 0)
		var repair := int(shift >= 3 and index == (shift - 2) % active_rooms)
		rooms.append([dirt, spill, 1, repair])
	task_total = remaining_tasks()
	haunt_limit = mini(1 + shift / 2, 4) if shift >= 2 else 0
	haunt_count = 0
	haunt_timer = 13.0 if shift == 2 else 15.0
	haunt_flash = 0.0
	ghost_time = 0.0
	notice = ""
	notice_time = 0.0
	sparks.clear()
	player = World.START
	facing = 0
	reset_interaction()


func reset_interaction() -> void:
	target = Vector2i(-1, -1)
	clear_gesture()
	walking = false


func resume() -> void:
	paused = false
	reset_interaction()
	ui.close_dialog()
	sound.start_audio()
	if not has_save:
		save_game()
	ui.refresh()


func toggle_sound() -> void:
	muted = not muted
	sound.set_muted(muted)
	if has_save:
		save_game()
	ui.refresh()


func move_worker(delta: float) -> void:
	var horizontal := int(down(KEY_D) or down(KEY_RIGHT)) - int(down(KEY_A) or down(KEY_LEFT))
	var vertical := int(down(KEY_S) or down(KEY_DOWN)) - int(down(KEY_W) or down(KEY_UP))
	var direction := (Vector2(horizontal, vertical) + walk_intent).limit_length()
	var old := player
	apply_motion(direction / world.scale * WALK_SPEED * delta)
	walking = player.distance_squared_to(old) > 0.01
	if direction.length_squared() > 0.01:
		if absf(direction.x) > absf(direction.y):
			facing = 1 if direction.x > 0 else 3
		else:
			facing = 0 if direction.y > 0 else 2


func apply_motion(motion: Vector2) -> void:
	if motion.is_zero_approx():
		return
	var steps := ceili(motion.length() / 6.0)
	var step := motion / float(steps)
	for index in steps:
		move_step(step)


func move_step(step: Vector2) -> void:
	var along_x := Vector2(player.x + step.x, player.y)
	if World.floor_contains(along_x, active_rooms):
		player.x = along_x.x
	var along_y := Vector2(player.x, player.y + step.y)
	if World.floor_contains(along_y, active_rooms):
		player.y = along_y.y


func down(code: Key) -> bool:
	return Input.is_physical_key_pressed(code)


func find_target() -> Vector2i:
	if all_done() and player.distance_to(World.DESK + Vector2(0, 33)) < 48:
		return Vector2i(-2, -2)
	var nearest := Vector2i(-1, -1)
	var distance := 37.0
	for index in active_rooms:
		if not World.room_rect(index).grow(-2).has_point(player):
			continue
		for task in 4:
			if rooms[index][task] < 1:
				continue
			var candidate := player.distance_to(World.station(index, task))
			if candidate < distance:
				distance = candidate
				nearest = Vector2i(index, task)
	return nearest


func complete_task(work: Vector2i) -> void:
	rooms[work.x][work.y] -= 1
	spawn_sparks(World.station(work.x, work.y), World.TASK_COLORS[work.y])
	if room_done(work.x):
		sound.play_cue("room")
		if all_done():
			announce("كل الغرف جاهزة. ارجع للاستقبال لإنهاء الوردية.", 6.0)
		else:
			announce("غرفة %d جاهزة للضيوف." % World.ROOM_NUMBERS[work.x], 3.0)
	else:
		sound.play_cue("work")
		announce("أنجزت مهمة: %s." % TASK_NAMES[work.y], 2.4)
	save_game()
	resume()


func remaining_tasks() -> int:
	var total := 0
	for index in active_rooms:
		for count in rooms[index]:
			total += count
	return total


func room_done(index: int) -> bool:
	return rooms[index] == [0, 0, 0, 0]


func clean_room_count() -> int:
	var total := 0
	for index in active_rooms:
		total += int(room_done(index))
	return total


func all_done() -> bool:
	return remaining_tasks() == 0


func update_haunting(delta: float) -> void:
	if haunt_count >= haunt_limit or all_done():
		return
	haunt_timer -= delta
	if haunt_timer <= 0.0:
		trigger_haunt()


func trigger_haunt() -> void:
	var index := rng.randi_range(0, active_rooms - 1)
	var current_room := -1
	for candidate in active_rooms:
		if World.room_rect(candidate).has_point(player):
			current_room = candidate
	if index == current_room:
		index = (index + 1) % active_rooms
	var task := 3 if haunt_count % 2 == 0 and not upgrades[1] else rng.randi_range(0, 2)
	if task == 3 and rooms[index][3] > 0:
		task = 0
	rooms[index][task] += 1
	task_total += 1
	haunt_count += 1
	haunt_timer = rng.randf_range(22.0, 34.0)
	haunt_flash = 1.0
	ghost_time = 3.4
	ghost_position = World.station(index, task) + Vector2(15, 4)
	spawn_sparks(ghost_position, Color("#f1a3cf"))
	var messages := ["بعثر الجن التراب", "سكب الجن الماء", "مزّق الجن الشراشف", "كسر الجن قطعة من الأثاث"]
	announce("%s في غرفة %d!" % [messages[task], World.ROOM_NUMBERS[index]], 6.5)
	sound.play_cue("haunt")
	save_game()
	ui.refresh()


func spawn_sparks(point: Vector2, tint: Color) -> void:
	for index in 9:
		var direction := Vector2.from_angle(float(index) * TAU / 9.0)
		sparks.append({"pos": point, "velocity": direction * rng.randf_range(24.0, 65.0), "color": tint, "life": rng.randf_range(0.35, 0.78)})


func update_sparks(delta: float) -> void:
	for index in range(sparks.size() - 1, -1, -1):
		var spark := sparks[index]
		spark.pos += spark.velocity * delta
		spark.life -= delta
		if spark.life <= 0.0:
			sparks.remove_at(index)


func is_owner() -> bool:
	return shift >= 4


func shift_name() -> String:
	return SHIFT_NAMES[shift - 1] if shift <= SHIFT_NAMES.size() else "ليلة جديدة في السراج"


func finish_shift() -> void:
	if paused or not all_done():
		return
	var finished := shift
	var proceeds := 0
	var costs := 0
	var earned := 0
	if is_owner():
		proceeds = active_rooms * (44 + (12 if upgrades[2] else 0)) + mini(shift - 4, 12) * 8
		costs = active_rooms * 8 + haunt_count * (3 if upgrades[1] else 6)
		earned = proceeds - costs
		total_profit += earned
	else:
		earned = WAGES[shift - 1]
	money += earned
	start_shift(shift + 1)
	save_game()
	sound.play_cue("shift")
	ui.refresh()
	ui.show_summary(finished, earned, proceeds, costs)


func buy_upgrade(index: int) -> void:
	if not is_owner() or upgrades[index] or money < UPGRADE_COSTS[index]:
		return
	money -= UPGRADE_COSTS[index]
	upgrades[index] = true
	save_game()
	sound.play_cue("room")
	ui.refresh()
	ui.show_shop()


func announce(message: String, duration: float) -> void:
	notice = message
	notice_time = duration


func save_game() -> void:
	var next_revision := save_revision + 1
	var file := FileAccess.open(SAVE_PATH % (next_revision % 2), FileAccess.WRITE)
	if file == null:
		announce("تعذّر حفظ التقدم على هذا الجهاز.", 6.0)
		return
	file.store_string(JSON.stringify({
		"revision": next_revision, "shift": shift, "money": money, "profit": total_profit,
		"upgrades": upgrades, "rooms": rooms, "task_total": task_total, "haunt_count": haunt_count,
		"muted": muted,
	}))
	file.flush()
	if file.get_error() != OK:
		announce("تعذّر حفظ التقدم على هذا الجهاز.", 6.0)
		return
	save_revision = next_revision
	has_save = true


func load_game() -> void:
	var latest: Dictionary = {}
	for slot in 2:
		var path := SAVE_PATH % slot
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var data: Variant = JSON.parse_string(file.get_as_text())
		if not data is Dictionary or not valid_save(data):
			continue
		if data.revision > latest.get("revision", 0):
			latest = data
	if latest.is_empty():
		return
	start_shift(maxi(1, int(latest.shift)))
	for index in 6:
		for task in 4:
			rooms[index][task] = maxi(0, int(latest.rooms[index][task]))
	for index in 3:
		upgrades[index] = bool(latest.upgrades[index])
	money = int(latest.money)
	total_profit = int(latest.profit)
	haunt_count = clampi(int(latest.haunt_count), 0, haunt_limit)
	task_total = maxi(int(latest.task_total), remaining_tasks())
	muted = bool(latest.muted)
	save_revision = int(latest.revision)
	has_save = true


func valid_save(data: Dictionary) -> bool:
	for field in ["revision", "shift", "money", "profit", "haunt_count", "task_total"]:
		if not is_save_number(data.get(field)):
			return false
	var saved_rooms: Variant = data.get("rooms")
	if not saved_rooms is Array or saved_rooms.size() != 6:
		return false
	for room: Variant in saved_rooms:
		if not room is Array or room.size() != 4 or not room.all(is_save_number):
			return false
	var saved_upgrades: Variant = data.get("upgrades")
	return saved_upgrades is Array and saved_upgrades.size() == 3 \
		and saved_upgrades.all(func(value): return value is bool) and data.get("muted") is bool


func is_save_number(value: Variant) -> bool:
	return (value is float or value is int) and absf(value) <= 2147483647 and int(value) == value
