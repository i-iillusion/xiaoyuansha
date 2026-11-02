extends RefCounted

func fixture(t):
	var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,options,_v): return options.find([[4,0],[0,1]]))
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	return game

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var helper = load("res://Test/i04_burning_interception_cases.gd").new()
	for mode in ["healthy","dead","owner_death","owner_sage","remaining_card"]:
		var game = fixture(t)
		var owner = game.players[0]
		var source = game._burning_camp_neighbors(owner)[0]
		var other = game._burning_camp_neighbors(owner)[1]
		var source_id = game.unit_registry.id_for(source)
		if mode != "healthy": source.hp = 1
		if mode in ["owner_death","owner_sage"]: owner.hp = 1
		if mode == "owner_sage":
			owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			owner.sage_activated = true
			game._sage_save_override = func(): return true
		# Here Lightning is only a cleanup fixture; its actual transfer and
		# supported judgment paths are exercised separately below.
		var remaining = CardBase.create(CardData.CardSubType.LIGHTNING) if mode == "remaining_card" else null
		if remaining != null: source.judgment_cards.append(remaining)
		var original = helper.put_fire(source)
		game.turn_manager.current_phase = TurnManager.Phase.JUDGE
		# Mechanical quota sentinel; the terrain phase must not reset the
		# suspended player's ordinary card counts as a new whole turn would.
		game.turn_manager.use_card("duel")
		game.turn_manager.use_strike()
		var frame = [game.turn_manager.turn_id,game.turn_manager.phase_id,game.turn_manager.current_player_idx,game.turn_manager.current_unit_id]
		t.check(await game._run_judgment(source,false), "I04 Q34 explicit mountain fire judgment completes: "+mode)
		t.check(source.hp == (3 if mode == "healthy" else -1) and source.is_dead() == (mode != "healthy"), "I04 mountain center takes two fire damage and commits normal lethal damage")
		t.check(source.judgment_cards.is_empty() and game.deck._discard.count(original) == 1 and game._card_action_serial == 0, "I04 mountain original judged card discards once without card USE")
		t.check(frame == [game.turn_manager.turn_id,game.turn_manager.phase_id,game.turn_manager.current_player_idx,game.turn_manager.current_unit_id] and ActorIdentity.key_for(game.players,game.unit_registry,source) == null and game.turn_manager._get_turn_count("duel",0) == 1 and game.turn_manager.strike_count_this_turn == 1, "I04 explicit judgment never grants terrain a whole turn, actor key or reset of player quotas")
		var expected_left = game.players[4] if mode == "owner_death" else owner
		t.check(game.players[1].hp == game.players[1].max_hp-1 and game.players[1].judgment_cards.size() == 1 and expected_left.judgment_cards.size() == 1, "I04 dead-center retained position selects current living neighbors and spreads only to them")
		t.check(game.players[2].hp == game.players[2].max_hp and game.players[3].hp == game.players[3].max_hp, "I04 mountain-center fire does not silently fan out to nonneighbors")
		if mode == "owner_death":
			t.check(owner.is_dead() and expected_left.hp == expected_left.max_hp-1 and other.unit_disappeared and not other.is_dead(), "I04 center death followed by summoner death skips both retired terrain and dead summoner, retaining source location")
		elif mode == "owner_sage":
			t.check(owner.hp == 5 and owner.max_hp == 6 and owner.hand_size() == 4 and owner.jim_rebuild_pending == 0 and other.unit_disappeared, "I04 center fire continues after Sage reset and then damages the restored living neighbor")
		else:
			t.check(owner.hp == (5 if mode == "healthy" else 4) and owner.max_hp == (6 if mode == "healthy" else 5) and owner.jim_rebuild_pending == (0 if mode == "healthy" else 1), "I04 lethal center pays Zaoshan before the later neighbor fire")
		if remaining != null: t.check(game.deck._discard.count(remaining) == 1, "I04 terrain final death clears its remaining judged resources exactly once")
		if mode != "healthy":
			t.check(game.unit_registry.entry(source_id).reason == UnitRegistry.Removal.NORMAL_DEATH and not game.mountain_space.ids().has(source_id), "I04 effect retains only a local anchor, never the dead terrain's live marker")
			var before = game.players.map(func(p): return p.hp)
			var rejected = await game._resolve_burning_camp_result(source,1)
			t.check(rejected.outcome == game.CHOICE_INVALID and before == game.players.map(func(p): return p.hp), "I04 already-retired center cannot begin another burning effect")
		await helper.dispose(t,game)
	await expired(t)
	await lan(t)
	await lightning(t)
	await disappeared_center(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func expired(t):
	for mode in ["phase","removed","unsupported"]:
		var game = fixture(t)
		var mountain = game._burning_camp_neighbors(game.players[0])[0]
		var card = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(mountain)
		if mode == "unsupported": card.sub_type = CardData.CardSubType.INDULGENCE # illegal-zone fault injection
		else:
			game._nullify_override = func():
				if mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.END
				else: mountain.unit_disappeared = true # retained positive-HP tombstone boundary
				return false
		t.check(not await game._run_judgment(mountain,false) and mountain.hp == 5 and mountain.judgment_cards == [card] and not game.deck._discard.has(card), "I04 stale/unsupported terrain judgment cannot consume old card or deal damage: "+mode)
		t.check(not game.turn_manager.skip_play_phase and not game.turn_manager.supply_shortage_active, "I04 terrain judgment cannot alter the fixed player's skip flags")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = helper.bridge_fixture(t)
	helper.click(t,bridge,0,"山甲 玩家5→玩家1；山乙 玩家1→玩家2")
	var game = bridge.game
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game._nullify_override = Callable()
	game.players[1].hand.append(null)
	var mountain = game._burning_camp_neighbors(game.players[0])[0]
	var original = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(mountain)
	var result: Array = []
	# Explicit internal phase dispatch; automatic spatial scheduling is 4b-2.
	var drive = func(): result.append(await game._run_judgment(mountain,false))
	drive.call()
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(1),"放弃")
	t.check(token != "" and bridge.input_owner() == 1 and bridge.snapshot(0).controls.is_empty() and mountain.hp == 5, "I04 terrain judgment awaits an actual human counter window without terrain owning input")
	t.check(not bridge.submit(0,token) and bridge.submit(1,token), "I04 only the living responder can decline the mountain card counter")
	for i in 3: await t.process_frame
	t.check(result == [true] and mountain.hp == 3 and game.players[0].hp == 5 and game.players[1].hp == 4, "I04 explicit terrain judgment completes actual remote-style counter, center and neighbor damage")
	t.check(game.deck._discard.count(original) == 1 and bridge.input_owner() == 0 and bridge.acting_unit() == "" and not bridge.submit(1,token), "I04 settled terrain judgment restores the suspended player's controls and rejects replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func lightning(t):
	var helper = load("res://Test/i04_burning_interception_cases.gd").new()
	for mode in ["receive","skip","wrap","hit","lethal"]:
		var game = fixture(t)
		var owner = game.players[0]
		var mountain = game._burning_camp_neighbors(owner)[0]
		var original = CardBase.create(CardData.CardSubType.LIGHTNING)
		original.source_seat = 3
		if mode in ["receive","skip","wrap"]:
			# Exercise spatial movement independently of counter payment; the LAN
			# case below covers the actual nullification input and original card.
			if mode == "skip": mountain.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
			if mode == "wrap":
				for body in game._burning_camp_circle(owner):
					if body != owner: body.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
			var recipient = game._move_lightning(owner,original)
			var expected = mountain if mode == "receive" else (game.players[1] if mode == "skip" else owner)
			t.check(recipient == expected and recipient.judgment_cards.count(original) == 1, "I04 Q38 Lightning uses actual terrain order, skips duplicates across partition or wraps: "+mode)
			t.check(original.source_seat == 3 and not game.deck._discard.has(original) and game._card_action_serial == 0, "I04 Q38 transfer preserves original resource and metadata without USE")
		else:
			if mode == "lethal": mountain.hp = 4
			mountain.judgment_cards.append(original)
			var frame = [game.turn_manager.turn_id,game.turn_manager.phase_id,game.turn_manager.current_player_idx,game.turn_manager.current_unit_id]
			t.check(await game._run_judgment(mountain,false), "I04 Q34 mountain resolves its supported Lightning judgment: "+mode)
			t.check(mountain.hp == (1 if mode == "hit" else 0) and mountain.is_dead() == (mode == "lethal"), "I04 mountain takes three thunder plus its one elemental bonus")
			t.check(owner.hp == (6 if mode == "hit" else 5) and owner.max_hp == owner.hp and owner.jim_rebuild_pending == (0 if mode == "hit" else 1), "I04 lethal Lightning commits one mountain death and immediate Zaoshan cost")
			t.check(game.deck._discard.count(original) == 1 and mountain.judgment_cards.is_empty() and game._card_action_serial == 0, "I04 mountain Lightning discards once without new card USE")
			t.check(frame == [game.turn_manager.turn_id,game.turn_manager.phase_id,game.turn_manager.current_player_idx,game.turn_manager.current_unit_id] and ActorIdentity.key_for(game.players,game.unit_registry,mountain) == null, "I04 Lightning judgment cannot grant a terrain actor or whole turn")
		await helper.dispose(t,game)
	for wrap in [false,true]:
		var game = fixture(t)
		var owner = game.players[0]
		var mountain = game._burning_camp_neighbors(owner)[0]
		var original = CardBase.create(CardData.CardSubType.LIGHTNING)
		mountain.judgment_cards.append(original)
		if wrap:
			for body in game._burning_camp_circle(mountain):
				if body != mountain: body.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
		owner.hand.append(null)
		var offered: Array = []
		game._nullify_override = func(): offered.append(true); return offered.size() == 1
		t.check(await game._run_judgment(mountain,false), "I04 mountain Lightning nullifies through a paid counter: wrap="+str(wrap))
		var recipient = mountain if wrap else game.players[1]
		t.check(recipient.judgment_cards.count(original) == 1 and mountain.hp == 5 and owner.hand_size() == 0 and game._card_action_serial == 1, "I04 nullified terrain Lightning transfers once, or defers its wrapped original without rejudging")
		t.check(not game.deck._discard.has(original) and offered.size() == 2, "I04 wrapped Lightning does not restart counter/payment loop during the same judgment")
		await helper.dispose(t,game)
	await lightning_lan(t)

func disappeared_center(t):
	# Q43 withdraws the old Q39 Sacrifice-to-mountain premise. Preserve legal
	# disappearance continuation via a neighbor's Yudaxi killing the summoner.
	var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,options,_v): return options.find([[2,3],[0,1]]))
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	var owner = game.players[0]
	var mountain = game._burning_camp_neighbors(owner)[0]
	var other = game.unit_registry.all_bodies().filter(func(body): return body != mountain)[0]
	owner.hp = 1
	game.players[1].general_name = "里奥·普利威尔"
	game.players[1].hp = 1
	var original = load("res://Test/i04_burning_interception_cases.gd").new().put_fire(mountain)
	var deaths: Array = []
	game.unit_death_committed.connect(func(id): deaths.append(id))
	t.check(await game._run_judgment(mountain,false), "I04 Q43 legal neighbor Yudaxi removes summoner/carrier without aborting established fire")
	t.check(owner.is_dead() and owner.hand_size() == 0 and owner.max_hp == 6 and owner.jim_rebuild_pending == 0, "I04 summoner dies to Yudaxi without forbidden Sacrifice or fake Zaoshan cost")
	t.check(mountain.hp == 3 and not mountain.is_dead() and mountain.unit_disappeared and other.unit_disappeared and deaths.is_empty(), "I04 damaged carrier disappears, never commits a unit death")
	t.check(game.unit_registry.entry(game.unit_registry.id_for(mountain)).reason == UnitRegistry.Removal.SUMMONER_LOST and game.mountain_space.ids().is_empty(), "I04 Q39 original position survives only inside the established effect")
	t.check(game.players[1].hp == 1 and game.players[1].hand_size() == 1 and game.players[1].judgment_cards.size() == 1, "I04 legal neighbor Yudaxi revives Leo, and original fire spreads to that surviving selected neighbor")
	t.check(game.players[4].hp == game.players[4].max_hp-2 and game.players[4].judgment_cards.is_empty(), "I04 disappeared carrier does not replace its already-selected dead neighbor with E")
	t.check(game.players[2].hp == game.players[2].max_hp-2 and game.players[3].hp == game.players[3].max_hp-2 and game.deck._discard.count(original) == 1, "I04 legal nested death preserves committed Yudaxi deductions and discards original fire once")
	var before = game.players.map(func(p): return p.hp)
	var rejected = await game._resolve_burning_camp_result(mountain,1)
	t.check(rejected.outcome == game.CHOICE_INVALID and before == game.players.map(func(p): return p.hp), "I04 Q39 retired positive-HP carrier cannot start a fresh fire")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func lightning_lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = helper.bridge_fixture(t)
	helper.click(t,bridge,0,"山甲 玩家5→玩家1；山乙 玩家1→玩家2")
	var game = bridge.game
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game._nullify_override = Callable()
	game.players[1].hand.append(null)
	var original = CardBase.create(CardData.CardSubType.LIGHTNING)
	game.players[0].judgment_cards.append(original)
	var result: Array = []
	var drive = func(): result.append(await game._run_judgment(game.players[0],false))
	drive.call()
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(1),"无懈可击")
	t.check(token != "" and bridge.input_owner() == 1 and not bridge.submit(0,token), "I04 Q38 actual Lightning counter belongs only to responding human")
	t.check(bridge.submit(1,token), "I04 Q38 human pays a real arbitrary card as Nullification")
	for i in 3: await t.process_frame
	var mountain = game._burning_camp_neighbors(game.players[0])[0]
	t.check(result == [true] and mountain.judgment_cards == [original] and game.players[0].judgment_cards.is_empty() and mountain.hp == 5, "I04 Q38 actual nullified Lightning moves its original into adjacent mountain without damage")
	t.check(game.players[1].hand_size() == 0 and game._card_action_serial == 1 and not game.deck._discard.has(original), "I04 Q38 counter payment occurs once; transfer itself creates no USE or discard")
	t.check(bridge.input_owner() == 0 and bridge.acting_unit() == "" and not bridge.submit(1,token), "I04 Q38 settled counter restores parent actor and rejects replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
