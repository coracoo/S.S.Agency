# 正式schema3新档、跨职业装配、真实战斗和schema2原字节备份迁移。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Store=preload("res://scripts/rpg/save_store.gd")
const Strategy=preload("res://tools/campaign/saga_battle_strategy.gd")
const Forms=preload("res://scripts/rpg/dual_form.gd")
class FaultStore extends "res://scripts/rpg/save_store.gd":
	func _replace_file(_temporary:String,_destination:String)->Error:return ERR_FILE_CANT_WRITE
class BackupFaultStore extends "res://scripts/rpg/save_store.gd":
	func _write_backup_file(path:String,bytes:PackedByteArray)->Error:
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(bytes.slice(0,8));file.close()
		return ERR_FILE_CANT_WRITE
var assertions:=0
var failures:Array[String]=[]
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures.append(message);printerr("FAIL: ",message)
func _initialize()->void:_run.call_deferred()
func _run()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	var session:=Session.new()
	check(session.start_new(true,["guard","mage","healer"]).ok,"正式新游戏可建立")
	var initial:Dictionary=session.campaign.safe_snapshot()
	check(initial.get("schema_version")==3,"正式入口必须实际使用无等级schema3")
	if initial.get("schema_version")!=3:session.close();_finish();return
	check(not initial.has("level") and not initial.has("xp"),"正式存档没有隐藏等级或经验")
	check(initial.roster.values().all(func(actor):return actor.has("build") and not actor.has("level") and not actor.has("xp")),"六个角色都使用无等级构筑")
	for malformed_version in [null,true,"2",[],{}]:
		var malformed_migration:Dictionary=initial.duplicate(true)
		malformed_migration.migration={"from_schema":malformed_version,"source_sha256":"0".repeat(64)}
		check(not Store.new()._decode(JSON.stringify(malformed_migration)).ok,"坏迁移来源版本安全拒绝："+str(malformed_version))
	var incomplete:Dictionary=initial.duplicate(true);incomplete.erase("gear")
	check(not Store.new()._decode(JSON.stringify(incomplete)).ok,"schema3缺装备库存不能被旧迁移默认补出")
	incomplete=initial.duplicate(true);incomplete.inventory.erase("healing_potion")
	check(not Store.new()._decode(JSON.stringify(incomplete)).ok,"schema3缺道具条目不能通过重读恢复初始库存")
	incomplete=initial.duplicate(true);incomplete.world.erase("map_layout");incomplete.world_history.night_1.erase("map_layout")
	check(not Store.new()._decode(JSON.stringify(incomplete)).ok,"schema3缺地图标记不能偷偷采用旧坐标迁移")
	check(not session.campaign.preview_loadout("p_guard",initial.roster.p_guard.build,{"weapon":12}).ok,"非法装备类型预览安全返回错误")
	for malformed in [null,[],{"version":1,"active":[],"passive":[]}]:
		var actor:Dictionary=initial.roster.p_mage.duplicate(true);actor.build=malformed
		check(not Forms.validate(actor,session.campaign._catalog).is_empty(),"坏焰华构筑返回错误而不是异常")
		check(Forms.available_skills(actor,session.campaign._catalog).is_empty(),"坏焰华构筑不暴露伪卡表")
	var draft:Dictionary=initial.roster.p_guard.build.duplicate(true)
	draft.active.default=["heavy_slash","cover"]
	draft.passive=["light_step"]
	var preview:Dictionary=session.campaign.preview_loadout("p_guard",draft)
	check(preview.ok and preview.stats.spd==initial.roster.p_guard.stats.spd+3,"跨职业和被动速度/防御取舍可预览")
	check(session.campaign.safe_snapshot()==initial,"装配预览不写模型和存档")
	check(session.campaign.set_loadout("p_guard",draft).ok,"合法跨职业构筑原子保存")
	var prepared:Dictionary=session.campaign.safe_snapshot()
	check(prepared.roster.p_guard.skill_ids==["heavy_slash","cover"] and prepared.cards==initial.cards,"已装技能成为实际卡位，收藏不被消耗")
	draft.active.default=["firebolt"]
	check(not session.campaign.set_loadout("p_guard",draft).ok and session.campaign.safe_snapshot()==prepared,"武器不符拒绝且库存/状态不变")
	draft=prepared.roster.p_guard.build.duplicate(true);draft.passive=["force_channel"]
	check(not session.campaign.set_loadout("p_guard",draft).ok,"没有收藏的被动不可装备")
	for event in ["dialogue:a1","dialogue:r1","dialogue:h1"]:check(session.commit_event(session.campaign.safe_snapshot().world,event).ok,"真实进战前置："+event)
	var started:Dictionary=session.begin_encounter(session.campaign.safe_snapshot().world,"basin_reflection")
	check(started.ok and started.has("rewards") and not started.has("xp"),"战前承诺使用明确奖励而非经验")
	if started.ok:
		var engine:RefCounted=session.router.create_engine()
		check(engine!=null and engine.snapshot().actors.values().all(func(actor):return not actor.has("level")),"真实战斗玩家及敌人均无等级字段")
		var commands:=0
		while engine!=null and engine.snapshot().outcome.is_empty() and commands<180:
			engine.advance()
			var state:Dictionary=engine.snapshot()
			if state.outcome.is_empty() and state.phase=="action_selection":
				var command:Dictionary=Strategy.choose(state,engine,session.campaign._catalog)
				if command.is_empty():break
				var accepted:Dictionary=engine.submit(command)
				if not accepted.accepted:break
				commands+=1
		var result:Dictionary=session.router.result_from_engine()
		check(result.get("outcome")=="victory", "无等级跨职业队伍以合法指令完成首战")
		if result.get("outcome")=="victory":
			check(session.router.finish(result).ok,"真实战果保存")
			var after:Dictionary=session.campaign.safe_snapshot()
			check(after.roster.p_guard.stats==prepared.roster.p_guard.stats and not after.has("xp"),"胜利不通过隐藏等级增长属性")
			check(session.router.finish(result).ok and session.campaign.safe_snapshot()==after,"重复交付不重复奖励")
		print("LOADOUT_REAL_BATTLE_COMMANDS:",commands)
	session.close()
	_test_migration()
	_finish()
func _test_migration()->void:
	var path:=Session.Chapters.SAVE_PATH
	var legacy:=FileAccess.get_file_as_bytes("res://tools/campaign/fixtures/loadout-schema2-chapter7.json")
	check(not legacy.is_empty(),"迁移使用既有真实隔离七章检查点")
	if legacy.is_empty():return
	# 同一隔离runner可先运行其他迁移测试；给本次故障注入唯一合法JSON空白，
	# 避免前一组的完整同哈希备份让写备份步骤被幂等跳过。剧情数据保持原样。
	var whitespace:="\n"
	for marker in Crypto.new().generate_random_bytes(16):whitespace+="\t".repeat(int(marker)+1)+"\n"
	legacy.append_array(whitespace.to_utf8_buffer())
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(legacy);file.close()
	var final_backup:=path+".schema2-"+FileAccess.get_sha256(path).substr(0,12)+".bak"
	var backup_fault:=BackupFaultStore.new()
	var interrupted:Dictionary=backup_fault.migrate_loadout(path)
	check(not interrupted.ok and FileAccess.get_file_as_bytes(path)==legacy,"备份写入中断保留原档")
	check(not FileAccess.file_exists(final_backup),"半成品备份不会占用最终哈希文件名")
	if interrupted.ok:
		file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(legacy);file.close()
	var fault:=FaultStore.new()
	var failed:Dictionary=fault.migrate_loadout(path)
	check(not failed.ok and FileAccess.get_file_as_bytes(path)==legacy,"原子替换失败保留旧档原字节")
	var migrated:Dictionary=Store.new().migrate_loadout(path)
	check(migrated.ok,"合法后章schema2真实档升级成功")
	if not migrated.ok:return
	var old:Dictionary=Store.new()._decode(legacy.get_string_from_utf8()).snapshot
	var current:Dictionary=migrated.snapshot
	check(current.schema_version==3 and not current.has("level") and not current.has("xp"),"迁移后正式模型没有等级/经验")
	check(current.saga==old.saga and current.world==old.world and current.applied_battle_ids==old.applied_battle_ids,"迁移保留剧情、银钱、交易、导航和战果事实")
	check(FileAccess.get_file_as_bytes(migrated.backup_path)==legacy,"备份逐字节等于合法原档")
	var again:Dictionary=Store.new().migrate_loadout(path)
	check(again.ok and again.snapshot==current,"重复加载不重复授卡或补装备")
	var valid_bytes:=FileAccess.get_file_as_bytes(path)
	file=FileAccess.open(path,FileAccess.WRITE);file.store_string("{corrupt");file.close()
	check(not Store.new().migrate_loadout(path).ok and FileAccess.get_file_as_string(path)=="{corrupt","损坏旧档保持原样不迁移")
	# 只恢复本测试在已核验临时user://内构造的坏夹具，供同一门禁后续用例正常创建新档。
	file=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(valid_bytes);file.close()
func _finish()->void:
	print("LOADOUT_CAMPAIGN: %d assertions, %d failures"%[assertions,failures.size()])
	quit(1 if not failures.is_empty() else 0)
