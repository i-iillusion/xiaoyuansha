extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "选牌：" + label)

func run(host):
	suite = host
	game = host.game
	suite.reset_players()
	var p = game.players[0]
	var first = CardBase.create(CardData.CardSubType.STRIKE)
	var second = CardBase.create(CardData.CardSubType.PEACH)
	p.hand.assign([null, first, null])
	p.determined_cards.append(second)
	var snapshot = HandSelection.new(p)
	check(snapshot.take([0, 0], 2).is_empty() and p.hand_size() == 4, "重复索引无副作用")
	check(snapshot.take([4], 1).is_empty() and snapshot.take([-1], 1).is_empty(), "越界索引拒绝")
	check(snapshot.take([1], 2).is_empty(), "不足数量不能部分支付")
	check(snapshot.take([3, 0], 2) == [second, null], "明确选择跨区具体牌与一张任意牌")
	check(p.hand == [first, null] and p.determined_cards.is_empty(), "保留未选中的另一张任意牌")
	check(snapshot.take([1], 1).is_empty(), "过期快照不可重复支付")
	snapshot = HandSelection.new(p)
	p.hand.reverse()
	check(snapshot.take([0], 1).is_empty(), "等待期间重排牌区不按旧位置误扣")

	for mode in ["confirm", "cancel", "timeout", "mandatory", "moved", "ended"]:
		suite.reset_players()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.DISCARD
		game._hand_discard_override = Callable()
		p.hand.append(first)
		p.determined_cards.append(second)
		var action = func():
			var prompt: HandDiscardPrompt = null
			for child in game.get_node("UI").get_children():
				if child is HandDiscardPrompt and not child.is_queued_for_deletion():
					prompt = child
			check(prompt != null, "实际选牌弹窗存在：" + mode)
			if prompt == null:
				return
			check(prompt.confirm.disabled, "未选足不能确认")
			if mode == "timeout" or mode == "mandatory":
				game._countdown_on_timeout.call()
			elif mode == "cancel":
				prompt.timeout()
			elif mode == "ended":
				game._finish_game("平局", "选牌窗口测试")
			else:
				var buttons = prompt.find_children("*", "CheckButton", true, false)
				buttons[1].button_pressed = true
				check(not prompt.confirm.disabled, "选足后可确认")
				if mode == "moved":
					p.determined_cards.clear()
				prompt.confirm.pressed.emit()
				prompt.confirm.pressed.emit() # 第二次信号不能再次结算。
		action.call_deferred()
		var ok = await game._select_hand_discard(p, 1, mode == "mandatory")
		if mode == "confirm":
			check(ok and p.hand == [first] and p.determined_cards.is_empty() and game.deck._discard == [second], "按钮选择指定原牌且重复点击只支付一次")
		elif mode == "mandatory":
			check(ok and p.hand.is_empty() and p.determined_cards == [second], "强制弃牌超时沿既有自动策略执行，不跳过")
		else:
			check(not ok and p.hand == [first] and game.deck._discard.is_empty(), "取消/超时/失效/终局不支付：" + mode)
		check(not game._countdown_active and not game._countdown_on_timeout.is_valid(), "弃牌阶段结束响应计时无残留")
		await game.get_tree().process_frame
		check(game.get_node("UI").get_children().filter(func(c): return c is HandDiscardPrompt).is_empty(), "弹窗已释放")
	suite.reset_players()
	game = null
	suite = null
