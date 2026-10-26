extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for mode in ["hidden", "shown", "unit_source", "wrap", "indulgence", "supply", "chain"]: await check_case(t, mode)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func check_case(t, mode: String):
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	var owner: Player = game.players[0]
	owner.hp = 3
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, owner)
	var id = game.unit_registry.id_for(dragon)
	for p in game.players: p.hand.clear()
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game._rescue_choice_override = func(_r, _d, _o): return -1
	game._dodge_override = func(): return false
	if mode in ["indulgence", "supply", "chain"]:
		var shown: Array[Player] = [game.players[1]]
		game.fire_dragon_state.record_use(id, 1, shown)
		game._card_action_serial = 1 # Match the prepared historical USE receipt.
		if mode == "chain":
			game.turn_manager.current_unit_id = id
			dragon.hand.append(null)
			var targets: Array[Player] = [dragon, game.players[1]]
			await game._execute_iron_chain(targets)
			t.check(dragon.chained and game.players[1].chained and dragon.hand_size() == 0, "I03 actual unit iron-chain uses its own original hand and both targets")
			t.check(game.fire_dragon_state.is_revealed_to(id, dragon), "I03 actual iron-chain USE records its self target after prepared history")
			game.turn_manager.current_unit_id = ""
			game.turn_manager.current_player_idx = 1
			game.players[1].hand.append(null)
			var hp = game.players[1].hp
			await game.execute_card_on_target(dragon, CardData.CardSubType.FIRE_STRIKE)
			t.check(dragon.hp == 2 and game.players[1].hp == hp - 1 and owner.hp == 3 and not dragon.chained and not game.players[1].chained,
				"I03 fire damage propagates between actual unit and fixed player once, not to controller")
		else:
			game.turn_manager.current_player_idx = 1
			game.players[1].hand.append(null)
			await game.execute_card_on_target(dragon, CardData.CardSubType.INDULGENCE if mode == "indulgence" else CardData.CardSubType.SUPPLY_SHORTAGE)
			t.check(dragon.judgment_cards.size() == 1 and owner.judgment_cards.is_empty(), "I03 delay actually paid into visible dragon zone: " + mode)
			var original = dragon.judgment_cards[0]
			game.turn_manager.current_player_idx = 0
			game.turn_manager.current_unit_id = id
			game.turn_manager.current_phase = TurnManager.Phase.JUDGE
			await game._do_judge(0)
			await game._do_draw(0)
			if mode == "indulgence":
				await game._do_play(0)
				t.check(dragon.hand_size() == 1 and game.turn_manager.current_phase == TurnManager.Phase.DISCARD, "I03 unit indulgence skips actual unit PLAY, draws own one")
			else: t.check(dragon.hand_size() == 0 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I03 unit supply shortage reduces own one-card draw to zero")
			t.check(game.deck._discard.count(original) == 1 and owner.hand_size() == 0 and dragon.judgment_cards.is_empty(), "I03 unit delay consumed once without borrowing controller zone/hand")
	else:
		var holder: Player = dragon if mode in ["unit_source", "wrap"] else owner
		if mode == "shown":
			var shown: Array[Player] = [owner]
			game.fire_dragon_state.record_use(id, 1, shown)
		if mode == "wrap":
			for seat in game.players.size():
				game.turn_manager.current_player_idx = seat
				game.players[seat].hand.append(null)
				await game.play_card(CardData.CardSubType.LIGHTNING)
		game.turn_manager.current_player_idx = 0
		game.turn_manager.current_unit_id = id if holder == dragon else ""
		holder.hand.append(null)
		await game.play_card(CardData.CardSubType.LIGHTNING)
		var original = holder.judgment_cards[0]
		var uses = game._card_action_serial
		owner.hand.append(null) # _nullify_override answers the local human, not an AI.
		game._nullify_override = func(): return true
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		t.check(await game._run_judgment(holder, false), "I03 actual lightning nullification/transfer finishes: " + mode)
		var dest: Player = dragon if mode in ["shown", "wrap"] else game.players[1]
		t.check(dest.judgment_cards.has(original) and not game.deck._discard.has(original), "I03 lightning retains original and uses legal character successor: " + mode)
		t.check(holder.hp == 3 and game._card_action_serial == uses + 1, "I03 only actual nullification adds card event, movement adds no USE or damage")
		if mode in ["hidden", "unit_source"]:
			t.check(not game.fire_dragon_state.is_revealed_to(id, owner if mode == "hidden" else game.players[1]), "I03 lightning movement never invents dragon revelation")
		if mode == "wrap":
			t.check(dragon.judgment_cards == [original], "I03 original returned to unit waits instead of repeating same judgment")
			game._nullify_override = func(): return false
			t.check(await game._run_judgment(dragon, false) and dragon.is_dead() and game.deck._discard.count(original) == 1,
				"I03 returned unit lightning hits next judgment, real unit rescue/death and one discard")
	game._game_over = true
	game.queue_free()
	await t.process_frame
