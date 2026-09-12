# ST-04/05：五人标准身份局判胜与普通濒死窗口回归。未覆盖 QA-007 特殊时序。
extends SceneTree

const IDENTITIES = ["主公", "忠臣", "反贼", "反贼", "内奸"]
var checks := 0
var failures := 0
var game: GameManager
var winners: Array[String] = []

func _init():
	_run()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)

func make_roster() -> Array[Player]:
	var roster: Array[Player] = []
	for i in range(5):
		var p := Player.new()
		p.identity = IDENTITIES[i]
		p.player_name = "P%d" % i
		p.seat_index = i
		p.hp = 4
		roster.append(p)
	return roster

func mark_dead(roster: Array[Player], indices: Array):
	for i in indices:
		roster[i].hp = 0
		roster[i].mark_dead()

func free_roster(roster: Array[Player]):
	for p in roster:
		p.free()

func expect_winner(roster: Array[Player], expected: String, message: String):
	var outcome := IdentityVictory.evaluate(roster)
	check(outcome.get("winner", "") == expected, message)

func check_pure_matrix():
	var cases = [
		{"dead": [], "winner": "", "name": "V01 开局继续"},
		{"dead": [2], "winner": "", "name": "一名反贼死亡继续"},
		{"dead": [2, 3], "winner": "", "name": "V02 内奸仍存活不能判主公胜"},
		{"dead": [2, 3, 4], "winner": "主公", "name": "V04 主忠均存活获胜"},
		{"dead": [1, 2, 3, 4], "winner": "主公", "name": "V04 忠臣死亡也属获胜阵营"},
		{"dead": [0], "winner": "反贼", "name": "V05 主公阵亡，其他人均存活"},
		{"dead": [0, 2, 3], "winner": "反贼", "name": "V07 反贼全死也可获胜"},
		{"dead": [0, 1, 2, 3], "winner": "内奸", "name": "V06 唯一存活内奸胜"},
		{"dead": [0, 1, 4], "winner": "反贼", "name": "主公与内奸死亡，反贼胜"},
		{"dead": [0, 1, 2, 3, 4], "winner": "", "name": "V14 不裁定全员同时死亡"},
	]
	for entry in cases:
		var roster := make_roster()
		mark_dead(roster, entry["dead"])
		expect_winner(roster, entry["winner"], entry["name"])
		roster.reverse()
		expect_winner(roster, entry["winner"], "V10 交换名单顺序：" + entry["name"])
		free_roster(roster)

	var roster := make_roster()
	mark_dead(roster, [2, 3])
	roster[4].hp = -2
	expect_winner(roster, "", "V03 负体力内奸仍在救援，不判主公胜")
	check(roster[4].is_dying() and roster[4].hp == -2, "判胜器不修改生命状态或体力")
	roster[4].mark_dead()
	roster[2].hp = 5
	expect_winner(roster, "主公", "V12 已标死者直接赋正体力不视作复活")
	free_roster(roster)

	roster = make_roster()
	mark_dead(roster, [1, 2, 3, 4])
	roster[0].hp = 0
	expect_winner(roster, "", "V08 主公尚在救援，不能宣告任何胜方")
	free_roster(roster)

	roster = make_roster()
	mark_dead(roster, [0])
	roster[1].hp = -1
	expect_winner(roster, "", "V09 其他角色仍在濒死救援时暂缓终局")
	free_roster(roster)

	roster = make_roster()
	mark_dead(roster, [2, 3, 4])
	var invalid: Array[Player] = [roster[0], roster[1]]
	expect_winner(invalid, "", "V13 两人局不套用五人胜负条件")
	invalid = roster.duplicate()
	invalid[1] = roster[0]
	expect_winner(invalid, "", "V13 重复角色引用不视作五人局")
	invalid[1] = null
	expect_winner(invalid, "", "V13 缺失角色拒绝判胜")
	roster[1].identity = "奸雄"
	expect_winner(roster, "", "V13 奸雄模式不能跳过声明窗口套用基线")
	roster[1].identity = "主公"
	expect_winner(roster, "", "V13 重复主公拒绝判胜")
	roster[1].identity = "反贼"
	expect_winner(roster, "", "V13 非标准身份配比拒绝判胜")
	roster[0].identity = "忠臣"
	expect_winner(roster, "", "V13 无主公拒绝判胜")
	free_roster(roster)

func reset_case():
	for i in range(game.players.size()):
		var p := game.players[i]
		p.identity = IDENTITIES[i]
		p.identity_revealed = i == 0
		p.general_name = "稻草人"
		p.hp = p.max_hp
		p.hand.clear()
		p.equipment.clear()
		p.judgment_cards.clear()
		p.determined_cards.clear()
		p.chained = false
		p.kneeling = false
		p.sage_activated = false
	game.reset_game_over_state()
	game._stop_countdown()
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._dying_peach_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	winners.clear()

func check_integration():
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 5
	GameManager.selected_general = "稻草人"
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	game.start_game()
	game.game_over.connect(func(winner: String): winners.append(winner))
	var lord := game.players[0]
	var traitor := game.players[4]

	for source in [null, game.players[1], game.players[2], traitor]:
		reset_case()
		lord.hp = 1
		await game._deal_damage(source, lord, 1, EffectChain.DamageType.PHYSICAL)
		check(lord.is_dead(), "V05 主公完成死亡处理")
		check(winners == ["反贼"], "V05 忠臣/反贼/内奸/无来源不改变胜方")

	reset_case()
	mark_dead(game.players, [1, 2, 3])
	lord.hp = 1
	await game._deal_damage(null, lord, 1, EffectChain.DamageType.THUNDER)
	check(winners == ["内奸"], "V06 单挑时主公死于无来源伤害，内奸胜")

	reset_case()
	mark_dead(game.players, [2, 3])
	lord.hp = -1
	lord.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	lord.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	traitor.hp = 0
	game._handle_death(traitor, null)
	check(not game._game_over and winners.is_empty(), "V03/V08 内奸已死但主公仍在救援，不提前结束")
	game._dying_peach_override = func(): return true
	await game._check_dying(lord)
	check(lord.hp == 1 and lord.is_alive() and lord.hand.is_empty(), "V08 负体力需连续两桃才能救回")
	check(winners == ["主公"], "V09 最后救援成功后自动重查，主公阵营胜")

	reset_case()
	# 主公在座位4，唯一内奸（人类玩家0）正在濒死；主公先完成死亡。
	lord.identity = "内奸"
	traitor.identity = "主公"
	mark_dead(game.players, [1, 2, 3])
	lord.hp = 0
	lord.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	traitor.hp = 0
	game._handle_death(traitor, null)
	check(winners.is_empty(), "V09/V10 内奸救援尚未结束时不提前判胜")
	game._dying_peach_override = func(): return true
	await game._check_dying(lord)
	check(winners == ["内奸"], "V09/V10 异位主公已死，内奸救回后仅宣告一次胜利")

	reset_case()
	mark_dead(game.players, [3, 4])
	var rebel := game.players[2]
	rebel.hp = 1
	await game._deal_damage(lord, rebel, 1, EffectChain.DamageType.PHYSICAL)
	check(winners == ["主公"] and lord.hand_size() == 3, "V04 末个敌对角色死亡，执行一次奖惩与终局")
	var overlay = game._game_over_overlay
	game._handle_death(rebel, lord)
	game._check_win_condition(rebel, null)
	game._check_win_condition(null, null)
	check(winners.size() == 1 and lord.hand_size() == 3, "V11 重复通知不重复发奖或 game_over")
	check(game._game_over_overlay == overlay, "V11 终局弹窗不重复创建")
	var previous_hp := rebel.hp
	check(not await game._pay_yes_ah_cost(rebel), "已死亡角色不能支付是啊费用")
	check(rebel.hp == previous_hp, "拒绝无效支付不改变体力")
	game.queue_free()
	await process_frame

func _run():
	check_pure_matrix()
	await check_integration()
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
