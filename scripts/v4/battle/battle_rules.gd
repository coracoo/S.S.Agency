class_name BattleRulesV4
extends RefCounted
## V4 战斗纯逻辑层（GDD §6 回合结算契约 / 代码实施方案 A 期）。
## 不持有 UI、纹理、屏幕坐标；battle_canvas 表现层调用本类，
## 意图预览与实际结算复用同一规则（GDD §6.1「统一预览与实际伤害」）。
## 全部为 static 纯函数，输入输出皆为基础类型/Dictionary，可无头单测。

# ---------- 卡牌目标校验（「错误目标不扣费」的唯一判定点，GDD §6.2.2） ----------

## 费用闸：AP 不足不能打出（点击/详情弹窗同规则）
static func can_afford(card: Dictionary, ap: int) -> bool:
	return ap >= int(card.get("cost", 0))

## 场景槽目标资格：结界符只能贴阵眼；鸣钟可敲燃烧槽（惊焰救急）；其余须空闲。
## slot: {state, seal_point}；card: 卡牌 data（用 slot_state 区分用途）
static func slot_targetable(card: Dictionary, slot: Dictionary) -> bool:
	var want_seal: bool = String(card.get("slot_state", "")) == "sealed"
	if want_seal and not bool(slot.get("seal_point", false)):
		return false # 结界符只能贴阵眼（含重新提名中的阵眼）
	var state: String = String(slot.get("state", "idle"))
	var rings: bool = String(card.get("slot_state", "")) == "ringing"
	if rings:
		return state == "idle" or state == "burning" or state == "targetable"
	return state == "idle" or state == "targetable"

# ---------- 火势：按回合开始时的燃烧快照只传播一跳（GDD §6.2 拟修正规则落地） ----------
## 旧实现遍历槽表时新点燃的槽会在同一 pass 继续蔓延，遍历顺序决定一回合烧几层；
## 本函数先快照燃烧集合，再只点燃它们的相邻空闲槽，结果与遍历顺序无关。
## states: {slot_id: state_string}；adjacent: {slot_id: [neighbor_id...]}
## 返回 {changed: {slot_id: "burning"}, next_burning: [已含新点燃的燃烧快照]}
static func fire_spread_snapshot(states: Dictionary, adjacent: Dictionary) -> Dictionary:
	var burning_snapshot: Array = []
	for sid in states:
		if states[sid] == "burning":
			burning_snapshot.append(sid)
	var changed := {}
	for sid in burning_snapshot:
		for adj in (adjacent.get(sid, []) as Array):
			if states.get(adj, "") == "idle":
				changed[adj] = "burning"
				states[adj] = "burning" # 本跳内不二次蔓延（快照语义）
	return {"changed": changed, "burning": burning_snapshot}

# ---------- 敌方意图：每敌独立记录（GDD §6.1；当前波内数值一致，结构先行） ----------
## 状态覆盖优先级：鸣钟眩晕 > 暴走 > 遇火恐惧（猛扑降级为普通攻击）
static func compute_intent(pattern: Array, turn: int, stunned: bool, berserk: bool,
		has_burning: bool) -> String:
	var base := "attack"
	if not pattern.is_empty():
		base = String(pattern[turn % pattern.size()])
	if stunned:
		return "stun"
	if berserk:
		return "berserk"
	if has_burning and base == "pounce":
		return "attack" # 恐惧中的猛扑降级
	return base

# ---------- 敌方攻击结算：来源分解、同一来源只乘一次（GDD §七 统一预览与实际伤害） ----------
## p: {attack, spirit_mult, obsession(执念暴怒), intent, pounce_mult,
##     has_burning, fear_attack_mult, stun_skip}
## 返回 {damage:int, stun_immune:bool, lines:[{text, color_key}]} —— lines 供表现层飘字
static func resolve_enemy_attack(p: Dictionary) -> Dictionary:
	var mult := float(p.get("spirit_mult", 1.0))
	var lines: Array = []
	var intent := String(p.get("intent", "attack"))
	var stun_immune := false
	if intent == "stun":
		if bool(p.get("stun_skip", false)):
			stun_immune = true
			lines.append({"text": "免疫眩晕", "color_key": "gold_500"})
			intent = "attack" # 免疫后按普通攻击结算
		else:
			return {"damage": 0, "stun_immune": false, "lines": [{"text": "眩晕…", "color_key": "fuji_500"}]}
	if bool(p.get("obsession", false)):
		mult *= 1.5
		lines.append({"text": "执念暴怒！", "color_key": "vermilion_500"})
	elif intent == "berserk":
		mult *= 1.5
		lines.append({"text": "暴走！", "color_key": "vermilion_500"})
	elif intent == "pounce":
		mult *= float(p.get("pounce_mult", 1.8))
	elif bool(p.get("has_burning", false)):
		mult *= float(p.get("fear_attack_mult", 0.5))
		lines.append({"text": "恐惧…", "color_key": "fuji_500"})
	var dmg := int(round(float(p.get("attack", 6)) * mult))
	return {"damage": dmg, "stun_immune": stun_immune, "lines": lines}

# ---------- 胜负评估：失败优先（GDD §6.2.4 成功与失败同时成立时失败优先） ----------
## player_hp / units_alive 为检查瞬间的快照值。返回 "lose" / "win" / "ongoing"
static func evaluate_battle(player_hp: int, units_alive: int) -> String:
	if player_hp <= 0:
		return "lose"
	if units_alive <= 0:
		return "win"
	return "ongoing"

# ---------- B 期：护盾 / 标记 / 整理（GDD §5.3、§5.6） ----------

## 卡牌效果解析：effects JSON → 归一化数值（预览与实际结算共用）
static func parse_effects(card: Dictionary) -> Dictionary:
	var fx: Dictionary = card.get("effects", {})
	return {
		"shield": int(fx.get("shield", 0)),
		"cleanse": int(fx.get("cleanse", 0)),
		"mark": int(fx.get("mark", 0)),
		"consume_mark": int(fx.get("consume_mark", 0)),
		"bonus": int(fx.get("bonus", 0)),
		"spirit": int(fx.get("spirit", 0)),
		"draw": int(fx.get("draw", 0)),
	}

## 护盾承伤：护盾先于生命扣除（GDD §5.6）。返回新值与分项
static func apply_shield(hp: int, shield: int, dmg: int) -> Dictionary:
	var absorbed := mini(shield, dmg)
	return {
		"hp": maxi(0, hp - (dmg - absorbed)),
		"shield": shield - absorbed,
		"absorbed": absorbed,
		"through": dmg - absorbed,
	}

## 标记叠加：最多 3 层（GDD §5.6），下限 0
static func add_marks(marks: int, delta: int) -> int:
	return clampi(marks + delta, 0, 3)

## 攻击附加：消耗标记换加成（追符斩）。返回 {power, consumed, lines:[...]}
static func consume_marks_for_bonus(power: int, marks: int, need: int, bonus: int) -> Dictionary:
	if need > 0 and marks >= need:
		return {"power": power + bonus, "consumed": need, "lines": ["标记迸发 +%d" % bonus]}
	return {"power": power, "consumed": 0, "lines": []}

## 整理（GDD §5.3）：每回合一次、1 灵墨；无其他可抽牌则不可用不扣费。
## p: {ap, used(本回合已整理), hand(手牌数), deck(抽牌堆), discard(弃牌堆,不含暂存张)}
## 返回 {ok, reason}
static func can_tidy(p: Dictionary) -> Dictionary:
	if bool(p.get("used", false)):
		return {"ok": false, "reason": "每回合只能整理一次"}
	if int(p.get("ap", 0)) < 1:
		return {"ok": false, "reason": "灵墨不足（需 1）"}
	if int(p.get("hand", 0)) <= 0:
		return {"ok": false, "reason": "没有可整理的手牌"}
	# 可抽牌 = 抽牌堆 + 弃牌堆（暂存张最终也回弃牌，但不能抽回刚选中的那张——
	# 抽出在弃置暂存之前，若两堆合计只有暂存张自身则等于抽回： conservative 判定）
	if int(p.get("deck", 0)) + int(p.get("discard", 0)) < 1:
		return {"ok": false, "reason": "没有其他可抽的牌"}
	return {"ok": true, "reason": ""}

# ---------- B 期：构筑合法性（GDD §5.2，构筑界面与战斗发牌共用） ----------
## deck_ids: 16 个卡 id；library: {id: card_def}（CardLibraryV4.load_library）
## main_id / support_id: 主战/支援角色 id；卡 def 的 owner 字段决定归属
## （owner==main → 主战卡；owner==support → 支援卡；其余视为通用卡）。
## 返回错误字符串列表；空列表 = 合法。
static func validate_deck(deck_ids: Array, main_id: String, support_id: String,
		library: Dictionary) -> Array:
	var errors: Array = []
	if deck_ids.size() != 16:
		errors.append("牌组须正好 16 张（当前 %d 张）" % deck_ids.size())
	# 未知卡与重复上限：同一基础卡最多 2 张（升级分支 base_id 合计），独特卡最多 1 张
	var base_counts := {}
	var main_count := 0
	var support_count := 0
	for id in deck_ids:
		if not library.has(id):
			errors.append("未知卡牌：%s" % str(id))
			continue
		var def: Dictionary = library[id]
		var base := String(def.get("base_id", id))
		base_counts[base] = int(base_counts.get(base, 0)) + 1
		var tags: Array = def.get("tags", [])
		var max_copies := 1 if tags.has("unique") else 2
		if int(base_counts[base]) > max_copies:
			errors.append("「%s」超过重复上限（最多 %d 张）" % [def.get("name", base), max_copies])
		var owner := String(def.get("owner", ""))
		if owner == main_id and not main_id.is_empty():
			main_count += 1
		elif owner == support_id and not support_id.is_empty():
			support_count += 1
	if main_count < 6:
		errors.append("至少 6 张主战卡（当前 %d 张）" % main_count)
	if not support_id.is_empty() and support_count > 6:
		errors.append("支援卡最多 6 张（当前 %d 张）" % support_count)
	return errors

## 费用分布提示（GDD §5.2「费用分布提示」）：返回 {cost_string: 张数}，按费用升序
static func deck_cost_curve(deck_ids: Array, library: Dictionary) -> Dictionary:
	var curve := {}
	for id in deck_ids:
		if not library.has(id):
			continue
		var cost := int((library[id] as Dictionary).get("cost", 0))
		var key := str(cost)
		curve[key] = int(curve.get(key, 0)) + 1
	return curve

# ---------- B 期：器物效果（GDD §7：主战配置 1 件，明确触发上限） ----------
## 取值器：某效果键在本场已用次数未达 limit 才生效，否则返回 0。
## artifact: artifacts.json 单条 {id, effect:{键:值}, limit}；uses: 本场该键已触发次数
static func artifact_value(artifact: Dictionary, key: String, uses: int) -> int:
	if artifact.is_empty():
		return 0
	if uses >= int(artifact.get("limit", 0)):
		return 0
	return int((artifact.get("effect", {}) as Dictionary).get(key, 0))

## 结界符费用折扣：cost - discount，最低 min_cost（避免免费无限贴符）
static func artifact_seal_cost(cost: int, discount: int, min_cost := 1) -> int:
	if discount <= 0:
		return cost
	return maxi(min_cost, cost - discount)


# ---------- C 期：回合仪式（GDD §八：独立目标，共享交互） ----------

## 引灯稳定度衰减（每回合结束，GDD §8.3）：衰减后钳 0，lamp_out 供立即失败判定
static func ritual_decay(lamp: int, decay: int) -> Dictionary:
	var l := maxi(0, lamp - decay)
	return {"lamp": l, "lamp_out": l <= 0}

## 添灯/灯油：恢复稳定度并钳到上限
static func ritual_add_fuel(lamp: int, amount: int, max_lamp: int) -> int:
	return mini(max_lamp, lamp + amount)

## 仪式目标条件评估（GDD §8.3 结算）：
## lamp≤0 或 hp≤0 立即失败；turn<max_turns 继续；第 max_turns 回合结束查目标缺项。
## objectives: {id: {name, done}}；返回 {result: "win"/"lose"/"ongoing", missing: [文案]}
static func ritual_evaluate(lamp: int, hp: int, objectives: Dictionary,
		turn: int, max_turns: int) -> Dictionary:
	if lamp <= 0:
		return {"result": "lose", "missing": ["引灯熄灭"]}
	if hp <= 0:
		return {"result": "lose", "missing": ["主战倒下"]}
	if turn < max_turns:
		return {"result": "ongoing", "missing": []}
	var missing: Array = []
	for id in objectives:
		var o: Dictionary = objectives[id]
		if not bool(o.get("done", false)):
			missing.append(String(o.get("name", id)))
	if missing.is_empty():
		return {"result": "win", "missing": []}
	return {"result": "lose", "missing": missing}

## 仪式目标使用资格（前提链 + 回合窗口，不满足不扣费）：
## obj: {min_turn, requires:[id]}；ctx: {turn, done:{id:true}}
## 返回 {ok, reason}
static func ritual_objective_available(obj: Dictionary, ctx: Dictionary) -> Dictionary:
	var turn := int(ctx.get("turn", 1))
	var min_turn := int(obj.get("min_turn", 1))
	if turn < min_turn:
		return {"ok": false, "reason": "时机未到（第 %d 回合起）" % min_turn}
	var done: Dictionary = ctx.get("done", {})
	for req in (obj.get("requires", []) as Array):
		if not bool(done.get(String(req), false)):
			return {"ok": false, "reason": "需要先完成「%s」" % String(req)}
	return {"ok": true, "reason": ""}
