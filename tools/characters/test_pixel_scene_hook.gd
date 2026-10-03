extends SceneTree
var failed:=0
func check(value:bool,message:String)->void:
	print(('PASS: ' if value else 'FAIL: ')+message)
	if not value:failed+=1
func _initialize()->void:call_deferred('run')
func run()->void:
	var actor=load('res://scripts/characters/pixel_character_world.gd').new()
	root.add_child(actor);actor.set_physics_process(false)
	check(actor.has_method('enable_scene_integration'),'共享角色提供显式可逆融合入口')
	if not actor.has_method('enable_scene_integration'):actor.queue_free();quit(1);return
	var baseline=actor.billboard.material_override
	var texture_rid=actor.animator.sprite.sprite_frames.get_frame_texture('idle',0).get_rid()
	check(actor.scene_integration==null,'默认不改变旧角色基线材质')
	check(actor.enable_scene_integration(),'批准融合profile可显式启用')
	var helper=actor.scene_integration
	check(actor.billboard.material_override!=baseline,'显式启用后采用融合材质')
	check(actor.enable_scene_integration() and actor.scene_integration==helper,'重复启用不会添加多个helper')
	actor.disable_scene_integration()
	check(actor.billboard.material_override==baseline,'禁用恢复原始材质')
	check(actor.animator.sprite.sprite_frames.get_frame_texture('idle',0).get_rid()==texture_rid,'启停融合不修改原帧纹理')
	check(actor.enable_scene_integration(),'可重新启用')
	check(actor.select_manifest('guard','res://assets/chars/pixel/guard/high_detail_pilot/manifest.json'),'融合开启时可按需换高细节形态')
	await process_frame
	check(actor.scene_integration==helper,'换形态复用同一helper')
	actor.disable_scene_integration()
	actor.scene_integration.queue_free()
	await process_frame
	check(actor.enable_scene_integration(),'helper单独释放后可以重新启用')
	actor.disable_scene_integration()
	actor.queue_free();await process_frame
	print('SCENE_HOOK_RESULT: ',failed)
	quit(1 if failed else 0)
