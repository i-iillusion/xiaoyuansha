# ============================================================
# EquipmentPool.gd — 装备唯一性管理（武器/防具）
#
# 规则：每种武器或防具在一局游戏内只有一张。
#       名称首次声明后不能由另一张牌重新具体化；未弃置的原牌可移动后再装备。
#       弃置不释放名称，也不使原牌重新可用。
# 坐骑（+1/-1 马）不受此规则限制。
# ============================================================
class_name EquipmentPool
extends RefCounted

var _claimed: Dictionary = {}

# 值为首次声明时的原对象；旧式无对象声明仅占名称，不授权后来实例。
func is_claimed(sub: CardData.CardSubType) -> bool:
	return _claimed.has(sub)

func is_claimed_original(sub: CardData.CardSubType, card: CardBase) -> bool:
	return card != null and _claimed.has(sub) and _claimed[sub] == card

# 尝试占用该装备；已被占用返回 false
func claim(sub: CardData.CardSubType, card: CardBase = null) -> bool:
	if _claimed.has(sub):
		return false
	_claimed[sub] = card if card != null else true
	return true

func claimed_count() -> int:
	return _claimed.size()

func clear():
	_claimed.clear()
