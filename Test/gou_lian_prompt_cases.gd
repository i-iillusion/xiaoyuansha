extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._gou_lian_slot_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.mount_plus = 0
		p.mount_minus = 0

func drive(action: String, source: Player, victim: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 3 and not game._countdown_active, "E03e-9a：两匹选择及取消，沿用无计时")
	match action:
		"cancel":
			buttons[2].pressed.emit()
			return
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
		"replace", "remove":
			victim.determined_cards.append(victim.remove_equipment("mount_2"))
			if action == "replace": victim.equip_card_to_slot("mount_2", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
		"weapon", "same_weapon":
			source.determined_cards.append(source.remove_equipment("weapon"))
			if action == "same_weapon": source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
		"armor": victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
		"source_dead", "victim_dead":
			var dead = source if action == "source_dead" else victim
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "E03e-9a回归")
			return
	buttons[1].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["second", "cancel", "close", "phase", "phase_idle", "actor", "replace", "remove", "weapon", "same_weapon", "armor", "source_dead", "victim_dead", "ended", "illegal"]:
			reset()
			events.clear()
			var source = game.players[0]
			var victim = game.players[1]
			source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
			var first = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
			var second = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
			victim.equip_card_to_slot("mount_1", first)
			victim.equip_card_to_slot("mount_2", second)
			var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: source.determined_cards.append(kill)
			else: source.hand.append(null)
			if action == "illegal": game._gou_lian_slot_override = func(): return "weapon"
			else: drive.call_deferred(action, source, victim)
			await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
			var gained = action == "second"
			suite.check(victim.hp == (0 if action == "victim_dead" else 9), "E03e-9a：选择失效不回滚已提交伤害：" + action)
			suite.check(source.determined_cards.count(second) == (1 if gained else 0) and not game.deck._discard.has(second), "E03e-9a：只取得所选原马一次，不弃置")
			suite.check(victim.get_equipment_card("mount_1") == first and not source.determined_cards.has(first), "E03e-9a：未选坐骑保持原槽")
			suite.check(victim.mount_plus == (0 if action in ["second", "remove"] else 1) and source.mount_plus == 0, "E03e-9a：移出扣原计数，入手不授装备效果")
			suite.check(events.size() == 1 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-9a：已付杀只一次，用牌事件不因获得增加")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-9a：等待结束")
			if action == "replace": suite.check(victim.get_equipment_card("mount_2") != null and victim.get_equipment_card("mount_2") != second, "E03e-9a：旧选择不能偷后来同名马")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-9a：窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var source = game.players[1]
	var victim = game.players[2]
	source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
	var mount = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	victim.equip_card_to_slot("mount_1", mount)
	source.hand.append(null)
	game.turn_manager.play_actor_idx = 1
	await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
	suite.check(victim.hp == 9 and source.determined_cards == [mount] and victim.mount_count() == 0, "E03e-9a：非0号AI原策略取得原马，不等待人类")
	reset()
	victim = game.players[1]
	victim.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
	var slots: Array[String] = ["mount_1"]
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._ask_gou_lian_slot(victim, slots) == "", "E03e-9a：关闭不是主动取消")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._equip_pick_result.emit("mount_1")
		suite.check(not pending.answer.settled, "E03e-9a：旧按钮及共享装备信号不污染下次")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._ask_gou_lian_slot(victim, slots) == "cancel", "E03e-9a：下一合法主动取消正常完成")
	await suite.process_frame
	reset()
	suite = null
	game = null
