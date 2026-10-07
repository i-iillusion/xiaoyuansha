extends RefCounted

# Real initialized scenes and real card/dying routes. Controlled choices only;
# an explicitly pre-existing dying/dead state is not a new simultaneous effect.
func new_game(suite, count: int, general: String = "稻草人") -> GameManager:
	GameManager.selected_players = count
	GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY if count == 5 else GameManager.MODE_FREE_FOR_ALL
	GameManager.selected_general = general
	GameManager.random_general = false
	GameManager.random_identity = false
	var game: GameManager = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	suite.root.add_child(game)
	await suite.process_frame
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game._rescue_choice_override = func(_r, _d, _o): return -1
	game._dodge_override = func(): return false
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game.start_game()
	game._stop_countdown()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hand.clear()
		p.determined_cards.clear()
	return game

func run(suite):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	for concrete in [false, true]:
		for element in [CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE]:
			var game = await new_game(suite, 2)
			var a = game.players[0]
			var b = game.players[1]
			a.hp = 1
			b.hp = 1
			a.chained = true
			b.chained = true
			var original: CardBase = CardBase.create(element) if concrete else null
			if concrete: a.determined_cards.append(original)
			else: a.hand.append(null)
			var weapon = CardBase.create(CardData.CardSubType.POFENG_SPEAR)
			a.equip_card_to_slot("weapon", weapon)
			var winners: Array = []
			game.game_over.connect(func(w): winners.append(w))
			await game.execute_card_on_target(b, element)
			suite.check(game._game_over and winners == [a.player_name] and a.hp == 1 and a.is_alive() and b.is_dead(), "G01a real paid elemental kill ends before chain reaches last survivor")
			suite.check(a.hand_size() == 0 and game.deck._discard.size() == 1 and (not concrete or game.deck._discard[0] == original), "G01a arbitrary/concrete payment once, original object retained, no FFA reward")
			suite.check(a.hand_limit_bonus == 0 and a.chained and b.chained, "G01a no ordinary post-damage spear bonus or chain processing after terminal commit")
			suite.check(game._dead_processed == [b] and game._dying_contexts.is_empty() and game._pending_card_actions.is_empty(), "G01a final death once, dying/card owners released")
			var hp_before = a.hp
			await game._deal_damage_result(null, a, 1, EffectChain.DamageType.PHYSICAL)
			suite.check(a.hp == hp_before and a.is_alive(), "G01a late damage entry after game over cannot mutate winner")
			game._check_win_condition(null, null)
			game._handle_death(b, a)
			await suite.process_frame
			suite.check(winners.size() == 1 and game.deck._discard.size() == 1 and not game._countdown_active, "G01a duplicate checks/death and later frame cannot award or end twice")
			game.queue_free()
			await suite.process_frame
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
