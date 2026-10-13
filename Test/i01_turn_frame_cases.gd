extends RefCounted

func run(t):
	var live: Array[int] = [0,1,2,3,4]
	var tm = TurnManager.new()
	tm.debug_log = false
	tm.player_count = 5
	tm.live_seats = func(): return live.duplicate()
	tm.start_game()
	t.check(tm.current_player_idx == 0 and tm.rounds.round_id == 1, "I01c real turn manager begins first ordinary round")
	tm._change_phase(TurnManager.Phase.PLAY)
	tm.use_strike()
	tm.use_card("duel")
	tm.set_phase_skill_used("test", true)
	var original_turn = tm.turn_id
	var original_phase = tm.phase_id
	var original_revision = tm.get_context_revision()
	var pending = tm.rounds.pending_seats()
	t.check(tm.begin_extra_turn(1) and tm.turn_id > original_turn and tm.strike_count_this_turn == 0, "I01c extra turn owns fresh counters")
	tm._change_phase(TurnManager.Phase.PLAY)
	tm.use_strike()
	t.check(tm.begin_extra_turn(2), "I01c nested extra frame enters")
	tm.next_turn()
	t.check(tm.current_player_idx == 1 and tm.strike_count_this_turn == 1 and tm.current_phase == TurnManager.Phase.PLAY, "I01c nested extra resumes its parent phase/counter")
	tm.next_turn()
	t.check(tm.current_player_idx == 0 and tm.turn_id == original_turn and tm.phase_id == original_phase, "I01c outer ordinary identity restored, no new ordinary turn")
	t.check(tm.strike_count_this_turn == 1 and tm.duel_count_this_turn == 1 and tm.phase_skill_used("test"), "I01c ordinary limits and phase skill use survive extras")
	t.check(tm.rounds.pending_seats() == pending and tm.get_context_revision() > original_revision, "I01c extras do not consume quota or revive stale input revision")
	tm.next_turn()
	t.check(tm.current_player_idx == 1 and tm.turn_id > original_turn + 2 and tm.strike_count_this_turn == 0, "I01c next ordinary has unique turn id and new limits")
	live.erase(0)
	for seat in [2,3,4]:
		tm.next_turn()
		t.check(tm.current_player_idx == seat and tm.rounds.round_id == 1, "I01c dead head does not discard remaining ordinary turns")
	tm.next_turn()
	t.check(tm.current_player_idx == 1 and tm.rounds.round_head == 1 and tm.rounds.round_id == 2, "I01c R2 next round begins smallest living permanent seat")
	var frame = tm.begin_standalone_phase(2, TurnManager.Phase.PLAY)
	var gift_round = tm.rounds.round_id
	var gift_pending = tm.rounds.pending_seats()
	tm.use_strike()
	t.check(not frame.is_empty() and tm.begin_extra_turn(3), "I01c granted phase state can be suspended at a safe checkpoint")
	tm.next_turn()
	t.check(tm.current_player_idx == 1 and tm.get_play_actor_idx() == 2 and tm.strike_count_this_turn == 1, "I01c restoration preserves gifted phase actor and its counts")
	t.check(tm.complete_standalone_phase(frame) and tm.rounds.round_id == gift_round and tm.rounds.pending_seats() == gift_pending, "I01c standalone completes without consuming a round quota")
	tm.skip_full_turn = true
	tm.advance_phase()
	t.check(tm.current_phase == TurnManager.Phase.END, "I01c facedown skip reaches end")
	tm.next_turn()
	t.check(tm.current_player_idx == 2 and not tm.rounds.pending_seats().has(1), "I01c facedown skip consumes one ordinary quota")
	tm.free()

	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.FREE_FOR_ALL)
	t.check(game.turn_manager.rounds != null and game.turn_manager.rounds.round_id == 1, "I01c production scene uses round ledger")
	game._game_over = true # Freeze scene callbacks; exercise the real configured manager below.
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	for i in 5: game.turn_manager.next_turn()
	t.check(game.turn_manager.rounds.round_id == 2 and game.turn_manager.current_player_idx == 0, "I01c actual configured roster transitions after every ordinary player")
	game.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
