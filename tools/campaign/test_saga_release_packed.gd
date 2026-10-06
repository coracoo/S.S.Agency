# 此探针从包外执行；生产路径只由正式PCK提供，不打包测试助手或开发正文。
extends SceneTree
const Saga = preload("res://scripts/campaign/saga_catalog.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
const Region = preload("res://scripts/campaign/saga_world.gd")
var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("ASSERT FAIL: ", message)

func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: 七章PCK检查须先核验实际隔离user目录")
		quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var catalog := Catalog.new()
	check(catalog.load_all().is_empty(), "包内权威战斗目录可完整读取")
	var data := Saga.data()
	check(data.get("chapters", []).size() == 6, "包内必须保留第二至第七章动态正文")
	var scene_count := 0
	for chapter in data.get("chapters", []):
		scene_count += chapter.get("scenes", []).size()
		check(int(chapter.id) >= 2 and int(chapter.id) <= 7, "动态章节编号有效")
	check(scene_count == 137, "包内必须保留137场批准正文")
	for path in ["res://data/rpg/saga_enemies.json", "res://data/rpg/saga_encounters.json"]:
		check(FileAccess.file_exists(path), "包内保留新增动态数据：" + path)
		if not FileAccess.file_exists(path): continue
		var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(document is Dictionary and document.get("definitions", []).size() > 0, "动态数据可解析：" + path)
		if not document is Dictionary: continue
		if path.ends_with("saga_encounters.json"):
			check(document.definitions.size() == 26, "包内必须登记26场真实遭遇")
			for entry in document.definitions:
				check(not catalog.get_definition("encounters", str(entry.id)).is_empty(), "权威目录含新增遭遇：" + str(entry.id))
	for name in ["saga_stage", "saga_ending", "saga_catalog", "saga_progress", "saga_route_rules", "saga_save_rules", "saga_world", "saga_battle_narrator"]:
		check(ResourceLoader.exists("res://scripts/campaign/" + name + ".gd"), "七章生产脚本已发包：" + name)
	check(ResourceLoader.exists("res://scripts/rpg/saga_boss_rules.gd"), "七章战斗机制已发包")
	_check_npc_sheets()
	_check_enemy_sheets()
	for path in [Saga.SCENE_PATH, Saga.ENDING_PATH]:
		var packed: PackedScene = load(path)
		check(packed != null, "包内新生产场景可加载：" + path)
		if packed == null: continue
		var instance := packed.instantiate()
		check(instance != null and instance.get_script() != null, "包内新生产场景脚本可实例化：" + path)
		if instance != null: instance.free()
	for chapter in range(2, 8):
		var world: Node3D = Region.build(chapter)
		check(world.get_node_or_null("PermanentCollision") != null, "后六章实际地图含持续碰撞：" + str(chapter))
		check(world.get_node_or_null(Region.LANDMARKS[chapter]) != null, "后六章实际地图含地区美术：" + str(chapter))
		check(not Region.anchors(chapter).is_empty(), "后六章动态位置登记可加载：" + str(chapter))
		print("PCK_SAGA_REGION_BUILT:", chapter, ":", world.get_child_count())
		world.free()
	for path in ["res://tools/campaign/test_saga_state.gd", "res://tools/campaign/saga_battle_strategy.gd", "res://docs/campaign/README.md"]:
		check(not FileAccess.file_exists(path) and not ResourceLoader.exists(path), "测试助手和开发说明不得发包：" + path)
	print("PCK_SAGA_RELEASE: 6 regions, ", scene_count, " scenes, ", assertions, " assertions, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _check_npc_sheets() -> void:
	check(ResourceLoader.exists("res://scripts/campaign/saga_npc_art.gd"), "正式包必须包含新增居民的生产loader")
	if not ResourceLoader.exists("res://scripts/campaign/saga_npc_art.gd"): return
	var path := "res://assets/chars/npcs/saga/asset_manifest.json"
	check(FileAccess.file_exists(path), "NPC生产loader的动态manifest必须保留原字节")
	if not FileAccess.file_exists(path): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(manifest is Dictionary and manifest.get("characters") is Dictionary, "NPC动态manifest格式有效")
	if not manifest is Dictionary or not manifest.get("characters") is Dictionary: return
	for speaker in ["乔伯", "吴济", "姚芹", "孟衡", "宋婆", "方澄", "方素", "李茂", "杜平", "杜应", "沈烛舟", "罗婶", "罗苇", "许成", "许照漪", "赵医工", "邱安", "阿杏", "阿柳", "陆芸", "陈樵", "陈葵", "陶婶"]:
		check(manifest.characters.has(speaker), "正式包必须包含已批准的剧情NPC：" + speaker)
	var images: Dictionary = {}
	for speaker in manifest.characters:
		var row: Dictionary = manifest.characters[speaker]
		var sheet := str(row.get("sheet", ""))
		if not images.has(sheet):
			var png := Image.new()
			var loaded := png.load_png_from_buffer(FileAccess.get_file_as_bytes(sheet)) == OK
			check(loaded, "包内NPC图集可从原始PNG解码：" + sheet)
			if not loaded: continue
			images[sheet] = png
		var image: Image = images[sheet]
		check(_source_hash(sheet) == str(row.get("generation", {}).get("sha256", "")), "NPC原图与来源声明SHA256一致：" + str(speaker))
		for field in ["world_region", "portrait_region"]:
			var region: Array = row.get(field, [])
			check(region.size() == 4, "NPC裁图边界齐全：" + str(speaker) + ":" + field)
			if region.size() != 4: continue
			var rect := Rect2i(int(region[0]), int(region[1]), int(region[2]), int(region[3]))
			check(rect.size.x > 0 and rect.size.y > 0 and Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect), "NPC裁图完整位于图集内：" + str(speaker) + ":" + field)
	print("PCK_SAGA_NPC_ART:", manifest.characters.size(), " characters, ", images.size(), " raw sheets")

func _source_hash(path: String) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(FileAccess.get_file_as_bytes(path))
	return hash.finish().hex_encode()

func _check_enemy_sheets() -> void:
	check(ResourceLoader.exists("res://scripts/rpg/ui/saga_enemy_art.gd"), "正式包必须包含后六章专属敌图的生产loader")
	if not ResourceLoader.exists("res://scripts/rpg/ui/saga_enemy_art.gd"): return
	var path := "res://assets/chars/enemies/saga/asset_manifest.json"
	check(FileAccess.file_exists(path), "专属敌图动态manifest必须保留原字节")
	if not FileAccess.file_exists(path): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(manifest is Dictionary and manifest.get("enemies") is Dictionary, "专属敌图manifest格式有效")
	if not manifest is Dictionary or not manifest.get("enemies") is Dictionary: return
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/saga_enemies.json"))
	check(manifest.enemies.size() == 15 and definitions.definitions.size() == 15, "正式包必须齐全保留15类后六章专属敌图")
	var images: Dictionary = {}
	for definition in definitions.definitions:
		var id := str(definition.id)
		check(manifest.enemies.has(id), "专属敌图覆盖实际战斗ID：" + id)
		if not manifest.enemies.has(id): continue
		var row: Dictionary = manifest.enemies[id]
		var sheet := str(row.get("sheet", ""))
		if not images.has(sheet):
			var png := Image.new()
			var loaded := png.load_png_from_buffer(FileAccess.get_file_as_bytes(sheet)) == OK
			check(loaded, "专属敌图可从原始PNG解码：" + sheet)
			if not loaded: continue
			images[sheet] = png
		var image: Image = images[sheet]
		check(_source_hash(sheet) == str(row.get("source", {}).get("sha256", "")), "专属敌图与来源声明SHA256一致：" + id)
		var region: Array = row.get("region", [])
		check(region.size() == 4, "专属敌图裁框齐全：" + id)
		if region.size() != 4: continue
		var rect := Rect2i(int(region[0]), int(region[1]), int(region[2]), int(region[3]))
		check(rect.size.x > 0 and rect.size.y > 0 and Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect), "专属敌图裁框位于图集内：" + id)
		var anchor: Array = row.get("anchor", [])
		check(anchor.size() == 2 and float(anchor[0]) >= 0 and float(anchor[0]) <= rect.size.x and float(anchor[1]) >= 0 and float(anchor[1]) <= rect.size.y, "专属敌图脚点位于本地裁框内：" + id)
		check(float(row.get("content_height_px", 0)) > 0 and float(row.get("content_height_px", 0)) <= rect.size.y, "专属敌图可见身高有效：" + id)
		check(str(row.get("facing", "")) == "right", "专属敌图保留当前战斗右向约定：" + id)
	print("PCK_SAGA_ENEMY_ART:", manifest.enemies.size(), " enemies, ", images.size(), " raw sheets")
