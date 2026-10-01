class_name FishData
extends RefCounted
## Данные игры: водоёмы и виды рыб. Чтобы добавить рыбу, дополни FISH и впиши её id в нужный водоём.

# sky / sky2 — верх и низ неба, water — вода, hills — холмы на горизонте.
const LAKES: Array = [
	{
		"name": "Тихий пруд",
		"cost": 0,
		"sky": "9fd8f2", "sky2": "e6f6fc",
		"water": "2f8aa8", "hills": "7bb381",
		"fish": ["crucian", "roach", "perch", "goldfish"],
	},
	{
		"name": "Быстрая река",
		"cost": 400,
		"sky": "8ec5e8", "sky2": "f3ead2",
		"water": "2c6f8f", "hills": "5f9a68",
		"fish": ["bream", "chub", "pike", "trout", "zander"],
	},
	{
		"name": "Глубокое озеро",
		"cost": 1500,
		"sky": "f2a65a", "sky2": "fbd9a6",
		"water": "1f4e73", "hills": "496e5a",
		"fish": ["carp", "burbot", "pike", "catfish", "sturgeon"],
	},
]

# price — базовая цена, speed — насколько быстро рыба мечется при вываживании (0..1),
# min_w / max_w — вес в кг, weight — шанс клёва (чем меньше, тем реже).
const FISH: Dictionary = {
	"crucian": {"name": "Карась", "price": 8, "speed": 0.35, "min_w": 0.2, "max_w": 0.9, "weight": 50, "color": "c9a24a"},
	"roach": {"name": "Плотва", "price": 6, "speed": 0.40, "min_w": 0.1, "max_w": 0.5, "weight": 50, "color": "b8c4cc"},
	"perch": {"name": "Окунь", "price": 12, "speed": 0.50, "min_w": 0.15, "max_w": 0.8, "weight": 40, "color": "7a9a3a"},
	"goldfish": {"name": "Золотая рыбка", "price": 90, "speed": 0.80, "min_w": 0.3, "max_w": 1.2, "weight": 6, "color": "ffc107"},
	"bream": {"name": "Лещ", "price": 25, "speed": 0.45, "min_w": 0.5, "max_w": 2.5, "weight": 45, "color": "a8a28a"},
	"chub": {"name": "Голавль", "price": 30, "speed": 0.60, "min_w": 0.4, "max_w": 2.0, "weight": 35, "color": "8fa6b3"},
	"pike": {"name": "Щука", "price": 55, "speed": 0.80, "min_w": 1.0, "max_w": 6.0, "weight": 25, "color": "6b8e4e"},
	"trout": {"name": "Форель", "price": 70, "speed": 0.85, "min_w": 0.3, "max_w": 2.5, "weight": 18, "color": "e57f84"},
	"zander": {"name": "Судак", "price": 65, "speed": 0.75, "min_w": 0.8, "max_w": 5.0, "weight": 20, "color": "7d8f9a"},
	"carp": {"name": "Карп", "price": 85, "speed": 0.70, "min_w": 1.0, "max_w": 9.0, "weight": 40, "color": "b5833a"},
	"burbot": {"name": "Налим", "price": 80, "speed": 0.65, "min_w": 0.7, "max_w": 4.0, "weight": 30, "color": "7b6a4a"},
	"catfish": {"name": "Сом", "price": 160, "speed": 0.95, "min_w": 5.0, "max_w": 40.0, "weight": 12, "color": "4a4f45"},
	"sturgeon": {"name": "Осётр", "price": 300, "speed": 1.00, "min_w": 5.0, "max_w": 30.0, "weight": 5, "color": "6f7f8c"},
}


## Случайная рыба для водоёма. Наживка повышает шанс редких видов.
static func pick_fish(lake_idx: int, bait_level: int) -> String:
	var ids: Array = LAKES[lake_idx]["fish"]
	var weights: Array = []
	var total: float = 0.0
	for id in ids:
		var w: float = float(FISH[id]["weight"])
		if w <= 25.0:
			w *= 1.0 + 0.3 * bait_level
		weights.append(w)
		total += w
	var r: float = randf() * total
	for i in ids.size():
		r -= float(weights[i])
		if r <= 0.0:
			return String(ids[i])
	return String(ids[0])


## Вес пойманной рыбы: крупные экземпляры встречаются реже.
static func roll_weight(id: String) -> float:
	var f: Dictionary = FISH[id]
	var u: float = randf()
	u = u * u
	return snappedf(lerpf(float(f["min_w"]), float(f["max_w"]), u), 0.01)


## Цена зависит от веса: от 70% до 150% базовой.
static func price_for(id: String, weight: float) -> int:
	var f: Dictionary = FISH[id]
	var k: float = inverse_lerp(float(f["min_w"]), float(f["max_w"]), weight)
	return int(round(float(f["price"]) * (0.7 + 0.8 * k)))
