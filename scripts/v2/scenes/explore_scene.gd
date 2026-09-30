extends Node2D
## 横版→网格大地图探索场景 v3
##
## 承载 64×64 图块地图的全部玩法：
##   - 网格移动（A/D/W/S 或方向键，图块碰撞：墙/坑/锁门/存活敌人）
##   - NPC 互动（相邻格按 E → 对话节点）
##   - 敌人遇敌（走入敌人格 → 卡牌战斗，胜利后旗标+移除）
##   - 道具拾取（踩上道具格 → 旗标 + 可选给卡）
##   - 封印门（钥匙旗标解锁，锁定时提示）
##   - 传送门出口（旗标满足 → 章节 complete）
##
## 数据：chapter.scene.map 指向 data/v2/maps/*.json（由 build_asset_pipeline.py 生成）。
## 资产：经 AssetRegistry（manifest 驱动）加载。

const TILE := 32

@onready var world: Node2D = $World
@onready var hint_label: Label = $UI/HintLabel
@onready var interact_prompt: Label = $UI/InteractPrompt
@onready var alert_label: Label = $UI/AlertLabel

var chapter_id: String = ""
var chapter_data: Dictionary = {}
var scene_def: Dictionary = {}
var map: TileMapV2
var player: PlayerController
var camera: Camera2D

# 物件表现节点
var _object_nodes: Dictionary = {}  # obj_id → Node2D
var _player_tile: Vector2i


func _ready() -> void:
	chapter_id = GameBridge.next_chapter_id
	GameBridge.clear_chapter()
	if chapter_id.is_empty():
		chapter_id = "chapter_1"
	chapter_data = ChapterLoader.load_chapter(chapter_id)
	if chapter_data.is_empty():
		push_error("ExploreScene: chapter not found " + chapter_id)
		return
	scene_def = chapter_data.get("scene", {})
	var map_id = str(scene_def.get("map", ""))
	if map_id.is_empty():
		push_error("ExploreScene: chapter.scene.map missing（旧格式或配置缺失）")
		return
	DebugLog.node_ready("ExploreScene", "ch=" + chapter_id + " map=" + map_id)

	# 加载地图
	map = TileMapV2.new()
	if not map.load_map("res://data/v2/maps/%s.json" % map_id):
		push_error("ExploreScene: map load failed " + map_id)
		return

	_build_world()


func _build_world() -> void:
	# 图块层
	var tm = map.build_tilemap_node()
	if tm != null:
		world.add_child(tm)

	# 玩家（位置：跨场景保留优先）
	var start_tile = map.player_start
	if GameBridge.explore_return_tile.x >= 0:
		start_tile = GameBridge.explore_return_tile
	GameBridge.explore_return_tile = Vector2i(-1, -1)
	_player_tile = start_tile

	player = PlayerController.new()
	world.add_child(player)
	player.setup(str(scene_def.get("player_sprite", "")), map.tile_to_world_feet(start_tile.x, start_tile.y))

	# 相机刚性跟随（禁用平滑：平滑导致子像素漂移 + NEAREST 采样 = 画面闪烁）
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	camera.limit_left = 0
	camera.limit_top = 0
	var px_size = map.map_pixel_size()
	camera.limit_right = int(px_size.x)
	camera.limit_bottom = int(px_size.y)
	player.add_child(camera)
	camera.make_current()

	# 物件表现
	_spawn_object_nodes()


func _spawn_object_nodes() -> void:
	for obj in map.objects:
		if not (obj is Dictionary):
			continue
		var t = obj.get("tile", [0, 0])
		var tile = Vector2i(int(t[0]), int(t[1]))
		var otype = str(obj.get("type", ""))
		# 已击败的敌人 / 已拾取的道具不生成
		if otype == "enemy":
			var flag = str(obj.get("on_defeat_flag", ""))
			if not flag.is_empty() and NarrativeState.has_flag(flag):
				continue
		elif otype == "item":
			var sflag = str(obj.get("set_flag", ""))
			if not sflag.is_empty() and NarrativeState.has_flag(sflag):
				continue
		var node = _make_object_node(obj)
		world.add_child(node)
		_object_nodes[str(obj.get("id", ""))] = node


func _make_object_node(obj: Dictionary) -> Node2D:
	var t = obj.get("tile", [0, 0])
	var node = Node2D.new()
	node.position = map.tile_to_world_feet(int(t[0]), int(t[1]))
	var otype = str(obj.get("type", ""))

	var sprite_path = str(obj.get("sprite", ""))
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		var s = Sprite2D.new()
		s.texture = load(sprite_path)
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.centered = false
		if otype == "item":
			s.scale = Vector2(1.0, 1.0)
			s.position = Vector2(-8, -20)  # 16×16 道具悬在地面上方
			s.z_index = 3
		else:
			# 整数 2× 缩放（同玩家，避免 1.5× 奇偶像素闪烁）
			s.scale = Vector2(2.0, 2.0)
			s.position = Vector2(-32, -96)
			s.z_index = 4
		node.add_child(s)
	else:
		# 占位色块（保证可见）
		var ph = ColorRect.new()
		match otype:
			"enemy": ph.color = Color(0.76, 0.23, 0.23, 1)
			"npc": ph.color = Color(0.47, 0.43, 0.39, 1)
			"item": ph.color = Color(0.83, 0.69, 0.22, 1)
			_: ph.color = Color(0.6, 0.6, 0.6, 1)
		ph.size = Vector2(24, 36)
		ph.position = Vector2(-12, -36)
		ph.z_index = 4
		node.add_child(ph)
	return node


# ===== 每帧：输入 + 提示 =====

func _process(_delta: float) -> void:
	if player == null or map == null:
		return
	_handle_move_input()
	_update_prompts()


func _handle_move_input() -> void:
	if player.is_sliding():
		return
	var dir := Vector2i.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir = Vector2i(-1, 0)
	elif Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir = Vector2i(1, 0)
	elif Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir = Vector2i(0, -1)
	elif Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir = Vector2i(0, 1)
	if dir == Vector2i.ZERO:
		return
	_try_step(dir)


## 走一格：地图玩法的核心入口
func _try_step(dir: Vector2i) -> void:
	var target = _player_tile + dir
	var obj = map.get_object_at(target.x, target.y)

	# 1) 敌人格：走入即遇敌
	if map.is_enemy_at(target.x, target.y) and not obj.is_empty():
		_start_encounter(obj)
		return

	# 2) 锁门：提示并阻挡
	if not map.is_door_open(target.x, target.y):
		var door_obj = map.doors.get(target, {})
		var msg = str(door_obj.get("locked_text", "门被锁住了"))
		alert_label.text = "🔒 " + msg
		alert_label.modulate.a = 1.0
		var tw = create_tween()
		tw.tween_interval(1.2)
		tw.tween_property(alert_label, "modulate:a", 0.0, 0.3)
		DebugLog.info("MAP: door blocked at %s" % target)
		return

	# 3) 不可走（墙/坑）
	if not map.is_walkable(target.x, target.y):
		return

	# 4) 正常移动
	var moved = player.slide_to(map.tile_to_world_feet(target.x, target.y))
	if moved:
		_player_tile = target
		player.slide_finished.connect(_on_step_landed.bind(target), CONNECT_ONE_SHOT)


## 每步落地后检查地面玩法（拾取/传送门）
func _on_step_landed(tile: Vector2i) -> void:
	var obj = map.get_object_at(tile.x, tile.y)
	if obj.is_empty():
		return
	match str(obj.get("type", "")):
		"item":
			_pickup_item(obj, tile)
		"portal":
			_try_portal(obj)


## 拾取：旗标 + 可选给卡 + 移除表现节点
func _pickup_item(obj: Dictionary, tile: Vector2i) -> void:
	var sflag = str(obj.get("set_flag", ""))
	if not sflag.is_empty():
		NarrativeState.set_flag(sflag, true)
	var card = str(obj.get("give_card", ""))
	if not card.is_empty():
		# card_ 旗标由 GameStateV2.init_battle 读取并入牌池
		NarrativeState.set_flag("card_" + card, true)
	var text = str(obj.get("pickup_text", "获得道具"))
	DebugLog.info("MAP: pickup id=" + str(obj.get("id", "")) + " flag=" + sflag + " card=" + card)
	map.remove_object(str(obj.get("id", "")))
	var node = _object_nodes.get(str(obj.get("id", "")))
	if node != null:
		_object_nodes.erase(str(obj.get("id", "")))
		node.queue_free()
	# 拾取飘字（屏幕提示）
	alert_label.modulate.a = 1.0
	alert_label.text = "✦ " + text
	var tw = create_tween()
	tw.tween_interval(1.0)
	tw.tween_property(alert_label, "modulate:a", 0.0, 0.3)


## 传送门：旗标满足 → 章节 complete
func _try_portal(obj: Dictionary) -> void:
	var req = str(obj.get("requires_flag", ""))
	if not req.is_empty() and not NarrativeState.has_flag(req):
		alert_label.modulate.a = 1.0
		alert_label.text = "🔒 " + str(obj.get("locked_text", "封印未解"))
		var tw = create_tween()
		tw.tween_interval(1.2)
		tw.tween_property(alert_label, "modulate:a", 0.0, 0.3)
		return
	DebugLog.info("MAP: portal entered -> chapter complete")
	NarrativeState.mark_chapter_complete(chapter_id)
	SceneRouter.go_title()


## 遇敌：进卡牌战斗（保留玩家图块位置）
func _start_encounter(obj: Dictionary) -> void:
	GameBridge.explore_return_tile = _player_tile
	var enemy_template = str(obj.get("enemy_template", "paper_effigy"))
	var on_encounter = str(obj.get("on_encounter", "battle_1"))
	DebugLog.info("MAP: encounter enemy=" + enemy_template + " node=" + on_encounter)
	GameBridge.battle_node_id = on_encounter
	GameBridge.enemy_ids = [enemy_template]
	GameBridge.chapter_id_for_battle = chapter_id
	GameBridge.pending_defeat_flag = str(obj.get("on_defeat_flag", ""))
	get_tree().change_scene_to_file("res://scenes/v2/card_battle.tscn")


## NPC 互动：相邻格按 E
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_interact") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		_try_npc_interact()


func _try_npc_interact() -> void:
	# 4 邻格找 NPC
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t = _player_tile + dir
		var obj = map.get_object_at(t.x, t.y)
		if obj.is_empty() or str(obj.get("type", "")) != "npc":
			continue
		var on_trigger = str(obj.get("on_trigger", ""))
		if on_trigger.is_empty():
			continue
		GameBridge.explore_return_tile = _player_tile
		DebugLog.info("MAP: npc interact id=" + str(obj.get("id", "")) + " -> " + on_trigger)
		GameBridge.next_chapter_id = chapter_id
		GameBridge.next_node_id = on_trigger
		GameBridge.return_to_explore = true
		get_tree().change_scene_to_file("res://scenes/v2/dialog.tscn")
		return


# ===== 提示 UI =====

func _update_prompts() -> void:
	# NPC 相邻 → 互动提示
	var npc_near = ""
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var obj = map.get_object_at((_player_tile + dir).x, (_player_tile + dir).y)
		if not obj.is_empty() and str(obj.get("type", "")) == "npc":
			npc_near = str(obj.get("name", "???"))
			break
	if not npc_near.is_empty():
		interact_prompt.text = "按 E 与「%s」互动" % npc_near
		interact_prompt.modulate.a = 1.0
	else:
		interact_prompt.modulate.a = 0.0

	# 敌人 3 格内 → 危险提示
	var nearest := 9999.0
	for obj in map.objects:
		if not (obj is Dictionary) or str(obj.get("type", "")) != "enemy":
			continue
		var flag = str(obj.get("on_defeat_flag", ""))
		if not flag.is_empty() and NarrativeState.has_flag(flag):
			continue
		var t = obj.get("tile", [0, 0])
		var d = Vector2i(int(t[0]), int(t[1])).distance_to(_player_tile)
		nearest = min(nearest, d)
	if nearest <= 1.5:
		alert_label.text = "‼ 敌人接邻"
		alert_label.modulate.a = 1.0
	elif nearest <= 3.0:
		alert_label.text = "⚠ 前方危险"
		alert_label.modulate.a = 0.8
	elif alert_label.text.begins_with("⚠") or alert_label.text.begins_with("‼"):
		alert_label.modulate.a = 0.0
		alert_label.text = ""
	hint_label.text = "WASD/方向键 移动 · E 互动 · 碰敌人开战 · 钥匙开锁"
