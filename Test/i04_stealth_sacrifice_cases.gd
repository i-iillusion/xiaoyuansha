extends RefCounted

func make_dragon(game):
	game.players[1].general_name = "克里斯·西弗"
	return load("res://Test/i03_summon_cases.gd").new().seed_dragon(game,game.players[1])

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["hidden","visible","concrete","hidden_virtual","virtual","lethal_virtual"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
		load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game)
		game.turn_manager.current_player_idx = 3
		var dragon = make_dragon(game)
		var id = game.unit_registry.id_for(dragon)
		# Explicit prior-USE visibility boundary, not upstream turn/summon proof.
		var shown: Array[Player] = [game.players[3],game.players[0]]
		if mode not in ["hidden","hidden_virtual"]: shown.append(game.players[4])
		game.fire_dragon_state.record_use(id,1,shown)
		var original: CardBase
		if mode == "concrete":
			game.players[4].hand.clear()
			original = CardBase.create(CardData.CardSubType.SACRIFICE)
			game.players[4].determined_cards.append(original)
		if mode in ["virtual","lethal_virtual","hidden_virtual"]:
			game.players[4].general_name = "安普提·斯丢皮得"
			game.players[4].hand.clear()
			game.players[4].hp = 1 if mode in ["lethal_virtual","hidden_virtual"] else 3
			game._yes_ah_override = func(): return "skill"
			game._rps_override = func(p): return game.RPS_ROCK if p == game.players[4] else game.RPS_PAPER
		var offered: Array = []
		var actions: Array = []
		game.card_action_committed.connect(func(e): actions.append(e))
		game._sacrifice_actor_override = func(p,target,_amount):
			if target != dragon: return false
			offered.append(p.seat_index)
			return p.seat_index in [0,4]
		game.players[3].hand.append(null)
		await game.execute_card_on_target(dragon,CardData.CardSubType.DUEL)
		var hidden = mode in ["hidden","hidden_virtual"]
		var sacrifice = actions.filter(func(e): return e.sub_type == CardData.CardSubType.SACRIFICE)
		t.check(offered == ([3] if hidden else [3,4]) and dragon.hp == (2 if hidden else 3), "I04 Q50 hidden E is never asked; visible E may protect, visible cross-region A remains excluded: "+mode)
		t.check(game.players[0].hand_size() == 1 and game.players[2].hand_size() == 1 and game.players[5].hand_size() == 1, "I04 unit visibility and mountain region are independent necessary gates")
		t.check(sacrifice.size() == (0 if hidden else 1) and actions.all(func(e): return e.settlement_completed) and game._pending_card_actions.is_empty(), "I04 Q50 only legal actual protection commits and completes a Sacrifice USE")
		if mode == "hidden_virtual": t.check(game.players[4].hp == 1 and game.players[4].is_alive(), "I04 hidden no-hand protector cannot even pay virtual HP cost")
		elif mode == "lethal_virtual": t.check(game.players[4].is_dead() and game.players[4].hp == 0 and sacrifice[0].is_virtual, "I04 Q49/Q50 paid visible virtual response survives final death using retained visibility, without dead actor response authority")
		elif not hidden: t.check(game.players[4].hp == (1 if mode == "virtual" else 4) and (original == null or (sacrifice[0].card == original and game.deck._discard.count(original) == 1)), "I04 visible concrete/virtual protection preserves actual payment and independent transferred damage")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	for visible in [false,true]: await lan(t,visible)
	await stale(t)
	await unit_responder(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func choose_duel(t,bridge,seat,target):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	for text in ["出牌","锦囊牌","普通锦囊","决斗"]: helper.click(t,bridge,seat,text)
	await t.create_timer(0.15).timeout
	bridge.game._target_confirm_override = func(): return 1
	var token: String = bridge.snapshot(seat).targets.get(str(target),"")
	t.check(token != "" and bridge.submit(seat,token), "I04 Q50 actual Duel target command: "+str(target))
	for i in 3: await t.process_frame

func bridge_fixture(t,visible):
	var bridge = load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
	var game = bridge.game
	game._sacrifice_actor_override = func(_p,_target,_amount): return false
	game._duel_respond_override = func(): return false
	game._medicine_choice_override = func(_p,_options): return "cancel" # Explicitly decline Chris's unrelated DRAW choice.
	var dragon = make_dragon(game)
	var id = game.unit_registry.id_for(dragon)
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	helper.click(t,bridge,1,"结束出牌")
	for i in 3: await t.process_frame
	t.check(game.turn_manager.current_unit_id == id and dragon.hand_size() == 1 and bridge.acting_unit() == id, "I04 actual B whole-turn END reaches attached R first DRAW/PLAY with its own single arbitrary card")
	if visible:
		# Actual authorized paid two-target card entry, not fabricated revealed bits.
		var targets: Array[Player] = [game.players[3],game.players[4]]
		await game._execute_iron_chain(targets)
	else: await choose_duel(t,bridge,1,3)
	t.check(game.fire_dragon_state.is_revealed_to(id,game.players[3]) and game.fire_dragon_state.is_revealed_to(id,game.players[4]) == visible and dragon.hand_size() == 0, "I04 real unit Duel/Chain USE reveals exactly D / D+E and pays R's card, not B's")
	helper.click(t,bridge,1,"结束出牌")
	for i in 3: await t.process_frame
	helper.click(t,bridge,2,"结束出牌")
	for i in 3: await t.process_frame
	t.check(game.turn_manager.current_player_idx == 3 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 ordinary order resumes through C to actual D PLAY")
	game._sacrifice_actor_override = Callable()
	await choose_duel(t,bridge,3,id)
	helper.click(t,bridge,3,"放弃") # Source D can legally protect but declines first.
	for i in 3: await t.process_frame
	return [bridge,dragon,id]

func lan(t,visible):
	var data = await bridge_fixture(t,visible)
	var bridge = data[0]
	var game = bridge.game
	var find = load("res://Test/i04_movement_cases.gd").new()
	var token = find.find(bridge.snapshot(4),"打出【舍己为人】")
	if visible:
		t.check(token != "" and bridge.input_owner() == 4 and not bridge.submit(2,token) and bridge.submit(4,token), "I04 revealed E has actual exclusive protection command")
		for i in 3: await t.process_frame
		for seat in [1,2,3]:
			load("res://Test/i04_aoe_region_cases.gd").new().click(t,bridge,seat,"放弃")
			for i in 3: await t.process_frame
	else: t.check(token == "" and bridge.snapshot(4).controls.is_empty() and game.players[4].hand_size() == 1, "I04 Q50 hidden E has no response window and cannot spend a card after real upstream unit Duel")
	t.check(data[1].hp == (3 if visible else 2) and game.players[4].hp == (4 if visible else 5) and game.players[4].hand_size() == (0 if visible else 1), "I04 real hidden/revealed unit damage or protection follows Q50")
	t.check(bridge.input_owner() == 3 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._pending_card_actions.is_empty() and (not visible or not bridge.submit(4,token)), "I04 unit protection completion returns D's actual PLAY and rejects old E response")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func unit_responder(t):
	var bridge = load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
	var game = bridge.game
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	var dragon = make_dragon(game)
	var id = game.unit_registry.id_for(dragon)
	# Prior visibility/action-serial snapshot, not a claim of an upstream paid
	# AOE. All see R, avoiding any new question about this response revealing R.
	var shown: Array[Player] = []
	shown.assign(game.players)
	game.fire_dragon_state.record_use(id,1,shown)
	game._card_action_serial = 1
	dragon.hand.append(null)
	var actions: Array = []
	game.card_action_committed.connect(func(e): actions.append(e))
	var result: Array = []
	var drive = func(): result.append(await game._deal_damage_result(game.players[3],game.players[4],1,EffectChain.DamageType.PHYSICAL))
	drive.call()
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(1),"打出【舍己为人】")
	t.check(token != "" and bridge.input_owner() == 1 and game.players[1].hand_size() == 0 and dragon.hand_size() == 1, "I04 response controller has no hand, but actual R's own card authorizes its protection window")
	t.check(bridge.submit(1,token), "I04 R's controller may submit R's actual protection response")
	for i in 3: await t.process_frame
	t.check(result.size() == 1 and not result[0].invalidated and game.players[4].hp == 5 and dragon.hp == 2 and dragon.hand_size() == 0 and game.players[1].hand_size() == 0, "I04 unit response pays and damages R, never borrows controller hand or HP")
	t.check(actions.size() == 1 and actions[0].actor_key == id and actions[0].settlement_completed and game._pending_card_actions.is_empty() and not bridge.submit(1,token), "I04 unit protection fact belongs to R and old controller token cannot replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func stale(t):
	var data = await bridge_fixture(t,true)
	var bridge = data[0]
	var game = bridge.game
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(4),"打出【舍己为人】")
	t.check(token != "", "I04 visible E has real pending response before explicit visibility invalidation")
	# Engineering invalidation only; no ordinary skill is claimed to hide R again.
	game.fire_dragon_state._dragons[data[2]].revealed.erase(game.players[4])
	for i in 3: await t.process_frame
	t.check(not bridge.submit(4,token) and game.players[4].hand_size() == 1 and data[1].hp == 3 and game.players[4].hp == 5, "I04 lost visibility after choice cannot authorize old protection payment or damage")
	t.check(game._pending_card_actions.is_empty(), "I04 invalidated unit response abandons its old parent continuation without pending USE leaks")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
