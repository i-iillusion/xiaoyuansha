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
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	for p in game.players:
		p.hp = 10
		p.max_hp = 10
		p.hand.clear()
	var owner = game.players[0]
	owner.general_name = "史蒂芬·彼特先斯"
	owner.awoken = true # 本测试不触发另一个技能的交互弹窗。
	for i in range(3):
		owner.hand.append(null)
	var opponents: Array[Player] = []
	for i in range(1, 5):
		var p = game.players[i]
		p.hand.append(null)
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
		p.hand.append(null)
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
	# GEN-01：抽将池只含可用武将；随机分配无放回，不拿稻草人补足。
	var pool = GeneralData.get_available_random_generals()
	check(pool.size() == 7 and not pool.has("稻草人"), "随机池仅含当前七名非占位武将")
	for count in [2, 3, 5, 7]:
		var draw = GeneralData.draw_unique_random_generals(count)
		var unique = {}
		for name in draw:
			unique[name] = true
		check(draw.size() == count and unique.size() == count, "%d人随机选将无重复" % count)
	check(GeneralData.METADATA_ONLY_GENERALS.size() == 24
		and GeneralData.get_implementation_status("安迪·沃费尔") == "deferred",
		"手册其余24将均有资料状态，安迪仍暂缓")
	for count in [8, 10]:
		var draw = GeneralData.draw_unique_random_generals(count)
		var unique = {}
		var metadata_count = 0
		for name in draw:
			unique[name] = true
			if GeneralData.get_implementation_status(name) == "metadata_only":
				metadata_count += 1
		check(draw.size() == count and unique.size() == count
			and metadata_count == count - pool.size() and not unique.has("安迪·沃费尔")
			and not unique.has("稻草人"),
			"%d人名单只以手册未实装将补足，仍无重复和暂缓将" % count)
	check(GeneralData.draw_unique_random_generals(31).is_empty(), "超过非暂缓武将总数不返回部分名单")
	check(GeneralData.get_max_hp("里奥·普利威尔", 5) == 5
		and GeneralData.get_max_hp("吉姆·芒顿", 10) == 6
		and GeneralData.get_max_hp("泰瑞·谢尔", 5) == 4
		and GeneralData.get_max_hp("泰瑞·谢尔", 10) == 9,
		"手册固定体力与泰瑞按开局其他玩家人数计算")
	check(GeneralData.get_gender("克莉丝汀·艾") == "female"
		and GeneralData.get_gender("萨利·赛克斯") == "female"
		and GeneralData.get_gender("里奥·普利威尔") == "male",
		"手册女性武将资料不再沿用全员男性默认")
	var metadata_player = Player.new()
	metadata_player.general_name = "里奥·普利威尔"
	metadata_player.max_hp = GeneralData.get_max_hp(metadata_player.general_name, 5)
	root.add_child(metadata_player)
	var metadata_popup = PlayerDetailPopup.create(root, metadata_player)
	await process_frame
	var skill_rows = metadata_popup.get_node("Panel/Content/SkillsSection/SkillsList").get_children()
	var warning_found = false
	for row in skill_rows:
		if row is Label and row.text.contains("技能尚未实装") and row.text.contains("6.7"):
			warning_found = true
	check(warning_found, "资料武将详情明确显示技能未实装及手册章节，而非没有技能")
	metadata_popup.queue_free()
	metadata_player.queue_free()
	var previous_count = GameManager.selected_players
	var previous_mode = GameManager.selected_mode
	GameManager.selected_players = 5
	GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY
	GameManager.random_general = true
	var random_game: GameManager = load("res://Scenes/Game.tscn").instantiate()
	random_game.auto_start = false
	root.add_child(random_game)
	await process_frame
	random_game._shensu_override = func(): return false
	random_game._meiyong_override = func(): return false
	random_game.start_game()
	random_game._stop_countdown()
	var actual_names = {}
	for player in random_game.players:
		actual_names[player.general_name] = true
	check(random_game.players.size() == 5 and actual_names.size() == 5
		and not actual_names.has("稻草人"), "真实五人开局每名玩家获得不同的非占位武将")
	random_game.queue_free()
	GameManager.selected_players = previous_count
	GameManager.selected_mode = previous_mode
	GameManager.random_general = false
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
