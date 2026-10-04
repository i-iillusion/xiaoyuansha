extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func drive(action: String, victim: Player, target: Player, mule: CardBase):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 4 and not game._countdown_active and buttons.all(func(b): return b.text != "取消"), "E03e-13b：转移者选择目标四槽，无计时/无拒绝按钮")
	suite.check(victim.get_equipment_card(Player.MOUNT_SLOTS[1]) == mule, "E03e-13b：选择之前原马仍在转移者装备区")
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
			game.turn_manager.play_actor_idx = 2
		"source_mount":
			victim.determined_cards.append(victim.remove_equipment(Player.MOUNT_SLOTS[1]))
			victim.equip_card_to_slot(Player.MOUNT_SLOTS[1], CardBase.create(mule.sub_type))
		"target_mount":
			target.determined_cards.append(target.remove_equipment(Player.MOUNT_SLOTS[2]))
			target.equip_card_to_slot(Player.MOUNT_SLOTS[2], CardBase.create(CardData.CardSubType.MOUNT_PLUS))
		"target_dead":
			target.hp = 0
			target.mark_dead()
		"ended":
			game._finish_game("平局", "满槽劣马回归")
			return
	buttons[2].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var prompt = load("res://Test/mule_prompt_cases.gd").new()
	prompt.suite = suite
	prompt.game = game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
		for concrete in [false, true]:
			for hidden in [false, true]:
				for action in ["choose", "close", "phase", "phase_idle", "actor", "source_mount", "target_mount", "target_dead", "ended"]:
					prompt.reset()
					var victim = game.players[0]
					var target = game.players[1]
					var attacker = game.players[2]
					var mule = CardBase.create(sub)
					victim.equip_card_to_slot(Player.MOUNT_SLOTS[1], mule)
					var originals: Dictionary = {}
					for index in [0, 1, 3]:
						var old = CardBase.create(CardData.CardSubType.MOUNT_PLUS if index == 0 else CardData.CardSubType.MOUNT_MINUS)
						target.equip_card_to_slot(Player.MOUNT_SLOTS[index], old)
						originals[index] = old
					var replaced: CardBase
					if hidden:
						target.general_name = "安普提·斯丢皮得"
						target.hand.append(null)
						game.turn_manager.play_actor_idx = 1
						game._sao_type_override = func(): return "mount"
						await game._do_sao_hide(target, false)
						game._sao_type_override = Callable()
						replaced = target.get_hidden_equipment_card(Player.MOUNT_SLOTS[2])
						suite.check(replaced != null and target.hand_size() == 0, "E03e-13b：目标真实支付任意手牌暗置马至最后空槽")
					else:
						replaced = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
						target.equip_card_to_slot(Player.MOUNT_SLOTS[2], replaced)
					var declarations: Array = []
					game._sao_reveal_sub_override = func():
						declarations.append(true)
						return CardData.CardSubType.MULE_PLUS
					if sub == CardData.CardSubType.MULE_MINUS: game._minus_mule_target_override = func(): return target
					else: game._plus_mule_target_override = func(): return target
					attacker.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.QILING_BOW))
					var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
					if concrete: attacker.determined_cards.append(kill)
					else: attacker.hand.append(null)
					game.turn_manager.play_actor_idx = 2
					events.clear()
					drive.call_deferred(action, victim, target, mule)
					await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
					var moved = action == "choose"
					suite.check(victim.hp == 9 and events.size() == 1 and attacker.hand_size() == 0 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-13b：原杀已造成伤害及支付保留一次")
					suite.check(target.get_equipment_card(Player.MOUNT_SLOTS[2]) == mule if moved else not target.equipment_cards.values().has(mule), "E03e-13b：由人类转移者选择目标第三槽，不固定第一槽")
					suite.check(originals.keys().all(func(index): return target.get_equipment_card(Player.MOUNT_SLOTS[index]) == originals[index]), "E03e-13b：非选中槽原牌不弃不换")
					suite.check(game.deck._discard.count(replaced) == (1 if moved else 0) and not game.deck._discard.has(mule), "E03e-13b：只弃被选择原马一次，转移原马不入弃")
					suite.check(declarations.is_empty() and (not hidden or replaced.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT), "E03e-13b：被顶掉暗置马仍暗置，不声明")
					suite.check((victim.get_equipment_card(Player.MOUNT_SLOTS[1]) == mule) == (not moved and action != "source_mount") and game._choice_prompt_stack.is_empty(), "E03e-13b：失效不移后来换入原马，等待已结束")
					await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-13b：全部转移选槽窗口释放")
	# A是AI而B是人类时，选择权仍在A，不应错误弹出B的选择窗口。
	for sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
		prompt.reset()
		var victim = game.players[1]
		var target = game.players[0]
		var mule = CardBase.create(sub)
		victim.equip_card_to_slot(Player.MOUNT_SLOTS[1], mule)
		var old_cards: Array = []
		for slot in Player.MOUNT_SLOTS:
			var old = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
			old_cards.append(old)
			target.equip_card_to_slot(slot, old)
		if sub == CardData.CardSubType.MULE_MINUS: game._minus_mule_target_override = func(): return target
		else: game._plus_mule_target_override = func(): return target
		await game._deal_damage(game.players[2], victim, 1, EffectChain.DamageType.PHYSICAL)
		suite.check(victim.hp == 9 and target.get_equipment_card(Player.MOUNT_SLOTS[0]) == mule and game._choice_prompt_stack.is_empty(), "E03e-13b：AI转移者自行选择，不把选择权给人类目标")
		suite.check(game.deck._discard == [old_cards[0]] and target.mount_plus == 3 and target.mount_count() == 4, "E03e-13b：AI策略只顶选中原马，目标计数同步")
		await suite.process_frame
	prompt.reset()
	var target = game.players[1]
	for slot in Player.MOUNT_SLOTS: target.equip_card_to_slot(slot, CardBase.create(CardData.CardSubType.MOUNT_PLUS))
	var old_callbacks: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old_callbacks.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_mule_replace_picker(target, func(): return true) == "", "E03e-13b：外部关闭选槽明确失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old_callbacks[0].call()
		game._minus_mule_target_result.emit(target)
		game._plus_mule_target_result.emit(target)
		suite.check(not pending.answer.settled and not game._countdown_active, "E03e-13b：旧按钮及旧目标信号不提交新强制窗口")
		pending.overlay.find_children("*", "Button", true, false)[2].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_mule_replace_picker(target, func(): return true) == Player.MOUNT_SLOTS[2], "E03e-13b：旧窗口关闭后下一合法第三槽选择可完成")
	await suite.process_frame
	game.card_action_committed.disconnect(collect)
	game._sao_reveal_sub_override = Callable()
	prompt.reset()
	prompt.suite = null
	prompt.game = null
	suite = null
	game = null
