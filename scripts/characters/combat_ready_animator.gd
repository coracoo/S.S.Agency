extends "res://scripts/characters/pixel_character_animator.gd"
## Static combat-ready prototype; action timing and down handling stay inherited.
const READY_ANIMATION: StringName = &"combat_ready_static"

func _update_locomotion() -> void:
	if definition.is_empty() or _locked or _down: return
	var reference := float(definition.manifest.move_speed_mps)
	if _speed > reference * 0.03 or not sprite.sprite_frames.has_animation(READY_ANIMATION):
		super._update_locomotion()
		return
	if sprite.animation != READY_ANIMATION or not sprite.is_playing():
		sprite.play(READY_ANIMATION)
	sprite.speed_scale = 1.0
	_update_layers()
