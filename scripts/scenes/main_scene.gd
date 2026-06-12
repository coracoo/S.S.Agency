extends Node2D

func _ready() -> void:
	# Preload card data
	Card.load_cards()
	UnitFactory.load_templates()
	StatusEffectManager.load_defs()
	get_viewport().size_changed.connect(_layout_title_screen)

	$Title.text = "GODNOT"
	$Subtitle.text = "- 凛音 · 薄荷 · 焰华 -"
	$ClickLabel.text = "Click to start"
	_layout_title_screen()

func _layout_title_screen() -> void:
	var view_size = get_viewport_rect().size
	$ColorRect.size = view_size
	$Title.position = Vector2(view_size.x * 0.5 - 250.0, view_size.y * 0.5 - 100.0)
	$Title.size = Vector2(500, 60)
	$Subtitle.position = Vector2(view_size.x * 0.5 - 220.0, view_size.y * 0.5 - 28.0)
	$Subtitle.size = Vector2(440, 30)
	$ClickLabel.position = Vector2(view_size.x * 0.5 - 120.0, view_size.y * 0.5 + 54.0)
	$ClickLabel.size = Vector2(240, 30)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		start_battle()

func start_battle() -> void:
	var battle = load("res://scenes/battle.tscn").instantiate()
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	queue_free()
