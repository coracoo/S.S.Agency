extends Node3D
## 第一幕的独立美术检查器。只切镜头/显示，不连接探索、线索或战斗状态。

@onready var hero: Camera3D = $Cameras/Hero
@onready var inspection: Camera3D = $Cameras/Inspection
@onready var character: Sprite3D = $CharacterReference
@onready var hud: CanvasLayer = $PreviewHUD
@onready var hero_button: Button = $PreviewHUD/Margin/Stack/Controls/Hero
@onready var inspection_button: Button = $PreviewHUD/Margin/Stack/Controls/Inspection
@onready var character_button: Button = $PreviewHUD/Margin/Stack/Controls/Character

func _ready() -> void:
	hero.look_at(Vector3(0.6, 3.2, 0.0))
	inspection.look_at(Vector3(1.0, 1.9, 0.0))
	hero_button.pressed.connect(show_view.bind(false))
	inspection_button.pressed.connect(show_view.bind(true))
	character_button.pressed.connect(toggle_character)
	reset_preview()

func show_view(use_inspection: bool) -> void:
	if use_inspection:
		inspection.make_current()
	else:
		hero.make_current()
	hero_button.set_pressed_no_signal(not use_inspection)
	inspection_button.set_pressed_no_signal(use_inspection)

func toggle_character() -> void:
	character.visible = not character.visible
	character_button.set_pressed_no_signal(character.visible)

func toggle_hud() -> void:
	hud.visible = not hud.visible

func reset_preview() -> void:
	show_view(false)
	character.visible = false
	character_button.set_pressed_no_signal(false)
	hud.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			show_view(false)
		KEY_2:
			show_view(true)
		KEY_C:
			toggle_character()
		KEY_H:
			toggle_hud()
		KEY_R:
			reset_preview()
		KEY_ESCAPE:
			get_tree().quit()
		_:
			return
	get_viewport().set_input_as_handled()
