extends RefCounted

var suite
var game: GameManager
var windows: Array = []
var asks := 0
var rounds := 0

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game._bloodthirsty_override = Callable()
	game._rps_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	asks = 0
	rounds = 0

# 只固定现有AI随机源，不绕过人类真实出拳入口或改变AI策略。
func gesture_for(result: int) -> int:
	seed(104)
	var opponent = randi() % 3
	seed(104)
	for gesture in 3:
		if game._rps_result(gesture, opponent) == result: return gesture
	return -1

func drive(action: String, invalid_point: int, source: Player, victim: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	if buttons.size() == 2:
		asks += 1
		suite.check(not game._countdown_active, "E03e-10b：每点确认无计时")
		var decline = asks == 2 and action in ["tie_win_decline", "lose_decline", "timeout_win_decline"]
		if not decline: drive.call_deferred(action, invalid_point, source, victim)
		buttons[1 if decline else 0].pressed.emit()
		return
	rounds += 1
	suite.check(buttons.size() == 3 and game._countdown_active, "E03e-10b：真实出拳三手势，保留倒计时")
	if asks == invalid_point:
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
			"weapon", "same_weapon":
				source.determined_cards.append(source.remove_equipment("weapon"))
				if action == "same_weapon": source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
			"shield": victim.equip_card_to_slot("armor", CardBase.create(CardData.CardSubType.QINGGANG_SHIELD))
			"source_dead", "victim_dead":
				var dead = source if action == "source_dead" else victim
				dead.hp = 0
				dead.mark_dead()
			"ended":
				game._finish_game("平局", "E03e-10b回归")
				return
		buttons[0].pressed.emit()
		return
	if asks == 1 or (action == "tie_win_decline" and rounds == 1):
		drive.call_deferred(action, invalid_point, source, victim)
	if action == "timeout_win_decline":
		# 找到下一次AI出石头的种子，超时布按现有规则取胜。
		for candidate in range(1, 100):
			seed(candidate)
			if randi() % 3 == GameManager.RPS_ROCK:
				seed(candidate)
				break
		game._countdown_on_timeout.call()
		return
	var desired = GameManager.RPS_WIN
	if action == "tie_win_decline" and rounds == 1: desired = GameManager.RPS_DRAW
	if action == "lose_decline": desired = GameManager.RPS_LOSE
	var gesture = gesture_for(desired)
	# 按钮顺序石头、剪刀、布，常量顺序石头、布、剪刀。
	buttons[[0, 2, 1][gesture]].pressed.emit()
	pending.answer.submit(GameManager.RPS_PAPER)

func run(host):
	suite = host
	game = host.game
	var events: Array = []
	var collect = func(event): events.append(event)
	game.card_action_committed.connect(collect)
	for concrete in [false, true]:
		for action in ["win_win", "tie_win_decline", "lose_decline", "timeout_win_decline", "close", "phase", "phase_idle", "actor", "weapon", "same_weapon", "shield", "source_dead", "victim_dead", "ended"]:
			for invalid_point in ([0] if action in ["win_win", "tie_win_decline", "lose_decline", "timeout_win_decline"] else [1, 2]):
				reset()
				events.clear()
				var source = game.players[0]
				var victim = game.players[1]
				source.hp = 8
				source.wine_stacks = 1
				source.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
				var kill = CardBase.create(CardData.CardSubType.STRIKE) if concrete else null
				if concrete: source.determined_cards.append(kill)
				else: source.hand.append(null)
				drive.call_deferred(action, invalid_point, source, victim)
				await game.execute_card_on_target(victim, CardData.CardSubType.STRIKE)
				var wins = 2 if action == "win_win" else (1 if action in ["tie_win_decline", "timeout_win_decline"] or invalid_point == 2 else 0)
				suite.check(source.hp == (0 if action == "source_dead" else 8 + wins), "E03e-10b：只有效获胜回复，已回复不撤销：" + action + str(invalid_point))
				suite.check(victim.hp == (0 if action == "victim_dead" else 8), "E03e-10b：出拳失效不撤销已造成伤害")
				suite.check(asks == (2 if invalid_point == 0 else invalid_point), "E03e-10b：平局不重问发动，失效不进入下一点")
				suite.check(rounds == (1 if action in ["lose_decline", "timeout_win_decline"] else (2 if invalid_point == 0 else invalid_point)), "E03e-10b：平局重猜，不重复获得本点回血")
				suite.check(events.size() == 1 and source.hand.is_empty() and (not concrete or game.deck._discard.count(kill) == 1), "E03e-10b：不增加拼点费用及用牌事件")
				suite.check(game._choice_prompt_stack.is_empty(), "E03e-10b：确认及出拳等待清理")
		await suite.process_frame
		suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-10b：组合窗口实际释放")
	game.card_action_committed.disconnect(collect)
	reset()
	var source = game.players[0]
	var victim = game.players[1]
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		old.append(game._countdown_on_timeout)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_rps_prompt(source, victim.player_name) == GameManager.RPS_INVALID, "E03e-10b：真实出拳关闭明确失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		old[1].call()
		suite.check(not pending.answer.settled and game._countdown_active, "E03e-10b：已释放窗口旧按钮/旧超时不污染新出拳")
		pending.overlay.find_children("*", "Button", true, false)[2].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_rps_prompt(source, victim.player_name) == GameManager.RPS_PAPER, "E03e-10b：下一合法布按钮正确映射")
	await suite.process_frame
	reset()
	# 防御性混合嵌套只验证计时所有权，不宣称可同时发动多个技能。
	var nested = func():
		var outer = game._choice_prompt_stack.back()
		game._step_remaining = 12.0
		var outer_timeout = game._countdown_on_timeout
		var skip = func():
			var pending = game._choice_prompt_stack.back()
			outer_timeout.call()
			suite.check(not game._countdown_active and not pending.answer.settled and not outer.answer.settled, "E03e-10b：确认暂停出拳计时，旧超时不替两者答复")
			pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
		skip.call_deferred()
		suite.check(await game._show_bloodthirsty_prompt(source, victim) == 0, "E03e-10b：嵌套确认仍可主动放弃")
		suite.check(game._countdown_active and game._step_remaining == 12.0 and not outer.answer.settled, "E03e-10b：确认结束恢复出拳剩余时间")
		var scissors = func():
			var pending = game._choice_prompt_stack.back()
			suite.check(game._countdown_active and game._step_remaining == game.STEP_SECONDS, "E03e-10b：内层出拳取得自身计时")
			pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
		scissors.call_deferred()
		suite.check(await game._show_rps_prompt(source, victim.player_name) == GameManager.RPS_SCISSORS, "E03e-10b：内层剪刀按钮映射正确")
		suite.check(game._step_remaining == 12.0 and not outer.answer.settled, "E03e-10b：内层结束不重置或结算外层")
		outer.overlay.find_children("*", "Button", true, false)[0].pressed.emit()
	nested.call_deferred()
	suite.check(await game._show_rps_prompt(source, victim.player_name) == GameManager.RPS_ROCK and game._choice_prompt_stack.is_empty(), "E03e-10b：外层石头独立完成，混合嵌套等待清空")
	await suite.process_frame
	reset()
	suite = null
	game = null
