extends RefCounted

func fixture(t):
	var game = load("res://Test/i05_simba_tuanfei_cases.gd").new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	return game

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await rounds(t)
	await choices(t)
	await skipped(t)
	await death(t)
	await frames(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func finish(game):
	game.turn_manager.current_phase = TurnManager.Phase.END
	await game._do_end(game.turn_manager.current_player_idx)

func rounds(t):
	var game = fixture(t)
	var tm = game.turn_manager
	var a = game.players[0]
	game._draw_blank_cards(game.players[1], 2)
	await finish(game)
	t.check(tm.current_player_idx == 1 and tm.rounds.round_id == 1 and a.tuanfei_extra_draws == 2, "I05d Q12 normal END carries incomplete contribution in the same round")
	game._draw_blank_cards(game.players[2], 1)
	await finish(game)
	t.check(tm.current_player_idx == 2 and a.hand_size() == 1 and a.tuanfei_extra_draws == 0, "I05d actual END pays carried three once before advancing")
	game._draw_blank_cards(game.players[3], 4)
	await finish(game)
	t.check(tm.current_player_idx == 3 and a.hand_size() == 2 and a.tuanfei_extra_draws == 1, "I05d actual END retains one after four contributions")
	await finish(game)
	t.check(a.tuanfei_extra_draws == 1 and tm.current_player_idx == 4, "I05d penultimate END does not clear remainder")
	await finish(game)
	t.check(tm.rounds.round_id == 2 and tm.current_player_idx == 0 and a.tuanfei_extra_draws == 0 and a.hand_size() == 2, "I05d Q12 real round boundary clears remainder without paying another card")
	var turn = tm.turn_id
	await game._do_end(4)
	t.check(tm.turn_id == turn and a.hand_size() == 2, "I05d stale END or wrong actor cannot pay or advance")
	await dispose(t, game)

func drive_end(game, done):
	await game._do_end(game.turn_manager.current_player_idx)
	done.append(true)

func choices(t):
	for mode in ["cancel", "timeout", "win", "close"]:
		var game = fixture(t)
		var tm = game.turn_manager
		var a = game.players[0]
		var sunny = game.players[4]
		game._draw_blank_cards(game.players[1], 3)
		sunny.general_name = "桑尼·斯派"
		game._corruption_rules_enabled = true
		game._corruption_choice_override = Callable()
		game._rps_override = func(p): return GameManager.RPS_ROCK if p == sunny else GameManager.RPS_SCISSORS
		tm.current_phase = TurnManager.Phase.END
		var turn = tm.turn_id
		var done: Array = []
		drive_end(game, done)
		await t.process_frame
		t.check(done.is_empty() and tm.turn_id == turn and tm.current_phase == TurnManager.Phase.END and a.hand_size() == 1, "I05d real reward Corruption blocks END continuation: " + mode)
		await game._do_end(0)
		t.check(done.is_empty() and tm.turn_id == turn and a.hand_size() == 1 and a.tuanfei_extra_draws == 0, "I05d concurrent END cannot duplicate reward: " + mode)
		if mode == "close":
			game._choice_prompt_stack.back().overlay.queue_free()
		elif mode == "timeout":
			game._countdown_on_timeout.call()
		else:
			var adapter = LanGameBridge.new()
			t.root.add_child(adapter); adapter.game = game
			var label = "发动" if mode == "win" else "取消"
			var buttons = adapter.snapshot(4).controls.filter(func(c): return c.text == label)
			t.check(buttons.size() == 1 and adapter.submit(4, buttons[0].id), "I05d Corruption END choice accepted through real remote input bridge: " + mode)
			adapter.queue_free()
		for i in 5: await t.process_frame
		t.check(done == [true], "I05d pending END returns after reward reaction: " + mode)
		if mode == "close":
			t.check(tm.turn_id == turn and tm.current_phase == TurnManager.Phase.END and a.hand_size() == 1, "I05d technical close invalidates END and keeps committed reward")
			await game._do_end(0)
			t.check(tm.turn_id == turn and a.hand_size() == 1, "I05d invalidated END cannot be replayed as a normal decline")
		else:
			t.check(tm.current_player_idx == 1 and tm.turn_id > turn and tm.current_phase == TurnManager.Phase.START, "I05d valid reward reaction resumes next turn once: " + mode)
			t.check(a.hand_size() == (0 if mode == "win" else 1) and sunny.hand_size() == (1 if mode == "win" else 0), "I05d reward transfer versus ordinary decline is preserved: " + mode)
		await dispose(t, game)

func skipped(t):
	var game = fixture(t)
	var tm = game.turn_manager
	var a = game.players[0]
	tm.next_turn()
	game.players[1].facedown = true
	game._draw_blank_cards(game.players[2], 4)
	tm.phase_changed.connect(game._on_phase_changed)
	await game._do_start(1)
	for i in 4: await t.process_frame
	t.check(not game.players[1].facedown and tm.current_player_idx == 2 and tm.current_phase == TurnManager.Phase.PLAY, "I05d Q11 actual facedown START skips complete turn and reaches next PLAY")
	t.check(a.hand_size() == 1 and a.tuanfei_extra_draws == 1, "I05d Q11/Q12 skipped END pays one and retains one within round")
	game._draw_blank_cards(game.players[2], 2)
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	game.end_play_phase()
	for i in 5: await t.process_frame
	t.check(a.hand_size() == 2 and a.tuanfei_extra_draws == 0 and tm.current_player_idx == 3, "I05d Q12 later same-round actual turn completes skipped-turn remainder")
	await dispose(t, game)

func death(t):
	var game = fixture(t)
	var tm = game.turn_manager
	tm.next_turn()
	tm.current_phase = TurnManager.Phase.PLAY
	tm.play_actor_idx = 1
	var b = game.players[1]
	var c = game.players[2]
	b.hp = 1; b.hand.append(null)
	game._draw_blank_cards(c, 3)
	game._duel_respond_override = func(): return true
	game._duel_second_override = func(): return false
	game._set_input_player(b)
	tm.phase_changed.connect(game._on_phase_changed)
	await game.execute_card_on_target(c, CardData.CardSubType.DUEL)
	for i in 6: await t.process_frame
	t.check(b.is_dead() and not game._game_over, "I05d Q7 real Duel kills current PLAY actor without ending the game")
	t.check(game._pending_card_actions.is_empty() and tm.current_player_idx == 2 and tm.current_phase == TurnManager.Phase.PLAY, "I05d Q7 original card completes before dead PLAY actor advances through END")
	t.check(game.players[0].hand_size() == 1 and game.players[0].tuanfei_extra_draws == 0, "I05d Q7 terminated current turn pays Tuanfei once")
	await dispose(t, game)

func frames(t):
	var game = fixture(t)
	var tm = game.turn_manager
	var a = game.players[0]
	game._draw_blank_cards(game.players[1], 2)
	var original = tm.turn_id
	t.check(tm.begin_extra_turn(2), "I05d authorized extra frame starts without closing round")
	await finish(game)
	t.check(tm.turn_id == original and tm.rounds.round_id == 1 and a.tuanfei_extra_draws == 2, "I05d extra END retains remainder and resumes original frame")
	tm.current_phase = TurnManager.Phase.START
	var frame = tm.begin_standalone_phase(1, TurnManager.Phase.PLAY)
	t.check(not frame.is_empty(), "I05d authorized standalone phase prefix is valid")
	await game._do_end(tm.current_player_idx)
	t.check(not tm._standalone_play_frame.is_empty() and a.tuanfei_extra_draws == 2 and a.hand.is_empty(), "I05d standalone phase cannot masquerade as a turn END")
	tm.complete_standalone_phase(frame)
	t.check(a.tuanfei_extra_draws == 2 and tm.rounds.round_id == 1, "I05d standalone completion neither pays nor clears round remainder")
	await dispose(t, game)
