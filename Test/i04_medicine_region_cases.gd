extends RefCounted

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["none","single","same","across","stale"]:
		for concrete in [false,true]:
			var game=load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
			load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game,0 if mode=="none" else (1 if mode=="single" else 2))
			for p in game.players: p.hand.clear(); p.determined_cards.clear()
			var actor=game.players[1]
			var target=game.players[0 if mode=="across" else 2]
			actor.general_name="克里斯·西弗"
			game.turn_manager.current_phase=TurnManager.Phase.DRAW
			var original=CardBase.create(CardData.CardSubType.LIANNU)
			if concrete: target.determined_cards.append(original)
			else: target.hand.append(null)
			t.check(game._medicine_candidates(actor).has(target)==(mode!="across"),"I04 medicine candidates exclude cross-region while single/no mountain still permits")
			game._medicine_choice_override=func(_p,_options):
				if mode=="stale":
					var mountains=game.unit_registry.active_units().filter(func(body): return game._is_mountain_body(body))
					var live: Array[int]=[0,1,2,3,4,5]
					game.mountain_space.move(game.unit_registry.id_for(mountains[0]),1,2,live)
				return [target]
			var moved=mode not in ["across","stale"]
			var result=await game._draw_phase_cards(actor)
			t.check(result==moved and actor.hand_size()==(1 if moved else 0) and target.hand_size()==(0 if moved else 1),"I04 medicine actual DRAW replacement moves one legal card only; stale/cross selection cannot draw or steal")
			t.check(game._medicine_pending.is_empty(),"I04 medicine invalid/successful resolution releases lease")
			if concrete: t.check((actor.hand.has(original) if moved else target.determined_cards.has(original)) and game.deck._discard.count(original)==0,"I04 medicine transfer keeps same concrete original and never discards it")
			await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
