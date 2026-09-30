extends Node2D
## 回合仪式场景（GDD §八《回廊守灯》原型）：复用背景/卡牌/特效/回合 UI，
## 胜负由目标条件判断，不伪装成高血量敌人。
## 规则唯一来源 BattleRulesV4.ritual_*；本场景只做表现与输入。

const BattleCardScript = preload("res://scripts/ui/battle_card.gd")
const UIThemeScript = preload("res://scripts/ui/theme.gd")
const SfxScript = preload("res://scripts/ui/sfx.gd")
const InkTransitionScript = preload("res://scripts/ui/ink_transition.gd")
const PngLoaderScript = preload("res://scripts/ui/png_loader.gd")

@export var ritual_data_path := "res://data/rituals/ritual_lamp.json"

var _theme = null
var _cfg: Dictionary = {}
var _artifact: Dictionary = {}

# 回合状态
var _turn := 0
var _max_turns := 6
var _ap := 0
var _ap_max := 6
var _hp := 30
var _hp_max := 30
var _shield := 0
var _busy := false
var _over := false
# 引灯（GDD §8.3）
var _lamp := 4
var _lamp_max := 6
var _add_fuel_used := false
var _items: Array = [] # {def, uses_left}
var _objectives := {} # id: {def, done}
# 牌（仪式中只有术法/防护类可用；attack/slot/seal 置灰并说明原因）
var _deck: Array = []
var _discard: Array = []
var _cards: Array = []
var _hand_limit := 5
var _player: Sprite2D = null
var _idle_frames: Array = []
var _idle_fps := 6.0
var _idle_t := 0.0
var _idle_idx := 0

# HUD
var _hud: CanvasLayer = null
var _turn_label: Label = null
var _ap_label: Label = null
var _lamp_label: Label = null
var _hp_label: Label = null
var _shield_label: Label = null
var _hint: Label = null
var _obj_rows := {} # id: Button
var _fuel_btn: Button = null
var _item_btns: Array = []
var _hand_layer: Control = null

func _ready() -> void:
	_theme = UIThemeScript.load_theme()
	_load_data()
	_load_artifact()
	_build_background()
	_build_player()
	_build_hud()
	_deal_hand()
	_new_turn()
	WashiOverlay.add_to(self)
	if "--auto-demo" in OS.get_cmdline_user_args():
		_run_auto_demo()

func _process(delta: float) -> void:
	if _idle_frames.size() > 1 and not _over:
		_idle_t += delta
		if _idle_t >= 1.0 / _idle_fps:
			_idle_t = 0.0
			_idle_idx = (_idle_idx + 1) % _idle_frames.size()
			_player.texture = _idle_frames[_idle_idx]
	if Input.is_action_just_pressed("ui_cancel") and not _over:
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().change_scene_to_file(NextBattleV4.return_path))

# ---------- 数据 ----------

func _load_data() -> void:
	var f := FileAccess.open(ritual_data_path, FileAccess.READ)
	if f == null:
		push_error("[RitualCanvas] 缺少 %s" % ritual_data_path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_cfg = parsed
	_ap_max = int(_cfg.get("ap_per_turn", 6))
	_max_turns = int(_cfg.get("max_turns", 6))
	var lamp: Dictionary = _cfg.get("lamp", {})
	_lamp_max = int(lamp.get("max", 6))
	_lamp = int(lamp.get("start", 4))
	var p: Dictionary = _cfg.get("player", {})
	_hp_max = int(p.get("hp", 30))
	_hp = _hp_max
	for it in (_cfg.get("items", []) as Array):
		_items.append({"def": it, "uses_left": int(it.get("uses", 1))})
	for o in (_cfg.get("objectives", []) as Array):
		_objectives[String(o.get("id", ""))] = {"def": o, "done": false}

func _load_artifact() -> void:
	var aid := String(BuildSaveV4.load_build().get("artifact", ""))
	if aid.is_empty():
		return
	var f := FileAccess.open("res://data/artifacts.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		for a in (parsed as Array):
			if a is Dictionary and String(a.get("id", "")) == aid:
				_artifact = a
				return

# ---------- 搭建 ----------

func _build_background() -> void:
	var tex: Texture2D = PngLoaderScript.load_texture(String(_cfg.get("bg", "")))
	if tex:
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		# 设计分辨率 1920×1080 铺满（与 ui_theme canvas.base 一致）；
		# 不用 get_viewport_rect()：_ready 时机可能拿到 0 尺寸
		spr.scale = Vector2(1920.0 / tex.get_width(), 1080.0 / tex.get_height())
		add_child(spr)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.06, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

func _build_player() -> void:
	var p: Dictionary = _cfg.get("player", {})
	_player = Sprite2D.new()
	var pos: Array = p.get("pos", [210, 930])
	_player.position = Vector2(float(pos[0]), float(pos[1]))
	var h := float(p.get("height_px", 450))
	var anims: Dictionary = p.get("anims", {})
	var idle: Array = anims.get("idle", [])
	_idle_fps = float(anims.get("fps", 6))
	for path in idle:
		var t: Texture2D = PngLoaderScript.load_texture(String(path))
		if t:
			_idle_frames.append(t)
	if _idle_frames.is_empty():
		var fallback: Texture2D = PngLoaderScript.load_texture(String(p.get("sprite", "")))
		if fallback:
			_idle_frames.append(fallback)
	if not _idle_frames.is_empty():
		_player.texture = _idle_frames[0]
		var th := float(_idle_frames[0].get_height()) * _player.scale.y
		if th > 0:
			_player.scale = Vector2(h / th, h / th)
	add_child(_player)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_turn_label = _label("", 26, Vector2(60, 30))
	_ap_label = _label("", 22, Vector2(60, 70))
	_lamp_label = _label("", 24, Vector2(760, 30))
	_hp_label = _label("", 20, Vector2(60, 130))
	_shield_label = _label("", 18, Vector2(60, 160))
	_shield_label.add_theme_color_override("font_color", _theme.color("fuji_500"))
	_hint = _label("", 20, Vector2(400, 1030))
	# 目标面板（和纸）
	var panel := PanelContainer.new()
	panel.position = Vector2(1380, 40)
	panel.size = Vector2(500, 320)
	panel.add_theme_stylebox_override("panel", _theme.washi_panel())
	_hud.add_child(panel)
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(450, 280)
	pv.add_theme_constant_override("separation", 8)
	panel.add_child(pv)
	pv.add_child(_panel_label("送行仪式", 22))
	for id in _objectives:
		var o: Dictionary = _objectives[id]
		var btn := Button.new()
		btn.add_theme_font_size_override("font_size", 18)
		btn.custom_minimum_size = Vector2(430, 46)
		btn.pressed.connect(func() -> void: _try_objective(id))
		_obj_rows[id] = btn
		pv.add_child(btn)
	# 添灯 + 道具栏（独立于手牌，GDD §8.2）
	var fuel_cfg: Dictionary = _cfg.get("add_fuel", {})
	_fuel_btn = Button.new()
	_fuel_btn.position = Vector2(60, 220)
	_fuel_btn.custom_minimum_size = Vector2(200, 52)
	_fuel_btn.add_theme_font_size_override("font_size", 20)
	_fuel_btn.pressed.connect(_on_add_fuel)
	_hud.add_child(_fuel_btn)
	for i in _items.size():
		var b := Button.new()
		b.position = Vector2(60 + i * 220, 284)
		b.custom_minimum_size = Vector2(200, 52)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void: _use_item(i))
		_item_btns.append(b)
		_hud.add_child(b)
	var end_btn := Button.new()
	end_btn.text = "结束回合"
	end_btn.position = Vector2(1660, 990)
	end_btn.custom_minimum_size = Vector2(200, 56)
	end_btn.add_theme_font_size_override("font_size", 22)
	end_btn.pressed.connect(_on_end_turn)
	_hud.add_child(end_btn)
	_hand_layer = Control.new()
	_hand_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.add_child(_hand_layer)
	# 开场白横幅
	_banner(String(_cfg.get("intro", "")), 4.5)
	_refresh_hud()

func _label(text: String, sz: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", sz)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_color", _theme.color("paper_100"))
	_hud.add_child(l)
	return l

func _panel_label(text: String, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf")
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_color", _theme.color("ink_900"))
	return l

func _banner(text: String, seconds: float) -> void:
	_hint.text = text
	_hint.visible = not text.is_empty()
	if not text.is_empty():
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if is_instance_valid(_hint):
				_hint.visible = false)

func _float_text(pos: Vector2, text: String, color: Color, sz: int) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", sz)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_color", color)
	l.modulate.a = 0.0
	_hud.add_child(l)
	var tw: Tween = create_tween().set_parallel()
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_property(l, "position:y", pos.y - 60, 1.1).set_trans(Tween.TRANS_SINE)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func() -> void: if is_instance_valid(l): l.queue_free())

# ---------- 回合流 ----------

func _new_turn() -> void:
	_turn += 1
	_ap = _ap_max
	_add_fuel_used = false
	_shield = 0
	if _turn == 3:
		_banner("第三次叩门——回廊尽头的水面泛起倒影（可开始辨认）", 3.5)
	if _turn == 5:
		_banner("亡者显现，怨念加剧——可以念引路词了", 3.5)
	if _cards.size() < _hand_limit:
		_draw_cards(_hand_limit - _cards.size())
	_refresh_hud()

func _on_end_turn() -> void:
	if _over or _busy:
		return
	_end_turn_resolve()

func _end_turn_resolve() -> void:
	_busy = true
	_refresh_hud()
	# 阴风：稳定度衰减（GDD §8.3）
	var dec: Dictionary = BattleRulesV4.ritual_decay(_lamp,
		int(_cfg.get("lamp", {}).get("decay_per_turn", 1)))
	_lamp = int(dec["lamp"])
	_float_text(Vector2(760, 90), "阴风——稳定度 %d/%d" % [_lamp, _lamp_max],
		_theme.color("fuji_500"), 22)
	SfxScript.play(self, "card_play", -22.0)
	_refresh_hud()
	await get_tree().create_timer(0.8).timeout
	var result: Dictionary = BattleRulesV4.ritual_evaluate(_lamp, _hp, _objectives, _turn, _max_turns)
	if result["result"] == "lose":
		_show_end(false, result["missing"])
		return
	if result["result"] == "win":
		_show_end(true, [])
		return
	# 环境冲击（亡者怨念，可被护盾吸收）
	for hit in (_cfg.get("env_hits", []) as Array):
		if _turn >= int(hit.get("from_turn", 99)):
			_damage_player(int(hit.get("damage", 3)))
			_float_text(Vector2(960, 420), String(hit.get("text", "怨念冲击")),
				_theme.color("vermilion_500"), 28)
			SfxScript.play(self, "explosion", -10.0)
			_refresh_hud()
			await get_tree().create_timer(0.7).timeout
	result = BattleRulesV4.ritual_evaluate(_lamp, _hp, _objectives, _turn, _max_turns)
	if result["result"] == "lose":
		_show_end(false, result["missing"])
		return
	_busy = false
	_new_turn()

func _damage_player(amount: int) -> void:
	if _shield > 0:
		var res: Dictionary = BattleRulesV4.apply_shield(_hp, _shield, amount)
		_hp = int(res["hp"])
		_shield = int(res["shield"])
		_float_text(Vector2(300, 860), "护盾抵挡 %d" % int(res["absorbed"]),
			_theme.color("fuji_500"), 22)
	else:
		_hp = maxi(0, _hp - amount)
		_float_text(Vector2(300, 860), "-%d" % amount, _theme.color("vermilion_500"), 26)

# ---------- 玩家行动 ----------

func _on_add_fuel() -> void:
	if _over or _busy or _add_fuel_used:
		return
	var fc: Dictionary = _cfg.get("add_fuel", {})
	var cost := int(fc.get("cost", 2))
	if _ap < cost:
		_float_text(Vector2(300, 300), "灵墨不足", _theme.color("fuji_500"), 20)
		return
	_ap -= cost
	_add_fuel_used = true
	_lamp = BattleRulesV4.ritual_add_fuel(_lamp, int(fc.get("amount", 2)), _lamp_max)
	_float_text(Vector2(760, 90), "添灯——稳定度 %d/%d" % [_lamp, _lamp_max],
		_theme.color("gold_500"), 24)
	SfxScript.play(self, "fire_ignite", -12.0)
	_refresh_hud()

func _use_item(idx: int) -> void:
	if _over or _busy or idx >= _items.size():
		return
	var slot: Dictionary = _items[idx]
	if int(slot["uses_left"]) <= 0:
		return
	var def: Dictionary = slot["def"]
	var cost := int(def.get("cost", 0))
	if _ap < cost:
		_float_text(Vector2(300, 380), "灵墨不足", _theme.color("fuji_500"), 20)
		return
	_ap -= cost
	slot["uses_left"] = int(slot["uses_left"]) - 1
	_lamp = BattleRulesV4.ritual_add_fuel(_lamp, int(def.get("amount", 3)), _lamp_max)
	_float_text(Vector2(760, 90), "%s——稳定度 %d/%d" % [def.get("name", "道具"), _lamp, _lamp_max],
		_theme.color("gold_500"), 24)
	SfxScript.play(self, "fire_ignite", -12.0)
	_refresh_hud()

func _try_objective(id: String) -> void:
	if _over or _busy or not _objectives.has(id):
		return
	var o: Dictionary = _objectives[id]
	if bool(o["done"]):
		return
	var def: Dictionary = o["def"]
	var avail: Dictionary = BattleRulesV4.ritual_objective_available(def,
		{"turn": _turn, "done": _done_map()})
	if not avail["ok"]:
		_float_text(Vector2(1380, 380), String(avail["reason"]), _theme.color("fuji_500"), 20)
		return
	var cost := int(def.get("cost", 1))
	if _ap < cost:
		_float_text(Vector2(1380, 380), "灵墨不足（需 %d）" % cost, _theme.color("fuji_500"), 20)
		return
	_ap -= cost
	o["done"] = true
	_float_text(Vector2(1450, 420), "✓ %s" % def.get("name", id),
		_theme.color("successful"), 26)
	SfxScript.play(self, "seal")
	_refresh_hud()

func _done_map() -> Dictionary:
	var m := {}
	for id in _objectives:
		m[id] = bool(_objectives[id]["done"])
	return m

# ---------- 手牌（仅术法/防护类可用；其余置灰说明原因） ----------

func _deal_hand() -> void:
	_deck = CardLibraryV4.build_deck_defs(_cfg, _artifact)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_deck.shuffle()
	_hand_limit = int(_cfg.get("deck", {}).get("hand_limit", 5))
	_draw_cards(_hand_limit)

func _draw_cards(n: int) -> void:
	for i in n:
		if _deck.is_empty():
			if _discard.is_empty():
				return
			_deck = _discard.duplicate()
			_discard.clear()
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			_deck.shuffle()
		var def: Dictionary = _deck.pop_front()
		var card: Variant = BattleCardScript.new()
		card.setup(def, _theme)
		card.clicked.connect(_on_card_clicked)
		card.hover_changed.connect(_on_card_hover)
		_hand_layer.add_child(card)
		_cards.append(card)
	_relayout_hand()

# ---------- 卡牌悬浮说明（与战斗同一组件，悬停浮出移开即散） ----------

var _tooltip: CardTooltip = null
var _tooltip_card: Variant = null

func _on_card_hover(card: Variant, is_hovered: bool) -> void:
	if is_hovered:
		_hide_tooltip()
		_tooltip = CardTooltip.build(_theme, card.data)
		_tooltip_card = card
		_hand_layer.add_child(_tooltip)
		_tooltip.call_deferred("place_above", card)
	else:
		if _tooltip_card == card:
			_hide_tooltip()

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.queue_free()
	_tooltip = null
	_tooltip_card = null

func _relayout_hand() -> void:
	var n: int = maxi(1, _cards.size())
	var cw := 176.0
	var ch := 246.0
	var spacing: float = (mini(cw + 16.0, (1720.0 - cw) / maxi(1, n - 1))) if n > 1 else 0.0
	var total: float = cw + spacing * (n - 1)
	var x0: float = (1920.0 - total) * 0.5
	for i in _cards.size():
		var c: Variant = _cards[i]
		c.set_home(Vector2(x0 + i * spacing, 1080.0 - ch - 14.0))

func _on_card_clicked(card: Variant) -> void:
	if _over or _busy:
		return
	_hide_tooltip()
	if String(card.data.get("type", "")) != "skill":
		_float_text(Vector2(960, 640), "仪式中不可用：此卡需要敌方或场景槽位",
			_theme.color("fuji_500"), 20)
		return
	if _ap < int(card.data.get("cost", 0)):
		_float_text(Vector2(960, 640), "灵墨不足", _theme.color("fuji_500"), 20)
		return
	_play_skill(card)

func _play_skill(card: Variant) -> void:
	_busy = true
	_ap -= int(card.data.get("cost", 0))
	var def: Dictionary = card.data
	var fx: Dictionary = BattleRulesV4.parse_effects(def)
	var lines: Array = []
	if fx["shield"] > 0:
		_player_shield_grant(fx["shield"], lines)
	if fx["draw"] > 0:
		_draw_cards(fx["draw"])
		lines.append("抽牌 %d" % fx["draw"])
	if fx["spirit"] != 0:
		lines.append("灵气安定 %+d" % fx["spirit"])
	if fx["cleanse"] > 0:
		lines.append("净化")
	if lines.is_empty():
		lines.append("无事发生")
	for i in lines.size():
		_float_text(Vector2(700, 560 + 40 * i), String(lines[i]), _theme.color("fuji_500"), 24)
	SfxScript.play(self, "card_play", -14.0)
	_cards.erase(card)
	card.queue_free()
	_relayout_hand()
	_discard.append(def)
	_busy = false
	_refresh_hud()

func _player_shield_grant(base: int, lines: Array) -> void:
	# 器物：守心佩类（与战斗同一取值器）
	var bonus := BattleRulesV4.artifact_value(_artifact, "shield_bonus", 0)
	_shield += base + bonus
	lines.append("护盾 +%d" % (base + bonus) if bonus <= 0 else "护盾 +%d（%s +%d）" % [
		base + bonus, _artifact.get("name", "器物"), bonus])

# ---------- HUD 刷新 ----------

func _refresh_hud() -> void:
	_turn_label.text = "第 %d/%d 回合" % [_turn, _max_turns]
	_ap_label.text = "灵墨 %d/%d" % [_ap, _ap_max]
	var filled := ""
	for i in _lamp_max:
		filled += "●" if i < _lamp else "○"
	_lamp_label.text = "引灯稳定度 %s  %d/%d" % [filled, _lamp, _lamp_max]
	_lamp_label.add_theme_color_override("font_color",
		_theme.color("vermilion_500") if _lamp <= 2 else _theme.color("gold_500"))
	_hp_label.text = "生命 %d/%d" % [_hp, _hp_max]
	_shield_label.text = "护盾 %d" % _shield
	_shield_label.visible = _shield > 0
	var fc: Dictionary = _cfg.get("add_fuel", {})
	_fuel_btn.text = "%s（%d 灵墨）" % [fc.get("name", "添灯"), int(fc.get("cost", 2))]
	_fuel_btn.disabled = _over or _busy or _add_fuel_used or _ap < int(fc.get("cost", 2))
	for i in _item_btns.size():
		var slot: Dictionary = _items[i]
		var def: Dictionary = slot["def"]
		_item_btns[i].text = "%s ×%d（%d 灵墨）" % [
			def.get("name", "道具"), int(slot["uses_left"]), int(def.get("cost", 0))]
		_item_btns[i].disabled = _over or _busy or int(slot["uses_left"]) <= 0 \
			or _ap < int(def.get("cost", 0))
	for id in _obj_rows:
		var o: Dictionary = _objectives[id]
		var def: Dictionary = o["def"]
		var mark := "✓" if bool(o["done"]) else "☐"
		_obj_rows[id].text = "%s %s（%d 灵墨）" % [mark, def.get("name", id), int(def.get("cost", 1))]
		_obj_rows[id].disabled = _over or _busy or bool(o["done"])
	for c in _cards:
		c.disabled = _over or _busy or String(c.data.get("type", "")) != "skill" \
			or _ap < int(c.data.get("cost", 0))

# ---------- 结算 ----------

func _show_end(win: bool, missing: Array) -> void:
	_over = true
	_busy = false
	_refresh_hud()
	var panel := PanelContainer.new()
	panel.position = Vector2(510, 250)
	panel.size = Vector2(900, 480)
	panel.add_theme_stylebox_override("panel", _theme.washi_panel())
	_hud.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(830, 420)
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var title := _panel_label("送行完成" if win else "仪式中断", 36)
	v.add_child(title)
	var body := _panel_label(String(_cfg.get("win_text" if win else "lose_text", "")), 20)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	if not win and not missing.is_empty():
		var miss := _panel_label("缺项：%s" % "、".join(missing), 20)
		miss.add_theme_color_override("font_color", _theme.color("vermilion_500"))
		v.add_child(miss)
	var again := Button.new()
	again.text = "再试一次"
	again.add_theme_font_size_override("font_size", 22)
	again.pressed.connect(func() -> void:
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().reload_current_scene()))
	v.add_child(again)
	var back := Button.new()
	back.text = "返回探索"
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(func() -> void:
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().change_scene_to_file(NextBattleV4.return_path)))
	v.add_child(back)
	SfxScript.play(self, "seal" if win else "explosion")

# ---------- 自动连招冒烟：--auto-demo 按 GDD §8.3 时序自动完成仪式 ----------

func _run_auto_demo() -> void:
	while not _over:
		await get_tree().process_frame
		if _busy:
			continue
		# 目标链：引路→安放→辨认（按可用性与前提）
		var acted := false
		for id in ["guide", "place", "identify"]:
			if not _objectives.has(id) or bool(_objectives[id]["done"]):
				continue
			var def: Dictionary = _objectives[id]["def"]
			var avail: Dictionary = BattleRulesV4.ritual_objective_available(def,
				{"turn": _turn, "done": _done_map()})
			if avail["ok"] and _ap >= int(def.get("cost", 1)):
				_try_objective(id)
				acted = true
				break
		if acted:
			continue
		# 维持引灯：低了才添/用油
		if _lamp <= _lamp_max - int(_cfg.get("add_fuel", {}).get("amount", 2)) \
				and not _add_fuel_used and _ap >= int(_cfg.get("add_fuel", {}).get("cost", 2)):
			_on_add_fuel()
			continue
		if _lamp <= 2:
			var used_oil := false
			for i in _items.size():
				if int(_items[i]["uses_left"]) > 0 \
						and _ap >= int((_items[i]["def"] as Dictionary).get("cost", 0)):
					_use_item(i)
					used_oil = true
					break
			if used_oil:
				continue
		# 有护盾卡就打（挡第 5 回合起的怨念冲击）
		for c in _cards:
			if String(c.data.get("type", "")) == "skill" \
					and BattleRulesV4.parse_effects(c.data)["shield"] > 0 \
					and _ap >= int(c.data.get("cost", 0)):
				_play_skill(c)
				break
		await get_tree().create_timer(0.3).timeout
		if not _busy and not _over:
			_on_end_turn()
		await get_tree().create_timer(1.6).timeout
