extends RefCounted

# Controlled legal decisions on a real initialized scene. No fabricated card facts,
# duplicate Leo, changed victory evaluator, or production scheduling shortcuts.
func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode,
		GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for count in [2, 3, 5]:
		var traces: Array = []
		for repeat in 2:
			GameManager.selected_players = count
			GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY if count == 5 else GameManager.MODE_FREE_FOR_ALL
			GameManager.selected_general = "里奥·普利威尔"
			GameManager.random_general = false
			GameManager.random_identity = false
			var game: GameManager = load("res://Scenes/Game.tscn").instantiate()
			game.auto_start = false
			suite.root.add_child(game)
			await suite.process_frame
			# Disable only automatic phase-to-AI advancement, not the tested card/dying flows.
			game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
			var winners: Array = []
			game.game_over.connect(func(winner): winners.append(winner))
			game._dying_peach_override = Callable()
			game._rescue_choice_override = func(_r, _d, _options): return -1
			game._duel_respond_override = func(): return false
			game._nullify_override = func(): return false
			game._sacrifice_override = func(): return false
			game._zone_pick_override = func(): return "hand"
			game._ai_response_override = func(_view, _kind, options): return CardData.CardSubType.STRIKE if options.has(CardData.CardSubType.STRIKE) else -1
			game._prep_replace_override = func(_l, _u, _t, current, _options): return CardData.CardSubType.DUEL if current == CardData.CardSubType.SNATCH else -1
			game.start_game()
			game._stop_countdown()
			var tm = game.turn_manager
			var leo = game.players[0]
			var target = game.players[1]
			var expected_hp = 6 if count == 5 else 5
			suite.check(game.players.size() == count and leo.general_name == "里奥·普利威尔" and leo.max_hp == expected_hp and leo.hp == expected_hp and leo.hand == [null, null, null, null] and leo.prep_tokens == 0,
				"F03b actual %d-player start has correct Leo HP/lord bonus/four arbitrary cards/no marks" % count)
			suite.check(leo.identity_max_hp_bonus == (1 if count == 5 else 0) and game.players.slice(1).all(func(p): return p.identity_max_hp_bonus == 0 and p.hp == GeneralData.get_max_hp(p.general_name)),
				"F03b only classic lord gets one identity-layer bonus; FFA and other generals unchanged")
			tm.current_phase = TurnManager.Phase.DRAW
			game._do_draw(0)
			suite.check(leo.hand.size() == 5 and tm.current_phase == TurnManager.Phase.PLAY, "F03b actual draw phase applies choutai once and enters PLAY")
			await game.play_card(CardData.CardSubType.WINE)
			suite.check(leo.hand.size() == 4 and leo.prep_tokens == 1 and tm.wine_count_this_turn == 1, "F03b actual own completed wine grants one usable old mark")
			leo.hp = 1
			target.hp = 2
			await game.execute_card_on_target(target, CardData.CardSubType.SNATCH)
			var results: Array = []
			for result in game.yudaxi.results: results.append([result.deaths, result.aborted])
			suite.check(leo.hp == 1 and leo.is_alive() and target.is_dead() and game.yudaxi.results.size() == 1 and game.yudaxi.results[0].deaths == 1,
				"F03b actual paid Snatch becomes Duel, failed response enters and survives yudaxi")
			suite.check(leo.hand.size() == 4 and target.hand_size() == 0 and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty() and not game.yudaxi.is_active(),
				"F03b parent once paid, extra draw unaffected by choutai, no null-source kill reward or context leak")
			suite.check(tm.duel_count_this_turn == 1 and tm.steal_count_this_turn == 0 and leo.prep_tokens == (0 if count == 2 else 1),
				"F03b final category counted; ongoing parent completes, terminal parent is abandoned not fake completed")
			if count == 2:
				suite.check(game._game_over and winners.size() == 1, "F03b two-player yudaxi winner is final survivor only after all dying windows settle")
			else:
				suite.check(not game._game_over and winners.is_empty(), "F03b successful yudaxi does not prematurely end three-player/classic mode")
				# Existing remaining player legally pays a real Duel; Leo declines its response.
				var next_actor = game.players[2]
				tm.current_player_idx = 2
				tm._reset_turn_counts()
				tm.current_phase = TurnManager.Phase.PLAY
				await game.execute_card_on_target(leo, CardData.CardSubType.DUEL)
				suite.check(leo.is_dead() and leo.hp == 0 and game.yudaxi.results.size() == 1 and game.yudaxi.results[0].deaths == 0,
					"F03b next actual paid Duel fails X-zero yudaxi and confirms final death")
				suite.check(leo.hand_size() == 0 and leo.equipment.is_empty() and leo.judgment_cards.is_empty() and next_actor.hand.size() == 3,
					"F03b final death clears all zones after failure; hostile killer pays original card once")
				for result in game.yudaxi.results: results.append([result.deaths, result.aborted])
			var outcome = IdentityVictory.evaluate(game.players) if count == 5 else FreeForAllVictory.evaluate(game.players)
			suite.check(game._game_over and not outcome.is_empty() and winners == [outcome.get("winner", "")], "F03b mode final winner agrees with independent victory evaluator")
			var state: Array = []
			for p in game.players:
				state.append([p.seat_index, p.hp, p.is_dead(), p.hand_size(), p.prep_tokens, p.identity_revealed])
			var settled = [state, results, winners.duplicate(), game.deck._discard.size()]
			await suite.process_frame
			await suite.process_frame
			suite.check(winners.size() == 1 and game._pending_card_actions.is_empty() and game._dying_contexts.is_empty() and game._choice_prompt_stack.is_empty(), "F03b final scene has one winner, no late choice/card/dying continuation")
			var later: Array = []
			for p in game.players: later.append([p.seat_index, p.hp, p.is_dead(), p.hand_size(), p.prep_tokens, p.identity_revealed])
			suite.check(later == state and game.deck._discard.size() == settled[3], "F03b final HP/card/identity state stays stable across later frames")
			# Primitive reset is tested here only for start snapshot separation, not a
			# legal revival of a final dead player or a second victory notification.
			leo.restore_game_start_state()
			suite.check(leo.max_hp == expected_hp and leo.hp == expected_hp and leo.prep_tokens == 0 and leo.identity_max_hp_bonus == (1 if count == 5 else 0),
				"F03b general reset retains current identity bonus without adding it twice")
			traces.append(settled)
			game.queue_free()
			await suite.process_frame
		suite.check(traces[0] == traces[1], "F03b %d-player controlled full lifecycle repeats deterministically" % count)
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
	# Separate production default action-policy evidence: six complete games,
	# no forced HP, no controlled phase advancement, actual terminal state.
	await load("res://Test/full_game_cases.gd").new().run(suite, "里奥·普利威尔", "F03b-AI")
