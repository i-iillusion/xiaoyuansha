extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for option in 3:
		var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
		game.lan_enabled = true
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		var max_player: Player = game.players[1]
		max_player.general_name = "麦克斯·欧尼斯特"
		max_player.hand.clear()
		var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, game.players[0])
		var id = game.unit_registry.id_for(dragon)
		t.check(not game._meiyong_target_valid(max_player, dragon, 1), "I03 hidden dragon cannot receive Max targeted gift")
		var revealed: Array[Player] = [max_player]
		game.fire_dragon_state.record_use(id, 1, revealed)
		game.turn_manager.current_player_idx = 1
		game.turn_manager.current_phase = TurnManager.Phase.START
		game._meiyong_override = func(): return true
		game._meiyong_option_override = func(): return option
		game._meiyong_target_override = func(): return dragon
		if option == 1:
			game._meiyong_target_override = Callable()
			var click_gift = func(): game._on_meiyong_target_click(dragon)
			click_gift.call_deferred()
			var chosen = await game._pick_meiyong_target(1, max_player)
			t.check(chosen == dragon and not game._is_meiyong_targeting, "I03 actual gift target click resolves dragon body, never players[-1]")
			game._meiyong_target_override = func(): return dragon
			var click_strike = func(): game._on_shensu_target_click(dragon)
			click_strike.call_deferred()
			chosen = await game._pick_shensu_strike_target(max_player)
			t.check(chosen == dragon and not game._is_shensu_targeting, "I03 actual Shensu target click resolves visible dragon body")
		var before_turn = game.turn_manager.turn_id
		var eggs = game.players[0].fire_dragon_eggs
		if option == 0:
			dragon.judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
			max_player.judgment_cards.append(CardBase.create(CardData.CardSubType.SUPPLY_SHORTAGE))
		if option == 2:
			dragon.hp = 2
			dragon.hand.append(null)
			var finish = func():
				t.check(game._play_actor() == dragon and game.turn_manager.get_play_actor_key() == id and game._input_seat == 0,
					"I03 gifted unit PLAY uses unit body and its controller, not Max")
				await game.play_card(CardData.CardSubType.PEACH)
				game.end_play_phase()
			finish.call_deferred()
		var outcome = await game._maybe_meiyong(max_player)
		t.check(outcome == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager._standalone_play_frame.is_empty(), "I03 unit gift completes and restores source START: " + str(option))
		t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.turn_id == before_turn and game.fire_dragon_state.turn_count(id) == 0 and game.players[0].fire_dragon_eggs == eggs,
			"I03 gifted unit phase never creates own turn, round quota or egg")
		t.check(max_player.hand_size() == 1, "I03 Max draws exactly once after legal unit/phase choice")
		if option == 0:
			t.check(dragon.judgment_cards.is_empty() and max_player.judgment_cards.size() == 1 and not game.turn_manager.skip_play_phase, "I03 gifted unit judgment suppresses indulgence without processing source zone")
			game.turn_manager.current_phase = TurnManager.Phase.JUDGE
			await game._do_judge(1)
			t.check(max_player.judgment_cards.size() == 1 and game.turn_manager.current_phase == TurnManager.Phase.DRAW, "I03 completed unit gift skips source's original judgment even without integer unit seat")
		elif option == 1:
			t.check(dragon.hand_size() == 1, "I03 gifted dragon DRAW has own base one")
			game.turn_manager.current_phase = TurnManager.Phase.DRAW
			await game._do_draw(1)
			t.check(max_player.hand_size() == 1 and dragon.hand_size() == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I03 completed unit draw skips Max draw without duplication")
		else:
			t.check(dragon.hp == 3 and dragon.hand_size() == 0, "I03 gifted unit actually spends its own card on self Peach")
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			await game._do_play(1)
			t.check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD and game.turn_manager.play_actor_unit_id.is_empty(), "I03 completed gift skips source PLAY and clears unit override")
		game._game_over = true
		game.queue_free()
		await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
