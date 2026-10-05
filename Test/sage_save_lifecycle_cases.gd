extends RefCounted

var suite
var game: GameManager

func prepare(phase):
	suite.reset_players()
	game.deck._discard.clear()
	game._sage_save_override = Callable()
	game.turn_manager.current_phase = phase
	game.players[0].identity = "忠臣"
	game.players[0].identity_revealed = false
	game.players[0].hp = 0
	game.players[0].hand.assign([null, CardBase.create(CardData.CardSubType.STRIKE)])
	game.players[0].judgment_cards.assign([CardBase.create(CardData.CardSubType.INDULGENCE)])
	game.players[0].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
	game.players[0].sage_activated = true

func run(host):
	suite = host
	game = host.game
	for phase in [TurnManager.Phase.JUDGE, TurnManager.Phase.PLAY]:
		for mode in ["accept", "decline", "timeout", "close", "phase", "reset", "armor", "end", "shared", "duplicate"]:
			prepare(phase)
			var victim = game.players[0]
			var original = victim.get_equipment_card("armor")
			var judgment = victim.judgment_cards[0]
			var chain = game._new_damage_chain(game.players[1], victim, null, 1, EffectChain.DamageType.PHYSICAL)
			var action = func():
				var overlay = game._choice_prompt_stack.back().overlay
				var buttons = overlay.find_children("*", "Button", true, false)
				suite.check(buttons.size() == 2 and game._countdown_active, "E03e-21a：真实贤者窗口两按钮，保留原响应倒计时")
				match mode:
					"decline": buttons[1].pressed.emit()
					"timeout": game._countdown_on_timeout.call()
					"close": overlay.queue_free()
					"phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
					"reset": game.reset_game_over_state()
					"armor": victim.remove_equipment("armor")
					"end": game._game_over = true
					"shared":
						game._response_ready.emit()
						suite.check(not game._choice_prompt_stack.back().answer.settled, "E03e-21a：旧共享回答不能决定贤者保命")
						buttons[0].pressed.emit()
					"duplicate":
						suite.check(await game._ask_sage_save(victim) == GameManager.CHOICE_INVALID and game._choice_prompt_stack.size() == 1, "E03e-21a：同一濒死者重复发起不覆盖原等待")
						buttons[0].pressed.emit()
					_: buttons[0].pressed.emit()
				if mode in ["accept", "shared", "duplicate"]: buttons[0].pressed.emit()
			action.call_deferred()
			var result = await game._resolve_dying(victim, null, "test", chain)
			var saved = mode in ["accept", "shared", "duplicate"]
			var invalid = mode in ["close", "phase", "reset", "armor", "end"]
			suite.check(result == (GameManager.CHOICE_INVALID if invalid else 0) and game._sage_save_pending.is_empty() and game._dying_contexts.is_empty(), "E03e-21a：贤者答复与失效向死亡入口传播，原等待释放")
			if saved:
				suite.check(victim.is_alive() and victim.hand == [null, null, null, null] and victim.judgment_cards.is_empty() and victim.get_armor() == -1 and not victim.identity_revealed and victim.identity == "忠臣", "E03e-21a：有效发动复原武将，清自己区域摸4，身份不恢复或公开")
				suite.check(game.deck._discard.count(original) == 1 and game.deck._discard.count(judgment) == 1, "E03e-21a：重复按钮不重复清牌或摸牌")
			elif invalid:
				suite.check(victim.is_dying() and victim.hand.size() == 2 and victim.judgment_cards == [judgment] and not victim.identity_revealed and chain.continuation_invalid, "E03e-21a：技术失效不误复活/确认死亡/翻身份/清原牌，停止原效果链")
			else:
				suite.check(victim.is_dead() and victim.hand.is_empty() and victim.judgment_cards.is_empty() and victim.identity_revealed and not chain.continuation_invalid, "E03e-21a：正常放弃/超时继续实际死亡，非技术失效")
			game._halt_countdown()
			await suite.process_frame
			suite.check(game.get_node_or_null("UI/SageSavePrompt") == null, "E03e-21a：结束没有残留贤者遮罩")
	prepare(TurnManager.Phase.JUDGE)
	var victim = game.players[0]
	var new_done: Array = [false]
	var restart = func():
		var old_answer = game._choice_prompt_stack.back().answer
		var old_timeout = game._countdown_on_timeout
		game.reset_game_over_state()
		var finish_new = func():
			old_answer.submit(1)
			old_timeout.call()
			var pending = game._choice_prompt_stack.back()
			suite.check(not pending.answer.settled and game._sage_save_pending.has(victim), "E03e-21a：重开旧按钮/超时不回答新贤者窗口或清新锁")
			pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
		finish_new.call_deferred()
		await game._resolve_dying(victim, null, "new")
		new_done[0] = true
	restart.call_deferred()
	suite.check(await game._resolve_dying(victim, null, "old") == GameManager.CHOICE_INVALID, "E03e-21a：旧濒死执行重开后明确失效")
	while not new_done[0]: await suite.process_frame
	suite.check(victim.is_alive() and victim.hand == [null, null, null, null] and game._dying_contexts.is_empty() and game._sage_save_pending.is_empty(), "E03e-21a：重开仅新有效答复清牌摸4，旧上下文不删新窗口")
	suite.reset_players()
	game._sage_save_override = Callable()
	game = null
	suite = null
