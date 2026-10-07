# 独立图集清单合同：批准/生产门禁、动态帧数、像素SHA、阶段锚与有限播放。
extends SceneTree
var checks := 0
var failures := 0
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var loader = load("res://scripts/rpg/ui/imagegen_effect_manifest.gd")
	check(loader != null,"独立imagegen清单加载器存在")
	if loader != null:
		for skill in ["firebolt","flame_wave","ice_arrow","burn_brand"]:
			var blocked: Dictionary = loader.load_effect(skill)
			check(not blocked.ok and blocked.reason=="production_disabled","素材存在不等于生产呈现已经通过："+skill)
			var effect: Dictionary = loader.load_effect(skill,loader.REGISTRY,true)
			check(effect.ok,"技术QA批准的素材可在明确预览加载："+skill)
			if not effect.ok: continue
			check(effect.frames.size()==(16 if skill in ["ice_arrow","burn_brand"] else 12),"12/16帧清单不套用旧24帧格子")
			check(effect.atlas.get_width()==1024,"FileAccess载入正式运行图页")
			check(effect.frames[1].texture.region==Rect2(0,0,256,256),"运行坐标由显式scale转换")
			var cast: Dictionary = loader.phase_frame(effect,"cast",0.0)
			var travel: Dictionary = loader.phase_frame(effect,"travel",0.0)
			check(cast.frame==1 and travel.frame==5,"各阶段按实际清单起始帧")
			check(loader.phase_frame(effect,"hit",1.0).is_empty(),"单次阶段结束不把末帧永久停住")
			if skill=="firebolt":
				check(cast.anchor==Vector2(128,128) and travel.anchor==Vector2(192,128),"施法与投射物使用不同注册锚")
				check(loader.phase_frame(effect,"cast",.19).frame==2,"40/55/65/65毫秒权重保留非等距帧时长")
				check(loader.phase_frame(effect,"hit",.999).frame==12,"尾段使用真实第12帧，不插值造帧")
			var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(effect.manifest_path))
			var bad := source.duplicate(true); bad.frames[0].atlas_native_xywh[0] = 99999
			check(not loader.compile_frames(bad,effect.atlas,.5,256).ok,"拒绝越界矩形，不裁掉问题帧")
			bad = source.duplicate(true); bad.frames[0].nominal_duration_ms=0
			check(not loader.compile_frames(bad,effect.atlas,.5,256).ok,"拒绝零长度阶段权重")
			bad = source.duplicate(true); bad.phases.cast.append(999)
			check(not loader.compile_frames(bad,effect.atlas,.5,256).ok,"拒绝悬空阶段帧")
		var absent: Dictionary = loader.load_effect("holy_shield",loader.REGISTRY,true)
		check(not absent.ok and absent.reason=="unregistered","缺少生图清单明确缺口，不能回退程序几何图")
	print("IMAGEGEN_EFFECT_MANIFEST: %d assertions, %d failures" % [checks,failures])
	quit(1 if failures else 0)
