extends RefCounted

var suite
var game: GameManager

func reset(concrete: bool):
	suite.reset_players()
	game.deck._discard.clear()
	game._exit_zhuangbi_mode()
	game._zhuangbi_blocked_this_phase = false
	game._hand_discard_override = Callable()
	game._zhuangbi_again_override = func(): return false
	game._rps_override = func(p): return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 0
	var actor = game.players[0]
	var target = game.players[1]
	actor.general_name = "史蒂芬·彼特先斯"
	actor.hand.assign([CardBase.create(CardData.CardSubType.PEACH) if concrete else null, null, null])
	target.hand.assign([CardBase.create(CardData.CardSubType.DODGE) if concrete else null])

func pay_current():
	var picker = game._choice_prompt_stack.back().overlay
	picker.find_children("*", "CheckButton", true, false)[0].button_pressed = true
	picker.confirm.pressed.emit()

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		for close in [false, true]:
			reset(concrete)
			var actor = game.players[0]
			var target = game.players[1]
			var first = actor.hand[0]
			var second = target.hand[0]
			var duplicate = func():
				var pending = game._choice_prompt_stack.back()
				var owner = game._zhuangbi_execution_owner
				await game._execute_zhuangbi([target])
				suite.check(game._choice_prompt_stack.size() == 1 and game._zhuangbi_execution_owner == owner and actor.hand_size() == 3 and target.hand_size() == 1, "E03e-17b-3：重复装逼不叠支付窗口、不清原锁")
				if close: pending.overlay.queue_free()
				else: pay_current()
			duplicate.call_deferred()
			await game._execute_zhuangbi([target])
			suite.check(game._zhuangbi_execution_owner == -1 and game._choice_prompt_stack.is_empty(), "E03e-17b-3：成功/关闭只释放自己的锁")
			suite.check(actor.hand_size() == (3 if close else 2) and target.hand_size() == (1 if close else 0) and target.hp == (10 if close else 9), "E03e-17b-3：有效装逼双方费用/成功伤害各一次，零手牌仍出拳")
			if concrete: suite.check(game.deck._discard.count(first) == (0 if close else 1) and game.deck._discard.count(second) == (0 if close else 1), "E03e-17b-3：具体原费用不重复弃")
			await suite.process_frame
	for stage in ["rps", "again"]:
		reset(true)
		var actor = game.players[0]
		var target = game.players[1]
		var first = actor.hand[0]
		var second = target.hand[0]
		game._hand_discard_override = func(_snapshot, _count, _mandatory): return [0] # 明确支付本例跟踪的第一张具体牌，不把默认末尾策略当作第一张。
		if stage == "rps": game._rps_override = Callable()
		else: game._zhuangbi_again_override = Callable()
		var restart = func():
			var old = game._choice_prompt_stack.back()
			var stale_button = old.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable
			var stale_timeout = game._countdown_on_timeout
			suite.check(actor.hand_size() == 2 and target.hand_size() == 0 and target.hp == (9 if stage == "again" else 10), "E03e-17b-3：重开前原双方已付费、已完成伤害状态正确")
			game.reset_game_over_state()
			target.hand.append(null)
			var settle = func():
				var current = game._choice_prompt_stack.back()
				var owner = game._zhuangbi_execution_owner
				stale_button.call()
				stale_timeout.call()
				await suite.process_frame
				suite.check(game._zhuangbi_execution_owner == owner and not current.answer.settled and game._countdown_active, "E03e-17b-3：旧出拳/再发动/超时/清理不污染同阶段新执行")
				if stage == "again":
					current.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
				else:
					seed(104)
					var opponent = randi() % 3
					seed(104)
					var gesture = 0
					for pick in 3:
						if game._rps_result(pick, opponent) == GameManager.RPS_WIN: gesture = pick
					current.overlay.find_children("*", "Button", true, false)[[0, 2, 1][gesture]].pressed.emit()
			settle.call_deferred()
			await game._execute_zhuangbi([target])
			suite.check(actor.hand_size() == 1 and target.hand_size() == 0 and target.hp == (8 if stage == "again" else 9) and game.deck._discard.count(first) == 1 and game.deck._discard.count(second) == 1, "E03e-17b-3：旧原费用/伤害保留，新执行只结算一次")
		restart.call_deferred()
		await game._execute_zhuangbi([target])
		while game._zhuangbi_execution_owner != -1:
			await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty() and game._is_zhuangbi_targeting == (stage == "again") and not game._zhuangbi_blocked_this_phase, "E03e-17b-3：只有新成功确认可再发动，旧执行不改新目标模式或平局禁用")
		await suite.process_frame
	reset(true)
	var actor = game.players[0]
	var target = game.players[1]
	actor.hand.resize(1)
	var fee = actor.hand[0]
	game._awaken_pick_override = Callable()
	var awaken = func():
		var pending = game._choice_prompt_stack.back()
		var owner = game._zhuangbi_execution_owner
		await game._execute_zhuangbi([target])
		suite.check(game._choice_prompt_stack.size() == 1 and game._zhuangbi_execution_owner == owner and actor.max_hp == 9 and actor.hand_size() == 2, "E03e-17b-3：最后手牌支付后觉醒期间重复执行不重付/重扣上限/重摸")
		pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
	var pay = func():
		awaken.call_deferred()
		pay_current()
	pay.call_deferred()
	await game._execute_zhuangbi([target])
	suite.check(actor.awoken and actor.awake_choice == 1 and actor.hand_size() == 2 and actor.max_hp == 9 and target.hp == 9 and game.deck._discard.count(fee) == 1, "E03e-17b-3：觉醒只结算一次，原有效装逼继续目标费用/伤害")
	suite.check(game._zhuangbi_execution_owner == -1 and game._choice_prompt_stack.is_empty(), "E03e-17b-3：觉醒组合结束锁和等待清理")
	await suite.process_frame
	reset(false)
	game._rps_override = Callable()
	game._zhuangbi_again_override = Callable()
	game._awaken_pick_override = Callable()
	suite = null
	game = null
