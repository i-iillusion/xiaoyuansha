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
	return _take_at(hand, index, sub)

# 响应要求“杀”时接受普通/火/雷杀；不是主动声明另一种具体杀。
# 同样优先具体牌，再选任意牌；任意牌默认以普通杀响应。
static func find_response_index(hand: Array[CardBase], expected: CardData.CardSubType) -> int:
	if expected != CardData.CardSubType.STRIKE:
		return find_index(hand, expected)
	var blank_index := -1
	for i in range(hand.size() - 1, -1, -1):
		var card := hand[i]
		if card != null and card.sub_type in [CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE]:
			return i
		if card == null and blank_index < 0:
			blank_index = i
	return blank_index

static func take_response(hand: Array[CardBase], expected: CardData.CardSubType) -> CardBase:
	return _take_at(hand, find_response_index(hand, expected), expected)

static func _take_at(hand: Array[CardBase], index: int, blank_sub: CardData.CardSubType) -> CardBase:
	if index < 0:
		return null
	var card := hand[index]
	if card == null:
		card = CardBase.create(blank_sub)
	hand.remove_at(index)
	return card
