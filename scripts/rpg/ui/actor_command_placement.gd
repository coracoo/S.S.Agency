# 仅计算逻辑画布中的矩形。角色、意图等保护区由调用方膨胀后传入。
extends RefCounted
const GAP := 18.0

static func choose(anchor: Rect2, desired: Vector2, compact: Vector2, obstacles: Array[Rect2], area: Rect2 = Rect2(24,116,1872,868)) -> Dictionary:
	area = area.abs()
	if not area.has_area(): return _result(Rect2(area.position,Vector2.ZERO),true,0.0)
	var preferred: Array[Rect2] = []
	if _fits(desired,area):
		var left := anchor.position.x-GAP-desired.x
		var right := anchor.end.x+GAP
		var sides: Array[float] = [left,right]
		if anchor.position.x-area.position.x < area.end.x-anchor.end.x: sides.reverse()
		for x in sides:
			for y in [anchor.get_center().y-desired.y*.5,anchor.position.y,anchor.end.y-desired.y]:
				_append_rect(preferred,Vector2(x,y),desired,area)
		for x in [anchor.get_center().x-desired.x*.5,anchor.position.x,anchor.end.x-desired.x]:
			_append_rect(preferred,Vector2(x,anchor.position.y-GAP-desired.y),desired,area)
	for rectangle in preferred:
		if _clear(rectangle,obstacles): return _result(rectangle,false,0.0)
	# 障碍边缘的交叉点可找到恰好可容纳的窄口，不依赖粗步长网格。
	var floating: Array[Rect2] = []
	if _fits(desired,area): floating = _edge_candidates(anchor,desired,obstacles,area)
	var clear_rectangle := Rect2()
	var distance := INF
	for rectangle in floating:
		if not _clear(rectangle,obstacles): continue
		var candidate_distance: float = rectangle.get_center().distance_squared_to(anchor.get_center())
		if candidate_distance < distance:
			clear_rectangle = rectangle
			distance = candidate_distance
	if clear_rectangle.has_area(): return _result(clear_rectangle,false,0.0)
	# compact的内部排版由view负责；这里只钳制外框，不改字号或人物尺寸。
	var dock_size := Vector2(clampf(compact.x,0.0,area.size.x),clampf(compact.y,0.0,area.size.y))
	var docked := _dock_candidates(anchor,dock_size,obstacles,area)
	for rectangle in docked:
		if _clear(rectangle,obstacles): return _result(rectangle,true,0.0)
	# 无空位时不假装成功：比较两种形态，返回最小遮挡和实际碰撞量。
	var best := _result(Rect2(area.position,Vector2.ZERO),true,INF)
	for rectangle in docked:
		var obstruction := _obstruction_area(rectangle,obstacles)
		if obstruction < float(best.obstruction_area): best = _result(rectangle,true,obstruction)
	preferred.append_array(floating)
	for rectangle in preferred:
		var obstruction := _obstruction_area(rectangle,obstacles)
		if obstruction < float(best.obstruction_area): best = _result(rectangle,false,obstruction)
	return best

static func _fits(size: Vector2, area: Rect2) -> bool:
	return size.is_finite() and size.x > 0.0 and size.y > 0.0 and size.x <= area.size.x and size.y <= area.size.y

static func _append_rect(candidates: Array[Rect2], position: Vector2, size: Vector2, area: Rect2) -> void:
	if not _fits(size,area): return
	var rectangle := Rect2(Vector2(clampf(position.x,area.position.x,area.end.x-size.x),clampf(position.y,area.position.y,area.end.y-size.y)),size)
	if not candidates.has(rectangle): candidates.append(rectangle)

static func _edge_candidates(anchor: Rect2, size: Vector2, obstacles: Array[Rect2], area: Rect2) -> Array[Rect2]:
	var xs: Array[float] = [area.position.x,area.end.x-size.x,anchor.get_center().x-size.x*.5]
	var ys: Array[float] = [area.position.y,area.end.y-size.y,anchor.get_center().y-size.y*.5]
	for obstacle in obstacles:
		if not obstacle.has_area(): continue
		xs.append_array([obstacle.position.x-size.x,obstacle.end.x])
		ys.append_array([obstacle.position.y-size.y,obstacle.end.y])
	xs.sort()
	ys.sort()
	var candidates: Array[Rect2] = []
	for x in xs:
		for y in ys: _append_rect(candidates,Vector2(x,y),size,area)
	return candidates

static func _dock_candidates(anchor: Rect2, size: Vector2, obstacles: Array[Rect2], area: Rect2) -> Array[Rect2]:
	var candidates: Array[Rect2] = []
	var xs: Array[float] = [area.get_center().x-size.x*.5,anchor.get_center().x-size.x*.5,area.position.x,area.end.x-size.x]
	var edges: Array[float] = []
	for obstacle in obstacles:
		if obstacle.has_area(): edges.append_array([obstacle.position.x-size.x,obstacle.end.x])
	edges.sort()
	xs.append_array(edges)
	# 固定贴area底边，保留调用方约定的miniHUD区域。
	for x in xs: _append_rect(candidates,Vector2(x,area.end.y-size.y),size,area)
	return candidates

static func _clear(rectangle: Rect2, obstacles: Array[Rect2]) -> bool:
	for obstacle in obstacles:
		if obstacle.has_area() and rectangle.intersects(obstacle): return false
	return true

static func _obstruction_area(rectangle: Rect2, obstacles: Array[Rect2]) -> float:
	# 扫描交集的竖条并合并Y区间；相互重叠的角色保护区只计一次。
	var intersections: Array[Rect2] = []
	var xs: Array[float] = []
	for obstacle in obstacles:
		if not rectangle.intersects(obstacle): continue
		var intersection := rectangle.intersection(obstacle)
		if not intersection.has_area(): continue
		intersections.append(intersection)
		if not xs.has(intersection.position.x): xs.append(intersection.position.x)
		if not xs.has(intersection.end.x): xs.append(intersection.end.x)
	if intersections.is_empty(): return 0.0
	xs.sort()
	var total := 0.0
	for index in range(xs.size()-1):
		var middle := (xs[index]+xs[index+1])*.5
		var intervals: Array[Vector2] = []
		for intersection in intersections:
			if intersection.position.x < middle and middle < intersection.end.x:
				intervals.append(Vector2(intersection.position.y,intersection.end.y))
		intervals.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		var covered := 0.0
		var start := 0.0
		var finish := 0.0
		var found := false
		for interval in intervals:
			if not found:
				start = interval.x
				finish = interval.y
				found = true
			elif interval.x <= finish:
				finish = maxf(finish,interval.y)
			else:
				covered += finish-start
				start = interval.x
				finish = interval.y
		if found: covered += finish-start
		total += (xs[index+1]-xs[index])*covered
	return total

static func _result(rectangle: Rect2, docked: bool, obstruction: float) -> Dictionary:
	return {"rect":rectangle,"docked":docked,"obstruction_area":obstruction}
