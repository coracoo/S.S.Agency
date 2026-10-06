extends SceneTree
const Kit = preload("res://scripts/rpg/ui/ui_kit.gd")
var failures: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(2); return
	if not ResourceLoader.exists("res://scripts/rpg/ui/saga_enemy_art.gd"): failures.append("后章敌人必须有独立原图登记加载器")
	var root_node := Node2D.new(); root.add_child(root_node)
	var host := Kit.actor_sprite(root_node, "res://assets/chars/npcs/act_one/liang_world.png", 180.0, false, {"region":[0,0,100,200],"anchor":[50,190],"content_height_px":180})
	var sprite := host.get_child(0) as Sprite2D
	if sprite == null or not sprite.texture is AtlasTexture: failures.append("敌图图集必须按登记区域显示，不能露出相邻敌人")
	elif sprite.texture.get_size() != Vector2(100,200): failures.append("图集尺寸不符")
	if sprite != null and not sprite.offset.is_equal_approx(Vector2(0,-90)): failures.append("脚锚必须使用图集区域内局部坐标")
	root_node.free()
	for failure in failures: printerr("FAIL: ", failure)
	print("SAGA_ENEMY_ART: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
