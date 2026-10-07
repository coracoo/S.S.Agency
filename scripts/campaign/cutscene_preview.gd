# F6独立预览：只读本地文件，不建立主线会话、不接触正式存档。
extends Control
const Player = preload("res://scripts/campaign/cutscene_player.gd")
const Clips = preload("res://scripts/campaign/cutscene_catalog.gd")
var _label: Label
func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("10141b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_label = Label.new()
	_label.position = Vector2(80, 80)
	_label.add_theme_font_override("font", load("res://assets/fonts/Alibaba-PuHuiTi-Regular.ttf"))
	_label.add_theme_font_size_override("font_size", 26)
	add_child(_label)
	var player := Player.new()
	add_child(player)
	player.finished.connect(func(result):
		_label.text = "过场预览结束：%s\n重新按 F6 可重播；本预览不写入任何主线进度。" % result
		player.queue_free())
	if not player.play_file(Clips.resolve_file(Clips.STONE_BOWL_FILE)):
		_label.text = "未找到可播放的 Ogg Theora 过场。\n请将转换后的文件放入：\nassets/cutscenes/night1_stone_bowl.ogv\n\n说明：docs/campaign/cutscenes.md"
		player.queue_free()
