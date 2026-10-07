# 真实加载器的运行投影；对比清单变更前后的帧区域、虚拟画布、时长与技能阶段。
extends SceneTree
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const Effects = preload("res://scripts/rpg/ui/imagegen_effect_manifest.gd")
const FORMS := ["controller", "guard", "healer", "homura_mage", "homura_sword", "mint", "rinne"]
var failures := 0
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func rect(value: Rect2) -> Array:
	return [value.position.x, value.position.y, value.size.x, value.size.y]
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var snapshot := {"characters":{}, "effects":{}}
	for form in FORMS:
		var contexts := {}
		for context in ["full", "world", "battle"]:
			var definition: Dictionary = Definition.load_definition("res://assets/chars/pixel/%s/video_actions/manifest.json" % form, context)
			check(definition.get("ok", false), form + ":" + context)
			if not definition.get("ok", false): continue
			var animations := {}
			var sprites: SpriteFrames = definition.frames
			for action in sprites.get_animation_names():
				var frames := []
				for index in sprites.get_frame_count(action):
					var texture: AtlasTexture = sprites.get_frame_texture(action, index)
					frames.append({"region":rect(texture.region), "margin":rect(texture.margin), "duration":sprites.get_frame_duration(action, index), "size":[texture.get_width(), texture.get_height()], "atlas_size":[texture.atlas.get_width(), texture.atlas.get_height()], "clip":texture.filter_clip})
				animations[str(action)] = {"frames":frames, "speed":sprites.get_animation_speed(action), "loop":sprites.get_animation_loop(action)}
			contexts[context] = {"canvas":definition.manifest.canvas.duplicate(true), "animations":animations, "layer_count":definition.layer_frames.size()}
			definition.clear()
		snapshot.characters[form] = contexts
	for skill in ["firebolt", "flame_wave", "ice_arrow", "burn_brand"]:
		var blocked: Dictionary = Effects.load_effect(skill)
		check(not blocked.ok and blocked.reason == "production_disabled", skill + " 保持生产关闭")
		var effect: Dictionary = Effects.load_effect(skill, Effects.REGISTRY, true)
		check(effect.ok, skill + " 可显式预览")
		if not effect.ok: continue
		var frames := {}
		for id in effect.frames:
			var frame: Dictionary = effect.frames[id]
			frames[str(id)] = {"region":rect(frame.texture.region), "anchor":[frame.anchor.x, frame.anchor.y], "duration_ms":frame.duration_ms, "phase":frame.phase, "tail":frame.tail, "scale":frame.scale}
		var samples := {}
		for phase in effect.phases:
			var ids := []
			for step in range(101):
				ids.append(Effects.phase_frame(effect, phase, float(step) / 100.0).get("frame", 0))
			samples[phase] = ids
		snapshot.effects[skill] = {"frames":frames, "phases":effect.phases, "samples":samples, "atlas_sha256":effect.atlas_sha256, "texture_bytes":effect.texture_bytes, "display_size":effect.display_size, "particles":effect.particles, "blocked_reason":blocked.reason}
	var path := OS.get_environment("PUBLIC_RUNTIME_SNAPSHOT_PATH")
	check(not path.is_empty() and not path.begins_with("res://"), "投影证据位于项目外")
	if not path.is_empty():
		var output := FileAccess.open(path, FileAccess.WRITE)
		check(output != null, "写入投影证据")
		if output != null: output.store_string(JSON.stringify(snapshot, "\t", true)); output.close()
	print("PUBLIC_RUNTIME_SNAPSHOT: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)
