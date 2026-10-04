extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._calamity_target_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(action: String, source: Player, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 5 and not game._countdown_active, "E03e-11a：四名其他角色及取消，沿用无计时")
	if action == "cancel":
		buttons[-1].pressed.emit()
		return
	if action == "close":
		pending.overlay.queue_free()
		return
	match action:
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = -1
		"weapon", "same_weapon":
			source.determined_cards.append(source.remove_equipment("weapon"))
			if action == "same_weapon": source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CALAMITY_SWORD))
		"source_dead", "target_dead":
			var dead = source if action == "source_dead" else target
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "灾厄选择回归")
			return
	buttons[1].pressed.emit() # 2号C，而非受伤的1号B。
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["choose", "cancel", "close", "phase", "phase_idle", "actor", "weapon", "same_weapon", "source_dead", "target_dead", "ended"]:
			reset()
			events.clear()
			var source = game.players[0]
			var victim = game.players[1]
			var target = game.players[2]
			var sword = CardBase.create(CardData.CardSubType.CALAMITY_SWORD)
			var old = CardBase.create(CardData.CardSubType.LIANNU)
			source.equip_card_to_slot("weapon", sword)
			target.equip_card_to_slot("weapon", old)
			source.wine_stacks = 1
			var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: source.determined_cards.append(kill)
			else: source.hand.append(null)
			drive.call_deferred(action, source, target)
			await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
			var moved = action == "choose"
			suite.check(victim.hp == 9, "E03e-11a：酒杀减1后已造成伤害保留：" + action)
			suite.check(target.get_equipment_card("weapon") == (sword if moved else old), "E03e-11a：只合法选择替换目标，不动过期目标原牌")
			suite.check(game.deck._discard.count(old) == (1 if moved else 0) and not game.deck._discard.has(sword), "E03e-11a：只弃被替换原装备一次，不弃转移剑")
			suite.check((source.get_equipment_card("weapon") == sword) == (not moved and action not in ["weapon", "same_weapon"]), "E03e-11a：同名换实例不移动后来者")
			suite.check(events.size() == 1 and source.hand.is_empty() and (not concrete or game.deck._discard.count(kill) == 1), "E03e-11a：转移不增加用牌事件或撤销杀费用")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-11a：等待已结束")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-11a：窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var source = game.players[0]
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_calamity_target_picker(source) == GameManager.CHOICE_INVALID, "E03e-11a：关闭明确失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._calamity_target_result.emit(game.players[1])
		suite.check(not pending.answer.settled, "E03e-11a：旧按钮及共享信号不污染下次")
		pending.overlay.find_children("*", "Button", true, false)[-1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_calamity_target_picker(source) == null, "E03e-11a：下一合法取消返回null，非失效")
	await suite.process_frame
	reset()
	suite = null
	game = null
