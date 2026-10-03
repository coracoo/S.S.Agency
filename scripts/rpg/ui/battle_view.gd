# 可操作视图只提交六字段命令；HP/费用/意图/战果全部读取模型。
class_name RpgBattleView
extends Control
signal presentation_tick
const TrialSession = preload("res://scripts/exploration_3d/approach_session.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const LegacyActor = preload("res://scripts/rpg/ui/legacy_actor_view.gd")
const HdActor = preload("res://scripts/rpg/ui/hd_actor_view.gd")
const HdEvents = preload("res://scripts/rpg/ui/hd_event_player.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")

var engine: RefCounted
var campaign: RefCounted
var router: RefCounted
var pending_command: Dictionary = {}
var processing := false
var last_error := ""
var result_saved := false
var result_response: Dictionary = {}
var _catalog := Catalog.new()
var _config: Dictionary
var _nonce := 0
var _display_actor_id := ""
var _canvas: Control
var _hud: Dictionary = {}
var _actors: Dictionary = {}
var _danger_layer: Node2D
var _skill_buttons: Array[Button] = []
var _basic_buttons: Dictionary = {}
var _log_lines: Array[String] = []
var _result: Control
var _items: Control
var _preview_panel: Control
var _log_panel: Control
var _built := false
var _hd_views: Dictionary = {}
var _presentation_views: Dictionary = {}
var _hd_player: Node
var _presentation_generation := 0
var _navigating := false
var _hd_failed := false
var _exit_confirmation: Control
var _asset_error_panel: Control
var _asset_loading := false

func _init() -> void:
	_catalog.load_all()
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))

func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_resize_canvas)
	_resize_canvas()
	if engine == null and Router.session != null:
		router = Router.session
		bind(router.create_engine(), router.campaign)
	elif engine != null:
		_render()
	else:
		last_error = "没有战前安全档，请从RPG入口准备遭遇"
		_hud.prompt.text = last_error

func bind(battle_engine: RefCounted, campaign_model: RefCounted) -> void:
	_cancel_presentation()
	engine = battle_engine
	campaign = campaign_model
	pending_command = {}
	processing = false
	result_saved = false
	if engine == null:
		last_error = "战斗创建失败" if router == null else router.last_error
		return
	if _built: _build_actors()
	if _hd_failed:
		processing = true
		_show_hd_error()
		return
	processing = _hd_enabled()
	_consume_events(engine.advance())
	if _built:
		_render()
		if processing: _finish_initial_presentation(_presentation_generation)
		else: _check_result()

func select_command(kind: String, ability_id: String = "") -> void:
	if processing or engine == null: return
	var state: Dictionary = engine.snapshot()
	if state.get("phase") != "action_selection" or state.get("outcome", "") != "" or state.actors[state.active_actor_id].side != "player": return
	_nonce += 1
	pending_command = {"command_id": "ui_%d_%d" % [state.revision, _nonce], "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": kind, "ability_id": ability_id, "target_ids": []}
	last_error = ""
	if _built:
		_items.visible = false
		_render()

func select_target(actor_id: String) -> void:
	if processing or pending_command.is_empty(): return
	# 空目标已是合法命令时，模型负责完整集合（全体／自身），点选不能覆写。
	if command_options(pending_command.kind, pending_command.ability_id).get("automatic", false): return
	pending_command.target_ids = [actor_id]
	if _built: _render()

func current_preview() -> Dictionary:
	if engine == null or pending_command.is_empty(): return {"legal": false, "reasons": [], "effective_target_ids": [], "effects": [], "damage_ranges": [], "mp_cost": 0, "item_cost": 0, "cooldown": 0}
	return Presenter.preview(engine, pending_command)

func cancel_command() -> void:
	if processing: return
	pending_command = {}
	last_error = ""
	if _built:
		_items.visible = false
		_render()

func confirm_command() -> void:
	if processing or pending_command.is_empty() or engine == null: return
	var preview := current_preview()
	if not preview.legal:
		last_error = "；".join(preview.reasons)
		if _built: _render()
		return
	# 在同一同步调用中先锁按钮，保留同一ID；重复输入不生成新命令。
	processing = true
	var committed := pending_command.duplicate(true)
	_display_actor_id = committed.actor_id
	var result: Dictionary = engine.submit(committed)
	if not result.accepted:
		processing = false
		last_error = "；".join(result.reasons)
		if _built: _render()
		return
	pending_command = {}
	_consume_events(result.events)
	if _built:
		_render()
	if is_inside_tree(): _continue_after_action()

func _continue_after_action() -> void:
	var generation := _presentation_generation
	if _hd_enabled():
		if not await _await_presentation(generation): return
	else:
		await get_tree().create_timer(0.48).timeout
	if generation != _presentation_generation or not is_inside_tree(): return
	_consume_events(engine.advance())
	if _hd_enabled() and not await _await_presentation(generation): return
	processing = false
	_render()
	_check_result()
func _finish_initial_presentation(generation: int) -> void:
	if not await _await_presentation(generation): return
	processing = false
	_render()
	_check_result()
func _await_presentation(generation: int) -> bool:
	while generation == _presentation_generation and is_inside_tree() and _hd_player != null and _hd_player.is_busy():
		await presentation_tick
	return generation == _presentation_generation and is_inside_tree()
func _process(_delta: float) -> void:
	presentation_tick.emit()
func _cancel_presentation() -> void:
	_presentation_generation += 1
	presentation_tick.emit()
	if is_instance_valid(_hd_player): _hd_player.cancel()
	processing = false
func _hd_enabled() -> bool:
	return TrialSession.current != null and TrialSession.current.router == router


# 候选仅由真实预览探测，避免视图复制目标规则/免疫/成本判断。
func command_options(kind: String, ability_id: String = "") -> Dictionary:
	if engine == null: return {}
	var state: Dictionary = engine.snapshot()
	if state.active_actor_id.is_empty(): return {}
	var command := {"command_id": "probe_%d" % _nonce, "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": kind, "ability_id": ability_id, "target_ids": []}
	var first: Dictionary = engine.preview(command)
	if first.legal: return {"preview": first, "targets": [], "automatic": true}
	var targets: Array[String] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for id in ids:
		command.target_ids = [id]
		var value: Dictionary = engine.preview(command)
		if value.legal:
			targets.append(id)
			if not first.legal: first = value
	# 没有合法目标时仍展示一个单体探测的资源/CD原因。
	if targets.is_empty() and not ids.is_empty():
		command.target_ids = [ids[0]]
		first = engine.preview(command)
	return {"preview": first, "targets": targets, "automatic": false}

func _build() -> void:
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	Kit.backdrop(_canvas, _config)
	_danger_layer = Node2D.new()
	_danger_layer.z_index = 1
	_canvas.add_child(_danger_layer)
	Kit.panel(_canvas, Rect2(32, 28, 1856, 124))
	_hud.title = Kit.label(_canvas, "逢魔退治帖　／　回合制 RPG", Rect2(56, 39, 590, 42), 30)
	_hud.turn = Kit.label(_canvas, "", Rect2(56, 84, 580, 45), 26)
	_hud.queue = Kit.label(_canvas, "", Rect2(650, 48, 950, 90), 25)
	_hud.queue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Kit.button(_canvas, "日志", Rect2(1610, 46, 106, 76), _toggle_log)
	Kit.button(_canvas, "返回标题", Rect2(1728, 46, 138, 76), _return_title)
	Kit.label(_canvas, "远处 · 敌方", Rect2(1490 if _config.near_side == "left" else 55, 154, 370, 26), 22)
	Kit.label(_canvas, "近处 · 出战队员", Rect2(55 if _config.near_side == "left" else 1490, 154, 370, 26), 22)
	Kit.panel(_canvas, Rect2(32, 750, 1856, 292), true)
	_hud.prompt = Kit.label(_canvas, "选择技能 → 点击目标 → 确认　／　Esc 取消选择", Rect2(770, 704, 1090, 40), 25)
	for index in range(4):
		var x := 770 + (index % 2) * 330
		var y := 812 + (index / 2) * 105
		var button := Kit.button(_canvas, "技能", Rect2(x, y, 316, 96))
		button.pressed.connect(_select_skill_slot.bind(index))
		_skill_buttons.append(button)
	for row in [["attack_physical", "物理普攻", 812], ["defend", "防御", 882], ["item", "道具", 952]]:
		_basic_buttons[row[0]] = Kit.button(_canvas, row[1], Rect2(1440, row[2], 185, 61), _basic_pressed.bind(row[0]))
	_basic_buttons.attack_magic = Kit.button(_canvas, "中性魔攻", Rect2(1637, 812, 225, 61), select_command.bind("attack_magic"))
	_hud.cancel = Kit.button(_canvas, "取消选择", Rect2(1637, 882, 225, 61), cancel_command)
	_hud.confirm = Kit.button(_canvas, "确认行动", Rect2(1637, 952, 225, 61), confirm_command, true)
	_preview_panel = Kit.panel(_canvas, Rect2(60 if _config.near_side == "left" else 940, 154, 920, 180))
	_hud.preview_title = Kit.label(_preview_panel, "行动预览", Rect2(18, 6, 884, 38), 26)
	_hud.preview = RichTextLabel.new()
	_hud.preview.position = Vector2(18, 48)
	_hud.preview.size = Vector2(884, 118)
	_hud.preview.add_theme_font_override("normal_font", Kit.font)
	_hud.preview.add_theme_font_size_override("normal_font_size", 24)
	_hud.preview.add_theme_color_override("default_color", Kit.color("paper_100"))
	_preview_panel.add_child(_hud.preview)
	_items = Kit.panel(_canvas, Rect2(1140, 385, 720, 348))
	Kit.label(_items, "道具 · 使用占用本次行动", Rect2(20, 14, 680, 40), 27)
	for index in range(_catalog.get_ids("items").size()):
		var id: String = _catalog.get_ids("items")[index]
		var item: Dictionary = _catalog.get_definition("items", id)
		var button := Kit.button(_items, item.name, Rect2(20, 68 + index * 65, 680, 57), select_command.bind("item", id))
		_hud["item_" + id] = button
	_items.visible = false
	_log_panel = Kit.panel(_canvas, Rect2(48, 220, 760, 500))
	_hud.log = RichTextLabel.new()
	_hud.log.position = Vector2(22, 22)
	_hud.log.size = Vector2(716, 456)
	_hud.log.add_theme_font_override("normal_font", Kit.font)
	_hud.log.add_theme_font_size_override("normal_font_size", 25)
	_hud.log.add_theme_color_override("default_color", Kit.color("paper_100"))
	_log_panel.add_child(_hud.log)
	_log_panel.visible = false
	_hud.latest = Kit.label(_canvas, "", Rect2(50, 1044, 1550, 32), 22)
	_result = Kit.panel(_canvas, Rect2(435, 220, 1050, 660), true)
	_hud.result_title = Kit.label(_result, "", Rect2(48, 38, 950, 72), 46, true)
	_hud.result_body = Kit.label(_result, "", Rect2(48, 128, 950, 342), 29, true)
	_hud.result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.result_action = Kit.button(_result, "", Rect2(48, 510, 455, 86), _result_action, true)
	Kit.button(_result, "返回标题 · 保留安全档", Rect2(532, 510, 465, 86), _return_title)
	_result.visible = false
	_built = true

func _resize_canvas() -> void:
	var available := get_viewport_rect().size
	var factor := minf(available.x / 1920.0, available.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (available - Vector2(1920, 1080) * factor) / 2.0

func _build_actors() -> void:
	if is_instance_valid(_hd_player): _hd_player.cancel()
	_hd_views.clear()
	_presentation_views.clear()
	_hd_failed = false
	for widgets in _actors.values():
		for node in widgets.values():
			if is_instance_valid(node) and node is Node: node.free()
	_actors.clear()
	var state: Dictionary = engine.snapshot()
	var allies: Array = []
	var enemies: Array = []
	for id in state.actors:
		if state.actors[id].side == "player": allies.append(id)
		else: enemies.append(id)
	# 编队顺序由campaign提供；孤立测试以稳定ID排序。
	allies.sort()
	if campaign != null: allies = campaign.snapshot().party.duplicate()
	enemies.sort()
	var crowded := enemies.size() > 2
	_hud.prompt.position = Vector2(1000 if _config.near_side == "right" else 50, 704) if crowded else Vector2(770, 704)
	_hud.prompt.size = Vector2(850, 40) if crowded else Vector2(1090, 40)
	for index in range(allies.size() + enemies.size()):
		var ally := index < allies.size()
		var slot := index if ally else index - allies.size()
		var id: String = allies[slot] if ally else enemies[slot]
		var actor: Dictionary = state.actors[id]
		var layout: Array = _config.ally_slots[slot] if ally else (_config.boss_slot if actor.class_id == "gatekeeper" else _config.enemy_slots[slot])
		# 三/四敌共享独立窄列；不把双敌面板放到交错脚点上互相覆盖。
		var compact := crowded and not ally
		if compact: layout = [150 + slot * 224, 575, 220]
		var foot := Vector2(layout[0], layout[1])
		if _config.near_side == "left": foot.x = 1920 - foot.x
		var shadow := Polygon2D.new()
		var points: PackedVector2Array = []
		for part in range(32): points.append(Vector2(cos(TAU * part / 32.0) * 72, sin(TAU * part / 32.0) * 15))
		shadow.polygon = points
		shadow.color = Color(0.02, 0.015, 0.03, 0.5)
		shadow.position = foot
		_canvas.add_child(shadow)
		var art: String = _config.class_art[actor.class_id].actor if ally else _config.enemy_art.get(actor.class_id, _config.enemy_art.default)
		var native_facing: String = _config.asset_facings.get(art, "right")
		var toward_right: bool = not ally if _config.near_side == "right" else ally
		var sprite: Node2D
		if ally and _hd_enabled():
			var hd := HdActor.new()
			var definition: Dictionary = TrialSession.current.bundle.get_definition(actor.get("identity_id", "")) if TrialSession.current.bundle != null else {}
			if not hd.configure(definition, float(layout[2]), 1 if toward_right else -1):
				_hd_failed = true
				last_error = "人物高清素材未就绪，请重试加载"
			sprite = hd
			_canvas.add_child(sprite)
			_hd_views[id] = hd
		else:
			sprite = Kit.actor_sprite(_canvas, art, float(layout[2]), Kit.flip_for(native_facing, toward_right))
			if _hd_enabled():
				_canvas.remove_child(sprite)
				var adapter := LegacyActor.new()
				adapter.configure(sprite, float(layout[2]), native_facing, toward_right)
				_canvas.add_child(adapter)
				sprite = adapter
		if _hd_enabled(): _presentation_views[id] = sprite
		sprite.set_meta("source_facing", native_facing)
		sprite.set_meta("foot_point", foot)
		sprite.set_meta("content_height", float(layout[2]))
		sprite.set_meta("facing_right", toward_right)
		sprite.position = foot
		var ring := Line2D.new()
		var ring_points := points.duplicate()
		ring_points.append(points[0])
		ring.points = ring_points
		ring.width = 4
		ring.default_color = Kit.color("gold_500")
		ring.position = foot
		_canvas.add_child(ring)
		var target := Kit.button(_canvas, "", Rect2(foot.x - 110, foot.y - float(layout[2]), 220, float(layout[2]) + 34), select_target.bind(id))
		for style in ["normal", "hover", "pressed", "focus", "disabled"]: target.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		target.mouse_filter = Control.MOUSE_FILTER_PASS
		var card: Panel
		var avatar: TextureRect
		if ally:
			card = Kit.panel(_canvas, Rect2(48 + slot * 234, 810, 222, 210))
			if _hd_enabled():
				var identity: String = actor.get("identity_id", "")
				var definition: Dictionary = TrialSession.current.bundle.get_definition(identity) if TrialSession.current.bundle != null else {}
				var face := Portraits.from_definition(definition, identity, "avatar")
				avatar = TextureRect.new()
				avatar.position = Vector2(12, 12)
				avatar.size = Vector2(48, 48)
				avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if face.ok:
					avatar.texture = face.texture
					avatar.set_meta("identity_id", identity)
					avatar.set_meta("source_path", face.source_path)
				else:
					_hd_failed = true
					last_error = face.error
				card.add_child(avatar)
			else:
				avatar = Kit.image(card, _config.class_art[actor.class_id].badge, Rect2(12, 12, 48, 48))
		else:
			var card_x: float = (55.0 if _config.near_side == "right" else 1535.0) if actor.class_id == "gatekeeper" else foot.x - 164
			card = Kit.panel(_canvas, Rect2(foot.x - 107, 184, 214, 172) if compact else Rect2(card_x, 180 + slot * 8, 328, 205))
		var title := Kit.label(card, "", Rect2(66 if ally else 12, 10, 150 if ally else 300, 38), 26)
		var hp := Kit.label(card, "", Rect2(12, 55 if ally else 48, 210 if ally else 300, 32), 24)
		var hpbar := Kit.bar(card, Rect2(12, 89 if ally else 82, 198 if ally else 304, 9), Kit.color("successful"))
		var mp := Kit.label(card, "", Rect2(12, 104 if ally else 96, 210 if ally else 300, 32), 24)
		mp.add_theme_color_override("font_color", Kit.color("mizu_500"))
		var status := Kit.scroll_text(card, Rect2(12, 144 if ally else 133, 198 if ally else 304, 56 if ally else 62), 23)
		if compact:
			title.position = Vector2(10, 8)
			title.size = Vector2(194, 28)
			title.add_theme_font_size_override("font_size", 20)
			hp.position = Vector2(10, 38)
			hp.size = Vector2(194, 27)
			hp.add_theme_font_size_override("font_size", 20)
			hpbar.position = Vector2(10, 68)
			hpbar.size = Vector2(194, 9)
			mp.position = Vector2(10, 80)
			mp.size = Vector2(194, 27)
			mp.add_theme_font_size_override("font_size", 20)
			status.position = Vector2(10, 111)
			status.size = Vector2(194, 51)
			status.add_theme_font_size_override("normal_font_size", 18)
		var intent: Label
		if not ally:
			var intent_rect := Rect2(55 if _config.near_side == "right" else 1510, 407, 365, 275) if actor.class_id == "gatekeeper" else Rect2(foot.x - 178, foot.y + 2, 356, maxf(52, 744 - (foot.y + 2)))
			if compact: intent_rect = Rect2(foot.x - 107, 586, 214, 158)
			intent = Kit.label(_canvas, "", intent_rect, 18 if compact else (22 if actor.class_id == "gatekeeper" else 20))
			intent.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			intent.add_theme_color_override("font_outline_color", Kit.color("ink_900"))
			intent.add_theme_constant_override("outline_size", 6)
		_actors[id] = {"sprite": sprite, "shadow": shadow, "ring": ring, "target": target, "card": card, "avatar": avatar, "title": title, "hp": hp, "mp": mp, "hpbar": hpbar, "status": status, "intent": intent}
	if _hd_enabled():
		if not is_instance_valid(_hd_player):
			_hd_player = HdEvents.new()
			add_child(_hd_player)
		_hd_player.bind_actors(_presentation_views)
	# 模态保持在人物及点选热区前。
	for node in [_preview_panel, _items, _log_panel, _result]: _canvas.move_child(node, -1)

func _render() -> void:
	if not _built or engine == null: return
	var state: Dictionary = engine.snapshot()
	var model := Presenter.present(state, _catalog, _display_actor_id if processing else "")
	if _actors.is_empty(): _build_actors()
	_render_danger(model.danger)
	var active: Dictionary = state.actors.get(_display_actor_id if processing else state.active_actor_id, {})
	_hud.turn.text = "第 %d 轮　·　%s%s" % [state.round, Presenter.actor_name(active, _catalog), " 结算中…" if processing else " 行动"]
	var queue: Array[String] = []
	for index in range(model.queue.size()):
		var name := Presenter.actor_name(state.actors[model.queue[index]], _catalog)
		queue.append(("▶" if index == model.queue_index else ("✓" if index < model.queue_index else "")) + name)
	_hud.queue.add_theme_font_size_override("font_size", 20 if queue.size() > 5 else 25)
	_hud.queue.text = "本轮顺序\n" + " → ".join(queue)
	var preview := current_preview()
	var automatic: bool = not pending_command.is_empty() and command_options(pending_command.kind, pending_command.ability_id).get("automatic", false)
	for row in model.actors:
		var w: Dictionary = _actors[row.actor_id]
		w.title.text = (row.label if row.side == "enemy" and model.actors.size() > 5 else row.name) + (" · 倒地" if row.hp == 0 else "")
		if row.side == "enemy" and model.actors.size() > 5:
			w.title.tooltip_text = w.title.text
			for font_size in [20, 18, 16]:
				w.title.add_theme_font_size_override("font_size", font_size)
				if Kit.font.get_string_size(w.title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= 194: break
			w.title.size.x = 194
		w.hp.text = "HP %d / %d" % [row.hp, row.max_hp]
		w.hpbar.max_value = row.max_hp
		w.hpbar.value = row.hp
		w.mp.text = "MP %d / %d" % [row.mp, row.max_mp]
		w.status.text = "盾 %d%s\n%s" % [row.shield, " · %d次行动" % row.shield_remaining if row.shield > 0 else "", " / ".join(row.statuses) if not row.statuses.is_empty() else "无状态"]
		w.status.tooltip_text = w.status.text
		w.sprite.modulate = Color(0.4, 0.4, 0.4, 0.55) if row.hp == 0 else Color.WHITE
		w.ring.visible = row.active or preview.effective_target_ids.has(row.actor_id)
		w.ring.default_color = Kit.color("vermilion_500") if preview.effective_target_ids.has(row.actor_id) else Kit.color("gold_500")
		w.target.disabled = processing or pending_command.is_empty() or automatic
		w.target.tooltip_text = "%s\n%s" % [row.label, w.status.text]
		if w.intent != null:
			w.intent.text = row.intent.get("text", "倒地")
			w.intent.tooltip_text = w.intent.text
	for index in range(4):
		var button := _skill_buttons[index]
		button.disabled = processing or model.commands.skills.size() <= index or not state.outcome.is_empty()
		if model.commands.skills.size() <= index:
			button.text = "技能槽 %d" % (index + 1)
			continue
		var slot: Dictionary = model.commands.skills[index]
		var options := command_options("skill", slot.id)
		var p: Dictionary = options.get("preview", {})
		var reasons: Array = p.get("reasons", [])
		var reason: String = str(reasons[0]) if not p.get("legal", false) and not reasons.is_empty() else slot.target_label
		if not processing and not p.get("legal", false): button.disabled = true
		button.add_theme_font_size_override("font_size", 24)
		var effect_text := Presenter.card_summary(slot, p, _catalog)
		var full_effect_text := Presenter.ability_summary(slot, p, _catalog)
		var cd_text := " · CD%d" % p.get("cooldown", slot.cooldown) if p.get("cooldown", slot.cooldown) > 0 else ""
		button.text = "%s　MP %d%s · %s\n%s" % [slot.name, p.get("mp_cost", slot.mp_cost), cd_text, slot.target_short, effect_text if p.get("legal", false) or processing else reason]
		# 三字技能名加MP/CD时最多缩两级，保持四卡固定边界，不让最小尺寸挤压基础指令。
		for font_size in [24, 22, 20]:
			button.add_theme_font_size_override("font_size", font_size)
			if Array(button.text.split("\n")).all(func(line): return Kit.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= 296): break
		button.size = Vector2(316, 96)
		button.tooltip_text = button.text + "\n" + full_effect_text + "\n" + slot.target_label + ("\n" + " / ".join(reasons) if not reasons.is_empty() else "")
	for kind in _basic_buttons:
		_basic_buttons[kind].disabled = processing or active.is_empty() or not state.outcome.is_empty()
	_basic_buttons.attack_magic.visible = model.commands.basic.has("attack_magic")
	_hud.confirm.disabled = processing or not preview.legal
	_hud.cancel.disabled = processing or pending_command.is_empty()
	var selection_prompt := ("全体目标已选，可直接确认" if preview.effective_target_ids.size() > 1 else "目标已选，可直接确认") if automatic else "点击目标后确认"
	_hud.prompt.text = last_error if not last_error.is_empty() else (selection_prompt + " · Esc 可取消" if not pending_command.is_empty() else "选择技能 → 点击目标 → 确认　／　Esc 取消选择")
	_preview_panel.visible = not pending_command.is_empty()
	if _preview_panel.visible:
		_hud.preview_title.text = "%s　MP %d　道具 %d" % [Presenter.ability_name(pending_command.ability_id if not pending_command.ability_id.is_empty() else pending_command.kind, _catalog), preview.mp_cost, preview.item_cost]
		_hud.preview.text = "\n".join(Presenter.preview_lines(preview, state, _catalog))
	for id in _catalog.get_ids("items"):
		_hud["item_" + id].text = "%s　×%d" % [_catalog.get_definition("items", id).name, model.inventory.get(id, 0)]
		_hud["item_" + id].disabled = processing
	_hud.log.text = "\n".join(_log_lines)
	_hud.latest.text = _log_lines.back() if not _log_lines.is_empty() else "HP/MP与库存跨战保留 · 道具占用一次行动"

func _select_skill_slot(index: int) -> void:
	var model := Presenter.present(engine.snapshot(), _catalog)
	if index < model.commands.skills.size(): select_command("skill", model.commands.skills[index].id)

func _basic_pressed(kind: String) -> void:
	if kind == "item":
		if not processing: _items.visible = not _items.visible
	else: select_command(kind)

func _toggle_log() -> void:
	_log_panel.visible = not _log_panel.visible

func _play_action(actor_id: String, target_ids: Array = []) -> void:
	if not _actors.has(actor_id): return
	var sprite: Node2D = _actors[actor_id].sprite
	var foot: Vector2 = sprite.get_meta("foot_point", sprite.position)
	var toward_right: bool = sprite.get_meta("facing_right", false)
	for target_id in target_ids:
		if target_id != actor_id and _actors.has(target_id):
			toward_right = _actors[target_id].sprite.get_meta("foot_point").x > foot.x
			break
	Kit.face_actor(sprite, toward_right)
	var animated := sprite.get_node_or_null("Animated")
	if animated != null:
		animated.play("attack")
	else:
		var old = sprite.get_meta("action_tween") if sprite.has_meta("action_tween") else null
		if old != null and old.is_valid(): old.kill()
		sprite.position = foot
		var tween := create_tween()
		sprite.set_meta("action_tween", tween)
		tween.tween_property(sprite, "position:x", foot.x + (30.0 if toward_right else -30.0), 0.14)
		tween.tween_property(sprite, "position:x", foot.x, 0.22)

func _event_fx(event: Dictionary) -> void:
	if not _built or not _actors.has(event.target_id): return
	var text := ""
	var tint := Kit.color("gold_500")
	match event.type:
		"damage":
			text = ("暴击 " if event.payload.critical else "") + str(event.payload.damage)
			tint = Kit.color("vermilion_500")
		"healed":
			text = "HP +%d" % event.payload.actual
			tint = Kit.color("successful")
		"mp_restored":
			text = "MP +%d" % event.payload.actual
			tint = Kit.color("mizu_500")
		"shield_applied": text = "盾 %d" % event.payload.shield.amount
		"charge_interrupted": text = "蓄力打断"
		"revived": text = "复苏 HP %d" % event.payload.hp
	if text.is_empty(): return
	var target: Node2D = _actors[event.target_id].sprite
	var foot: Vector2 = target.get_meta("foot_point", target.position)
	var label := Kit.label(_canvas, text, Rect2(foot.x - 90, foot.y - float(target.get_meta("content_height", 300)) * 0.55, 250, 44), 33)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", Kit.color("ink_900"))
	label.add_theme_constant_override("outline_size", 7)
	_canvas.move_child(_result, -1)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 44, 0.72)
	tween.tween_property(label, "modulate:a", 0.0, 0.72)
	tween.chain().tween_callback(label.queue_free)

func _consume_events(events: Array) -> void:
	if engine == null: return
	var state: Dictionary = engine.snapshot()
	var played: Dictionary = {}
	for event in events:
		var line := Presenter.event_line(event, state, _catalog)
		if not line.is_empty(): _log_lines.append(line)
		if _built and not _hd_enabled():
			_event_fx(event)
			if event.type == "damage" and not played.has(event.actor_id):
				played[event.actor_id] = true
				_play_action(event.actor_id, [event.target_id])
	if _hd_enabled() and is_instance_valid(_hd_player): _hd_player.enqueue(events, state)
	while _log_lines.size() > 80: _log_lines.pop_front()

func _check_result() -> void:
	if engine == null or engine.snapshot().outcome.is_empty(): return
	pending_command = {}
	_result.visible = true
	if not result_saved: save_result()
	_show_result()

func save_result() -> Dictionary:
	if router == null:
		last_error = "孤立模型没有持久化会话"
		return {"ok": false, "error": last_error}
	result_response = router.finish(router.result_from_engine())
	result_saved = result_response.get("ok", false)
	last_error = result_response.get("error", "")
	if _built: _show_result()
	return result_response

func _show_result() -> void:
	if not _built or engine == null: return
	var state: Dictionary = engine.snapshot()
	var victory: bool = state.outcome == "victory"
	_hud.result_title.text = "退治成功" if victory else "队伍败北"
	var lines: Array[String] = []
	if not result_saved:
		lines.append("战果尚未保存：" + last_error)
		lines.append("安全档保持原样。修复写入问题后可以重试提交。")
	elif victory:
		var saved: Dictionary = campaign.snapshot()
		lines.append("共享等级 L%d　经验 %d" % [saved.level, saved.xp])
		for id in saved.party:
			var actor: Dictionary = saved.roster[id]
			lines.append("%s　HP %d/%d　MP %d/%d" % [Presenter.actor_name(actor, _catalog), actor.hp, actor.stats.hp, actor.mp, actor.stats.mp])
		lines.append("库存：" + _inventory_text(saved.inventory))
		lines.append("水钵异常已解决 · 返回参道" if _hd_enabled() else ("连战完成" if saved.next_encounter_id.is_empty() else ("下一步：休息准备点" if saved.phase == "rest" else "下一场普通战")))
	else:
		lines.append("重试将恢复同一战前状态、库存与种子")
		lines.append("没有额外补给或经验")
	if result_saved and not last_error.is_empty(): lines.append(last_error)
	_hud.result_body.text = "\n".join(lines)
	_hud.result_action.text = "重试保存战果" if not result_saved else ("继续" if victory else "同条件重试")

func _inventory_text(inventory: Dictionary) -> String:
	var entries: Array[String] = []
	for id in _catalog.get_ids("items"): entries.append("%s×%d" % [_catalog.get_definition("items", id).name, inventory.get(id, 0)])
	return "　".join(entries)

func _result_action() -> void:
	if _navigating: return
	if not result_saved:
		save_result()
		return
	if engine.snapshot().outcome == "defeat":
		var retried: Dictionary = router.retry()
		if not retried.ok:
			last_error = retried.error
			result_saved = false
			_show_result()
			return
		_result.visible = false
		_log_lines.clear()
		bind(router.create_engine(), campaign)
	else:
		_navigating = true
		var error := _change_scene(result_response.get("next_scene", "res://scenes/rpg/launcher.tscn"))
		if error != OK:
			_navigating = false
			last_error = "返场失败（%d），安全战果已保存，可重试返回" % error
			_show_result()

func _return_title() -> void:
	if _hd_enabled():
		if is_instance_valid(_exit_confirmation): return
		_exit_confirmation = Kit.panel(_canvas, Rect2(0, 0, 1920, 1080))
		_exit_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
		Kit.label(_exit_confirmation, "返回标题？", Rect2(470, 280, 980, 70), 42)
		var message := "继续试玩会从同一战前状态重试。未提交的战斗过程不会保存。"
		if engine != null and engine.snapshot().outcome == "victory" and not result_saved: message = "战果尚未保存。返回标题会丢失本场未提交战果，继续试玩将回到同一战前状态。"
		if result_saved and engine != null and engine.snapshot().outcome == "victory": message = "战果已安全保存。继续试玩将回到参道。"
		var body := Kit.label(_exit_confirmation, message, Rect2(470, 380, 980, 150), 30)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		Kit.button(_exit_confirmation, "返回标题", Rect2(470, 610, 460, 84), _confirm_return_title)
		Kit.button(_exit_confirmation, "取消", Rect2(970, 610, 460, 84), _cancel_return_title)
		return
	_confirm_return_title()
func _cancel_return_title() -> void:
	if is_instance_valid(_exit_confirmation): _exit_confirmation.queue_free()
	_exit_confirmation = null
func _confirm_return_title() -> void:
	var session: RefCounted = TrialSession.current if _hd_enabled() else null
	var error := _change_scene("res://scenes/v3/title.tscn")
	if error != OK:
		last_error = "标题未能打开（%d），会话仍保留" % error
		_cancel_return_title()
		return
	_cancel_presentation()
	if session != null: session.close()
	Router.clear_session()
func _change_scene(path: String) -> Error:
	return get_tree().change_scene_to_file(path)
func _show_hd_error() -> void:
	if is_instance_valid(_asset_error_panel): _asset_error_panel.queue_free()
	_asset_error_panel = Kit.panel(_canvas, Rect2(430, 300, 1060, 470), true)
	Kit.label(_asset_error_panel, "人物素材尚未就绪", Rect2(42, 32, 970, 60), 38, true)
	var body := Kit.label(_asset_error_panel, last_error + "\n战前状态保持不变，请重试加载。", Rect2(42, 115, 970, 170), 28, true)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Kit.button(_asset_error_panel, "重试加载", Rect2(42, 335, 464, 80), _retry_hd_assets)
	Kit.button(_asset_error_panel, "返回标题", Rect2(546, 335, 464, 80), _return_title)
func _retry_hd_assets() -> void:
	if not _hd_enabled() or _asset_loading: return
	_asset_loading = true
	var generation := _presentation_generation
	var result: Dictionary = await TrialSession.current.prepare_assets()
	_asset_loading = false
	if generation != _presentation_generation or not is_inside_tree(): return
	if not result.ok:
		last_error = result.error
		_show_hd_error()
		return
	if is_instance_valid(_asset_error_panel): _asset_error_panel.queue_free()
	_asset_error_panel = null
	bind(router.create_engine(), campaign)
func _exit_tree() -> void:
	_cancel_presentation()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_exit_confirmation):
		get_viewport().set_input_as_handled()
		_cancel_return_title()
		return
	if event.is_action_pressed("ui_cancel"):
		cancel_command()
		get_viewport().set_input_as_handled()

# 纯表现红色承诺线/范围，使用Presenter给出的原始锁定ID，不挑选新目标。
func _render_danger(markers: Array) -> void:
	for node in _danger_layer.get_children(): node.free()
	for marker in markers:
		if not _actors.has(marker.actor_id): continue
		var source: Vector2 = _actors[marker.actor_id].sprite.get_meta("foot_point")
		var feet: Array[Vector2] = []
		for id in marker.target_ids:
			if _actors.has(id): feet.append(_actors[id].sprite.get_meta("foot_point"))
		if marker.area and not feet.is_empty():
			var bounds := Rect2(feet[0] - Vector2(125, 52), Vector2(250, 104))
			for foot in feet: bounds = bounds.expand(foot - Vector2(125, 52)).expand(foot + Vector2(125, 52))
			var area := Polygon2D.new()
			area.polygon = PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
			area.color = Color(0.88, 0.15, 0.12, 0.19)
			_danger_layer.add_child(area)
		for foot in feet:
			var line := Line2D.new()
			line.width = 5
			line.default_color = Color(0.95, 0.18, 0.12, 0.9)
			if marker.area:
				for part in range(33): line.add_point(foot + Vector2(cos(TAU * part / 32.0) * 115, sin(TAU * part / 32.0) * 33))
			else:
				line.points = PackedVector2Array([source - Vector2(0, 85), foot - Vector2(0, 35)])
			_danger_layer.add_child(line)
