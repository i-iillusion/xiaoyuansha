# ============================================================
# Deck.gd — 弃牌堆管理
# 不再有固定牌堆，卡牌在使用时按需创建
# ============================================================
class_name Deck
extends RefCounted

var _discard: Array[CardBase] = []

# 弃牌
func discard(card: CardBase):
	_discard.append(card)

func discard_count() -> int:
	return _discard.size()
