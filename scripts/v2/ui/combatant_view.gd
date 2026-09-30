class_name CombatantView
extends PanelContainer
## 战斗单位视图 v2
##
## 一个立绘 + HP 条 + 护盾 + 状态/tag 图标 + 意图图标（仅敌人）。
## 替代旧 battle_scene._update_sprite（销毁子节点重建）。
## 数据驱动：setup() 接收 UnitV2，自动渲染；点击时发 target_selected 信号（敌人立绘可选为目标）。

signal target_selected(unit)
signal died(unit)

var _unit: UnitV2
var _role: String = "enemy"  # "enemy" / "player"
var _intent: Dictionary = {}

var _portrait: TextureRect
var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _shield_label: Label
var _tag_label: Label
var _intent_label: Label
var _click_area: Control
var _flash_rect: ColorRect  # 受击红闪覆盖层


func _ready() -> void:
	custom_minimum_size = Vector2(180, 280)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP  # 确保自身能接收点击
	_build_layout()
	_apply_theme()


func _build_layout() -> void:
	# 受击闪烁层（最底，全 panel 覆盖）
	_flash_rect = ColorRect.new()
	_flash_rect.name = "FlashRect"
	_flash_rect.color = Color(1, 0.2, 0.2, 0)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash_rect)

	var vb = VBoxContainer.new()
	vb.name = "VBox"
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 16)
	vb.add_child(_name_label)

	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.custom_minimum_size = Vector2(140, 180)
	_portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vb.add_child(_portrait)

	_hp_bar = ProgressBar.new()
	_hp_bar.name = "HpBar"
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_bar.custom_minimum_size = Vector2(160, 20)
	_hp_bar.min_value = 0
	_hp_bar.show_percentage = false
	vb.add_child(_hp_bar)

	_hp_label = Label.new()
	_hp_label.name = "HpLabel"
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 14)
	vb.add_child(_hp_label)

	_shield_label = Label.new()
	_shield_label.name = "ShieldLabel"
	_shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shield_label.add_theme_font_size_override("font_size", 14)
	_shield_label.add_theme_color_override("font_color", Color(0.5, 0.75, 1.0))
	vb.add_child(_shield_label)

	_tag_label = Label.new()
	_tag_label.name = "TagLabel"
	_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tag_label.add_theme_font_size_override("font_size", 12)
	_tag_label.add_theme_color_override("font_color", Color(0.31, 0.78, 0.31))
	vb.add_child(_tag_label)

	_intent_label = Label.new()
	_intent_label.name = "IntentLabel"
	_intent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.add_theme_font_size_override("font_size", 14)
	_intent_label.add_theme_color_override("font_color", Color(0.76, 0.23, 0.23))
	vb.add_child(_intent_label)

	# 点击命中区（覆盖整个 panel，用于选目标）
	_click_area = Control.new()
	_click_area.name = "ClickArea"
	_click_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_click_area.anchors_preset = Control.PRESET_FULL_RECT
	_click_area.gui_input.connect(_on_click_area_gui_input)
	add_child(_click_area)


func setup(unit, role: String, intent: Dictionary) -> void:
	# 解绑旧 unit 的 signal（若有）
	if _unit != null and _unit.hp_changed.is_connected(_on_unit_hp_changed):
		_unit.hp_changed.disconnect(_on_unit_hp_changed)
	if _unit != null and _unit.died.is_connected(_on_unit_died):
		_unit.died.disconnect(_on_unit_died)
	_unit = unit
	_role = role
	_intent = intent
	# 绑新 unit 的 signal，HP 变化时自动刷新
	if _unit != null:
		if not _unit.hp_changed.is_connected(_on_unit_hp_changed):
			_unit.hp_changed.connect(_on_unit_hp_changed)
		if not _unit.died.is_connected(_on_unit_died):
			_unit.died.connect(_on_unit_died)
	call_deferred("_refresh")


func _on_unit_hp_changed(_u) -> void:
	_refresh()


func _on_unit_died(_u) -> void:
	_refresh()
	play_death()


func _apply_theme() -> void:
	# 应用 JSON 驱动的 9-slice 蒸汽道术面板
	UIThemeFactoryV2.apply_panel(self, "main")


func set_intent(intent: Dictionary) -> void:
	_intent = intent
	call_deferred("_refresh")


func _refresh() -> void:
	if _unit == null:
		return
	_name_label.text = _unit.name
	_name_label.add_theme_color_override("font_color", _unit.color)
	_hp_bar.max_value = _unit.max_hp
	_hp_bar.value = _unit.current_hp
	_hp_label.text = "%d / %d" % [_unit.current_hp, _unit.max_hp]
	_shield_label.visible = _unit.shield > 0
	_shield_label.text = "护盾 %d" % _unit.shield if _unit.shield > 0 else ""
	var tags_text = ""
	for t in _unit.tags:
		tags_text += "[%s] " % t
	_tag_label.text = tags_text
	# 立绘
	var portrait_path = _unit.sprites.get("portrait", "")
	if portrait_path.is_empty():
		portrait_path = _unit.sprites.get("battle", "")
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		_portrait.texture = load(portrait_path)
	# 意图（仅敌人）
	if _role == "enemy" and not _intent.is_empty():
		_intent_label.text = String(_intent.get("description", ""))
	else:
		_intent_label.text = ""
	# 死亡时灰显
	modulate.a = 1.0 if _unit.is_alive else 0.35


func _on_click_area_gui_input(event: InputEvent) -> void:
	_handle_click(event)


## CombatantView 自己也响应点击（PanelContainer.gui_input），双保险
func _gui_input(event: InputEvent) -> void:
	_handle_click(event)


func _handle_click(event: InputEvent) -> void:
	if _role != "enemy":
		return
	if _unit == null or not _unit.is_alive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DebugLog.info("COMBATANT: clicked enemy id=" + str(_unit.id))
		target_selected.emit(_unit)


# ===== 视觉反馈（Tween 程序化，不用粒子）=====

## 受击：红闪 + 后退抖动
func play_hit() -> void:
	if _portrait == null:
		return
	_kill_tween()
	var t = create_tween()
	t.set_parallel(true)
	# 红色覆盖层闪 3 次
	t.tween_property(_flash_rect, "color:a", 0.5, 0.05)
	t.chain().tween_property(_flash_rect, "color:a", 0.0, 0.10)
	t.chain().tween_property(_flash_rect, "color:a", 0.35, 0.05)
	t.chain().tween_property(_flash_rect, "color:a", 0.0, 0.10)
	# 立绘轻微后退再回弹
	var orig_x = _portrait.position.x
	t.tween_property(_portrait, "position:x", orig_x - 6.0, 0.06)
	t.chain().tween_property(_portrait, "position:x", orig_x, 0.10)


## 攻击：立绘前冲
func play_attack(direction: int = 1) -> void:
	# direction: 1=向右冲（敌人向右攻击玩家视图，玩家向左），-1=向左
	if _portrait == null:
		return
	_kill_tween()
	var orig_x = _portrait.position.x
	var t = create_tween()
	t.tween_property(_portrait, "position:x", orig_x + 12.0 * direction, 0.10).set_trans(Tween.TRANS_SINE)
	t.tween_property(_portrait, "position:x", orig_x, 0.12).set_trans(Tween.TRANS_BACK)


## 治疗：绿色微闪 + 上浮
func play_heal() -> void:
	if _portrait == null:
		return
	_kill_tween()
	var orig_color = _portrait.modulate
	var t = create_tween()
	t.set_parallel(true)
	t.tween_property(_portrait, "modulate:g", 1.3, 0.10)
	t.chain().tween_property(_portrait, "modulate", orig_color, 0.20)


## 死亡：旋转倒下 + 淡出 + 下沉
func play_death() -> void:
	if _portrait == null:
		return
	_kill_tween()
	modulate.a = 1.0
	var t = create_tween().set_parallel(true)
	t.tween_property(_portrait, "rotation", deg_to_rad(75.0), 0.5).set_trans(Tween.TRANS_QUAD)
	t.tween_property(_portrait, "modulate:a", 0.0, 0.5)
	t.tween_property(_portrait, "position:y", _portrait.position.y + 30.0, 0.5)


## 待机呼吸（idle 循环，由 battle_scene 在 setup 后调用一次）
func play_idle_breath() -> void:
	if _portrait == null:
		return
	_kill_tween()
	var orig_scale = _portrait.scale
	var t = create_tween().set_loops()
	t.tween_property(_portrait, "scale:y", orig_scale.y * 1.03, 0.9).set_trans(Tween.TRANS_SINE)
	t.tween_property(_portrait, "scale:y", orig_scale.y, 0.9).set_trans(Tween.TRANS_SINE)


func _kill_tween() -> void:
	if _portrait != null and _portrait.has_meta("_active_tween"):
		var old = _portrait.get_meta("_active_tween")
		if old is Tween and old.is_valid():
			old.kill()
	# create_tween 会自动绑定到本节点，树销毁时统一清理
