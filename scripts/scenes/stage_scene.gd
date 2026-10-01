class_name StageScene
extends Node2D
## 《逢魔退治帖》v3 探索模式横版舞台（Phase 0 地基）。
## 能力：全屏场景画渲染、平台剖面行走（像素移动 + 地面吸附）、
## 跟随相机（领先量 + 鼠标视差微偏移）、灵墨刻度 HUD。
## 后续 Phase 接入：L0–L4 分层视差、纵深线、探索输入扩展、clues.json。

## 舞台数据路径：默认第一幕参道；第二幕等由各自 .tscn 覆写（stage_corridor.tscn）
@export var stage_data_path := "res://data/stages/test_approach.json"

const UIThemeScript = preload("res://scripts/ui/theme.gd")
const InkTransitionScript = preload("res://scripts/ui/ink_transition.gd")
const SfxScript = preload("res://scripts/ui/sfx.gd")
const DialogueOverlayScript = preload("res://scripts/ui/dialogue_overlay.gd")
const RpgRouter = preload("res://scripts/rpg/encounter_router.gd")
const RpgStore = preload("res://scripts/rpg/save_store.gd")
var _rpg_pending_clue := ""

var _cfg: Dictionary = {}
var _theme = null

var _bg_sprite: Sprite2D = null
# 前景视差层（2.5D）：约定 res://assets/bg/parallax/<舞台id>_fg1/_fg2.png（透明底边角植被/柱缘），
# 相机移动时比背景滑动更快，人物走过会被短暂遮挡——画面驱动解密的纵深感
var _fg_layers: Array = [] # [{sprite, factor, base_x}]
var _occluders: Array = [] # 中景遮挡体 [{sprite, base_y, xmin, xmax}]
var _player: Node2D = null # Sprite2D（单帧旧素材）或 AnimatedSprite2D（逐帧动画）
var _player_animated := false # true=逐帧动画模式（待机/走路帧表由 player_anims 数据驱动）
var _anim_manifest: Dictionary = {} # player_anims_from 清单（v3：画布/脚底锚点/移速mps/每帧时长）
var _has_attack_anim := false # 清单含 attack 动画时开放 J 键攻击
var _attacking := false # 攻击演出中：锁位移、不可重入，播完回待机
var _j_prev := false
var _actual_speed := 0.0 # 本帧实际位移速度（px/s）：堵墙≈0，驱动步态播放比例
var _demo_left := false # --stage-anim-check 自动验收：左走段
var _player_base_scale := 1.0 # 透视缩放前的基准缩放（_build_player 算出，_update 里乘透视系数）
var _ground_base_y := 900.0   # 透视基准：剖面最高点 y（最近地面）
var _camera: Camera2D = null

var _player_x: float = 0.0
var _facing: int = 1 # 1=右 -1=左
var _idle_time: float = 0.0
var _moving := false
var _walk_phase: float = 0.0
var _ground: Array = [] # [[x, y], ...] 按 x 升序（无遮罩时的兜底折线）
var _ground_cols: PackedFloat32Array = PackedFloat32Array() # 行走遮罩逐列落脚高度（优先于折线）
var _elapsed: float = 0.0 # 场景累计时间（异常光效脉冲用）
var input_enabled := true # 标题屏作实时背景时关探索输入（GDD §9.4 S1）
var backdrop_mode := false # 标题屏活背景模式：隐藏 HUD 与线索，只保留画面

# ---- 画面线索（GDD §8 Phase 3，数据驱动 data/clues/<stage>.json）----
var _clues: Array = []
var _resolved: Dictionary = {} # clue_id -> true
var _active_clue: Variant = null # 当前进入调查半径的线索
var _investigating := false
var _clue_count_label: Label = null
var _hint_label: Label = null
var _exit_prompted := false # 全部线索已解决后的「前往下一幕」提示只播一次
# 推镜 + 解密特写（GDD Phase 3「绘卷推镜 + 解密特写」）
var _cinematic := false # 推镜期间相机脱离跟随，由 tween 接管

# ---- S3 探索 HUD（GDD §9.4 S3，CanvasLayer 屏幕固定）----
var _hud_layer: CanvasLayer = null
var _spirit := 0 # 灵墨刻度（逢魔压力，舞台数据驱动）
var _party: Array = []
var _party_index := 0
var _party_frames: Array = []
var _stat_panel: Control = null
var _key1_prev := false

# ---- 剧情对话（xlsx 配置驱动：config/dialogue.xlsx → data/dialogues.json）----
var _dlg_cfg: Dictionary = {} # 本舞台的对话段（enter/hotspots/nodes）
var _dlg_playing := false
var _dlg_fired: Dictionary = {} # hotspot x(字符串键) -> true，只触发一次

## 灵墨刻度：10 墨点；灵气≥睁眼阈值后，点亮的墨点画成「睁眼」（fuji 环 + 墨瞳）
class InkDots extends Control:
	var value := 0
	var eye_from := 4
	var dot: Color = Color.WHITE
	var eye: Color = Color.WHITE
	func setup(v: int, ef: int, c_dot: Color, c_eye: Color) -> void:
		value = v
		eye_from = ef
		dot = c_dot
		eye = c_eye
		queue_redraw()
	func _draw() -> void:
		for i in range(10):
			var c := Vector2(9 + i * 19.0, 9)
			if i < value:
				if value >= eye_from:
					draw_arc(c, 7.0, 0, TAU, 28, eye, 2.0)
					draw_circle(c, 2.4, dot)
				else:
					draw_circle(c, 5.2, dot)
			else:
				draw_arc(c, 5.2, 0, TAU, 28, Color(dot, 0.28), 1.4)

## cover 裁切图像区（同 battle_canvas.CoverArt 思路：自绘可控）
class CoverImage extends Control:
	var tex: Texture2D = null
	func _draw() -> void:
		if tex == null:
			return
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var s: float = maxf(size.x / maxf(tw, 1.0), size.y / maxf(th, 1.0))
		var w := tw * s
		var h := th * s
		draw_texture_rect(tex, Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h), false)

## 解密特写：墨晕暗角——径向渐变贴图，外深内浅收拢视线（CanvasItem 无擦除，贴图最稳）
class Vignette extends Control:
	var ink: Color = Color(0.05, 0.04, 0.06)
	var strength := 0.72
	var hole_radius := 340.0 # 聚光孔半径（屏幕像素）
	var _tex: ImageTexture = null
	func _ready() -> void:
		_build_tex()
	func _build_tex() -> void:
		var N := 256
		var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
		var c := N * 0.5
		var max_r_tex := sqrt(c * c * 2.0)
		# 屏幕半对角 → 贴图单位，求聚光孔的比例位置
		var sw := maxf(size.x, 2.0)
		var sh := maxf(size.y, 2.0)
		var max_r_screen := sqrt(sw * sw + sh * sh) * 0.5
		var hole_frac := clampf(hole_radius / max_r_screen, 0.0, 0.9)
		for y in range(N):
			for x in range(N):
				var d := Vector2(x - c, y - c).length() / max_r_tex
				var t := clampf((d - hole_frac) / maxf(1.0 - hole_frac, 0.001), 0.0, 1.0)
				img.set_pixel(x, y, Color(ink.r, ink.g, ink.b, strength * t * t))
		_tex = ImageTexture.create_from_image(img)
	func _draw() -> void:
		if _tex:
			draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)

func _ready() -> void:
	_theme = UIThemeScript.load_theme()
	_load_stage_data()
	_load_clues()
	_build_background()
	_build_parallax()
	_build_occluders()
	_build_player()
	_build_camera()
	_build_hud()
	set_process(true)
	WashiOverlay.add_to(self)
	var rpg_world: Dictionary = {} if backdrop_mode else RpgRouter.take_world(scene_file_path)
	if rpg_world.is_empty():
		_load_dialogue()
	else:
		restore_rpg_world(rpg_world)
		# 恢复已有舞台仅重建对话数据，不再次播放入场段。
		var dialogue_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/dialogues.json"))
		if dialogue_data is Dictionary: _dlg_cfg = dialogue_data.get("stages", {}).get(_cfg.get("id", ""), {})
	if "--stage-demo" in OS.get_cmdline_user_args():
		_run_auto_demo()
	if "--stage-walk" in OS.get_cmdline_user_args():
		_run_walk_demo()
	if "--stage-anim-check" in OS.get_cmdline_user_args():
		_run_anim_check()

# ---------- 数据 ----------

func _load_stage_data() -> void:
	var f := FileAccess.open(stage_data_path, FileAccess.READ)
	if f == null:
		push_error("[StageScene] 找不到舞台数据 %s" % stage_data_path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_cfg = parsed
	_ground = _cfg.get("ground_profile", [[0, 900], [2048, 900]])
	# 透视基准：剖面最高点 y（最近地面），登高以此按比例缩小
	for p in _ground:
		_ground_base_y = maxf(_ground_base_y, float(p[1]))
	_load_walk_mask() # 有遮罩则以遮罩顶缘为准（逐列贴画），并重算基准
	_player_x = float(_cfg.get("spawn_x", 600))

## 行走遮罩：assets/bg/walkmasks/<舞台id>.png（白=可行走面，顶缘=落脚高度）。
## 由 tools/build_walk_masks.py 生成（锚点折线+边缘吸附，已含站姿偏移）——
## 比 ground_profile 折线贴画：脚精确踩在画出来的石阶棱线/地板缝上。
## 逐列扫描顶缘存入 _ground_cols；缺失/全黑列退回折线按比例映射。
func _load_walk_mask() -> void:
	var path := "res://assets/bg/walkmasks/%s.png" % _cfg.get("id", "stage")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var img := Image.new()
	if img.load_png_from_buffer(f.get_buffer(f.get_length())) != OK:
		return
	img.convert(Image.FORMAT_L8)
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return
	var data := img.get_data()
	_ground_cols = PackedFloat32Array()
	_ground_cols.resize(w)
	_ground_base_y = 0.0
	for x in range(w):
		var gy := -1.0
		for y in range(h):
			if data[y * w + x] > 127:
				gy = float(y)
				break
		if gy < 0.0:
			# 该列全黑：退回折线（遮罩与背景同宽，按比例映射）
			gy = _ground_y_poly(float(x) * 2048.0 / float(w))
		_ground_cols[x] = gy
		_ground_base_y = maxf(_ground_base_y, gy)
	if _ground_base_y <= 0.0:
		_ground_cols = PackedFloat32Array() # 空遮罩：整体退回折线

## 线索表：按舞台 id 加载 data/clues/<id>.json（GDD §8：画面驱动解密）
func _load_clues() -> void:
	if backdrop_mode:
		return
	var path := "res://data/clues/%s.json" % _cfg.get("id", "test_approach")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[StageScene] 无线索表 %s（纯探索模式）" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_clues = parsed.get("clues", [])

## 台词表：data/dialogues.json 按舞台 id 取段（config/dialogue.xlsx 导出）
## 自动演出/后台模式/显式 --no-dialogue 时关闭（避免与验证钩子抢输入）
func _load_dialogue() -> void:
	if backdrop_mode:
		return
	var args := OS.get_cmdline_user_args()
	if "--no-dialogue" in args or "--stage-demo" in args or "--stage-anim-check" in args:
		return
	var f := FileAccess.open("res://data/dialogues.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_dlg_cfg = parsed.get("stages", {}).get(_cfg.get("id", ""), {})
	if _dlg_cfg.is_empty():
		return
	var enter_id := String(_dlg_cfg.get("enter", ""))
	if not enter_id.is_empty():
		_play_dialogue_chain(enter_id)

## 顺序播一条对话链（期间锁探索输入，结束后归还）
func _play_dialogue_chain(start_id: String) -> void:
	if _dlg_playing:
		return
	_dlg_playing = true
	var was_input := input_enabled
	input_enabled = false
	var overlay := DialogueOverlayScript.new(_theme)
	add_child(overlay)
	await overlay.play(_dlg_cfg.get("nodes", {}), start_id)
	overlay.queue_free()
	_dlg_playing = false
	if not _investigating:
		input_enabled = was_input

# ---------- 场景搭建 ----------

func _build_background() -> void:
	_bg_sprite = Sprite2D.new()
	_bg_sprite.texture = _load_texture(_cfg.get("bg", ""))
	_bg_sprite.centered = false
	# 场景画等比缩放到覆盖 1920×1080（令牌 canvas 基准）
	var cw := float(_theme.canvas("base_width"))
	var ch := float(_theme.canvas("base_height"))
	if _bg_sprite.texture:
		var s: float = maxf(cw / _bg_sprite.texture.get_width(), ch / _bg_sprite.texture.get_height())
		# 过填充 +8% 并水平居中：相机跟随/鼠标视差(±20px)时不露灰边
		# （用户复核：随鼠标移动背景出现灰边）
		s *= 1.08
		_bg_sprite.scale = Vector2(s, s)
		_bg_sprite.position = Vector2(cw * 0.5 - _bg_sprite.texture.get_width() * s * 0.5, 0)
	# z=-1：场景画必须画在宿主 _draw（落地阴影/线索异常光）之下，
	# 否则父节点 CanvasItem 的自绘内容会被不透明子精灵整幅盖住
	_bg_sprite.z_index = -1
	add_child(_bg_sprite)
	# 远景层（可选，bg_far + bg_far_factor 缺省 0.85）：远山/暮色等大景物。
	# 与主背景同尺寸同过填充缩放（视差位移仅 ±50px 内，1.08 过填充余量足够），
	# z=-2 垫在主背景之下；注册进 _fg_layers（factor<1 时现有公式天然慢速）
	_build_far_layer()

func _build_far_layer() -> void:
	var far_path: String = _cfg.get("bg_far", "")
	if far_path.is_empty():
		return
	var t: Texture2D = _load_texture(far_path)
	if t == null:
		return
	var cw := float(_theme.canvas("base_width"))
	var ch := float(_theme.canvas("base_height"))
	var spr := Sprite2D.new()
	spr.texture = t
	spr.centered = false
	var s: float = maxf(cw / t.get_width(), ch / t.get_height()) * 1.08
	spr.scale = Vector2(s, s)
	var base_x: float = cw * 0.5 - t.get_width() * s * 0.5
	spr.position = Vector2(base_x, 0)
	spr.z_index = -2
	add_child(spr)
	_fg_layers.append({"sprite": spr, "factor": float(_cfg.get("bg_far_factor", 0.85)),
			"base_x": base_x})

## 中景遮挡体：从背景画抠出的柱子/木板/石翼（tools/build_occluders.py），
## 与背景同位置同缩放（视差系数 1.0），z=5 压在角色(z0)之上、前景视差层(z9/10)之下。
## 逐帧按玩家脚点深度切换 visible：脚点在物体基线(base_y)上方=人在物体后方→显示遮挡；
## 否则隐藏（玩家盖在物体上，露出的仍是原画同位置像素，切换零跳变）。
func _build_occluders() -> void:
	if _bg_sprite == null or _bg_sprite.texture == null:
		return
	var f := FileAccess.open("res://data/occluders/%s.json" % _cfg.get("id", "stage"),
			FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return
	var s := float(_bg_sprite.scale.x)
	var bx := float(_bg_sprite.position.x)
	for occ in parsed.get("occluders", []):
		var t: Texture2D = _load_texture(occ.get("tex", ""))
		if t == null:
			continue
		var spr := Sprite2D.new()
		spr.texture = t
		spr.centered = false
		spr.scale = Vector2(s, s)
		var off: Array = occ.get("offset", [0, 0])
		spr.position = Vector2(bx + float(off[0]) * s, float(off[1]) * s)
		spr.z_index = 5
		add_child(spr)
		_occluders.append({"sprite": spr, "base_y": float(occ.get("base_y", 99999.0)),
				"xmin": float(occ.get("xmin", 0.0)), "xmax": float(occ.get("xmax", 0.0))})

func _update_occluders() -> void:
	if _occluders.is_empty():
		return
	if _player == null:
		for occ in _occluders:
			(occ["sprite"] as Sprite2D).visible = true
		return
	var feet := _ground_y(_player_x)
	for occ in _occluders:
		(occ["sprite"] as Sprite2D).visible = feet < float(occ["base_y"]) \
				and _player_x >= float(occ["xmin"]) and _player_x <= float(occ["xmax"])

## 前景视差层：透明底边角前景图（fg1 快/fg2 慢两档），比背景滑动更快。
## 相机在 cw/2 处两图与画面对齐；相机右移 Δ，前景相对背景左滑 (factor-1)·Δ。
func _build_parallax() -> void:
	var cw := float(_theme.canvas("base_width"))
	var ch := float(_theme.canvas("base_height"))
	var specs := [["fg1", 1.30, 10], ["fg2", 1.15, 9]]
	for spec in specs:
		var t: Texture2D = _load_texture(
			"res://assets/bg/parallax/%s_%s.png" % [_cfg.get("id", "stage"), spec[0]])
		if t == null:
			continue
		var spr := Sprite2D.new()
		spr.texture = t
		spr.centered = false
		var s: float = maxf(cw / t.get_width(), ch / t.get_height()) * 1.08
		spr.scale = Vector2(s, s)
		var base_x: float = cw * 0.5 - t.get_width() * s * 0.5
		spr.position = Vector2(base_x, 0)
		spr.z_index = int(spec[2]) # 压在角色(z0)之上：人物走过前景植被被短暂遮挡
		add_child(spr)
		_fg_layers.append({"sprite": spr, "factor": float(spec[1]), "base_x": base_x})

## 每帧按相机位置推前景层（与 _update_camera 解耦：推镜 tween 期间也生效）
func _update_parallax() -> void:
	if _fg_layers.is_empty() or _camera == null:
		return
	var cw := float(_theme.canvas("base_width"))
	for layer in _fg_layers:
		var spr: Sprite2D = layer["sprite"]
		spr.position.x = float(layer["base_x"]) \
			+ (float(layer["factor"]) - 1.0) * (cw * 0.5 - _camera.position.x)

## 动画清单解析：player_anims_from（v3 manifest，含画布/锚点/移速/每帧时长）优先；
## 无清单或读取失败退回舞台自带 player_anims（旧数组+统一 fps 格式兼容）
func _resolve_player_anims() -> Dictionary:
	var from: String = _cfg.get("player_anims_from", "")
	if from.is_empty():
		return _cfg.get("player_anims", {})
	var f := FileAccess.open(from, FileAccess.READ)
	if f == null:
		push_error("[StageScene] 找不到动画清单 %s" % from)
		return _cfg.get("player_anims", {})
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		push_error("[StageScene] 动画清单解析失败 %s" % from)
		return _cfg.get("player_anims", {})
	_anim_manifest = parsed
	return parsed.get("anims", {})

## 清单动画装配：frames(文件名)+durations_ms(每帧时长,毫秒)——不用统一帧率，精确还原节奏；
## pingpong=乒乓呼吸序列（往返各帧时长不变）；loop=false=单次播放（攻击收招）
func _add_manifest_anim(frames: SpriteFrames, state: String, spec: Dictionary) -> bool:
	var dir: String = _anim_manifest.get("dir", "")
	var names: Array = spec.get("frames", [])
	var durs: Array = spec.get("durations_ms", [])
	var texs: Array[Texture2D] = []
	for n in names:
		var t: Texture2D = _load_texture(dir + n + ".png")
		if t != null:
			texs.append(t)
	if texs.is_empty():
		return false
	frames.add_animation(state)
	frames.set_animation_speed(state, 1.0) # 时长直接给秒，速度=1
	frames.set_animation_loop(state, bool(spec.get("loop", true)))
	# Godot 4：帧时长只能在 add_frame 时给（duration=秒×speed 倒数）
	var idx := 0
	for i in range(texs.size()):
		frames.add_frame(state, texs[i],
			float(durs[i]) / 1000.0 if i < durs.size() else 0.1)
		idx += 1
	if bool(spec.get("pingpong", false)):
		for i in range(texs.size() - 2, 0, -1):
			frames.add_frame(state, texs[i], float(durs[i]) / 1000.0)
			idx += 1
	return true

func _build_player() -> void:
	# 逐帧动画优先：清单格式（字典：frames/durations_ms）或旧数组格式 + 统一 fps
	var anims: Dictionary = _resolve_player_anims()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var built := 0
	for state in ["idle", "walk", "attack"]:
		var spec: Variant = anims.get(state, null)
		if spec is Dictionary:
			if _add_manifest_anim(frames, state, spec):
				built += 1
		elif spec is Array and state != "attack":
			var cell_frames: Array[Texture2D] = []
			for p in spec:
				var t: Texture2D = _load_texture(p)
				if t != null:
					cell_frames.append(t)
			if not cell_frames.is_empty():
				frames.add_animation(state)
				if state == "idle":
					# 待机放慢（独立 idle_fps，缺省 0.6×）+ 乒乓序列 [0..n-1..1]：
					# 往返呼吸感，循环时长翻倍，治「动作频率过快/不够细致」
					frames.set_animation_speed(state, float(anims.get("idle_fps",
						maxf(3.0, float(anims.get("fps", 8)) * 0.6))))
					frames.add_frame(state, cell_frames[0])
					for i in range(1, cell_frames.size()):
						frames.add_frame(state, cell_frames[i])
					for i in range(cell_frames.size() - 2, 0, -1):
						frames.add_frame(state, cell_frames[i])
				else:
					frames.set_animation_speed(state, float(anims.get("fps", 8)))
					for t2 in cell_frames:
						frames.add_frame(state, t2)
				built += 1
	if built > 0:
		var asp := AnimatedSprite2D.new()
		asp.sprite_frames = frames
		asp.animation = "idle"
		asp.play()
		# 归一化与锚点：清单给画布尺寸/脚底锚点/内容身高（v3 576x384 锚(288,358)，
		# 内容高298=脚底到发顶）；旧素材兜底=画布底中心锚点、按画布高归一化
		var tex := frames.get_frame_texture("idle", 0)
		var tex_w := float(tex.get_width())
		var tex_h := float(tex.get_height())
		var norm_h := tex_h
		var anchor := Vector2(tex_w * 0.5, tex_h)
		if not _anim_manifest.is_empty():
			var canvas: Dictionary = _anim_manifest.get("canvas", {})
			norm_h = float(canvas.get("content_height_px", tex_h))
			var a: Array = canvas.get("anchor", [tex_w * 0.5, tex_h])
			anchor = Vector2(float(a[0]), float(a[1]))
		var target_h := float(_cfg.get("player_height_px", 500))
		var s: float = target_h / norm_h
		asp.scale = Vector2(s, s)
		_player_base_scale = s
		asp.offset = Vector2(tex_w, tex_h) * 0.5 - anchor # 锚点移到脚底中心，方便贴地
		_player = asp
		_player_animated = true
		_has_attack_anim = frames.has_animation("attack")
		asp.animation_finished.connect(_on_player_anim_finished)
	else:
		var sp := Sprite2D.new()
		sp.texture = _load_texture(_cfg.get("player_sprite", ""))
		var target_h2 := float(_cfg.get("player_height_px", 500))
		if sp.texture:
			sp.scale = Vector2(target_h2 / sp.texture.get_height(), target_h2 / sp.texture.get_height())
			_player_base_scale = sp.scale.x
		# 锚点移到脚底中心，方便贴地
		var tex_h2 := float(sp.texture.get_height()) if sp.texture else 1.0
		sp.offset = Vector2(0, -tex_h2 * 0.5)
		_player = sp
	add_child(_player)
	_update_player_transform(0.0)

## 移速：舞台显式 move_speed 优先；否则按清单 move_speed_mps 换算像素速度——
## drawn 像素身高（content_height_px×基准缩放）= height_m 米 → v=s×身高px/height_m
func _effective_move_speed() -> float:
	var s := float(_cfg.get("move_speed", 0.0))
	if s > 0.0:
		return s
	if not _anim_manifest.is_empty():
		var mps := float(_anim_manifest.get("move_speed_mps", 0.0))
		var canvas: Dictionary = _anim_manifest.get("canvas", {})
		var content_h := float(canvas.get("content_height_px", 0.0))
		var height_m := float(canvas.get("height_m", 1.6))
		if mps > 0.0 and content_h > 0.0:
			return mps * (content_h * _player_base_scale) / maxf(height_m, 0.01)
	return 240.0

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 5.0
	add_child(_camera)
	_camera.make_current()

func _build_hud() -> void:
	if backdrop_mode:
		return # 标题屏活背景：不带探索 HUD
	# S3：整套 HUD 进 CanvasLayer 屏幕固定（世界坐标会随相机漂移）
	_hud_layer = CanvasLayer.new()
	add_child(_hud_layer)
	# 左上：场景名横批 + 灵墨刻度（10 墨点，灵气≥睁眼阈值后墨点「睁眼」）
	var name_l := _hud_label(_cfg.get("name", "stage"), Vector2(48, 26), 18)
	name_l.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud_layer.add_child(name_l)
	_spirit = int(_cfg.get("spirit", 2))
	var eye_from := int(_theme.raw().get("spirit", {}).get("eye_open_from", 4))
	var dots := InkDots.new()
	dots.setup(_spirit, eye_from, _theme.color("paper_300"), _theme.color("fuji_500"))
	dots.position = Vector2(48, 56)
	dots.size = Vector2(196, 18)
	_hud_layer.add_child(dots)
	# 右上：异象计数 + ◆ 系统菜单
	_clue_count_label = _hud_label("", Vector2(1560, 26), 18)
	_hud_layer.add_child(_clue_count_label)
	_refresh_clue_count()
	var menu_btn := Button.new()
	menu_btn.text = "◆ 系统"
	menu_btn.position = Vector2(1772, 20)
	menu_btn.size = Vector2(100, 30)
	menu_btn.focus_mode = Control.FOCUS_NONE
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0, 0, 0, 0)
	menu_btn.add_theme_stylebox_override("normal", msb)
	menu_btn.add_theme_stylebox_override("hover", msb)
	menu_btn.add_theme_stylebox_override("pressed", msb)
	menu_btn.add_theme_font_override("font", _font(18))
	menu_btn.add_theme_font_size_override("font_size", 18)
	menu_btn.add_theme_color_override("font_color", _theme.color("paper_300"))
	menu_btn.pressed.connect(_on_system_menu)
	_hud_layer.add_child(menu_btn)
	if RpgRouter.enabled():
		var prepare := Button.new()
		prepare.name = "RpgPreparation"
		prepare.text = "◆ RPG休息 / 整备" if RpgRouter.session.campaign.snapshot().get("phase") == "rest" else "◆ RPG整备 / 道具"
		prepare.position = Vector2(1450, 70)
		prepare.size = Vector2(422, 56)
		prepare.add_theme_font_override("font", _font(24))
		prepare.add_theme_font_size_override("font_size", 24)
		prepare.pressed.connect(_on_rpg_preparation)
		_hud_layer.add_child(prepare)
	# 左下：队伍栏（头像 + HP/恐惧 + 手牌卡背点）
	_build_party_panel()
	# 调查提示条（底部居中，屏幕固定）
	_hint_label = _hud_label("", Vector2(540, 984), 22)
	_hint_label.size = Vector2(840, 30)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", _theme.color("gold_500"))
	_hint_label.visible = false
	_hud_layer.add_child(_hint_label)

## 队伍栏（GDD §9.4 S3）：头像横排，当前角色金框；1 键切换；HP/恐惧条 + 手牌卡背小点
func _build_party_panel() -> void:
	_party = _cfg.get("party", [
		{"name": "凛音", "art": "res://assets/chars/rinne_idle.png",
			"hp": 30, "hp_max": 30, "fear": 0, "fear_max": 100, "hand": 3},
	])
	var base := Vector2(48, 1080 - 96 - 60)
	for i in range(_party.size()):
		var m: Dictionary = _party[i]
		var frame := Panel.new()
		frame.position = base + Vector2(i * 88, 0)
		frame.size = Vector2(76, 76)
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Color(_theme.color("ink_900"), 0.55)
		fsb.set_border_width_all(3)
		fsb.set_corner_radius_all(4)
		frame.add_theme_stylebox_override("panel", fsb)
		_hud_layer.add_child(frame)
		_party_frames.append(frame)
		var art := CoverImage.new()
		art.tex = _load_texture(m.get("art", ""))
		art.position = Vector2(4, 4)
		art.size = Vector2(68, 68)
		frame.add_child(art)
	_update_party_hud()

## 切换角色后刷新：金框 / 玩家立绘 / 状态条
func _update_party_hud() -> void:
	for i in range(_party_frames.size()):
		var fsb: StyleBoxFlat = _party_frames[i].get_theme_stylebox("panel") as StyleBoxFlat
		fsb.border_color = _theme.color("gold_500") if i == _party_index else Color(_theme.color("paper_300"), 0.35)
		_party_frames[i].queue_redraw()
	# 状态条区（队伍栏右侧，仅当前角色）
	if _stat_panel != null:
		_stat_panel.queue_free()
	_stat_panel = Control.new()
	_stat_panel.position = Vector2(48 + _party.size() * 88 + 12, 1080 - 96 - 52)
	var m: Dictionary = _party[_party_index]
	var name_l := _hud_label(m.get("name", "?"), Vector2(0, -26), 18)
	_stat_panel.add_child(name_l)
	_stat_panel.add_child(_bar_rect(Vector2(0, 0), Vector2(180, 8),
		float(m.get("hp", 0)) / maxf(float(m.get("hp_max", 1)), 1.0), _theme.color("successful")))
	_stat_panel.add_child(_bar_rect(Vector2(0, 16), Vector2(180, 6),
		float(m.get("fear", 0)) / maxf(float(m.get("fear_max", 1)), 1.0), _theme.color("fuji_500")))
	# 手牌卡背小点（探索时不展开卡面）
	for i in range(int(m.get("hand", 0))):
		var dot := ColorRect.new()
		dot.color = _theme.color("gold_500")
		dot.position = Vector2(200 + i * 22, 0)
		dot.size = Vector2(12, 18)
		_stat_panel.add_child(dot)
	_hud_layer.add_child(_stat_panel)

func _bar_rect(pos: Vector2, sz: Vector2, frac: float, c: Color) -> Control:
	var wrap := Control.new()
	wrap.position = pos
	wrap.size = sz
	var bg := ColorRect.new()
	bg.color = Color(_theme.color("ink_900"), 0.6)
	bg.size = sz
	wrap.add_child(bg)
	var fill := ColorRect.new()
	fill.color = c
	fill.size = Vector2(sz.x * clampf(frac, 0.0, 1.0), sz.y)
	wrap.add_child(fill)
	return wrap

# 保留原探索的场景与所有谜题字段，写成功才离场；失败可原地重试。
func _on_rpg_preparation() -> void:
	if backdrop_mode or not RpgRouter.enabled() or not input_enabled or _dlg_playing or _investigating or _cinematic: return
	var opened: Dictionary = RpgRouter.session.open_preparation(export_rpg_world())
	if opened.ok:
		get_tree().change_scene_to_file(opened.next_scene)
	else:
		var notice := AcceptDialog.new()
		notice.title = "存档失败"
		notice.dialog_text = opened.error
		add_child(notice)
		notice.confirmed.connect(notice.queue_free)
		notice.canceled.connect(notice.queue_free)
		notice.popup_centered(Vector2i(600, 160))

func _on_system_menu() -> void:
	InkTransitionScript.transition(get_tree(), func() -> void:
		get_tree().change_scene_to_file("res://scenes/v3/title.tscn"))

func _refresh_clue_count() -> void:
	if _clue_count_label == null:
		return
	_clue_count_label.text = "异象 %d/%d" % [_resolved.size(), _clues.size()]
	_clue_count_label.add_theme_color_override("font_color",
		_theme.color("gold_500") if _resolved.size() == _clues.size() else _theme.color("paper_300"))

# ---------- 每帧 ----------

func _process(delta: float) -> void:
	_elapsed += delta
	_update_active_clue()
	# 剧情热点：走到配置的世界 x 坐标触发一次（对话播放期间由 _dlg_playing 挡住）
	if not _dlg_cfg.is_empty() and not _dlg_playing and not _investigating \
			and input_enabled:
		for h in _dlg_cfg.get("hotspots", []):
			var hx := str(h.get("x", ""))
			if _dlg_fired.has(hx):
				continue
			if _player_x >= float(h.get("x", 0.0)):
				_dlg_fired[hx] = true
				_play_dialogue_chain(String(h.get("node", "")))
				break
	# 1 键切换当前角色（GDD S3：切换 1 键）
	var k1 := Input.is_key_pressed(KEY_1)
	if input_enabled and k1 and not _key1_prev and _party.size() > 1:
		_party_index = (_party_index + 1) % _party.size()
		var m: Dictionary = _party[_party_index]
		if _player is Sprite2D: # 逐帧动画模式暂不支持换皮（帧表未按成员拆分）
			(_player as Sprite2D).texture = _load_texture(m.get("art", ""))
		_update_party_hud()
	_key1_prev = k1
	if input_enabled and Input.is_action_just_pressed("ui_accept"):
		if _active_clue != null and not _investigating:
			_investigate(_active_clue)
			return
		if _all_clues_resolved() and not _cfg.get("next", "").is_empty():
			# 全部异象已解决：E 前往下一幕（stage 配置 next 字段串联章节）
			InkTransitionScript.transition(get_tree(), func() -> void:
				get_tree().change_scene_to_file(_cfg["next"]))
			return
		if _clues.is_empty():
			# 纯探索模式（无线索表）保留旧入口：E 先进战前构筑，再出战（GDD §5.2）
			InkTransitionScript.transition(get_tree(), func() -> void:
				_go_battle("res://scenes/v3/battle.tscn"))
			return
	# J：攻击（v3 六姿势收招，清单含 attack 动画时开放）：锁位移、不可重入
	var kj := Input.is_key_pressed(KEY_J)
	if input_enabled and kj and not _j_prev and not _attacking \
			and _has_attack_anim and not _dlg_playing:
		_start_attack()
	_j_prev = kj
	var dir := Input.get_axis("ui_left", "ui_right")
	if _demo_walking:
		dir = 1.0
	if _demo_left:
		dir = -1.0
	if _attacking:
		dir = 0.0 # 攻击期间锁位移
	_moving = dir != 0.0
	if _moving:
		_facing = 1 if dir > 0 else -1
		_idle_time = 0.0
		_walk_phase += delta * 11.0
	else:
		_idle_time += delta
	var speed := _effective_move_speed()
	var bounds: Array = _cfg.get("bounds", [120, 1800])
	var old_x := _player_x
	_player_x = clampf(_player_x + dir * speed * delta, bounds[0], bounds[1])
	# 实际位移速度：堵墙/到界时≈0，驱动步态播放比例（不原地踏步，v3 frame_motion 同款）
	_actual_speed = absf(_player_x - old_x) / maxf(delta, 0.0001)
	_update_player_transform(delta)
	_update_camera(delta)
	_update_parallax()
	_update_occluders()
	queue_redraw()

func _update_player_transform(delta: float) -> void:
	if _player == null:
		return
	var gy := _ground_y(_player_x)
	if _player_animated:
		# 逐帧动画：状态机 idle/walk/attack；walk 播放速度跟实际位移走
		# （堵墙 speed_scale→0 并回待机，不原地踏步）
		var asp: AnimatedSprite2D = _player as AnimatedSprite2D
		var want := "idle"
		if _attacking:
			want = "attack"
		elif _moving and _actual_speed > _effective_move_speed() * 0.03:
			want = "walk"
		if asp.animation != want:
			asp.play(want)
		if want == "walk":
			asp.speed_scale = clampf(_actual_speed / maxf(_effective_move_speed(), 1.0), 0.0, 2.0)
		else:
			asp.speed_scale = 1.0
		_player.position = Vector2(_player_x, gy)
	else:
		# 单帧素材的过渡生命感（无动画数据时的兜底）
		var bob := 0.0
		if _moving:
			bob = -absf(sin(_walk_phase)) * 4.0
			_player.rotation = sin(_walk_phase) * 0.03
		else:
			bob = sin(_idle_time * 2.2) * 2.0
			_player.rotation = lerpf(_player.rotation, 0.0, delta * 8.0)
		_player.position = Vector2(_player_x, gy + bob)
	# 透视缩放：地面越高=越远=人物略缩小（钉进画中透视，治「行动位置不自然」）。
	# 以剖面最低处（最近）为 1.0，每升高 1px 缩 0.0009， clamps 防极端配置。
	var persp := clampf(1.0 - (_ground_base_y - gy) * 0.0012, 0.65, 1.02)
	_player.scale = Vector2(_player_base_scale * persp * _facing,
		_player_base_scale * persp)

func _draw() -> void:
	# 落地阴影：贴地半透明椭圆
	if _theme == null or _player == null:
		return
	var gy := _ground_y(_player_x)
	var c: Color = _theme.color("ink_900")
	draw_ground_ellipse(Rect2(Vector2(_player_x - 70, gy - 10), Vector2(140, 22)), Color(c, 0.30))
	# 画面线索：异常渲染 + 靠近高亮（先画异常，圈标在上层）
	if not backdrop_mode:
		for clue in _clues:
			if _resolved.has(clue.get("id", "")):
				continue
			_draw_clue_anomaly(clue)
			if clue == _active_clue:
				_draw_clue_prompt(clue)

## 倒影冷光异常（GDD §8「倒影不一致」）：石钵静水 + 不该存在的冷光呼吸
## TODO(素材管线)：水钵立绘走 gen_steampunk_manifest 日式批次替换矢量占位
func _draw_clue_anomaly(clue: Dictionary) -> void:
	var pos: Vector2 = _clue_pos(clue)
	var an: Dictionary = clue.get("anomaly", {})
	var mizu: Color = _theme.color("mizu_500")
	# 石钵：墨色钵体 + 靛青水面（shape=none 的锚点异象不画钵体，只画光——
	# 如吊钟舌下的钟鸣光、树洞里的棺纹冷光）
	if an.get("shape", "basin") != "none":
		draw_ground_ellipse(Rect2(pos + Vector2(-52, -26), Vector2(104, 40)), _theme.color("ink_700"))
		draw_ground_ellipse(Rect2(pos + Vector2(-40, -22), Vector2(80, 26)), Color(mizu, 0.85))
	# 冷光：fuji 紫蓝多层柔光，缓慢呼吸 + 细闪（逢魔的「不对劲」）
	var glow_c: Color = _theme.color(an.get("color", "fuji_500"))
	var speed: float = float(an.get("flicker_speed", 2.6))
	var breath := 0.72 + 0.20 * sin(_elapsed * speed) + 0.08 * sin(_elapsed * speed * 3.7)
	var radius: float = float(an.get("glow_radius", 120))
	for i in range(3):
		var rr: float = radius * (1.0 - i * 0.3) * breath
		draw_circle(pos + Vector2(0, -18), rr, Color(glow_c, 0.16 - i * 0.045))
	# 光心一粒，像水底浮起的灯笼火
	draw_circle(pos + Vector2(0, -18), 7.0 * breath, Color(glow_c, 0.8))

## 进入调查半径：金墨虚线环 + 上浮问号
func _draw_clue_prompt(clue: Dictionary) -> void:
	var pos: Vector2 = _clue_pos(clue)
	var gold: Color = _theme.color("gold_500")
	var rr: float = 64.0 + 5.0 * sin(_elapsed * 4.0)
	var dash := 20
	for i in range(dash):
		var a0 := TAU * float(i) / dash
		var a1 := a0 + TAU / dash * 0.55
		draw_arc(pos + Vector2(0, -30), rr, a0, a1, 12, Color(gold, 0.85), 2.5)
	var font := _font(34)
	if font:
		draw_string(font, pos + Vector2(-12, -108), "?",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 34, gold)

## 线索锚点：x 取自数据；配了 y_abs 直接锚画中器物（钟舌/树洞/钵口沿），
## 否则贴地面剖面 + y_offset
func _clue_pos(clue: Dictionary) -> Vector2:
	var x := float(clue.get("x", 0.0))
	if clue.has("y_abs"):
		return Vector2(x, float(clue["y_abs"]))
	return Vector2(x, _ground_y(x) + float(clue.get("y_offset", 0.0)))

func _update_active_clue() -> void:
	if backdrop_mode:
		return
	_active_clue = null
	for clue in _clues:
		if _resolved.has(clue.get("id", "")):
			continue
		var dist := absf(_player_x - float(clue.get("x", 0.0)))
		if dist <= float(clue.get("radius", 140.0)):
			_active_clue = clue
			break
	if _hint_label != null:
		if _active_clue != null and not _investigating:
			_hint_label.text = "%s —— %s（E 调查）" % [_active_clue.get("name", "异象"), _active_clue.get("hint", "")]
			_hint_label.visible = true
		elif _all_clues_resolved() and not _cfg.get("next", "").is_empty():
			# 异象已尽：提示按 E 前往下一幕（每场只播一次，之后常驻显示）
			if not _exit_prompted:
				_exit_prompted = true
				_show_exit_banner()
			_hint_label.text = "异象已尽 —— 按 E 前往下一幕"
			_hint_label.visible = true
		else:
			_hint_label.visible = false

func _all_clues_resolved() -> bool:
	return not _clues.is_empty() and _resolved.size() >= _clues.size()

## 全部异象解决的一次性横幅（顶部居中，墨线风格）
func _show_exit_banner() -> void:
	var cw: float = get_viewport_rect().size.x
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _theme.washi_panel())
	var l := _hud_label("—— 此幕异象已尽 ——", Vector2.ZERO, 26)
	l.add_theme_color_override("font_color", _theme.color("vermilion_500"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(560, 0)
	panel.add_child(l)
	panel.position = Vector2(cw * 0.5 - 280, 96)
	panel.modulate.a = 0.0
	_hud_layer.add_child(panel)
	var tw: Tween = create_tween().set_parallel()
	tw.tween_property(panel, "modulate:a", 1.0, 0.5)
	tw.tween_property(panel, "position:y", 88, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

## 调查：绘卷推镜聚焦异象 → 墨晕暗角 + 和纸调查面板特写 → 墨线转场进战斗
func _investigate(clue: Dictionary) -> void:
	_investigating = true
	input_enabled = false
	SfxScript.play(self, "seal")
	# 推镜：相机推向异象、画面放大定格（GDD：画面驱动——解密先看懂画面）
	_cinematic = true
	var focus: Vector2 = _clue_pos(clue) + Vector2(0, -50)
	var tw: Tween = create_tween().set_parallel()
	tw.tween_property(_camera, "position", focus, 1.0)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_camera, "zoom", Vector2(1.45, 1.45), 1.0)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	_show_clue_closeup(clue)

## 解密特写：暗角收拢 + 和纸面板浮出（线索名 + 解密文案）
func _show_clue_closeup(clue: Dictionary) -> void:
	if backdrop_mode: return
	var cw := float(_theme.canvas("base_width"))
	var ch := float(_theme.canvas("base_height"))
	var ink: Color = _theme.color("ink_900")
	# 墨晕暗角
	var v := Vignette.new()
	v.ink = ink
	v.position = Vector2.ZERO
	v.size = Vector2(cw, ch)
	v.modulate.a = 0.0
	_hud_layer.add_child(v)
	# 和纸调查面板（底部居中）：线索名金签 + 解密文案墨字
	var panel := Panel.new()
	panel.position = Vector2(cw * 0.5 - 500, ch - 300)
	panel.size = Vector2(1000, 220)
	panel.add_theme_stylebox_override("panel", _theme.washi_panel())
	var name_l := _hud_label(clue.get("name", "异象"), Vector2(28, 18), 22)
	name_l.add_theme_color_override("font_color", _theme.color("vermilion_500"))
	panel.add_child(name_l)
	var body := _hud_label(clue.get("resolve_text", "……"), Vector2(28, 58), 20)
	body.add_theme_color_override("font_color", ink)
	body.custom_minimum_size = Vector2(944, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(body)
	panel.modulate.a = 0.0
	panel.position.y += 24
	_hud_layer.add_child(panel)
	# 浮出演出
	var tw2: Tween = create_tween().set_parallel()
	tw2.tween_property(v, "modulate:a", 1.0, 0.6)
	tw2.tween_property(panel, "modulate:a", 1.0, 0.5).set_delay(0.25)
	tw2.tween_property(panel, "position:y", panel.position.y - 24, 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.25)
	await get_tree().create_timer(2.6).timeout
	# RPG战斗线索随胜利提交；仪式线索沿用入场语义，但先写隔离安全档。
	var battle_path: String = clue.get("battle", "res://scenes/v3/battle.tscn")
	var clue_id: String = clue.get("id", "")
	if RpgRouter.enabled() and (RpgRouter.session.supports(scene_file_path, battle_path, clue_id) or RpgRouter.session.supports_ritual(scene_file_path, battle_path, clue_id)):
		_rpg_pending_clue = clue_id
	else:
		_resolved[clue_id] = true
		_refresh_clue_count()
	InkTransitionScript.transition(get_tree(), func() -> void:
		_go_battle(clue.get("battle", "res://scenes/v3/battle.tscn"))
		if not _investigating:
			v.queue_free()
			panel.queue_free())

## 统一战斗入口：先登记下一场战斗与返回场景，再切战前构筑（GDD §5.2）
func _go_battle(battle_path: String) -> void:
	if backdrop_mode: return
	var started: Dictionary = {}
	if RpgRouter.enabled():
		if RpgRouter.session.supports(scene_file_path, battle_path, _rpg_pending_clue):
			started = RpgRouter.session.begin(scene_file_path, battle_path, export_rpg_world(), _rpg_pending_clue)
		elif RpgRouter.session.supports_ritual(scene_file_path, battle_path, _rpg_pending_clue):
			started = RpgRouter.session.begin_ritual(scene_file_path, battle_path, export_rpg_world(), _rpg_pending_clue)
	if not started.is_empty():
		if started.ok:
			get_tree().change_scene_to_file(started.get("battle_scene", started.get("scene_path", "")))
		else:
			# 失败不进入旧奖励流程，也不提前解决线索；原因留给画面提示。
			if _hint_label != null:
				_hint_label.text = started.error
				_hint_label.visible = true
			if is_inside_tree():
				var notice := AcceptDialog.new()
				notice.title = "存档失败"
				notice.dialog_text = started.error
				add_child(notice)
				notice.confirmed.connect(notice.queue_free)
				notice.canceled.connect(notice.queue_free)
				notice.popup_centered(Vector2i(600, 160))
			input_enabled = true
			_investigating = false
			_cinematic = false
			if _camera != null: _camera.zoom = Vector2.ONE
		return
	NextBattleV4.set_next(battle_path, scene_file_path)
	get_tree().change_scene_to_file("res://scenes/v3/deck.tscn")

# 世界只包含值类型；同场景恢复后，原出口和异象判断继续使用既有字段。
func export_rpg_world() -> Dictionary:
	return {"scene_path": scene_file_path, "player_x": _player_x, "facing": _facing, "resolved": _resolved.duplicate(true), "dlg_fired": _dlg_fired.duplicate(true), "exit_prompted": _exit_prompted, "spirit": _spirit, "party_index": _party_index}

func restore_rpg_world(world: Dictionary) -> void:
	if not RpgStore.validate_world(world).is_empty() or world.get("scene_path") != scene_file_path: return
	if not _party.is_empty() and int(world.party_index) >= _party.size(): return
	_player_x = float(world.player_x)
	_facing = int(world.facing)
	_resolved = world.resolved.duplicate(true)
	_dlg_fired = world.dlg_fired.duplicate(true)
	_exit_prompted = world.exit_prompted
	_spirit = int(world.spirit)
	_party_index = int(world.party_index)
	_refresh_clue_count()
	if _hud_layer != null:
		for child in _hud_layer.get_children():
			if child is InkDots:
				child.value = _spirit
				child.queue_redraw()
		if not _party.is_empty(): _update_party_hud()

func _hud_label(text: String, pos: Vector2, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	var f := _font(sz)
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", _theme.color("paper_100"))
	return l

func _font(_sz: int) -> Font:
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	return f if f else ThemeDB.fallback_font

# ---------- 自动演出：线索验证（验证用，--stage-demo 开启）----------

func _run_auto_demo() -> void:
	await get_tree().create_timer(1.0).timeout
	# 传送到线索调查半径边缘，验证异常渲染 + 提示条
	if _clues.is_empty():
		return
	var clue: Dictionary = _clues[0]
	_player_x = float(clue.get("x", 0.0)) - float(clue.get("radius", 140.0)) * 0.8
	await get_tree().create_timer(1.5).timeout
	_investigate(clue)

var _demo_walking := false # --stage-walk：自动向右走 5 秒（验证走路动画与台阶贴合）

func _run_walk_demo() -> void:
	await get_tree().create_timer(1.0).timeout
	input_enabled = false # 屏蔽键盘，避免与自动走抢输入
	_demo_walking = true
	await get_tree().create_timer(5.0).timeout
	_demo_walking = false

## v3 迁移验收（--stage-anim-check）：右走循环 → J 攻击收招 → 左走朝向翻转 →
## 右走顶墙回待机。分段截图核对各阶段姿势与锚点（脚贴行走遮罩）
func _run_anim_check() -> void:
	await get_tree().create_timer(1.0).timeout
	input_enabled = false
	_demo_walking = true # 1.0–3.0s 右走
	await get_tree().create_timer(2.0).timeout
	_demo_walking = false
	_start_attack() # 3.0s 攻击（0.46s 六姿势收招）
	await get_tree().create_timer(1.2).timeout
	_demo_left = true # 4.2–5.7s 左走（scale 翻转，时间进度不丢）
	await get_tree().create_timer(1.5).timeout
	_demo_left = false
	_demo_walking = true # 5.7s 起右走直至顶 bounds 右墙（回待机不踏步）
	await get_tree().create_timer(4.0).timeout
	_demo_walking = false

## J 键攻击：攻击动画单次播放，期间 _process 锁位移；不可重入（v3 同款）
func _start_attack() -> void:
	if _attacking or not _has_attack_anim or _player == null:
		return
	_attacking = true
	_idle_time = 0.0
	var asp: AnimatedSprite2D = _player as AnimatedSprite2D
	asp.speed_scale = 1.0
	asp.play("attack")

func _on_player_anim_finished(anim: StringName) -> void:
	if anim == "attack":
		_attacking = false
		if _player is AnimatedSprite2D:
			(_player as AnimatedSprite2D).play("idle")

func draw_ground_ellipse(rect: Rect2, c: Color) -> void:
	# draw_circle 的椭圆近似（按高度压缩，CanvasItem.draw_ellipse 为原生方法，勿覆盖）
	var center := rect.get_center()
	var rx := rect.size.x * 0.5
	var ry := rect.size.y * 0.5
	var points := PackedVector2Array()
	for i in range(33):
		var a := TAU * float(i) / 32.0
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(points, c)

func _update_camera(_delta: float) -> void:
	if _camera == null:
		return
	if _cinematic:
		return # 推镜/特写期间相机由 tween 接管
	# 相机跟随：水平跟随角色 + 面向侧领先 120px + 鼠标视差微偏移（±20px）
	var cw := float(_theme.canvas("base_width"))
	var half := cw * 0.5
	var bounds: Array = _cfg.get("bounds", [120, 1800])
	var target_x := _player_x + _facing * 120.0
	# 场景不足宽时不越界
	var min_c := minf(half, bounds[0])
	var max_c := maxf(bounds[1], half)
	if bounds[1] - bounds[0] <= cw:
		target_x = (bounds[0] + bounds[1]) * 0.5
	else:
		target_x = clampf(target_x, half, bounds[1] - half + 200.0)
	var mouse := get_global_mouse_position()
	var par := clampf((mouse.x - target_x) / cw, -0.5, 0.5) * 40.0
	_camera.position = Vector2(target_x + par, 540.0)

# ---------- 工具 ----------

## 地面高度：优先行走遮罩逐列采样（双线性），无遮罩退回分段线性折线
func _ground_y(x: float) -> float:
	if not _ground_cols.is_empty():
		var w := float(_ground_cols.size())
		var fx := clampf(x, 0.0, w - 1.0)
		var i := int(fx)
		var y0 := _ground_cols[i]
		var y1 := _ground_cols[mini(i + 1, _ground_cols.size() - 1)]
		return lerpf(y0, y1, fx - float(i))
	return _ground_y_poly(x)

## 分段线性插值求地面高度（ground_profile 折线，遮罩缺失时的兜底）
func _ground_y_poly(x: float) -> float:
	var pts: Array = _ground
	if pts.is_empty():
		return 900.0
	if x <= float(pts[0][0]):
		return float(pts[0][1])
	for i in range(pts.size() - 1):
		var x0 := float(pts[i][0])
		var y0 := float(pts[i][1])
		var x1 := float(pts[i + 1][0])
		var y1 := float(pts[i + 1][1])
		if x >= x0 and x <= x1:
			return lerpf(y0, y1, (x - x0) / maxf(x1 - x0, 1.0))
	return float(pts[pts.size() - 1][1])

## 贴图直读：FileAccess 走虚拟文件系统，导出 pck 内可用
func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return PngLoader.load_texture(path)
