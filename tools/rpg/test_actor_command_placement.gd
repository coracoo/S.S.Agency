# 纯几何契约：不创建场景、不读取模型、不写玩家资料。
extends RefCounted
const Placement = preload("res://scripts/rpg/ui/actor_command_placement.gd")
const AREA := Rect2(24,116,1872,868)
const DESIRED := Vector2(480,560)
const COMPACT := Vector2(1872,172)
static var assertion_count := 0

static func run() -> Array[String]:
	assertion_count = 0
	var failures: Array[String] = []
	_test_three_anchors(failures)
	_test_wide_boss(failures)
	_test_above_opening(failures)
	_test_screen_edges(failures)
	_test_exact_pocket(failures)
	_test_bottom_dock(failures)
	_test_dock_order_independence(failures)
	_test_narrow_area(failures)
	_test_no_space_diagnostic(failures)
	_test_oversized_sizes(failures)
	return failures

static func _test_three_anchors(failures: Array[String]) -> void:
	var anchors: Array[Rect2] = [Rect2(1100,300,150,420),Rect2(1350,300,150,420),Rect2(1600,300,150,420)]
	var obstacles: Array[Rect2] = anchors.duplicate()
	obstacles.append_array([Rect2(80,200,300,540),Rect2(390,250,180,480),Rect2(70,745,320,34),Rect2(390,735,180,34)])
	for index in anchors.size():
		var result: Dictionary = Placement.choose(anchors[index],DESIRED,COMPACT,obstacles)
		_assert_clear(result,obstacles,AREA,"三人第%d锚点" % index,failures)
		_expect(not result.docked,"存在浮动空位时不必停靠：%d" % index,failures)
		var again: Dictionary = Placement.choose(anchors[index],DESIRED,COMPACT,obstacles)
		_expect(result == again,"相同输入必须可复现：%d" % index,failures)
	var reversed: Array[Rect2] = obstacles.duplicate()
	reversed.reverse()
	_expect(Placement.choose(anchors[1],DESIRED,COMPACT,obstacles) == Placement.choose(anchors[1],DESIRED,COMPACT,reversed),"障碍登记顺序不改变放置结果",failures)

static func _test_wide_boss(failures: Array[String]) -> void:
	var anchor := Rect2(1300,300,170,420)
	var obstacles: Array[Rect2] = [anchor,Rect2(80,180,640,600),Rect2(80,782,640,30),Rect2(1510,300,170,420),Rect2(1720,300,150,420)]
	var result: Dictionary = Placement.choose(anchor,DESIRED,COMPACT,obstacles)
	_assert_clear(result,obstacles,AREA,"宽首领与三人同屏",failures)
	_expect(not result.docked,"首领旁仍有完整开口时保留浮动面板",failures)

static func _test_above_opening(failures: Array[String]) -> void:
	var area := Rect2(0,0,1200,900)
	var anchor := Rect2(500,500,200,300)
	var obstacles: Array[Rect2] = [anchor,Rect2(0,400,500,500),Rect2(700,400,500,500)]
	var result: Dictionary = Placement.choose(anchor,Vector2(300,240),Vector2(1200,120),obstacles,area)
	_assert_clear(result,obstacles,area,"两侧封闭但上方开放",failures)
	var rectangle: Rect2 = result.rect
	_expect(not result.docked and rectangle.end.y <= anchor.position.y,"两侧无位时使用上方候选",failures)

static func _test_screen_edges(failures: Array[String]) -> void:
	for anchor in [Rect2(1840,620,100,300),Rect2(-40,200,150,500),Rect2(1700,30,180,400)]:
		var obstacles: Array[Rect2] = [anchor]
		var result: Dictionary = Placement.choose(anchor,DESIRED,COMPACT,obstacles)
		_assert_clear(result,obstacles,AREA,"屏边锚点%s" % str(anchor),failures)

static func _test_exact_pocket(failures: Array[String]) -> void:
	# 空位尺寸恰好容纳面板，粗步长网格会漏掉这个开口。
	var area := Rect2(10,10,1000,800)
	var pocket := Rect2(273,163,317,431)
	var obstacles: Array[Rect2] = [Rect2(10,10,1000,153),Rect2(10,163,263,431),Rect2(590,163,420,431),Rect2(10,594,1000,216)]
	var result: Dictionary = Placement.choose(Rect2(850,600,100,180),pocket.size,Vector2(1000,120),obstacles,area)
	_assert_clear(result,obstacles,area,"非整数网格开口",failures)
	_expect(result.rect == pocket and not result.docked,"障碍边缘搜索找到恰好可用的完整空位",failures)

static func _test_bottom_dock(failures: Array[String]) -> void:
	var obstacles: Array[Rect2] = [Rect2(24,116,1872,696)]
	var result: Dictionary = Placement.choose(Rect2(1400,350,200,380),DESIRED,COMPACT,obstacles)
	_assert_clear(result,obstacles,AREA,"浮动无位的底部停靠",failures)
	_expect(result.docked and result.rect == Rect2(24,812,1872,172),"紧凑技能菜单停靠812至984且不挤入miniHUD",failures)

static func _test_narrow_area(failures: Array[String]) -> void:
	var area := Rect2(40,120,780,860)
	var obstacles: Array[Rect2] = [Rect2(40,120,780,688)]
	var result: Dictionary = Placement.choose(Rect2(600,380,170,380),DESIRED,Vector2(780,172),obstacles,area)
	_assert_clear(result,obstacles,area,"调用方定义的窄画幅",failures)
	_expect(result.docked and result.rect == Rect2(40,808,780,172),"停靠位置来自area而非固定1920宽",failures)

static func _test_dock_order_independence(failures: Array[String]) -> void:
	var area := Rect2(0,0,1000,200)
	var anchor := Rect2(500,0,100,50)
	var obstacles: Array[Rect2] = [Rect2(0,0,100,200),Rect2(400,0,300,200),Rect2(900,0,100,200)]
	var first: Dictionary = Placement.choose(anchor,Vector2(1100,560),Vector2(200,100),obstacles,area)
	obstacles.reverse()
	var reversed: Dictionary = Placement.choose(anchor,Vector2(1100,560),Vector2(200,100),obstacles,area)
	_assert_clear(first,obstacles,area,"左右均有紧凑停靠开口",failures)
	_expect(first == reversed,"障碍登记顺序不改变紧凑停靠位置",failures)

static func _test_no_space_diagnostic(failures: Array[String]) -> void:
	# 同一保护区重复登记不能把碰撞面积重复相加。
	var obstacles: Array[Rect2] = [AREA,AREA,Rect2(24,116,936,868)]
	var result: Dictionary = Placement.choose(Rect2(1300,300,170,420),DESIRED,COMPACT,obstacles)
	var rectangle: Rect2 = result.rect
	_expect(AREA.encloses(rectangle),"无空位时仍不越出area",failures)
	_expect(float(result.obstruction_area) > 0.0,"无空位必须明确报告碰撞量",failures)
	_expect(is_equal_approx(float(result.obstruction_area),DESIRED.x*DESIRED.y),"选择较小遮挡且按障碍并集计量",failures)
	var small: Dictionary = Placement.choose(Rect2(1300,300,170,420),DESIRED,Vector2(900,100),obstacles)
	_expect(small.docked and is_equal_approx(float(small.obstruction_area),90000.0),"紧凑形态碰撞更少时选择紧凑停靠",failures)

static func _test_oversized_sizes(failures: Array[String]) -> void:
	var area := Rect2(40,100,400,300)
	var obstacles: Array[Rect2] = []
	var result: Dictionary = Placement.choose(Rect2(200,200,80,160),DESIRED,COMPACT,obstacles,area)
	_assert_clear(result,obstacles,area,"小area的外框钳制",failures)
	_expect(result.docked and result.rect == Rect2(40,228,400,172),"desired不适合时钳制compact外框而非越屏",failures)

static func _assert_clear(result: Dictionary, obstacles: Array[Rect2], area: Rect2, label: String, failures: Array[String]) -> void:
	var rectangle: Rect2 = result.rect
	_expect(area.encloses(rectangle),label+"：面板必须位于area内",failures)
	_expect(is_zero_approx(float(result.obstruction_area)),label+"：应找到零遮挡位置",failures)
	for obstacle in obstacles:
		_expect(not rectangle.intersects(obstacle),label+"：不可遮住角色或意图保护区",failures)

static func _expect(value: bool, message: String, failures: Array[String]) -> void:
	assertion_count += 1
	if not value: failures.append(message)
