extends RefCounted

var suite
var game: GameManager
var punch := 0
var need := 2
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._soul_blade_activate_override = func(): return true
	game._soul_blade_discard_override = Callable()
	game._hand_discard_override = Callable()
	game._rps_override = func(p):
		punch += 1
		if p.seat_index == 0: return GameManager.RPS_ROCK
		return GameManager.RPS_SCISSORS if need == 2 and punch == 2 else GameManager.RPS_PAPER
	punch = 0
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.facedown = false
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func mutate(action: String, source: Player, victim: Player):
	match action:
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
		"weapon":
			source.determined_cards.append(source.remove_equipment("weapon"))
		"same_weapon":
			source.determined_cards.append(source.remove_equipment("weapon"))
			var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
			blade.soul_blade_activated = true
			source.equip_card_to_slot("weapon", blade)
		"victim_dead":
			victim.hp = 0
			victim.mark_dead()
		"ended": game._finish_game("平局", "摄魂弃牌回归")

func drive(stage: String, action: String, source: Player, victim: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	if stage == "confirm":
		suite.check(buttons.size() == 2 and not game._countdown_active, "E03e-14b：弃牌确认无倒计时")
		if action == "close":
			pending.overlay.queue_free()
			return
		mutate(action, source, victim)
		if action in ["phase_idle", "ended"]: return
		if action == "no":
			buttons[1].pressed.emit()
			return
		if action == "pay": drive.call_deferred("payment", "pay", source, victim)
		buttons[0].pressed.emit()
		return
	suite.check(pending.overlay is HandDiscardPrompt and game._countdown_active, "E03e-14b：实际选牌保留响应倒计时")
	if action == "close":
		pending.overlay.queue_free()
		return
	mutate(action, source, victim)
	if action in ["phase_idle", "ended"]: return
	if action == "cancel":
		pending.overlay.timeout()
		return
	if action == "timeout":
		game._countdown_on_timeout.call()
		return
	var checks = pending.overlay.find_children("*", "CheckButton", true, false)
	# 留下一张任意牌，精确选择后面的具体牌，不使用自动费用默认。
	for i in range(1, need + 1): checks[i].button_pressed = true
	if action == "stale": source.determined_cards.reverse()
	pending.overlay.confirm.pressed.emit()

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for cost in [2, 4]:
		need = cost
		for concrete in [false, true]:
			for stage in ["confirm", "payment"]:
				var actions = ["pay", "no", "close", "phase", "phase_idle", "weapon", "same_weapon", "victim_dead", "ended"] if stage == "confirm" else ["pay", "cancel", "timeout", "close", "phase", "phase_idle", "weapon", "same_weapon", "victim_dead", "ended", "stale"]
				for action in actions:
					reset()
					events.clear()
					var source = game.players[0]
					var victim = game.players[1]
					var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
					blade.soul_blade_activated = true
					source.equip_card_to_slot("weapon", blade)
					source.hand.append(null)
					var cards: Array = []
					for i in cost:
						var card = CardBase.create(CardData.CardSubType.PEACH if i % 2 == 0 else CardData.CardSubType.DODGE)
						cards.append(card)
						source.determined_cards.append(card)
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
					if stage == "payment": game._soul_blade_discard_override = func(): return true
					drive.call_deferred(stage, action, source, victim)
					await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
					var paid = action == "pay"
					suite.check(victim.hp == (0 if action == "victim_dead" else 9) and victim.facedown == paid, "E03e-14b：仅足额成功支付翻面，原伤害保留")
					suite.check(source.hand.size() == 1 and cards.all(func(card): return game.deck._discard.count(card) == (1 if paid else 0)), "E03e-14b：选中的原具体牌入弃一次，未选任意牌保留")
					suite.check(later.size() == (1 if action in ["pay", "no", "cancel", "timeout"] else 0), "E03e-14b：拒绝继续后效，失效/过期选牌停止")
					suite.check(events.size() == 1 and punch == 4 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-14b：杀支付一次，两次拼点无牌费用")
					suite.check(game._choice_prompt_stack.is_empty(), "E03e-14b：全部等待清理")
					await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-14b：所有确认及选牌窗口释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_soul_blade_discard_prompt("B", 2) == GameManager.CHOICE_INVALID, "E03e-14b：确认关闭明确失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._response_ready.emit()
		suite.check(not pending.answer.settled, "E03e-14b：旧确认回调与共享信号不污染新窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_soul_blade_discard_prompt("B", 4) == 0, "E03e-14b：下次确认可以放弃")
	await suite.process_frame
	game.players[0].hand.append(null)
	var old_timeout: Array = []
	var close_hand = func():
		var pending = game._choice_prompt_stack.back()
		old_timeout.append(game._countdown_on_timeout)
		pending.overlay.queue_free()
	close_hand.call_deferred()
	suite.check(await game._select_hand_discard_result(game.players[0], 1, false) == GameManager.HandDiscardOutcome.ACTION_INVALIDATED, "E03e-14b：实际选牌关闭不是主动拒绝")
	await suite.process_frame
	var new_hand = func():
		var pending = game._choice_prompt_stack.back()
		old_timeout[0].call()
		suite.check(not pending.answer.settled, "E03e-14b：旧选牌计时不会支付新选择")
		pending.overlay.timeout()
	new_hand.call_deferred()
	suite.check(await game._select_hand_discard_result(game.players[0], 1, false) == GameManager.HandDiscardOutcome.DECLINED and game.players[0].hand_size() == 1, "E03e-14b：新选牌取消不支付")
	await suite.process_frame
	reset()
	game._soul_blade_activate_override = Callable()
	game._soul_blade_discard_override = Callable()
	game._plus_mule_target_override = Callable()
	game._rps_override = Callable()
	suite = null
	game = null
