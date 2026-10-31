extends RefCounted

func fixture(t):
	var game = load("res://Test/i04_gather_cases.gd").new().fixture(t)
	game._nullify_override = func(): return false
	game._zone_pick_override = func(): return "hand"
	return game

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var game = fixture(t)
	var a = game.players[0]
	var b = game.players[1]
	var c = game.players[2]
	# Seed B's own PLAY with Jacky's unlimited Duel; not an upstream turn claim.
	b.general_name = "杰基·斯特朗"
	b.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.QILING_BOW))
	c.equip_card_to_slot("weapon",CardBase.create(CardData.CardSubType.LIANNU))
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	t.check(game._get_duel_targets(b).has(c) and not game.get_trick_targets(b,CardData.CardSubType.DUEL).has(c), "I04 M2 Jacky's unlimited Duel never bypasses the region barrier")
	t.check(game._get_strike_targets(c).has(game.players[3]) and not game.get_trick_targets(b,CardData.CardSubType.BORROWED_SWORD).has(c), "I04 M2 otherwise-armed and legal Borrowed Sword first target is blocked across regions")
	var hand = b.hand_size()
	var serial = game._card_action_serial
	for sub in GameManager.TARGET_TRICKS:
		t.check(not game.get_trick_targets(b,sub).has(c), "I04 single-trick declaration rejects the other region: %s" % CardData.get_type_name(sub))
		if sub == CardData.CardSubType.IRON_CHAIN: continue
		await game.execute_card_on_target(c,sub)
		t.check(b.hand_size() == hand and game._card_action_serial == serial, "I04 forged direct cross-region entry cannot pay or declare: %s" % CardData.get_type_name(sub))
	t.check(not game.get_trick_targets(c,CardData.CardSubType.DISMANTLE).has(b), "I04 M2 ordinary trick region protection is bidirectional")
	var pair: Array[Player] = [a,c]
	await game._execute_iron_chain(pair)
	t.check(b.hand_size() == hand and not a.chained and not c.chained and game._card_action_serial == serial, "I04 two-target Iron Chain rejects the whole mixed-region declaration before payment")
	var roster = game._prep_group_scope(b,CardData.CardSubType.BARBARIAN_INVASION)
	t.check(roster.size() == 4 and roster.has(c), "I04 declaration checks never shrink an AOE's original Prep scope by region")
	var mountains = game.unit_registry.active_units()
	mountains[0].hp = 1
	t.check(not game.get_trick_targets(b,CardData.CardSubType.DISMANTLE).has(c), "I04 wounded mountain retains its declaration barrier")
	# Geometric one-wall fixture; actual mountain death/cost is covered elsewhere.
	mountains[0].hp = 0
	mountains[0].mark_dead()
	game._retire_final_unit(mountains[0])
	t.check(game.get_trick_targets(b,CardData.CardSubType.DISMANTLE).has(c), "I04 one remaining mountain permits the finite alternate route")
	await dispose(t,game)
	game = fixture(t)
	a = game.players[0]
	b = game.players[1]
	hand = a.hand_size()
	var target_hand = b.hand_size()
	await game.execute_card_on_target(b,CardData.CardSubType.DISMANTLE)
	t.check(a.hand_size() == hand-1 and b.hand_size() == target_hand-1 and game._pending_card_actions.is_empty(), "I04 same-region paid Dismantle still resolves and completes normally")
	pair = [a,b]
	await game._execute_iron_chain(pair)
	t.check(a.hand_size() == hand-2 and a.chained and b.chained and game._pending_card_actions.is_empty(), "I04 same-region two-target Iron Chain keeps both declared targets and pays once")
	await dispose(t,game)
	game = fixture(t)
	a = game.players[0]
	# Unit membership fixture, not Jim summoning another general's dragon.
	var dragon = FireDragonState.create_body()
	var id = game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON,dragon,game.players[2])
	var attached = game.fire_dragon_state.attach(id)
	dragon.hand.append(null) # initial attachment must retain the adjudicated empty hand
	var revealed_to: Array[Player] = [a]
	t.check(attached and game.fire_dragon_state.record_use(id,1,revealed_to), "I04 region fixture attaches an initially empty dragon before granting its hand and reveal fact")
	t.check(game._character_targets(a).has(dragon) and not game.get_trick_targets(a,CardData.CardSubType.DISMANTLE).has(dragon), "I04 revealed dragon still inherits its controller's region at declaration")
	t.check(not game.get_trick_targets(dragon,CardData.CardSubType.DISMANTLE).has(a) and game.get_trick_targets(dragon,CardData.CardSubType.DISMANTLE).has(game.players[3]), "I04 dragon source uses its controller's region without adding a spatial vertex")
	await dispose(t,game)
	await yudaxi_cross(t)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func yudaxi_cross(t):
	for gather in [false,true]:
		var game = fixture(t)
		var owner = game.players[0]
		var leo = game.players[2]
		leo.general_name = "里奥·普利威尔"
		for p in game.players:
			p.hand.clear(); p.determined_cards.clear(); p.hp = 4
		owner.hp = 2
		leo.hp = 1
		game._rescue_choice_override = func(_r,_d,_o): return -1
		game._sacrifice_actor_override = func(_p,_target,_n): return false
		var serial = game._card_action_serial
		if gather:
			owner.hand.append(null)
			game._jim_gather_choice_override = func(_p,options,_v): return options.find("lose")
			game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
			t.check(await game._activate_jushan(owner) == 1 and game.players[3].hp == 1 and game.players[4].hp == 1, "I04 Q28 original opposite-side example retains both D/E after global Yudaxi removes Jim")
		else:
			# Seed D's PLAY; real physical payment, damage, rescue and Yudaxi follow.
			game.turn_manager.current_player_idx = 3
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			game.players[3].hand.append(null)
			await game.execute_card_on_target(leo,CardData.CardSubType.STRIKE)
			t.check(game.players[3].hand_size() == 0 and game._card_action_serial == serial+1 and game._pending_card_actions.is_empty(), "I04 Q29 real same-region paid Strike completes after nested cross-region Yudaxi")
		t.check(owner.is_dead() and leo.hp == 1 and leo.hand_size() == 1 and game.players[1].hp == 2, "I04 Q29 Yudaxi affects Jim and B across the two-mountain partition")
		t.check(game.yudaxi.results.size() == 1 and game.yudaxi.results[0].deaths == 1 and game.mountain_space.ids().is_empty() and not game._game_over, "I04 Q29 only Jim's final death contributes X; mountain disappearance adds no deaths")
		await dispose(t,game)

func lan(t):
	var bridge = LanGameBridge.new()
	bridge._enable_mountain_rules_for_tests = true
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 0 else "稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 single-trick declaration adapter starts")
	var helper = load("res://Test/i04_movement_cases.gd").new()
	bridge.submit(0,helper.find(bridge.snapshot(0),"山甲 玩家2→玩家3；山乙 玩家5→玩家1"))
	var game = bridge.game
	game._halt_countdown()
	game._nullify_override = func(): return false
	game._zone_pick_override = func(): return "hand"
	game._target_confirm_override = func(): return 1
	var old_inspect: String = bridge.snapshot(0).targets.get("2","")
	var hand = game.players[0].hand_size()
	var target_hand = game.players[1].hand_size()
	game._enter_targeting_mode(CardData.CardSubType.DISMANTLE)
	var view = bridge.snapshot(0)
	t.check(view.targets.size() == 1 and view.targets.has("1") and not view.targets.has("2"), "I04 real LAN Dismantle offers only its legal same-region opponent")
	t.check(not bridge.submit(0,old_inspect) and game.players[0].hand_size() == hand, "I04 prior inspection token cannot become a paid cross-region declaration")
	var token: String = view.targets.get("1","")
	t.check(token != "" and not bridge.submit(1,token) and bridge.submit(0,token), "I04 valid same-region target command belongs only to its actor")
	t.check(game.players[0].hand_size() == hand-1 and game.players[1].hand_size() == target_hand-1 and game._pending_card_actions.is_empty(), "I04 actual LAN target command completes one paid same-region Dismantle")
	t.check(not bridge.submit(0,token), "I04 completed declaration's target token cannot replay")
	game._enter_iron_chain_mode()
	view = bridge.snapshot(0)
	t.check(view.targets.size() == 2 and view.targets.has("0") and view.targets.has("1") and not view.targets.has("2"), "I04 real LAN Iron Chain retains self and same-region ally but excludes the other region")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
