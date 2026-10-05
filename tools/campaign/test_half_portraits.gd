# 对话只显示腰部上身，保持已认可原PNG和战斗/地图全身资源不变。
extends SceneTree
const Portraits = preload("res://scripts/characters/identity_portraits.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("ASSERT FAIL:",label)
func _initialize()->void:
	if OS.get_environment("RPG_TEST_ISOLATED")!="1":quit(2);return
	_run.call_deferred()
func _run()->void:
	for binding in [["rinne","rinne"],["mint","mint"],["guard","guard"],["homura","sword"],["homura","mage"],["healer","healer"],["controller","controller"]]:
		var definition:Dictionary=Portraits.load_idle_definition(binding[0],binding[1])
		var portrait:Dictionary=Portraits.from_definition(definition,binding[0],"portrait")
		check(portrait.ok,"正式上身肖像来源有效:"+binding[0]+binding[1])
		if not portrait.ok:continue
		var key:String=definition.manifest.dir.trim_prefix("res://assets/chars/pixel/").get_slice("/",0)
		var ground:float=Stature._config().forms[key].ground_y_px
		check(portrait.region.end.y<=ground*.55,"对话裁界不能下到腿部:"+key)
		check(is_equal_approx(portrait.region.size.x/portrait.region.size.y,2.0/3.0),"对话保持统一2:3上身取景:"+key)
		check(portrait.texture is AtlasTexture and portrait.texture.atlas==definition.frames.get_frame_texture(&"idle",0),"只调整UI窗口，原人物不重画:"+key)
	print("HALF_PORTRAITS:",checks," assertions, ",failures," failures")
	quit(0 if failures==0 else 1)
