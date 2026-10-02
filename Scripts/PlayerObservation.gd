# 白名单值快照。绝不把Player/CardBase引用或他人手牌/暗置牌名交给策略。
class_name PlayerObservation
extends RefCounted

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
			"identity": p.identity if p == actor or p.identity_revealed else "",
			"hand_count": p.hand_size(), "equipment": equipment,
			"judgments": judgments, "chained": p.chained, "facedown": p.facedown})
	var own_cards: Array = []
	for zone in ["hand", "determined_cards"]:
		var cards: Array = actor.get(zone)
		for index in cards.size():
			var card = cards[index]
			own_cards.append({"zone": zone, "index": index,
				"sub": -1 if card == null else card.sub_type})
	return {"actor": actor.seat_index, "phase": phase, "revision": revision,
		"players": visible, "own_cards": own_cards}
