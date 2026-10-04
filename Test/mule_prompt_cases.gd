extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._minus_mule_target_override = Callable()
	game._plus_mule_target_override = Callable()
	game._calamity_target_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null
		p.mount_plus = 0
		p.mount_minus = 0

func drive(action: String, victim: Player, target: Player, sub: int):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 5 and not game._countdown_active, "E03e-13a：劣马其他存活目标及取消，保持无计时")
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
			game.turn_manager.play_actor_idx = 2
			game.turn_manager.play_actor_idx = 1
		"mount", "same_mount":
			victim.determined_cards.append(victim.remove_equipment(Player.MOUNT_SLOTS[2]))
			if action == "same_mount": victim.equip_card_to_slot(Player.MOUNT_SLOTS[2], CardBase.create(sub))
		"victim_dead", "target_dead":
			var dead = victim if action == "victim_dead" else target
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "劣马选择回归")
			return
	buttons[1].pressed.emit()
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
		for concrete in [false, true]:
			for action in ["choose", "cancel", "close", "phase", "phase_idle", "actor", "mount", "same_mount", "victim_dead", "target_dead", "ended"]:
				reset()
				events.clear()
				var source = game.players[1]
				var victim = game.players[0]
				var target = game.players[2]
				var mule = CardBase.create(sub)
				victim.equip_card_to_slot(Player.MOUNT_SLOTS[2], mule)
				var old_plus = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
				var old_minus = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
				target.equip_card_to_slot(Player.MOUNT_SLOTS[0], old_plus)
				target.equip_card_to_slot(Player.MOUNT_SLOTS[1], old_minus)
				var calls: Array = []
				game._calamity_target_override = func():
					calls.append(true)
					return "cancel"
				source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.CALAMITY_SWORD))
				source.wine_stacks = 1
				var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
				if concrete: source.determined_cards.append(kill)
				else: source.hand.append(null)
				game.turn_manager.play_actor_idx = 1
				drive.call_deferred(action, victim, target, sub)
				await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
				var moved = action == "choose"
				suite.check(victim.hp == (0 if action == "victim_dead" else 9), "E03e-13a：真实酒杀减伤已提交，不因劣马选择过期回滚")
				suite.check(target.get_equipment_card(Player.MOUNT_SLOTS[2]) == (mule if moved else null), "E03e-13a：原马仅进入目标空槽，失效不转后来者")
				suite.check(target.get_equipment_card(Player.MOUNT_SLOTS[0]) == old_plus and target.get_equipment_card(Player.MOUNT_SLOTS[1]) == old_minus and target.mount_plus == 1 and target.mount_minus == 1, "E03e-13a：非满槽转移不弃其他马或改变普通马计数")
				suite.check((victim.get_equipment_card(Player.MOUNT_SLOTS[2]) == mule) == (not moved and action not in ["mount", "same_mount"]), "E03e-13a：原实例唯一，换同名马不误转移")
				suite.check(not game.deck._discard.has(mule) and not game.deck._discard.has(old_plus) and not game.deck._discard.has(old_minus), "E03e-13a：非满槽转移不弃原马或目标原牌")
				suite.check(calls.size() == (1 if action in ["choose", "cancel"] else 0), "E03e-13a：取消继续原剑后效，失效停止旧动作")
				suite.check(events.size() == 1 and source.hand_size() == 0 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-13a：原杀支付和使用事件各一次")
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-13a：独立等待清理")
				await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-13a：窗口全部释放")
		reset()
		var old_callbacks: Array = []
		var capture = func():
			var pending = game._choice_prompt_stack.back()
			old_callbacks.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
			pending.overlay.queue_free()
		capture.call_deferred()
		suite.check(await game._show_mule_target_picker(game.players[0], sub == CardData.CardSubType.MULE_MINUS) == GameManager.CHOICE_INVALID, "E03e-13a：关闭是失效，不是放弃")
		await suite.process_frame
		var next = func():
			var pending = game._choice_prompt_stack.back()
			old_callbacks[0].call()
			game._minus_mule_target_result.emit(game.players[1])
			game._plus_mule_target_result.emit(game.players[2])
			suite.check(not pending.answer.settled, "E03e-13a：两种劣马旧共享信号和按钮不污染新窗口")
			pending.overlay.find_children("*", "Button", true, false)[-1].pressed.emit()
		next.call_deferred()
		suite.check(await game._show_mule_target_picker(game.players[0], sub != CardData.CardSubType.MULE_MINUS) == null, "E03e-13a：跨种下一窗口可合法取消")
		await suite.process_frame
	game.card_action_committed.disconnect(collect)
	reset()
	suite = null
	game = null
