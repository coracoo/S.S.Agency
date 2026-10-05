# NPC旁白与呈现独立于主线状态；真实几何、原PNG、脚锚一起验收。
extends SceneTree
const Layout = preload("res://scripts/campaign/act_one_layout.gd")
const Geometry = preload("res://scripts/campaign/act_one_geometry.gd")
const REFERENCES := {
	"liang": {"crown": Vector2i(525, 64), "sole": Vector2i(400, 1483), "ground": 1487.0, "height": 1.72},
	"acheng": {"crown": Vector2i(518, 62), "sole": Vector2i(380, 1493), "ground": 1497.0, "height": 1.76},
	"mint": {"crown": Vector2i(616, 50), "sole": Vector2i(650, 1062), "ground": 1063.0, "height": 1.58},
	"guard": {"crown": Vector2i(565, 97), "sole": Vector2i(744, 1122), "ground": 1123.0, "height": 1.86},
	"controller": {"crown": Vector2i(504, 50), "sole": Vector2i(638, 1073), "ground": 1074.0, "height": 1.66},
}
var failures: Array[String] = []
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	_run.call_deferred()
func _run() -> void:
	var path := "res://scripts/campaign/act_one_npcs.gd"
	check(FileAccess.file_exists(path), "连续寺域拥有独立NPC定义与呈现模块")
	if not FileAccess.file_exists(path): _finish(); return
	var Npcs = load(path)
	if Npcs == null: check(false, "NPC脚本可以加载"); _finish(); return
	var party: Array = ["p_swordsman", "p_ranger", "p_guard"]
	if Npcs.definitions(1).size() != 5:
		check(false, "两名独立居民素材与配置应已加入")
		_finish(); return
	var visible: Array = Npcs.definitions(1, party)
	var visible_ids: Array = []
	for item in visible: visible_ids.append(item.id)
	visible_ids.sort()
	check(visible_ids == ["npc:acheng", "npc:controller", "npc:liang"], "默认出战薄荷与岑照不又站场")
	var story_before := FileAccess.get_sha256("res://data/dialogues.json")
	var case_before := FileAccess.get_sha256("res://data/cases/night_patrol.json")
	var bodies: Dictionary = {}
	for night in range(1, 6):
		var entries: Array = Npcs.definitions(night)
		check(entries.size() == 5, "未指定出战队时两居民加三同伴：%d" % night)
		check(entries == Npcs.definitions(night), "同一夜次对白重载一致：%d" % night)
		var identities: Array = []
		for entry in entries:
			identities.append(entry.get("identity_id", ""))
			check(entry.kind == "npc" and str(entry.id).begins_with("npc:"), "独立NPC交互类型与命名空间")
			check(not str(entry.body).contains("还没看完"), "固定旁白不假设水钵调查尚未完成")
			check(not str(entry.body).is_empty() and str(entry.body).length() <= 160, "NPC对白为简短完整文本")
			check(not entry.has("dialogue") and not entry.has("rewards") and not entry.has("requires"), "旁白不消费主线节点、奖励或解锁条件")
			check(not str(entry.get("source", "")).is_empty(), "原人物设定有来源")
			check(entry.interaction_radius >= 1.2 and entry.interaction_radius <= 2.2, "靠近交互距离有界")
			var p := Vector3(entry.position[0], entry.position[1], entry.position[2])
			check(not Layout.region_at(p).is_empty(), "NPC脚点在真实可走区：" + entry.id)
			check(absf(Layout.surface_height(p) - p.y) < 0.001, "NPC脚点登记高度与地图一致：" + entry.id)
			if not bodies.has(entry.id): bodies[entry.id] = []
			check(not bodies[entry.id].has(entry.body), "五夜各有独立环境对白：" + entry.id)
			bodies[entry.id].append(entry.body)
			if night < 4: check(not str(entry.body).contains("小夜") and not str(entry.body).contains("顾家"), "前三夜旁白不提前揭示小夜身份与顾家旧约")
		identities.sort()
		check(identities == ["acheng", "controller", "guard", "liang", "mint"], "两名独立居民与原同伴；不复制主角、亡灵或敌人")
		entries[0].body = "测试调用方临时改文"
		check(Npcs.definitions(night)[0].body != "测试调用方临时改文", "调用方不能污染后续NPC对白")
	check(Npcs.definitions(0).is_empty() and Npcs.definitions(6).is_empty(), "无效夜次不静默套用别夜对白")
	var geometry := Geometry.build({}); root.add_child(geometry)
	var npcs: Node3D = Npcs.build(1); root.add_child(npcs)
	await physics_frame
	await physics_frame
	check(npcs.name == "ActOneNPCs", "NPC呈现根节点接口")
	check(npcs.get_child_count() == 5, "每名可用NPC均创建真实世界节点")
	check(npcs.find_children("*", "CollisionObject3D", true, false).is_empty(), "NPC不添加碰撞或攻击实体")
	var space := geometry.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new(); capsule.radius = 0.22; capsule.height = 1.4
	var query := PhysicsShapeQueryParameters3D.new(); query.shape = capsule
	for entry in Npcs.definitions(1):
		var actor := npcs.get_node_or_null(str(entry.id).replace(":", "_")) as Node3D
		check(actor != null, "NPC实体与交互id一一对应：" + entry.id)
		if actor == null: continue
		check(actor.position == Vector3(entry.position[0],entry.position[1],entry.position[2]), "可见NPC与交互坐标一致：" + entry.id)
		check(actor.get_meta("interaction_id", "") == entry.id, "实体保存正确交互id")
		var sprite := actor.get_node_or_null("Body") as AnimatedSprite3D
		check(sprite != null and sprite.sprite_frames != null, "NPC以真实高清待机全身显示")
		if sprite == null or sprite.sprite_frames == null: continue
		var reference: Dictionary = REFERENCES[entry.identity_id]
		var texture := sprite.sprite_frames.get_frame_texture("idle", 0)
		var image := texture.get_image()
		check(image.get_pixelv(reference.crown).a >= 0.5 and image.get_pixelv(reference.sole).a >= 0.5, "实测头顶与鞋底确为原PNG不透明像素")
		var ground: float = (texture.get_height() * 0.5 - reference.ground + sprite.offset.y) * sprite.pixel_size
		var crown: float = (texture.get_height() * 0.5 - reference.crown.y + sprite.offset.y) * sprite.pixel_size
		check(absf(ground) < 0.00001, "NPC脚底精确贴角色根地面")
		check(absf(crown - ground - reference.height) < 0.0001, "NPC实测身高符合158/186/166cm")
		check(not sprite.no_depth_test and sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y, "全身人物正确进入3D深度且竖直朝向相机")
		var position: Vector3 = actor.global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(position + Vector3.UP * 0.3, position - Vector3.UP * 0.4))
		check(not hit.is_empty() and absf(hit.position.y - position.y) < 0.035, "NPC真实地面射线贴地：" + entry.id)
		query.transform.origin = position + Vector3.UP * 0.75
		for overlap in space.intersect_shape(query): print("NPC_OVERLAP:", entry.id, ":", overlap.collider.name)
		check(space.intersect_shape(query).is_empty(), "NPC不站在墙/树/植床中：" + entry.id)
		var approaches := 0
		for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			query.transform.origin = position + direction * 1.2 + Vector3.UP * 0.75
			if space.intersect_shape(query).is_empty(): approaches += 1
		check(approaches >= 2, "NPC至少两侧可近身交互且留出路面：" + entry.id)
	for entry in Npcs.definitions(1):
		var portrait: Dictionary = npcs.portrait(entry.id)
		var body: AnimatedSprite3D = npcs.get_node(str(entry.id).replace(":", "_") + "/Body")
		check(portrait.ok and portrait.texture != body.sprite_frames.get_frame_texture("idle", 0), "对话立绘必须独立于地图全身，禁止fallback全身")
		if entry.role == "resident":
			check(str(portrait.get("source_path", "")).ends_with(entry.identity_id + "_half.png"), "居民对话只用专用半身PNG")
			check(portrait.get("framing", "") == "half_body", "居民半身取景有明确契约")
		else:
			check(portrait.texture is AtlasTexture, "同伴交谈沿用主线统一上身取景")
	check(npcs.portrait("npc:missing").get("empty", false), "未知NPC肖像明确清空")
	var original_nodes := npcs.get_children()
	npcs.refresh_night(5)
	check(npcs.get_children() == original_nodes, "夜次更新原位复用NPC实体不重复创建")
	for entry in Npcs.definitions(5):
		var actor: Node = npcs.get_node(str(entry.id).replace(":", "_"))
		check(actor.get_meta("body", "") == entry.body, "实体夜次对白刷新到第五夜")
	npcs.refresh_night(5, party)
	check(npcs.get_child_count() == 3 and npcs.get_node_or_null("npc_mint") == null and npcs.get_node_or_null("npc_guard") == null, "出战变化立即移除同伴实体")
	npcs.refresh_night(5, ["p_controller", "p_healer", "p_mage"])
	check(npcs.get_child_count() == 4 and npcs.get_node_or_null("npc_controller") == null and npcs.get_node_or_null("npc_mint") != null, "换队重新生成未出战同伴")
	check(FileAccess.get_sha256("res://data/dialogues.json") == story_before and FileAccess.get_sha256("res://data/cases/night_patrol.json") == case_before, "NPC查询/生成/更新均不修改原主线文本")
	npcs.free(); geometry.free()
	_finish()
func _finish() -> void:
	print("ACT ONE NPCS: ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
