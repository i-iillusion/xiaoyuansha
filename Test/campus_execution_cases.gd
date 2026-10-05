extends RefCounted

var suite
var game: GameManager

func reset(concrete: bool):
	suite.reset_players()
	game.deck._discard.clear()
	game._hand_discard_override = Callable()
	game._rps_override = func(p): return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 0
	var actor = game.players[0]
	var target = game.players[1]
	actor.general_name = "杰基·斯特朗"
	actor.hand.assign([CardBase.create(CardData.CardSubType.PEACH) if concrete else null, null, null])
	target.hand.assign([CardBase.create(CardData.CardSubType.DODGE) if concrete else null])

func pay_current():
	var picker = game._choice_prompt_stack.back().overlay
	var choices = picker.find_children("*", "CheckButton", true, false)
	choices[0].button_pressed = true
	picker.confirm.pressed.emit()

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		for close in [false, true]:
			reset(concrete)
			var actor = game.players[0]
			var target = game.players[1]
			var source_fee = actor.hand[0]
			var target_fee = target.hand[0]
			var duplicate = func():
				var pending = game._choice_prompt_stack.back()
				var owner = game._campus_execution_owner
				await game._execute_campus_dominator(actor, target)
				suite.check(game._choice_prompt_stack.size() == 1 and game._campus_execution_owner == owner and actor.hand_size() == 3 and target.hand_size() == 1, "E03e-17b-2：重复霸主不叠支付窗口或释放原锁")
				if close: pending.overlay.queue_free()
				else: pay_current()
			duplicate.call_deferred()
			await game._execute_campus_dominator(actor, target)
			suite.check(game._campus_execution_owner == -1 and game._choice_prompt_stack.is_empty(), "E03e-17b-2：完成/关闭释放自己的执行锁")
			suite.check(actor.hand_size() == (3 if close else 2) and target.hand_size() == (1 if close else 0) and target.hp == (10 if close else 9), "E03e-17b-2：原有效霸主双方费用一次、零手牌仍拼点、仅一次伤害")
			if concrete: suite.check(game.deck._discard.count(source_fee) == (0 if close else 1) and game.deck._discard.count(target_fee) == (0 if close else 1), "E03e-17b-2：具体双方费用各只入弃一次")
			await suite.process_frame
	for concrete in [false, true]:
		reset(concrete)
		game._rps_override = Callable()
		var actor = game.players[0]
		var target = game.players[1]
		var source_fee = actor.hand[0]
		var target_fee = target.hand[0]
		var capture_old = func():
			var old = game._choice_prompt_stack.back()
			var stale_button = old.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable
			var stale_timeout = game._countdown_on_timeout
			suite.check(actor.hand_size() == 2 and target.hand_size() == 0, "E03e-17b-2：旧真实拼点前双方已各付一次")
			game.reset_game_over_state()
			target.hand.append(null)
			game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
			var settle_new = func():
				var current = game._choice_prompt_stack.back()
				var owner = game._campus_execution_owner
				stale_button.call()
				stale_timeout.call()
				await suite.process_frame
				suite.check(game._campus_execution_owner == owner and not current.answer.settled and game._countdown_active, "E03e-17b-2：同阶段重开后旧拼点/超时/清理不污染新执行")
				seed(104)
				var opponent = randi() % 3
				seed(104)
				var gesture = 0
				for pick in 3:
					if game._rps_result(pick, opponent) == GameManager.RPS_WIN: gesture = pick
				current.overlay.find_children("*", "Button", true, false)[[0, 2, 1][gesture]].pressed.emit()
			settle_new.call_deferred()
			await game._execute_campus_dominator(actor, target)
			var paid = game.deck._discard.count(source_fee) == 1 and game.deck._discard.count(target_fee) == 1 if concrete else true
			suite.check(actor.hand_size() == 1 and target.hand_size() == 0 and target.hp == 9 and paid, "E03e-17b-2：旧费用保留不重复、新双方费用正常、仅新拼点造成一次伤害")
		var pay_old = func():
			capture_old.call_deferred()
			pay_current()
		pay_old.call_deferred()
		await game._execute_campus_dominator(actor, target)
		while game._campus_execution_owner != -1:
			await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty() and actor.hp == 10 and target.hp == 9, "E03e-17b-2：旧拼点不会补伤害，全部等待清理")
		await suite.process_frame
	suite.reset_players()
	game._rps_override = Callable()
	suite = null
	game = null
