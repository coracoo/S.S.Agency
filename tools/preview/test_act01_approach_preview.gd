# 独立预览验收：节点、按键处理器/按钮信号回归与正式入口隔离。
# Godot --headless --path . --script res://tools/preview/test_act01_approach_preview.gd
extends SceneTree

const PREVIEW := "res://scenes/preview/act01_approach_3d.tscn"
var _failed := false

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: " + label)
	else:
		print("PASS: " + label)

func _key(preview: Node, code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.echo = echo
	preview._unhandled_key_input(event)

func _run() -> void:
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/v3/title.tscn", "默认入口仍是原版标题")
	_check(ResourceLoader.exists(PREVIEW), "独立参道预览存在")
	if not ResourceLoader.exists(PREVIEW):
		quit(1)
		return
	var packed := load(PREVIEW) as PackedScene
	_check(packed != null, "预览可以导入为 PackedScene")
	if packed == null:
		quit(1)
		return
	var preview := packed.instantiate()
	root.add_child(preview)
	await process_frame
	var hero := preview.get_node("Cameras/Hero") as Camera3D
	var detail := preview.get_node("Cameras/Inspection") as Camera3D
	var character := preview.get_node("CharacterReference") as Sprite3D
	var hud := preview.get_node("PreviewHUD") as CanvasLayer
	_check(root.get_camera_3d() == hero, "默认启用固定画卷镜头")
	_check(hero.keep_aspect == Camera3D.KEEP_WIDTH and detail.keep_aspect == Camera3D.KEEP_WIDTH, "窄窗口保持路线横向视野")
	_check(not character.visible, "默认隐藏二维人物比例参照")
	_check(preview.get_node("WorldEnvironment").environment != null, "预览具有真实三维环境光")
	_check(preview.get_node("Model").get_child_count() > 0, "GLB 实体已实例化")
	_key(preview, KEY_2)
	_check(root.get_camera_3d() == detail, "2 切换检查镜头")
	_key(preview, KEY_1)
	_check(root.get_camera_3d() == hero, "1 返回固定镜头")
	preview.get_node("PreviewHUD/Margin/Stack/Controls/Inspection").pressed.emit()
	_check(root.get_camera_3d() == detail, "检查按钮切换镜头")
	preview.get_node("PreviewHUD/Margin/Stack/Controls/Hero").pressed.emit()
	_check(root.get_camera_3d() == hero, "固定按钮切换镜头")
	_key(preview, KEY_C)
	_check(character.visible, "C 显示人物参照")
	_key(preview, KEY_C, true)
	_check(character.visible, "忽略按键自动重复")
	_key(preview, KEY_C)
	_check(not character.visible, "重复 C 恢复隐藏")
	_key(preview, KEY_H)
	_check(not hud.visible, "H 隐藏所有预览说明")
	_key(preview, KEY_H)
	_check(hud.visible, "H 可重新显示说明")
	_key(preview, KEY_2)
	_key(preview, KEY_C)
	_key(preview, KEY_H)
	_key(preview, KEY_R)
	_check(root.get_camera_3d() == hero and not character.visible and hud.visible, "R 完整恢复初始预览状态")
	_check(not preview.has_node("StageScene") and not preview.has_node("BattleCanvas"), "预览不实例化探索/战斗逻辑")
	preview.queue_free()
	await process_frame
	print("ACT01_PREVIEW: " + ("FAIL" if _failed else "PASS"))
	quit(1 if _failed else 0)
