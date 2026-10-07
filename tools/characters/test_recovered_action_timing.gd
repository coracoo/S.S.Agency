# 恢复版仍须保持原生毫秒时基；用真实加载器证明短帧不被Godot最小时长截断。
extends SceneTree
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const Actor = preload("res://scripts/rpg/ui/hd_actor_view.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _seconds(frames: SpriteFrames, action: StringName) -> float:
	var duration := 0.0
	for frame in frames.get_frame_count(action): duration += frames.get_frame_duration(action,frame) / frames.get_animation_speed(action)
	return duration
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var page := Image.create(8,8,false,Image.FORMAT_RGBA8)
	page.fill(Color.WHITE)
	check(page.save_png("user://timing.png") == OK,"在隔离目录写入微型透明页")
	var manifest := {"identity_id":"rinne","form_id":"rinne","move_speed_mps":2.6,"canvas":{"w":8,"h":8,"anchor":[4,7],"content_height_px":6,"height_m":1.68},"packed_frames":{},"anims":{}}
	for action in ["idle","walk","attack","battle_dash"]:
		manifest.packed_frames[action] = {"atlas":"user://missing_world_only.png" if action == "walk" else "user://timing.png","atlas_size":[8,8],"region":[0,0,8,8],"offset":[0,0]}
		manifest.anims[action] = {"frames":[action,action,action],"durations_ms":[1,4,80],"loop":action in ["idle","walk"]}
	manifest.anims.attack.impact_ms = 5
	var file := FileAccess.open("user://timing.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest)); file.close()
	var definition := Definition.load_definition("user://timing.json","battle")
	check(definition.get("ok",false),"battle不加载缺失的world专用页")
	if not definition.get("ok",false): quit(1); return
	check(not definition.frames.has_animation("walk"),"battle没有完整world跑步动作")
	check(definition.frames.has_animation("battle_dash"),"battle加载紧凑闪身专用动作")
	for action in ["idle","attack","battle_dash"]:
		if not definition.frames.has_animation(action): continue
		check(is_equal_approx(_seconds(definition.frames,action),.085),"保留1/4/80ms累计85ms："+action)
		for frame in 3:
			check(is_equal_approx(definition.frames.get_frame_duration(action,frame)/definition.frames.get_animation_speed(action),float([1,4,80][frame]) / 1000.0),"每个短帧仍是原生时长："+action)
	check(definition.manifest.anims.attack.impact_ms == 5,"资源时基修正不改命中标记")
	var actor := Actor.new(); root.add_child(actor)
	check(actor.configure(definition,319.2,-1) and actor.play_action(&"attack"),"真实战斗演员接受加载后的完整动作")
	check(is_equal_approx(actor.action_timeout()-.35,.085),"真实演员收招长度沿用85ms")
	check(is_equal_approx(actor.action_impact_time(),.005),"真实演员命中仍在5ms")
	actor.free()
	print("RECOVERED_ACTION_TIMING: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
