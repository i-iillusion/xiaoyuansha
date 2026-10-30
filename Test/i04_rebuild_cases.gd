extends RefCounted

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for scenario in ["normal","waiting","gift","cancel","midphase","sage","reset"]:
		var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,_o,_v): return 0)
		game._halt_countdown()
		var owner = game.players[0]
		var mountains = game.unit_registry.active_units()
		var first = mountains[0]
		var second = mountains[1]
		owner.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.LIANNU))
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		first.hp = 1
		await game.execute_card_on_target(first,CardData.CardSubType.STRIKE)
		game._do_play(0)
		t.check(game._jim_rebuild_count(owner) == 0 and owner.jim_rebuild_pending == 1, "I04c2c death in current PLAY cannot reopen its already-bound empty window: "+scenario)
		# Seed the next stage boundary, not a fictitious whole round. The real
		# phase dispatcher / standalone frame and its completion are then used.
		var frame: Dictionary = {}
		if scenario in ["gift","cancel"]:
			game.turn_manager.current_player_idx = 1
			game.turn_manager.current_phase = TurnManager.Phase.START
			frame = game.turn_manager.begin_standalone_play(0)
			game._do_play(1)
		else: game.turn_manager._change_phase(TurnManager.Phase.PLAY)
		t.check(game._jim_rebuild_count(owner) == 1 and owner.jim_rebuild_pending == 0, "I04c2c next actual PLAY binds deferred entitlement once: "+scenario)
		var gate: ChoicePromptAnswer
		if scenario == "waiting":
			var phase = game.turn_manager.phase_id
			game.turn_manager._change_phase(TurnManager.Phase.WAITING)
			t.check(game._jim_rebuild_count(owner) == 0 and owner.jim_rebuild_available == 1, "I04c2c WAITING suspends usability without expiring the opportunity")
			game.turn_manager._change_phase(TurnManager.Phase.PLAY)
			t.check(game.turn_manager.phase_id == phase and game._jim_rebuild_count(owner) == 1, "I04c2c WAITING resume preserves original phase entitlement")
		elif scenario == "gift":
			game.end_play_phase()
			t.check(frame.completed and owner.jim_rebuild_available == 0 and game._jim_rebuild_count(owner) == 0, "I04 Q1b real granted PLAY completion expires unused opportunity")
		elif scenario == "cancel":
			game.turn_manager.cancel_standalone_play(frame)
			t.check(game._jim_rebuild_count(owner) == 0 and owner.jim_rebuild_available == 0, "I04c2c technically invalidated gift frame cannot retain an actionable permission")
		elif scenario == "reset":
			game.reset_game_over_state()
			t.check(game._jim_rebuild_count(owner) == 0 and owner.jim_rebuild_available == 0, "I04c2c technical restart invalidates old phase permission")
		elif scenario == "sage":
			second.hp = 1
			owner.hp = 1
			owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			owner.sage_activated = true
			game._rescue_choice_override = func(_r,_d,_o): return -1
			game._sage_save_override = func(): return true
			await game.execute_card_on_target(second,CardData.CardSubType.STRIKE)
			t.check(owner.hp == 6 and owner.max_hp == 6 and owner.jim_rebuild_pending == 0 and game._jim_rebuild_count(owner) == 0, "I04c2c real Sage clears current and deferred general-card rebuild resources")
			game._do_play(0)
			t.check(game._jim_rebuild_count(owner) == 0 and game.turn_manager.strikes_used() == 2, "I04c2c Sage cannot recreate consumed permission or rewind turn Strike history")
		else:
			if scenario == "midphase":
				second.hp = 1
				await game.execute_card_on_target(second,CardData.CardSubType.STRIKE)
				game._do_play(0)
				t.check(game._jim_rebuild_count(owner) == 1 and owner.jim_rebuild_pending == 1, "I04c2c new death in bound PLAY remains deferred; old permission not doubled")
			# Suspend the genuine mandatory-discard picker so the phase exit can
			# be inspected before an automatic turn/AI advance. No rule is mocked.
			game._draw_blank_cards(owner,maxi(1,owner.hand_limit()-owner.hand_size()+1))
			gate = ChoicePromptAnswer.new()
			game._hand_discard_override = func(_s,_c,_m): await gate.answered; return [0]
			game.end_play_phase()
			t.check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD and owner.jim_rebuild_available == 0 and game._jim_rebuild_count(owner) == 0, "I04 Q1b ordinary PLAY exit expires unused permission")
			t.check(owner.jim_rebuild_pending == (1 if scenario == "midphase" else 0), "I04c2c phase expiry preserves only genuinely future death entitlement")
		game._game_over = true
		if gate != null: gate.submit(0)
		await t.process_frame
		game.queue_free()
		await t.process_frame
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
