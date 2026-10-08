# 机关对白分段及地图表现门禁；模型API接入后追加真实操作、恢复和故障事务验证。
extends SceneTree
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Rules = preload("res://scripts/campaign/mechanism_rules.gd")
var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ",message)

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2);return
	_run.call_deferred()

func _run() -> void:
	_test_segments()
	check(ResourceLoader.exists("res://scripts/campaign/mechanism_layer.gd"),"六类机关必须有真实地图表现模块")
	if ResourceLoader.exists("res://scripts/campaign/mechanism_layer.gd"): await _test_geometry()
	print("MECHANISM_STAGE: %d assertions, %d failures" % [assertions,failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_segments() -> void:
	var stage: Script = load("res://scripts/campaign/saga_stage.gd")
	check(stage.has_method("next_story_segment"),"对白必须先经source_index机关停点路由")
	if not stage.has_method("next_story_segment"): return
	var water: Array = Saga.scene("C2-10").lines
	var before := water.duplicate(true)
	var segment: Dictionary = stage.next_story_segment(water,[{"before_source_index":7,"mechanism_id":"water_echo"}],0)
	check(_indices(segment.lines) == [1,2,3,4,5,6] and not segment.gate.is_empty(),"水口只播操作前1–6，不能先播成功来源7")
	check(segment.next_source_index == 7 and not segment.complete and water == before,"停点不改批准对白且保留下一来源位置")
	segment = stage.next_story_segment(water,[],7)
	check(_indices(segment.lines) == [7,8,9,10,11,12] and segment.complete,"水口完整实验证据满足后才续播7–12")
	var ferry: Array = Saga.scene("C3-16").lines
	segment = stage.next_story_segment(ferry,[{"before_source_index":1,"mechanism_id":"ferry"}],0)
	check(segment.lines.is_empty() and not segment.complete,"修渡结构未完成时不能播第一句成功叙述")
	segment = stage.next_story_segment(ferry,[{"before_source_index":5,"mechanism_id":"ferry"}],1)
	check(_indices(segment.lines) == [1,2,3,4],"修好结构后先播1–4，再停住空船试航来源5")
	var junction: Array = Saga.scene("C6-08").lines
	for span in [[0,12],[12,14],[14,17]]:
		segment = stage.next_story_segment(junction,[{"before_source_index":span[1],"mechanism_id":"junction"}],span[0])
		check(segment.lines.all(func(line): return line.source_index >= span[0] and line.source_index < span[1]),"双线机关在12/14/17前逐次停住")
		check(not segment.complete and segment.next_source_index == span[1],"双线未满足停点不会自动结束本场")
	var ward: Array = Saga.scene("C6-09").lines
	segment = stage.next_story_segment(ward,[{"before_source_index":8,"mechanism_id":"ward_test"}],0)
	check(_indices(segment.lines) == [1,2,3,4,5,6,7],"停阵首验前只播1–7")
	segment = stage.next_story_segment(ward,[{"before_source_index":13,"mechanism_id":"ward_test"}],8)
	check(_indices(segment.lines) == [8,9,10,11,12] and not segment.complete,"源13虽不在lines仍是换手操作屏障")
	segment = stage.next_story_segment(ward,[],13)
	check(_indices(segment.lines) == [14] and segment.complete,"不同操作者复验后才播来源14")
	var driftwood: Array = Saga.choice("C6-S03","a").lines
	var not_repaired: Array = driftwood.filter(func(line): return not line.get("when",{}).get("ferry_repaired",false))
	segment = stage.next_story_segment(not_repaired,[{"before_source_index":10,"mechanism_id":"ferry"}],0)
	check(_indices(segment.lines) == [8,9],"未修渡支线先播8–9再回地图补修")
	segment = stage.next_story_segment(not_repaired,[{"before_source_index":17,"mechanism_id":"driftwood"}],10)
	check(_indices(segment.lines) == [10,11,15,16],"补修完成后仍停在实际担架走通的来源17前")
	var repaired: Array = driftwood.filter(func(line): return line.get("when",{}).get("ferry_repaired",true))
	segment = stage.next_story_segment(repaired,[{"before_source_index":17,"mechanism_id":"driftwood"}],0)
	check(_indices(segment.lines) == [13,15,16],"已修分支不会重放未修成功叙述，也不能跳过清路")
	var alley: Dictionary = Saga.choice("C6-S04","a")
	segment = stage.next_story_segment(alley.lines,[{"before_source_index":8,"mechanism_id":"alley"}],0)
	check(_indices(segment.lines) == [7] and not segment.complete,"choice通道末尾仍停8前，准备不足不能开原短战")
	segment = stage.next_story_segment(alley.after_lines,[{"before_source_index":11,"mechanism_id":"alley"}],0)
	check(segment.lines.is_empty() and not segment.complete,"战后先拆远镜，不能直接播放来源12后的对白")
	segment = stage.next_story_segment(alley.after_lines,[{"before_source_index":15,"mechanism_id":"alley"}],11)
	check(_indices(segment.lines) == [12,13,14] and not segment.complete,"战后对白12–14后仍须实地引导接应")
	segment = stage.next_story_segment(alley.after_lines,[],15)
	check(segment.lines.is_empty() and segment.complete,"来源15引导完成后才允许场次结束")
	segment = stage.next_story_segment(water,[{"before_source_index":7,"mechanism_id":"water_echo"}],10)
	check(segment.lines.is_empty() and not segment.complete,"旧呈现游标也不能越过尚未满足的较早门禁")

func _indices(lines: Array) -> Array:
	return lines.map(func(line): return int(line.source_index))

func _test_geometry() -> void:
	var layer_script: Script = load("res://scripts/campaign/mechanism_layer.gd")
	check(layer_script.can_instantiate(),"机关表现脚本实际可实例化")
	if not layer_script.can_instantiate(): return
	for chapter in [2,3,6]:
		# 这里只检查只读可见几何投影；完整模型事务与真实行走在下方接入测试另外验证。
		var saved := {"mechanisms":Rules.initial(),"saga":{"chapter":chapter,"events":[],"battles":[],"battle_encounters":{}}}
		var layer: Node3D = layer_script.new()
		root.add_child(layer)
		layer.configure(saved)
		await process_frame
		check(layer.groups.size() == {2:1,3:1,6:5}[chapter],"本章只建立登记的可见机关：%d" % chapter)
		var visible_parts:Array={2:[["water_echo","basin"],["water_echo","block"],["water_echo","mirror_edge"]],3:[["ferry","old_board"],["ferry","pile"],["ferry","new_board"]],6:[["junction","rod"],["ward_test","pin"],["driftwood","log_0"],["alley","far_mirror"]]}[chapter]
		check(visible_parts.all(func(pair):return layer.part(pair[0],pair[1]) is MeshInstance3D),"真实操作对象有对应网格；不以任意网格数量冒充视觉质量")
		check(layer.find_children("*","CollisionShape3D",true,false).size()==(1 if chapter==6 else 0),"仅漂木本体有局部碰撞，其余观察站不堵主干道")
		if chapter == 2:
			var raised: float = layer.part("water_echo","block").position.y
			saved.mechanisms.states.water_echo.step = 2
			layer.sync(saved)
			await process_frame
			check(layer.part("water_echo","block").position.y < raised and layer.views.water_echo.visual.bell_stopped,"隔断放下后水挡落下、钟立即停住")
			saved.mechanisms.states.water_echo.step = 4
			layer.sync(saved)
			check(layer.part("water_echo","block").position.y == raised and not layer.views.water_echo.visual.bell_stopped,"撤回隔断后恢复同音水纹状态")
		elif chapter == 3:
			var start: Vector3 = layer.part("ferry","boat").position
			saved.mechanisms.states.ferry.step = 7
			var immutable := saved.duplicate(true)
			layer.animate_commit(saved,{"mechanism_id":"ferry","action_id":"sail_out","visual_duration":1.6})
			await create_timer(.45).timeout
			var middle: Vector3 = layer.part("ferry","boat").position
			var destination: Array = Rules.definition("ferry").boat_paths["3"][1]
			check(layer.animating and middle.x > start.x and middle.x < float(destination[0]),"空船去程存在可采样的连续中间位置")
			while layer.animating: await process_frame
			check(layer.part("ferry","boat").position == Vector3(destination[0],destination[1],destination[2]),"去程动画抵达登记远岸")
			check(saved == immutable and saved.mechanisms.states.ferry.step == 7,"动画结束不修改源快照，不自动完成回程")
			saved.mechanisms.states.ferry.step = 8;saved.mechanisms.states.ferry.complete = true
			await layer.animate_commit(saved,{"mechanism_id":"ferry","action_id":"sail_back","visual_duration":1.6})
			check(layer.part("ferry","boat").position == start,"独立回程动作回到原岸")
			check(layer.part("ferry","brace").visible and layer.part("ferry","new_board").visible and not layer.part("ferry","old_board").visible,"修渡状态实际显示副桩支撑、替换木板")
			check(layer.part("ferry","nails").scale.y < .2 and layer.part("ferry","lamp_glass").position.y > 1.5,"钉头压平和灯升高均有几何变化")
		else:
			saved.mechanisms.states.junction.step = 3
			saved.mechanisms.states.ward_test.step = 3
			saved.mechanisms.states.alley.step = 2
			layer.sync(saved)
			check(layer.part("junction","support").visible and not layer.part("junction","lower").visible and not layer.part("junction","pin").visible,"双线先托杆、隔断下线并取走实销")
			check(not layer.part("junction","lamp_glass").material_override.emission_enabled,"取销不会擅自点亮普通灯")
			check(not layer.part("ward_test","inner").visible and layer.part("ward_test","outer").visible and layer.part("ward_test","outer_lamp_glass").material_override.emission_enabled,"内圈退出时外圈与外灯仍保留")
			check(layer.part("alley","near_cloth").visible and layer.part("alley","far_mirror").visible,"近镜遮好并不预先拆掉远镜")
			saved.mechanisms.states.junction.step = 4
			saved.mechanisms.states.ward_test.step = 5
			saved.mechanisms.states.driftwood.step = 6
			saved.mechanisms.states.alley.step = 5
			for id in ["junction","ward_test","driftwood","alley"]: saved.mechanisms.states[id].complete = true
			layer.sync(saved)
			check(layer.part("junction","lamp_glass").material_override.emission_enabled,"普通灯独立操作后实际发亮")
			check(layer.part("ward_test","exit_label").text.contains("换手复验完成"),"换手复验具有出口反馈")
			check(layer.part("driftwood","stretcher").position == Vector3(23,0,10) and layer.part("driftwood","checkpoint_2").visible,"担架终态在第三个实际检查位置")
			check(layer.part("driftwood","log_0").position.x > 21,"漂木从承力点移开，显示清开的通路")
			check(not layer.part("alley","far_mirror").visible and layer.part("alley","removed_mirror").visible and not layer.part("alley","loop").visible,"战后拆下远镜后镜路闭环消失")
			check(layer.part("alley","handoff_label").text.contains("渡河状态以现场记录为准"),"出巷接应不伪称已经渡河")
		layer.free()
