# 只解析友方屏幕脚点；正交战场会将其反投影到原地面，不改变身高或战斗数据。
extends RefCounted
const Forms = preload("res://scripts/rpg/dual_form.gd")
const CANVAS_WIDTH := 1920.0
const COLUMNS := [1230.0,1470.0,1710.0]
const FRONT_CLASSES := ["swordsman","guard"]
const REAR_CLASSES := ["ranger","mage","healer","controller"]
const HOME_INSET := 1.0
const TARGET_WIDTH := 220.0

# 同类保持原party次序；role来自Catalog使用的当前形态职业，不以actor_id或外观猜测。
static func role_for_actor(actor: Dictionary) -> String:
	if actor.get("side") != "player": return ""
	var active_class := Forms.active_class(actor)
	if FRONT_CLASSES.has(active_class): return "front"
	if REAR_CLASSES.has(active_class): return "rear"
	return ""

# feet 是已经 near_side 镜像后的屏幕坐标；调用方只统一加一次framing shift。
# home_limits 可传入按整段动作与双朝向求得的脚域；不通过时拒绝静默越界。
# 未传home_limits的结果只是布局提案，不能据此声称任意替补/形态均通过近战门禁。
static func resolve(party_order: Array,actors: Dictionary,near_side: String = "right",ground_y: float = 740.0,home_limits: Dictionary = {}) -> Dictionary:
	if party_order.is_empty() or party_order.size() > COLUMNS.size(): return _failed("仅支持一至三名友方")
	if near_side not in ["right","left"] or not is_finite(ground_y): return _failed("画布方向或地面脚点无效")
	var front: Array[String] = []
	var rear: Array[String] = []
	var seen: Dictionary = {}
	for raw_id in party_order:
		if not raw_id is String or str(raw_id).is_empty(): return _failed("友方ID无效")
		var actor_id := str(raw_id)
		if seen.has(actor_id) or not actors.get(actor_id) is Dictionary: return _failed("友方ID重复或缺失："+actor_id)
		var actor: Dictionary = actors[actor_id]
		var role := role_for_actor(actor)
		if role.is_empty(): return _failed("友方身份或当前职业未登记："+actor_id)
		seen[actor_id] = true
		if role == "front": front.append(actor_id)
		else: rear.append(actor_id)
	var order: Array[String] = []
	order.append_array(front)
	order.append_array(rear)
	var feet: Dictionary = {}
	var roles: Dictionary = {}
	var slots: Dictionary = {}
	for lane in order.size():
		var actor_id: String = order[lane]
		var is_front := lane < front.size()
		var rank := lane if is_front else lane-front.size()
		# 默认2前1后：前脚点720/704，后脚点644；都保留在原740地面基准上方。
		var y_offset: float = -20.0-16.0*rank if is_front else -96.0+12.0*(rear.size()-1-rank)
		var foot := Vector2(COLUMNS[lane],ground_y+y_offset)
		if near_side == "left": foot.x = CANVAS_WIDTH-foot.x
		feet[actor_id] = foot
		roles[actor_id] = "front" if is_front else "rear"
		var actor: Dictionary = actors[actor_id]
		slots[actor_id] = {"lane":lane,"role":roles[actor_id],"identity_id":str(actor.get("identity_id","")),"initial_form_id":str(actor.get("form_id","")),"initial_class_id":Forms.active_class(actor),"foot":foot}
	var plan := {"ok":true,"error":"","feet":feet,"roles":roles,"slots":slots,"front":front,"rear":rear,"order":order,"home_limits_checked":false,"shared_shift_x":0.0}
	return fit_home_limits(plan,home_limits) if not home_limits.is_empty() else plan

# 全动作/双朝向安全域由调用方以真实camera求得，焰华须同时预留剑/法两形态。
# x只能共同平移：逐人clamp会令三近战中的guard与第二人重叠，破坏目标热区。
# y可逐人内收；不调整像素比例、镜头、动作帧或物理高度。
static func fit_home_limits(plan: Dictionary,home_limits: Dictionary) -> Dictionary:
	if not plan.get("ok",false): return _failed(str(plan.get("error","布局提案无效")))
	var minimum_shift := -INF
	var maximum_shift := INF
	var usable_limits: Dictionary = {}
	for actor_id in plan.order:
		var raw: Variant = home_limits.get(actor_id)
		if not raw is Rect2: return _failed("缺少全动作脚域："+str(actor_id))
		var allowed: Rect2 = raw
		if not allowed.position.is_finite() or not allowed.size.is_finite(): return _failed("全动作脚域非有限："+str(actor_id))
		allowed = allowed.grow(-HOME_INSET)
		if not allowed.has_area(): return _failed("全动作脚域不足："+str(actor_id))
		usable_limits[actor_id] = allowed
		var foot: Vector2 = plan.feet[actor_id]
		minimum_shift = maxf(minimum_shift,allowed.position.x-foot.x)
		maximum_shift = minf(maximum_shift,allowed.end.x-foot.x)
	if minimum_shift > maximum_shift: return _failed("全队无法共同内收；需要另审编队间距，不能逐人挤压")
	var shift_x := clampf(0.0,minimum_shift,maximum_shift)
	var fitted: Dictionary = plan.duplicate(true)
	for actor_id in fitted.order:
		var allowed: Rect2 = usable_limits[actor_id]
		var foot: Vector2 = fitted.feet[actor_id]
		foot.x += shift_x
		foot.y = clampf(foot.y,allowed.position.y,allowed.end.y)
		fitted.feet[actor_id] = foot
		fitted.slots[actor_id].foot = foot
	for a in range(fitted.order.size()):
		for b in range(a+1,fitted.order.size()):
			var first: Vector2 = fitted.feet[fitted.order[a]]
			var second: Vector2 = fitted.feet[fitted.order[b]]
			if absf(first.x-second.x) < TARGET_WIDTH: return _failed("目标热区横向重叠，拒绝提交新脚点")
	fitted.home_limits_checked = true
	fitted.shared_shift_x = shift_x
	return fitted

static func _failed(message: String) -> Dictionary:
	return {"ok":false,"error":message,"feet":{},"roles":{},"slots":{},"front":[],"rear":[],"order":[],"home_limits_checked":false,"shared_shift_x":0.0}
