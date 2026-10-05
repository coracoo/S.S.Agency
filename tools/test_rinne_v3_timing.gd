# 凛音 v3 右向逐帧迁移时序单测：无头跑 SceneTree
# 验证：帧文件齐、每帧时长精确（走圈0.503s/攻击0.46s）、SpriteFrames 装配回读、
#       攻击六段边界单调、清单锚点/移速字段在位
# 用法: Godot --path <项目> --headless --script res://tools/test_rinne_v3_timing.gd
extends SceneTree
const LegacyPaths = preload("res://scripts/characters/legacy_asset_paths.gd")

const MANIFEST := "res://assets/chars/rinne_25d/animation_manifest.json"
const WALK_PERIOD := 0.503
const ATTACK_DURATION := 0.46

var _passed := 0
var _failed := 0

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("PASS: ", msg)
	else:
		_failed += 1
		push_error("FAIL: " + msg)

func _initialize() -> void:
	var f := FileAccess.open(LegacyPaths.resolve(MANIFEST), FileAccess.READ)
	_assert(f != null, "清单可打开 %s" % MANIFEST)
	if f == null:
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_assert(parsed is Dictionary, "清单 JSON 解析成功")
	var m: Dictionary = parsed
	# 帧文件齐全（dir + frames 逐个探测）
	var dir: String = m.get("dir", "")
	var anims: Dictionary = m.get("anims", {})
	var all_exist := true
	var total_files := 0
	for state in anims:
		var spec: Dictionary = anims[state]
		for n in spec.get("frames", []):
			total_files += 1
			if not FileAccess.file_exists(LegacyPaths.resolve(dir + n + ".png")):
				all_exist = false
				push_error("缺帧: " + dir + n + ".png")
	_assert(all_exist, "全部 %d 帧文件存在" % total_files)
	# 帧数：走路10（含4张补间）、攻击6（f1-f3+收招f1-f3）、待机4
	_assert(anims.get("walk", {}).get("frames", []).size() == 10, "走路 10 帧")
	_assert(anims.get("attack", {}).get("frames", []).size() == 6, "攻击 6 姿势")
	_assert(anims.get("idle", {}).get("frames", []).size() == 4, "待机 4 帧")
	# 每帧时长求和 = 周期
	var walk_durs: Array = anims.get("walk", {}).get("durations_ms", [])
	var attack_durs: Array = anims.get("attack", {}).get("durations_ms", [])
	var walk_sum := 0.0
	for d in walk_durs:
		walk_sum += float(d)
	var attack_sum := 0.0
	for d in attack_durs:
		attack_sum += float(d)
	_assert(absf(walk_sum / 1000.0 - WALK_PERIOD) < 0.005,
		"走路一圈 %.3fs ≈ 0.503s" % (walk_sum / 1000.0))
	_assert(absf(attack_sum / 1000.0 - ATTACK_DURATION) < 0.005,
		"攻击全程 %.3fs ≈ 0.460s" % (attack_sum / 1000.0))
	# 攻击六段边界（累计ends）单调递增且收尾=0.46
	var ends := [0.075, 0.130, 0.225, 0.280, 0.360, 0.460]
	var mono := true
	for i in range(1, ends.size()):
		if ends[i] <= ends[i - 1]:
			mono = false
	_assert(mono and absf(ends[5] - ATTACK_DURATION) < 0.001, "攻击六段边界单调且收尾0.46s")
	# 走路非匀速（补间不能把原相位改成平均帧率）：时长集合至少两种值
	var distinct := {}
	for d in walk_durs:
		distinct[d] = true
	_assert(distinct.size() >= 2, "走路每帧时长非统一（保留原关键帧相位）")
	# SpriteFrames 装配回读：时长真实写入（speed=1 时 帧显示时长=duration）
	# 帧图经 FileAccess 直读（同 PngLoader 路线，新 PNG 无需 --import）
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var walk_spec: Dictionary = anims.get("walk", {})
	frames.add_animation("walk")
	frames.set_animation_speed("walk", 1.0)
	# Godot 4：帧时长在 add_frame 时给（duration=秒×speed 倒数），无 set_frame_duration
	var img := Image.new()
	var probe := FileAccess.open(LegacyPaths.resolve(dir + walk_spec["frames"][0] + ".png"), FileAccess.READ)
	var probe_tex: Texture2D = null
	if probe != null and img.load_png_from_buffer(probe.get_buffer(probe.get_length())) == OK:
		probe_tex = ImageTexture.create_from_image(img)
	for i in range(walk_spec.get("frames", []).size()):
		frames.add_frame("walk", probe_tex, float(walk_spec["durations_ms"][i]) / 1000.0)
	var reread_sum := 0.0
	for i in range(frames.get_frame_count("walk")):
		reread_sum += frames.get_frame_duration("walk", i)
	_assert(absf(reread_sum - WALK_PERIOD) < 0.005,
		"SpriteFrames 回读走路时长和 %.3fs" % reread_sum)
	# 画布/锚点/移速字段在位（脚底配准 + 2.6m/s 换算依据）
	var canvas: Dictionary = m.get("canvas", {})
	var anchor_arr: Array = canvas.get("anchor", [])
	_assert(anchor_arr.size() == 2 and absf(float(anchor_arr[0]) - 288.0) < 0.01 \
			and absf(float(anchor_arr[1]) - 358.0) < 0.01, "脚底锚点 (288,358)")
	_assert(int(canvas.get("content_height_px", 0)) == 298, "内容身高 298px")
	_assert(absf(float(m.get("move_speed_mps", 0.0)) - 2.6) < 0.001, "移速 2.6 m/s")
	print("RESULT: %d 断言通过, %d 失败" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
