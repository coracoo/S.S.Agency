class_name Pathfinding
extends RefCounted

const INF_COST := 999999

static func get_reachable_tiles(map: GameMap, start: Vector2i, max_steps: int) -> Array:
	var best_cost = {}
	var queue = [{"pos": start, "steps": 0}]
	best_cost[start] = 0
	var result = []

	while queue.size() > 0:
		queue.sort_custom(func(a, b): return a.steps < b.steps)
		var current = queue.pop_front()
		if current.steps != best_cost.get(current.pos, current.steps):
			continue
		if current.steps > 0:
			result.append(current.pos)
		if current.steps >= max_steps:
			continue
		for neighbor in map.get_neighbors(current.pos):
			if not map.is_walkable(neighbor):
				continue
			if map.is_occupied(neighbor):
				continue
			var cost = map.get_move_cost(neighbor)
			var next_steps = current.steps + cost
			if next_steps > max_steps:
				continue
			if next_steps < best_cost.get(neighbor, INF_COST):
				best_cost[neighbor] = next_steps
				queue.append({"pos": neighbor, "steps": next_steps})

	return result

static func find_path(map: GameMap, start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return [start] if map.is_walkable(start) else []

	var open_set = []
	var came_from = {}
	var g_score = {}
	g_score[start] = 0
	open_set.append({"pos": start, "f": _heuristic(start, goal)})

	while open_set.size() > 0:
		var best_idx = 0
		for i in range(1, open_set.size()):
			if open_set[i].f < open_set[best_idx].f:
				best_idx = i
		var current = open_set[best_idx]
		open_set.remove_at(best_idx)
		var pos = current.pos

		if pos == goal:
			return _reconstruct(came_from, pos)

		for neighbor in map.get_neighbors(pos):
			if not map.is_walkable(neighbor):
				continue
			if map.is_occupied(neighbor) and neighbor != goal:
				continue
			var tent_g = g_score.get(pos, INF_COST) + map.get_move_cost(neighbor)
			if tent_g < g_score.get(neighbor, INF_COST):
				came_from[neighbor] = pos
				g_score[neighbor] = tent_g
				var f = tent_g + _heuristic(neighbor, goal)
				var found = false
				for item in open_set:
					if item.pos == neighbor:
						item.f = f
						found = true
						break
				if not found:
					open_set.append({"pos": neighbor, "f": f})

	return []

static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array:
	var path = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path
