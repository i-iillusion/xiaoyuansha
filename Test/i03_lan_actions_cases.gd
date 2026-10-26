extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/i03_egg_cases.gd").new().fixture(t)
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.players[0].hp = 3
	game._sync_all_ui()
	t.check(game._self_info_panel.get_meta("prep_indicator").text == "火龙蛋:1", "I03 native Chris panel shows actual egg resource")
	var dragon = load("res://Test/i03_summon_cases.gd").new().seed_dragon(game, game.players[0])
	var id = game.unit_registry.id_for(dragon)
	dragon.hand.append(null)
	var original = CardBase.create(CardData.CardSubType.LIANNU)
	game.players[2].equip_card_to_slot("weapon", original)
	dragon.determined_cards.append(game.players[2].remove_equipment("weapon"))
	game._sync_unit_board()
	var native = game._native_unit_board
	t.check(native.visible and native._list.get_child(0).get_meta("player") == dragon and native._list.get_child_count() == 3, "I03 native unit surface exposes actual body and own concrete card without spatial seat")
	game.lan_enabled = true
	game.turn_manager.current_unit_id = id
	game._set_input_player(dragon)
	game._sync_all_ui() # Prepared phase must refresh the actual body's hand availability.
	var bridge = LanGameBridge.new()
	t.root.add_child(bridge)
	bridge.game = game
	var state = bridge.snapshot(0)
	t.check(state.players[0].eggs == game.players[0].fire_dragon_eggs, "I03 wire exposes actual Chris egg resource count")
	t.check(state.acting_unit == id and state.turn == 0 and state.units[0].own_cards.size() == 2 and state.players.size() == 5 and state.space == [0,1,2,3,4], "I03 wire actual unit separate from fixed turn/controller and spatial roster")
	t.check(bridge.snapshot(1).units[0].own_cards.is_empty() and state.units[0].gender == "none", "I03 wire unit privacy and explicit no gender")
	var receiver = LanSession.new()
	t.root.add_child(receiver)
	receiver.mode = state.mode
	receiver.count = state.count
	state.match = state.history.match
	receiver._view_match = state.match
	receiver.history.reset(state.match)
	receiver._receive_state(state)
	t.check(not receiver.latest.is_empty(), "I03 actual receiver accepts acting unit")
	for bad in ["missing", "integer", "unknown", "flip", "chain", "gender"]:
		var changed = state.duplicate(true)
		match bad:
			"missing": changed.erase("acting_unit")
			"integer": changed.acting_unit = 0
			"unknown": changed.acting_unit = "unit:unknown"
			"flip": changed.units[0].facedown = 1
			"chain": changed.units[0].chained = "false"
			"gender": changed.units[0].gender = "unknown"
		receiver.latest = {}
		var history = receiver.history.packet(0)
		receiver._receive_state(changed)
		t.check(receiver.latest.is_empty() and receiver.history.packet(0) == history, "I03 malformed acting-unit state rejected before history: " + bad)
	var play = state.controls.filter(func(button): return button.text == "出牌")[0]
	t.check(not bridge.submit(1, play.id) and bridge.submit(0, play.id), "I03 only unit controller opens actual Play selector through opaque command")
	var selectors = game.get_node("UI").get_children().filter(func(node): return node is CardSelector)
	t.check(selectors.size() == 1 and selectors[0].player == dragon, "I03 LAN Play binds actual unit hand, not owner hand")
	selectors[0].queue_free()
	await t.process_frame
	# Fixed B cannot select hidden F. Actual unit USE then reveals only B.
	game.turn_manager.current_unit_id = ""
	game.turn_manager.current_player_idx = 1
	game._set_input_player(game.players[1])
	game._enter_targeting_mode(CardData.CardSubType.STRIKE)
	t.check(not bridge.snapshot(1).targets.has(id), "I03 hidden unit has no target token from B")
	game._exit_targeting_mode()
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_unit_id = id
	game._set_input_player(dragon)
	game._dodge_override = func(): return false
	game._sacrifice_override = func(): return false
	await game.execute_card_on_target(game.players[1], CardData.CardSubType.STRIKE)
	t.check(dragon.hand_size() == 1 and dragon.determined_cards == [original] and game.fire_dragon_state.is_revealed_to(id, game.players[1]), "I03 actual unit USE pays own arbitrary card and reveals B, retaining concrete original")
	game.turn_manager.current_unit_id = ""
	game.turn_manager.current_player_idx = 1
	game._set_input_player(game.players[1])
	game._target_confirm_override = func(): return 1
	game._enter_targeting_mode(CardData.CardSubType.STRIKE)
	state = bridge.snapshot(1)
	var token: String = state.targets.get(id, "")
	var hp = dragon.hp
	t.check(not token.is_empty() and bridge.submit(1, token), "I03 revealed unit target resolves string ID to actual body")
	await t.process_frame
	t.check(dragon.hp == hp - 1 and game.players[0].hp == 3 and not bridge.submit(1, token), "I03 unit target takes damage, not owner, and old token cannot replay")
	var unit_hp_logs = game.action_history.entries.filter(func(event): return event.kind == "hp" and event.details.get("actor_unit", "") == id)
	t.check(not unit_hp_logs.is_empty() and unit_hp_logs.back().actor == -1, "I03 public unit HP log carries safe unit ID, not controller actor")
	game._exit_targeting_mode()
	var stale: String = bridge.snapshot(1).targets.get(id, "")
	game.players[0].mark_dead()
	game._remove_summoner_units(game.players[0])
	t.check(not bridge.submit(1, stale) and bridge.snapshot(1).units.is_empty(), "I03 disappearance removes target rows and invalidates unit command")
	game._game_over = true
	game.queue_free()
	bridge.queue_free()
	receiver.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
