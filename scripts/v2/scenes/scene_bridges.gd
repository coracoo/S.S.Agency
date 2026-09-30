extends Node
## 游戏桥接器 v2（Autoload 单例）
##
## Godot 的 change_scene_to_file 无法直接给新场景传参。用本 autoload 单例做中转：
## 路由器写入 → 新场景 _ready 时读出 → 用完清空。
##
## 三个桥合并到一个单例，避免注册多个 autoload。

# ===== Dialog 场景读 =====
var next_chapter_id: String = ""
var next_node_id: String = ""

# ===== CardBattle 场景读 =====
var battle_node_id: String = ""
var enemy_ids: Array = []
var chapter_id_for_battle: String = ""
var battle_result: String = ""  # "victory" / "defeat"，战斗结束时写入
var pending_defeat_flag: String = ""  # 战斗胜利后要 set 的 flag（探索场景用）

# ===== Ending 场景读 =====
var ending_id: String = ""

# ===== 探索层相关 =====
var return_to_explore: bool = false  # dialog 场景用：对话结束后回 explore 而不是切下一节点
var explore_return_tile: Vector2i = Vector2i(-1, -1)  # 玩家离开探索时的图块坐标（跨场景保留）


func clear_chapter() -> void:
	next_chapter_id = ""
	next_node_id = ""


func clear_battle() -> void:
	battle_node_id = ""
	enemy_ids = []
	chapter_id_for_battle = ""
	battle_result = ""
	pending_defeat_flag = ""


func clear_explore() -> void:
	return_to_explore = false
	explore_return_tile = Vector2i(-1, -1)


func clear_ending() -> void:
	ending_id = ""
