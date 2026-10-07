# 原敌图动作与退场回归：真实事件队列和3D材质，不伪称敌人已有逐帧视频。
extends SceneTree
const Actor = preload("res://scripts/rpg/ui/legacy_actor_view.gd")
const Events = preload("res://scripts/rpg/ui/hd_event_player.gd")
const Backdrop = preload("res://scripts/rpg/ui/battle_world_backdrop.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Fixture = preload("res://tools/rpg/fixtures.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()

func _run() -> void:
	var probe := Actor.new()
	check(ResourceLoader.exists("res://scripts/rpg/ui/enemy_presentation_profiles.gd"), "敌方表现分类存在")
	check(probe.has_method("configure_attack_presentation"), "原图适配器接受当帧攻击表现")
	probe.feedback_label.free()
	probe.free()
	if failures > 0: _finish(); return
	_test_profiles()
	await _test_motion_and_projection()
	await _test_event_defeat(false)
	await _test_event_defeat(true)
	await _test_engine_lethal()
	await _test_deferred_hit_and_reset()
	_finish()

func _test_profiles() -> void:
	var profiles: Script = load("res://scripts/rpg/ui/enemy_presentation_profiles.gd")
	var rows := [
		["hound", {"kind":"attack_physical"}, {}, "melee"],
		["saga_anchor_left", {"kind":"attack_physical"}, {}, "ranged"],
		["fire_spirit", {"kind":"attack_magic"}, {}, "cast"],
		["saga_paper_soldier", {"kind":"skill","ability_id":"saga_paper_bind"}, {"damage_type":"physical"}, "ranged"],
		["saga_lamp_shadow", {"kind":"skill","ability_id":"saga_shadow_glow"}, {"damage_type":"magic","element":"fire"}, "cast"],
		["hound", {"kind":"skill","ability_id":"bite"}, {"damage_type":"physical"}, "melee"],
		["gatekeeper", {"kind":"skill","ability_id":"boss_pulse_charge"}, {"damage_type":"none"}, "cast"],
	]
	for row in rows:
		var result: Dictionary = profiles.resolve(row[0], row[1], row[2])
		check(result.style == row[3], "真实指令分类："+str(row[0])+"/"+str(row[1]))
		check(result.tint is Color and result.has("effect_id"), "表现提供可用色调与独立特效选择")
	var charge: Dictionary = profiles.resolve("gatekeeper", {"kind":"skill","ability_id":"boss_pulse_charge"}, {"damage_type":"none"})
	check(charge.effect_id == "", "未造成伤害的蓄力不借用攻击命中特效")
	var fire: Dictionary = profiles.resolve("saga_lamp_shadow", {"kind":"skill","ability_id":"saga_shadow_glow"}, {"damage_type":"magic","element":"fire"})
	check(fire.effect_id == "firebolt", "已知火伤害复用现有火焰资产")

func _actor(side: String = "enemy") -> Node2D:
	var actor := Actor.new()
	root.add_child(actor)
	var visual := Node2D.new()
	var sprite := Sprite2D.new()
	var picture := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	picture.fill(Color.WHITE)
	sprite.texture = ImageTexture.create_from_image(picture)
	sprite.offset = Vector2(0,-16)
	visual.add_child(sprite)
	actor.call("configure", visual, 300.0, "right", true, side)
	actor.position = Vector2(620, 550)
	return actor

func _backdrop(actor: Node2D) -> Control:
	var backdrop := Backdrop.new()
	root.add_child(backdrop)
	backdrop.configure({}, false)
	backdrop.bind_visuals({"enemy":{"sprite":actor}})
	return backdrop

func _frames(count: int) -> void:
	for index in count: await process_frame

func _test_motion_and_projection() -> void:
	var actor := _actor()
	actor.set_process(false)
	var backdrop := _backdrop(actor)
	var body: Sprite3D = backdrop.actor_entries.enemy.body
	var home := body.position
	for style in ["melee", "ranged", "cast"]:
		actor.play_action(&"attack")
		# 和正式action_started相同，在play_action之后的同帧选择当前攻击样式。
		actor.configure_attack_presentation({"style":style, "tint":Color(.65,.75,1.0)})
		actor._process(.18)
		if style == "melee": check(actor.visual.position.x > 20, "近战原图向目标前冲")
		elif style == "ranged": check(actor.visual.position.x < -8, "远程原图后坐，与近战区分")
		else: check(actor.visual.modulate.b > actor.visual.modulate.r, "施法色调聚光可读")
		check(body.position != home or body.material_override.get_shader_parameter("appearance_tint") != Color.WHITE, style+"当帧同步真实3D位移/色调")
		actor._process(.17)
		check(actor.is_action_busy(), style+"维持原0.36秒动作边界")
		actor._process(.02)
		check(not actor.is_action_busy() and actor.visual.position == Vector2.ZERO and actor.visual.modulate == Color.WHITE, style+"收招恢复原图脚点与颜色")
		check(body.position.is_equal_approx(home) and body.material_override.get_shader_parameter("appearance_tint") == Color.WHITE, style+"真实3D同步恢复")
	check(not actor.has_method("action_impact_time"), "静态敌图不伪造原生视频命中时刻")
	backdrop.free()
	actor.free()
	await process_frame

func _test_event_defeat(parallel: bool) -> void:
	var source := _actor("player")
	var enemy := _actor()
	var other := _actor()
	var backdrop := _backdrop(enemy)
	var body: Sprite3D = backdrop.actor_entries.enemy.body
	var shadow: MeshInstance3D = backdrop.actor_entries.enemy.shadow
	var queue := Events.new()
	root.add_child(queue)
	queue.bind_actors({"source":source, "enemy":enemy, "other":other})
	var records: Array[Dictionary] = []
	queue.action_started.connect(func(_event: Dictionary, _timing: Dictionary): source.configure_attack_presentation({"style":"ranged", "tint":Color.WHITE}))
	queue.event_presented.connect(func(event: Dictionary):
		if event.get("target_id") != "enemy": return
		records.append({"type":event.type,"frame":Engine.get_process_frames()})
		if event.type == "damage": check(enemy.visible and not enemy.is_downed(), "致死伤害事件仍先保留敌人受击")
		if event.type == "actor_defeated": check(enemy.visible and enemy.is_downed(), "真实死亡事件启动退场前敌图仍可见"))
	var events: Array = [
		{"sequence":1,"type":"command_accepted","actor_id":"source","payload":{"command":{"command_id":"lethal","kind":"attack_physical"}}},
		{"sequence":2,"type":"damage","actor_id":"source","target_id":"enemy","payload":{"damage":20}},
		{"sequence":3,"type":"actor_defeated","actor_id":"source","target_id":"enemy","payload":{}},
	]
	if parallel: events.append({"sequence":4,"type":"damage","actor_id":"source","target_id":"other","payload":{"damage":20}})
	queue.enqueue(events,{"actors":{"source":{"hp":10},"enemy":{"hp":0},"other":{"hp":10}}})
	await _frames(8)
	check(records.is_empty() and enemy.visible and not enemy.is_downed(), "攻击过程中不能读取最终0HP提前退场")
	var flashes := 0
	var previous_alpha := 1.0
	for frame in 180:
		await process_frame
		var alpha: float = enemy.visual.modulate.a
		if enemy.is_downed() and alpha < .2 and previous_alpha >= .2: flashes += 1
		previous_alpha = alpha
		if enemy.visible: check(body.material_override.get_shader_parameter("appearance_tint").a == alpha, "闪烁alpha同步到真实3D材质")
		if not queue.is_busy(): break
	check(not queue.is_busy() and flashes >= 2, "真实队列等待至少两次闪烁后完成")
	check(not enemy.visible and not body.visible and not shadow.visible, "死亡后敌图与实际3D阴影一起消失")
	enemy.set_downed(true)
	await _frames(3)
	check(not enemy.visible and not enemy.is_action_busy(), "重复倒地快照不重播闪烁或重新显形")
	check(records.size() == 2 and records[0].type == "damage" and records[1].type == "actor_defeated", "伤害与死亡顺序保持且不重复")
	queue.enqueue([{"sequence":5,"type":"revived","actor_id":"source","target_id":"enemy","payload":{"hp":10}}], {"actors":{"enemy":{"hp":10}}})
	for frame in 60:
		await process_frame
		if not queue.is_busy(): break
	check(enemy.visible and body.visible and shadow.visible and not enemy.is_downed() and enemy.visual.modulate == Color.WHITE, "复活重置退场、恢复敌图和阴影")
	queue.enqueue(events, {"actors":{"enemy":{"hp":0}}})
	await _frames(4)
	check(enemy.visible and not enemy.is_downed(), "重复旧致死批次不会覆盖后来的复活")
	queue.free()
	backdrop.free()
	source.free()
	enemy.free()
	other.free()
	await process_frame

func _test_engine_lethal() -> void:
	var player_data := Fixture.actor("swordsman", "source")
	player_data.stats.spd = 999
	var enemy_data := Fixture.enemy("hound", "enemy")
	enemy_data.hp = 1
	var witness_data := Fixture.enemy("hound", "witness")
	var engine := Battle.new()
	check(engine.start({"actors":{"source":player_data,"enemy":enemy_data,"witness":witness_data},"inventory":{}},71).started, "实际战斗夹具启动")
	engine.advance(false)
	var before := engine.snapshot()
	var accepted := engine.submit({"command_id":"actual_enemy_lethal","expected_revision":before.revision,"actor_id":"source","kind":"attack_physical","ability_id":"","target_ids":["enemy"]})
	check(accepted.accepted and accepted.events.any(func(event): return event.type == "actor_defeated"), "权威引擎实际生成敌方致死事件")
	var committed := engine.snapshot()
	var source := _actor("player")
	var enemy := _actor()
	var queue := Events.new()
	root.add_child(queue)
	queue.bind_actors({"source":source, "enemy":enemy})
	queue.enqueue(accepted.events, committed)
	await _frames(5)
	check(committed.actors.enemy.hp == 0 and enemy.visible and not enemy.is_downed(), "权威HP已为零时，呈现仍等待真实攻击/受击时序")
	for frame in 160:
		await process_frame
		if not queue.is_busy(): break
	check(not enemy.visible and enemy.is_downed() and not queue.is_busy(), "真实致死队列最终完成闪烁退场")
	check(engine.snapshot() == committed, "死亡表现不更改伤害、胜负、随机数或资源")
	queue.free()
	source.free()
	enemy.free()
	await process_frame

func _test_deferred_hit_and_reset() -> void:
	for mode in ["cancel", "revive", "reconfigure"]:
		var actor := _actor()
		actor.set_process(false)
		actor.play_action(&"hit")
		actor.set_downed_after_hit()
		actor._process(.1)
		check(actor.is_downed() and actor._action == &"hit" and actor.visual.modulate.a == 1, "多目标致死先完整保留hit尾段")
		if mode == "cancel": actor.cancel_action()
		elif mode == "revive": actor.set_downed(false)
		else:
			var replacement := Node2D.new()
			replacement.add_child(Sprite2D.new())
			actor.configure(replacement,300,"right",true,"enemy")
		actor._process(2.0)
		check(actor.is_downed() == (mode == "cancel"), mode+"清理退场状态，无迟到死亡覆盖")
		check(actor.visible == (mode != "cancel"), mode+"保持取消对齐或恢复后的可见性")
		actor.free()
	var ally := _actor("player")
	ally.set_process(false)
	ally.set_downed(true)
	ally._process(2.0)
	check(ally.visible and ally.is_downed(), "旧fallback友方倒地保持在场")
	ally.play_action(&"recover")
	ally._process(.3)
	check(ally.visible and not ally.is_downed(), "旧fallback友方复活恢复")
	ally.free()
	await process_frame

func _finish() -> void:
	print("ENEMY_ACTION_PRESENTATION: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
