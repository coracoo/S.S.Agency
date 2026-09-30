class_name BuildSaveV4
extends RefCounted
## V4 构筑存档（GDD §5.2「牌组保存」+ 持久化清单「构筑」）。
## 存 user://build.json：{version, main, support, deck:[16 个卡 id]}。
## 战斗发牌优先读本档；不合法或不存在则兜底战斗配置里的旧预设牌组。

const PATH := "user://build.json"
const VERSION := 1

## 读取构筑；无档/解析失败返回 {}（调用方走旧配置兜底）
static func load_build() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}

## 保存构筑；成功返回 true。artifact_id 可空（GDD §7：主战最多配置 1 件器物）
static func save_build(main_id: String, support_id: String, deck_ids: Array,
		artifact_id := "") -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"version": VERSION,
		"main": main_id,
		"support": support_id,
		"artifact": artifact_id,
		"deck": deck_ids,
	}, "\t"))
	return true

## 构筑是否可直接用于战斗（与构筑界面同一套校验，禁止两边规则漂移）
static func is_legal(build: Dictionary, library: Dictionary) -> bool:
	if build.is_empty():
		return false
	return (BattleRulesV4.validate_deck(
		build.get("deck", []), String(build.get("main", "")),
		String(build.get("support", "")), library) as Array).is_empty()
