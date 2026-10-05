# 结案/续监只显示已经成功提交的正式状态，无旧卡牌奖励。
extends Node3D
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Catalog = preload("res://scripts/campaign/chapter_catalog.gd")
const Geometry = preload("res://scripts/campaign/chapter_geometry.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
var _root: Control
var _card: Control
var _shade: ColorRect
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
	_root = Control.new()
	layer.add_child(_root)
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.06, 0.065, 0.72)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shade)
	_card = Control.new()
	_card.size = Vector2(1120, 712)
	_root.add_child(_card)
	Art.panel(_card, Rect2(0, 0, 1120, 712)).name = "EndingPanel"
	var complete: bool = str(state.get("story_phase", "")) == "complete" and bool(state.get("chapter_complete", false))
	var sendoff: bool = str(state.get("resolution", "")) == "sendoff"
	var headline: String = "第一章 · 五夜 · 结案" if sendoff else "第一章 · 五夜 · 续监"
	if not complete: headline = "正式完成记录尚未提交"
	var title: Label = Kit.label(_card, headline, Rect2(68, 56, 984, 96), 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var stamp_panel := Art.panel(_card, Rect2(124, 202, 872, 126), true)
	stamp_panel.name = "EndingStampPanel"
	stamp_panel.visible = complete
	var stamp: Label = Kit.label(_card, "送行 · 安魂" if sendoff else "镇守 · 本案未结", Rect2(156, 232, 808, 66), 42)
	stamp.visible = complete
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.add_theme_color_override("font_color", Color("e2c99b"))
	var body: String = "逢魔神社夜巡，五夜。\n送行者一，安魂。案件状态：已结案。" if sendoff else "五夜夜巡流程已完成。\n异象暂息，案件状态：续监。"
	if not complete: body = "请从标题继续正式主线，完成结局演出与存档。"
	var status: Label = Kit.label(_card, body, Rect2(100, 380, 920, 140), 30)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("e3d8bf"))
	var back := Art.button(_card, "返回标题", Rect2(270, 572, 580, 84), _return_title, true)
	back.focus_mode = Control.FOCUS_ALL
	get_viewport().size_changed.connect(_layout)
	_layout()
	back.grab_focus()
func _layout() -> void:
	if _root == null: return
	_root.size = get_viewport().get_visible_rect().size
	_shade.size = _root.size
	_card.position = (_root.size - _card.size) * 0.5
func _return_title() -> void:
	if _leaving: return
	_leaving = true
	if Session.current != null: Session.current.close()
	var error: Error = get_tree().change_scene_to_file("res://scenes/campaign/title.tscn")
	if error != OK: _leaving = false
