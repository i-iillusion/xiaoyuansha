extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	var owner: Player = game.players[0]
	owner.hp = 3
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game._rescue_choice_override = func(_r, _v, _o): return -1
	for p in game.players: p.hand.clear()
	var revealed: Array[Player] = [game.players[1]]
	game.fire_dragon_state.record_use(id, 1, revealed)
	t.check(game.get_trick_targets(game.players[1], CardData.CardSubType.BURNING_CAMP).has(dragon), "I03 Q10 B may legally place delayed fire on dragon revealed to B")
	t.check(game._burning_camp_neighbors(dragon) == [game.players[1], owner], "I03 Q10 dragon neighbors are B then A, not B and E")
	t.check(game.ordinary_seat_distance(owner, game.players[2]) == 2 and game.ordinary_seat_distance(dragon, game.players[2]) == 2,
		"I03 Q10 effect adjacency does not add a distance seat")
	game.players[1].hand.append(null)
	game.turn_manager.current_player_idx = 1
	await game.execute_card_on_target(dragon, CardData.CardSubType.BURNING_CAMP)
	t.check(dragon.judgment_cards.size() == 1 and game.players[1].hand_size() == 0, "I03 Q10 B actually pays original arbitrary card into dragon judgment zone")
	var fire = dragon.judgment_cards[0]
	var before: Array = game.players.map(func(p): return p.hp)
	t.check(await game._run_judgment(dragon, false), "I03 Q10 actual dragon judgment completes delayed fire")
	t.check(dragon.hp == 2 and owner.hp == before[0] - 1 and game.players[1].hp == before[1] - 1, "I03 Q10 actual center/A/B each take one fire damage")
	t.check(range(2, 5).all(func(seat): return game.players[seat].hp == before[seat]), "I03 Q10 C/D/E take no adjacent damage")
	t.check(owner.judgment_cards.size() == 1 and game.players[1].judgment_cards.size() == 1 and dragon.judgment_cards.is_empty(), "I03 Q10 fire spreads only to A/B judgment zones")
	t.check(game.deck._discard.count(fire) == 1 and game.players[4].judgment_cards.is_empty(), "I03 Q10 original delayed card discarded once, no E spread")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
