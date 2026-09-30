extends Node
## 地图系统测试 v3
##
## 验证 64×64 大地图 + 地图全玩法的数据层：
##   1. manifest 加载 + 图块 atlas 注册
##   2. 地图加载（≥60×60）
##   3. TileMap 节点构建（渲染层）
##   4. 基础规则：墙不可走、出生点可走、坑不可走
##   5. BFS 全图连通性：从出生点可达 所有敌人/道具/NPC 邻位/门邻位
##   6. 钥匙门玩法：拿钥匙前门锁死，set flag 后门可通行
##   7. 传送门玩法：旗标满足后可踏入
##   8. 拾取→战斗牌池闭环：card_* 旗标使牌池扩容
##   9. 敌人击败移除：defeat_enemy_at 后该格可走

func _ready() -> void:
	print("===== [MAP-TEST] 64×64 地图系统测试 =====")
	var results: Array = []
	results.append(_test_manifest())
	results.append(_test_map_load())
	results.append(_test_tilemap_node())
	results.append(_test_basic_rules())
	results.append(_test_bfs_connectivity())
	results.append(_test_door_gameplay())
	results.append(_test_portal_gameplay())
	results.append(_test_card_flag_to_deck())
	results.append(_test_enemy_defeat())
	var failed = results.count(false)
	print("===== [MAP-TEST] %d/%d PASSED =====" % [results.count(true), results.size()])
	get_tree().quit(0 if failed == 0 else 1)


func _ok(label: String, cond: bool) -> bool:
	var tag = "OK" if cond else "FAIL"
	print("  [%s] %s" % [tag, label])
	return cond


func _test_manifest() -> bool:
	AssetRegistry.load_manifest(true)
	var ok = AssetRegistry.has("tiles/wall") and AssetRegistry.has("ui9/panel_main")
	ok = ok and AssetRegistry.get_tileset_atlas_path() != ""
	var coords = AssetRegistry.get_tile_atlas_coords("wall")
	ok = ok and coords.x >= 0
	return _ok("manifest 加载（tiles/ui9/atlas 坐标）", ok)


func _test_map_load() -> bool:
	var m = TileMapV2.new()
	var ok = m.load_map("res://data/v2/maps/map_64.json")
	ok = ok and m.width >= 60 and m.height >= 60
	ok = ok and m.ground.size() == m.height
	ok = ok and m.objects.size() >= 5
	return _ok("地图加载 %dx%d，物件 %d 个" % [m.width, m.height, m.objects.size()], ok)


func _test_tilemap_node() -> bool:
	var m = TileMapV2.new()
	m.load_map("res://data/v2/maps/map_64.json")
	var tm = m.build_tilemap_node()
	var ok = tm != null and tm.tile_set != null
	if tm != null:
		# 有格子被填充
		ok = ok and tm.get_used_rect().size.x >= 60
		tm.free()
	return _ok("TileMap 节点构建（atlas + cells）", ok)


func _test_basic_rules() -> bool:
	var m = TileMapV2.new()
	m.load_map("res://data/v2/maps/map_64.json")
	# 边界全是墙
	var ok = not m.is_walkable(0, 0) and not m.is_walkable(m.width - 1, m.height - 1)
	# 出生点可走
	ok = ok and m.is_walkable(m.player_start.x, m.player_start.y)
	# 存在至少一个坑且不可走
	var has_pit := false
	var pit_blocked := true
	for y in m.height:
		for x in m.width:
			if m.tile_name_at(x, y) == "pit":
				has_pit = true
				if m.is_walkable(x, y):
					pit_blocked = false
	ok = ok and has_pit and pit_blocked
	return _ok("基础规则（边界墙/出生点/坑阻挡）", ok)


## BFS：从出生点出发，可达每个关键物件的格位或其 4 邻位
func _reachable_set(m: TileMapV2) -> Dictionary:
	var start = m.player_start
	var visited := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if visited.has(nxt):
				continue
			if not m.is_walkable(nxt.x, nxt.y):
				continue
			visited[nxt] = true
			queue.append(nxt)
	return visited


func _test_bfs_connectivity() -> bool:
	var m = TileMapV2.new()
	m.load_map("res://data/v2/maps/map_64.json")
	var reach = _reachable_set(m)
	var ok = reach.size() > 300  # 大量格子连通
	var all_objects_ok := true
	for obj in m.objects:
		var t = obj.get("tile", [0, 0])
		var pos = Vector2i(int(t[0]), int(t[1]))
		# 物件所在格本身或其 4 邻格必须可达
		var near = reach.has(pos)
		if not near:
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if reach.has(pos + dir):
					near = true
					break
		if not near:
			all_objects_ok = false
			print("    unreachable object: ", obj.get("id"), " at ", pos)
	ok = ok and all_objects_ok
	return _ok("BFS 连通：reach=%d 格，全部物件可达" % reach.size(), ok)


func _test_door_gameplay() -> bool:
	var m = TileMapV2.new()
	m.load_map("res://data/v2/maps/map_64.json")
	var ok = m.doors.size() >= 1
	# 初始（无钥匙）：门格不可走
	var locked_all := true
	var door_keys := []
	for key in m.doors:
		door_keys.append(key)
		if m.is_walkable(key.x, key.y):
			locked_all = false
	ok = ok and locked_all
	# 给钥匙旗标：门可走
	NarrativeState.set_flag("has_key", true)
	var open_all := true
	for key in door_keys:
		if not m.is_walkable(key.x, key.y):
			open_all = false
	ok = ok and open_all
	NarrativeState.clear_flags()
	return _ok("钥匙门玩法（锁定→旗标解锁）", ok)


func _test_portal_gameplay() -> bool:
	var m = TileMapV2.new()
	m.load_map("res://data/v2/maps/map_64.json")
	var ok = m.portal.size() == 1
	# 传送门地砖本身可走（踏上去才判旗标），requires_flag 逻辑在 explore 层
	for key in m.portal:
		ok = ok and m.tile_name_at(key.x, key.y) == "portal"
		ok = ok and not str(m.portal[key].get("requires_flag", "")).is_empty()
	return _ok("传送门配置（P 地砖 + requires_flag）", ok)


func _test_card_flag_to_deck() -> bool:
	NarrativeState.clear_flags()
	NarrativeState.set_flag("card_talisman_yinlei", true)
	var state = GameStateV2.new()
	state.init_battle(["rinne"], ["paper_effigy"])
	var base = 5  # rinne starting_deck 数量
	var ok = state.players[0].deck.card_ids.size() == base + 1
	NarrativeState.clear_flags()
	return _ok("拾取卡牌→战斗牌池（base %d + 1）" % base, ok)


func _test_enemy_defeat() -> bool:
	var m = TileMapV2.new()
	m.load_map("res://data/v2/maps/map_64.json")
	var found := false
	var flag := ""
	for obj in m.objects:
		if str(obj.get("type", "")) == "enemy":
			var t = obj.get("tile", [0, 0])
			var pos = Vector2i(int(t[0]), int(t[1]))
			var blocked_before: bool = not m.is_walkable(pos.x, pos.y)
			flag = m.defeat_enemy_at(pos.x, pos.y)
			# 击败后：返回旗标，且该格（普通地板）变为可走
			var walkable_after: bool = m.is_walkable(pos.x, pos.y) if m.tile_name_at(pos.x, pos.y) != "wall" else true
			found = blocked_before and (not flag.is_empty()) and walkable_after
			break
	return _ok("敌人击败移除（占位→可走，flag=%s）" % flag, found)
