extends SceneTree
func _initialize() -> void: call_deferred('run')
func run() -> void:
	var actor=load('res://scripts/characters/pixel_character_world.gd').new();root.add_child(actor)
	actor.set_physics_process(false)
	var original_material=actor.billboard.material_override
	var original_shadow=actor.shadow.visible
	var helper=load('res://scripts/characters/character_scene_integration.gd').new();actor.add_child(helper)
	helper.attach_to(actor);helper.set_enabled(true)
	helper.queue_free();await process_frame
	var ok=actor.billboard.material_override==original_material and actor.shadow.visible==original_shadow
	print(('PASS: ' if ok else 'FAIL: ')+'单独释放helper不遗留批准材质或隐藏基线阴影')
	actor.queue_free();await process_frame
	quit(0 if ok else 1)
