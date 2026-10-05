extends "res://Test/rescue_cases.gd"

func prepare():
	reset_case()
	game.deck._discard.clear()
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	game.players[0].hand.assign([null, null])
	game.players[2].hp = 0

func run(host):
	suite = host
	game = host.game
	for mode in ["pay", "concrete", "decline", "timeout", "close", "phase", "reset", "end", "hand", "rescuer", "healed", "duplicate"]:
		prepare()
		var victim = game.players[2]
		var helper = game.players[0]
		var concrete = CardBase.create(PEACH)
		if mode == "concrete": helper.hand.assign([concrete, CardBase.create(STRIKE)])
		var chain = game._new_damage_chain(game.players[1], victim, null, 1, EffectChain.DamageType.PHYSICAL)
		var action = func():
			var pending = game._choice_prompt_stack.back()
			var buttons = pending.overlay.find_children("*", "Button", true, false)
			suite.check(buttons.size() == 2 and game._countdown_active, "E03e-21b：真实救他人窗口仅桃/放弃，保留计时")
			match mode:
				"decline": buttons[1].pressed.emit()
				"timeout": game._countdown_on_timeout.call()
				"close": pending.overlay.queue_free()
				"phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
				"reset": game.reset_game_over_state()
				"end": game._game_over = true
				"hand": helper.hand.pop_back()
				"rescuer": helper.mark_dead()
				"healed": victim.hp = 1
				"duplicate":
					suite.check(await game._ask_rescue_card(helper, victim) == GameManager.CHOICE_INVALID and game._choice_prompt_stack.size() == 1, "E03e-21b：重复救援请求不覆盖原窗口或支付")
					buttons[0].pressed.emit()
				_: buttons[0].pressed.emit()
			if mode in ["pay", "concrete", "duplicate"]: buttons[0].pressed.emit()
		action.call_deferred()
		var result = await game._resolve_dying(victim, null, "test", chain)
		var invalid = mode in ["close", "phase", "reset", "end", "hand", "rescuer"]
		suite.check(result == (GameManager.CHOICE_INVALID if invalid else 0) and game._rescue_choice_pending.is_empty() and game._dying_contexts.is_empty(), "E03e-21b：独立救援结果释放原锁，技术失效传到死亡入口")
		if invalid:
			suite.check(victim.is_dying() and not victim.identity_revealed and helper.hand.size() == (1 if mode == "hand" else 2) and chain.continuation_invalid, "E03e-21b：失效不付桃、不误死亡/翻身份，外部移走原牌不回滚")
		elif mode in ["pay", "concrete", "duplicate"]:
			suite.check(victim.hp == 1 and helper.hand.size() == 1 and not victim.identity_revealed and game.deck._discard.size() == 1 and (mode != "concrete" or game.deck._discard[0] == concrete), "E03e-21b：重复点击仅付一张任意/具体桃、救回一次，保留原实例")
		elif mode == "healed":
			suite.check(victim.hp == 1 and helper.hand.size() == 2 and not chain.continuation_invalid, "E03e-21b：正常外部救回结束询问，不支付或误作技术失效")
		else:
			suite.check(victim.is_dead() and victim.identity_revealed and helper.hand.size() == 2 and not chain.continuation_invalid, "E03e-21b：正常放弃/超时不扣救援牌，继续死亡流程")
		game._halt_countdown()
		await suite.process_frame
		suite.check(game.get_node_or_null("UI/RescuePrompt") == null, "E03e-21b：结束清理原救援遮罩")
	prepare()
	var victim = game.players[2]
	var new_done: Array = [false]
	var restart = func():
		var old_answer = game._choice_prompt_stack.back().answer
		var old_timeout = game._countdown_on_timeout
		game.reset_game_over_state()
		var finish = func():
			old_answer.submit(PEACH)
			old_timeout.call()
			var pending = game._choice_prompt_stack.back()
			suite.check(not pending.answer.settled and game._rescue_choice_pending.has(victim), "E03e-21b：重开旧救援按钮/超时不回答新窗口或释放新锁")
			pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
		finish.call_deferred()
		await game._resolve_dying(victim, null, "new")
		new_done[0] = true
	restart.call_deferred()
	suite.check(await game._resolve_dying(victim, null, "old") == GameManager.CHOICE_INVALID, "E03e-21b：重开旧救援执行返回技术失效")
	while not new_done[0]: await suite.process_frame
	suite.check(victim.hp == 1 and game.players[0].hand.size() == 1 and game._rescue_choice_pending.is_empty() and game._dying_contexts.is_empty(), "E03e-21b：重开仅新窗口付一次桃，不删新濒死上下文")
	reset_case()
	suite.reset_players()
	game = null
	suite = null
