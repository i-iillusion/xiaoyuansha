extends RefCounted

func fixture(t):
	var game = load("res://Test/i05_simba_good_deed_flow_cases.gd").new().fixture(t)
	game.players[0].simba_emergency_enabled = true
	game._simba_deed_choice_override = func(_p, _c, _r, _v): return -1
	game._simba_emergency_choice_override = func(_p, _t, _v): return 0
	return game

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await instances(t)
	await rescue_order(t)
	await self_rescue(t)
	await bridge(t)
	await invalid(t)
	await interactions(t)
	await nested_invalid(t)
	await negative_recipient(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func instances(t):
	for element in [EffectChain.DamageType.PHYSICAL, EffectChain.DamageType.FIRE, EffectChain.DamageType.THUNDER]:
		for amount in [1, 3]:
			var game = fixture(t)
			var owner = game.players[0]
			var target = game.players[1]
			var seen: Array = []
			game._simba_emergency_choice_override = func(p, q, valid):
				seen.append([p, q, valid.call()])
				return 0
			var chain = game._new_damage_chain(game.players[2], target, null, amount, element)
			chain.skip_targeting = true; chain.skip_response = true
			await chain.start()
			await game._finish_damage_chain(chain)
			t.check(chain.damage.applied_amount == amount and seen.size() == 1 and seen[0] == [owner, target, true], "I05d Emergency offers once per real damage instance, not each point or element")
			t.check(owner.hp == 4 and target.hp == 6 - amount and target.good_deed_marks == 1, "I05d Emergency costs one and grants one extra HP plus mark")
			t.check(await game._try_simba_emergency(target, chain) == 0 and owner.hp == 4 and target.good_deed_marks == 1, "I05d repeated damage callback cannot offer or pay Emergency twice")
			await dispose(t, game)
	var game = fixture(t)
	var owner = game.players[0]
	var target = game.players[1]
	var offers: Array = []
	game._simba_emergency_choice_override = func(_p, _t, _v): offers.append(true); return 0
	owner.simba_emergency_enabled = false
	await game._deal_damage_result(game.players[2], target, 1, EffectChain.DamageType.PHYSICAL)
	t.check(offers.is_empty() and target.good_deed_marks == 0 and owner.hp == 5, "I05d Emergency private capability disabled leaves original damage unchanged")
	owner.simba_emergency_enabled = true
	owner.hp -= 1
	await game._resolve_dying(owner, null, "good_deed_cost")
	t.check(offers.is_empty(), "I05d HP cost is not a damage instance and cannot trigger Emergency")
	await dispose(t, game)

func rescue_order(t):
	for mode in ["healthy", "cost_dead", "cost_peach", "cost_sage"]:
		var game = fixture(t)
		var owner = game.players[0]
		var target = game.players[1]
		target.hp = 1
		if mode != "healthy": owner.hp = 1
		if mode == "cost_peach": owner.hand.append(null)
		if mode == "cost_sage":
			owner.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			owner.sage_activated = true
			game._sage_save_override = func(): return true
		var rescue_seen: Array = []
		game._rescue_choice_override = func(p, q, options):
			rescue_seen.append([q, target.hp, target.good_deed_marks])
			return CardData.CardSubType.PEACH if mode == "cost_peach" and p == owner and q == owner and options.has(CardData.CardSubType.PEACH) else -1
		var result = await game._deal_damage_result(game.players[2], target, 1, EffectChain.DamageType.PHYSICAL)
		t.check(not result.invalidated and target.hp == 1 and target.good_deed_marks == 1 and target.is_alive(), "I05d Q4 Emergency rescues actual victim before ordinary Peach: " + mode)
		t.check(rescue_seen.all(func(row): return row[0] != target and row[1] == 1 and row[2] == 1), "I05d Q3b recipient commit precedes any cost payer rescue: " + mode)
		if mode == "cost_dead": t.check(owner.is_dead() and not game._game_over, "I05d lethal Emergency cost does not undo recipient effect")
		elif mode == "cost_peach": t.check(owner.is_alive() and owner.hp == 1 and owner.hand.is_empty(), "I05d Emergency cost uses actual normal Peach self rescue")
		elif mode == "cost_sage": t.check(owner.is_alive() and owner.hp == owner.max_hp and owner.hand_size() == 4, "I05d Emergency cost can complete actual Sage restoration")
		else: t.check(owner.hp == 4 and rescue_seen.is_empty(), "I05d fully rescued victim never spends a Peach")
		await dispose(t, game)

func self_rescue(t):
	var game = fixture(t)
	var owner = game.players[0]
	owner.hp = 1; owner.hand.assign([null, null])
	var offers: Array = []
	game._simba_emergency_choice_override = func(p, q, _valid): offers.append([p, q]); return 0
	game._rescue_choice_override = func(p, q, options): return CardData.CardSubType.PEACH if p == owner and q == owner and options.has(CardData.CardSubType.PEACH) else -1
	var result = await game._deal_damage_result(game.players[2], owner, 2, EffectChain.DamageType.PHYSICAL)
	t.check(not result.invalidated and offers == [[owner, owner]] and owner.good_deed_marks == 1, "I05d own damage offers one Emergency and one mark without an invented self-target ban")
	t.check(owner.is_alive() and owner.hp == 1 and owner.hand.is_empty(), "I05d own Emergency net HP zero preserves original negative-HP rescue and pays both Peaches")
	await dispose(t, game)

func drive(game, target, result):
	result.append(await game._deal_damage_result(game.players[3], target, 1, EffectChain.DamageType.PHYSICAL))

func bridge(t):
	for seat in [0, 1]:
		for mode in ["confirm", "cancel", "timeout", "close"]:
			var game = fixture(t)
			var owner = game.players[seat]
			if seat == 1:
				owner.general_name = game.players[0].general_name
				game.players[0].general_name = "placeholder"
				owner.simba_emergency_enabled = true
			var target = game.players[2]
			game._simba_emergency_choice_override = Callable()
			var adapter = LanGameBridge.new()
			t.root.add_child(adapter); adapter.game = game
			var result: Array = []
			drive(game, target, result)
			await t.process_frame
			var view = adapter.snapshot(seat)
			t.check(result.is_empty() and target.hp == 4 and target.good_deed_marks == 0 and owner.hp == 5, "I05d actual Emergency prompt holds committed damage but pays nothing before confirmation")
			# Names are read from authoritative actual controls, not invented commands.
			var actions = view.controls.filter(func(c): return c.text == "发动急救")
			t.check(actions.size() == 1 and not adapter.submit((seat + 1) % 5, actions[0].id), "I05d Emergency fixed recipient prompt belongs only to acting host/remote seat")
			var token = actions[0].id
			if mode == "timeout": game._countdown_on_timeout.call()
			elif mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
			else:
				var buttons = actions if mode == "confirm" else view.controls.filter(func(c): return c.text == "取消")
				t.check(buttons.size() == 1 and adapter.submit(seat, buttons[0].id), "I05d actual Emergency confirm/cancel travels through LAN bridge")
			for i in 4: await t.process_frame
			t.check(result.size() == 1 and result[0].invalidated == (mode == "close"), "I05d Emergency distinguishes technical close from ordinary decline/timeout")
			t.check(owner.hp == (4 if mode == "confirm" else 5) and target.hp == (5 if mode == "confirm" else 4) and target.good_deed_marks == (1 if mode == "confirm" else 0), "I05d Emergency confirmation is sole cost/effect commit boundary")
			t.check(not adapter.submit(seat, token) and int(adapter.snapshot(seat).players[2].get("good_deed_marks", 0)) == target.good_deed_marks, "I05d Emergency updates authoritative recipient value and rejects consumed input token")
			adapter.game = null; adapter.queue_free()
			await dispose(t, game)

func invalid(t):
	for mode in ["phase", "owner_reset", "target_reset", "generation", "end"]:
		var game = fixture(t)
		var owner = game.players[0]
		var target = game.players[1]
		game._simba_emergency_choice_override = func(_p, _q, _valid):
			match mode:
				"phase": game.turn_manager.current_phase = TurnManager.Phase.END; game.turn_manager._context_revision += 1
				"owner_reset": owner.restore_game_start_state()
				"target_reset": target.restore_game_start_state()
				"generation": game._dying_lifecycle_generation += 1
				"end": game._game_over = true
			return 0
		var result = await game._deal_damage_result(game.players[2], target, 1, EffectChain.DamageType.PHYSICAL)
		t.check(result.invalidated and owner.hp == 5 and target.good_deed_marks == 0, "I05d stale Emergency selection never pays or grants a marker: " + mode)
		await dispose(t, game)

func interactions(t):
	for element in [EffectChain.DamageType.FIRE, EffectChain.DamageType.THUNDER]:
		var game = fixture(t)
		var owner = game.players[0]
		var offered: Array = []
		for seat in [1, 2]: game.players[seat].chained = true
		game._simba_emergency_choice_override = func(_p, q, _valid): offered.append(q); return 0
		var result = await game._deal_damage_result(game.players[3], game.players[1], 1, element)
		t.check(not result.invalidated and offered == [game.players[1], game.players[2]] and owner.hp == 3, "I05d fire/thunder propagation creates two distinct actual damage Emergency opportunities")
		t.check(game.players[1].good_deed_marks == 1 and game.players[2].good_deed_marks == 1 and not game.players[1].chained and not game.players[2].chained, "I05d Emergency extra HP does not cancel committed elemental damage or chain removal")
		await dispose(t, game)
	var game = fixture(t)
	var owner = game.players[0]
	var victim = game.players[1]
	var protector = game.players[2]
	protector.hand.append(null)
	game._sacrifice_override = Callable()
	game._sacrifice_actor_override = func(p, target, _amount): return p == protector and target == victim
	var offered: Array = []
	game._simba_emergency_choice_override = func(_p, q, _valid): offered.append(q); return 0
	var result = await game._deal_damage_result(game.players[3], victim, 1, EffectChain.DamageType.PHYSICAL)
	t.check(not result.invalidated and result.target == protector and offered == [protector], "I05d Sacrifice offers Emergency only for actual transferred damage receiver")
	t.check(victim.hp == 5 and victim.good_deed_marks == 0 and protector.hp == 5 and protector.good_deed_marks == 1 and owner.hp == 4, "I05d transferred Emergency never marks or heals the protected original target")
	await dispose(t, game)
	game = fixture(t)
	owner = game.players[0]
	var jim = game.players[4]
	var first = game._spawn_mountain_at(jim, 1, 2)
	game._spawn_mountain_at(jim, 4, 0)
	var offers: Array = []
	game._simba_emergency_choice_override = func(_p, q, _v): offers.append(q); return 0
	await game._deal_damage_result(game.players[3], game.players[2], 1, EffectChain.DamageType.PHYSICAL)
	t.check(offers.is_empty() and owner.hp == 5 and game.players[2].good_deed_marks == 0, "I05d Emergency cannot cross real mountain partition")
	t.check(not game._emergency_target_allowed(owner, first), "I05d terrain is not an ordinary Emergency recipient")
	await dispose(t, game)
	for visible in [false, true]:
		game = fixture(t)
		owner = game.players[0]
		var chris = game.players[1]
		chris.general_name = "克里斯·西弗"
		var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, chris)
		var id = game.unit_registry.id_for(dragon)
		var audience: Array[Player] = [owner]
		if visible: game.fire_dragon_state.record_use(id, 1, audience)
		await game._deal_damage_result(null, dragon, 1, EffectChain.DamageType.PHYSICAL)
		t.check(owner.hp == (4 if visible else 5) and dragon.hp == (3 if visible else 2) and dragon.good_deed_marks == (1 if visible else 0), "I05d real registered dragon Emergency respects recipient stealth: " + str(visible))
		t.check(chris.hp == 5 and chris.good_deed_marks == 0, "I05d unit Emergency grants only independent body, never controller")
		await dispose(t, game)

func nested_invalid(t):
	var game = fixture(t)
	var owner = game.players[0]
	var target = game.players[1]
	var source = game.players[3]
	owner.hp = 1
	owner.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
	owner.sage_activated = true
	source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.POFENG_SPEAR))
	var result: Array = []
	drive(game, target, result)
	await t.process_frame
	t.check(result.is_empty() and owner.hp == 0 and target.hp == 5 and target.good_deed_marks == 1 and not game._choice_prompt_stack.is_empty(), "I05d Emergency parent waits on lethal cost payer Sage after recipient commit")
	game._choice_prompt_stack.back().overlay.queue_free()
	for i in 4: await t.process_frame
	t.check(result.size() == 1 and result[0].invalidated and source.hand_limit_bonus == 0, "I05d nested Emergency cost technical failure propagates to original damage and stops post-damage weapon")
	t.check(owner.is_dying() and target.hp == 5 and target.good_deed_marks == 1 and game._dying_contexts.is_empty(), "I05d nested invalidation retains committed cost and grant without false death or refund")
	await dispose(t, game)

func negative_recipient(t):
	var game = fixture(t)
	var owner = game.players[0]
	var target = game.players[1]
	owner.hp = 1; target.hp = 1
	owner.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
	owner.sage_activated = true
	game._sage_save_override = func(): return true
	var offered: Array = []
	game._rescue_choice_override = func(p, q, options):
		offered.append(q)
		return CardData.CardSubType.PEACH if p == owner and q == target and options.has(CardData.CardSubType.PEACH) else -1
	var result = await game._deal_damage_result(game.players[3], target, 2, EffectChain.DamageType.PHYSICAL)
	t.check(not result.invalidated and owner.hp == 5 and owner.hand_size() == 3 and target.hp == 1 and target.good_deed_marks == 1, "I05d still-dying recipient receives ordinary rescue only after cost payer Sage, and can use its new hand")
	t.check(not offered.is_empty() and offered.all(func(q): return q == target), "I05d negative recipient Emergency commits once, then resumes original damage rescue instead of bypassing it")
	await dispose(t, game)
	game = fixture(t)
	owner = game.players[0]; target = game.players[1]
	target.hp = 6
	await game._deal_damage_result(game.players[3], target, 1, EffectChain.DamageType.PHYSICAL)
	t.check(target.hp == 6 and target.max_hp == 5 and target.good_deed_marks == 1 and owner.hp == 4, "I05d Emergency preserves allowed extra HP above maximum, never replaces it with capped healing")
	await dispose(t, game)
