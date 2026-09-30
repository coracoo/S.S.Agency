extends Control
## 战后选牌奖励屏 v2（最小版）
##
## 胜利后从 CardV2 池随机抽 3 张供玩家选 1 张加入牌组。
## 选择后回调 on_picked(card_id)，由 card_battle_scene 加牌并切回对话。
## 暂时不做稀有度过滤，P2 阶段再细化。

signal picked(card_id: String)
signal skipped()

@onready var title_label: Label = $VBox/TitleLabel
@onready var cards_row: HBoxContainer = $VBox/CardsRow
@onready var skip_btn: Button = $VBox/SkipBtn

const CardView = preload("res://scripts/v2/ui/card_view.gd")


func _ready() -> void:
	UIThemeFactoryV2.apply_button(skip_btn)
	skip_btn.pressed.connect(func(): skipped.emit())


## 显示奖励屏，从可选卡池随机抽 3 张
## [param exclude_ids] 玩家牌组已有的卡 id（避免重复展示，可选）
func setup(exclude_ids: Array = []) -> void:
	call_deferred("_build_choices", exclude_ids)


func _build_choices(exclude_ids: Array) -> void:
	for c in cards_row.get_children():
		c.queue_free()
	var pool = CardV2.get_all_ids()
	# 过滤掉已有的（保持稀有度多样性的逻辑留 P2）
	var candidates = []
	for cid in pool:
		if not exclude_ids.has(cid):
			candidates.append(cid)
	candidates.shuffle()
	var picks = candidates.slice(0, mini(3, candidates.size()))
	for i in picks.size():
		var cid = picks[i]
		var card_def = CardV2.get_card(cid)
		var view = CardView.new()
		view.setup(card_def, i, false)
		view.custom_minimum_size = Vector2(180, 260)
		view.clicked.connect(func(_idx): picked.emit(cid))
		cards_row.add_child(view)
