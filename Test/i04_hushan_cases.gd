extends RefCounted

func fixture(t):
	var game = load("res://Test/i04_initial_cases.gd").new().fixture(t,5,true,func(_p,_o,_v): return 0)
	game._halt_countdown()
	var mountains = game.unit_registry.active_units()
	mountains[0].hp = 2
	mountains[1].hp = 3
	game._jim_mountain_target_override = func(_p,_targets,_valid): return 0
	game._hand_discard_override = func(snapshot,count,_mandatory): return snapshot.defaults(count)
	return game

func dispose(t,game):
	game._game_over = true
	game.queue_free()
	await t.process_frame

func run(t):
	var saved = [GameManager.selected_players,GameManager.selected_mode,GameManager.selected_general,GameManager.random_general,GameManager.random_identity]
	var game = fixture(t)
	var owner = game.players[0]
	var mountains = game.unit_registry.active_units()
	var resource = CardBase.create(CardData.CardSubType.LIANNU)
	owner.hand.clear()
	owner.determined_cards.append(resource) # legal equipment-hand type, not a concrete basic card
	var serial = game._card_action_serial
	t.check(await game._activate_hushan(owner) == 1 and mountains[0].hp == 5 and mountains[1].hp == 3, "I04 Hushan heals only the selected wounded terrain to its maximum")
	t.check(owner.hand_size() == 0 and game.deck._discard.count(resource) == 1 and game._card_action_serial == serial, "I04 Hushan discards the original equipment-hand resource once, without card USE")
	t.check(owner.hp == 6 and owner.max_hp == 6 and turn_used(game,owner), "I04 Hushan costs a card, never substitute HP, and marks the actual PLAY quota")
	owner.hand.append(null)
	game._jim_mountain_target_override = func(_p,_t,_v): return 1
	t.check(await game._activate_hushan(owner) == 0 and owner.hand_size() == 1 and mountains[1].hp == 3, "I04 Hushan cannot activate a second time in the same PLAY")
	# Real standalone PLAY frame after seeded next-stage context; no upstream
	# Max grant/payment is claimed by this phase-specific regression.
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_play(0)
	game._do_play(1)
	t.check(await game._activate_hushan(owner) == 1 and mountains[1].hp == 5 and owner.hand_size() == 0, "I04 Hushan has its own once-per-PLAY quota in a granted phase")
	game.end_play_phase()
	t.check(frame.completed and game._jim_mountain_skill_pending.is_empty(), "I04 Hushan completes without keeping a granted phase or skill lease open")
	await dispose(t,game)
	game = fixture(t)
	owner = game.players[0]
	mountains = game.unit_registry.active_units()
	mountains[0].hp = 5
	var full_hand = owner.hand_size()
	game._mountain_rules_enabled = false
	game._open_player_detail(owner)
	var popup = game._detail_popup_root.get_child(0)
	t.check(popup._skills_container.get_children().all(func(node): return not node is Button) and GeneralData.get_implementation_status(owner.general_name) == "prototype", "I04 explicit disabled rules hide active Hushan even after general publication")
	game._mountain_rules_enabled = true
	t.check(await game._activate_hushan(owner) == 1 and mountains[0].hp == 5 and owner.hand_size() == full_hand-1, "I04 Q23 full mountain accepts one genuine card fee without extra recovery")
	t.check(turn_used(game,owner) and await game._activate_hushan(owner) == 0 and owner.hand_size() == full_hand-1, "I04 Q23 full mountain consumes the same once-per-PLAY quota")
	await dispose(t,game)
	game = fixture(t)
	owner = game.players[0]
	mountains = game.unit_registry.active_units()
	var hand = owner.hand_size()
	game._jim_mountain_target_override = func(_p,targets,_v): return targets.size()
	t.check(await game._activate_hushan(owner) == game.CHOICE_INVALID and owner.hand_size() == hand and not turn_used(game,owner), "I04 Hushan invalid target index is technical invalidation, not voluntary cancellation")
	game._jim_mountain_target_override = func(_p,_t,_v): return -1
	t.check(await game._activate_hushan(owner) == 0 and owner.hand_size() == hand and not turn_used(game,owner), "I04 Hushan optional target cancellation neither pays nor uses the quota")
	game._jim_mountain_target_override = func(_p,_t,_v): return 0
	game._hand_discard_override = func(_s,_c,_m): return []
	t.check(await game._activate_hushan(owner) == 0 and mountains[0].hp == 2 and not turn_used(game,owner), "I04 Hushan refusing the optional card cost leaves damage and quota unchanged")
	game._hand_discard_override = func(snapshot,count,_m): return snapshot.defaults(count)
	t.check(await game._activate_hushan(owner) == 1 and owner.hand_size() == hand-1, "I04 Hushan remains usable after cancellation, with one genuine payment")
	await dispose(t,game)
	for fault in ["phase","reset","target","restore","free","reentry"]:
		game = fixture(t)
		owner = game.players[0]
		mountains = game.unit_registry.active_units()
		var target: Player = mountains[0]
		hand = owner.hand_size()
		var nested: Array = []
		if fault == "free":
			game._jim_mountain_target_override = func(_p,targets,_valid):
				targets[0].queue_free()
				await t.process_frame
				return 0
		game._hand_discard_override = func(snapshot,count,_m):
			var manager: GameManager = snapshot.owner.get_parent()
			if fault == "phase": manager.turn_manager.current_phase = TurnManager.Phase.DRAW
			if fault == "reset": manager.reset_game_over_state()
			if fault == "target": target.hp = 0; target.mark_dead(); manager._retire_final_unit(target)
			if fault == "restore": manager._do_sage_save(snapshot.owner) # technical fault injection only
			if fault == "reentry": nested.append(await manager._activate_hushan(snapshot.owner))
			return snapshot.defaults(count)
		var result = await game._activate_hushan(owner)
		t.check(result == (1 if fault == "reentry" else game.CHOICE_INVALID) and game._jim_mountain_skill_pending.is_empty(), "I04 Hushan invalidation/reentry releases only its own skill lease: "+fault)
		if fault == "reentry": t.check(nested == [0] and owner.hand_size() == hand-1 and target.hp == 5, "I04 Hushan reentry cannot duplicate cost or recovery")
		elif fault == "restore": t.check(owner.hand_size() == 4 and target.unit_disappeared and not turn_used(game,owner), "I04 Hushan cannot heal a disappeared original target after general restoration")
		elif fault == "free": t.check(owner.hand_size() == hand and not turn_used(game,owner), "I04 Hushan freed target cannot be dereferenced or charged by an old selection")
		else: t.check(owner.hand_size() == hand and target.hp <= 2 and not turn_used(game,owner), "I04 Hushan stale fee choice cannot consume cards or heal an old target")
		await dispose(t,game)
	await lan(t)
	GameManager.selected_players=saved[0]
	GameManager.selected_mode=saved[1]
	GameManager.selected_general=saved[2]
	GameManager.random_general=saved[3]
	GameManager.random_identity=saved[4]

func turn_used(game,owner) -> bool:
	return game.turn_manager.phase_skill_used("hushan",owner.seat_index)

func lan(t):
	var bridge = LanGameBridge.new()
	bridge._enable_mountain_rules_for_tests = true
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for seat in 5: roster.append({"name":"P%d"%seat,"general":"吉姆·芒顿" if seat == 0 else "稻草人"})
	t.check(bridge.start(roster,GameModes.FREE_FOR_ALL,AiActionPacer.Speed.FAST), "I04 Hushan actual human adapter starts")
	bridge.submit(0,bridge.snapshot(0).controls[0].id)
	var game = bridge.game
	game._halt_countdown()
	var owner = game.players[0]
	var mountains = game.unit_registry.active_units()
	mountains[0].hp = 2
	mountains[1].hp = 3
	var hand = owner.hand_size()
	game._open_player_detail(owner)
	var menu = bridge.snapshot(0)
	var skill_token = ""
	for button in menu.controls:
		if "【护山】" in button.text: skill_token = button.id
	t.check(not skill_token.is_empty() and not bridge.submit(1,skill_token) and bridge.submit(0,skill_token), "I04 Hushan launches from its gated detail-menu button with actor ownership")
	var view = bridge.snapshot(0)
	var target_token = ""
	for button in view.controls:
		if button.text.begins_with("山1"): target_token = button.id
	t.check(not target_token.is_empty() and bridge.snapshot(1).controls.is_empty() and not bridge.submit(1,target_token), "I04 Hushan target selection is private to its actor")
	t.check(bridge.submit(0,target_token), "I04 Hushan real opaque target selection opens the existing fee picker")
	view = bridge.snapshot(0)
	var card_token = ""
	for button in view.controls:
		if "任意牌" in button.text: card_token = button.id; break
	t.check(not card_token.is_empty() and bridge.submit(0,card_token), "I04 Hushan actor selects an original arbitrary hand card through LAN controls")
	view = bridge.snapshot(0)
	var confirm = ""
	for button in view.controls:
		if button.text == "确认弃牌" and not button.disabled: confirm = button.id
	t.check(not confirm.is_empty() and not bridge.submit(1,confirm) and bridge.submit(0,confirm), "I04 Hushan fee confirmation checks input ownership")
	t.check(owner.hand_size() == hand-1 and mountains[0].hp == 5 and mountains[1].hp == 3 and turn_used(game,owner), "I04 Hushan real menu/target/card/confirm commands finish one heal and one payment")
	t.check(not bridge.submit(0,target_token) and not bridge.submit(0,confirm), "I04 Hushan old target/fee tokens cannot replay")
	game._game_over = true
	bridge.queue_free()
	await t.process_frame
