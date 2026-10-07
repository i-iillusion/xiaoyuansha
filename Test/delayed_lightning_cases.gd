extends "res://Test/terminal_boundary_cases.gd"

func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	for concrete in [false, true]:
		for mode in ["normal", "grant", "move", "dead", "duplicate", "return"]:
			var game = await new_game(suite, 5)
			var a = game.players[0]
			for p in game.players: p.hp = 4
			var remaining: CardBase = null
			if mode == "return":
				game.turn_manager.current_player_idx = 4
				game.players[4].hand.append(null)
				await game.execute_card_on_target(a, CardData.CardSubType.INDULGENCE)
				remaining = a.judgment_cards[0]
				game.turn_manager.current_player_idx = 0
			var original: CardBase = CardBase.create(CardData.CardSubType.LIGHTNING) if concrete else null
			if concrete: a.determined_cards.append(original)
			else: a.hand.append(null)
			await game.play_card(CardData.CardSubType.LIGHTNING)
			var placed = a.judgment_cards.back()
			suite.check(a.hand_size() == 0 and placed.sub_type == CardData.CardSubType.LIGHTNING and (not concrete or placed == original) and not game.deck._discard.has(placed) and a.hp == 4, "G02c real arbitrary/concrete lightning waits, original retained on use: " + mode)
			if mode in ["duplicate", "return"]:
				for seat in (range(1, 5) if mode == "return" else [1]):
					game.turn_manager.current_player_idx = seat
					game.players[seat].hand.append(null)
					await game.play_card(CardData.CardSubType.LIGHTNING)
			if mode == "dead":
				game.players[1].hp = 1
				await game._deal_damage_result(game.players[2], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
				suite.check(game.players[1].is_dead() and not game._game_over, "G02c real next-seat death leaves ongoing legal identity game")
			game.turn_manager.current_player_idx = 0
			game.turn_manager.current_phase = TurnManager.Phase.JUDGE
			if mode in ["move", "dead", "duplicate", "return"]:
				a.hand.append(null)
				game._nullify_override = Callable()
				var accept = func():
					game._nullify_override = func(): return false
					game._choice_prompt_stack.back().overlay.find_children("*", "Button", true, false)[0].pressed.emit()
				accept.call_deferred()
				await game._do_judge(0)
				var destination = a if mode == "return" else game.players[2 if mode in ["dead", "duplicate"] else 1]
				suite.check(destination.judgment_cards.has(placed) and game.deck._discard.count(placed) == 0 and placed.source_seat == 0 and a.hp == 4 and a.hand_size() == 0, "G02c paid real nullification moves same lightning; skips dead/duplicate, no premature damage: " + mode)
				suite.check(game.turn_manager.current_phase == TurnManager.Phase.DRAW, "G02c movement completes actual judgment without extra turn: " + mode)
				if mode == "return":
					suite.check(a.judgment_cards == [placed] and game.deck._discard.count(remaining) == 1 and game.turn_manager.skip_play_phase, "G02c deferred own lightning does not block other pending judgment")
					game.turn_manager.current_phase = TurnManager.Phase.JUDGE
					await game._do_judge(0)
					suite.check(a.hp == 1 and a.judgment_cards.is_empty() and game.deck._discard.count(placed) == 1, "G02c returned original hits only next actual judgment")
			elif mode == "grant":
				game.players[1].general_name = "麦克斯·欧尼斯特"
				game.players[1].hand.append(null)
				game.turn_manager.current_player_idx = 1
				game.turn_manager.current_phase = TurnManager.Phase.START
				game._meiyong_override = func(): return true
				game._meiyong_option_override = func(): return 0
				game._meiyong_target_override = func(): return a
				suite.check(await game._maybe_meiyong(game.players[1]) == 1 and game.turn_manager.current_phase == TurnManager.Phase.START, "G02c real grant lightning restores source START")
				suite.check(a.hp == 1 and a.judgment_cards.is_empty() and game.deck._discard.count(placed) == 1, "G02c lightning still inflicts three thunder in granted judgment")
			else:
				await game._do_judge(0)
				suite.check(a.hp == 1 and game.turn_manager.current_phase == TurnManager.Phase.DRAW and game.deck._discard.count(placed) == 1 and a.judgment_cards.is_empty(), "G02c normal actual judgment damages three and discards same original once")
			game.queue_free()
			await suite.process_frame
	var game = await new_game(suite, 5)
	var a = game.players[0]
	a.hand.assign([null, null])
	await game.play_card(CardData.CardSubType.LIGHTNING)
	var original = a.judgment_cards[0]
	await game.play_card(CardData.CardSubType.LIGHTNING)
	suite.check(a.hand_size() == 1 and a.judgment_cards == [original] and not game.can_declare_trick(a, CardData.CardSubType.LIGHTNING, true), "G02c same-name lightning illegal before physical or virtual payment")
	game.queue_free()
	await suite.process_frame
	# Existing full judgment/terminal prompt modules remain mounted. Add actual
	# placement before a stale nullification window, including independent move.
	for mode in ["close", "phase", "reset", "move", "end"]:
		game = await new_game(suite, 5)
		a = game.players[0]
		a.hand.assign([null, null])
		await game.play_card(CardData.CardSubType.LIGHTNING)
		original = a.judgment_cards[0]
		game._nullify_override = Callable()
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		var invalidate = func():
			match mode:
				"close": game._choice_prompt_stack.back().overlay.queue_free()
				"phase": game.turn_manager.current_phase = TurnManager.Phase.END
				"reset": game.reset_game_over_state()
				"move":
					a.judgment_cards.erase(original)
					game.players[2].judgment_cards.append(original)
				"end": game._finish_game("平局", "G02c defensive terminal boundary")
		invalidate.call_deferred()
		await game._do_judge(0)
		suite.check(a.hp == a.max_hp and a.hand_size() == 1 and game.deck._discard.is_empty() and a.judgment_cards.has(original) == (mode != "move"), "G02c stale original judgment does not nullify/damage/pay/discard on " + mode)
		suite.check(game.turn_manager.current_phase == (TurnManager.Phase.END if mode == "phase" else TurnManager.Phase.JUDGE), "G02c stale placement-judgment entry never advances old stage on " + mode)
		await suite.process_frame
		suite.check(game._choice_prompt_stack.is_empty(), "G02c stale window has no residual owner on " + mode)
		game.queue_free()
		await suite.process_frame
	GameManager.selected_players = previous[0]
	# A real fatal lightning ends the two-player game before chain transmission.
	game = await new_game(suite, 2)
	a = game.players[0]
	a.hp = 1
	game.players[1].hp = 3
	a.chained = true
	game.players[1].chained = true
	a.hand.append(null)
	await game.play_card(CardData.CardSubType.LIGHTNING)
	original = a.judgment_cards[0]
	var winners: Array = []
	game.game_over.connect(func(w): winners.append(w))
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._do_judge(0)
	suite.check(a.is_dead() and winners == [game.players[1].player_name] and game.players[1].hp == 3 and game.players[1].hand_size() == 0, "G02c real fatal lightning commits winner once before unsourced chain, no FFA reward")
	suite.check(game.deck._discard.count(original) == 1 and a.judgment_cards.is_empty() and game.turn_manager.current_phase == TurnManager.Phase.JUDGE, "G02c terminal lightning releases original once and does not advance DRAW")
	game.queue_free()
	await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
