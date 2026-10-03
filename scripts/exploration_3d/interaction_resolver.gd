# 只选择一个可达交互点；相同输入产生相同稳定 ID。
extends RefCounted
static func choose(position: Vector3, targets: Array[Dictionary], flags: Dictionary) -> String:
	var candidates: Array[Dictionary] = []
	for target in targets:
		if not target.get("position") is Vector3: continue
		var allowed := true
		for required in target.get("requires", []): allowed = allowed and flags.get(required, false) == true
		if not allowed: continue
		var distance := position.distance_squared_to(target.position)
		if distance > pow(float(target.get("radius", 0)), 2): continue
		candidates.append({"id": str(target.get("id", "")), "distance": distance, "priority": int(target.get("priority", 0))})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(a.distance, b.distance): return a.distance < b.distance
		if a.priority != b.priority: return a.priority < b.priority
		return a.id < b.id)
	return "" if candidates.is_empty() else candidates[0].id
