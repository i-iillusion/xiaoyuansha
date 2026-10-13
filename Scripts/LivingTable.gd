# 普通圆桌的只读视图：编号固定，仅最终死亡者离开距离圆环。
# 后续空间规则可替换查询，不修改玩家的身份编号或回合数组。
class_name LivingTable
extends RefCounted

const UNREACHABLE: int = 1000000

static func ordered(players: Array, preserve_space: bool = false) -> Array[Player]:
	var result: Array[Player] = []
	for p in players:
		if p != null and not p.is_dead():
			result.append(p)
	if not preserve_space: result.sort_custom(func(a, b): return a.seat_index < b.seat_index)
	return result

static func distance(players: Array, source: Player, target: Player, preserve_space: bool = false) -> int:
	var circle = ordered(players, preserve_space)
	var a = circle.find(source)
	var b = circle.find(target)
	if a < 0 or b < 0:
		return UNREACHABLE
	var gap = absi(a - b)
	return mini(gap, circle.size() - gap)
