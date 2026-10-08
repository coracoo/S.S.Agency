# 新机关版本的合法旧档迁移；只操作Python核验的隔离user目录。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Store=preload("res://scripts/rpg/save_store.gd")
class FaultStore extends "res://scripts/rpg/save_store.gd":
	func _replace_file(_temporary:String,_destination:String)->Error:return ERR_FILE_CANT_WRITE
var assertions:=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	assertions+=1
	if not value:failures.append(message);printerr("FAIL:",message)
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var session:=Session.new();check(session.start_new(true).ok,"创建隔离正式源")
	var store:=Store.new();var path:=Session.Chapters.SAVE_PATH
	var legacy:Dictionary=session.campaign.safe_snapshot()
	legacy.progression_version=2;legacy.erase("mechanisms");legacy.erase("mechanism_migration")
	check(store.write_safe(legacy,path)==OK,"合法商人v2旧检查点可完整验证")
	var bytes:=FileAccess.get_file_as_bytes(path)
	var failed:Dictionary=FaultStore.new().migrate_loadout(path)
	check(not failed.ok and FileAccess.get_file_as_bytes(path)==bytes,"升级替换失败保持原v2文件")
	var migrated:Dictionary=store.migrate_loadout(path)
	check(migrated.ok and migrated.snapshot.get("progression_version")==3,"商人v2合法升级到地图机关v3")
	if migrated.ok and migrated.snapshot.get("progression_version")==3:
		check(FileAccess.get_file_as_bytes(migrated.backup_path)==bytes,"完整保留原字节备份")
		var stripped:Dictionary=migrated.snapshot.duplicate(true)
		stripped.progression_version=2;stripped.erase("mechanisms");stripped.erase("mechanism_migration")
		check(stripped==legacy,"地图版本迁移不重发卡/装备/金钱或修改角色")
		check(migrated.snapshot.mechanisms.history.is_empty(),"新局旧检查点没有虚构物理操作历史")
		var current_bytes:=FileAccess.get_file_as_bytes(path)
		check(store.migrate_loadout(path).ok and FileAccess.get_file_as_bytes(path)==current_bytes,"重复继续不重新迁移")
		for malformed in [null,true,"2",[],{}]:
			var invalid:Dictionary=migrated.snapshot.duplicate(true)
			invalid.mechanism_migration.from_progression_version=malformed
			check(not store._decode(JSON.stringify(invalid)).ok,"错类型迁移来源安全拒绝："+str(malformed))
		var invalid:Dictionary=migrated.snapshot.duplicate(true);invalid.erase("mechanisms")
		check(not store._decode(JSON.stringify(invalid)).ok,"新版本丢失机关状态不可静默重置")
		invalid=legacy.duplicate(true);invalid["mechanisms"]={"version":99}
		check(not store._decode(JSON.stringify(invalid)).ok,"旧v2不能携带未知新机关状态被清空")
		var old_two:=FileAccess.get_file_as_bytes("res://tools/campaign/fixtures/loadout-schema2-chapter7.json")
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(old_two);file.close()
		var full:Dictionary=store.migrate_loadout(path)
		check(full.ok and full.snapshot.progression_version==3,"真实旧schema2可一次迁到当前版本")
		if full.ok:
			check(full.snapshot.mechanisms.history.is_empty(),"旧章七投影历史完成而不伪造操作")
			check(full.snapshot.mechanisms.legacy.events==full.snapshot.saga.events.size(),"投影明确记录迁移时的历史前缀")
			check(full.snapshot.mechanisms.states.ferry.complete==full.snapshot.saga.flags.ferry_repaired,"旧渡是否已修只由真实完成事实决定")
			check(full.snapshot.mechanisms.states.alley.complete==full.snapshot.saga.flags.alley_rescued,"旧后巷救援是否完成保持真实事实")
	session.close()
	print("MECHANISM_MIGRATION:",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
