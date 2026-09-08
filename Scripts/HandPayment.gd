# 物理手牌使用的原子选择/移除；不处理目标合法性、技能费用、响应窗口或牌的去向。
class_name HandPayment
extends RefCounted

# 自动选牌策略：先用已具体化的同类型牌，再使用任意牌。
# 策略不是额外游戏规则；提供 preferred 供后续显式选牌入口使用。
static func find_index(hand: Array[CardBase], sub: CardData.CardSubType, preferred: CardBase = null) -> int:
	if preferred != null:
		if preferred.sub_type != sub:
			return -1
		return hand.find(preferred)
	var blank_index := -1
	for i in range(hand.size() - 1, -1, -1):
		var card := hand[i]
		if card != null and card.sub_type == sub:
			return i
		if card == null and blank_index < 0:
			blank_index = i
	return blank_index

# 返回被使用的具体资源；null 表示支付失败且手牌不变。
# 不可将 take 用作“弃置任意手牌”接口：弃牌费用不要求匹配声明类型。
static func take(hand: Array[CardBase], sub: CardData.CardSubType, preferred: CardBase = null) -> CardBase:
	var index := find_index(hand, sub, preferred)
	if index < 0:
		return null
	var card := hand[index]
	if card == null:
		card = CardBase.create(sub)
	hand.remove_at(index)
	return card
