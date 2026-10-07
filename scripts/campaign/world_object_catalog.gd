# 环境物品只登记既有地图上的一次性互动；不新增剧情事件、场景或战利品。
extends RefCounted
const TEMPLE_LAYOUT := "act_one_connected_v1"
const SAGA_LAYOUT := "saga_regions_v1"

static func all() -> Array[Dictionary]:
	return [
		_pickup("temple_approach_bundle","参道药包",1,[-6.0,0.03,1.1],"healing_potion",1),
		_pickup("temple_courtyard_bundle","前庭茶包",1,[15.0,2.89,4.0],"energy_tea",1),
		_pickup("temple_mirror_bundle","镜殿净化粉",1,[41.8,2.89,-11.3],"cleansing_powder",1),
		_door("temple_mirror_door","推开镜殿侧门",1,[37.02,2.89,-12.3],PI * .5),
		_pickup("region_2_bundle","晒场行旅药包",2,[-9.35,0.0,6.25],"healing_potion",1),
		_door("region_2_door","推开灯铺木门",2,[2.0,0.0,-7.35]),
		_pickup("region_3_bundle","西仓备用茶包",3,[-12.65,0.0,-7.1],"energy_tea",1),
		_door("region_3_door","推开西仓木门",3,[-14.0,0.0,-8.35]),
		_pickup("region_4_bundle","中庭净化粉",4,[1.4,0.0,5.8],"cleansing_powder",1),
		_door("region_4_door","推开抛光间木门",4,[-14.0,0.0,-8.35]),
		_pickup("region_5_bundle","后院艾灸卷",5,[2.4,0.0,1.2],"moxa_roll",2),
		_door("region_5_door","推开病房木门",5,[-11.0,0.0,-8.35]),
		_pickup("region_6_bundle","前庭应急药包",6,[-5.6,0.0,1.1],"revival_potion",1),
		_door("region_6_door","推开本殿木门",6,[-7.0,0.0,-10.35]),
		_pickup("region_7_bundle","石阶醒神茶",7,[-12.8,0.0,.8],"energy_tea",2),
	]

static func _pickup(id: String, label: String, chapter: int, position: Array, item: String, quantity: int) -> Dictionary:
	return {"id":id,"label":"拾取 · " + label,"kind":"pickup","chapter":chapter,"position":position,"radius":1.5,"item_id":item,"quantity":quantity,"location":id}

static func _door(id: String, label: String, chapter: int, position: Array, yaw: float = 0.0) -> Dictionary:
	return {"id":id,"label":label,"kind":"door","chapter":chapter,"position":position,"radius":1.75,"yaw":yaw,"location":id}

static func get_object(id: String) -> Dictionary:
	for entry in all():
		if entry.id == id: return entry
	return {}

static func belongs_to_night(id: String, night: int) -> bool:
	var entry := get_object(id)
	if entry.is_empty(): return false
	return int(entry.chapter) == (1 if night >= 1 and night <= 5 else night - 4)

static func for_night(night: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in all():
		if belongs_to_night(str(entry.id),night): result.append(entry)
	return result

static func available(night: int, completed: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in for_night(night):
		if not completed.get(entry.id,false): result.append(entry)
	return result

static func validate_saved(value: Variant) -> Array[String]:
	if not value is Dictionary: return ["地图物件状态必须为字典"]
	for id in value:
		if not id is String or get_object(id).is_empty(): return ["未登记的地图物件状态"]
		if not value[id] is bool or value[id] != true: return ["地图物件只记录已完成的真实状态"]
	return []
