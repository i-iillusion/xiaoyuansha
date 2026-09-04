# ============================================================
# CardBase.gd — 单张卡牌的数据资源
# 简化版：无花色点数，只有类型
# ============================================================
extends Resource
class_name CardBase

@export var card_id: String = ""
@export var card_name: String = ""
@export var sub_type: CardData.CardSubType = CardData.CardSubType.STRIKE
@export_multiline var description: String = ""

# 延时锦囊放置者的座位（闪电伤害来源用）
var source_seat: int = -1

static func create(sub: CardData.CardSubType) -> CardBase:
	var card = CardBase.new()
	card.card_id = "card_%d" % Time.get_ticks_usec()
	card.card_name = CardData.get_type_name(sub)
	card.sub_type = sub
	card.description = CardData.CARD_DESCRIPTIONS.get(sub, "")
	return card
