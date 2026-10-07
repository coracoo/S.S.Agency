# 表现门禁等待真实资源与演员，避免把异步_ready误当作同步初始化。
extends RefCounted

static func wait_for_battle(tree: SceneTree, view: Control, party: Array) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if view._hd_failed: return {"ok": false, "error": view.last_error}
		if view._asset_loading or view.engine == null or view._hd_player == null: continue
		var ready: bool = view._hd_views.size() == party.size()
		for actor_id in party:
			if not view._hd_views.has(actor_id) or not view._actors.has(actor_id): ready = false
		if ready: return {"ok": true, "error": ""}
	return {"ok": false, "error": "等待战斗资源/引擎/高清演员超时：" + view.last_error}

static func rewards(started: Dictionary, outcome: String) -> Dictionary:
	return started.rewards.duplicate(true) if outcome == "victory" else {"coins": 0, "gear": {}, "items": {}, "cards": {}}
