extends RefCounted

func configure(game):
	load("res://Test/i04_burning_interception_cases.gd").new().prepare(game)
	var jim = game.players[4]
	jim.general_name = "吉姆·芒顿"
	jim.max_hp = 6
	jim.hp = 6
	# Q41 boundary fixture: A -> first -> center -> B. Actual initial skill
	# placement and natural spatial dispatch are covered in separate tasks.
	var first = game._spawn_mountain_at(jim,0,1)
	var center = game._spawn_mountain_at(jim,game.unit_registry.id_for(first),1)
	game.players[1].hp = 1
	game.players[0].hand.append(null)
	game.players[2].hand.append(null)
	load("res://Test/i04_burning_interception_cases.gd").new().put_fire(center)
	return center

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
	var center = configure(game)
	var offered: Array = []
	game._rescue_choice_override = func(p,_dying,options):
		offered.append(p.seat_index)
		return CardData.CardSubType.PEACH if options.has(CardData.CardSubType.PEACH) else -1
	var frame = [game.turn_manager.turn_id,game.turn_manager.phase_id,game.turn_manager.current_player_idx,game.turn_manager.current_unit_id]
	game.turn_manager.use_card("duel")
	t.check(await game._run_judgment(center,false), "I04 Q41 mountain judgment and actual rescue finish")
	t.check(offered == [2] and game.players[2].hand_size() == 0 and game.players[0].hand_size() == 1 and game.players[1].hp == 1, "I04 Q41 C pays Peach before A; empty-handed B is passed normally")
	t.check(center.hp == 3 and game.deck._discard.size() == 2 and game._card_action_serial == 1 and game._pending_card_actions.is_empty(), "I04 Q41 fire and one real rescue each settle once without a terrain card USE")
	t.check(frame == [game.turn_manager.turn_id,game.turn_manager.phase_id,game.turn_manager.current_player_idx,game.turn_manager.current_unit_id] and game.turn_manager._get_turn_count("duel",0) == 1 and ActorIdentity.key_for(game.players,game.unit_registry,center) == null, "I04 Q41 spatial rescue origin never changes player quotas, turn frame or actor identity")
	t.check(game._mountain_judgment_contexts.is_empty() and game._rescue_order_for_turn()[0] == game.players[0], "I04 completed judgment retires only its rescue origin")
	game.players[3].hp = 1
	await game._deal_damage_result(null,game.players[3],1,EffectChain.DamageType.PHYSICAL)
	t.check(offered == [2,0] and game.players[0].hand_size() == 0 and game.players[3].hp == 1, "I04 ordinary subsequent damage returns to current-player-first rescue")
	await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)
	await invalidated(t)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func invalidated(t):
	for mode in ["phase","reset","reentry"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t,5,GameModes.FREE_FOR_ALL)
		var center = configure(game)
		var reentered: Array = []
		game._nullify_override = func():
			if mode == "phase": game.turn_manager.current_phase = TurnManager.Phase.END
			elif mode == "reset": game.reset_game_over_state()
			else: reenter(game,center,reentered)
			return false
		game._rescue_choice_override = func(_p,_d,_o): return CardData.CardSubType.PEACH
		var complete = await game._run_judgment(center,false)
		t.check(complete == (mode == "reentry") and game._mountain_judgment_contexts.is_empty(), "I04 terrain rescue context cleans up on completion, stale phase or reset: "+mode)
		if mode == "reentry": t.check(reentered == [false] and game.players[0].hand_size() == 1 and game.players[2].hand_size() == 0, "I04 duplicate same-carrier judgment cannot replace the parent origin or pay twice")
		else: t.check(center.hp == 5 and game.players[1].hp == 1 and game.players[0].hand_size() == 1 and game.players[2].hand_size() == 1, "I04 expired judgment cannot damage or spend rescue cards")
		await load("res://Test/i04_burning_interception_cases.gd").new().dispose(t,game)

func reenter(game,center,result):
	result.append(await game._run_judgment(center,false))

func lan(t):
	var bridge = load("res://Test/i04_aoe_region_cases.gd").new().bridge_fixture(t,4)
	var game = bridge.game
	var center = configure(game)
	game._rescue_choice_override = Callable()
	var result: Array = []
	var drive = func(): result.append(await game._run_judgment(center,false))
	drive.call()
	for i in 3: await t.process_frame
	var token = load("res://Test/i04_movement_cases.gd").new().find(bridge.snapshot(2),"使用【桃】")
	t.check(token != "" and bridge.input_owner() == 2 and bridge.snapshot(0).controls.is_empty() and game.players[1].is_dying(), "I04 Q41 actual human rescue first grants C input, not previous actor A")
	t.check(not bridge.submit(0,token) and bridge.submit(2,token), "I04 Q41 only C can pay the pending remote rescue Peach")
	for i in 3: await t.process_frame
	t.check(result == [true] and game.players[1].hp == 1 and game.players[0].hand_size() == 1 and game.players[2].hand_size() == 0, "I04 Q41 actual Bridge payment follows terrain-position rescue order")
	t.check(bridge.input_owner() == 0 and bridge.acting_unit() == "" and game._mountain_judgment_contexts.is_empty() and not bridge.submit(2,token), "I04 Q41 completed rescue returns suspended player's input and rejects replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
