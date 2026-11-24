extends Node2D

const World = preload("res://game/world.gd")
const Interface = preload("res://game/interface.gd")
const Sound = preload("res://game/sound.gd")
const Updates = preload("res://startup/content_updater.gd")
const Saves = preload("res://game/save_state.gd")
const Diagnostics = preload("res://game/diagnostics.gd")
const ACTIVE_COUNTS := [2, 3, 4, 5, 6]
const SHIFT_NAMES := ["أول وردية", "أصوات بالممر", "آخر ليلة للمدير", "المفتاح صار لك", "الجناح السادس"]
const TASK_NAMES := ["كنس الأرض", "مسح الأرض", "تغيير الشراشف", "إصلاح الأثاث"]
const WAGES := [45, 65, 90]
const SAVE_PATH := Saves.PATH
const UPGRADE_NAMES := ["عربة تنظيف أسرع", "أقفال تحمي الأثاث", "تجهيزات للضيوف"]
const UPGRADE_COSTS := [140, 210, 300]
const NO_POINTER := -2
const MOUSE_POINTER := -1
const STICK_DEAD_ZONE := 10.0
const STICK_RADIUS := 53.0
const WALK_SPEED := 55.0
const MAX_STEP_DELTA := 0.1
const MAX_SPARKS := 27
const SPARKS_PER_EVENT := 9
const HAUNT_MESSAGES := ["بعثر الجن التراب", "سكب الجن الماء", "مزّق الجن الشراشف", "كسر الجن قطعة من الأثاث"]

var world: Node2D
var map_view: Control
var ui: Control
var sound: Node
var diagnostics: Logger
var initialized := false
var update_fault_reported := false
var backgrounded := false
var player := World.START
var target := Vector2i(-1, -1)
var last_target_position := Vector2.INF
var facing := 0
var walking := false
var elapsed := 0.0
var rooms: Array[Array] = []
var active_rooms := 2
var shift := 1
var money := 0
var total_profit := 0
var upgrades := [false, false, false]
var task_total := 0
var haunt_timer := 0.0
var haunt_count := 0
var haunt_marks := 0
var haunt_limit := 0
var haunt_flash := 0.0
var ghost_time := 0.0
var ghost_position := Vector2.ZERO
var spark_positions := PackedVector2Array()
var spark_velocities := PackedVector2Array()
var spark_colors := PackedColorArray()
var spark_lifetimes := PackedFloat32Array()
var spark_count := 0
var notice := ""
var notice_time := 0.0
var paused := true:
	set(value):
		paused = value
		if is_instance_valid(sound):
			sound.set_ambience_paused(value)
var muted := false
var save_revision := 0
var save_slot := 0
var has_save := false
var needs_save_migration := false
var read_only_save := false
var pointer := NO_POINTER
var gesture_origin := Vector2.ZERO
var walk_intent := Vector2.ZERO
var dragging := false
var input_generation := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	diagnostics = Diagnostics.install(get_tree())
	if OS.has_feature("android"):
		Engine.max_fps = 30
		OS.low_processor_usage_mode = true
		DisplayServer.screen_set_keep_on(false)
	rng.randomize()
	spark_positions.resize(MAX_SPARKS)
	spark_velocities.resize(MAX_SPARKS)
	spark_colors.resize(MAX_SPARKS)
	spark_lifetimes.resize(MAX_SPARKS)
	load_game()
	if not has_save:
		start_shift(1)
	world = World.new()
	world.game = self
	map_view = Control.new()
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_view.clip_contents = true
	add_child(map_view)
	map_view.add_child(world)
	sound = Sound.new()
	add_child(sound)
	sound.set_muted(muted)
	ui = Interface.new()
	ui.game = self
	add_child(ui)
	initialized = is_instance_valid(ui.hud)
	if not initialized:
		push_error("Hotel startup could not initialize the HUD.")
		return
	ui.show_welcome()
	if get_tree().has_meta(Updates.BOOT_META):
		var revision: int = get_tree().get_meta(Updates.BOOT_META)
		get_tree().remove_meta(Updates.BOOT_META)
		get_tree().create_timer(1.0).timeout.connect(
			func(): Updates.confirm_startup(revision), CONNECT_ONE_SHOT
		)


func _process(delta: float) -> void:
	if not initialized or paused or backgrounded:
		return
	if not is_instance_valid(world) or not is_instance_valid(ui) or not is_instance_valid(ui.hud):
		if not update_fault_reported:
			update_fault_reported = true
			push_error("Hotel update skipped because its world or interface is unavailable.")
		return
	if ui.needs_rotation or not is_finite(delta) or delta <= 0.0:
		return
	var step := minf(delta, MAX_STEP_DELTA)
	elapsed += step
	var previous_flash := haunt_flash
	var notice_visible := notice_time > 0.0
	var had_effects := has_world_effects()
	haunt_flash = move_toward(haunt_flash, 0.0, step * 1.3)
	ghost_time = maxf(0.0, ghost_time - step)
	notice_time = maxf(0.0, notice_time - step)
	move_worker(step)
	if player != last_target_position:
		last_target_position = player
		update_target()
	update_haunting(step)
	update_sparks(step)
	world.follow_player(step)
	world.update_actors(had_effects or has_world_effects())
	if previous_flash != haunt_flash:
		ui.update_flash()
	if notice_visible and notice_time <= 0.0:
		ui.refresh_live()


func has_world_effects() -> bool:
	return haunt_flash > 0.0 or ghost_time > 0.0 or spark_count > 0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			cancel_input()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_RESUMED:
			if OS.has_feature("android"):
				set_backgrounded(what == NOTIFICATION_APPLICATION_PAUSED)


func set_backgrounded(value: bool) -> void:
	backgrounded = value
	cancel_input()
	process_mode = PROCESS_MODE_DISABLED if value else PROCESS_MODE_INHERIT
	if is_instance_valid(sound):
		sound.set_backgrounded(value)
	if value and is_instance_valid(diagnostics):
		diagnostics.flush()


func can_play() -> bool:
	return initialized and not paused and not backgrounded and is_instance_valid(ui) and not ui.needs_rotation


func _unhandled_input(event: InputEvent) -> void:
	if not can_play() or pointer != NO_POINTER:
		return
	if event is InputEventScreenTouch and event.pressed:
		begin_gesture(event.index, event.position)
	elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			begin_gesture(MOUSE_POINTER, event.position)


func _input(event: InputEvent) -> void:
	if pointer == NO_POINTER or not can_play():
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
	if not can_play() or pointer != NO_POINTER or not point.is_finite() or ui.blocks_gesture_at(point):
		return
	pointer = index
	gesture_origin = point
	walk_intent = Vector2.ZERO
	dragging = false


func drag_gesture(point: Vector2) -> void:
	if not point.is_finite():
		cancel_input()
		return
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
	if pointer == NO_POINTER:
		return
	var tap := not dragging and not canceled
	clear_gesture()
	if tap:
		tap_after_release.call_deferred(input_generation)


func tap_after_release(generation: int) -> void:
	if generation == input_generation and pointer == NO_POINTER:
		tap_interact()


func clear_gesture() -> void:
	pointer = NO_POINTER
	walk_intent = Vector2.ZERO
	dragging = false


func cancel_input() -> void:
	input_generation += 1
	clear_gesture()
	if is_instance_valid(ui) and is_instance_valid(ui.chore_board):
		ui.chore_board.cancel_stroke()


func tap_interact() -> void:
	if not can_play():
		return
	update_target()
	if target == Vector2i(-2, -2):
		finish_shift()
	elif target.x >= 0:
		ui.show_chore(target)


func _unhandled_key_input(event: InputEvent) -> void:
	if not initialized or backgrounded or not is_instance_valid(ui) or ui.needs_rotation:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if ui.modal_kind == "diagnostics":
				ui.close_diagnostics()
			elif ui.can_resume():
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
	shift = maxi(1, number)
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
	haunt_marks = 0
	haunt_timer = 13.0 if shift == 2 else 15.0
	haunt_flash = 0.0
	ghost_time = 0.0
	notice = ""
	notice_time = 0.0
	spark_count = 0
	player = World.START
	facing = 0
	reset_interaction()
	if is_instance_valid(world):
		world.follow_player(0.0, true)
		world.queue_redraw()
		world.update_actors(true)


func reset_interaction() -> void:
	if target.x >= 0 and is_instance_valid(world):
		world.queue_redraw()
	target = Vector2i(-1, -1)
	last_target_position = Vector2.INF
	cancel_input()
	walking = false


func resume() -> void:
	if not initialized or not is_instance_valid(ui) or not is_instance_valid(sound):
		return
	reset_interaction()
	ui.close_dialog()
	paused = false
	sound.start_audio()
	if not has_save or needs_save_migration:
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
	apply_motion(direction * WALK_SPEED * minf(delta, MAX_STEP_DELTA))
	walking = player.distance_squared_to(old) > 0.01
	if direction.length_squared() > 0.01:
		if absf(direction.x) > absf(direction.y):
			facing = 1 if direction.x > 0 else 3
		else:
			facing = 0 if direction.y > 0 else 2


func apply_motion(motion: Vector2) -> void:
	if not motion.is_finite() or motion.is_zero_approx():
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


func update_target() -> void:
	var nearby := find_target()
	if nearby != target:
		target = nearby
		world.queue_redraw()
		ui.refresh_live()


func find_target() -> Vector2i:
	if all_done() and player.distance_to(World.DESK + Vector2(0, 33)) < 48:
		return Vector2i(-2, -2)
	var nearest := Vector2i(-1, -1)
	var distance := 37.0
	var index := World.room_at(player, active_rooms)
	if not is_room_open(index):
		return nearest
	for task in World.TASK_COUNT:
		if task_count(index, task) < 1 or not World.has_task_station(index, task):
			continue
		var candidate := player.distance_to(World.station(index, task))
		if candidate < distance:
			distance = candidate
			nearest = Vector2i(index, task)
	return nearest


func complete_task(work: Vector2i) -> void:
	if not initialized or not is_instance_valid(ui) or ui.modal_kind != "chore":
		return
	if task_count(work.x, work.y) < 1 or not World.has_task_station(work.x, work.y):
		push_warning("Ignored a chore completion for an unavailable station: %s" % work)
		resume()
		return
	rooms[work.x][work.y] -= 1
	world.queue_redraw()
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
	for index in mini(active_rooms, rooms.size()):
		for count in rooms[index]:
			total += count
	return total


func room_done(index: int) -> bool:
	if not is_room_open(index):
		return false
	for count in rooms[index]:
		if count > 0:
			return false
	return true


func is_room_open(index: int) -> bool:
	return index >= 0 and index < active_rooms and index < rooms.size() and rooms[index].size() == World.TASK_COUNT


func task_count(index: int, task: int) -> int:
	if not is_room_open(index) or task < 0 or task >= rooms[index].size():
		return 0
	return rooms[index][task]


func clean_room_count() -> int:
	var total := 0
	for index in active_rooms:
		total += int(room_done(index))
	return total


func all_done() -> bool:
	return remaining_tasks() == 0


func update_haunting(delta: float) -> void:
	if haunt_count >= haunt_limit or all_done() or ghost_time > 0.0:
		return
	haunt_timer -= delta
	if haunt_timer <= 0.0:
		trigger_haunt()


func trigger_haunt() -> void:
	if not can_play() or ghost_time > 0.0 or haunt_count >= haunt_limit or all_done():
		return
	haunt_timer = rng.randf_range(22.0, 34.0)
	var current_room := World.room_at(player, active_rooms)
	var work := Vector2i(-1, -1)
	if haunt_count % 2 == 0 and not upgrades[1]:
		work = choose_haunt(current_room, 3, 4)
	if work.x < 0:
		work = choose_haunt(current_room, 0, 3)
	if work.x < 0:
		return
	rooms[work.x][work.y] = 1
	haunt_marks |= haunt_bit(work.x, work.y)
	world.queue_redraw()
	task_total += 1
	haunt_count += 1
	haunt_flash = 1.0
	ghost_time = 3.4
	ghost_position = World.station(work.x, work.y) + Vector2(15, 4)
	spawn_sparks(ghost_position, Color("#f1a3cf"))
	announce("%s في غرفة %d!" % [HAUNT_MESSAGES[work.y], World.ROOM_NUMBERS[work.x]], 6.5)
	sound.play_cue("haunt")
	save_game()
	ui.refresh()


func choose_haunt(current_room: int, first_task: int, end_task: int) -> Vector2i:
	var chosen := Vector2i(-1, -1)
	var eligible := 0
	for index in mini(active_rooms, rooms.size()):
		if index == current_room or not is_room_open(index):
			continue
		for task in range(first_task, end_task):
			if task_count(index, task) != 0 or haunt_marks & haunt_bit(index, task):
				continue
			if not World.has_task_station(index, task):
				continue
			eligible += 1
			if rng.randi_range(1, eligible) == 1:
				chosen = Vector2i(index, task)
	return chosen


func haunt_bit(index: int, task: int) -> int:
	return 1 << (index * World.TASK_COUNT + task)


func spawn_sparks(point: Vector2, tint: Color) -> void:
	var amount := mini(SPARKS_PER_EVENT, MAX_SPARKS - spark_count)
	for index in amount:
		var direction := Vector2.from_angle(float(index) * TAU / SPARKS_PER_EVENT)
		var slot := spark_count + index
		spark_positions[slot] = point
		spark_velocities[slot] = direction * rng.randf_range(24.0, 65.0)
		spark_colors[slot] = tint
		spark_lifetimes[slot] = rng.randf_range(0.35, 0.78)
	spark_count += amount


func update_sparks(delta: float) -> void:
	for index in range(spark_count - 1, -1, -1):
		spark_positions[index] += spark_velocities[index] * delta
		spark_lifetimes[index] -= delta
		if spark_lifetimes[index] <= 0.0:
			spark_count -= 1
			spark_positions[index] = spark_positions[spark_count]
			spark_velocities[index] = spark_velocities[spark_count]
			spark_lifetimes[index] = spark_lifetimes[spark_count]
			spark_colors[index] = spark_colors[spark_count]


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
	if index < 0 or index >= UPGRADE_COSTS.size():
		push_warning("Ignored an invalid hotel upgrade index: %d" % index)
		return
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
	if is_instance_valid(ui):
		ui.refresh_live()


func save_game() -> void:
	if read_only_save:
		return
	var next_revision := save_revision + 1
	var next_slot := 1 - save_slot
	var result := Saves.write_slot(next_slot, {
		"version": Saves.VERSION, "revision": next_revision, "shift": shift, "money": money, "profit": total_profit,
		"upgrades": upgrades, "rooms": rooms, "task_total": task_total, "haunt_count": haunt_count,
		"haunt_marks": haunt_marks, "haunt_timer": haunt_timer, "muted": muted,
	})
	if result != OK:
		push_warning("Hotel save failed: %s" % error_string(result))
		announce("تعذّر حفظ التقدم على هذا الجهاز.", 6.0)
		return
	save_revision = next_revision
	save_slot = next_slot
	has_save = true
	needs_save_migration = false


func load_game() -> void:
	var entry := Saves.load_latest()
	read_only_save = entry.future
	if not entry.has("data"):
		return
	var saved: Dictionary = entry.data
	start_shift(maxi(1, Saves.integer(saved.get("shift"), 1)))
	var saved_rooms: Variant = saved.get("rooms")
	if saved_rooms is Array:
		for index in mini(active_rooms, saved_rooms.size()):
			if saved_rooms[index] is Array:
				for task in mini(World.TASK_COUNT, saved_rooms[index].size()):
					rooms[index][task] = Saves.integer(saved_rooms[index][task], rooms[index][task], Saves.MAX_TASKS_PER_STATION)
	var saved_upgrades: Variant = saved.get("upgrades")
	if saved_upgrades is Array:
		for index in mini(upgrades.size(), saved_upgrades.size()):
			if saved_upgrades[index] is bool:
				upgrades[index] = saved_upgrades[index]
	money = Saves.integer(saved.get("money"), 0)
	total_profit = Saves.integer(saved.get("profit"), 0)
	haunt_count = mini(Saves.integer(saved.get("haunt_count"), 0), haunt_limit)
	haunt_marks = Saves.integer(saved.get("haunt_marks"), 0, Saves.MAX_HAUNT_MARKS)
	var timer: Variant = saved.get("haunt_timer")
	if (timer is float or timer is int) and timer >= 0.0 and timer <= 60.0:
		haunt_timer = float(timer)
	task_total = maxi(Saves.integer(saved.get("task_total"), task_total), remaining_tasks())
	muted = saved.get("muted") == true
	save_revision = entry.revision
	save_slot = entry.slot
	has_save = true
	needs_save_migration = entry.version < Saves.VERSION or not entry.complete
