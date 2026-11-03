extends RefCounted

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game.lan_enabled = true
	game._spawn_mountain_at(game.players[0],0,1)
	game._spawn_mountain_at(game.players[0],3,4)
	return game

func put(game,sub):
	# Explicit old-card boundary: A legally placed it before the walls existed.
	var card = CardBase.create(sub)
	card.source_seat = 0
	game.players[1].judgment_cards.append(card)
	return card

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for sub in [CardData.CardSubType.BURNING_CAMP,CardData.CardSubType.LIGHTNING,CardData.CardSubType.INDULGENCE,CardData.CardSubType.SUPPLY_SHORTAGE]:
		for mode in ["odd","even","self","pass"]:
			var game = fixture(t)
			var original = put(game,sub)
			for p in game.players: p.hand.append(null)
			var offered: Array = []
			var actions: Array = []
			game.card_action_committed.connect(func(event): actions.append(event))
			game._nullify_override = func():
				var seat = game._input_seat
				offered.append(seat)
				if game.players[seat].hand_size() == 0: return false
				if seat in [0,4]: return true # Must never be asked across the walls.
				return (mode in ["odd","even"] and seat == 2) or (mode == "even" and seat == 3) or (mode == "self" and seat == 1)
			t.check(await game._run_judgment(game.players[1],false), "I04 Q47 old delayed judgment completes despite original source A being isolated: %s/%s"%[sub,mode])
			var expected = [2,3,1] if mode == "pass" else ([2,3,1,2,3] if mode == "even" else ([2,3,1,2,3,1] if mode == "self" else [2,3,1,2]))
			t.check(offered == expected and original.source_seat == 0, "I04 Q47 first response starts at holder B's downstream C; counters follow last actor, metadata stays A")
			t.check(game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1, "I04 Q42 old player judgment excludes willing opposite-region A/E without payment")
			var active = mode in ["even","pass"]
			if sub == CardData.CardSubType.BURNING_CAMP:
				t.check(game.players[1].hp == (4 if active else 5) and game.deck._discard.count(original) == 1, "I04 old Fire uses chain parity and discards original exactly once")
			elif sub == CardData.CardSubType.LIGHTNING:
				t.check(game.players[1].hp == (2 if active else 5) and (game.deck._discard.count(original) == 1 if active else game.players[2].judgment_cards == [original]), "I04 old Lightning either deals thunder or transfers the exact original to next legal C")
			elif sub == CardData.CardSubType.INDULGENCE:
				t.check(game.turn_manager.skip_play_phase == active and game.deck._discard.count(original) == 1, "I04 old Indulgence uses scoped parity without losing skip effect")
			else:
				t.check(game.turn_manager.supply_shortage_active == active and game.deck._discard.count(original) == 1, "I04 old Supply Shortage uses scoped parity without losing draw modifier")
			t.check(actions.size() == (2 if mode == "even" else (0 if mode == "pass" else 1)) and actions.all(func(e): return e.settlement_completed), "I04 old judgment commits only actual counters, all completed once")
			t.check(game.players[1].judgment_cards.is_empty() and game._pending_card_actions.is_empty() and game._input_seat == 0, "I04 scoped holder judgment returns parent input without fabricating original card USE")
			await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await granted(t)
	await lan(t)
	await stale(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func granted(t):
	for sub in [CardData.CardSubType.BURNING_CAMP,CardData.CardSubType.LIGHTNING,CardData.CardSubType.INDULGENCE,CardData.CardSubType.SUPPLY_SHORTAGE]:
		var game = fixture(t)
		put(game,sub)
		for p in game.players: p.hand.append(null)
		var offered: Array = []
		game._nullify_override = func():
			offered.append(game._input_seat)
			return game._input_seat == 2 and game.players[2].hand_size() > 0
		t.check(await game._run_judgment(game.players[1],true), "I04 gifted judgment retains its existing delayed-card rules")
		var dangerous = sub in [CardData.CardSubType.BURNING_CAMP,CardData.CardSubType.LIGHTNING]
		t.check(offered == ([2,3,1,2] if dangerous else []) and not game.turn_manager.skip_play_phase and not game.turn_manager.supply_shortage_active, "I04 gifted fire/Lightning use holder downstream; Indulgence/Supply do not create forbidden response windows")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func bridge_fixture(t):
	var bridge = load("res://Test/i04_aoe_region_cases.gd").new().bridge_fixture(t,4)
	var game = bridge.game
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game._spawn_mountain_at(game.players[4],0,1)
	game._spawn_mountain_at(game.players[4],3,4)
	var original = put(game,CardData.CardSubType.BURNING_CAMP)
	for seat in [0,1,2,4]: game.players[seat].hand.append(null)
	game._nullify_override = Callable()
	return [bridge,original]

func lan(t):
	var data = bridge_fixture(t)
	var bridge = data[0]
	var game = bridge.game
	load("res://Test/i04_aoe_region_cases.gd").new().click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	var find = load("res://Test/i04_movement_cases.gd").new()
	var token = find.find(bridge.snapshot(2),"打出【无懈可击】")
	t.check(token != "" and bridge.input_owner() == 2 and bridge.snapshot(0).controls.is_empty() and bridge.snapshot(4).controls.is_empty(), "I04 Q47 natural B JUDGE offers actual downstream C before B, excludes original source A")
	t.check(not bridge.submit(1,token) and bridge.submit(2,token), "I04 real holder-judgment response accepts C only and pays one actual card")
	for i in 3: await t.process_frame
	# B still has a card: it must be offered after C's downstream D.
	var decline = find.find(bridge.snapshot(1),"放弃")
	t.check(decline != "" and bridge.input_owner() == 1 and bridge.submit(1,decline), "I04 actual counter sequence permits holder B to decline after downstream D")
	for i in 3: await t.process_frame
	t.check(game.players[1].hp == 5 and game.deck._discard.count(data[1]) == 1 and game.players[2].hand_size() == 0 and game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1, "I04 natural old Fire canceled once; excluded-side hands and holder HP preserved")
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and bridge.input_owner() == 1 and game._pending_card_actions.is_empty() and not bridge.submit(2,token), "I04 natural delayed chain resumes B DRAW/PLAY and rejects old C response")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func stale(t):
	for mode in ["phase","removed"]:
		var data = bridge_fixture(t)
		var bridge = data[0]
		var game = bridge.game
		var result: Array = []
		var drive = func(): result.append(await game._run_judgment(game.players[1],false))
		drive.call()
		for i in 3: await t.process_frame
		var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(2),"打出【无懈可击】")
		t.check(token != "", "I04 holder judgment has real C response before explicit invalidation")
		# Engineering invalidation, not a claim that these actions are legal inside a response.
		if mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.END
		else: game.players[1].judgment_cards.erase(data[1])
		for i in 3: await t.process_frame
		t.check(result == [false] and game.players[2].hand_size() == 1 and not bridge.submit(2,token), "I04 stale holder/original card cannot authorize old response or charge C")
		t.check(not game.deck._discard.has(data[1]) and game._pending_card_actions.is_empty(), "I04 invalidated holder judgment neither consumes original nor leaks pending actions")
		game._game_over = true
		bridge.queue_free()
		await t.process_frame
