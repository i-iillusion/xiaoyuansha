extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._gou_lian_slot_override = Callable()
	game._sao_type_override = func(): return "mount"
	game._sao_transfer_declare_override = Callable()
	for p in game.players:
		p.mount_plus = 0
		p.mount_minus = 0
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(action: String, holder: Player, recipient: Player, card: CardBase):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	suite.check(pending.who == holder.player_name and holder == game.players[0], "E03e-9b：由原持有者声明而非取得者")
	suite.check(recipient.determined_cards.count(card) == 1 and not holder.has_hidden_equip(), "E03e-9b：先完成原对象离区入手，再询问声明")
	suite.check(game._countdown_active, "E03e-9b：沿用现有明置选择计时")
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	match action:
		"cancel":
			buttons.back().pressed.emit()
			return
		"timeout":
			game._countdown_on_timeout.call()
			return
		"close":
			pending.overlay.queue_free()
			return
		"phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
		"removed":
			recipient.remove_from_hand(card)
			holder.determined_cards.append(card)
		"holder_dead", "recipient_dead":
			var dead = holder if action == "holder_dead" else recipient
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "E03e-9b回归")
			return
	buttons[0].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		for action in ["choose", "cancel", "timeout", "close", "phase", "removed", "holder_dead", "recipient_dead", "ended"]:
			reset()
			var holder = game.players[0]
			var recipient = game.players[1]
			holder.general_name = "安普提·斯丢皮得"
			var original = CardBase.create(CardData.CardSubType.MOUNT_PLUS) if concrete else null
			if concrete: holder.determined_cards.append(original)
			else: holder.hand.append(null)
			await game._do_sao_hide(holder, false)
			var card = holder.get_hidden_equipment_card("mount_1")
			suite.check(card != null and holder.hand_size() == 0 and (not concrete or card == original), "E03e-9b：真实苕支付任意/具体牌，原坐骑对象保留")
			recipient.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
			var kill = CardBase.create(CardData.CardSubType.STRIKE)
			recipient.determined_cards.append(kill)
			game.turn_manager.play_actor_idx = 1
			drive.call_deferred(action, holder, recipient, card)
			await game.execute_card_on_target(holder, CardData.CardSubType.STRIKE)
			var declared = action in ["choose", "cancel", "timeout"]
			var correct_name = card.sub_type == CardData.CardSubType.MOUNT_PLUS if concrete else (
				card.sub_type == game.SAO_MOUNT_SUBS[0] if action == "choose" else card.sub_type in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS])
			suite.check(correct_name if declared else card.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT, "E03e-9b：合法声明/取消默认与等待失效分开：" + action)
			suite.check(recipient.determined_cards.count(card) == (0 if action == "removed" else 1)
				and not holder.equipment.has("mount_1") and not game.deck._discard.has(card), "E03e-9b：声明失效不撤销已移动资源或吞牌")
			suite.check(holder.hp == (0 if action == "holder_dead" else 9) and game.deck._discard.count(kill) == 1, "E03e-9b：原伤害和原杀支付不回滚")
			suite.check(recipient.mount_count() == 0 and recipient.mount_plus == 0 and recipient.mount_minus == 0, "E03e-9b：拿到手牌不授坐骑效果")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-9b：声明等待结束")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-9b：声明节点实际释放")
	# 原持有者非0号仍按原AI声明策略；取得者0号仅选择哪匹马。
	reset()
	var holder = game.players[1]
	var recipient = game.players[0]
	holder.general_name = "安普提·斯丢皮得"
	holder.hand.append(null)
	game.turn_manager.play_actor_idx = 1
	await game._do_sao_hide(holder, false)
	var card = holder.get_hidden_equipment_card("mount_1")
	game.turn_manager.play_actor_idx = 0
	recipient.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.GOU_LIAN_CLAW))
	recipient.hand.append(null)
	game._gou_lian_slot_override = func(): return "mount_1"
	await game.execute_card_on_target(holder, CardData.CardSubType.STRIKE)
	suite.check(holder.hp == 9 and recipient.determined_cards == [card] and card.sub_type == game.SAO_MOUNT_SUBS[0], "E03e-9b：非0号原持有者声明，原对象入0号手牌")
	reset()
	game._sao_type_override = Callable()
	suite = null
	game = null
