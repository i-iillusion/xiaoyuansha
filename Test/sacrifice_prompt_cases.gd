extends RefCounted

var suite
var game: GameManager

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._sacrifice_override = Callable()

func drive(action: String):
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
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			buttons[0].pressed.emit()
		"hand":
			game.players[0].hand.append(null)
			buttons[0].pressed.emit()
		"ended": game._finish_game("平局", "E03e-2回归")

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["accept", "decline", "timeout", "close", "phase", "hand", "ended"]:
			reset()
			events.clear()
			var rescuer = game.players[0]
			var target = game.players[1]
			var source = game.players[2]
			var original = CardBase.create(CardData.CardSubType.SACRIFICE) if concrete else null
			if concrete:
				rescuer.determined_cards.append(original)
			else:
				rescuer.hand.append(null)
			drive.call_deferred(action)
			await game._deal_damage(source, target, 2, EffectChain.DamageType.PHYSICAL)
			if action == "accept":
				suite.check(target.hp == 10 and rescuer.hp == 8 and rescuer.hand_size() == 0
					and events.size() == 1 and game.deck._discard.size() == 1
					and (not concrete or game.deck._discard[0] == original), "E03e-2：真实伤害链舍己仅支付一次并转移全部伤害")
			else:
				var declined = action in ["decline", "timeout", "hand"]
				suite.check(target.hp == (8 if declined else 10) and rescuer.hp == 10,
					"E03e-2：拒绝/未能支付继续原伤害，失效停止旧伤害：" + action)
				suite.check(rescuer.hand_size() == (2 if action == "hand" else 1) and events.is_empty()
					and game.deck._discard.is_empty(), "E03e-2：不虚构舍己支付或使用事件")
			await suite.process_frame
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-2：舍己窗口已释放")
	# 是啊无牌虚拟使用只支付体力一次；二级窗口失效无费用且不继续原伤害。
	for virtual_use in [false, true]:
		reset()
		events.clear()
		var rescuer = game.players[0]
		rescuer.general_name = "安普提·斯丢皮得"
		if not virtual_use: rescuer.hand.append(null)
		var decide = func():
			drive("accept")
			if not virtual_use: drive.call_deferred("close")
		decide.call_deferred()
		await game._deal_damage(game.players[2], game.players[1], 2, EffectChain.DamageType.PHYSICAL)
		suite.check(game.players[1].hp == 10 and rescuer.hp == (7 if virtual_use else 10)
			and rescuer.hand_size() == (0 if virtual_use else 1) and events.size() == (1 if virtual_use else 0)
			and game.deck._discard.is_empty(), "E03e-2：是啊虚拟使用/二级关闭区分，不误收费")
		await suite.process_frame
	# 已支付卡牌后上下文失效：费用不回滚，也不安排新伤害。
	reset()
	var original = CardBase.create(CardData.CardSubType.SACRIFICE)
	game.players[0].hand.append(original)
	var invalidate = func(_event): game.turn_manager.current_phase = TurnManager.Phase.END
	game.card_action_committed.connect(invalidate)
	drive.call_deferred("accept")
	await game._deal_damage(game.players[2], game.players[1], 2, EffectChain.DamageType.PHYSICAL)
	suite.check(game.players[0].hp == 10 and game.players[1].hp == 10 and game.players[0].hand_size() == 0
		and game.deck._discard.count(original) == 1, "E03e-2：已用舍己后失效不返还牌、不继续转移")
	game.card_action_committed.disconnect(invalidate)
	await suite.process_frame
	# 旧超时及共享信号不能污染下一次合法窗口。
	reset()
	game.players[0].hand.append(null)
	var saved: Array = []
	var close_first = func():
		saved.append(game._countdown_on_timeout)
		drive("close")
	close_first.call_deferred()
	await game._deal_damage(game.players[2], game.players[1], 2, EffectChain.DamageType.PHYSICAL)
	await suite.process_frame
	var second = func():
		var pending = game._choice_prompt_stack.back()
		game._response_ready.emit()
		saved[0].call()
		suite.check(not pending.answer.settled, "E03e-2：旧信号/旧超时不能替新舍己作答")
		drive("accept")
	second.call_deferred()
	await game._deal_damage(game.players[2], game.players[1], 2, EffectChain.DamageType.PHYSICAL)
	suite.check(game.players[0].hp == 8 and game.players[1].hp == 10 and game.players[0].hand_size() == 0,
		"E03e-2：旧窗口失效后下一次合法转移正常")
	await suite.process_frame
	game.card_action_committed.disconnect(collect)
	reset()
	game.turn_manager.current_phase = phase
	suite = null
	game = null
