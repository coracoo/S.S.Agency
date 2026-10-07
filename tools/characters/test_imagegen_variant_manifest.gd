# 全部二十八形态显式预览；未知形态、显式事件合同与生产门禁不会静默回退。
extends SceneTree
var checks := 0
var failures := 0
var decoded_bytes := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func _initialize() -> void: _run.call_deferred()
func write_json(path: String, value: Dictionary) -> void:
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(value)); output.close()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var loader = load("res://scripts/rpg/ui/imagegen_effect_manifest.gd")
	var registry: Dictionary = loader._json(loader.REGISTRY)
	check(registry.effects.size()==24, "保留二十四个实际技能ID")
	if registry.effects.size()!=24: quit(1); return
	var count := 0
	var new_count := 0
	for skill in registry.effects:
		var root: Dictionary = registry.effects[skill]
		var variants: Dictionary = root.get("variants", {"":root})
		if root.has("variants"):
			check(loader.load_effect(skill,loader.REGISTRY,true).get("reason")=="form_required", "共享ID必须明确形态："+skill)
			for wrong in ["", "guard", "homura_mage", "swordsman", "unknown"]:
				var refused: Dictionary = loader.load_effect(skill,loader.REGISTRY,true,wrong)
				check(not refused.ok, "拒绝空或错误形态："+skill+":"+wrong)
		for form in variants:
			count += 1
			var effect: Dictionary = loader.load_effect(skill,loader.REGISTRY,true,form)
			check(effect.ok, "已登记形态可显式预览："+skill+":"+form+":"+str(effect.get("reason","")))
			if not effect.ok: continue
			decoded_bytes += int(effect.texture_bytes)
			check(loader.load_effect(skill,loader.REGISTRY,false,form).get("reason")=="production_disabled", "生产总门禁保持关闭")
			var entry: Dictionary = variants[form]
			var manifest: Dictionary = loader._json(entry.manifest)
			check(FileAccess.get_sha256(entry.manifest)==entry.manifest_sha256, "清单SHA与登记一致")
			check(FileAccess.get_sha256(effect.atlas_path)==effect.atlas_sha256, "图集原PNG SHA一致")
			check(effect.variant_key==(form+"-"+skill if not form.is_empty() else skill), "缓存键区分同ID的两套图")
			check(int(effect.texture_bytes)==effect.frames.size()*256*256*4, "真实RGBA解码内存按原图计算")
			for phase in effect.phases:
				var ids: Array = effect.phases[phase]
				if ids.is_empty(): continue
				check(loader.phase_frame(effect,phase,0.0).frame==int(ids[0]), "阶段起帧保留："+phase)
				check(loader.phase_frame(effect,phase,.999999).frame==int(ids[-1]), "阶段尾帧保留："+phase)
				check(loader.phase_frame(effect,phase,1.0).is_empty(), "有限播放结束不滞留："+phase)
				for id in ids:
					var frame: Dictionary = effect.frames[int(id)]
					check(frame.texture.get_image().get_used_rect().has_area(), "每个阶段帧有真实透明图像："+phase+":"+str(id))
			if manifest.has("form_id"):
				new_count += 1
				check(effect.form_id==manifest.form_id, "返回实际素材形态")
				check(effect.phase_groups==manifest.phase_groups, "独立层的激活/循环分组完整保留")
				check(not effect.event_layers.is_empty() and effect.visual_event_contract.id=="physical_skill_visual_v1", "十六形态经完整有限合同绑定")
				check(not effect.phases.has("hit"), "不伪造冻结原图不存在的命中段")
				for group in effect.phase_groups.values(): check(group.binding=="physical_skill_visual_v1", "新层显式绑定同版本合同")
				var bad := manifest.duplicate(true)
				var first: String = bad.phase_groups.keys()[0]
				bad.phase_groups[first].binding="automatic"
				check(not loader.compile_frames(bad,effect.atlas,.5,256).ok, "拒绝把有限绑定层改成任意自动播放")
				bad=manifest.duplicate(true); bad.phase_groups[first].loop_frames=[999]
				check(not loader.compile_frames(bad,effect.atlas,.5,256).ok, "拒绝独立分组引用不一致帧")
				bad=manifest.duplicate(true); bad.phase_groups.erase(first)
				check(not loader.compile_frames(bad,effect.atlas,.5,256).ok, "拒绝丢失独立分组")
				bad=manifest.duplicate(true); bad.erase("phase_groups")
				check(not loader.compile_frames(bad,effect.atlas,.5,256).ok, "新形态清单不能省略已登记分组")
				if form.is_empty():
					check(loader.load_effect(skill,loader.REGISTRY,true,"wrong_form").get("reason")=="form_mismatch", "单形态技能拒绝显式错误形态")
			else:
				check(loader.load_effect(skill,loader.REGISTRY,true).ok, "十二法术三参数调用保持兼容")
	check(count==28 and new_count==16, "二十八形态包含新十六套")
	check(decoded_bytes==114294784, "二十八套RGBA解码合计109MiB")
	var pending := registry.duplicate(true); pending.production_renderer_enabled=true
	write_json("user://variant_pending_registry.json",pending)
	for skill in pending.effects:
		for form in pending.effects[skill].get("variants",{"":pending.effects[skill]}):
			check(loader.load_effect(skill,"user://variant_pending_registry.json",false,form).get("reason")=="gameplay_qa_pending", "每个形态独立保留游戏QA门禁")
	var swapped := registry.duplicate(true)
	swapped.effects.heavy_slash.variants.rinne = registry.effects.heavy_slash.variants.homura_sword.duplicate(true)
	write_json("user://swapped_variant_registry.json",swapped)
	check(loader.load_effect("heavy_slash","user://swapped_variant_registry.json",true,"rinne").get("reason")=="form_mismatch", "交换有效SHA条目也不能串形态")
	print("IMAGEGEN_VARIANT_DECODED_RGBA_BYTES: ",decoded_bytes)
	print("IMAGEGEN_VARIANT_MANIFEST: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
