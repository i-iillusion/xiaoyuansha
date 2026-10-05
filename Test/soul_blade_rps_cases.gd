extends RefCounted

var suite
var game: GameManager
var rounds := 0
var discards := 0
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._soul_blade_activate_override = Callable()
	game._soul_blade_discard_override = Callable()
	game._hand_discard_override = Callable()
	game._rps_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	rounds = 0
	discards = 0
	for p in game.players: p.facedown = false

func gesture_for(result: int) -> int:
	seed(104)
	var opponent = randi() % 3
	seed(104)
	for gesture in 3:
		if game._rps_result(gesture, opponent) == result: return gesture
	return -1

func drive(action: String, invalid_round: int, source: Player, victim: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	if buttons.size() == 2:
		suite.check(not game._countdown_active, "E03e-14c：发动与弃牌确认无倒计时")
		var label = pending.overlay.find_children("*", "Label", true, false)[0]
		if label.text.begins_with("拼点未全赢"):
			discards += 1
			var need = 2 if action == "win_lose" else 4
			suite.check(label.text.contains(str(need)), "E03e-14c：真实胜负决定两张/四张费用")
			buttons[1].pressed.emit()
			return
		drive.call_deferred(action, invalid_round, source, victim)
		buttons[0].pressed.emit()
		return
	rounds += 1
	suite.check(buttons.size() == 3 and game._countdown_active, "E03e-14c：真实出拳保持计时")
	if rounds == invalid_round:
		match action:
			"close":
				pending.overlay.queue_free()
				return
			"phase", "phase_idle":
				game.turn_manager.current_phase = TurnManager.Phase.END
				game.turn_manager.current_phase = TurnManager.Phase.PLAY
				if action == "phase_idle": return
			"same_weapon":
				source.determined_cards.append(source.remove_equipment("weapon"))
				var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
				blade.soul_blade_activated = true
				source.equip_card_to_slot("weapon", blade)
			"victim_dead":
				victim.hp = 0
				victim.mark_dead()
			"ended":
				game._finish_game("平局", "摄魂真实出拳回归")
				return
		buttons[0].pressed.emit()
		return
	var desired = GameManager.RPS_WIN
	if invalid_round == 3 and rounds == 2: desired = GameManager.RPS_DRAW
	if action == "tie_win" and rounds == 1: desired = GameManager.RPS_DRAW
	if action == "win_lose" and rounds == 2: desired = GameManager.RPS_LOSE
	if action == "lose_lose": desired = GameManager.RPS_LOSE
	if rounds < (3 if action == "tie_win" or invalid_round == 3 else 2):
		drive.call_deferred(action, invalid_round, source, victim)
	var gesture = gesture_for(desired)
	buttons[[0, 2, 1][gesture]].pressed.emit()
	# 失败的真实两局后进入弃牌确认，留足手牌并只拒绝费用。
	if action in ["win_lose", "lose_lose"] and rounds == 2:
		drive.call_deferred(action, invalid_round, source, victim)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["win_win", "tie_win", "win_lose", "lose_lose", "close", "phase", "phase_idle", "same_weapon", "victim_dead", "ended"]:
			for invalid_round in ([0] if action in ["win_win", "tie_win", "win_lose", "lose_lose"] else [1, 2, 3]):
				reset()
				events.clear()
				var source = game.players[0]
				var victim = game.players[1]
				var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
				blade.soul_blade_activated = true
				source.equip_card_to_slot("weapon", blade)
				for i in 4: source.hand.append(null)
				var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
				if concrete:
					source.determined_cards.append(kill)
					game._pending_determined_card = kill
				else: source.hand.append(null)
				var later: Array = []
				victim.equip_card_to_slot(Player.MOUNT_SLOTS[0], CardBase.create(CardData.CardSubType.MULE_PLUS))
				game._plus_mule_target_override = func():
					later.append(true)
					return "cancel"
				drive.call_deferred(action, invalid_round, source, victim)
				await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
				suite.check(victim.hp == (0 if action == "victim_dead" else 9) and victim.facedown == (action in ["win_win", "tie_win"]), "E03e-14c：只有完整两胜翻面，伤害不撤销")
				suite.check(rounds == (invalid_round if invalid_round > 0 else (3 if action == "tie_win" else 2)), "E03e-14c：平局重猜，不误算为新的一次拼点")
				suite.check(discards == (1 if action in ["win_lose", "lose_lose"] else 0) and source.hand_size() == (5 if action == "same_weapon" else 4), "E03e-14c：拒绝费用不扣牌，失效不进入弃牌确认")
				suite.check(later.size() == (1 if invalid_round == 0 else 0), "E03e-14c：过期真实出拳停止后效")
				suite.check(events.size() == 1 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-14c：原殺只支付一次，拼点不额外付牌")
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-14c：等待清理")
				await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-14c：真实出拳与平局所有窗口释放")
	game.card_action_committed.disconnect(collect)
	reset()
	game._plus_mule_target_override = Callable()
	suite = null
	game = null
