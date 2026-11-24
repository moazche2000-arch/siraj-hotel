extends RefCounted

const Rules = preload("res://game/settings.gd")
const Saves = preload("res://game/save_state.gd")
const Task = Rules.Task
const Request = Rules.Request
const Item = Rules.Item
enum DirtCause { TIME, GUEST, CHECKOUT, HAUNT, LEAK }

var rooms: Array[Dictionary] = []
var waiting: Array[Dictionary] = []
var upgrades: Array[bool] = [false, false, false]
var rng := RandomNumberGenerator.new()
var day := 1
var second := 0
var cash := Rules.STARTING_CASH
var reputation := Rules.STARTING_REPUTATION
var income := 0
var expenses := 0
var last_review := ""
var pending_report: Dictionary = {}
var employee := false
var wage_day := 0
var cleaner_in := Rules.CLEANER_INTERVAL
var cleaner_room := -1
var arrival_in := Rules.FIRST_ARRIVAL_SECONDS
var maintenance_in := Rules.MAINTENANCE_FIRST_SECOND
var haunt_in := Rules.HAUNT_FIRST_SECOND
var service_clock := 0
var room_cursor := 0
var haunt_cursor := 0
var haunt_sequence := 0
var maintenance_sequence := 0
var task_room := -1
var task_kind := -1
var task_slot := -1
var task_reason := ""
var task_expires := 0
var task_wait := 0
var next_guest_id := 1
var map_revision := 0
var notice := ""
var event_revision := 0
var ghost_room := -1


func _init() -> void:
	rng.randomize()
	for index in Rules.ROOM_COUNT:
		rooms.append({
			"open": index == 0, "clean": 100.0, "items": [0, 0, 0, 0, 0, 0], "broken": 0,
			"guest": {}, "checkout": 0, "incident": -1, "incident_slot": -1,
			"request": -1, "requested_item": -1, "deadline": 0, "request_in": 0,
			"clean_until": 0, "haunt_at": 0, "offer_at": 0, "dirt_debt": 0.0, "dirt_cause": DirtCause.TIME,
		})


func valid_room(index: int) -> bool:
	return index >= 0 and index < rooms.size()


func is_open(index: int) -> bool:
	return valid_room(index) and rooms[index].open


func slot_item(room: int, slot: int) -> int:
	if not is_open(room) or slot < 0 or slot >= Rules.SLOT_COUNT:
		return 0
	return rooms[room].items[slot]


func broken_at(room: int, slot: int) -> bool:
	return slot_item(room, slot) > 0 and (int(rooms[room].broken) & (1 << slot)) != 0


func unlock_room(index: int) -> bool:
	if not valid_room(index) or is_open(index) or cash < Rules.ROOM_PRICES[index]:
		return false
	spend(Rules.ROOM_PRICES[index])
	rooms[index].open = true
	map_revision += 1
	record("اشتريت الغرفة %d." % (101 + index))
	return true


func can_place(room: int, slot: int, item: int) -> bool:
	if not is_open(room) or slot < 0 or slot >= Rules.SLOT_COUNT or not Rules.valid_item(item):
		return false
	var old := slot_item(room, slot)
	if cash < Rules.ITEM_PRICES[item - 1] or (old == item and not broken_at(room, slot)):
		return false
	if not rooms[room].guest.is_empty() and Rules.item_kind(old) == Item.BED and Rules.item_kind(item) != Item.BED:
		return first_item(room, Item.BED, true, slot) >= 0
	return true


func place_furniture(room: int, slot: int, item: int) -> bool:
	if not can_place(room, slot, item):
		return false
	spend(Rules.ITEM_PRICES[item - 1])
	rooms[room].items[slot] = item
	rooms[room].broken &= ~(1 << slot)
	if rooms[room].incident == Task.BULB and rooms[room].incident_slot == slot:
		clear_incident(room)
	map_revision += 1
	record("وضعت %s في الغرفة %d." % [Rules.item_name(item), 101 + room])
	check_request(room)
	if task_room == room and task_slot == slot and task_kind in [Task.REPAIR, Task.BULB]:
		clear_task()
	return true


func first_item(room: int, kind: int, working_only: bool = false, except_slot: int = -1) -> int:
	for slot in Rules.SLOT_COUNT:
		if slot != except_slot and Rules.item_kind(slot_item(room, slot)) == kind:
			if not working_only or not broken_at(room, slot):
				return slot
	return -1


func first_broken(room: int) -> int:
	for slot in Rules.SLOT_COUNT:
		if broken_at(room, slot):
			return slot
	return -1


func comfort(room: int) -> int:
	var result := 0
	for slot in Rules.SLOT_COUNT:
		var item := slot_item(room, slot)
		if Rules.valid_item(item) and not broken_at(room, slot):
			result += Rules.ITEM_COMFORT[item - 1]
	return result


func broken_count(room: int) -> int:
	var result := 0
	for slot in Rules.SLOT_COUNT:
		if broken_at(room, slot):
			result += 1
	return result


func appeal(room: int) -> int:
	if not is_open(room):
		return 0
	return clampi(roundi(rooms[room].clean * 0.60 + comfort(room) * 1.65 - broken_count(room) * 8), 0, 100)


func nightly_rate(room: int) -> int:
	if not is_open(room):
		return 0
	var clean: float = rooms[room].clean
	var furnishing := comfort(room)
	var broken := broken_count(room)
	var rate := Rules.BASE_NIGHTLY_RATE + roundi(furnishing * Rules.COMFORT_RATE + clean * Rules.CLEANLINESS_RATE)
	if clean >= 88.0 and furnishing >= 18 and broken == 0:
		rate += Rules.EXCELLENT_ROOM_BONUS
	if clean < 48.0:
		rate -= Rules.DIRTY_ROOM_DISCOUNT
	rate -= broken * Rules.BROKEN_ITEM_DISCOUNT
	if upgrades[2]:
		rate += Rules.AMENITIES_NIGHTLY_BONUS
	return maxi(10, rate)


func get_waiting(id: int) -> Dictionary:
	for guest: Dictionary in waiting:
		if guest.id == id:
			return guest
	return {}


func guest_name(guest: Dictionary) -> String:
	return Rules.GUEST_NAMES[clampi(int(guest.get("name", 0)), 0, Rules.GUEST_NAMES.size() - 1)]


func can_book(room: int) -> bool:
	return is_open(room) and rooms[room].guest.is_empty() and first_item(room, Item.BED, true) >= 0


func accept_guest(id: int, room: int) -> bool:
	if not can_book(room):
		return false
	for index in waiting.size():
		var guest: Dictionary = waiting[index]
		if guest.id != id:
			continue
		waiting.remove_at(index)
		rooms[room].guest = guest
		rooms[room].checkout = day + guest.nights
		rooms[room].request_in = next_request_delay(room)
		map_revision += 1
		record("استقبلت %s في الغرفة %d." % [guest_name(guest), 101 + room])
		return true
	return false


func reject_guest(id: int) -> bool:
	for index in waiting.size():
		if waiting[index].id == id:
			record("غادر %s الاستقبال." % guest_name(waiting[index]))
			waiting.remove_at(index)
			map_revision += 1
			return true
	return false


func remaining_nights(room: int) -> int:
	if not is_open(room) or rooms[room].guest.is_empty():
		return 0
	return maxi(0, int(rooms[room].checkout) - day)


func buy_upgrade(index: int) -> bool:
	if index < 0 or index >= upgrades.size() or upgrades[index] or cash < Rules.UPGRADE_PRICES[index]:
		return false
	upgrades[index] = true
	spend(Rules.UPGRADE_PRICES[index])
	record("تم شراء %s." % Rules.UPGRADE_NAMES[index])
	return true


func set_employee(hire: bool) -> bool:
	if employee == hire:
		return false
	if hire and wage_day != day:
		if cash < Rules.CLEANER_WAGE:
			return false
		spend(Rules.CLEANER_WAGE)
		wage_day = day
	employee = hire
	cleaner_room = -1
	cleaner_in = Rules.CLEANER_INTERVAL
	map_revision += 1
	record("بدأ عامل التنظيف عمله." if hire else "أنهيت توظيف عامل التنظيف.")
	return true


func tick(player_room: int = -1) -> bool:
	if not pending_report.is_empty():
		return false
	second += 1
	service_clock += 1
	for index in rooms.size():
		if is_open(index):
			update_room(index)
	update_arrivals()
	update_cleaner()
	update_jobs(player_room)
	if second >= maxi(1, Rules.DAY_SECONDS):
		close_day()
		return true
	return false


func update_room(index: int) -> void:
	var room: Dictionary = rooms[index]
	var is_empty: bool = room.guest.is_empty()
	var was_clean: bool = room.clean >= Rules.CLEANING_THRESHOLD
	if not is_clean_protected(index):
		var nights := 0 if is_empty else maxi(0, int(room.guest.nights) - remaining_nights(index))
		var decay := Rules.EMPTY_DIRT_PER_SECOND if is_empty else Rules.OCCUPIED_DIRT_PER_SECOND + nights * Rules.STAY_DIRT_PER_DAY
		var residue := minf(room.dirt_debt, Rules.EVENT_DIRT_PER_SECOND)
		room.dirt_debt -= residue
		decay += residue
		if room.incident == Task.LEAK:
			decay += Rules.LEAK_DIRT_PER_SECOND
		if room.dirt_cause == DirtCause.TIME and not is_empty:
			room.dirt_cause = DirtCause.GUEST
		room.clean = maxf(0.0, room.clean - decay)
	if was_clean and room.clean < Rules.CLEANING_THRESHOLD:
		map_revision += 1
	if not is_empty and room.request < 0 and room.request_in > 0:
		room.request_in -= 1


func clean_seconds(index: int) -> int:
	return maxi(0, int(rooms[index].clean_until) - service_clock) if is_open(index) else 0


func is_clean_protected(index: int) -> bool:
	return clean_seconds(index) > 0


func update_arrivals() -> void:
	for index in range(waiting.size() - 1, -1, -1):
		waiting[index].patience -= 1
		if waiting[index].patience <= 0:
			waiting.remove_at(index)
			map_revision += 1
	arrival_in -= 1
	if arrival_in > 0:
		return
	arrival_in = maxi(7, rng.randi_range(Rules.ARRIVAL_INTERVAL.x, Rules.ARRIVAL_INTERVAL.y) - (reputation >> 3))
	if waiting.size() >= Rules.MAX_WAITING:
		return
	var quality := int(rng.randi_range(0, 100) < reputation)
	if reputation >= 65 and rng.randi_range(0, 100) < reputation - 28:
		quality += 1
	var guest := {
		"id": next_guest_id, "name": choose_guest_name(),
		"look": rng.randi_range(0, 3), "preference": rng.randi_range(0, Rules.PREFERENCES.size() - 1),
		"nights": rng.randi_range(Rules.MIN_STAY, Rules.MAX_STAY), "quality": quality,
		"budget": rng.randi_range(51, 71) + quality * 18,
		"patience": Rules.GUEST_PATIENCE_SECONDS, "fulfilled": 0, "missed": 0, "scares": 0,
	}
	next_guest_id += 1
	waiting.append(guest)
	map_revision += 1
	record("%s ينتظر عند الاستقبال." % guest_name(guest))


func choose_guest_name() -> int:
	var taken := 0
	for guest: Dictionary in waiting:
		taken |= 1 << int(guest.name)
	for room: Dictionary in rooms:
		if not room.guest.is_empty():
			taken |= 1 << int(room.guest.name)
	var start := rng.randi_range(0, Rules.GUEST_NAMES.size() - 1)
	for offset in Rules.GUEST_NAMES.size():
		var candidate := (start + offset) % Rules.GUEST_NAMES.size()
		if (taken & (1 << candidate)) == 0:
			return candidate
	return start


func next_request_delay(index: int) -> int:
	var guest: Dictionary = rooms[index].guest
	var width := maxi(1, Rules.REQUEST_INTERVAL.y - Rules.REQUEST_INTERVAL.x + 1)
	return Rules.REQUEST_INTERVAL.x + (int(guest.get("id", 0)) * 7 + day + service_clock) % width


func create_request(index: int) -> bool:
	var room: Dictionary = rooms[index]
	if room.guest.is_empty() or room.request_in > 0:
		return false
	var missing := Item.RUG
	match int(room.guest.preference):
		Rules.Preference.CLEAN:
			missing = Item.LAMP
		Rules.Preference.COMFORT:
			missing = Item.TV
	if first_broken(index) >= 0:
		room.request = Request.REPAIR
	elif first_item(index, missing, true) < 0:
		room.request = Request.AMENITY
		room.requested_item = missing
	elif room.clean < Rules.CLEANING_THRESHOLD and not is_clean_protected(index):
		room.request = Request.CLEAN
	else:
		room.request_in = next_request_delay(index)
		return false
	room.deadline = Rules.REQUEST_DEADLINE
	return offer_request(index)


func request_name(index: int) -> String:
	if not is_open(index):
		return ""
	var room: Dictionary = rooms[index]
	match int(room.request):
		Request.CLEAN:
			return "تنظيف الغرفة"
		Request.REPAIR:
			return "إصلاح الأثاث"
		Request.AMENITY:
			var kind: int = room.requested_item
			return Rules.ITEM_NAMES[kind] if kind >= 0 and kind < Rules.ITEM_NAMES.size() else "قطعة أثاث"
	return ""


func reset_request(index: int) -> void:
	var room: Dictionary = rooms[index]
	room.request = -1
	room.requested_item = -1
	room.deadline = 0
	room.request_in = next_request_delay(index)


func check_request(index: int) -> void:
	var room: Dictionary = rooms[index]
	if task_room != index or room.guest.is_empty() or room.request < 0 or task_seconds_left() <= 0:
		return
	var fulfilled := false
	match int(room.request):
		Request.CLEAN:
			fulfilled = room.clean >= 94.0
		Request.REPAIR:
			fulfilled = not broken_at(index, task_slot)
		Request.AMENITY:
			fulfilled = first_item(index, room.requested_item, true) >= 0
	if fulfilled:
		var reward: int = Rules.REQUEST_REWARDS[room.request]
		earn(reward)
		room.guest.fulfilled += 1
		reputation = mini(100, reputation + 1)
		reset_request(index)
		clear_task()
		record("طلب الغرفة %d اكتمل. مكافأة %d ر.س." % [101 + index, reward])


func update_cleaner() -> void:
	if not employee:
		return
	cleaner_in -= 1
	if cleaner_in > 0:
		return
	cleaner_in = Rules.CLEANER_INTERVAL
	var lowest := Rules.CLEANING_THRESHOLD
	var selected := -1
	for index in rooms.size():
		if is_open(index) and rooms[index].clean < lowest:
			lowest = rooms[index].clean
			selected = index
	cleaner_room = selected
	map_revision += 1
	if selected >= 0:
		rooms[selected].clean = minf(100.0, rooms[selected].clean + Rules.CLEANER_GAIN + (4.0 if upgrades[0] else 0.0))
		check_request(selected)
		if task_room == selected and task_kind == Task.CLEAN and rooms[selected].request < 0 and rooms[selected].clean >= Rules.CLEANING_THRESHOLD:
			clear_task()
			record("عامل التنظيف خلّص مهمة الغرفة %d." % (101 + selected))


func update_jobs(player_room: int) -> void:
	maintenance_in = maxi(0, maintenance_in - 1)
	if day >= Rules.HAUNT_FIRST_DAY:
		haunt_in = maxi(0, haunt_in - 1)
	if task_room >= 0:
		if task_expires > 0 and task_seconds_left() <= 0:
			ignore_task(task_room, true)
		return
	if task_wait > 0:
		task_wait -= 1
		return
	if offer_pending_room_work():
		return
	if haunt_in <= 0 and haunt_event(player_room):
		return
	if maintenance_in <= 0 and maintenance_event():
		return
	offer_room_need()


func event_room(start: int, excluded: int = -1, haunted: bool = false) -> int:
	for offset in rooms.size():
		var index := (start + offset) % rooms.size()
		if index == excluded or not can_offer(index) or is_clean_protected(index):
			continue
		if rooms[index].incident >= 0 or rooms[index].request >= 0:
			continue
		if haunted and rooms[index].haunt_at > service_clock:
			continue
		return index
	return -1


func maintenance_event() -> bool:
	var index := event_room(room_cursor)
	if task_room >= 0 or task_wait > 0 or index < 0:
		return false
	var room: Dictionary = rooms[index]
	var lamp := first_item(index, Item.LAMP, true)
	var choice := maintenance_sequence % 3
	maintenance_sequence += 1
	maintenance_in = maxi(1, Rules.MAINTENANCE_INTERVAL)
	var reason := "ظهر تسريب ماء في الغرفة %d." % (101 + index)
	if choice == 0 and lamp >= 0:
		room.incident = Task.BULB
		room.incident_slot = lamp
		room.broken |= 1 << lamp
		reason = "احترقت لمبة مركّبة في الغرفة %d." % (101 + index)
	elif choice == 1 and not room.guest.is_empty():
		room.incident = Task.KEY
		reason = "ضيف الغرفة %d ضيّع مفتاحه." % (101 + index)
	else:
		room.incident = Task.LEAK
		add_dirt(index, Rules.LEAK_EVENT_DIRT, DirtCause.LEAK)
	return offer_task(index, room.incident, room.incident_slot, reason)


func haunt_event(player_room: int = -1) -> bool:
	if task_room >= 0 or task_wait > 0 or day < Rules.HAUNT_FIRST_DAY or haunt_in > 0:
		return false
	var index := event_room(haunt_cursor, player_room, true)
	if index < 0:
		return false
	var room: Dictionary = rooms[index]
	var choice := haunt_sequence % 3
	haunt_sequence += 1
	haunt_cursor = (index + 1) % rooms.size()
	haunt_in = clampi(Rules.HAUNT_INTERVAL.y - (day - Rules.HAUNT_FIRST_DAY) * Rules.HAUNT_ACCELERATION_PER_DAY, Rules.HAUNT_INTERVAL.x, Rules.HAUNT_INTERVAL.y)
	room.haunt_at = service_clock + Rules.HAUNT_ROOM_COOLDOWN
	var slot := breakable_slot(index)
	add_dirt(index, Rules.HAUNT_DIRT, DirtCause.HAUNT)
	if not room.guest.is_empty() and choice == 1:
		room.incident = Task.CALM
		room.guest.scares += 1
		offer_task(index, Task.CALM, -1, "الجن خوّفوا ضيف الغرفة %d." % (101 + index), 0, index)
	elif choice != 2 and slot >= 0 and (not upgrades[1] or rng.randi_range(1, 100) <= Rules.LOCK_BREAK_RISK_PERCENT):
		room.broken |= 1 << slot
		offer_task(index, Task.REPAIR, slot, "الجن كسروا قطعة أثاث في الغرفة %d." % (101 + index), 0, index)
	else:
		task_wait = Rules.TASK_GAP
		record("الجن مرّوا بالغرفة %d وتركوا أثرًا." % (101 + index), index)
	return true


func breakable_slot(room: int) -> int:
	var start := haunt_sequence % Rules.SLOT_COUNT
	for offset in Rules.SLOT_COUNT:
		var slot := (start + offset) % Rules.SLOT_COUNT
		if slot_item(room, slot) > 0 and not broken_at(room, slot):
			return slot
	return -1


func add_dirt(index: int, amount: float, cause: int) -> void:
	var room: Dictionary = rooms[index]
	room.dirt_debt = minf(100.0, float(room.dirt_debt) + amount)
	room.dirt_cause = cause


func can_offer(index: int) -> bool:
	return is_open(index) and rooms[index].offer_at <= service_clock


func offer_pending_room_work() -> bool:
	for offset in rooms.size():
		var index := (room_cursor + offset) % rooms.size()
		if not can_offer(index):
			continue
		var room: Dictionary = rooms[index]
		if room.incident >= 0:
			return offer_task(index, room.incident, room.incident_slot, "مشكلة %s قائمة في الغرفة %d." % [Rules.TASK_NAMES[room.incident], 101 + index])
		if room.request >= 0 and not room.guest.is_empty() and offer_request(index):
			return true
	return false


func offer_room_need() -> void:
	for offset in rooms.size():
		var index := (room_cursor + offset) % rooms.size()
		if not can_offer(index):
			continue
		var room: Dictionary = rooms[index]
		if create_request(index):
			return
		var broken := first_broken(index)
		if broken >= 0:
			offer_task(index, Task.REPAIR, broken, "الأثاث في الغرفة %d يحتاج إصلاحًا." % (101 + index))
			return
		if room.clean < Rules.CLEANING_THRESHOLD and not is_clean_protected(index):
			offer_task(index, Task.CLEAN, -1, cleaning_reason(index))
			return


func cleaning_reason(index: int) -> String:
	match int(rooms[index].dirt_cause):
		DirtCause.GUEST:
			return "إقامة الضيف في الغرفة %d خفّضت النظافة." % (101 + index)
		DirtCause.CHECKOUT:
			return "الضيف غادر الغرفة %d وتركها تحتاج تنظيف." % (101 + index)
		DirtCause.HAUNT:
			return "أثر الجن تراكم في الغرفة %d." % (101 + index)
		DirtCause.LEAK:
			return "الغرفة %d تحتاج تنظيفًا بعد التسريب." % (101 + index)
	return "الغبار تراكم مع الوقت في الغرفة %d." % (101 + index)


func offer_request(index: int) -> bool:
	var room: Dictionary = rooms[index]
	var reason := "ضيف الغرفة %d طلب %s." % [101 + index, request_name(index)]
	var deadline := maxi(1, mini(int(room.deadline), Rules.REQUEST_DEADLINE))
	match int(room.request):
		Request.CLEAN:
			if not is_clean_protected(index):
				return offer_task(index, Task.CLEAN, -1, reason, deadline)
		Request.REPAIR:
			var slot := first_broken(index)
			if slot >= 0:
				return offer_task(index, Task.REPAIR, slot, reason, deadline)
		Request.AMENITY:
			if room.requested_item >= 0 and first_item(index, room.requested_item, true) < 0:
				return offer_task(index, Task.AMENITY, -1, reason, deadline)
	reset_request(index)
	return false


func offer_task(index: int, kind: int, slot: int, reason: String, deadline: int = 0, ghost: int = -1) -> bool:
	if task_room >= 0 or task_wait > 0 or not is_open(index) or kind < 0 or kind >= Rules.TASK_NAMES.size():
		return false
	task_room = index
	task_kind = kind
	task_slot = slot
	task_reason = reason
	var seconds := deadline if deadline > 0 else Rules.TASK_IGNORE_SECONDS
	task_expires = service_clock + seconds if seconds > 0 else 0
	room_cursor = (index + 1) % rooms.size()
	map_revision += 1
	record(reason, ghost)
	return true


func task_seconds_left() -> int:
	return maxi(0, task_expires - service_clock)


func ignore_task(index: int, expired: bool = false) -> bool:
	if task_room != index or not is_open(index):
		return false
	var room: Dictionary = rooms[index]
	if room.request >= 0 and not room.guest.is_empty():
		room.guest.missed += 1
		reputation = maxi(0, reputation - 1)
		reset_request(index)
	room.offer_at = service_clock + Rules.IGNORED_ROOM_COOLDOWN
	clear_task()
	record("انتهت المهلة في الغرفة %d." % (101 + index) if expired else "تجاهلت مهمة الغرفة %d مؤقتًا." % (101 + index))
	return true


func clear_task() -> void:
	task_room = -1
	task_kind = -1
	task_slot = -1
	task_reason = ""
	task_expires = 0
	task_wait = Rules.TASK_GAP
	map_revision += 1


func can_do_task(index: int, task: int, slot: int = -1) -> bool:
	if not is_open(index) or task_room != index or (task_kind != task and not (task_kind == Task.CALM and task == Task.BANISH)):
		return false
	var room: Dictionary = rooms[index]
	match task:
		Task.CLEAN:
			return not is_clean_protected(index) and (room.clean < Rules.CLEANING_THRESHOLD or room.request == Request.CLEAN)
		Task.REPAIR:
			return task_slot == slot and broken_at(index, slot) and (room.incident != Task.BULB or room.incident_slot != slot)
		Task.BANISH:
			return room.incident == Task.CALM
		Task.LEAK, Task.BULB, Task.CALM, Task.KEY:
			return room.incident == task
	return false


func complete_task(index: int, task: int, slot: int = -1) -> bool:
	if not can_do_task(index, task, slot):
		return false
	var room: Dictionary = rooms[index]
	match task:
		Task.CLEAN:
			room.clean = 100.0
			room.clean_until = service_clock + Rules.CLEAN_COOLDOWN
			room.dirt_debt = 0.0
			room.dirt_cause = DirtCause.TIME
		Task.REPAIR:
			room.broken &= ~(1 << slot)
		Task.BULB:
			var bulb_slot: int = room.incident_slot
			if bulb_slot >= 0 and bulb_slot < Rules.SLOT_COUNT:
				room.broken &= ~(1 << bulb_slot)
			clear_incident(index)
		Task.CALM, Task.BANISH:
			if not room.guest.is_empty():
				room.guest.scares = maxi(0, int(room.guest.scares) - 1)
			clear_incident(index)
			if task == Task.BANISH:
				haunt_in = maxi(haunt_in, Rules.BANISH_DELAY)
		Task.LEAK:
			room.clean = minf(100.0, room.clean + 12.0)
			clear_incident(index)
		Task.KEY:
			earn(8)
			clear_incident(index)
	map_revision += 1
	record("%s · اكتملت المهمة في %d." % [Rules.TASK_NAMES[task], 101 + index])
	check_request(index)
	if task_room == index:
		clear_task()
	return true


func clear_incident(index: int) -> void:
	rooms[index].incident = -1
	rooms[index].incident_slot = -1


func close_day() -> void:
	var visitors := 0
	var reviews := ""
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		if not is_open(index) or room.guest.is_empty():
			continue
		spend(Rules.ROOM_DAILY_COST)
		if room.checkout <= day + 1:
			visitors += 1
			reviews += ("\n" if not reviews.is_empty() else "") + checkout_guest(index)
	pending_report = {
		"day": day, "income": income, "expenses": expenses, "net": income - expenses,
		"reviews": reviews, "visitors": visitors,
	}
	day += 1
	second = 0
	income = 0
	expenses = 0
	if employee and cash >= Rules.CLEANER_WAGE:
		spend(Rules.CLEANER_WAGE)
		wage_day = day
	elif employee:
		employee = false
		cleaner_room = -1
		record("توقّف عامل التنظيف لأن الرصيد ما يكفي راتبه اليومي.")
	map_revision += 1


func checkout_guest(index: int) -> String:
	var room: Dictionary = rooms[index]
	var guest: Dictionary = room.guest
	if room.request >= 0:
		guest.missed += 1
	var rate := nightly_rate(index)
	var payment := mini(rate, guest.budget) * int(guest.nights)
	var stars := roundi(guest_score(index))
	earn(payment)
	reputation = clampi(reputation + (stars - 3) * 5, 0, 100)
	last_review = "%s · %d/5 · دفع %d ر.س" % [guest_name(guest), stars, payment]
	if task_room == index and (room.request >= 0 or room.incident in [Task.CALM, Task.KEY]):
		clear_task()
	room.guest = {}
	room.checkout = 0
	add_dirt(index, Rules.CHECKOUT_DIRT, DirtCause.CHECKOUT)
	if room.incident == Task.CALM or room.incident == Task.KEY:
		clear_incident(index)
	reset_request(index)
	return last_review


func guest_score(index: int) -> float:
	if not is_open(index) or rooms[index].guest.is_empty():
		return 0.0
	var room: Dictionary = rooms[index]
	var guest: Dictionary = room.guest
	var score: float = 1.25 + appeal(index) * 0.033
	score += guest.fulfilled * 0.32 - guest.missed * 0.45 - guest.scares * 0.48
	match int(guest.preference):
		Rules.Preference.CLEAN:
			score += 0.5 if room.clean >= 86.0 else -0.5
		Rules.Preference.COMFORT:
			score += 0.55 if comfort(index) >= 22 else -0.45
		Rules.Preference.BUDGET:
			score += 0.45 if nightly_rate(index) <= guest.budget * 0.85 else -0.32
	return clampf(score, 1.0, 5.0)


func spend(amount: int) -> void:
	cash -= amount
	expenses += amount


func earn(amount: int) -> void:
	cash += amount
	income += amount


func record(message: String, haunted_room: int = -1) -> void:
	notice = message
	ghost_room = haunted_room
	event_revision += 1


func snapshot() -> Dictionary:
	return {
		"day": day, "second": second, "cash": cash, "reputation": reputation,
		"income": income, "expenses": expenses, "last_review": last_review, "report": pending_report,
		"rooms": rooms, "waiting": waiting, "upgrades": upgrades, "next_guest": next_guest_id,
		"employee": employee, "wage_day": wage_day, "cleaner_in": cleaner_in,
		"arrival_in": arrival_in, "maintenance_in": maintenance_in, "haunt_in": haunt_in,
		"service_clock": service_clock, "room_cursor": room_cursor, "haunt_cursor": haunt_cursor,
		"haunt_sequence": haunt_sequence, "maintenance_sequence": maintenance_sequence,
		"task_room": task_room, "task_kind": task_kind, "task_slot": task_slot,
		"task_reason": task_reason, "task_expires": task_expires, "task_wait": task_wait,
	}


func restore(data: Dictionary, version: int) -> void:
	var saved_upgrades: Variant = data.get("upgrades")
	if saved_upgrades is Array:
		for index in mini(upgrades.size(), saved_upgrades.size()):
			upgrades[index] = saved_upgrades[index] is bool and saved_upgrades[index]
	if version < Saves.MANAGEMENT_VERSION:
		cash = maxi(Rules.STARTING_CASH, Saves.integer(data.get("money"), Rules.STARTING_CASH))
		return
	day = maxi(1, Saves.integer(data.get("day"), 1))
	second = clampi(Saves.integer(data.get("second"), 0), 0, maxi(0, Rules.DAY_SECONDS - 1))
	service_clock = Saves.integer(data.get("service_clock"), mini((day - 1) * Rules.DAY_SECONDS + second, Saves.MAX_INTEGER))
	cash = Saves.signed_integer(data.get("cash"), Rules.STARTING_CASH)
	reputation = Saves.integer(data.get("reputation"), Rules.STARTING_REPUTATION, 100)
	income = Saves.integer(data.get("income"), 0)
	expenses = Saves.integer(data.get("expenses"), 0)
	var saved_review: Variant = data.get("last_review")
	last_review = saved_review.left(180) if saved_review is String else ""
	employee = data.get("employee") is bool and data.get("employee")
	wage_day = Saves.integer(data.get("wage_day"), 0, day)
	cleaner_in = Saves.integer(data.get("cleaner_in"), Rules.CLEANER_INTERVAL, 300)
	arrival_in = Saves.integer(data.get("arrival_in"), Rules.FIRST_ARRIVAL_SECONDS, 300)
	maintenance_in = Saves.integer(data.get("maintenance_in"), Rules.MAINTENANCE_FIRST_SECOND, 3600)
	haunt_in = Saves.integer(data.get("haunt_in"), Rules.HAUNT_FIRST_SECOND, 3600)
	if version < Saves.VERSION:
		maintenance_in = maxi(maintenance_in, Rules.MAINTENANCE_FIRST_SECOND)
		haunt_in = maxi(haunt_in, Rules.HAUNT_FIRST_SECOND)
	room_cursor = Saves.integer(data.get("room_cursor"), 0, rooms.size() - 1)
	haunt_cursor = Saves.integer(data.get("haunt_cursor"), 0, rooms.size() - 1)
	haunt_sequence = Saves.integer(data.get("haunt_sequence"), 0)
	maintenance_sequence = Saves.integer(data.get("maintenance_sequence"), 0)
	next_guest_id = maxi(1, Saves.integer(data.get("next_guest"), 1))
	var ids := {}
	var saved_rooms: Variant = data.get("rooms")
	if saved_rooms is Array:
		for index in mini(rooms.size(), saved_rooms.size()):
			if saved_rooms[index] is Dictionary:
				restore_room(index, saved_rooms[index], ids)
	var saved_waiting: Variant = data.get("waiting")
	if saved_waiting is Array:
		for index in mini(saved_waiting.size(), Rules.MAX_WAITING):
			if saved_waiting[index] is Dictionary:
				var guest := restore_guest(saved_waiting[index], ids)
				if not guest.is_empty() and guest.patience > 0:
					waiting.append(guest)
	var report: Variant = data.get("report")
	if report is Dictionary and Saves.integer(report.get("day"), 0) == day - 1 and day > 1:
		var earnings := Saves.integer(report.get("income"), 0)
		var charges := Saves.integer(report.get("expenses"), 0)
		var reviews: Variant = report.get("reviews")
		pending_report = {
			"day": day - 1, "income": earnings, "expenses": charges, "net": earnings - charges,
			"reviews": reviews.left(650) if reviews is String else "",
			"visitors": Saves.integer(report.get("visitors"), 0, Rules.ROOM_COUNT),
		}
	restore_task(data)


func restore_room(index: int, saved: Dictionary, ids: Dictionary) -> void:
	var room: Dictionary = rooms[index]
	room.open = index == 0 or (saved.get("open") is bool and saved.get("open"))
	if not room.open:
		return
	room.clean = Saves.number(saved.get("clean"), 100.0, 100.0)
	room.clean_until = Saves.integer(saved.get("clean_until"), 0)
	room.haunt_at = Saves.integer(saved.get("haunt_at"), 0)
	room.offer_at = Saves.integer(saved.get("offer_at"), 0)
	room.dirt_debt = Saves.number(saved.get("dirt_debt"), 0.0, 100.0)
	room.dirt_cause = Saves.integer(saved.get("dirt_cause"), DirtCause.TIME, DirtCause.LEAK)
	var items: Variant = saved.get("items")
	var broken := Saves.integer(saved.get("broken"), 0, (1 << Rules.SLOT_COUNT) - 1)
	if items is Array:
		for slot in mini(items.size(), Rules.SLOT_COUNT):
			room.items[slot] = Saves.integer(items[slot], 0, Rules.ITEM_PRICES.size())
			if room.items[slot] > 0 and (broken & (1 << slot)) != 0:
				room.broken |= 1 << slot
	var guest: Variant = saved.get("guest")
	if guest is Dictionary:
		room.guest = restore_guest(guest, ids)
	var incident := Saves.integer(saved.get("incident"), -1, Task.KEY)
	var incident_slot := Saves.integer(saved.get("incident_slot"), -1, Rules.SLOT_COUNT - 1)
	if incident == Task.LEAK or (incident == Task.BULB and Rules.item_kind(slot_item(index, incident_slot)) == Item.LAMP and broken_at(index, incident_slot)):
		room.incident = incident
		room.incident_slot = incident_slot
	if room.guest.is_empty():
		return
	room.checkout = clampi(Saves.integer(saved.get("checkout"), day + room.guest.nights), day + 1, day + Rules.MAX_STAY)
	if incident == Task.KEY or incident == Task.CALM:
		room.incident = incident
	room.request_in = Saves.integer(saved.get("request_in"), Rules.REQUEST_INTERVAL.x, 300)
	room.request = Saves.integer(saved.get("request"), -1, Request.AMENITY)
	room.requested_item = Saves.integer(saved.get("requested_item"), -1, Rules.ITEM_NAMES.size() - 1)
	room.deadline = Saves.integer(saved.get("deadline"), 0, Rules.REQUEST_DEADLINE)
	if room.deadline <= 0 or (room.request == Request.AMENITY and room.requested_item < 0):
		room.request = -1
		room.deadline = 0


func restore_task(data: Dictionary) -> void:
	task_wait = Saves.integer(data.get("task_wait"), 0, Rules.TASK_GAP)
	var index := Saves.integer(data.get("task_room"), -1, rooms.size() - 1)
	var kind := Saves.integer(data.get("task_kind"), -1, Rules.TASK_NAMES.size() - 1)
	if not is_open(index) or kind < 0:
		return
	task_room = index
	task_kind = kind
	task_slot = Saves.integer(data.get("task_slot"), -1, Rules.SLOT_COUNT - 1)
	task_expires = Saves.integer(data.get("task_expires"), 0)
	var reason: Variant = data.get("task_reason")
	task_reason = reason.left(200) if reason is String and not reason.is_empty() else "الغرفة %d تحتاج %s." % [101 + index, Rules.TASK_NAMES[kind]]
	if kind == Task.AMENITY and rooms[index].request == Request.AMENITY and not rooms[index].guest.is_empty():
		return
	if not can_do_task(index, kind, task_slot):
		clear_task()


func restore_guest(data: Dictionary, ids: Dictionary) -> Dictionary:
	var id := Saves.integer(data.get("id"), 0)
	if id <= 0 or ids.has(id):
		return {}
	ids[id] = true
	next_guest_id = maxi(next_guest_id, id + 1)
	return {
		"id": id, "name": Saves.integer(data.get("name"), 0, Rules.GUEST_NAMES.size() - 1),
		"look": Saves.integer(data.get("look"), 0, 3), "preference": Saves.integer(data.get("preference"), 0, Rules.PREFERENCES.size() - 1),
		"nights": maxi(Rules.MIN_STAY, Saves.integer(data.get("nights"), Rules.MIN_STAY, Rules.MAX_STAY)),
		"quality": Saves.integer(data.get("quality"), 0, 2), "budget": maxi(15, Saves.integer(data.get("budget"), 60, 200)),
		"patience": Saves.integer(data.get("patience"), Rules.GUEST_PATIENCE_SECONDS, Rules.GUEST_PATIENCE_SECONDS),
		"fulfilled": Saves.integer(data.get("fulfilled"), 0, 100), "missed": Saves.integer(data.get("missed"), 0, 100),
		"scares": Saves.integer(data.get("scares"), 0, 100),
	}
