class_name CardLibraryV4
extends RefCounted
## V4 卡库（GDD §5.2 构筑规则的数据源）。
## 扫描 data/battles/*.json 合并全部卡牌定义，按 id 去重（先出现者优先）。
## 构筑界面与战斗发牌共用同一份卡库，保证「收藏里有什么，战斗就能发什么」。
## 全部为 static 纯函数，可无头单测。

const BATTLES_DIR := "res://data/battles"

## 返回 {card_id: card_def}。读取失败返回空表（调用方须兜底旧配置路径）
static func load_library() -> Dictionary:
	var lib := {}
	var dir := DirAccess.open(BATTLES_DIR)
	if dir == null:
		push_warning("[CardLibraryV4] 打不开 %s" % BATTLES_DIR)
		return lib
	for fname in dir.get_files():
		if not fname.ends_with(".json"):
			continue
		var f := FileAccess.open("%s/%s" % [BATTLES_DIR, fname], FileAccess.READ)
		if f == null:
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if not (parsed is Dictionary):
			continue
		for def in (parsed.get("cards", []) as Array):
			if def is Dictionary:
				var id := String(def.get("id", ""))
				if not id.is_empty() and not lib.has(id):
					lib[id] = def
	return lib

## 用卡库把 id 列表解析成卡定义列表；未知 id 跳过（调用方校验合法性后再用）
static func resolve_ids(deck_ids: Array, library: Dictionary) -> Array:
	var defs: Array = []
	for id in deck_ids:
		if library.has(id):
			defs.append(library[id])
	return defs

## 战斗/仪式共用的组牌入口（GDD §5.2 构筑优先、旧配置兜底铁律的唯一实现）。
## cfg: 场次 JSON（含 cards/deck）；artifact: 当前器物（可空，结界符折扣）。
## 返回入抽牌堆的卡定义数组（已按器物折扣修正费用，折扣落到副本不改卡库）。
static func build_deck_defs(cfg: Dictionary, artifact: Dictionary) -> Array:
	var library := load_library()
	var build := BuildSaveV4.load_build()
	if BuildSaveV4.is_legal(build, library):
		var defs: Array = resolve_ids(build.get("deck", []), library)
		if defs.size() == 16:
			return _apply_seal_discount(defs, artifact)
	# 兜底：旧配置 copies 份预设
	var out: Array = []
	var copies := int(cfg.get("deck", {}).get("copies", 1))
	for def in (cfg.get("cards", []) as Array):
		for i in copies:
			out.append(def)
	return _apply_seal_discount(out, artifact)

## 器物：裁符小刀类——结界符灵墨费用折扣（最低 1）。入参出参均为新/原定义混合，
## 被折扣的卡以副本替换，调用方持有数组即可安全洗牌
static func _apply_seal_discount(defs: Array, artifact: Dictionary) -> Array:
	var discount := BattleRulesV4.artifact_value(artifact, "seal_cost_discount", 0)
	if discount <= 0:
		return defs
	var out: Array = []
	for d in defs:
		if String((d as Dictionary).get("type", "")) == "seal":
			var nd: Dictionary = (d as Dictionary).duplicate()
			nd["cost"] = BattleRulesV4.artifact_seal_cost(int(d.get("cost", 0)), discount)
			out.append(nd)
		else:
			out.append(d)
	return out
