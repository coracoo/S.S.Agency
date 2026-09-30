extends Node
## 全局 debug 日志 v2（Autoload 单例）
##
## 把所有关键事件（场景切换、按钮点击、节点渲染）写到 user://debug.log
## 用于排查"看不到画面"类问题——玩家关掉游戏后，开发者读日志就知道发生了什么。

const LOG_PATH := "user://debug.log"
var _file: FileAccess


func _ready() -> void:
	_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if _file == null:
		push_error("DebugLog: cannot open " + LOG_PATH)
		return
	_log("=== Game session started at " + Time.get_datetime_string_from_system() + " ===")


func _log(msg: String) -> void:
	if _file == null:
		return
	_file.store_line("[%s] %s" % [Time.get_time_string_from_system(), msg])
	_file.flush()


func info(msg: String) -> void:
	_log(msg)


func scene_switch(from: String, to: String) -> void:
	_log("SCENE_SWITCH: " + from + " -> " + to)


func button_clicked(btn_name: String) -> void:
	_log("BUTTON_CLICKED: " + btn_name)


func node_ready(node_name: String, detail: String = "") -> void:
	_log("NODE_READY: " + node_name + (" (" + detail + ")" if not detail.is_empty() else ""))
