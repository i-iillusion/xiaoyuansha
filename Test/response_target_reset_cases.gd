extends "res://Test/target_confirm_cases.gd"

func run(host):
	suite = host
	game = host.game
	for accepted in [false, true]:
		for mode in ["normal", "reset", "phase", "removed"]:
			reset()
			var actor = game.players[0]
			actor.hand.append(null)
			var original_players = game.players.duplicate()
			var decision = func():
				await suite.process_frame
				match mode:
					"reset": game.reset_game_over_state()
					"phase": game.turn_manager.current_phase = TurnManager.Phase.END
					"removed": game.players.erase(actor)
				return accepted
			var result = await game._ask_basic_card_response_result(actor, CardData.CardSubType.DODGE, Callable(), decision)
			var paid = mode == "normal" and accepted
			var expected = GameManager.BasicResponseOutcome.INVALIDATED if mode != "normal" else (GameManager.BasicResponseOutcome.PAID if paid else GameManager.BasicResponseOutcome.DECLINED)
			suite.check(result == expected and actor.hand_size() == (0 if paid else 1) and game.deck._discard.size() == (1 if paid else 0), "E03e-22d-3a：基础响应先复查失效，再区分接受/拒绝，不扣旧牌：%s/%s" % [mode, accepted])
			game.players.assign(original_players)
	reset()
	game.players[0].hand.append(null)
	var invalid = func(): return GameManager.CHOICE_INVALID
	suite.check(await game._ask_basic_card_response_result(game.players[0], CardData.CardSubType.DODGE, Callable(), invalid) == GameManager.BasicResponseOutcome.INVALIDATED and game.players[0].hand_size() == 1, "E03e-22d-3a：显式失效不是truthy接受")
	for chain in [false, true]:
		for concrete in [false, true]:
			reset()
			var sub = CardData.CardSubType.IRON_CHAIN if chain else CardData.CardSubType.STRIKE
			var actor = game.players[0]
			var card = CardBase.create(sub)
			if concrete:
				actor.determined_cards.append(card)
				game._pending_determined_card = card
			else: actor.hand.append(null)
			if chain: game._enter_iron_chain_mode()
			else: game._enter_targeting_mode(sub)
			var next_generation: Array = []
			var restart = func():
				game.reset_game_over_state()
				game._pending_determined_card = card if concrete else null
				# 相同阶段重开且尚未重新进入目标模式，仍不能由旧协程清理。
				next_generation.append(game._card_target_generation)
				game._card_target_confirm_owner = game._card_target_generation
			restart.call_deferred()
			if chain: await game._on_iron_chain_target_click(game.players[1])
			else: await game._on_target_click(game.players[1])
			suite.check(actor.hand_size() == 1 and game.deck._discard.is_empty() and game._card_target_generation == next_generation[0] and game._card_target_confirm_owner == next_generation[0] and game._pending_determined_card == (card if concrete else null), "E03e-22d-3a：实际目标/铁索窗口重开，旧答复不清新锁/原牌")
			await suite.process_frame
	reset()
	game = null
	suite = null
