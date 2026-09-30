extends Control
## 真相结算场景（GDD §6 样章结案：揭晓真相 → 处理方式选择 → 余波 → 成长奖励）。
## 数据：data/cases/<case_id>.json（stage_config.xlsx case 表导出）；
## 对话渲染复用 DialogueOverlay（含分支选择）；结束后授予奖励（幂等）+ 结案朱印。

const UIThemeScript = preload("res://scripts/ui/theme.gd")
const SfxScript = preload("res://scripts/ui/sfx.gd")
const InkTransitionScript = preload("res://scripts/ui/ink_transition.gd")
const DialogueOverlayScript = preload("res://scripts/ui/dialogue_overlay.gd")

const TITLE_SCENE := "res://scenes/v3/title.tscn"

var _theme = null
var _cfg: Dictionary = {}

func _ready() -> void:
	_theme = UIThemeScript.load_theme()
	_load_case()
	if _cfg.is_empty():
		# 无案件配置（直连调试）：直接回标题，不卡死
		get_tree().change_scene_to_file(TITLE_SCENE)
		return
	WashiOverlay.add_to(self)
	_play()

func _load_case() -> void:
	var path := "res://data/cases/%s.json" % CaseFlowV4.case_id
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("[TruthScene] 缺少 %s" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_cfg = parsed

func _play() -> void:
	var overlay := DialogueOverlayScript.new(_theme)
	add_child(overlay)
	var nodes: Dictionary = _cfg.get("nodes", {})
	var start: String = String(nodes.keys()[0]) if not nodes.is_empty() else ""
	await overlay.play(nodes, start)
	overlay.queue_free()
	_grant_and_stamp()

## 授予奖励（幂等）+ 结案朱印 + 返回标题
func _grant_and_stamp() -> void:
	var case_id := String(_cfg.get("id", CaseFlowV4.case_id))
	var granted: Dictionary = ProgressSaveV4.grant(case_id, _cfg.get("rewards", {}))
	SfxScript.play(self, "seal")
	var panel := PanelContainer.new()
	panel.position = Vector2(560, 300)
	panel.size = Vector2(800, 420)
	panel.add_theme_stylebox_override("panel", _theme.washi_panel())
	add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(730, 360)
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var title := _label(String(_cfg.get("stamp", "结 案")), 36, true)
	v.add_child(title)
	var lines: Array = []
	for cid in (granted["cards"] as Array):
		lines.append("新卡入藏：%s" % _card_name(cid))
	for aid in (granted["artifacts"] as Array):
		lines.append("器物入手：%s" % _artifact_name(aid))
	if lines.is_empty():
		lines.append("奖励已在此前领取过（成长记录保留）")
	var body := _label("\n".join(lines), 22, false)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(body)
	var back := Button.new()
	back.text = "返回标题"
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func() -> void:
		InkTransitionScript.transition(get_tree(), func() -> void:
			get_tree().change_scene_to_file(TITLE_SCENE)))
	v.add_child(back)

func _card_name(id: String) -> String:
	for def in (CardLibraryV4.load_library().values() as Array):
		if String((def as Dictionary).get("id", "")) == id:
			return String((def as Dictionary).get("name", id))
	return id

func _artifact_name(id: String) -> String:
	var f := FileAccess.open("res://data/artifacts.json", FileAccess.READ)
	if f == null:
		return id
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		for a in (parsed as Array):
			if String((a as Dictionary).get("id", "")) == id:
				return String((a as Dictionary).get("name", id))
	return id

func _label(text: String, sz: int, bold: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	var f: Font = load("res://assets/fonts/Alibaba-PuHuiTi-%s.ttf" % ("Bold" if bold else "Regular"))
	if f:
		l.add_theme_font_override("font", f)
	l.add_theme_color_override("font_color", _theme.color("ink_900"))
	return l
