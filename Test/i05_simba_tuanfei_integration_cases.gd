extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await harvest(t)
	await dragon(t)
	await snapshots(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func harvest(t):
	var game = load("res://Test/i05_simba_tuanfei_end_cases.gd").new().fixture(t)
	var a = game.players[0]
	var sunny = game.players[4]
	sunny.general_name = "桑尼·斯派"
	game._corruption_rules_enabled = true
	var offers: Array = []
	game._corruption_choice_override = func(_p, batch, _stage, _valid):
		offers.append([batch.owner, batch.count])
		return 0 if batch.owner == a else -1
	game._rps_override = func(p): return GameManager.RPS_ROCK if p == sunny else GameManager.RPS_SCISSORS
	for p in game.players.slice(1, 4): p.hp = p.max_hp - 3
	a.hand.append(null)
	game._set_input_player(a)
	await game.play_card(CardData.CardSubType.HARVEST)
	t.check(a.hand.is_empty() and a.tuanfei_extra_draws == 9 and game.players.slice(1, 4).all(func(p): return p.hand_size() == 3), "I05d full paid Harvest contributes three actual three-card extra batches")
	t.check(game._pending_card_actions.is_empty() and offers.size() == 3, "I05d full Harvest completes all original Corruption and card-action continuations")
	await load("res://Test/i05_simba_tuanfei_end_cases.gd").new().finish(game)
	var reward = offers.filter(func(row): return row[0] == a)
	t.check(reward.size() == 1 and reward[0][1] == 3 and sunny.hand_size() == 3 and a.hand.is_empty(), "I05d Q10 full paid card to actual END grants one batch, Sunny takes it once")
	t.check(game.turn_manager.current_player_idx == 1 and a.tuanfei_extra_draws == 0, "I05d full card/fee/Corruption chain advances only after completion")
	await dispose(t, game)

func dragon(t):
	var base = load("res://Test/i05_simba_tuanfei_end_cases.gd").new()
	var game = base.fixture(t)
	var tm = game.turn_manager
	var a = game.players[0]
	var chris = game.players[4]
	chris.general_name = "克里斯·西弗"
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, chris)
	var id = game.unit_registry.id_for(dragon)
	for i in 4: await base.finish(game)
	t.check(tm.current_player_idx == 4 and tm.rounds.round_id == 1, "I05d attached last-seat fixture reaches final ordinary owner")
	game._draw_blank_cards(game.players[1], 4)
	await base.finish(game)
	t.check(tm.current_unit_id == id and tm.rounds.round_id == 1 and a.hand_size() == 1 and a.tuanfei_extra_draws == 1, "I05d owner END pays but does not close round before its real attached dragon turn")
	game._draw_blank_cards(dragon, 1, ExtraDrawBatch.Context.DRAW_PHASE)
	t.check(a.tuanfei_extra_draws == 1 and dragon.hand_size() == 1, "I05d dragon ordinary DRAW is not an extra contribution")
	game._draw_blank_cards(dragon, 3)
	t.check(a.tuanfei_extra_draws == 4 and chris.hand.is_empty(), "I05d intelligent unit extra draw counts as its own contribution, not controller transfer")
	await base.finish(game)
	t.check(tm.current_unit_id.is_empty() and tm.current_player_idx == 0 and tm.rounds.round_id == 2 and a.hand_size() == 2 and a.tuanfei_extra_draws == 0, "I05d actual dragon END pays once then true round boundary clears final remainder")
	await dispose(t, game)

func snapshots(t):
	var game = load("res://Test/i05_simba_tuanfei_end_cases.gd").new().fixture(t)
	var a = game.players[0]
	var adapter = LanGameBridge.new()
	t.root.add_child(adapter); adapter.game = game
	game._set_input_player(a)
	game._play_btn.visible = true; game._end_play_btn.visible = true
	var before = adapter.snapshot(0)
	var old = before.controls.filter(func(c): return c.text == "结束出牌")
	t.check(old.size() == 1 and not before.players[0].has("tuanfei_extra_draws"), "I05d zero remainder preserves old value snapshot shape")
	game._draw_blank_cards(game.players[1], 2)
	var after = adapter.snapshot(0)
	t.check(after.players[0].get("tuanfei_extra_draws", -1) == 2 and adapter.snapshot(1).players[0].get("tuanfei_extra_draws", -1) == 2, "I05d host and remote value snapshots show authoritative private counter")
	t.check(not adapter.submit(0, old[0].id), "I05d counter change invalidates old UI token without accepting stale END")
	for i in 5: await load("res://Test/i05_simba_tuanfei_end_cases.gd").new().finish(game)
	t.check(not adapter.snapshot(0).players[0].has("tuanfei_extra_draws"), "I05d round cleanup removes optional counter from authoritative wire snapshot")
	adapter.game = null; adapter.queue_free()
	await dispose(t, game)
