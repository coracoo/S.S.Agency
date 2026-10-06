# 终章全文由探索场次顺序播放；此页仅展示已提交的最终结案，不代替或跳过后日谈。
extends Node3D
const Session = preload("res://scripts/campaign/chapter_session.gd")
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Region = preload("res://scripts/campaign/saga_world.gd")
const Art = preload("res://scripts/campaign/presentation/night_menu_art.gd")
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
var _leaving := false
var _root: Control
var _card: Control
var _shade: ColorRect
func _ready() -> void:
	var state: Dictionary=Session.current.campaign.safe_snapshot() if Session.current != null else {}
	var saga: Dictionary=state.get("saga",{})
	var complete: bool=state.get("story_phase","")=="complete" and state.get("chapter_complete",false) and not str(saga.get("ending","")).is_empty()
	add_child(Region.build(7))
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=12; camera.position=Vector3(12,8,16); add_child(camera); camera.look_at(Vector3(12,1,0)); camera.make_current()
	var layer:=CanvasLayer.new(); add_child(layer)
	_root=Control.new(); layer.add_child(_root)
	_shade=ColorRect.new(); _shade.color=Color(.025,.04,.06,.68); _root.add_child(_shade)
	_card=Control.new(); _card.size=Vector2(1160,760); _root.add_child(_card)
	Art.panel(_card,Rect2(Vector2.ZERO,_card.size))
	var ending:=str(saga.get("ending",""))
	var titles: Dictionary={"dawn":"天明 · 各自前行","vigil":"守夜 · 有限续守","shatter":"断镜 · 离城","eternal":"永夜 · 未获同意"}
	var title:=Kit.label(_card,"七章终 · "+str(titles.get(ending,ending)) if complete else "旅程尚未结案",Rect2(72,64,1016,90),46)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var body: String="最后的对白与后日谈已写入记录。\n走过的路、做过的选择，以及仍需承担的后果，都保留在正式存档里。" if complete else "请继续正式主线，完成最后的后日谈与保存。"
	var text:=Kit.label(_card,body,Rect2(108,250,944,170),28); text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	if complete:
		Kit.label(_card,"逢魔退治帖 · 完",Rect2(108,460,944,65),34).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	else: Art.button(_card,"继续旅程",Rect2(306,480,548,76),_continue)
	var back:=Art.button(_card,"返回标题",Rect2(306,590,548,84),_return_title,true)
	get_viewport().size_changed.connect(_layout); _layout(); back.grab_focus()
func _layout() -> void:
	_root.size=get_viewport().get_visible_rect().size; _shade.size=_root.size
	var factor:=minf(1.0,minf(_root.size.x/_card.size.x,_root.size.y/_card.size.y)); _card.scale=Vector2.ONE*factor; _card.position=(_root.size-_card.size*factor)/2
func _continue() -> void:
	if _leaving: return
	_leaving=true
	if get_tree().change_scene_to_file(Saga.SCENE_PATH)!=OK: _leaving=false
func _return_title() -> void:
	if _leaving: return
	_leaving=true
	if Session.current != null: Session.current.close()
	if get_tree().change_scene_to_file("res://scenes/campaign/title.tscn")!=OK: _leaving=false
