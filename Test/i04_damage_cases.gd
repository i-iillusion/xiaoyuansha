extends RefCounted

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	for effect in ["soul","blood","kevin","pofeng"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		var source = game.players[0]
		var mountain = game._spawn_mountain_at(game.players[1],1,2)
		var asks: Array = []
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		game._rps_override = func(_p): asks.append("gesture"); return 0
		game._kaiwen_override = func(): asks.append("kevin"); return true
		game._bloodthirsty_override = func(): asks.append("blood"); return true
		game._soul_blade_activate_override = func(): asks.append("soul"); return true
		if effect == "kevin": source.general_name = "凯文·罗本"
		else:
			var weapon = {"soul":CardData.CardSubType.SOUL_BLADE,"blood":CardData.CardSubType.BLOODTHIRSTY_BLADE,"pofeng":CardData.CardSubType.POFENG_SPEAR}[effect]
			source.equip_card_to_slot("weapon",CardBase.create(weapon))
		source.soul_blade_activated = effect == "soul"
		source.hp = 2
		var hand = source.hand_size()
		# Actual damage + post-damage pipeline. Target selection and Dodge are
		# deliberately skipped here: this is Q14, not full legal killing terrain.
		var chain = game._new_damage_chain(source,mountain,CardBase.create(CardData.CardSubType.STRIKE),2,EffectChain.DamageType.PHYSICAL)
		chain.skip_targeting = true
		chain.skip_response = true
		await chain.start()
		t.check(chain.damage.committed and mountain.hp == 3 and not chain.continuation_invalid, "I04 Q14 committed terrain damage finishes without technical invalidation: "+effect)
		t.check(asks.is_empty() and not mountain.facedown and source.hp == 2 and source.hand_size() == hand, "I04 Q14 no terrain RPS prompt, gesture, flip, healing or draw: "+effect)
		t.check(chain.damage.events.has("after_take_damage") and ActorIdentity.key_for(game.players,game.unit_registry,mountain) == null, "I04 Q14 remaining damage hooks finish without assigning terrain an actor identity")
		t.check(source.hand_limit_bonus == (2 if effect == "pofeng" else 0), "I04 Q14 unrelated Pofeng damage benefit remains intact")
		t.check(await game._try_soul_blade(source,mountain) == 0 and await game._try_bloodthirsty(source,mountain,2) == 0 and await game._try_kaiwen_deal(source,mountain,2) == 0, "I04 Q14 direct optional-effect entry points also decline normally")
		# Both real fixed players and intelligent units must retain their existing
		# RPS behavior. Unit registration is a classification fixture, not a new
		# authorization for this source general to summon a dragon.
		if effect != "pofeng":
			for unit_target in [false,true]:
				var target = game.players[2]
				if unit_target:
					target = FireDragonState.create_body()
					var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,target,game.players[1])
					game.fire_dragon_state.attach(id)
				asks.clear()
				game._rps_override = func(p): asks.append("gesture"); return 0 if p == source else 2
				var result = 0
				var before_hand = source.hand_size()
				var before_hp = source.hp
				if effect == "soul": result = await game._try_soul_blade(source,target)
				elif effect == "blood": result = await game._try_bloodthirsty(source,target,1)
				else: result = await game._try_kaiwen_deal(source,target,1)
				t.check(result == 0 and asks.has("gesture"), "I04 Q14 player/intelligent-unit RPS still executes: %s/%s" % [effect,unit_target])
				t.check(target.facedown if effect == "soul" else (source.hp == before_hp+1 if effect == "blood" else source.hand_size() == before_hand+2), "I04 Q14 eligible target retains existing RPS reward: %s/%s" % [effect,unit_target])
		game._game_over = true
		game.queue_free()
		await t.process_frame
	await soul_count(t)
	await strike_basics(t)
	await spear_terrain(t)
	await sacrifice_terrain(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func soul_count(t):
	for prior_player in [false,true]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		var source = game.players[0]
		var target = game.players[2]
		var mountain = game._spawn_mountain_at(game.players[1],1,2)
		source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.SOUL_BLADE))
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		if prior_player:
			await count_damage(game,source,target,2)
			t.check(source.soul_blade_track_target == target and source.soul_blade_track_count == 2 and not source.soul_blade_activated, "I04 Q15 player C first accumulates two actual damage")
		await count_damage(game,source,mountain,1 if prior_player else 3)
		t.check(not source.soul_blade_activated and source.soul_blade_track_count == (2 if prior_player else 0), "I04 Q15 terrain damage never accumulates or activates Soul Blade")
		t.check(source.soul_blade_track_target == (target if prior_player else null), "I04 Q15 terrain damage preserves previous target, including no previous player")
		if prior_player:
			await count_damage(game,source,target,1)
			t.check(source.soul_blade_activated and source.soul_blade_track_count == 3 and source.soul_blade_track_target == target, "I04 Q15 C2 -> mountain1 -> C1 activates on final C damage")
		t.check(not game._game_over and game._choice_prompt_stack.is_empty(), "I04 Q15 activation-count sequence finishes without a mountain prompt")
		game._game_over = true
		game.queue_free()
		await t.process_frame

func count_damage(game, source, target, amount):
	# Real committed damage/post-damage hooks; upstream card selection is not
	# part of this activation-counter regression.
	var chain = game._new_damage_chain(source,target,null,amount,EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	chain.skip_response = true
	await chain.start()

func strike_basics(t):
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,6,GameModes.FREE_FOR_ALL)
	var first = game._spawn_mountain_at(game.players[0],1,2)
	var second = game._spawn_mountain_at(game.players[0],3,4)
	var source = game.players[1]
	t.check(game._get_strike_targets(source).has(first) and not game._get_strike_targets(source).has(second), "I04c2b ordinary strike range includes adjacent terrain but not distant terrain")
	source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QILING_BOW))
	var targets = game._get_strike_targets(source)
	t.check(targets.has(first) and targets.has(second), "I04c2b Qiling ignores finite terrain distance")
	t.check(not targets.has(game.players[2]) and not targets.has(game.players[3]) and targets.has(game.players[4]), "I04c2b Qiling cannot bypass two-mountain partition")
	for sub in game.TARGET_TRICKS:
		t.check(not game.get_trick_targets(source,sub).has(first) and not game.get_trick_targets(source,sub).has(second), "I04c2b terrain never enters ordinary trick candidates: "+str(sub))
	var dragon = FireDragonState.create_body()
	var dragon_id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,dragon,source)
	game.fire_dragon_state.attach(dragon_id)
	t.check(game._get_strike_targets(dragon).has(first) and not game._get_strike_targets(dragon).has(second), "I04c2b dragon strike uses owner base anchor with its own range")
	game.players[0].mark_dead()
	game._remove_summoner_units(game.players[0])
	t.check(not game._get_strike_targets(source).has(first) and not game._has_damage_target_body(first), "I04c2b disappeared original terrain loses target membership")
	game._game_over = true
	game.queue_free()
	await t.process_frame
	for sub in [CardData.CardSubType.STRIKE,CardData.CardSubType.FIRE_STRIKE,CardData.CardSubType.THUNDER_STRIKE]:
		game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		source = game.players[0]
		first = game._spawn_mountain_at(game.players[1],0,1)
		# Q16 now forbids Sacrifice for terrain; willing responders are covered
		# separately by sacrifice_terrain, including the actual LAN adapter.
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		var dodge_asks: Array = []
		game._dodge_override = func(): dodge_asks.append(true); return true
		var completed: Array = []
		game.card_action_completed.connect(func(event): completed.append(event))
		var hand = source.hand_size()
		await game.execute_card_on_target(first,sub)
		t.check(first.hp == (4 if sub == CardData.CardSubType.STRIKE else 3), "I04c2b paid strike applies physical1 or elemental2 once: "+str(sub))
		t.check(source.hand_size() == hand-1 and game.turn_manager.strikes_used() == 1 and completed.size() == 1 and completed[0].settlement_completed, "I04c2b paid terrain strike consumes one hand/count and completes its original receipt")
		t.check(dodge_asks.is_empty() and first.hand_size() == 0 and game._choice_prompt_stack.is_empty(), "I04c2b ordinary terrain has no Dodge/controller prompt")
		t.check(game._pending_card_actions.is_empty() and not game._game_over and first.is_alive(), "I04c2b nonlethal terrain strike leaves no abandoned action")
		game._game_over = true
		game.queue_free()
		await t.process_frame

func spear_terrain(t):
	for sage in [false,true]:
		var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,false)
		game._halt_countdown()
		var source = game.players[0]
		var mountain = game._spawn_mountain_at(source,0,1)
		var other = game._spawn_mountain_at(source,0,1)
		source.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR))
		game._zhangba_override = func(): return 1
		game._sacrifice_actor_override = func(_p,_target,_amount): return false
		if sage:
			source.equip_card_to_slot("armor",CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
			source.sage_activated = true
			source.hp = 1
			game._rescue_choice_override = func(_r,_d,_o): return -1
			game._sage_save_override = func(): return true
		var completed: Array = []
		game.card_action_completed.connect(func(event): completed.append(event))
		await game.execute_card_on_target(mountain,CardData.CardSubType.THUNDER_STRIKE)
		if sage:
			t.check(source.is_alive() and source.hp == 6 and source.hand_size() == 4, "I04c2b Zhangba cost enters real Sage rescue and restores Jim")
			t.check(mountain.unit_disappeared and other.unit_disappeared and mountain.hp == 5 and other.hp == 5, "I04c2b confirmed Sage clears old terrain before pending Strike damage, without ghost hits")
			t.check(game.mountain_space.ids().is_empty() and not source.jim_mountains_started, "I04c2b pending Strike cannot regenerate terrain after Sage")
		else:
			t.check(source.hp == 5 and mountain.hp == 2 and other.hp == 5, "I04c2b Zhangba pays one HP and adds damage before mountain elemental bonus, once")
		t.check(completed.size() == 1 and completed[0].settlement_completed and game._pending_card_actions.is_empty(), "I04c2b Zhangba terrain continuation completes original paid action: "+str(sage))
		t.check(game.turn_manager.strikes_used() == 1 and not game._game_over and game._choice_prompt_stack.is_empty(), "I04c2b Zhangba continuation neither refunds use nor leaves stale choices")
		game._game_over = true
		game.queue_free()
		await t.process_frame

func sacrifice_terrain(t):
	for lan in [false,true]:
		for sub in [CardData.CardSubType.STRIKE,CardData.CardSubType.FIRE_STRIKE]:
			var bridge: LanGameBridge
			var game: GameManager
			if lan:
				bridge = LanGameBridge.new()
				t.root.add_child(bridge)
				var roster: Array[Dictionary] = []
				for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 1 else "稻草人"})
				t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 Q16 real LAN adapter starts its human roster")
				game = bridge.game
			else:
				game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
			game._halt_countdown()
			var source = game.players[0]
			var volunteer = game.players[2]
			# Placement is an internal fixture; the actual paid card, damage chain
			# and (for LAN) input-ownership adapter are exercised below.
			var mountain = game._spawn_mountain_at(game.players[1],0,1)
			game._spawn_mountain_at(game.players[1],0,1)
			var offered: Array = []
			game._sacrifice_actor_override = func(p,_target,_amount): offered.append(p); return p == volunteer
			var cards = volunteer.hand.duplicate()
			var hp = volunteer.hp
			var before_source = source.hand_size()
			var actions: Array = []
			game.card_action_committed.connect(func(event): actions.append(event))
			await game.execute_card_on_target(mountain,sub)
			t.check(offered.is_empty() and volunteer.hand == cards and volunteer.hp == hp, "I04 Q16 willing volunteer gets no offer, payment or transferred damage: %s/%s" % [lan,sub])
			t.check(mountain.hp == (4 if sub == CardData.CardSubType.STRIKE else 3) and source.hand_size() == before_source-1, "I04 Q16 original mountain damage and original card payment remain intact")
			t.check(actions.size() == 1 and actions[0].sub_type == sub and actions[0].settlement_completed and game._pending_card_actions.is_empty(), "I04 Q16 no phantom Sacrifice action; paid Strike completes")
			var reply = await game._maybe_sacrifice_result(source,mountain,1,EffectChain.DamageType.PHYSICAL)
			t.check(not reply.invalidated and reply.player == null and offered.is_empty() and game._choice_prompt_stack.is_empty(), "I04 Q16 direct production entry declines normally without creating a prompt")
			if lan:
				t.check(bridge.input_owner() == 0 and bridge.snapshot(2).controls.is_empty(), "I04 Q16 LAN ownership never moves to the would-be rescuer")
			game._game_over = true
			if lan: bridge.queue_free()
			else: game.queue_free()
			await t.process_frame
	# The exclusion is specific to ordinary mountains. Existing character and
	# intelligent-unit transfer behavior remains; unit registration is only a
	# classification fixture, not an upstream legal summoning/targeting proof.
	for dragon in [false,true]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		var victim = game.players[1]
		if dragon:
			victim = FireDragonState.create_body()
			var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,victim,game.players[1])
			game.fire_dragon_state.attach(id)
		var volunteer = game.players[2]
		game._sacrifice_actor_override = func(p,_target,_amount): return p == volunteer
		var cards = volunteer.hand_size()
		var hp = volunteer.hp
		var target_hp = victim.hp
		var result = await game._deal_damage_result(game.players[0],victim,1,EffectChain.DamageType.PHYSICAL)
		t.check(not result.invalidated and victim.hp == target_hp and volunteer.hp == hp-1 and volunteer.hand_size() == cards-1, "I04 Q16 fixed-player/dragon damage still supports paid Sacrifice: "+str(dragon))
		t.check(game._pending_card_actions.is_empty() and game._choice_prompt_stack.is_empty(), "I04 Q16 ordinary character transfer completes its existing action")
		game._game_over = true
		game.queue_free()
		await t.process_frame
