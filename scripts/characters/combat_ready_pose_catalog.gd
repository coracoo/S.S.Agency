extends RefCounted
## References existing loaded textures. No image generation or pose deformation.
const READY_ANIMATION := "combat_ready_static"
const POSES := {
	"rinne": {"form_id": "rinne", "animation": "defend", "frame": "retained_defend"},
	"guard": {"form_id": "guard", "animation": "defend", "frame": "retained_defend"},
	"mint": {"form_id": "mint", "animation": "attack", "frame": "attack_029"}
}

static func _failed(message: String) -> Dictionary:
	return {"ok": false, "combat_ready_error": message}

static func prepare(value: Dictionary) -> Dictionary:
	if not value.get("ok", false): return value
	var manifest: Dictionary = value.get("manifest", {})
	var identity := str(manifest.get("identity_id", ""))
	if not POSES.has(identity): return value
	var pose: Dictionary = POSES[identity]
	if str(manifest.get("form_id", "")) != str(pose.form_id):
		return _failed("Combat-ready prototype has no pose for this form: " + identity)
	var expected_dir := "res://assets/chars/pixel/" + identity + "/video_actions/frames/"
	if str(manifest.get("dir", "")) != expected_dir:
		return _failed("Combat-ready prototype requires the current video_actions definition: " + identity)
	var source_frames: SpriteFrames = value.get("frames")
	if source_frames == null or not source_frames.has_animation(str(pose.animation)):
		return _failed("Combat-ready source animation is not loaded: " + identity)
	var animations: Dictionary = manifest.get("anims", {})
	var source_spec: Dictionary = animations.get(str(pose.animation), {})
	var names: Array = source_spec.get("frames", [])
	var source_index := names.find(str(pose.frame))
	if source_index < 0 or source_index >= source_frames.get_frame_count(str(pose.animation)):
		return _failed("Combat-ready source frame is not loaded: " + identity + "/" + str(pose.frame))
	var texture := source_frames.get_frame_texture(str(pose.animation), source_index)
	if texture == null:
		return _failed("Combat-ready source texture is missing: " + identity)
	# Keep the AtlasTexture (including its virtual-canvas margins) by reference.
	# Duplicate the mutable animation resource, never its texture subresources.
	var prepared := value.duplicate(true)
	var prepared_manifest := manifest.duplicate(true)
	var prepared_frames := source_frames.duplicate(false) as SpriteFrames
	if prepared_frames == null:
		return _failed("Combat-ready SpriteFrames could not be copied: " + identity)
	if prepared_frames.has_animation(READY_ANIMATION):
		prepared_frames.remove_animation(READY_ANIMATION)
	prepared_frames.add_animation(READY_ANIMATION)
	prepared_frames.set_animation_speed(READY_ANIMATION, 1000.0)
	prepared_frames.set_animation_loop(READY_ANIMATION, true)
	prepared_frames.add_frame(READY_ANIMATION, texture, 1000.0)
	prepared_manifest.anims[READY_ANIMATION] = {
		"frames": [str(pose.frame)], "durations_ms": [1000.0],
		"loop": true, "single_pose": true, "static_prototype": true,
		"source_animation": str(pose.animation)
	}
	prepared.manifest = prepared_manifest
	prepared.frames = prepared_frames
	prepared.combat_ready_static = {
		"identity_id": identity, "form_id": str(pose.form_id),
		"source_animation": str(pose.animation), "source_frame": str(pose.frame),
		"source_index": source_index, "static_prototype": true
	}
	return prepared
