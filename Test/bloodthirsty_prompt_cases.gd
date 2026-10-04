extends RefCounted

var suite
var game: GameManager
var windows: Array = []
var asks := 0
var punches := 0

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._bloodthirsty_override = Callable()
	game._rps_override = func(p):
		punches += 1
		return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	asks = 0
	punches = 0

func drive(action: String, source: Player, victim: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	asks += 1
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 2 and not game._countdown_active, "E03e-10a：发动与放弃，无新增计时")
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
			if action == "same_weapon": source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
		"shield": victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
		"source_dead", "victim_dead":
			var dead = source if action == "source_dead" else victim
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "E03e-10a回归")
			return
	var accept = action == "yes_yes" or (action == "yes_no" and asks == 1) or (action == "no_yes" and asks == 2)
	if action in ["yes_yes", "yes_no", "no_yes", "no_no"] and asks == 1:
		drive.call_deferred(action, source, victim)
	buttons[0 if accept else 1].pressed.emit()
	pending.answer.submit(1)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["yes_yes", "yes_no", "no_yes", "no_no", "close", "phase", "phase_idle", "actor", "weapon", "same_weapon", "shield", "source_dead", "victim_dead", "ended"]:
			reset()
			events.clear()
			var source = game.players[0]
			var victim = game.players[1]
			source.hp = 8
			source.wine_stacks = 1
			source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
			var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: source.determined_cards.append(kill)
			else: source.hand.append(null)
			drive.call_deferred(action, source, victim)
			await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
			var wins = 2 if action == "yes_yes" else (1 if action in ["yes_no", "no_yes"] else 0)
			suite.check(source.hp == (0 if action == "source_dead" else 8 + wins), "E03e-10a：逐点选择仅获胜回血：" + action)
			suite.check(victim.hp == (0 if action == "victim_dead" else 8), "E03e-10a：已造成两点伤害不回滚：" + action)
			suite.check(asks == (2 if action in ["yes_yes", "yes_no", "no_yes", "no_no"] else 1), "E03e-10a：失效不是拒绝，不再询问下一点")
			suite.check(punches == wins * 2, "E03e-10a：拒绝及失效不出拳，不额外支付手牌")
			suite.check(events.size() == 1 and source.hand.is_empty() and (not concrete or game.deck._discard.count(kill) == 1), "E03e-10a：真实杀仅支付及提交一次")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-10a：确认等待已结束")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-10a：窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var source = game.players[0]
	var victim = game.players[1]
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_bloodthirsty_prompt(source, victim) == GameManager.CHOICE_INVALID, "E03e-10a：外部关闭明确失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._response_ready.emit()
		suite.check(not pending.answer.settled, "E03e-10a：旧按钮及共享响应不污染新窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_bloodthirsty_prompt(source, victim) == 0, "E03e-10a：下一合法放弃正常完成")
	await suite.process_frame
	reset()
	source = game.players[1]
	victim = game.players[2]
	source.hp = 9
	source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == source else GameManager.RPS_SCISSORS
	await game._try_bloodthirsty(source, victim, 2)
	suite.check(source.hp == 10 and game._choice_prompt_stack.is_empty(), "E03e-10a：AI每点沿用不满血才发动，满血后不再发动")
	game._bloodthirsty_override = func(): return GameManager.CHOICE_INVALID
	source.hp = 8
	suite.check(await game._try_bloodthirsty(source, victim, 2) == GameManager.CHOICE_INVALID and source.hp == 8, "E03e-10a：显式失效不得转成bool真值")
	reset()
	game._rps_override = Callable()
	suite = null
	game = null
