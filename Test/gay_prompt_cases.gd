extends RefCounted

var suite
var game: GameManager
var windows: Array = []

func reset():
	suite.reset_players()
	game.deck._discard.clear()
	game._gay_used = false
	game._gay_x_override = Callable()
	game._hand_discard_override = Callable()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 0

func drive(action: String, actor: Player, target: Player):
	var pending = game._choice_prompt_stack.back()
	windows.append(pending.overlay)
	var buttons = pending.overlay.find_children("*", "Button", true, false)
	suite.check(buttons.size() == 4 and buttons[-1].text == "取消" and game._countdown_active, "E03e-17a：数量范围三张、原计时和取消保留")
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
			game.turn_manager.play_actor_idx = 1
			game.turn_manager.play_actor_idx = 0
		"gender": target.gender = "female"
		"healed": target.hp = target.max_hp
		"limit": target.max_hp = 1
		"hand": actor.hand.pop_back()
		"dead":
			target.hp = 0
			target.mark_dead()
		"skill": actor.general_name = "稻草人"
		"ended":
			game._finish_game("平局", "Gay数量选择测试")
			return
	if action == "yes":
		# 数量选择后真实手牌选择；选择第三张与第一张而非固定首两张。
		var pay = func():
			var current = game._choice_prompt_stack.back()
			var picker = current.overlay
			var choices = picker.find_children("*", "CheckButton", true, false)
			choices[2].button_pressed = true
			choices[0].button_pressed = true
			picker.confirm.pressed.emit()
		pay.call_deferred()
	buttons[3 if action == "cancel" else 1].pressed.emit()

func run(host):
	suite = host
	game = host.game
	for concrete in [false, true]:
		for action in ["yes", "cancel", "timeout", "close", "phase", "phase_idle", "actor", "gender", "healed", "limit", "hand", "dead", "skill", "ended"]:
			reset()
			var actor = game.players[0]
			var target = game.players[1]
			actor.general_name = "比尔·盖伊"
			actor.gender = "male"
			target.gender = "male"
			actor.max_hp = 5
			target.max_hp = 4
			actor.hp = 1
			target.hp = 1
			var first = CardBase.create(CardData.CardSubType.PEACH) if concrete else null
			var third = CardBase.create(CardData.CardSubType.DODGE) if concrete else null
			actor.hand.assign([first, null, third])
			# 手牌变成2张仍能支付2张，不制造仅手牌变化即全动作失效的新规则。
			if action != "yes": game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
			drive.call_deferred(action, actor, target)
			await game._execute_gay(actor, target)
			var success = action in ["yes", "hand"]
			suite.check(game._gay_used == success and actor.hp == (3 if success else 1), "E03e-17a：有效选择支付后回血并占次数，失效不发动")
			suite.check(target.hp == (0 if action == "dead" else (4 if action == "healed" else (3 if success else 1))), "E03e-17a：同性受伤目标才按X回血")
			suite.check(actor.hand_size() == (1 if action == "yes" else (0 if action == "hand" else 3)), "E03e-17a：任意及具体原费用一次支付，失效不扣牌")
			if concrete and action == "yes":
				suite.check(game.deck._discard.count(first) == 1 and game.deck._discard.count(third) == 1, "E03e-17a：真实多选支付第一/第三原实例，不固定扣前两张")
			suite.check(game._choice_prompt_stack.is_empty(), "E03e-17a：数量及支付等待清理")
			await suite.process_frame
	suite.check(windows.all(func(window): return not is_instance_valid(window)), "E03e-17a：数量窗口实际释放")
	reset()
	var old: Array = []
	var capture = func():
		var pending = game._choice_prompt_stack.back()
		old.append(pending.overlay.find_children("*", "Button", true, false)[0].get_signal_connection_list("pressed")[0].callable)
		old.append(game._countdown_on_timeout)
		pending.overlay.queue_free()
	capture.call_deferred()
	suite.check(await game._show_gay_x_picker(2) == GameManager.CHOICE_INVALID, "E03e-17a：关闭数量选择明确失效，不是主动取消")
	await suite.process_frame
	var next = func():
		var pending = game._choice_prompt_stack.back()
		old[0].call()
		old[1].call()
		suite.check(not pending.answer.settled and game._countdown_active, "E03e-17a：旧数量按钮/超时不污染下一合法窗口")
		pending.overlay.find_children("*", "Button", true, false)[1].pressed.emit()
	next.call_deferred()
	suite.check(await game._show_gay_x_picker(2) == 2, "E03e-17a：下一合法窗口可选两张")
	await suite.process_frame
	reset()
	game._hand_discard_override = Callable()
	suite = null
	game = null
