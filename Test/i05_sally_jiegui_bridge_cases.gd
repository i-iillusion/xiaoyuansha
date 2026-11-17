extends RefCounted

func token(bridge, seat, text):
	var buttons = bridge.snapshot(seat).controls.filter(func(c): return not c.disabled and c.text == text)
	return buttons[0].id if buttons.size() == 1 else ""

func start_strike(game, owner, target, result):
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	result.append(true)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for seat in [0, 1]:
		await target_choices(t, helper, seat)
		for mode in ["yes", "no", "close", "reset", "weapon"]:
			var game = helper.fixture(t, seat)
			var owner = game.players[seat]; var target = game.players[(seat + 1) % 5]
			game._chixiong_activate_override = Callable()
			var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
			owner.hand.append(null)
			var result: Array = []; start_strike(game, owner, target, result)
			await t.process_frame
			var yes = token(bridge, seat, "发动")
			t.check(yes != "" and result.is_empty() and bridge.input_owner() == seat and not game._countdown_active, "I05e2b host/remote virtual Chixiong uses original untimed authoritative window")
			t.check(not bridge.submit((seat + 2) % 5, yes) and bridge.snapshot((seat + 2) % 5).controls.is_empty(), "I05e2b wrong peer cannot answer source's virtual sword")
			if mode == "yes": t.check(bridge.submit(seat, yes), "I05e2b authorized source confirms via opaque token")
			elif mode == "no": t.check(bridge.submit(seat, token(bridge, seat, "不发动")), "I05e2b authorized source may decline weapon effect")
			elif mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
			else:
				if mode == "reset": owner.restore_game_start_state()
				else: owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
				game._choice_prompt_stack.back().answer.submit(1)
			for i in 4: await t.process_frame
			t.check(result == [true] and target.hp == (4 if mode in ["yes", "no"] else 5) and owner.hand_size() == (1 if mode == "yes" else 0), "I05e2b host/remote source confirmation, decline and stale window have exact effects")
			t.check(not bridge.submit(seat, yes) and game._pending_card_actions.is_empty(), "I05e2b old activation token cannot repeat a paid Strike or reward")
			bridge.game = null; bridge.queue_free(); await helper.dispose(t, game)
		for mode in ["confirm", "cancel", "timeout", "close", "replace"]:
			var game = helper.fixture(t, seat)
			var owner = game.players[seat]
			var original = CardBase.create(CardData.CardSubType.SILVER_LION)
			owner.equip_card_to_slot("armor", original); owner.hp = 2
			var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
			var portrait = bridge.snapshot(seat).targets.get(str(seat), "")
			t.check(portrait != "" and bridge.submit(seat, portrait), "I05e2b real own portrait opens private skill detail")
			await t.process_frame
			var button = bridge.snapshot(seat).controls.filter(func(c): return "【姐贵】" in c.text)
			t.check(button.size() == 1 and bridge.snapshot((seat + 1) % 5).controls.is_empty(), "I05e2b detail has exactly one owner-only active Jiegui entry")
			if button.size() != 1: bridge.game = null; bridge.queue_free(); await helper.dispose(t, game); continue
			t.check(bridge.submit(seat, button[0].id), "I05e2b actual private skill button opens shared discard prompt")
			await t.process_frame
			var choices = bridge.snapshot(seat).controls.filter(func(c): return c.toggle and not c.disabled)
			t.check(choices.size() == 1 and bridge.input_owner() == seat, "I05e2b host/remote owns actual equipment selection and confirmation")
			if choices.size() != 1: bridge.game = null; bridge.queue_free(); await helper.dispose(t, game); continue
			var selection = choices[0].id
			game._step_remaining = 7.0
			t.check(not bridge.submit((seat + 1) % 5, selection) and bridge.submit(seat, selection), "I05e2b only owner may select original equipment")
			t.check(game._step_remaining <= 7.0 and owner.hp == 2 and owner.get_equipment_card("armor") == original, "I05e2b selected slot preserves one countdown and makes no move")
			var confirmation = token(bridge, seat, "确认弃置装备")
			if mode == "timeout": game._countdown_on_timeout.call()
			elif mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
			elif mode == "replace":
				owner.determined_cards.append(owner.remove_equipment("armor"))
				owner.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.RENWANG_DUN))
				game._choice_prompt_stack.back().answer.submit(0)
			else:
				var command = confirmation if mode == "confirm" else token(bridge, seat, "取消弃置装备")
				t.check(command != "" and bridge.submit(seat, command), "I05e2b real confirmation or cancellation command accepted")
			for i in 4: await t.process_frame
			t.check(game.deck._discard.count(original) == (1 if mode == "confirm" else 0) and owner.hp == (3 if mode in ["confirm", "replace"] else 2), "I05e2b opaque commands commit once or leave original untouched")
			t.check(game._jiegui_discard_pending.is_empty() and not bridge.submit(seat, confirmation) and not bridge.submit(seat, selection), "I05e2b old confirmation/selection tokens cannot affect the next window")
			bridge.game = null; bridge.queue_free(); await helper.dispose(t, game)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func target_choices(t, helper, seat):
	for mode in ["draw", "discard", "close", "reset"]:
		var game = helper.fixture(t, seat)
		var owner = game.players[seat]; var target = game.players[(seat + 1) % 5]
		game._chixiong_target_override = Callable()
		game._hand_discard_override = Callable()
		var bridge = LanGameBridge.new(); t.root.add_child(bridge); bridge.game = game
		var original = CardBase.create(CardData.CardSubType.PEACH)
		target.hand.append(original); owner.hand.append(null)
		var result: Array = []; start_strike(game, owner, target, result); await t.process_frame
		var discard = token(bridge, target.seat_index, "弃置一张手牌")
		t.check(discard != "" and bridge.input_owner() == target.seat_index and not bridge.submit(seat, discard), "I05e2b native target choice belongs to actual target, not sword source")
		if mode == "draw":
			t.check(bridge.submit(target.seat_index, token(bridge, target.seat_index, "令 %s 摸一张牌" % owner.player_name)), "I05e2b target may grant real reward through opaque command")
		elif mode == "discard":
			t.check(bridge.submit(target.seat_index, discard), "I05e2b target selects actual hand discard branch")
			await t.process_frame
			var choices = bridge.snapshot(target.seat_index).controls.filter(func(c): return c.toggle and not c.disabled)
			t.check(choices.size() == 1 and bridge.submit(target.seat_index, choices[0].id), "I05e2b target alone selects original concrete hand resource")
			t.check(bridge.submit(target.seat_index, token(bridge, target.seat_index, "确认弃牌")), "I05e2b real mandatory hand prompt confirms selected original")
		elif mode == "close": game._choice_prompt_stack.back().overlay.queue_free()
		else: target.restore_game_start_state(); game._choice_prompt_stack.back().answer.submit(1)
		for i in 4: await t.process_frame
		t.check(result == [true] and target.hp == (4 if mode in ["draw", "discard"] else 5), "I05e2b target decision or technical invalidation controls original parent precisely")
		t.check(owner.hand_size() == (1 if mode == "draw" else 0) and game.deck._discard.count(original) == (1 if mode == "discard" else 0), "I05e2b target real payment and source reward are exclusive")
		t.check(not bridge.submit(target.seat_index, discard) and game._pending_card_actions.is_empty(), "I05e2b old target token cannot re-pay or repeat reward")
		bridge.game = null; bridge.queue_free(); await helper.dispose(t, game)
