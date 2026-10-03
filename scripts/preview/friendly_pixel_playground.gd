extends Node3D
## 独立角色验收，不改变旧预览或正式游戏入口。
@export var use_delivery_roster := false
@export var roster_path := 'res://assets/chars/pixel/roster.json'
@export var initial_form := 'rinne'
@export var use_approved_scene_integration := false
const World = preload('res://scripts/characters/pixel_character_world.gd')
var actor
var stage
var _label := Label.new()
var _panel := CanvasLayer.new()
var _selection_note := ''

func _ready() -> void:
	stage = preload('res://scenes/preview/act01_approach_3d.tscn').instantiate()
	add_child(stage)
	stage.hud.visible = false
	stage.set_process_unhandled_key_input(false)
	_add_floor(Vector3(-4.8, -0.07, 0), Vector3(10.4, 0.2, 3), 0)
	# 16阶视觉对应连续坡面代理，台阶不直接阻挡胶囊。
	_add_floor(Vector3(3.658, 1.3686, 0), Vector3(7.042, 0.2, 3), -atan2(2.86, 6.435))
	_add_floor(Vector3(8.92, 2.79, 0), Vector3(4.2, 0.2, 3), 0)
	_add_floor(Vector3(-10.3, 2, 0), Vector3(0.2, 6, 3), 0)
	_add_floor(Vector3(10.3, 4, 0), Vector3(0.2, 6, 3), 0)
	actor = World.new()
	actor.name = 'PlayableCharacter'
	actor.position = Vector3(-3.0, 0.2, 0)
	add_child(actor)
	_build_hud()
	if use_delivery_roster:
		_select_roster_form(initial_form)
		actor.position = Vector3(-4.5,0.05,1.1)
		stage.hero.size = 4.7
		var foreground=stage.get_node('Model').find_child('50_Path_Boundary_Front',true,false)
		if foreground is Node3D: foreground.visible=false


func _add_floor(location: Vector3, size: Vector3, angle: float) -> void:
	var body := StaticBody3D.new()
	body.position = location
	body.rotation.z = -angle
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)

func _build_hud() -> void:
	add_child(_panel)
	var box := VBoxContainer.new()
	box.position = Vector2(22, 20)
	_panel.add_child(box)
	box.add_theme_font_override('font', load('res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf'))
	_label.add_theme_font_size_override('font_size', 21)
	box.add_child(_label)
	var row := HBoxContainer.new()
	box.add_child(row)
	for pair in [['原动作基线', 'legacy_rinne'], ['凛音', 'rinne'], ['焰华·剑', 'homura_sword'], ['焰华·术', 'homura_mage'], ['薄荷', 'mint'], ['岑照', 'guard'], ['苏合', 'healer'], ['清明', 'controller']]:
		if use_delivery_roster and pair[1]=='legacy_rinne': continue
		var button := Button.new()
		button.text = pair[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_roster_form.bind(pair[1]))
		row.add_child(button)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	for state in ['attack', 'hit', 'defend', 'down', 'recover']:
		var button := Button.new()
		button.text = {'attack':'出招','hit':'受击','defend':'防御','down':'失能','recover':'恢复'}.get(state,state) if use_delivery_roster else state
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(actor.animator.request_action.bind(state))
		actions.add_child(button)

func _select_roster_form(id: String) -> void:
	if use_delivery_roster:
		var roster: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(roster_path))
		for form in roster.forms:
			if form.id == id:
				if not actor.select_manifest(id,form.manifest):
					_selection_note='该形态素材尚未就绪。'
					return
				_selection_note=str(form.get('costume_note',''))
				if use_approved_scene_integration: actor.enable_scene_integration(stage)
				return
	actor.select_form(id)

func _process(_delta: float) -> void:
	if use_delivery_roster:
		stage.hero.position=actor.global_position+Vector3(0,2.2,8)
		stage.hero.look_at(actor.global_position+Vector3(0,0.85,0))
		var names={'rinne':'凛音','homura_sword':'焰华 · 剑','homura_mage':'焰华 · 术','mint':'薄荷','guard':'岑照','healer':'苏合','controller':'清明'}
		var states={'idle':'待机','walk':'行走','attack':'出招','hit':'受击','defend':'防御','down':'失能','recover':'恢复'}
		_label.text='友方像素角色 | A/D行走 · J出招 · 1/2镜头 · H面板 · R重置\n%s · %s' % [names.get(actor.form_id,actor.form_id),states.get(str(actor.animator.sprite.animation),str(actor.animator.sprite.animation))]
		if not _selection_note.is_empty():_label.text+='\n'+_selection_note
		return
	_label.text = '友方动画验收 | A/D 左右行走 · J 出招 · 1/2 镜头 · H 面板 · R 重置\n%s | %s:%d | %s' % [actor.form_id, actor.animator.sprite.animation, actor.animator.sprite.frame, actor.warning]

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1: stage.show_view(false)
		KEY_2: stage.show_view(true)
		KEY_H: _panel.visible = not _panel.visible
		KEY_R:
			actor.position = Vector3(-4.5,0.05,1.1) if use_delivery_roster else Vector3(-3,0.2,0)
			actor.velocity = Vector3.ZERO
			actor.animator.reset()
			stage.show_view(false)
		KEY_ESCAPE: get_tree().quit()
