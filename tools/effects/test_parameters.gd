extends SceneTree
const Parameters = preload("res://scripts/effects/core/effect_parameters.gd")
func _initialize() -> void:
	var from := Vector2(100,200); var target := Vector2(600,200)
	var launch := 5.0/24.0; var impact_at := 7.0/24.0
	var failures: Array[String]=[]
	if Parameters.sample(0,from,target,.1,launch,impact_at).phase!=1.0: failures.append("charge")
	var middle := Parameters.sample(0,from,target,.25,launch,impact_at)
	if middle.phase!=2.0 or middle.bolt.distance_to(Vector2(350,200))>0.0001: failures.append("flight midpoint")
	if Parameters.sample(0,from,target,.3,launch,impact_at).phase!=0.0: failures.append("no fabricated impact")
	var tail := Parameters.sample(0,from,target,.9,launch,impact_at,.6)
	if tail.phase!=3.0 or absf(tail.impact-.6)>0.000000001: failures.append("independent impact age")
	if absf(tail.flash-exp(-.6*13.0))>0.000000000001: failures.append("approved flash decay")
	for failure in failures: printerr("FAIL: shared parameters ",failure)
	print("PARAMETERS_GD_RESULT failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
