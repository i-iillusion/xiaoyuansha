extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for gifted in [false, true]:
		var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
		game.lan_enabled = true
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, game.players[0])
		var id = game.unit_registry.id_for(dragon)
		if gifted:
			game.turn_manager.current_player_idx = 1
			game.turn_manager.current_phase = TurnManager.Phase.START
			t.check(not game.turn_manager.begin_standalone_play(id).is_empty(), "I03 input fixture grants distinct unit PLAY")
		else: game.turn_manager.current_unit_id = id
		dragon.hand.append(null)
		game._set_input_player(game.players[2])
		game._restore_play_skill_buttons()
		t.check(game._input_seat == 0 and game._play_btn.visible and game._end_play_btn.visible, "I03 normal/gifted unit PLAY restores controller and action buttons")
		game._on_play_btn_pressed()
		var selectors = game.get_node("UI").get_children().filter(func(node): return node is CardSelector)
		t.check(selectors.size() == 1 and selectors[0].player == dragon, "I03 restored Play opens selector for actual dragon, not controller")
		selectors[0].queue_free()
		await t.process_frame
		var answers: Array = []
		var outer = func(): answers.append(["outer", await game._show_choice_popup("outer", ["OK"], Callable(), false)])
		game._set_input_player(game.players[2])
		outer.call()
		var outer_answer = game._choice_prompt_stack.back().answer
		var inner = func(): answers.append(["inner", await game._show_choice_popup("inner", ["OK"], Callable(), false)])
		game._set_input_player(game.players[3])
		inner.call()
		game._choice_prompt_stack.back().answer.submit(0)
		await t.process_frame
		t.check(game._input_seat == 2 and game._choice_prompt_stack.size() == 1 and answers == [["inner", 0]], "I03 nested unit-turn response restores previous responder, not unit controller yet")
		outer_answer.submit(0)
		await t.process_frame
		t.check(game._input_seat == 0 and game._choice_prompt_stack.is_empty() and answers == [["inner", 0], ["outer", 0]], "I03 final response restores unit controller even in another player's gifted phase")
		game._game_over = true
		game._restore_play_skill_buttons()
		t.check(not game._play_btn.visible and not game._end_play_btn.visible, "I03 ended game cannot reopen unit action buttons")
		game.queue_free()
		await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
