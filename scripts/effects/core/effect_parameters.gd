extends RefCounted
## 共同参数契约v1：秒、父容器像素。命中只有真实事件能够进入phase=3。
static func sample(clock: float, hand: Vector2, target: Vector2, elapsed: float, launch: float, impact_at: float, hit_age: float = -1.0, flight_origin: Vector2 = Vector2.INF) -> Dictionary:
	var phase := 0.0
	var charge := 0.0
	var bolt := hand
	var flash := 0.0
	if hit_age >= 0.0:
		phase=3.0; flash=exp(-hit_age*13.0)
	elif elapsed < launch:
		phase=1.0; charge=clampf(elapsed/launch,0.0,1.0)
	elif elapsed < impact_at:
		phase=2.0
		if flight_origin.is_finite(): hand=flight_origin
		bolt=hand.lerp(target,clampf((elapsed-launch)/(impact_at-launch),0.0,1.0))
	return {"time":clock,"hand":hand,"target":target,"bolt":bolt,"charge":charge,"phase":phase,"impact":maxf(hit_age,0.0),"flash":flash}
