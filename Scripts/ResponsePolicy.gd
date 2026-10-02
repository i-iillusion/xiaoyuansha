# 保守策略，不是规则限制。只读取公开值快照及合法响应选项。
class_name ResponsePolicy
extends RefCounted

static func choose(view: Dictionary, kind: String, options: Array) -> int:
	if options.is_empty():
		return -1
	if kind == "basic":
		return options[0]
	if kind != "rescue":
		# 无懈/舍己默认保守放弃；可注入策略不会改变规则入口。
		return -1
	var target = int(view.response.get("target", -1))
	if target == view.actor:
		return options[0]
	if view.mode != GameManager.MODE_CLASSIC_IDENTITY:
		return -1
	var own: Dictionary = {}
	var other: Dictionary = {}
	for p in view.players:
		if p.seat == view.actor:
			own = p
		if p.seat == target:
			other = p
	if own.is_empty() or other.is_empty() or other.identity == "":
		return -1
	var allies = (own.identity in ["主公", "忠臣"] and other.identity in ["主公", "忠臣"]) \
		or (own.identity == "反贼" and other.identity == "反贼")
	return CardData.CardSubType.PEACH if allies and options.has(CardData.CardSubType.PEACH) else -1
