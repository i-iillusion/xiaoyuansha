extends RefCounted

func fixture(t, count := 5, enable := true, override: Callable = Callable()):
	load("res://Test/h02_integration_cases.gd").new().prepare(count,GameModes.FREE_FOR_ALL)
	GameManager.selected_general = "吉姆·芒顿"
	var game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	game._mountain_rules_enabled = enable
	game._mountain_placement_override = override
	t.root.add_child(game)
	game.start_game()
	return game

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved=[GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for count in [2,5,10]:
		for choice in [0,-1]:
			var game = fixture(t,count,true,func(_owner,_options,_valid): return choice)
			var owner=game.players[0]
			t.check(owner.jim_mountains_started and game.mountain_space.ids().size()==2, "I04c1 real startup commits two mountains once: %d/%d" % [count,choice])
			t.check(game.turn_manager.current_phase==TurnManager.Phase.PLAY and game._jim_opening_pending.is_empty(), "I04c1 successful opening resumes normal START/JUDGE/DRAW/PLAY")
			t.check(owner.hand_size()==6 and game._card_action_serial==0, "I04c1 locked summon spends no hand and publishes no card USE")
			var placements=game._mountain_snapshot().placements()
			if choice==0: t.check(placements[0].left==0 and placements[1].left==0, "I04c1 same-gap placement remains legal")
			else: t.check(placements[0].left==count-1 and placements[0].right==0 and placements[1].left==0 and placements[1].right==1, "I04 Q2 forced timeout uses owner's left and right")
			t.check(await game._maybe_initial_mountains(owner,func(): return true)==0 and game.unit_registry.active_units().size()==2, "I04c1 later invocation cannot repeat a committed opening")
			await dispose(t,game)
	# Every invalidation occurs while the real first START is suspended, before
	# registration. These are fault injection cases, not authorized game actions.
	for scenario in ["index","phase","general","death","reset","registry","space","reentry","general_reset"]:
		var nested: Array=[]
		var override=func(owner,options,valid):
			# start_game has already constructed the authoritative Player/Deck/UI.
			var game: GameManager=owner.get_parent()
			if scenario=="index": return options.size()
			if scenario=="phase": game.turn_manager.current_phase=TurnManager.Phase.DRAW
			if scenario=="general": owner.general_name="稻草人"
			if scenario=="death": owner.mark_dead()
			if scenario=="reset": game.reset_game_over_state()
			if scenario=="registry": game._reset_unit_registry()
			if scenario=="space": game.turn_manager.rounds.relocate_before(3,0)
			if scenario=="general_reset": owner.restore_game_start_state()
			if scenario=="reentry": nested.append(await game._maybe_initial_mountains(owner,valid))
			return 0
		var game=fixture(t,5,true,override)
		var paid=scenario=="reentry"
		t.check(game.mountain_space.ids().size()==(2 if paid else 0) and game.players[0].jim_mountains_started==paid, "I04c1 no partial registration or consumed opportunity after invalidation: "+scenario)
		t.check(game._jim_opening_pending.is_empty(), "I04c1 pending lease released: "+scenario)
		if paid: t.check(nested==[game.CHOICE_INVALID], "I04c1 nested activation cannot duplicate the same first START")
		await dispose(t,game)
	# Exact Q8 START pipeline with a seeded flip: this does not claim the whole
	# upstream Soul-Blade card sequence has been played by a LAN client.
	var game=fixture(t,5,false)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game._mountain_rules_enabled=true
	game._mountain_placement_override=func(_owner,_options,_valid): return -1
	var owner=game.players[0]
	owner.facedown=true
	game.turn_manager.current_phase=TurnManager.Phase.START
	await game._do_start(0)
	t.check(not owner.facedown and game.turn_manager.current_phase==TurnManager.Phase.END and not owner.jim_mountains_started and game.unit_registry.active_units().is_empty(), "I04 Q8 flipped first START reaches END without summoning/consuming the opportunity")
	t.check(owner.hand_size()==6 and game.turn_manager.current_player_idx==0 and not game.turn_manager.skip_full_turn, "I04 Q8 skipping draws no extra cards; transient skip flag consumed by START-to-END, not a permanent skill state")
	game.turn_manager.skip_full_turn=false
	game.turn_manager.current_phase=TurnManager.Phase.START
	await game._do_start(0)
	t.check(owner.jim_mountains_started and game.unit_registry.active_units().size()==2, "I04 Q8 next normal START performs the first locked summon")
	await dispose(t,game)
	# Real ordinary rescue/Sage pipeline. Upstream mountain final-death dispatch
	# is seeded here, not claimed as a played strike or implemented Zaoshan cost.
	for skip_after_restore in [false,true]:
		game=fixture(t,5,true,func(_owner,_options,_valid): return 0)
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		owner=game.players[0]
		var old_ids=game.mountain_space.ids()
		for id in old_ids:
			var mountain: Player=game.unit_registry.entry(id).body
			mountain.hp=0
			mountain.mark_dead()
			t.check(game._retire_final_unit(mountain), "I04 Q9 final-dispatch fixture removes the original mountain before Sage")
		var armor=CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
		owner.equip_card_to_slot("armor",armor)
		owner.sage_activated=true
		game._rescue_choice_override=func(_rescuer,_dying,_options): return -1
		game._sage_save_override=func(): return true
		owner.hp=0
		await game._resolve_dying(owner,null,"I04 Q9 first-trigger Sage regression")
		t.check(owner.is_alive() and owner.hp==owner.max_hp and not owner.jim_mountains_started, "I04 Q9 real Sage restores the unspent first-trigger state")
		t.check(owner.hand_size()==4 and owner.equipment.is_empty() and game.deck._discard.count(armor)==1, "I04 Q9 Sage keeps its existing clear/restore/draw-four semantics")
		t.check(game.mountain_space.ids().is_empty(), "I04 Q9 restoring eligibility does not immediately generate terrain")
		if skip_after_restore:
			owner.facedown=true
			game.turn_manager.current_phase=TurnManager.Phase.START
			await game._do_start(0)
			t.check(not owner.facedown and not owner.jim_mountains_started and game.mountain_space.ids().is_empty(), "I04 Q8/Q9 a flipped turn after Sage still preserves renewed eligibility")
		game.turn_manager.skip_full_turn=false
		game.turn_manager.current_phase=TurnManager.Phase.START
		await game._do_start(0)
		t.check(owner.jim_mountains_started and game.mountain_space.ids().size()==2, "I04 Q9 next normal START repeats the locked summon")
		t.check(game.mountain_space.ids().all(func(id): return not old_ids.has(id)) and game.unit_registry.active_units().all(func(body): return body.hp==5 and body.max_hp==5), "I04 Q9 repeated summon creates new full-health bodies, never resurrects old handles")
		t.check(owner.hand_size()==4 and game._card_action_serial==0, "I04 Q9 repeated locked summon spends no card or extra card-use count")
		await dispose(t,game)
	# Q13's three real dying paths with existing mountains. Registry-only dragon
	# and resource seeds isolate cleanup classification, not new summon/equip rules.
	# Put both mountains in one gap: rescuer and owner remain in the same region;
	# the Peach case must not accidentally authorize healing across two barriers.
	for path in ["peach","sage","death"]:
		game=fixture(t,5,true,func(_owner,_options,_valid): return 0)
		game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
		owner=game.players[0]
		var ids=game.mountain_space.ids()
		var old_mountains: Array=[]
		for index in ids.size():
			var body: Player=game.unit_registry.entry(ids[index]).body
			body.hp=2+2*index
			old_mountains.append(body)
		var lion=CardBase.create(CardData.CardSubType.SILVER_LION)
		old_mountains[0].equip_card_to_slot("armor",lion)
		var judgment=CardBase.create(CardData.CardSubType.INDULGENCE)
		old_mountains[0].judgment_cards.append(judgment)
		old_mountains[0].hand.append(null)
		var dragon=FireDragonState.create_body()
		var dragon_id=game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,dragon,owner)
		game.fire_dragon_state.attach(dragon_id)
		var armor=CardBase.create(CardData.CardSubType.SAGE_PROTECTION)
		owner.equip_card_to_slot("armor",armor)
		owner.sage_activated=true
		var deaths: Array=[]
		var removed: Array=[]
		game.unit_death_committed.connect(func(id): deaths.append(id))
		game.unit_removed.connect(func(id,reason): removed.append([id,reason]))
		game._rescue_choice_override=func(rescuer,_dying,options):
			return CardData.CardSubType.PEACH if path=="peach" and rescuer==game.players[1] and options.has(CardData.CardSubType.PEACH) else -1
		game._sage_save_override=func(): return path=="sage"
		owner.hp=0
		await game._resolve_dying(owner,null,"I04 Q13 existing terrain: "+path)
		t.check(deaths.is_empty(), "I04 Q13 cleanup never fabricates mountain/dragon normal death: "+path)
		if path=="peach":
			t.check(owner.hp==1 and owner.jim_mountains_started and game.mountain_space.ids()==ids, "I04 Q13 ordinary Peach rescue preserves both mountains and spent first-trigger")
			t.check(removed.is_empty() and old_mountains[0].hp==2 and old_mountains[1].hp==4 and old_mountains[0].get_equipment_card("armor")==lion, "I04 Q13 rescue preserves terrain HP/cards/positions without lion healing")
		else:
			t.check(game.mountain_space.ids().is_empty() and old_mountains.all(func(body): return body.unit_disappeared and not body.is_dead()), "I04 Q13 old mountains disappear, not die: "+path)
			t.check(old_mountains[0].hp==2 and old_mountains[0].equipment.is_empty() and old_mountains[0].hand_size()==0 and old_mountains[0].judgment_cards.is_empty() and game.deck._discard.count(lion)==1 and game.deck._discard.count(judgment)==1, "I04 Q13 cleanup discards originals once with no lost-equipment heal: "+path)
			var reason=UnitRegistry.Removal.SAGE_RESTORE if path=="sage" else UnitRegistry.Removal.SUMMONER_LOST
			t.check(removed.has([ids[0],reason]) and removed.has([ids[1],reason]), "I04 Q13 cleanup reason stays distinct from normal mountain death: "+path)
		if path=="sage":
			t.check(owner.is_alive() and owner.hp==6 and owner.max_hp==6 and not owner.jim_mountains_started and owner.hand_size()==4, "I04 Q13 confirmed Sage clears terrain without Zaoshan loss and restores eligibility")
			t.check(game.unit_registry.contains_active(dragon) and not dragon.unit_disappeared and removed.size()==2, "I04 Q13 Sage mountain exception never removes fire dragon")
			game.turn_manager.skip_full_turn=false
			game.turn_manager.current_phase=TurnManager.Phase.START
			await game._do_start(0)
			t.check(owner.jim_mountains_started and game.mountain_space.ids().size()==2 and game.mountain_space.ids().all(func(id): return not ids.has(id)), "I04 Q13 next normal START creates two new terrain handles after clearing old pair")
		elif path=="death":
			t.check(owner.is_dead() and not game.unit_registry.contains_active(dragon) and dragon.unit_disappeared and removed.size()==3, "I04 Q13 ordinary final death retains existing all-attachment disappearance rule")
		await dispose(t,game)
	# Actual adapter start, controller-private first START prompt, and normal
	# timeout callback. No edits to phase/HP/hand or model-only turn starts.
	for choose in [true,false]:
		var bridge=LanGameBridge.new()
		bridge._enable_mountain_rules_for_tests=true
		t.root.add_child(bridge)
		var roster: Array[Dictionary]=[]
		for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat==0 else "稻草人"})
		t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04c1 real adapter starts with gated Jim roster")
		var view=bridge.snapshot(0)
		t.check(view.owner==0 and view.controls.size()==30 and bridge.snapshot(1).controls.is_empty(), "I04 Q24 initial pair choices include either side of planned first mountain, private and uncancellable")
		var stale=view.controls[0].id
		if choose:
			t.check(not bridge.submit(1,stale) and bridge.submit(0,stale), "I04c1 real opaque command checks first-placement owner")
		else: bridge.game._countdown_on_timeout.call()
		t.check(bridge.game.players[0].jim_mountains_started and bridge.game.unit_registry.active_units().size()==2, "I04c1 real placement click/timeout registers both bodies")
		t.check(not bridge.submit(0,stale), "I04c1 old placement token cannot submit again in PLAY")
		bridge.game._game_over=true
		bridge.queue_free()
		await t.process_frame
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]
