# 纯布局契约；由正式隔离运行器执行，不启动 BattleView 或写存档。
extends SceneTree
const Layout = preload("res://scripts/rpg/ui/battle_party_depth_layout.gd")
const Stature = preload("res://scripts/characters/character_stature.gd")
const ACTIONS := ["idle","battle_dash","attack","item","down","hit","defend","recover"]
var failures := 0
var checks := 0

func _initialize() -> void:
	var actors := {
		"p_swordsman":{"actor_id":"p_swordsman","side":"player","identity_id":"rinne","class_id":"swordsman"},
		"p_ranger":{"actor_id":"p_ranger","side":"player","identity_id":"mint","class_id":"ranger"},
		"p_guard":{"actor_id":"p_guard","side":"player","identity_id":"guard","class_id":"guard"}
	}
	var party := ["p_swordsman","p_ranger","p_guard"]
	var original := actors.duplicate(true)
	var plan: Dictionary = Layout.resolve(party,actors)
	_check(plan.ok,"default party resolves")
	_check(plan.feet.p_swordsman == Vector2(1230,720),"rinne front foot")
	_check(plan.feet.p_guard == Vector2(1470,704),"guard second front foot")
	_check(plan.feet.p_ranger == Vector2(1710,644),"mint rear foot")
	_check(party == ["p_swordsman","p_ranger","p_guard"] and actors == original,"party/model data unchanged")
	_check(plan.feet.p_swordsman.y > plan.feet.p_ranger.y and plan.feet.p_guard.y > plan.feet.p_ranger.y,"both melee feet in front of ranger")
	var mirrored: Dictionary = Layout.resolve(party,actors,"left")
	for actor_id in party:
		_check(mirrored.feet[actor_id].x+plan.feet[actor_id].x == 1920.0 and mirrored.feet[actor_id].y == plan.feet[actor_id].y,"mirror once: "+actor_id)
	var reversed: Dictionary = Layout.resolve(["p_guard","p_ranger","p_swordsman"],actors)
	_check(reversed.front == ["p_guard","p_swordsman"] and reversed.rear == ["p_ranger"],"same-role party order remains stable")
	var homura := {"actor_id":"p_mage","side":"player","identity_id":"homura","class_id":"mage","dual_form_version":1,"form_id":"sword"}
	_check(Layout.role_for_actor(homura) == "front","p_mage sword form is melee")
	homura.form_id = "mage"
	_check(Layout.role_for_actor(homura) == "rear","same p_mage mage form is rear")
	_check(not Layout.resolve(["p_guard","p_guard"],actors).ok,"duplicate actor rejected")
	_check(not Layout.resolve(party,actors,"other").ok,"unknown mirror direction rejected")
	var enemy_actors := actors.duplicate(true)
	enemy_actors.p_guard.side = "enemy"
	_check(not Layout.resolve(party,enemy_actors).ok,"enemy cannot enter ally plan")
	_check(not Layout.resolve(party,actors,"right",740,{"p_swordsman":Rect2(0,0,1,1)}).ok,"missing or unsafe full-animation home limits rejected")
	var ids: Array = plan.order
	for left in range(ids.size()):
		for right in range(left+1,ids.size()):
			_check(absf(plan.feet[ids[left]].x-plan.feet[ids[right]].x) >= 220.0,"220px target hotboxes have no shared horizontal area")
	for height in [6.2,4.8]:
		for actor_id in party:
			_check_manifest_home(str(actor_id),str(actors[actor_id].identity_id),plan.feet[actor_id],height)
	_test_three_front(actors)
	_test_three_rear()
	print("PARTY_DEPTH_LAYOUT checks=%d failures=%d" % [checks,failures])
	quit(0 if failures == 0 else 1)

func _check_manifest_home(actor_id: String,identity: String,foot: Vector2,camera_height: float) -> void:
	var limits := _manifest_home_limits(identity,camera_height)
	_check(limits.has_area() and limits.has_point(foot),"full battle / both facing home safe: %s / camera %.1f" % [actor_id,camera_height])

func _test_three_front(base: Dictionary) -> void:
	var actors := base.duplicate(true)
	actors["p_mage"] = {"actor_id":"p_mage","side":"player","identity_id":"homura","class_id":"mage","dual_form_version":1,"form_id":"sword"}
	var party := ["p_swordsman","p_mage","p_guard"]
	var plan: Dictionary = Layout.resolve(party,actors)
	var limits := {"p_swordsman":_manifest_home_limits("rinne",6.2),"p_mage":_manifest_home_limits("homura",6.2),"p_guard":_manifest_home_limits("guard",6.2)}
	var fitted: Dictionary = Layout.fit_home_limits(plan,limits)
	_check(fitted.ok,"three melee can use one common shift")
	if not fitted.ok: return
	_check(fitted.shared_shift_x < -230.0 and fitted.shared_shift_x > -232.0,"three melee worst-case shift about 230.85px")
	for actor_id in party:
		_check(limits[actor_id].has_point(fitted.feet[actor_id]),"three melee complete home safe: "+str(actor_id))
	_check(is_equal_approx(fitted.feet.p_mage.x-fitted.feet.p_swordsman.x,240.0) and is_equal_approx(fitted.feet.p_guard.x-fitted.feet.p_mage.x,240.0),"common shift keeps all three hotboxes separated")
	var mirrored: Dictionary = Layout.fit_home_limits(Layout.resolve(party,actors,"left"),limits)
	_check(mirrored.ok,"three melee mirrored fit")
	if mirrored.ok:
		for actor_id in party: _check(is_equal_approx(mirrored.feet[actor_id].x+fitted.feet[actor_id].x,1920.0),"fit remains mirror symmetric: "+str(actor_id))
	actors.p_mage.form_id = "mage"
	_check(fitted.roles.p_mage == "front" and fitted.slots.p_mage.initial_form_id == "sword","initial role snapshot does not move during later form change")
	var first_actors := base.duplicate(true)
	first_actors["p_mage"] = {"actor_id":"p_mage","side":"player","identity_id":"homura","class_id":"mage","dual_form_version":1,"form_id":"sword"}
	var first_plan: Dictionary = Layout.resolve(["p_mage","p_ranger","p_guard"],first_actors)
	var first_limits := {"p_mage":limits.p_mage,"p_ranger":_manifest_home_limits("mint",6.2),"p_guard":limits.p_guard}
	var homura_first: Dictionary = Layout.fit_home_limits(first_plan,first_limits)
	_check(homura_first.ok and homura_first.feet.get("p_mage",Vector2.INF).y < 712.0,"first melee Homura clamps only safe y for both forms")

func _test_three_rear() -> void:
	var actors := {
		"p_mage":{"actor_id":"p_mage","side":"player","identity_id":"homura","class_id":"mage","dual_form_version":1,"form_id":"mage"},
		"p_healer":{"actor_id":"p_healer","side":"player","identity_id":"healer","class_id":"healer"},
		"p_controller":{"actor_id":"p_controller","side":"player","identity_id":"controller","class_id":"controller"}
	}
	var plan: Dictionary = Layout.resolve(["p_mage","p_healer","p_controller"],actors)
	var fitted: Dictionary = Layout.fit_home_limits(plan,{"p_mage":_manifest_home_limits("homura",6.2),"p_healer":_manifest_home_limits("healer",6.2),"p_controller":_manifest_home_limits("controller",6.2)})
	_check(fitted.ok and fitted.front.is_empty() and fitted.rear.size() == 3,"three rear roles resolved without actor-id heuristics")
	if fitted.ok:
		_check(fitted.feet.p_mage != fitted.feet.p_healer and fitted.feet.p_mage != fitted.feet.p_controller and fitted.feet.p_healer != fitted.feet.p_controller,"three rear feet remain distinct")

func _manifest_home_limits(identity: String,camera_height: float) -> Rect2:
	var forms: Array = ["homura_mage","homura_sword"] if identity == "homura" else [identity]
	var result := Rect2()
	var first := true
	for form in forms:
		var limits := _single_manifest_home_limits(str(form),camera_height)
		if not limits.has_area(): return Rect2()
		result = limits if first else result.intersection(limits)
		first = false
	return result

func _single_manifest_home_limits(identity: String,camera_height: float) -> Rect2:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/chars/pixel/%s/video_actions/manifest.json" % identity))
	if not raw is Dictionary:
		_check(false,"manifest readable: "+identity)
		return Rect2()
	var manifest: Dictionary = raw
	var definition := {"manifest":manifest}
	var anchor := Stature.body_anchor(definition)
	var scale := Stature.world_pixel_size(definition)*Stature.battle_pixels_per_metre()
	var cosine := 11.0/sqrt(121.0+camera_height*camera_height)
	var horizontal := 0.0
	var top := INF
	var bottom := -INF
	for action in ACTIONS:
		for frame in manifest.anims.get(action,{}).get("frames",[]):
			var packed: Dictionary = manifest.packed_frames.get(frame,{})
			if packed.is_empty():
				_check(false,"packed frame exists: "+str(frame))
				return Rect2()
			var x0: float = packed.offset[0]-anchor.x
			var x1: float = packed.offset[0]+packed.region[2]-anchor.x
			horizontal = maxf(horizontal,maxf(absf(x0),absf(x1))*scale/cosine)
			top = minf(top,(float(packed.offset[1])-anchor.y)*scale)
			bottom = maxf(bottom,(float(packed.offset[1])+float(packed.region[3])-anchor.y)*scale)
	var minimum := Vector2(16.0+horizontal,154.0-top)
	var maximum := Vector2(1904.0-horizontal,744.0-bottom)
	return Rect2(minimum,maximum-minimum)

func _check(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
