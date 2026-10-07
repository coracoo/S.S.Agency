# 真实 BattleView/LegacyActor/引擎事件：旧敌人无 impact 元数据，也必须遵循实际呈现边界。
# 小纹理只隔离人物资源成本；敌方适配器、控件、队列与规则均使用正式实现。
extends SceneTree
const F = preload("res://tools/rpg/fixtures.gd")
const Battle = preload("res://scripts/rpg/battle_engine.gd")
const Policy = preload("res://scripts/rpg/enemy_policy.gd")
const Actions = preload("res://tools/characters/test_expanded_actions.gd")
const LegacyActor = preload("res://scripts/rpg/ui/legacy_actor_view.gd")
const Backdrop = preload("res://scripts/rpg/ui/battle_world_backdrop.gd")

class FixtureView extends "res://scripts/rpg/ui/battle_view.gd":
	var definition: Dictionary = {}
	func _hd_enabled() -> bool: return true
	func _actor_definition(_actor: Dictionary) -> Dictionary: return definition

var failed := 0
var assertions := 0
var definition: Dictionary

func check(ok: bool, label: String) -> void:
	assertions += 1
	print(("PASS: " if ok else "FAIL: ") + label)
	if not ok: failed += 1

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	var fixture := Actions.new()
	definition = fixture.definition()
	# 独立down纹理身份让实际3D帧断言不能被所有动作共用同一测试贴图蒙混通过。
	var down_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	down_image.fill(Color(0.3, 0.4, 0.5))
	var down_texture := ImageTexture.create_from_image(down_image)
	for frame in range(4): definition.frames.set_frame("down", frame, down_texture, 0.10)
	definition.manifest.merge({"identity_id":"rinne", "form_id":"rinne", "portrait_source_manifest":"res://assets/chars/pixel/rinne/high_detail_complete/manifest.json"})
	fixture.free()
	for route in ["submit", "bind", "continue"]:
		for lethal in [false, true]: await _test_enemy_hit(route, lethal)
	await _test_multiple_hits()
	await _test_projected_tint()
	for cancellation in ["view", "player", "unbind", "exit"]:
		await _test_cancel_retry(cancellation)
	print("ENEMY_IMPACT_HUD_RESULT: ", failed, " (", assertions, " assertions)")
	quit(1 if failed else 0)

func _make_view(lethal: bool, automatic: bool = false, multiple: bool = false) -> FixtureView:
	var target := F.actor("swordsman", "p_swordsman")
	target["identity_id"] = "rinne"; target["form_id"] = "rinne"
	target.stats.hp = 2000; target.hp = 1 if lethal else 1000; target.stats.spd = 10
	target.shield = F.shield(7, 3, "p_swordsman")
	target.statuses = [F.status("mark", 0.1, 3, "e_1")]
	var witness := F.actor("guard", "p_witness")
	witness["identity_id"] = "rinne"; witness["form_id"] = "rinne"
	witness.stats.spd = 1
	var enemy := F.enemy("hound", "e_1")
	enemy.stats.hp = 5000; enemy.hp = 5000; enemy.stats.atk = 100; enemy.stats.spd = 300
	var actors := {"p_swordsman":target, "p_witness":witness, "e_1":enemy}
	if multiple:
		var second := enemy.duplicate(true)
		second.actor_id = "e_2"; second.stats.spd = 200
		actors["e_2"] = second
	var engine := Battle.new()
	if automatic: engine.set_policy(Policy.new())
	var result := engine.start({"actors":actors, "inventory":{"revival_potion":2}}, 71)
	check(result.started, "敌方回归真实引擎夹具合法：" + str(result.get("reasons", [])))
	engine.advance(false)
	var view := FixtureView.new()
	view.definition = definition; view.engine = engine
	root.add_child(view)
	check(not view._hd_failed, "真实 BattleView 人物资源装配成功")
	check(not view._hd_views.has("e_1") and view._presentation_views.e_1 is LegacyActor and view._hd_player._views.e_1 == view._presentation_views.e_1, "敌方来源确为只注册在表现字典的正式 LegacyActor")
	check(not view._presentation_views.e_1.has_method("action_impact_time"), "旧敌人没有新增或伪造命中时刻")
	return view

func _command(state: Dictionary, id: String = "enemy_impact") -> Dictionary:
	return {"command_id":id, "expected_revision":int(state.revision), "actor_id":state.active_actor_id, "kind":"attack_physical", "ability_id":"", "target_ids":["p_swordsman"]}

func _submit(view: FixtureView) -> Dictionary:
	var before: Dictionary = view.engine.snapshot()
	var command := _command(before)
	var result: Dictionary = view.engine.submit(command)
	check(result.accepted, "敌方正式指令只提交一次")
	var committed: Dictionary = view.engine.snapshot()
	view.processing = true
	view._consume_events(result.events, before)
	view._render()
	return {"before":before, "committed":committed, "command":command, "events":result.events}

func _test_enemy_hit(route: String, lethal: bool) -> void:
	var label := route + ("致死" if lethal else "非致死")
	var view := _make_view(lethal, route != "submit")
	var before: Dictionary = view.engine.snapshot()
	var previous_status: String = view._actors.p_swordsman.status.text
	var observations: Array[Dictionary] = []
	view._hd_player.event_presented.connect(func(event: Dictionary):
		if event.type not in ["damage", "actor_defeated"]: return
		var w: Dictionary = view._actors.p_swordsman
		observations.append({"type":event.type, "tick":Engine.get_process_frames()})
		if event.type == "damage":
			check(not view._presentation_views.e_1.is_action_busy(), label + "伤害只在旧敌人现有攻击结束后呈现")
			check(w.hpbar.value == event.payload.absorption.hp_after and w.hp.text == "HP %d / %d" % [event.payload.absorption.hp_after,before.actors.p_swordsman.stats.hp], label + "伤害事件同帧同步血条与HP文字")
			check(w.status.text == ("" if lethal else previous_status.get_slice("\n",1)), label + "护盾耗尽与致死状态清理和伤害同步")
			check(w.title.text.contains("倒地") == lethal and (w.sprite.modulate != Color.WHITE) == lethal, label + "倒地标题与灰态只服从已呈现HP")
			check(not w.sprite.is_downed(), label + "受击事件不越过后续个人倒地动作")
			var displayed: float = w.hpbar.value
			view._on_event_presented(event)
			check(w.hpbar.value == displayed, label + "重复伤害呈现信号不会二次扣血")
		else:
			check(w.sprite.is_downed() and w.sprite.animator.sprite.animation == "down", label + "actor_defeated 开始个人倒地视频")
			check(observations.size() == 2 and observations[0].tick < observations[1].tick, label + "倒地事件保持在受击之后"))
	if route == "submit": _submit(view)
	elif route == "bind": view.bind(view.engine, null)
	else:
		view.processing = true
		view._continue_after_action()
		view._render()
	var committed: Dictionary = view.engine.snapshot()
	check(committed.actors.p_swordsman.hp < before.actors.p_swordsman.hp and (committed.actors.p_swordsman.hp == 0) == lethal, label + "模型在表现之前已提交真实结果")
	var w: Dictionary = view._actors.p_swordsman
	check(w.hpbar.value == before.actors.p_swordsman.hp and w.hp.text == "HP %d / %d" % [before.actors.p_swordsman.hp,before.actors.p_swordsman.stats.hp], label + "攻击前HP文字与血条不提前变化")
	check(w.status.visible and w.status.text == previous_status, label + "攻击前盾与状态不提前清空")
	check(not w.title.text.contains("倒地") and w.sprite.modulate == Color.WHITE and not w.sprite.is_downed(), label + "攻击前不显示倒地标题灰态或倒地姿势")
	for tick in range(8): await process_frame
	view._render()
	check(observations.is_empty() and view._presentation_views.e_1.is_action_busy(), label + "原0.36秒敌方动作仍正常播放且尚无伤害事件")
	check(w.hpbar.value == before.actors.p_swordsman.hp and w.status.text == previous_status and w.sprite.modulate == Color.WHITE, label + "攻击进行中重绘仍保留完整旧HUD")
	await _drain(view)
	check(observations.size() == (2 if lethal else 1), label + "应有伤害和倒地事件均且只呈现一次")
	check(view.engine.snapshot() == committed, label + "呈现不修改伤害资源随机数轮序或重放日志")
	check(w.hpbar.value == committed.actors.p_swordsman.hp and view._pending_hp_events.is_empty(), label + "队列完成后HUD与模型一致且令牌清空")
	if lethal: check(w.sprite.is_downed() and not w.sprite.animator.sprite.is_playing() and w.sprite.animator.sprite.frame == 3, label + "个人倒地末帧保持")
	view.free()

func _test_multiple_hits() -> void:
	var view := _make_view(false, true, true)
	var before: Dictionary = view.engine.snapshot()
	var hp_after: Array[int] = []
	view._hd_player.event_presented.connect(func(event: Dictionary):
		if event.type != "damage": return
		hp_after.append(int(event.payload.absorption.hp_after))
		check(view._actors.p_swordsman.hpbar.value == hp_after.back(), "连续两个敌方指令按各次伤害事件显示中间HP")
		check(not view._presentation_views[event.actor_id].is_action_busy(), "连续指令各自等待真实来源动作完成"))
	view.processing = true
	view._continue_after_action()
	var committed: Dictionary = view.engine.snapshot()
	view._render()
	check(view._actors.p_swordsman.hpbar.value == before.actors.p_swordsman.hp, "同批多次敌伤提交后仍先显示初始HP")
	await _drain(view)
	check(hp_after.size() == 2 and hp_after[0] > hp_after[1] and hp_after[1] == committed.actors.p_swordsman.hp, "连续伤害展示完整中间值并落到最终快照")
	check(view.engine.snapshot() == committed, "连续敌方表现不多结算任一指令")
	view.free()

func _test_cancel_retry(cancellation: String) -> void:
	var view := _make_view(true)
	var result := _submit(view)
	# deferred 排队尚未取出时保留真实事件；取消后旧令牌不能回写新战斗。
	var old_event: Dictionary = view._hd_player._batches[0].events.filter(func(event): return event.type == "damage")[0].duplicate(true)
	await process_frame
	await process_frame
	match cancellation:
		"view": view._cancel_presentation()
		"player": view._hd_player.cancel()
		"unbind": view._hd_player.bind_actors({})
		"exit": root.remove_child(view)
	var w: Dictionary = view._actors.p_swordsman
	check(not view._hd_player.is_busy() and view._pending_hp_events.is_empty() and view._display_hp.is_empty() and view._display_shields.is_empty() and view._display_statuses.is_empty(), cancellation + "取消清空所有显示快照令牌")
	check(w.hpbar.value == 0 and not w.status.visible and w.title.text.contains("倒地") and w.sprite.modulate != Color.WHITE and w.sprite.is_downed(), cancellation + "取消时生命盾状态灰态与倒地全部同步已提交结果")
	var duplicate: Dictionary = view.engine.submit(result.command)
	check(not duplicate.accepted and view.engine.snapshot() == result.committed, cancellation + "重试已提交指令不会二次伤害或耗资源")
	if cancellation == "exit": root.add_child(view)
	var replacement := _make_view(false)
	var expected: Dictionary = replacement.engine.snapshot()
	view.bind(replacement.engine, null)
	await _drain(view)
	if not old_event.is_empty(): view._on_event_presented(old_event)
	check(view.engine.snapshot() == expected and view._actors.p_swordsman.hpbar.value == expected.actors.p_swordsman.hp and not view._actors.p_swordsman.sprite.is_downed(), cancellation + "重绑重试不会被旧表现令牌污染")
	var retry := _submit(view)
	check(view._actors.p_swordsman.hpbar.value == retry.before.actors.p_swordsman.hp, cancellation + "新战斗同名命令仍可正常延迟显示")
	await _drain(view)
	check(view._actors.p_swordsman.hpbar.value == retry.committed.actors.p_swordsman.hp and view.engine.snapshot() == retry.committed, cancellation + "重试的新表现完成且仅对应一次真实提交")
	view.free(); replacement.free()

# 使用真实 3D 桥接与 ShaderMaterial，不能只断言隐藏的 2D 来源颜色。
func _test_projected_tint() -> void:
	for cancel in [false, true]:
		var view := _make_view(true)
		var backdrop := Backdrop.new()
		view._canvas.add_child(backdrop)
		backdrop.configure({})
		view._world_backdrop = backdrop
		backdrop.bind_visuals(view._actors)
		var body: Sprite3D = backdrop.actor_entries.p_swordsman.body
		var observed: Array[String] = []
		view._hd_player.event_presented.connect(func(event: Dictionary):
			if event.type not in ["damage", "actor_defeated", "revived"]: return
			observed.append(event.type)
			if event.type == "actor_defeated":
				var expected_texture: Texture2D = view._hd_views.p_swordsman.animator.sprite.sprite_frames.get_frame_texture("down", 0)
				check(body.get_meta("logical_frame_texture_id") == expected_texture.get_instance_id(), "actor_defeated同帧实际3D使用已启动的down首帧而非旧hit纹理")
				return
			var expected: Color = view._actors.p_swordsman.sprite.modulate
			check(body.material_override.get_shader_parameter("appearance_tint") == expected, event.type + "事件同帧实际3D材质颜色与HP标题同步"))
		_submit(view)
		check(body.material_override.get_shader_parameter("appearance_tint") == Color.WHITE, "命中前实际3D材质不提前灰化")
		if cancel:
			var opacity_before: Array = backdrop.geometry._tree_occluders.map(func(entry): return entry.opacity)
			view._hd_player.cancel()
			check(body.material_override.get_shader_parameter("appearance_tint") == view._actors.p_swordsman.sprite.modulate, "取消同帧实际3D材质与已提交倒地HUD同步")
			check(backdrop.geometry._tree_occluders.map(func(entry): return entry.opacity) == opacity_before, "即时材质对齐不额外推进遮挡渐隐时钟")
		else:
			await _drain(view)
			view.engine.advance(false)
			var before: Dictionary = view.engine.snapshot()
			var command := {"command_id":"enemy_impact_revive", "expected_revision":int(before.revision), "actor_id":before.active_actor_id, "kind":"item", "ability_id":"revival_potion", "target_ids":["p_swordsman"]}
			var result: Dictionary = view.engine.submit(command)
			check(result.accepted, "真实存活队友可合法使用复苏药")
			var committed: Dictionary = view.engine.snapshot()
			view._consume_events(result.events, before)
			view._render()
			check(view._actors.p_swordsman.hpbar.value == 0 and view._actors.p_swordsman.sprite.is_downed(), "复苏使用标记前保持旧0HP与个人倒地")
			await _drain(view)
			check(observed == ["damage", "actor_defeated", "revived"] and not view._actors.p_swordsman.sprite.is_downed(), "真实复苏按原item标记解除倒地")
			check(view.engine.snapshot() == committed and committed.inventory.revival_potion == 1, "复苏呈现不重复消耗或修改模型")
		view.free()

func _drain(view: FixtureView) -> void:
	for tick in range(240):
		if not view._hd_player.is_busy(): break
		await process_frame
	check(not view._hd_player.is_busy(), "敌方队列在现有动作时限内结束")
