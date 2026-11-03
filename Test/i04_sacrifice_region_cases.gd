extends RefCounted

func configure(game, walls := 2):
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game.lan_enabled = true
	game.turn_manager.current_player_idx = 1 # Native acting boundary only.
	game._duel_respond_override = func(): return false
	if walls > 0: game._spawn_mountain_at(game.players[5],0,1)
	if walls > 1: game._spawn_mountain_at(game.players[5],4,5)
	for seat in [0,2,4,5]: game.players[seat].hand.append(null)

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for mode in ["first","decline","none","concrete","one_wall","no_walls","sourceless","fire","thunder","virtual"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
		configure(game,1 if mode == "one_wall" else (0 if mode == "no_walls" else 2))
		var resource: CardBase
		if mode == "concrete":
			game.players[4].hand.clear()
			resource = CardBase.create(CardData.CardSubType.SACRIFICE)
			game.players[4].determined_cards.append(resource)
		if mode == "virtual":
			game.players[4].general_name = "安普提·斯丢皮得"
			game.players[4].hand.clear()
			game.players[4].hp = 3
			game._yes_ah_override = func(): return "skill"
			game._rps_override = func(p): return game.RPS_ROCK if p == game.players[4] else game.RPS_PAPER
		var offered: Array = []
		game._sacrifice_actor_override = func(p,target,_amount):
			if target != game.players[3]: return false # No recursive protection of the substitute.
			offered.append(p.seat_index)
			if mode == "none": return p.seat_index in [0,5]
			if mode in ["decline","one_wall","no_walls"] and p.seat_index == 4: return false
			return p.seat_index in [0,2,4,5]
		var actions: Array = []
		game.card_action_committed.connect(func(event): actions.append(event))
		var damage_only = mode in ["sourceless","fire","thunder"]
		if damage_only:
			var element = EffectChain.DamageType.FIRE if mode == "fire" else (EffectChain.DamageType.THUNDER if mode == "thunder" else EffectChain.DamageType.PHYSICAL)
			await game._deal_damage_result(null if mode == "sourceless" else game.players[1],game.players[3],1,element)
		else:
			game.players[1].hand.append(null)
			await game.execute_card_on_target(game.players[3],CardData.CardSubType.DUEL)
		var winner = 2 if mode == "decline" else (5 if mode in ["one_wall","no_walls"] else 4)
		var expected: Array = [4,1,2] if mode in ["decline","none"] else ([4,5] if mode in ["one_wall","no_walls"] else [4])
		t.check(offered == expected, "I04 Q48 exact downstream of damaged D, E first; region filtering or legal one/no-wall traversal: "+mode)
		t.check(game.players[3].hp == (4 if mode == "none" else 5), "I04 original D receives damage only if no legal volunteer accepts")
		if mode != "none": t.check(game.players[winner].hp == (1 if mode == "virtual" else 4), "I04 independent transferred damage applies to selected volunteer once")
		if mode not in ["one_wall","no_walls"]: t.check(game.players[0].hand_size() == 1 and game.players[5].hand_size() == 1, "I04 willing opposite-region volunteers are neither offered nor charged")
		var counters = actions.filter(func(e): return e.sub_type == CardData.CardSubType.SACRIFICE)
		t.check(counters.size() == (0 if mode == "none" else 1) and actions.all(func(e): return e.settlement_completed) and game._pending_card_actions.is_empty(), "I04 actual original and Sacrifice actions complete once, without forbidden cross-region USE")
		if resource != null: t.check(counters[0].card == resource and game.deck._discard.count(resource) == 1, "I04 concrete Sacrifice keeps its original instance and discards once")
		if mode == "virtual": t.check(counters[0].is_virtual and not game.deck._discard.has(counters[0].card), "I04 surviving virtual cost pays HP, not a fabricated physical discard")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await lan(t)
	await stale(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func bridge_fixture(t):
	var bridge = LanGameBridge.new()
	bridge._enable_mountain_rules_for_tests = true
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 6: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 5 else "稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 Q48 six-human adapter starts")
	# Same explicit two-wall/initial-hand boundary; native current actor is NOT changed.
	var game = bridge.game
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	game._spawn_mountain_at(game.players[5],0,1)
	game._spawn_mountain_at(game.players[5],4,5)
	for seat in [0,2,4,5]: game.players[seat].hand.append(null)
	game._sacrifice_actor_override = Callable()
	game._sacrifice_override = Callable()
	return bridge

func lan(t):
	var helper = load("res://Test/i04_aoe_region_cases.gd").new()
	var bridge = bridge_fixture(t)
	var game = bridge.game
	helper.click(t,bridge,0,"结束出牌")
	for i in 3: await t.process_frame
	helper.click(t,bridge,1,"出牌")
	helper.click(t,bridge,1,"锦囊牌")
	helper.click(t,bridge,1,"普通锦囊")
	helper.click(t,bridge,1,"决斗")
	await t.create_timer(0.15).timeout
	game._target_confirm_override = func(): return 1
	var target: String = bridge.snapshot(1).targets.get("3","")
	t.check(target != "" and bridge.submit(1,target), "I04 Q48 actual B Duel menu selects D and pays original card")
	for i in 3: await t.process_frame
	var find = load("res://Test/i04_movement_cases.gd").new()
	var token = find.find(bridge.snapshot(4),"打出【舍己为人】")
	t.check(token != "" and bridge.input_owner() == 4 and bridge.snapshot(2).controls.is_empty() and bridge.snapshot(0).controls.is_empty() and bridge.snapshot(5).controls.is_empty(), "I04 Q48 actual E window precedes willing C; opposite A/F have no controls")
	t.check(not bridge.submit(2,token) and bridge.submit(4,token), "I04 only E can pay its actual Sacrifice token")
	# Transferred E damage starts at E's downstream: B still has one drawn
	# card after using Duel, so B must decline before C gets its own window.
	for i in 3: await t.process_frame
	var b_decline = find.find(bridge.snapshot(1),"放弃")
	t.check(b_decline != "" and bridge.submit(1,b_decline), "I04 transferred-damage response starts after E, reaching B before C")
	for i in 3: await t.process_frame
	var decline = find.find(bridge.snapshot(2),"放弃")
	t.check(decline != "" and bridge.submit(2,decline), "I04 C may decline the separate transferred-damage window")
	for i in 3: await t.process_frame
	t.check(game.players[3].hp == 5 and game.players[4].hp == 4 and game.players[4].hand_size() == 0 and game.players[2].hand_size() == 1 and game.players[0].hand_size() == 1 and game.players[5].hand_size() == 1, "I04 real E payment transfers one Duel damage, keeps C and opposite-side resources")
	t.check(bridge.input_owner() == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game._pending_card_actions.is_empty() and not bridge.submit(4,token), "I04 completed transferred damage returns B PLAY and rejects old E token")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame

func stale(t):
	for mode in ["phase","region"]:
		var bridge = bridge_fixture(t)
		var game = bridge.game
		var result: Array = []
		var drive = func(): result.append(await game._deal_damage_result(game.players[1],game.players[3],1,EffectChain.DamageType.PHYSICAL))
		drive.call()
		for i in 3: await t.process_frame
		var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(4),"打出【舍己为人】")
		t.check(token != "", "I04 real downstream E response exists before explicit invalidation")
		# Engineering invalidation, not a claim of legal movement inside a response.
		if mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.END
		else: game.turn_manager.rounds.relocate_before(4,0)
		for i in 3: await t.process_frame
		t.check(result.size() == 1 and result[0].invalidated and not bridge.submit(4,token), "I04 changed context or responder region invalidates old Sacrifice token")
		t.check(game.players[3].hp == 5 and game.players[4].hp == 5 and game.players[4].hand_size() == 1 and game._pending_card_actions.is_empty(), "I04 invalidated protection charges nobody and applies no stale damage")
		game._game_over = true
		bridge.queue_free()
		await t.process_frame
