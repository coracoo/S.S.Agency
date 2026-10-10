# 无等级装配的唯一纯派生入口；不引用目录或双形态脚本，避免装配/目录循环依赖。
class_name RpgLoadoutRules
extends RefCounted

const DATA_PATH := "res://data/rpg/loadouts.json"
const Legacy = preload("res://scripts/rpg/legacy_loadout_rules.gd")
const BUILD_VERSION := 2
const IDENTITIES := {"guard":"guard","swordsman":"rinne","ranger":"mint","mage":"homura","healer":"healer","controller":"controller"}
const IDENTITY_NAMES := {"guard":"岑照","rinne":"凛音","mint":"薄荷","homura":"焰华","healer":"苏合","controller":"清明"}
const STAT_KEYS := ["hp", "mp", "atk", "matk", "def", "mdef", "spd"]
const SLOTS := ["weapon", "armor", "accessory"]
const MODIFIER_ZERO := {"mp_cost_add": 0, "cooldown_add": 0, "coefficient_add": 0.0, "duration_add": 0}
static var _cached_data: Dictionary = {}

static func has_data(actor: Dictionary) -> bool:
	return actor.has("build")

static func _legacy_actor(actor: Dictionary) -> bool:
	var build: Variant = actor.get("build")
	return build is Dictionary and build.get("version") == 1

static func default_build(class_id: String) -> Dictionary:
	var row: Dictionary = _data().get("classes", {}).get(class_id, {})
	if row.is_empty(): return {}
	return {"version": BUILD_VERSION, "active": row.active.duplicate(true), "passive": []}

static func initial_cards(version: int = BUILD_VERSION) -> Dictionary:
	if version == 1: return Legacy.initial_cards()
	return _data().get("initial_cards", {}).duplicate(true)

static func identity_for(actor: Dictionary) -> String:
	return str(actor.get("identity_id",IDENTITIES.get(actor.get("class_id",""),"")))

static func identity_label(actor: Dictionary) -> String:
	return str(IDENTITY_NAMES.get(identity_for(actor),"当前角色"))

static func card_allowed(actor: Dictionary, id: String, form: String = "") -> bool:
	var definition := card(id)
	if definition.is_empty() or definition.get("owner_identity","") != identity_for(actor): return false
	var current := form
	if current.is_empty(): current = str(actor.get("form_id","")) if actor.get("class_id") == "mage" else "default"
	return definition.allowed_forms.is_empty() or definition.allowed_forms.has(current)

static func can_magic_attack(actor: Dictionary, catalog: RefCounted) -> bool:
	var derived := derive(actor,catalog)
	if not derived.ok or not derived.weapon_tags.has("focus"): return false
	return _legacy_actor(actor) or identity_for(actor) in ["homura","healer","controller"]

static func skill_id_for_card(id: String) -> String:
	var definition := card(id)
	return str(definition.get("skill_id",id)) if definition.get("type") == "active" else ""

static func prepared_card(actor: Dictionary, skill_id: String, form: String = "") -> Dictionary:
	var value: Variant = actor.get("build")
	if not value is Dictionary or not value.get("active") is Dictionary: return {}
	var build: Dictionary = value
	if _legacy_actor(actor): return Legacy.card(skill_id)
	var current := form
	if current.is_empty(): current = str(actor.get("form_id","")) if actor.get("class_id") == "mage" else "default"
	for id in build.get("active",{}).get(current,[]):
		if skill_id_for_card(str(id)) == skill_id and card_allowed(actor,str(id),current): return card(str(id))
	return {}

static func needs_role_migration(snapshot: Dictionary) -> bool:
	if snapshot.get("schema_version") != 3: return false
	for actor in snapshot.get("roster",{}).values():
		if actor is Dictionary and _legacy_actor(actor): return true
	return false

static func upgrade_role_builds(snapshot: Dictionary, catalog: RefCounted) -> Dictionary:
	# 调用方先完整校验旧档，再备份原字节并原子提交；本函数不写盘、不发战果。
	var candidate := snapshot.duplicate(true)
	var removed: Array[String] = []
	var unlocked := initial_cards()
	for id in unlocked:
		candidate.cards[id] = maxi(int(candidate.cards.get(id,0)),int(unlocked[id]))
	for actor_id in candidate.roster:
		var actor: Dictionary = candidate.roster[actor_id]
		if not _legacy_actor(actor): continue
		var active: Dictionary = {}
		for form in actor.build.active:
			var prepared: Array[String] = []
			for old_id in actor.build.active[form]:
				var id: String = str(old_id)
				if identity_for(actor) == "homura" and form == "sword" and id in ["heavy_slash","armor_break","sweep","battle_spirit"]:
					id = "homura_"+id
				if card_allowed(actor,id,str(form)): prepared.append(id)
				else: removed.append(str(actor_id)+":"+str(old_id))
			active[form] = prepared
		var passive: Array[String] = []
		for id in actor.build.passive:
			if card_allowed(actor,str(id)): passive.append(str(id))
			else: removed.append(str(actor_id)+":"+str(id))
		actor.build = {"version":BUILD_VERSION,"active":active,"passive":passive}
		var derived := derive(actor,catalog)
		if not derived.ok: return {"ok":false,"error":"角色专属迁移派生失败："+"；".join(derived.errors)}
		actor.stats = derived.stats
		actor.skill_ids = derived.skill_ids
		actor.hp = mini(int(actor.hp),int(actor.stats.hp))
		actor.mp = mini(int(actor.mp),int(actor.stats.mp))
	return {"ok":true,"snapshot":candidate,"removed_cards":removed}

static func starting_equipment(class_id: String) -> Dictionary:
	var row: Dictionary = _data().get("classes", {}).get(class_id, {})
	if row.is_empty(): return {}
	return {"weapon": row.weapon_id, "armor": "standard_armor", "accessory": "standard_accessory"}

static func card(id: String) -> Dictionary:
	for row in _data().get("cards", []):
		if row.id == id: return row.duplicate(true)
	return {}

static func all_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row in _data().get("cards", []): result.append(row.duplicate(true))
	return result

static func derive(actor: Dictionary, catalog: RefCounted) -> Dictionary:
	# version1只用于合法旧档完整校验；Campaign写入入口拒绝继续提交旧构筑。
	if _legacy_actor(actor): return Legacy.derive(actor,catalog)
	var errors: Array[String] = []
	var result := {"ok": false, "errors": errors, "stats": {}, "skill_ids": [], "capacity": {"active_used": 0, "active_max": 10, "passive_used": 0, "passive_max": 4}, "weapon_tags": []}
	var data := _data()
	if data.is_empty():
		errors.append("装配数据结构或版本非法")
		return result
	if catalog == null or not catalog.has_method("get_definition"):
		errors.append("装配缺少合法数据目录")
		return result
	var class_id = actor.get("class_id")
	if not class_id is String or not data.classes.has(class_id):
		errors.append("装配身份未登记")
		return result
	# 两形态始终使用同一身份基底；主动卡无属性词条，切形不改变资源上限或速度。
	var baseline: Dictionary = data.classes[class_id]
	var stats: Dictionary = baseline.stats.duplicate(true)
	var equipment = actor.get("equipment")
	var weapon_tags: Array[String] = []
	if not equipment is Dictionary:
		errors.append("装备必须为字典")
	else:
		for slot in equipment:
			if not slot in SLOTS or not equipment[slot] is String:
				errors.append("装备槽或装备ID非法：" + str(slot))
				continue
			var id: String = equipment[slot]
			if id.is_empty(): continue
			var definition: Dictionary = catalog.get_definition("equipment", id)
			if definition.is_empty() or definition.get("slot") != slot:
				errors.append("装备不存在或槽位不符：" + id)
				continue
			_add_stats(stats, definition.get("stats"), data.equipment_stat_bounds, errors, "装备" + id, true)
			if slot == "weapon":
				if not data.weapons.has(id):
					errors.append("武器标签未登记：" + id)
					continue
				var mapping: Dictionary = data.weapons[id]
				var tags: Array = baseline.weapon_tags if mapping.get("use_class_tags", false) else mapping.get("tags", [])
				for tag in tags: weapon_tags.append(tag)
	result.weapon_tags = weapon_tags
	result.capacity.active_max = data.limits.active_capacity
	result.capacity.passive_max = data.limits.passive_capacity
	var build = actor.get("build")
	if not build is Dictionary:
		errors.append("装配build必须为字典")
		return result
	if build.size() != 3 or not build.has_all(["version", "active", "passive"]): errors.append("装配字段不完整或含未知字段")
	if not build.get("version") is int or build.version != BUILD_VERSION: errors.append("装配版本非法")
	if not build.get("active") is Dictionary or not build.get("passive") is Array:
		errors.append("主动配置必须为字典，被动配置必须为数组")
		return result
	var current := "default"
	var expected: Array = ["default"]
	if class_id == "mage":
		expected = ["sword", "mage"]
		if not actor.get("form_id") is String or not actor.form_id in expected:
			errors.append("焰华当前形态未登记")
			current = ""
		else: current = actor.form_id
	if build.active.size() != expected.size(): errors.append("身份主动配置数量不符")
	for form in build.active:
		if not form in expected: errors.append("身份含未登记主动配置：" + str(form))
	# 备用形态同样校验武器、卡位与容量；当前形态只决定输出技能与容量显示。
	for form in expected:
		var active = build.active.get(form)
		var checked := _check_cards(active,"active",weapon_tags,errors,form,actor,form)
		if form == current:
			result.skill_ids = checked.skills
			result.capacity.active_used = checked.used
		for skill_id in checked.skills:
			if catalog.get_definition("skills",skill_id).is_empty(): errors.append("招式数据未登记："+skill_id)
	var passive := _check_cards(build.passive,"passive",weapon_tags,errors,"角色被动",actor,current)
	result.capacity.passive_used = passive.used
	for id in passive.ids:
		_add_stats(stats, card(id).stats, data.card_stat_bounds, errors, "被动" + id, true)
	for key in STAT_KEYS:
		stats[key] = clampi(int(stats[key]), int(data.stat_bounds[key][0]), int(data.stat_bounds[key][1]))
	result.stats = stats
	result.ok = errors.is_empty()
	return result

static func validate_actor(actor: Dictionary, catalog: RefCounted, owned_cards: Variant = null) -> Array[String]:
	if _legacy_actor(actor): return Legacy.validate_actor(actor,catalog,owned_cards)
	var result := derive(actor, catalog)
	var errors: Array[String] = []
	errors.assign(result.errors)
	for key in ["level", "xp"]:
		if actor.has(key): errors.append("无等级角色不得含有" + key)
	if result.ok:
		var actual = actor.get("stats")
		if not actual is Dictionary or actual != result.stats:
			errors.append("角色属性与装配派生不符")
		elif actual is Dictionary:
			for key in actual:
				if not actual[key] is int: errors.append("角色派生属性必须为整数：" + str(key))
		if not actor.get("skill_ids") is Array or actor.skill_ids != result.skill_ids:
			errors.append("角色技能与当前装配不符")
	if owned_cards != null:
		if not owned_cards is Dictionary:
			errors.append("技能卡收藏必须为字典")
		else:
			for id in owned_cards:
				if not id is String or card(str(id)).is_empty() or not owned_cards[id] is int or owned_cards[id] < 1:
					errors.append("技能卡收藏ID或数量非法：" + str(id))
			var build = actor.get("build")
			if build is Dictionary:
				var groups: Array = []
				if build.get("active") is Dictionary: groups.append_array(build.active.values())
				groups.append(build.get("passive"))
				for group in groups:
					if not group is Array: continue
					for id in group:
						if not id is String or not owned_cards.get(id) is int or owned_cards.get(id, 0) < 1:
							errors.append("尚未拥有技能卡：" + str(id))
	return errors

static func skill_modifiers(actor: Dictionary, skill_id: String) -> Dictionary:
	if _legacy_actor(actor): return Legacy.skill_modifiers(actor,skill_id)
	var result := MODIFIER_ZERO.duplicate()
	var build = actor.get("build")
	if not build is Dictionary or not build.get("active") is Dictionary or not build.get("passive") is Array: return result
	var form := str(actor.get("form_id", "")) if actor.get("class_id") == "mage" else "default"
	var active = build.active.get(form)
	var prepared := prepared_card(actor,skill_id)
	if not active is Array or prepared.is_empty(): return result
	for key in prepared.modifiers: result[key] += prepared.modifiers[key]
	var errors: Array[String] = []
	var tags: Array[String] = []
	var checked := _check_cards(build.passive,"passive",tags,errors,"角色被动",actor,form)
	if not errors.is_empty(): return result
	for id in checked.ids:
		for key in card(id).modifiers: result[key] += card(id).modifiers[key]
	for key in result:
		var bounds: Array = _data().modifier_bounds[key]
		result[key] = clampf(float(result[key]), float(bounds[0]), float(bounds[1])) if key == "coefficient_add" else clampi(int(result[key]), int(bounds[0]), int(bounds[1]))
	return result

static func visual_form(actor: Dictionary, skill_id: String) -> String:
	if _legacy_actor(actor): return Legacy.visual_form(actor,skill_id)
	var definition := prepared_card(actor,skill_id)
	if definition.get("type") != "active": return ""
	if definition.visual_form == "rinne" and actor.get("class_id") == "mage" and actor.get("identity_id") == "homura" and actor.get("actor_id") == "p_mage" and actor.get("form_id") == "sword":
		return "homura_sword"
	return definition.visual_form

static func _check_cards(value: Variant, type: String, weapon_tags: Array[String], errors: Array[String], label: String, actor: Dictionary = {}, form: String = "") -> Dictionary:
	var result := {"ids": [], "skills": [], "used": 0}
	if not value is Array:
		errors.append(label + "卡表必须为数组")
		return result
	var limits: Dictionary = _data().limits
	if value.size() > limits[type + "_slots"]: errors.append(label + "超过卡位上限")
	var seen: Dictionary = {}
	var seen_skills: Dictionary = {}
	for id in value:
		if not id is String:
			errors.append(label + "卡ID必须为字符串")
			continue
		if seen.has(id):
			errors.append(label + "重复技能卡：" + id)
			continue
		seen[id] = true
		var definition := card(id)
		if definition.is_empty():
			errors.append(label + "未登记技能卡：" + id)
			continue
		if definition.type != type:
			errors.append(label + "卡类型不符：" + id)
			continue
		if not card_allowed(actor,id,form):
			errors.append(label+"不是本角色/形态的技能："+str(definition.name))
			continue
		result.ids.append(id)
		if type == "active":
			var skill_id := skill_id_for_card(id)
			if seen_skills.has(skill_id): errors.append("同一招式的原式和变式不能同时装配："+str(definition.name))
			seen_skills[skill_id] = true
			result.skills.append(skill_id)
		result.used += definition.capacity_cost
		var compatible: bool = definition.weapon_tags.is_empty()
		for tag in definition.weapon_tags:
			if weapon_tags.has(tag): compatible = true
		if not compatible: errors.append(label + "不满足武器标签：" + id)
	if result.used > limits[type + "_capacity"]: errors.append(label + "超过装配容量")
	return result

static func _add_stats(target: Dictionary, deltas: Variant, bounds: Dictionary, errors: Array[String], label: String, signed: bool) -> void:
	if not deltas is Dictionary:
		errors.append(label + "属性词条必须为字典")
		return
	for key in deltas:
		if not key in STAT_KEYS or not _whole(deltas[key]):
			errors.append(label + "属性词条非法：" + str(key))
			continue
		var minimum: int = int(bounds[key][0]) if signed else 0
		if deltas[key] < minimum or deltas[key] > bounds[key][1]:
			errors.append(label + "属性词条超出范围：" + str(key))
			continue
		target[key] += int(deltas[key])

static func _whole(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))

static func _integerize(value: Variant) -> Variant:
	if value is float and _whole(value): return int(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(_integerize(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[key] = _integerize(value[key])
		return result
	return value

static func _data() -> Dictionary:
	if not _cached_data.is_empty(): return _cached_data
	if not FileAccess.file_exists(DATA_PATH): return {}
	var data: Variant = _integerize(JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH)))
	if not data is Dictionary or data.get("schema_version") != 1 or data.get("rules_version") != "role-loadout-2": return {}
	for field in ["classes", "weapons", "limits", "stat_bounds", "equipment_stat_bounds", "card_stat_bounds", "modifier_bounds", "initial_cards"]:
		if not data.get(field) is Dictionary: return {}
	if not data.get("cards") is Array: return {}
	for key in ["active_slots", "passive_slots", "active_capacity", "passive_capacity"]:
		if not data.limits.get(key) is int or data.limits[key] < 1: return {}
	for bounds in [data.stat_bounds, data.equipment_stat_bounds, data.card_stat_bounds, data.modifier_bounds]:
		var expected: Array = MODIFIER_ZERO.keys() if bounds == data.modifier_bounds else STAT_KEYS
		if bounds.size() != expected.size(): return {}
		for key in expected:
			var pair = bounds.get(key)
			if not pair is Array or pair.size() != 2: return {}
			for number in pair:
				if not (number is int or number is float) or not is_finite(number): return {}
			if pair[0] > pair[1]: return {}
	var known: Dictionary = {}
	for row in data.cards:
		if not row is Dictionary or not row.get("id") is String or row.id.is_empty() or known.has(row.id): return {}
		known[row.id] = true
		if not row.get("type") in ["active", "passive"] or not row.get("capacity_cost") is int or row.capacity_cost < 1: return {}
		for field in ["name", "summary", "visual_form"]:
			if not row.get(field) is String: return {}
		if not row.get("weapon_tags") is Array or not row.get("stats") is Dictionary or not row.get("modifiers") is Dictionary: return {}
		for tag in row.weapon_tags:
			if not tag is String or tag.is_empty(): return {}
		if not row.get("owner_identity") in IDENTITIES.values() or not row.get("allowed_forms") is Array: return {}
		for form in row.allowed_forms:
			if not form in ["default","sword","mage"]: return {}
		# 主动卡不直接加人物属性；变式仅通过有界修正改变本招式。
		if row.type == "active" and (not row.stats.is_empty() or not row.get("skill_id") is String or row.skill_id.is_empty()): return {}
		if row.type == "active" and not row.visual_form in ["rinne","guard","mint","homura_sword","homura_mage","healer","controller"]: return {}
		if row.type == "active":
			var expected_visual: String = str(row.owner_identity)
			if expected_visual == "homura":
				if row.allowed_forms.size()!=1 or not row.allowed_forms[0] in ["sword","mage"]: return {}
				expected_visual = "homura_"+str(row.allowed_forms[0])
			elif row.allowed_forms != ["default"]: return {}
			if row.visual_form != expected_visual: return {}
		elif not row.allowed_forms.is_empty() or not row.visual_form.is_empty(): return {}
		var errors: Array[String] = []
		var zero := {"hp": 0, "mp": 0, "atk": 0, "matk": 0, "def": 0, "mdef": 0, "spd": 0}
		_add_stats(zero, row.stats, data.card_stat_bounds, errors, row.id, true)
		if not errors.is_empty(): return {}
		for key in row.modifiers:
			var value = row.modifiers[key]
			if not MODIFIER_ZERO.has(key) or not (value is int or value is float) or not is_finite(value): return {}
			if key != "coefficient_add" and not value is int: return {}
			if value < data.modifier_bounds[key][0] or value > data.modifier_bounds[key][1]: return {}
	for class_id in data.classes:
		var row = data.classes[class_id]
		if not row is Dictionary or not row.get("stats") is Dictionary or row.stats.size() != STAT_KEYS.size() or not row.get("active") is Dictionary or not row.get("weapon_tags") is Array or not row.get("weapon_id") is String: return {}
		for key in STAT_KEYS:
			if not row.stats.get(key) is int or row.stats[key] < data.stat_bounds[key][0] or row.stats[key] > data.stat_bounds[key][1]: return {}
	for id in data.initial_cards:
		if not known.has(id) or not data.initial_cards[id] is int or data.initial_cards[id] < 1: return {}
	_cached_data = data
	return _cached_data
