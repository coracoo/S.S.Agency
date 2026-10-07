# 十六形态显式合同、有限表与篡改拒绝；全部图集由真实FileAccess加载。
extends SceneTree
const Loader = preload("res://scripts/rpg/ui/imagegen_effect_manifest.gd")
const Policy = preload("res://scripts/rpg/ui/physical_skill_visual_event_policy.gd")
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void: _run.call_deferred()
func refused(manifest: Dictionary, effect: Dictionary, label: String) -> void:
	check(not Loader.compile_frames(manifest,effect.atlas,.5,256).ok,label+":"+effect.variant_key)
func write_json(path: String, value: Dictionary) -> void:
	var output := FileAccess.open(path,FileAccess.WRITE)
	output.store_string(JSON.stringify(value)); output.close()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var count := 0
	for form in Policy.SKILLS:
		for skill in Policy.SKILLS[form]:
			count += 1
			var effect: Dictionary = Loader.load_effect(skill,Loader.REGISTRY,true,form)
			check(effect.ok,"完整有限合同可显式加载："+form+":"+skill+":"+str(effect.get("reason","")))
			if not effect.ok: continue
			var source: Dictionary = Loader._json(effect.manifest_path)
			var before := source.duplicate(true)
			check(Loader._same_contract(source.visual_event_contract,Policy.contract_identity(form,skill)),"manifest身份与唯一策略登记相符")
			check(Loader._same_contract(effect.visual_event_contract,source.visual_event_contract),"loader返回已核身份")
			check(Loader._same_contract(effect.event_layers,Policy.bindings(form,skill,source.phase_groups)),"完整事件字段同源精确匹配")
			check(Loader._same_contract(effect.reaction_layers,Policy.reaction_bindings(form,skill,source.phase_groups)),"独立反应字段同源精确匹配")
			check(Loader.compile_frames(source,effect.atlas,.5,256).ok and source==before,"校验不修改输入")
			_test_mutations(source,effect)
			_test_unbound(source,effect)
			_test_semantics(source,effect)
	check(count==16,"恰好十六视觉形态")
	_test_legacy_casters()
	_test_registry_identity()
	print("PHYSICAL_SKILL_MANIFEST_CONTRACT: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
func _test_mutations(source: Dictionary, effect: Dictionary) -> void:
	for field in ["id","version","form","ability_id","variant_key"]:
		var bad := source.duplicate(true); bad.visual_event_contract[field]="unknown"
		refused(bad,effect,"拒绝错误合同身份："+field)
		bad=source.duplicate(true); bad.visual_event_contract.erase(field)
		refused(bad,effect,"拒绝缺失合同字段："+field)
	for version in [0,2,true,"1"]:
		var bad := source.duplicate(true); bad.visual_event_contract.version=version
		refused(bad,effect,"拒绝非版本1")
	var bad := source.duplicate(true); bad.visual_event_contract.extra=true
	refused(bad,effect,"拒绝未知合同扩展")
	for field in ["skill_id","form_id"]:
		bad=source.duplicate(true); bad[field]="unknown"
		refused(bad,effect,"拒绝manifest身份篡改")
	for field in ["visual_event_contract","event_layers","reaction_layers","phase_groups"]:
		bad=source.duplicate(true); bad.erase(field)
		refused(bad,effect,"拒绝缺失已绑定声明："+field)
	var phase: String = source.phase_groups.keys()[0]
	var other: String = source.phase_groups.keys()[1]
	for binding in ["unbound","automatic","physical_skill_visual_v2"]:
		bad=source.duplicate(true); bad.phase_groups[phase].binding=binding
		refused(bad,effect,"拒绝混合或未知组绑定")
	bad=source.duplicate(true); bad.phase_groups.erase(phase)
	refused(bad,effect,"拒绝缺失阶段组")
	bad=source.duplicate(true); bad.phases.erase(phase)
	refused(bad,effect,"拒绝缺失原阶段")
	for values in [[],[1,1],[999],[1.5],source.phases[other]]:
		bad=source.duplicate(true); bad.phase_groups[phase].activation_frames=values
		refused(bad,effect,"拒绝缺帧重复越界小数跨组帧")
	var layer_id: String = source.event_layers.keys()[0]
	bad=source.duplicate(true); bad.event_layers.erase(layer_id)
	refused(bad,effect,"拒绝遗漏任一有限事件层")
	bad=source.duplicate(true); bad.event_layers.unknown=source.event_layers[layer_id]
	refused(bad,effect,"拒绝未知事件层")
	for field in ["event_type","status_id","phase","cue","target","placement","lifetime"]:
		bad=source.duplicate(true); bad.event_layers[layer_id][field]="unknown"
		refused(bad,effect,"拒绝任意事件状态或落点："+field)
	for values in [[],[1,1],[999],source.phases[other]]:
		bad=source.duplicate(true); bad.event_layers[layer_id].activation_frames=values
		refused(bad,effect,"拒绝事件层缺帧重复越界跨组帧")
	bad=source.duplicate(true); bad.event_layers[layer_id].phase_segments[0].phase=other
	refused(bad,effect,"拒绝跨阶段段名伪装")
	bad=source.duplicate(true); bad.event_layers[layer_id].extra=true
	refused(bad,effect,"拒绝未声明字段")
func _test_unbound(source: Dictionary, effect: Dictionary) -> void:
	var unbound := source.duplicate(true); unbound.erase("visual_event_contract")
	for group in unbound.phase_groups.values(): group.binding="unbound"
	unbound.event_layers={}; unbound.reaction_layers={}
	check(Loader.compile_frames(unbound,effect.atlas,.5,256).ok,"素材登记unbound路径保留")
	unbound.event_layers=source.event_layers.duplicate(true)
	check(Loader.compile_frames(unbound,effect.atlas,.5,256).get("reason")=="unbound_event_layers","未声明合同不能偷偷绑定事件")
	unbound.event_layers={}; unbound.reaction_layers={"unknown":{}}
	check(Loader.compile_frames(unbound,effect.atlas,.5,256).get("reason")=="unbound_reaction_layers","未声明合同不能偷偷绑定反应")
func _test_semantics(source: Dictionary, effect: Dictionary) -> void:
	for name in source.event_layers:
		var layer: Dictionary = source.event_layers[name]
		if not layer.start_phase.is_empty():
			check(layer.phase_segments.size()==2 and layer.phase_segments[0].phase==layer.start_phase and layer.phase_segments[1].phase==layer.phase,"apply→sustain保留两个原组")
			check(layer.activation_frames==source.phase_groups[layer.start_phase].activation_frames+source.phase_groups[layer.phase].activation_frames and layer.loop_frames==source.phase_groups[layer.phase].loop_frames,"跨组激活及最终循环无丢帧")
		if layer.has("reason"):
			var bad := source.duplicate(true); bad.event_layers[name].reason="expired"
			refused(bad,effect,"不把自然到期冒充技能消耗或净化")
		if name=="mp_refund":
			check(layer.positive_actual==true,"回蓝声明实际值必须为正")
			for value in [false,0,"actual"]:
				var bad := source.duplicate(true); bad.event_layers[name].positive_actual=value
				refused(bad,effect,"拒绝伪造实际回蓝门槛")
			var bad := source.duplicate(true); bad.event_layers[name].erase("positive_actual")
			refused(bad,effect,"拒绝删除实际回蓝门槛")
		if name=="conditional_precision":
			check(layer.requires_precision==true and layer.precast_evidence.condition=="target_has_status" and layer.precast_evidence.status_id=="armor_break","精准声明使用施法前破甲和唯一首伤害证明")
			for field in ["requires_precision","precast_evidence"]:
				var bad := source.duplicate(true); bad.event_layers[name].erase(field)
				refused(bad,effect,"拒绝删除精准证明："+field)
			for field in layer.precast_evidence:
				var bad := source.duplicate(true); bad.event_layers[name].precast_evidence.erase(field)
				refused(bad,effect,"拒绝删除精准子条件："+field)
	if effect.skill_id=="cover":
		check(not source.event_layers.has("cover_redirected") and source.reaction_layers.keys()==["cover_redirected"],"掩护反应独立于施加层")
		for field in source.reaction_layers.cover_redirected:
			var bad := source.duplicate(true); bad.reaction_layers.cover_redirected.erase(field)
			refused(bad,effect,"拒绝缺失反应字段："+field)
		for change in ["apply","reason","frames","endpoints","target","phase","lifetime"]:
			var bad := source.duplicate(true)
			match change:
				"apply": bad.reaction_layers.cover_redirected.event_type="status_applied"
				"reason": bad.reaction_layers.cover_redirected.requires="any_status_removed"
				"frames": bad.reaction_layers.cover_redirected.activation_frames=[13,13,999]
				"endpoints": bad.reaction_layers.cover_redirected.endpoints=["enemy","original_target_id"]
				"target": bad.reaction_layers.cover_redirected.target="event_source"
				"phase": bad.reaction_layers.cover_redirected.phase="cover_status"
				"lifetime": bad.reaction_layers.cover_redirected.lifetime="status"
			refused(bad,effect,"拒绝错误掩护反应："+change)
		var bad := source.duplicate(true); bad.event_layers.cover_redirected=bad.reaction_layers.cover_redirected; bad.reaction_layers={}
		refused(bad,effect,"不能把cover反应绑定在apply层")
	else:
		var bad := source.duplicate(true); bad.reaction_layers={"cover_redirected":{}}
		refused(bad,effect,"非掩护技能不得附反应")
func _test_legacy_casters() -> void:
	for skill in ["heal","group_heal","cleanse","holy_shield","weaken","slow","seal","magic_break"]:
		var effect: Dictionary = Loader.load_effect(skill,Loader.REGISTRY,true)
		check(effect.ok,"旧八caster单阶段合同可加载："+skill)
		if not effect.ok: continue
		var source := Loader._json(effect.manifest_path)
		for name in source.event_layers:
			var layer: Dictionary = source.event_layers[name]
			check(layer.activation_frames+layer.loop_frames==source.phases[name],"旧caster仍禁止跨原阶段拼接")
			var bad := source.duplicate(true); bad.event_layers[name].activation_frames.append(source.phases.cast[0])
			refused(bad,effect,"旧caster跨阶段帧拒绝")
		var bad := source.duplicate(true); bad.visual_event_contract=Policy.contract_identity("guard","cover")
		refused(bad,effect,"旧caster不能伪装十六形态合同")
func _test_registry_identity() -> void:
	var registry := Loader._json(Loader.REGISTRY)
	for skill in Loader.SHARED_SKILLS:
		check(Loader.load_effect(skill,Loader.REGISTRY,true).get("reason")=="form_required","共享技能禁止裸ID回退")
		var swapped := registry.duplicate(true)
		swapped.effects[skill].variants.rinne=registry.effects[skill].variants.homura_sword.duplicate(true)
		write_json("user://physical_swapped.json",swapped)
		check(Loader.load_effect(skill,"user://physical_swapped.json",true,"rinne").get("reason")=="form_mismatch","有效SHA也不能串Rinne/Sword")
	for skill in ["cover","mark"]:
		var bad_registry := registry.duplicate(true)
		var manifest := Loader._json(bad_registry.effects[skill].manifest)
		manifest.form_id="homura_sword"
		write_json("user://physical_wrong_form.json",manifest)
		bad_registry.effects[skill].manifest="user://physical_wrong_form.json"
		bad_registry.effects[skill].manifest_sha256=FileAccess.get_sha256("user://physical_wrong_form.json")
		write_json("user://physical_wrong_registry.json",bad_registry)
		check(Loader.load_effect(skill,"user://physical_wrong_registry.json",true).get("reason")=="form_mismatch","单形态无form参数也须核登记身份")
