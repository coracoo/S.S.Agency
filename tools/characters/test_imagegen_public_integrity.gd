# 用隔离目录中的真实文件验证运行清单与图集防篡改，不修改项目登记。
extends SceneTree
const Loader = preload("res://scripts/rpg/ui/imagegen_effect_manifest.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value)); file.close()
func reason(result: Dictionary, expected: String) -> bool:
	return not result.get("ok", false) and result.get("reason", "") == expected
func _run() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var registry: Dictionary = Loader._json(Loader.REGISTRY)
	check(registry.get("schema_version") == 2, "公开registry明确版本2")
	check(Loader.load_effect("firebolt", Loader.REGISTRY, true).ok, "正确运行清单可显式预览")
	var old := registry.duplicate(true); old.schema_version = 1
	write_json("user://old_registry.json", old)
	check(reason(Loader.load_effect("firebolt", "user://old_registry.json", true), "invalid_registry"), "拒绝旧registry合同")
	var changed := registry.duplicate(true)
	changed.effects.firebolt.manifest_sha256 = "changed"
	write_json("user://wrong_hash.json", changed)
	check(reason(Loader.load_effect("firebolt", "user://wrong_hash.json", true), "receipt_mismatch"), "错误manifest SHA被拒绝")
	changed = registry.duplicate(true)
	var manifest: Dictionary = Loader._json(changed.effects.firebolt.manifest)
	manifest.frames[0].nominal_duration_ms += 1
	write_json("user://changed_manifest.json", manifest)
	changed.effects.firebolt.manifest = "user://changed_manifest.json"
	write_json("user://changed_registry.json", changed)
	check(reason(Loader.load_effect("firebolt", "user://changed_registry.json", true), "receipt_mismatch"), "帧时长篡改被拒绝")
	changed = registry.duplicate(true)
	changed.asset_root = "user://"
	DirAccess.make_dir_recursive_absolute("user://firebolt")
	var atlas := FileAccess.open("user://firebolt/firebolt-atlas-runtime-256.png", FileAccess.WRITE)
	atlas.store_string("changed atlas bytes"); atlas.close()
	write_json("user://changed_atlas_registry.json", changed)
	check(reason(Loader.load_effect("firebolt", "user://changed_atlas_registry.json", true), "atlas_hash_mismatch"), "图集原字节篡改被拒绝")
	changed = registry.duplicate(true); changed.production_renderer_enabled = true
	write_json("user://pending_registry.json", changed)
	check(reason(Loader.load_effect("firebolt", "user://pending_registry.json"), "gameplay_qa_pending"), "游戏验收门禁独立保留")
	changed = registry.duplicate(true); changed.effects.firebolt.approved_for_runtime = false
	write_json("user://unapproved_registry.json", changed)
	check(reason(Loader.load_effect("firebolt", "user://unapproved_registry.json", true), "art_unapproved"), "未批准素材在预览也不能载入")
	check(reason(Loader.load_effect("firebolt"), "production_disabled"), "原生产开关始终关闭")
	print("IMAGEGEN_PUBLIC_INTEGRITY: %d assertions, %d failures" % [checks, failures])
	quit(1 if failures else 0)
