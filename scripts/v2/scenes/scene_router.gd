extends Node
## 场景路由器 v2（Autoload 单例）
##
## 统一管理 v2 架构的场景流转：标题 → 章节 → 对话 → 卡牌战 → 结局。
## 所有场景切换走这里，便于后续加转场动画、加载界面等。

const TITLE_SCENE := "res://scenes/v2/title.tscn"
const DIALOG_SCENE := "res://scenes/v2/dialog.tscn"
const CARD_BATTLE_SCENE := "res://scenes/v2/card_battle.tscn"
const ENDING_SCENE := "res://scenes/v2/ending.tscn"
const EXPLORE_SCENE := "res://scenes/v2/explore.tscn"


func go_title() -> void:
	DebugLog.scene_switch("current", "title")
	get_tree().change_scene_to_file(TITLE_SCENE)


func go_explore(chapter_id: String) -> void:
	DebugLog.scene_switch("current", "explore ch=" + chapter_id)
	GameBridge.next_chapter_id = chapter_id
	GameBridge.next_node_id = ""
	# 注意：不清 explore_return_tile（对话/战斗返回时玩家位置靠它保留，由 explore_scene 消费后清空）
	get_tree().change_scene_to_file(EXPLORE_SCENE)


func go_dialog(chapter_id: String, node_id: String = "") -> void:
	DebugLog.scene_switch("current", "dialog ch=" + chapter_id + " node=" + node_id)
	GameBridge.next_chapter_id = chapter_id
	GameBridge.next_node_id = node_id
	get_tree().change_scene_to_file(DIALOG_SCENE)


func go_battle(battle_node_id: String, enemy_ids: Array, chapter_id: String) -> void:
	DebugLog.scene_switch("current", "battle node=" + battle_node_id)
	GameBridge.battle_node_id = battle_node_id
	GameBridge.enemy_ids = enemy_ids.duplicate()
	GameBridge.chapter_id_for_battle = chapter_id
	get_tree().change_scene_to_file(CARD_BATTLE_SCENE)


func go_ending(ending_id: String = "") -> void:
	DebugLog.scene_switch("current", "ending id=" + ending_id)
	GameBridge.ending_id = ending_id
	get_tree().change_scene_to_file(ENDING_SCENE)


## 开始新游戏：清存档 → 第一章入口
func start_new_game() -> void:
	NarrativeState.wipe()
	# node_id 留空，让 dialog 场景读 chapter 的 entry 字段（避免硬编码与 chapter 不同步）
	NarrativeState.enter_chapter("chapter_1", "")
	go_dialog("chapter_1", "")


## 继续游戏：读存档 → 跳到上次所在章节/节点
func continue_game() -> void:
	if not NarrativeState.has_save():
		start_new_game()
		return
	NarrativeState.load()
	go_dialog(NarrativeState.current_chapter, NarrativeState.current_node)
