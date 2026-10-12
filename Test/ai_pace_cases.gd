extends RefCounted

var done := false
var reply: Variant

func capture(callback: Callable) -> void:
	done = false
	reply = await callback.call()
	done = true

func frames(t, count := 3) -> void:
	for i in count: await t.process_frame

func fixture(t, concrete := true) -> GameManager:
	GameManager.selected_players = 2
	GameManager.selected_mode = GameManager.MODE_FREE_FOR_ALL
	GameManager.selected_general = "稻草人"
	GameManager.random_general = false
	GameManager.random_identity = false
	var game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	t.root.add_child(game)
	game.start_game()
	game._halt_countdown()
	game._dodge_override = func(): return false
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game._rescue_choice_override = func(_p, _d, _o): return -1
	for p in game.players:
		p.hand.clear()
		p.determined_cards.clear()
	game.players[0].hp = 2
	if concrete:
		game.players[1].determined_cards.assign([CardBase.create(CardData.CardSubType.WINE), CardBase.create(CardData.CardSubType.STRIKE)])
	else: game.players[1].hand.assign([null, null])
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = -1
	game.ai_driver.chooser = func(_view, options):
		for sub in [CardData.CardSubType.WINE, CardData.CardSubType.STRIKE]:
			for i in options.size():
				if options[i].sub == sub: return i
		return -1
	game.action_history.reset("pace-test")
	return game

func run(t):
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	for concrete in [false, true]:
		var baseline: Array = []
		for speed in [AiActionPacer.Speed.SLOW, AiActionPacer.Speed.STANDARD, AiActionPacer.Speed.FAST]:
			var game = fixture(t, concrete)
			game.ai_pacer.speed = speed
			var delays: Array = []
			game.ai_pacer.wait_override = func(seconds):
				delays.append(seconds)
				await t.process_frame
			var originals = game.players[1].determined_cards.duplicate()
			await game._run_ai_play(game.players[1])
			t.check(game._game_over and game.players[0].is_dead() and game.players[1].hand_size() == 0, "PACE fixed wine/kill reaches same victory and payment")
			t.check(delays == ([] if speed == AiActionPacer.Speed.FAST else [AiActionPacer.SECONDS[speed], AiActionPacer.SECONDS[speed]]), "PACE three speeds use independent presentation clock")
			if concrete: t.check(originals.all(func(card): return game.deck._discard.count(card) == 1), "PACE concrete originals discarded once")
			var trace = game.action_history.entries.duplicate(true)
			if baseline.is_empty(): baseline = trace
			else: t.check(trace == baseline, "PACE three speeds preserve all public event order/results")
			game.queue_free()
			await frames(t)
	for mode in ["phase", "reset", "target", "hand", "end", "exit"]:
		var game = fixture(t)
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		if mode in ["target", "hand"]: game.players[1].determined_cards.remove_at(0)
		var original = game.players[1].determined_cards[0]
		var events: Array = []
		game.card_action_committed.connect(func(event): events.append(event))
		game.ai_pacer.speed = AiActionPacer.Speed.STANDARD
		var release = ChoicePromptAnswer.new()
		var clocks: Array = []
		game.ai_pacer.wait_override = func(seconds):
			clocks.append(seconds)
			await release.answered
		capture(game._run_ai_play.bind(game.players[1]))
		await frames(t, 5)
		t.check(not done and clocks.size() == 1 and events.is_empty(), "PACE pending gate has not submitted or paid: " + mode)
		var ref = weakref(game)
		match mode:
			"phase":
				game.turn_manager.current_phase = TurnManager.Phase.DRAW
				game.turn_manager.current_phase = TurnManager.Phase.PLAY
			"reset": game.reset_game_over_state()
			"target": game.players[0].mark_dead() # Defensive injection, not a new interrupt rule.
			"hand": game.players[1].determined_cards.clear()
			"end": game._finish_game("平局", "pace test")
			"exit": game.queue_free()
		if mode == "exit": await frames(t)
		release.submit(1)
		await frames(t, 4)
		t.check(done and events.is_empty(), "PACE stale wait cannot submit a late card: " + mode)
		if mode == "exit": t.check(ref.get_ref() == null, "PACE owner exit cancels before its script is destroyed")
		else:
			t.check(not game.deck._discard.has(original) and game._ai_running_revisions.is_empty(), "PACE stale choice preserves unpaid original and releases lease")
			game.queue_free()
			await frames(t)
	await _real_clock(t)
	await _lan_humans(t)
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]

func _real_clock(t):
	var owner = Node.new()
	t.root.add_child(owner)
	var pacer = AiActionPacer.new()
	pacer.speed = AiActionPacer.Speed.STANDARD
	var start = Time.get_ticks_usec()
	t.check(await pacer.before_action(owner, func(): return true, func(): return true), "PACE real clock completes valid wait")
	t.check(Time.get_ticks_usec() - start >= int(AiActionPacer.SECONDS[pacer.speed] * 1000000), "PACE real clock observes configured delay")
	var state = [true]
	capture(pacer.before_action.bind(owner, func(): return state[0], func(): return true))
	await frames(t)
	state[0] = false
	await frames(t)
	t.check(done and reply == false, "PACE real clock cancels expired context without waiting full delay")
	owner.queue_free()
	await frames(t)

func _lan_humans(t):
	var bridge = LanGameBridge.new()
	t.root.add_child(bridge)
	bridge.start([{"name": "A", "general": "稻草人"}, {"name": "B", "general": "稻草人"}], GameManager.MODE_FREE_FOR_ALL)
	var game = bridge.game
	game._halt_countdown()
	game.ai_pacer.speed = AiActionPacer.Speed.SLOW
	var clocks: Array = []
	game.ai_pacer.wait_override = func(seconds): clocks.append(seconds)
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game._dodge_override = Callable()
	capture(game.execute_card_on_target.bind(game.players[1], CardData.CardSubType.STRIKE))
	await frames(t, 4)
	t.check(not done and game._countdown_active, "PACE LAN human response retains its original countdown")
	t.check(not bridge.snapshot(1).controls.is_empty() and bridge.snapshot(0).controls.is_empty(), "PACE LAN response inputs belong only to target peer")
	t.check(clocks.is_empty(), "PACE slow mode never waits inside human response or damage")
	game._countdown_on_timeout.call()
	await frames(t, 4)
	t.check(done and clocks.is_empty(), "PACE LAN timeout resumes original effect without AI pacing")
	bridge.queue_free()
	await frames(t)
