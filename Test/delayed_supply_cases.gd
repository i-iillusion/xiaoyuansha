extends "res://Test/delayed_indulgence_cases.gd"

func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	await run_delayed(suite, CardData.CardSubType.SUPPLY_SHORTAGE, "G02b")
	await run_limits(suite, CardData.CardSubType.SUPPLY_SHORTAGE, "supply_shortage", "G02b")
	var game = await new_game(suite, 5)
	var a = game.players[0]
	a.hand.append(null)
	await game.execute_card_on_target(game.players[2], CardData.CardSubType.SUPPLY_SHORTAGE)
	suite.check(a.hand_size() == 1 and game.players[2].judgment_cards.is_empty() and game.turn_manager._get_turn_count("supply_shortage", 0) == 0, "G02b distance two rejects before payment or quota")
	game.players[1].equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.TENGJIA))
	suite.check(game.get_trick_targets(a, CardData.CardSubType.SUPPLY_SHORTAGE).has(game.players[1]), "G02b legal delayed target not filtered by unrelated strike armor immunity")
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.SUPPLY_SHORTAGE)
	suite.check(a.hand_size() == 0 and game.players[1].judgment_cards.size() == 1, "G02b armor does not prevent legal delayed placement")
	game.queue_free()
	await suite.process_frame
	# DRAW base modifiers are separate from the one-card shortage.
	for general in ["里奥·普利威尔", "比尔·盖伊"]:
		game = await new_game(suite, 5)
		var b = game.players[1]
		b.general_name = general
		var original = CardBase.create(CardData.CardSubType.SUPPLY_SHORTAGE)
		b.judgment_cards.append(original)
		game.turn_manager.current_player_idx = 1
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		await game._do_judge(1)
		await game._do_draw(1)
		suite.check(b.hand_size() == (0 if general == "里奥·普利威尔" else 2) and game.turn_manager.current_phase == TurnManager.Phase.PLAY and not game.turn_manager.supply_shortage_active and game.deck._discard.count(original) == 1, "G02b real normal DRAW applies shortage after locked base draw: " + general)
		game.queue_free()
		await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
