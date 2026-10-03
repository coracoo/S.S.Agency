extends SceneTree
func _initialize() -> void: call_deferred('run')
func run() -> void:
	var actor=load('res://scripts/characters/pixel_character_world.gd').new();root.add_child(actor);actor.set_physics_process(false)
	actor.select_manifest('guard','res://assets/chars/pixel/guard/high_detail_complete/manifest.json');actor.animator.set_process(false)
	var helper=load('res://scripts/characters/character_scene_integration.gd').new();actor.add_child(helper);helper.attach_to(actor)
	actor.animator.definition.manifest['scene_integration']={'contact_metadata':'res://does_not_exist.json'}
	helper.current_contact_specs()
	var ok=helper.contact_mode=='root_fallback'
	print(('PASS: ' if ok else 'FAIL: ')+'manifest指定文件优先；缺失文件安全根部柔影，不退用别的角色标注')
	actor.queue_free();await process_frame;quit(0 if ok else 1)
