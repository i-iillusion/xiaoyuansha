extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game._clear_pending_determined_card()
	game._target_confirm_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._card_target_generation += 1
	game._card_target_confirm_owner = -1
	game._is_targeting = false
	game._is_iron_chain_targeting = false
	game._iron_chain_targets.clear()
	for p in game.players:
		p.mount_plus = 0
		p.mount_minus = 0
		p.chained = false
		p.judgment_cards.clear()

func drive(action: String, chain: bool, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 2 and not game._countdown_active, "E03e-15c：目标确认独立无计时")
	if chain: game._on_iron_chain_target_click(game.players[2])
	else: game._on_target_click(game.players[2])
	suite.check(game._choice_prompt_stack.size() == 1 and (not chain or game._iron_chain_targets == [target]), "E03e-15c：确认期间重复点击不另开窗口或添加目标")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = -1
		"dead":
			target.hp = 0
			target.mark_dead()
		"shield": target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.TENGJIA))
		"cancel_reopen":
			game._on_cancel_target_pressed()
			if chain: game._enter_iron_chain_mode()
			else: game._enter_targeting_mode(CardData.CardSubType.STRIKE)
		"ended":
			game._finish_game("平局", "目标确认回归")
			return
	buttons[1 if action == "no" or (chain and action == "yes") else 0].pressed.emit()
	pending.answer.submit(1)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for chain in [false, true]:
		for concrete in [false, true]:
			for action in (["yes", "more", "close", "phase", "phase_idle", "actor", "dead", "ended", "cancel_reopen"] if chain else ["yes", "no", "close", "phase", "phase_idle", "actor", "dead", "ended", "cancel_reopen", "shield"]):
				reset()
				events.clear()
				var p = game.players[0]
				var target = game.players[1]
				var other = game.players[2]
				var sub = CardData.CardSubType.IRON_CHAIN if chain else CardData.CardSubType.STRIKE
				var original = CardBase.create(sub) if concrete else null
				if concrete:
					p.determined_cards.append(original)
					game._pending_determined_card = original
				else: p.hand.append(null)
				if chain: game._enter_iron_chain_mode()
				else: game._enter_targeting_mode(sub)
				drive.call_deferred(action, chain, target)
				if chain: await game._on_iron_chain_target_click(target)
				else: await game._on_target_click(target)
				if action == "more":
					suite.check(game._is_iron_chain_targeting and game._iron_chain_targets == [target] and p.hand_size() == 1 and events.is_empty(), "E03e-15c：继续第二目标前不提前付牌")
					await game._on_iron_chain_target_click(other)
				var paid = action in ["yes", "more"]
				suite.check(events.size() == (1 if paid else 0) and p.hand_size() == (0 if paid else 1), "E03e-15c：仅合法确认支付一次，过期不扣牌")
				suite.check(not concrete or game.deck._discard.count(original) == (1 if paid else 0), "E03e-15c：具体原牌只弃一次，取消不丢失")
				suite.check(target.chained == (chain and paid) and other.chained == (action == "more") and target.hp == (0 if action == "dead" else (9 if paid and not chain else 10)), "E03e-15c：铁索否仅首目标、继续两目标；普通杀仅有效确认命中")
				suite.check(game._choice_prompt_stack.is_empty() and game._card_target_confirm_owner == -1, "E03e-15c：旧确认等待/点击锁清理")
				if action == "cancel_reopen":
					suite.check(game._is_iron_chain_targeting if chain else game._is_targeting, "E03e-15c：旧失效协程不清理取消后新开的同类选择")
				elif action not in ["no", "more"]:
					suite.check(not game._is_iron_chain_targeting and not game._is_targeting, "E03e-15c：完成或失效后清本次目标选择")
				await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-15c：全部确认窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_target_confirm("A", "B", CardData.CardSubType.STRIKE) == GameManager.CHOICE_INVALID, "E03e-15c：目标确认关闭显式失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._target_cfm_result.emit(true)
		game._iron_chain_cfm_result.emit(true)
		suite.check(not pending.answer.settled, "E03e-15c：旧按钮/两个共享信号不污染新铁索确认")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_more_target_confirm("B") == 0, "E03e-15c：下一铁索确认可以只选首目标")
	await suite.process_frame
	for chain in [false, true]:
		reset()
		game.players[0].hand.append(null)
		var first = game.players[1]
		var second = game.players[4]
		if chain: game._enter_iron_chain_mode()
		else: game._enter_targeting_mode(CardData.CardSubType.STRIKE)
		var reopen = func():
			var previous = game._choice_prompt_stack.back()
			game._on_cancel_target_pressed()
			if chain:
				game._enter_iron_chain_mode()
				game._on_iron_chain_target_click(second)
			else:
				game._enter_targeting_mode(CardData.CardSubType.STRIKE)
				game._on_target_click(second)
			var current = game._choice_prompt_stack.back()
			previous.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
			suite.check(not current.answer.settled and game._card_target_confirm_owner == game._card_target_generation, "E03e-15c：旧答复不答新确认，也不释放新点击锁")
			var finish = func(): current.overlay.find_children("*", "Button", true, false)[1 if chain else 0].pressed.emit()
			finish.call_deferred()
		reopen.call_deferred()
		if chain: await game._on_iron_chain_target_click(first)
		else: await game._on_target_click(first)
		await suite.process_frame
		suite.check(game.players[0].hand_size() == 0 and game._choice_prompt_stack.is_empty() and game._card_target_confirm_owner == -1, "E03e-15c：真正重开的新确认合法支付一次并完成清理")
		suite.check(not first.chained and first.hp == 10 and (second.chained if chain else second.hp == 9), "E03e-15c：仅新目标生效，旧目标不受旧确认影响")
	reset()
	suite = null
	game = null
