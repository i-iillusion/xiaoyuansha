extends RefCounted
const Farming = preload("res://Test/i05_david_farming_cases.gd")

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	await payments(t)
	await invalidation(t)
	await drawing(t)
	await granted(t)
	await native(t)
	for seat in [0, 1]:
		for mode in ["confirm", "cancel", "timeout", "restore"]:
			await bridge_case(t, seat, mode)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func payments(t):
	for kind in ["blank", "concrete", "mixed"]:
		var game = Farming.new().fixture(t)
		var p = game.players[0]
		p.farm_empty_fields = 2
		var a = CardBase.create(CardData.CardSubType.LIANNU)
		var b = CardBase.create(CardData.CardSubType.PEACH)
		if kind == "blank": p.hand.assign([null, null, null, null])
		elif kind == "concrete": p.hand.assign([a, b, null, null])
		else: p.hand.assign([null, null, null]); p.determined_cards.append(a)
		game._hand_discard_override = func(_snapshot, _n, mandatory):
			t.check(not mandatory, "I05b upgrade cost stays voluntary")
			return [0, 1] if kind != "mixed" else [0, 3]
		var serial = game._card_action_serial
		t.check(await game._activate_farming_upgrade(p) == 1 and p.hand_size() == 2 and p.farm_empty_fields == 1 and p.farm_good_fields == 1, "I05b two original hand cards upgrade exactly one field: " + kind)
		if kind != "blank":
			t.check(game.deck._discard.count(a) == 1 and (kind == "mixed" or game.deck._discard.count(b) == 1), "I05b upgrade discards selected concrete original resources once")
		game._hand_discard_override = func(snapshot, n, _mandatory): return snapshot.defaults(n)
		t.check(await game._activate_farming_upgrade(p) == 1 and p.farm_empty_fields == 0 and p.farm_good_fields == 2 and p.hand_size() == 0, "I05b another upgrade remains legal in the same PLAY; no invented phase quota")
		t.check(game._card_action_serial == serial and p.farm_hand_actions == 0 and game._farming_upgrade_pending.is_empty(), "I05b fees create neither USE/RESPONSE nor new fields and release their lease")
		await Farming.new().dispose(t, game)
	var game = Farming.new().fixture(t)
	var p = game.players[0]
	p.hand.assign([null, null])
	p.farm_empty_fields = 1
	game._hand_discard_override = func(_s, _n, _m): return []
	t.check(await game._activate_farming_upgrade(p) == 0 and p.hand_size() == 2 and p.farm_empty_fields == 1, "I05b optional fee cancellation leaves cards and field intact")
	game._hand_discard_override = func(s, n, _m): return s.defaults(n)
	t.check(await game._activate_farming_upgrade(p) == 1 and p.farm_good_fields == 1, "I05b upgrade can be retried after cancellation")
	for fault in ["no_field", "one_card", "wrong_actor", "outside_play", "disabled"]:
		p.farm_empty_fields = 1
		p.hand.assign([null, null])
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game.turn_manager.play_actor_idx = -1
		game._david_rules_enabled = true
		if fault == "no_field": p.farm_empty_fields = 0
		if fault == "one_card": p.hand.pop_back()
		if fault == "wrong_actor": game.turn_manager.play_actor_idx = 1
		if fault == "outside_play": game.turn_manager.current_phase = TurnManager.Phase.DRAW
		if fault == "disabled": game._david_rules_enabled = false
		var count = p.hand_size()
		t.check(await game._activate_farming_upgrade(p) == 0 and p.hand_size() == count and p.farm_good_fields == 1, "I05b upgrade entry revalidates eligibility: " + fault)
	await Farming.new().dispose(t, game)

func invalidation(t):
	for fault in ["phase", "empty", "good", "restore", "role", "disabled", "reset", "stale_hand", "reentry"]:
		var game = Farming.new().fixture(t)
		var p = game.players[0]
		p.hand.assign([null, null])
		p.farm_empty_fields = 1
		var nested: Array = []
		game._hand_discard_override = func(snapshot, count, _mandatory):
			if fault == "phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
			if fault == "empty": p.farm_empty_fields = 2
			if fault == "good": p.farm_good_fields = 1
			if fault == "restore": p.restore_game_start_state()
			if fault == "role": p.general_name = "稻草人"
			if fault == "disabled": game._david_rules_enabled = false
			if fault == "reset": game.reset_game_over_state()
			if fault == "stale_hand": p.hand.append(null)
			if fault == "reentry": nested.append(await game._activate_farming_upgrade(p))
			return snapshot.defaults(count)
		var result = await game._activate_farming_upgrade(p)
		t.check(result == (1 if fault == "reentry" else game.CHOICE_INVALID) and game._farming_upgrade_pending.is_empty(), "I05b stale/reentrant upgrade releases only its own lease: " + fault)
		if fault == "reentry":
			t.check(nested == [0] and p.hand_size() == 0 and p.farm_good_fields == 1, "I05b recursive activation cannot double-charge or convert a second field")
		else:
			t.check(p.hand_size() == (3 if fault == "stale_hand" else 2) and p.farm_good_fields == (1 if fault == "good" else 0), "I05b invalid selection never spends new cards or converts new state: " + fault)
		await Farming.new().dispose(t, game)

func drawing(t):
	for fields in [0, 1, 3]:
		for granted in [false, true]:
			var game = Farming.new().fixture(t)
			var p = game.players[0]
			p.farm_good_fields = fields
			game.turn_manager.supply_shortage_active = true
			t.check(await game._draw_phase_cards(p, not granted) and p.hand_size() == 2 + fields - (0 if granted else 1), "I05b good fields add only phase draws, preserving supply/granted DRAW behavior")
			t.check(game.turn_manager.supply_shortage_active == granted and p.farm_good_fields == fields and p.farm_empty_fields == 0, "I05b extra phase draws neither spend fields nor consume source supply in a grant")
			var before = p.hand_size()
			game._draw_blank_cards(p, 2)
			t.check(p.hand_size() == before + 2 and p.farm_hand_actions == 0 and game._card_action_serial == 0, "I05b unrelated bonus draws do not apply good fields or create card actions")
			await Farming.new().dispose(t, game)

func granted(t):
	for option in [1, 2]:
		var game = Farming.new().fixture(t)
		var source = game.players[0]
		var actor = game.players[1]
		source.general_name = "麦克斯·欧尼斯特"
		actor.general_name = "大卫·法米尔"
		actor.hand.assign([null, null] if option == 2 else [])
		actor.determined_cards.clear()
		actor.farm_empty_fields = 1
		actor.farm_good_fields = 2 if option == 1 else 0
		game.turn_manager.current_phase = TurnManager.Phase.START
		game.turn_manager.supply_shortage_active = true
		game._meiyong_override = func(): return true
		game._meiyong_option_override = func(): return option
		game._meiyong_target_override = func(): return actor
		game._hand_discard_override = func(s, n, _m): return s.defaults(n)
		var source_hand = source.hand_size()
		if option == 2:
			var action = func():
				t.check(game._play_actor() == actor and game.turn_manager.current_player_idx == 0, "I05b real Max gift retains source turn and recipient PLAY")
				t.check(await game._activate_farming_upgrade(actor) == 1 and actor.farm_good_fields == 1 and actor.hand_size() == 0, "I05b actual Max-granted PLAY permits normal voluntary field upgrade")
				game.end_play_phase()
			action.call_deferred()
		var result = await game._maybe_meiyong(source)
		t.check(result == 1 and game.turn_manager.current_phase == TurnManager.Phase.START and game.turn_manager.current_player_idx == 0 and source.hand_size() == source_hand + 1, "I05b Max gift completes once and resumes source START with its ordinary draw")
		t.check(actor.farm_hand_actions == 0 and game._card_action_serial == 0 and game._meiyong_execution_owner == -1, "I05b genuine gifted stage adds neither hand USE nor a fabricated owner turn")
		if option == 1:
			t.check(actor.hand_size() == 4 and actor.farm_good_fields == 2 and game.turn_manager.supply_shortage_active, "I05b actual gifted DRAW adds two good fields without consuming source supply")
		await Farming.new().dispose(t, game)

func native(t):
	var game = Farming.new().fixture(t)
	game.lan_enabled = false
	var p = game.players[0]
	p.hand.assign([null, null])
	p.farm_empty_fields = 1
	game._open_player_detail(p)
	var popup = game._detail_popup_root.get_child(0)
	var buttons = popup._skills_container.get_children().filter(func(n): return n is Button and "【种田】" in n.text)
	t.check(buttons.size() == 1 and popup._marks_container.get_child(0).text == "空田：1  好田：0", "I05b native gated detail shows the actual upgrade and field resources")
	if not buttons.is_empty(): buttons[0].pressed.emit()
	await t.process_frame
	var prompts = game.get_node("UI").get_children().filter(func(n): return n is HandDiscardPrompt and not n.is_queued_for_deletion())
	t.check(prompts.size() == 1, "I05b native skill button opens the real two-card payment picker")
	var chosen: Array[int] = [0, 1]
	if not prompts.is_empty(): prompts[0].submit(chosen)
	for i in 3: await t.process_frame
	t.check(p.hand_size() == 0 and p.farm_good_fields == 1, "I05b native UI callback completes exactly one upgrade")
	await Farming.new().dispose(t, game)

func token(bridge, seat, text):
	for control in bridge.snapshot(seat).controls:
		if control.text == text and not control.disabled: return control.id
	return ""

func bridge_case(t, seat, mode):
	var bridge = LanGameBridge.new()
	t.root.add_child(bridge)
	var roster: Array[Dictionary] = []
	for n in 3: roster.append({"name": "P%d" % n, "general": "稻草人"})
	t.check(bridge.start(roster, GameModes.FREE_FOR_ALL, AiActionPacer.Speed.FAST), "I05b actual Bridge starts before private David boundary fixture")
	var game = bridge.game
	game._halt_countdown()
	game._david_rules_enabled = true
	var p = game.players[seat]
	p.general_name = "大卫·法米尔"
	p.capture_game_start_state()
	p.farm_empty_fields = 1
	p.hand.assign([null, null])
	p.determined_cards.clear()
	# Actual standalone phase machinery, not a fabricated "owner is the recipient" turn.
	var frame: Dictionary = {}
	if seat == 1:
		game.turn_manager.current_phase = TurnManager.Phase.START
		frame = game.turn_manager.begin_standalone_play(seat)
		game._do_play(0)
		game._halt_countdown()
	game._set_input_player(p)
	game._open_player_detail(p)
	var skill = ""
	for control in bridge.snapshot(seat).controls:
		if "【种田】" in control.text: skill = control.id
	t.check(not skill.is_empty() and not bridge.submit(1 - seat, skill) and bridge.submit(seat, skill), "I05b native detail is exposed as actor-owned opaque Bridge command")
	var picks: Array = []
	for control in bridge.snapshot(seat).controls:
		if "任意牌" in control.text: picks.append(control.id)
	t.check(picks.size() == 2 and bridge.snapshot(1 - seat).controls.is_empty(), "I05b two-card payment window belongs only to the actual operator")
	if mode == "confirm":
		for i in 2:
			var selected = ""
			for control in bridge.snapshot(seat).controls:
				if "任意牌" in control.text and not control.pressed: selected = control.id; break
			t.check(not selected.is_empty() and bridge.submit(seat, selected), "I05b real Bridge hand-card toggle updates the current selection")
		var confirm = token(bridge, seat, "确认弃牌")
		t.check(not confirm.is_empty() and not bridge.submit(1 - seat, confirm) and bridge.submit(seat, confirm), "I05b only actor can confirm real two-card payment")
		t.check(not bridge.submit(seat, confirm), "I05b consumed fee token cannot replay")
	elif mode == "cancel":
		var cancel = token(bridge, seat, "取消发动")
		t.check(not cancel.is_empty() and bridge.submit(seat, cancel), "I05b real Bridge can decline the voluntary upgrade fee")
	elif mode == "timeout":
		# Existing timer callback, not a claim to have naturally exhausted 60 seconds.
		game._choice_prompt_stack.back().answer.submit(-1)
	else:
		p.restore_game_start_state()
	for i in 4: await t.process_frame
	t.check(p.hand_size() == (0 if mode == "confirm" else 2) and p.farm_good_fields == (1 if mode == "confirm" else 0), "I05b Bridge confirmation/cancel/timeout/restore preserves exact payment result: " + mode)
	t.check(game._farming_upgrade_pending.is_empty() and not bridge.submit(seat, skill) and (picks.is_empty() or not bridge.submit(seat, picks[0])), "I05b old menu/hand tokens and skill lease cannot survive the completed choice")
	if seat == 1:
		t.check(game.turn_manager.current_player_idx == 0 and p.farm_hand_actions == 0 and game.turn_manager.complete_standalone_phase(frame) and game.turn_manager.current_phase == TurnManager.Phase.START, "I05b granted PLAY upgrades return to original START without changing owner or farming count")
	game._game_over = true
	bridge.queue_free()
	for i in 3: await t.process_frame
