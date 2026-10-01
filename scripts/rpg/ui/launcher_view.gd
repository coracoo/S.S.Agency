# 准备/休息/继续只调用Campaign与Router；不会在载入失败时自动新开局。
class_name RpgLauncherView
extends Control
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Campaign = preload("res://scripts/rpg/campaign.gd")
const Router = preload("res://scripts/rpg/encounter_router.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")

# 编队草稿只在确认时提交；所有装备和分支变更仍由Campaign校验并保存。
@export var available_class_ids: Array[String] = ["guard", "swordsman", "ranger", "mage", "healer", "controller"]
var selected_class_ids: Array[String] = ["guard", "swordsman", "healer"]
var router: RefCounted
var campaign: RefCounted
var last_error := ""
var last_response: Dictionary = {}
var _catalog := Catalog.new()
var _config: Dictionary
var _canvas: Control
var _hud: Dictionary = {}
var _cards: Array[Dictionary] = []
var _pending_item := ""
var _built := false
var _roster_panel: Panel
var _roster_widgets: Dictionary = {}
var _branch_buttons: Dictionary = {}
var _equipment_buttons: Dictionary = {}
var _draft_party: Array[String] = []
var _detail_class := "guard"
var _preview_branch := ""
var _skill_labels: Array[Label] = []

func _init() -> void:
	_catalog.load_all()
	_config = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))

func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_resize_canvas)
	_resize_canvas()
	open({"router": Router.session} if Router.session != null else {})

func open(session: Dictionary) -> void:
	router = session.get("router")
	if router == null: router = Router.new(null, _catalog)
	campaign = router.campaign
	_sync_party_selection()
	last_error = ""
	if _built: _render()

func new_game(independent_boss: bool = false) -> Dictionary:
	if independent_boss:
		var regular_router: RefCounted = router.get_meta("regular_router") if router.has_meta("regular_router") else router
		campaign = Campaign.new(_catalog, null, "user://rpg_v1/slot_boss_test.json")
		router = Router.new(campaign, _catalog)
		router.set_meta("rpg_independent_boss", true)
		router.set_meta("regular_router", regular_router)
	elif router.get_meta("rpg_independent_boss", false):
		router = router.get_meta("regular_router") if router.has_meta("regular_router") else Router.new(null, _catalog)
		campaign = router.campaign
	var result: Dictionary = campaign.new_run(selected_class_ids, 5)
	last_response = result
	last_error = result.get("error", "")
	if result.ok:
		Router.activate(router)
		if independent_boss: return start_encounter("slice_boss")
	if _built: _render()
	return result

func continue_game() -> Dictionary:
	var result: Dictionary = router.load_safe_run()
	last_response = result
	last_error = result.get("error", "")
	if result.ok:
		_sync_party_selection()
		Router.activate(router)
		if is_inside_tree() and result.next_scene != "res://scenes/rpg/launcher.tscn": get_tree().change_scene_to_file(result.next_scene)
	if _built: _render()
	return result

func start_encounter(encounter_id: String = "") -> Dictionary:
	var current: Dictionary = campaign.snapshot()
	if current.is_empty(): return _error("请明确新开局，或继续已有安全档")
	if not current.world.is_empty(): return _error("请返回原探索，从场景中的线索进入战斗")
	if encounter_id.is_empty(): encounter_id = current.next_encounter_id
	if encounter_id.is_empty(): return _error("连战已完成，可返回标题或明确开始新局")
	var result: Dictionary = campaign.begin_battle(encounter_id, current.world)
	last_error = result.get("error", "")
	if result.ok:
		var adopted: Dictionary = router.adopt_battle(result)
		if not adopted.ok: return _error(adopted.error)
		Router.activate(router)
		if is_inside_tree(): get_tree().change_scene_to_file("res://scenes/rpg/battle.tscn")
	if _built: _render()
	return result

func rest_party() -> Dictionary:
	var result: Dictionary = campaign.rest()
	last_error = result.get("error", "")
	if _built: _render()
	return result

func use_item(item_id: String, actor_id: String) -> Dictionary:
	var result: Dictionary = campaign.use_item_outside(item_id, actor_id)
	last_error = result.get("error", "")
	if result.ok: _pending_item = ""
	if _built: _render()
	return result

func set_party(actor_ids: Array[String]) -> Dictionary:
	var result: Dictionary = campaign.set_party(actor_ids)
	if result.ok: _sync_party_selection()
	last_error = result.get("error", "")
	if _built: _render()
	return result

func set_branch(actor_id: String, branch_id: String) -> Dictionary:
	var result: Dictionary = campaign.set_branch(actor_id, branch_id)
	last_error = result.get("error", "")
	if _built: _render()
	return result

func equip(actor_id: String, slot: String, equipment_id: String) -> Dictionary:
	var result: Dictionary = campaign.equip(actor_id, slot, equipment_id)
	last_error = result.get("error", "")
	if _built: _render()
	return result

func _build() -> void:
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	Kit.backdrop(_canvas, _config)
	Kit.panel(_canvas, Rect2(56, 50, 1808, 150))
	Kit.label(_canvas, "逢魔退治帖", Rect2(88, 64, 700, 62), 48)
	_hud.subtitle = Kit.label(_canvas, "回合制 RPG　／　战前准备", Rect2(88, 135, 1450, 50), 28)
	Kit.button(_canvas, "返回标题", Rect2(1630, 88, 204, 70), _return_title)
	Kit.panel(_canvas, Rect2(60, 225, 1260, 720), true)
	Kit.label(_canvas, "出战名册", Rect2(95, 248, 650, 56), 36, true)
	_hud.roster_notice = Kit.button(_canvas, "六选三 / 成长装备", Rect2(625, 264, 382, 52), open_roster)
	_hud.summary = Kit.label(_canvas, "", Rect2(95, 310, 1180, 65), 26, true)
	for index in range(3):
		var x := 100 + index * 395
		var card := Kit.panel(_canvas, Rect2(x, 393, 370, 485))
		var title := Kit.label(card, "", Rect2(22, 18, 326, 48), 33)
		var badge := Kit.image(card, _config.class_art[selected_class_ids[index]].badge, Rect2(276, 16, 65, 65))
		var sprite := Kit.actor_sprite(card, _config.class_art[selected_class_ids[index]].actor, 230, false)
		sprite.position = Vector2(185, 310)
		var stats := Kit.label(card, "", Rect2(22, 318, 326, 109), 25)
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var button := Kit.button(card, "道具目标", Rect2(22, 444, 326, 31), _item_target.bind(index))
		sprite.set_meta("art_id", _config.class_art[selected_class_ids[index]].actor)
		_cards.append({"card": card, "class_id": selected_class_ids[index], "title": title, "badge": badge, "sprite": sprite, "stats": stats, "button": button})
	Kit.label(_canvas, _config.art_note, Rect2(64, 946, 1780, 44), 22)
	Kit.panel(_canvas, Rect2(1350, 225, 514, 720))
	_hud.continue = Kit.button(_canvas, "继续安全档", Rect2(1380, 256, 454, 68), continue_game, true)
	_hud.new = Kit.button(_canvas, "新开连战 · L5自选三人", Rect2(1380, 338, 454, 68), _request_new)
	_hud.next = Kit.button(_canvas, "进入下一场", Rect2(1380, 420, 454, 68), start_encounter)
	_hud.rest = Kit.button(_canvas, "休息 · 全员恢复", Rect2(1380, 502, 454, 68), rest_party)
	_hud.explore = Kit.button(_canvas, "进入原参道探索", Rect2(1380, 584, 454, 68), _explore)
	Kit.button(_canvas, "独立 Boss 测试 · 满状态", Rect2(1380, 666, 454, 68), _request_boss)
	_hud.inventory = Kit.label(_canvas, "", Rect2(1380, 757, 454, 162), 25)
	_hud.inventory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.error = Kit.label(_canvas, "", Rect2(64, 996, 1780, 78), 27)
	_hud.error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.error.add_theme_color_override("font_outline_color", Kit.color("ink_900"))
	_hud.error.add_theme_constant_override("outline_size", 5)
	var items := Kit.panel(_canvas, Rect2(100, 610, 1170, 276))
	Kit.label(items, "战外道具 · 点击道具，再选队员（安全探索可用）", Rect2(22, 12, 1120, 44), 27)
	for index in range(_catalog.get_ids("items").size()):
		var id: String = _catalog.get_ids("items")[index]
		_hud["outside_" + id] = Kit.button(items, _catalog.get_definition("items", id).name, Rect2(22 + (index % 2) * 563, 74 + (index / 2) * 88, 542, 72), _choose_item.bind(id))
	_hud.item_panel = items
	_hud.item_panel.visible = false
	_hud.items = Kit.button(_canvas, "战外道具", Rect2(1030, 260, 242, 60), _toggle_items)
	var confirm := ConfirmationDialog.new()
	confirm.title = "明确开始新局"
	confirm.dialog_text = "将替换当前RPG连战安全档。旧卡牌/探索存档不受影响。"
	confirm.ok_button_text = "开始新局"
	confirm.cancel_button_text = "取消"
	confirm.confirmed.connect(new_game)
	add_child(confirm)
	_hud.new_confirm = confirm
	var boss_confirm := ConfirmationDialog.new()
	boss_confirm.title = "独立测试"
	boss_confirm.dialog_text = "独立Boss测试使用单独测试槽、满状态与初始库存，不携带连战奖励。"
	boss_confirm.ok_button_text = "开始独立测试"
	boss_confirm.cancel_button_text = "取消"
	boss_confirm.confirmed.connect(new_game.bind(true))
	add_child(boss_confirm)
	_hud.boss_confirm = boss_confirm
	_build_roster()
	_built = true

func _resize_canvas() -> void:
	var available := get_viewport_rect().size
	var factor := minf(available.x / 1920, available.y / 1080)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (available - Vector2(1920, 1080) * factor) / 2

func _render() -> void:
	if not _built or campaign == null: return
	var state: Dictionary = campaign.snapshot()
	var ready := not state.is_empty()
	var phase_label: String = "连战已完成" if ready and state.next_encounter_id.is_empty() else {"preparation": "准备点", "rest": "休息点", "exploration": "连战途中", "battle": "待战安全档", "defeat": "败北可重试"}.get(state.get("phase", ""), state.get("phase", ""))
	_hud.summary.text = "六职业选三人 · L5新局预览　／　两场普通战 → 休息 → 棺守" if not ready else "共享等级 L%d　·　经验 %d　·　%s" % [state.level, state.xp, phase_label]
	_hud.subtitle.text = "回合制 RPG　／　独立Boss测试" if router.get_meta("rpg_independent_boss", false) else "回合制 RPG　／　连战准备"
	_hud.error.text = last_error
	if not _pending_item.is_empty(): _hud.error.text = "选择%s的目标队员%s" % [_catalog.get_definition("items", _pending_item).name, " · " + last_error if not last_error.is_empty() else ""]
	_hud.next.disabled = not campaign.can_use_outside_items() or state.get("next_encounter_id", "").is_empty() or not state.get("world", {}).is_empty()
	_hud.next.text = "连战已完成" if ready and state.next_encounter_id.is_empty() else "进入：" + _encounter_label(state.get("next_encounter_id", "slice_1"))
	_hud.rest.disabled = not campaign.can_prepare()
	_hud.items.disabled = not campaign.can_use_outside_items()
	if _hud.items.disabled:
		_pending_item = ""
		_hud.item_panel.hide()
	_hud.explore.disabled = not campaign.can_use_outside_items() or (state.get("world", {}).is_empty() and state.get("phase") != "preparation")
	_hud.explore.text = "返回原探索 · 已保存" if not state.get("world", {}).is_empty() else "进入原参道探索"
	if not state.get("world", {}).is_empty(): _hud.next.text = "下一战请从原探索进入"
	var ids: Array = state.party if ready else selected_class_ids.map(func(id): return "p_" + id)
	for index in range(3):
		var actor: Dictionary = state.roster[ids[index]] if ready else Factory.new(_catalog).create(selected_class_ids[index], ids[index], 5, {"weapon": "standard_weapon", "armor": "standard_armor", "accessory": "standard_accessory"})
		var class_id: String = actor.get("class_id", selected_class_ids[index])
		_update_card_art(index, class_id)
		_cards[index].title.text = "%d · %s" % [index + 1, _catalog.get_definition("classes", class_id).name]
		_cards[index].stats.text = "HP %d/%d　MP %d/%d\nATK %d　MATK %d\nDEF %d　MDEF %d　SPD %d" % [actor.hp, actor.stats.hp, actor.mp, actor.stats.mp, actor.stats.atk, actor.stats.matk, actor.stats.def, actor.stats.mdef, actor.stats.spd]
		_cards[index].button.disabled = _pending_item.is_empty() or _hud.items.disabled
	var inventory: Dictionary = state.inventory if ready else {"healing_potion": 3, "mana_potion": 1, "revival_potion": 1, "cleansing_powder": 1}
	var lines: Array[String] = []
	for id in _catalog.get_ids("items"):
		var text := "%s ×%d" % [_catalog.get_definition("items", id).name, inventory.get(id, 0)]
		lines.append(text)
		_hud["outside_" + id].text = text
	_hud.inventory.text = "队伍库存\n" + "　".join(lines)
	_render_roster()

func _request_new() -> void:
	_hud.new_confirm.popup_centered(Vector2i(600, 220))

func _request_boss() -> void:
	_hud.boss_confirm.popup_centered(Vector2i(640, 220))

func _choose_item(id: String) -> void:
	if not campaign.can_use_outside_items(): return
	_pending_item = id
	_hud.item_panel.visible = false
	_render()

func _item_target(index: int) -> void:
	if _pending_item.is_empty(): return
	use_item(_pending_item, campaign.snapshot().party[index])

func _toggle_items() -> void:
	if not campaign.can_use_outside_items(): return
	_hud.item_panel.visible = not _hud.item_panel.visible

func _explore() -> void:
	if not campaign.can_use_outside_items(): return
	var state: Dictionary = campaign.snapshot()
	var next_scene := "res://scenes/v3/stage.tscn"
	if not state.world.is_empty():
		var resumed: Dictionary = router.resume_exploration()
		if not resumed.ok:
			_error(resumed.error)
			return
		next_scene = resumed.next_scene
	elif state.phase != "preparation": return
	Router.activate(router)
	get_tree().change_scene_to_file(next_scene)

func _return_title() -> void:
	Router.clear_session()
	get_tree().change_scene_to_file("res://scenes/v3/title.tscn")

func _error(message: String) -> Dictionary:
	last_error = message
	if _built: _render()
	return {"ok": false, "error": message}

func _encounter_label(encounter_id: String) -> String:
	var names: Array[String] = []
	for id in _catalog.get_definition("encounters", encounter_id).get("enemy_ids", []): names.append(_config.get("enemy_labels", {}).get(id, _catalog.get_definition("enemies", id).get("name", id)))
	return "＋".join(names) if not names.is_empty() else "下一场"

func _update_card_art(index: int, class_id: String) -> void:
	var card: Dictionary = _cards[index]
	if card.class_id == class_id: return
	card.sprite.free()
	card.badge.free()
	var art: Dictionary = _config.class_art[class_id]
	card.sprite = Kit.actor_sprite(card.card, art.actor, 230, false)
	card.sprite.position = Vector2(185, 310)
	card.sprite.set_meta("art_id", art.actor)
	card.badge = Kit.image(card.card, art.badge, Rect2(276, 16, 65, 65))
	card.class_id = class_id

func _build_roster() -> void:
	_roster_panel = Kit.panel(_canvas, Rect2(75, 215, 1770, 745), true)
	_roster_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	Kit.label(_roster_panel, "出战编队 · 六选三", Rect2(30, 18, 850, 52), 35, true)
	Kit.button(_roster_panel, "关闭", Rect2(1580, 18, 156, 52), func(): _roster_panel.hide())
	_hud.party_count = Kit.label(_roster_panel, "", Rect2(30, 78, 575, 42), 25, true)
	for index in range(available_class_ids.size()):
		var id := available_class_ids[index]
		var y := 135 + index * 75
		var details := Kit.button(_roster_panel, _catalog.get_definition("classes", id).name + " · 查看", Rect2(30, y, 315, 61), select_roster_actor.bind(id))
		var toggle := Kit.button(_roster_panel, "", Rect2(361, y, 213, 61), toggle_party_member.bind(id))
		_roster_widgets[id] = {"details": details, "toggle": toggle}
	_hud.party_apply = Kit.button(_roster_panel, "确认三人编队", Rect2(30, 608, 544, 62), apply_party_selection, true)
	Kit.label(_roster_panel, "选择仅为草稿，确认后保存；战中不可换人", Rect2(30, 682, 565, 42), 22, true)
	Kit.panel(_roster_panel, Rect2(608, 85, 1128, 634))
	_hud.detail_title = Kit.label(_roster_panel, "", Rect2(632, 92, 1076, 45), 28)
	_hud.detail_stats = Kit.label(_roster_panel, "", Rect2(632, 139, 1076, 35), 23)
	for index in range(4):
		var label := Kit.label(_roster_panel, "", Rect2(632, 184 + index * 39, 1076, 37), 22)
		_skill_labels.append(label)
	for index in range(3):
		var id: String = ["", "economy", "power"][index]
		_branch_buttons[id] = Kit.button(_roster_panel, ["无分支", "节约 / 持续", "强度"][index], Rect2(632 + index * 267, 348, 250, 50), preview_branch.bind(id))
	_hud.branch_apply = Kit.button(_roster_panel, "应用分支", Rect2(1438, 348, 267, 50), confirm_branch, true)
	_hud.branch_preview = Kit.scroll_text(_roster_panel, Rect2(632, 410, 1076, 120), 23)
	Kit.label(_roster_panel, "装备 · 三槽替换（升上限不回复；降上限钳制）", Rect2(632, 533, 1076, 36), 24)
	for index in range(3):
		var slot: String = ["weapon", "armor", "accessory"][index]
		_equipment_buttons[slot] = Kit.button(_roster_panel, "", Rect2(632 + index * 360, 582, 346, 58), _toggle_equipment.bind(slot))
	_hud.roster_error = Kit.label(_roster_panel, "", Rect2(632, 652, 1076, 55), 23)
	_hud.roster_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_roster_panel.hide()

func open_roster() -> void:
	var state: Dictionary = campaign.snapshot()
	_draft_party.clear()
	if state.is_empty(): _draft_party.assign(selected_class_ids)
	else:
		for id in state.party: _draft_party.append(state.roster[id].class_id)
	_detail_class = _draft_party[0]
	_preview_branch = _detail_actor().branch.get("id", "")
	_pending_item = ""
	_hud.item_panel.hide()
	_roster_panel.show()
	_render_roster()

func toggle_party_member(class_id: String) -> void:
	if not available_class_ids.has(class_id) or not _can_prepare(): return
	if _draft_party.has(class_id): _draft_party.erase(class_id)
	elif _draft_party.size() < 3: _draft_party.append(class_id)
	_render_roster()

func apply_party_selection() -> Dictionary:
	if not _can_prepare() or _draft_party.size() != 3: return _error("请选择三名不同队员；仅准备/休息点可调整")
	if not campaign.snapshot().is_empty():
		var ids: Array[String] = []
		for id in _draft_party: ids.append("p_" + id)
		var result := set_party(ids)
		if not result.ok: return result
	selected_class_ids.assign(_draft_party)
	last_error = ""
	_render()
	return {"ok": true}

func select_roster_actor(class_id: String) -> void:
	if not available_class_ids.has(class_id): return
	_detail_class = class_id
	_preview_branch = _detail_actor().branch.get("id", "")
	_render_roster()

func preview_branch(branch_id: String) -> void:
	_preview_branch = "duration" if branch_id == "economy" and _detail_class == "ranger" else branch_id
	_render_roster()

func confirm_branch() -> Dictionary:
	return set_branch("p_" + _detail_class, _preview_branch)

func _toggle_equipment(slot: String) -> void:
	var current: Dictionary = _detail_actor()
	equip(current.actor_id, slot, Factory.STANDARD[slot] if current.equipment.get(slot, "").is_empty() else "")

func _detail_actor() -> Dictionary:
	var state: Dictionary = campaign.snapshot()
	return state.roster["p_" + _detail_class] if not state.is_empty() else Factory.new(_catalog).create(_detail_class, "p_" + _detail_class, 5, Factory.STANDARD)

func _can_prepare() -> bool:
	var state: Dictionary = campaign.snapshot()
	return state.is_empty() or campaign.can_prepare()

func _render_roster() -> void:
	if _roster_panel == null or not _roster_panel.visible: return
	var actor := _detail_actor()
	var ready: bool = not campaign.snapshot().is_empty()
	var editable := _can_prepare()
	_hud.party_count.text = "已选 %d / 3　·　可查看全部六名职业槽位" % _draft_party.size()
	_hud.party_apply.disabled = not editable or _draft_party.size() != 3
	for id in _roster_widgets:
		var picked := _draft_party.has(id)
		_roster_widgets[id].toggle.text = "✓ 出战 · 移除" if picked else "加入编队"
		_roster_widgets[id].toggle.disabled = not editable or (not picked and _draft_party.size() >= 3)
		_roster_widgets[id].details.text = ("▶ " if id == _detail_class else "") + _catalog.get_definition("classes", id).name + " · 查看"
	_hud.detail_title.text = "%s　·　共享等级 L%d　·　分支%s" % [_catalog.get_definition("classes", actor.class_id).name, actor.level, {"": "未选择", "economy": "节约", "duration": "持续", "power": "强度"}.get(actor.branch.get("id", ""), "")]
	_hud.detail_stats.text = "HP %d/%d　MP %d/%d　ATK %d　MATK %d　DEF %d　MDEF %d　SPD %d" % [actor.hp, actor.stats.hp, actor.mp, actor.stats.mp, actor.stats.atk, actor.stats.matk, actor.stats.def, actor.stats.mdef, actor.stats.spd]
	for index in range(4):
		var skill: Dictionary = _catalog.skill_for(actor, actor.skill_ids[index])
		var line := "%s%s　MP %d · CD%d　%s" % ["🔒 L%d " % skill.unlock_level if actor.level < skill.unlock_level else "", skill.name, skill.mp_cost, skill.cooldown, Presenter.ability_summary(skill, {}, _catalog)]
		_skill_labels[index].text = line
		_skill_labels[index].tooltip_text = line
	for id in _branch_buttons:
		var actual: String = "duration" if id == "economy" and actor.class_id == "ranger" else id
		_branch_buttons[id].text = ("✓ " if actual == _preview_branch else "") + {"": "无分支", "economy": "节约", "duration": "持续", "power": "强度"}[actual]
	_hud.branch_apply.disabled = not ready or not editable or (actor.level < 6 and not _preview_branch.is_empty())
	_hud.branch_preview.text = Presenter.branch_preview(actor, _preview_branch, _catalog)
	for slot in _equipment_buttons:
		var item_id: String = actor.equipment.get(slot, "")
		_equipment_buttons[slot].text = ("装备：" + _catalog.get_definition("equipment", Factory.STANDARD[slot]).name) if item_id.is_empty() else "卸下：" + _catalog.get_definition("equipment", item_id).name
		_equipment_buttons[slot].disabled = not ready or not editable
	_hud.roster_error.text = last_error if not last_error.is_empty() else ("战斗已锁定，返回准备/休息点后调整" if not editable else ("L6解锁二选一；L9强化同一分支；休息点免费改选" if ready else "先确认编队，再明确新开局；新局不会继承分支"))

func _sync_party_selection() -> void:
	var state: Dictionary = campaign.snapshot()
	if state.is_empty(): return
	selected_class_ids.clear()
	for id in state.party: selected_class_ids.append(state.roster[id].class_id)
