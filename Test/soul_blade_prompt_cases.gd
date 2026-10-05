extends RefCounted

var suite
var game: GameManager
var windows: Array = []
var punches := 0

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._soul_blade_activate_override = Callable()
	game._soul_blade_discard_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	punches = 0
	game._rps_override = func(p):
		punches += 1
		return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	for p in game.players:
		p.facedown = false
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(action: String, source: Player, victim: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 2 and not game._countdown_active, "E03e-14a：摄魂确认两项，无倒计时")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = -1
		"weapon", "same_weapon":
			source.determined_cards.append(source.remove_equipment("weapon"))
			if action == "same_weapon":
				source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.SOUL_BLADE))
				source.soul_blade_activated = true
		"shield": victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
		"source_dead", "victim_dead":
			var dead = source if action == "source_dead" else victim
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "E03e-14a回归")
			return
	buttons[1 if action == "no" else 0].pressed.emit()
	pending.answer.submit(1)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["yes", "no", "close", "phase", "phase_idle", "actor", "weapon", "same_weapon", "shield", "source_dead", "victim_dead", "ended"]:
			reset()
			events.clear()
			var source = game.players[0]
			var victim = game.players[1]
			var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
			blade.soul_blade_activated = true
			source.equip_card_to_slot("weapon", blade)
			victim.equip_card_to_slot(Player.MOUNT_SLOTS[0], CardBase.create(CardData.CardSubType.MULE_PLUS))
			var later: Array = []
			game._plus_mule_target_override = func():
				later.append(true)
				return "cancel"
			var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: source.determined_cards.append(kill)
			else: source.hand.append(null)
			drive.call_deferred(action, source, victim)
			await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
			suite.check(victim.hp == (0 if action == "victim_dead" else 9), "E03e-14a：原杀已提交伤害不回滚：" + action)
			suite.check(victim.facedown == (action == "yes") and punches == (4 if action == "yes" else 0), "E03e-14a：仅有效发动两次拼点，过期不翻面")
			suite.check(later.size() == (1 if action in ["yes", "no"] else 0), "E03e-14a：放弃继续受伤后效，失效必须停止")
			suite.check(events.size() == 1 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-14a：真实杀只支付提交一次")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-14a：窗口等待清理")
			await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-14a：所有旧窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_soul_blade_activate_prompt("B") == GameManager.CHOICE_INVALID, "E03e-14a：外部关闭显式失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._response_ready.emit()
		suite.check(not pending.answer.settled, "E03e-14a：旧按钮与共享信号不污染新窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_soul_blade_activate_prompt("B") == 0, "E03e-14a：下一窗口可以正常放弃")
	await suite.process_frame
	reset()
	var source = game.players[1]
	var victim = game.players[2]
	var blade = CardBase.create(CardData.CardSubType.SOUL_BLADE)
	blade.soul_blade_activated = true
	source.equip_card_to_slot("weapon", blade)
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == source else GameManager.RPS_SCISSORS
	suite.check(await game._try_soul_blade(source, victim) == 0 and victim.facedown and game._choice_prompt_stack.is_empty(), "E03e-14a：AI沿用直接发动，无人类确认窗口")
	reset()
	game._plus_mule_target_override = Callable()
	game._rps_override = Callable()
	suite = null
	game = null
