# 五人经典身份局的只读判胜器。无 UI、奖惩和击杀者依赖。
# 依据与边界：Docs/HumanAgent/规则差异与五人局验收.md（ST-04/05）。
class_name IdentityVictory
extends RefCounted

const STANDARD_COUNTS = {"主公": 1, "忠臣": 1, "反贼": 2, "内奸": 1}

# 空字典表示继续/等待/不在支持范围；不代填 1V1、奸雄及特殊死亡规则。
static func evaluate(players: Array[Player]) -> Dictionary:
	if players.size() != 5:
		return {}
	var counts = {"主公": 0, "忠臣": 0, "反贼": 0, "内奸": 0}
	var survivors: Array[Player] = []
	var seen: Array[Player] = []
	var lord: Player = null
	var has_dying := false
	var opponents_remain := false
	for p in players:
		if p == null or seen.has(p) or not counts.has(p.identity):
			return {}
		seen.append(p)
		counts[p.identity] += 1
		if p.identity == "主公":
			lord = p
		if p.is_dying():
			has_dying = true
		if not p.is_dead():
			survivors.append(p)
			if p.identity == "反贼" or p.identity == "内奸":
				opponents_remain = true
	if counts != STANDARD_COUNTS or lord == null:
		return {}
	# 濒死不是阵亡；普通救援/死亡入口结束后由主控重查。
	if has_dying:
		return {}
	# 全员同时死亡不可能由本批正常逐人终局产生，留给特殊规则裁定。
	if survivors.is_empty():
		return {}
	if lord.is_dead():
		if survivors.size() == 1 and survivors[0].identity == "内奸":
			return {"winner": "内奸", "reason": "主公阵亡，内奸为唯一存活角色"}
		return {"winner": "反贼", "reason": "%s 阵亡" % lord.player_name}
	if not opponents_remain:
		return {"winner": "主公", "reason": "反贼与内奸已全部阵亡"}
	return {}
