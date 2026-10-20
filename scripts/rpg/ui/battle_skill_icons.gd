extends Control
## 外部 v5 技能墨绘：只绘制图形，不修改技能、选择、消耗或时序。
## 40 单位原稿缩放到现有 34—40px 图标槽；负形保持透明，纸纹由父卡片提供。

const DESIGN_SIZE := 40.0
const INK := Color("252B29")
const SEAL := Color("A64234")
const DISABLED_INK := Color("74776F")
const DISABLED_SEAL := Color("8A8074")

const SKILL_INFO := {
	"heavy_slash": {"name":"重斩", "semantic":"单敌重击；宽刃重斩", "motif":"single_broad_blade"},
	"armor_break": {"name":"破甲斩", "semantic":"单敌伤害并降低物防；裂开的甲片", "motif":"split_armor"},
	"sweep": {"name":"横扫", "semantic":"全体敌人物理攻击；横向宽弧", "motif":"wide_sweeping_arc"},
	"battle_spirit": {"name":"战意", "semantic":"自身输出提升；向上聚起的战意", "motif":"rising_spirit"},
	"mark": {"name":"标记", "semantic":"单敌猎物标记；瞄准环与朱砂靶心", "motif":"prey_reticle"},
	"hunt": {"name":"猎杀", "semantic":"单敌射击，猎物标记强化并被消耗；弓与贯靶箭", "motif":"bow_and_target_arrow"},
	"ambush": {"name":"奇袭", "semantic":"突袭尚未行动的单敌；阴影中先落的短刃", "motif":"descending_ambush_blade"},
	"smoke_screen": {"name":"烟幕", "semantic":"自身护盾；环护小盾的烟团", "motif":"smoke_shelter"},
	"cover": {"name":"掩护", "semantic":"保护另一队友并承受一次直击；护住同伴的斜盾", "motif":"sheltering_shield_and_ally"},
	"shield_bash": {"name":"盾击", "semantic":"单敌伤害并打断；前倾盾与撞击芒", "motif":"shield_impact"},
	"iron_wall": {"name":"铁壁", "semantic":"自身护盾；直立厚壁", "motif":"three_plate_wall"},
	"taunt": {"name":"挑衅", "semantic":"单敌攻击转向施术者；定向喊声与回引箭", "motif":"directed_taunt_call"}
}

# 正式专属卡只是同一招式的变式；图形沿用其真实原式，不按名字猜测。
const SKILL_ALIASES := {
	"rinne_quick_slash":"heavy_slash", "rinne_deep_break":"armor_break",
	"mint_long_mark":"mark", "mint_quick_hunt":"hunt",
	"guard_charged_bash":"shield_bash", "guard_brief_cover":"cover"
}

var _raw_id := ""
var _canonical_id := ""
var _selection_key := ""
var _disabled := false
var _supported := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func configure(entry: Dictionary, key: String, disabled: bool) -> void:
	_selection_key = key
	_raw_id = str(entry.get("id",entry.get("ability_id","")))
	if key.begins_with("skill:"):
		_raw_id = key.trim_prefix("skill:")
	_canonical_id = str(SKILL_ALIASES.get(_raw_id,_raw_id))
	_disabled = disabled
	_supported = SKILL_INFO.has(_canonical_id)
	set_meta("trial_icon_id",_raw_id)
	set_meta("trial_icon_canonical_id",_canonical_id)
	set_meta("trial_icon_supported",_supported)
	queue_redraw()

func supported_skill_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for skill_id in SKILL_INFO:
		result.append(str(skill_id))
	for alias_id in SKILL_ALIASES:
		result.append(str(alias_id))
	result.sort()
	return result

func supports_skill_id(skill_id: String) -> bool:
	return SKILL_INFO.has(str(SKILL_ALIASES.get(skill_id,skill_id)))

func diagnostic_snapshot() -> Dictionary:
	var info: Dictionary = SKILL_INFO.get(_canonical_id,{})
	return {
		"id":_raw_id, "canonical_id":_canonical_id, "selection_key":_selection_key,
		"supported_id":_supported, "supported":_supported, "disabled":_disabled,
		"name":str(info.get("name","")),
		"semantic":str(info.get("semantic","未登记的技能图标")),
		"motif":str(info.get("motif","unsupported")),
		"renderer":"code_native_vector_ink", "bitmap_assets":false,
		"design_size":Vector2(DESIGN_SIZE,DESIGN_SIZE),
		"design_ink_bounds":Rect2(2,2,36,36),
		"slot_size":size, "supported_ids":supported_skill_ids()
	}

func _draw() -> void:
	if not _supported:
		return
	var edge := minf(size.x,size.y)
	if edge <= 0.0:
		return
	draw_set_transform((size-Vector2.ONE*edge)*0.5,0.0,Vector2.ONE*(edge/DESIGN_SIZE))
	match _canonical_id:
		"heavy_slash": _draw_heavy_slash()
		"armor_break": _draw_armor_break()
		"sweep": _draw_sweep()
		"battle_spirit": _draw_battle_spirit()
		"mark": _draw_mark()
		"hunt": _draw_hunt()
		"ambush": _draw_ambush()
		"smoke_screen": _draw_smoke_screen()
		"cover": _draw_cover()
		"shield_bash": _draw_shield_bash()
		"iron_wall": _draw_iron_wall()
		"taunt": _draw_taunt()
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _ink() -> Color:
	return DISABLED_INK if _disabled else INK

func _seal() -> Color:
	return DISABLED_SEAL if _disabled else SEAL

func _polygon(coordinates: Array, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(0,coordinates.size(),2):
		points.append(Vector2(float(coordinates[index]),float(coordinates[index+1])))
	draw_colored_polygon(points,color)

func _stroke(coordinates: Array, width: float, color: Color, closed: bool = false) -> void:
	var points := PackedVector2Array()
	for index in range(0,coordinates.size(),2):
		points.append(Vector2(float(coordinates[index]),float(coordinates[index+1])))
	if closed and not points.is_empty():
		points.append(points[0])
	draw_polyline(points,color,width,true)

func _arc(center: Vector2, radius: float, start_degrees: float, end_degrees: float, width: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 21:
		var angle := deg_to_rad(lerpf(start_degrees,end_degrees,float(index)/20.0))
		points.append(center+Vector2(cos(angle),sin(angle))*radius)
	draw_polyline(points,color,width,true)

func _draw_heavy_slash() -> void:
	# 粗重单刃与斜向刀柄；比横扫更窄、更纵向。
	_polygon([31,3, 30,13, 14,29, 10,25, 24,8],_ink())
	_polygon([8,22, 18,31, 16,33, 6,25],_ink())
	_polygon([10,29, 13,32, 7,38, 3,36],_ink())
	_polygon([33,9, 36,13, 23,28, 26,21],_seal())
	_stroke([18,29, 21,27],1.5,_ink())

func _draw_armor_break() -> void:
	# 两块断甲之间留透明裂缝；不用“完整盾”误指护盾。
	_polygon([8,7, 18,5, 21,12, 16,17, 20,23, 14,34, 7,27, 5,15],_ink())
	_polygon([24,5, 33,8, 35,17, 31,29, 20,36, 23,24, 20,18, 26,12],_ink())
	_stroke([20,7, 23,12, 18,18, 22,23, 18,31],2.0,_seal())
	_stroke([8,3, 6,5],1.8,_ink())
	_stroke([34,30, 37,32],1.8,_ink())

func _draw_sweep() -> void:
	# 横贯的粗弧表达全体范围；尾端收成刀锋。
	_polygon([3,18, 8,12, 17,9, 28,10, 36,15, 38,20, 31,16, 22,15, 13,17, 7,21],_ink())
	_polygon([6,23, 14,25, 26,24, 35,20, 30,28, 21,31, 11,29],_ink())
	_stroke([8,33, 16,35, 26,33],2.0,_seal())
	_polygon([32,7, 35,4, 36,9],_ink())
	_polygon([3,26, 5,30, 2,29],_ink())

func _draw_battle_spirit() -> void:
	# 只表现聚势上扬，不画命中目标；这是自身增伤。
	_polygon([20,2, 25,12, 24,18, 30,13, 34,24, 32,31, 26,36, 13,36, 6,30, 6,24, 12,14, 13,23, 17,18],_ink())
	_polygon([20,11, 24,23, 22,33, 17,33, 14,28, 18,23],_seal())
	_polygon([3,13, 5,8, 7,16],_seal())
	_polygon([32,7, 35,11, 31,14],_ink())

func _draw_mark() -> void:
	# 三段猎物瞄准环与靶心；与猎杀的弓箭区分。
	_arc(Vector2(20,20),11.0,-75.0,8.0,3.0,_ink())
	_arc(Vector2(20,20),11.0,35.0,165.0,3.0,_ink())
	_arc(Vector2(20,20),11.0,192.0,260.0,3.0,_ink())
	_stroke([20,3, 20,12],2.7,_ink())
	_stroke([28,20, 37,20],2.7,_ink())
	_stroke([20,28, 20,37],2.7,_ink())
	_stroke([3,20, 12,20],2.7,_ink())
	_polygon([20,14, 25,20, 20,26, 15,20],_seal())

func _draw_hunt() -> void:
	# 弓身与横贯箭；末端朱砂短划表示命中已标记猎物。
	_stroke([8,5, 14,11, 17,20, 14,29, 8,35],3.2,_ink())
	_stroke([8,5, 9,20, 8,35],1.7,_ink())
	_polygon([4,18, 27,18, 27,13, 37,20, 27,26, 27,22, 4,22, 8,20],_ink())
	_polygon([3,14, 9,18, 9,20, 3,18],_ink())
	_stroke([33,8, 35,12],2.0,_seal())
	_stroke([34,29, 36,25],2.0,_seal())

func _draw_ambush() -> void:
	# 上方短刃抢先落下；左右阴影收拢，不与重斩共用斜剑轮廓。
	_polygon([17,3, 23,3, 22,10, 18,10],_ink())
	_polygon([12,10, 28,10, 28,13, 12,14],_ink())
	_polygon([16,15, 24,15, 23,24, 20,31, 16,23],_ink())
	_polygon([3,31, 8,21, 11,19, 10,28, 16,34, 25,34, 31,28, 30,19, 34,23, 37,32, 30,37, 10,37],_ink())
	_polygon([28,3, 31,4, 28,9, 26,8],_seal())
	_stroke([7,13, 10,15],1.8,_ink())

func _draw_smoke_screen() -> void:
	# 烟团包住小盾：真实效果是自身护盾，不是群体遮蔽或闪避。
	_stroke([10,29, 5,26, 3,21, 5,16, 10,15, 10,10, 15,6, 20,7, 23,11, 28,8, 33,10, 34,15, 37,19, 36,24, 32,27],3.0,_ink())
	_stroke([5,31, 9,34, 13,33],2.2,_ink())
	_stroke([28,33, 32,33, 35,30],2.2,_ink())
	_stroke([14,18, 20,16, 27,19, 26,29, 20,35, 14,29],2.6,_ink(),true)
	_stroke([17,24, 20,27, 24,21],2.0,_seal())

func _draw_cover() -> void:
	# 左侧斜盾遮住右下同伴；这是替另一人承伤。
	_polygon([6,5, 20,3, 27,11, 22,17, 20,12, 11,10, 10,22, 17,29, 14,34, 5,25, 3,13],_ink())
	_stroke([11,14, 10,22, 15,27],1.8,_seal())
	draw_circle(Vector2(27,23),4.0,_ink(),true,-1,true)
	_polygon([21,29, 28,28, 33,31, 36,37, 19,37],_ink())
	_stroke([31,7, 35,10],2.0,_seal())

func _draw_shield_bash() -> void:
	# 斜前冲的实盾与右侧撞击芒，区别于静止铁壁。
	_polygon([7,9, 20,5, 28,10, 26,26, 18,35, 8,28, 4,17],_ink())
	_stroke([10,13, 19,10, 22,13, 21,24, 18,29],2.0,_seal())
	_polygon([29,14, 36,10, 34,17, 38,19, 31,23, 33,30, 27,26],_ink())
	_stroke([3,29, 8,33],2.0,_ink())

func _draw_iron_wall() -> void:
	# 三块厚实竖板与低基座，形成稳定、正立的自身屏障。
	_polygon([4,10, 12,8, 12,32, 4,31],_ink())
	_polygon([15,4, 25,4, 25,33, 15,33],_ink())
	_polygon([28,8, 36,10, 36,31, 28,32],_ink())
	_polygon([3,34, 19,35, 37,33, 37,37, 3,37],_ink())
	_stroke([18,11, 22,11],2.0,_seal())
	_stroke([18,17, 22,17],2.0,_seal())

func _draw_taunt() -> void:
	# 朝向单敌的喊声；回引钩指向自身，表达迫使目标转火。
	_polygon([6,17, 12,17, 23,8, 23,29, 12,23, 6,23],_ink())
	_polygon([11,25, 16,27, 17,35, 12,36],_ink())
	_stroke([28,12, 32,9],2.5,_seal())
	_stroke([28,19, 36,18],2.5,_seal())
	_stroke([28,25, 33,28],2.5,_seal())
	_stroke([35,31, 31,35, 24,35],2.5,_ink())
	_polygon([26,30, 20,35, 26,38],_ink())
