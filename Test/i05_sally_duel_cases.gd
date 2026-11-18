extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var fixture = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for mode in ["ordinary","jackie","jackie_unboosted","decline","invalid"]:
		var game = fixture.fixture(t)
		var sally = game.players[0]
		var target = game.players[1]
		sally.sally_smoking_enabled = true
		if mode != "jackie_unboosted": sally.sally_boost_turn = game.turn_manager.turn_id
		if mode.begins_with("jackie"): target.general_name = "杰基·斯特朗"
		var duel = CardBase.create(CardData.CardSubType.DUEL)
		sally.determined_cards.append(duel)
		sally.hand.append_array([null,null] if mode.begins_with("jackie") else [null])
		target.hand.append_array([null,null] if mode != "jackie_unboosted" else [null])
		var windows: Array = []
		game._duel_respond_override = func():
			windows.append([game._local_player(),1])
			return true
		game._duel_second_override = func():
			windows.append([game._local_player(),2])
			if mode == "invalid": game._dying_lifecycle_generation += 1
			return mode != "decline"
		var facts: Array = []
		var initial_discard_count = game.deck.discard_count()
		game.card_action_committed.connect(func(event): facts.append(event))
		await game.execute_card_on_target(target,CardData.CardSubType.DUEL)
		var expected = [[target,1],[target,2]]
		var payers = [target]
		match mode:
			"ordinary":
				expected.append([sally,1])
				payers.append_array([target,sally])
			"jackie":
				expected = [[sally,1],[sally,2],[target,1],[target,2]]
				payers = [sally,sally,target,target]
			"jackie_unboosted":
				expected = [[sally,1],[sally,2],[target,1]]
				payers = [sally,sally,target]
		t.check(windows == expected, "I05e5b actual Duel response order and quotas: " + mode)
		var actual_payers: Array = []
		for event in facts:
			if event.kind == CardActionEvent.Kind.RESPONSE and event.settlement_completed:
				actual_payers.append(event.actor_body)
		t.check(actual_payers == payers and game.deck.discard_count() == initial_discard_count+payers.size()+1, "I05e5b each completed physical response paid once: " + mode)
		var sally_loses = mode.begins_with("jackie")
		t.check(sally.hp == (2 if sally_loses else 3) and target.hp == (5 if sally_loses or mode == "invalid" else 4), "I05e5b Duel damage occurs only after a failed response: " + mode)
		t.check(facts.size() == payers.size()+1 and facts[0].card == duel and facts[0].settlement_completed == (mode != "invalid") and game._pending_card_actions.is_empty(), "I05e5b paid parent Duel completes once or abandons on technical failure: " + mode)
		await fixture.dispose(t,game)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]; GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]
