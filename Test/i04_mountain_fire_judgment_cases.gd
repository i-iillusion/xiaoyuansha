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
		# A legal previously-received Lightning is a cleanup fixture only, not
		# proof of its still-unimplemented transfer or normal judgment path.
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
