extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "D01：" + label)

func run(host):
	suite = host
	game = host.game
	suite.reset_players()
	var a: Player = game.players[0]
	var b: Player = game.players[1]
	var old_identity = b.identity
	var revealed = b.identity_revealed
	b.identity = "内奸"
	b.identity_revealed = false
	b.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden.hidden_category = "weapon"
	check(b.equip_hidden_card_to_slot("weapon", hidden), "暗置测试原牌合法落位")
	a.hand.append(null)
	a.determined_cards.append(CardBase.create(CardData.CardSubType.DODGE))
	var snapshot = game._ai_observation(a)
	check(snapshot.players[1].identity == "" and snapshot.players[1].hand_count == 1,
		"隐藏身份不可见，他人仅暴露手牌数")
	check(not snapshot.players[1].has("hand") and not snapshot.players[1].has("determined_cards"),
		"白名单不包含他人手牌内容")
	check(snapshot.players[1].equipment.weapon == CardData.CardSubType.HIDDEN_EQUIPMENT,
		"他人暗置仅暴露占位类别，不暴露原牌名")
	check(snapshot.own_cards.size() == 2 and snapshot.own_cards[0].sub == -1
		and snapshot.own_cards[1].sub == CardData.CardSubType.DODGE, "自己任意牌与具体牌可见")
	snapshot.players[1].hp = -100
	snapshot.own_cards.clear()
	check(b.hp == 10 and a.hand_size() == 2, "策略修改快照不改变实际对局")
	b.identity_revealed = true
	check(game._ai_observation(a).players[1].identity == "内奸", "公开后身份可见")
	b.identity = old_identity
	b.identity_revealed = revealed
	var driver = DecisionDriver.new(42)
	driver.action_budget = 3
	var count: Array = [0]
	var valid: Array = [true]
	var observe = func(): return {"actor": 1, "revision": 1}
	var options = func(_view): return [{"actor": 1, "kind": "test"}]
	var execute = func(_action): count[0] += 1
	var current = func(): return valid[0]
	var result = await driver.run(observe, func(_view): return [], execute, current)
	check(result.reason == "end" and count[0] == 0, "无候选明确结束")
	result = await driver.run(observe, options, execute, current)
	check(result.reason == "budget" and count[0] == 3, "候选不减少也只执行有限预算")
	driver.chooser = func(_view, _options):
		await game.get_tree().process_frame
		valid[0] = false
		return 0
	result = await driver.run(observe, options, execute, current)
	check(result.reason == "stale" and count[0] == 3, "等待后上下文过期不执行旧计划")
	valid[0] = true
	driver.chooser = func(_view, _options): return -1
	result = await driver.run(observe, options, execute, current)
	check(result.reason == "end" and count[0] == 3, "决策器可主动结束")
	var traces: Array = []
	for repeat in 2:
		var seeded = DecisionDriver.new(91)
		seeded.action_budget = 8
		var trace: Array = []
		await seeded.run(observe, func(_view): return [{"n": 1}, {"n": 2}, {"n": 3}],
			func(action): trace.append(action.n), current)
		traces.append(trace)
	check(traces[0] == traces[1], "相同种子动作序列可重放")
	var phase = game.turn_manager.current_phase
	var actor_idx = game.turn_manager.current_player_idx
	b.hand.clear()
	b.determined_cards.clear()
	# 隔离本测试的阶段推进观察，避免继续启动下一名角色的真实回合。
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	await game._run_ai_play(b)
	check(game.turn_manager.current_phase == TurnManager.Phase.DISCARD, "真实AI空候选阶段自行结束")
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._game_over = true
	await game._run_ai_play(b)
	check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "终局停止且不推进阶段")
	suite.reset_players()
	game.turn_manager.current_player_idx = actor_idx
	game.turn_manager.current_phase = phase
	game.turn_manager.phase_changed.connect(game._on_phase_changed)
