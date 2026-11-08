extends RefCounted
const Counter = preload("res://Test/i05_david_nullification_cases.gd")
const Farming = preload("res://Test/i05_david_farming_cases.gd")

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	await active(t)
	await stale(t)
	await dying(t)
	await original_costs(t)
	await peter(t)
	await regions(t)
	await native_empty_hand(t)
	for mode in ["hand", "field", "skip", "timeout", "restore"]: await active_bridge(t, mode)
	for self_save in [false, true]:
		for mode in ["field", "skip", "timeout", "restore"]: await rescue_bridge(t, self_save, mode)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func active(t):
	for cost in ["hand", "field", "skip"]:
		var game = Counter.new().fixture(t, 0)
		var p = game.players[0]
		p.farm_good_fields = 1
		p.hand.append(null)
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		game._farming_peach_override = func(_p, options, valid):
			t.check(options.has("hand") and options.has("field") and valid.call(), "I05b active Peach offers both actual hand and field resources")
			return cost
		await game.play_card(CardData.CardSubType.PEACH)
		t.check(p.hp == (3 if cost == "skip" else 4) and p.hand_size() == (0 if cost == "hand" else 1), "I05b active Peach pays only the chosen hand resource or preserves cancellation")
		t.check(p.farm_good_fields == (0 if cost == "field" else 1) and p.farm_empty_fields == (1 if cost == "field" else 0), "I05b one good field is consumed and exactly one empty field obtained")
		t.check(facts.size() == (0 if cost == "skip" else 1) and game._farming_peach_pending.is_empty(), "I05b active Peach produces one completed fact, never a cost-selection USE")
		if not facts.is_empty():
			t.check(facts[0].is_virtual == (cost == "field") and facts[0].from_hand == (cost == "hand") and facts[0].settlement_completed and game.deck._discard.has(facts[0].card) == (cost == "hand"), "I05b field Peach has virtual provenance; physical hand Peach keeps normal discard")
		await Farming.new().dispose(t, game)
	var game = Counter.new().fixture(t, 0)
	var p = game.players[0]
	p.farm_good_fields = 2
	p.hp = 2
	game._sync_all_ui()
	t.check(not game._play_btn.disabled and game.can_declare_basic(p, CardData.CardSubType.PEACH) and not game.can_declare_basic(p, CardData.CardSubType.WINE), "I05b empty hand with a good field enables only the legal Peach declaration")
	await game.play_card(CardData.CardSubType.WINE)
	t.check(p.farm_good_fields == 2 and p.hp == 2 and game._card_action_serial == 0, "I05b empty-hand field capability never authorizes unrelated free cards")
	await game.play_card(CardData.CardSubType.PEACH)
	await game.play_card(CardData.CardSubType.PEACH)
	t.check(p.hp == 4 and p.farm_good_fields == 0 and p.farm_empty_fields == 2 and p.farm_hand_actions == 0 and game._play_btn.disabled, "I05b repeated field Peaches heal to cap without hand-use farming and then close the empty-hand entry")
	p.farm_good_fields = 1
	await game.play_card(CardData.CardSubType.PEACH)
	t.check(p.farm_good_fields == 1 and p.farm_empty_fields == 2 and game._card_action_serial == 2, "I05b full-health active Peach is illegal and never converts a field")
	await Farming.new().dispose(t, game)

func stale(t):
	for fault in ["field", "hand", "phase", "restore", "gate", "reentry"]:
		var game = Counter.new().fixture(t, 0)
		var p = game.players[0]
		p.farm_good_fields = 1
		p.hand.append(null)
		var nested: Array = []
		game._farming_peach_override = func(_p, _o, _v):
			if fault == "field": p.farm_good_fields = 2
			if fault == "hand": p.hand.append(null)
			if fault == "phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
			if fault == "restore": p.restore_game_start_state()
			if fault == "gate": game._david_rules_enabled = false
			if fault == "reentry": await game.play_card(CardData.CardSubType.PEACH); nested.append(game._card_action_serial)
			return "field"
		await game.play_card(CardData.CardSubType.PEACH)
		t.check(game._card_action_serial == (1 if fault == "reentry" else 0) and p.farm_empty_fields == (1 if fault == "reentry" else 0), "I05b stale active cost cannot charge another resource or reenter: " + fault)
		t.check(game._farming_peach_pending.is_empty() and p.hand_size() == (2 if fault == "hand" else 1) and (fault != "reentry" or nested == [0]), "I05b active cost lease releases safely and leaves all unchosen cards: " + fault)
		await Farming.new().dispose(t, game)

func dying(t):
	for self_save in [false, true]:
		for staff in [false, true]:
			var game = Counter.new().fixture(t, 1 if self_save else 2)
			var victim = game.players[1]
			var farmer = victim if self_save else game.players[2]
			farmer.farm_good_fields = 2
			victim.hp = 1
			if staff: farmer.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.HEAL_STAFF))
			var facts: Array = []
			game.card_action_committed.connect(func(a): facts.append(a))
			game._rescue_choice_override = func(r, d, options):
				if r == farmer:
					t.check(d == victim and options.has(game.RESCUE_FIELD_PEACH), "I05b normal rescue order offers good-field Peach, including DYING self")
					return game.RESCUE_FIELD_PEACH
				return -1
			var result = await game._deal_damage_result(game.players[0], victim, 3 if staff else 2, EffectChain.DamageType.PHYSICAL)
			t.check(not result.invalidated and victim.hp == 1 and victim.is_alive() and farmer.farm_good_fields == 0 and farmer.farm_empty_fields == 2, "I05b negative-HP rescue repeats good-field Peaches in original order until saved")
			t.check(facts.size() == 2 and facts.all(func(a): return a.actor_body == farmer and a.sub_type == CardData.CardSubType.PEACH and a.is_virtual and not a.from_hand and a.settlement_completed), "I05b actual rescue records exactly two virtual Peaches with correct source and completion")
			t.check(game.deck._discard.is_empty() and farmer.hand_size() == 0 and farmer.farm_hand_actions == 0 and game._dying_contexts.is_empty(), "I05b rescue never fabricates a hand/discard or loops hand-use farming")
			if staff:
				t.check(farmer.heal_staff_peach_used, "I05b good-field Peach uses the normal first-Peach staff bonus once")
				game._reset_turn_flags()
				farmer.farm_good_fields = 1
				await game._deal_damage_result(game.players[0], victim, 1, EffectChain.DamageType.PHYSICAL)
				t.check(victim.hp == 2 and farmer.farm_good_fields == 0 and farmer.heal_staff_peach_used, "I05b staff turn-reset boundary restores the next field Peach bonus")
			await Farming.new().dispose(t, game)

func original_costs(t):
	var game = Counter.new().fixture(t, 0)
	var p = game.players[0]
	p.farm_good_fields = 1
	# Explicit concrete-card boundary; ordinary draws remain arbitrary cards.
	var original = CardBase.create(CardData.CardSubType.PEACH)
	p.determined_cards.append(original)
	game._pending_determined_card = original
	await game.play_card(CardData.CardSubType.PEACH)
	t.check(p.hp == 4 and p.determined_cards.is_empty() and game.deck._discard.count(original) == 1, "I05b explicitly chosen concrete Peach still pays that original instance")
	t.check(p.farm_good_fields == 1 and p.farm_empty_fields == 0 and p.farm_hand_actions == 1, "I05b explicit hand payment never silently substitutes a good field")
	await Farming.new().dispose(t, game)
	for field_cost in [false, true]:
		game = Counter.new().fixture(t, 2)
		p = game.players[2]
		p.farm_good_fields = 1
		p.hand.append(null)
		var victim = game.players[1]
		victim.hp = 0
		var facts: Array = []
		game.card_action_committed.connect(func(a): facts.append(a))
		var options = game._rescue_options(p, victim)
		t.check(options.has(CardData.CardSubType.PEACH) and options.has(game.RESCUE_FIELD_PEACH), "I05b rescue offers distinct legal physical and field Peach costs")
		t.check(game._use_rescue_card(p, victim, game.RESCUE_FIELD_PEACH if field_cost else CardData.CardSubType.PEACH) and victim.hp == 1, "I05b shared rescue payment accepts the selected cost, not an automatic substitution")
		t.check(p.hand_size() == (1 if field_cost else 0) and p.farm_good_fields == (0 if field_cost else 1) and p.farm_empty_fields == (1 if field_cost else 0), "I05b rescue only changes the selected resource and its own field conversion")
		t.check(facts.size() == 1 and facts[0].is_virtual == field_cost and facts[0].from_hand != field_cost and facts[0].settlement_completed, "I05b rescue provenance/completion distinguishes physical and field Peaches")
		await Farming.new().dispose(t, game)

func peter(t):
	for self_save in [false, true]:
		var game = Counter.new().fixture(t, 1 if self_save else 2)
		var source = game.players[0]
		var victim = game.players[1]
		var farmer = victim if self_save else game.players[2]
		source.general_name = load("res://Test/i05_peter_card_cases.gd").PETER
		victim.hp = 1
		farmer.farm_good_fields = 1
		game._peter_peach_override = func(_p, _t, _v): return 1
		game._peter_exclusion_override = func(_p, _c, _k, _v): return []
		game._rescue_choice_override = func(r, _d, options): return game.RESCUE_FIELD_PEACH if r == farmer and options.has(game.RESCUE_FIELD_PEACH) else -1
		await game._deal_damage_result(source, victim, 1, EffectChain.DamageType.PHYSICAL)
		t.check((victim.is_alive() if self_save else victim.is_dead()) and farmer.farm_good_fields == (0 if self_save else 1), "I05b Peter bans third-party field Peach but preserves victim self-rescue")
		await Farming.new().dispose(t, game)

func regions(t):
	var game = Counter.new().fixture(t, 1)
	var farmer = game.players[1]
	farmer.farm_good_fields = 1
	game.players[4].general_name = "吉姆·芒顿"
	game._spawn_mountain_at(game.players[4], 0, 1)
	game._spawn_mountain_at(game.players[4], 3, 4)
	game.players[4].hp = 0 # Eligibility boundary, not an illegal cross-region damage claim.
	t.check(not game._rescue_options(farmer, game.players[4]).has(game.RESCUE_FIELD_PEACH) and not game._use_rescue_card(farmer, game.players[4], game.RESCUE_FIELD_PEACH) and farmer.farm_good_fields == 1, "I05b field resource never bypasses mountain rescue restrictions")
	await Farming.new().dispose(t, game)
	game = Counter.new().fixture(t, 2)
	farmer = game.players[2]
	farmer.farm_good_fields = 1
	var dragon = load("res://Test/i04_stealth_sacrifice_cases.gd").new().make_dragon(game)
	dragon.hp = 0
	t.check(not game._rescue_options(farmer, dragon).has(game.RESCUE_FIELD_PEACH), "I05b unseen dragon cannot receive a field Peach")
	var targets: Array[Player] = [farmer]
	game.fire_dragon_state.record_use(game.unit_registry.id_for(dragon), 1, targets)
	t.check(game._use_rescue_card(farmer, dragon, game.RESCUE_FIELD_PEACH) and dragon.hp == 1, "I05b visible intelligent unit receives the same legal field Peach rescue")
	await Farming.new().dispose(t, game)

func find(b, seat, prefix):
	for c in b.snapshot(seat).controls:
		if c.text.begins_with(prefix) and not c.disabled: return c.id
	return ""

func bridge_fixture(t, owner := 0):
	var b = LanGameBridge.new()
	t.root.add_child(b)
	var roster: Array[Dictionary] = []
	for n in 3: roster.append({"name": "P%d" % n, "general": "稻草人"})
	t.check(b.start(roster, GameModes.FREE_FOR_ALL, AiActionPacer.Speed.FAST), "I05b Peach Bridge opens ordinary PLAY before explicit private field fixture")
	b.game._david_rules_enabled = true
	b.game._halt_countdown()
	for p in b.game.players: p.hand.clear(); p.determined_cards.clear()
	var farmer = b.game.players[owner]
	farmer.general_name = "大卫·法米尔"
	farmer.max_hp = 4
	farmer.hp = 2
	farmer.capture_game_start_state()
	farmer.farm_good_fields = 1
	b.game._sync_all_ui()
	return b

func dispose_bridge(t, b):
	b.game._game_over = true
	b.queue_free()
	for i in 4: await t.process_frame

func native_empty_hand(t):
	var b = bridge_fixture(t)
	for text in ["出牌", "基本牌", "桃"]:
		var action = find(b, 0, text)
		t.check(not action.is_empty() and b.submit(0, action), "I05b zero-hand native selector reaches legal field Peach: " + text)
		for i in 2: await t.process_frame
	await t.create_timer(0.15).timeout # Let the selector's existing 0.1s close tween finish.
	for i in 4: await t.process_frame
	var p = b.game.players[0]
	t.check(p.hp == 3 and p.farm_good_fields == 0 and p.farm_empty_fields == 1 and p.hand_size() == 0, "I05b actual empty-hand play button/selector performs one field Peach")
	await dispose_bridge(t, b)

func active_bridge(t, mode):
	var b = bridge_fixture(t)
	var game = b.game
	var p = game.players[0]
	p.hand.append(null)
	var done: Array = []
	var play = func(): await game.play_card(CardData.CardSubType.PEACH); done.append(true)
	play.call_deferred()
	for i in 3: await t.process_frame
	var field = find(b, 0, "好田当桃")
	t.check(not field.is_empty() and not b.submit(1, field), "I05b mixed-cost Peach menu is owned only by current actor")
	if mode in ["hand", "field", "skip"]:
		var chosen = find(b, 0, "使用手牌桃" if mode == "hand" else ("好田当桃" if mode == "field" else "取消"))
		t.check(not chosen.is_empty() and b.submit(0, chosen), "I05b actual payment menu accepts hand/field or cancellation")
	elif mode == "timeout": game._countdown_on_timeout.call()
	else: p.restore_game_start_state()
	for i in 4: await t.process_frame
	t.check(done.size() == 1 and p.hp == (3 if mode in ["hand", "field"] else (4 if mode == "restore" else 2)) and p.hand_size() == (0 if mode == "hand" else 1), "I05b mixed UI confirmation/cancel/timeout/restore pays exactly the selected original resource")
	t.check(p.farm_empty_fields == (1 if mode == "field" else 0) and p.farm_good_fields == (0 if mode in ["field", "restore"] else 1) and not b.submit(0, field) and game._farming_peach_pending.is_empty(), "I05b old active-cost tokens and leases cannot charge a later field")
	await dispose_bridge(t, b)

func rescue_bridge(t, self_save, mode):
	var owner = 0 if self_save else 1
	var b = bridge_fixture(t, owner)
	var game = b.game
	var farmer = game.players[owner]
	var victim = farmer if self_save else game.players[2]
	victim.hp = 1
	game._sacrifice_actor_override = func(_p, _t, _n): return false
	var done: Array = []
	var damage = func(): done.append(await game._deal_damage_result(game.players[1 if self_save else 0], victim, 1, EffectChain.DamageType.PHYSICAL))
	damage.call_deferred()
	for i in 3: await t.process_frame
	var field = find(b, owner, "好田当桃")
	t.check(not field.is_empty() and b.input_owner() == owner and not b.submit(1 - owner, field), "I05b actual DYING rescue presents field payment only to the proper responder")
	if mode == "field": t.check(b.submit(owner, field), "I05b actual self/other responder uses field through ordinary rescue UI")
	elif mode == "skip": t.check(b.submit(owner, find(b, owner, "放弃")), "I05b ordinary rescue refusal preserves good field")
	elif mode == "timeout": game._countdown_on_timeout.call()
	else: farmer.restore_game_start_state()
	for i in 5: await t.process_frame
	t.check(done.size() == 1 and (victim.hp == 1 if mode == "field" else (done[0].invalidated if mode == "restore" else victim.is_dead())), "I05b original damage resumes after field rescue/refusal or records technical expiry")
	t.check(farmer.farm_good_fields == (0 if mode in ["field", "restore"] else 1) and farmer.farm_empty_fields == (1 if mode == "field" else 0) and not b.submit(owner, field) and game._rescue_choice_pending.is_empty(), "I05b rescue payment/timeout/restore never reuses an old field token")
	await dispose_bridge(t, b)
