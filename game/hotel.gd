extends Node2D

const World = preload("res://game/world.gd")
const Interface = preload("res://game/interface.gd")
const Sound = preload("res://game/sound.gd")
const Management = preload("res://game/management.gd")
const Rules = preload("res://game/settings.gd")
const Saves = preload("res://game/save_state.gd")
const Updates = preload("res://startup/content_updater.gd")
const Diagnostics = preload("res://game/diagnostics.gd")

const NO_POINTER := -2
const MOUSE_POINTER := -1
const NO_TARGET := -1
const RECEPTION := -2
const STICK_DEAD_ZONE := 10.0
const STICK_RADIUS := 53.0
const MAX_STEP_DELTA := 0.1
const COLLISION_STEP := 3.0
const MAX_SPARKS := 27
const SPARKS_PER_EVENT := 9

var world: Node2D
var map_view: Control
var map_fade: ColorRect
var ui: Control
var sound: Node
var diagnostics: Logger
var business := Management.new()
var initialized := false
var update_fault_reported := false
var backgrounded := false
var paused := true:
	set(value):
		paused = value
		if is_instance_valid(sound):
			sound.set_ambience_paused(value)
var muted := false
var player_speed_index := 1
var player := World.START
var target := NO_TARGET
var facing := 0
var walking := false
var elapsed := 0.0
var second_accumulator := 0.0
var unsaved_seconds := 0
var seen_event := -1
var painted_map := -1

var pointer := NO_POINTER
var gesture_origin := Vector2.ZERO
var walk_intent := Vector2.ZERO
var dragging := false
var input_generation := 0

var haunt_flash := 0.0
var ghost_time := 0.0
var ghost_position := Vector2.ZERO
var spark_positions := PackedVector2Array()
var spark_velocities := PackedVector2Array()
var spark_colors := PackedColorArray()
var spark_lifetimes := PackedFloat32Array()
var spark_count := 0
var effects_rng := RandomNumberGenerator.new()
var notice := ""
var save_slot := 0
var save_revision := 0
var has_save := false
var needs_migration := false
var read_only_save := false


func _ready() -> void:
	diagnostics = Diagnostics.install(get_tree())
	if OS.has_feature("android"):
		Engine.max_fps = 30
		OS.low_processor_usage_mode = true
		DisplayServer.screen_set_keep_on(false)
	effects_rng.randomize()
	spark_positions.resize(MAX_SPARKS)
	spark_velocities.resize(MAX_SPARKS)
	spark_colors.resize(MAX_SPARKS)
	spark_lifetimes.resize(MAX_SPARKS)
	load_game()
	world = World.new()
	world.game = self
	map_view = Control.new()
	map_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_view.clip_contents = true
	add_child(map_view)
	map_view.add_child(world)
	map_fade = ColorRect.new()
	map_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_view.add_child(map_fade)
	map_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_fade.hide()
	sound = Sound.new()
	add_child(sound)
	sound.set_muted(muted)
	ui = Interface.new()
	ui.game = self
	add_child(ui)
	initialized = is_instance_valid(ui.hud)
	if not initialized:
		push_error("Hotel startup could not initialize the business ledger.")
		return
	ui.show_welcome()
	if get_tree().has_meta(Updates.BOOT_META):
		var revision: int = get_tree().get_meta(Updates.BOOT_META)
		get_tree().remove_meta(Updates.BOOT_META)
		get_tree().create_timer(1.0).timeout.connect(func(): Updates.confirm_startup(revision), CONNECT_ONE_SHOT)


func _process(delta: float) -> void:
	if not initialized or paused or backgrounded or not is_finite(delta) or delta <= 0.0:
		return
	if not is_instance_valid(world) or not is_instance_valid(ui) or not is_instance_valid(ui.hud):
		if not update_fault_reported:
			update_fault_reported = true
			push_error("Hotel update skipped because its world or ledger is unavailable.")
		return
	if ui.needs_rotation:
		return
	var step := minf(delta, MAX_STEP_DELTA)
	elapsed += step
	var past_effects := effect_active()
	var last_flash := haunt_flash
	haunt_flash = move_toward(haunt_flash, 0.0, step * 1.3)
	ghost_time = maxf(0.0, ghost_time - step)
	move_worker(step)
	update_target()
	second_accumulator += step
	if second_accumulator >= 1.0:
		second_accumulator -= 1.0
		advance_time()
	update_sparks(step)
	world.follow_player(step)
	world.update_actors(past_effects or effect_active())
	if last_flash != haunt_flash:
		ui.update_flash()


func advance_time() -> void:
	var ended := business.tick(World.room_at(player))
	unsaved_seconds += 1
	sync_business()
	if ended or unsaved_seconds >= Rules.AUTOSAVE_SECONDS:
		save_game()
	if ended:
		sound.play_cue("shift")
		ui.show_summary()


func sync_business() -> void:
	if painted_map != business.map_revision:
		painted_map = business.map_revision
		world.queue_redraw()
	if seen_event != business.event_revision:
		seen_event = business.event_revision
		notice = business.notice
		if business.is_open(business.ghost_room):
			ghost_position = World.room_rect(business.ghost_room).get_center()
			ghost_time = 3.4
			haunt_flash = 1.0
			spawn_sparks(ghost_position, Color("#c8bb85"))
			sound.play_cue("haunt")
	ui.refresh()


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
	if value and initialized:
		if has_save or unsaved_seconds > 0:
			save_game()
		diagnostics.flush()


func can_play() -> bool:
	return initialized and not paused and not backgrounded and is_instance_valid(ui) and not ui.needs_rotation


func _unhandled_input(event: InputEvent) -> void:
	if not can_play() or pointer != NO_POINTER:
		return
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
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
	elif event is InputEventMouseButton and pointer == MOUSE_POINTER and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
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
	pointer = NO_POINTER
	walk_intent = Vector2.ZERO
	dragging = false
	if tap:
		tap_after_release.call_deferred(input_generation)


func tap_after_release(generation: int) -> void:
	if generation == input_generation and pointer == NO_POINTER:
		tap_interact()


func cancel_input() -> void:
	input_generation += 1
	pointer = NO_POINTER
	walk_intent = Vector2.ZERO
	dragging = false
	walking = false
	if is_instance_valid(ui) and is_instance_valid(ui.chore_board):
		ui.chore_board.cancel_stroke()


func tap_interact() -> void:
	if not can_play():
		return
	update_target()
	if target == RECEPTION:
		ui.show_reception()
	elif target >= 0:
		ui.show_room(target)


func _unhandled_key_input(event: InputEvent) -> void:
	if not initialized or backgrounded or not is_instance_valid(ui) or ui.needs_rotation:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if ui.modal_kind == "diagnostics":
				ui.close_diagnostics()
			elif not paused:
				ui.show_pause()
			elif ui.can_resume():
				resume()
		KEY_M:
			toggle_sound()
		KEY_E, KEY_SPACE, KEY_ENTER:
			tap_interact()


func resume() -> void:
	if not initialized or not is_instance_valid(ui) or not is_instance_valid(sound):
		return
	if not business.pending_report.is_empty():
		ui.show_summary()
		return
	ui.close_dialog()
	paused = false
	sound.start_audio()
	if not has_save or needs_migration:
		save_game()
	sync_business()
	update_target()


func acknowledge_day() -> void:
	if business.pending_report.is_empty():
		return
	business.pending_report.clear()
	save_game()
	resume()


func toggle_sound() -> void:
	if not is_instance_valid(sound) or not is_instance_valid(ui):
		return
	muted = not muted
	sound.set_muted(muted)
	if has_save:
		save_game()
	ui.refresh()


func set_player_speed(index: int) -> bool:
	if index < 0 or index >= Rules.SPEED_MULTIPLIERS.size():
		return false
	player_speed_index = index
	cancel_input()
	return save_game()


func start_new_game() -> bool:
	if not initialized or read_only_save or ui.modal_kind != "new_game":
		return false
	var previous := business
	business = Management.new()
	if not save_game():
		business = previous
		return false
	player = World.START
	target = NO_TARGET
	facing = 0
	notice = ""
	seen_event = -1
	painted_map = -1
	haunt_flash = 0.0
	ghost_time = 0.0
	spark_count = 0
	second_accumulator = 0.0
	world.follow_player(0.0, true)
	world.update_actors(true)
	resume()
	return true


func move_worker(delta: float) -> void:
	var horizontal := int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	var vertical := int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	var direction := (Vector2(horizontal, vertical) + walk_intent).limit_length()
	var old := player
	var multiplier: float = Rules.SPEED_MULTIPLIERS[clampi(player_speed_index, 0, Rules.SPEED_MULTIPLIERS.size() - 1)]
	apply_motion(direction * Rules.PLAYER_SPEED * multiplier * clampf(delta, 0.0, MAX_STEP_DELTA))
	walking = player.distance_squared_to(old) > 0.01
	if direction.length_squared() > 0.01:
		if absf(direction.x) > absf(direction.y):
			facing = 1 if direction.x > 0 else 3
		else:
			facing = 0 if direction.y > 0 else 2


func apply_motion(motion: Vector2) -> void:
	if not motion.is_finite() or motion.is_zero_approx():
		return
	var distance := motion.length()
	if not is_finite(distance) or distance > 256.0:
		push_warning("Hotel ignored an unsafe movement step.")
		return
	var steps := maxi(1, ceili(distance / COLLISION_STEP))
	var step := motion / float(steps)
	for index in steps:
		var along_x := Vector2(player.x + step.x, player.y)
		if World.floor_contains(along_x, business):
			player.x = along_x.x
		var along_y := Vector2(player.x, player.y + step.y)
		if World.floor_contains(along_y, business):
			player.y = along_y.y


func update_target() -> void:
	var next := NO_TARGET
	var room := World.room_at(player)
	if business.is_open(room):
		next = room
	elif World.AT_RECEPTION.has_point(player) or World.RECEPTION_RECT.has_point(player):
		next = RECEPTION
	if target != next:
		target = next


func buy_room(room: int) -> bool:
	return finish_business_action(business.unlock_room(room))


func buy_item(room: int, slot: int, item: int) -> bool:
	if not business.can_place(room, slot, item):
		return false
	var footprint := World.furniture_bounds(room, slot, item)
	if footprint.has_area() and footprint.grow(4).has_point(player):
		notice = "ابتعد عن خانة الأثاث قبل وضع القطعة."
		return false
	return finish_business_action(business.place_furniture(room, slot, item))


func check_in(guest_id: int, room: int) -> bool:
	return finish_business_action(business.accept_guest(guest_id, room))


func turn_away(guest_id: int) -> bool:
	return finish_business_action(business.reject_guest(guest_id))


func buy_upgrade(index: int) -> bool:
	return finish_business_action(business.buy_upgrade(index))


func change_cleaner(hire: bool) -> bool:
	return finish_business_action(business.set_employee(hire))


func start_task(room: int, kind: int, slot: int = -1) -> void:
	if World.room_at(player) == room and business.can_do_task(room, kind, slot):
		ui.show_chore(room, kind, slot)


func ignore_task(room: int) -> bool:
	return finish_business_action(business.ignore_task(room))


func complete_task(room: int, kind: int, slot: int) -> void:
	if not initialized or ui.modal_kind != "chore":
		return
	if World.room_at(player) == room and business.complete_task(room, kind, slot):
		spawn_sparks(player, Color("#bbcb92"))
		finish_business_action(true)
	ui.show_room(room)


func finish_business_action(changed: bool) -> bool:
	if changed:
		sound.play_cue("work")
		sync_business()
		save_game()
	return changed


func effect_active() -> bool:
	return haunt_flash > 0.0 or ghost_time > 0.0 or spark_count > 0


func spawn_sparks(point: Vector2, tint: Color) -> void:
	var amount := mini(SPARKS_PER_EVENT, MAX_SPARKS - spark_count)
	for index in amount:
		var direction := Vector2.from_angle(float(index) * TAU / SPARKS_PER_EVENT)
		var slot := spark_count + index
		spark_positions[slot] = point
		spark_velocities[slot] = direction * effects_rng.randf_range(24.0, 65.0)
		spark_colors[slot] = tint
		spark_lifetimes[slot] = effects_rng.randf_range(0.35, 0.78)
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


func save_game() -> bool:
	if read_only_save:
		return false
	var payload := business.snapshot()
	payload.version = Saves.VERSION
	payload.revision = save_revision + 1
	payload.muted = muted
	payload.player_speed_index = player_speed_index
	var next_slot := 1 - save_slot
	var result := Saves.write_slot(next_slot, payload)
	if result != OK:
		push_warning("Hotel save failed: %s" % error_string(result))
		notice = "تعذّر حفظ تقدّم الفندق."
		return false
	save_slot = next_slot
	save_revision = payload.revision
	has_save = true
	needs_migration = false
	unsaved_seconds = 0
	return true


func load_game() -> void:
	var entry := Saves.load_latest()
	read_only_save = entry.future
	if not entry.has("data"):
		return
	var saved: Dictionary = entry.data
	business.restore(saved, entry.version)
	muted = saved.get("muted") is bool and saved.get("muted")
	player_speed_index = Saves.integer(saved.get("player_speed_index"), 1, Rules.SPEED_MULTIPLIERS.size() - 1)
	save_revision = entry.revision
	save_slot = entry.slot
	has_save = true
	needs_migration = entry.version < Saves.VERSION or not entry.complete
