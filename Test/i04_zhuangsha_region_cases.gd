extends RefCounted

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["two_walls_win","two_walls_lose","one_wall","no_walls","alone"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
		load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,2 if mode.begins_with("two") else (1 if mode == "one_wall" else 0))
		var dying = game.players[4]
		if mode == "alone":
			game._spawn_mountain_at(game.players[5],3,4)
			game._spawn_mountain_at(game.players[5],4,5)
		dying.general_name = "安普提·斯丢皮得"
		dying.hp = 1
		for p in game.players: p.hand.clear(); p.determined_cards.clear()
		var seen: Array = []
		game._rps_override = func(p):
			if p == dying: return game.RPS_ROCK
			seen.append(p.seat_index)
			return game.RPS_SCISSORS if p.seat_index == 1 or (p.seat_index == 2 and mode != "two_walls_lose") else game.RPS_PAPER
		await game._deal_damage(null if mode == "alone" else game.players[3],dying,1,EffectChain.DamageType.PHYSICAL)
		var expected = [] if mode == "alone" else ([1,2,3] if mode.begins_with("two") else [0,1,2,3,5])
		t.check(seen == expected, "I04 Q53 actual dying pipeline asks only same-region fixed players, no summoned units: " + mode)
		var saved_life = mode == "two_walls_win"
		t.check(dying.is_alive() == saved_life and dying.hp == (1 if saved_life else 0), "I04 Q53 uses same-region denominator: 2/3 saves, 1/3 or 2/5 does not")
		t.check(game._dying_contexts.is_empty() and not game._game_over, "I04 Q53 completes rescue/predeath settlement without ending surviving multiplayer game")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
