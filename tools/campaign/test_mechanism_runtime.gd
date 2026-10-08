# 真实地图胶囊行走、E/Enter交互和对白停点；仅经隔离Python入口运行。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Fixture=preload("res://tools/campaign/saga_transaction_fixture.gd")
const Rules=preload("res://scripts/campaign/mechanism_rules.gd")
const Saga=preload("res://scripts/campaign/saga_catalog.gd")
const Strategy=preload("res://tools/campaign/saga_battle_strategy.gd")
const CASES:={
	"water_echo":{"before":"C2-09","scene":"C2-10","flag":"water_echo_verified","actions":["observe","block","listen","unblock","listen"]},
	"ferry":{"before":"C3-15","scene":"C3-16","flag":"ferry_repaired","actions":["dry_wood","brace_pile","transfer_rope","replace_board","flatten_nails","raise_lamp","sail_out","sail_back"]},
	"junction":{"before":"C6-07","scene":"C6-08","flag":"control_pin_held","actions":["support_rod","isolate","take_pin","light_lamp"]},
	"ward_test":{"before":"C6-08","scene":"C6-09","flag":"temporary_ward_verified","actions":["position_outer","position_inner","pull_pin","check_exit","second_operator"]},
	"driftwood":{"before":"C6-12","scene":"C6-S03","flag":"evacuation_route_ready","actions":["brace","cut_right","move_wood","stretcher_start","stretcher_slope","stretcher_handoff"]},
	"late_ferry":{"before":"C6-12","scene":"C6-S03","mechanism":"driftwood","flag":"evacuation_route_ready","actions":["brace","cut_right","move_wood","stretcher_start","stretcher_slope","stretcher_handoff"]},
	"alley":{"before":"C6-12","scene":"C6-S04","flag":"alley_rescued","actions":["prepare_cloth","cover_near","remove_far","guard_exit","handoff"]}}
var assertions:=0
var failures:Array[String]=[]
var session:RefCounted
var stage:Node3D
var walked:=0.0
var case_id:="water_echo"
var scene_id:=""
var capture_root:=""
func check(value:bool,message:String)->void:
	assertions+=1
	if not value:failures.append(message);printerr("FAIL:",message)
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	_run.call_deferred()
func _run()->void:
	case_id=OS.get_environment("MECHANISM_RUNTIME_CASE") if not OS.get_environment("MECHANISM_RUNTIME_CASE").is_empty() else "water_echo"
	if not CASES.has(case_id):check(false,"未知实地用例");_finish();return
	var specification:Dictionary=CASES[case_id];scene_id=specification.scene
	var primary_mechanism:String=specification.get("mechanism",case_id)
	capture_root=OS.get_environment("ACT_ONE_OUTPUT")
	if not capture_root.is_empty():
		if DisplayServer.get_name()=="headless":check(false,"图形采集需要真实后端");_finish();return
		root.position=Vector2i(-32000,-32000)
	session=Session.new()
	check(Fixture.enter_saga(session),"经正式事务进入后六章")
	check(Fixture.through(session,scene_id,true) if case_id=="ferry" else Fixture.through(session,specification.before,false,{"C3-15":"b"} if case_id=="late_ferry" else {}),"经正式事务抵达机关前："+case_id)
	if case_id=="late_ferry":check(not session.campaign.safe_snapshot().saga.flags.ferry_repaired and not session.campaign.safe_snapshot().mechanisms.states.ferry.complete,"第三章真实暂缓保留未修渡口")
	print("MECHANISM_RUNTIME_CHECKPOINT:",case_id," chapter=",session.campaign.safe_snapshot().get("saga",{}).get("chapter")," active=",session.campaign.safe_snapshot().get("saga",{}).get("active_scene"))
	if not failures.is_empty():_finish();return
	stage=load("res://scenes/campaign/saga.tscn").instantiate();root.add_child(stage)
	for frame in 10000:
		await process_frame
		if stage.ready_for_play or not stage.last_error.is_empty():break
	check(stage.ready_for_play,"正式地区和人物资源加载完成："+str(stage.last_error))
	if not stage.ready_for_play:_finish();return
	stage.player.set_camera_basis(Basis.IDENTITY)
	var anchor:Array=stage.config.anchors[Saga.scene(scene_id).location]
	var approach:=Vector2(anchor[0],anchor[2]-1.1 if case_id in ["driftwood","late_ferry"] else anchor[2])
	check(await _walk_route(approach),"实际走到调查点，不传送")
	check(stage.nearby_interactions().any(func(row):return row.id==scene_id),"真实距离允许调查登记场次")
	await _open_target(scene_id)
	await _drain_dialogue()
	check(stage._mode=="explore" and stage.controls_enabled,"对白在对应来源动作前暂停回到地图")
	check(session.campaign.safe_snapshot().mechanisms.states[primary_mechanism].step==0 and not session.campaign.safe_snapshot().saga.flags.get(specification.flag,false),"对白不自动解谜或提前写成功事实")
	var initial:Dictionary=session.campaign.safe_snapshot()
	if case_id in ["driftwood","late_ferry"]:
		check(_heap_blocks_route(),"未清堆木在真实物理空间挡住担架中央路线")
		var approach_position:=Vector2(stage.player.position.x,stage.player.position.z)
		stage.player.set_move_input(Vector2(0,1));stage.player.set_run_input(true)
		for frame in 45:await physics_frame
		stage.player.set_move_input(Vector2.ZERO);stage.player.set_run_input(false)
		check(stage.player.position.z<10.0 and stage.player.position.z>approach_position.y+.2,"真实角色胶囊会在堆木前停住，不能只靠射线证明阻挡")
		check(await _walk(approach_position),"被阻挡后可实际退回安全位置")
	await _capture("before")
	var action_sequence:Array=[]
	if case_id=="late_ferry":
		for action_id in ["dry_wood","brace_pile","transfer_rope","replace_board","flatten_nails","raise_lamp","sail_out","sail_back"]:action_sequence.append(["ferry",action_id])
	for action_id in specification.actions:action_sequence.append([primary_mechanism,action_id])
	for action_pair in action_sequence:
		var mechanism_id:String=action_pair[0];var action_id:String=action_pair[1]
		if case_id=="alley" and action_id=="remove_far":
			await _alley_battle()
			initial=session.campaign.safe_snapshot()
		var target:Dictionary={}
		for candidate in Rules.targets(session.campaign.safe_snapshot()):
			if candidate.mechanism_id==mechanism_id and candidate.action_id==action_id:target=candidate;break
		check(not target.is_empty(),"实际操作站登记："+action_id)
		if target.is_empty():break
		check(await _walk_route(Vector2(target.position[0],target.position[2]),.52 if case_id=="late_ferry" else .24),"胶囊实际抵达操作站："+action_id)
		if action_id=="second_operator":
			var first:String=session.campaign.safe_snapshot().mechanisms.states.ward_test.first_actor
			await _open_target(target.id)
			check(not stage._modal_buttons.any(func(button):return _button_text(button)==target.label),"未换同伴时不提供必然失败且锁在错误窗口的确认")
			for button in stage._modal_buttons:
				if _button_text(button).contains("回到地图"):button.grab_focus();await _key(KEY_ENTER);break
			for attempt in 8:
				if stage._current_mechanism_actor()!=first:break
				await _key(KEY_TAB)
			check(stage._current_mechanism_actor()!=first,"真实Tab换成另一位同伴复验")
		var before_step:int=session.campaign.safe_snapshot().mechanisms.states[mechanism_id].step
		await _open_target(target.id)
		check(stage._mode=="mechanism_prompt" and not stage.controls_enabled,"E打开物件操作并锁移动")
		if stage._mode!="mechanism_prompt":break
		var confirm:Button=null
		for button in stage._modal_buttons:
			if _button_text(button)==target.label:confirm=button;break
		check(confirm!=null,"合法动作有可见确认按钮")
		if confirm==null:break
		var boat_before:Vector3=stage._mechanism_layer.part("ferry","boat").position if action_id in ["sail_out","sail_back"] else Vector3.ZERO
		confirm.grab_focus();await _key(KEY_ENTER)
		check(not stage.controls_enabled,"提交后的物件动画期间输入保持锁定")
		if action_id in ["sail_out","sail_back"]:
			for frame in 12:await physics_frame
			check(stage._mechanism_animating and not stage._mechanism_layer.part("ferry","boat").position.is_equal_approx(boat_before),"空船实际连续移动且动画未瞬间结束")
			await _capture(action_id+"-middle")
		for frame in 240:
			await physics_frame
			if not stage._mechanism_animating:break
		check(session.campaign.safe_snapshot().mechanisms.states[mechanism_id].step==before_step+1,"一次确认只提交一个真实步骤")
		check(session.campaign.safe_snapshot().inventory==initial.inventory and session.campaign.safe_snapshot().roster==initial.roster,"地图操作不消费或恢复战斗资源")
		if action_id=="move_wood":check(not _heap_blocks_route(),"清除后真实中央路线解除碰撞")
		if action_id in ["block","unblock","take_pin","light_lamp","second_operator","move_wood","remove_far","handoff"]:await _capture(action_id+"-settled")
		await _drain_dialogue()
	check(session.campaign.safe_snapshot().saga.completed.has(scene_id) and session.campaign.safe_snapshot().saga.flags.get(specification.flag,false),"实地操作后对白续播并提交原剧情")
	check(walked>8,"记录到多个位置之间的实地行走")
	await _capture("after")
	var saved:Dictionary=session.campaign.safe_snapshot()
	stage.free();stage=null;session.close();session=Session.new()
	check(session.resume().ok and session.campaign.safe_snapshot()==saved,"真实会话重开保留现场状态")
	print("MECHANISM_WALK_METRES:",walked);_finish()
func _open_target(id:String)->void:
	await _key(KEY_E)
	print("MECHANISM_INPUT_OPEN:",id," mode=",stage._mode)
	if stage._mode=="interaction_select":
		var target_label:=""
		for target in stage._targets:
			if target.id==id:target_label=target.label;break
		for button in stage._modal_buttons:
			if not target_label.is_empty() and _button_text(button).ends_with(target_label):
				button.grab_focus();await _key(KEY_ENTER);print("MECHANISM_INPUT_SELECTED:",id," mode=",stage._mode);return
func _button_text(button:Button)->String:
	if not button.text.is_empty():return button.text
	for label in button.find_children("*","Label",true,false):
		if not label.text.is_empty():return str(label.text)
	return ""
func _drain_dialogue()->void:
	for count in 180:
		await process_frame
		if stage._mode=="dialogue":await _key(KEY_E)
		elif stage._mode in ["choice","confirmation"]:
			if stage._modal_buttons.is_empty():return
			stage._modal_buttons[0].grab_focus();await _key(KEY_ENTER)
		else:return
	check(false,"对白应在有限确认次数内到达地图停点")
func _walk_route(target:Vector2,tolerance:float=.24)->bool:
	var here:=Vector2(stage.player.position.x,stage.player.position.z)
	if case_id in ["driftwood","late_ferry"] and not session.campaign.safe_snapshot().mechanisms.states.driftwood.complete and session.campaign.safe_snapshot().mechanisms.states.driftwood.step<3 and here.y<9.8 and target.y>10:
		if not await _walk(Vector2(22,here.y)):return false
		if not await _walk(Vector2(22,11.4)):return false
		here=Vector2(stage.player.position.x,stage.player.position.z)
	if absf(here.x-target.x)>4 and (absf(here.y)>2 or absf(target.y)>2):
		if not await _walk(Vector2(here.x,0)):return false
		if not await _walk(Vector2(target.x,0)):return false
	return await _walk(target,tolerance)
func _heap_blocks_route()->bool:
	var query:=PhysicsRayQueryParameters3D.create(Vector3(19.8,.45,9.0),Vector3(19.8,.45,11.5),1,[stage.player.get_rid()])
	var hit:=stage.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and str(hit.collider.name)=="DriftwoodBlocker"
func _alley_battle()->void:
	check(stage._mode=="battle_cue","遮近镜后才抵达原短战提示")
	var before:Dictionary=session.campaign.safe_snapshot()
	var station:Dictionary={}
	for row in Rules.targets(before):
		if row.mechanism_id=="alley" and row.action_id=="remove_far":station=row;break
	var world:Dictionary=before.world.duplicate(true);world.position=station.position.duplicate()
	check(not session.campaign.commit_mechanism(world,"alley","remove_far",before.party[0]).ok,"未胜利不能提前拆远镜")
	var started:Dictionary=session.begin_encounter(stage.export_world(),scene_id)
	check(started.ok,"遮近镜后可按原登记实际进战")
	if not started.ok:return
	var engine:RefCounted=session.router.create_engine()
	for turn in 180:
		engine.advance();var state:Dictionary=engine.snapshot()
		if not state.outcome.is_empty():break
		if state.phase=="action_selection":
			var command:Dictionary=Strategy.choose(state,engine,session.campaign._catalog)
			if command.is_empty() or not engine.submit(command).accepted:break
	var result:Dictionary=session.router.result_from_engine()
	check(result.get("outcome")=="victory" and session.router.finish(result).ok,"原短战实际合法指令获胜且保存")
	stage.apply_committed_world(session.campaign.safe_snapshot().world)
	stage._begin_story(scene_id);await _drain_dialogue()
	check(stage._mode=="explore" and session.campaign.safe_snapshot().mechanisms.states.alley.step==2,"战后来源11处停住，远镜仍须实际拆除")
func _capture(label:String)->void:
	if capture_root.is_empty():return
	stage.camera_rig.follow(stage._mechanism_focus if stage._mechanism_animating and is_instance_valid(stage._mechanism_focus) else stage.player,10)
	# 离屏Windows窗口可能不触发自动frame_post_draw；显式绘制并同步取图，不作无界信号等待。
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(capture_root.path_join(case_id+"-"+label+".png"))==OK,"保存实际场景画面："+label)
func _walk(target:Vector2,tolerance:float=.24)->bool:
	var began:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<35000:
		if not stage.controls_enabled:return false
		var here:=Vector2(stage.player.position.x,stage.player.position.z)
		if here.distance_to(target)<tolerance:
			stage.player.set_move_input(Vector2.ZERO);stage.player.set_run_input(false)
			await physics_frame;return true
		if stage.player.position.y<-.5:return false
		stage.player.set_move_input((target-here).normalized());stage.player.set_run_input(true)
		await physics_frame
		walked+=here.distance_to(Vector2(stage.player.position.x,stage.player.position.z))
	stage.player.set_move_input(Vector2.ZERO);return false
func _key(code:Key)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.pressed=true
	Input.parse_input_event(event);await process_frame;await process_frame
	event.pressed=false;Input.parse_input_event(event);await process_frame;await process_frame
func _finish()->void:
	if is_instance_valid(stage):stage.free()
	if session!=null:session.close()
	print("MECHANISM_RUNTIME:",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
