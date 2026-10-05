# 结案/续监只显示已经成功提交的正式状态，无旧卡牌奖励。
extends Node3D
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Geometry = preload("res://scripts/campaign/chapter_geometry.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
var _leaving: bool = false
func _ready() -> void:
	var state: Dictionary = Session.current.campaign.safe_snapshot() if Session.current != null else {}
	add_child(Geometry.build(5, Catalog.night(5)))
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	camera.position = Vector3(0, 5, 11)
	add_child(camera)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.make_current()
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var root: Control = Control.new()
	root.size = Vector2(1920, 1080)
	layer.add_child(root)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.025, 0.06, 0.065, 0.72)
	shade.size = root.size
	root.add_child(shade)
	Kit.panel(root, Rect2(410, 208, 1100, 668))
	var complete: bool = str(state.get("story_phase", "")) == "complete" and bool(state.get("chapter_complete", false))
	var sendoff: bool = str(state.get("resolution", "")) == "sendoff"
	var headline: String = "第一章 · 五夜 · 结案" if sendoff else "第一章 · 五夜 · 续监"
	if not complete: headline = "正式完成记录尚未提交"
	var title: Label = Kit.label(root, headline, Rect2(460, 264, 1000, 96), 56)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var stamp: Label = Kit.label(root, "送行 · 安魂" if sendoff else "镇守 · 本案未结", Rect2(460, 410, 1000, 90), 46)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.add_theme_color_override("font_color", Kit.color("ui_muted"))
	var body: String = "逢魔神社夜巡，五夜。\n送行者一，安魂。案件状态：已结案。" if sendoff else "五夜夜巡流程已完成。\n异象暂息，案件状态：续监。"
	if not complete: body = "请从标题继续正式主线，完成结局演出与存档。"
	var status: Label = Kit.label(root, body, Rect2(490, 548, 940, 140), 30)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Kit.muted(status)
	Kit.button(root, "返回标题", Rect2(670, 738, 580, 80), _return_title, true).focus_mode = Control.FOCUS_NONE
func _return_title() -> void:
	if _leaving: return
	_leaving = true
	if Session.current != null: Session.current.close()
	var error: Error = get_tree().change_scene_to_file("res://scenes/campaign/title.tscn")
	if error != OK: _leaving = false
