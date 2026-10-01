extends Node
## Автозагрузка (GameState): деньги, улучшения, садок, журнал, сохранение в user://.

const SAVE_PATH := "user://fishing_save.json"
const MAX_LEVEL := 5
const UPGRADE_COSTS: Array = [80, 200, 450, 900, 1800]
const UPGRADES: Dictionary = {
	"rod": {"name": "Удочка", "desc": "Шире зелёная зона при вываживании"},
	"line": {"name": "Леска", "desc": "Рыба медленнее срывается с крючка"},
	"bait": {"name": "Наживка", "desc": "Клёв быстрее, чаще попадаются редкие рыбы"},
}

var money: int = 0
var levels: Dictionary = {"rod": 0, "line": 0, "bait": 0}
var unlocked_lakes: Array = [0]
var current_lake: int = 0
var journal: Dictionary = {}  # id -> {"count": int, "best": float}
var inventory: Array = []  # [{"id": String, "weight": float, "price": int}]
var total_caught: int = 0


func _ready() -> void:
	load_game()


func level(kind: String) -> int:
	return int(levels.get(kind, 0))


## Цена следующего уровня или -1, если достигнут максимум.
func upgrade_cost(kind: String) -> int:
	var lv: int = level(kind)
	if lv >= MAX_LEVEL:
		return -1
	return int(UPGRADE_COSTS[lv])


func buy_upgrade(kind: String) -> bool:
	var cost: int = upgrade_cost(kind)
	if cost < 0 or money < cost:
		return false
	money -= cost
	levels[kind] = level(kind) + 1
	save_game()
	return true


func is_lake_unlocked(idx: int) -> bool:
	return unlocked_lakes.has(idx)


func unlock_lake(idx: int) -> bool:
	if is_lake_unlocked(idx):
		return true
	var cost: int = int(FishData.LAKES[idx]["cost"])
	if money < cost:
		return false
	money -= cost
	unlocked_lakes.append(idx)
	save_game()
	return true


func select_lake(idx: int) -> void:
	if is_lake_unlocked(idx):
		current_lake = idx
		save_game()


## Кладёт рыбу в садок и обновляет журнал. Возвращает {"new_species": bool, "record": bool}.
func add_fish(id: String, weight: float, price: int) -> Dictionary:
	inventory.append({"id": id, "weight": weight, "price": price})
	total_caught += 1
	var entry: Dictionary = journal.get(id, {"count": 0, "best": 0.0})
	var is_new: bool = int(entry["count"]) == 0
	var is_record: bool = weight > float(entry["best"])
	entry["count"] = int(entry["count"]) + 1
	if is_record:
		entry["best"] = weight
	journal[id] = entry
	save_game()
	return {"new_species": is_new, "record": is_record and not is_new}


func inventory_value() -> int:
	var sum: int = 0
	for item in inventory:
		sum += int(item["price"])
	return sum


## Продаёт весь садок, возвращает выручку.
func sell_all() -> int:
	var earned: int = inventory_value()
	money += earned
	inventory.clear()
	save_game()
	return earned


func save_game() -> void:
	var data := {
		"money": money,
		"levels": levels,
		"unlocked_lakes": unlocked_lakes,
		"current_lake": current_lake,
		"journal": journal,
		"inventory": inventory,
		"total_caught": total_caught,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Не удалось сохранить игру: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	money = int(d.get("money", 0))
	total_caught = int(d.get("total_caught", 0))
	current_lake = int(d.get("current_lake", 0))

	var saved_levels: Dictionary = d.get("levels", {})
	for kind in ["rod", "line", "bait"]:
		levels[kind] = clampi(int(saved_levels.get(kind, 0)), 0, MAX_LEVEL)

	unlocked_lakes = [0]
	for v in d.get("unlocked_lakes", [0]):
		var idx: int = int(v)
		if idx >= 0 and idx < FishData.LAKES.size() and not unlocked_lakes.has(idx):
			unlocked_lakes.append(idx)
	if not unlocked_lakes.has(current_lake):
		current_lake = 0

	journal = {}
	var saved_journal: Dictionary = d.get("journal", {})
	for id in saved_journal:
		if FishData.FISH.has(id):
			var e: Dictionary = saved_journal[id]
			journal[id] = {"count": int(e.get("count", 0)), "best": float(e.get("best", 0.0))}

	inventory = []
	for item in d.get("inventory", []):
		if FishData.FISH.has(item.get("id", "")):
			inventory.append({
				"id": String(item["id"]),
				"weight": float(item.get("weight", 0.0)),
				"price": int(item.get("price", 0)),
			})
