extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "雌雄选牌：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._chixiong_target_override = func(): return true
	game._liehuo_override = func(): return false

func run(host):
	suite = host
	game = host.game
	var target = game.players[0]
	var source = game.players[1]
	var first = CardBase.create(CardData.CardSubType.STRIKE)
	var second = CardBase.create(CardData.CardSubType.PEACH)
	reset_case()
	target.hand.append(first)
	target.determined_cards.append(second)
	game._hand_discard_override = func(snapshot, count, mandatory):
		check(snapshot.owner == target and count == 1 and mandatory, "应由目标选择一张且不能取消弃牌")
		return [1]
	await game._resolve_chixiong(source, target)
	check(target.hand == [first] and target.determined_cards.is_empty() and game.deck._discard == [second], "弃所选原牌，保留未选牌")
	check(source.hand_size() == 0, "弃牌分支不同时让发动者摸牌")

	reset_case()
	target.hand.append(first)
	game._chixiong_target_override = func(): return false
	await game._resolve_chixiong(source, target)
	check(target.hand == [first] and source.hand == [null] and game.deck._discard.is_empty(), "选择摸牌分支不弃目标的牌")
	reset_case()
	await game._resolve_chixiong(source, target)
	check(source.hand == [null], "无手牌时仍直接令发动者摸牌")

	reset_case()
	target.determined_cards.append(second)
	target.equipment["armor"] = CardData.CardSubType.LIEHUO_SHIELD
	game._liehuo_override = func(): return true
	game._hand_discard_override = func(_snapshot, _count, _mandatory):
		check(false, "烈火盾替代成功不应再询问弃牌")
		return []
	await game._resolve_chixiong(source, target)
	check(target.hp == 9 and target.determined_cards == [second] and game.deck._discard.is_empty(), "保留原有烈火盾替代顺序")

	reset_case()
	target.hand.append(first)
	target.determined_cards.append(second)
	var attempts: Array = []
	game._hand_discard_override = func(_snapshot, _count, _mandatory):
		attempts.append(true)
		if attempts.size() == 1:
			target.hand.clear() # 选牌期间第一张离手，不能按旧索引误扣。
			return [1]
		return [0]
	await game._resolve_chixiong(source, target)
	check(attempts.size() == 2 and game.deck._discard == [second] and target.hand_size() == 0, "过期选择重新询问并只支付当前原牌一次")

	reset_case()
	target.hand.append(first)
	game._hand_discard_override = func(_snapshot, _count, _mandatory):
		game.turn_manager.current_phase = TurnManager.Phase.END
		return [0]
	await game._resolve_chixiong(source, target)
	check(target.hand == [first] and game.deck._discard.is_empty(), "过期阶段不付款、不无限重问")

	for mode in ["choose", "timeout"]:
		reset_case()
		target.hand.append(first)
		target.determined_cards.append(second)
		game._hand_discard_override = Callable()
		var action = func():
			var prompt: HandDiscardPrompt = null
			for child in game.get_node("UI").get_children():
				if child is HandDiscardPrompt and not child.is_queued_for_deletion():
					prompt = child
			check(prompt != null, "实际目标选牌弹窗存在")
			if prompt == null: return
			if mode == "timeout":
				game._countdown_on_timeout.call()
			else:
				var buttons = prompt.find_children("*", "CheckButton", true, false)
				buttons[1].button_pressed = true
				prompt.confirm.pressed.emit()
		action.call_deferred()
		await game._resolve_chixiong(source, target)
		var expected = second if mode == "choose" else first
		check(game.deck._discard == [expected] and target.hand_size() == 1 and source.hand_size() == 0, "实际按钮或超时只完成弃牌分支：" + mode)
		await game.get_tree().process_frame
		check(game.get_node("UI").get_children().filter(func(c): return c is HandDiscardPrompt).is_empty(), "实际选牌弹窗释放")
	reset_case()
	game._chixiong_target_override = Callable()
	game._liehuo_override = Callable()
	game = null
	suite = null
