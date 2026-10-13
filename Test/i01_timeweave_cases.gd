extends RefCounted

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.FREE_FOR_ALL)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.players[4].general_name = "桑尼·泰姆"
	game._timeweave_candidates_override = func(): return [game.players[4]]
	return game

func dispose(t, game):
	game._game_over = true
	game.queue_free()
	await t.process_frame
	await t.process_frame

func restart(tm, done):
	await tm.start_game()
	done.value = true

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for scenario in ["head", "middle", "defer"]:
		var game = fixture(t)
		var starts: Array[int] = []
		game.turn_manager.phase_changed.connect(func(_old, phase, seat):
			if phase == TurnManager.Phase.START: starts.append(seat))
		var offers: Array[int] = []
		game._timeweave_choice_override = func(_actor, nominee):
			offers.append(nominee)
			return 0 if (scenario == "head" and nominee == 0) or (scenario == "middle" and nominee == 1) else -1
		if scenario == "defer":
			# Prepared R5 placement; A already began in the fixture before the skill
			# hook was attached. No declined choice itself changes placement.
			game.turn_manager.rounds.relocate_before(4,1)
			starts.append(0)
		else:
			await game.turn_manager.start_game()
		for i in 4: await game.turn_manager.next_turn()
		var expected = [4,0,1,2,3] if scenario == "head" else ([0,4,1,2,3] if scenario == "middle" else [0,1,2,3,4])
		t.check(starts == expected and game.turn_manager.rounds.round_id == 1, "I01d legal insertion/defer processes each ordinary turn once before next round")
		t.check(game.turn_manager.rounds.round_head == 0 and game.players.map(func(p): return p.seat_index) == [0,1,2,3,4], "I01-Q1 anchor/permanent IDs unchanged when E starts before A")
		if scenario == "defer": t.check(offers.has(4) and offers.size() == 3, "I01-Q2 own-position timeout postpones, last quota forces without another offer")
		if scenario == "middle":
			t.check(game.turn_manager.rounds.space_order() == [0,4,1,2,3] and game.ordinary_seat_distance(game.players[3],game.players[4]) == 2, "I01d R5 spatial relocation changes D->E distance")
			t.check(game._yudaxi_targets(game.players[3]).map(func(p): return p.seat_index) == [0,4,1,2], "I01d Yudaxi next-seat order follows space not fixed IDs")
			game._timeweave_choice_override = func(_actor,_nominee): return -1
			await game.turn_manager.next_turn()
			t.check(game.turn_manager.rounds.round_id == 2 and game.turn_manager.rounds.space_order() == [0,4,1,2,3], "I01d R5 spatial placement survives next round")
		await dispose(t,game)

	for action in ["accept", "timeout", "close"]:
		var game = fixture(t)
		game.lan_enabled = true
		var bridge = LanGameBridge.new()
		t.root.add_child(bridge)
		bridge.game = game
		var starts: Array[int] = []
		game.turn_manager.phase_changed.connect(func(_old,phase,seat):
			if phase == TurnManager.Phase.START: starts.append(seat))
		var done = {"value":false}
		restart(game.turn_manager,done)
		await t.process_frame
		var owner = bridge.snapshot(4)
		t.check(not done.value and starts.is_empty() and owner.owner == 4, "I01d real choice precedes nominee START effects")
		var button = owner.controls.filter(func(c): return c.text == "现在行动")[0]
		t.check(bridge.snapshot(1).controls.is_empty() and not bridge.submit(1,button.id), "I01d LAN owner only, fixed-seat non-owner cannot answer")
		if action == "accept": t.check(bridge.submit(4,button.id), "I01d real owner insertion button accepted")
		elif action == "timeout": game._countdown_on_timeout.call()
		else: game._choice_prompt_stack.back().overlay.queue_free()
		for i in 3: await t.process_frame
		t.check(done.value and game._choice_prompt_stack.is_empty() and not bridge.submit(4,button.id), "I01d choice cleanup and old-token rejection")
		t.check(starts == ([4] if action == "accept" else ([0] if action == "timeout" else [])), "I01d timeout is no insertion, technical close never starts a turn")
		var state = bridge.snapshot(1)
		t.check(state.space.size() == 5 and state.round == 1 and state.players[4].seat == 4, "I01d spatial snapshot separate from fixed player rows")
		var receiver = LanSession.new()
		t.root.add_child(receiver)
		receiver.mode = state.mode
		receiver.count = state.count
		receiver._view_match = state.history.match
		receiver.history.reset(state.history.match)
		state.match = state.history.match
		receiver._receive_state(state)
		t.check(not receiver.latest.is_empty(), "I01e valid wire spatial state accepted")
		var malformed = state.duplicate(true)
		malformed.space[0] = malformed.space[1]
		receiver.latest = {}
		receiver._receive_state(malformed)
		t.check(receiver.latest.is_empty(), "I01e duplicate spatial ID rejected before consuming history")
		malformed = state.duplicate(true)
		malformed.round = 0
		receiver._receive_state(malformed)
		t.check(receiver.latest.is_empty(), "I01e invalid round rejected")
		receiver.queue_free()
		var room = load("res://Scenes/LanRoom.tscn").instantiate()
		t.root.add_child(room)
		room._state_changed(state)
		t.check(room._board.get_children()[0].text.begins_with(str(state.space[0]+1)+"号"), "I01d actual LAN board uses spatial order")
		room.queue_free()
		bridge.game = null
		bridge.queue_free()
		await dispose(t,game)

	var game = fixture(t)
	game._timeweave_choice_override = func(_actor,_nominee):
		game.turn_manager.current_player_idx = 1
		game.turn_manager.current_player_idx = 0
		return 0
	var starts: Array[int] = []
	game.turn_manager.phase_changed.connect(func(_old,phase,seat):
		if phase == TurnManager.Phase.START: starts.append(seat))
	await game.turn_manager.start_game()
	t.check(starts.is_empty() and game.turn_manager.rounds.space_order() == [0,1,2,3,4], "I01d stale override cannot authorize insertion after fields leave and return")
	await dispose(t,game)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
