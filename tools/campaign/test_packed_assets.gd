# 在独立PCK中通过res://加载原始JSON/PNG，而非读取宿主项目文件。
extends SceneTree
const Bundle = preload("res://scripts/characters/party_asset_bundle.gd")
const Definition = preload("res://scripts/characters/pixel_character_definition.gd")
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1":
		printerr("FAIL: PCK测试须先验证实际隔离user目录")
		quit(1)
		return
	var failures: Array[String] = []
	var frame_count := 0
	for key in Bundle.MANIFESTS:
		var definition: Dictionary = Definition.load_definition(Bundle.MANIFESTS[key])
		if not definition.get("ok", false):
			failures.append(key + ": " + str(definition.get("errors", [])))
			continue
		var manifest: Dictionary = definition.manifest
		var face: Dictionary = Portraits.from_definition(definition, manifest.identity_id, "avatar")
		if not face.ok: failures.append(key + ": " + face.error)
		for animation in manifest.anims.values(): frame_count += animation.frames.size()
		print("PCK_FORM_LOADED:", key, ":", manifest.dir)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rpg/presentation.json"))
	var provenance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/chars/enemies/current/asset_manifest.json"))
	for asset in provenance.assets:
		var path: String = config.enemy_art[asset.enemy_id]
		var bytes := FileAccess.get_file_as_bytes(path)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		var image := Image.new()
		if hash.finish().hex_encode() != asset.sha256 or image.load_png_from_buffer(bytes) != OK or image.get_size() != Vector2i(1024, 1536): failures.append("PCK最终敌图加载/hash失败：" + asset.enemy_id)
		print("PCK_ENEMY_LOADED:", asset.enemy_id, ":", path)
	for failure in failures: printerr("ASSERT FAIL: ", failure)
	print("PACKED PRESENTATION: 7 forms, ", frame_count, " frame references, 6 enemies, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
