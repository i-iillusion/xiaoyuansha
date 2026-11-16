extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.CLASSIC)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.lan_enabled = true
	game._nullify_override = func(): return false
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	var owner = game.players[0]
	var target = game.players[1]
	var source = game.players[2]
	var sunny = game.players[4]
	owner.general_name = "辛巴·古德曼"
	owner.simba_lord_skill_enabled = true
	owner.simba_wanci_enabled = true
	owner.simba_good_deeds_enabled = true
	owner.simba_tuanfei_enabled = true
	owner.simba_emergency_enabled = true
	owner.capture_game_start_state()
	sunny.general_name = "桑尼·斯派"; sunny.max_hp = 4; sunny.hp = 4; sunny.capture_game_start_state()
	game._simba_deed_choice_override = func(_p, candidates, reclaim, _valid): return -1 if reclaim else candidates.find(target)
	game._simba_emergency_choice_override = func(_p, victim, _valid): return 0 if victim == target else -1
	game._sage_save_override = func(): return true
	game._corruption_rules_enabled = true
	game._corruption_choice_override = func(_p, _batch, _stage, _valid): return 0
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == sunny else GameManager.RPS_SCISSORS
	target.hp = 3
	t.check(owner.hp == 6 and owner.hand_limit() == 8 and await game._perform_good_deed(owner) == 1, "I05d combined classic lord has dynamic hand limit and actual Good Deed entry")
	t.check(owner.hp == 5 and target.hp == 4 and target.good_deed_marks == 1, "I05d combined active cost and recipient extra HP/mark commit")
	# Resource prefix represents already-authorized prior draws and injuries.
	var prior = game._draw_blank_cards(source, 4)
	await game._resolve_corruption_batch(prior)
	t.check(owner.tuanfei_extra_draws == 4 and sunny.hand_size() == 4, "I05d combined actual Corruption transfer preserves original fee facts")
	owner.hp = 1; target.hp = 1
	owner.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION)); owner.sage_activated = true
	var result = await game._deal_damage_result(source, target, 2, EffectChain.DamageType.PHYSICAL)
	t.check(not result.invalidated and target.is_dead() and owner.is_alive() and not game._game_over, "I05d Emergency cost Sage completes before still-dying recipient exhausts ordinary rescue")
	t.check(owner.hp == 6 and owner.hand.is_empty() and owner.get_armor() == -1 and sunny.hand_size() == 8, "I05d combined Sage grants real four-card batch, actual Sunny wins it before original victim rescue")
	t.check(owner.tuanfei_extra_draws == 0 and owner.good_deed_marks == 0 and target.good_deed_marks == 2, "I05d Sage resets owner's own counter/marks only, preserves other's committed Good Deed/Emergency marks")
	t.check(owner.simba_lord_skill_enabled and owner.simba_wanci_enabled and owner.simba_good_deeds_enabled and owner.simba_tuanfei_enabled and owner.simba_emergency_enabled and owner.hand_limit() == 8, "I05d all five server capabilities survive general-card reset and current lord authority remains dynamic")
	var lightning = CardBase.create(CardData.CardSubType.LIGHTNING)
	owner.judgment_cards.append(lightning)
	t.check(await game._run_judgment(owner, false) and owner.hp == 6 and source.judgment_cards == [lightning], "I05d restored Wanci still fails actual Lightning and transfers original past finally-dead seat")
	var next = game._draw_blank_cards(source, 3)
	await game._resolve_corruption_batch(next)
	t.check(owner.tuanfei_extra_draws == 3 and sunny.hand_size() == 11, "I05d restored fee counter records fresh actual draw, not transfer or old pre-Sage contribution")
	game.turn_manager.current_phase = TurnManager.Phase.END
	await game._do_end(0)
	t.check(owner.tuanfei_extra_draws == 0 and owner.hand.is_empty() and sunny.hand_size() == 12 and game.turn_manager.current_player_idx == 2, "I05d full restored END waits reward Corruption then skips processed final death without duplicating payout")
	owner.hp = 1
	await game._deal_damage_result(source, owner, 1, EffectChain.DamageType.PHYSICAL)
	t.check(owner.is_dead() and game._game_over and not game._tuanfei_enabled(owner), "I05d final lord death follows existing identity verdict and retires future fee eligibility")
	t.check(game._pending_card_actions.is_empty() and game._dying_contexts.is_empty() and game._choice_prompt_stack.is_empty(), "I05d combined completed lifecycle leaves no suspended card, rescue or optional response")
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)
	await reset_pending_end(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func reset_pending_end(t):
	var base = load("res://Test/i05_simba_tuanfei_end_cases.gd").new()
	var game = base.fixture(t)
	var owner = game.players[0]
	var sunny = game.players[4]
	game._draw_blank_cards(game.players[1], 3)
	sunny.general_name = "桑尼·斯派"
	game._corruption_rules_enabled = true
	game._corruption_choice_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.END
	var turn = game.turn_manager.turn_id
	var done: Array = []
	base.drive_end(game, done)
	await t.process_frame
	t.check(done.is_empty() and owner.hand_size() == 1 and not game._choice_prompt_stack.is_empty(), "I05d real END waits while reward Corruption is still unconfirmed")
	game.reset_game_over_state()
	for i in 5: await t.process_frame
	t.check(done == [true] and game.turn_manager.turn_id == turn and game.turn_manager.current_phase == TurnManager.Phase.END, "I05d actual reset lifecycle retires old END continuation without opening next turn")
	t.check(owner.hand_size() == 1 and owner.tuanfei_extra_draws == 0, "I05d reset invalidation neither refunds committed reward nor repeats it")
	game._corruption_rules_enabled = false
	game._draw_blank_cards(game.players[1], 2)
	await base.finish(game)
	t.check(game.turn_manager.current_player_idx == 1 and owner.hand_size() == 1 and owner.tuanfei_extra_draws == 2, "I05d fresh-generation END has an independent lease and reconnects round remainder observer")
	for i in 4: await base.finish(game)
	t.check(game.turn_manager.rounds.round_id == 2 and owner.tuanfei_extra_draws == 0, "I05d fresh lifecycle clears remainder at its real round boundary, not through old callback")
	await base.dispose(t, game)
