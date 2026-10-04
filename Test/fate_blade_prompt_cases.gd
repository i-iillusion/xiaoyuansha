extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._fate_blade_override = Callable()
	game._dying_peach_override = func(): return true
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 1

func drive(action: String, victim: Player, source: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(not game._countdown_active, "E03e-8：命运窗口保留无计时")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"phase":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
		"actor":
			game.turn_manager.play_actor_idx = 2
			game.turn_manager.play_actor_idx = 1
		"weapon", "same_weapon":
			victim.determined_cards.append(victim.remove_equipment("weapon"))
			if action == "same_weapon":
				victim.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FATE_BLADE))
		"healed": victim.heal(1)
		"victim_dead":
			victim.hp = 0
			victim.mark_dead()
		"source_dead", "source_dead_no":
			source.hp = 0
			source.mark_dead()
		"ended":
			game._finish_game("平局", "E03e-8回归")
			return
	buttons[1 if action in ["no", "source_dead_no"] else 0].pressed.emit()
	pending.answer.submit(1)

func run(host):
	suite = host
	game = host.game
	var victim = game.players[0]
	var old_identity = victim.identity
	var old_revealed = victim.identity_revealed
	# 给真实拒绝路径一张桃，救援由统一支付入口完成，避免夹具死亡清牌掩盖费用。
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["yes", "no", "close", "phase", "actor", "weapon", "same_weapon", "healed", "victim_dead", "source_dead", "source_dead_no", "ended"]:
			reset()
			events.clear()
			victim.identity = "反贼"
			victim.identity_revealed = false
			victim.hp = 1
			var source = game.players[1]
			var blade = CardBase.create(CardData.CardSubType.FATE_BLADE)
			victim.equip_card_to_slot("weapon", blade)
			var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
			if concrete: source.determined_cards.append(kill)
			else: source.hand.append(null)
			var peach = CardBase.create(CardData.CardSubType.PEACH)
			victim.determined_cards.append(peach)
			game._rescue_choice_override = func(rescuer, _dying, options):
				return CardData.CardSubType.PEACH if rescuer == victim and options.has(CardData.CardSubType.PEACH) else -1
			drive.call_deferred(action, victim, source)
			await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
			var prevented = action in ["yes", "source_dead"]
			var damaged = action in ["no", "source_dead_no"]
			suite.check(victim.hp == (0 if action == "victim_dead" else (2 if action == "healed" else 1)), "E03e-8：保命/拒绝救援/失效体力：" + action)
			suite.check(game.deck._discard.count(blade) == (1 if prevented else 0), "E03e-8：仅有效发动弃原命运一次")
			suite.check(game.deck._discard.count(peach) == (1 if damaged else 0), "E03e-8：只有真实拒绝伤害进入求救支付")
			suite.check(events.size() == (2 if damaged else 1) and (not concrete or game.deck._discard.count(kill) == 1), "E03e-8：原杀已付不退款，保命不额外用牌")
			suite.check(not victim.identity_revealed and game._choice_prompt_stack.is_empty(), "E03e-8：救回/防止不亮身份，等待结束")
			if action == "same_weapon":
				suite.check(victim.get_equipment_card("weapon") != blade and victim.get_equipment_card("weapon") != null, "E03e-8：不弃后来换入同名实例")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-8：命运窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	victim.hp = 1
	victim.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FATE_BLADE))
	var source = game.players[1]
	var chain = game._new_damage_chain(source, victim, CardBase.create(CardData.CardSubType.STRIKE), 1, EffectChain.DamageType.PHYSICAL)
	game._rescue_choice_override = func(rescuer, _dying, options):
		return CardData.CardSubType.PEACH if rescuer == victim and options.has(CardData.CardSubType.PEACH) else -1
	victim.determined_cards.append(CardBase.create(CardData.CardSubType.PEACH))
	drive.call_deferred("source_dead_no", victim, source)
	await chain.start()
	suite.check(chain.damage.committed and chain.damage.source == null, "E03e-8：来源死亡拒绝保命后余伤真实无源提交")
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_fate_blade_prompt(victim) == game.CHOICE_INVALID, "E03e-8：关闭与拒绝不同")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		game._response_ready.emit()
		suite.check(not pending.answer.settled, "E03e-8：旧按钮/响应信号不污染下次")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_fate_blade_prompt(victim) == 0, "E03e-8：下一合法拒绝正常完成")
	await suite.process_frame
	for reply in [true, false, -2]:
		game._fate_blade_override = func(): return reply
		suite.check(await game._show_fate_blade_prompt(victim) == (-2 if typeof(reply) == TYPE_INT else (1 if reply else 0)), "E03e-8：bool钩子兼容失效整数")
	reset()
	game._fate_blade_override = func():
		suite.check(false, "E03e-8：非致命或已减伤不应询问")
		return true
	victim.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.FATE_BLADE))
	suite.check(await game._try_fate_blade_save(victim, 1) == 0, "E03e-8：非致命不触发")
	victim.hp = 1
	victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.BAIHUA_SKIRT))
	await suite.strike(game.players[1], victim)
	suite.check(victim.hp == 1 and victim.get_weapon() == CardData.CardSubType.FATE_BLADE, "E03e-8：百花防伤先于致命保命")
	reset()
	victim.identity = old_identity
	victim.identity_revealed = old_revealed
	game._fate_blade_override = Callable()
	suite = null
	game = null
