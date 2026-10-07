extends "res://Test/terminal_boundary_cases.gd"

# G02d-a only: Q1 deduplication, Q3 unsourced damage. Q4 propagation timing
# and Q2 changing living neighbors are intentionally not claimed here.
func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	for count in [2, 3, 5]:
		for concrete in [false, true]:
			for granted in [false, true]:
				var game = await new_game(suite, count)
				var a = game.players[0]
				var b = game.players[1]
				for p in game.players: p.hp = 4
				b.hp = 3
				var original: CardBase = CardBase.create(CardData.CardSubType.BURNING_CAMP) if concrete else null
				if concrete: a.determined_cards.append(original)
				else: a.hand.append(null)
				await game.execute_card_on_target(b, CardData.CardSubType.BURNING_CAMP)
				var placed = b.judgment_cards[0]
				suite.check(a.hand_size() == 0 and a.hp == 4 and b.hp == 3 and game.deck._discard.is_empty() and (not concrete or placed == original), "G02d-a real arbitrary/concrete fire card waits without immediate damage")
				if granted:
					a.general_name = "麦克斯·欧尼斯特"
					a.hand.append(null)
					game.turn_manager.current_phase = TurnManager.Phase.START
					game._meiyong_override = func(): return true
					game._meiyong_option_override = func(): return 0
					game._meiyong_target_override = func(): return b
					suite.check(await game._maybe_meiyong(a) == 1 and game.turn_manager.current_phase == TurnManager.Phase.START, "G02d-a real gifted fire judgment restores source START")
				else:
					game.turn_manager.current_player_idx = 1
					game.turn_manager.current_phase = TurnManager.Phase.JUDGE
					await game._do_judge(1)
					suite.check(game.turn_manager.current_phase == TurnManager.Phase.DRAW, "G02d-a normal fire judgment advances normally")
				suite.check(a.hp == 3 and b.hp == 2 and (count == 2 or game.players[2].hp == 3), "G02d-a center and unique neighbor each receive exactly one fire damage")
				suite.check(b.judgment_cards.is_empty() and game.deck._discard.count(placed) == 1 and a.judgment_cards.size() == 1 and (count == 2 or game.players[2].judgment_cards.size() == 1), "G02d-a original discarded once; living neighbors' new fire cards wait, no immediate recursion")
				if count == 5: suite.check(game.players[3].hp == 4 and game.players[4].hp == 4 and game.players[3].judgment_cards.is_empty(), "G02d-a non-neighbors untouched in no-death five-player case")
				game.queue_free()
				await suite.process_frame
	# The original living lord gets no rebel kill reward from unsourced fire.
	var game = await new_game(suite, 5)
	game.players[0].hand.append(null)
	game.players[2].hp = 1
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
	var original = game.players[1].judgment_cards[0]
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._do_judge(1)
	suite.check(game.players[2].is_dead() and not game._game_over and game.players[0].hand_size() == 0 and game.deck._discard.count(original) == 1, "G02d-a fire finally kills rebel but living original caster earns no sourced kill reward")
	game.queue_free()
	await suite.process_frame
	# Lower-level accidental caller source must not change Q3 either.
	game = await new_game(suite, 5)
	game.players[2].hp = 1
	await game._resolve_burning_camp_damage(game.players[0], game.players[1], 1)
	suite.check(game.players[2].is_dead() and game.players[0].hand_size() == 0, "G02d-a helper enforces unsourced fire even when caller passes a living source")
	game.queue_free()
	await suite.process_frame
	# Fatal center in two-player mode ends before any neighbor hit or propagation.
	game = await new_game(suite, 2)
	game.players[0].hp = 3
	game.players[1].hp = 1
	game.players[0].hand.append(null)
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.BURNING_CAMP)
	original = game.players[1].judgment_cards[0]
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._do_judge(1)
	suite.check(game._game_over and game.players[0].hp == 3 and game.players[0].judgment_cards.is_empty() and game.deck._discard.count(original) == 1 and game.turn_manager.current_phase == TurnManager.Phase.JUDGE, "G02d-a fatal center commits terminal before neighbor fire or propagation")
	game.queue_free()
	await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
