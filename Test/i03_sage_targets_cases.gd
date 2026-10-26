extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in ["hidden", "visible", "hand_remove", "rps_remove", "unit_source"]:
		var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
		game.lan_enabled = true
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		var owner: Player = game.players[0]
		var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
		var id = game.unit_registry.id_for(dragon)
		var wearer: Player = dragon if mode == "unit_source" else game.players[1]
		var target: Player = game.players[1] if mode == "unit_source" else dragon
		game.turn_manager.current_player_idx = 0 if mode == "unit_source" else 1
		if mode == "unit_source": game.turn_manager.current_unit_id = id
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game._set_input_player(wearer)
		owner.hand.clear()
		wearer.hand.assign([null])
		var original = CardBase.create(CardData.CardSubType.LIANNU)
		game.players[2].equip_card_to_slot("weapon", original)
		wearer.determined_cards.append(game.players[2].remove_equipment("weapon"))
		wearer.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
		var choices: Array = []
		game._rps_override = func(body):
			choices.append(body)
			if mode == "rps_remove" and body == wearer:
				owner.mark_dead() # Defensive interruption, not an invented effect.
				game._remove_summoner_units(owner)
			return 0 if body == wearer else 2
		game._hand_discard_override = func(snapshot, count, mandatory):
			t.check(snapshot.owner == wearer and count == 1 and not mandatory, "I03 Sage cost belongs to actual wearer")
			if mode == "hand_remove":
				owner.mark_dead()
				game._remove_summoner_units(owner)
			return [1]
		if mode not in ["hidden", "unit_source"]:
			var shown: Array[Player] = [wearer]
			game.fire_dragon_state.record_use(id, 1, shown)
		game._start_sage_ping_mode(wearer)
		await game._on_sage_target_click(target)
		if mode == "hidden":
			t.check(game._is_sage_targeting and wearer.hand_size() == 2 and choices.is_empty(), "I03 Sage click cannot select hidden dragon or pay cost")
			t.check(not await game._sage_ping(wearer, target) and wearer.hand_size() == 2, "I03 Sage direct entry also rejects hidden dragon")
		elif mode == "hand_remove":
			t.check(wearer.hand_size() == 2 and not game.deck._discard.has(original) and wearer.sage_tokens == 0 and choices.is_empty(), "I03 removed unit during cost selection prevents payment and RPS")
		elif mode == "rps_remove":
			t.check(wearer.hand_size() == 1 and game.deck._discard.count(original) == 1 and wearer.sage_tokens == 0 and choices == [wearer], "I03 removed unit after Sage payment grants no late token, no refund")
		else:
			t.check(wearer.sage_tokens == 1 and choices == [wearer, target] and wearer.hand_size() == 1 and game.deck._discard.count(original) == 1,
				"I03 legal unit Sage interaction spends exact original and awards once: " + mode)
			if mode == "unit_source": t.check(owner.hand_size() == 0 and not game.fire_dragon_state.is_revealed_to(id, target), "I03 unit equipment activation neither spends owner's cards nor invents card USE revelation")
		game._game_over = true
		game.queue_free()
		await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
