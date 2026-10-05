extends RefCounted

var suite
var game: GameManager
var windows: Array = []
var asks := 0
var rounds := 0

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game._clear_pending_determined_card()
	game._kaiwen_override = Callable()
	game._rps_override = func(p): return GameManager.RPS_ROCK if p.seat_index == 0 else GameManager.RPS_SCISSORS
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 1
	asks = 0
	rounds = 0
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null

func drive(action: String, owner: Player, opponent: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 2 and game._countdown_active, "E03e-16d：凯文原两按钮和响应计时保留")
	match action:
		"close":
			pending.overlay.queue_free()
			return
		"timeout":
			game._countdown_on_timeout.call()
			return
		"phase", "phase_idle":
			game.turn_manager.current_phase = TurnManager.Phase.END
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			if action == "phase_idle": return
		"actor":
			game.turn_manager.play_actor_idx = 2
			game.turn_manager.play_actor_idx = 1
		"owner_dead", "opponent_dead":
			var dead = owner if action == "owner_dead" else opponent
			dead.hp = 0
			dead.mark_dead()
		"skill": owner.general_name = "稻草人"
		"ended":
			game._finish_game("平局", "凯文确认测试")
			return
	buttons[1 if action == "no" else 0].pressed.emit()
	game._response_ready.emit() # 原共享信号不得再提交此窗口。

func real_rps():
	var pending = game._choice_prompt_stack.back()
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	if buttons.size() == 2:
		suite.check(game._countdown_active, "E03e-16d：实际视觉停顿后确认仍有计时")
		real_rps.call_deferred()
		buttons[0].pressed.emit()
		return
	rounds += 1
	suite.check(buttons.size() == 3 and game._countdown_active, "E03e-16d：凯文真实出拳保持计时")
	seed(104)
	var opponent = randi() % 3
	seed(104)
	var gesture = opponent if rounds == 1 else (opponent + 1) % 3
	# 使用既有RPS映射求获胜手势，不把循环数字顺序当玩法。
	if rounds == 2:
		for pick in 3:
			if game._rps_result(pick, opponent) == GameManager.RPS_WIN: gesture = pick
	if rounds == 1: real_rps.call_deferred()
	buttons[[0, 2, 1][gesture]].pressed.emit()

func after_visual_delay():
	while game._choice_prompt_stack.is_empty():
		await suite.process_frame
	real_rps()

func run(host):
	suite = host
	game = host.game
	for receive in [false, true]:
		for action in ["yes", "no", "timeout", "close", "phase", "phase_idle", "actor", "owner_dead", "opponent_dead", "skill", "ended", "second_close"]:
			reset()
			var owner = game.players[0]
			var opponent = game.players[1]
			owner.general_name = "凯文·罗本"
			var revision = game.turn_manager.get_context_revision()
			# 仅绕过0.8秒视觉停顿：仍调用真实窗口/真实伤害链/实际摸牌。
			var valid = func():
				return not game._game_over and revision == game.turn_manager.get_context_revision() and owner.is_alive() and opponent.is_alive() and owner.general_name == "凯文·罗本"
			game._kaiwen_override = func():
				asks += 1
				drive.call_deferred("close" if action == "second_close" and asks == 2 else ("yes" if action == "second_close" else action), owner, opponent)
				return await game._show_kaiwen_prompt(opponent.player_name, receive, valid)
			var source = opponent if receive else owner
			var victim = owner if receive else opponent
			var amount = 2 if action in ["yes", "no", "timeout", "second_close"] else 1
			var chain = game._new_damage_chain(source, victim, null, amount, EffectChain.DamageType.PHYSICAL)
			chain.skip_targeting = true
			chain.skip_response = true
			await chain.start()
			await game._finish_damage_chain(chain)
			var invalid = action not in ["yes", "no", "timeout"]
			suite.check(chain.continuation_invalid == invalid and chain.damage.committed and not chain.is_cancelled, "E03e-16d：失效停止后效，不冒充防止原伤害")
			suite.check(victim.hp == (0 if action == ("owner_dead" if receive else "opponent_dead") else 10 - amount), "E03e-16d：原伤害实际提交且不回滚")
			suite.check(owner.hand_size() == (4 if action == "yes" else (2 if action == "second_close" else 0)), "E03e-16d：每点自愿发动赢摸两张，后一窗口失效保留前次摸牌")
			suite.check(asks == amount and game._choice_prompt_stack.is_empty(), "E03e-16d：按点询问、失效不再重问、等待清理")
			await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-16d：凯文确认节点实际释放")
	for receive in [false, true]:
		reset()
		game._kaiwen_override = Callable()
		game._rps_override = Callable()
		var owner = game.players[0]
		var opponent = game.players[1]
		owner.general_name = "凯文·罗本"
		after_visual_delay.call_deferred()
		await game._deal_damage(opponent if receive else owner, owner if receive else opponent, 1, EffectChain.DamageType.PHYSICAL)
		suite.check(rounds == 2 and owner.hand_size() == 2, "E03e-16d：无确认/出拳钩子，真实平局重猜后获胜只摸两张")
		await suite.process_frame
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		old.append(game._countdown_on_timeout)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_kaiwen_prompt("B", false) == GameManager.CHOICE_INVALID, "E03e-16d：关闭返回显式失效")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		old[1].call()
		game._response_ready.emit()
		suite.check(not pending.answer.settled and game._countdown_active, "E03e-16d：旧按钮/超时/共享信号不污染新窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_kaiwen_prompt("B", true) == 0, "E03e-16d：下一合法窗口可主动不发动")
	await suite.process_frame
	reset()
	game._rps_override = Callable()
	game._kaiwen_override = Callable()
	suite = null
	game = null
