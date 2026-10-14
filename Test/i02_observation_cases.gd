extends RefCounted

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	for action in ["accept", "disappear", "close"]:
		var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.FREE_FOR_ALL)
		game.lan_enabled = true
		var helper = load("res://Test/i02_lifecycle_cases.gd").new()
		var owner = game.players[3]
		var dragon = helper.add_unit(game, UnitRegistry.Kind.FIRE_DRAGON, owner)
		var mountain = helper.add_unit(game, UnitRegistry.Kind.MOUNTAIN, owner)
		dragon.hand.assign([null, null])
		var original = CardBase.create(CardData.CardSubType.LIANNU)
		game.players[2].equip_card_to_slot("weapon", original)
		dragon.determined_cards.append(game.players[2].remove_equipment("weapon"))
		var id = game.unit_registry.id_for(dragon)
		var bridge = LanGameBridge.new()
		t.root.add_child(bridge)
		bridge.game = game
		game._set_input_player(dragon)
		t.check(game._input_seat == 3 and game._is_human(dragon) and not game._is_human(mountain), "I02d intelligent input resolves to controller, normal unit has no operator")
		var state = bridge.snapshot(3)
		state.match = state.history.match
		t.check(state.players.size() == 5 and state.space == [0,1,2,3,4] and state.units.size() == 2, "I02d separate unit wire rows never enter player space or roles")
		t.check(state.units[0].own_cards.size() == 3 and bridge.snapshot(1).units[0].own_cards.is_empty(), "I02d only controller sees unit hand values")
		t.check(not state.units[0].has("identity") and not state.units[1].has("identity") and UnitObservation.valid(state.units,5,3), "I02d unit faction is not an independent leaked identity")
		var receiver = LanSession.new()
		t.root.add_child(receiver)
		receiver.mode = state.mode
		receiver.count = state.count
		receiver._view_match = state.match
		receiver.history.reset(state.match)
		receiver._receive_state(state)
		t.check(not receiver.latest.is_empty(), "I02d actual receiver accepts valid separate unit state")
		for bad in ["missing", "duplicate", "private", "controller", "identity", "sub", "summoner", "cap"]:
			var changed = state.duplicate(true)
			match bad:
				"missing": changed.erase("units")
				"duplicate": changed.units.append(changed.units[0].duplicate(true))
				"private": changed.actor = 1
				"controller": changed.units[0].controller = 2
				"identity": changed.units[0].identity = "反贼"
				"sub": changed.units[0].own_cards[0].sub = 99999
				"summoner": changed.units[0].summoner = 5
				"cap":
					for index in 2:
						var extra = changed.units[1].duplicate(true)
						extra.id = "unit:extra:%d" % index
						changed.units.append(extra)
			receiver.latest = {}
			var history_before = receiver.history.packet(0)
			receiver._receive_state(changed)
			t.check(receiver.latest.is_empty() and receiver.history.packet(0) == history_before, "I02d malformed/private unit packet rejected before history: " + bad)
		var room = load("res://Scenes/LanRoom.tscn").instantiate()
		t.root.add_child(room)
		room._state_changed(state)
		var board = room.body.get_node("UnitBoard")
		t.check(board.get_child_count() == 2 and board.get_child(0) is Label and board.get_child(0).get_meta("unit") == id, "I02d actual client renders separate readonly unit board")
		t.check("连弩" in board.get_child(0).text and "任意牌" in board.get_child(0).text, "I02d controller can read its real concrete/blank unit hand")
		room._state_changed(bridge.snapshot(1))
		t.check(not "连弩" in room.body.get_node("UnitBoard").get_child(0).text, "I02d other client unit panel does not leak unit hand name")
		var answers: Array = []
		var wait = func(): answers.append(await game._show_choice_popup("单位控制者窗口验证", ["确认", "取消"], func(): return game.unit_registry.contains_active(dragon), false))
		wait.call()
		await t.process_frame
		var choice = bridge.snapshot(3).controls.filter(func(control): return control.text == "确认")[0]
		t.check(bridge.input_owner() == 3 and bridge.snapshot(1).controls.is_empty() and not bridge.submit(1,choice.id), "I02d real unit-related choice is controller-owned, cannot impersonate")
		if action == "accept": t.check(bridge.submit(3,choice.id), "I02d controller submits actual choice")
		elif action == "disappear":
			owner.hp = 1
			await game._deal_damage(game.players[0], owner, 1, EffectChain.DamageType.PHYSICAL)
			t.check(not bridge.submit(3,choice.id) and bridge.snapshot(3).units.is_empty(), "I02d real owner final death removes rows and invalidates old unit choice token")
		else: game._choice_prompt_stack.back().overlay.queue_free()
		for frame in 3: await t.process_frame
		t.check(answers == [0 if action == "accept" else GameManager.CHOICE_INVALID] and game._choice_prompt_stack.is_empty(), "I02d accept/attached disappearance/technical close resolve independently")
		t.check(not bridge.submit(3,choice.id), "I02d consumed or obsolete unit choice token cannot answer again")
		var extra = Player.new()
		extra.identity = ""
		t.check(game._register_unit_body(UnitRegistry.Kind.FIRE_DRAGON, extra, owner).is_empty(), "I02d same summoner second dragon or dead summoner rejected")
		extra.free()
		if action != "disappear":
			var second = helper.add_unit(game, UnitRegistry.Kind.MOUNTAIN, game.players[2])
			var third = Player.new()
			third.identity = ""
			t.check(game.unit_registry.contains_active(second) and game._register_unit_body(UnitRegistry.Kind.MOUNTAIN,third,game.players[1]).is_empty(), "I02d global two-mountain membership cap enforced")
			third.free()
		var retained = game.unit_registry
		game._game_over = true
		game.queue_free()
		room.queue_free()
		bridge.queue_free()
		receiver.queue_free()
		for frame in 2: await t.process_frame
		t.check(retained.all_bodies().is_empty() and retained.entry(id).is_empty(), "I02d scene exit clears retained unit references/IDs")
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
