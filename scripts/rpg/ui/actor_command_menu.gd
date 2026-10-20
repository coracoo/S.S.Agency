extends Control
## 紧凑纸叶菜单；沿用真实模型、费用、目标和确认流程。
## 原画笔RGB提供纸纹，代码alpha遮罩提供紧凑纸叶轮廓。
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const SkillIcons = preload("res://scripts/rpg/ui/battle_skill_icons.gd")
const PAPER := Color("F3EFE5")
const INK := Color("252B29")
const SEAL := Color("A64234")
const MUTED := Color("545952")
const TRIAL_SKILL_RECTS := [Rect2(864,450,244,90),Rect2(856,548,244,88),Rect2(850,644,244,88),Rect2(856,740,244,88)]
const TRIAL_SCROLL_ORIGIN := Vector2(842,440)
const TRIAL_SCROLL_SIZE := Vector2(280,400)
const TRIAL_ITEMS_RECT := Rect2(850,478,274,350)
const TRIAL_DETAIL_RECT := Rect2(1120,150,480,202)
const TRIAL_BACK_RECT := Rect2(1710,975,160,64)
const TRIAL_TARGET_RECT := Rect2(850,490,260,138)
const TRIAL_CONFIRM_RECT := Rect2(866,654,180,88)
const TRIAL_HIT_ALPHA := 0.18
const TRIAL_720_SCALE := 720.0/1080.0
const TRIAL_BRUSH_ROOT := "res://assets/ui/battle_washi_compact/"
const SKILL_BASE_NAMES := {"heavy_slash":"重斩","armor_break":"破甲斩","sweep":"横扫","battle_spirit":"战意"}

class TrialLeafButton extends Button:
	var trial_menu: Control
	func _has_point(point: Vector2) -> bool:
		if is_instance_valid(trial_menu): return bool(trial_menu.call("_trial_leaf_has_point",self,point))
		return Rect2(Vector2.ZERO,size).has_point(point)

signal command_requested(kind: String, ability_id: String)
signal page_requested(page: String)
signal back_requested
signal confirm_requested

var skill_buttons: Array[Button] = []
var basic_buttons: Dictionary = {}
var confirm_button: Button
var back_button: Button
var use_washi_paper := true
var trial_paper_normal_path := TRIAL_BRUSH_ROOT+"normal-brush.png"
var trial_paper_selected_path := TRIAL_BRUSH_ROOT+"selected-brush.png"
var _built := false
var _docked := false
var _model: Dictionary = {}
var _page := "commands"
var _pages: Dictionary = {}
var _header: Label
var _header_paper: Panel
var _skills_entry: Button
var _skill_scroll: ScrollContainer
var _skill_content: Control
var _item_scroll: ScrollContainer
var _item_content: Control
var _item_buttons: Array[Button] = []
var _target_line: Label
var _target_paper: Panel
var _focus_keys: Dictionary = {}
var _trial_textures: Dictionary = {}
var _trial_images: Dictionary = {}
var _trial_masked_textures: Dictionary = {}
var _trial_masked_images: Dictionary = {}
var _trial_mask_metrics: Dictionary = {}
var _trial_catalog: RefCounted
var _trial_layout_busy := false
var _trial_hover_button: Button
var _trial_focus_button: Button
var _trial_last_entry: Dictionary = {}
var _trial_detail: Control
var _trial_detail_title: Label
var _trial_detail_resource: Label
var _trial_detail_scroll: ScrollContainer
var _trial_detail_body: Label
var _trial_detail_selection_key := ""
var _trial_detail_signature := ""

static func size_for_page(_page_name: String, _docked_mode: bool) -> Vector2:
	return TRIAL_SCROLL_SIZE

func required_size_for_page(page_name: String, docked_mode: bool) -> Vector2:
	return size_for_page(page_name,docked_mode)

func _ready() -> void:
	_ensure_built()
	visibility_changed.connect(_sync_focus_modes)
	resized.connect(_layout)
	_layout()
	_sync_focus_modes()

func _ensure_built() -> void:
	if _built: return
	_built = true
	Kit.init()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for page_name in ["commands","skills","items","target"]:
		var panel := Control.new()
		panel.name = page_name.capitalize()
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		_pages[page_name] = panel
	# 保留诊断节点；四页均隐藏旧父纸板与旧页眉。
	_header_paper = _hidden_panel(self,"OldHeaderPaper")
	_header = _label(24)
	_header.name = "OldHeader"
	_header.hide()
	add_child(_header)
	_skills_entry = _leaf("skills")
	_skills_entry.name = "SkillsEntry"
	_pages.commands.add_child(_skills_entry)
	_skills_entry.pressed.connect(_request_page.bind("skills",_skills_entry))
	for kind in ["attack_physical","attack_magic","defend","item"]:
		var button := _leaf(kind)
		button.name = kind.to_pascal_case()
		_pages.commands.add_child(button)
		basic_buttons[kind] = button
		if kind == "item": button.pressed.connect(_request_page.bind("items",button))
		else: button.pressed.connect(_request_command.bind(kind,button))
	_skill_scroll = _scroll(_pages.skills)
	_skill_scroll.name = "SkillScroll"
	_skill_content = _content(_skill_scroll)
	for index in 4:
		var button := _leaf("skill:")
		button.name = "Skill%d" % index
		_skill_content.add_child(button)
		skill_buttons.append(button)
		button.pressed.connect(_request_command.bind("skill",button))
	_item_scroll = _scroll(_pages.items)
	_item_scroll.name = "ItemScroll"
	_item_content = _content(_item_scroll)
	for index in 7:
		var button := _leaf("item:")
		button.name = "Item%d" % index
		_item_content.add_child(button)
		_item_buttons.append(button)
		button.pressed.connect(_request_command.bind("item",button))
	_target_paper = _hidden_panel(_pages.target,"OldTargetPaper")
	_target_line = _label(24)
	_target_line.name = "TrialTargetText"
	_target_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_line.add_theme_color_override("font_color",PAPER)
	_pages.target.add_child(_target_line)
	confirm_button = _leaf("confirm")
	confirm_button.name = "Confirm"
	_pages.target.add_child(confirm_button)
	confirm_button.pressed.connect(_request_confirm)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.set_meta("command_key","back")
	back_button.mouse_filter = Control.MOUSE_FILTER_STOP
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.add_theme_font_override("font",Kit.font)
	back_button.add_theme_font_size_override("font_size",24)
	for state in ["normal","hover","pressed","disabled","focus"]: back_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: back_button.add_theme_color_override(state,PAPER)
	add_child(back_button)
	back_button.pressed.connect(_request_back)
	var decoration := Node2D.new()
	decoration.name = "TrialBackInk"
	back_button.add_child(decoration)
	var line := Line2D.new()
	line.points = PackedVector2Array([Vector2(0,54),Vector2(160,54)])
	line.width = 1
	line.default_color = Color(PAPER.r,PAPER.g,PAPER.b,.65)
	decoration.add_child(line)
	var dot := Polygon2D.new()
	dot.position = Vector2(12,30)
	dot.color = SEAL
	var points := PackedVector2Array()
	for part in 16: points.append(Vector2(cos(TAU*part/16),sin(TAU*part/16))*3.5)
	dot.polygon = points
	decoration.add_child(dot)
	_build_detail()

func present(model: Dictionary) -> void:
	_ensure_built()
	var previous_page := _page
	_model = model.duplicate(true)
	_page = str(_model.get("page","commands"))
	if not _pages.has(_page): _page = "commands"
	if previous_page != _page:
		_trial_hover_button = null
		_trial_focus_button = null
	for page_name in _pages: _pages[page_name].visible = page_name == _page
	_focus_keys = {"skills":_skills_entry,"confirm":confirm_button,"back":back_button}
	var basics: Array = _model.get("basics",[])
	var basic_entries: Array = _model.get("basic_entries",[])
	_set_leaf(_skills_entry,{"kind":"skills","name":"技能","full_summary":"选择已装备的真实技能。"},"技能","","skills")
	_skills_entry.visible = true
	_skills_entry.disabled = false
	var names := {"attack_physical":"物理普攻","attack_magic":"魔法普攻","defend":"防御","item":"道具"}
	for kind in basic_buttons:
		var button: Button = basic_buttons[kind]
		var entry: Dictionary = {"kind":kind,"name":names[kind]}
		for candidate in basic_entries:
			if candidate is Dictionary and str(candidate.get("kind","")) == kind:
				entry = candidate.duplicate(true)
				break
		button.visible = kind in basics
		# basics 原字段没有 legal；不从中文原因猜规则。
		button.disabled = not bool(entry.get("selectable",entry.get("legal",true)))
		var resource := "MP %s" % str(entry.get("mp_cost",0)) if entry.has("mp_cost") else ""
		if kind == "item":
			# 道具入口只导航；未选择具体道具时不展示空ID预览的报错。
			resource = ""
			entry = {"kind":"item","name":"道具","full_summary":"选择道具，查看持有数量和可用目标。"}
		_set_leaf(button,entry,str(entry.get("name",names[kind])),resource,kind)
		_focus_keys[kind] = button
	var skills: Array = _model.get("skills",[])
	for index in skill_buttons.size():
		var button: Button = skill_buttons[index]
		var entry: Dictionary = skills[index] if index < skills.size() else {}
		var id := str(entry.get("id",""))
		button.visible = not entry.is_empty()
		button.disabled = not bool(entry.get("selectable",entry.get("legal",false)))
		button.set_meta("ability_id",id)
		_set_leaf(button,entry,_base_skill_name(entry),_skill_resource(entry),"skill:"+id)
		_focus_keys["skill:"+id] = button
	var items: Array = _model.get("items",[])
	for index in _item_buttons.size():
		var button: Button = _item_buttons[index]
		var entry: Dictionary = items[index] if index < items.size() else {}
		var id := str(entry.get("id",""))
		button.visible = not entry.is_empty()
		button.disabled = not bool(entry.get("selectable",entry.get("legal",false)))
		button.set_meta("ability_id",id)
		_set_leaf(button,entry,str(entry.get("name","")),"数量 %s" % str(entry.get("count",0)),"item:"+id)
		_focus_keys["item:"+id] = button
	var target_entry := _selected_entry()
	var selected_name := str(target_entry.get("name",_model.get("selected_label","")))
	var target_parts := _strings([selected_name,_model.get("cost_text",""),_model.get("target_text","")])
	_target_line.text = "\n".join(target_parts)
	if _target_line.text.is_empty(): _target_line.text = str(_model.get("prompt","选择目标后确认"))
	_target_line.tooltip_text = _target_line.text+"\n"+str(_model.get("prompt",""))
	_set_leaf(confirm_button,{"name":"确认","full_summary":_model.get("prompt","")},"确认","","confirm")
	confirm_button.disabled = not bool(_model.get("confirm_legal",false))
	back_button.visible = true
	back_button.text = "返回标题" if _page == "commands" else "返回"
	_layout()
	_sync_focus_modes()

func set_placement(_rect: Rect2, _docked_mode: bool) -> void:
	_ensure_built()
	_docked = false
	position = Vector2.ZERO
	size = Vector2(1920,1080)
	_layout()

func focus_key(key: String) -> void:
	_ensure_built()
	var requested: Control = _focus_keys.get(key)
	if requested != null and requested in enabled_controls():
		requested.grab_focus()
		# 固定弧列不允许被滚动父节点平移；道具仍使用真实滚动。
		if requested.get_parent() == _item_content: _item_scroll.ensure_control_visible(requested)

func occupied_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	if not _built or not is_visible_in_tree(): return result
	var inverse := get_global_transform().affine_inverse()
	for button in _all_buttons():
		if not button.is_visible_in_tree(): continue
		var local: Rect2 = button.get_meta("trial_visual_rect",Rect2(Vector2.ZERO,button.size))
		var rectangle := Rect2(inverse*button.global_position+local.position,local.size)
		if _item_scroll.is_ancestor_of(button): rectangle = rectangle.intersection(Rect2(inverse*_item_scroll.global_position,_item_scroll.size))
		if rectangle.has_area(): result.append(rectangle.grow(2))
	if _target_line.is_visible_in_tree() and not _target_line.text.is_empty():
		# 登记实际文字行盒，不把260×138标签的空白尾部当作可见内容。
		# 包含字形留白和额外2px边距；不移动目标说明或改变其字号。
		var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		var measured := Kit.font.get_multiline_string_size(_target_line.text,HORIZONTAL_ALIGNMENT_LEFT,_target_line.size.x,24,-1,flags)
		result.append(Rect2(_target_line.position,Vector2(ceilf(measured.x),ceilf(measured.y))).grow(2))
	if _trial_detail.is_visible_in_tree(): result.append(TRIAL_DETAIL_RECT)
	return result

func enabled_controls() -> Array[Control]:
	var result: Array[Control] = []
	if not _built or not is_visible_in_tree(): return result
	for button in _all_buttons():
		if button.is_visible_in_tree() and not button.disabled: result.append(button)
	return result

func _all_buttons() -> Array[Button]:
	var result: Array[Button] = [_skills_entry]
	for kind in ["attack_physical","attack_magic","defend","item"]: result.append(basic_buttons[kind])
	result.append_array(skill_buttons)
	result.append_array(_item_buttons)
	result.append(confirm_button)
	result.append(back_button)
	return result

func _sync_focus_modes() -> void:
	if not _built: return
	var enabled := enabled_controls()
	for button in _all_buttons():
		if button not in enabled:
			if button.has_focus(): button.release_focus()
			button.focus_mode = Control.FOCUS_NONE
		else: button.focus_mode = Control.FOCUS_ALL
	for index in enabled.size():
		var button := enabled[index]
		var previous := enabled[(index-1+enabled.size())%enabled.size()]
		var following := enabled[(index+1)%enabled.size()]
		button.focus_previous = button.get_path_to(previous)
		button.focus_next = button.get_path_to(following)

func _request_page(page_name: String, button: Button) -> void:
	if _can_press(button): page_requested.emit(page_name)

func _request_command(kind: String, button: Button) -> void:
	if not _can_press(button): return
	_trial_last_entry = button.get_meta("trial_entry",{}).duplicate(true)
	_trial_last_entry["selection_key"] = str(button.get_meta("command_key",""))
	command_requested.emit(kind,str(button.get_meta("ability_id","")))

func _request_confirm() -> void:
	if _can_press(confirm_button): confirm_requested.emit()

func _request_back() -> void:
	if _can_press(back_button): back_requested.emit()

func _can_press(button: Button) -> bool:
	return button.is_visible_in_tree() and not button.disabled

func _layout() -> void:
	if not _built or _trial_layout_busy: return
	_trial_layout_busy = true
	position = Vector2.ZERO
	size = Vector2(1920,1080)
	for panel in _pages.values(): panel.size = size
	_header.hide()
	_header_paper.hide()
	_target_paper.hide()
	_skill_scroll.position = TRIAL_SCROLL_ORIGIN
	_skill_scroll.size = TRIAL_SCROLL_SIZE
	_skill_scroll.clip_contents = false
	_skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_skill_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_skill_scroll.scroll_horizontal = 0
	_skill_scroll.scroll_vertical = 0
	_skill_content.custom_minimum_size = TRIAL_SCROLL_SIZE
	_skill_content.size = TRIAL_SCROLL_SIZE
	_skill_content.position = Vector2.ZERO
	for index in skill_buttons.size(): _layout_paper(skill_buttons[index],TRIAL_SKILL_RECTS[index],TRIAL_SCROLL_ORIGIN,index == 0)
	var commands: Array[Button] = [_skills_entry]
	for kind in ["attack_physical","attack_magic","defend","item"]:
		if basic_buttons[kind].visible: commands.append(basic_buttons[kind])
	for index in commands.size():
		var frame: Rect2
		if commands.size() <= 4: frame = TRIAL_SKILL_RECTS[index]
		else:
			# 魔攻角色五个真实入口：向上增加一片，不删除、不缩字号。
			var frames := [Rect2(864,352,244,90),Rect2(856,450,244,88),Rect2(850,546,244,88),Rect2(856,642,244,88),Rect2(864,738,244,88)]
			frame = frames[index]
		_layout_paper(commands[index],frame,Vector2.ZERO,index == 0)
	_item_scroll.position = TRIAL_ITEMS_RECT.position
	_item_scroll.size = TRIAL_ITEMS_RECT.size
	_item_scroll.clip_contents = true
	_item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	var item_y := 0.0
	for button in _item_buttons:
		if not button.visible: continue
		_layout_paper(button,Rect2(TRIAL_ITEMS_RECT.position+Vector2(0,item_y),Vector2(244,88)),TRIAL_ITEMS_RECT.position,false)
		item_y += 96.0
	_item_content.custom_minimum_size = Vector2(248,maxf(1,item_y-8))
	_item_content.size = _item_content.custom_minimum_size
	_target_line.position = TRIAL_TARGET_RECT.position
	_target_line.size = TRIAL_TARGET_RECT.size
	_target_line.clip_text = false
	_target_line.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_layout_paper(confirm_button,TRIAL_CONFIRM_RECT,Vector2.ZERO,true,true)
	back_button.position = TRIAL_BACK_RECT.position
	back_button.size = TRIAL_BACK_RECT.size
	_trial_detail.position = TRIAL_DETAIL_RECT.position
	_trial_detail.size = TRIAL_DETAIL_RECT.size
	_trial_layout_busy = false
	_refresh_detail()

func _layout_paper(button: Button, frame: Rect2, origin: Vector2, tall: bool, small: bool = false) -> void:
	button.position = frame.position-origin
	button.size = frame.size
	# 纸片无需跨层覆盖；抬高首片会穿过后创建的退出确认弹层。
	button.z_index = 0
	var kind := "selected" if tall else "normal"
	var title: Label = button.get_node("Title")
	var resource: Label = button.get_node("Resource")
	var title_rect := Rect2(26,6,frame.size.x-40,44)
	var resource_rect := Rect2(26,48,frame.size.x-40,32)
	var icon: Control = button.get_node("IconSlot")
	var skill_icon := str(button.get_meta("command_key","")).begins_with("skill:")
	icon.visible = skill_icon
	icon.position = Vector2(26,10)
	icon.size = Vector2(38,38)
	if skill_icon:
		# 图标与技能标题同排；保留已认可的纸片、MP/CD行和所有全局位置。
		title_rect.position.x = 70
		title_rect.size.x = frame.size.x-84
	if resource.text.is_empty() or small: title_rect.position.y = (frame.size.y-44)*0.5
	_place_label(title,title_rect,32)
	_place_label(resource,resource_rect,22)
	resource.visible = not resource.text.is_empty() and not small
	button.get_node("Detail").hide()
	button.get_node("Reason").hide()
	# Keep the old node for inspection compatibility, but it cannot fill the mask.
	var backing: Polygon2D = button.get_node("TrialPaperBacking")
	backing.polygon = PackedVector2Array()
	backing.hide()
	var ink_regions := _trial_ink_regions(button)
	var quiet := _trial_quiet_core(button,frame.size)
	var hit_core := Rect2(26,11,maxf(128,quiet.size.x-16),frame.size.y-22)
	var variant_seed := float(posmod(str(button.get_meta("command_key","")).hash(),97))/97.0*3.1
	var cache_key := _trial_mask_key(kind,frame.size,quiet,ink_regions,variant_seed)
	var paper: TextureRect = button.get_node("TrialBrushPaper")
	paper.texture = _trial_masked_texture(kind,frame.size,quiet,hit_core,ink_regions,variant_seed,cache_key)
	paper.position = Vector2.ZERO
	paper.size = frame.size
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	var metrics: Dictionary = _trial_mask_metrics.get(cache_key,{})
	button.set_meta("trial_paper_kind",kind)
	button.set_meta("trial_mask_cache_key",cache_key)
	button.set_meta("trial_paper_draw_rect",Rect2(Vector2.ZERO,frame.size))
	button.set_meta("trial_visual_rect",metrics.get("visual_bounds",Rect2(Vector2.ZERO,frame.size)))
	button.set_meta("trial_quiet_text_core_rect",quiet)
	button.set_meta("trial_glyph_ink_regions",ink_regions)
	button.set_meta("trial_hit_core_rect",hit_core)
	button.set_meta("trial_requested_frame",frame)
	button.set_meta("trial_requested_title_rect",title_rect)
	button.set_meta("trial_requested_resource_rect",resource_rect)
	button.set_meta("trial_requested_content_right_padding",frame.size.x-title_rect.end.x)
	button.set_meta("trial_missing_icon",skill_icon and not bool(icon.call("supports_skill_id",str(button.get_meta("ability_id","")))))
	for label_name in ["Title","Resource"]:
		var label: Label = button.get_node(label_name)
		label.add_theme_color_override("font_color",MUTED if button.disabled else INK)

func _trial_ink_regions(button: Button) -> Array[Rect2]:
	var result: Array[Rect2] = []
	var icon: Control = button.get_node("IconSlot")
	if icon.visible: result.append(Rect2(icon.position+Vector2(2,2),icon.size-Vector2(4,4)))
	for label_name in ["Title","Resource"]:
		var label: Label = button.get_node(label_name)
		if not label.visible or label.text.is_empty(): continue
		var font_size := label.get_theme_font_size("font_size")
		var width := Kit.font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
		# Conservative ink envelopes from the actual 1080/720 render: the
		# 32px title inks y~16..42; 22px resource inks y~56..74. Protect
		# those glyphs, rather than the much taller Label control rectangles.
		var ink_top := label.position.y+(7 if label_name == "Title" else 6)
		result.append(Rect2(label.position.x-2,ink_top,width+4,font_size))
	return result

func _trial_quiet_core(button: Button, paper_size: Vector2) -> Rect2:
	var regions := _trial_ink_regions(button)
	if regions.is_empty(): return Rect2(24,13,paper_size.x-48,32)
	var bounds := regions[0]
	for region in regions: bounds = bounds.merge(region)
	return bounds

func _trial_mask_key(kind: String, paper_size: Vector2, quiet: Rect2, regions: Array[Rect2], seed: float) -> String:
	var key := "%s:%dx%d:%d:%d" % [kind,roundi(paper_size.x),roundi(paper_size.y),roundi(quiet.end.x),roundi(seed*1000)]
	for region in regions: key += ":%d,%d,%d,%d" % [roundi(region.position.x),roundi(region.position.y),roundi(region.size.x),roundi(region.size.y)]
	return key

# A few broad, asymmetric horizontal brush runs have continuous soft ends.
# Thin furrows remain connected to an outside edge; there are no particles or
# high-frequency teeth. The separate glyph envelopes stay >=.97 alpha, while
# the full 66-logical-pixel accessibility core stays >=.44 alpha.
func _trial_masked_texture(kind: String, paper_size: Vector2, quiet: Rect2, hit_core: Rect2, ink_regions: Array[Rect2], variant_seed: float, cache_key: String) -> Texture2D:
	if _trial_masked_textures.has(cache_key): return _trial_masked_textures[cache_key]
	_trial_texture(kind)
	var width := maxi(1,roundi(paper_size.x))
	var height := maxi(1,roundi(paper_size.y))
	var image := Image.create(width,height,false,Image.FORMAT_RGBA8)
	var source: Image = _trial_images.get(kind)
	var tone := _trial_paper_color(kind)
	var seed := variant_seed+(1.7 if kind == "selected" else 0.35)
	var edge_count := 0
	var erased_edge_count := 0
	var partial_edge_count := 0
	var visible_count := 0
	var alpha_area := 0.0
	var quiet_min_alpha := 1.0
	var ink_min_alpha := 1.0
	var hit_min_alpha := 1.0
	var bounds := Rect2()
	var hit_bounds := Rect2()
	var has_bounds := false
	var has_hit_bounds := false
	for y in height:
		for x in width:
			var point := Vector2(x+0.5,y+0.5)
			var alpha := _trial_perimeter_alpha(point,Vector2(width,height),quiet,hit_core,ink_regions,seed)
			var color := tone
			if source != null:
				var sx := clampi(floori(point.x/width*source.get_width()),0,source.get_width()-1)
				var sy := clampi(floori(point.y/height*source.get_height()),0,source.get_height()-1)
				var grain := source.get_pixel(sx,sy)
				color = tone.lerp(grain,clampf(grain.a,0,1)*0.28)
			color.a = alpha
			image.set_pixel(x,y,color)
			alpha_area += alpha
			if hit_core.has_point(point): hit_min_alpha = minf(hit_min_alpha,alpha)
			for ink in ink_regions:
				if ink.has_point(point): ink_min_alpha = minf(ink_min_alpha,alpha)
			if quiet.has_point(point): quiet_min_alpha = minf(quiet_min_alpha,alpha)
			else:
				edge_count += 1
				if alpha < TRIAL_HIT_ALPHA: erased_edge_count += 1
				elif alpha < 0.98: partial_edge_count += 1
			var pixel_rect := Rect2(x,y,1,1)
			if alpha > 0.02:
				bounds = bounds.merge(pixel_rect) if has_bounds else pixel_rect
				has_bounds = true
			if alpha >= TRIAL_HIT_ALPHA:
				visible_count += 1
				hit_bounds = hit_bounds.merge(pixel_rect) if has_hit_bounds else pixel_rect
				has_hit_bounds = true
	var texture := ImageTexture.create_from_image(image)
	_trial_masked_images[cache_key] = image
	_trial_masked_textures[cache_key] = texture
	_trial_mask_metrics[cache_key] = {
		"visual_bounds":bounds,"visual_alpha_threshold":0.02,"hit_visual_bounds":hit_bounds,
		"visible_pixel_count":visible_count,"alpha_weighted_area_px2":alpha_area,"frame_area_px2":width*height,
		"edge_pixel_count":edge_count,"erased_edge_pixel_count":erased_edge_count,
		"erased_edge_fraction":float(erased_edge_count)/maxi(1,edge_count),"partial_edge_pixel_count":partial_edge_count,
		"quiet_core_min_alpha":quiet_min_alpha,"glyph_ink_min_alpha":ink_min_alpha,"glyph_ink_alpha_floor":0.97,
		"hit_core_min_alpha":hit_min_alpha,"hit_core_alpha_floor":0.44,"hit_alpha_threshold":TRIAL_HIT_ALPHA,
		"quiet_rect_is_glyph_envelope_union":true,"glyph_envelopes_are_conservative_estimates":true,
		"top_bottom_soft_transition_logical_px":Vector2(7.7,11.9),"end_soft_transition_logical_px":Vector2(18,23),
		"mask_method":"broad asymmetric horizontal brush runs with continuous soft retreat and connected fiber furrows",
		"mask_revision":"v4-soft-runs-02","mask_seed":seed,"mask_uses_particles":false,
		"erased_fraction_is_visual_acceptance":false,"old_opaque_backing_visible":false}
	return texture

func _trial_feathered_rect(point: Vector2, rectangle: Rect2, fringe: float) -> float:
	var dx := maxf(0,maxf(rectangle.position.x-point.x,point.x-rectangle.end.x))
	var dy := maxf(0,maxf(rectangle.position.y-point.y,point.y-rectangle.end.y))
	return 1-smoothstep(0,fringe,Vector2(dx,dy).length())

func _trial_perimeter_alpha(point: Vector2, paper_size: Vector2, quiet: Rect2, hit_core: Rect2, ink_regions: Array[Rect2], seed: float) -> float:
	var u := point.x/paper_size.x
	var v := (point.y-paper_size.y*0.5)/(paper_size.y*0.5)
	var taper := pow(clampf(absf(v),0,1),1.6)
	var body_right := maxf(quiet.end.x+4,minf(182,paper_size.x-20))
	# Low-frequency curves travel along the whole stroke. They do not stamp
	# a repeating sawtooth on every side of a rectangular quiet block.
	var left := maxf(9.75,7+taper*17+sin(v*3.8+seed)*3)
	var right := minf(paper_size.x-9.75,body_right+10+(1-taper)*18+sin(v*3.2+seed)*5)
	var top := 7+sin(u*5.1+seed)*3+sin(u*11.3+seed)*1.5
	var bottom := paper_size.y-(7+cos(u*4.3+seed)*3+sin(u*9.7+seed)*1.5)
	var top_soft := 7+sin(u*4+seed)*1.5
	var bottom_soft := 7+cos(u*3.7+seed)*1.5
	top = maxf(top,top_soft*0.55+1)
	bottom = minf(bottom,paper_size.y-bottom_soft*0.55-1)
	var vertical := minf(smoothstep(top-top_soft*0.55,top+top_soft*0.85,point.y),1-smoothstep(bottom-bottom_soft*0.85,bottom+bottom_soft*0.55,point.y))
	var horizontal := minf(smoothstep(left-9,left+9,point.x),1-smoothstep(right-14,right+9,point.x))
	var alpha := minf(vertical,horizontal)
	# These long, gently slanted furrows lead into the exterior. Their
	# width is several pixels, so 720p reduction does not create hard teeth.
	var left_fiber_y := 24+point.x*0.035+sin(point.x*0.025+seed)*2
	var left_fiber := (1-smoothstep(8,34,point.x))*(1-smoothstep(1.6,4.4,absf(point.y-left_fiber_y)))
	var right_fiber_y := paper_size.y*0.40+(point.x-body_right)*0.08+sin(point.x*0.022+seed)*2
	var right_fiber := smoothstep(body_right-9,paper_size.x-1,point.x)*(1-smoothstep(1.8,4.8,absf(point.y-right_fiber_y)))
	var lower_fiber_y := paper_size.y*0.74+(point.x-body_right)*0.03+sin(point.x*0.018+seed)*1.4
	var lower_fiber := smoothstep(body_right-18,paper_size.x-5,point.x)*(1-smoothstep(1.3,3.5,absf(point.y-lower_fiber_y)))
	alpha *= 1-0.84*maxf(left_fiber,maxf(right_fiber,lower_fiber))
	# Smoothly join guaranteed text and click support to the brush body.
	# These floors do not fill the Label's blank top/bottom padding.
	alpha = maxf(alpha,0.44*_trial_feathered_rect(point,hit_core,6))
	for ink in ink_regions: alpha = maxf(alpha,0.97*_trial_feathered_rect(point,ink,8))
	return clampf(alpha,0,1)

func _place_label(label: Label, rectangle: Rect2, font_size: int) -> void:
	label.add_theme_font_size_override("font_size",font_size)
	label.custom_minimum_size = Vector2.ZERO
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	label.clip_text = false
	label.position = rectangle.position
	label.size = rectangle.size

func _set_leaf(button: Button, entry: Dictionary, base_title: String, resource: String, key: String) -> void:
	button.set_meta("command_key",key)
	button.set_meta("trial_entry",entry.duplicate(true))
	button.set_meta("trial_resource",resource)
	button.set_meta("trial_full_name",str(entry.get("name",base_title)))
	button.get_node("Title").text = base_title
	button.get_node("Resource").text = resource
	button.get_node("Detail").text = _text(entry.get("full_summary",entry.get("summary","")))
	button.get_node("Reason").text = _reason_text(entry)
	button.get_node("IconSlot").call("configure",entry,key,button.disabled)
	var summary := _text(entry.get("full_summary",entry.get("summary","")))
	var reason := _reason_text(entry)
	button.set_meta("trial_full_tooltip","\n".join(_strings([entry.get("name",base_title),resource,summary,reason if not summary.contains(reason) else ""])))
	# 全文已由固定详情区与无障碍名称提供，避免原生浮窗遮住MP/CD和相邻纸片。
	button.tooltip_text = ""
	button.accessibility_name = str(entry.get("name",base_title))+" "+resource+" "+_reason_text(entry)

func _base_skill_name(entry: Dictionary) -> String:
	var id := str(entry.get("id",""))
	if SKILL_BASE_NAMES.has(id): return str(SKILL_BASE_NAMES[id])
	var provided := str(entry.get("base_name",""))
	if not provided.is_empty(): return provided
	if id.is_empty(): return ""
	if _trial_catalog == null:
		_trial_catalog = Catalog.new()
		_trial_catalog.call("load_all")
	var definition: Dictionary = _trial_catalog.call("get_definition","skills",id)
	return str(definition.get("name",entry.get("name","")))

func _skill_resource(entry: Dictionary) -> String:
	var cooldown := str(entry.get("cd_text",""))
	if cooldown.is_empty(): cooldown = "CD 0"
	return "MP %s  ·  %s" % [str(entry.get("mp_cost",0)),cooldown]

func _selected_entry() -> Dictionary:
	var id := str(_model.get("selected_ability_id",_model.get("selected_id","")))
	var kind := str(_model.get("selected_kind",""))
	if not id.is_empty():
		var entries: Array = _model.get("items",[]) if kind == "item" else _model.get("skills",[])
		for entry in entries:
			if entry is Dictionary and str(entry.get("id","")) == id:
				var result: Dictionary = entry.duplicate(true)
				result["selection_key"] = ("item:" if kind == "item" else "skill:")+id
				return result
	if not kind.is_empty():
		for entry in _model.get("basic_entries",[]):
			if entry is Dictionary and str(entry.get("kind","")) == kind:
				var result: Dictionary = entry.duplicate(true)
				result["selection_key"] = kind
				return result
	return _trial_last_entry.duplicate(true)

func _build_detail() -> void:
	_trial_detail = Control.new()
	_trial_detail.name = "TrialDetail"
	_trial_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_trial_detail.hide()
	add_child(_trial_detail)
	_trial_detail_title = _label(32)
	_trial_detail_title.name = "TrialDetailTitle"
	_trial_detail_title.add_theme_color_override("font_color",PAPER)
	_trial_detail.add_child(_trial_detail_title)
	_trial_detail_resource = _label(22)
	_trial_detail_resource.name = "TrialDetailResource"
	_trial_detail_resource.add_theme_color_override("font_color",PAPER)
	_trial_detail.add_child(_trial_detail_resource)
	_trial_detail_scroll = _scroll(_trial_detail)
	_trial_detail_scroll.name = "TrialDetailScroll"
	_trial_detail_body = _label(22)
	_trial_detail_body.name = "TrialDetailBody"
	_trial_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trial_detail_body.add_theme_color_override("font_color",PAPER)
	_trial_detail_scroll.add_child(_trial_detail_body)

func _trial_hover(button: Button, entered: bool) -> void:
	if entered: _trial_hover_button = button
	elif _trial_hover_button == button: _trial_hover_button = null
	_refresh_detail()

func _trial_focus(button: Button, entered: bool) -> void:
	if entered:
		_trial_hover_button = null
		_trial_focus_button = button
		if button.get_parent() == _item_content: _item_scroll.ensure_control_visible(button)
	elif _trial_focus_button == button: _trial_focus_button = null
	_refresh_detail()

func _refresh_detail() -> void:
	if not _built: return
	var active: Button
	if is_instance_valid(_trial_hover_button) and _trial_hover_button.is_visible_in_tree(): active = _trial_hover_button
	elif is_instance_valid(_trial_focus_button) and _trial_focus_button.is_visible_in_tree(): active = _trial_focus_button
	var entry: Dictionary = {}
	var resource := ""
	var key := ""
	if _page == "target":
		entry = _selected_entry()
		key = str(entry.get("selection_key",""))
		resource = _skill_resource(entry) if key.begins_with("skill:") else str(_model.get("cost_text",""))
	elif active != null:
		entry = active.get_meta("trial_entry",{})
		key = str(active.get_meta("command_key",""))
		resource = str(active.get_meta("trial_resource",""))
	else:
		for button in _all_buttons():
			if button == back_button or not button.is_visible_in_tree(): continue
			entry = button.get_meta("trial_entry",{})
			key = str(button.get_meta("command_key",""))
			resource = str(button.get_meta("trial_resource",""))
			break
	_trial_detail_selection_key = key
	var full_name := str(entry.get("name",""))
	var summary := _text(entry.get("full_summary",entry.get("summary","")))
	var reason := _reason_text(entry)
	if not reason.is_empty() and not summary.contains(reason): summary = summary+("\n" if not summary.is_empty() else "")+reason
	# 禁用原因在费用行直接可见；长说明仍保留全文滚动，不让原因埋到末尾。
	if not reason.is_empty() and Kit.font.get_string_size(resource+"  ·  "+reason,HORIZONTAL_ALIGNMENT_LEFT,-1,22).x <= 480:
		resource += ("  ·  " if not resource.is_empty() else "")+reason
	_trial_detail_title.text = full_name
	_trial_detail_resource.text = resource
	_trial_detail_body.text = summary
	_trial_detail.visible = not full_name.is_empty() and _page in ["commands","skills","items","target"]
	_place_label(_trial_detail_title,Rect2(0,0,480,46),32)
	_place_label(_trial_detail_resource,Rect2(0,52,480,32),22)
	_trial_detail_scroll.position = Vector2(0,90)
	_trial_detail_scroll.size = Vector2(480,112)
	_trial_detail_scroll.clip_contents = true
	# 透明详情区无纸内边距；50/32 行盒后正文 112px，全文可滚动。
	_trial_detail_body.position = Vector2.ZERO
	_trial_detail_body.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_trial_detail_body.clip_text = false
	_trial_detail_body.max_lines_visible = -1
	var flags := TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	var measured := Kit.font.get_multiline_string_size(summary,HORIZONTAL_ALIGNMENT_LEFT,460,22,-1,flags)
	var body_height := maxf(112,ceilf(measured.y)+4)
	_trial_detail_body.custom_minimum_size = Vector2(460,body_height)
	_trial_detail_body.size = Vector2(460,body_height)
	var signature := key+"\n"+full_name+"\n"+resource+"\n"+summary
	if signature != _trial_detail_signature:
		_trial_detail_scroll.scroll_vertical = 0
		_trial_detail_signature = signature
	for button in _all_buttons():
		var seal: Polygon2D = button.get_node_or_null("TrialFocusSeal")
		if seal == null: continue
		seal.position = Vector2(15,44)
		seal.visible = button.is_visible_in_tree() and str(button.get_meta("command_key","")) == key

func _leaf(key: String) -> Button:
	var button := TrialLeafButton.new()
	button.trial_menu = self
	button.set_meta("command_key",key)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.focus_mode = Control.FOCUS_NONE
	button.clip_contents = false
	button.custom_minimum_size = Vector2.ZERO
	for state in ["normal","hover","pressed","disabled","focus"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var backing := Polygon2D.new()
	backing.name = "TrialPaperBacking"
	backing.hide()
	button.add_child(backing)
	var paper := TextureRect.new()
	paper.name = "TrialBrushPaper"
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	button.add_child(paper)
	var icon: Control = SkillIcons.new()
	icon.name = "IconSlot"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	for label_name in ["Title","Resource","Detail","Reason"]:
		var label := _label(36 if label_name == "Title" else 22)
		label.name = label_name
		button.add_child(label)
	var seal := Polygon2D.new()
	seal.name = "TrialFocusSeal"
	seal.color = SEAL
	var points := PackedVector2Array()
	for part in 16: points.append(Vector2(cos(TAU*part/16),sin(TAU*part/16))*3.5)
	seal.polygon = points
	seal.hide()
	button.add_child(seal)
	button.mouse_entered.connect(_trial_hover.bind(button,true))
	button.mouse_exited.connect(_trial_hover.bind(button,false))
	button.focus_entered.connect(_trial_focus.bind(button,true))
	button.focus_exited.connect(_trial_focus.bind(button,false))
	return button

func _label(font_size: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font",Kit.font)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",INK)
	label.add_theme_constant_override("line_spacing",0)
	label.add_theme_constant_override("outline_size",0)
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	return label

func _scroll(parent: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.focus_mode = Control.FOCUS_NONE
	parent.add_child(scroll)
	return scroll

func _content(parent: Control) -> Control:
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(content)
	return content

func _hidden_panel(parent: Control, node_name: String) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	panel.hide()
	parent.add_child(panel)
	return panel

func _reason_text(entry: Dictionary) -> String:
	return " · ".join(_strings(entry.get("reasons",[])))

func _text(value: Variant) -> String:
	if value is Array or value is PackedStringArray:
		var lines := PackedStringArray()
		for line in value:
			if not str(line).is_empty(): lines.append(str(line))
		return "\n".join(lines)
	return str(value)

func _strings(values: Array) -> PackedStringArray:
	var result := PackedStringArray()
	for value in values:
		var text := _text(value)
		if not text.is_empty(): result.append(text)
	return result

# 只读原 PNG 创建纹理；不 resize、不保存源图、不使用九宫格。
func set_trial_paper_paths(normal_path: String, selected_path: String) -> void:
	trial_paper_normal_path = normal_path
	trial_paper_selected_path = selected_path
	_trial_textures.clear()
	_trial_images.clear()
	_trial_masked_textures.clear()
	_trial_masked_images.clear()
	_trial_mask_metrics.clear()
	if _built: _layout()

func _trial_texture(kind: String) -> Texture2D:
	if _trial_textures.has(kind): return _trial_textures[kind]
	var path := trial_paper_selected_path if kind == "selected" else trial_paper_normal_path
	var source: Image = Image.load_from_file(path)
	if source == null or source.is_empty():
		push_error("TRIAL_BRUSH_MISSING: "+path)
		return null
	_trial_images[kind] = source
	var texture := ImageTexture.create_from_image(source)
	_trial_textures[kind] = texture
	return texture

func _trial_paper_color(kind: String) -> Color:
	if not _trial_images.has(kind): return Color("F7F1DF")
	var source: Image = _trial_images[kind]
	var total := Vector3.ZERO
	var count := 0
	for row in 7:
		for column in 9:
			var x := clampi(roundi(source.get_width()*(.18+.08*column)),0,source.get_width()-1)
			var y := clampi(roundi(source.get_height()*(.20+.10*row)),0,source.get_height()-1)
			var color := source.get_pixel(x,y)
			if color.a < .85: continue
			total += Vector3(color.r,color.g,color.b)
			count += 1
	if count == 0: return Color("F7F1DF")
	total /= float(count)
	return Color(total.x,total.y,total.z,1)

func _trial_mask_alpha_at(button: Button, point: Vector2) -> float:
	var draw: Rect2 = button.get_meta("trial_paper_draw_rect",Rect2(Vector2.ZERO,button.size))
	var cache_key := str(button.get_meta("trial_mask_cache_key",""))
	if not draw.has_point(point) or not _trial_masked_images.has(cache_key): return 0.0
	var image: Image = _trial_masked_images[cache_key]
	var uv := (point-draw.position)/draw.size
	var x := clampi(floori(uv.x*image.get_width()),0,image.get_width()-1)
	var y := clampi(floori(uv.y*image.get_height()),0,image.get_height()-1)
	return image.get_pixel(x,y).a

func _trial_leaf_has_point(button: Button, point: Vector2) -> bool:
	var hit_core: Rect2 = button.get_meta("trial_hit_core_rect",Rect2())
	if hit_core.has_point(point): return true
	return _trial_mask_alpha_at(button,point) >= TRIAL_HIT_ALPHA

func _trial_point_diagnostics(button: Button) -> Dictionary:
	var core: Rect2 = button.get_meta("trial_hit_core_rect",Rect2())
	var quiet: Rect2 = button.get_meta("trial_quiet_text_core_rect",Rect2())
	var probes := {"hit_core_center":core.get_center(),"hit_core_top_left_inside":core.position+Vector2(0.5,0.5),"hit_core_bottom_right_inside":core.end-Vector2(0.5,0.5),"quiet_text_center":quiet.get_center(),"transparent_top_left":Vector2(0.5,0.5),"outside_right":Vector2(button.size.x+1,button.size.y*0.5)}
	var results := {}
	for key in probes:
		var point: Vector2 = probes[key]
		results[key] = {"local_point":point,"mask_alpha":_trial_mask_alpha_at(button,point),"accepted":bool(button.call("_has_point",point))}
	return results

func _label_diagnostics(label: Label) -> Dictionary:
	var font_size := label.get_theme_font_size("font_size")
	return {"text":label.text,"visible":label.is_visible_in_tree(),"rect":label.get_rect(),"global_rect":label.get_global_rect(),"font_size":font_size,"native_line_height":label.get_theme_font("font").get_height(font_size),"overrun_behavior":label.text_overrun_behavior,"clip_text":label.clip_text,"line_count":label.get_line_count()}

func trial_layout_diagnostics() -> Dictionary:
	var cards: Array[Dictionary] = []
	var paper_union := Rect2()
	var has_paper_union := false
	var occupied_union := Rect2()
	var has_occupied_union := false
	for occupied in occupied_rects():
		occupied_union = occupied_union.merge(occupied) if has_occupied_union else occupied
		has_occupied_union = true
	for button in _all_buttons():
		if button == back_button: continue
		var labels := {}
		for label_name in ["Title","Resource","Detail","Reason"]: labels[label_name] = _label_diagnostics(button.get_node(label_name))
		var visual: Rect2 = button.get_meta("trial_visual_rect",Rect2())
		var global_visual := Rect2(button.global_position+visual.position,visual.size)
		if _item_scroll.is_ancestor_of(button): global_visual = global_visual.intersection(_item_scroll.get_global_rect())
		if button.is_visible_in_tree() and global_visual.has_area():
			paper_union = paper_union.merge(global_visual) if has_paper_union else global_visual
			has_paper_union = true
		var quiet: Rect2 = button.get_meta("trial_quiet_text_core_rect",Rect2())
		var hit_core: Rect2 = button.get_meta("trial_hit_core_rect",Rect2())
		var physical_hit_size := hit_core.size*TRIAL_720_SCALE
		var cache_key := str(button.get_meta("trial_mask_cache_key",""))
		cards.append({
			"command_key":button.get_meta("command_key",""),"ability_id":button.get_meta("ability_id",""),
			"visible":button.is_visible_in_tree(),"disabled":button.disabled,
			"requested_global_rect":button.get_meta("trial_requested_frame",Rect2()),"actual_global_rect":button.get_global_rect(),
			"paper_draw_rect":button.get_meta("trial_paper_draw_rect",Rect2()),"paper_visual_rect":visual,"paper_visual_global_rect":global_visual,
			"quiet_text_core_rect":quiet,"quiet_text_core_global_rect":Rect2(button.global_position+quiet.position,quiet.size),
			"glyph_ink_regions":button.get_meta("trial_glyph_ink_regions",[]),
			"hit_core_rect":hit_core,"physical_hit_core_size_at_720":physical_hit_size,
			"physical_min_hit_dimension_at_720":minf(physical_hit_size.x,physical_hit_size.y),
			"physical_hit_core_meets_44px_at_720":minf(physical_hit_size.x,physical_hit_size.y)>=44,
			"alpha_edge_metrics":_trial_mask_metrics.get(cache_key,{}),"point_semantics":_trial_point_diagnostics(button),
			"content_left_padding":button.get_meta("trial_requested_title_rect",Rect2()).position.x,"content_right_padding":button.get_meta("trial_requested_content_right_padding",0),
			"missing_ink_icon":button.get_meta("trial_missing_icon",false),"icon_slot_draws_nothing":not button.get_node("IconSlot").visible,"icon_slot_hidden":not button.get_node("IconSlot").visible,
			"icon":button.get_node("IconSlot").call("diagnostic_snapshot"),"icon_rect":button.get_node("IconSlot").get_rect(),
			"old_opaque_backing_visible":button.get_node("TrialPaperBacking").visible,"labels":labels,"tooltip":button.get_meta("trial_full_tooltip",""),"native_tooltip_enabled":not button.tooltip_text.is_empty()})
	return {
		"trial_only":true,"version":5,"source_revision":"8a3839716a1f05251057844c3016391a7b0cdadc",
		"visual_acceptance":"requires rendered review; perimeter erasure percentage is not visual acceptance","mask_revision":"v4-soft-runs-02","page":_page,
		"normal_brush":trial_paper_normal_path,"selected_brush":trial_paper_selected_path,"new_brushes_loaded":_trial_textures.size()==2,
		"paper_resampled":true,"paper_mask_generated_at_draw_size":true,"source_brush_rgb_sampled_for_grain":true,"source_alpha_drives_hit_test":false,
		"paper_nine_slice":false,"missing_ink_icons":false,"cards":cards,
		"menu_paper_union_bounds":paper_union,"menu_union_bounds_including_detail_and_back":occupied_union,
		"selection_key":_trial_detail_selection_key,"detail_rect":_trial_detail.get_global_rect(),"detail_visible":_trial_detail.is_visible_in_tree(),
		"detail_title":_label_diagnostics(_trial_detail_title),"detail_resource":_label_diagnostics(_trial_detail_resource),"detail_body":_label_diagnostics(_trial_detail_body),
		"detail_scroll_rect":_trial_detail_scroll.get_global_rect(),"detail_scroll_vertical":_trial_detail_scroll.scroll_vertical,
		"detail_body_full_text":_trial_detail_body.text,"detail_body_visible":_trial_detail_body.is_visible_in_tree(),
		"oldpanels_visible":{"header":_header.is_visible_in_tree(),"header_paper":_header_paper.is_visible_in_tree(),"target_paper":_target_paper.is_visible_in_tree()},
		"item_scroll_rect":_item_scroll.get_global_rect(),"item_scroll_vertical":_item_scroll.scroll_vertical,"item_content_size":_item_content.size,
		"back_text":back_button.text,"back_rect":back_button.get_global_rect(),"back_visible":back_button.is_visible_in_tree()}
