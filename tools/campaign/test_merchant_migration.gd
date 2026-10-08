# 无等级v1早期检查点进入商人v2，必须保留原字节与全部既有进度。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Store=preload("res://scripts/rpg/save_store.gd")
var assertions:=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	assertions+=1
	if not value:failures.append(message);printerr("FAIL:",message)
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var session:=Session.new();check(session.start_new(true).ok,"创建隔离正式检查点")
	var legacy:Dictionary=session.campaign.safe_snapshot()
	legacy.progression_version=1;legacy.erase("merchant");legacy.erase("merchant_migration")
	legacy.erase("mechanisms");legacy.erase("mechanism_migration")
	var store:=Store.new();var path:=Session.Chapters.SAVE_PATH
	var schema2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/campaign/fixtures/loadout-schema2-chapter7.json"))
	for invalid_ledger in [null,{"version":99,"purchases":[]}]:
		var damaged:Dictionary=schema2.duplicate(true);damaged["merchant"]=invalid_ledger
		check(not store._decode(JSON.stringify(damaged)).ok,"schema2携带未知新账本不能被当合法旧档清空")
	var damaged_source:Dictionary=schema2.duplicate(true);damaged_source["merchant_migration"]={"from_progression_version":1,"source_sha256":"0".repeat(64)}
	check(not store._decode(JSON.stringify(damaged_source)).ok,"schema2不可伪装商人迁移来源")
	check(store.write_safe(legacy,path)==OK,"合法无等级v1仍能被严格读取")
	var original:=FileAccess.get_file_as_bytes(path)
	var result:Dictionary=store.migrate_loadout(path)
	check(result.ok and result.snapshot.get("progression_version")==3,"合法无等级旧检查点迁移到当前版本："+str(result.get("error","")))
	if result.ok and result.snapshot.get("progression_version")==3:
		check(result.snapshot.merchant=={"version":1,"purchases":[]},"首次迁移只加空商人账本")
		var stripped:Dictionary=result.snapshot.duplicate(true)
		stripped.progression_version=1;stripped.erase("merchant");stripped.erase("merchant_migration")
		stripped.erase("mechanisms");stripped.erase("mechanism_migration")
		check(stripped==legacy,"既有装备/卡组/资源/剧情不变，不重新初始化装配")
		check(FileAccess.get_file_as_bytes(result.backup_path)==original,"备份保留无等级v1原字节")
		var once:=FileAccess.get_file_as_bytes(path)
		check(store.migrate_loadout(path).ok and FileAccess.get_file_as_bytes(path)==once,"重复迁移不重写或补发")
		var missing:Dictionary=result.snapshot.duplicate(true);missing.erase("merchant")
		check(not store.validate(missing).is_empty(),"v2不能抹去账本重新补货")
		for invalid in [null,true,"1",[],{}]:
			missing=result.snapshot.duplicate(true);missing.merchant_migration.from_progression_version=invalid
			check(not store._decode(JSON.stringify(missing)).ok,"错类型迁移来源安全拒绝："+str(invalid))
	session.close()
	print("MERCHANT_MIGRATION:",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
