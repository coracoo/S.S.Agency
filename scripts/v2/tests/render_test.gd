extends Control
## 渲染层最小测试
##
## 只有一个红色 ColorRect + 一个白字 Label。如果这个都看不见，
## 说明是 Forward+ 渲染器 + 显卡的兼容性问题，跟游戏代码无关。

func _ready() -> void:
	DebugLog.info("RENDER_TEST: ready, should show RED background + white text")
	print("=== RENDER_TEST: 如果你能看到红底白字，说明渲染正常 ===")
