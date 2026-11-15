extends RefCounted

func fixture(t):
	var game = load("res://Test/i05_simba_good_deed_flow_cases.gd").new().fixture(t)
	game._corruption_rules_enabled = false
	game.players[0].simba_tuanfei_enabled = true
	return game

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await contexts_and_remainders(t)
	await regions(t)
	await physical_facts(t)
	await one_batch(t)
	await stolen_facts(t)
	await invalidation(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func contexts_and_remainders(t):
	var game = fixture(t)
	var actor = game.players[0]
	var source = game.players[1]
	game._draw_blank_cards(source, 4, ExtraDrawBatch.Context.INITIAL_DEAL)
	game._draw_blank_cards(source, 2, ExtraDrawBatch.Context.DRAW_PHASE)
	game._draw_blank_cards(actor, 3)
	t.check(actor.tuanfei_extra_draws == 0, "I05d fee excludes initial deal, normal/gift DRAW and own extra draws")
	game._draw_blank_cards(source, 2)
	t.check(actor.tuanfei_extra_draws == 2 and await game._settle_tuanfei_end(func(): return true) == 0 and actor.hand_size() == 3, "I05d fee incomplete three carries without reward")
	game._draw_blank_cards(game.players[2], 1)
	t.check(actor.tuanfei_extra_draws == 3 and await game._settle_tuanfei_end(func(): return true) == 0 and actor.hand_size() == 4 and actor.tuanfei_extra_draws == 0, "I05d Q2 subsequent source completes carried three")
	game._draw_blank_cards(source, 3)
	game._draw_blank_cards(game.players[2], 3)
	game._draw_blank_cards(game.players[3], 1)
	var first = actor.hand_size()
	t.check(await game._settle_tuanfei_end(func(): return true) == 0 and actor.hand_size() == first + 2 and actor.tuanfei_extra_draws == 1, "I05d floor conversion pays two from seven and retains one")
	t.check(await game._settle_tuanfei_end(func(): return true) == 0 and actor.hand_size() == first + 2 and actor.tuanfei_extra_draws == 1, "I05d consumed contribution cannot be paid twice or count own reward")
	actor.restore_game_start_state()
	t.check(actor.tuanfei_extra_draws == 0 and actor.simba_tuanfei_enabled, "I05d Sage resets general counter, not private server capability")
	actor.simba_tuanfei_enabled = false
	game._draw_blank_cards(source, 3)
	t.check(actor.tuanfei_extra_draws == 0, "I05d fee is private and disabled by default capability gate")
	actor.simba_tuanfei_enabled = true
	actor.general_name = "稻草人"
	game._draw_blank_cards(source, 3)
	t.check(actor.tuanfei_extra_draws == 0, "I05d enabled capability does not give another general the skill")
	await dispose(t, game)

func regions(t):
	for initially_split in [false, true]:
		var game = fixture(t)
		var actor = game.players[0]
		var jim = game.players[2]
		jim.general_name = "吉姆·芒顿"; jim.max_hp = 6; jim.hp = 3
		# Registered terrain/resource prefix; full paid Move Mountain is in 5c/7.
		var first = game._spawn_mountain_at(jim, 1, 2) if initially_split else game._spawn_mountain_at(jim, 4, 0)
		var first_id = game.unit_registry.id_for(first)
		var second = game._spawn_mountain_at(jim, 4, 0) if initially_split else game._spawn_mountain_at(jim, 4, first_id)
		var second_id = game.unit_registry.id_for(second)
		t.check(game._mountain_effect_reaches(actor, jim) == (not initially_split), "I05d Q9 actual initial partition matches case")
		game._draw_blank_cards(jim, 3)
		t.check(actor.tuanfei_extra_draws == (0 if initially_split else 3), "I05d Q6/Q9 eligibility fixed at physical draw commit")
		var moved = game.mountain_space.move(first_id, 4, second_id, game._mountain_live_seats()) if initially_split else game.mountain_space.move(first_id, 1, 2, game._mountain_live_seats())
		t.check(moved and game._mountain_effect_reaches(actor, jim) == initially_split, "I05d Q9 real terrain move reverses region relationship")
		t.check(await game._settle_tuanfei_end(func(): return true) == 0 and actor.hand_size() == (0 if initially_split else 1), "I05d Q9 reward does not refilter historical draws by current region")
		await dispose(t, game)

func physical_facts(t):
	var game = fixture(t)
	var actor = game.players[0]
	var drawer = game.players[1]
	game._extra_draw_receipts_enabled = true
	var batch = game._draw_blank_cards(drawer, 2)
	drawer.restore_game_start_state()
	t.check(not batch.valid() and actor.tuanfei_extra_draws == 2, "I05d historical fee facts survive receipt invalidation after drawer general reset")
	game._draw_yudaxi_reward(game.players[2], 1)
	t.check(actor.tuanfei_extra_draws == 3, "I05d Corruption-exempt Yudaxi reward remains an actual EXTRA draw fact")
	game.turn_manager.current_player_idx = 1
	game.turn_manager.play_actor_idx = 1
	drawer.hp = 0
	await game._resolve_dying(drawer, null, "test")
	t.check(drawer.is_dead() and actor.tuanfei_extra_draws == 3, "I05d drawer death/hand cleanup does not erase earlier eligible facts")
	t.check(await game._settle_tuanfei_end(func(): return true) == 0 and actor.hand_size() == 1, "I05d Q7 payout primitive can consume credit after turn actor final death")
	await dispose(t, game)

func one_batch(t):
	var game = fixture(t)
	var actor = game.players[0]
	var sunny = game.players[4]
	sunny.general_name = "桑尼·斯派"
	game._corruption_rules_enabled = true
	var offered: Array = []
	game._corruption_choice_override = func(_p, batch, _stage, _valid):
		offered.append([batch.owner, batch.count])
		return 0 if batch.owner == actor else -1
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == sunny else GameManager.RPS_SCISSORS
	for drawer in game.players.slice(1, 4):
		var batch = game._draw_blank_cards(drawer, 3)
		t.check(await game._resolve_corruption_batch(batch) == 0, "I05d pre-reward actual Corruption may be declined")
	t.check(actor.tuanfei_extra_draws == 9, "I05d actual three-source facts total nine before one reward")
	t.check(await game._settle_tuanfei_end(func(): return true) == 0, "I05d Q10 reward awaits original Corruption parent")
	var reward = offered.filter(func(row): return row[0] == actor)
	t.check(reward.size() == 1 and reward[0][1] == 3 and sunny.hand_size() == 3 and actor.hand.is_empty(), "I05d Q10 one three-card reward opens one Corruption batch, transferred once")
	t.check(actor.tuanfei_extra_draws == 0 and game.players.slice(1, 4).all(func(p): return p.hand_size() == 3), "I05d card transfer is not another draw; own reward is not counted")
	await dispose(t, game)

func start_reward(game, results, allowed):
	results.append(await game._settle_tuanfei_end(allowed))

func stolen_facts(t):
	var game = fixture(t)
	var actor = game.players[0]
	var sunny = game.players[4]
	sunny.general_name = "桑尼·斯派"
	game._corruption_rules_enabled = true
	game._corruption_choice_override = func(_p, _b, _s, _v): return 0
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == sunny else GameManager.RPS_SCISSORS
	var batch = game._draw_blank_cards(game.players[1], 3)
	t.check(await game._resolve_corruption_batch(batch) == 1 and game.players[1].hand.is_empty() and sunny.hand_size() == 3 and actor.tuanfei_extra_draws == 3, "I05d real Corruption taking all original cards does not erase draw facts or count transfers twice")
	t.check(await game._settle_tuanfei_end(func(): return true) == 0 and sunny.hand_size() == 4 and actor.hand.is_empty() and actor.tuanfei_extra_draws == 0, "I05d emptied original receipt still funds one reward, its own stolen reward gives no extra credit")
	await dispose(t, game)

func invalidation(t):
	var game = fixture(t)
	var actor = game.players[0]
	game._draw_blank_cards(game.players[1], 3)
	game.players[4].general_name = "桑尼·斯派"
	game._corruption_rules_enabled = true
	game._corruption_choice_override = Callable()
	var results: Array = []
	var allowed = func(): return not game._game_over
	start_reward(game, results, allowed)
	await t.process_frame
	t.check(results.is_empty() and actor.hand_size() == 1 and actor.tuanfei_extra_draws == 0 and not game._choice_prompt_stack.is_empty(), "I05d fee debit/reward already committed while real Corruption window waits")
	game._choice_prompt_stack.back().overlay.queue_free()
	for i in 4: await t.process_frame
	t.check(results == [GameManager.CHOICE_INVALID] and actor.hand_size() == 1 and actor.tuanfei_extra_draws == 0, "I05d technical reward reaction failure is explicit, without rollback or duplicate reward")
	await dispose(t, game)
