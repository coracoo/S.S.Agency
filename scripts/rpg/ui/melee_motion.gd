# 只给表现层提供有限的接近几何；不读取角色HP、技能目录或战斗随机数。
extends RefCounted
const APPROACH_SECONDS := 0.20
const RETURN_SECONDS := 0.22
const CONTACT_HOLD_SECONDS := 0.06
const REACH_BY_FORM := {"rinne":0.34,"guard":0.24,"homura_sword":0.34}

static func form_key(definition: Dictionary) -> String:
	var manifest: Dictionary = definition.get("manifest", {})
	var identity := str(manifest.get("identity_id", ""))
	return "homura_" + str(manifest.get("form_id", "")) if identity == "homura" else identity

static func is_melee_form(definition: Dictionary) -> bool:
	return REACH_BY_FORM.has(form_key(definition))

static func strike_point(home: Vector2, target: Vector2, body_height: float, form: String, target_radius: float, allowed_feet: Rect2) -> Vector2:
	var gap := maxf(24.0, target_radius) + body_height * float(REACH_BY_FORM.get(form,0.34))
	var distance := home.distance_to(target)
	if distance <= gap: return home
	var desired := target + (home-target).normalized()*gap
	return Vector2(clampf(desired.x,allowed_feet.position.x,allowed_feet.end.x),clampf(desired.y,allowed_feet.position.y,allowed_feet.end.y))
