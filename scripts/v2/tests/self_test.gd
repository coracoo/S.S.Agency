extends Node
## v2 架构自检脚本（临时）
##
## 用法：临时把 project.godot 的 main_scene 指向此脚本的场景，或在编辑器里运行。
## 验证：数据加载、单位创建、卡牌打出、combo 触发、章节加载、结局判定 6 大链路。
## 全部通过打印 [SELF-TEST] ALL PASSED，否则打印具体失败项。

func _ready() -> void:
	print("===== [SELF-TEST] v2 架构链路自检 =====")
	var results: Array = []
	results.append(_test_data_load())
	results.append(_test_unit_creation())
	results.append(_test_battle_init())
	results.append(_test_card_play())
	results.append(_test_combo_engine())
	results.append(_test_chapter_load())
	results.append(_test_narrative_flags())
	results.append(_test_ending_resolve())
	print("===== [SELF-TEST] %d/%d PASSED =====" % [results.count(true), results.size()])
	var failed = results.count(false)
	if failed == 0:
		print("[SELF-TEST] ALL PASSED")
	else:
		print("[SELF-TEST] %d FAILED" % failed)
	# 自动退出（headless 验证用）
	get_tree().quit(0 if failed == 0 else 1)


func _ok(label: String, cond: bool) -> bool:
	var tag = "OK" if cond else "FAIL"
	print("  [%s] %s" % [tag, label])
	return cond


func _test_data_load() -> bool:
	CardV2.load_cards()
	var c = CardV2.get_card("talisman_zhenhun")
	return _ok("CardV2.load_cards / get_card", not c.is_empty() and c.get("cost") == 1)


func _test_unit_creation() -> bool:
	var units_data = JsonLoader.load_file("res://data/v2/units.json")
	var tmpl = {}
	for u in units_data.get("units", []):
		if u.get("id") == "rinne":
			tmpl = u
	if tmpl.is_empty():
		return _ok("UnitV2 创建（找不到 rinne 模板）", false)
	var unit = UnitV2.new(tmpl, "rinne")
	var ok = unit.is_alive and unit.current_hp == 60 and unit.has_tag("daoist")
	return _ok("UnitV2 创建（hp=60, tag=daoist）", ok)


func _test_battle_init() -> bool:
	var state = GameStateV2.new()
	state.init_battle(["rinne"], ["steam_jiangshi"])
	var ok = state.players.size() == 1 and state.enemies.size() == 1
	ok = ok and state.get_alive_enemies().size() == 1
	return _ok("GameStateV2.init_battle（1v1）", ok)


func _test_card_play() -> bool:
	var state = GameStateV2.new()
	state.init_battle(["rinne"], ["paper_effigy"])
	state.start_player_turn()
	var enemy = state.enemies[0]
	var hp_before = enemy.current_hp
	var card_def = CardV2.get_card("peach_wood_slash")  # 8 物理伤害
	var player_entry = state.players[0]
	var resolver = CardResolverV2.new(state.combo_engine)
	state.spend_qi(int(card_def.get("cost", 0)))
	resolver.play_card(card_def, enemy, state, player_entry)
	# paper_effigy defense=1 → mitigation = int(1*0.5)=0 → 实际 8 伤害
	var ok = enemy.current_hp == hp_before - 8
	return _ok("CardResolverV2 打牌（敌人掉 8 血）", ok)


func _test_combo_engine() -> bool:
	var state = GameStateV2.new()
	state.init_battle(["rinne"], ["paper_effigy", "paper_effigy"])
	state.start_player_turn()
	# 给两个敌人都挂 wet
	var e0 = state.enemies[0]
	var e1 = state.enemies[1]
	e0.apply_tag("wet", 1)
	e1.apply_tag("wet", 1)
	# 用蒸汽阀（fire 标签，all_enemies）触发 steam_explosion combo
	var card_def = CardV2.get_card("steam_valve_release")
	var resolver = CardResolverV2.new(state.combo_engine)
	state.spend_qi(int(card_def.get("cost", 0)))
	var result = resolver.play_card(card_def, null, state, state.players[0])
	var triggered = result.get("combos_triggered", [])
	var ok = not triggered.is_empty() and triggered[0].get("combo_id") == "steam_explosion"
	return _ok("ComboEngine 蒸汽爆裂连锁（wet+fire→spread）", ok)


func _test_chapter_load() -> bool:
	var ch = ChapterLoader.load_chapter("chapter_1")
	var ok = not ch.is_empty() and ch.get("entry") == "intro_dialog"
	ok = ok and ch.get("nodes", {}).has("battle_1")
	ok = ok and ch.has("scene")  # 探索场景定义
	return _ok("ChapterLoader.load_chapter（chapter_1 含 battle_1 + scene）", ok)


func _test_narrative_flags() -> bool:
	NarrativeState.wipe()
	NarrativeState.set_flag("chose_fight", true)
	NarrativeState.set_flag("helped_mechanist", true)
	var ok = NarrativeState.has_flag("chose_fight") and NarrativeState.has_flag("helped_mechanist")
	# 测试结局条件匹配
	var endings = [
		{"id": "a", "priority": 10, "condition": {"chose_fight": true, "helped_mechanist": true}},
		{"id": "b", "priority": 5, "condition": {"chose_fight": true}}
	]
	var resolved = NarrativeState.resolve_ending(endings)
	ok = ok and resolved.get("id") == "a"  # 高优先级匹配
	return _ok("NarrativeState flags + resolve_ending（高优先级 a）", ok)


func _test_ending_resolve() -> bool:
	NarrativeState.wipe()
	NarrativeState.set_flag("battle_defeated", true)
	var endings = JsonLoader.load_file("res://data/v2/endings.json").get("endings", [])
	var resolved = NarrativeState.resolve_ending(endings)
	var ok = resolved.get("id") == "defeat"
	return _ok("Endings.json 匹配（战败→defeat）", ok)
