extends SceneTree
const Presenter = preload("res://scripts/rpg/ui/battle_presenter.gd")
const Catalog = preload("res://scripts/rpg/catalog.gd")
var failures: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("RPG_TEST_ISOLATED") != "1": quit(1); return
	var title_source := FileAccess.get_file_as_string("res://scripts/campaign/title.gd")
	if not title_source.contains("当前七章主线进度"): failures.append("覆盖正式档前必须明确会替换全部七章进度")
	var catalog := Catalog.new()
	var errors := catalog.load_all()
	if not errors.is_empty(): failures.append("目录：" + "；".join(errors))
	var event := {"type": "saga_recoil_blocked", "actor_id": "", "target_id": "", "payload": {"text": "先清开出口，再断镜线。"}}
	if Presenter.event_line(event, {"actors": {}}, catalog) != event.payload.text: failures.append("战斗机制反馈必须进入正式战报")
	var reflected := {"effects": [{"type":"saga_reflected", "actor_id":"mirror", "target_id":"p_mage", "payload":{"damage":25,"normal":25,"critical_damage":38,"text":"反射"}}]}
	var preview_state := {"actors":{"p_mage":{"actor_id":"p_mage","class_id":"mage","side":"player","identity_id":"homura","hp":20}}}
	var preview: Array[String] = Presenter.preview_lines(reflected, preview_state, catalog)
	if not "\n".join(preview).contains("反射") or not "\n".join(preview).contains("25"): failures.append("指令预览必须显示反射造成的自身伤害")
	var presenter = Presenter.new()
	if not presenter.has_method("queue_name"): failures.append("行动顺序必须保留敌方姓名而不是只显示编号")
	else:
		var actor := {"actor_id":"e_01_saga_borrowed_voice","class_id":"saga_borrowed_voice","side":"enemy"}
		if presenter.call("queue_name", actor, catalog) != "借声客": failures.append("新首领行动顺序姓名错误")
	if not presenter.has_method("sprite_id"): failures.append("新敌人须明确复用已交付sprite_id")
	else:
		for enemy in catalog.get_all("enemies"):
			if enemy.has("sprite_id") and presenter.call("sprite_id", enemy.id, catalog) != enemy.sprite_id: failures.append("敌图映射不符：" + enemy.id)
	for failure in failures: printerr("FAIL: ", failure)
	print("SAGA_PRESENTATION_CHECKS: ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
