extends RefCounted
const Farming = preload("res://Test/i05_david_farming_cases.gd")

func fixture(t, seat := 1):
	var game = Farming.new().fixture(t)
	for p in game.players:
		p.general_name = "稻草人"
		p.hand.clear()
		p.determined_cards.clear()
	var farmer = game.players[seat]
	farmer.general_name = "大卫·法米尔"
	farmer.max_hp = 4
	farmer.hp = 3
	farmer.capture_game_start_state()
	return game

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	await immediate_counter(t)
	await parity(t)
	await payments(t)
	await stale(t)
	await permissions(t)
	await staff_and_ai(t)
	for seat in [0, 1]:
		for mode in ["empty", "cancel", "timeout", "restore"]: await bridge_case(t, seat, mode)
	await bridge_case(t, 1, "good")
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func immediate_counter(t):
	var game = fixture(t, 0)
	var p = game.players[0]
	p.hand.assign([null, null])
	game.players[2].hand.append(null)
	game._nullify_override = func(): return game._input_seat == 2 and game.players[2].hand_size() > 0
	var facts: Array = []
	game.card_action_committed.connect(func(a): facts.append(a))
	game._farming_nullification_override = func(actor, options, valid):
		t.check(actor == p and options.has("field_empty") and p.farm_empty_fields == 1 and valid.call() and not facts[1].settlement_completed, "I05b Q1 second-hand Duel's new field can pay its actual unfinished counter chain")
		return "field_empty"
	await game.play_card(CardData.CardSubType.WINE)
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.DUEL)
	t.check(p.hand_size() == 0 and p.farm_empty_fields == 0 and p.farm_hand_actions == 2 and game.players[1].hp == 4, "I05b Q1 new field actually counters physical Nullification and restores original Duel")
	t.check(facts.size() == 4 and facts[3].is_virtual and not facts[3].from_hand and facts.all(func(a): return a.settlement_completed), "I05b Q1 Wine/Duel/physical counter/field counter are exactly four completed facts")
	t.check(game.deck._discard.size() == 3 and not game.deck._discard.has(facts[3].card) and game._pending_card_actions.is_empty(), "I05b no physical field-card discard or extra farming loop")
	await Farming.new().dispose(t, game)

func parity(t):
	for good in [false, true]:
		for anti in [false, true]:
			var game = fixture(t)
			var p = game.players[1]
			p.farm_empty_fields = 0 if good else 1
			p.farm_good_fields = 1 if good else 0
			game.players[0].hand.append(null)
			if anti: game.players[2].hand.append(null)
			var observations: Array = []
			game._nullify_override = func():
				if game._input_seat == 2: observations.append(p.hp)
				return anti and game._input_seat == 2 and game.players[2].hand_size() > 0
			game._farming_nullification_override = func(_p, _o, _v): return "field_good" if good else "field_empty"
			var facts: Array = []
			game.card_action_committed.connect(func(a): facts.append(a))
			await game.execute_card_on_target(p, CardData.CardSubType.DUEL)
			t.check(p.hp == 3 + (1 if good else 0) - (1 if anti else 0) and p.farm_empty_fields == 0 and p.farm_good_fields == 0, "I05b field counter preserves odd/even Nullification and committed good-field recovery")
			t.check(not observations.is_empty() and observations[0] == (4 if good else 3), "I05b Q4 next counter observes immediate recovery, never chain-end delayed healing")
			t.check(facts.size() == (3 if anti else 2) and facts[1].is_virtual and not facts[1].from_hand and facts.all(func(a): return a.settlement_completed), "I05b field and physical counters share normal completion pipeline once")
			t.check(not game.deck._discard.has(facts[1].card) and p.farm_hand_actions == 0 and game._pending_card_actions.is_empty(), "I05b virtual counter pays only one field and never counts as a hand card")
			await Farming.new().dispose(t, game)

func payments(t):
	for choice in ["card", "field_empty", "field_good", "skip"]:
		var game = fixture(t)
		var p = game.players[1]
		p.farm_empty_fields = 1
		p.farm_good_fields = 1
		p.hand.append(null)
		var picked: Array = []
		game._farming_nullification_override = func(_p, options, valid):
			picked.append(true)
			if picked.size() == 1:
				t.check(options.has("card") and options.has("field_empty") and options.has("field_good") and valid.call(), "I05b actual payment chooser permits hand, empty field and good field independently")
			return choice if picked.size() == 1 else "skip"
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		var result = await game._ask_nullification_chain_result("原效果", Callable(), game.players[0], game.players[2])
		t.check(result == (game.NullificationOutcome.PASSED if choice == "skip" else game.NullificationOutcome.NULLIFIED), "I05b chosen cost preserves chain outcome; declining never pays")
		t.check(p.hand_size() == (0 if choice == "card" else 1) and p.farm_empty_fields == (0 if choice == "field_empty" else 1) and p.farm_good_fields == (0 if choice == "field_good" else 1), "I05b only chosen original resource is consumed")
		t.check(p.hp == (4 if choice == "field_good" else 3) and facts.size() == (0 if choice == "skip" else 1), "I05b only good field heals; all costs produce at most one USE")
		if not facts.is_empty():
			t.check(facts[0].is_virtual == (choice != "card") and facts[0].from_hand == (choice == "card") and facts[0].settlement_completed, "I05b physical/virtual origin flags remain accurate through chain completion")
		await Farming.new().dispose(t, game)
	var game = fixture(t)
	var p = game.players[1]
	p.hp = 4
	p.farm_good_fields = 1
	game._farming_nullification_override = func(_p, _o, _v): return "field_good"
	await game._ask_nullification_chain_result("原效果", Callable(), game.players[0], game.players[2])
	t.check(p.hp == 4 and p.farm_good_fields == 0 and "回复0体力" in game.action_history.visible_text(), "I05b full-health good field is payable but neither overheals nor logs invented recovery")
	await Farming.new().dispose(t, game)

func stale(t):
	for fault in ["empty", "good", "restore", "role", "gate", "phase", "excluded", "hand", "invalid"]:
		var game = fixture(t)
		var p = game.players[1]
		p.farm_good_fields = 1
		var scope = {"origin": game.players[0], "region": p, "peter": {"excluded": []}}
		game._farming_nullification_override = func(_p, _o, _v):
			if fault == "empty": p.farm_empty_fields = 1
			if fault == "good": p.farm_good_fields = 2
			if fault == "restore": p.restore_game_start_state()
			if fault == "role": p.general_name = "稻草人"
			if fault == "gate": game._david_rules_enabled = false
			if fault == "phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
			if fault == "excluded": scope.peter.excluded.append(p)
			if fault == "hand": p.hand.append(null)
			return "invalid-cost" if fault == "invalid" else "field_good"
		var reply = await game._ask_nullification_round_result("原效果", Callable(), scope)
		t.check(reply.outcome == (game.NullificationOutcome.PASSED if fault == "hand" else game.NullificationOutcome.INVALIDATED), "I05b stale field response cannot be reinterpreted as payment: " + fault)
		t.check(p.farm_good_fields == (0 if fault == "restore" else (2 if fault == "good" else 1)) and p.hp == (4 if fault == "restore" else 3) and game._card_action_serial == 0, "I05b rejected choice neither spends later fields, heals, nor fabricates USE: " + fault)
		await Farming.new().dispose(t, game)

func permissions(t):
	for excluded in [false, true]:
		var game = fixture(t)
		var p = game.players[1]
		p.farm_empty_fields = 1
		var asks: Array = []
		game._farming_nullification_override = func(_p, _o, _v): asks.append(true); return "field_empty"
		var targets: Array[Player] = [game.players[2]]
		var scope = game._new_peter_trick_scope(game.players[0], targets)
		scope.asked = true
		if excluded: scope.excluded = [p]
		var result = await game._ask_nullification_chain_result("原效果", Callable(), game.players[0], game.players[2], scope)
		t.check(asks.size() == (0 if excluded else 1) and p.farm_empty_fields == (1 if excluded else 0) and result == (game.NullificationOutcome.PASSED if excluded else game.NullificationOutcome.NULLIFIED), "I05b Peter's original-card ban also forbids field-funded counters")
		await Farming.new().dispose(t, game)
	var game = fixture(t)
	game.players[4].general_name = "吉姆·芒顿"
	game._spawn_mountain_at(game.players[4], 0, 1)
	game._spawn_mountain_at(game.players[4], 3, 4)
	var p = game.players[1]
	p.farm_empty_fields = 1
	var asks: Array = []
	game._farming_nullification_override = func(_p, _o, _v): asks.append(true); return "field_empty"
	await game._ask_nullification_chain_result("隔山效果", Callable(), game.players[0], game.players[4])
	t.check(asks.is_empty() and p.farm_empty_fields == 1 and game._card_action_serial == 0, "I05b fields never bypass mountain-region response restrictions")
	game._david_rules_enabled = false
	t.check(game._farming_nullification_choices(p).is_empty(), "I05b metadata-only private gate cannot grant free counter capability")
	await Farming.new().dispose(t, game)

func staff_and_ai(t):
	var game = fixture(t)
	var p = game.players[1]
	p.hp = 2
	p.farm_good_fields = 1
	p.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.HEAL_STAFF))
	game._farming_nullification_override = func(_p, _o, _v): return "field_good"
	await game._ask_nullification_chain_result("原效果", Callable(), game.players[0], game.players[2])
	t.check(p.hp == 3 and not p.heal_staff_peach_used, "I05b good-field recovery is not Peach: staff never boosts or consumes first-Peach bonus")
	await Farming.new().dispose(t, game)
	for expired in [false, true]:
		game = fixture(t)
		game.lan_enabled = false
		p = game.players[1]
		p.farm_empty_fields = 1
		game._ai_response_override = func(_view, kind, options):
			if kind == "nullification" and options.has(CardData.CardSubType.NULLIFICATION):
				if expired: p.farm_empty_fields = 0 # Defensive state expiry at the awaited choice.
				return CardData.CardSubType.NULLIFICATION
			return -1
		var reply = await game._ask_nullification_round_result("AI响应")
		t.check(reply.outcome == (game.NullificationOutcome.PASSED if expired else game.NullificationOutcome.NULLIFIED) and p.farm_empty_fields == 0 and p.hand_size() == 0, "I05b AI field response is legal without a hand; expired offer cannot index empty choices or pay")
		if reply.get("card_action") != null:
			t.check(reply.card_action.is_virtual and not reply.card_action.from_hand, "I05b AI uses the same single virtual field payment")
			game._abandon_card_actions([reply.card_action]) # Single round, not a pretend completed chain.
		await Farming.new().dispose(t, game)

func find(bridge, seat, prefix):
	for c in bridge.snapshot(seat).controls:
		if c.text.begins_with(prefix) and not c.disabled: return c.id
	return ""

func bridge_case(t, seat, mode):
	var bridge = LanGameBridge.new()
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for n in 3: roster.append({"name": "P%d" % n, "general": "稻草人"})
	t.check(bridge.start(roster, GameModes.FREE_FOR_ALL, AiActionPacer.Speed.FAST), "I05b counter Bridge starts in ordinary playable phase")
	var game = bridge.game
	game._halt_countdown()
	game._david_rules_enabled = true
	game._nullify_override = Callable()
	game._duel_respond_override = func(): return false
	game._sacrifice_actor_override = func(_p, _t, _n): return false
	for p in game.players: p.hand.clear(); p.determined_cards.clear()
	var farmer = game.players[seat]
	farmer.general_name = "大卫·法米尔"
	farmer.capture_game_start_state()
	if seat == 1:
		farmer.farm_empty_fields = 0 if mode == "good" else 1
		farmer.farm_good_fields = 1 if mode == "good" else 0
		farmer.hp = 3
	game.players[0].hand.assign([null, null] if seat == 0 else [null])
	if seat == 0:
		await game.play_card(CardData.CardSubType.WINE)
		game.players[1].hand.append(null)
	var done: Array = []
	var play = func():
		await game.execute_card_on_target(game.players[2], CardData.CardSubType.DUEL)
		done.append(true)
	play.call_deferred()
	for i in 3: await t.process_frame
	if seat == 0:
		var physical = find(bridge, 1, "打出【无懈可击】")
		t.check(not physical.is_empty() and bridge.submit(1, physical), "I05b Q1 actual other seat pays physical counter before new-field response")
		for i in 3: await t.process_frame
	var field = find(bridge, seat, "好田当无懈" if mode == "good" else "空田当无懈")
	t.check(not field.is_empty() and bridge.input_owner() == seat and not bridge.submit(1 - seat, field), "I05b field counter menu belongs only to its actual responder")
	if mode in ["empty", "good"]:
		t.check(bridge.submit(seat, field) and not bridge.submit(seat, field), "I05b opaque field command pays at most once")
	elif mode == "cancel":
		var skip = find(bridge, seat, "取消")
		t.check(not skip.is_empty() and bridge.submit(seat, skip), "I05b real responder can decline without spending field")
	elif mode == "timeout":
		game._countdown_on_timeout.call() # Real timeout callback, not a natural full-reserve wait.
	else: farmer.restore_game_start_state()
	for i in 5: await t.process_frame
	var paid = mode in ["empty", "good"]
	var expected_hp = (4 if paid else 5) if seat == 0 else (5 if paid or mode == "restore" else 4)
	t.check(done.size() == 1 and game.players[2].hp == expected_hp and game._pending_card_actions.is_empty(), "I05b Bridge finishes original effect with correct parity or technical invalidation")
	t.check(farmer.farm_empty_fields == (0 if paid or mode == "restore" else 1) and farmer.farm_good_fields == 0 and (mode != "good" or farmer.hp == 4), "I05b Bridge pays exact field; good field heals immediately; cancel/timeout preserve it")
	t.check(not bridge.submit(seat, field) and bridge.input_owner() == 0, "I05b old counter token never survives return to source PLAY")
	game._game_over = true
	bridge.queue_free()
	for i in 3: await t.process_frame
