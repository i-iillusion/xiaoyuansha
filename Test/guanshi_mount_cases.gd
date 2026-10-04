extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._guanshi_override = func(): return true
	game._guanshi_mount_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.mount_plus = 0
		p.mount_minus = 0

func drive(action: String, actor: Player, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 2 and not game._countdown_active, "E03e-7b：两匹候选，无取消按钮或计时")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
		"replace", "remove":
			actor.determined_cards.append(actor.remove_equipment("mount_2"))
			if action == "replace":
				actor.equip_card_to_slot("mount_2", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
		"weapon": actor.determined_cards.append(actor.remove_equipment("weapon"))
		"armor": target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
		"source_dead":
			actor.hp = 0
			actor.mark_dead()
		"target_dead":
			target.hp = 0
			target.mark_dead()
		"ended":
			game._finish_game("平局", "E03e-7b回归")
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
		for action in ["second", "close", "phase", "replace", "remove", "weapon", "armor", "source_dead", "target_dead", "ended", "illegal"]:
			reset()
			events.clear()
			var actor = game.players[0]
			var target = game.players[1]
			var axe = CardBase.create(CardData.CardSubType.GUANSHI_AXE)
			actor.equip_card_to_slot("weapon", axe)
			var first = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
			var second = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
			actor.equip_card_to_slot("mount_1", first)
			actor.equip_card_to_slot("mount_2", second)
			var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			var dodge = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
			if concrete:
				actor.determined_cards.append(kill)
				target.determined_cards.append(dodge)
			else:
				actor.hand.append(null)
				target.hand.append(null)
			var responses: Array = []
			game._dodge_override = func():
				responses.append(true)
				return true
			if action == "illegal":
				game._guanshi_mount_override = func(): return "weapon"
			else:
				drive.call_deferred(action, actor, target)
			await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
			suite.check(target.hp == (0 if action == "target_dead" else (9 if action == "second" else 10)), "E03e-7b：有效支付才强制命中：" + action)
			suite.check(actor.get_equipment_card("mount_1") == first and not game.deck._discard.has(first), "E03e-7b：不误弃未选坐骑")
			suite.check(game.deck._discard.count(second) == (1 if action == "second" else 0) and not game.deck._discard.has(axe), "E03e-7b：只弃所选原马一次，不弃武器")
			suite.check(game.deck._discard.size() == (3 if action == "second" else 2)
				and (not concrete or (game.deck._discard.count(kill) == 1 and game.deck._discard.count(dodge) == 1)), "E03e-7b：已付杀闪不退款或重复入弃")
			suite.check(events.size() == 2 and responses.size() == 1 and target.hand_size() == 0, "E03e-7b：不重开闪响应或用牌事件")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-7b：所有出口结束等待")
			if action == "replace":
				suite.check(actor.get_equipment_card("mount_2") != null and actor.get_equipment_card("mount_2") != second, "E03e-7b：后来换入的同名马留在原槽")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-7b：窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var actor = game.players[0]
	actor.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_MINUS))
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_mount_discard_picker(actor) == "", "E03e-7b：关闭返回无效槽")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._mount_replace_result.emit("mount_1")
		suite.check(not pending.answer.settled, "E03e-7b：旧按钮及替换坐骑信号不污染新窗口")
		pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_mount_discard_picker(actor) == "mount_1", "E03e-7b：下一合法选择正常完成")
	await suite.process_frame
	reset()
	game._guanshi_override = Callable()
	suite = null
	game = null
