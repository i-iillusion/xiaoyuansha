extends RefCounted

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
	load("res://Test/i04_sacrifice_region_cases.gd").new().configure(game)
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	game.turn_manager.current_player_idx = 3
	var dragon = load("res://Test/i04_stealth_sacrifice_cases.gd").new().make_dragon(game)
	var shown: Array[Player] = [game.players[3]]
	game.fire_dragon_state.record_use(game.unit_registry.id_for(dragon),1,shown)
	game._card_action_serial = 1 # Explicit matching prior-USE/visibility boundary.
	dragon.hand.append(null)
	return [game,dragon]

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await native_cases(t)
	await recording_guard(t)
	await sacrifice_lan(t)
	await direct_lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func native_cases(t):
	for mode in ["sacrifice","nullification","counter"]:
		var data = fixture(t)
		var game = data[0]
		var dragon = data[1]
		var id = game.unit_registry.id_for(dragon)
		game.players[3].hand.append(null)
		if mode == "counter": game.players[2].hand.append(null)
		var actions: Array = []
		var c_paid: Array[bool] = [false]
		game.card_action_committed.connect(func(e):
			actions.append(e)
			if e.actor_body == game.players[2] and e.sub_type == CardData.CardSubType.NULLIFICATION: c_paid[0] = true)
		game._nullify_override = func():
			if mode == "sacrifice": return false
			if mode == "counter" and game._input_seat == 2: return game.players[2].hand_size() > 0
			return game._input_seat == 1 and dragon.hand_size() > 0 and (mode != "counter" or c_paid[0])
		game._sacrifice_actor_override = func(p,target,_amount): return mode == "sacrifice" and p == dragon and target == game.players[4]
		await game.execute_card_on_target(game.players[4],CardData.CardSubType.DUEL)
		t.check(game.players[4].hp == (4 if mode == "counter" else 5) and dragon.hp == (2 if mode == "sacrifice" else 3) and dragon.hand_size() == 0, "I04 Q51 actual unit response pays its own card and applies redirect/counter parity: "+mode)
		t.check(not game.fire_dragon_state.is_revealed_to(id,game.players[4]) and not game.fire_dragon_state.is_revealed_to(id,game.players[2]) and game.fire_dragon_state.is_revealed_to(id,game.players[3]), "I04 unit Sacrifice/Nullification/anti-Nullification never reveal protected or countered roles, preserving prior D visibility")
		t.check(actions.size() == (3 if mode == "counter" else 2) and actions.all(func(e): return e.settlement_completed) and game._pending_card_actions.is_empty(), "I04 real original/counter actions complete once, with no fake visibility USE")
		t.check(not game._can_target_body(game.players[4],dragon), "I04 Q51 original target E still cannot select hidden R after the response")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func recording_guard(t):
	for sub in [CardData.CardSubType.NULLIFICATION,CardData.CardSubType.SACRIFICE,CardData.CardSubType.DUEL,CardData.CardSubType.IRON_CHAIN]:
		var data = fixture(t)
		var game = data[0]
		var dragon = data[1]
		var id = game.unit_registry.id_for(dragon)
		# Recording seam only: inject a supplied role list after real material
		# payment. This is not permission to open a free-standing counter window.
		var card = HandPayment.take_card(dragon,sub)
		game.deck.discard(card)
		var action = game._record_card_action(dragon,card,CardActionEvent.Kind.USE,true,false,[game.players[4]])
		var direct = sub in [CardData.CardSubType.DUEL,CardData.CardSubType.IRON_CHAIN]
		t.check(game.fire_dragon_state.is_revealed_to(id,game.players[4]) == direct and game.fire_dragon_state.is_revealed_to(id,game.players[3]), "I04 Q51/Q52 recording guard ignores counter role lists, while direct declarations retain normal reveal")
		var replay_targets: Array[Player] = [game.players[2]]
		t.check(not game.fire_dragon_state.record_use(id,action.id,replay_targets) and not game.fire_dragon_state.is_revealed_to(id,game.players[2]) and game.deck._discard.count(card) == 1, "I04 counter USE still advances its serial and cannot be replayed to manufacture visibility")
		game._abandon_card_actions([action]) # No claim that injected effects resolved.
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func start_bridge(t):
	var bridge = load("res://Test/i04_sacrifice_region_cases.gd").new().bridge_fixture(t)
	var game = bridge.game
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	var dragon = load("res://Test/i04_stealth_sacrifice_cases.gd").new().make_dragon(game)
	game._medicine_choice_override = func(_p,_options): return "cancel"
	game._sacrifice_actor_override = func(_p,_target,_amount): return false
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	helper.click(t,bridge,1,"结束出牌")
	for i in 3: await t.process_frame
	t.check(game._play_actor() == dragon and dragon.hand_size() == 1, "I04 Q51/Q52 real B whole turn hands off to R's own first DRAW/PLAY")
	return [bridge,dragon,game.unit_registry.id_for(dragon)]

func sacrifice_lan(t):
	var data = await start_bridge(t)
	var bridge = data[0]
	var game = bridge.game
	var dragon = data[1]
	var id = data[2]
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var cards = load("res://Test/i04_stealth_sacrifice_cases.gd").new()
	game.players[3].hand.append(null) # Prior response-card boundary, not extra R draw.
	game._duel_respond_override = Callable()
	await cards.choose_duel(t,bridge,1,3)
	helper.click(t,bridge,3,"出【杀】")
	for i in 3: await t.process_frame
	t.check(dragon.hp == 2 and dragon.hand_size() == 0 and game.fire_dragon_state.is_revealed_to(id,game.players[3]) and not game.fire_dragon_state.is_revealed_to(id,game.players[4]), "I04 Q51 real D Strike response hurts empty R, revealing only original Duel target D")
	helper.click(t,bridge,1,"结束出牌")
	for i in 3: await t.process_frame
	helper.click(t,bridge,2,"结束出牌")
	for i in 3: await t.process_frame
	for text in ["出牌","锦囊牌","普通锦囊","五谷丰登"]: helper.click(t,bridge,3,text)
	await t.create_timer(0.15).timeout
	t.check(dragon.hp == 2 and dragon.hand_size() == 1 and game.players[3].hand_size() == 1, "I04 real D Harvest legally gives wounded visible R exactly one arbitrary card")
	game._sacrifice_actor_override = Callable()
	await cards.choose_duel(t,bridge,3,4)
	helper.click(t,bridge,1,"放弃") # B's own two cards are not R's response material.
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(1),"打出【舍己为人】")
	t.check(token != "" and bridge.submit(1,token), "I04 controller B actually submits R's separate Sacrifice after declining its own response")
	for i in 3: await t.process_frame
	t.check(dragon.hp == 1 and dragon.hand_size() == 0 and game.players[4].hp == 5 and game.players[1].hand_size() == 2 and not game.fire_dragon_state.is_revealed_to(id,game.players[4]), "I04 Q51 exact timeline: R pays/receives transferred damage, E stays healthy and still cannot see R")
	t.check(bridge.input_owner() == 3 and game._pending_card_actions.is_empty(), "I04 actual redirected Duel completes back in D PLAY")
	helper.click(t,bridge,3,"结束出牌")
	for i in 3: await t.process_frame
	for text in ["出牌","锦囊牌","普通锦囊","决斗"]: helper.click(t,bridge,4,text)
	await t.create_timer(0.15).timeout
	t.check(not bridge.snapshot(4).targets.has(id) and game.players[4].hand_size() == 2, "I04 Q51 E's next real turn cannot target R with Duel; no payment is taken for unavailable target")
	helper.click(t,bridge,4,"取消选择")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func direct_lan(t):
	var data = await start_bridge(t)
	var bridge = data[0]
	var game = bridge.game
	var dragon = data[1]
	var id = data[2]
	game.players[2].hand.append(null)
	game._nullify_override = Callable()
	await load("res://Test/i04_stealth_sacrifice_cases.gd").new().choose_duel(t,bridge,1,3)
	t.check(game.fire_dragon_state.is_revealed_to(id,game.players[3]) and game.players[3].hp == 5, "I04 Q52 R reveals to declared D before any Duel effect, while original card is still counterable")
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(2),"打出【无懈可击】")
	t.check(token != "" and bridge.submit(2,token), "I04 Q52 real C Nullification cancels R's declared Duel")
	for i in 3: await t.process_frame
	load("res://Test/i04_aoe_region_cases.gd").new().click(t,bridge,1,"放弃")
	for i in 3: await t.process_frame
	t.check(game.players[3].hp == 5 and game.fire_dragon_state.is_revealed_to(id,game.players[3]) and not game.fire_dragon_state.is_revealed_to(id,game.players[2]), "I04 Q52 canceled direct effect retains D visibility, without revealing R to counter user C")
	t.check(bridge.acting_unit() == id and bridge.input_owner() == 1 and dragon.hand_size() == 0 and game._pending_card_actions.is_empty() and not bridge.submit(2,token), "I04 direct-card counter completes both payments and returns R PLAY without old-token authority")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
