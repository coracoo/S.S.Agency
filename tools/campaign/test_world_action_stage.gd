# Real node/physics tests for run, hop and environmental state presentation.
extends SceneTree
const SaveBase = preload("res://scripts/rpg/save_store.gd")
class FaultStore extends SaveBase:
	var fail_write := false
	func _replace_file(temporary: String, destination: String) -> Error:
		return ERR_FILE_CANT_WRITE if fail_write else super._replace_file(temporary,destination)
const Player = preload("res://scripts/exploration_3d/player_controller.gd")
const Objects = preload("res://scripts/campaign/world_object_catalog.gd")
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message); printerr("ASSERT FAIL: ",message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _definition() -> Dictionary:
	var frames := SpriteFrames.new(); frames.remove_animation("default")
	var image := Image.create(8,16,false,Image.FORMAT_RGBA8); image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	for action in ["idle","walk","run","jump","interact","pickup"]:
		frames.add_animation(action); frames.set_animation_speed(action,10); frames.set_animation_loop(action,action in ["idle","walk","run"])
		for index in 6: frames.add_frame(action,texture)
	return {"ok":true,"frames":frames,"manifest":{"canvas":{"w":8,"h":16,"anchor":[4,16],"height_m":1.6,"content_height_px":16},"move_speed_mps":2.6,"run_speed_mps":4.2,"mirror_allowed":true,"anims":{"pickup":{"events":{"pickup":200}},"interact":{"events":{"interact":200}},"jump":{"vertical_motion_baked":false}}}}
func _run() -> void:
	var player := Player.new()
	check(player.has_method("set_run_input") and player.has_method("request_jump"),"run and jump controller API exists")
	check(ResourceLoader.exists("res://scripts/campaign/world_object_layer.gd"),"visible object layer exists")
	if not player.has_method("request_jump") or not ResourceLoader.exists("res://scripts/campaign/world_object_layer.gd"):
		player.free(); _finish(); return
	var stage_script: Script = load("res://scripts/campaign/chapter_stage.gd")
	stage_script._register_input()
	for action in ["approach_run","approach_jump","approach_lead"]: check(InputMap.has_action(action),"registered input " + action)
	var floor_body := StaticBody3D.new(); var floor_shape := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size=Vector3(50,.2,50)
	floor_shape.shape=box; floor_shape.position.y=-.1; floor_body.add_child(floor_shape); root.add_child(floor_body)
	InputMap.erase_action("approach_run"); InputMap.erase_action("approach_jump")
	player.shared_definition=_definition(); root.add_child(player); player.position=Vector3(0,.01,0); player.set_move_input(Vector2.ZERO)
	check(InputMap.has_action("approach_run") and InputMap.has_action("approach_jump"),"standalone controller registers own new actions for legacy exploration")
	for frame in 4: await physics_frame
	var start := player.position
	player.set_move_input(Vector2.RIGHT)
	for frame in 30: await physics_frame
	var walking := player.position.x-start.x
	player.set_run_input(true); start=player.position
	for frame in 30: await physics_frame
	var running := player.position.x-start.x
	check(running > walking*1.45 and running < walking*1.8,"run movement uses honest faster physical displacement")
	check(player.animator.sprite.animation == &"run","actual running selects run animation")
	player.set_move_input(Vector2.ZERO); player.set_run_input(false)
	for frame in 3: await physics_frame
	start=player.position
	check(player.request_jump(),"grounded hop starts")
	check(not player.request_jump(),"duplicate jump ignored")
	var max_visual_height := 0.0
	for frame in 16:
		await physics_frame
		max_visual_height=maxf(max_visual_height,player.billboard.position.y)
	check(max_visual_height>.25,"jump visibly lifts the character")
	check(absf(player.position.y-start.y)<.03 and Vector2(player.position.x-start.x,player.position.z-start.z).length()<.01,"hop keeps navigation capsule grounded and stationary")
	player.set_control_enabled(false)
	check(not player.request_jump() and player.billboard.position.y==0,"menu cancels hop and cannot jump under lock")
	player.set_move_input(Vector2.RIGHT); player.set_run_input(true); start=player.position
	for frame in 5: await physics_frame
	check(player.position.distance_to(start)<.03,"locked controls ignore run and movement")
	player.set_control_enabled(true); player.set_move_input(Vector2.ZERO)
	player.animator.definition.manifest.anims.jump.vertical_motion_baked=true
	for frame in 3: await physics_frame
	check(player.request_jump(),"native baked jump starts")
	for frame in 12: await physics_frame
	check(player.billboard.position.y==0 and player.animator.sprite.animation==&"jump","native jump uses source vertical motion without duplicate billboard lift")
	for frame in 35: await physics_frame
	check(player.billboard.position.y==0 and player._hop_duration==0,"native jump ends on exact grounded baseline")
	player.keyboard_input=true
	for action in ["approach_left","approach_right","approach_run","approach_jump"]: Input.action_press(action)
	player.set_control_enabled(false); player.set_control_enabled(true); start=player.position
	for frame in 6: await physics_frame
	check(player.position.distance_to(start)<.03 and not player.request_jump(),"opposite movement plus held run/jump cannot leak through menu close")
	for action in ["approach_left","approach_right","approach_run","approach_jump"]: Input.action_release(action)
	for frame in 3: await physics_frame
	Input.action_press("approach_right"); start=player.position
	for frame in 6: await physics_frame
	check(player.position.x>start.x+.15,"all-keys release rearms keyboard movement")
	Input.action_release("approach_right")
	player.free(); floor_body.free()
	await _test_props()
	await _test_placements()
	await _test_stage_transactions()
	_finish()
func _test_props() -> void:
	var script: Script=load("res://scripts/campaign/world_object_layer.gd")
	var layer: Node3D=script.new(); root.add_child(layer)
	layer.configure(1,{})
	await physics_frame; await physics_frame
	var door: Node3D=layer.object_node("temple_mirror_door")
	check(door!=null and door.find_child("DoorLeaf",true,false)!=null,"registered door has visible hinged leaf")
	var at:=Vector3(37.02,2.89,-12.3)
	var ray:=PhysicsRayQueryParameters3D.create(at+Vector3(-1,1,0),at+Vector3(1,1,0))
	check(not layer.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"closed door has real collision")
	check(layer.object_node("temple_approach_bundle").visible,"uncollected bundle visibly present")
	layer.apply_state({"temple_mirror_door":true,"temple_approach_bundle":true},true)
	for frame in 60: await physics_frame
	check(layer.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(),"opened door removes blocking collision")
	check(absf(door.get_node("Hinge").rotation.y)>1.3,"door opening visibly rotates hinge")
	check(not layer.object_node("temple_approach_bundle").visible,"consumed bundle hidden")
	layer.configure(2,{"temple_mirror_door":true,"temple_approach_bundle":true})
	check(not layer.object_node("temple_approach_bundle").visible,"same temple object stays consumed across night change")
	layer.free()
func _test_placements() -> void:
	var capsule:=CapsuleShape3D.new(); capsule.radius=.22; capsule.height=1.4
	var query:=PhysicsShapeQueryParameters3D.new(); query.shape=capsule
	for chapter in range(1,8):
		var geometry: Node3D=load("res://scripts/campaign/act_one_geometry.gd").build({}) if chapter==1 else load("res://scripts/campaign/saga_world.gd").build(chapter)
		root.add_child(geometry)
		await physics_frame; await physics_frame
		var space:=geometry.get_world_3d().direct_space_state
		for entry in Objects.for_night(1 if chapter==1 else chapter+4):
			var at:=Vector3(entry.position[0],entry.position[1],entry.position[2])
			var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*.4,at-Vector3.UP*.4))
			check(not hit.is_empty() and hit.normal.y>.8,"object has real ground " + str(entry.id))
			query.transform.origin=at+Vector3.UP*.75
			check(space.intersect_shape(query).is_empty(),"object placement is not inside existing scenery " + str(entry.id))
		geometry.free()
func _finish() -> void:
	print("WORLD_ACTION_STAGE_ASSERTIONS:",assertions," FAILURES:",failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_stage_transactions() -> void:
	var Session: Script=load("res://scripts/campaign/chapter_session.gd")
	var session: RefCounted=Session.new()
	check(session.start_new(true).ok,"stage integration uses isolated formal session")
	check(session.commit_event(session.campaign.safe_snapshot().world,"dialogue:a1").ok,"initial dialogue precommitted for runtime test")
	for identity in ["rinne","mint","guard"]:
		var definition:=_definition()
		definition.manifest["identity_id"]=identity; definition.manifest["form_id"]=identity
		session.bundle._definitions[identity]=definition
		session.bundle._bindings["p_"+{"rinne":"swordsman","mint":"ranger","guard":"guard"}[identity]]={"identity_id":identity,"form_id":identity}
	var stage: Node3D=load("res://scripts/campaign/chapter_stage.gd").new()
	root.add_child(stage)
	for frame in 90:
		await physics_frame
		if stage.ready_for_play: break
	check(stage.ready_for_play,"real first chapter stage enters exploration")
	if not stage.ready_for_play: stage.free(); session.close(); return
	check(stage.exploration_leads().size()==3,"current selected party exposes three loaded visual leads")
	var before: Dictionary=session.campaign.safe_snapshot()
	stage._lead_armed=true
	check(stage._cycle_exploration_lead() and stage.player.form_id=="mint","Tab changes exploration actor to next selected party member")
	check(not stage._cycle_exploration_lead(),"held Tab cannot cycle twice")
	check(session.campaign.safe_snapshot()==before,"visual lead switching never mutates battle party or story")
	var pickup: Dictionary=Objects.get_object("temple_approach_bundle")
	stage.player.position=Vector3(pickup.position[0],pickup.position[1],pickup.position[2]) + Vector3(.6,0,0)
	stage.player.velocity=Vector3.ZERO; stage.player.set_move_input(Vector2.ZERO)
	for frame in 4: await physics_frame
	stage._confirm_armed=true
	check(stage.request_interaction(str(pickup.id)),"real E target starts pickup animation")
	check(stage.player.facing==-1,"pickup reach faces target on camera-left")
	check(not stage.request_interaction(str(pickup.id)),"duplicate E blocked during pickup")
	check(session.campaign.safe_snapshot()==before,"before contact marker reward is not issued")
	for frame in 50: await physics_frame
	check(session.campaign.safe_snapshot().get("world_objects",{}).get(pickup.id,false),"contact marker commits pickup")
	check(stage.controls_enabled and stage._mode=="explore","pickup recovery restores exploration control")
	check(not stage._world_object_layer.object_node(str(pickup.id)).visible,"committed pickup disappears from real stage")
	check(stage.interaction_dispatch(str(pickup.id)).is_empty(),"consumed pickup leaves target list")
	var store:=FaultStore.new(); session.campaign._store=store
	var door: Dictionary=Objects.get_object("temple_mirror_door")
	stage.player.position=Vector3(door.position[0]-1.05,door.position[1],door.position[2]); stage.player.velocity=Vector3.ZERO
	stage.player.set_move_input(Vector2.ZERO)
	for frame in 4: await physics_frame
	store.fail_write=true; stage._confirm_armed=true
	check(stage.request_interaction(str(door.id)),"door action starts before injected commit failure")
	check(stage.player.facing==1,"door reach faces target on camera-right")
	for frame in 40: await physics_frame
	check(stage._mode=="error" and not stage.controls_enabled,"failed save holds menu/control lock for retry")
	check(not session.campaign.safe_snapshot().world_objects.has(door.id),"failed door never persists opened state")
	check(not stage._world_object_layer.object_node(str(door.id)).get_node("DoorCollision/Shape").disabled,"failed door keeps real blocking collision")
	store.fail_write=false; stage._retry_world_object(str(door.id))
	for frame in 50: await physics_frame
	check(stage.controls_enabled and session.campaign.safe_snapshot().world_objects.get(door.id,false),"same door retry completes safe transaction and unlocks controls")
	var untouched: Dictionary=Objects.get_object("temple_courtyard_bundle")
	stage.player.position=Vector3(untouched.position[0],untouched.position[1],untouched.position[2])
	stage.player.velocity=Vector3.ZERO; stage.player.set_move_input(Vector2.ZERO)
	for frame in 3: await physics_frame
	stage._confirm_armed=true
	check(stage.request_interaction(str(untouched.id)),"second pickup can start")
	stage.shutdown()
	for frame in 30: await physics_frame
	check(not session.campaign.safe_snapshot().get("world_objects",{}).has(untouched.id),"scene shutdown before contact invalidates old action callback")
	stage.free()
	await _test_later_stage(session)
	session.close()

func _test_later_stage(session: RefCounted) -> void:
	var Fixture: Script=load("res://tools/campaign/world_action_fixture.gd")
	check(Fixture.complete_first(session.campaign) and session.campaign.continue_saga().ok,"stage fixture reaches existing second chapter")
	var party: Array[String]=["p_mage","p_healer","p_controller"]
	check(session.campaign.set_party(party).ok,"existing party menu transaction selects remaining identities")
	for key in ["homura_sword","homura_mage","healer","controller"]:
		var definition:=_definition()
		var identity: String="homura" if key.begins_with("homura_") else key
		definition.manifest["identity_id"]=identity; definition.manifest["form_id"]=key.trim_prefix("homura_")
		session.bundle._definitions[key]=definition
	var stage: Node3D=load("res://scripts/campaign/saga_stage.gd").new(); root.add_child(stage)
	for frame in 90:
		await physics_frame
		if stage.ready_for_play: break
	check(stage.ready_for_play,"real later-map stage enters exploration")
	if not stage.ready_for_play: stage.free(); return
	check(stage.exploration_leads().size()==4,"naturally unlocked Homura supplies both forms beside healer and controller")
	check(stage.player.form_id=="homura_sword","party change restores a valid loaded lead")
	for expected in ["homura_mage","healer","controller","homura_sword"]:
		stage._lead_armed=true
		check(stage._cycle_exploration_lead() and stage.player.form_id==expected,"remaining exploration form usable " + expected)
	var pickup: Dictionary=Objects.get_object("region_2_bundle")
	stage.player.position=Vector3(pickup.position[0]+.65,pickup.position[1],pickup.position[2])
	stage.player.set_move_input(Vector2.ZERO)
	for frame in 4: await physics_frame
	stage._confirm_armed=true
	check(stage.request_interaction(str(pickup.id)),"later-map E dispatches real pickup action")
	for frame in 50: await physics_frame
	check(session.campaign.safe_snapshot().get("world_objects",{}).get(pickup.id,false),"later-map pickup writes durable state")
	check(stage.interaction_dispatch(str(pickup.id)).is_empty(),"later-map consumed target removed")
	var door: Dictionary=Objects.get_object("region_2_door")
	stage.player.position=Vector3(door.position[0],door.position[1],door.position[2]+1.05); stage.player.velocity=Vector3.ZERO
	stage.player.set_move_input(Vector2.ZERO)
	for frame in 4: await physics_frame
	stage._confirm_armed=true
	check(stage.request_interaction(str(door.id)),"later-map door accepts nearby action")
	for frame in 50: await physics_frame
	check(session.campaign.safe_snapshot().world_objects.get(door.id,false),"later-map door transaction persists")
	check(stage.controls_enabled,"later-map door recovery returns control")
	stage.shutdown(); stage.free()
