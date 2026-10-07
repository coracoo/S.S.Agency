extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Actions = preload("res://tools/characters/test_expanded_actions.gd")
class FixtureView extends "res://scripts/rpg/ui/battle_view.gd":
	var definition: Dictionary = {}
	func _hd_enabled() -> bool: return true
	func _actor_definition(_actor: Dictionary) -> Dictionary: return definition
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var fixture := Actions.new()
	var definition := fixture.definition()
	definition.manifest.merge({"identity_id":"rinne","form_id":"rinne","portrait_source_manifest":"res://assets/chars/pixel/rinne/high_detail_complete/manifest.json"})
	fixture.free()
	var actor := F.actor("swordsman","p_swordsman")
	actor["identity_id"]="rinne"; actor["form_id"]="rinne"; actor.stats.spd=100
	var enemy := F.enemy("hound","e_1")
	enemy.hp=1; enemy.statuses=[F.status("mark",1,2,"p_swordsman")]
	var engine := Battle.new()
	print("START:",engine.start({"actors":{"p_swordsman":actor,"e_1":enemy},"inventory":{}},17))
	engine.advance(false)
	var view := FixtureView.new(); view.definition=definition; view.engine=engine; root.add_child(view)
	# 此历史HP夹具专门量测接近+原生命中；不据其小纹理批准生产冲刺。
	view._hd_views.p_swordsman.allow_unapproved_melee_preview=true
	print("BEFORE:HP=",view._actors.e_1.hpbar.value," STATUS=",view._actors.e_1.status.text)
	var timing := {"clock":0.0,"started":-1.0,"impact":0.0,"approach":0.0,"hits":0,"hit_time":-1.0,"synchronized":false}
	view._hd_player._frame_tick.connect(func(delta): timing.clock += delta)
	view._hd_player.action_started.connect(func(event,info):
		if event.actor_id == "p_swordsman":
			timing.started = timing.clock
			timing.impact = info.native_impact_seconds
			timing.approach = info.approach_seconds)
	view._hd_player.event_presented.connect(func(event):
		if event.type == "damage" and event.target_id == "e_1":
			timing.hits += 1
			timing.hit_time = timing.clock
			timing.synchronized = view._actors.e_1.hpbar.value == 0 and not view._actors.e_1.status.visible)
	view.select_command("attack_physical"); view.confirm_command()
	print("IMMEDIATE:HP=",view._actors.e_1.hpbar.value," STATUS_VISIBLE=",view._actors.e_1.status.visible," STATUS=",view._actors.e_1.status.text," MODEL_HP=",engine.snapshot().actors.e_1.hp)
	var early_cleared: bool = view._actors.e_1.hpbar.value == 1 and not view._actors.e_1.status.visible
	print("LETHAL_STATUS_EARLY_CLEAR:",early_cleared)
	var failed := 1 if early_cleared else 0
	# 原15帧期限只覆盖原地200ms出手；现在分别检查200ms接近与接纳后的原生命中。
	for frame in range(120):
		await process_frame
		if timing.hits == 0 and (view._actors.e_1.hpbar.value != 1 or not view._actors.e_1.status.visible):
			print("FAIL: 接近/原生出手命中前提前改变HP或状态")
			failed += 1
			break
		if not view._hd_player.is_busy(): break
	if timing.hits != 1 or not timing.synchronized:
		print("FAIL: 唯一命中未同步显示HP与致死状态清理")
		failed += 1
	if timing.approach < .18 or timing.started < .18 or absf(float(timing.impact)-.2) > .001:
		print("FAIL: 物理攻击缺少接近或改写了原生200ms标记")
		failed += 1
	if absf(float(timing.hit_time)-float(timing.started)-float(timing.impact)) > .035:
		print("FAIL: 实际命中不在接纳后的原生标记：",timing)
		failed += 1
	print("LETHAL_STATUS_IMPACT_TIMING:",timing)
	print("LETHAL_STATUS_IMPACT_RESULT: ",failed)
	view.free(); quit(1 if failed else 0)
