class_name NextBattleV4
extends RefCounted
## 场景间传递「下一场战斗」的轻量载体（GDD §5.2：战前构筑是独立场景）。
## stage 触发战斗时先写本类的 scene_path 再切到构筑场景；
## 构筑场景「出战」读 scene_path 进入战斗，「返回」读 return_path 回探索。
## 走 static 而不是 autoload：只有两个场景用到，不必注册全局单例。

static var scene_path := "res://scenes/v3/battle.tscn"
static var return_path := "res://scenes/v3/title.tscn"

static func set_next(battle: String, ret: String) -> void:
	scene_path = battle
	return_path = ret
