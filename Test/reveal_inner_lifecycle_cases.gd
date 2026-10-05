extends "res://Test/sao_opportunity_cases.gd"

func prepare():
	reset()
	game.players[0].general_name = "安普提·斯丢皮得"
	var card = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	card.hidden_category = "weapon"
	game.players[0].equip_hidden_card_to_slot("weapon", card)
	game._sao_reveal_override = func(): return true
	game._sao_reveal_sub_override = Callable()
	game._sao_reveal_slot_override = Callable()
	return card

func run(host):
	suite = host
	game = host.game
	for mode in ["yes", "cancel", "close", "reset", "move"]:
		var card = prepare()
		game._reveal_ask_pending = true
		var action = func():
			var pending = game._choice_prompt_stack.back()
			match mode:
				"cancel": pending.answer.submit(-1)
				"close": pending.overlay.queue_free()
				"reset": game.reset_game_over_state()
				"move": game.players[0].determined_cards.append(game.players[0].remove_equipment("weapon"))
				_: pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
		action.call_deferred()
		var result = await game._maybe_ask_reveal()
		suite.check(result == (1 if mode == "yes" else (0 if mode == "cancel" else GameManager.CHOICE_INVALID)) and (card.sub_type != CardData.CardSubType.HIDDEN_EQUIPMENT) == (mode == "yes"), "E03e-22d-2：明置内层实际网格正常/取消/关闭/重开/原牌移动结果：" + mode)
		await suite.process_frame
	for mode in ["cancel", "close", "move"]:
		prepare()
		var armor = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
		armor.hidden_category = "armor"
		game.players[0].equip_hidden_card_to_slot("armor", armor)
		var action = func():
			var pending = game._choice_prompt_stack.back()
			match mode:
				"cancel": pending.answer.submit(-1)
				"close": pending.overlay.queue_free()
				"move": game.players[0].remove_equipment("armor")
		action.call_deferred()
		var result = await game._do_sao_reveal(game.players[0])
		suite.check(result == (0 if mode == "cancel" else GameManager.CHOICE_INVALID) and game.players[0].get_hidden_equipment_card("weapon") != null, "E03e-22d-2：真实多槽选择取消/失效不自动取首槽")
		await suite.process_frame
	for route in ["damage", "nullification"]:
		prepare()
		game._reveal_ask_pending = true
		var close = func(): game._choice_prompt_stack.back().overlay.queue_free()
		close.call_deferred()
		if route == "damage":
			var result = await game._deal_damage_result(game.players[2], game.players[1], 1, EffectChain.DamageType.PHYSICAL)
			suite.check(result.invalidated and game.players[1].hp == 9, "E03e-22d-2：实际伤害后明置内层关闭传递失效，已受伤保留")
		else:
			game.players[0].hand.assign([null])
			game._nullify_override = func(): return true
			game._yes_ah_override = func(): return "card"
			var result = await game._ask_nullification_round_result("明置内层失效")
			suite.check(result.outcome == GameManager.NullificationOutcome.INVALIDATED and game.players[0].hand.is_empty() and game.deck._discard.size() == 1, "E03e-22d-2：无懈已付原牌保留，明置内层失效不继续反无懈")
		await suite.process_frame
	reset()
	game._sao_reveal_override = Callable()
	game = null
	suite = null
