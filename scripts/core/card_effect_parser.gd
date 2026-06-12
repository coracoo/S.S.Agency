class_name CardEffectParser
extends RefCounted

static func resolve_effects(effects: Array, ctx: Dictionary) -> Array:
	var results = []
	for e in effects:
		results.append(_resolve(e, ctx))
	return results

static func _resolve(effect: Dictionary, ctx: Dictionary) -> Dictionary:
	var t = effect.get("type", "")
	match t:
		"deal_damage":
			return _deal_damage(effect, ctx)
		"heal":
			return _heal(effect, ctx)
		"move_to":
			return {"type": "move_to", "moved": true}
		"buff_stat":
			return {"type": "buff_stat", "shield_amount": effect.get("value", 0)}
		"draw_cards":
			return {"type": "draw_cards", "drawn_cards": effect.get("value", 1)}
		"gain_energy":
			return {"type": "gain_energy", "gained_energy": effect.get("value", 1)}
		"apply_status":
			return {"type": "apply_status", "status_id": effect.get("statusId", ""), "status_duration": effect.get("duration", 1)}
		"lifesteal":
			return {"type": "lifesteal", "ratio": effect.get("ratio", 0.3)}
		"pull":
			return {"type": "pull", "distance": effect.get("distance", 1)}
		"retreat":
			return {"type": "retreat", "distance": effect.get("distance", 1)}
		"add_terrain_effect":
			return {"type": "add_terrain_effect", "effect": effect.get("effect", "fire")}
		"create_noise":
			return {"type": "create_noise", "volume": effect.get("volume", 3), "duration": effect.get("duration", 1), "source_type": effect.get("sourceType", "card")}
		"push_unit":
			return {"type": "push_unit", "distance": effect.get("distance", 1)}
		_:
			return {"type": "unknown"}

static func _deal_damage(effect: Dictionary, ctx: Dictionary) -> Dictionary:
	var base = effect.get("value", 0)
	var scaling = 0
	var sc = effect.get("scaling", {})
	if not sc.is_empty():
		var stat_key = sc.get("stat", "intelligence")
		var caster_stats = ctx.get("caster_stats", {})
		scaling = int(caster_stats.get(stat_key, 0) * sc.get("multiplier", 0.0))

	var raw = base + scaling
	var defense = 0
	var dmg_type = effect.get("damageType", "physical")
	var target_stats = ctx.get("target_stats", {})
	if dmg_type == "physical":
		defense = int(target_stats.get("defense", 0) * 0.5)
	elif dmg_type == "magic":
		defense = int(target_stats.get("magic_resist", 0) * 0.3)
	var defense_modifier = ctx.get("target_defense_modifier", 1.0)
	defense = int(defense * defense_modifier)

	var final_dmg = maxi(1, raw - defense)

	# Terrain dodge check
	var dodge_chance = int(ctx.get("target_dodge", 0))
	if dodge_chance > 0 and randi() % 100 < dodge_chance:
		return {"type": "deal_damage", "damage": 0, "dodged": true, "damage_type": dmg_type}

	return {"type": "deal_damage", "damage": final_dmg, "damage_type": dmg_type}

static func _heal(effect: Dictionary, ctx: Dictionary) -> Dictionary:
	var base = effect.get("value", 0)
	var scaling = 0
	var sc = effect.get("scaling", {})
	if not sc.is_empty():
		var caster_stats = ctx.get("caster_stats", {})
		scaling = int(caster_stats.get(sc.get("stat", "intelligence"), 0) * sc.get("multiplier", 0.0))
	return {"type": "heal", "heal_amount": base + scaling}
