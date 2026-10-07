# 神秘商人真实保存事务；剧情进度使用标记明确的夹具，不能声称自然通关。
extends SceneTree
const Session=preload("res://scripts/campaign/chapter_session.gd")
const Store=preload("res://scripts/rpg/save_store.gd")
const Fixture=preload("res://tools/campaign/saga_transaction_fixture.gd")
class FaultStore extends "res://scripts/rpg/save_store.gd":
	func _replace_file(_temporary:String,_destination:String)->Error:return ERR_FILE_CANT_WRITE
var assertions:=0
var failures:Array[String]=[]
func check(value:bool,message:String)->void:
	assertions+=1
	if not value:failures.append(message);printerr("FAIL:",message)
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	_run.call_deferred()
func _run()->void:
	var session:=Session.new()
	check(session.campaign.has_method("buy_merchant_item"),"正式模型存在唯一商人交易入口")
	if not session.campaign.has_method("buy_merchant_item"):session.close();_finish();return
	check(Fixture.enter_saga(session),"经首章事务夹具进入第二章")
	var model:RefCounted=session.campaign
	var merchant=load("res://scripts/campaign/merchant_catalog.gd")
	check(model.safe_snapshot().get("merchant")==merchant.initial(),"正式新档建立空全局库存账本")
	var before:Dictionary=model.safe_snapshot()
	check(not model.call("buy_merchant_item",before.world,"gear_iron_amulet_v1",1).ok and model.safe_snapshot()==before,"未到安全窗口不可远程购买")
	check(Fixture.through(session,"C2-13"),"真实模型完成C2-13安全前置")
	before=model.safe_snapshot()
	check(merchant.presence(before),"第二章危机解除后商人出现")
	var world:Dictionary=before.world.duplicate(true)
	var point:Vector3=merchant.anchor(before);world.position=[point.x,point.y,point.z]
	var far:Dictionary=world.duplicate(true);far.position[0]+=6
	check(not model.call("buy_merchant_item",far,"gear_iron_amulet_v1",1).ok and model.safe_snapshot()==before,"远离摊位不允许购买且不写档")
	check(not model.call("buy_merchant_item",world,"gear_iron_amulet_v1",2).ok and model.safe_snapshot()==before,"超过全球库存拒绝")
	for bad_count in [1.5,true]:
		check(not model.call("buy_merchant_item",world,"gear_iron_amulet_v1",bad_count).ok and model.safe_snapshot()==before,"模型接口不把错类型数量截断为一件："+str(bad_count))
	check(not model.call("buy_merchant_item",world,"card_force_channel_v1",1).ok and model.safe_snapshot()==before,"未解锁后章被动不能偷买")
	var original_bytes:=FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH)
	var original_store:RefCounted=model._store;model._store=FaultStore.new(model._catalog)
	check(not model.call("buy_merchant_item",world,"gear_iron_amulet_v1",1).ok,"写盘失败明确返回")
	check(model.safe_snapshot()==before and FileAccess.get_file_as_bytes(Session.Chapters.SAVE_PATH)==original_bytes,"写盘失败钱/装备/库存/文件全部不变")
	model._store=original_store
	var bought:Dictionary=model.call("buy_merchant_item",world,"gear_iron_amulet_v1",1)
	check(bought.ok,"真实购买成功："+str(bought.get("error","")))
	if not bought.ok:session.close();_finish();return
	var after:Dictionary=model.safe_snapshot()
	check(after.saga.coins==before.saga.coins-80 and after.gear.iron_amulet==int(before.gear.get("iron_amulet",0))+1,"按真实目录扣款并入库")
	check(after.merchant.purchases.size()==1 and merchant.spent(after)==80,"商品扣款进入唯一全局账本")
	check(Store.new().validate(after).is_empty(),"含商人交易的正式档严格合法")
	check(not model.call("buy_merchant_item",after.world,"gear_iron_amulet_v1",1).ok and model.safe_snapshot()==after,"重发购买不复制限量商品")
	check(model.rest().ok and model.safe_snapshot().merchant==after.merchant,"休息不重置商人库存")
	var reloaded:=Session.new()
	check(reloaded.resume().ok and reloaded.campaign.safe_snapshot()==model.safe_snapshot(),"整数JSON重读保留钱和库存")
	session=reloaded;model=session.campaign
	check(Fixture.through(session,"C3-08"),"进入第三章商人窗口的真实事务")
	var revisited:Dictionary=model.safe_snapshot()
	check(merchant.presence(revisited),"第三章实际地点显示同一商人")
	var sold:Array=merchant.offers(revisited,model._catalog).filter(func(row):return row.id=="gear_iron_amulet_v1")
	check(sold.size()==1 and sold[0].stock==0,"跨章货架保持第二章已售状态")
	var invalid:Dictionary=revisited.duplicate(true);invalid.merchant.purchases[0].unit_price=1
	check(not Store.new().validate(invalid).is_empty(),"伪造价格拒绝")
	invalid=revisited.duplicate(true);invalid.erase("merchant")
	check(not Store.new()._decode(JSON.stringify(invalid)).ok,"缺账本不可通过读档刷新全球库存")
	invalid=revisited.duplicate(true);invalid.merchant.purchases[0].quantity=true
	check(not Store.new()._decode(JSON.stringify(invalid)).ok,"账本错类型安全拒绝")
	session.close();_finish()
func _finish()->void:
	print("MERCHANT_TRANSACTIONS:",assertions," assertions, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
