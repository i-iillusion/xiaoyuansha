extends RefCounted

func begin(game, owner, result):
	result.append(await game._perform_jiegui_discard(owner))

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for seat in [0, 1]:
		for mode in ["confirm", "cancel", "timeout", "close", "replace", "reset", "disable", "phase", "dead", "ended", "overlap"]:
			var game = helper.fixture(t, seat)
			var owner = game.players[seat]
			var original = CardBase.create(CardData.CardSubType.SILVER_LION)
			owner.equip_card_to_slot("armor", original); owner.hp = 2
			var facts: Array = []; game.card_action_committed.connect(func(e): facts.append(e))
			var result: Array = []
			begin(game, owner, result)
			await t.process_frame
			t.check(result.is_empty() and game._jiegui_discard_pending.owner == owner and game._choice_prompt_stack.size() == 1, "I05e2b own PLAY has one authoritative optional discard window: %d/%s" % [seat, mode])
			var prompt = game._choice_prompt_stack.back().overlay
			var buttons = prompt.find_children("*", "Button", true, false)
			game._step_remaining = 7.0
			buttons[0].pressed.emit()
			t.check(owner.get_equipment_card("armor") == original and owner.hp == 2 and game._step_remaining <= 7.0 and not prompt.confirm.disabled, "I05e2b slot selection commits nothing and preserves original countdown")
			match mode:
				"confirm": prompt.confirm.pressed.emit()
				"cancel": buttons.back().pressed.emit()
				"timeout": game._countdown_on_timeout.call()
				"close": prompt.queue_free()
				"replace":
					owner.determined_cards.append(owner.remove_equipment("armor"))
					owner.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.RENWANG_DUN))
					prompt.confirm.pressed.emit()
				"reset": owner.restore_game_start_state(); prompt.confirm.pressed.emit()
				"disable": owner.sally_jiegui_enabled = false; prompt.confirm.pressed.emit()
				"phase":
					game.turn_manager.current_phase = TurnManager.Phase.END
					game.turn_manager.current_phase = TurnManager.Phase.PLAY
					prompt.confirm.pressed.emit()
				"dead": owner.hp = 0; owner.mark_dead(); prompt.confirm.pressed.emit()
				"ended": game._finish_game("平局", "I05e2b engineering invalidation")
				"overlap":
					t.check(await game._perform_jiegui_discard(owner) == 0 and game._choice_prompt_stack.size() == 1, "I05e2b repeated active entry cannot create a second window")
					buttons.back().pressed.emit()
			for i in 4: await t.process_frame
			var expected = 1 if mode == "confirm" else (0 if mode in ["cancel", "timeout", "overlap"] else GameManager.CHOICE_INVALID)
			t.check(result == [expected] and game.deck._discard.count(original) == (1 if mode == "confirm" else 0), "I05e2b confirm/cancel/timeout/technical invalidation preserve exact original: " + mode)
			t.check(facts.is_empty() and game._jiegui_discard_pending.is_empty() and game._choice_prompt_stack.is_empty(), "I05e2b no card USE and no pending lease after voluntary equipment action")
			if mode == "confirm":
				t.check(owner.hp == 3 and owner.get_equipment_card("armor") == null and game.action_history.entries.any(func(e): return e.kind == "skill" and "【姐贵】" in e.text), "I05e2b committed lion loss heals once and creates public skill log")
			await helper.dispose(t, game)
	await persistent_equipment(t, helper)
	await phase_guards(t, helper)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func persistent_equipment(t, helper):
	for sub in [CardData.CardSubType.POFENG_SPEAR, CardData.CardSubType.SAGE_PROTECTION, CardData.CardSubType.SOUL_BLADE, CardData.CardSubType.MOUNT_MINUS, CardData.CardSubType.HIDDEN_EQUIPMENT]:
		var game = helper.fixture(t)
		var owner = game.players[0]
		var card = CardBase.create(sub)
		var slot = "armor" if sub == CardData.CardSubType.SAGE_PROTECTION else (Player.MOUNT_SLOTS[0] if sub == CardData.CardSubType.MOUNT_MINUS else "weapon")
		if sub == CardData.CardSubType.HIDDEN_EQUIPMENT:
			card.hidden_category = "weapon"; owner.equip_hidden_card_to_slot(slot, card)
		else: owner.equip_card_to_slot(slot, card)
		if sub == CardData.CardSubType.POFENG_SPEAR: owner.hand_limit_bonus = 4
		if sub == CardData.CardSubType.SAGE_PROTECTION: owner.sage_tokens = 2; owner.sage_activated = true
		if sub == CardData.CardSubType.SOUL_BLADE: owner.soul_blade_activated = true
		var result: Array = []
		begin(game, owner, result); await t.process_frame
		var prompt = game._choice_prompt_stack.back().overlay
		prompt.find_children("*", "Button", true, false)[0].pressed.emit(); prompt.confirm.pressed.emit()
		for i in 3: await t.process_frame
		t.check(result == [1] and game.deck._discard.count(card) == 1 and not owner.equipment.has(slot), "I05e2b actual chosen weapon/armor/mount/hidden original reaches discard once")
		if sub == CardData.CardSubType.POFENG_SPEAR: t.check(owner.hand_limit_bonus == 0 and owner.has_virtual_chixiong_effect(), "I05e2b Pofeng loss clears bonus and empty weapon slot restores virtual sword")
		if sub == CardData.CardSubType.SAGE_PROTECTION: t.check(owner.sage_tokens == 0 and not owner.sage_activated and card.sage_tokens == 2 and card.sage_activated, "I05e2b Sage state leaves body and follows actual discarded resource per E06")
		if sub == CardData.CardSubType.SOUL_BLADE: t.check(not owner.soul_blade_activated and card.soul_blade_activated, "I05e2b active Soul state follows actual resource, not virtual sword")
		if sub == CardData.CardSubType.MOUNT_MINUS: t.check(owner.mount_minus == 0, "I05e2b actual mount modifier removed")
		if sub == CardData.CardSubType.HIDDEN_EQUIPMENT: t.check(card.sub_type == sub and card.hidden_category == "weapon" and owner.has_virtual_chixiong_effect(), "I05e2b discarded hidden card stays hidden, no fabricated declaration")
		await helper.dispose(t, game)

func phase_guards(t, helper):
	var game = helper.fixture(t)
	var owner = game.players[0]
	t.check(await game._perform_jiegui_discard(owner) == 0, "I05e2b virtual sword alone is not a discardable resource")
	var card = CardBase.create(CardData.CardSubType.SILVER_LION); owner.equip_card_to_slot("armor", card)
	game.turn_manager.current_player_idx = 1; game.turn_manager.play_actor_idx = 1
	t.check(await game._perform_jiegui_discard(owner) == 0 and owner.get_equipment_card("armor") == card, "I05e2b SA-Q6 other player's PLAY cannot open voluntary discard")
	var response: Array = []
	var drive = func(): response.append(await game._show_dodge_prompt("B", "杀"))
	game._set_input_player(owner); drive.call(); await t.process_frame
	t.check(await game._perform_jiegui_discard(owner) == 0 and game._choice_prompt_stack.size() == 1, "I05e2b actual Dodge response cannot insert Jiegui discard")
	game._choice_prompt_stack.back().answer.submit(0)
	for i in 3: await t.process_frame
	t.check(response == [0] and owner.get_equipment_card("armor") == card, "I05e2b response finishes without voluntary loss")
	await helper.dispose(t, game)
	game = helper.fixture(t); owner = game.players[0]
	game.turn_manager.current_player_idx = 2; game.turn_manager.current_phase = TurnManager.Phase.START
	var frame = game.turn_manager.begin_standalone_phase(0, TurnManager.Phase.PLAY)
	owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
	var result: Array = []; begin(game, owner, result); await t.process_frame
	var prompt = game._choice_prompt_stack.back().overlay
	prompt.find_children("*", "Button", true, false)[0].pressed.emit(); prompt.confirm.pressed.emit()
	for i in 3: await t.process_frame
	t.check(not frame.is_empty() and result == [1] and owner.has_virtual_chixiong_effect(), "I05e2b actual gifted PLAY permits voluntary discard")
	t.check(game.turn_manager.complete_standalone_phase(frame) and game.turn_manager.current_player_idx == 2, "I05e2b gifted action returns to suspended turn holder")
	await helper.dispose(t, game)
