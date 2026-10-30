extends RefCounted

func fixture(t, count := 5, same_gap := false):
	var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,count,true,func(_p,options,_v):
		return 0 if same_gap else options.find([[1,2],[4,0] if count == 5 else [4,5]]))
	game._halt_countdown()
	game._rescue_choice_override = func(_r,_d,_o): return -1
	game._jim_gather_choice_override = func(_p,options,_v): return options.find("heal")
	game._hand_discard_override = func(snapshot,count,_m): return snapshot.defaults(count)
	return game

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func used(game): return game.turn_manager.phase_skill_used("jushan",0)

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var game = fixture(t)
	var owner = game.players[0]
	var hand = owner.hand_size()
	var serial = game._card_action_serial
	owner.hp = 5
	game.players[1].hp = 2
	var other_hp = game.players[2].hp
	t.check(await game._activate_jushan(owner) == 1 and owner.hp == 6 and game.players[1].hp == 3 and game.players[2].hp == other_hp, "I04 Gather heals only players in the smaller side, capped at maximum")
	t.check(owner.hand_size() == hand-1 and used(game) and game._card_action_serial == serial, "I04 Gather pays one original hand card and actual PLAY quota without card USE")
	t.check(await game._activate_jushan(owner) == 0 and owner.hand_size() == hand-1, "I04 Gather cannot activate twice in the same PLAY")
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_play(0)
	game._do_play(1)
	t.check(await game._activate_jushan(owner) == 1 and game.players[1].hp == 4, "I04 Gather has an independent quota in granted PLAY")
	game.end_play_phase()
	t.check(frame.completed and game._jim_mountain_skill_pending.is_empty(), "I04 Gather releases the active skill lease before finishing a granted stage")
	await dispose(t,game)
	game = fixture(t,6)
	owner = game.players[0]
	# Attached Fire body is a population-count fixture, not Jim's summon skill.
	var dragon = FireDragonState.create_body()
	var dragon_id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,dragon,game.players[1])
	game.fire_dragon_state.attach(dragon_id)
	hand = owner.hand_size()
	t.check(await game._activate_jushan(owner) == 0 and owner.hand_size() == hand and not used(game), "I04 Q5 a fire dragon cannot break a three-versus-three player-count tie")
	await dispose(t,game)
	game = fixture(t)
	owner = game.players[0]
	var mountain = game.unit_registry.active_units()[0]
	mountain.hp = 0
	mountain.mark_dead()
	game._retire_final_unit(mountain) # one-mountain eligibility fixture, not death cost
	t.check(await game._activate_jushan(owner) == 0 and not used(game), "I04 M4 one remaining mountain cannot Gather")
	await dispose(t,game)
	game = fixture(t,5,true)
	owner = game.players[0]
	var offered: Array = []
	game._jim_gather_choice_override = func(_p,options,_v): offered.assign(options); return 0
	var before = game.players.map(func(p): return p.hp)
	t.check(await game._activate_jushan(owner) == 1 and offered == ["lose"], "I04 M5 same-player-interval mountains offer only populated larger-side loss")
	t.check(game.players.all(func(p): return p.hp == before[p.seat_index]-1), "I04 same-interval Gather loses one HP per player, owner included last")
	await dispose(t,game)
	# Seed an established Kneel status; not a claim about the upstream skill UI.
	game = fixture(t)
	game.players[1].general_name = "布鲁斯·萨维奇"
	game.players[1].kneeling = true
	game.players[1].hp = 2
	t.check(await game._activate_jushan(game.players[0]) == 1 and game.players[1].hp == 2, "I04 Gather does not acquire Yudaxi's special permission to affect a kneeling player")
	var events = game.action_history.entries.filter(func(event): return event.kind == "skill" and "【聚山】" in event.text)
	t.check(events.size() == 1 and events[0].targets == [0], "I04 Gather counts the kneeling player but does not declare them as an effect target")
	await dispose(t,game)
	await rescue_order(t)
	for fault in ["cancel","index","fee","phase","space","reset","restore","reentry"]:
		game = fixture(t)
		owner = game.players[0]
		owner.hp = 5
		hand = owner.hand_size()
		var nested: Array = []
		game._jim_gather_choice_override = func(p,options,_v):
			if fault == "cancel": return -1
			if fault == "index": return options.size()
			if fault == "reentry": nested.append(await p.get_parent()._activate_jushan(p))
			return 0
		game._hand_discard_override = func(snapshot,count,_m):
			var manager: GameManager = snapshot.owner.get_parent()
			if fault == "fee": return []
			if fault == "phase": manager.turn_manager.current_phase = TurnManager.Phase.DRAW
			if fault == "space": manager.turn_manager.rounds.relocate_before(3,1)
			if fault == "reset": manager.reset_game_over_state()
			if fault == "restore": manager._do_sage_save(snapshot.owner) # technical invalidation only
			return snapshot.defaults(count)
		var result = await game._activate_jushan(owner)
		t.check(result == (0 if fault in ["cancel","fee"] else (1 if fault == "reentry" else game.CHOICE_INVALID)) and game._jim_mountain_skill_pending.is_empty(), "I04 Gather distinguishes cancellation, invalidation and reentry: "+fault)
		if fault == "reentry": t.check(nested == [0] and owner.hp == 6 and owner.hand_size() == hand-1, "I04 Gather reentry cannot pay or heal twice")
		elif fault == "restore": t.check(owner.hp == 6 and owner.hand_size() == 4 and not used(game), "I04 Gather cannot commit after the original general and mountains restore")
		else: t.check(owner.hp == 5 and owner.hand_size() == hand and not used(game), "I04 Gather stale or cancelled selection does not pay or affect HP: "+fault)
		await dispose(t,game)
	await lan(t)
	await lan_rescue(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func rescue_order(t):
	var game = fixture(t)
	var owner = game.players[0]
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	owner.hand.append(null)
	var c = game.players[2]
	var d = game.players[3]
	var e = game.players[4]
	c.hp = 1
	d.hp = 1
	e.hp = 3
	e.hand.append(null)
	var observed: Array = []
	d.hp_changed.connect(func(hp):
		if hp == 0: observed.append([c.hp,e.hp,e.hand_size()]))
	game._rescue_choice_override = func(rescuer,dying,options):
		if rescuer == e and options.has(CardData.CardSubType.PEACH):
			observed.append([dying.seat_index,d.hp,e.hp])
			return CardData.CardSubType.PEACH
		return -1
	game._jim_gather_choice_override = func(_p,options,_v): return options.find("lose")
	t.check(await game._activate_jushan(owner) == 1, "I04 Q6 Gather directly affects the larger side across both mountain boundaries")
	t.check(c.hp == 1 and c.is_alive() and d.is_dead() and e.hp == 2 and e.hand_size() == 0, "I04 Q27 E's sole arbitrary card saves C before D loses HP, then E loses HP")
	t.check(observed == [[2,1,3],[1,3,0]], "I04 Q27 first rescue completes before next loss; later targets were not pre-deducted")
	t.check(owner.hand_size() == 0 and game._dying_contexts.is_empty() and not game._game_over, "I04 Gather loss has no killer reward and releases all dying frames")
	await dispose(t,game)

func lan(t):
	var bridge = LanGameBridge.new()
	bridge._enable_mountain_rules_for_tests = true
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 0 else "稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 Gather real human adapter starts")
	var helper = load("res://Test/i04_movement_cases.gd").new()
	bridge.submit(0,bridge.snapshot(0).controls[0].id) # same player interval: loss only
	var game = bridge.game
	game._halt_countdown()
	var hand = game.players[0].hand_size()
	var before = game.players.map(func(p): return p.hp)
	game._open_player_detail(game.players[0])
	var menu_token = helper.find(bridge.snapshot(0),"【聚山】")
	t.check(menu_token != "" and not bridge.submit(1,menu_token) and bridge.submit(0,menu_token), "I04 Gather menu ownership is checked through the real bridge")
	var option_token = helper.find(bridge.snapshot(0),"较多侧")
	t.check(option_token != "" and bridge.snapshot(1).controls.is_empty() and bridge.submit(0,option_token), "I04 Gather option window is private and opens a genuine fee picker")
	var card_token = helper.find(bridge.snapshot(0),"任意牌")
	t.check(card_token != "" and bridge.submit(0,card_token), "I04 Gather chooses original arbitrary hand card through LAN")
	var confirm = helper.find(bridge.snapshot(0),"确认弃牌")
	t.check(confirm != "" and not bridge.submit(1,confirm) and bridge.submit(0,confirm), "I04 Gather fee confirmation rejects another player")
	t.check(game.players[0].hand_size() == hand-1 and used(game) and game.players.all(func(p): return p.hp == before[p.seat_index]-1), "I04 Gather menu/option/card/confirm commits one loss for each original larger-side player")
	t.check(not bridge.submit(0,menu_token) and not bridge.submit(0,option_token) and not bridge.submit(0,confirm), "I04 Gather old menu and payment tokens cannot replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func lan_rescue(t):
	var bridge = LanGameBridge.new()
	bridge._enable_mountain_rules_for_tests = true
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 0 else "稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 Q27 real rescue adapter starts")
	var helper = load("res://Test/i04_movement_cases.gd").new()
	var placement = helper.find(bridge.snapshot(0),"山甲 玩家2→玩家3；山乙 玩家5→玩家1")
	t.check(placement != "" and bridge.submit(0,placement), "I04 Q27 actor selects the real two-versus-three initial placement")
	var game = bridge.game
	game._halt_countdown()
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	game.players[0].hand.append(null)
	game.players[2].hp = 1
	game.players[3].hp = 1
	game.players[4].hp = 3
	game.players[4].hand.append(null)
	game._open_player_detail(game.players[0])
	bridge.submit(0,helper.find(bridge.snapshot(0),"【聚山】"))
	bridge.submit(0,helper.find(bridge.snapshot(0),"较多侧"))
	bridge.submit(0,helper.find(bridge.snapshot(0),"任意牌"))
	t.check(bridge.submit(0,helper.find(bridge.snapshot(0),"确认弃牌")), "I04 Q27 actor pays Gather fee before yielding to the first rescue")
	var rescue = helper.find(bridge.snapshot(4),"使用【桃】")
	t.check(rescue != "" and bridge.snapshot(0).controls.is_empty() and game.players[2].hp == 0 and game.players[3].hp == 1 and game.players[4].hp == 3, "I04 Q27 LAN waits for E to rescue C before deducting D or E")
	t.check(not bridge.submit(0,rescue) and bridge.submit(4,rescue), "I04 Q27 only E controls their one-card rescue response")
	t.check(game.players[2].hp == 1 and game.players[3].is_dead() and game.players[4].hp == 2 and game.players[4].hand_size() == 0, "I04 Q27 real remote-style rescue token saves C, then completes D and E")
	t.check(game._dying_contexts.is_empty() and game._jim_mountain_skill_pending.is_empty() and not bridge.submit(4,rescue), "I04 Q27 completed human rescue releases frames and rejects replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
