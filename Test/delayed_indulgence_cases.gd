extends "res://Test/terminal_boundary_cases.gd"

# CARD-01, TURN-02, adopted book 3.1/4.2.1. No new judge randomness.
func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	await run_delayed(suite, CardData.CardSubType.INDULGENCE, "G02a")
	await run_limits(suite, CardData.CardSubType.INDULGENCE, "indulgence", "G02a")
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]

func run_limits(suite, sub: CardData.CardSubType, key: String, label: String):
	var game = await new_game(suite, 5)
	var a = game.players[0]
	a.hand.assign([null, null, null])
	await game.execute_card_on_target(game.players[1], sub)
	var original = game.players[1].judgment_cards[0]
	await game.execute_card_on_target(game.players[1], sub)
	suite.check(a.hand_size() == 2 and game.players[1].judgment_cards == [original] and game.turn_manager._get_turn_count(key, 0) == 1 and not game.get_trick_targets(a, sub).has(game.players[1]), label + " duplicate original name is illegal before payment/count; UI and execution agree")
	await game.execute_card_on_target(game.players[4], sub)
	suite.check(a.hand_size() == 1 and game.turn_manager._get_turn_count(key, 0) == 2 and not game.can_declare_trick(a, sub, true), label + " two uses reached even with virtual payment")
	await game.execute_card_on_target(game.players[2], sub)
	suite.check(a.hand_size() == 1 and game.players[2].judgment_cards.is_empty() and game.deck._discard.is_empty(), label + " third use cannot pay or place")
	game.turn_manager.current_player_idx = 1
	game.players[1].hand.append(null)
	suite.check(game.can_declare_trick(game.players[1], sub) and game.turn_manager._get_turn_count(key, 1) == 0, label + " delayed use quota belongs to actual actor, not global")
	game.turn_manager._reset_turn_counts()
	suite.check(game.can_declare_trick(game.players[1], sub), label + " next-turn counts clear without removing original judgments")
	game.queue_free()
	await suite.process_frame

func run_delayed(suite, sub: CardData.CardSubType, label: String):
	for concrete in [false, true]:
		for mode in ["normal", "grant", "skip"]:
			var game = await new_game(suite, 5)
			var a = game.players[0]
			var b = game.players[1]
			var original: CardBase = CardBase.create(sub) if concrete else null
			if concrete: a.determined_cards.append(original)
			else: a.hand.append(null)
			await game.execute_card_on_target(b, sub)
			suite.check(a.hand_size() == 0 and b.judgment_cards.size() == 1 and game.deck._discard.is_empty(), label + " paid card waits in judgment, not discarded or resolved on use")
			var placed: CardBase = b.judgment_cards[0]
			suite.check(placed.sub_type == sub and placed.source_seat == 0 and (not concrete or placed == original), label + " arbitrary concretizes; concrete keeps original instance/source metadata")
			suite.check(not game.turn_manager.skip_play_phase and not game.turn_manager.supply_shortage_active and game._pending_card_actions.is_empty(), label + " placement completes use without premature stage modifier")
			if mode == "grant":
				a.general_name = "麦克斯·欧尼斯特"
				a.hand.append(null)
				game.turn_manager.current_phase = TurnManager.Phase.START
				game._meiyong_override = func(): return true
				game._meiyong_option_override = func(): return 0
				game._meiyong_target_override = func(): return b
				var turn = game.turn_manager.turn_id
				suite.check(await game._maybe_meiyong(a) == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.turn_id == turn and game.turn_manager.granted_judge_completed, label + " real granted judgment returns to source START without extra turn")
				suite.check(not game.turn_manager.skip_play_phase and not game.turn_manager.supply_shortage_active and b.hand_size() == 0 and a.hand_size() == 2, label + " granted judgment has no later-stage penalty; only source draws grant reward")
				game.turn_manager.current_phase = TurnManager.Phase.JUDGE
				await game._do_judge(0)
				suite.check(game.turn_manager.current_phase == TurnManager.Phase.DRAW and not game.turn_manager.granted_judge_completed, label + " later source judgment consumes grant completion once")
			else:
				game.turn_manager.current_player_idx = 1
				game.turn_manager.current_phase = TurnManager.Phase.JUDGE
				if mode == "skip":
					game.turn_manager.skip_judge_phase = true
					await game._do_judge(1)
					suite.check(b.judgment_cards == [placed] and game.deck._discard.is_empty() and not game.turn_manager.skip_judge_phase and game.turn_manager.current_phase == TurnManager.Phase.DRAW, label + " skipped judgment leaves original for next judgment")
					game.turn_manager.current_phase = TurnManager.Phase.JUDGE
				await game._do_judge(1)
				suite.check(game.turn_manager.current_phase == TurnManager.Phase.DRAW and (game.turn_manager.skip_play_phase if sub == CardData.CardSubType.INDULGENCE else game.turn_manager.supply_shortage_active), label + " actual normal judgment applies only its own pending modifier")
				await game._do_draw(1)
				suite.check(b.hand == ([null, null] if sub == CardData.CardSubType.INDULGENCE else [null]) and game.turn_manager.current_phase == (TurnManager.Phase.DISCARD if sub == CardData.CardSubType.INDULGENCE else TurnManager.Phase.PLAY), label + " real draw/phase consumes skip PLAY or draws one fewer, not skip DRAW")
				suite.check(not game.turn_manager.skip_play_phase and not game.turn_manager.supply_shortage_active, label + " normal modifier consumed exactly once")
			suite.check(b.judgment_cards.is_empty() and game.deck._discard.count(placed) == 1, label + " completed judgment discards the same original exactly once")
			game.queue_free()
			await suite.process_frame
	# Drive real human nullification prompts, not an injected completed result.
	for mode in ["decline", "accept", "timeout", "close", "phase", "reset", "move", "end"]:
		var game = await new_game(suite, 5)
		game.players[0].hand.append(null)
		await game.execute_card_on_target(game.players[1], sub)
		var original = game.players[1].judgment_cards[0]
		game.players[0].hand.append(null)
		game._nullify_override = Callable()
		game.turn_manager.current_player_idx = 1
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		var drive = func():
			var pending = game._choice_prompt_stack.back()
			game._nullify_override = func(): return false
			match mode:
				"close": pending.overlay.queue_free()
				"phase": game.turn_manager.current_phase = TurnManager.Phase.END
				"reset": game.reset_game_over_state()
				"move":
					game.players[1].judgment_cards.erase(original)
					game.players[2].judgment_cards.append(original)
				"end": game._finish_game("平局", label + " defensive terminal boundary")
				"timeout": game._countdown_on_timeout.call()
				_:
					pending.overlay.find_children("*", "Button", true, false)[0 if mode == "accept" else 1].pressed.emit()
		drive.call_deferred()
		await game._do_judge(1)
		var completed = mode in ["decline", "accept", "timeout"]
		suite.check(game.deck._discard.count(original) == (1 if completed else 0) and game.players[1].judgment_cards.has(original) == (not completed and mode != "move"), label + " real judge original ownership on " + mode)
		suite.check(game.turn_manager.current_phase == (TurnManager.Phase.DRAW if completed else (TurnManager.Phase.END if mode == "phase" else TurnManager.Phase.JUDGE)), label + " invalidated judgment never advances old stage on " + mode)
		suite.check((game.turn_manager.skip_play_phase if sub == CardData.CardSubType.INDULGENCE else game.turn_manager.supply_shortage_active) == (mode in ["decline", "timeout"]), label + " nullification versus technical invalidation on " + mode)
		suite.check(game.players[0].hand_size() == (0 if mode == "accept" else 1) and game.deck._discard.size() == (2 if mode == "accept" else (1 if completed else 0)), label + " nullification payment and delayed discard each exactly once on " + mode)
		if mode == "move": suite.check(game.players[2].judgment_cards == [original], label + " stale judge never recovers independently moved original")
		await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty() and game._pending_card_actions.is_empty(), label + " no residual prompt or completion owner on " + mode)
		game.queue_free()
		await suite.process_frame
	for empty in [false, true]:
		var game = await new_game(suite, 5)
		var original = CardBase.create(sub)
		if not empty: game.players[0].judgment_cards.append(original)
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		game.turn_manager.skip_judge_phase = true
		game._finish_game("平局", label + " late entry")
		await game._do_judge(0)
		suite.check(game.turn_manager.current_phase == TurnManager.Phase.JUDGE and game.turn_manager.skip_judge_phase and game.deck._discard.is_empty() and game.players[0].judgment_cards.has(original) == not empty, label + " terminal entry preserves stage/flags/original even with empty judgment")
		game.queue_free()
		await suite.process_frame
