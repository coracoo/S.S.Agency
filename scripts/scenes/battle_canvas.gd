extends Node2D
## 《逢魔退治帖》v3 战斗绘卷（GDD §9.4 S4 / §5.2b / §5.4 / §5.5）。
## 玩法逻辑：灵气密度五档（敌方攻击修正/狂暴）、场景槽火势沿 adjacency 蔓延、
## 水钵扑灭、敌方恐惧(遇火)/眩晕(鸣钟)、封印击杀（阵眼≥N 贴符 + 灵气≥M）。
## auto_demo=true 或命令行 --auto-demo 自动打一套封印连招（截图验证用，默认关闭）。

const BattleCardScript = preload("res://scripts/ui/battle_card.gd")
const SceneSlotScript = preload("res://scripts/ui/scene_slot.gd")
const UIThemeScript = preload("res://scripts/ui/theme.gd")
const SfxScript = preload("res://scripts/ui/sfx.gd")
const FxBurstScript = preload("res://scripts/ui/fx_burst.gd")
const InkTransitionScript = preload("res://scripts/ui/ink_transition.gd")

const STAGE_SCENE := "res://scenes/v3/stage.tscn"

## S5 详情卡面：cover 裁切绘制的插画区（TextureRect 的 COVERED 不裁切，手绘可控）
class CoverArt extends Control:
	var tex: Texture2D = null
	func _init() -> void:
		clip_contents = true # cover 裁切会画超尺寸，必须裁剪到控件矩形
	func _draw() -> void:
		if tex == null:
			return
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var s: float = maxf(size.x / maxf(tw, 1.0), size.y / maxf(th, 1.0))
		var w := tw * s
		var h := th * s
		draw_texture_rect(tex, Rect2((size.x - w) * 0.5, (size.y - h) * 0.5, w, h), false)

## 敌方血条（HUD 顶层，盖过立绘）：HP 条 + Boss 破阵阈值金刻度 + 状态签
##  canvas.queue_redraw 盖不到 Sprite2D 子节点，HUD Control 才是正确图层
class EnemyBar extends Control:
	var canvas = null
	var _seen := -1
	func _process(_d: float) -> void:
		if canvas == null:
			return
		var v: int = canvas._hp_version
		if v != _seen:
			_seen = v
			queue_redraw()
	func _draw() -> void:
		if canvas == null or canvas._theme == null:
			return
		var t = canvas._theme
		var ink: Color = t.color("ink_900")
		var verm: Color = t.color("vermilion_500")
		var gold: Color = t.color("gold_500")
		# 多对多：每个存活单位头顶小血条（血条跟随立绘位置），目标选定金标
		if canvas._units.size() > 1:
			for u in canvas._units:
				var sp: Node2D = u.get("sprite")
				if sp == null:
					continue
				var hp_max := maxi(int(u.get("hp_max", 1)), 1)
				var hp := int(u.get("hp", 0))
				var unit_h := float((u.get("data") as Dictionary).get("height_px", 500))
				var w := 150.0
				# EnemyBar 自身位于 HUD 右侧（见 _build_hud）：世界坐标需减去自身位置换成局部坐标
				var tl := sp.position + Vector2(-w * 0.5, -unit_h - 26.0) - position
				draw_rect(Rect2(tl, Vector2(w, 8)), Color(ink, 0.8))
				draw_rect(Rect2(tl, Vector2(w * float(hp) / float(hp_max), 8)), verm)
				# V4 §5.6 标记层：血条上方金点（最多 3）
				var marks := int(u.get("marks", 0))
				for mi in marks:
					draw_circle(tl + Vector2(9 + mi * 20, -16), 7, gold)
					draw_string(canvas._font(11), tl + Vector2(4 + mi * 20, -12), "符",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
				if canvas._awaiting_target:
					var c := tl + Vector2(w * 0.5, -12.0)
					draw_arc(c, 11.0, 0, TAU, 24, gold, 2.5)
					draw_string(canvas._font(16), c + Vector2(-16, -16), "选",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 16, gold)
			return
		var hp_max: int = maxi(canvas._enemy_hp_max, 1)
		draw_rect(Rect2(Vector2.ZERO, Vector2(360, 10)), Color(ink, 0.8))
		var w := 360.0 * float(canvas._enemy_hp) / float(hp_max)
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, 10)), verm)
		var guard := int(canvas._cur_enemy().get("seal_guard", 0))
		if guard > 0 and canvas._enemy_hp > 0 and not canvas._over:
			var tx := 360.0 * float(guard) / float(hp_max)
			draw_line(Vector2(tx, -4), Vector2(tx, 14), gold, 2.0)
			var tag := " 封印可施" if canvas._guard_broken else " 棺气护体"
			var tc: Color = gold if canvas._guard_broken else verm
			draw_string(canvas._font(20), Vector2(0, 34), tag,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, tc)
		# V4 §5.6 标记层：单敌时画在血条右侧
		var fm: Dictionary = canvas._front_unit() if not canvas._units.is_empty() else {}
		var fmarks := int(fm.get("marks", 0))
		for mi in fmarks:
			draw_circle(Vector2(384 + mi * 24, 5), 9, gold)
			draw_string(canvas._font(13), Vector2(378 + mi * 24, 10), "符",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)

## 演示/联调：true 或命令行 --auto-demo 时自动打一套连招（正式默认关闭）
@export var auto_demo := false
## 战斗数据（各幕 .tscn 覆写，实现各幕专属战斗分化）
@export var battle_data_path := "res://data/battles/demo_corridor.json"

var _cfg: Dictionary = {}
var _theme = null

var _enemy_sprite: Node2D = null # Sprite2D 或 AnimatedSprite2D（anims 数据驱动）
var _player_sprite: Node2D = null
# 多敌人波次：enemies 数组按序轮换登场（GDD §5.2b 遭遇战波次）
var _enemies: Array = []
var _enemy_index := 0
var _enemy_name_label: Label = null
var _enemy_hp := 0
var _enemy_hp_max := 1
var _player_hp := 0
var _player_hp_max := 1
# ---- V4 B 期：护盾 / 整理（GDD §5.3 §5.6） ----
var _player_shield := 0 # 护盾先于生命承伤，玩家回合开始清空
var _tidy_used := false # 整理每回合一次
var _tidy_mode := false # 整理激活中：点手牌执行整理
var _tidy_btn: Button = null
var _shield_label: Label = null
var _ap := 0
var _ap_max := 6
var _turn := 0
var _enemy_stunned := false
# Boss 破阵（seal_guard）：HP 降至阈值以下前封印无效（棺气护体）
var _guard_broken := false
# 执念暴怒（obsession，P3）：敌方 obsession_slot 被点燃后该波余下回合无视恐惧、攻击×1.5
var _obsession_rage := false
# 血量版本号：HUD 敌方血条按它增量重绘（queue_redraw 盖不过 Sprite2D 子节点）
var _hp_version := 0
var _enemy_intent := "" # 本回合敌方意图（INTO THE BREACH 式可预测，玩家回合开始即公示）
var _intent_label: Label = null
var _chain := 0
var _busy := false

# 多对多（v3.5）：一波可同场多个敌方单位（数据 count 字段），每单位独立 HP/贴图。
# _units 只存存活单位；_enemy_hp/_enemy_sprite 等旧字段保持「前排单位」派生意义，
# 波级状态（意图/眩晕/破阵/暴怒）仍为全波共享。
var _units: Array = [] # [{data, sprite, hp, hp_max}]
var _awaiting_target := false # 攻击牌多目标选定中
var _pending_attack_card: Variant = null

# 灵气密度（GDD §5.4：0-10 五档，驱动敌方强度与封印条件）
var _spirit := 0
var _spirit_cfg: Dictionary = {}
var _seal_rule: Dictionary = {"min_seal_points": 3, "min_spirit": 6}

var _slots: Dictionary = {}      # id -> scene_slot
var _slot_cfg: Dictionary = {}   # id -> 原始配置（adjacent/seal_point/extinguish）
var _cards: Array = []
var _selected_card: Variant = null
var _over := false

var _hud: CanvasLayer = null
var _hand_layer: Control = null
# 牌组循环（GDD 卡牌手感）：抽牌堆 / 弃牌堆 / 回合补牌
var _deck: Array = []
var _discard: Array = []
var _hand_limit := 5
var _deck_count_label: Label = null
var _discard_count_label: Label = null
var _banner: Label = null
var _hint: Label = null
var _spirit_label: Label = null
# 器物（GDD §7：主战配置 1 件，改变打法、明确触发上限）；_artifact_uses 按效果键记本场次数
var _artifact: Dictionary = {}
var _artifact_uses := {}

func _ready() -> void:
	_theme = UIThemeScript.load_theme()
	_load_data()
	_load_artifact()
	_build_background()
	_build_actors()
	_build_slots()
	_build_hud()
	_new_turn()
	WashiOverlay.add_to(self)
	if "--card-detail" in OS.get_cmdline_user_args():
		_run_card_detail_demo()
	elif auto_demo or "--auto-demo" in OS.get_cmdline_user_args():
		_run_auto_demo()

## 器物载入：构筑存档里登记的 id → data/artifacts.json 定义（无存档/找不到=空器物）
func _load_artifact() -> void:
	_artifact = {}
	_artifact_uses = {}
	var aid := String(BuildSaveV4.load_build().get("artifact", ""))
	if aid.is_empty():
		return
	var f := FileAccess.open("res://data/artifacts.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		for a in (parsed as Array):
			if a is Dictionary and String(a.get("id", "")) == aid:
				_artifact = a
				return

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().change_scene_to_file(STAGE_SCENE))
	if _over and Input.is_action_just_pressed("ui_accept"):
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().reload_current_scene())

# ---------- 数据 ----------

func _load_data() -> void:
	var f := FileAccess.open(battle_data_path, FileAccess.READ)
	if f == null:
		push_error("[BattleCanvas] 缺少 %s" % battle_data_path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_cfg = parsed
	_ap_max = int(_cfg.get("ap_per_turn", 6))
	_spirit_cfg = _cfg.get("spirit", {})
	_seal_rule = _cfg.get("seal_rule", _seal_rule)
	_spirit = int(_spirit_cfg.get("start", 3))
	# 波次阵容：兼容旧版单 enemy 字段
	_enemies = _cfg.get("enemies", [])
	if _enemies.is_empty():
		var legacy: Dictionary = _cfg.get("enemy", {})
		if not legacy.is_empty():
			_enemies = [legacy]

# ---------- 搭建 ----------

func _build_background() -> void:
	var bg := Sprite2D.new()
	bg.texture = _load_texture(_cfg.get("bg", ""))
	bg.centered = false
	var cw := float(_theme.canvas("base_width"))
	var ch := float(_theme.canvas("base_height"))
	if bg.texture:
		var s: float = maxf(cw / bg.texture.get_width(), ch / bg.texture.get_height())
		# 过填充 +8% 并水平居中：视口抖动/转场推镜时不露灰边
		s *= 1.08
		bg.scale = Vector2(s, s)
		bg.position = Vector2(cw * 0.5 - bg.texture.get_width() * s * 0.5, 0)
	add_child(bg)

func _build_actors() -> void:
	var pd: Dictionary = _cfg.get("player", {})
	_player_hp_max = int(pd.get("hp", 30))
	_player_hp = _player_hp_max
	_player_sprite = _make_actor(pd, false)
	_spawn_enemy(0)

func _cur_enemy() -> Dictionary:
	if _enemy_index < _enemies.size():
		var e: Dictionary = _enemies[_enemy_index]
		return e
	return {}

func _spawn_enemy(idx: int) -> void:
	_enemy_index = idx
	_guard_broken = false
	_obsession_rage = false
	_hp_version += 1
	var ed: Dictionary = _cur_enemy()
	# 清上一波单位
	for u in _units:
		var old_sp: Node2D = u.get("sprite")
		if old_sp:
			old_sp.queue_free()
	_units.clear()
	# 组生成：count 个同型单位 staggered 排布（前排靠玩家，错位纵深）
	var count := maxi(1, int(ed.get("count", 1)))
	var spacing := float(ed.get("spacing_px", 230.0))
	var base: Array = ed.get("pos", [1500, 900])
	for i in range(count):
		var d2 := ed.duplicate()
		d2["pos"] = [float(base[0]) - spacing * float(i), float(base[1]) + (26.0 if i % 2 == 1 else 0.0)]
		var sp := _make_actor(d2, true)
		var target_alpha := sp.modulate.a
		sp.modulate.a = 0.0 # 自暗处逐一淡入
		var tw: Tween = sp.create_tween()
		tw.tween_property(sp, "modulate:a", target_alpha, 0.6).set_delay(0.15 * i)
		_units.append({"data": ed, "sprite": sp,
			"hp": int(ed.get("hp", 26)), "hp_max": int(ed.get("hp", 26))})
	_sync_front()

## 前排（最靠玩家）存活单位；空波返回 {}
func _front_unit() -> Dictionary:
	for u in _units:
		if int(u.get("hp", 0)) > 0:
			return u
	return {}

## 派生访问器同步：旧字段 _enemy_hp/_enemy_sprite 始终指前排单位
func _sync_front() -> void:
	var u := _front_unit()
	_enemy_sprite = u.get("sprite")
	_enemy_hp = int(u.get("hp", 0))
	_enemy_hp_max = maxi(1, int(u.get("hp_max", 1)))

## 敌方被击败（HP 归零或封印击杀）：还有下一波则轮换登场，否则结算
func _enemy_died(win_text: String) -> void:
	if _over:
		return
	if _enemy_index + 1 < _enemies.size():
		_start_next_wave()
	else:
		_game_over(win_text)

func _start_next_wave() -> void:
	_busy = true
	await get_tree().create_timer(0.9).timeout
	# 随上一波消散的残符清场，重新布置阵眼
	for sid in _slots.keys():
		var slot: Variant = _slots[sid]
		if slot.state == "sealed":
			slot.state = "idle"
	_spawn_enemy(_enemy_index + 1)
	var ed: Dictionary = _cur_enemy()
	if _enemy_name_label:
		_enemy_name_label.text = ed.get("name", "")
	var n := maxi(1, int(ed.get("count", 1)))
	var wave_txt := "—— 第 %d 波 · %s ——" % [_enemy_index + 1, ed.get("name", "")]
	if n > 1:
		wave_txt = "—— 第 %d 波 · %s ×%d ——" % [_enemy_index + 1, ed.get("name", ""), n]
	_float_text(Vector2(960, 320), wave_txt,
		_theme.color("vermilion_500"), 30)
	SfxScript.play(self, "explosion", -8.0)
	_busy = false
	_compute_intent()
	queue_redraw()

func _make_actor(d: Dictionary, flip: bool) -> Node2D:
	# 优先逐帧动画（anims 数据驱动：idle 循环 / cast 单次施法），无数据退回单帧
	var anims: Dictionary = d.get("anims", {})
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var built := 0
	for state in ["idle", "cast"]:
		var cell_frames: Array[Texture2D] = []
		for p in anims.get(state, []):
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
				for t in cell_frames:
					frames.add_frame(state, t)
			built += 1
	if built > 0:
		var asp := AnimatedSprite2D.new()
		asp.sprite_frames = frames
		if frames.has_animation("cast"):
			frames.set_animation_loop("cast", false) # 施法单次播放，结束自动停末帧
		var first := "idle" if frames.has_animation("idle") else "cast"
		var fh := float(frames.get_frame_texture(first, 0).get_height())
		var target_h := float(d.get("height_px", 500))
		var s: float = target_h / fh
		asp.scale = Vector2(s * (-1.0 if flip else 1.0), s)
		asp.offset = Vector2(0, -fh * 0.5)
		var p0: Array = d.get("pos", [200, 900])
		asp.position = Vector2(p0[0], p0[1])
		var tint0: Array = d.get("tint", [])
		if tint0.size() >= 3:
			asp.modulate = Color(float(tint0[0]), float(tint0[1]), float(tint0[2]))
		add_child(asp)
		asp.play(first)
		return asp
	var sp := Sprite2D.new()
	sp.texture = _load_texture(d.get("sprite", ""))
	var target_h := float(d.get("height_px", 500))
	if sp.texture:
		var s: float = target_h / sp.texture.get_height()
		sp.scale = Vector2(s * (-1.0 if flip else 1.0), s)
		sp.offset = Vector2(0, -sp.texture.get_height() * 0.5)
	var p: Array = d.get("pos", [200, 900])
	sp.position = Vector2(p[0], p[1])
	# 可选色调（波次敌人复用贴图时用 tint 区分）
	var tint: Array = d.get("tint", [])
	if tint.size() >= 3:
		sp.modulate = Color(float(tint[0]), float(tint[1]), float(tint[2]))
	add_child(sp)
	return sp

## 我方施法演出：出牌时播 cast 帧动画，播完回 idle（无动画数据静默跳过）
func _play_player_cast() -> void:
	if _player_sprite is AnimatedSprite2D:
		var asp: AnimatedSprite2D = _player_sprite as AnimatedSprite2D
		if asp.sprite_frames.has_animation("cast"):
			asp.play("cast")
			if not asp.animation_finished.is_connected(_on_cast_finished):
				asp.animation_finished.connect(_on_cast_finished)

func _on_cast_finished() -> void:
	if _player_sprite is AnimatedSprite2D:
		(_player_sprite as AnimatedSprite2D).play("idle")

# ---------- 法术特效（AI 帧表，assets/fx，绘本水彩） ----------
const VFX_FILES := {
	"fire": ["fire_burst_f1.png", "fire_burst_f2.png", "fire_burst_f3.png",
		"fire_burst_f4.png", "fire_burst_f5.png", "fire_burst_f6.png"],
	"bell": ["bell_wave_f1.png", "bell_wave_f2.png", "bell_wave_f3.png", "bell_wave_f4.png"],
	"seal": ["seal_burst_f1.png", "seal_burst_f2.png", "seal_burst_f3.png",
		"seal_burst_f4.png", "seal_burst_f5.png", "seal_burst_f6.png"],
}
const VFX_FPS := 14.0

## 在世界坐标 at 处播放一次性法术帧动画，播完自动释放
func _play_vfx(kind: String, at: Vector2, px := 420.0) -> void:
	var files: Array = VFX_FILES.get(kind, [])
	if files.is_empty():
		return
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("fx")
	frames.set_animation_loop("fx", false)
	frames.set_animation_speed("fx", VFX_FPS)
	for fn in files:
		var t: Texture2D = _load_texture("res://assets/fx/" + fn)
		if t != null:
			frames.add_frame("fx", t)
	if frames.get_frame_count("fx") == 0:
		return
	var asp := AnimatedSprite2D.new()
	asp.sprite_frames = frames
	var s := px / float(frames.get_frame_texture("fx", 0).get_height())
	asp.scale = Vector2(s, s)
	asp.position = at
	asp.z_index = 30 # 高于立绘（槽位火环/槽位本身），低于手牌
	add_child(asp)
	asp.play("fx")
	asp.animation_finished.connect(asp.queue_free)

func _build_slots() -> void:
	var cw := float(_theme.canvas("base_width"))
	var ch := float(_theme.canvas("base_height"))
	for s: Dictionary in _cfg.get("slots", []):
		var sid: String = s.get("id", "")
		_slot_cfg[sid] = s
		var slot: Variant = SceneSlotScript.new()
		var frac: Array = s.get("pos", [0.5, 0.5])
		slot.setup(sid, s.get("name", ""), _theme,
			Vector2(frac[0] * cw, frac[1] * ch))
		slot.seal_point = s.get("seal_point", false)
		slot.extinguish = s.get("extinguish", false)
		slot.adjacent = s.get("adjacent", [])
		slot.state = s.get("state", "idle")
		slot.slot_clicked.connect(_on_slot_clicked)
		add_child(slot)
		_slots[sid] = slot

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var top := _label("回合 %d" % _turn, Vector2(60, 26), 24)
	top.name = "TurnLabel"
	_hud.add_child(top)
	# 灵气组移到右下（对标已批准战斗合成图：右上角只留回合横幅与意图徽标）
	_spirit_label = _label("灵气 %d/10" % _spirit, Vector2(1300, 894), 20)
	_spirit_label.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud.add_child(_spirit_label)
	for i in range(10):
		var dot := _label("●", Vector2(1300 + i * 24, 924), 14)
		dot.name = "SpiritDot%d" % i
		_hud.add_child(dot)

	_hud.add_child(_label(_cfg.get("player", {}).get("name", ""), Vector2(150, 986), 20))
	var en: Dictionary = _cur_enemy()
	var el := _label(en.get("name", ""), Vector2(1300, 824), 20)
	el.name = "EnemyName"
	_enemy_name_label = el
	_hud.add_child(el)
	# 敌方血条（含 Boss 破阵可视化）：右侧横条（对标合成图位置）
	var ebar := EnemyBar.new()
	ebar.canvas = self
	ebar.position = Vector2(1300, 856)
	ebar.size = Vector2(500, 22)
	_hud.add_child(ebar)
	# 敌方意图气泡（GDD 参考作品：可预测敌人意图）——悬于立绘上方
	_intent_label = _label("", Vector2(1150, 130), 22)
	_intent_label.size = Vector2(500, 30)
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intent_label.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud.add_child(_intent_label)

	var btn := Button.new()
	btn.text = "结束回合"
	btn.position = Vector2(1630, 988)
	btn.custom_minimum_size = Vector2(220, 52)
	btn.pressed.connect(_on_end_turn)
	_hud.add_child(btn)
	# V4 §5.3 整理按钮：每回合一次，1 灵墨换手牌
	_tidy_btn = Button.new()
	_tidy_btn.position = Vector2(1486, 988)
	_tidy_btn.custom_minimum_size = Vector2(120, 52)
	_tidy_btn.pressed.connect(_on_tidy_pressed)
	_hud.add_child(_tidy_btn)
	_update_tidy_btn()
	# 护盾数值（血条上方蓝条在 _draw，数值标签在此）
	_shield_label = _label("", Vector2(580, 942), 18)
	_shield_label.add_theme_color_override("font_color", _theme.color("fuji_500"))
	_shield_label.visible = false
	_hud.add_child(_shield_label)
	# 器物铭牌（GDD §7）：开战即明示本场携带的器物与触发上限
	if not _artifact.is_empty():
		var art_label := _label("器物 · %s（上限 %d）" % [
			_artifact.get("name", ""), int(_artifact.get("limit", 0))], Vector2(580, 966), 15)
		art_label.add_theme_color_override("font_color", _theme.color("gold_500"))
		_hud.add_child(art_label)
	# 牌堆 / 弃牌堆计数（牌组循环可视化）——敌方血条下方纵排
	_deck_count_label = _label("牌堆 0", Vector2(1300, 978), 16)
	_deck_count_label.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud.add_child(_deck_count_label)
	_discard_count_label = _label("弃牌 0", Vector2(1300, 1004), 16)
	_discard_count_label.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hud.add_child(_discard_count_label)

	_banner = _label("", Vector2(560, 400), 72)
	_banner.name = "Banner"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_color", _theme.color("gold_500"))
	_banner.visible = false
	_hud.add_child(_banner)
	_hint = _label("", Vector2(760, 500), 20)
	_hint.add_theme_color_override("font_color", _theme.color("paper_300"))
	_hint.visible = false
	_hud.add_child(_hint)

	_hand_layer = Control.new()
	_hand_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hand_layer)
	_deal_hand()
	_refresh_spirit_hud()

# ---------- 灵气 HUD ----------

func _refresh_spirit_hud() -> void:
	var hot := _spirit >= int(_spirit_cfg.get("empowered_from", 6))
	for i in range(10):
		var dot: Label = _hud.get_node_or_null("SpiritDot%d" % i)
		if dot == null:
			continue
		var filled := i < _spirit
		var c: Color = _theme.color("paper_100") if not hot else _theme.color("vermilion_500")
		dot.add_theme_color_override("font_color",
			c if filled else Color(c, 0.18))
	_spirit_label.text = "灵气 %d/10" % _spirit
	_spirit_label.add_theme_color_override("font_color",
		_theme.color("vermilion_500") if hot else _theme.color("paper_300"))

## 灵气五档攻击修正（GDD §5.4：weak/正常/强化/暴走/百鬼夜行）
func _spirit_attack_mult() -> float:
	var mults: Dictionary = _spirit_cfg.get("tier_attack_mult", {})
	if _spirit >= 10:
		return float(mults.get("berserk", 1.5))
	if _spirit >= int(_spirit_cfg.get("berserk_from", 8)):
		return float(mults.get("berserk", 1.5))
	if _spirit >= int(_spirit_cfg.get("empowered_from", 6)):
		return float(mults.get("empowered", 1.3))
	if _spirit < int(_spirit_cfg.get("weak_below", 3)):
		return float(mults.get("weak", 0.7))
	return float(mults.get("normal", 1.0))

func _is_berserk() -> bool:
	return _spirit >= int(_spirit_cfg.get("berserk_from", 8))

# ---------- 手牌 ----------

func _deal_hand() -> void:
	_hide_tooltip()
	for c in _cards:
		c.queue_free()
	_cards.clear()
	_deck.clear()
	_discard.clear()
	# 牌组：构筑优先、旧配置兜底、器物结界折扣，统一走 CardLibraryV4.build_deck_defs
	_deck = CardLibraryV4.build_deck_defs(_cfg, _artifact)
	var hand_limit := int(_cfg.get("deck", {}).get("hand_limit", 5))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_deck.shuffle()
	_hand_limit = hand_limit
	_draw_cards(_hand_limit)
	_refresh_pile_counts()

## 补牌 n 张：抽牌堆空了先重洗弃牌堆（杀戮尖塔式循环）
func _draw_cards(n: int) -> void:
	for i in n:
		if _deck.is_empty():
			if _discard.is_empty():
				return
			_deck = _discard.duplicate()
			_discard.clear()
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			_deck.shuffle()
			_float_text(Vector2(960, 640), "洗 牌", _theme.color("paper_300"), 22)
			SfxScript.play(self, "card_play", -18.0)
			_refresh_pile_counts()
		var def: Dictionary = _deck.pop_front()
		_spawn_hand_card(def)
	_refresh_pile_counts()

func _spawn_hand_card(def: Dictionary) -> void:
	var card: Variant = BattleCardScript.new()
	card.setup(def, _theme)
	card.clicked.connect(_on_card_clicked)
	card.hover_changed.connect(_on_card_hover)
	_hand_layer.add_child(card)
	_cards.append(card)
	_relayout_hand()
	_hide_tooltip()
	# 从牌堆位置飞入手位
	card.position = Vector2(1760, 986)
	card.scale = Vector2(0.4, 0.4)
	var home: Vector2 = card._home_pos
	var tw: Tween = card.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "position", home, 0.3)
	tw.parallel().tween_property(card, "scale", Vector2.ONE, 0.3)
func _refresh_pile_counts() -> void:
	if _deck_count_label:
		_deck_count_label.text = "牌堆 %d" % _deck.size()
	if _discard_count_label:
		_discard_count_label.text = "弃牌 %d" % _discard.size()

func _refresh_card_states() -> void:
	for c in _cards:
		c.disabled = not BattleRulesV4.can_afford(c.data, _ap)

# ---------- 出牌 ----------

func _on_card_clicked(card: Variant) -> void:
	if _over or _busy:
		return
	_hide_tooltip()
	# 费用闸：AP 不足置灰的卡不能打出（置灰只是视觉，点击/详情弹窗打出都要拦）
	if card.disabled or not BattleRulesV4.can_afford(card.data, _ap):
		_float_text(Vector2(960, 640), "灵墨不足", _theme.color("fuji_500"), 22)
		return
	# V4 §5.3 整理激活中：点击手牌 = 暂存该牌、抽一张、弃置暂存
	if _tidy_mode:
		_tidy_card(card)
		return
	if _selected_card == card:
		card.set_selected(false)
		_selected_card = null
		_set_slots_targetable(null)
		return
	if _selected_card != null:
		_selected_card.set_selected(false)
		_selected_card = null
	if _awaiting_target:
		# 目标选定中：再点同一张卡取消；点其他卡先取消再处理新卡
		var was_pending: Variant = _pending_attack_card
		_cancel_targeting()
		if was_pending == card:
			return
	if card.data.get("type", "attack") == "attack":
		if _units.size() > 1 and not auto_demo:
			_begin_targeting(card) # 多目标：高亮等点选
			SfxScript.play(self, "card_play", -16.0)
		elif _units.size() > 0:
			_play_attack(card, _front_unit())
		return
	# V4 §5.4 术法/防护：需选敌（标记）走目标选定；其余（护盾/灵气）直接结算
	if card.data.get("type", "") == "skill":
		if card.data.get("target", "") == "enemy":
			if _units.size() > 1 and not auto_demo:
				_begin_targeting(card)
				SfxScript.play(self, "card_play", -16.0)
			elif _units.size() > 0:
				_play_skill(card, _front_unit())
		else:
			_play_skill(card, {})
		return
	if _selected_card == card:
		card.set_selected(false)
		_selected_card = null
		_set_slots_targetable(null)
		return
	if _selected_card != null:
		_selected_card.set_selected(false)
		_selected_card = null
	card.set_selected(true)
	_selected_card = card
	_set_slots_targetable(card)
	SfxScript.play(self, "card_play", -14.0)

# ---------- 卡牌悬浮说明（替代原 S5 详情弹层：悬停浮出，移开即散）----------

var _tooltip: CardTooltip = null
var _tooltip_card: Variant = null

func _on_card_hover(card: Variant, is_hovered: bool) -> void:
	if is_hovered:
		_hide_tooltip()
		_tooltip = CardTooltip.build(_theme, card.data)
		_tooltip_card = card
		_hand_layer.add_child(_tooltip)
		_tooltip.call_deferred("place_above", card)
	else:
		# 快速移过相邻牌时 exit 可能晚于下一张的 enter，只收自己这张的
		if _tooltip_card == card:
			_hide_tooltip()

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.queue_free()
	_tooltip = null
	_tooltip_card = null

func _detail_button(text: String, pos: Vector2, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(240, 56)
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(_theme.color("ink_900"), 0.9 if primary else 0.6)
	sb.border_color = _theme.color("gold_500") if primary else _theme.color("paper_300")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_font_override("font", _font(22))
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", _theme.color("paper_100"))
	return btn

## --card-detail 冒烟：直接浮出首张手牌的悬浮说明
func _run_card_detail_demo() -> void:
	await get_tree().create_timer(1.2).timeout
	if _cards.is_empty():
		return
	_on_card_hover(_cards[0], true)

## 目标合法性：结界符只能贴阵眼，其余场景卡任意空闲槽（GDD §5.5）
func _set_slots_targetable(card: Variant) -> void:
	for sid in _slots:
		var slot: Variant = _slots[sid]
		# 目标资格走统一规则（V4：预览与实际结算同一判定点，错误目标不扣费）
		var ok: bool = card != null and BattleRulesV4.slot_targetable(card.data,
				{"state": slot.state, "seal_point": slot.seal_point})
		if ok:
			slot.state = "targetable"
		elif slot.state == "targetable":
			slot.state = "idle"

func _on_slot_clicked(slot: Variant) -> void:
	if _awaiting_target:
		return # 攻击目标选定中：槽位点击交给 _unhandled_input 的单位命中
	if _selected_card == null or _busy or _over:
		return
	if slot == null or slot.state != "targetable":
		# 无效目标：取消选中，避免卡牌悬空选中导致无法结束回合
		_selected_card.set_selected(false)
		_selected_card = null
		_set_slots_targetable(null)
		return
	var card: Variant = _selected_card
	_selected_card = null
	card.set_selected(false)
	_busy = true
	_play_player_cast()
	var slot_state: String = card.data.get("slot_state", "idle")
	_spend_ap(int(card.data.get("cost", 0)))
	var target: Vector2 = slot.position
	_fly_card(card, target)
	SfxScript.play(self, "card_play")
	await get_tree().create_timer(0.28).timeout
	slot.state = slot_state
	var new_state: String = slot_state
	if new_state == "burning":
		SfxScript.play(self, "fire_ignite")
		_play_vfx("fire", slot.position + Vector2(0, -100))
	elif new_state == "ringing":
		SfxScript.play(self, "bell")
		_play_vfx("bell", slot.position + Vector2(0, -120))
		# 钟鸣惊焰（卡牌效果文承诺的连锁）：鸣响当场清除全场燃烧，防火势封死阵眼
		var put_out := false
		for s2 in _slots.values():
			if s2.state == "burning":
				s2.state = "idle"
				put_out = true
		if put_out:
			_float_text(Vector2(960, 260), "钟鸣惊焰 —— 火势尽熄",
				_theme.color("gold_500"), 26)
	elif new_state == "sealed":
		SfxScript.play(self, "seal")
		_play_vfx("seal", slot.position + Vector2(0, -130))
	else:
		SfxScript.play(self, "door")
	FxBurstScript.burst(self, target, _theme.color("hi_500"))
	_float_text(target + Vector2(0, -80), _slot_state_text(new_state),
		_theme.color("gold_500") if new_state == "sealed" else _theme.color("hi_500"))
	# 执念机制（P3，v2 obsession 的 v3 语义重实现）：敌方 obsession_slot 被点燃 →
	# 该波余下回合无视恐惧、攻击 ×1.5（玩家可用「引燃逼暴走换封印窗口」做决策）
	var en0: Dictionary = _cur_enemy()
	if new_state == "burning" and _enemy_hp > 0 and not _over \
			and not _obsession_rage \
			and String(en0.get("obsession_slot", "")) == slot.slot_id:
		_obsession_rage = true
		_float_text(Vector2(960, 380),
			String(en0.get("obsession_text", "执念受威胁——暴怒！")),
			_theme.color("vermilion_500"), 30)
		SfxScript.play(self, "explosion", -8.0)
	_chain += 1
	if new_state == "sealed":
		_chain += 1
	_show_chain()
	_busy = false

func _slot_state_text(s: String) -> String:
	return {"burning": "燃烧！", "ringing": "鸣响！", "spilled": "倾覆！", "sealed": "镇符！"}.get(s, s)

func _play_attack(card: Variant, unit: Dictionary) -> void:
	_busy = true
	_play_player_cast()
	var power := int(card.data.get("power", 0))
	_spend_ap(int(card.data.get("cost", 0)))
	var sp: Node2D = unit.get("sprite")
	var target: Vector2 = sp.position + Vector2(0, -260)
	_fly_card(card, target)
	SfxScript.play(self, "card_play")
	await get_tree().create_timer(0.28).timeout
	# V4 §5.6 标记消耗：带 consume_mark 的卡（追符斩）消耗标记层数换加成
	var fx: Dictionary = BattleRulesV4.parse_effects(card.data)
	if fx["consume_mark"] > 0:
		var mb: Dictionary = BattleRulesV4.consume_marks_for_bonus(power,
				int(unit.get("marks", 0)), fx["consume_mark"], fx["bonus"])
		power = int(mb["power"])
		if int(mb["consumed"]) > 0:
			unit["marks"] = BattleRulesV4.add_marks(int(unit.get("marks", 0)), -int(mb["consumed"]))
			_hp_version += 1
			_float_text(sp.position + Vector2(0, -660), "标记迸发 +%d" % fx["bonus"],
				_theme.color("gold_500"), 26)
	var burning := _has_slot_state("burning")
	if burning:
		power += 3
	FxBurstScript.burst(self, target, _theme.color("vermilion_500"))
	SfxScript.play(self, "hurt")
	_damage_unit(unit, power)
	if burning:
		_float_text(sp.position + Vector2(120, -460), "火助 +3", _theme.color("hi_500"))
	_chain += 1
	_show_chain()
	_busy = false

## V4 §5.4 术法/防护结算：护盾/净化/标记/灵气/抽牌（unit 仅标记目标需要）
func _play_skill(card: Variant, unit: Dictionary = {}) -> void:
	_busy = true
	_play_player_cast()
	_spend_ap(int(card.data.get("cost", 0)))
	var fx: Dictionary = BattleRulesV4.parse_effects(card.data)
	_fly_card(card, Vector2(960, 420))
	SfxScript.play(self, "card_play")
	await get_tree().create_timer(0.28).timeout
	var anchor := Vector2(960, 420)
	if not unit.is_empty():
		var usp: Node2D = unit.get("sprite")
		anchor = usp.position + Vector2(0, -560)
	var lines: Array = []
	if fx["shield"] > 0:
		# 器物：守心佩类——护盾值额外加成（明确触发上限）
		var sbonus := BattleRulesV4.artifact_value(_artifact, "shield_bonus",
			int(_artifact_uses.get("shield_bonus", 0)))
		_player_shield += fx["shield"] + sbonus
		if sbonus > 0:
			_artifact_uses["shield_bonus"] = int(_artifact_uses.get("shield_bonus", 0)) + 1
			lines.append("护盾 +%d（%s +%d）" % [fx["shield"] + sbonus, _artifact.get("name", "器物"), sbonus])
		else:
			lines.append("护盾 +%d" % fx["shield"])
	if fx["cleanse"] > 0:
		lines.append("净化")
	if fx["spirit"] != 0:
		_spirit = clampi(_spirit + fx["spirit"], 0, 10)
		_refresh_spirit_hud()
		lines.append("灵气 %+d" % fx["spirit"])
	if fx["draw"] > 0:
		_draw_cards(fx["draw"])
		lines.append("抽牌 %d" % fx["draw"])
	if not unit.is_empty() and fx["mark"] > 0:
		unit["marks"] = BattleRulesV4.add_marks(int(unit.get("marks", 0)), fx["mark"])
		_hp_version += 1
		FxBurstScript.burst(self, anchor, _theme.color("gold_500"))
		lines.append("标记 +%d（%d/3）" % [fx["mark"], int(unit["marks"])])
	for i in lines.size():
		_float_text(anchor + Vector2(0, -46 * i), String(lines[i]),
			_theme.color("fuji_500"), 26)
	_refresh_shield()
	_discard_card(card)
	_chain += 1
	_show_chain()
	_busy = false

# ---------- V4 §5.3 整理：每回合一次、1 灵墨：暂存手牌→抽一张→弃置暂存 ----------

func _on_tidy_pressed() -> void:
	if _over or _busy:
		return
	if _tidy_mode: # 再点取消
		_tidy_mode = false
		if _hint:
			_hint.text = ""
			_hint.visible = false
		_update_tidy_btn()
		return
	var check: Dictionary = BattleRulesV4.can_tidy({
		"ap": _ap + _tidy_free_credit(), "used": _tidy_used, "hand": _cards.size(),
		"deck": _deck.size(), "discard": _discard.size(),
	})
	if not check["ok"]:
		_float_text(Vector2(960, 640), String(check["reason"]), _theme.color("fuji_500"), 22)
		return
	_tidy_mode = true
	if _hint:
		_hint.text = "整理：选择一张手牌暂存换抽（再点「整理」取消）"
		_hint.visible = true
	_update_tidy_btn()

func _tidy_card(card: Variant) -> void:
	var def: Dictionary = card.data
	var check: Dictionary = BattleRulesV4.can_tidy({
		"ap": _ap + _tidy_free_credit(), "used": _tidy_used, "hand": _cards.size(),
		"deck": _deck.size(), "discard": _discard.size(),
	})
	if not check["ok"]: # 激活后状态变化（如牌被打掉）：不可用即取消
		_float_text(Vector2(960, 640), String(check["reason"]), _theme.color("fuji_500"), 22)
		_tidy_mode = false
		_update_tidy_btn()
		return
	_tidy_mode = false
	_tidy_used = true
	var credit := _tidy_free_credit()
	if credit > 0:
		# 器物：净火香囊类——本场第一次整理免灵墨
		_artifact_uses["tidy_free_once"] = int(_artifact_uses.get("tidy_free_once", 0)) + 1
		_float_text(Vector2(960, 600), "%s · 免费整理" % _artifact.get("name", "器物"),
			_theme.color("gold_500"), 24)
	else:
		_spend_ap(1)
	if _hint:
		_hint.text = ""
		_hint.visible = false
	_cards.erase(card)
	card.queue_free()
	_relayout_hand()
	_draw_cards(1) # 先抽（暂存张不进弃牌堆，不会抽回自身）
	_discard.append(def)
	_refresh_pile_counts()
	_float_text(Vector2(960, 600), "整 理", _theme.color("paper_300"), 24)
	_update_tidy_btn()

func _update_tidy_btn() -> void:
	if _tidy_btn == null:
		return
	_tidy_btn.text = "整理·选牌中" if _tidy_mode else ("整理" if not _tidy_used else "整理(已用)")
	_tidy_btn.disabled = _over

## 器物：净火香囊类——本场第一次整理免灵墨；未达触发上限返回 1 点费用抵扣
func _tidy_free_credit() -> int:
	var free := BattleRulesV4.artifact_value(_artifact, "tidy_free_once",
		int(_artifact_uses.get("tidy_free_once", 0)))
	return 1 if free > 0 else 0

func _refresh_shield() -> void:
	if _shield_label != null:
		_shield_label.text = "护盾 %d" % _player_shield
		_shield_label.visible = _player_shield > 0
	queue_redraw()

func _fly_card(card: Variant, target: Vector2) -> void:
	var tw: Tween = card.create_tween().set_parallel()
	tw.tween_property(card, "position",
		target - card.size * card.scale * 0.5, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "scale", card.scale * 0.25, 0.28)
	tw.chain().tween_callback(_discard_card.bind(card))

func _discard_card(card: Variant) -> void:
	_discard.append(card.data)
	_cards.erase(card)
	card.queue_free()
	_relayout_hand()
	_refresh_pile_counts()

func _relayout_hand() -> void:
	var n := _cards.size()
	if n == 0:
		return
	var spacing := 138 if n <= 5 else 118
	var cw := 176
	var ch := 246
	var x0 := (1920 - (spacing * (n - 1) + cw)) * 0.5
	# 扇形布局（对标已批准战斗合成图）：绕牌心微旋转，边缘牌略抬
	var mid := (n - 1) * 0.5
	for i in _cards.size():
		var off := float(i) - mid
		_cards[i].pivot_offset = _cards[i].size * 0.5
		_cards[i].rotation_degrees = off * 2.6
		_cards[i].set_home(Vector2(x0 + i * spacing, 1080 - ch - 16 - absf(off) * 8))
		var tw2: Tween = _cards[i].create_tween()
		tw2.tween_property(_cards[i], "position", _cards[i]._home_pos, 0.25)

func _has_slot_state(s: String) -> bool:
	for slot in _slots.values():
		if slot.state == s:
			return true
	return false

func _count_slot_state(s: String) -> int:
	var n := 0
	for slot in _slots.values():
		if slot.state == s:
			n += 1
	return n

func _spend_ap(cost: int) -> void:
	_ap = maxi(0, _ap - cost)
	_refresh_card_states()
	queue_redraw()

func _show_chain() -> void:
	if _chain >= 2:
		_float_text(Vector2(960, 260), "连锁 ×%d" % _chain,
			_theme.color("gold_500"), 40)

## 对指定敌方单位造成伤害；击杀后移出 _units，全灭则推进波次/结算
func _damage_unit(u: Dictionary, amount: int) -> void:
	if _units.is_empty():
		return
	u["hp"] = maxi(0, int(u.get("hp", 0)) - amount)
	_hp_version += 1
	var sp: Node2D = u.get("sprite")
	_float_text(sp.position + Vector2(0, -560), "-%d" % amount,
		_theme.color("vermilion_500"))
	# Boss 破阵：首次降至 seal_guard 阈值以下，棺盖碎裂、封印解禁
	var guard := int((u.get("data") as Dictionary).get("seal_guard", 0))
	if guard > 0 and not _guard_broken and int(u["hp"]) > 0 and int(u["hp"]) <= guard:
		_guard_broken = true
		_float_text(Vector2(960, 240), "棺盖碎裂 —— 封印可施！",
			_theme.color("gold_500"), 34)
		FxBurstScript.burst(self, sp.position + Vector2(0, -420),
			_theme.color("gold_500"), 40, 260.0)
		SfxScript.play(self, "explosion", -6.0)
	var tw: Tween = sp.create_tween()
	tw.tween_property(sp, "position:x", sp.position.x + 14, 0.05)
	tw.tween_property(sp, "position:x", sp.position.x, 0.2)
	sp.modulate = Color(1.8, 1.2, 1.2)
	var tw2: Tween = sp.create_tween()
	tw2.tween_property(sp, "modulate", Color.WHITE, 0.3)
	if int(u["hp"]) <= 0:
		_kill_unit(u)
	_sync_front()
	queue_redraw()

func _kill_unit(u: Dictionary) -> void:
	_units.erase(u)
	var sp: Node2D = u.get("sprite")
	if sp:
		var tw: Tween = sp.create_tween().set_parallel()
		tw.tween_property(sp, "modulate:a", 0.0, 0.5)
		tw.tween_property(sp, "scale", sp.scale * 0.85, 0.5)
		tw.chain().tween_callback(sp.queue_free)
	if _units.is_empty():
		_enemy_died("退 治 成 功")

## 攻击牌目标选定：多单位同场时高亮可选，点击单位确认；再点同一张卡取消
func _begin_targeting(card: Variant) -> void:
	_awaiting_target = true
	_pending_attack_card = card
	if _hint:
		_hint.text = "选定攻击目标（再点卡牌取消）"
		_hint.visible = true
	_hp_version += 1 # 触发 EnemyBar 画目标高亮

func _cancel_targeting() -> void:
	_awaiting_target = false
	_pending_attack_card = null
	if _hint:
		_hint.text = ""
		_hint.visible = false
	_hp_version += 1

func _unhandled_input(ev: InputEvent) -> void:
	if not _awaiting_target or _over:
		return
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var m: Vector2 = (ev as InputEventMouseButton).position
		var best: Dictionary = {}
		var best_dx := 1e9
		for u in _units:
			var sp: Node2D = u.get("sprite")
			var dx := absf(m.x - sp.position.x)
			# 立绘纵向范围宽松命中（脚底锚点上方 ~height）
			if dx < 150.0 and m.y > sp.position.y - 800.0 and m.y < sp.position.y + 60.0 \
					and dx < best_dx:
				best = u
				best_dx = dx
		if not best.is_empty():
			var card: Variant = _pending_attack_card
			_cancel_targeting()
			if String(card.data.get("type", "")) == "skill":
				_play_skill(card, best)
			else:
				_play_attack(card, best)

func _damage_player(amount: int) -> void:
	# V4 §5.6：护盾先于生命承伤；穿透部分才扣血飘字
	var through := amount
	if _player_shield > 0:
		var res: Dictionary = BattleRulesV4.apply_shield(_player_hp, _player_shield, amount)
		_player_hp = int(res["hp"])
		_player_shield = int(res["shield"])
		through = int(res["through"])
		if int(res["absorbed"]) > 0:
			_float_text(_player_sprite.position + Vector2(60, -540),
				"护盾抵挡 %d" % int(res["absorbed"]), _theme.color("fuji_500"), 24)
			_refresh_shield()
	else:
		_player_hp = maxi(0, _player_hp - amount)
	if through > 0:
		_float_text(_player_sprite.position + Vector2(0, -480), "-%d" % through,
			_theme.color("vermilion_500"))
	_hp_version += 1
	_player_sprite.modulate = Color(1.8, 1.2, 1.2)
	var tw: Tween = _player_sprite.create_tween()
	tw.tween_property(_player_sprite, "modulate", Color.WHITE, 0.3)
	queue_redraw()

# ---------- 回合结算 ----------

func _on_end_turn() -> void:
	if _over or _selected_card != null or _busy or _awaiting_target:
		return
	# 结束回合取消整理选牌状态
	if _tidy_mode:
		_tidy_mode = false
		if _hint:
			_hint.text = ""
			_hint.visible = false
		_update_tidy_btn()
	# 本回合鸣钟 → 下回合眩晕（在清空 ringing 前先捕获；意图已在 _new_turn 同步公示）
	_enemy_stunned = _has_slot_state("ringing")
	# 1) 火势蔓延（V4 契约 GDD §6.2：按回合开始的燃烧快照只传播一跳——
	# 旧实现同 pass 内二次蔓延、遍历顺序决定烧几层，本次行为变更落地+记录）
	var fire_states := {}
	var fire_adjacent := {}
	for sid in _slots.keys():
		var slot: Variant = _slots[sid]
		fire_states[sid] = slot.state
		fire_adjacent[sid] = slot.adjacent
	var spread: Dictionary = BattleRulesV4.fire_spread_snapshot(fire_states, fire_adjacent)
	for sid2 in (spread.get("changed", {}) as Dictionary):
		var nb: Variant = _slots[sid2]
		nb.state = "burning"
		_play_vfx("fire", nb.position, 260.0)
		FxBurstScript.burst(self, nb.position, _theme.color("vermilion_500"))
	# 2) 倾覆扑灭：spilled 槽（倾覆卡产生，水钵槽自带 extinguish 标记同源语义）
	# 扑灭相邻火势后自身复原 idle——水克火反制链的一环（鸣钟惊焰是另一环）
	for sid in _slots.keys():
		var slot: Variant = _slots[sid]
		if slot.state == "spilled":
			for adj in slot.adjacent:
				var neighbor: Variant = _slots.get(adj)
				if neighbor != null and neighbor.state == "burning":
					neighbor.state = "idle"
					_float_text(neighbor.position + Vector2(0, -60), "扑灭",
						_theme.color("fuji_500"), 22)
			slot.state = "idle"
	# 2.5) （鸣钟惊焰已移至鸣响瞬间结算：_on_slot_clicked ringing 分支当场清场）
	# 3) 封印判定：阵眼镇符数 + 灵气（GDD §5.5）
	var sealed_n := _count_slot_state("sealed")
	if sealed_n >= int(_seal_rule.get("min_seal_points", 3)):
		var guard := int(_cur_enemy().get("seal_guard", 0))
		if guard > 0 and not _guard_broken:
			# Boss 破阵：棺气护体期间封印被弹开（阵眼保留，破阵后下回合即启）
			_float_text(Vector2(960, 300),
				"棺气护体！符纸被弹开（先击破至 HP≤%d）" % guard,
				_theme.color("vermilion_500"), 26)
			SfxScript.play(self, "explosion", -10.0)
		elif _spirit >= int(_seal_rule.get("min_spirit", 6)):
			_seal_kill()
			return
		else:
			_float_text(Vector2(960, 300), "灵气不足，封印未启（需≥%d）" % int(_seal_rule.get("min_spirit", 6)),
				_theme.color("fuji_500"), 24)
	# 4) 敌方行动：每个存活单位按各自公示意图依次行动（V4 §6.1 逐敌独立；
	# 尖啸为波级行动只结算一次灵气；眩晕/免疫/暴怒/恐惧走统一规则分解）
	var en: Dictionary = _cur_enemy()
	if _enemy_intent == "howl":
		var gain := int(en.get("howl_spirit", 2))
		_spirit = clampi(_spirit + gain, 0, 10)
		_refresh_spirit_hud()
		var front_sp: Node2D = _front_unit().get("sprite", null)
		if front_sp:
			_float_text(front_sp.position + Vector2(0, -560), "尖啸！灵气 +%d" % gain,
				_theme.color("vermilion_500"))
		SfxScript.play(self, "bell", -8.0)
	else:
		for u in _units.duplicate():
			if _over:
				return
			var sp: Node2D = u.get("sprite")
			# V4 §6.1：逐敌独立意图 + §七 来源分解（预览与实际结算同一规则）
			var res: Dictionary = BattleRulesV4.resolve_enemy_attack({
				"attack": int(en.get("attack", 6)),
				"spirit_mult": _spirit_attack_mult(),
				"obsession": _obsession_rage,
				"intent": String(u.get("intent", _enemy_intent)),
				"pounce_mult": float(en.get("pounce_mult", 1.8)),
				"has_burning": _has_slot_state("burning"),
				"fear_attack_mult": float(en.get("fear_attack_mult", 0.5)),
				"stun_skip": bool(en.get("stun_skip", false)),
			})
			for ln in (res["lines"] as Array):
				_float_text(sp.position + Vector2(-140, -520), String(ln["text"]),
					_theme.color(String(ln["color_key"])))
			if int(res["damage"]) <= 0:
				continue
			_damage_player(int(res["damage"]))
			SfxScript.play(self, "hurt")
			if _check_lose():
				return
			if _units.size() > 1:
				await get_tree().create_timer(0.4).timeout # 多单位行动错拍
	# 行动后刷新意图公示：尖啸/燃烧/鸣钟清空改变了下回合的状态覆盖
	_compute_intent()
	# 5) 鸣钟耗尽
	for slot in _slots.values():
		if slot.state == "ringing":
			slot.state = "idle"
	_new_turn()

## 封印击杀：金色结界收拢，妖怪被画进符纸（GDD §5.5 表现；多单位同场全灭）
func _seal_kill() -> void:
	_hp_version += 1
	SfxScript.play(self, "seal")
	var victims := _units.duplicate()
	_units.clear()
	_sync_front()
	for u in victims:
		var sp: Node2D = u.get("sprite")
		_play_vfx("seal", sp.position + Vector2(0, -300), 640.0)
		FxBurstScript.burst(self, sp.position + Vector2(0, -300),
			_theme.color("gold_500"), 60, 320.0)
		var tw: Tween = sp.create_tween().set_parallel()
		tw.tween_property(sp, "modulate:v", 3.0, 0.5)
		tw.tween_property(sp, "scale", sp.scale * 0.6, 0.6)
		tw.chain().tween_property(sp, "modulate:a", 0.0, 0.15)
		tw.chain().tween_callback(sp.queue_free)
	await get_tree().create_timer(0.85).timeout
	_enemy_died("封 印 成 功")

## 敌方意图计算（GDD 参考作品：可预测敌人意图）
## 基础 = 数据 pattern 轮转；状态覆盖：鸣钟眩晕 > 暴走 > 遇火恐惧（猛扑降级为虚弱扑击）
func _compute_intent() -> void:
	var en: Dictionary = _cur_enemy()
	var pattern: Array = en.get("pattern", ["attack"])
	var base := String(pattern[_turn % pattern.size()])
	_enemy_stunned = _has_slot_state("ringing")
	# V4 §6.1：意图逐敌独立记录（当前波内输入一致 → 数值与旧版一致，结构先行；
	# 后续每敌差异化 pattern/抗性直接落在各自字典上，不用再拆波级共享）
	for u in _units:
		u["intent"] = BattleRulesV4.compute_intent(pattern, _turn, _enemy_stunned,
				_is_berserk(), _has_slot_state("burning"))
	_enemy_intent = String(_front_unit().get("intent", base)) if not _units.is_empty() else base
	var txt: String = {"stun": "眩晕…", "berserk": "暴走扑击！"}.get(_enemy_intent,
		String(en.get("intent_text", {}).get(_enemy_intent, _enemy_intent)))
	_intent_label.text = "意图 · %s" % txt
	var danger := _enemy_intent in ["berserk", "pounce", "howl"]
	_intent_label.add_theme_color_override("font_color",
		_theme.color("vermilion_500") if danger else _theme.color("paper_300"))

func _new_turn() -> void:
	_turn += 1
	_ap = _ap_max
	# 器物：聚灵砚类——首场首回合灵墨加成（触发上限在 artifact_value 内判定）
	if _turn == 1:
		var ap_bonus := BattleRulesV4.artifact_value(_artifact, "first_turn_ap",
			int(_artifact_uses.get("first_turn_ap", 0)))
		if ap_bonus > 0:
			_ap += ap_bonus
			_artifact_uses["first_turn_ap"] = int(_artifact_uses.get("first_turn_ap", 0)) + 1
			_float_text(Vector2(960, 880), "%s · 灵墨 +%d" % [_artifact.get("name", "器物"), ap_bonus],
				_theme.color("gold_500"), 24)
	_chain = 0
	_busy = false
	# V4 §5.6：剩余护盾在下次玩家回合开始清空；§5.3 整理每回合一次
	_player_shield = 0
	_tidy_used = false
	_tidy_mode = false
	_refresh_shield()
	_update_tidy_btn()
	# 补牌至手牌上限（首回合发牌已满则跳过；牌堆空自动重洗弃牌堆）
	if _cards.size() < _hand_limit:
		_draw_cards(_hand_limit - _cards.size())
	# 灵气增长（阶段2起额外加成，GDD §八 三阶段）
	var gain := int(_spirit_cfg.get("per_turn", 1))
	if _turn >= int(_spirit_cfg.get("phase2_from_turn", 4)):
		gain += int(_spirit_cfg.get("phase2_bonus", 2))
	_spirit = clampi(_spirit + gain, 0, 10)
	_refresh_spirit_hud()
	# 灵气高压（P2 评估落地）：密度≥阈值时玩家回合开始受灵压侵蚀，给敌方尖啸堆灵气真实威胁
	var pressure_from := int(_spirit_cfg.get("pressure_damage_from", 0))
	if pressure_from > 0 and _spirit >= pressure_from and _player_hp > 0:
		var pressure_dmg := int(_spirit_cfg.get("pressure_damage", 1))
		_damage_player(pressure_dmg)
		_float_text(Vector2(960, 200), "灵压侵蚀 —— 灵气 %d/%d" % [_spirit, pressure_from],
			_theme.color("fuji_500"), 24)
		if _check_lose():
			return
	_refresh_card_states()
	_compute_intent()
	SfxScript.play(self, "turn_end", -12.0)
	var tl: Label = _hud.get_node_or_null("TurnLabel")
	if tl:
		tl.text = "回合 %d" % _turn
	queue_redraw()

func _check_win() -> bool:
	# 波全灭判定统一走 _damage_unit/_kill_unit；此处仅作兜底。
	# V4 §6.2.4：评估走统一规则，玩家 0 血同瞬间不判胜（失败优先）
	if BattleRulesV4.evaluate_battle(_player_hp, _units.size()) == "win" \
			and not _over and _enemy_index < _enemies.size():
		_enemy_died("退 治 成 功")
		return true
	return false

func _check_lose() -> bool:
	if _player_hp <= 0:
		_game_over("逢 魔 沉 沦")
		return true
	return false

func _game_over(text: String) -> void:
	_over = true
	SfxScript.play(self, "seal")
	_hint.text = ""
	_hint.visible = false
	_show_result_panel(text, text != "逢 魔 沉 沦")

# ---------- S6 结算/奖励——「绘卷落款」（GDD §9.4 S6）----------

## 画面定格 → 水墨收拢 → 绘卷落款面板：墨印评价 ★1–3、奖励卡牌飞入、残页与结算小字
func _show_result_panel(text: String, win: bool) -> void:
	await get_tree().create_timer(0.9).timeout
	# 水墨收拢：三层墨色依次渐起，如墨从四周漫进画面
	var dim := ColorRect.new()
	dim.color = Color(_theme.color("ink_900"), 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.z_index = 90
	_hud.add_child(dim)
	var dtw: Tween = dim.create_tween()
	dtw.tween_property(dim, "color:a", 0.78, 0.7)
	# 落款面板：和纸卷自下而上展开
	var panel := Panel.new()
	panel.position = Vector2(520, 1080)
	panel.size = Vector2(880, 560)
	panel.z_index = 91
	panel.add_theme_stylebox_override("panel", _theme.washi_panel())
	_hud.add_child(panel)
	var ptw: Tween = panel.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ptw.tween_property(panel, "position:y", 260.0, 0.45)
	# 落款标题
	var title_l := _label(text, Vector2(240, 30), 40)
	var title_font: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Bold.ttf")
	if title_font:
		title_l.add_theme_font_override("font", title_font)
	title_l.add_theme_color_override("font_color",
		_theme.color("vermilion_500") if win else _theme.color("ink_700"))
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.size = Vector2(400, 56)
	panel.add_child(title_l)
	# 墨印评价 ★1–3：生命≥50% 与速战各加一印
	var rating := 1
	if win:
		if _player_hp >= _player_hp_max * 0.5:
			rating += 1
		if _turn <= int(_cfg.get("rating_turn_target", 6)):
			rating += 1
	else:
		rating = 0
	for i in range(3):
		var earned := i < rating
		var seal_l := _label("★", Vector2(340 + i * 100, 108), 56)
		seal_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seal_l.size = Vector2(60, 60)
		seal_l.add_theme_color_override("font_color",
			_theme.color("vermilion_500") if earned else Color(_theme.color("paper_300"), 0.5))
		seal_l.scale = Vector2.ZERO
		panel.add_child(seal_l)
		var stw: Tween = seal_l.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		stw.tween_property(seal_l, "scale", Vector2.ONE, 0.3).set_delay(0.5 + i * 0.18)
	if win:
		# 奖励卡牌：从画面右侧飞入牌位
		var defs: Array = _cfg.get("cards", [])
		if not defs.is_empty():
			var reward: Dictionary = defs[_turn % defs.size()]
			var card_art := CoverArt.new()
			card_art.tex = _load_texture(reward.get("art", ""))
			card_art.position = Vector2(1900, 250)
			card_art.size = Vector2(140, 196)
			panel.add_child(card_art)
			var ctw: Tween = card_art.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			ctw.tween_property(card_art, "position:x", 160.0, 0.5).set_delay(1.0)
			var card_name := _label("获得 · %s" % reward.get("name", "?"), Vector2(130, 456), 20)
			card_name.size = Vector2(220, 28)
			card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			card_name.add_theme_color_override("font_color", _theme.color("ink_700"))
			panel.add_child(card_name)
		var page_l := _label("绘卷残页 ×1 —— 妖怪手帖新解一页", Vector2(420, 250), 20)
		page_l.add_theme_color_override("font_color", _theme.color("ink_700"))
		panel.add_child(page_l)
	var stats := _label("灵气 %d/10 · 用时 %d 回合" % [_spirit, _turn], Vector2(420, 300), 18)
	stats.add_theme_color_override("font_color", _theme.color("paper_300"))
	panel.add_child(stats)
	if not win:
		var lose_l := _label("绘卷被墨迹侵染……重整旗鼓再来。", Vector2(420, 250), 20)
		lose_l.add_theme_color_override("font_color", _theme.color("ink_700"))
		panel.add_child(lose_l)
	# 行动按钮：再战 / 返回探索（与 R / ESC 快捷键等价）
	var retry_btn := _detail_button("再战一局", Vector2(200, 480), true)
	retry_btn.pressed.connect(func() -> void:
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().change_scene_to_file("res://scenes/v3/battle.tscn")))
	panel.add_child(retry_btn)
	var back_btn := _detail_button("返回探索", Vector2(470, 480), false)
	back_btn.pressed.connect(func() -> void:
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().change_scene_to_file(STAGE_SCENE)))
	panel.add_child(back_btn)

# ---------- HUD 绘制 ----------

func _draw() -> void:
	if _theme == null:
		return
	var ink: Color = _theme.color("ink_900")
	var verm: Color = _theme.color("vermilion_500")
	var green: Color = _theme.color("successful")
	var gold: Color = _theme.color("gold_500")
	var fuji: Color = _theme.color("fuji_500")
	var paper: Color = _theme.color("paper_100")

	_bar(Vector2(150, 946), Vector2(420, 16), _player_hp, _player_hp_max, green, ink)
	# V4 §5.6 护盾条：血条上方细蓝条（回合开始清空，见 _new_turn）
	if _player_shield > 0:
		_bar(Vector2(150, 928), Vector2(420, 8), _player_shield, _player_hp_max, fuji, ink)
	# 敌方血条由 HUD 层 EnemyBar 绘制（盖过立绘），此处不再绘制
	for i in range(_ap_max):
		var x := 1560 + i * 28
		var filled := i < _ap
		draw_circle(Vector2(x + 10, 970), 9, gold if filled else Color(ink))
		draw_arc(Vector2(x + 10, 970), 9, 0, TAU, 24, gold, 1.5)
	# 意图气泡：攻/晕/恐
	var bp := Vector2(1560, 120)
	var intent := "攻"
	var ic: Color = verm
	if _enemy_stunned:
		intent = "晕"
		ic = fuji
	elif _has_slot_state("burning") and not _is_berserk():
		intent = "恐"
		ic = fuji
	elif _is_berserk():
		intent = "狂"
	draw_circle(bp, 30, ic)
	draw_arc(bp, 30, 0, TAU, 32, paper, 2.0)
	draw_string(_font(24), bp + Vector2(0, 8), intent,
		HORIZONTAL_ALIGNMENT_CENTER, -1, 24, paper)

func _bar(pos: Vector2, size: Vector2, cur: int, maxv: int, fill: Color, ink: Color) -> void:
	draw_rect(Rect2(pos, size), Color(ink, 0.75))
	var w := size.x * float(cur) / float(maxi(maxv, 1))
	draw_rect(Rect2(pos, Vector2(w, size.y)), fill)

func _label(text: String, pos: Vector2, sz: int) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", _font(sz))
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", _theme.color("paper_100"))
	return l

func _float_text(world_pos: Vector2, text: String, c: Color, sz := 30) -> void:
	var l := _label(text, Vector2.ZERO, sz)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", _theme.color("ink_900"))
	l.add_theme_constant_override("outline_size", 6)
	_hud.add_child(l)
	l.position = world_pos
	var tw: Tween = l.create_tween().set_parallel()
	tw.tween_property(l, "position:y", world_pos.y - 60, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.25)
	tw.chain().tween_callback(l.queue_free)

func _font(sz: int) -> Font:
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf")
	return f if f else ThemeDB.fallback_font

func _load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	return PngLoader.load_texture(path) # FileAccess 虚拟文件系统，导出 pck 内可用

# ---------- 自动演出：封印连招（验证用）----------

func _run_auto_demo() -> void:
	# 循环打出封印连招直至战斗结束（多波次验证：每波约 8s 推进）
	# 所有 _auto_play_* 调用必须 await——不 await 的协程会并发穿插，
	# 在出牌协程 _busy 未清时就发起下一次点击，导致点击被拦截失步。
	# Boss 破阵阶段（seal_guard 未破）：鸣钟眩晕 + 双斩 + 引燃挂恐惧减伤
	while not _over:
		await _demo_idle()
		if _over:
			break
		var guarded: bool = int(_cur_enemy().get("seal_guard", 0)) > 0 and not _guard_broken
		if guarded:
			# 破阵回合：AP 1+2+2+1=6
			await _auto_play_slot("bell", "slot_bell")
			await _demo_idle()
			if _over:
				break
			await _auto_play_attack("slash")
			await _demo_idle()
			if _over:
				break
			if _guard_broken:
				continue # 棺盖已碎：回到循环头改打封印分支（原 break 会终止整个演出）
			await _auto_play_attack("slash")
			await _demo_idle()
			if _over:
				break
			if _guard_broken:
				continue
			var shoji_g: Variant = _slots.get("slot_shoji")
			if shoji_g != null and shoji_g.state == "idle":
				await _auto_play_slot("ignite", "slot_shoji")
			await _demo_idle()
			if _over:
				break
			_on_end_turn() # 鸣钟眩晕：本回合敌方跳过
			await _demo_idle()
			await get_tree().create_timer(0.6).timeout
			continue
		await _auto_play_slot("bell", "slot_bell") # 先鸣钟：眩晕敌方 + 惊焰清场
		await _demo_idle()
		if _over:
			break
		await _auto_play_slot("seal", "slot_rope")
		await _demo_idle()
		if _over:
			break
		await _auto_play_slot("seal2", "slot_eaves")
		await _demo_idle()
		if _over:
			break
		var shoji: Variant = _slots.get("slot_shoji")
		if shoji != null and shoji.state == "idle":
			await _auto_play_slot("ignite", "slot_shoji")
		await _demo_idle()
		if _over:
			break
		_on_end_turn() # 敌遇火恐惧；灵气 5<6 封印未启
		await _demo_idle()
		if _over:
			break
		_on_end_turn() # 灵气≥6 + 阵眼≥2 → 封印击杀
		await _demo_idle()
		await get_tree().create_timer(0.6).timeout

## 自动演出：直接打出攻击牌（破阵用）
func _auto_play_attack(card_id: String) -> void:
	var card: Variant = _ensure_card_in_hand(card_id)
	if card == null:
		return
	await _demo_idle() # 确保出牌协程的 _busy 已清
	_on_card_clicked(card) # attack 类型立即结算
	await get_tree().create_timer(0.5).timeout

## 自动演出节拍：等战斗忙标记解除（最长 6s 防死锁）
func _demo_idle() -> void:
	var waited := 0.0
	while not _over and _busy and waited < 6.0:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	await get_tree().create_timer(0.35).timeout

func _auto_play_slot(card_id: String, slot_id: String) -> void:
	var card: Variant = _ensure_card_in_hand(card_id)
	if card == null:
		return
	await _demo_idle() # 确保上一个出牌协程的 _busy 已清，点击不被拦截
	_on_card_clicked(card)
	await get_tree().create_timer(0.35).timeout
	_on_slot_clicked(_slots.get(slot_id))
	await get_tree().create_timer(0.45).timeout

## 演出兜底：牌组洗牌后目标牌可能不在开局手牌，从抽牌堆/弃牌堆捞上来
func _ensure_card_in_hand(id: String) -> Variant:
	var card: Variant = _find_card(id)
	if card != null:
		return card
	var def: Dictionary = {}
	for i in _deck.size():
		if (_deck[i] as Dictionary).get("id", "") == id:
			def = _deck[i]
			_deck.remove_at(i)
			break
	if def.is_empty():
		for i in _discard.size():
			if (_discard[i] as Dictionary).get("id", "") == id:
				def = _discard[i]
				_discard.remove_at(i)
				break
	if def.is_empty():
		return null
	_spawn_hand_card(def)
	_refresh_pile_counts()
	return _find_card(id)

func _find_card(id: String) -> Variant:
	for c in _cards:
		if c.data.get("id", "") == id:
			return c
	return null

func _dump_states() -> String:
	var parts := PackedStringArray()
	for sid in _slots:
		parts.append("%s=%s" % [sid, _slots[sid].state])
	return "spirit=%d sealed=%d | " % [_spirit, _count_slot_state("sealed")] + ", ".join(parts)
