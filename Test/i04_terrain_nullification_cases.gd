extends RefCounted

func configure(game):
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game.lan_enabled = true # Native fixtures need all real responder branches.
	var center = game._spawn_mountain_at(game.players[0],0,1)
	game._spawn_mountain_at(game.players[0],3,4)
	var original = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(center)
	return [center,original]

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["Bfirst","Ccounter","Efirst","selflast"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		var pair = configure(game)
		game.players[0].hand.append(null)
		game.players[4].hand.append(null)
		game.players[1].hand.append(null)
		if mode in ["Ccounter","selflast"]: game.players[2].hand.append(null)
		if mode == "selflast": game.players[1].hand.append(null); game.players[3].hand.append(null)
		var offered: Array = []
		var actions: Array = []
		var early_completion: Array = []
		game.card_action_committed.connect(func(event):
			early_completion.append(actions.any(func(previous): return previous.settlement_completed))
			actions.append(event))
		game._nullify_override = func():
			var seat = game._input_seat
			offered.append(seat)
			if game.players[seat].hand_size() == 0: return false
			if mode == "Efirst": return seat == 4
			return seat == 1 or (mode == "Ccounter" and seat == 2)
		t.check(await game._run_judgment(pair[0],false), "I04 Q42/Q45 terrain counter chain completes: "+mode)
		var expected = {"Bfirst":[1,2,3,1],"Ccounter":[1,2,3,1,2],"Efirst":[1,2,3,4,0,4],"selflast":[1,2,3,1,2,3,1]}[mode]
		t.check(offered == expected, "I04 Q45 exact downstream order, same-region counter and last-position self counter: "+mode)
		t.check(pair[0].hp == (3 if mode in ["Ccounter","selflast"] else 5) and game.players[0].hand_size() == 1 and game.players[4].hand_size() == (0 if mode == "Efirst" else 1), "I04 Q42 parity applies to original fire; opposite side cannot interfere with an established counter")
		t.check(actions.size() == (2 if mode in ["Ccounter","selflast"] else 1) and actions.all(func(e): return e.settlement_completed) and not early_completion.has(true), "I04 scoped chain completes every committed counter together, never between responses")
		t.check(game.deck._discard.count(pair[1]) == 1 and game._pending_card_actions.is_empty() and game._mountain_judgment_contexts.is_empty() and game._input_seat == 0, "I04 scoped chain settles original once and restores original actor input")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await virtual_death(t)
	await paid_physical_death(t)
	await lan(t)
	await stale(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func virtual_death(t):
	for counter in [false,true]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		var pair = configure(game)
		var actor = game.players[1]
		actor.general_name = "安普提·斯丢皮得"
		actor.hp = 1
		if counter: game.players[2].hand.append(null)
		game.players[0].hand.append(null)
		game.players[4].hand.append(null)
		game._rps_override = func(p): return game.RPS_ROCK if p == actor else game.RPS_PAPER
		var actions: Array = []
		var offered: Array = []
		game.card_action_committed.connect(func(event): actions.append(event))
		game._nullify_override = func():
			var seat = game._input_seat
			offered.append(seat)
			return (seat == 1 and actor.is_alive()) or (counter and seat == 2 and game.players[2].hand_size() > 0)
		t.check(await game._run_judgment(pair[0],false), "I04 Q20/Q45 virtual counter survives actor death in scoped terrain chain")
		t.check(actor.is_dead() and not game._mountain_live_seats().has(1) and offered == ([1,2,3,2] if counter else [1,2,3]), "I04 dead counter source retains only its region/order anchor, never live/input membership")
		t.check(actions.size() == (2 if counter else 1) and actions[0].is_virtual and actions[0].settlement_completed and not game.deck._discard.has(actions[0].card), "I04 lethal virtual Nullification remains a completed nonphysical USE")
		t.check(pair[0].hp == (3 if counter else 5) and game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1, "I04 scoped even/odd parity continues correctly after final death; other region cannot counter")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func bridge_fixture(t):
	var bridge = load("res://Test/i04_aoe_region_cases.gd").new().bridge_fixture(t,4)
	var pair = configure(bridge.game)
	for seat in [0,1,2,4]: bridge.game.players[seat].hand.append(null)
	bridge.game._nullify_override = Callable()
	return [bridge,pair[0],pair[1]]

func paid_physical_death(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
	var pair = configure(game)
	for seat in [0,1,2,4]: game.players[seat].hand.append(null)
	var actions: Array = []
	var offered: Array = []
	# Engineering death injection after an irrevocable physical USE, distinct
	# from the legal virtual-cost death pipeline exercised above.
	game.card_action_committed.connect(func(event):
		actions.append(event)
		if event.actor_body == game.players[1]: game.players[1].mark_dead())
	game._nullify_override = func():
		var seat = game._input_seat
		offered.append(seat)
		return seat in [1,2] and game.players[seat].is_alive() and game.players[seat].hand_size() > 0
	t.check(await game._run_judgment(pair[0],false), "I04 TIME04 paid physical Nullification also survives later actor death")
	t.check(offered == [1,2,3,2] and game.players[1].is_dead() and not game._mountain_live_seats().has(1), "I04 physical paid-source death keeps only spatial origin, never response membership")
	t.check(actions.size() == 2 and actions[0].from_hand and not actions[0].is_virtual and actions.all(func(e): return e.settlement_completed) and game.deck._discard.count(actions[0].card) == 1, "I04 post-USE death cannot revoke or repay a committed physical counter")
	t.check(pair[0].hp == 3 and game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1, "I04 scoped parity and excluded-region cards remain correct after physical paid-source death")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func drive(game,center,result):
	result.append(await game._run_judgment(center,false))

func lan(t):
	var data = bridge_fixture(t)
	var bridge = data[0]
	var game = bridge.game
	var result: Array = []
	drive(game,data[1],result)
	for i in 3: await t.process_frame
	var find = load("res://Test/i04_movement_cases.gd").new()
	var token = find.find(bridge.snapshot(1),"打出【无懈可击】")
	t.check(token != "" and bridge.input_owner() == 1 and bridge.snapshot(0).controls.is_empty() and bridge.snapshot(4).controls.is_empty(), "I04 Q45 actual mountain counter offers downstream B before A/E")
	t.check(not bridge.submit(4,token) and bridge.submit(1,token), "I04 only B can pay first counter from actual human window")
	for i in 3: await t.process_frame
	var next_token = find.find(bridge.snapshot(2),"打出【无懈可击】")
	t.check(next_token != "" and bridge.input_owner() == 2 and not bridge.submit(1,token) and bridge.snapshot(4).controls.is_empty(), "I04 Q42 actual counter moves to same-region C, rejecting opposite side and old B token")
	t.check(bridge.submit(2,next_token), "I04 same-region human C counter accepted")
	for i in 3: await t.process_frame
	t.check(result == [true] and data[1].hp == 3 and game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1 and game._card_action_serial == 2, "I04 two actual counters enable mountain fire; excluded side keeps its real hands")
	t.check(bridge.input_owner() == 0 and bridge.acting_unit() == "" and not bridge.submit(2,next_token) and game._pending_card_actions.is_empty(), "I04 scoped actual counter chain returns original PLAY input and rejects replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func stale(t):
	for mode in ["move","phase","reset","death"]:
		var data = bridge_fixture(t)
		var bridge = data[0]
		var game = bridge.game
		var result: Array = []
		drive(game,data[1],result)
		for i in 3: await t.process_frame
		var find = load("res://Test/i04_movement_cases.gd").new()
		var first = find.find(bridge.snapshot(1),"打出【无懈可击】")
		t.check(first != "" and bridge.submit(1,first), "I04 stale scoped case first counter really pays: "+mode)
		for i in 3: await t.process_frame
		var second = find.find(bridge.snapshot(2),"打出【无懈可击】")
		t.check(second != "", "I04 same-region C has pending actual counter before fault injection")
		# Engineering invalidation only, not claiming mid-window legal Sunny use.
		if mode == "move": game.turn_manager.rounds.relocate_before(2,0)
		elif mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.END
		elif mode == "death": game.players[2].mark_dead()
		else: game.reset_game_over_state()
		for i in 3: await t.process_frame
		t.check(result == [false] and game.players[2].hand_size() == 1 and game.players[1].hand_size() == 0, "I04 stale/moved/reset responder cannot pay a second card; prior valid payment is retained")
		t.check(not game.deck._discard.has(data[2]) and not bridge.submit(2,second) and game._pending_card_actions.is_empty() and game._mountain_judgment_contexts.is_empty(), "I04 expired scoped chain leaves original judgment unconsumed and abandons only continuation")
		game._game_over = true
		bridge.queue_free()
		await t.process_frame
