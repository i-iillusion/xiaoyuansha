# 无窗口自动对局观察器：不修改牌/体力/胜负，只把0号的选择交给有界AI。
extends GameManager

var replay_actions: Array = []
var replay_logs: Array[String] = []
var replay_cards: Dictionary = {}
var replay_violations: Array[String] = []

func _do_play(pid: int):
	await super._do_play(pid)
	if pid == 0 and not _game_over and turn_manager.current_phase == TurnManager.Phase.PLAY:
		await _run_ai_play(players[turn_manager.get_play_actor_idx()])

func _execute_ai_action(action: Dictionary):
	if not _ai_offered_actions.has(action):
		replay_violations.append("执行了未提供的动作")
	var before = replay_state()
	await super._execute_ai_action(action)
	var seen: Array = []
	for p in players:
		var resources: Array = p.hand.duplicate()
		resources.append_array(p.determined_cards)
		resources.append_array(p.judgment_cards)
		for slot in p.get_equip_slots():
			resources.append(p.get_equipment_card(slot))
		for card in resources:
			if card != null:
				if seen.has(card):
					replay_violations.append("原牌重复归属")
				seen.append(card)
	for card in deck._discard:
		if card != null and seen.has(card):
			replay_violations.append("原牌重复入弃或入弃后仍在牌区")
		seen.append(card)
	replay_actions.append({"step": replay_actions.size() + 1, "action": action.duplicate(true),
		"before": before, "after": replay_state()})

func _update_debug(msg: String, color: Color = Color(1, 1, 1, 0.55)):
	replay_logs.append(msg)
	super._update_debug(msg, color)

func card_ids(cards: Array) -> Array:
	var result: Array = []
	for card in cards:
		if card == null:
			result.append([0, -1])
			continue
		if not replay_cards.has(card):
			replay_cards[card] = replay_cards.size() + 1
		result.append([replay_cards[card], card.sub_type])
	return result

func replay_state() -> Dictionary:
	var roster: Array = []
	for p in players:
		var equipment: Array = []
		for slot in p.get_equip_slots():
			equipment.append(p.get_equipment_card(slot))
		roster.append({"seat": p.seat_index, "hp": p.hp, "dead": p.is_dead(),
			"hand": card_ids(p.hand), "determined": card_ids(p.determined_cards),
			"equipment": card_ids(equipment), "judgment": card_ids(p.judgment_cards)})
	return {"phase": turn_manager.current_phase, "turn_owner": turn_manager.current_player_idx,
		"roster": roster, "discard": card_ids(deck._discard)}
