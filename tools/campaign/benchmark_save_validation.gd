# 同一旧章七检查点的保存校验成本对照；只读内存，不写真实玩家存档。
extends SceneTree
const Store=preload("res://scripts/rpg/save_store.gd")
const Merchant=preload("res://scripts/campaign/merchant_catalog.gd")
var failures:Array[String]=[]
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var store:=Store.new()
	var decoded:Dictionary=store._decode(FileAccess.get_file_as_string("res://tools/campaign/fixtures/loadout-schema2-chapter7.json"))
	if not decoded.ok:printerr(decoded.error);quit(1);return
	var latest:Dictionary=store._upgrade_loadout(decoded.snapshot,FileAccess.get_sha256("res://tools/campaign/fixtures/loadout-schema2-chapter7.json"))
	var baseline:Dictionary=latest.duplicate(true)
	baseline.progression_version=1;baseline.erase("merchant");baseline.erase("merchant_migration");baseline.erase("mechanisms");baseline.erase("mechanism_migration")
	for title in ["without_merchant","current"]:
		var sample:Dictionary=baseline if title=="without_merchant" else latest
		var samples:Array[float]=[]
		for attempt in 21:
			var start:=Time.get_ticks_usec();var errors:=store.validate(sample)
			var elapsed:=float(Time.get_ticks_usec()-start)/1000.0
			if not errors.is_empty():failures.append("；".join(errors));break
			if attempt>0:samples.append(elapsed)
		if not samples.is_empty():
			samples.sort();print("SAVE_VALIDATION_COST:",JSON.stringify({"case":title,"events":sample.saga.events.size(),"samples":samples.size(),"median_ms":samples[samples.size()/2],"min_ms":samples[0],"max_ms":samples[-1]}))
	var start:=Time.get_ticks_usec()
	for attempt in 20:
		var errors:=Merchant.validate(latest,store._catalog)
		if not errors.is_empty():failures.append("；".join(errors))
	print("MERCHANT_VALIDATION_MEAN_MS:",float(Time.get_ticks_usec()-start)/20000.0)
	for failure in failures:printerr("FAIL:",failure)
	quit(0 if failures.is_empty() else 1)
