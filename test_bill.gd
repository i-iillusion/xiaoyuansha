# test_bill.gd — 比尔·盖伊冒烟测试（英姿 / 神速 / Gay）
extends SceneTree

var failures := 0
var asserts := 0
var game = null

func _init():
	_run()

func _check(cond: bool, msg: String):
	asserts += 1
	if not cond:
		failures += 1
		print("FAIL: ", msg)

# 重置回合环境：P0 当前、清跳过标志、阶段回 DRAW 前置
func _env():
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.DRAW
	game.turn_manager.skip_play_phase = false
	game.turn_manager.skip_judge_phase = false
	game.turn_manager.skip_play_discard_phase = false
	game.turn_manager.supply_shortage_active = false
	game.turn_manager.strike_count_this_turn = 0
	game.turn_manager.duel_count_this_turn = 0
	game.turn_manager.aoe_count_this_turn = 0
	game.turn_manager.steal_count_this_turn = 0
	game._gay_used = false

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 5
	GameManager.selected_general = "比尔·盖伊"
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	game.auto_start = false
	root.add_child(game)
	for i in range(6):
		await process_frame
	# 通用钩子：不弹窗
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._aoe_override = func(): return false
	game._shensu_override = Callable()
	game._shensu_option_override = Callable()
	game._shensu_target_override = Callable()
	game._gay_x_override = Callable()
	game.start_game()
	for i in range(6):
		await process_frame

	var p0 = game.players[0]
	var p1 = game.players[1]
	var p2 = game.players[2]

	# ---- 用例1：武将数据 ----
	_check(GeneralData.is_valid("比尔·盖伊"), "比尔·盖伊武将存在")
	_check(GeneralData.get_max_hp("比尔·盖伊") == 3, "比尔·盖伊 3 血")
	_check(GeneralData.get_skills("比尔·盖伊").size() == 3, "三个技能: %d" % GeneralData.get_skills("比尔·盖伊").size())
	_check(p0.general_name == "比尔·盖伊", "玩家0 = 比尔·盖伊")
	_check(p0.max_hp == 3, "玩家0 体力上限 3")

	# ---- 用例2：【英姿】摸牌阶段多摸一张（2+1=3）----
	_env()
	p0.hand.clear()
	game._do_draw(0)
	_check(p0.hand_size() == 3, "英姿摸 3 张（2+1）: %d" % p0.hand_size())
	# 兵粮寸断叠加：3-1=2
	_env()
	p0.hand.clear()
	game.turn_manager.supply_shortage_active = true
	game._do_draw(0)
	_check(p0.hand_size() == 2, "英姿+兵粮：摸 2 张: %d" % p0.hand_size())

	# ---- 用例3：【神速】选项2：跳过出牌弃牌 + 摸牌减益顺延叠加 ----
	_env()
	p0.shensu_penalty = 0
	p0.shensu_used_this_turn = false
	game._shensu_override = func(): return true
	game._shensu_option_override = func(): return 2
	await game._maybe_shensu(p0)
	_check(p0.shensu_penalty == 1, "选2 后欠账 1 层: %d" % p0.shensu_penalty)
	_check(p0.shensu_used_this_turn, "选2 当回合标记")
	_check(game.turn_manager.skip_play_discard_phase, "选2 后跳出牌弃牌阶段")
	# 下回合（未发动）：摸牌 -1 后清零
	p0.shensu_used_this_turn = false
	p0.hand.clear()
	game.turn_manager.skip_play_discard_phase = false
	game._do_draw(0)
	_check(p0.hand_size() == 2, "减益结算：摸 2 张（3-1）: %d" % p0.hand_size())
	_check(p0.shensu_penalty == 0, "减益结算后清零: %d" % p0.shensu_penalty)
	# 连续两回合选2 → 欠账 2 层 → 下回合一次扣 2
	game._shensu_option_override = func(): return 2
	p0.shensu_used_this_turn = false
	await game._maybe_shensu(p0)  # 第2次选2
	_check(p0.shensu_penalty == 1, "再次选2 欠账+1: %d" % p0.shensu_penalty)
	p0.shensu_used_this_turn = false
	await game._maybe_shensu(p0)  # 第3次选2
	_check(p0.shensu_penalty == 2, "连续选2 欠账累计 2 层: %d" % p0.shensu_penalty)
	p0.shensu_used_this_turn = false
	p0.hand.clear()
	game.turn_manager.skip_play_discard_phase = false
	game._do_draw(0)
	_check(p0.hand_size() == 1, "欠 2 层一次扣清：摸 1 张（3-2）: %d" % p0.hand_size())
	_check(p0.shensu_penalty == 0, "扣清后归零")
	# 最少摸 0：欠 5 层 → 摸 0
	p0.shensu_penalty = 5
	p0.hand.clear()
	game._do_draw(0)
	_check(p0.hand_size() == 0, "欠 5 层：摸 0 张（下限）: %d" % p0.hand_size())
	_check(p0.shensu_penalty == 0, "下限结算后清零")
	game._shensu_override = Callable()

	# ---- 用例4：【神速】选项1：跳过判定 + 视为无距离杀 ----
	_env()
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.judgment_cards.clear()
	p0.judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
	p1.hp = p1.max_hp
	p1.hand.clear()
	game._shensu_override = func(): return true
	game._shensu_option_override = func(): return 1
	game._shensu_target_override = func(): return p1
	await game._maybe_shensu(p0)
	_check(game.turn_manager.skip_judge_phase, "选项1：跳过判定阶段")
	_check(p1.hp == p1.max_hp - 1, "神速杀命中：p1 受 1 点伤害: %d" % p1.hp)
	_check(p0.hand_size() == 2, "神速杀不耗手牌: %d" % p0.hand_size())
	_check(game.turn_manager.strike_count_this_turn == 0, "神速杀不占杀次数")
	_check(p0.judgment_cards.size() == 1, "判定牌保留（未被结算）")
	# 判定阶段被跳过：判定牌不结算
	var judge_before = p0.judgment_cards.size()
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	game._do_judge(0)
	_check(p0.judgment_cards.size() == judge_before, "跳过判定：乐不思蜀保留，未生效")
	_check(p0.judgment_cards.is_empty() == false, "判定牌仍存在")
	p0.judgment_cards.clear()

	# ---- 用例5：【神速】选项1 判定区无牌不可发动 ----
	_env()
	p1.hp = p1.max_hp
	game._shensu_override = func(): return true
	game._shensu_option_override = func(): return 1
	game._shensu_target_override = func(): return p1
	await game._maybe_shensu(p0)
	_check(p1.hp == p1.max_hp, "判定区无牌：选项1 不发动（无伤害）: %d" % p1.hp)
	_check(not game.turn_manager.skip_judge_phase, "判定区无牌：不跳判定")
	game._shensu_override = Callable()

	# ---- 用例6：【神速】杀吃酒加成；目标藤甲不可选 ----
	_env()
	p0.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
	p1.hp = p1.max_hp
	p1.hand.clear()
	p0.wine_stacks = 1
	game._shensu_override = func(): return true
	game._shensu_option_override = func(): return 1
	game._shensu_target_override = func(): return p1
	await game._maybe_shensu(p0)
	_check(p1.hp == p1.max_hp - 2, "神速杀吃酒：伤害 2 点: %d" % p1.hp)
	_check(p0.wine_stacks == 0, "酒层数被消耗")
	p0.judgment_cards.clear()
	# 藤甲目标不能选（校验拒绝，无伤害）
	game._shensu_target_override = Callable()
	game._is_shensu_targeting = true
	p1.hp = p1.max_hp
	p1.equipment["armor"] = CardData.CardSubType.TENGJIA
	game._on_shensu_target_click(p1)
	_check(p1.hp == p1.max_hp, "藤甲目标被拒：无伤害")
	_check(game._is_shensu_targeting, "拒绝后仍在目标选择")
	p1.remove_equipment("armor")
	game._is_shensu_targeting = false
	# 取消：退出目标选择（emit null 无监听者，无碍）
	game._is_shensu_targeting = true
	game._cancel_target_btn.visible = true
	game._on_cancel_target_pressed()
	_check(not game._is_shensu_targeting, "取消神速杀目标选择")
	game._shensu_override = Callable()
	game._shensu_option_override = Callable()

	# ---- 用例7：【Gay】数据校验 + 详情按钮 ----
	game._open_player_detail(p0)
	await process_frame
	_check(_find_btn_rec(game._detail_popup_root, "Gay") != null, "详情弹窗有【Gay】按钮")
	for child in game._detail_popup_root.get_children():
		child.queue_free()
	game._detail_popup_root.visible = false

	# ---- 用例8：【Gay】执行：弃 X 张，双方各回复 X ----
	_env()
	p0.hp = 1
	p1.hp = 1
	p1.hand.clear()
	p0.hand.clear()
	for i in range(3):
		p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game._gay_x_override = func(): return 2
	await game._execute_gay(p0, p1)
	_check(p0.hand_size() == 1, "Gay 弃 2 张（3->1）: %d" % p0.hand_size())
	_check(p0.hp == 3, "自己回复 2 点（1->3 封顶）: %d" % p0.hp)
	_check(p1.hp == 3, "目标回复 2 点（1->3）: %d" % p1.hp)
	_check(game._gay_used, "Gay 已标记使用")
	# 已使用后不能再发动（执行入口拒绝）
	var hp_before = p1.hp
	await game._execute_gay(p0, p1)
	_check(p1.hp == hp_before, "限一次：二次发动被拒")
	# 取消（X=0）
	_env()
	p0.hp = 1
	p1.hp = 1
	p0.hand.clear()
	for i in range(3):
		p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game._gay_x_override = func(): return 0
	await game._execute_gay(p0, p1)
	_check(p0.hp == 1 and p1.hp == 1, "取消 Gay：双方不回复")
	_check(p0.hand_size() == 3, "取消 Gay：不弃牌: %d" % p0.hand_size())
	_check(not game._gay_used, "取消不标记使用")

	# ---- 用例9：【Gay】目标校验 ----
	_env()
	p0.hp = 1
	p2.hp = p2.max_hp  # 满血目标
	game._is_gay_targeting = true
	game._on_gay_target_click(p2)
	_check(game._is_gay_targeting, "满血目标被拒，仍在选择")
	_check(p2.hp == p2.max_hp, "满血目标未回复")
	# 异性目标被拒
	p2.hp = 1
	p2.gender = "female"
	game._on_gay_target_click(p2)
	_check(game._is_gay_targeting, "异性目标被拒（拒绝后仍在选择）")
	_check(p2.hp == 1, "异性目标未回复")
	p2.gender = "male"
	# 自己不能选
	p0.hand.clear()
	for i in range(3):
		p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game._gay_x_override = func(): return 1
	var p0_hp_before = p0.hp
	game._on_gay_target_click(p0)
	_check(p0.hp == p0_hp_before, "不能选自己（无效果）")
	_check(game._is_gay_targeting, "选自己被拒后仍在选择")
	# 取消
	game._on_cancel_target_pressed()
	_check(not game._is_gay_targeting, "取消 Gay 目标选择")

	# ---- 用例10：【Gay】正常目标全流程（点击 → X → 回复）----
	_env()
	p0.hp = 1
	p1.hp = 1
	p0.hand.clear()
	for i in range(3):
		p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	game._gay_x_override = func(): return 1
	game._is_gay_targeting = true
	await game._on_gay_target_click(p1)
	_check(not game._is_gay_targeting, "执行后退出目标选择")
	_check(p0.hp == 2, "全流程：自己回 1: %d" % p0.hp)
	_check(p1.hp == 2, "全流程：目标回 1: %d" % p1.hp)
	_check(game._gay_used, "全流程：标记使用")
	# 回合外不能发动
	game.turn_manager.current_phase = TurnManager.Phase.DRAW
	game._on_gay_skill_clicked(p0)
	_check(not game._is_gay_targeting, "非出牌阶段不进入目标选择")
	game._gay_x_override = Callable()

	# ---- 用例11：全套件回归环境（其他武将测试用 false）已设——收尾 ----
	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _find_btn_rec(node: Node, text: String) -> Button:
	if node is Button and not node.is_queued_for_deletion() and node.text.contains(text):
		return node
	for c in node.get_children():
		var r = _find_btn_rec(c, text)
		if r:
			return r
	return null

func _check2(cond: bool, msg: String):
	_check(cond, msg)
