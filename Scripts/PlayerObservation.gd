# 白名单值快照。绝不把Player/CardBase引用或他人手牌/暗置牌名交给策略。
class_name PlayerObservation
extends RefCounted

# Knowing one's own role is independent of revealing it to other players.
static func visible_identity(player: Player, viewer: Player = null) -> String:
	return player.identity if player == viewer or player.identity_revealed else ""

static func sally_status(player: Player) -> Dictionary:
	if not SallySmokingState.enabled(player):
		return {}
	return {
		"smoking": player.sally_smoke_active,
		"boosted": player.sally_boost_turn >= 0,
		"surgery_pending": player.sally_surgery_pending,
		"surgery_active": player.sally_surgery_active,
	}

static func gender_label(gender: String) -> String:
	match gender:
		"female": return "女性"
		"male": return "男性"
		_: return "无性别"

static func sally_labels(status: Dictionary) -> Array[String]:
	var labels: Array[String] = []
	if status.get("smoking", false): labels.append("抽烟状态")
	if status.get("boosted", false): labels.append("双倍响应")
	if status.get("surgery_pending", false): labels.append("肺部手术待生效")
	if status.get("surgery_active", false): labels.append("肺部手术已生效")
	return labels

static func capture(players: Array, actor: Player, phase: int, revision: int) -> Dictionary:
	var visible: Array = []
	for p in players:
		var equipment: Dictionary = {}
		for slot in p.equipment:
			equipment[slot] = p.equipment[slot]
		var judgments: Array = []
		for card in p.judgment_cards:
			judgments.append(card.sub_type)
		visible.append({"seat": p.seat_index, "hp": p.hp, "max_hp": p.max_hp,
			"dead": p.is_dead(), "dying": p.is_dying(), "general": p.general_name,
			"identity": visible_identity(p, actor), "gender": p.gender,
			"hand_count": p.hand_size(), "equipment": equipment,
			"judgments": judgments, "chained": p.chained, "facedown": p.facedown})
		if p.good_deed_marks > 0: visible.back()["good_deed_marks"] = p.good_deed_marks
		if p.tuanfei_extra_draws > 0: visible.back()["tuanfei_extra_draws"] = p.tuanfei_extra_draws
		var status = sally_status(p)
		if not status.is_empty(): visible.back()["sally"] = status
	var own_cards: Array = []
	for zone in ["hand", "determined_cards"]:
		var cards: Array = actor.get(zone)
		for index in cards.size():
			var card = cards[index]
			own_cards.append({"zone": zone, "index": index,
				"sub": -1 if card == null else card.sub_type})
	return {"actor": actor.seat_index, "phase": phase, "revision": revision,
		"players": visible, "own_cards": own_cards}
