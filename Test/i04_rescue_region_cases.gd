extends RefCounted

func fixture(t,walls := 2):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game.lan_enabled = true
	if walls > 0: game._spawn_mountain_at(game.players[5],0,1)
	if walls > 1: game._spawn_mountain_at(game.players[5],4,5)
	return game

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["normal","negative","self","concrete","one_wall","no_walls"]:
		var game = fixture(t,1 if mode == "one_wall" else (0 if mode == "no_walls" else 2))
		var dying = game.players[3]
		dying.hp = 1
		for seat in [0,5]: game.players[seat].hand.append(null)
		var expected = 0 if mode in ["one_wall","no_walls"] else (3 if mode == "self" else 2)
		var sub = CardData.CardSubType.WINE if mode == "self" else CardData.CardSubType.PEACH
		var original: CardBase
		if mode == "concrete":
			original = CardBase.create(sub)
			game.players[2].determined_cards.append(original)
		else:
			game.players[3 if mode == "self" else 2].hand.append(null)
		if mode == "negative": game.players[2].hand.append(null)
		var offered: Array = []
		var actions: Array = []
		game.card_action_committed.connect(func(e): actions.append(e))
		game._rescue_choice_override = func(rescuer,_target,options):
			offered.append(rescuer.seat_index)
			return sub if options.has(sub) else -1
		var result = await game._deal_damage_result(null,dying,2 if mode == "negative" else 1,EffectChain.DamageType.PHYSICAL)
		t.check(not result.invalidated and dying.hp == 1 and dying.is_alive(), "I04 ordinary same-region rescue completes actual dying pipeline: "+mode)
		t.check(offered == ([2,2] if mode == "negative" else [expected]) and actions.size() == (2 if mode == "negative" else 1), "I04 ordinary current-turn origin is preserved, excluded A/F skipped; one/no-wall and repeated Peach remain legal")
		t.check(actions.all(func(e): return e.sub_type == sub and e.actor_body == game.players[expected] and e.settlement_completed) and game._pending_card_actions.is_empty(), "I04 rescue actor, self-Wine and completed USE facts stay correct")
		if mode not in ["one_wall","no_walls"]: t.check(game.players[0].hand_size() == 1 and game.players[5].hand_size() == 1, "I04 willing other-region rescuers retain their arbitrary cards")
		if original != null: t.check(actions[0].card == original and game.deck._discard.count(original) == 1, "I04 concrete Peach is paid as its original instance, once")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await payment_guard(t)
	await lan(t)
	await stale(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func payment_guard(t):
	var game = fixture(t)
	var dying = game.players[3]
	dying.hp = 0 # Explicit eligibility/payment boundary, not a full prior damage claim.
	for seat in [0,2]: game.players[seat].hand.append(null)
	t.check(game._rescue_options(game.players[0],dying).is_empty() and not game._use_rescue_card(game.players[0],dying,CardData.CardSubType.PEACH) and game.players[0].hand_size() == 1 and dying.hp == 0, "I04 direct rescue payment cannot bypass mountain eligibility or charge illegal remote Peach")
	t.check(game._rescue_options(game.players[2],dying).has(CardData.CardSubType.PEACH) and game._use_rescue_card(game.players[2],dying,CardData.CardSubType.PEACH) and dying.hp == 1 and game.players[2].hand_size() == 0, "I04 direct payment shares the same same-region eligibility as interactive rescue")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func bridge_fixture(t):
	var bridge = load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
	var game = bridge.game
	game._sacrifice_actor_override = func(_p,_t,_a): return false
	game._rescue_choice_override = Callable()
	game.players[3].hp = 1
	return bridge

func lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = bridge_fixture(t)
	var game = bridge.game
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	# Natural B DRAW gives two arbitrary cards. Real Wine consumes one,
	# Duel consumes the other, so current-turn B cannot pay rescue before C.
	helper.click(t,bridge,1,"出牌")
	helper.click(t,bridge,1,"基本牌")
	helper.click(t,bridge,1,"酒")
	await t.create_timer(0.15).timeout # Existing 0.1s card-selector confirmation tween.
	for i in 3: await t.process_frame
	helper.click(t,bridge,1,"出牌")
	helper.click(t,bridge,1,"锦囊牌")
	helper.click(t,bridge,1,"普通锦囊")
	helper.click(t,bridge,1,"决斗")
	await t.create_timer(0.15).timeout
	game._target_confirm_override = func(): return 1
	var target: String = bridge.snapshot(1).targets.get("3","")
	t.check(target != "" and bridge.submit(1,target), "I04 rescue actual B Wine then Duel legally spends both drawn cards before D's dying window")
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(2),"使用【桃】")
	t.check(token != "" and bridge.input_owner() == 2 and bridge.snapshot(0).controls.is_empty() and bridge.snapshot(5).controls.is_empty(), "I04 actual ordinary rescue offers same-region C, never willing opposite A/F")
	t.check(not bridge.submit(0,token) and bridge.submit(2,token), "I04 only C can pay actual Peach from current dying response")
	for i in 3: await t.process_frame
	t.check(game.players[3].hp == 1 and game.players[2].hand_size() == 0 and game.players[4].hand_size() == 1 and game.players[0].hand_size() == 1 and game.players[5].hand_size() == 1 and game._card_action_serial == 3, "I04 original Wine/Duel and actual rescue each count once, unused same/opposite resources remain")
	t.check(bridge.input_owner() == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._pending_card_actions.is_empty() and not bridge.submit(2,token), "I04 rescue finishes ordinary dying context and returns actual B PLAY, rejecting old Peach token")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func stale(t):
	for mode in ["phase","region"]:
		var bridge = bridge_fixture(t)
		var game = bridge.game
		var result: Array = []
		var drive = func(): result.append(await game._deal_damage_result(null,game.players[3],1,EffectChain.DamageType.PHYSICAL))
		drive.call()
		for i in 3: await t.process_frame
		var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(2),"使用【桃】")
		t.check(token != "", "I04 real same-region rescue window exists before explicit technical invalidation")
		if mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.END
		else: game.turn_manager.rounds.relocate_before(2,0)
		for i in 3: await t.process_frame
		t.check(result.size() == 1 and result[0].invalidated and not bridge.submit(2,token) and game.players[2].hand_size() == 1, "I04 expired/responder-moved Peach window cannot pay from old token")
		t.check(game.players[3].hp == 0 and not game.players[3].is_dead() and game._pending_card_actions.is_empty() and game._rescue_choice_pending.is_empty(), "I04 invalidated rescue preserves committed damage, applies no stale heal/death or pending response")
		game._game_over = true
		bridge.queue_free()
		await t.process_frame
