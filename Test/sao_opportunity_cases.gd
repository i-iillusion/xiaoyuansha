extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._sao_reveal_override = Callable()
	game._sao_reveal_sub_override = Callable()
	game._reveal_ask_pending = false
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func hide(owner: Player, category: String) -> CardBase:
	owner.general_name = "安普提·斯丢皮得"
	owner.hand.append(null)
	game._sao_type_override = func(): return category
	await game._do_sao_hide(owner, false)
	game._sao_type_override = Callable()
	var original = owner.get_hidden_equipment_card(category)
	suite.check(original != null and owner.hand.is_empty(), "E03e-16a：真实苕支付任意牌一次，生成原暗置装备")
	return original

func drive(action: String, owner: Player, category: String):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 3 and buttons[-1].text == "取消" and game._countdown_active, "E03e-16a：抢先/机会确认两选项加取消，保留通用响应计时")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			var actor = game.turn_manager.play_actor_idx
			game.turn_manager.play_actor_idx = 2
			game.turn_manager.play_actor_idx = actor
		"moved", "same":
			owner.determined_cards.append(owner.remove_equipment(category))
			if action == "same":
				var replacement = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
				replacement.hidden_category = category
				owner.equip_hidden_card_to_slot(category, replacement)
		"ended":
			game._finish_game("平局", "苕确认生命周期回归")
			return
		"timeout":
			game._countdown_on_timeout.call()
			return
	buttons[2 if action == "cancel" else (1 if action == "no" else 0)].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for category in ["weapon", "armor"]:
		var sub = CardData.CardSubType.LIANNU if category == "weapon" else CardData.CardSubType.RENWANG_DUN
		for concrete in [false, true]:
			for action in ["yes", "no", "cancel", "timeout", "close", "phase", "phase_idle", "actor", "moved", "same", "ended"]:
				reset()
				var owner = game.players[0]
				var actor = game.players[1]
				var original = await hide(owner, category)
				events.clear()
				var incoming = CardBase.create(sub) if concrete else null
				actor.hand.append(incoming)
				game.turn_manager.play_actor_idx = 1
				drive.call_deferred(action, owner, category)
				await game.play_card(sub)
				var actor_paid = action in ["no", "cancel", "timeout", "moved", "same"]
				suite.check(events.size() == (1 if actor_paid else 0) and actor.hand_size() == (0 if actor_paid else 1), "E03e-16a：抢先/关闭/行动失效不付原装备；原暗置已离开则原动作可继续")
				suite.check(actor.equipment.has(category) == actor_paid and (not concrete or not actor_paid or actor.get_equipment_card(category) == incoming), "E03e-16a：真实装备入口保留原牌实例")
				suite.check(original.sub_type == (sub if action == "yes" else CardData.CardSubType.HIDDEN_EQUIPMENT) and not game.deck._discard.has(original), "E03e-16a：仅有效抢先明置原暗置，不转化后来者")
				suite.check(game.equipment_pool.is_claimed(sub) == (action == "yes" or actor_paid), "E03e-16a：有效明置/装备才占唯一名称")
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-16a：抢先确认等待清理")
				await suite.process_frame
		for action in ["yes", "no", "cancel", "timeout", "close", "phase", "phase_idle", "actor", "moved", "same", "ended"]:
			reset()
			var owner = game.players[0]
			var original = await hide(owner, category)
			events.clear()
			game._sao_reveal_sub_override = func(): return sub
			game._reveal_ask_pending = true
			drive.call_deferred(action, owner, category)
			await game._maybe_ask_reveal()
			suite.check(original.sub_type == (sub if action == "yes" else CardData.CardSubType.HIDDEN_EQUIPMENT) and game.equipment_pool.is_claimed(sub) == (action == "yes"), "E03e-16a：仅有效机会明置，旧答复不明置后来暗置原牌")
			suite.check(events.is_empty() and owner.hand_size() == (1 if action in ["moved", "same"] else 0), "E03e-16a：明置同一原牌无需再次支付/生成使用事件")
			suite.check(game._choice_prompt_stack.is_empty() and not game._reveal_ask_pending, "E03e-16a：机会只询问一次，过期不重新默认发动")
			await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-16a：所有窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		old.append(game._countdown_on_timeout)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_sao_preempt_prompt(game.players[1], CardData.CardSubType.LIANNU, "武器") == GameManager.CHOICE_INVALID, "E03e-16a：抢先关闭明确失效，不默认阻止/不阻止")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		old[1].call()
		suite.check(not pending.answer.settled and game._countdown_active, "E03e-16a：旧抢先按钮/超时不会答复新明置机会")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_reveal_opportunity_prompt(game.players[0]) == 0, "E03e-16a：下一合法明置机会仍可暂不明置")
	await suite.process_frame
	reset()
	game._sao_type_override = Callable()
	suite = null
	game = null
