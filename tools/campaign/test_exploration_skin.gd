# 正式探索外框/模态与地图沿用生图皮肤，先核验隔离目录。
extends SceneTree
const Stage = preload("res://scripts/campaign/chapter_stage.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("FAIL: ", message)
func _run() -> void:
	for resolution in [Vector2i(1920,1080), Vector2i(1280,720), Vector2i(1180,812)]:
		root.size = resolution
		var stage = Stage.new()
		root.add_child(stage)
		stage.set_process(false)
		stage._close_modal()
		await process_frame
		check(absf(stage._hud.prompt_panel.get_global_rect().end.y - (root.get_visible_rect().end.y - 30)) < 2, "窄高窗口提示条贴近底部安全边距")
		for id in ["map", "pause"]:
			var button: Button = stage._hud[id]
			check(button.get_theme_stylebox("normal") is StyleBoxTexture, "HUD入口使用生图：" + id)
			check(button.size.y >= 72, "HUD入口字形有内框留白")
		var info = stage._ui_layer.get_child(0).find_child("NightInformation", true, false)
		check(info.get_theme_stylebox("panel") is StyleBoxTexture, "短信息卡使用生图内凹底")
		stage._show_modal("进入战斗", "线索正文不改写。\n可取消继续调查。", [{"text":"进入战斗","call":Callable()}, {"text":"暂不应战","call":Callable()}])
		await process_frame
		for child in stage._modal.get_children():
			if child is Panel: check(child.get_theme_stylebox("panel") is StyleBoxTexture, "确认弹窗使用生成外框")
		for button in stage._modal_buttons:
			check(button.get_theme_stylebox("normal") is StyleBoxTexture, "弹窗动作使用生图按钮")
			check(button.size.y >= 72, "弹窗按钮不压字")
			check(root.get_visible_rect().encloses(button.get_global_rect()), "弹窗按钮保持画布内")
		stage.free()
	root.size = Vector2i(1180,812)
	var resizing = Stage.new()
	root.add_child(resizing)
	resizing.set_process(false)
	resizing._show_modal("切比例保留长文", "线索原文。".repeat(300), [{"text":"确认","call":Callable()},{"text":"取消","call":Callable()}])
	await process_frame
	root.size = Vector2i(1920,1080)
	await process_frame
	await process_frame
	for button in resizing._modal_buttons:
		check(root.get_visible_rect().encloses(button.get_global_rect()), "打开长弹窗后切比例，按钮仍完整可见")
	resizing.free()
	print("EXPLORATION_SKIN:",checks," FAILURES:",failures.size())
	quit(0 if failures.is_empty() else 1)
