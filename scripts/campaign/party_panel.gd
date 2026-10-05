# 正式探索的六选三整备；所有实际资源修改只委托Campaign原子保存。
class_name ChapterPartyPanel
extends CanvasLayer
signal closed
const Stature = preload("res://scripts/characters/character_stature.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Factory = preload("res://scripts/rpg/actor_factory.gd")
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const CLASSES: Array[String] = ["swordsman", "ranger", "guard", "mage", "healer", "controller"]
var session: RefCounted
var campaign: RefCounted
var last_error := ""
var draft_party: Array[String] = []
var detail_actor_id := "p_swordsman"
var preview_branch_id := ""
var busy := false
var _catalog := Catalog.new()
var _root: Control
var _canvas: Control
var _hud: Dictionary = {}
var _rows: Dictionary = {}
var _skills: Array[Label] = []
var _branches: Dictionary = {}
var _equipment: Dictionary = {}
var _items: Dictionary = {}
var _generation := 0
var _closing := false

func _init() -> void:
	layer = 20
	_catalog.load_all()
func open(value: RefCounted) -> void:
	session = value
	campaign = session.campaign if session != null else null
	if campaign == null: last_error = "没有正式主线会话"
	else:
		var state: Dictionary = campaign.safe_snapshot()
		draft_party.assign(state.get("party", []))
		if not draft_party.is_empty(): detail_actor_id = draft_party[0]
		preview_branch_id = _detail().get("branch", {}).get("id", "")
	var first_open := _root == null
	if first_open: _build()
	_render()
	if first_open and _rows.has(detail_actor_id): _rows[detail_actor_id].detail.grab_focus()
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.07, 0.072, 0.86)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_canvas = Control.new()
	_canvas.size = Vector2(1920, 1080)
	_root.add_child(_canvas)
	Kit.panel(_canvas, Rect2(42, 36, 1836, 1008))
	Kit.label(_canvas, "夜巡整备", Rect2(78, 55, 1250, 65), 40)
	_hud.close = Kit.button(_canvas, "返回探索", Rect2(1590, 59, 250, 64), close_panel)
	_hud.count = Kit.muted(Kit.label(_canvas, "", Rect2(78, 132, 760, 45), 24))
	for index in CLASSES.size():
		var class_id := CLASSES[index]
		var actor_id := "p_" + class_id
		var y := 205 + index * 87
		_rows[actor_id] = {"detail": Kit.button(_canvas, "", Rect2(78, y, 278, 70), select_actor.bind(actor_id)), "toggle": Kit.button(_canvas, "", Rect2(372, y, 186, 70), toggle_member.bind(actor_id))}
	_hud.apply = Kit.button(_canvas, "保存三人编队", Rect2(78, 740, 480, 70), apply_party, true)
	_hud.rest = Kit.button(_canvas, "休息 · 全员恢复", Rect2(78, 825, 480, 62), rest_party)
	_hud.portrait = TextureRect.new()
	_hud.portrait.position = Vector2(580, 202)
	_hud.portrait.size = Vector2(286, 490)
	_hud.portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hud.portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hud.portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_hud.portrait)
	_hud.form = Kit.button(_canvas, "", Rect2(580, 708, 286, 66), toggle_form)
	Kit.panel(_canvas, Rect2(900, 184, 940, 590))
	_hud.title = Kit.label(_canvas, "", Rect2(922, 198, 890, 43), 31)
	_hud.stats = Kit.label(_canvas, "", Rect2(922, 249, 890, 73), 23)
	for index in 4: _skills.append(Kit.label(_canvas, "", Rect2(922, 332 + index * 40, 890, 38), 21))
	for index in 3:
		var branch: String = ["", "economy", "power"][index]
		_branches[branch] = Kit.button(_canvas, "", Rect2(922 + index * 210, 507, 196, 53), preview_branch.bind(branch))
	_hud.branch_apply = Kit.button(_canvas, "应用分支", Rect2(1560, 507, 252, 53), apply_branch)
	_hud.branch_preview = Kit.scroll_text(_canvas, Rect2(922, 571, 890, 110), 22)
	for index in 3:
		var slot: String = ["weapon", "armor", "accessory"][index]
		_equipment[slot] = Kit.button(_canvas, "", Rect2(922 + index * 300, 702, 286, 52), toggle_equipment.bind(slot))
	Kit.muted(Kit.label(_canvas, "随身道具  ·  使用于当前查看的队员", Rect2(580, 807, 1220, 40), 24))
	var item_ids: Array = _catalog.get_ids("items")
	for index in item_ids.size():
		var id: String = item_ids[index]
		_items[id] = Kit.button(_canvas, "", Rect2(580 + index % 2 * 620, 858 + index / 2 * 64, 598, 56), use_item.bind(id))
	_hud.error = Kit.muted(Kit.label(_canvas, "", Rect2(78, 983, 1740, 47), 22))
	_hud.error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if is_inside_tree():
		get_viewport().size_changed.connect(_resize)
		_resize()
func _ready() -> void:
	if _root != null:
		if not get_viewport().size_changed.is_connected(_resize): get_viewport().size_changed.connect(_resize)
		_resize()
func _resize() -> void:
	var available := get_viewport().get_visible_rect().size
	var factor := minf(available.x / 1920.0, available.y / 1080.0)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (available - Vector2(1920, 1080) * factor) / 2.0
func _detail() -> Dictionary:
	return campaign.safe_snapshot().get("roster", {}).get(detail_actor_id, {}) if campaign != null else {}
func select_actor(actor_id: String) -> void:
	if busy or campaign == null or not campaign.safe_snapshot().roster.has(actor_id): return
	detail_actor_id = actor_id
	preview_branch_id = _detail().branch.get("id", "")
	_render()
func toggle_member(actor_id: String) -> void:
	if busy or campaign == null or not campaign.can_prepare() or not campaign.safe_snapshot().roster.has(actor_id): return
	if draft_party.has(actor_id): draft_party.erase(actor_id)
	elif draft_party.size() < 3: draft_party.append(actor_id)
	_render()
func apply_party() -> Dictionary:
	if busy: return _failure("人物资源正在加载")
	if draft_party.size() != 3 or draft_party[0] == draft_party[1] or draft_party[0] == draft_party[2] or draft_party[1] == draft_party[2]: return _failure("请选择三名不同队员")
	var result: Dictionary = campaign.set_party(draft_party)
	last_error = result.get("error", "")
	if result.ok: await _prepare_selected()
	_render()
	return result
func toggle_form() -> Dictionary:
	if busy or _detail().get("identity_id") != "homura": return _failure("仅焰华有双形态")
	var target := "sword" if _detail().form_id == "mage" else "mage"
	var result: Dictionary = campaign.set_form(detail_actor_id, target)
	last_error = result.get("error", "")
	if result.ok: await _prepare_selected()
	_render()
	return result
func preview_branch(branch: String) -> void:
	if busy: return
	preview_branch_id = "duration" if branch == "economy" and _detail().get("class_id") == "ranger" else branch
	_render()
func apply_branch() -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	return _show_response(campaign.set_branch(detail_actor_id, preview_branch_id))
func toggle_equipment(slot: String) -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	var actor := _detail()
	return _show_response(campaign.equip(detail_actor_id, slot, Factory.STANDARD[slot] if actor.equipment.get(slot, "").is_empty() else ""))
func use_item(item_id: String) -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	return _show_response(campaign.use_item_outside(item_id, detail_actor_id))
func rest_party() -> Dictionary:
	if busy or campaign == null: return _failure("整备操作暂不可用，请等待人物加载")
	return _show_response(campaign.rest())
func _show_response(result: Dictionary) -> Dictionary:
	last_error = result.get("error", "")
	_render()
	return result
func _failure(message: String) -> Dictionary:
	return _show_response({"ok": false, "error": message})
func _prepare_selected() -> bool:
	busy = true
	_generation += 1
	var generation := _generation
	_render()
	var result: Dictionary = await session.prepare_assets()
	if generation != _generation or not is_instance_valid(_root): return false
	busy = false
	last_error = result.get("error", "")
	return result.get("ok", false)
func close_panel() -> void:
	if busy or _closing: return
	_closing = true
	# 关闭前重新确认当前已保存三人对应的资源，加载失败留在整备可重试。
	if session != null and not await _prepare_selected():
		_closing = false
		_render()
		return
	closed.emit()
	queue_free()
func _render() -> void:
	if _root == null: return
	var actor := _detail()
	if actor.is_empty():
		_hud.error.text = last_error
		return
	var state: Dictionary = campaign.safe_snapshot()
	var editable: bool = not busy and campaign.can_prepare()
	_hud.count.text = "出战  %d / 3   ·   六位同伴，选择三人同行" % draft_party.size()
	_hud.close.disabled = busy
	_hud.apply.disabled = not editable or draft_party.size() != 3
	_hud.rest.disabled = not editable
	for id in _rows:
		var row: Dictionary = _rows[id]
		var entry: Dictionary = state.roster[id]
		row.detail.text = Presenter.presentation_name(entry, _catalog.get_definition("classes", entry.class_id)) + " · " + _catalog.get_definition("classes", entry.get("active_class_id", entry.class_id)).name
		row.detail.disabled = busy
		Kit.set_selected(row.detail, id == detail_actor_id)
		row.toggle.text = "✓ 出战中" if draft_party.has(id) else "+ 加入出战"
		Kit.set_selected(row.toggle, draft_party.has(id))
		row.toggle.disabled = not editable or (not draft_party.has(id) and draft_party.size() >= 3)
	_hud.title.text = "%s · L%d · %s · %dcm" % [Presenter.presentation_name(actor, _catalog.get_definition("classes", actor.class_id)), actor.level, _catalog.get_definition("classes", actor.get("active_class_id", actor.class_id)).name, roundi(Stature.height_cm(actor.identity_id))]
	_hud.stats.text = "HP %d/%d　MP %d/%d\nATK %d　MATK %d　DEF %d　MDEF %d　SPD %d" % [actor.hp, actor.stats.hp, actor.mp, actor.stats.mp, actor.stats.atk, actor.stats.matk, actor.stats.def, actor.stats.mdef, actor.stats.spd]
	var face := Portraits.from_definition(Portraits.load_idle_definition(actor.identity_id, actor.form_id), actor.identity_id, "portrait")
	_hud.portrait.texture = face.get("texture")
	_hud.form.visible = actor.identity_id == "homura"
	var forms: Array = actor.get("unlocked_forms", [actor.form_id])
	var mage_unlocked: bool = forms.has("mage")
	_hud.form.disabled = not editable or not mage_unlocked
	_hud.form.text = ("法师 → 切换剑士" if actor.form_id == "mage" else "剑士 → 切换法师") if mage_unlocked else "剑士 · 法师未解锁"
	_hud.form.tooltip_text = "第一夜战斗胜利后解锁法师；战斗中在焰华自己的行动机会自由切换两套现有四技能，共用HP/MP、CD、状态与装备"
	for index in 4:
		var skill: Dictionary = _catalog.skill_for(actor, actor.skill_ids[index])
		var line := "%s%s　MP%d · CD%d　%s" % ["L%d锁定 · " % skill.unlock_level if actor.level < skill.unlock_level else "", skill.name, skill.mp_cost, skill.cooldown, Presenter.ability_summary(skill, {}, _catalog)]
		_skills[index].text = line
		_skills[index].tooltip_text = line
	for id in _branches:
		var actual: String = "duration" if id == "economy" and actor.class_id == "ranger" else id
		_branches[id].text = ("✓ " if actual == preview_branch_id else "") + {"": "无分支", "economy": "节约", "duration": "持续", "power": "强度"}[actual]
		_branches[id].disabled = busy
		Kit.set_selected(_branches[id], actual == preview_branch_id)
	_hud.branch_apply.disabled = not editable or (actor.level < 6 and not preview_branch_id.is_empty())
	_hud.branch_preview.text = Presenter.branch_preview(actor, preview_branch_id, _catalog)
	for slot in _equipment:
		var equipment_id: String = actor.equipment.get(slot, "")
		_equipment[slot].text = ("装备：" + _catalog.get_definition("equipment", Factory.STANDARD[slot]).name) if equipment_id.is_empty() else "卸下：" + _catalog.get_definition("equipment", equipment_id).name
		_equipment[slot].disabled = not editable
	for id in _items:
		_items[id].text = "%s ×%d" % [_catalog.get_definition("items", id).name, state.inventory.get(id, 0)]
		_items[id].disabled = busy or not campaign.can_use_outside_items() or state.inventory.get(id, 0) < 1
	_hud.error.text = "正在加载当前三人高清资源…" if busy else (last_error if not last_error.is_empty() else ("焰华双职业共享HP、MP、CD、状态、装备与行动槽；切换不回复、不额外行动" if state.roster.p_mage.get("unlocked_forms", []).has("mage") else "焰华开局为剑士；第一夜战斗胜利后解锁法师，之后战内可自由切换"))
func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
func _exit_tree() -> void:
	_generation += 1
