# ============================================================
# EquipmentPool.gd — 装备唯一性管理（武器/防具）
#
# 规则：每种武器或防具在一局游戏内只有一张。
#       只要有人装备过（claim），其他人就都无法再装备同样的武器/防具。
#       即使之后被弃置/牵走，占用也永久保留。
# 坐骑（+1/-1 马）不受此规则限制。
# ============================================================
class_name EquipmentPool
extends RefCounted

var _claimed: Dictionary = {}

# 该装备是否已被装备过（全场唯一）
func is_claimed(sub: CardData.CardSubType) -> bool:
	return _claimed.has(sub)

# 尝试占用该装备；已被占用返回 false
func claim(sub: CardData.CardSubType) -> bool:
	if _claimed.has(sub):
		return false
	_claimed[sub] = true
	return true

func claimed_count() -> int:
	return _claimed.size()

func clear():
	_claimed.clear()
