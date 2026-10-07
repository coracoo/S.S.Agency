# 可操作视图只提交六字段命令；HP/费用/意图/战果全部读取模型。
class_name RpgBattleView
extends Control
signal presentation_tick
const PartyFraming = preload("res://scripts/rpg/ui/battle_party_framing.gd")
const BattleEffects = preload("res://scripts/rpg/ui/imagegen_battle_effects.gd")
const WorldBackdrop = preload("res://scripts/rpg/ui/battle_world_backdrop.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
const ChapterSession = preload("res://scripts/campaign/chapter_session.gd")
const TrialSession = preload("res://scripts/exploration_3d/approach_session.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const LegacyActor = preload("res://scripts/rpg/ui/legacy_actor_view.gd")
const HdActor = preload("res://scripts/rpg/ui/hd_actor_view.gd")
const SagaEnemyArt = preload("res://scripts/rpg/ui/saga_enemy_art.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const SagaNarrator = preload("res://scripts/campaign/saga_battle_narrator.gd")
const HdEvents = preload("res://scripts/rpg/ui/hd_event_player.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
const ITEM_ORDER := ["healing_potion", "mana_potion", "revival_potion", "cleansing_powder", "energy_tea", "guard_charm", "moxa_roll"]

var engine: RefCounted
var campaign: RefCounted
var router: RefCounted
var pending_command: Dictionary = {}
# 唯一目标为「自动预填」（区别于玩家手动点选），提示语文本区分两种路径。
var _auto_targeted := false
var processing := false
var last_error := ""
var result_saved := false
var result_response: Dictionary = {}
var _catalog := Catalog.new()
var _config: Dictionary
var _nonce := 0
var _display_actor_id := ""
var _world_backdrop: Control
var _canvas: Control
var _hud: Dictionary = {}
var _actors: Dictionary = {}
var _danger_layer: Node2D
var _fx_layer: Node2D
# 生图像素批准与游戏呈现批准分开；正式开关由独立registry控制。
var _skill_effects_ready := false
var _effect_actions: Dictionary = {}
var _visual_sequences: Dictionary = {}
var _skill_buttons: Array[Button] = []
var _basic_buttons: Dictionary = {}
var _log_lines: Array[String] = []
var _pending_logs: Dictionary = {}
var _log_event_seen: Dictionary = {}
var _saga_narration_seen: Dictionary = {}
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
var _exit_previous_focus: Control
var _asset_error_panel: Control
var _asset_loading := false
var _asset_request := -1
var _needs_initial_advance := false
var _popup_shade: ColorRect
var _modal_focus_root: Control
var _modal_previous_focus: Control
var _modal_focus_modes: Array[Dictionary] = []

# 只暂存已提交事件的HP显示快照；模型的HP与伤害始终由BattleEngine独占。
var _display_hp: Dictionary = {}
var _display_mp: Dictionary = {}
var _display_shields: Dictionary = {}
var _display_statuses: Dictionary = {}
var _pending_hp_events: Dictionary = {}
var _hp_event_nonce := 0

func _init() -> void:
	_catalog.load_all()
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))

func _ready() -> void:
	if router == null and Router.session != null:
		router = Router.session
		campaign = router.campaign
	if campaign == null and router != null: campaign = router.campaign
	_build()
	get_viewport().size_changed.connect(_resize_canvas)
	_resize_canvas()
	if not await _prewarm_battle_assets(true): return
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
	_needs_initial_advance = true
	if _built: _build_actors()
	if _hd_failed:
		processing = true
		_show_hd_error()
		return
	processing = _hd_enabled()
	var before: Dictionary = engine.snapshot()
	_consume_events(engine.advance(), before)
	_needs_initial_advance = false
	if _built:
		_render()
		if processing: _finish_initial_presentation(_presentation_generation)
		else: _check_result()

func select_command(kind: String, ability_id: String = "") -> void:
	if processing or engine == null or (_active_popup() != null and _active_popup() != _items): return
	var state: Dictionary = engine.snapshot()
	if state.get("phase") != "action_selection" or state.get("outcome", "") != "" or state.actors[state.active_actor_id].side != "player": return
	_nonce += 1
	pending_command = {"command_id": "ui_%d_%d" % [state.revision, _nonce], "expected_revision": int(state.revision), "actor_id": state.active_actor_id, "kind": kind, "ability_id": ability_id, "target_ids": []}
	last_error = ""
	_auto_targeted = false
	# 唯一合法目标自动选中：需要点选目标时只剩一个候选（最常见=单场最后一个敌人），
	# 直接预填目标，玩家一步确认即可；仍可 Esc 取消或改选（当前也无其他候选）。
	var options: Dictionary = command_options(kind, ability_id)
	if not options.get("automatic", false) and options.get("targets", []).size() == 1:
		pending_command.target_ids = [options.targets[0]]
		_auto_targeted = true
	if _built:
		_items.visible = false
		_render()

func select_target(actor_id: String) -> void:
	if processing or pending_command.is_empty() or _active_popup() != null: return
	# 空目标已是合法命令时，模型负责完整集合（全体／自身），点选不能覆写。
	if command_options(pending_command.kind, pending_command.ability_id).get("automatic", false): return
	pending_command.target_ids = [actor_id]
	_auto_targeted = false
	if _built: _render()

func current_preview() -> Dictionary:
	if engine == null or pending_command.is_empty(): return {"legal": false, "reasons": [], "effective_target_ids": [], "effects": [], "damage_ranges": [], "mp_cost": 0, "item_cost": 0, "cooldown": 0}
	return Presenter.preview(engine, pending_command)

func cancel_command() -> void:
	if processing or (_active_popup() != null and _active_popup() != _items): return
	pending_command = {}
	last_error = ""
	if _built:
		_items.visible = false
		_render()

func confirm_command() -> void:
	if processing or pending_command.is_empty() or engine == null or _active_popup() != null: return
	var preview := current_preview()
	if not preview.legal:
		last_error = "；".join(preview.reasons)
		if _built: _render()
		return
	# 在同一同步调用中先锁按钮，保留同一ID；重复输入不生成新命令。
	processing = true
	var committed := pending_command.duplicate(true)
	_display_actor_id = committed.actor_id
	var before: Dictionary = engine.snapshot()
	var result: Dictionary = engine.submit(committed)
	if not result.accepted:
		processing = false
		last_error = "；".join(result.reasons)
		if _built: _render()
		return
	pending_command = {}
	_consume_events(result.events, before)
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
	var before: Dictionary = engine.snapshot()
	_consume_events(engine.advance(), before)
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
func _process(delta: float) -> void:
	if is_instance_valid(_world_backdrop): _world_backdrop.sync_visuals(delta)
	_sync_effect_positions()
	presentation_tick.emit()
func _cancel_presentation() -> void:
	_flush_pending_logs()
	if is_instance_valid(_fx_layer): _fx_layer.clear()
	_effect_actions.clear()
	_visual_sequences.clear()
	_presentation_generation += 1
	presentation_tick.emit()
	if is_instance_valid(_hd_player): _hd_player.cancel()
	if is_instance_valid(_world_backdrop): _world_backdrop.cancel_trails()
	_reconcile_display_hp()
	processing = false
func _asset_session() -> RefCounted:
	if ChapterSession.current != null and ChapterSession.current.router == router: return ChapterSession.current
	if TrialSession.current != null and TrialSession.current.router == router: return TrialSession.current
	return null
func _hd_enabled() -> bool:
	return _is_chapter() or _asset_session() != null
func _is_chapter() -> bool:
	return (campaign != null and campaign.safe_snapshot().get("schema_version") == 2) or (ChapterSession.current != null and ChapterSession.current.router == router)
func _actor_definition(actor: Dictionary) -> Dictionary:
	var session := _asset_session()
	if session == null or session.bundle == null: return {}
	return session.bundle.get_definition(actor.get("identity_id", ""), actor.get("form_id", ""))


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
	var background_config: Dictionary = _config
	if _is_chapter() and campaign != null: background_config = Kit.config_for_night(_config, int(campaign.safe_snapshot().get("world", {}).get("night", 1)))
	if _is_chapter() and campaign != null:
		_world_backdrop = WorldBackdrop.new()
		_canvas.add_child(_world_backdrop)
		var visual_session := _asset_session()
		var depth_enabled: bool = visual_session.get_meta("hd2d_depth_enabled", true) if visual_session != null else true
		_world_backdrop.configure(campaign.safe_snapshot().get("world", {}), depth_enabled)
		_canvas.set_meta("background_path", "res://scripts/campaign/saga_world.gd" if campaign.safe_snapshot().has("saga") else "res://scripts/campaign/act_one_geometry.gd")
	else:
		_canvas.set_meta("background_path", background_config.fallback_background)
		Kit.backdrop(_canvas, background_config)
	_danger_layer = Node2D.new()
	_danger_layer.z_index = 1
	_canvas.add_child(_danger_layer)
	_fx_layer = BattleEffects.new()
	_skill_effects_ready = _fx_layer.production_enabled()
	_canvas.add_child(_fx_layer)
	Art.panel(_canvas, Rect2(32, 24, 550, 130))
	Art.panel(_canvas, Rect2(602, 24, 922, 130))
	_hud.title = Kit.label(_canvas, "遭遇  ·  夜巡异象", Rect2(72, 48, 470, 36), 27)
	if campaign != null and campaign.safe_snapshot().has("saga"):
		var encounter: Dictionary = _catalog.get_definition("encounters", str(campaign.safe_snapshot().pending_battle.get("encounter_id", "")))
		_hud.title.text = str(encounter.get("name", "夜巡异象"))
		_hud.title.tooltip_text = str(encounter.get("objective", ""))
	_hud.turn = Kit.label(_canvas, "", Rect2(72, 96, 470, 32), 23)
	Kit.muted(Kit.label(_canvas, "本轮顺序", Rect2(642, 48, 842, 28), 20))
	_hud.queue = Kit.label(_canvas, "", Rect2(642, 90, 842, 36), 22)
	_hud.queue.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hud.queue.mouse_filter = Control.MOUSE_FILTER_PASS
	_hud.log_toggle = _art_button(_canvas, "日志", Rect2(1540, 28, 144, 92), _toggle_log)
	_hud.exit = _art_button(_canvas, "返回标题", Rect2(1696, 28, 192, 92), _return_title)
	_hud.form = _art_button(_canvas, "焰华切换职业", Rect2(1408, 124, 480, 88), switch_active_form)
	_hud.form.add_theme_font_size_override("font_size", 20)
	_hud.form.hide()
	_hud.prompt = Kit.label(_canvas, "选择技能 → 点击目标 → 确认　／　Esc 取消选择", Rect2(50 if _config.near_side == "right" else 1000, 710, 850, 32), 22)
	_hud.prompt.add_theme_color_override("font_outline_color", Color("101918"))
	_hud.prompt.add_theme_constant_override("outline_size", 5)
	# 2×2保留技能名称、费用与摘要的可读字号，并让生图金边外另有安全留白。
	for index in range(4):
		var x := 752 + (index % 2) * 348
		var y := 760 + (index / 2) * 152
		var button := _art_button(_canvas, "技能", Rect2(x, y, 336, 132))
		button.pressed.connect(_select_skill_slot.bind(index))
		_skill_buttons.append(button)
	for row in [["attack_physical", "物理普攻", 760], ["defend", "防御", 856], ["item", "道具", 952]]:
		_basic_buttons[row[0]] = _art_button(_canvas, row[1], Rect2(1450, row[2], 194, 92), _basic_pressed.bind(row[0]))
	_basic_buttons.attack_magic = _art_button(_canvas, "中性魔攻", Rect2(1656, 760, 208, 92), select_command.bind("attack_magic"))
	_hud.cancel = _art_button(_canvas, "取消选择", Rect2(1656, 856, 208, 92), cancel_command)
	_hud.confirm = _art_button(_canvas, "确认行动", Rect2(1656, 952, 208, 92), confirm_command, true)
	_preview_panel = Art.panel(_canvas, Rect2(60 if _config.near_side == "left" else 956, 594, 932, 160))
	_hud.preview_title = Kit.label(_preview_panel, "", Rect2(40, 22, 560, 38), 26)
	_hud.preview_cost = Kit.muted(Kit.label(_preview_panel, "", Rect2(600, 30, 292, 28), 20))
	_hud.preview_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.preview = Kit.scroll_text(_preview_panel, Rect2(40, 66, 852, 84), 20)
	_popup_shade = ColorRect.new()
	_popup_shade.size = Vector2(1920, 1080)
	_popup_shade.color = Color(0.01, 0.018, 0.026, 0.7)
	_popup_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_shade.hide()
	_canvas.add_child(_popup_shade)
	_items = Art.panel(_canvas, Rect2(526, 150, 868, 890))
	_items.mouse_filter = Control.MOUSE_FILTER_STOP
	Kit.label(_items, "道具 · 占用本次行动", Rect2(40, 40, 530, 36), 25)
	_hud.items_close = _art_button(_items, "返回", Rect2(648, 22, 180, 92), _close_items)
	for index in range(ITEM_ORDER.size()):
		var id: String = ITEM_ORDER[index]
		var item: Dictionary = _catalog.get_definition("items", id)
		var button := _art_button(_items, item.name, Rect2(32, 124 + index * 96, 804, 92), select_command.bind("item", id))
		button.add_theme_font_size_override("font_size", 21)
		Art.left_text(button, 100, 40, 28)
		Art.icon(button, id, Rect2(32, 24, 44, 44))
		_hud["item_" + id] = button
	_items.visible = false
	_log_panel = Art.panel(_canvas, Rect2(530, 260, 860, 514))
	_log_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	Kit.label(_log_panel, "战斗日志", Rect2(40, 42, 540, 36), 27)
	_hud.log_close = _art_button(_log_panel, "收起", Rect2(640, 22, 180, 92), _toggle_log)
	_hud.log = Kit.scroll_text(_log_panel, Rect2(40, 118, 780, 358), 24)
	_hud.log.scroll_following = true
	_log_panel.visible = false
	_hud.latest = Kit.label(_canvas, "", Rect2(50, 1052, 1550, 26), 18)
	_result = Art.panel(_canvas, Rect2(435, 208, 1050, 688))
	_result.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.result_title = Kit.label(_result, "", Rect2(52, 42, 946, 66), 44)
	_hud.result_body = Kit.scroll_text(_result, Rect2(52, 138, 946, 340), 28)
	_hud.result_action = _art_button(_result, "", Rect2(52, 552, 455, 92), _result_action, true)
	_hud.result_exit = _art_button(_result, "返回标题 · 保留安全档", Rect2(535, 552, 463, 92), _result_secondary)
	_result.visible = false
	_built = true

# 内金边厚约8～12像素，文字再留至少20像素，不能只验证Control外框。
func _art_button(parent: Node, text: String, rect: Rect2, action: Callable = Callable(), primary: bool = false) -> Button:
	var button := Art.button(parent, text, rect, action, primary)
	Art.center_text(button, 34, 34, 28)
	return button

func _focus_cycle(buttons: Array) -> void:
	var enabled: Array[Button] = []
	for button in buttons:
		if button is Button and button.visible and not button.disabled: enabled.append(button)
	for index in enabled.size():
		var previous := enabled[posmod(index - 1, enabled.size())].get_path()
		var next := enabled[(index + 1) % enabled.size()].get_path()
		enabled[index].focus_previous = previous
		enabled[index].focus_next = next
		for direction in ["focus_neighbor_left", "focus_neighbor_top"]: enabled[index].set(direction, previous)
		for direction in ["focus_neighbor_right", "focus_neighbor_bottom"]: enabled[index].set(direction, next)

func _close_items() -> void:
	_close_popup()

func _resize_canvas() -> void:
	var available := get_viewport_rect().size
	var factor := minf(available.x / 1920.0, available.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (available - Vector2(1920, 1080) * factor) / 2.0

func _build_actors() -> void:
	if is_instance_valid(_fx_layer): _fx_layer.clear()
	_effect_actions.clear()
	if is_instance_valid(_world_backdrop): _world_backdrop.clear_visuals()
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
	var party_shift := _party_framing_shift(allies,state)
	var crowded := enemies.size() > 2
	var final_lineup := enemies.any(func(id): return state.actors[id].class_id == "saga_final_recoil")
	for index in range(allies.size() + enemies.size()):
		var ally := index < allies.size()
		var slot := index if ally else index - allies.size()
		var id: String = allies[slot] if ally else enemies[slot]
		var actor: Dictionary = state.actors[id]
		var layout: Array = _config.ally_slots[slot] if ally else (_config.boss_slot if actor.class_id == "gatekeeper" else _config.enemy_slots[slot])
		if ally and _hd_enabled():
			# 所有友方同一地面与px/m；只按身份物理身高，不按slot或武器画布fit。
			layout = [layout[0], Stature.battle_ground_y(), Stature.battle_body_height(actor.get("identity_id", ""))]
		# 三/四敌共享独立窄列；不把双敌面板放到交错脚点上互相覆盖。
		var compact := crowded and not ally
		if compact: layout = [(182 if final_lineup else 150) + slot * 224, 566, 220]
		var foot := Vector2(layout[0], layout[1])
		if _config.near_side == "left": foot.x = 1920 - foot.x
		if ally: foot.x += party_shift
		var shadow := Polygon2D.new()
		var points: PackedVector2Array = []
		for part in range(32): points.append(Vector2(cos(TAU * part / 32.0) * 72, sin(TAU * part / 32.0) * 15))
		shadow.polygon = points
		shadow.color = Color(0.02, 0.015, 0.03, 0.5)
		shadow.position = foot
		_canvas.add_child(shadow)
		var enemy_sprite_id: String = Presenter.sprite_id(actor.class_id, _catalog) if not ally else ""
		var art: String = _config.class_art[actor.class_id].actor if ally else _config.enemy_art.get(enemy_sprite_id, _config.enemy_art.default)
		var enemy_geometry: Dictionary = _config.get("enemy_geometry", {}).get(enemy_sprite_id, {}) if not ally else {}
		var enemy_art: Dictionary = SagaEnemyArt.definition(actor.class_id) if not ally else {}
		if enemy_art.get("ok", false):
			art = enemy_art.sheet
			enemy_geometry = enemy_art.geometry
		elif not enemy_art.is_empty():
			_hd_failed = true
			last_error = str(enemy_art.get("error", "敌方原图损坏"))
		var native_facing: String = str(enemy_art.get("facing", _config.asset_facings.get(art, "right")))
		var toward_right: bool = not ally if _config.near_side == "right" else ally
		var sprite: Node2D
		if ally and _hd_enabled():
			var hd := HdActor.new()
			var definition := _actor_definition(actor)
			if not hd.configure(definition, float(layout[2]), 1 if toward_right else -1):
				_hd_failed = true
				last_error = "人物高清素材未就绪，请重试加载"
			sprite = hd
			_canvas.add_child(sprite)
			_hd_views[id] = hd
		else:
			sprite = Kit.actor_sprite(_canvas, art, float(layout[2]), Kit.flip_for(native_facing, toward_right), enemy_geometry)
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
		ring.width = 2.5
		ring.default_color = Kit.color("ui_focus")
		ring.position = foot
		_canvas.add_child(ring)
		var target := Art.button(_canvas, "", Rect2(foot.x - 110, foot.y - float(layout[2]), 220, float(layout[2]) + 34), select_target.bind(id))
		for style in ["normal", "disabled"]: target.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		for style in ["hover", "pressed", "focus"]: target.add_theme_stylebox_override(style, Art.style("focus", 12))
		target.mouse_filter = Control.MOUSE_FILTER_PASS
		var card: Panel
		var avatar: TextureRect
		if ally:
			card = Art.panel(_canvas, Rect2(48 + slot * 234, 760, 222, 284), true)
			if _hd_enabled():
				var identity: String = actor.get("identity_id", "")
				var definition := _actor_definition(actor)
				var face := Portraits.from_definition(definition, identity, "avatar")
				avatar = TextureRect.new()
				avatar.position = Vector2(26, 26)
				avatar.size = Vector2(40, 40)
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
				avatar = Kit.image(card, _config.class_art[actor.class_id].badge, Rect2(26, 26, 40, 40))
		else:
			var card_x: float = (55.0 if _config.near_side == "right" else 1535.0) if actor.class_id == "gatekeeper" else foot.x - 164
			var card_y := 174.0 + slot * 4
			if actor.class_id != "gatekeeper": card_y = minf(card_y, foot.y - float(layout[2]) - 202.0)
			card = Art.panel(_canvas, Rect2(foot.x - 107, 154, 214, 174) if compact else Rect2(card_x, card_y, 328, 194), true)
		var content_width := card.size.x - 52
		var title := Kit.label(card, "", Rect2(78 if ally else 26, 26, 118 if ally else content_width, 32), 23 if ally else (18 if compact else 23))
		title.clip_text = true
		var hp := Kit.label(card, "", Rect2(26, 80 if ally else 62, content_width, 28), 20 if ally else (18 if compact else 20))
		var hpbar := Art.gauge(card, "hp", Rect2(26, 116 if ally else 94, content_width, 8))
		var mp := Kit.label(card, "", Rect2(26, 134 if ally else 108, content_width, 26), 20 if ally else 18)
		var mpbar: TextureProgressBar
		if ally: mpbar = Art.gauge(card, "mp", Rect2(26, 170, content_width, 8))
		var status := Kit.scroll_text(card, Rect2(26, 192 if ally else 142, content_width, 64 if ally else 30), 18 if ally else 17)
		status.add_theme_color_override("default_color", Color("d3d0b9"))
		if compact:
			title.position.y = 24
			title.size.y = 24
			hp.position.y = 54
			hpbar.position.y = 84
			mp.position.y = 98
			status.position.y = 130
			status.size.y = 24
		var intent: Label
		if not ally:
			var intent_rect := Rect2(55 if _config.near_side == "right" else 1510, 407, 365, 275) if actor.class_id == "gatekeeper" else Rect2(foot.x - 178, foot.y + 2, 356, maxf(52, 744 - (foot.y + 2)))
			if compact: intent_rect = Rect2(foot.x - 101, 574, 202, 124)
			intent = Kit.label(_canvas, "", intent_rect, 18 if compact else (22 if actor.class_id == "gatekeeper" else 20))
			intent.size.y = 34
			intent.autowrap_mode = TextServer.AUTOWRAP_OFF
			intent.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			intent.mouse_filter = Control.MOUSE_FILTER_PASS
			intent.add_theme_color_override("font_outline_color", Kit.color("ink_900"))
			intent.add_theme_constant_override("outline_size", 6)
		_actors[id] = {"sprite": sprite, "shadow": shadow, "ring": ring, "target": target, "card": card, "avatar": avatar, "title": title, "hp": hp, "mp": mp, "hpbar": hpbar, "mpbar": mpbar, "status": status, "intent": intent}
		if sprite.has_signal("presentation_position_changed"): sprite.connect("presentation_position_changed",_sync_actor_presentation.bind(id))
		if sprite is HdActor: sprite.animator.action_finished.connect(_on_effect_actor_finished.bind(str(id)))
	if _hd_enabled():
		if not is_instance_valid(_hd_player):
			_hd_player = HdEvents.new()
			add_child(_hd_player)
			_hd_player.event_presented.connect(_on_event_presented)
			_hd_player.action_started.connect(_on_action_started)
			_hd_player.drained.connect(_reconcile_display_hp)
			_hd_player.cancelled.connect(_on_presentation_cancelled)
		_hd_player.bind_actors(_presentation_views)
	if is_instance_valid(_world_backdrop):
		if not _world_backdrop.visuals_synchronized.is_connected(_sync_effect_positions): _world_backdrop.visuals_synchronized.connect(_sync_effect_positions)
		_world_backdrop.bind_visuals(_actors)
	# 模态保持在人物及点选热区前。
	for node in [_preview_panel, _popup_shade, _items, _log_panel, _result]: _canvas.move_child(node, -1)

func _render() -> void:
	if not _built or engine == null: return
	var state: Dictionary = engine.snapshot()
	# 只覆盖显示副本，实时预览/合法性始终读取engine权威状态。
	var shown := state.duplicate(true)
	for field in [["hp",_display_hp],["mp",_display_mp],["shield",_display_shields],["statuses",_display_statuses]]:
		for actor_id in field[1]:
			if shown.actors.has(actor_id): shown.actors[actor_id][field[0]] = field[1][actor_id]
	var model := Presenter.present(shown, _catalog, _display_actor_id if processing else "")
	if _actors.is_empty(): _build_actors()
	if _hd_failed:
		processing = true
		_show_hd_error()
		return
	_render_danger(model.danger)
	var active: Dictionary = state.actors.get(_display_actor_id if processing else state.active_actor_id, {})
	_hud.turn.text = "第 %d 轮　·　%s%s" % [state.round, Presenter.actor_name(active, _catalog), " 结算中…" if processing else " 行动"]
	var queue: Array[String] = []
	var queue_details: Array[String] = []
	for index in range(model.queue.size()):
		var queued: Dictionary = state.actors[model.queue[index]]
		var name := Presenter.actor_name(queued, _catalog)
		var short_name: String = Presenter.queue_name(queued, _catalog)
		queue.append(("▸" if index == model.queue_index else ("✓" if index < model.queue_index else "")) + short_name)
		queue_details.append(("当前 · " if index == model.queue_index else ("已行动 · " if index < model.queue_index else "")) + name)
	_hud.queue.text = "  →  ".join(queue)
	_hud.queue.tooltip_text = "本轮顺序\n" + "\n".join(queue_details)
	var preview := current_preview()
	var automatic: bool = not pending_command.is_empty() and command_options(pending_command.kind, pending_command.ability_id).get("automatic", false)
	for row in model.actors:
		var w: Dictionary = _actors[row.actor_id]
		w.title.text = (row.label if row.side == "enemy" and model.actors.size() > 5 else row.name) + (" · 倒地" if row.hp == 0 else "")
		if row.side == "enemy" and model.actors.size() > 5:
			w.title.tooltip_text = w.title.text
			for font_size in [18, 17, 16]:
				w.title.add_theme_font_size_override("font_size", font_size)
				if Kit.font.get_string_size(w.title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= w.card.size.x - 52: break
			w.title.size.x = w.card.size.x - 52
		w.hp.text = "HP %d / %d" % [row.hp, row.max_hp]
		w.hpbar.max_value = row.max_hp
		w.hpbar.value = row.hp
		if w.mpbar != null:
			w.mpbar.max_value = row.max_mp
			w.mpbar.value = row.mp
		w.mp.text = "MP %d / %d" % [row.mp, row.max_mp]
		var status_text := " / ".join(row.statuses) if not row.statuses.is_empty() else "无状态"
		var shield_text := "盾 %d%s" % [row.shield, " · %d次行动" % row.shield_remaining if row.shield > 0 else ""]
		w.status.tooltip_text = shield_text + "\n" + status_text
		var status_lines: Array[String] = []
		if row.shield > 0: status_lines.append(shield_text)
		if not row.statuses.is_empty(): status_lines.append(status_text)
		w.status.text = "\n".join(status_lines)
		if row.side == "enemy":
			# 窄卡首行只放可完整读完的状态名；时钟与全部状态仍可滚动或悬停查看。
			w.status.text = _enemy_status_summary(shown.actors[row.actor_id], row.shield, w.status.size.x, w.status.get_theme_font_size("normal_font_size")) + "\n" + "\n".join(status_lines) if not row.statuses.is_empty() else (shield_text if row.shield > 0 else "")
		w.status.visible = row.shield > 0 or not row.statuses.is_empty()
		if row.side == "enemy": w.mp.visible = row.max_mp > 0
		# 空状态收拢卡片，但生图内框继续保留原有20～28像素底部阅读区。
		var content_bottom: float = w.hpbar.position.y + w.hpbar.size.y
		if w.mp.visible: content_bottom = maxf(content_bottom, w.mp.position.y + w.mp.size.y)
		if w.mpbar != null: content_bottom = maxf(content_bottom, w.mpbar.position.y + w.mpbar.size.y)
		if w.status.visible: content_bottom = maxf(content_bottom, w.status.position.y + w.status.size.y)
		w.card.size.y = content_bottom + (28.0 if row.side == "player" else (20.0 if w.card.size.x < 300 else 22.0))
		w.sprite.modulate = Color(0.4, 0.4, 0.4, 0.55) if row.hp == 0 else Color.WHITE
		w.ring.visible = row.active or preview.effective_target_ids.has(row.actor_id)
		w.ring.default_color = Kit.color("vermilion_500") if preview.effective_target_ids.has(row.actor_id) else Kit.color("ui_focus")
		w.target.disabled = processing or pending_command.is_empty() or automatic
		w.target.add_theme_stylebox_override("normal", Art.style("focus", 12) if preview.effective_target_ids.has(row.actor_id) else StyleBoxEmpty.new())
		w.target.tooltip_text = "%s\n%s" % [row.label, w.status.tooltip_text]
		if w.intent != null:
			var full_intent: String = row.intent.get("text", "倒地" if row.hp == 0 else "意图待定")
			w.intent.text = full_intent.get_slice("\n", 0)
			w.intent.tooltip_text = full_intent
			w.target.tooltip_text += "\n" + full_intent
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
		var effect_text := Presenter.card_summary(slot, p, _catalog)
		var full_effect_text := Presenter.ability_summary(slot, p, _catalog)
		var cd_text := " · CD%d" % p.get("cooldown", slot.cooldown) if p.get("cooldown", slot.cooldown) > 0 else ""
		button.text = "%s　MP %d%s\n%s" % [slot.name, p.get("mp_cost", slot.mp_cost), cd_text, (slot.target_short + " · " + effect_text) if p.get("legal", false) or processing else reason]
		# 名称与费用独立成行；第二行只呈现模型摘要，完整效果继续保留悬停及行动预览。
		for font_size in [22, 20, 18, 17]:
			button.add_theme_font_size_override("font_size", font_size)
			if Array(button.text.split("\n")).all(func(line): return Kit.font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= 268): break
		button.size = Vector2(336, 132)
		Art.selected(button, pending_command.get("kind", "") == "skill" and pending_command.get("ability_id", "") == slot.id)
		button.tooltip_text = button.text + "\n" + full_effect_text + "\n" + slot.target_label + ("\n" + " / ".join(reasons) if not reasons.is_empty() else "")
	for kind in _basic_buttons:
		_basic_buttons[kind].disabled = processing or active.is_empty() or not state.outcome.is_empty()
		Art.selected(_basic_buttons[kind], pending_command.get("kind", "") == kind)
	_basic_buttons.attack_magic.visible = model.commands.basic.has("attack_magic")
	_hud.confirm.disabled = processing or not preview.legal
	_hud.cancel.disabled = processing or pending_command.is_empty()
	var is_homura: bool = active.get("identity_id") == "homura"
	var unlocked: bool = active.get("unlocked_forms", []).has("mage")
	_hud.form.visible = is_homura
	_hud.form.disabled = processing or not unlocked or state.get("phase") != "action_selection" or state.active_actor_id != active.get("actor_id")
	_hud.form.text = ("法师 → 剑士 · 自由切换" if active.get("form_id") == "mage" else "剑士 → 法师 · 自由切换") if unlocked else "剑士 · 法师第一夜战斗后解锁"
	_hud.form.tooltip_text = "共用HP/MP、CD、状态、装备和当前行动槽；切换不消耗行动，不治疗、不补蓝"
	var auto_single: bool = _auto_targeted and pending_command.get("target_ids", []).size() == 1
	var selection_prompt := ("全体目标已选，可直接确认" if preview.effective_target_ids.size() > 1 else "目标已选，可直接确认") if automatic else ("唯一目标已自动选中，可直接确认" if auto_single else "点击目标后确认")
	if not automatic and not auto_single and preview.legal and not preview.effective_target_ids.is_empty(): selection_prompt = "目标已选，可确认"
	_hud.prompt.text = last_error if not last_error.is_empty() else (selection_prompt + " · Esc 可取消" if not pending_command.is_empty() else "选择技能 → 点击目标 → 确认　／　Esc 取消选择")
	_preview_panel.visible = not pending_command.is_empty()
	if _preview_panel.visible:
		_hud.preview_title.text = Presenter.ability_name(pending_command.ability_id if not pending_command.ability_id.is_empty() else pending_command.kind, _catalog)
		var cost_parts: Array[String] = ["MP %d" % preview.mp_cost]
		if int(preview.get("cooldown", 0)) > 0: cost_parts.append("CD %d" % preview.cooldown)
		if preview.item_cost > 0: cost_parts.append("道具 %d" % preview.item_cost)
		_hud.preview_cost.text = " · ".join(cost_parts)
		var detail_lines: Array[String] = []
		if pending_command.kind == "skill":
			for slot in model.commands.skills:
				if slot.id == pending_command.ability_id:
					detail_lines.append(Presenter.ability_summary(slot, preview, _catalog) + "　·　" + slot.target_label)
		detail_lines.append_array(Presenter.preview_lines(preview, state, _catalog))
		_hud.preview.text = "\n".join(detail_lines)
	for id in _catalog.get_ids("items"):
		_hud["item_" + id].text = "%s　×%d" % [_catalog.get_definition("items", id).name, model.inventory.get(id, 0)]
		var options := command_options("item", id)
		_hud["item_" + id].disabled = processing or not options.get("preview", {}).get("legal", false)
		_hud["item_" + id].tooltip_text = "\n".join(Presenter.preview_lines(options.get("preview", {}), state, _catalog))
	_hud.log.text = "\n".join(_log_lines)
	_hud.latest.text = _log_lines.back() if not _log_lines.is_empty() else "HP/MP与库存跨战保留 · 道具占用一次行动"
	_sync_modal_focus()

func _enemy_status_summary(actor: Dictionary, shield: int, width: float, font_size: int) -> String:
	var names: Array[String] = []
	for status in actor.get("statuses", []):
		names.append(_catalog.get_definition("statuses", status.id).get("name", status.id))
	var prefix := "盾%d · " % shield if shield > 0 else ""
	for count in range(names.size(), 0, -1):
		var summary := prefix + " / ".join(names.slice(0, count)) + (" +%d" % (names.size() - count) if count < names.size() else "")
		if Kit.font.get_string_size(summary, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width - 16: return summary
	return prefix + "%d种状态" % names.size()

# 自由切换也是权威引擎的一次标准命令；不调用advance、不结束当前行动槽。
func switch_active_form() -> Dictionary:
	if processing or engine == null or _active_popup() != null: return {"accepted": false, "reasons": ["当前表现尚未结束或正在查看弹层"]}
	var state: Dictionary = engine.snapshot()
	var actor: Dictionary = state.get("actors", {}).get(state.get("active_actor_id", ""), {})
	if actor.get("identity_id") != "homura" or state.get("phase") != "action_selection": return {"accepted": false, "reasons": ["仅焰华自己的行动机会可以切换"]}
	var target := "mage" if actor.get("form_id") == "sword" else "sword"
	_nonce += 1
	var command := {"command_id": "form_%d_%d" % [state.revision, _nonce], "expected_revision": int(state.revision), "actor_id": actor.actor_id, "kind": "switch_form", "ability_id": "", "target_ids": [], "form_id": target}
	var preview: Dictionary = engine.preview(command)
	if not preview.get("legal", false):
		last_error = "；".join(preview.get("reasons", []))
		if _built: _render()
		return {"accepted": false, "reasons": preview.get("reasons", [])}
	var form_actor := actor.duplicate(true)
	form_actor.form_id = target
	if _hd_enabled() and not _actor_definition(form_actor).get("ok", false):
		last_error = "焰华另一形态资源尚未就绪，请重试加载"
		_hd_failed = true
		if _built: _show_hd_error()
		return {"accepted": false, "reasons": [last_error]}
	var result: Dictionary = engine.submit(command)
	if not result.get("accepted", false):
		last_error = "；".join(result.get("reasons", []))
		if _built: _render()
		return result
	pending_command = {}
	last_error = ""
	_display_actor_id = ""
	_sync_hd_forms(engine.snapshot())
	_consume_events(result.events)
	if _built: _render()
	return result

func _sync_hd_forms(state: Dictionary) -> void:
	for actor_id in _hd_views:
		var actor: Dictionary = state.actors[actor_id]
		var hd: Node2D = _hd_views[actor_id]
		if hd._definition.get("manifest", {}).get("form_id") == actor.get("form_id"): continue
		var definition := _actor_definition(actor)
		if not hd.configure(definition, float(hd.get_meta("content_height")), 1 if hd.get_meta("facing_right") else -1):
			_hd_failed = true
			last_error = "焰华高清形态未能切换，请重试资源"
			continue
		var face := Portraits.from_definition(definition, actor.identity_id, "avatar")
		if not face.ok:
			_hd_failed = true
			last_error = face.error
			continue
		_actors[actor_id].avatar.texture = face.texture
		_actors[actor_id].avatar.set_meta("source_path", face.source_path)

func _select_skill_slot(index: int) -> void:
	var model := Presenter.present(engine.snapshot(), _catalog)
	if index < model.commands.skills.size(): select_command("skill", model.commands.skills[index].id)

func _basic_pressed(kind: String) -> void:
	if _active_popup() != null: return
	if kind == "item":
		if not processing:
			_items.visible = true
			_sync_modal_focus()
	else: select_command(kind)

func _toggle_log() -> void:
	if _active_popup() == _log_panel: _close_popup(); return
	if _active_popup() != null: return
	_log_panel.visible = true
	_sync_modal_focus()

func _close_popup() -> void:
	_items.hide()
	_log_panel.hide()
	_sync_modal_focus()

func _active_popup() -> Control:
	for node in [_exit_confirmation, _asset_error_panel, _result, _items, _log_panel]:
		if is_instance_valid(node) and node.visible: return node
	return null

func _collect_focus_controls(node: Node, controls: Array[Control]) -> void:
	if node is Control and node.focus_mode != Control.FOCUS_NONE: controls.append(node)
	for child in node.get_children(): _collect_focus_controls(child, controls)

# 弹层遮罩挡鼠标，显式撤下后层焦点；关闭后恢复原来的键盘位置。
func _sync_modal_focus() -> void:
	var popup := _active_popup()
	if is_instance_valid(_popup_shade): _popup_shade.visible = popup != null
	if popup == _modal_focus_root: return
	for saved in _modal_focus_modes:
		if is_instance_valid(saved.control): saved.control.focus_mode = saved.mode
	_modal_focus_modes.clear()
	if popup == null:
		_modal_focus_root = null
		if is_instance_valid(_modal_previous_focus) and _modal_previous_focus.is_visible_in_tree(): _modal_previous_focus.grab_focus()
		_modal_previous_focus = null
		return
	if _modal_focus_root == null: _modal_previous_focus = get_viewport().gui_get_focus_owner()
	_modal_focus_root = popup
	var controls: Array[Control] = []
	_collect_focus_controls(_canvas, controls)
	var local: Array[Control] = []
	for control in controls:
		if popup.is_ancestor_of(control) and control.is_visible_in_tree():
			if control.focus_mode in [Control.FOCUS_CLICK, Control.FOCUS_ALL] and (not control is BaseButton or not control.disabled): local.append(control)
		else:
			_modal_focus_modes.append({"control": control, "mode": control.focus_mode})
			control.focus_mode = Control.FOCUS_NONE
	for index in range(local.size()):
		var current := local[index]
		var previous := local[(index + local.size() - 1) % local.size()].get_path()
		var next := local[(index + 1) % local.size()].get_path()
		current.focus_previous = previous; current.focus_next = next
		current.focus_neighbor_top = previous; current.focus_neighbor_left = previous
		current.focus_neighbor_bottom = next; current.focus_neighbor_right = next
	if not local.is_empty() and not local.has(get_viewport().gui_get_focus_owner()): local[0].grab_focus()

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

func _event_log_key(event: Dictionary) -> String:
	var sequence := int(event.get("sequence",0))
	if sequence>0: return str(sequence)
	# 老夹具可能没有sequence；只取原始字段，不把视觉标注混进键。
	return JSON.stringify([event.get("type"),event.get("actor_id"),event.get("target_id"),event.get("payload",{})]).sha256_text()
func _append_log_lines(lines: Array) -> void:
	for line in lines: _log_lines.append(str(line))
	while _log_lines.size()>80: _log_lines.pop_front()
	if _built and is_instance_valid(_hud.get("log")):
		_hud.log.text="\n".join(_log_lines)
		_hud.latest.text=_log_lines.back() if not _log_lines.is_empty() else "HP/MP与库存跨战保留 · 道具占用一次行动"
func _present_event_log(event: Dictionary) -> void:
	var key := _event_log_key(event)
	if not _pending_logs.has(key): return
	_append_log_lines(_pending_logs[key])
	_pending_logs.erase(key)
func _flush_pending_logs() -> void:
	# 表现取消不会回滚已提交模型；结束时保留完整已结算账目，但不重播效果。
	for lines in _pending_logs.values(): _append_log_lines(lines)
	_pending_logs.clear()

func _consume_events(events: Array, before: Dictionary = {}) -> void:
	if engine == null: return
	var state: Dictionary = engine.snapshot()
	var played: Dictionary = {}
	var defer_logs := _hd_enabled() and is_instance_valid(_hd_player)
	for event in events:
		var sequence := int(event.get("sequence",0))
		if sequence>0 and _log_event_seen.has(sequence): continue
		if sequence>0: _log_event_seen[sequence]=true
		var lines: Array[String] = []
		var line := Presenter.event_line(event, state, _catalog)
		if not line.is_empty(): lines.append(line)
		if campaign != null and campaign.safe_snapshot().has("saga"):
			var safe: Dictionary = campaign.safe_snapshot()
			var narrative: Dictionary = Saga.scene(str(safe.saga.active_scene))
			lines.append_array(SagaNarrator.select(narrative.get("battle_lines", []), event, safe, _saga_narration_seen, state.actors))
		# 结算已提交但表现尚未到M；日志与可见HP一样等待该事件，不能提前透露结果。
		if defer_logs and event.get("type") not in ["command_accepted","form_changed"]:
			if not lines.is_empty(): _pending_logs[_event_log_key(event)]=lines
		else: _append_log_lines(lines)
		if _built and not _hd_enabled():
			_play_visual_effect(event)
			_event_fx(event)
			if event.type == "damage" and not played.has(event.actor_id):
				played[event.actor_id] = true
				_play_action(event.actor_id, [event.target_id])
	if _hd_enabled() and is_instance_valid(_hd_player):
		# free switch_form没有攻击动作；command_accepted仍进入日志，模型事件不丢失。
		var visual_events: Array = events.filter(func(event): return not (event.get("type") == "command_accepted" and event.get("payload", {}).get("command", {}).get("kind") == "switch_form")).duplicate(true)
		# 在HP暂存前拒绝重复事件，不能等队列去重后才把已显示HP恢复一次。
		visual_events = visual_events.filter(func(event): return int(event.get("sequence",0)) <= 0 or not _visual_sequences.has(int(event.sequence)))
		for event in visual_events:
			if int(event.get("sequence",0)) > 0: _visual_sequences[int(event.sequence)] = true
		if visual_events.any(func(event): return event.get("type") != "form_changed"):
			_annotate_effect_context(visual_events,state)
			_defer_impact_hp(visual_events, before, state)
			_hd_player.enqueue(visual_events, state)
	while _log_lines.size() > 80: _log_lines.pop_front()

func _check_result() -> void:
	if engine == null or engine.snapshot().outcome.is_empty(): return
	pending_command = {}
	_result.visible = true
	_items.hide()
	_log_panel.hide()
	_focus_cycle([_hud.result_action, _hud.result_exit])
	_hud.result_action.grab_focus()
	if not result_saved: save_result()
	_show_result()
	_sync_modal_focus()

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
	_hud.result_title.text = "异象平息" if victory else "队伍败北"
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
		lines.append("本夜战斗已完成 · 返回调查现场" if _is_chapter() else ("水钵异常已解决 · 返回参道" if _hd_enabled() else ("连战完成" if saved.next_encounter_id.is_empty() else ("下一步：休息准备点" if saved.phase == "rest" else "下一场普通战"))))
	else:
		lines.append("重试将恢复同一战前状态、库存与种子")
		lines.append("没有额外补给或经验")
	if result_saved and not last_error.is_empty(): lines.append(last_error)
	_hud.result_body.text = "\n".join(lines)
	_hud.result_exit.text = "返回整备 · 保留战前资源" if not victory and campaign != null and campaign.safe_snapshot().has("saga") else "返回标题 · 保留安全档"
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
		_sync_modal_focus()
		_log_lines.clear(); _pending_logs.clear(); _log_event_seen.clear()
		_saga_narration_seen.clear()
		bind(router.create_engine(), campaign)
	else:
		_navigating = true
		var error := _change_scene(result_response.get("next_scene", "res://scenes/rpg/launcher.tscn"))
		if error != OK:
			_navigating = false
			last_error = "返场失败（%d），安全战果已保存，可重试返回" % error
			_show_result()

func _result_secondary() -> void:
	if _navigating: return
	if campaign != null and campaign.safe_snapshot().has("saga") and engine != null and engine.snapshot().outcome == "defeat":
		var result: Dictionary = campaign.leave_saga_battle()
		if not result.ok:
			last_error = result.error
			_show_result()
			return
		router.resume_exploration()
		_navigating = true
		if _change_scene(Saga.SCENE_PATH) != OK:
			_navigating = false
			last_error = "返回整备失败，战前进度已保存，可从标题继续"
			_show_result()
		return
	_return_title()

func _return_title() -> void:
	if _hd_enabled():
		if is_instance_valid(_exit_confirmation): return
		_exit_previous_focus = get_viewport().gui_get_focus_owner()
		_exit_confirmation = Control.new()
		_exit_confirmation.size = Vector2(1920, 1080)
		_canvas.add_child(_exit_confirmation)
		Art.panel(_exit_confirmation, Rect2(410, 224, 1100, 566))
		_exit_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
		Kit.label(_exit_confirmation, "返回标题？", Rect2(470, 280, 980, 70), 42)
		var message := "继续游戏会从同一战前状态重试。未提交的战斗过程不会保存。"
		if engine != null and engine.snapshot().outcome == "victory" and not result_saved: message = "战果尚未保存。返回标题会丢失本场未提交战果，继续游戏将回到同一战前状态。"
		if result_saved and engine != null and engine.snapshot().outcome == "victory": message = "战果已安全保存。继续游戏将回到调查现场。"
		var body := Kit.label(_exit_confirmation, message, Rect2(470, 380, 980, 150), 30)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var leave := _art_button(_exit_confirmation, "返回标题", Rect2(470, 634, 460, 92), _confirm_return_title)
		var cancel := _art_button(_exit_confirmation, "取消", Rect2(970, 634, 460, 92), _cancel_return_title)
		# Tab与四方向都只在当前确认框内循环，默认保留本场。
		leave.focus_next = cancel.get_path(); leave.focus_previous = cancel.get_path()
		cancel.focus_next = leave.get_path(); cancel.focus_previous = leave.get_path()
		for direction in ["focus_neighbor_left", "focus_neighbor_right", "focus_neighbor_top", "focus_neighbor_bottom"]:
			leave.set(direction, cancel.get_path())
			cancel.set(direction, leave.get_path())
		cancel.grab_focus()
		_sync_modal_focus()
		return
	_confirm_return_title()
func _cancel_return_title() -> void:
	if is_instance_valid(_exit_confirmation):
		_exit_confirmation.hide()
		_exit_confirmation.queue_free()
	_exit_confirmation = null
	_sync_modal_focus()
	if is_instance_valid(_exit_previous_focus): _exit_previous_focus.grab_focus()
	_exit_previous_focus = null
func _confirm_return_title() -> void:
	var session := _asset_session()
	var error := _change_scene("res://scenes/campaign/title.tscn" if _is_chapter() else "res://scenes/v3/title.tscn")
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
	_asset_error_panel = Art.panel(_canvas, Rect2(430, 300, 1060, 470))
	Kit.label(_asset_error_panel, "人物素材尚未就绪", Rect2(42, 32, 970, 60), 38)
	var body := Kit.label(_asset_error_panel, last_error + "\n战前状态保持不变，请重试加载。", Rect2(42, 115, 970, 170), 28)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_art_button(_asset_error_panel, "重试加载", Rect2(42, 330, 464, 92), _retry_hd_assets)
	_art_button(_asset_error_panel, "返回标题", Rect2(546, 330, 464, 92), _return_title)
	_asset_error_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_sync_modal_focus()
func _retry_hd_assets() -> void:
	if not _hd_enabled() or _asset_loading: return
	if _asset_session() == null:
		last_error = "正式人物会话已失效，请返回标题继续安全档"
		_show_hd_error()
		return
	if not await _prewarm_battle_assets(): return
	if is_instance_valid(_asset_error_panel): _asset_error_panel.queue_free()
	_asset_error_panel = null
	_sync_modal_focus()
	if engine == null: bind(router.create_engine(), campaign)
	elif _needs_initial_advance: bind(engine, campaign)
	else:
		# 已提交命令不能重放；取消旧表现后，只为尚未开启的下一槽推进一次。
		_cancel_presentation()
		_build_actors()
		if _hd_failed:
			_render()
			return
		var state: Dictionary = engine.snapshot()
		if state.outcome.is_empty() and state.phase != "action_selection":
			processing = true
			_consume_events(engine.advance(), state)
			_render()
			_finish_initial_presentation(_presentation_generation)
		else:
			_render()
			_check_result()
func _exit_tree() -> void:
	if _asset_loading:
		var session := _asset_session()
		if session != null and session == ChapterSession.current: session.cancel_asset_preparation(_asset_request)
	_cancel_presentation()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(_exit_confirmation):
		get_viewport().set_input_as_handled()
		_cancel_return_title()
		return
	if event.is_action_pressed("ui_cancel"):
		if _active_popup() in [_items, _log_panel] and _active_popup() != null: _close_popup()
		elif _active_popup() != null: return
		else: cancel_command()
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

func _prewarm_battle_assets(entering_scene: bool = false) -> bool:
	var session := _asset_session()
	# 孤立模型与完整注入夹具没有正式会话，继续由原定义提供器负责。
	if session == null or (entering_scene and session != ChapterSession.current): return true
	_asset_loading = true
	processing = true
	var generation := _presentation_generation
	if session == ChapterSession.current: _asset_request = session.asset_generation + 1
	var result: Dictionary = await session.prepare_assets("battle", entering_scene) if session == ChapterSession.current else await session.prepare_assets()
	_asset_loading = false
	if generation != _presentation_generation or not is_inside_tree(): return false
	if not result.get("ok", false):
		_hd_failed = true
		last_error = str(result.get("error", "人物素材加载失败"))
		_show_hd_error()
		return false
	processing = false
	return true

func _defer_impact_hp(events: Array, before: Dictionary, state: Dictionary) -> void:
	var timed_action := false
	for event in events:
		var payload: Dictionary = event.get("payload", {})
		if event.get("type") == "command_accepted":
			var source = _presentation_views.get(str(event.get("actor_id", "")))
			timed_action = false
			var kind: String = str(payload.get("command", {}).get("kind", ""))
			if is_instance_valid(source) and kind != "defend":
				# 旧敌人没有视频命中标记，队列本来就等待其动作结束；HUD服从同一个事件边界。
				if source is LegacyActor:
					timed_action = true
				elif source is HdActor:
					var action := "item" if kind == "item" else "attack"
					var impact: Variant = source._definition.get("manifest", {}).get("anims", {}).get(action, {}).get("impact_ms")
					timed_action = (impact is int or impact is float) and is_finite(float(impact)) and float(impact) > 0
			continue
		if not timed_action: continue
		var target := str(event.get("target_id", ""))
		if not state.actors.has(target): continue
		var previous: Dictionary = before.get("actors", {}).get(target, state.actors[target])
		var display := {"target":target}
		var absorption: Dictionary = payload.get("absorption", {})
		match str(event.get("type", "")):
			"resources_changed":
				display.mp = int(payload.get("mp_after",previous.mp))
				if not _display_mp.has(target): _display_mp[target] = int(payload.get("mp_before",previous.mp))
			"damage", "periodic_damage", "saga_reflected":
				if not absorption.has("hp_after"): continue
				display.hp = int(absorption.hp_after)
				display.shield = absorption.get("shield_after", {}).duplicate(true)
				if not _display_hp.has(target): _display_hp[target] = int(absorption.get("hp_before", previous.hp))
				if not _display_shields.has(target): _display_shields[target] = absorption.get("shield_before", previous.get("shield", {})).duplicate(true)
				# 致死由absorb直接清空状态，不另发status_removed；与HP同一命中令牌显示。
				if bool(absorption.get("defeated",false)):
					display.statuses = []
					if not _display_statuses.has(target): _display_statuses[target] = previous.get("statuses",[]).duplicate(true)
			"healed":
				display.hp = int(payload.get("after", state.actors[target].hp))
				if not _display_hp.has(target): _display_hp[target] = int(payload.get("before", previous.hp))
			"revived":
				display.hp = int(payload.get("hp", state.actors[target].hp))
				if not _display_hp.has(target): _display_hp[target] = int(previous.hp)
			"mp_restored":
				display.mp = int(payload.get("after", state.actors[target].mp))
				if not _display_mp.has(target): _display_mp[target] = int(payload.get("before", previous.mp))
			"shield_applied", "shield_refreshed", "shield_tick":
				display.shield = payload.get("shield", payload.get("after", {})).duplicate(true)
				if not _display_shields.has(target): _display_shields[target] = previous.get("shield", {}).duplicate(true)
			"shield_removed":
				display.shield = {}
				if not _display_shields.has(target): _display_shields[target] = previous.get("shield", {}).duplicate(true)
			"status_applied", "status_refreshed", "status_removed", "status_tick":
				display.status_event = event.duplicate(true)
				if not _display_statuses.has(target): _display_statuses[target] = previous.get("statuses", []).duplicate(true)
			_: continue
		_hp_event_nonce += 1
		event["_hp_presentation_id"] = _hp_event_nonce
		_pending_hp_events[_hp_event_nonce] = display

func _play_visual_effect(event: Dictionary) -> void:
	if not _skill_effects_ready: return
	if not is_instance_valid(_fx_layer) or engine == null: return
	var context: Dictionary = event.get("_effect_context",{})
	if not context.is_empty() and int(context.get("generation",-1)) != _presentation_generation: return
	var target_id := str(event.get("target_id", ""))
	var source_id := str(event.get("actor_id", ""))
	if not _actors.has(target_id): return
	var state: Dictionary = engine.snapshot()
	var source: Dictionary = state.actors.get(source_id,{})
	var identity := str(source.get("identity_id",source.get("class_id","")))
	var form := "homura_" + str(source.get("form_id","sword")) if identity == "homura" else identity
	var target := _effect_center(target_id)
	var origin := target
	if _actors.has(source_id): origin = _effect_center(source_id)
	var effect_event := event
	if event.get("type") == "saga_reflected":
		# 原事件/HP令牌不变，只把已发生的反射伤害交给伤害视觉入口。
		effect_event = event.duplicate(true)
		effect_event.type = "damage"
		form = str(context.get("form",form))
	var spawned: bool = _fx_layer.present_event(effect_event,form,origin,target,_effect_battle_id(),context)
	if spawned and event.get("type") == "damage" and _hd_views.has(source_id):
		_hd_views[source_id].animator.hit_stop(0.045)

func _on_event_presented(event: Dictionary) -> void:
	if event.has("_presentation_generation") and int(event._presentation_generation) != _presentation_generation: return
	var context: Dictionary = event.get("_effect_context",{})
	if not context.is_empty() and int(context.get("generation",-1)) != _presentation_generation: return
	_present_event_log(event)
	_play_visual_effect(event)
	var token := int(event.get("_hp_presentation_id", -1))
	if not _pending_hp_events.has(token):
		# 倒地事件已先启动down；无资源令牌时也必须把首帧同步到真正绘制的3D身体。
		if event.get("type") == "actor_defeated" and is_inside_tree() and is_instance_valid(_world_backdrop): _world_backdrop.sync_visuals(0.0)
		return
	var displayed: Dictionary = _pending_hp_events[token]
	_pending_hp_events.erase(token)
	var target: String = displayed.target
	if displayed.has("hp"): _display_hp[target] = displayed.hp
	if displayed.has("mp"): _display_mp[target] = displayed.mp
	if displayed.has("shield"): _display_shields[target] = displayed.shield
	if displayed.has("statuses"): _display_statuses[target] = displayed.statuses
	if displayed.has("status_event"):
		var status_event: Dictionary = displayed.status_event
		var status: Dictionary = status_event.payload.get("status", status_event.payload.get("after", {}))
		var values: Array = _display_statuses.get(target, [])
		values = values.filter(func(value): return value.id != status.get("id", ""))
		if status_event.type != "status_removed": values.append(status.duplicate(true))
		_display_statuses[target] = values
	if _built and is_inside_tree():
		_render()
		# 子队列在本帧_process之后发事件；同帧同步实际3D颜色，不额外推进遮挡时钟。
		if is_instance_valid(_world_backdrop): _world_backdrop.sync_visuals(0.0)

func _reconcile_display_hp() -> void:
	if _display_hp.is_empty() and _display_mp.is_empty() and _display_shields.is_empty() and _display_statuses.is_empty() and _pending_hp_events.is_empty(): return
	_display_hp.clear()
	_display_mp.clear()
	_display_shields.clear()
	_display_statuses.clear()
	_pending_hp_events.clear()
	# 取消/解绑可能发生在搭建或退出中，只更新现有控件，不能重入_build_actors。
	if not _built or engine == null: return
	var model := Presenter.present(engine.snapshot(), _catalog)
	for row in model.actors:
		if not _actors.has(row.actor_id): continue
		var widgets: Dictionary = _actors[row.actor_id]
		if not is_instance_valid(widgets.hp): continue
		widgets.hp.text = "HP %d / %d" % [row.hp, row.max_hp]
		widgets.hpbar.value = row.hp
		widgets.mp.text = "MP %d / %d" % [row.mp, row.max_mp]
		if widgets.mpbar != null: widgets.mpbar.value = row.mp
		var status_lines: Array[String] = []
		if row.shield > 0: status_lines.append("盾 %d · %d次行动" % [row.shield,row.shield_remaining])
		if not row.statuses.is_empty(): status_lines.append(" / ".join(row.statuses))
		widgets.status.text = "\n".join(status_lines)
		widgets.status.visible = not status_lines.is_empty()
		widgets.title.text = (row.label if row.side == "enemy" and model.actors.size() > 5 else row.name) + (" · 倒地" if row.hp == 0 else "")
		widgets.sprite.modulate = Color(0.4, 0.4, 0.4, 0.55) if row.hp == 0 else Color.WHITE
		if widgets.sprite.has_method("set_downed"): widgets.sprite.set_downed(row.hp == 0)
	if is_inside_tree() and is_instance_valid(_world_backdrop): _world_backdrop.sync_visuals(0.0)

# 恢复重置前完整函数：双形态共同预留，切形态不改变编队位置。
func _party_framing_shift(allies: Array, state: Dictionary) -> float:
	if not _hd_enabled() or not is_instance_valid(_world_backdrop): return 0.0
	var bounds: Array[Rect2] = []
	var mirrored: bool = _config.near_side == "right"
	for slot in allies.size():
		var actor: Dictionary = state.actors[allies[slot]]
		var foot := Vector2(float(_config.ally_slots[slot][0]),Stature.battle_ground_y())
		if not mirrored: foot.x = 1920.0-foot.x
		var forms: Array = [actor.get("form_id", "")]
		if actor.get("identity_id", "") == "homura": forms = ["mage","sword"]
		for form in forms:
			var candidate := actor.duplicate(true)
			candidate.form_id = form
			var definition := _actor_definition(candidate)
			if not definition.get("ok",false): continue
			var flip: bool = mirrored and definition.manifest.get("mirror_allowed",true)
			bounds.append(PartyFraming.projected_bounds(_world_backdrop.camera,_world_backdrop._ground_point(foot),definition,flip))
	return PartyFraming.inward_translation(bounds)

func _sync_actor_presentation(actor_id: String) -> void:
	if not _actors.has(actor_id): return
	var widgets: Dictionary = _actors[actor_id]
	if not is_instance_valid(widgets.sprite): return
	var foot: Vector2 = widgets.sprite.position
	widgets.sprite.set_meta("foot_point",foot)
	if is_instance_valid(widgets.ring): widgets.ring.position = foot
	if is_instance_valid(widgets.shadow): widgets.shadow.position = foot
	if is_instance_valid(widgets.target): widgets.target.position = foot-Vector2(110,float(widgets.sprite.get_meta("content_height",300)))

func _on_presentation_cancelled() -> void:
	_flush_pending_logs()
	# 队列也可单独取消/重新绑定；其旧信号上下文不能重新生成特效或覆盖HP。
	_presentation_generation += 1
	presentation_tick.emit()
	processing = false
	if is_instance_valid(_fx_layer): _fx_layer.clear()
	_effect_actions.clear()
	if is_instance_valid(_world_backdrop): _world_backdrop.cancel_trails()
	_reconcile_display_hp()

func _effect_battle_id() -> String:
	return "%s:%s" % [engine.get_instance_id(),_presentation_generation]

func _sync_effect_positions() -> void:
	if not _skill_effects_ready or not is_instance_valid(_fx_layer) or not _fx_layer.has_method("update_positions"): return
	var positions := {}
	var hands := {}
	for actor_id in _actors:
		if not is_instance_valid(_actors[actor_id].sprite): continue
		positions[str(actor_id)]=_effect_center(str(actor_id))
		if is_instance_valid(_world_backdrop):
			var point: Dictionary = _world_backdrop.actor_action_attachment(str(actor_id))
			if point.ok: hands[str(actor_id)]=point.position
	_fx_layer.update_positions(positions,hands)

func _effect_center(actor_id: String) -> Vector2:
	if is_instance_valid(_world_backdrop) and _world_backdrop.actor_entries.has(actor_id):
		return _world_backdrop.actor_effect_center(actor_id)
	var source: Node2D = _actors[actor_id].sprite
	return source.position-Vector2(0,float(source.get_meta("content_height",300))*.48)

# 仅标注已经复制的视觉事件；实际承伤/受益者决定FX目标，反射和回合燃烧单独处理。
func _annotate_effect_context(events: Array, state: Dictionary) -> void:
	var context: Dictionary = {}
	for event in events:
		# 周期事件没有技能上下文，仍必须独立携带换场/取消代次。
		event["_presentation_generation"] = _presentation_generation
		if event.get("type") == "command_accepted":
			context = event.get("payload",{}).get("command",{}).duplicate(true)
			context["source_id"] = str(event.get("actor_id",""))
			context["effect_target_ids"] = []
			context["generation"] = _presentation_generation
			var actor: Dictionary = state.actors.get(context.source_id,{})
			var identity := str(actor.get("identity_id",actor.get("class_id","")))
			context["form"] = "homura_"+str(actor.get("form_id","sword")) if identity=="homura" else identity
		if event.get("type") == "periodic_damage":
			event["_effect_context"] = {}
			continue
		event["_effect_context"] = context
		if context.is_empty() or event.get("type") not in ["damage","healed","revived","mp_restored","shield_applied","shield_refreshed","status_applied","status_refreshed","status_removed","cleansed","charge_interrupted","effect_ignored"]: continue
		if event.get("type") == "status_removed" and event.get("payload",{}).get("reason") != "cleanse": continue
		var target_id := str(event.get("target_id",""))
		if _actors.has(target_id) and not context.effect_target_ids.has(target_id): context.effect_target_ids.append(target_id)

func _on_action_started(event: Dictionary, timing: Dictionary) -> void:
	if not _skill_effects_ready or not is_instance_valid(_fx_layer) or engine == null: return
	var context: Dictionary = event.get("_effect_context",{}).duplicate(true)
	if context.is_empty() or int(context.get("generation",-1)) != _presentation_generation: return
	var source_id := str(context.get("source_id",""))
	if not _actors.has(source_id): return
	# 接近已经完成；这里以原生命中剩余时长启动一次起手/飞行。
	context["impact_delay"] = float(timing.get("native_impact_seconds",0))
	context["action_duration"] = float(timing.get("action_duration",0))
	_effect_actions[source_id]={"context":context,"battle_id":_effect_battle_id()}
	var targets := {}
	for target_id in context.get("effect_target_ids",[]):
		if _actors.has(target_id): targets[str(target_id)] = _effect_center(str(target_id))
	var origin := _effect_center(source_id)
	if _fx_layer.has_method("requires_source_attachment") and _fx_layer.requires_source_attachment():
		var point: Dictionary = _world_backdrop.actor_action_attachment(source_id) if is_instance_valid(_world_backdrop) else {"ok":false,"reason":"missing_backdrop"}
		if not point.ok:
			_fx_layer.record_missing("source_attachment:"+str(context.get("form","")),str(point.reason))
			return
		origin=point.position
	_sync_effect_positions()
	_fx_layer.present_action(context,str(context.get("form","")),origin,targets,_effect_battle_id())

func _on_effect_actor_finished(actor_id: String) -> void:
	if not _effect_actions.has(actor_id): return
	var action: Dictionary = _effect_actions[actor_id]
	_effect_actions.erase(actor_id)
	if is_instance_valid(_fx_layer) and _fx_layer.has_method("finish_action"): _fx_layer.finish_action(action.context,action.battle_id)

# 实拍门禁读取真实billboard投影和可见卡片交集；不隐藏HP/反馈来消除报告。
func presentation_obstructions() -> Array[Dictionary]:
	var overlaps: Array[Dictionary] = []
	if not is_instance_valid(_world_backdrop): return overlaps
	for actor_id in _world_backdrop.actor_entries:
		var body_bounds: Rect2 = _world_backdrop.actor_screen_bounds(str(actor_id))
		for card_id in _actors:
			var card: Control = _actors[card_id].card
			if not is_instance_valid(card) or not card.visible: continue
			var card_bounds := Rect2(card.position,card.size)
			if body_bounds.intersects(card_bounds): overlaps.append({"actor_id":actor_id,"card_actor_id":card_id,"body":body_bounds,"card":card_bounds})
	return overlaps
