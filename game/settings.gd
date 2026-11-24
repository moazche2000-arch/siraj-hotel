extends RefCounted

const PLAYER_SPEED := 82.5
const STARTING_CASH := 100
const STARTING_REPUTATION := 35
const DAY_SECONDS := 100
const AUTOSAVE_SECONDS := 12
const ROOM_COUNT := 6
const SLOT_COUNT := 6
const ROOM_PRICES := [0, 135, 240, 385, 565, 800]

const MIN_STAY := 2
const MAX_STAY := 5
const MAX_WAITING := 3
const FIRST_ARRIVAL_SECONDS := 7
const GUEST_PATIENCE_SECONDS := 55
const ARRIVAL_INTERVAL := Vector2i(15, 32)
const REQUEST_DEADLINE := 32
const REQUEST_INTERVAL := Vector2i(28, 54)
const REQUEST_REWARDS := [10, 14, 18]
const OCCUPIED_DIRT_PER_SECOND := 0.31
const EMPTY_DIRT_PER_SECOND := 0.045
const LEAK_DIRT_PER_SECOND := 0.29
const CLEANING_THRESHOLD := 88.0
const CLEANING_GAIN := 74.0
const BASE_NIGHTLY_RATE := 34
const COMFORT_RATE := 0.65
const CLEANLINESS_RATE := 0.17
const EXCELLENT_ROOM_BONUS := 9
const DIRTY_ROOM_DISCOUNT := 9
const BROKEN_ITEM_DISCOUNT := 5
const ROOM_DAILY_COST := 6
const CLEANER_WAGE := 17
const CLEANER_INTERVAL := 18
const CLEANER_GAIN := 18.0
const HAUNT_FIRST_DAY := 2
const HAUNT_FIRST_SECOND := 19
const HAUNT_MIN_INTERVAL := 17
const HAUNT_START_INTERVAL := 52
const HAUNT_DIRT := 24.0
const MAINTENANCE_INTERVAL := Vector2i(35, 63)

const UPGRADE_NAMES := ["عربة تنظيف أسرع", "أقفال تحمي الأثاث", "تجهيزات للضيوف"]
const UPGRADE_PRICES := [140, 210, 300]
const AMENITIES_NIGHTLY_BONUS := 12
const LOCK_BREAK_RISK_PERCENT := 0

enum Task { CLEAN, REPAIR, LEAK, BULB, CALM, BANISH, KEY }
enum Request { CLEAN, REPAIR, AMENITY }
enum Item { BED, DESK, CHAIR, RUG, LAMP, WARDROBE, TV }
enum Preference { CLEAN, COMFORT, BUDGET }

const TASK_NAMES := ["كنس ومسح", "إصلاح الأثاث", "إيقاف التسريب", "تبديل اللمبة", "تهدئة الضيف", "طرد الجن", "البحث عن المفتاح"]
const PREFERENCES := ["يهتم بالنظافة", "يفضّل الأثاث المريح", "ميزانيته محدودة"]
const GUEST_TIERS := ["مسافر", "نزيل ميسور", "نزيل مميّز"]
const GUEST_NAMES := ["سالم العتيبي", "فهد النجار", "حسن الصيّاد", "يوسف المرسي", "ماجد البحري", "علي الدرويش", "خالد الرفاعي", "سعيد منصور", "ناصر الصالح", "كريم أمين", "إبراهيم حمزة", "عبدالله جابر"]
const ITEM_NAMES := ["سرير", "مكتب", "كرسي", "سجادة", "مصباح", "خزانة", "تلفزيون"]
const QUALITY_NAMES := ["عادي", "فاخر"]
const ITEM_PRICES := [48, 112, 27, 68, 17, 42, 19, 52, 15, 39, 38, 89, 69, 148]
const ITEM_COMFORT := [8, 18, 4, 10, 3, 8, 4, 11, 3, 8, 5, 12, 9, 20]
const ITEM_FOOTPRINTS := [
	Vector2(77, 33), Vector2(66, 30), Vector2(36, 32), Vector2.ZERO,
	Vector2(25, 24), Vector2(65, 29), Vector2(54, 31),
]


static func valid_item(item: int) -> bool:
	return item > 0 and item <= ITEM_PRICES.size()


static func item_kind(item: int) -> int:
	return (item - 1) >> 1 if valid_item(item) else -1


static func item_name(item: int) -> String:
	var kind := item_kind(item)
	return "%s %s" % [ITEM_NAMES[kind], QUALITY_NAMES[(item - 1) % 2]] if kind >= 0 else "خانة فاضية"
