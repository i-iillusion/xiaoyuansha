extends RefCounted
const SIMBA = "辛巴·古德曼"

func fixture(t):
	var game = load("res://Test/i05_simba_judgment_cases.gd").new().fixture(t)
	game.players[0].simba_good_deeds_enabled = true
	game.players[0].capture_game_start_state()
	return game

func dispose(t, game):
	await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	await active(t)
	await rescues(t)
	await stale(t)
	await bridge(t)
	await bridge_reclaim(t)
	await granted(t)
	await nested_invalid(t)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]

func active(t):
	for concrete in [false, true]:
		var game = fixture(t)
		var owner = game.players[0]
		var target = game.players[1]
		target.max_hp = 4; target.hp = 4
		var card = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
		if concrete: owner.determined_cards.append(card)
		else: owner.hand.append(null)
		var actions: Array = []
		game.card_action_committed.connect(func(a): actions.append(a))
		game._simba_deed_choice_override = func(_p, candidates, reclaim, valid):
			t.check(valid.call() and not reclaim and not candidates.has(owner), "I05d active candidates exclude self, retain full-HP others")
			return candidates.find(target)
		t.check(await game._perform_good_deed(owner) == 1 and await game._perform_good_deed(owner) == 1, "I05d active skill has no invented once-per-phase limit")
		t.check(owner.hp == 3 and target.hp == 6 and target.max_hp == 4 and target.good_deed_marks == 2, "I05d two actual costs and extra HP grants commit once each")
		t.check(owner.hand_size() == 1 and actions.is_empty() and (not concrete or owner.determined_cards == [card]), "I05d ordinary/concrete hand resources are never skill fees or USE facts")
		owner.simba_good_deeds_enabled = false
		t.check(await game._perform_good_deed(owner) == 0 and owner.hp == 3, "I05d private gate off rejects active entry without cost")
		await dispose(t, game)
	var game = fixture(t)
	var owner = game.players[0]
	var target = game.players[1]
	owner.hp = 1; target.hp = 2
	game._simba_deed_choice_override = func(_p, candidates, reclaim, _valid): return -1 if reclaim else candidates.find(target)
	var seen: Array = []
	game._rescue_choice_override = func(_r, dying, _options):
		seen.append([dying, target.hp, target.good_deed_marks])
		return -1
	game.players[2].hand.append(null)
	await game._perform_good_deed(owner)
	t.check(owner.is_dead() and target.hp == 3 and target.good_deed_marks == 1, "I05d Q3 recipient effect remains after cost kills giver")
	t.check(not seen.is_empty() and seen.all(func(s): return s[0] == owner and s[1] == 3 and s[2] == 1), "I05d recipient grant precedes the first actual ordinary rescue offer")
	await dispose(t, game)
	game = fixture(t)
	owner = game.players[0]; target = game.players[1]
	owner.hp = 1
	game._simba_deed_choice_override = func(_p, candidates, _reclaim, _valid): return candidates.find(target)
	t.check(await game._perform_good_deed(owner) == 1 and owner.hp == 1 and target.hp == 5 and target.good_deed_marks == 0, "I05d cost rescue can reclaim the just-granted mark without ordinary Peach")
	await dispose(t, game)

func rescues(t):
	for mode in ["before_peach", "repeat", "partial_decline", "target_death", "yudaxi"]:
		var game = fixture(t)
		var owner = game.players[0]
		var first = game.players[1]
		var second = game.players[2]
		game.turn_manager.current_player_idx = 3
		game.turn_manager.play_actor_idx = 3
		owner.hp = -2 if mode in ["repeat", "partial_decline"] else 0
		first.good_deed_marks = 1 if mode in ["repeat", "partial_decline"] else 2
		first.hp = 1 if mode in ["target_death", "yudaxi"] else 4
		if mode in ["repeat", "partial_decline"]:
			second.good_deed_marks = 2
			second.hp = 4
		if mode == "yudaxi":
			first.general_name = "里奥·普利威尔"
			for p in game.players.slice(2): p.hp = 4
		var asks: Array = []
		game._simba_deed_choice_override = func(_p, candidates, reclaim, valid):
			t.check(reclaim and valid.call(), "I05d recovery is offered in original dying context")
			asks.append(candidates.duplicate())
			return -1 if mode == "partial_decline" and asks.size() > 1 else 0
		var rescue_seen: Array = []
		if mode == "before_peach": game.players[3].hand.append(null)
		if mode == "target_death": second.hand.append(null)
		if mode == "partial_decline": first.hand.assign([null, null])
		game._rescue_choice_override = func(rescuer, dying, options):
			rescue_seen.append([dying, owner.hp, game._dying_contexts.has(owner)])
			return CardData.CardSubType.PEACH if mode == "partial_decline" and rescuer == first and options.has(CardData.CardSubType.PEACH) else -1
		await game._resolve_dying(owner, null, "test")
		match mode:
			"before_peach":
				t.check(owner.hp == 2 and first.hp == 2 and first.good_deed_marks == 0 and rescue_seen.is_empty() and game.players[3].hand_size() == 1, "I05d Q5a reclaim saves owner before anyone spends Peach")
			"repeat":
				t.check(owner.hp == 1 and asks.size() == 2 and first.hp == 3 and second.hp == 2 and first.good_deed_marks == 0 and second.good_deed_marks == 0, "I05d Q5c negative HP permits successive full reclaims")
			"partial_decline":
				t.check(owner.hp == 1 and first.good_deed_marks == 0 and first.hp == 3 and first.hand.is_empty() and second.good_deed_marks == 2, "I05d declining next recovery preserves previous commit, then ordinary Peaches finish rescue")
			"target_death":
				t.check(owner.hp == 2 and first.is_dead() and first.good_deed_marks == 0, "I05d Q5b owner recovers full X despite target final death")
				t.check(owner.hand.is_empty(), "I05d strong HP deduction has no damage-source kill reward")
				t.check(not rescue_seen.is_empty() and rescue_seen.all(func(s): return s[0] == first and s[1] == 2 and not s[2]), "I05d owner rescue frame is finished before target rescue offers")
			"yudaxi":
				t.check(owner.is_dead() and first.hp == 1 and first.is_alive(), "I05d recovered owner remains eligible for nested highest-priority Yudaxi")
				t.check(game.players.slice(2).all(func(p): return p.hp == 2), "I05d nested Yudaxi completes each actual remaining target")
		t.check(game._dying_contexts.is_empty(), "I05d completed recovery and nested dying frames release once")
		await dispose(t, game)

func stale(t):
	for mode in ["owner_reset", "target_reset", "phase", "end"]:
		var game = fixture(t)
		var owner = game.players[0]
		var target = game.players[1]
		target.capture_game_start_state()
		game._simba_deed_choice_override = func(_p, candidates, _reclaim, _valid):
			match mode:
				"owner_reset": owner.restore_game_start_state()
				"target_reset": target.restore_game_start_state()
				"phase": game.turn_manager.current_phase = TurnManager.Phase.DRAW
				"end": game._game_over = true
			return candidates.find(target)
		t.check(await game._perform_good_deed(owner) == GameManager.CHOICE_INVALID and owner.hp == 5 and target.hp == 5 and target.good_deed_marks == 0, "I05d stale selection never pays HP or grants marks: " + mode)
		t.check(game._simba_deed_pending.is_empty(), "I05d stale active lease releases without replacing a newer action")
		await dispose(t, game)

func start_active(game, owner, result):
	result.append(await game._perform_good_deed(owner))

func bridge(t):
	for seat in [0, 1]:
		for mode in ["confirm", "cancel", "timeout", "close"]:
			var game = fixture(t)
			var owner = game.players[seat]
			if seat != 0:
				game.players[0].general_name = "稻草人"
				game.players[0].simba_good_deeds_enabled = false
			owner.general_name = SIMBA; owner.simba_good_deeds_enabled = true
			game.turn_manager.current_player_idx = seat
			game.turn_manager.play_actor_idx = seat
			game._set_input_player(owner)
			var target = game.players[(seat + 1) % 5]
			var adapter = LanGameBridge.new()
			t.root.add_child(adapter); adapter.game = game
			game._open_player_detail(owner)
			var skill = adapter.snapshot(seat).controls.filter(func(c): return "【做好事】" in c.text)
			t.check(skill.size() == 1 and adapter.submit(seat, skill[0].id), "I05d host/remote starts active skill through actual detail button")
			await t.process_frame
			var view = adapter.snapshot(seat)
			var options = view.controls.filter(func(c): return c.text.begins_with(target.player_name + " ·"))
			t.check(options.size() == 1 and view.owner == seat and not game._simba_deed_pending.is_empty(), "I05d host/remote owns one shared optional target/confirmation window")
			if options.size() == 1:
				var token = options[0].id
				game._step_remaining = 7.0
				t.check(not adapter.submit((seat + 1) % 5, token) and adapter.submit(seat, token), "I05d wrong seat rejected, authorized selection accepted")
				t.check(game._step_remaining <= 7.0 and owner.hp == 5 and target.good_deed_marks == 0, "I05d selecting target does not reset countdown or commit any effect")
				var button_text = "确认做好事" if mode == "confirm" else "取消做好事"
				if mode == "timeout": game._countdown_on_timeout.call()
				elif mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
				else:
					var buttons = adapter.snapshot(seat).controls.filter(func(c): return c.text == button_text)
					t.check(buttons.size() == 1 and adapter.submit(seat, buttons[0].id), "I05d actual optional confirmation/cancel accepted")
				for i in 4: await t.process_frame
				t.check(owner.hp == (4 if mode == "confirm" else 5) and target.hp == (6 if mode == "confirm" else 5) and target.good_deed_marks == (1 if mode == "confirm" else 0), "I05d confirmed/cancelled/timed-out/closed window commits precisely according to outcome")
				t.check(game._simba_deed_pending.is_empty() and not adapter.submit(seat, token), "I05d completed window releases lease and rejects old token")
				var row = adapter.snapshot(seat).players[target.seat_index]
				t.check(int(row.get("good_deed_marks", 0)) == target.good_deed_marks, "I05d authoritative value snapshot exposes actual public marks")
			adapter.game = null; adapter.queue_free()
			await dispose(t, game)

func start_rescue(game, owner, result):
	result.append(await game._resolve_dying(owner, null, "test"))

func bridge_reclaim(t):
	for seat in [0, 1]:
		for mode in ["confirm", "cancel", "timeout", "close"]:
			var game = fixture(t)
			var owner = game.players[seat]
			if seat != 0:
				game.players[0].general_name = "稻草人"
				game.players[0].simba_good_deeds_enabled = false
			owner.general_name = SIMBA; owner.simba_good_deeds_enabled = true
			owner.hp = 0
			game.turn_manager.current_player_idx = (seat + 2) % 5
			var target = game.players[(seat + 1) % 5]
			target.good_deed_marks = 2
			var adapter = LanGameBridge.new()
			t.root.add_child(adapter); adapter.game = game
			var result: Array = []
			start_rescue(game, owner, result)
			await t.process_frame
			var view = adapter.snapshot(seat)
			var options = view.controls.filter(func(c): return c.text.begins_with(target.player_name + " ·"))
			t.check(result.is_empty() and view.owner == seat and options.size() == 1, "I05d actual pre-Peach recovery window belongs to dying host/remote")
			if options.size() == 1:
				var token = options[0].id
				game._step_remaining = 6.0
				t.check(not adapter.submit((seat + 1) % 5, token) and adapter.submit(seat, token), "I05d recovery rejects wrong seat and accepts authorized target")
				t.check(owner.hp == 0 and target.hp == 5 and target.good_deed_marks == 2 and game._step_remaining <= 6.0, "I05d unconfirmed recovery leaves HP/marks unchanged and keeps remaining timer")
				if mode == "timeout": game._countdown_on_timeout.call()
				elif mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
				else:
					var label = "确认回收" if mode == "confirm" else "放弃回收"
					var buttons = adapter.snapshot(seat).controls.filter(func(c): return c.text == label)
					t.check(buttons.size() == 1 and adapter.submit(seat, buttons[0].id), "I05d actual recovery confirmation/decline uses opaque input token")
				for i in 4: await t.process_frame
				if mode == "confirm":
					t.check(result == [0] and owner.hp == 2 and target.hp == 3 and target.good_deed_marks == 0, "I05d confirmed recovery commits full X once")
				elif mode == "close":
					t.check(result == [GameManager.CHOICE_INVALID] and owner.is_dying() and target.good_deed_marks == 2 and target.hp == 5, "I05d technical close does not act as decline or confirm death")
				else:
					t.check(result == [0] and owner.is_dead() and target.good_deed_marks == 2 and target.hp == 5, "I05d decline/timeout continues ordinary failed rescue without spending marks")
				t.check(game._dying_contexts.is_empty() and not adapter.submit(seat, token), "I05d old recovery token cannot pay or finish dying twice")
			adapter.game = null; adapter.queue_free()
			await dispose(t, game)

func granted(t):
	var game = fixture(t)
	var owner = game.players[0]
	var target = game.players[1]
	game.turn_manager.current_player_idx = 2
	game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_phase(0, TurnManager.Phase.PLAY)
	game._simba_deed_choice_override = func(_p, candidates, _reclaim, _valid): return candidates.find(target)
	t.check(not frame.is_empty() and await game._perform_good_deed(owner) == 1 and owner.hp == 4 and target.hp == 6, "I05d real standalone gifted PLAY permits Good Deed without requiring owner turn")
	t.check(game.turn_manager.complete_standalone_phase(frame) and game.turn_manager.current_player_idx == 2 and game.turn_manager.current_phase == TurnManager.Phase.START, "I05d gift returns to suspended source after its permitted active skill")
	await dispose(t, game)

func nested_invalid(t):
	var game = fixture(t)
	var owner = game.players[0]
	var target = game.players[1]
	var source = game.players[3]
	source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.POFENG_SPEAR))
	owner.hp = 1
	target.hp = 1; target.good_deed_marks = 2
	target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SAGE_PROTECTION))
	target.sage_activated = true
	game._simba_deed_choice_override = func(_p, candidates, _reclaim, _valid): return candidates.find(target)
	var result: Array = []
	var drive = func(): result.append(await game._deal_damage_result(source, owner, 1, EffectChain.DamageType.PHYSICAL))
	drive.call()
	await t.process_frame
	t.check(result.is_empty() and not game._choice_prompt_stack.is_empty() and owner.hp == 2 and target.hp == -1 and target.good_deed_marks == 0, "I05d actual damage parent waits on nested target Sage after owner recovery")
	game._choice_prompt_stack.back().overlay.queue_free()
	for i in 4: await t.process_frame
	t.check(result.size() == 1 and result[0].invalidated and source.hand_limit_bonus == 0, "I05d nested technical failure propagates into original damage continuation without post-damage Pofeng")
	t.check(owner.hp == 2 and target.hp == -1 and target.is_dying() and target.good_deed_marks == 0 and game._dying_contexts.is_empty(), "I05d invalid nested rescue neither refunds committed recovery nor confirms target death")
	await dispose(t, game)
