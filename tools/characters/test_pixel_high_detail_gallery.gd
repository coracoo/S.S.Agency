extends SceneTree
var failed:=0
func check(value:bool,message:String)->void:
	print(('PASS: ' if value else 'FAIL: ')+message)
	if not value:failed+=1
func _initialize()->void:call_deferred('run')
func run()->void:
	var path='res://scenes/preview/friendly_high_detail_gallery.tscn'
	check(FileAccess.file_exists(path),'高细节七形态有独立检视入口')
	if not FileAccess.file_exists(path):quit(1);return
	var scene=load(path).instantiate();root.add_child(scene)
	scene.actor.set_input_enabled(false);scene.actor.set_physics_process(false)
	await process_frame
	check(scene.actor.form_id=='guard' and scene.actor.animator.definition.manifest.canvas.content_height_px==1024,'默认选中已核验岑照1024身体源')
	check(scene.actor.scene_integration!=null and scene.actor.scene_integration.enabled,'新入口启用批准融合，旧入口默认不改')
	var helper=scene.actor.scene_integration
	scene._select_roster_form('mint');await process_frame
	check(scene.actor.form_id=='mint' and scene.actor.scene_integration==helper,'切换薄荷仍使用同一演员与融合helper')
	check(scene.actor.scene_integration.contact_mode=='annotated','薄荷自动切到自己的脚点数据')
	var roster:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(scene.roster_path))
	var ids:={};var identities:={}
	for form in roster.forms:ids[form.id]=true;identities[form.identity_id]=true
	check(ids.size()==7 and identities.size()==6,'七个形态属于六个身份')
	scene.queue_free();await process_frame
	print('HIGH_DETAIL_GALLERY_RESULT: ',failed);quit(1 if failed else 0)
