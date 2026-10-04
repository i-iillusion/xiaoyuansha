extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._calamity_robe_target_override = Callable()
	game._plus_mule_target_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(action: String, victim: Player, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 5 and not game._countdown_active, "E03e-12a：其他存活角色及取消，保持无计时")
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
		"robe", "same_robe":
			victim.determined_cards.append(victim.remove_equipment("armor"))
			if action == "same_robe": victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.CALAMITY_ROBE))
		"victim_dead", "target_dead":
			var dead = victim if action == "victim_dead" else target
			dead.hp = 0
			dead.mark_dead()
		"ended":
			game._finish_game("平局", "灾厄袍选择回归")
			return
	buttons[1].pressed.emit() # 其他角色列表1、2、3、4，选2。
	pending.answer.submit(0)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for sub in [CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE]:
			for action in ["choose", "cancel", "close", "phase", "phase_idle", "actor", "robe", "same_robe", "victim_dead", "target_dead", "ended"]:
				reset()
				events.clear()
				var source = game.players[1]
				var victim = game.players[0]
				var target = game.players[2]
				var robe = CardBase.create(CardData.CardSubType.CALAMITY_ROBE)
				var old = CardBase.create(CardData.CardSubType.SILVER_LION)
				victim.equip_card_to_slot("armor", robe)
				victim.equip_card_to_slot(Player.MOUNT_SLOTS[0], CardBase.create(CardData.CardSubType.MULE_PLUS))
				target.hp = 8
				target.equip_card_to_slot("armor", old)
				var calls: Array = []
				game._plus_mule_target_override = func():
					calls.append(true)
					return "cancel"
				var kill = CardBase.create(sub) if concrete else null
				if concrete: source.determined_cards.append(kill)
				else: source.hand.append(null)
				game.turn_manager.play_actor_idx = 1
				drive.call_deferred(action, victim, target)
				await game.execute_card_on_target(victim, sub)
				var moved = action == "choose"
				suite.check(victim.hp == (0 if action == "victim_dead" else (8 if sub == CardData.CardSubType.FIRE_STRIKE else 9)), "E03e-12a：受伤已提交；原袍火伤加一，不因窗口失效回滚")
				suite.check(target.get_equipment_card("armor") == (robe if moved else old), "E03e-12a：仅合法选择转移原袍并替换目标原甲")
				suite.check(target.hp == (0 if action == "target_dead" else (9 if moved else 8)), "E03e-12a：真实替换狮子回血一次，失效不失牌回血")
				suite.check(game.deck._discard.count(old) == (1 if moved else 0) and not game.deck._discard.has(robe), "E03e-12a：旧甲仅弃一次，原袍不弃置")
				suite.check((victim.get_equipment_card("armor") == robe) == (not moved and action not in ["robe", "same_robe"]), "E03e-12a：同名新实例不能被旧窗口转走")
				suite.check(calls.size() == (1 if action in ["choose", "cancel"] else 0), "E03e-12a：自愿取消继续劣马，过期动作不继续受伤后效")
				suite.check(events.size() == 1 and source.hand_size() == 0 and (not concrete or game.deck._discard.count(kill) == 1), "E03e-12a：真实原杀支付一次，不因选择失效返还或重复使用")
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-12a：等待结束")
				await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-12a：所有窗口实际释放")
	for concrete in [false, true]:
		for action in ["cancel", "close", "phase"]:
			reset()
			events.clear()
			var source = game.players[1]
			var victim = game.players[0]
			var target = game.players[2]
			victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.CALAMITY_ROBE))
			source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FANGTIAN_HALBERD))
			if concrete: source.determined_cards.append(CardBase.create(CardData.CardSubType.STRIKE))
			else: source.hand.append(null)
			game.turn_manager.play_actor_idx = 1
			var targets: Array[Player] = [victim, target]
			drive.call_deferred(action, victim, target)
			await game.execute_multi_strike(targets, CardData.CardSubType.STRIKE)
			suite.check(victim.hp == 9 and target.hp == (9 if action == "cancel" else 10), "E03e-12a：方天真实首目标袍窗口取消继续、失效停止后续目标")
			suite.check(events.size() == 1 and source.hand_size() == 0 and game._choice_prompt_stack.is_empty(), "E03e-12a：多目标原杀只支付一次，等待清理")
			await suite.process_frame
	reset()
	var old_callbacks: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old_callbacks.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_calamity_robe_target_picker(game.players[0]) == GameManager.CHOICE_INVALID, "E03e-12a：关闭返回失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old_callbacks[0].call()
		game._calamity_robe_target_result.emit(game.players[1])
		suite.check(not pending.answer.settled, "E03e-12a：旧按钮和共享信号不污染新选择")
		pending.overlay.find_children("*", "Button", true, false)[-1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_calamity_robe_target_picker(game.players[0]) == null, "E03e-12a：合法取消与失效不同")
	await suite.process_frame
	game.card_action_committed.disconnect(collect)
	reset()
	suite = null
	game = null
