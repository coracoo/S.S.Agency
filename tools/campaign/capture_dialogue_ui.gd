# 对话层独立截图：立绘/正文/分支三状态，无需章节会话。
extends SceneTree
const DialogueOverlayScript = preload("res://scripts/ui/dialogue_overlay.gd")
var output := ""
const NODES := {
	"n1": {"side": "left", "portrait": "res://assets/chars/portraits/rinne_half.png", "speaker": "rinne", "name": "凛音", "text": "……逢魔之时，山道上的灯火比昨日少了一盏。纸妖既已现身，棺中所封之物恐怕也安分不了多久。", "next": "n2"},
	"n2": {"side": "right", "portrait": "res://assets/chars/portraits/sayo_half.png", "speaker": "sayo", "name": "小夜", "text": "夜露正浓。要赶在子夜前布好墨线，还是先探一探祠堂的动静？", "choices": [
		{"text": "先布墨线，稳妥为上", "next": "n3"},
		{"text": "去祠堂。迟则生变，今晚就做个了断", "next": "n3"},
	]},
	"n3": {"side": "left", "portrait": "res://assets/chars/portraits/rinne_half.png", "speaker": "rinne", "name": "凛音", "text": "好。都跟上——别落单。", "next": ""},
}
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1" or OS.get_environment("ACT_ONE_OUTPUT").is_empty(): quit(2); return
	output = OS.get_environment("ACT_ONE_OUTPUT")
	_run.call_deferred()
func _shot(name: String) -> void:
	await process_frame
	await process_frame
	root.get_texture().get_image().save_png(output.path_join(name))
func _run() -> void:
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(1920, 1080)
	var dlg = DialogueOverlayScript.new(null)
	root.add_child(dlg)
	await process_frame
	dlg._nodes = NODES
	dlg._active = true
	# 状态1：打字完成、单立绘
	dlg._present_node("n1")
	dlg._typing = false
	dlg._text_label.visible_characters = -1
	dlg._hint_label.visible = true
	dlg._phase = "wait"
	await _shot("dialogue_text.png")
	# 状态2：双立绘 + 分支选项
	dlg._present_node("n2")
	dlg._typing = false
	dlg._text_label.visible_characters = -1
	dlg._show_choices(dlg._current_choices)
	dlg._phase = "choice"
	await _shot("dialogue_choices.png")
	print("DIALOGUE_CAPTURE: 2 screenshots")
	quit(0)
