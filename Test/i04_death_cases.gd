extends RefCounted

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for scenario in ["full","wounded","double","peach","sage","death"]:
		# Initial placement/wounds are fixture setup. The tested Strike pays a
		# real hand card and uses the complete damage/death/rescue pipeline.
		var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,false)
		game._halt_countdown()
		var owner = game.players[0]
		var first = game._spawn_mountain_at(owner,0,1)
		var second = game._spawn_mountain_at(owner,0,1)
		first.hp = 1
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		game._rescue_choice_override = func(_r,_d,_o): return -1
		if scenario == "wounded": owner.hp = 4
		if scenario in ["peach","sage","death"]: owner.hp = 1
		if scenario == "peach":
			game._rescue_choice_override = func(rescuer,dying,options): return CardData.CardSubType.PEACH if rescuer == game.players[1] and dying == owner and options.has(CardData.CardSubType.PEACH) else -1
		if scenario == "sage":
			owner.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			owner.sage_activated = true
			game._sage_save_override = func(): return true
		var deaths: Array = []
		var removed: Array = []
		var actions: Array = []
		game.unit_death_committed.connect(func(id): deaths.append(id))
		game.unit_removed.connect(func(id,reason): removed.append([id,reason]))
		game.card_action_completed.connect(func(event): actions.append(event))
		var first_id = game.unit_registry.id_for(first)
		if scenario == "double":
			second.hp = 1
			owner.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
			var targets: Array[Player] = [first,second]
			await game.execute_multi_strike(targets,CardData.CardSubType.STRIKE)
		else: await game.execute_card_on_target(first,CardData.CardSubType.STRIKE)
		t.check(first.is_dead() and game.unit_registry.entry(first_id).reason == UnitRegistry.Removal.NORMAL_DEATH and deaths.has(first_id), "I04c2c real terrain death commits once: "+scenario)
		if scenario == "full": t.check(owner.hp == 5 and owner.max_hp == 5 and owner.jim_rebuild_pending == 1, "I04 Q17 full Jim becomes 5/5, not 4/5")
		if scenario == "wounded": t.check(owner.hp == 3 and owner.max_hp == 5 and owner.jim_rebuild_pending == 1, "I04 Q17 wounded Jim loses exactly one HP and one maximum")
		if scenario == "double": t.check(owner.hp == 4 and owner.max_hp == 4 and owner.jim_rebuild_pending == 2 and deaths.size() == 2, "I04c2c one paid multi-Strike settles two separate costs sequentially")
		if scenario == "peach": t.check(owner.hp == 1 and owner.max_hp == 5 and owner.jim_rebuild_pending == 1 and second.is_alive(), "I04c2c cost HP loss awaits ordinary Peach rescue; remaining mountain retained")
		if scenario == "sage":
			t.check(owner.hp == 6 and owner.max_hp == 6 and owner.hand_size() == 4 and owner.jim_rebuild_pending == 0, "I04c2c cost HP loss awaits Sage and restores general-card deferred resource")
			t.check(second.unit_disappeared and not second.is_dead() and deaths.size() == 1 and removed.back()[1] == UnitRegistry.Removal.SAGE_RESTORE, "I04c2c Sage disappearance is not a second mountain death/cost")
		if scenario == "death":
			t.check(owner.is_dead() and owner.max_hp == 5 and second.unit_disappeared and not second.is_dead(), "I04c2c failed cost rescue finally kills Jim and removes remaining mountain")
			t.check(deaths.size() == 1 and removed.back()[1] == UnitRegistry.Removal.SUMMONER_LOST, "I04c2c summoner disappearance has no recursive mountain cost")
		t.check(actions.size() == (2 if scenario == "peach" else 1) and actions.all(func(event): return event.settlement_completed) and game._pending_card_actions.is_empty(), "I04c2c death and nested cost rescue finish every original paid action")
		if scenario == "peach":
			t.check(actions.filter(func(event): return event.sub_type == CardData.CardSubType.STRIKE).size() == 1 and actions.filter(func(event): return event.sub_type == CardData.CardSubType.PEACH).size() == 1, "I04c2c original Strike and actual rescue Peach each complete exactly once")
		var before = owner.max_hp
		await game._resolve_dying(first,null,"reentry test")
		t.check(owner.max_hp == before and deaths.count(first_id) == 1, "I04c2c repeated death dispatch cannot pay a second cost")
		game._game_over = true
		game.queue_free()
		await t.process_frame
	# Fault injection: a synchronous removal observer can reset this GameManager
	# before the old frame reaches the newly awaited summoner cost.
	var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,false)
	game._halt_countdown()
	var owner = game.players[0]
	var mountain = game._spawn_mountain_at(owner,0,1)
	mountain.hp = 1
	game._sacrifice_actor_override = func(_p,_target,_amount): return false
	game.unit_removed.connect(func(_id,reason):
		if reason == UnitRegistry.Removal.NORMAL_DEATH: game.reset_game_over_state())
	var completed: Array = []
	game.card_action_completed.connect(func(event): completed.append(event))
	await game.execute_card_on_target(mountain,CardData.CardSubType.STRIKE)
	t.check(owner.hp == 6 and owner.max_hp == 6 and owner.jim_rebuild_pending == 0, "I04c2c reset during death notification cannot charge an old cost to the new match")
	t.check(completed.is_empty() and game._pending_card_actions.is_empty(), "I04c2c invalidated old death frame cannot publish a completion in the new match")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
