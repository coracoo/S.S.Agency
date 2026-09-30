extends Control
## 战前构筑场景（GDD §5.2 牌组规则 + §9「补充构筑界面」）。
## 布局：左侧收藏（全部卡库，步进增删），右侧主战/支援选择 + 16 张槽位 +
## 合法性校验 / 费用分布 / 一键恢复预组；「出战」进入 NextBattleV4 登记的战斗。
## 规则唯一来源是 BattleRulesV4.validate_deck，本场景只做表现与编辑。

const UIThemeScript = preload("res://scripts/ui/theme.gd")
const SfxScript = preload("res://scripts/ui/sfx.gd")
const InkTransitionScript = preload("res://scripts/ui/ink_transition.gd")

## 合法预组（GDD §5.2「入门保障」）：凛音系 6（3 种×2）+ 跨角色卡 10 = 16，
## 对真实卡库满足「≥6 主战卡 / 支援≤6 / 同卡≤2」
const PRESET_DECK: Array[String] = [
	"slash", "slash", "guard", "guard", "chase_slash", "chase_slash",
	"ignite", "ignite", "bell", "bell", "seal", "seal", "seal2", "seal2",
	"amulet", "amulet",
]
const DEFAULT_MAIN := "rinne"
const DEFAULT_SUPPORT := "mint"

const TYPE_LABEL := {"attack": "攻", "slot": "景", "seal": "结", "skill": "术"}

var _theme = null
var _library: Dictionary = {}
var _roster: Array = [] # [{id, name}]
var _deck_ids: Array = []
var _main_id := DEFAULT_MAIN
var _support_id := DEFAULT_SUPPORT
var _artifact_id := "" # GDD §7：主战最多 1 件器物；空=不带
var _artifacts: Array = [] # data/artifacts.json 全集

var _list_box: VBoxContainer = null
var _slot_grid: GridContainer = null
var _valid_label: Label = null
var _count_label: Label = null
var _curve_label: Label = null
var _go_btn: Button = null
var _main_opt: OptionButton = null
var _support_opt: OptionButton = null
var _artifact_opt: OptionButton = null
var _artifact_desc_label: Label = null

func _ready() -> void:
	_theme = UIThemeScript.load_theme()
	_library = CardLibraryV4.load_library()
	_roster = _load_roster()
	_artifacts = _load_artifacts()
	_load_or_preset()
	_build_ui()
	_refresh_all()
	WashiOverlay.add_to(self)

# ---------- 数据 ----------

func _load_artifacts() -> Array:
	var f := FileAccess.open("res://data/artifacts.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Array else []

func _load_roster() -> Array:
	var f := FileAccess.open("res://data/units.json", FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and (parsed.get("units", []) is Array):
		return parsed["units"]
	return []

func _load_or_preset() -> void:
	var build := BuildSaveV4.load_build()
	if not build.is_empty():
		_main_id = String(build.get("main", DEFAULT_MAIN))
		_support_id = String(build.get("support", DEFAULT_SUPPORT))
		_artifact_id = String(build.get("artifact", ""))
		_deck_ids = (build.get("deck", []) as Array).duplicate()
	else:
		_main_id = DEFAULT_MAIN
		_support_id = DEFAULT_SUPPORT
		_artifact_id = ""
		_deck_ids = PRESET_DECK.duplicate()

func _autosave() -> void:
	BuildSaveV4.save_build(_main_id, _support_id, _deck_ids, _artifact_id)

func _owner_name(owner: String) -> String:
	for u in _roster:
		if String(u.get("id", "")) == owner:
			return String(u.get("name", owner))
	return "通用"

func _base_id(def: Dictionary) -> String:
	return String(def.get("base_id", def.get("id", "")))

func _count_of(base: String) -> int:
	var n := 0
	for id in _deck_ids:
		if _library.has(id) and _base_id(_library[id]) == base:
			n += 1
	return n

# ---------- UI 搭建 ----------

func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = _theme.color("ink_900")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var title := _label("战前构筑", 44, Vector2(72, 40), true)
	add_child(title)
	add_child(_label("固定 16 张 · 同一卡最多 2 张 · 至少 6 张主战卡 · 支援卡最多 6 张",
		18, Vector2(72, 104)))

	# 左侧：收藏列表（和纸面板 + 滚动）
	var left := PanelContainer.new()
	left.position = Vector2(60, 150)
	left.size = Vector2(1030, 790)
	left.add_theme_stylebox_override("panel", _theme.washi_panel())
	add_child(left)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(990, 750)
	left.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	_build_collection_rows()

	# 右侧：主战/支援 + 槽位 + 校验
	var right := PanelContainer.new()
	right.position = Vector2(1120, 150)
	right.size = Vector2(740, 790)
	right.add_theme_stylebox_override("panel", _theme.washi_panel())
	add_child(right)
	var rv := VBoxContainer.new()
	rv.custom_minimum_size = Vector2(680, 750)
	rv.add_theme_constant_override("separation", 14)
	right.add_child(rv)

	var party_row := HBoxContainer.new()
	party_row.add_theme_constant_override("separation", 24)
	party_row.add_child(_label("主战", 22, Vector2.ZERO, false, true))
	_main_opt = _roster_option(_main_id)
	_main_opt.item_selected.connect(_on_main_selected)
	party_row.add_child(_main_opt)
	party_row.add_child(_label("支援", 22, Vector2.ZERO, false, true))
	_support_opt = _roster_option(_support_id)
	_support_opt.item_selected.connect(_on_support_selected)
	party_row.add_child(_support_opt)
	party_row.add_child(_label("器物", 22, Vector2.ZERO, false, true))
	_artifact_opt = _artifact_option(_artifact_id)
	_artifact_opt.item_selected.connect(_on_artifact_selected)
	party_row.add_child(_artifact_opt)
	rv.add_child(party_row)
	_artifact_desc_label = _label("", 17, Vector2.ZERO, false, true)
	_artifact_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_artifact_desc_label.custom_minimum_size = Vector2(660, 48)
	rv.add_child(_artifact_desc_label)
	_update_artifact_desc()

	_count_label = _label("", 20, Vector2.ZERO, false, true)
	rv.add_child(_count_label)
	_curve_label = _label("", 18, Vector2.ZERO, false, true)
	rv.add_child(_curve_label)

	rv.add_child(_label("牌组槽位（点击移出）", 20, Vector2.ZERO, false, true))
	_slot_grid = GridContainer.new()
	_slot_grid.columns = 4
	_slot_grid.add_theme_constant_override("h_separation", 10)
	_slot_grid.add_theme_constant_override("v_separation", 10)
	rv.add_child(_slot_grid)

	_valid_label = _label("", 18, Vector2.ZERO)
	_valid_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_valid_label.custom_minimum_size = Vector2(660, 70)
	rv.add_child(_valid_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 18)
	var reset_btn := _btn("恢复预组", _on_reset_preset)
	btn_row.add_child(reset_btn)
	var back_btn := _btn("返回", _on_back)
	btn_row.add_child(back_btn)
	_go_btn = _btn("保存并出战", _on_go)
	btn_row.add_child(_go_btn)
	rv.add_child(btn_row)

func _build_collection_rows() -> void:
	for child in _list_box.get_children():
		child.queue_free()
	# 按费用→名称排序；收藏按成长存档门控（GDD §5.2/§9.1：结案解锁的新卡才进收藏）
	var ids := _library.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var da: Dictionary = _library[a]
		var db: Dictionary = _library[b]
		if int(da.get("cost", 0)) != int(db.get("cost", 0)):
			return int(da.get("cost", 0)) < int(db.get("cost", 0))
		return String(da.get("name", "")) < String(db.get("name", "")))
	var unlocked_n := 0
	for id in ids:
		var def: Dictionary = _library[id]
		if not ProgressSaveV4.is_card_unlocked(def):
			continue # 未解锁：收藏不显示（首通奖励门控）
		unlocked_n += 1
		_list_box.add_child(_collection_row(id, def))
	# 收藏计数头（重刷列表时同步更新）
	var head := _label("收藏 %d 种" % unlocked_n, 18, Vector2.ZERO, true, true)
	head.add_theme_color_override("font_color", _theme.color("vermilion_500"))
	_list_box.add_child(head)
	_list_box.move_child(head, 0)

func _collection_row(id: String, def: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_meta("card_id", id)
	row.add_theme_constant_override("separation", 14)
	var type_txt: String = TYPE_LABEL.get(String(def.get("type", "")), "卡")
	var name_l := _label("[%s] %s" % [type_txt, def.get("name", id)], 22, Vector2.ZERO, false, true)
	name_l.custom_minimum_size = Vector2(250, 0)
	row.add_child(name_l)
	var cost_l := _label("灵墨 %d" % int(def.get("cost", 0)), 18, Vector2.ZERO, false, true)
	cost_l.custom_minimum_size = Vector2(90, 0)
	row.add_child(cost_l)
	var owner_l := _label(_owner_name(String(def.get("owner", ""))), 18, Vector2.ZERO, false, true)
	owner_l.custom_minimum_size = Vector2(80, 0)
	row.add_child(owner_l)
	var cnt_l := _label("x%d" % _count_of(_base_id(def)), 20, Vector2.ZERO, false, true)
	cnt_l.name = "cnt_" + id
	cnt_l.custom_minimum_size = Vector2(48, 0)
	row.add_child(cnt_l)
	var minus := _btn("−", func() -> void: _remove_card(id))
	minus.custom_minimum_size = Vector2(44, 36)
	row.add_child(minus)
	var plus := _btn("＋", func() -> void: _add_card(id))
	plus.name = "plus_" + id
	plus.custom_minimum_size = Vector2(44, 36)
	row.add_child(plus)
	return row

func _roster_option(current: String) -> OptionButton:
	var opt := OptionButton.new()
	var idx := 0
	var sel := 0
	for u in _roster:
		var uid := String(u.get("id", ""))
		opt.add_item(String(u.get("name", uid)), idx)
		opt.set_item_metadata(idx, uid)
		if uid == current:
			sel = idx
		idx += 1
	opt.selected = sel
	opt.custom_minimum_size = Vector2(140, 40)
	return opt

func _artifact_option(current: String) -> OptionButton:
	var opt := OptionButton.new()
	opt.add_item("无器物", 0)
	opt.set_item_metadata(0, "")
	var sel := 0
	for i in _artifacts.size():
		var a: Dictionary = _artifacts[i]
		if not ProgressSaveV4.is_artifact_unlocked(a):
			continue # 未解锁器物不进构筑选项
		var idx := opt.item_count
		opt.add_item(String(a.get("name", "?")), idx)
		opt.set_item_metadata(idx, String(a.get("id", "")))
		if String(a.get("id", "")) == current:
			sel = idx
	opt.selected = sel
	opt.custom_minimum_size = Vector2(150, 40)
	return opt

func _update_artifact_desc() -> void:
	if _artifact_desc_label == null:
		return
	for a in _artifacts:
		if String(a.get("id", "")) == _artifact_id:
			_artifact_desc_label.text = "%s｜每场上限 %d 次｜%s" % [
				a.get("name", ""), int(a.get("limit", 0)), a.get("desc", "")]
			return
	_artifact_desc_label.text = "不带器物：本场无器物效果" if _artifact_id.is_empty() \
		else "⚠ 存档中的器物不存在：%s" % _artifact_id

func _label(text: String, sz: int, pos: Vector2, bold := false, dark := false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", sz)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-%s.ttf" % ("Bold" if bold else "Regular"))
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_color",
		_theme.color("ink_900") if dark else _theme.color("paper_100"))
	return l

func _btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	if f:
		b.add_theme_font_override("font", f)
	b.pressed.connect(on_press)
	return b

# ---------- 编辑操作 ----------

func _add_card(id: String) -> void:
	if not _library.has(id):
		return
	if _deck_ids.size() >= 16:
		return
	var def: Dictionary = _library[id]
	var base := _base_id(def)
	var cap := 1 if (def.get("tags", []) as Array).has("unique") else 2
	if _count_of(base) >= cap:
		return
	_deck_ids.append(id)
	_autosave()
	SfxScript.play(self, "card_play", -18.0)
	_refresh_all()

func _remove_card(id: String) -> void:
	for i in range(_deck_ids.size() - 1, -1, -1):
		if _deck_ids[i] == id:
			_deck_ids.remove_at(i)
			break
	_autosave()
	SfxScript.play(self, "card_play", -20.0)
	_refresh_all()

func _on_main_selected(idx: int) -> void:
	_main_id = String(_main_opt.get_item_metadata(idx))
	_autosave()
	_refresh_all()

func _on_support_selected(idx: int) -> void:
	_support_id = String(_support_opt.get_item_metadata(idx))
	_autosave()
	_refresh_all()

func _on_artifact_selected(idx: int) -> void:
	_artifact_id = String(_artifact_opt.get_item_metadata(idx))
	_autosave()
	_update_artifact_desc()
	SfxScript.play(self, "card_play", -20.0)

func _on_reset_preset() -> void:
	_deck_ids = PRESET_DECK.duplicate()
	_autosave()
	SfxScript.play(self, "card_play", -16.0)
	_refresh_all()

func _on_go() -> void:
	_autosave()
	SfxScript.play(self, "seal")
	InkTransitionScript.transition(get_tree(), func() -> void:
		get_tree().change_scene_to_file(NextBattleV4.scene_path))

func _on_back() -> void:
	_autosave()
	InkTransitionScript.transition(get_tree(), func() -> void:
		get_tree().change_scene_to_file(NextBattleV4.return_path))

# ---------- 刷新 ----------

func _refresh_all() -> void:
	# 收藏行计数与加号可用态
	for row in _list_box.get_children():
		var id := String(row.get_meta("card_id", ""))
		if id.is_empty() or not _library.has(id):
			continue
		var def: Dictionary = _library[id]
		var cnt := row.get_node_or_null("cnt_" + id)
		if cnt:
			(cnt as Label).text = "x%d" % _count_of(_base_id(def))
		var plus := row.get_node_or_null("plus_" + id)
		if plus:
			var cap := 1 if (def.get("tags", []) as Array).has("unique") else 2
			(plus as Button).disabled = _deck_ids.size() >= 16 \
				or _count_of(_base_id(def)) >= cap
	# 归属统计
	var main_n := 0
	var support_n := 0
	for id in _deck_ids:
		if not _library.has(id):
			continue
		var owner := String((_library[id] as Dictionary).get("owner", ""))
		if owner == _main_id:
			main_n += 1
		elif owner == _support_id:
			support_n += 1
	_count_label.text = "主战 %d · 支援 %d · 通用 %d —— 共 %d/16" % [
		main_n, support_n, _deck_ids.size() - main_n - support_n, _deck_ids.size()]
	# 费用分布
	var curve := BattleRulesV4.deck_cost_curve(_deck_ids, _library)
	var keys := curve.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s 灵墨:%d" % [k, curve[k]])
	_curve_label.text = "费用分布  " + ("　".join(parts) if parts else "—")
	# 槽位
	for child in _slot_grid.get_children():
		child.queue_free()
	for i in 16:
		var cell := Button.new()
		cell.custom_minimum_size = Vector2(158, 52)
		cell.add_theme_font_size_override("font_size", 16)
		if i < _deck_ids.size() and _library.has(_deck_ids[i]):
			var id: String = _deck_ids[i]
			cell.text = String((_library[id] as Dictionary).get("name", id))
			cell.pressed.connect(func() -> void: _remove_card(id))
		else:
			cell.text = "·"
			cell.disabled = true
		_slot_grid.add_child(cell)
	# 校验（规则唯一来源 BattleRulesV4）
	var errors := BattleRulesV4.validate_deck(_deck_ids, _main_id, _support_id, _library)
	if errors.is_empty():
		_valid_label.text = "✓ 牌组合法"
		_valid_label.add_theme_color_override("font_color", _theme.color("successful"))
		_go_btn.disabled = false
	else:
		_valid_label.text = "✗ " + "；".join(errors)
		_valid_label.add_theme_color_override("font_color", _theme.color("vermilion_500"))
		_go_btn.disabled = true
