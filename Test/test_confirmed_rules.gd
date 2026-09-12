# QA-103 / QA-110 / QA-111：已确认但先前未落地的规则。
extends SceneTree

var game: GameManager
var failures := 0
var checks := 0

func _init():
	_run()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)

func _run():
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "稻草人"
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	game.start_game()
	game._stop_countdown()
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	game._zhuangbi_again_override = func(): return false
	for p in game.players:
		p.hp = 10
		p.max_hp = 10
		p.hand.clear()
	var owner = game.players[0]
	owner.general_name = "史蒂芬·彼特先斯"
	owner.awoken = true # 本测试不触发另一个技能的交互弹窗。
	for i in range(3):
		owner.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	var opponents: Array[Player] = []
	for i in range(1, 5):
		var p = game.players[i]
		p.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
		opponents.append(p)
	game._rps_override = func(p):
		if p == owner: return game.RPS_ROCK
		return game.RPS_SCISSORS if p.seat_index <= 2 else game.RPS_PAPER
	await game._execute_zhuangbi(opponents)
	check(game._zhuangbi_blocked_this_phase, "2胜2负后本阶段禁用装逼")
	check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "胜负各半不强制进入弃牌阶段")
	check(owner.hand_size() == 2, "本次已支付的费用不退回")
	for p in opponents:
		check(p.hp == 10 and p.hand_size() == 0, "目标已付费用但不受到装逼伤害")
		p.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	await game._execute_zhuangbi(opponents)
	check(owner.hand_size() == 2 and opponents[0].hand_size() == 1, "再次调用不执行、不收取费用")
	await game._on_zhuangbi_skill_clicked(owner)
	check(not game._is_zhuangbi_targeting, "界面入口也阻止再次选择装逼目标")
	game.turn_manager.start_waiting("test", 1)
	game.turn_manager.end_waiting()
	check(game._zhuangbi_blocked_this_phase, "普通响应返回出牌阶段不清除禁用")
	game.turn_manager.current_phase = TurnManager.Phase.DRAW
	game.turn_manager.advance_phase()
	check(not game._zhuangbi_blocked_this_phase, "新的出牌阶段恢复可用")

	owner.general_name = "稻草人"
	owner.hand.clear()
	for i in range(2):
		owner.hand.append(CardBase.create(CardData.CardSubType.DISARM))
	await game._play_disarm()
	check(game.turn_manager.disarm_count_this_turn == 1, "首次卸甲归田记录使用次数")
	check(owner.hand_size() == 1, "首次卸甲归田支付一张牌")
	await game._play_disarm()
	check(owner.hand_size() == 1 and game.turn_manager.disarm_count_this_turn == 1, "重复使用被阻止且不消耗手牌")
	game.turn_manager.start_waiting("test", 1)
	game.turn_manager.end_waiting()
	check(not game.turn_manager.can_use("disarm"), "响应返回不会重置卸甲归田次数")
	game.turn_manager.current_phase = TurnManager.Phase.DRAW
	game.turn_manager.advance_phase()
	check(not game.turn_manager.can_use("disarm"), "同一回合新增出牌阶段仍不能再用卸甲归田")
	# 独立状态机验证回合边界，避免开启另一角色的异步 UI 流程。
	var turns = TurnManager.new()
	turns.use_card("disarm")
	turns.next_turn()
	check(turns.can_use("disarm"), "下一回合重置卸甲归田次数")
	turns.free()

	owner.hand.clear()
	var burning_card = CardBase.create(CardData.CardSubType.BURNING_CAMP)
	owner.hand.append(burning_card)
	var center = game.players[1]
	var discard_before_burning = game.deck.discard_count()
	await game.execute_card_on_target(center, CardData.CardSubType.BURNING_CAMP)
	check(center.judgment_cards.size() == 1, "火烧连营先进入目标判定区")
	check(center.judgment_cards[0] == burning_card, "火烧连营进入判定区时保留原实例")
	check(game.deck.discard_count() == discard_before_burning, "放置延时锦囊时不同时加入弃牌堆")
	check(owner.hand_size() == 0, "放置延时锦囊时支付费用")
	check(center.hp == 10 and owner.hp == 10 and game.players[2].hp == 10, "使用时目标与相邻角色不受伤")
	check(owner.judgment_cards.is_empty() and game.players[2].judgment_cards.is_empty(), "使用时不提前蔓延")
	await game._run_judgment(center, false)
	check(center.hp == 9 and owner.hp == 9 and game.players[2].hp == 9, "等到判定才造成三处火焰伤害")
	check(center.judgment_cards.is_empty(), "判定完成移除当前火烧连营")
	check(game.deck._discard.count(burning_card) == 1, "原火烧连营结算后只入弃牌堆一次")
	check(owner.judgment_cards.size() == 1 and game.players[2].judgment_cards.size() == 1, "判定生效后才向相邻判定区蔓延")
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
