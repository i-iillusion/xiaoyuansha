extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._zone_pick_override = Callable()
	game._equip_pick_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.judgment_cards.clear()
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(stage: String, action: String, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(not game._countdown_active and buttons.size() == (4 if stage == "zone" else 3), "E03e-15a：拆顺牌区/装备选择独立无计时")
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
		"same_armor":
			target.determined_cards.append(target.remove_equipment("armor"))
			target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SILVER_LION))
		"empty":
			target.determined_cards.append(target.remove_equipment("armor"))
			target.determined_cards.append(target.remove_equipment("weapon"))
		"ended":
			game._finish_game("平局", "拆顺选牌窗口回归")
			return
	if stage == "zone" and action == "choose": drive.call_deferred("equip", action, target)
	buttons[-1 if action == "cancel" else 1].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for snatch in [false, true]:
		for concrete in [false, true]:
			for stage in ["zone", "equip"]:
				for action in (["choose", "cancel", "close", "phase", "phase_idle", "actor", "dead", "ended", "empty"] if stage == "zone" else ["choose", "cancel", "close", "phase", "phase_idle", "actor", "dead", "ended", "same_armor"]):
					reset()
					events.clear()
					var source = game.players[0]
					var target = game.players[1]
					var sub = CardData.CardSubType.SNATCH if snatch else CardData.CardSubType.DISMANTLE
					var payment = CardBase.create(sub) if concrete else null
					source.hand.append(payment)
					var armor = CardBase.create(CardData.CardSubType.SILVER_LION)
					target.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.LIANNU))
					target.equip_card_to_slot("armor", armor)
					target.hand.append(null)
					target.judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
					target.hp = 8
					if stage == "equip": game._zone_pick_override = func(): return "equip"
					drive.call_deferred(stage, action, target)
					await game.execute_card_on_target(target, sub)
					var paid = stage == "equip" or action == "choose"
					var moved = action == "choose"
					suite.check(events.size() == (1 if paid else 0) and source.hand.size() == (0 if paid else 1), "E03e-15a：选区失效不付原牌，选装备失效保留已付款")
					suite.check(not concrete or game.deck._discard.count(payment) == (1 if paid else 0), "E03e-15a：原具体拆顺支付一次")
					suite.check(source.determined_cards.has(armor) == (moved and snatch) and game.deck._discard.count(armor) == (1 if moved and not snatch else 0), "E03e-15a：仅合法选择移动原甲一次")
					suite.check(target.hp == (0 if action == "dead" else (9 if moved or action in ["same_armor", "empty"] else 8)), "E03e-15a：狮子只在实际失去时回血，关闭不失装备")
					suite.check(target.get_equipment_card("armor") == armor if action not in ["choose", "same_armor", "empty"] else target.get_equipment_card("armor") != armor, "E03e-15a：后来换入的同名甲不被旧答复移走")
					suite.check(game._choice_prompt_stack.is_empty(), "E03e-15a：选区和选装备等待清理")
					await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-15a：全部窗口实际释放")
	for snatch in [false, true]:
		for zone in ["hand", "judgment"]:
			reset()
			events.clear()
			var source = game.players[0]
			var target = game.players[1]
			var sub = CardData.CardSubType.SNATCH if snatch else CardData.CardSubType.DISMANTLE
			source.hand.append(null)
			var original = CardBase.create(CardData.CardSubType.INDULGENCE)
			if zone == "hand": target.hand.append(null)
			else: target.judgment_cards.append(original)
			var choose = func():
				var pending = game._choice_prompt_stack.back()
				var buttons = pending.overlay.find_children("*", "Button", true, false)
				suite.check(buttons[1].disabled and not game._countdown_active, "E03e-15a：空装备区禁用，其他合法区仍可选")
				buttons[0 if zone == "hand" else 2].pressed.emit()
			choose.call_deferred()
			await game.execute_card_on_target(target, sub)
			suite.check(events.size() == 1 and target.hand.is_empty() and target.judgment_cards.is_empty(), "E03e-15a：真实手牌/判定区按钮正常完成拆顺")
			suite.check(source.hand.size() == (1 if snatch and zone == "hand" else 0) and source.determined_cards.has(original) == (snatch and zone == "judgment") and game.deck._discard.count(original) == (1 if not snatch and zone == "judgment" else 0), "E03e-15a：任意手牌保持任意，具体判定牌原实例只移动一次")
			await suite.process_frame
	game.card_action_committed.disconnect(collect)
	reset()
	var target = game.players[1]
	target.hand.append(null)
	target.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.SILVER_LION))
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[1].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_zone_picker("获取", target) == "", "E03e-15a：选区关闭区别于取消")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._zone_pick_result.emit("equip")
		game._equip_pick_result.emit("armor")
		suite.check(not pending.answer.settled, "E03e-15a：旧选区回调/两个旧信号不污染新装备选择")
		pending.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_equip_picker(target, target.get_equip_slots()) == "armor", "E03e-15a：下一合法装备窗口仍可选择")
	await suite.process_frame
	reset()
	suite = null
	game = null
