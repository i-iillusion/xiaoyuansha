# 一次伤害的共享记录。转移只改实际目标，不新建伤害或重放修正。
class_name DamageRecord
extends RefCounted

var original_source: Player
var source: Player
var original_target: Player
var target: Player
var card: CardBase
var element: int = 0
var amount: int = 0
var applied_amount: int = 0
var from_strike: bool = false
var is_chain: bool = false
var committed: bool = false
var sacrifice_offered: bool = false
var source_modifiers_applied: bool = false
var target_modifiers_applied: bool = false
var hp_before: int = 0
var hp_after: int = 0
var events: Array[String] = []

func _init(attacker: Player, victim: Player, source_card: CardBase, value: int):
	original_source = attacker
	source = attacker
	original_target = victim
	target = victim
	card = source_card
	amount = value
	from_strike = card != null and card.sub_type in [CardData.CardSubType.STRIKE,
		CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE]

func refresh_source():
	# 阵亡与濒死不同：只有完成死亡结算才将后续伤害改为无来源。
	if source != null and source.is_dead():
		source = null

func commit() -> bool:
	refresh_source()
	if committed or target == null or target.is_dead() or amount <= 0:
		return false
	committed = true
	hp_before = target.hp
	applied_amount = amount
	target.take_damage(amount)
	hp_after = target.hp
	return true
