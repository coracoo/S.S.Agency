extends Control
## 标题屏 v2
##
## 蒸汽道术风格标题屏。三个按钮：开始新游戏 / 继续 / 退出。
## 暂时用纯色块占位，P0 阶段换成 AI 生成的标题背景。

@onready var new_game_btn: Button = $NewGameBtn
@onready var continue_btn: Button = $ContinueBtn
@onready var exit_btn: Button = $ExitBtn


func _ready() -> void:
	# 预加载 v2 数据
	CardV2.load_cards()
	continue_btn.disabled = not NarrativeState.has_save()
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	exit_btn.pressed.connect(_on_exit)
	DebugLog.node_ready("TitleScene", "buttons connected, has_save=%s" % NarrativeState.has_save())
	# 9-slice 按钮主题（JSON 驱动）
	UIThemeFactoryV2.apply_button(new_game_btn)
	UIThemeFactoryV2.apply_button(continue_btn)
	UIThemeFactoryV2.apply_button(exit_btn)


func _on_new_game() -> void:
	DebugLog.button_clicked("NewGameBtn")
	SceneRouter.start_new_game()


func _on_continue() -> void:
	DebugLog.button_clicked("ContinueBtn")
	SceneRouter.continue_game()


func _on_exit() -> void:
	DebugLog.button_clicked("ExitBtn")
	get_tree().quit()
