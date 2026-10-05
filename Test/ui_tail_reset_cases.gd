extends "res://Test/target_confirm_cases.gd"

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		reset()
		var actor = game.players[0]
		var original = CardBase.create(CardData.CardSubType.STRIKE)
		if concrete:
			actor.determined_cards.append(original)
			game._pending_determined_card = original
		else: actor.hand.append(null)
		actor.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
		game.players[1].hand.append(null)
		var next_card = CardBase.create(CardData.CardSubType.PEACH)
		game._dodge_override = func():
			await suite.process_frame
			game.reset_game_over_state()
			actor.determined_cards.append(next_card)
			game._pending_determined_card = next_card
			return false
		game._is_multi_targeting = true
		game._targeting_card_sub = CardData.CardSubType.STRIKE
		game._multi_targets.assign([game.players[1], game.players[2]])
		await game._on_confirm_multi_target()
		suite.check(game._pending_determined_card == next_card and actor.determined_cards.has(next_card) and game.players[1].hp == 10 and game.players[2].hp == 10 and game.deck._discard.size() == 1 and (not concrete or game.deck._discard.count(original) == 1), "E03e-22d-3d：真实方天响应重开停止余目标，旧UI不清新原牌，已支付杀保留")
	for mode in ["normal", "close", "reset"]:
		reset()
		var actor = game.players[0]
		actor.hand.assign([null, null])
		actor.sage_tokens = 0
		actor.sage_activated = false
		actor.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
		game._start_sage_ping_mode(actor)
		game._rps_override = func(p): return GameManager.RPS_ROCK if p == actor else GameManager.RPS_SCISSORS
		if mode != "normal":
			game._rps_override = Callable()
			var action = func():
				var pending = game._choice_prompt_stack.back()
				if mode == "close": pending.overlay.queue_free()
				else:
					game.reset_game_over_state()
					game._start_sage_ping_mode(actor)
			action.call_deferred()
		await game._on_sage_target_click(game.players[1])
		suite.check(actor.sage_tokens == (1 if mode == "normal" else 0) and actor.hand_size() == 1 and game._is_sage_targeting == (mode == "reset") and game._play_btn.visible == (mode != "reset") and game._end_play_btn.visible == (mode != "reset"), "E03e-22d-3d：贤者主动拼点正常/关闭/同阶段重开，旧窗口不写新标记/恢复新选择按钮：" + mode)
		await suite.process_frame
	reset()
	game._rps_override = Callable()
	game = null
	suite = null
