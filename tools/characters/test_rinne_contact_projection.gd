# 真实BattleView+注册候选：在M读取实际3D木剑端/躯干投影，拒绝仅代理或全身框相交。
extends SceneTree
const F=preload("res://tools/rpg/fixtures.gd")
const Battle=preload("res://scripts/rpg/battle_engine.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
const Contacts=preload("res://scripts/characters/melee_contact_points.gd")
const Fixture=preload("res://tools/characters/test_imagegen_battle_view.gd").Fixture
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1" or OS.get_environment("RINNE_CANDIDATE_MANIFEST").is_empty():quit(2);return
	for side in ["right","left"]:await _case(side)
	print("RINNE_CONTACT_PROJECTION: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _case(side:String)->void:
	var source:=F.actor("swordsman","source");source["identity_id"]="rinne";source["form_id"]="rinne";source.stats.spd=999
	var enemy:=F.enemy("hound","target");enemy.stats.hp=5000;enemy.hp=5000
	var engine:=Battle.new();var started:=engine.start({"actors":{"source":source,"target":enemy},"inventory":{}},112)
	check(started.started,"真实引擎初始化："+str(started))
	if not started.started:return
	engine.advance(false)
	var view:=Fixture.new();view.definition=Definition.load_definition(OS.get_environment("RINNE_CANDIDATE_MANIFEST"),"battle");view.engine=engine;view._config.near_side=side;root.add_child(view)
	var actor:Node2D=view._actors.source.sprite;var target:Node2D=view._actors.target.sprite
	var contact:Dictionary=Contacts.resolve(view.definition)
	var packed:Dictionary=view.definition.manifest.packed_frames.attack_clean_030
	var atlas:=Image.load_from_file(packed.atlas)
	var sample:Vector2i=Vector2i(contact.logical_point)-Vector2i(packed.offset[0],packed.offset[1])+Vector2i(packed.region[0],packed.region[1])
	check(atlas.get_pixelv(sample).a>.8,"刃内接触点确实位于实际M帧木剑可见像素")
	var home:Vector2=actor.position;var committed:=engine.snapshot()
	check(actor.begin_melee_approach(target),"已验多姿势dash接近")
	actor._process(.2);actor.play_action(&"attack");actor.animator.sprite.set_frame_and_progress(17,0);view._world_backdrop.sync_visuals(0)
	var body:Sprite3D=view._world_backdrop.actor_entries.source.body;var camera:Camera3D=view._world_backdrop.camera
	var right:=Vector3(camera.global_basis.x.x,0,camera.global_basis.x.z).normalized()
	# 独立原生量测的木剑尖与M躯干参考，不复用站距profile的刃内接触点。
	var tip:=Vector2(1561.175,1403.074)-Vector2(1024,1442)
	var chest:=Vector2(1220,1120)-Vector2(1024,1442)
	if body.flip_h:tip.x=-tip.x;chest.x=-chest.x
	var projected_tip:=camera.unproject_position(body.global_position+(right*tip.x-Vector3.UP*tip.y)*body.pixel_size)
	var projected_chest:=camera.unproject_position(body.global_position+(right*chest.x-Vector3.UP*chest.y)*body.pixel_size)
	print("RINNE_CONTACT_MEASURE:",JSON.stringify({"side":side,"foot":[actor.position.x,actor.position.y],"tip":[projected_tip.x,projected_tip.y],"chest":[projected_chest.x,projected_chest.y],"target":[target.position.x,target.position.y]}))
	check(absf(projected_tip.x-target.position.x)<70,"木剑端到达目标可见范围，不越到敌后很远")
	check(absf(projected_chest.x-target.position.x)>120,"真实躯干与敌方身体分开，不能互穿")
	var destination:Vector2=actor.position
	actor.animator.position+=Vector2(900,900);view._world_backdrop.sync_visuals(0)
	check(actor.position==destination and camera.unproject_position(body.global_position).distance_to(destination)<.02,"隐藏代理偏移不改变实际站距/3D脚根")
	actor.cancel_action();view._world_backdrop.cancel_trails()
	check(actor.position.is_equal_approx(home) and not actor.is_melee_moving(),"新站距取消仍精确归home")
	check(engine.snapshot()==committed,"表现站距不更改规则模型")
	var unqualified:=view.definition.duplicate(true);unqualified.manifest.anims.attack.clean_body=false
	actor.configure(unqualified,319.2,1);view._world_backdrop.sync_visuals(0)
	check(actor._melee_contact_reach_px<0 and not actor.has_meta("melee_contact_profile"),"重绑即使复用SpriteFrames，缺少资格也清除旧接触点")
	view.free()
