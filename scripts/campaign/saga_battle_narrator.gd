# 战中原文只响应实际事件；相同提示每场一次，不将未发生的胜败或反射提前叙述。
extends RefCounted
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
static func _path(value: Dictionary, path: String):
	var current: Variant = value
	for key in path.split("."):
		if not current is Dictionary or not current.has(key): return null
		current = current[key]
	return current
static func select(lines: Array, event: Dictionary, saved: Dictionary, seen: Dictionary, actors: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	for index in range(lines.size()):
		var line: Dictionary = lines[index]
		var trigger: Dictionary = line.get("event", {})
		if trigger.is_empty() or trigger.get("type") != event.get("type"): continue
		var key := str(line.get("source_index", index)) + ":" + str(line.get("text", ""))
		if seen.has(key) and line.get("once_per_battle", true): continue
		if not Saga.matches(line.get("when", {}), Saga.context(saved.get("saga", {}))): continue
		var selected: String = str(saved.get("saga", {}).get("choices", {}).get(saved.get("saga", {}).get("active_scene", ""), ""))
		if not str(line.get("choice_id", "")).is_empty() and line.choice_id != selected: continue
		if trigger.has("excluded_actor") and saved.get("party", []).has(trigger.excluded_actor): continue
		if trigger.has("required_actor") and not saved.get("party", []).has(trigger.required_actor): continue
		if trigger.has("actor_id") and event.get("actor_id") != trigger.actor_id: continue
		if trigger.has("target_id") and event.get("target_id") != trigger.target_id: continue
		if trigger.has("actor_side") and actors.get(event.get("actor_id", ""), {}).get("side") != trigger.actor_side: continue
		if trigger.has("target_side") and actors.get(event.get("target_id", ""), {}).get("side") != trigger.target_side: continue
		if trigger.has("target_class") and actors.get(event.get("target_id", ""), {}).get("class_id") != trigger.target_class: continue
		if trigger.has("min_targets") and event.get("payload", {}).get("resolved_target_ids", []).size() < int(trigger.min_targets): continue
		var matches := true
		for path in trigger.get("requires", {}):
			if _path(event.get("payload", {}), path) != trigger.requires[path]: matches = false
		if not matches: continue
		seen[key] = true
		var speaker: String = str(line.get("speaker", ""))
		result.append((speaker + "：" if not speaker.is_empty() else "") + str(line.get("text", "")))
	return result
