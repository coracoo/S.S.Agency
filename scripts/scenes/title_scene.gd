class_name TitleScene
extends Node2D
## 《逢魔退治帖》v3 标题屏（GDD §9.4 S1）。
## 全屏实时渲染绘卷背景：直接实例化探索场景作活背景（参道 + 凛音待机 + 鼠标视差），
## 其上叠樱吹雪粒子与 UI 层。竖排题字 + 朱红落款章，按钮悬停金线 120ms 左→右扫过。

const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const RpgRouter = preload("res://scripts/rpg/encounter_router.gd")
const TrialSession = preload("res://scripts/exploration_3d/approach_session.gd")
const TRIAL_MENU_SCENE := "res://scenes/exploration_3d/trial_menu.tscn"

const STAGE_SCENE := "res://scenes/v3/stage.tscn"
const FIRST_STAGE := "res://scenes/v3/stage.tscn" # 「继续退治」直连；「新的委托」走挂轴
const COMMISSION_SCENE := "res://scenes/v3/commission.tscn"
const UIThemeScript = preload("res://scripts/ui/theme.gd")
const InkTransitionScript = preload("res://scripts/ui/ink_transition.gd")
const SfxScript = preload("res://scripts/ui/sfx.gd")
const StageSceneScript = preload("res://scripts/scenes/stage_scene.gd")

var _navigating := false
var _theme = null
var _hud: CanvasLayer = null
var _toast: Label = null
var _bg_stage: Variant = null
var _title_art_error := ""

# 樱吹雪粒子（绘卷背景的氛围层，标题屏专属；正式版迁 StageScene 氛围系统）
var _petals: Array = []
var _petal_colors: Array = []

func _ready() -> void:
	if TrialSession.current != null: TrialSession.current.close()
	RpgRouter.clear_session()
	_theme = UIThemeScript.load_theme()
	_build_live_background()
	_spawn_petals()
	_build_ui()
	if not _title_art_error.is_empty(): _show_toast(_title_art_error)
	set_process(true)

# ---------- 实时绘卷背景 ----------

func _build_live_background() -> void:
	var packed: PackedScene = load(STAGE_SCENE)
	if packed == null:
		push_error("[TitleScene] 无法加载背景场景 %s" % STAGE_SCENE)
		return
	_bg_stage = packed.instantiate()
	# 标题屏只取其「活的」画面：关掉探索输入与 HUD/线索（E 不会误进战斗）
	if _bg_stage.has_method("set"):
		_bg_stage.set("input_enabled", false)
		_bg_stage.set("backdrop_mode", true)
	add_child(_bg_stage)
	_apply_title_identity()

func _apply_title_identity() -> void:
	var definition := Portraits.load_idle_definition("rinne")
	if not definition.get("ok", false):
		_title_art_error = definition.get("error", "高清标题人物未就绪")
		if _bg_stage._player != null: _bg_stage._player.hide()
		return
	var player: AnimatedSprite2D = _bg_stage._player
	var canvas: Dictionary = definition.manifest.canvas
	player.sprite_frames = definition.frames
	player.offset = Vector2(canvas.w, canvas.h) * 0.5 - Vector2(canvas.anchor[0], canvas.anchor[1])
	player.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	player.set_meta("identity_id", "rinne")
	_bg_stage._anim_manifest = definition.manifest
	_bg_stage._player_base_scale = float(_bg_stage._cfg.get("player_height_px", 500)) / float(canvas.content_height_px)
	_bg_stage._has_attack_anim = false
	player.play(&"idle")
	_bg_stage._update_player_transform(0.0)

# ---------- 樱吹雪 ----------

func _spawn_petals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260929
	var paper: Color = _theme.color("paper_100")
	var amber: Color = _theme.color("hi_500")
	for i in range(42):
		_petals.append({
			"x": rng.randf_range(0.0, 1920.0),
			"y": rng.randf_range(0.0, 1080.0),
			"rot": rng.randf_range(0.0, TAU),
			"rot_v": rng.randf_range(-1.6, 1.6),
			"fall": rng.randf_range(26.0, 60.0),
			"sway": rng.randf_range(0.6, 1.6),
			"phase": rng.randf_range(0.0, TAU),
			"scale": rng.randf_range(0.7, 1.3),
		})
		# 多数素白，少数染一点烛火色
		var c: Color = Color(paper, rng.randf_range(0.55, 0.85)) if i % 5 != 0 else Color(amber, 0.7)
		_petal_colors.append(c)

func _process(delta: float) -> void:
	for i in range(_petals.size()):
		var p: Dictionary = _petals[i]
		p["y"] = float(p["y"]) + float(p["fall"]) * delta
		p["x"] = float(p["x"]) + sin(Time.get_ticks_msec() / 1000.0 * float(p["sway"]) + float(p["phase"])) * 22.0 * delta
		p["rot"] = float(p["rot"]) + float(p["rot_v"]) * delta
		if float(p["y"]) > 1110.0:
			p["y"] = -20.0
			p["x"] = fmod(float(p["x"]) + 733.0, 1920.0)
	queue_redraw()

func _draw() -> void:
	# 花瓣：压扁旋转的小椭圆
	for i in range(_petals.size()):
		var p: Dictionary = _petals[i]
		draw_set_transform(Vector2(float(p["x"]), float(p["y"])), float(p["rot"]), Vector2(1.0, 0.62) * float(p["scale"]))
		draw_circle(Vector2.ZERO, 6.0, _petal_colors[i])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------- UI 层 ----------

func _build_ui() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)
	_build_title_column()
	_build_menu()
	_build_footer()
	# 未开放功能 toast
	_toast = _label("", Vector2(660, 920), 20)
	_toast.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud.add_child(_toast)

## 竖排题字 + 朱红落款章（GDD S1：Display 96px 竖排，金色落款章）
func _build_title_column() -> void:
	var chars := "逢\n魔\n退\n治\n帖"
	var title := _label(chars, Vector2(1352, 132), 92)
	var title_font: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf")
	if title_font:
		title.add_theme_font_override("font", title_font)
	title.add_theme_color_override("font_color", _theme.color("paper_100"))
	title.add_theme_color_override("font_outline_color", _theme.color("ink_900"))
	title.add_theme_constant_override("outline_size", 10)
	title.add_theme_constant_override("line_spacing", 10)
	_hud.add_child(title)
	# 落款章：朱红方印 + 寮号
	var seal := Panel.new()
	seal.position = Vector2(1372, 776)
	seal.size = Vector2(76, 76)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _theme.color("vermilion_500")
	sb.set_corner_radius_all(8)
	sb.border_color = Color(_theme.color("paper_100"), 0.65)
	sb.set_border_width_all(2)
	seal.add_theme_stylebox_override("panel", sb)
	_hud.add_child(seal)
	var seal_text := _label("退魔寮", Vector2(1388, 786), 20)
	seal_text.add_theme_color_override("font_color", _theme.color("paper_100"))
	seal_text.add_theme_constant_override("line_spacing", 2)
	_hud.add_child(seal_text)

func _build_menu() -> void:
	var items := [
		{"text": "参道篇试玩", "primary": true, "action": _on_approach_trial},
		{"text": "继续退治", "primary": false, "action": _on_start},
		{"text": "回合制 RPG 试作", "primary": false, "action": _on_rpg_prototype},
		{"text": "新的委托", "primary": false, "action": _on_commission},
		{"text": "妖怪手帖", "primary": false, "action": _on_codex_todo},
		{"text": "设置", "primary": false, "action": _on_settings_todo},
	]
	for i in range(items.size()):
		var it: Dictionary = items[i]
		var btn := _menu_button(String(it["text"]), bool(it["primary"]))
		btn.position = Vector2(820, 400 + i * 82)
		btn.pressed.connect(it["action"])
		_hud.add_child(btn)

## 主菜单按钮：墨框白字；悬停时金线自左向右 120ms「画」过（GDD S1 微交互）
func _menu_button(text: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(330, 64)
	btn.focus_mode = Control.FOCUS_NONE
	var base := StyleBoxFlat.new()
	base.bg_color = Color(_theme.color("ink_900"), 0.55 if primary else 0.35)
	base.border_color = Color(_theme.color("gold_500") if primary else _theme.color("paper_300"), 0.9)
	base.set_border_width_all(2)
	base.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("normal", base)
	btn.add_theme_stylebox_override("hover", base)
	btn.add_theme_stylebox_override("pressed", base)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Medium.ttf")
	if f:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", _theme.color("paper_100"))
	# 金线扫过：按钮底边一根 2px 金线，scale.x 0→1
	var sweep := ColorRect.new()
	sweep.color = _theme.color("gold_500")
	sweep.size = Vector2(330, 2)
	sweep.position = Vector2(0, 62)
	sweep.scale.x = 0.0
	btn.add_child(sweep)
	var tw: Tween = null
	btn.mouse_entered.connect(func() -> void:
		SfxScript.play(self, "bell", -22.0)
		if tw and tw.is_valid():
			tw.kill()
		tw = create_tween()
		tw.tween_property(sweep, "scale:x", 1.0, 0.12))
	btn.mouse_exited.connect(func() -> void:
		if tw and tw.is_valid():
			tw.kill()
		tw = create_tween()
		tw.tween_property(sweep, "scale:x", 0.0, 0.10))
	return btn

func _build_footer() -> void:
	# 底部墨线分隔（GDD S1）+ 版本/版权
	var line := ColorRect.new()
	line.color = Color(_theme.color("ink_900"), 0.8)
	line.size = Vector2(1920, 2)
	line.position = Vector2(0, 1022)
	_hud.add_child(line)
	var ver := _label("v0.3.0 · 技术验证版", Vector2(48, 1036), 14)
	ver.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud.add_child(ver)
	var copy := _label("© 退魔寮", Vector2(1772, 1036), 14)
	copy.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud.add_child(copy)

# ---------- 动作 ----------

func _on_start() -> void:
	if _navigating: return
	_navigating = true
	RpgRouter.clear_session()
	SfxScript.play(self, "card_play")
	InkTransitionScript.transition(get_tree(), func() -> void:
		get_tree().change_scene_to_file(FIRST_STAGE))

func _on_commission() -> void:
	if _navigating: return
	_navigating = true
	RpgRouter.clear_session()
	SfxScript.play(self, "card_play")
	InkTransitionScript.transition(get_tree(), func() -> void:
		get_tree().change_scene_to_file(COMMISSION_SCENE))

func _on_rpg_prototype() -> void:
	if _navigating: return
	_navigating = true
	RpgRouter.clear_session()
	get_tree().change_scene_to_file("res://scenes/rpg/launcher.tscn")

func _on_approach_trial() -> void:
	if _navigating: return
	_navigating = true
	var error := get_tree().change_scene_to_file(TRIAL_MENU_SCENE)
	if error != OK:
		_navigating = false
		_show_toast("参道试玩入口暂时无法加载，请重试。")

func _on_codex_todo() -> void:
	_show_toast("妖怪手帖编纂中……先退治几笔再说吧。")

func _on_settings_todo() -> void:
	_show_toast("笔墨未备，设置待后续版本。")

func _show_toast(text: String) -> void:
	SfxScript.play(self, "bell", -18.0)
	_toast.text = text
	var tw: Tween = create_tween()
	_toast.modulate.a = 1.0
	tw.tween_property(_toast, "modulate:a", 0.0, 1.8).set_delay(1.2)

# ---------- 工具 ----------

func _label(text: String, pos: Vector2, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", _theme.color("paper_100"))
	return l
