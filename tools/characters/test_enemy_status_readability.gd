# 真正敌卡字体/几何与号令打断时序；像素遮挡另由原生窄片复核。
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
func source()->Dictionary:
	var actor:=F.actor("controller","source");actor["identity_id"]="controller";actor.stats.spd=999;return actor
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var definition:=Definition.load_definition("res://assets/chars/pixel/controller/video_actions/manifest.json","battle")
	await _layout(definition)
	await _intent(definition,false)
	await _intent(definition,true)
	definition.clear();print("ENEMY_STATUS_READABILITY: %d assertions, %d failures"%[checks,failures]);quit(1 if failures else 0)
func _layout(definition:Dictionary)->void:
	var actors:={"source":source()}
	var ids:=["weaken","slow","magic_break","armor_break","mark","burn"]
	for index in 3:
		var id:="target%d"%index;var enemy:=F.enemy("hound",id)
		for i in [1,3,6][index]:enemy.statuses.append(F.status(ids[i],.2,2,"source",{"base":1}))
		actors[id]=enemy
	var engine:=Battle.new();check(engine.start({"actors":actors,"inventory":{}},771).started,"三敌状态夹具合法")
	engine.advance(false)
	var view:=Fixture.new();view.definition=definition;view.engine=engine;root.add_child(view)
	for frame in 3:await process_frame
	for index in 3:
		var id:="target%d"%index;var w:Dictionary=view._actors[id];var label:RichTextLabel=w.status
		for status in engine.snapshot().actors[id].statuses:
			var name:String=view._catalog.get_definition("statuses",status.id).name
			check(label.text.count(name)==1,id+" 每种状态正文一行，不重复摘要："+name)
			check(label.text.contains(view.Presenter.clock_text(status.clock,status.remaining)),id+" 完整时钟保留")
		if index<2:
			check(label.get_content_height()<=label.size.y+.5,id+" 一至三状态完整高度，不裁半行："+str([label.get_content_height(),label.size.y,label.position.y,w.card.position.y,view._world_backdrop.actor_screen_bounds(id).position.y,label.get_theme_font("normal_font").get_height(16)] ))
			check(not label.get_v_scroll_bar().visible,id+" 常态一至三行不产生多余滚动条")
		else:
			check(label.scroll_active and label.get_v_scroll_bar().visible,"六状态全部保留，可滚动查看更多")
			label.scroll_to_line(3);await process_frame
			check(label.get_v_scroll_bar().value>0,"六状态的后续行实际可滚动到达")
		check(label.get_rect().end.y<=w.card.size.y-18,"状态区完整包含在卡内")
		check(w.card.get_rect().end.y<=view._world_backdrop.actor_screen_bounds(id).position.y-2,"状态卡不扩到实际身体上沿")
	view.free();await process_frame
func _intent(definition:Dictionary,cancel:bool)->void:
	var enemy:=F.enemy("saga_borrowed_voice","target");enemy.stats.hp=5000;enemy.hp=5000
	enemy.statuses=[F.status("magic_break",.25,3,"source")]
	var engine:=Battle.new();engine.set_policy(load("res://scripts/rpg/enemy_policy.gd").new())
	check(engine.start({"actors":{"source":source(),"target":enemy},"inventory":{}},17).started,"实际号令启动")
	engine.advance(false)
	var view:=Fixture.new();view.definition=definition;view.engine=engine;root.add_child(view)
	var before:=engine.snapshot();var original:String=view._actors.target.intent.text
	var result:=engine.submit({"command_id":"interrupt","expected_revision":before.revision,"actor_id":"source","kind":"skill","ability_id":"seal","target_ids":["target"]})
	check(result.accepted and result.events.any(func(e):return e.type=="intent_updated"),"真实封缄更新意图")
	var committed:=engine.snapshot();var observed:={"updated":false}
	view._hd_player.event_presented.connect(func(event):
		if event.type=="intent_updated":
			observed.updated=true
			check(view._actors.target.intent.text.contains("已打断"),"intent_updated当帧显示真实取消提示"))
	view.processing=true;view._consume_events(result.events,before);view._render()
	check(view._actors.target.intent.text==original and not view._actors.target.intent.tooltip_text.contains("已打断") and not view._actors.target.target.tooltip_text.contains("已打断"),"M前正文及悬停都保留原意图")
	if cancel:view._cancel_presentation()
	else:
		for frame in 240:
			await process_frame
			if not view._hd_player.is_busy():break
		check(observed.updated,"意图呈现事件确实消费")
	check(view._actors.target.intent.text.contains("已打断"),"尾部或取消立即对齐最终意图")
	check(view._actors.target.target.tooltip_text.contains("已打断"),"目标悬停与当前打断意图一致")
	if not cancel:
		var w:Dictionary=view._actors.target
		check(w.status.text.contains("破魔3动") and w.status.text.contains("眩晕1动") and w.status.text.contains("失衡1动") and w.status.tooltip_text.contains("3次行动"),"带MP卡三状态各自次数可见，完整时钟悬停保留")
		check(w.status.get_content_height()<=w.status.size.y,"带MP的三状态卡完整显示："+str([w.status.get_content_height(),w.status.size.y,w.status.position.y,w.card.position.y,view._world_backdrop.actor_screen_bounds("target").position.y]))
	check(engine.snapshot()==committed,"UI修正不改模型")
	view.free();await process_frame
