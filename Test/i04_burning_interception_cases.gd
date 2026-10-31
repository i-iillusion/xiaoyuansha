extends RefCounted

func prepare(game):
	game._halt_countdown()
	game._nullify_override = func(): return false
	game._ai_response_override = func(_view,_kind,_options): return -1
	game._sacrifice_actor_override = func(_p,_target,_amount): return false
	game._rescue_choice_override = func(_r,_d,_o): return -1
	for p in game.players: p.hand.clear(); p.determined_cards.clear()

func put_fire(body,source_seat := 1):
	var card = CardBase.create(CardData.CardSubType.BURNING_CAMP)
	card.source_seat = source_seat
	body.judgment_cards.append(card)
	return card

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["healthy","one_dead","both_dead","duplicate"]:
		var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,options,_v): return options.find([[4,0],[0,1]]))
		prepare(game)
		var owner = game.players[0]
		var neighbors = game._burning_camp_neighbors(owner)
		t.check(neighbors.size() == 2 and neighbors.all(func(body): return game._is_mountain_body(body)), "I04 Q32 Jim's adjacent fire recipients are the two actual mountains")
		var near = neighbors[0]
		var far = neighbors[1]
		if mode in ["one_dead","both_dead"]: near.hp = 1
		if mode == "both_dead": far.hp = 1
		var existing = put_fire(far,3) if mode == "duplicate" else null
		# Native boundary fixture represents legal pre-opening placement. The LAN
		# case below actually pays/places the card before the genuine first START.
		var original = put_fire(owner)
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		var deaths: Array = []
		game.unit_death_committed.connect(func(id): deaths.append(id))
		t.check(await game._run_judgment(owner,false), "I04 Q30/Q32 old fire completes after later mountain isolation: "+mode)
		t.check(game.players.slice(1).all(func(p): return p.hp == p.max_hp and p.judgment_cards.is_empty()), "I04 Q33 fire neither damages nor spreads behind selected mountains: "+mode)
		t.check(owner.judgment_cards.is_empty() and game.deck._discard.count(original) == 1 and game._card_action_serial == 0, "I04 old original fire is discarded once; spreading never fabricates card USE")
		var lost = 2 if mode == "both_dead" else (1 if mode == "one_dead" else 0)
		t.check(owner.hp == 5-lost and owner.max_hp == 6-lost and owner.jim_rebuild_pending == lost and deaths.size() == lost, "I04 adjacent fire awaits each mountain's real death and separate immediate Zaoshan cost")
		if lost < 2:
			t.check(far.hp == 3 and far.judgment_cards.size() == 1 and far.judgment_cards[0].sub_type == CardData.CardSubType.BURNING_CAMP, "I04 Q33 surviving mountain receives exactly two fire damage and one delayed card")
			if existing != null: t.check(far.judgment_cards[0] == existing, "I04 same-name delayed fire keeps original existing instance rather than duplicating/replacing it")
		if lost == 0:
			t.check(near.hp == 3 and near.judgment_cards.size() == 1 and near.judgment_cards[0].source_seat == 1, "I04 generated fire retains metadata without becoming source-attributed damage")
		else:
			t.check(near.is_dead() and near.judgment_cards.is_empty(), "I04 G02-Q4 dead selected mountain receives no new fire and no substitute neighbor")
		var damages = game.action_history.entries.filter(func(entry): return entry.kind == "damage")
		t.check(damages.size() == 3 and damages.all(func(entry): return entry.text.begins_with("无来源 对")), "I04 center and two terrain hits retain sourceless fire attribution")
		await dispose(t,game)
	await disappearing_neighbor(t)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func disappearing_neighbor(t):
	for sage in [false,true]:
		var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,options,_v): return options.find([[0,1],[1,2]]))
		prepare(game)
		var owner = game.players[0]
		var center = game.players[1]
		owner.hp = 1
		if sage:
			owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			owner.sage_activated = true
			game._sage_save_override = func(): return true
		var neighbors = game._burning_camp_neighbors(center)
		neighbors[0].hp = 1
		var retired = neighbors[1]
		var original = put_fire(center,2)
		game.turn_manager.current_player_idx = 1
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		var deaths: Array = []
		game.unit_death_committed.connect(func(id): deaths.append(id))
		t.check(await game._run_judgment(center,false), "I04 first mountain's Zaoshan may remove the other selected mountain without invalidating old fire")
		t.check(deaths.size() == 1 and retired.unit_disappeared and not retired.is_dead() and retired.hp == 5 and retired.judgment_cards.is_empty(), "I04 disappeared second neighbor takes no late fire, receives no delayed card and adds no normal death")
		t.check(owner.is_alive() == sage and game.mountain_space.ids().is_empty() and (owner.jim_rebuild_pending == 0 if sage else owner.max_hp == 5), "I04 Sage restores general resources; final owner death retains its one charged Zaoshan cost")
		t.check(center.hp == center.max_hp-1 and game.players[2].hp == game.players[2].max_hp and game.players[2].judgment_cards.is_empty() and game.deck._discard.count(original) == 1 and not game._game_over, "I04 G02-Q4 selected disappearance never substitutes C or loses original card completion")
		await dispose(t,game)

func lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = helper.bridge_fixture(t,4)
	var game = bridge.game
	game._nullify_override = func(): return false
	game._target_confirm_override = func(): return 1
	game._sacrifice_actor_override = func(_p,_target,_amount): return false
	game._enter_targeting_mode(CardData.CardSubType.BURNING_CAMP)
	var token: String = bridge.snapshot(0).targets.get("4","")
	t.check(token != "" and not bridge.submit(4,token) and bridge.submit(0,token), "I04 Q32 real B pays delayed fire into fifth-seat Jim before any mountain exists")
	var original = game.players[4].judgment_cards[0]
	for seat in 4:
		game.players[seat].hand.clear()
		helper.click(t,bridge,seat,"结束出牌")
		for i in 3: await t.process_frame
	helper.click(t,bridge,4,"山甲 玩家4→玩家5；山乙 玩家5→玩家1")
	for i in 3: await t.process_frame
	var mountains = game.unit_registry.active_units()
	t.check(mountains.size() == 2 and mountains.all(func(body): return body.hp == 3 and body.judgment_cards.size() == 1), "I04 Q32/Q33 real opening and old judgment damage/spread to two mountains")
	t.check(game.players[4].hp == 5 and game.players.slice(0,4).all(func(p): return p.hp == p.max_hp and p.judgment_cards.is_empty()) and game.deck._discard.count(original) == 1, "I04 genuine Q32 timeline protects B/E and discards the actually paid original once")
	for seat in [0,4]:
		var view = bridge.snapshot(seat)
		t.check(UnitObservation.valid(view.units,5,seat) and view.units.all(func(row): return row.controller == -1 and row.own_cards.is_empty() and row.judgments == [CardData.CardSubType.BURNING_CAMP]), "I04 remote/controller snapshots publicly serialize mountain fire without granting terrain ownership")
	t.check(game.turn_manager.current_player_idx == 4 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and bridge.input_owner() == 4 and not bridge.submit(0,token), "I04 player-only judgment returns to Jim's real PLAY; old target token cannot replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
