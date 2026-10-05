extends "res://Test/play_skill_selection_generation_cases.gd"

func window():
	return game._choice_prompt_stack.back().overlay

func press(text: String):
	var buttons = window().find_children("*", "Button", true, false)
	var found = buttons.filter(func(button): return button.text.begins_with(text))
	suite.check(found.size() == 1 and not found[0].disabled, "E03e-18：真实交换选择按钮可用：" + text)
	if found.size() == 1: found[0].pressed.emit()

func run(host):
	suite = host
	game = host.game
	for kind in ["zone", "mount"]:
		for mode in ["accept", "cancel", "close", "phase", "resource", "dead", "end", "old_signal"]:
			reset("麦克斯·欧尼斯特")
			var a = game.players[1]
			var b = game.players[2]
			var slot = Player.MOUNT_SLOTS[0]
			a.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
			a.equip_card_to_slot(slot, CardBase.create(CardData.CardSubType.MOUNT_MINUS))
			var act = func():
				suite.check(not game._countdown_active, "E03e-18：区域及坐骑保持无倒计时")
				match mode:
					"cancel": press("取消")
					"close": window().queue_free()
					"phase": game.turn_manager.current_phase = TurnManager.Phase.DISCARD
					"resource":
						a.remove_equipment("weapon" if kind == "zone" else slot)
						a.equip_card_to_slot("weapon" if kind == "zone" else slot, CardBase.create(CardData.CardSubType.LIANNU if kind == "zone" else CardData.CardSubType.MOUNT_MINUS))
					"dead": a.mark_dead()
					"end": game._game_over = true
					"old_signal":
						game._lanzhonghou_zone_result.emit("done")
						game._lanzhonghou_mount_result.emit(Player.MOUNT_SLOTS[3])
						suite.check(not game._choice_prompt_stack.back().answer.settled, "E03e-18：旧共享交换信号不能回答新独立窗口")
				if mode == "accept" or mode == "old_signal": press("武器" if kind == "zone" else Player.EQUIP_SLOT_NAMES[slot])
				elif mode in ["phase", "resource", "dead", "end"]: press("武器" if kind == "zone" else Player.EQUIP_SLOT_NAMES[slot])
			act.call_deferred()
			var reply = await game._ask_lanzhonghou_zone(a, b, [], 3) if kind == "zone" else await game._ask_lanzhonghou_mount_slot(a, Player.MOUNT_SLOTS, "交换坐骑")
			var expected = ("weapon" if kind == "zone" else slot) if mode in ["accept", "old_signal"] else ("cancel" if mode == "cancel" else "invalid")
			suite.check(reply == expected and game.players[0].hand_size() == 3 and game._lanzhonghou_execution_owner == -1, "E03e-18：真实窗口区分有效、取消和技术失效，不自行支付")
			await suite.process_frame
	# 完整真实区域/双槽/多选支付；任意牌和流转回手的具体牌均付原对象。
	for concrete in [false, true]:
		reset("麦克斯·欧尼斯特")
		var a = game.players[1]
		var b = game.players[2]
		var weapon = CardBase.create(CardData.CardSubType.LIANNU)
		var mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
		a.equip_card_to_slot("weapon", weapon)
		a.equip_card_to_slot(Player.MOUNT_SLOTS[0], mount)
		var fee = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
		game.players[0].hand.assign([fee, null, null])
		var drive = func():
			press("武器")
			press("坐骑")
			press(Player.EQUIP_SLOT_NAMES[Player.MOUNT_SLOTS[0]])
			press(Player.EQUIP_SLOT_NAMES[Player.MOUNT_SLOTS[2]])
			press("完成交换")
			var payment = window()
			var checks = payment.find_children("*", "CheckButton", true, false)
			checks[0].button_pressed = true
			checks[1].button_pressed = true
			payment.confirm.pressed.emit()
		drive.call_deferred()
		await game._run_lanzhonghou(a, b)
		suite.check(game.players[0].hand_size() == 1 and game._lanzhonghou_used and game._lanzhonghou_execution_owner == -1 and game._lanzhonghou_pending.is_empty(), "E03e-18：完整真实选择支付两张，仅记一次、释放锁与暂存")
		suite.check(a.get_equipment_card("weapon") == null and a.get_equipment_card(Player.MOUNT_SLOTS[0]) == null and b.get_equipment_card("weapon") == weapon and b.get_equipment_card(Player.MOUNT_SLOTS[2]) == mount, "E03e-18：武器及跨坐骑空槽转移同一原对象一次")
		if concrete: suite.check(game.deck._discard.count(fee) == 1, "E03e-18：具体费用原牌仅入弃一次")
		await suite.process_frame
	for stage in ["second_mount", "payment"]:
		reset("麦克斯·欧尼斯特")
		var a = game.players[1]
		var b = game.players[2]
		var slot = Player.MOUNT_SLOTS[0]
		var original = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
		a.equip_card_to_slot(slot, original)
		var invalidate = func():
			press("坐骑")
			press(Player.EQUIP_SLOT_NAMES[slot])
			if stage == "payment":
				press(Player.EQUIP_SLOT_NAMES[Player.MOUNT_SLOTS[2]])
				press("完成交换")
			var pending_window = window()
			a.remove_equipment(slot)
			a.equip_card_to_slot(slot, CardBase.create(CardData.CardSubType.MOUNT_MINUS))
			if stage == "payment":
				pending_window.find_children("*", "CheckButton", true, false)[0].button_pressed = true
				pending_window.confirm.pressed.emit()
			else: press(Player.EQUIP_SLOT_NAMES[Player.MOUNT_SLOTS[2]])
		invalidate.call_deferred()
		await game._run_lanzhonghou(a, b)
		suite.check(game.players[0].hand_size() == 3 and not game._lanzhonghou_used and b.get_mount_slots().is_empty() and a.get_equipment_card(slot) != original and game._lanzhonghou_execution_owner == -1, "E03e-18：第二槽或支付期间原第一槽变化不收费、不转移后来牌")
		await suite.process_frame
	# 同人物同PLAY重开实际交换：旧按钮答复不结算新窗口、不清新执行锁。
	reset("麦克斯·欧尼斯特")
	var a = game.players[1]
	var b = game.players[2]
	var weapon = CardBase.create(CardData.CardSubType.LIANNU)
	a.equip_card_to_slot("weapon", weapon)
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	var finished: Array = [false]
	var restart = func():
		var old_button = window().find_children("*", "Button", true, false)[0]
		var old_callback = old_button.get_signal_connection_list("pressed")[0].callable
		game.reset_game_over_state()
		var finish_new = func():
			var new_owner = game._lanzhonghou_execution_owner
			old_callback.call()
			suite.check(new_owner != -1 and game._lanzhonghou_execution_owner == new_owner and not game._choice_prompt_stack.back().answer.settled and game.players[0].hand_size() == 3, "E03e-18：旧实际区域按钮不答新窗口、不释放新锁或支付")
			press("武器")
			press("完成交换")
		finish_new.call_deferred()
		await game._run_lanzhonghou(a, b)
		finished[0] = true
	restart.call_deferred()
	await game._run_lanzhonghou(a, b)
	while not finished[0]: await suite.process_frame
	suite.check(game.players[0].hand_size() == 2 and b.get_equipment_card("weapon") == weapon and game._lanzhonghou_used and game._lanzhonghou_execution_owner == -1, "E03e-18：重开仅新实际交换一次费用和移动")
	await suite.process_frame
	reset("稻草人")
	game._rps_override = Callable()
	suite = null
	game = null
