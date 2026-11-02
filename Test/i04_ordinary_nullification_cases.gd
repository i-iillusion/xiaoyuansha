extends RefCounted

func fixture(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game.lan_enabled = true
	game.turn_manager.current_player_idx = 1 # Native current-actor boundary.
	game._spawn_mountain_at(game.players[0],0,1)
	game._spawn_mountain_at(game.players[0],3,4)
	game._duel_respond_override = func(): return false
	game._zone_pick_override = func(): return "hand"
	return game

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	await single(t)
	await groups(t)
	await gifted(t)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func single(t):
	for mode in ["first","next","even","self","concrete","steal","dismantle","borrow"]:
		var game = fixture(t)
		var sub = CardData.CardSubType.DUEL
		if mode == "steal": sub = CardData.CardSubType.SNATCH
		elif mode == "dismantle": sub = CardData.CardSubType.DISMANTLE
		elif mode == "borrow":
			sub = CardData.CardSubType.BORROWED_SWORD
			game.players[2].equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QINGGANG_SWORD))
			game._borrowed_second_target_override = func(options): return options.find(game.players[3])
		var original: CardBase
		if mode == "concrete":
			original = CardBase.create(sub)
			game.players[1].determined_cards.append(original)
			game._pending_determined_card = original
		else: game.players[1].hand.append(null)
		for seat in [0,2,3,4]: game.players[seat].hand.append(null)
		if mode == "self": game.players[1].hand.append(null)
		var offered: Array = []
		var actions: Array = []
		game.card_action_committed.connect(func(event): actions.append(event))
		game._nullify_override = func():
			var seat = game._input_seat
			offered.append(seat)
			if game.players[seat].hand_size() == 0: return false
			if mode == "self": return seat in [0,1,4]
			if mode == "next": return seat in [0,3,4]
			return seat in [0,2,4] or (mode == "even" and seat == 3)
		await game.execute_card_on_target(game.players[2],sub)
		var expected: Array = [2,3,1,2]
		if mode in ["next","even"]: expected = [2,3,1,2,3]
		elif mode == "self": expected = [2,3,1,2,3,1]
		t.check(offered == expected and not offered.has(0) and not offered.has(4), "I04 Q46 ordinary first counter starts at actual user B's downstream C, excludes A/E: "+mode)
		t.check(game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1 and game.players[2].hp == (4 if mode == "even" else 5), "I04 ordinary odd/even counter parity preserves opposite-region hands and legal target damage")
		t.check(actions.size() == (3 if mode == "even" else 2) and actions[0].actor_body == game.players[1] and actions[0].sub_type == sub and actions.all(func(event): return event.settlement_completed), "I04 original paid trick and actual counters settle exactly once")
		t.check(game.deck._discard.count(actions[0].card) == 1 and (mode != "concrete" or actions[0].card == original) and game._pending_card_actions.is_empty() and game._input_seat == 1, "I04 ordinary/concrete original resource stays unique and returns B's PLAY input")
		if mode == "borrow": t.check(game.players[2].get_weapon() == CardData.CardSubType.QINGGANG_SWORD and game.turn_manager.borrowed_sword_count_this_turn == 1, "I04 nullified original Borrow keeps weapon equipped and counts the actual Borrow use once")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func groups(t):
	for sub in [CardData.CardSubType.PEACH_GARDEN,CardData.CardSubType.HARVEST,CardData.CardSubType.DISARM,CardData.CardSubType.BARBARIAN_INVASION,CardData.CardSubType.VOLLEY_OF_ARROWS,CardData.CardSubType.IRON_CHAIN]:
		var game = fixture(t)
		game.players[1].hand.append(null)
		for seat in [0,4]: game.players[seat].hand.append(null)
		for p in game.players: p.hp = 4
		if sub == CardData.CardSubType.DISARM:
			var equipment = [CardData.CardSubType.QINGGANG_SHIELD,CardData.CardSubType.LIANNU,CardData.CardSubType.QINGGANG_SWORD,CardData.CardSubType.BAGUA_ZHEN,CardData.CardSubType.ZHUGE_LIANNU]
			for seat in 5: game.players[seat].equip_card_to_slot("armor" if seat in [0,3] else "weapon",CardBase.create(equipment[seat]))
		var offered: Array = []
		game._nullify_override = func(): offered.append(game._input_seat); return game._input_seat in [0,4]
		match sub:
			CardData.CardSubType.PEACH_GARDEN: await game._play_peach_garden()
			CardData.CardSubType.HARVEST: await game._play_harvest()
			CardData.CardSubType.DISARM: await game._play_disarm()
			CardData.CardSubType.BARBARIAN_INVASION: await game._play_aoe(CardData.CardSubType.STRIKE,"南蛮入侵","杀")
			CardData.CardSubType.VOLLEY_OF_ARROWS: await game._play_aoe(CardData.CardSubType.DODGE,"万箭齐发","闪")
			CardData.CardSubType.IRON_CHAIN:
				var targets: Array[Player] = [game.players[2],game.players[3]]
				await game._execute_iron_chain(targets)
		var repetitions = 3 if sub in [CardData.CardSubType.PEACH_GARDEN,CardData.CardSubType.HARVEST,CardData.CardSubType.DISARM] else 2
		var expected: Array = []
		for i in repetitions: expected.append_array([2,3,1])
		t.check(offered == expected and game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1, "I04 Q46 each paid global/multi-target branch restarts downstream at user B and excludes other region: "+str(sub))
		t.check(game._card_action_serial == 1 and game._pending_card_actions.is_empty(), "I04 blocked responders cannot manufacture counter USE or change original group payment")
		if sub == CardData.CardSubType.PEACH_GARDEN: t.check(game.players[1].hp == 5 and game.players[2].hp == 5 and game.players[3].hp == 5 and game.players[0].hp == 4 and game.players[4].hp == 4, "I04 group heal still applies only to current original region")
		elif sub == CardData.CardSubType.HARVEST: t.check(game.players[1].hand_size() == 1 and game.players[2].hand_size() == 1 and game.players[3].hand_size() == 1, "I04 group draws do not let another region counter later branches")
		elif sub == CardData.CardSubType.DISARM: t.check(game.players[1].get_equip_slots().is_empty() and game.players[2].get_equip_slots().is_empty() and game.players[3].get_equip_slots().is_empty() and game.players[0].get_armor() == CardData.CardSubType.QINGGANG_SHIELD and game.players[4].get_weapon() == CardData.CardSubType.ZHUGE_LIANNU, "I04 Disarm's ordinary counter scope preserves equipment in the excluded region")
		elif sub == CardData.CardSubType.IRON_CHAIN: t.check(game.players[2].chained and game.players[3].chained and not game.players[0].chained and not game.players[4].chained, "I04 both declared chain targets complete with no forbidden cross-region counter")
		else: t.check(game.players[2].hp == 3 and game.players[3].hp == 3 and game.players[0].hp == 4 and game.players[4].hp == 4, "I04 actual AOE effects still preserve declaration and mountain regions")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func gifted(t):
	var game = fixture(t)
	game.turn_manager.current_player_idx = 2
	game.turn_manager.current_phase = TurnManager.Phase.START
	# Mechanical authorized-phase boundary, not a claim of Max's menu payment.
	var frame = game.turn_manager.begin_standalone_play(1)
	for seat in [0,1,2,4]: game.players[seat].hand.append(null)
	var offered: Array = []
	var actions: Array = []
	game.card_action_committed.connect(func(event): actions.append(event))
	game._nullify_override = func():
		var seat = game._input_seat
		offered.append(seat)
		return seat in [0,2,4] and game.players[seat].hand_size() > 0
	await game.execute_card_on_target(game.players[2],CardData.CardSubType.DUEL)
	t.check(not frame.is_empty() and offered == [2,3,1,2], "I04 Q46 gifted B PLAY uses actual B downstream C, not parent turn owner C downstream D")
	t.check(game.turn_manager.current_player_idx == 2 and game.turn_manager.get_play_actor_key() == 1 and game._input_seat == 1, "I04 gifted counter completion retains parent C turn and returns actual B input")
	t.check(actions.size() == 2 and actions[0].actor_key == 1 and actions[0].turn_owner_key == 2 and actions.all(func(e): return e.settlement_completed), "I04 gifted original/counter facts preserve acting bodies and turn ownership")
	t.check(game.turn_manager._get_turn_count("duel",1) == 1 and game.turn_manager._get_turn_count("duel",2) == 0 and game._pending_card_actions.is_empty(), "I04 gifted ordinary counter charges actual user's Duel quota once without advancing the parent")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = helper.bridge_fixture(t,4)
	var game = bridge.game
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY, "I04 ordinary counter adapter advances actual A END to B PLAY")
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	for seat in [0,1,2,4]: game.players[seat].hand.append(null)
	game._spawn_mountain_at(game.players[4],0,1)
	game._spawn_mountain_at(game.players[4],3,4)
	game._nullify_override = Callable()
	game._target_confirm_override = func(): return 1
	helper.click(t,bridge,1,"出牌")
	helper.click(t,bridge,1,"锦囊牌")
	helper.click(t,bridge,1,"普通锦囊")
	helper.click(t,bridge,1,"决斗")
	await t.create_timer(0.15).timeout
	var target: String = bridge.snapshot(1).targets.get("2","")
	t.check(target != "" and bridge.submit(1,target), "I04 actual ordinary Duel target command pays B's card and enters counter chain")
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(2),"打出【无懈可击】")
	t.check(token != "" and bridge.input_owner() == 2 and bridge.snapshot(0).controls.is_empty() and bridge.snapshot(4).controls.is_empty(), "I04 Q46 actual first ordinary counter belongs to C, not fixed A or target C's downstream D")
	t.check(not bridge.submit(4,token) and bridge.submit(2,token), "I04 ordinary C can pay real Nullification; opposite side cannot submit it")
	for i in 3: await t.process_frame
	t.check(game.players[2].hp == 5 and game.players[2].hand_size() == 0 and game.players[0].hand_size() == 1 and game.players[4].hand_size() == 1 and game._card_action_serial == 2, "I04 actual ordinary Duel is nullified by C once and excluded side retains physical hands")
	t.check(bridge.input_owner() == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._pending_card_actions.is_empty() and not bridge.submit(2,token), "I04 ordinary counter completion restores actual B PLAY and refuses old response token")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
