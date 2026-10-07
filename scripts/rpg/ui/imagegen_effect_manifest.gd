# 校验运行清单及图集原字节。素材批准与游戏呈现批准是两道独立门。
extends RefCounted
const PhysicalPolicy = preload("res://scripts/rpg/ui/physical_skill_visual_event_policy.gd")
const PHASES := ["cast","travel","hit","status","recovery_tail","heal_impact","guard_life_shield","cleanse_removal","rejuvenation_heal","holy_shield_edge","awake_clarity","weaken_apply","weaken_status","slow_apply_sustain","conditional_magic_break","stun_apply_sustain","charge_interrupt","mp_refund","damage_recovery","magic_break_status"]
const VARIANT_PHASES := ["contact_damage","recovery","conditional_precision","armor_break_status","conditional_weaken","cast_sweep","conditional_slow","armor_break_consumed","battle_spirit_apply","battle_spirit_status","conditional_burn","conditional_armor_break","conditional_shield","cover_link","cover_status","cover_redirected","shield_apply","shield_sustain","cleanse","sound_travel","taunt_status","mark_apply","mark_sustain","mark_consumed","mark_apply_sustain","battle_spirit"]
const SHARED_SKILLS := ["heavy_slash","armor_break","sweep","battle_spirit"]
const MELEE_FORMS := ["rinne","homura_sword"]
const TAIL_PHASES := ["hit","heal_impact","cleanse_removal","rejuvenation_heal","weaken_apply","charge_interrupt","mp_refund","damage_recovery"]
const REGISTRY := "res://assets/effects/imagegen_spells/registry.json"
static func _failure(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
static func _true(value: Variant) -> bool: return value is bool and value
# JSON数字会成为float；只等价接受精确数值，bool/string及未知字段不能混过合同。
static func _same_contract(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary or actual.size()!=expected.size(): return false
		for key in expected:
			if not actual.has(key) or not _same_contract(actual[key],expected[key]): return false
		return true
	if expected is Array:
		if not actual is Array or actual.size()!=expected.size(): return false
		for index in expected.size():
			if not _same_contract(actual[index],expected[index]): return false
		return true
	if expected is int or expected is float:
		return (actual is int or actual is float) and is_finite(float(actual)) and float(actual)==float(expected)
	return typeof(actual)==typeof(expected) and actual==expected

static func load_effect(skill: String,registry_path: String = REGISTRY,preview_pending: bool = false,form_id: String = "") -> Dictionary:
	var registry := _json(registry_path)
	if registry.get("schema_version") != 2: return _failure("invalid_registry")
	if not preview_pending and not _true(registry.get("production_renderer_enabled")): return _failure("production_disabled")
	var entry: Variant = registry.get("effects",{}).get(skill)
	if not entry is Dictionary: return _failure("unregistered")
	var variant_key := skill
	# 共用规则ID不代表共用美术；省略形态时绝不默认显示凛音。
	if skill in SHARED_SKILLS:
		if form_id.is_empty(): return _failure("form_required")
		if form_id not in MELEE_FORMS: return _failure("unregistered_form")
		var variants: Variant = entry.get("variants")
		if not variants is Dictionary or variants.size()!=2: return _failure("invalid_variants")
		for form in MELEE_FORMS:
			if not variants.get(form) is Dictionary: return _failure("invalid_variants")
		entry = variants[form_id]
		variant_key = form_id+"-"+skill
	elif entry.has("variants"): return _failure("invalid_variants")
	if not _true(entry.get("approved_for_runtime")): return _failure("art_unapproved")
	if not preview_pending and entry.get("gameplay_qa_pending",true) != false: return _failure("gameplay_qa_pending")
	var path := str(entry.get("manifest",""))
	var manifest := _json(path)
	if manifest.get("schema_version") != 1 or manifest.get("skill_id") != skill: return _failure("invalid_manifest")
	if (skill in SHARED_SKILLS or (manifest.has("form_id") and not form_id.is_empty())) and manifest.get("form_id")!=form_id: return _failure("form_mismatch")
	# 单形态技能也以有限策略登记核身份，不能借空form跳过守卫/薄荷校验。
	for physical_form in PhysicalPolicy.SKILLS:
		if skill not in SHARED_SKILLS and skill in PhysicalPolicy.SKILLS[physical_form] and manifest.get("form_id")!=physical_form: return _failure("form_mismatch")
	if FileAccess.get_sha256(path) != entry.get("manifest_sha256"): return _failure("receipt_mismatch")
	var atlas_path := str(registry.get("asset_root","")).path_join(str(manifest.get("runtime_atlas","")))
	if not FileAccess.file_exists(atlas_path) or FileAccess.get_sha256(atlas_path) != manifest.get("runtime_atlas_sha256"): return _failure("atlas_hash_mismatch")
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(atlas_path)) != OK: return _failure("invalid_png")
	if image.get_width()*image.get_height()>16777216: return _failure("atlas_budget")
	var effect := compile_frames(manifest,ImageTexture.create_from_image(image),float(entry.get("runtime_scale",0)),float(entry.get("display_size_px",0)))
	if not effect.ok: return effect
	effect.merge({"skill_id":skill,"form_id":manifest.get("form_id",""),"variant_key":variant_key,"manifest_path":path,"atlas_path":atlas_path,"atlas_sha256":manifest.runtime_atlas_sha256,"texture_bytes":image.get_data_size(),"preview_pending":preview_pending,"particles":entry.get("particles",[])},true)
	return effect

# 清单明确坐标和阶段，不推测列数、格子尺寸或神经输出帧数。
static func compile_frames(manifest: Dictionary,atlas: Texture2D,runtime_scale: float,display_size: float) -> Dictionary:
	if atlas==null or not is_finite(runtime_scale) or runtime_scale<=0 or not is_finite(display_size) or display_size<=0: return _failure("invalid_scale")
	var source: Variant = manifest.get("frames")
	var phases: Variant = manifest.get("phases")
	if not source is Array or source.is_empty() or source.size()>256 or source.size()!=int(manifest.get("frame_count",0)) or not phases is Dictionary: return _failure("invalid_frames")
	var frames := {}
	for item in source:
		if not item is Dictionary: return _failure("invalid_frame")
		var id := int(item.get("frame",0))
		var rect: Variant = item.get("atlas_native_xywh")
		var anchor: Variant = item.get("anchor_runtime_px")
		var duration := float(item.get("nominal_duration_ms",0))
		if id<=0 or frames.has(id) or not rect is Array or rect.size()!=4 or not anchor is Array or anchor.size()!=2 or not is_finite(duration) or duration<=0: return _failure("invalid_frame")
		var coords: Array[float] = []
		for value in rect:
			if not (value is int or value is float) or not is_finite(float(value)) or not is_equal_approx(float(value)*runtime_scale,roundf(float(value)*runtime_scale)): return _failure("invalid_region")
			coords.append(float(value)*runtime_scale)
		var region := Rect2(coords[0],coords[1],coords[2],coords[3])
		if not region.has_area() or not Rect2(Vector2.ZERO,atlas.get_size()).encloses(region): return _failure("invalid_region")
		var point := Vector2(float(anchor[0]),float(anchor[1]))
		if not point.is_finite() or point.x<0 or point.y<0 or point.x>region.size.x or point.y>region.size.y: return _failure("invalid_anchor")
		var texture := AtlasTexture.new(); texture.atlas=atlas; texture.region=region
		frames[id] = {"frame":id,"phase":str(item.get("phase","")),"texture":texture,"anchor":point,"duration_ms":duration,"tail":bool(item.get("recovery_tail",false)),"scale":display_size/maxf(region.size.x,region.size.y)}
	# 旧Mage省略声明时仍要求三段；无伤害技能必须明确列出自己的真实阶段。
	var required_phases: Variant = manifest.get("required_phases",["cast","travel","hit"])
	if not required_phases is Array or required_phases.is_empty(): return _failure("invalid_required_phases")
	var required_seen := {}
	for required in required_phases:
		if not required is String or (required not in PHASES and required not in VARIANT_PHASES) or required=="recovery_tail" or required_seen.has(required): return _failure("invalid_required_phases")
		if not phases.get(required) is Array or phases[required].is_empty(): return _failure("missing_phase")
		required_seen[required]=true
	for phase in phases:
		if (phase not in PHASES and phase not in VARIANT_PHASES) or not phases[phase] is Array: return _failure("invalid_phase")
		var seen := {}
		for id in phases[phase]:
			var key := int(id)
			if not frames.has(key) or seen.has(key): return _failure("invalid_phase")
			if phase=="recovery_tail":
				if not frames[key].tail or frames[key].phase not in TAIL_PHASES: return _failure("invalid_tail")
			elif frames[key].phase!=phase: return _failure("invalid_phase")
			seen[key]=true
	# 显式版本合同才启用新分支；无合同仍维持完整unbound拒绝路径。
	var physical := manifest.has("visual_event_contract")
	var identity: Dictionary = {}
	if physical:
		identity = PhysicalPolicy.contract_identity(str(manifest.get("form_id", "")), str(manifest.get("skill_id", "")))
		var declared: Variant = manifest.visual_event_contract
		if identity.is_empty() or not declared is Dictionary or not _same_contract(declared,identity): return _failure("invalid_visual_event_contract")
		if declared.get("version") is bool: return _failure("invalid_visual_event_contract")
	var groups: Variant = manifest.get("phase_groups",{})
	if not groups is Dictionary: return _failure("invalid_phase_groups")
	if manifest.has("form_id") and not manifest.has("phase_groups"): return _failure("invalid_phase_groups")
	if manifest.has("phase_groups"):
		if groups.size()!=phases.size(): return _failure("invalid_phase_groups")
		var grouped_frames := {}
		for phase in phases:
			var group: Variant = groups.get(phase)
			if not group is Dictionary or group.get("binding")!=(PhysicalPolicy.CONTRACT_ID if physical else "unbound"): return _failure("invalid_phase_groups")
			var activation: Variant = group.get("activation_frames")
			var loop_frames: Variant = group.get("loop_frames")
			if not activation is Array or not loop_frames is Array or activation+loop_frames!=phases[phase]: return _failure("invalid_phase_groups")
			for id in phases[phase]:
				if grouped_frames.has(int(id)): return _failure("invalid_phase_groups")
				grouped_frames[int(id)]=true
		if grouped_frames.size()!=frames.size(): return _failure("invalid_phase_groups")
	var layers: Variant = manifest.get("event_layers",{})
	if not layers is Dictionary: return _failure("invalid_event_layers")
	var reactions: Variant = manifest.get("reaction_layers",{})
	if not reactions is Dictionary: return _failure("invalid_reaction_layers")
	if physical:
		var expected: Dictionary = PhysicalPolicy.bindings(identity.form,identity.ability_id,groups)
		var expected_reactions: Dictionary = PhysicalPolicy.reaction_bindings(identity.form,identity.ability_id,groups)
		if expected.is_empty() or not manifest.has("event_layers") or not _same_contract(layers,expected): return _failure("invalid_physical_event_layers")
		if identity.ability_id=="cover" and expected_reactions.is_empty(): return _failure("invalid_physical_reaction_layers")
		if not manifest.has("reaction_layers") or not _same_contract(reactions,expected_reactions): return _failure("invalid_physical_reaction_layers")
		# 跨apply→sustain只由有限表连接，原组仍独立覆盖所有原帧。
		for layer in expected.values():
			if (layer.lifetime=="action" and not layer.loop_frames.is_empty()) or (layer.lifetime!="action" and layer.loop_frames.is_empty()): return _failure("invalid_physical_event_layers")
	else:
		if not groups.is_empty() and not layers.is_empty(): return _failure("unbound_event_layers")
		if not reactions.is_empty(): return _failure("unbound_reaction_layers")
	for name in ({} if physical else layers):
		var layer: Variant = layers[name]
		if not layer is Dictionary or layer.get("phase")!=name or not phases.has(name): return _failure("invalid_event_layer")
		if layer.get("event_type") not in ["damage","healed","shield_applied","status_applied","status_removed","charge_interrupted","mp_restored"]: return _failure("invalid_event_layer")
		if layer.get("target") not in ["event_target","source"] or layer.get("placement") not in ["target_body","target_ground","caster_body"] or layer.get("lifetime") not in ["action","status","shield"]: return _failure("invalid_event_layer")
		if layer.get("event_type") in ["healed","mp_restored"] and layer.get("positive_payload")!="actual": return _failure("invalid_event_layer")
		if layer.get("event_type")=="status_applied" and layer.get("status_id","") not in ["weaken","slow","stun","magic_break","awake"]: return _failure("invalid_event_layer")
		if layer.get("lifetime")=="status" and layer.get("event_type")!="status_applied": return _failure("invalid_event_layer")
		if layer.get("lifetime")=="shield" and layer.get("event_type")!="shield_applied": return _failure("invalid_event_layer")
		if layer.get("event_type")=="status_removed" and layer.get("payload_equals")!={"reason":"cleanse"}: return _failure("invalid_event_layer")
		var activation: Variant = layer.get("activation_frames")
		var loop_frames: Variant = layer.get("loop_frames")
		if not activation is Array or not loop_frames is Array or activation+loop_frames!=phases[name]: return _failure("invalid_event_layer")
		if (layer.lifetime=="action" and not loop_frames.is_empty()) or (layer.lifetime!="action" and loop_frames.is_empty()): return _failure("invalid_event_layer")
		if layer.has("requires_event") and layer.requires_event!={"event_type":"status_removed","payload_equals":{"reason":"cleanse"},"same_action":true,"same_target":true}: return _failure("invalid_event_layer")
		if layer.has("max_instances_per_action") and layer.max_instances_per_action!=1: return _failure("invalid_event_layer")
	var placement: Variant = manifest.get("placement",{})
	if not placement is Dictionary: return _failure("invalid_placement")
	if not placement.is_empty() and (placement.get("cast")!="caster_focus" or placement.get("travel_origin")!="caster_focus" or placement.get("travel_target") not in ["target_body","target_ground"] or placement.get("travel_mode") not in ["projectile","target_drop"]): return _failure("invalid_placement")
	return {"ok":true,"frames":frames,"phases":phases.duplicate(true),"atlas":atlas,"display_size":display_size,"required_phases":required_phases.duplicate(),"event_layers":layers.duplicate(true),"reaction_layers":reactions.duplicate(true),"visual_event_contract":identity.duplicate(true),"phase_groups":groups.duplicate(true),"placement":placement.duplicate(true)}

# 时间只重定标真实帧权重；p>=1结束。低频状态循环由调用者显式取模。
static func phase_frame(effect: Dictionary,phase: String,progress: float) -> Dictionary:
	if not is_finite(progress) or progress<0 or progress>=1: return {}
	var ids: Array = effect.get("phases",{}).get(phase,[])
	var total := 0.0
	for id in ids: total += float(effect.frames[int(id)].duration_ms)
	var at := progress*total
	for id in ids:
		var frame: Dictionary = effect.frames[int(id)]
		at -= float(frame.duration_ms)
		if at<0: return frame
	return {}
