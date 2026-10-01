extends Node2D
## Рыбалка — симулятор с прокачкой.
## Сцена рисуется кодом (_draw), интерфейс строится в _build_ui(), данные лежат в GameState и FishData.

enum State { IDLE, WAITING, BITE, REELING, RESULT }

const W := 1152.0
const H := 648.0
const WATER_Y := 300.0
const ROD_TIP := Vector2(380.0, 235.0)
const FISHERMAN := Vector2(250.0, 410.0)
const BAR := Rect2(930.0, 130.0, 46.0, 400.0)

var state: State = State.IDLE
var t: float = 0.0
var wait_timer: float = 0.0
var bite_timer: float = 0.0
var bobber_pos: Vector2 = Vector2(600.0, 480.0)
var splash: float = 0.0
var shadows: Array = []

var cur_fish_id: String = ""

# Мини-игра вываживания: позиции от 0 (низ) до 1 (верх).
var fish_pos: float = 0.5
var fish_target: float = 0.5
var fish_retarget: float = 0.0
var zone_pos: float = 0.0
var zone_vel: float = 0.0
var zone_size: float = 0.25
var progress: float = 0.3

var result_text: String = ""
var result_good: bool = false
var result_timer: float = 0.0

var money_label: Label
var lake_label: Label
var shop_btn: Button
var map_btn: Button
var journal_btn: Button
var overlay: PanelContainer
var panel_box: VBoxContainer
var panel_kind: String = ""


func _ready() -> void:
	for i in 7:
		shadows.append({
			"x": randf() * W,
			"y": randf_range(WATER_Y + 80.0, H - 40.0),
			"speed": randf_range(8.0, 30.0),
			"size": randf_range(10.0, 22.0),
		})
	_build_ui()
	_update_hud()
	_set_state(State.IDLE)


# ---------------------------------------------------------------- логика

func _set_state(s: State) -> void:
	state = s
	var can_open: bool = s == State.IDLE
	shop_btn.disabled = not can_open
	map_btn.disabled = not can_open
	journal_btn.disabled = not can_open


func _process(delta: float) -> void:
	t += delta
	splash = maxf(0.0, splash - delta * 1.2)
	for s in shadows:
		s["x"] += float(s["speed"]) * delta
		if s["x"] > W + 80.0:
			s["x"] = -80.0
	match state:
		State.WAITING:
			wait_timer -= delta
			if wait_timer <= 0.0:
				_start_bite()
		State.BITE:
			bite_timer -= delta
			if bite_timer <= 0.0:
				_end_round("Клюнуло, но ты не успел подсечь.", false)
		State.REELING:
			_update_reel(delta)
		State.RESULT:
			result_timer += delta
			if result_timer > 4.0:
				_set_state(State.IDLE)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if overlay.visible:
		if key and key.pressed and key.keycode == KEY_ESCAPE:
			_close_panel()
		return
	if key and key.pressed and not key.echo:
		match key.keycode:
			KEY_SPACE:
				_on_action()
			KEY_S:
				_open_panel("shop")
			KEY_M:
				_open_panel("map")
			KEY_J:
				_open_panel("journal")
		return
	var mouse := event as InputEventMouseButton
	if mouse and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		_on_action()


func _on_action() -> void:
	match state:
		State.IDLE:
			_cast()
		State.WAITING:
			_set_state(State.IDLE)
		State.BITE:
			_hook()
		State.RESULT:
			if result_timer > 0.5:
				_set_state(State.IDLE)


func _cast() -> void:
	var bait: int = GameState.level("bait")
	wait_timer = maxf(1.2, randf_range(2.5, 6.5) - 0.5 * bait)
	bobber_pos = Vector2(randf_range(500.0, 820.0), randf_range(430.0, 560.0))
	splash = 1.0
	_set_state(State.WAITING)


func _start_bite() -> void:
	cur_fish_id = FishData.pick_fish(GameState.current_lake, GameState.level("bait"))
	bite_timer = 1.3
	_set_state(State.BITE)


func _hook() -> void:
	zone_size = 0.20 + 0.035 * GameState.level("rod")
	zone_pos = 0.0
	zone_vel = 0.0
	fish_pos = 0.4
	fish_target = 0.4
	fish_retarget = 0.5
	progress = 0.3
	_set_state(State.REELING)


func _update_reel(delta: float) -> void:
	var f: Dictionary = FishData.FISH[cur_fish_id]
	var speed: float = float(f["speed"])

	# Рыба плывёт к случайной точке и время от времени меняет цель.
	fish_retarget -= delta
	if fish_retarget <= 0.0:
		fish_target = randf()
		fish_retarget = randf_range(0.6, 1.6)
	fish_pos = move_toward(fish_pos, fish_target, speed * delta)

	# Зелёная зона: пока держишь кнопку — поднимается, иначе падает.
	var holding: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	zone_vel += (2.4 if holding else -2.0) * delta
	zone_vel = clampf(zone_vel, -1.2, 1.2)
	zone_pos += zone_vel * delta
	var max_pos: float = 1.0 - zone_size
	if zone_pos < 0.0:
		zone_pos = 0.0
		zone_vel = 0.0
	elif zone_pos > max_pos:
		zone_pos = max_pos
		zone_vel = 0.0

	var inside: bool = fish_pos >= zone_pos and fish_pos <= zone_pos + zone_size
	if inside:
		progress += 0.28 * delta
	else:
		var loss: float = maxf(0.06, 0.20 - 0.03 * GameState.level("line"))
		progress -= loss * (1.0 + speed * 0.5) * delta

	if progress >= 1.0:
		_catch()
	elif progress <= 0.0:
		_end_round("Рыба ушла вместе с наживкой.", false)


func _catch() -> void:
	var weight: float = FishData.roll_weight(cur_fish_id)
	var price: int = FishData.price_for(cur_fish_id, weight)
	var info: Dictionary = GameState.add_fish(cur_fish_id, weight, price)
	var fname: String = FishData.FISH[cur_fish_id]["name"]
	var text: String = "%s, %.2f кг  (~%d монет)" % [fname, weight, price]
	if info["new_species"]:
		text += "\nНовый вид в журнале!"
	elif info["record"]:
		text += "\nНовый рекорд веса!"
	_update_hud()
	_end_round(text, true)


func _end_round(text: String, good: bool) -> void:
	result_text = text
	result_good = good
	result_timer = 0.0
	_set_state(State.RESULT)


# ---------------------------------------------------------------- интерфейс

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	money_label = Label.new()
	money_label.position = Vector2(18.0, 12.0)
	_style_hud_label(money_label)
	root.add_child(money_label)

	lake_label = Label.new()
	lake_label.custom_minimum_size = Vector2(300.0, 0.0)
	lake_label.position = Vector2(W * 0.5 - 150.0, 12.0)
	lake_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_hud_label(lake_label)
	root.add_child(lake_label)

	var top := HBoxContainer.new()
	top.position = Vector2(W - 420.0, 10.0)
	root.add_child(top)
	shop_btn = _make_button("Магазин (S)", func(): _open_panel("shop"))
	map_btn = _make_button("Карта (M)", func(): _open_panel("map"))
	journal_btn = _make_button("Журнал (J)", func(): _open_panel("journal"))
	top.add_child(shop_btn)
	top.add_child(map_btn)
	top.add_child(journal_btn)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	overlay = PanelContainer.new()
	overlay.visible = false
	overlay.custom_minimum_size = Vector2(640.0, 0.0)
	center.add_child(overlay)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	overlay.add_child(margin)
	panel_box = VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 10)
	margin.add_child(panel_box)


func _style_hud_label(l: Label) -> void:
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("outline_size", 6)


func _make_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE  # чтобы Пробел не «нажимал» кнопки
	b.pressed.connect(cb)
	return b


func _update_hud() -> void:
	money_label.text = "Монеты: %d    Садок: %d" % [GameState.money, GameState.inventory.size()]
	lake_label.text = FishData.LAKES[GameState.current_lake]["name"]


func _open_panel(kind: String) -> void:
	if state != State.IDLE:
		return
	panel_kind = kind
	_refresh_panel()
	overlay.visible = true


func _close_panel() -> void:
	overlay.visible = false
	panel_kind = ""
	_update_hud()


func _refresh_panel() -> void:
	for c in panel_box.get_children():
		panel_box.remove_child(c)
		c.queue_free()
	match panel_kind:
		"shop":
			_build_shop()
		"map":
			_build_map()
		"journal":
			_build_journal()
	panel_box.add_child(_make_button("Закрыть (Esc)", _close_panel))


func _add_label(text: String, size: int = 16, wrap_width: float = 0.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if wrap_width > 0.0:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(wrap_width, 0.0)
	panel_box.add_child(l)
	return l


func _build_shop() -> void:
	_add_label("Магазин", 28)
	var n: int = GameState.inventory.size()
	var row := HBoxContainer.new()
	var info := Label.new()
	info.text = "В садке: %d шт. на %d монет" % [n, GameState.inventory_value()]
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var sell := _make_button("Продать всё", _on_sell_all)
	sell.disabled = n == 0
	row.add_child(sell)
	panel_box.add_child(row)
	panel_box.add_child(HSeparator.new())
	for kind in ["rod", "line", "bait"]:
		panel_box.add_child(_upgrade_row(kind))


func _upgrade_row(kind: String) -> Control:
	var info: Dictionary = GameState.UPGRADES[kind]
	var lv: int = GameState.level(kind)
	var row := HBoxContainer.new()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = "%s — уровень %d/%d" % [info["name"], lv, GameState.MAX_LEVEL]
	var desc := Label.new()
	desc.text = info["desc"]
	desc.modulate = Color(1, 1, 1, 0.65)
	col.add_child(title)
	col.add_child(desc)
	row.add_child(col)
	var cost: int = GameState.upgrade_cost(kind)
	var btn: Button
	if cost < 0:
		btn = _make_button("Максимум", func(): pass)
		btn.disabled = true
	else:
		btn = _make_button("%d монет" % cost, _on_buy_upgrade.bind(kind))
		btn.disabled = GameState.money < cost
	row.add_child(btn)
	return row


func _on_sell_all() -> void:
	GameState.sell_all()
	_update_hud()
	_refresh_panel()


func _on_buy_upgrade(kind: String) -> void:
	if GameState.buy_upgrade(kind):
		_update_hud()
		_refresh_panel()


func _build_map() -> void:
	_add_label("Карта водоёмов", 28)
	for i in FishData.LAKES.size():
		var lake: Dictionary = FishData.LAKES[i]
		var row := HBoxContainer.new()
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var here: bool = i == GameState.current_lake
		var title := Label.new()
		title.text = String(lake["name"]) + ("  (вы здесь)" if here else "")
		var names := PackedStringArray()
		for id in lake["fish"]:
			names.append(String(FishData.FISH[id]["name"]))
		var desc := Label.new()
		desc.text = "Рыба: " + ", ".join(names)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(380.0, 0.0)
		desc.modulate = Color(1, 1, 1, 0.65)
		col.add_child(title)
		col.add_child(desc)
		row.add_child(col)
		var btn: Button
		if GameState.is_lake_unlocked(i):
			btn = _make_button("Рыбачить здесь", _on_select_lake.bind(i))
			btn.disabled = here
		else:
			var cost: int = int(lake["cost"])
			btn = _make_button("Открыть за %d" % cost, _on_buy_lake.bind(i))
			btn.disabled = GameState.money < cost
		row.add_child(btn)
		panel_box.add_child(row)
		panel_box.add_child(HSeparator.new())


func _on_select_lake(i: int) -> void:
	GameState.select_lake(i)
	_update_hud()
	_refresh_panel()


func _on_buy_lake(i: int) -> void:
	if GameState.unlock_lake(i):
		_update_hud()
		_refresh_panel()


func _build_journal() -> void:
	_add_label("Журнал уловов", 28)
	_add_label("Всего поймано: %d" % GameState.total_caught)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 340.0)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for id in FishData.FISH:
		var l := Label.new()
		if GameState.journal.has(id):
			var e: Dictionary = GameState.journal[id]
			l.text = "%s — поймано %d, рекорд %.2f кг" % [FishData.FISH[id]["name"], int(e["count"]), float(e["best"])]
		else:
			l.text = "???"
			l.modulate = Color(1, 1, 1, 0.45)
		list.add_child(l)
	panel_box.add_child(scroll)


# ---------------------------------------------------------------- отрисовка

func _text(pos: Vector2, text: String, size: int, color: Color, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var font: Font = ThemeDB.fallback_font
	var lines := text.split("\n")
	for i in lines.size():
		var p: Vector2 = pos + Vector2(0.0, i * size * 1.25)
		draw_string_outline(font, p, lines[i], align, width, size, int(size * 0.2), Color(0, 0, 0, 0.7))
		draw_string(font, p, lines[i], align, width, size, color)


func _draw() -> void:
	var lake: Dictionary = FishData.LAKES[GameState.current_lake]
	_draw_sky(lake)
	_draw_water(lake)
	_draw_pier_and_fisherman()
	_draw_line_and_bobber()
	if state == State.REELING:
		_draw_reel_minigame()
	draw_rect(Rect2(0.0, 0.0, W, 54.0), Color(0, 0, 0, 0.35))
	_draw_hint_text()


func _draw_sky(lake: Dictionary) -> void:
	var top: Color = Color.html(lake["sky"])
	var low: Color = Color.html(lake["sky2"])
	var bands: int = 14
	var bh: float = WATER_Y / bands
	for i in bands:
		draw_rect(Rect2(0.0, bh * i, W, bh + 1.0), top.lerp(low, float(i) / (bands - 1)))
	draw_circle(Vector2(930.0, 110.0), 62.0, Color(1.0, 0.96, 0.75, 0.25))
	draw_circle(Vector2(930.0, 110.0), 44.0, Color(1.0, 0.96, 0.75, 0.95))
	for i in 3:
		var cx: float = fposmod(120.0 + i * 420.0 + t * (6.0 + i * 3.0), W + 240.0) - 120.0
		var cy: float = 80.0 + i * 38.0
		var cc := Color(1, 1, 1, 0.75)
		draw_circle(Vector2(cx, cy), 22.0, cc)
		draw_circle(Vector2(cx + 24.0, cy - 8.0), 28.0, cc)
		draw_circle(Vector2(cx + 54.0, cy), 22.0, cc)
	var hills: Color = Color.html(lake["hills"])
	_draw_hills(hills.lightened(0.18), 70.0, 0.006, 0.0)
	_draw_hills(hills, 38.0, 0.011, 2.0)


func _draw_hills(col: Color, height: float, freq: float, phase: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(0.0, WATER_Y))
	var x: float = 0.0
	while x <= W + 32.0:
		var y: float = WATER_Y - height - 26.0 * sin(x * freq + phase) - 14.0 * sin(x * freq * 2.7 + phase * 1.3)
		pts.append(Vector2(x, y))
		x += 32.0
	pts.append(Vector2(W + 32.0, WATER_Y))
	draw_colored_polygon(pts, col)


func _draw_water(lake: Dictionary) -> void:
	var water: Color = Color.html(lake["water"])
	var bands: int = 10
	var bh: float = (H - WATER_Y) / bands
	for i in bands:
		draw_rect(Rect2(0.0, WATER_Y + bh * i, W, bh + 1.0), water.darkened(0.45 * float(i) / bands))
	for row in 7:
		var y0: float = WATER_Y + 22.0 + row * 46.0
		var pts := PackedVector2Array()
		for xi in range(0, 73):
			var x: float = xi * 16.0
			pts.append(Vector2(x, y0 + sin(x * 0.03 + t * 1.6 + row) * 3.0))
		draw_polyline(pts, Color(1, 1, 1, 0.12), 2.0)
	for s in shadows:
		_draw_fish(Vector2(s["x"], s["y"]), float(s["size"]), Color(0, 0, 0, 0.18))


func _draw_fish(c: Vector2, s: float, col: Color) -> void:
	draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
	draw_circle(Vector2.ZERO, s, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(-s * 0.8, 0.0),
		c + Vector2(-s * 1.6, -s * 0.6),
		c + Vector2(-s * 1.6, s * 0.6),
	]), col)
	if col.a > 0.5:
		draw_circle(c + Vector2(s * 0.5, -s * 0.1), maxf(1.5, s * 0.12), Color.BLACK)


func _draw_pier_and_fisherman() -> void:
	var wood: Color = Color.html("8a5a35")
	var dark: Color = Color.html("5e3b20")
	for px in [36.0, 170.0, 310.0]:
		draw_rect(Rect2(px, 432.0, 14.0, 130.0), dark)
	draw_rect(Rect2(0.0, 408.0, 340.0, 26.0), wood)
	for i in range(0, 9):
		draw_line(Vector2(i * 42.0, 408.0), Vector2(i * 42.0, 434.0), dark, 2.0)

	var f: Vector2 = FISHERMAN
	var pants: Color = Color.html("2d3a5a")
	var skin: Color = Color.html("f1c9a0")
	var straw: Color = Color.html("e0b04a")
	draw_rect(Rect2(f.x - 12.0, f.y - 38.0, 10.0, 38.0), pants)
	draw_rect(Rect2(f.x + 2.0, f.y - 38.0, 10.0, 38.0), pants)
	draw_rect(Rect2(f.x - 15.0, f.y - 82.0, 30.0, 46.0), Color.html("d9534f"))
	draw_circle(f + Vector2(0.0, -96.0), 14.0, skin)
	draw_rect(Rect2(f.x - 20.0, f.y - 112.0, 40.0, 8.0), straw)
	draw_rect(Rect2(f.x - 12.0, f.y - 124.0, 24.0, 14.0), straw)
	var hand: Vector2 = f + Vector2(14.0, -62.0)
	draw_line(f + Vector2(8.0, -76.0), hand, skin, 6.0)
	draw_line(hand, _rod_tip(), Color.html("4a3320"), 4.0)


func _rod_tip() -> Vector2:
	match state:
		State.REELING:
			return ROD_TIP + Vector2(0.0, 14.0 + sin(t * 18.0) * 3.0)
		State.BITE:
			return ROD_TIP + Vector2(0.0, 8.0 + sin(t * 40.0) * 4.0)
	return ROD_TIP


func _bobber_now() -> Vector2:
	var p: Vector2 = bobber_pos
	match state:
		State.WAITING:
			p.y += sin(t * 2.2) * 2.5
		State.BITE:
			p += Vector2(sin(t * 38.0) * 3.0, absf(sin(t * 22.0)) * 9.0)
		State.REELING:
			p = Vector2(bobber_pos.x + (fish_pos - 0.5) * 80.0, bobber_pos.y + sin(t * 9.0) * 4.0)
	return p


func _draw_line_and_bobber() -> void:
	if state == State.IDLE or state == State.RESULT:
		return
	var tip: Vector2 = _rod_tip()
	var bob: Vector2 = _bobber_now()
	var sag: float = 34.0 if state == State.WAITING else 10.0
	var ctrl: Vector2 = (tip + bob) * 0.5 + Vector2(0.0, sag)
	var pts := PackedVector2Array()
	for i in range(0, 21):
		var u: float = i / 20.0
		pts.append(tip.lerp(ctrl, u).lerp(ctrl.lerp(bob, u), u))
	draw_polyline(pts, Color(1, 1, 1, 0.85), 1.5)

	# Круги на воде.
	var ripples: int = 3 if state == State.BITE else 1
	var ripple_speed: float = 30.0 if state == State.BITE else 14.0
	draw_set_transform(bobber_pos + Vector2(0.0, 6.0), 0.0, Vector2(1.0, 0.35))
	for k in ripples:
		var r: float = fposmod(t * ripple_speed + k * 12.0, 36.0)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(1, 1, 1, 1.0 - r / 36.0), 2.0)
	if splash > 0.0:
		draw_arc(Vector2.ZERO, (1.0 - splash) * 60.0, 0.0, TAU, 32, Color(1, 1, 1, splash), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var red: Color = Color.html("e53935")
	draw_circle(bob, 9.0, Color.WHITE)
	draw_circle(bob + Vector2(0.0, -4.0), 6.0, red)
	draw_line(bob + Vector2(0.0, -9.0), bob + Vector2(0.0, -22.0), red, 3.0)
	if state == State.BITE:
		_text(bob + Vector2(-8.0, -42.0), "!", 44, Color.html("ffeb3b"))


func _draw_reel_minigame() -> void:
	var f: Dictionary = FishData.FISH[cur_fish_id]
	draw_rect(Rect2(BAR.position - Vector2(16.0, 52.0), BAR.size + Vector2(76.0, 70.0)), Color(0, 0, 0, 0.5))
	_text(Vector2(BAR.position.x - 6.0, BAR.position.y - 24.0), "Вываживание", 18, Color.WHITE)
	draw_rect(BAR, Color(0.08, 0.18, 0.28, 0.95))

	var zh: float = zone_size * BAR.size.y
	var zy: float = BAR.end.y - (zone_pos + zone_size) * BAR.size.y
	var inside: bool = fish_pos >= zone_pos and fish_pos <= zone_pos + zone_size
	draw_rect(Rect2(BAR.position.x, zy, BAR.size.x, zh), Color(0.3, 0.85, 0.4, 0.85 if inside else 0.55))

	var fy: float = BAR.end.y - fish_pos * BAR.size.y
	_draw_fish(Vector2(BAR.position.x + BAR.size.x * 0.5 + 6.0, fy), 11.0, Color.html(f["color"]))

	var px: float = BAR.end.x + 14.0
	draw_rect(Rect2(px, BAR.position.y, 14.0, BAR.size.y), Color(0.08, 0.18, 0.28, 0.95))
	var ph: float = progress * BAR.size.y
	draw_rect(Rect2(px, BAR.end.y - ph, 14.0, ph), Color(1.0, 0.3, 0.25).lerp(Color(0.3, 0.9, 0.4), progress))


func _draw_hint_text() -> void:
	var center := HORIZONTAL_ALIGNMENT_CENTER
	match state:
		State.IDLE:
			_text(Vector2(0.0, H - 28.0), "Пробел или клик — забросить удочку", 22, Color.WHITE, W, center)
		State.WAITING:
			_text(Vector2(0.0, H - 28.0), "Ждём поклёвку...  (клик — смотать удочку)", 22, Color.WHITE, W, center)
		State.BITE:
			_text(Vector2(0.0, 160.0), "КЛЮЁТ! ЖМИ!", 54, Color.html("ffeb3b"), W, center)
		State.REELING:
			_text(Vector2(0.0, H - 28.0), "Зажимай Пробел или кнопку мыши — зелёная зона поднимается. Держи в ней рыбу!", 20, Color.WHITE, W, center)
		State.RESULT:
			var rect := Rect2(W * 0.5 - 300.0, 130.0, 600.0, 150.0)
			draw_rect(rect, Color(0, 0, 0, 0.6))
			var head: String = "Улов!" if result_good else "Не повезло..."
			var head_color: Color = Color.html("ffeb3b") if result_good else Color.html("ff8a80")
			_text(Vector2(rect.position.x, 175.0), head, 34, head_color, rect.size.x, center)
			_text(Vector2(rect.position.x, 222.0), result_text, 22, Color.WHITE, rect.size.x, center)
			if result_good:
				var f: Dictionary = FishData.FISH[cur_fish_id]
				_draw_fish(Vector2(W * 0.5 + 30.0, 100.0), 26.0, Color.html(f["color"]))
