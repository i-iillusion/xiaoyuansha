# 2～10 人无身份乱斗的只读判胜器。无 UI、击杀奖励和身份技能依赖。
# 规则：最后一名最终存活玩家获胜；所有玩家最终死亡则平局；存在濒死者时等待救援结束。
class_name FreeForAllVictory
extends RefCounted

const MIN_PLAYERS := 2
const MAX_PLAYERS := 10

# 空字典表示继续/等待/配置不受支持。
static func evaluate(players: Array[Player]) -> Dictionary:
	if players.size() < MIN_PLAYERS or players.size() > MAX_PLAYERS:
		return {}
	var seen: Array[Player] = []
	var survivors: Array[Player] = []
	var has_dying := false
	for p in players:
		# 乱斗必须无身份；重复或空角色也不由判胜器猜测。
		if p == null or seen.has(p) or p.identity != "":
			return {}
		seen.append(p)
		if p.is_dying():
			has_dying = true
		if not p.is_dead():
			survivors.append(p)
	# 濒死不是最终死亡，先等待普通救援或可撤销死亡窗口结束。
	if has_dying:
		return {}
	if survivors.size() == 1:
		var winner := survivors[0]
		return {
			"winner": winner.player_name,
			"winner_seat": winner.seat_index,
			"reason": "仅剩 %s 最终存活" % winner.player_name,
			"is_draw": false,
		}
	if survivors.is_empty():
		return {
			"winner": "平局",
			"winner_seat": -1,
			"reason": "所有玩家均已最终死亡",
			"is_draw": true,
		}
	return {}
