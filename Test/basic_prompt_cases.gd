extends RefCounted

func run(suite):
	var game: GameManager = suite.game
	var tm = game.turn_manager
	var old_phase = tm.current_phase
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for kind in ["aoe", "duel", "second", "dodge"]:
		for concrete in [false, true]:
			for action in ["accept", "decline", "timeout", "close", "phase", "hand", "ended"]:
				suite.reset_players()
				tm.current_phase = TurnManager.Phase.PLAY
				game._aoe_override = Callable()
				game._duel_respond_override = Callable()
				game._duel_second_override = Callable()
				game._dodge_override = Callable()
				game.deck._discard.clear()
				events.clear()
				var p: Player = game.players[0]
				var expected = CardData.CardSubType.DODGE if kind == "dodge" else CardData.CardSubType.STRIKE
				var original: CardBase = CardBase.create(expected) if concrete else null
				if concrete:
					p.determined_cards.append(original)
				else:
					p.hand.append(null)
				var prompt: Callable
				match kind:
					"aoe": prompt = game._show_aoe_prompt.bind("南蛮入侵", "杀")
					"duel": prompt = game._show_duel_prompt.bind(true)
					"second": prompt = game._show_duel_second_strike_prompt
					"dodge": prompt = game._show_dodge_prompt.bind("玩家2", "杀")
				var drive = func():
					var pending = game._choice_prompt_stack.back()
					var buttons = pending.overlay.find_children("*", "Button", true, false)
					match action:
						"accept":
							buttons[0].pressed.emit()
							pending.answer.submit(1)
						"decline": buttons[1].pressed.emit()
						"timeout": game._countdown_on_timeout.call()
						"close": pending.overlay.queue_free()
						"phase":
							tm.current_phase = TurnManager.Phase.END
							tm.current_phase = TurnManager.Phase.PLAY
							buttons[0].pressed.emit()
						"hand":
							p.hand.append(null)
							buttons[0].pressed.emit()
						"ended": game._finish_game("平局", "E03d回归")
				drive.call_deferred()
				var result = await game._ask_basic_card_response_result(p, expected, prompt)
				var wanted = GameManager.BasicResponseOutcome.PAID if action == "accept" else (
					GameManager.BasicResponseOutcome.DECLINED if action in ["decline", "timeout", "hand"] else GameManager.BasicResponseOutcome.INVALIDATED)
				suite.check(result == wanted, "E03d：真实响应区分成功/放弃/失效：" + kind + "/" + action)
				if action == "accept":
					suite.check(p.hand_size() == 0 and events.size() == 1 and game.deck._discard.size() == 1
						and (not concrete or game.deck._discard[0] == original),
						"E03d：重复按钮只支付并记录一次原响应牌")
				else:
					suite.check(p.hand_size() == (2 if action == "hand" else 1) and events.is_empty()
						and game.deck._discard.is_empty(), "E03d：放弃/失效不支付或发响应事件")
				await suite.process_frame
				suite.check(game._choice_prompt_stack.is_empty(), "E03d：响应窗口释放且无残留等待")
	# 真实杀链：外部销毁响应窗口是旧动作失效，不是主动不出闪而受伤。
	for close in [false, true]:
		suite.reset_players()
		tm.current_phase = TurnManager.Phase.PLAY
		game._dodge_override = Callable()
		var p: Player = game.players[0]
		p.hand.append(null)
		var decide = func():
			var pending = game._choice_prompt_stack.back()
			if close:
				pending.overlay.queue_free()
			else:
				pending.answer.submit(0)
		decide.call_deferred()
		await suite.strike(game.players[1], p)
		suite.check(p.hp == (10 if close else 9) and p.hand_size() == 1,
			"E03d：真实杀链窗口失效停止伤害，明确放弃仍受伤")
		await suite.process_frame
	# 决斗第一/第二次响应失效均不当作认输；第一张已经支付不返还。
	for second in [false, true]:
		suite.reset_players()
		tm.current_phase = TurnManager.Phase.PLAY
		game._duel_respond_override = Callable()
		game._duel_second_override = Callable()
		game.deck._discard.clear()
		var actor: Player = game.players[1]
		var responder: Player = game.players[0]
		actor.general_name = "杰基·斯特朗"
		var first = CardBase.create(CardData.CardSubType.STRIKE)
		var remaining = CardBase.create(CardData.CardSubType.FIRE_STRIKE)
		responder.hand.assign([remaining, first])
		var close_response = func():
			game._choice_prompt_stack.back().overlay.queue_free()
		var drive_duel = func():
			if second:
				game._choice_prompt_stack.back().answer.submit(1)
				close_response.call_deferred()
			else:
				close_response.call()
		drive_duel.call_deferred()
		await game._play_duel(actor, responder)
		suite.check(actor.hp == 10 and responder.hp == 10 and responder.hand_size() == (1 if second else 2),
			"E03d：真实决斗响应失效不造成伤害且已付第一张不返还")
		suite.check(game.deck._discard.size() == (1 if second else 0), "E03d：决斗失效不伪造第二次支付")
		await suite.process_frame
	# 4号出群体锦囊，第一响应者0号窗口关闭，不能伤害0号或继续后续目标。
	suite.reset_players()
	tm.current_phase = TurnManager.Phase.PLAY
	tm.current_player_idx = 4
	game._aoe_override = Callable()
	game.players[4].hand.append(CardBase.create(CardData.CardSubType.BARBARIAN_INVASION))
	game.players[0].hand.append(null)
	var close_aoe = func(): game._choice_prompt_stack.back().overlay.queue_free()
	close_aoe.call_deferred()
	await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
	suite.check(game.players[0].hp == 10 and game.players[1].hp == 10 and game.players[0].hand_size() == 1
		and game.players[4].hand_size() == 0, "E03d：真实AOE响应失效停止旧链，已使用的锦囊不返还")
	await suite.process_frame
	game.card_action_committed.disconnect(collect)
	suite.reset_players()
	tm.current_phase = old_phase
