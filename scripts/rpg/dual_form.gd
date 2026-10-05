# One Homura actor owns both existing careers, one resource pool and one slot.
class_name RpgDualForm
extends RefCounted
const VERSION := 1
const FORM_CLASSES := {"sword": "swordsman", "mage": "mage"}
const LOCKED_FORMS := ["sword"]
const UNLOCKED_FORMS := ["sword", "mage"]

static func has_data(actor: Dictionary) -> bool:
	return actor.has("dual_form_version") or actor.has("active_class_id") or actor.has("unlocked_forms")

static func enabled(actor: Dictionary) -> bool:
	if not actor.get("dual_form_version") is int or actor.dual_form_version != VERSION: return false
	for field in ["actor_id", "identity_id", "side", "class_id"]:
		if not actor.get(field) is String: return false
	return actor.actor_id == "p_mage" and actor.identity_id == "homura" and actor.side == "player" and actor.class_id == "mage"

static func active_class(actor: Dictionary) -> String:
	if enabled(actor) and actor.get("form_id") is String and FORM_CLASSES.has(actor.form_id): return FORM_CLASSES[actor.form_id]
	return str(actor.get("class_id", ""))

static func initialize(actor: Dictionary, catalog: RefCounted) -> void:
	actor["dual_form_version"] = VERSION
	actor["unlocked_forms"] = LOCKED_FORMS.duplicate()
	apply(actor, "sword", catalog)

static func apply(actor: Dictionary, form_id: String, catalog: RefCounted) -> void:
	actor["form_id"] = form_id
	actor["active_class_id"] = FORM_CLASSES[form_id]
	actor["skill_ids"] = catalog.get_definition("classes", FORM_CLASSES[form_id]).skill_ids.duplicate()

static func available_skills(actor: Dictionary, catalog: RefCounted) -> Array:
	if not enabled(actor): return actor.get("skill_ids", []).duplicate() if actor.get("skill_ids") is Array else []
	var skills: Array = []
	if not actor.get("unlocked_forms") is Array: return skills
	for form in actor.unlocked_forms:
		if not form is String or not FORM_CLASSES.has(form): continue
		for id in catalog.get_definition("classes", FORM_CLASSES[form]).get("skill_ids", []):
			if not skills.has(id): skills.append(id)
	return skills

static func validate(actor: Dictionary, catalog: RefCounted) -> Array[String]:
	var errors: Array[String] = []
	if not actor.get("dual_form_version") is int or actor.dual_form_version != VERSION: errors.append("双职业版本非法")
	for field in ["actor_id", "identity_id", "side", "class_id", "form_id", "active_class_id"]:
		if not actor.get(field) is String: errors.append("双职业字符串字段非法：" + field)
	if not actor.get("unlocked_forms") is Array or not actor.get("skill_ids") is Array: errors.append("双职业解锁/技能字段必须为数组")
	if not errors.is_empty(): return errors
	if not enabled(actor): errors.append("双职业只能属于同一个焰华p_mage")
	if not FORM_CLASSES.has(actor.form_id): return ["未登记焰华形态"]
	if actor.unlocked_forms != LOCKED_FORMS and actor.unlocked_forms != UNLOCKED_FORMS: errors.append("焰华形态解锁集合非法")
	if not actor.unlocked_forms.has(actor.form_id): errors.append("当前焰华形态尚未解锁")
	if actor.active_class_id != FORM_CLASSES[actor.form_id]: errors.append("焰华形态与当前职业不符")
	if actor.skill_ids != catalog.get_definition("classes", FORM_CLASSES[actor.form_id]).get("skill_ids", []): errors.append("焰华当前四技能必须匹配既有职业")
	return errors

static func switch_reason(actor: Dictionary, form_id: String) -> String:
	if not enabled(actor) or not actor.get("form_id") is String or not actor.get("unlocked_forms") is Array: return "只有焰华本人可切换职业"
	if not FORM_CLASSES.has(form_id): return "未登记的焰华形态"
	if not actor.get("unlocked_forms", []).has(form_id): return "法师形态尚未解锁"
	if actor.form_id == form_id: return "已在当前形态"
	return ""

static func valid_switch_command(command: Dictionary) -> bool:
	if command.size() != 7: return false
	for field in ["command_id", "actor_id", "kind", "ability_id", "form_id"]:
		if not command.get(field) is String: return false
	if command.command_id.is_empty() or command.actor_id.is_empty() or command.kind != "switch_form" or not command.ability_id.is_empty() or not FORM_CLASSES.has(command.form_id): return false
	return command.get("expected_revision") is int and command.get("target_ids") is Array and command.target_ids.is_empty()
