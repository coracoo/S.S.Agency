# 真正引擎/视图/3D背景接入新PNG后端；无头合同不代表像素或性能审核。
extends SceneTree
const F=preload("res://tools/rpg/fixtures.gd")
const Battle=preload("res://scripts/rpg/battle_engine.gd")
const Definition=preload("res://scripts/characters/pixel_character_definition.gd")
class Fixture extends "res://scripts/rpg/ui/battle_view.gd":
	var definition:Dictionary
	func _hd_enabled()->bool:return true
	func _actor_definition(_actor:Dictionary)->Dictionary:return definition
	func _build()->void:
		super._build()
		_world_backdrop=WorldBackdrop.new();_canvas.add_child(_world_backdrop);_canvas.move_child(_world_backdrop,0)
		_world_backdrop.configure({"night":1,"position":[-4.5,.03,.45]},false)
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var source:=F.actor("mage","source");source["identity_id"]="homura";source["form_id"]="mage";source.stats.spd=999
	var enemy:=F.enemy("hound","target");enemy.hp=5000;enemy.stats.hp=5000
	var engine:=Battle.new();var initialized:=engine.start({"actors":{"source":source,"target":enemy},"inventory":{}},12)
	check(initialized.started,"真实引擎初始化："+str(initialized))
	if not initialized.started:quit(1);return
	engine.advance(false)
	var view:=Fixture.new();view.definition=Definition.load_definition("res://assets/chars/pixel/homura_mage/video_actions/manifest.json","battle");view.engine=engine;root.add_child(view)
	var new_backend:bool=view._fx_layer.get_script().resource_path=="res://scripts/rpg/ui/imagegen_battle_effects.gd"
	check(new_backend,"真正BattleView默认后端已替换为imagegen清单管线")
	check(not view._skill_effects_ready,"新素材游戏QA未完时仍生产关闭")
	if new_backend:
		view._fx_layer.preview_pending_art=true;view._skill_effects_ready=true
		var before:=engine.snapshot()
		var result:=engine.submit({"command_id":"imagegen-real-firebolt","expected_revision":before.revision,"actor_id":"source","kind":"skill","ability_id":"firebolt","target_ids":["target"]})
		check(result.accepted,"真实火弹指令被引擎接纳")
		var committed:=engine.snapshot();var immutable:Array=result.events.duplicate(true)
		var home:Vector2=view._actors.source.sprite.position
		var observed:Dictionary={"started":0,"damage":0,"action":{},"event":{},"start_frame":-1,"resource_frame":-1}
		view._hd_player.action_started.connect(func(event,timing):
			observed.started+=1;observed.action=event.duplicate(true);observed.start_frame=Engine.get_process_frames()
			check(view._fx_layer.action_count()==1 and view._fx_layer.active_count()==2,"action_started接入真实施法/飞行两层")
			var action:Dictionary=view._fx_layer._actions.values()[0]
			check(is_equal_approx(action.duration,timing.action_duration),"来源原生E时长传给PNG后端")
			check(view._actors.target.hpbar.value==before.actors.target.hp,"施法开始还没有显示伤害")
			check(not view._hud.latest.text.contains("伤害"),"起手时底部反馈也没有提前泄出伤害"))
		view._hd_player.event_presented.connect(func(event):
			if event.type=="resources_changed":
				observed.resource_frame=Engine.get_process_frames()
				check(observed.resource_frame==observed.start_frame,"实际资源事件在动作接纳帧呈现，不等命中M")
				check(view._actors.source.mpbar.value==event.payload.mp_after,"MP只在真实资源事件更新且观察者看到一致值")
			if event.type=="damage":
				observed.damage+=1;observed.event=event.duplicate(true)
				check(view._fx_layer.hit_count()==1,"真实damage当帧创建一次火弹命中")
				check(view._hud.latest.text.contains("伤害"),"真实damage当帧更新可见战斗日志")
				check(view._actors.target.hpbar.value==event.payload.absorption.hp_after,"HP当帧与真实damage值一致")
				check(view._fx_layer._bursts.back().target.distance_to(view._world_backdrop.actor_effect_center("target"))<.01,"命中中心来自实际3D身体"))
		view.processing=true;view._consume_events(result.events,before);view._render()
		check(not view._hud.latest.text.contains("伤害"),"模型已提交但M前不提前显示结果日志")
		check(view._actors.source.mpbar.value==before.actors.source.mp,"资源事件尚未呈现时MP仍保持前值")
		for frame in 240:
			await process_frame
			check(view._actors.source.sprite.position==home,"施法角色原地")
			if not view._hd_player.is_busy():break
		check(observed.started==1 and observed.damage==1,"一次接纳/一次命中")
		check(view._fx_layer.active_count()==0 and view._fx_layer.texture_memory_bytes()==0,"原生动作结束后瞬态与页面全部释放")
		check(engine.snapshot()==committed and result.events==immutable,"表现没有改伤害/MP/原事件数组")
		view._cancel_presentation();view._on_action_started(observed.action,{"native_impact_seconds":.2,"action_duration":.6});view._on_event_presented(observed.event)
		check(view._fx_layer.active_count()==0,"取消后晚回调不能复活火弹")
		var cancelled:=Fixture.new();cancelled.definition=view.definition;cancelled.engine=engine;root.add_child(cancelled)
		cancelled.processing=true;cancelled._consume_events(result.events,before);cancelled._render()
		check(not cancelled._pending_logs.is_empty() and not cancelled._hud.latest.text.contains("伤害"),"取消夹具的结算日志在M前仍暂存")
		cancelled._cancel_presentation()
		check(cancelled._pending_logs.is_empty() and cancelled._hud.latest.text.contains("伤害"),"表现取消后保留完整已提交账目")
		var log_size:int=cancelled._log_lines.size()
		cancelled._on_event_presented(observed.event)
		check(cancelled._log_lines.size()==log_size,"晚事件不重复追加已取消批次日志")
		cancelled.free()
	view.free()
	print("IMAGEGEN_BATTLE_VIEW: %d assertions, %d failures"%[checks,failures])
	quit(1 if failures else 0)
