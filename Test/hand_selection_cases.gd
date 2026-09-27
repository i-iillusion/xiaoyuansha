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

	for mode in ["confirm", "cancel", "timeout", "mandatory", "moved", "ended", "phase_return", "actor_return"]:
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
				elif mode == "phase_return":
					game.turn_manager.current_phase = TurnManager.Phase.PLAY
					game.turn_manager.current_phase = TurnManager.Phase.DISCARD
				elif mode == "actor_return":
					game.turn_manager.current_player_idx = 1
					game.turn_manager.current_player_idx = 0
				prompt.confirm.pressed.emit()
				prompt.confirm.pressed.emit() # 第二次信号不能再次结算。
		action.call_deferred()
		var outcome = await game._select_hand_discard_result(p, 1, mode == "mandatory")
		var ok = outcome == GameManager.HandDiscardOutcome.PAID
		var expected = GameManager.HandDiscardOutcome.DECLINED
		if mode in ["confirm", "mandatory"]:
			expected = GameManager.HandDiscardOutcome.PAID
		elif mode == "moved":
			expected = GameManager.HandDiscardOutcome.STALE_SELECTION
		elif mode == "ended":
			expected = GameManager.HandDiscardOutcome.GAME_ENDED
		elif mode in ["phase_return", "actor_return"]:
			expected = GameManager.HandDiscardOutcome.ACTION_INVALIDATED
		check(outcome == expected, "实际UI结果类型明确：" + mode)
		if mode == "confirm":
			check(ok and p.hand == [first] and p.determined_cards.is_empty() and game.deck._discard == [second], "按钮选择指定原牌且重复点击只支付一次")
		elif mode == "mandatory":
			check(ok and p.hand.is_empty() and p.determined_cards == [second], "强制弃牌超时沿既有自动策略执行，不跳过")
		else:
			check(not ok and p.hand == [first] and game.deck._discard.is_empty(), "取消/超时/失效/终局不支付：" + mode)
		check(not game._countdown_active and not game._countdown_on_timeout.is_valid(), "弃牌阶段结束响应计时无残留")
		await game.get_tree().process_frame
		check(game.get_node("UI").get_children().filter(func(c): return c is HandDiscardPrompt).is_empty(), "弹窗已释放")
	await check_mandatory_prompt_rebuild(p, first, second)
	await check_result_statuses(p, first)
	check_context_revision()
	suite.reset_players()
	game = null
	suite = null

func check_result_statuses(p: Player, concrete: CardBase):
	for mode in ["paid_any", "paid_concrete", "declined", "invalid_index", "empty_before", "empty_after", "dead", "disallowed", "ended"]:
		suite.reset_players()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game.deck._discard.clear()
		if mode != "empty_before":
			p.hand.append(concrete if mode == "paid_concrete" else null)
		var queries: Array = []
		game._hand_discard_override = func(snapshot, count, _mandatory):
			queries.append(true)
			match mode:
				"declined": return []
				"invalid_index": return [99]
				"empty_after": p.hand.clear()
				"dead": p.hp = 0
				"ended": game._finish_game("平局", "选牌结果分类")
			return snapshot.defaults(count)
		var allowed = func(): return mode != "disallowed"
		var outcome = await game._select_hand_discard_result(p, 1, false, allowed)
		var expected = GameManager.HandDiscardOutcome.PAID
		match mode:
			"declined": expected = GameManager.HandDiscardOutcome.DECLINED
			"invalid_index": expected = GameManager.HandDiscardOutcome.STALE_SELECTION
			"empty_before", "empty_after": expected = GameManager.HandDiscardOutcome.INSUFFICIENT_CARDS
			"dead", "disallowed": expected = GameManager.HandDiscardOutcome.ACTION_INVALIDATED
			"ended": expected = GameManager.HandDiscardOutcome.GAME_ENDED
		check(outcome == expected, "结果不能将失效混为主动拒绝：" + mode)
		check(queries.size() == (0 if mode in ["empty_before", "disallowed"] else 1), "前置不满足不询问：" + mode)
		check(game.deck._discard == ([concrete] if mode == "paid_concrete" else []), "只成功支付具体原牌才入弃牌堆：" + mode)
		check(p.hand_size() == (0 if mode in ["paid_any", "paid_concrete", "empty_before", "empty_after"] else 1), "失败不扣牌或撤销外部变化：" + mode)
		# 旧答复不污染下一次合法操作；沿bool兼容入口验证真实任意牌支付。
		suite.reset_players()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		p.hand.append(null)
		var paid = await game._select_hand_discard(p, 1, true)
		check(paid and p.hand_size() == 0, "下一次合法选择可以继续：" + mode)

func check_context_revision():
	# 独立状态机避免 start_game 的游戏UI/摸牌副作用干扰支付夹具。
	var turns = TurnManager.new()
	turns.debug_log = false
	turns.player_count = 1
	var initial = turns.get_context_revision()
	var same_phase = turns.current_phase
	var same_actor = turns.current_player_idx
	turns.current_phase = same_phase
	turns.current_player_idx = same_actor
	check(turns.get_context_revision() == initial, "同值字段赋值不使当前选择失效")
	turns.start_game()
	check(turns.get_context_revision() > initial, "同座位同阶段重开也更新上下文")
	initial = turns.get_context_revision()
	turns.next_turn()
	check(turns.get_context_revision() > initial, "即使回合字段同值也不能复用旧回合答复")
	initial = turns.get_context_revision()
	turns._change_phase(turns.current_phase)
	check(turns.get_context_revision() > initial, "显式重入同名阶段是新上下文")
	turns.free()

func current_prompt() -> HandDiscardPrompt:
	for child in game.get_node("UI").get_children():
		if child is HandDiscardPrompt and not child.is_queued_for_deletion():
			return child
	return null

func answer_rebuilt_prompt(p: Player, first: CardBase, second: CardBase):
	var original = current_prompt()
	check(original != null, "强制重建前实际弹窗存在")
	if original == null:
		game._finish_game("平局", "缺失测试窗口")
		return
	p.hand.clear()
	var original_id = original.get_instance_id()
	original.submit([1]) # 原索引1指向具体牌，当前已变为索引0。
	original.submit([0]) # 已答复窗口的重复信号不能变为第二次支付。
	for _frame in range(10):
		await game.get_tree().process_frame
		var rebuilt = current_prompt()
		if rebuilt == null or rebuilt.get_instance_id() == original_id:
			continue
		check(game.deck._discard.is_empty() and p.determined_cards == [second], "重建前不误扣旧索引")
		var buttons = rebuilt.find_children("*", "CheckButton", true, false)
		check(buttons.size() == 1 and rebuilt.fallback == [0], "重建按钮和超时默认索引均来自当前牌区")
		game._countdown_on_timeout.call()
		check(not game.deck._discard.has(first), "过期窗口不能弃置已离手原牌")
		return
	check(false, "有效强制选择应重新打开窗口")
	game._finish_game("平局", "测试保护：未重建窗口")

func check_mandatory_prompt_rebuild(p: Player, first: CardBase, second: CardBase):
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.DISCARD
	game._hand_discard_override = Callable()
	p.hand.append(first)
	p.determined_cards.append(second)
	answer_rebuilt_prompt.call_deferred(p, first, second)
	var paid = await game._select_hand_discard(p, 1, true)
	check(paid and p.hand_size() == 0 and game.deck._discard == [second], "实际UI过期后重建，超时支付当前原牌一次")
	check(not game._countdown_active and not game._countdown_on_timeout.is_valid(), "重建窗口结束无残留响应计时")
	await game.get_tree().process_frame
	check(current_prompt() == null, "重建的强制窗口已清理")
