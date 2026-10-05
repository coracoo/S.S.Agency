# 只导出正式路由已经使用的AtlasTexture参考，不生成或改绘主角资产。
extends SceneTree
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	var output := OS.get_environment("ACT_ONE_OUTPUT")
	if output.is_empty(): quit(2); return
	for identity in ["rinne", "mint", "guard"]:
		var definition := Portraits.load_idle_definition(identity)
		var portrait := Portraits.from_definition(definition, identity, "portrait")
		if not portrait.ok: printerr(portrait); quit(1); return
		var path := output.path_join(identity + "_active_portrait_reference.png")
		if portrait.texture.get_image().save_png(path) != OK: quit(1); return
		print("ACTIVE_PORTRAIT_REFERENCE:", identity, ":", portrait.source_path, ":", portrait.region, ":", path)
	quit()
