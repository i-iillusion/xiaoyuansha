# test_bruce.gd：布鲁斯·萨维奇冒烟测试（无谋/ 暴怒/ 下跪）
extends SceneTree

var failures := 0
var asserts := 0
var game = null

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "布鲁斯·萨维奇"
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	var bruce = game.players[0]
	var p1 = game.players[1]
	var p2 = game.players[2]

	# 通用钩子：不弹窗
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false

	# ---- 用例 1：武将数量 ----
	_check(GeneralData.is_valid("布鲁斯·萨维奇"), "布鲁斯·萨维奇武将存在")
	_check(GeneralData.get_max_hp("布鲁斯·萨维奇") == 5, "布鲁斯·萨维奇 5 血")
	_check(GeneralData.get_skills("布鲁斯·萨维奇").size() == 3, "三个技能: %d" % GeneralData.get_skills("布鲁斯·萨维奇").size())
	_check(bruce.general_name == "布鲁斯·萨维奇", "玩家0 = 布鲁斯·萨维奇")
	_check(bruce.max_hp == 5, "玩家0 体力上限 5: %d" % bruce.max_hp)

	# ---- 用例 2：【无谋】手牌上限 ----
	bruce.hp = bruce.max_hp
	_check(bruce.hand_limit() == 5, "满血手牌上限正常: %d" % bruce.hand_limit())
	bruce.hp = 3
	_check(bruce.hand_limit() == 0, "受伤后无谋手牌上限 0: %d" % bruce.hand_limit())
	bruce.kneeling = true
	_check(bruce.hand_limit() == 5, "下跪状态固定手牌上限 5: %d" % bruce.hand_limit())
	bruce.kneeling = false
	_check(bruce.hand_limit() == 0, "解除下跪后无谋恢复: %d" % bruce.hand_limit())

	# ---- 用例 3：【暴怒】额外伤害 = 已损失体力值 ----
	_check(game._rage_bonus(bruce) == 2, "暴怒加成 = 已损失 2 点体力: %d" % game._rage_bonus(bruce))
	bruce.hp = bruce.max_hp
	_check(game._rage_bonus(bruce) == 0, "满血暴怒加成 0: %d" % game._rage_bonus(bruce))
	_check(game._rage_bonus(p1) == 0, "非布鲁斯无暴怒加成")

	# 决斗：布鲁斯 3 血发起决斗 ，目标掉 1+2=3 点伤害
	bruce.hp = 3
	p1.hp = p1.max_hp
	p1.hand.clear()
	bruce.hand.clear()
	await game._play_duel(bruce, p1)
	_check(p1.hp == p1.max_hp - 3, "决斗暴怒伤害 3 点: %d -> %d" % [p1.max_hp, p1.hp])

	# 杀：布鲁斯 3 血出杀 ，目标掉 1+2=3 点伤害
	p1.hp = p1.max_hp
	p1.hand.clear()
	bruce.hand.clear()
	bruce.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game.turn_manager.strike_count_this_turn = 0
	await game.execute_card_on_target(p1, CardData.CardSubType.STRIKE)
	_check(p1.hp == p1.max_hp - 3, "杀暴怒伤害 3 点: %d -> %d" % [p1.max_hp, p1.hp])
	_check(bruce.hand_size() == 0, "杀消耗手牌")

	# ---- 用例 3.5：【暴怒】+【丈八蛇矛】：流失体力后，额外伤害附加当时的暴怒加成 ----
	# 满血 + 丈八：杀 1 + 丈八流失 1 + 流失后暴怒 1 = 总伤害 3
	bruce.hp = bruce.max_hp
	p1.hp = p1.max_hp
	p1.hand.clear()
	bruce.hand.clear()
	bruce.equipment["weapon"] = CardData.CardSubType.ZHANGBA_SPEAR
	game._zhangba_override = func(): return 1
	bruce.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game.turn_manager.strike_count_this_turn = 0
	await game.execute_card_on_target(p1, CardData.CardSubType.STRIKE)
	_check(p1.hp == p1.max_hp - 3, "满血丈八流失 1 点：总伤害 3 点（杀1+丈八1+暴怒1）: %d -> %d" % [p1.max_hp, p1.hp])
	_check(bruce.hp == bruce.max_hp - 1, "布鲁斯流失 1 点: %d" % bruce.hp)
	# 目标带【白银狮子】：效果最后统一计算——基础+丈八额外（含暴怒）算同一次伤害，总伤害封顶 1 点
	p1.hp = p1.max_hp
	p1.equipment["armor"] = CardData.CardSubType.SILVER_LION
	bruce.hp = bruce.max_hp
	bruce.hand.clear()
	bruce.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game.turn_manager.strike_count_this_turn = 0
	await game.execute_card_on_target(p1, CardData.CardSubType.STRIKE)
	_check(p1.hp == p1.max_hp - 1, "白银狮子：总伤害封顶 1 点（额外被吸收）: %d -> %d" % [p1.max_hp, p1.hp])
	p1.remove_equipment("armor")
	# 目标带【战旗】：同样封顶 1 点
	p1.hp = p1.max_hp
	p1.equipment["armor"] = CardData.CardSubType.ZHANQI
	bruce.hp = bruce.max_hp
	bruce.hand.clear()
	bruce.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game.turn_manager.strike_count_this_turn = 0
	await game.execute_card_on_target(p1, CardData.CardSubType.STRIKE)
	_check(p1.hp == p1.max_hp - 1, "战旗：总伤害封顶 1 点（额外被吸收）: %d -> %d" % [p1.max_hp, p1.hp])
	p1.remove_equipment("armor")
	bruce.remove_equipment("weapon")
	game._zhangba_override = Callable()
	bruce.hp = bruce.max_hp
	p1.hp = p1.max_hp

	# ---- 用例 4：【下跪】发动条件 ----
	bruce.hp = 3
	bruce.hand.clear()
	bruce.kneeling = false
	bruce.kneel_used = false
	game.turn_manager.current_player_idx = 1  # 回合外
	_check(game._kneel_conditions_met(bruce), "回合外，无手牌，受伤 时可发动")
	game.turn_manager.current_player_idx = 0  # 自己的回合
	_check(not game._kneel_conditions_met(bruce), "自己的回合不能发动")
	game.turn_manager.current_player_idx = 1
	bruce.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	_check(not game._kneel_conditions_met(bruce), "有手牌不能发动")
	bruce.hand.clear()
	bruce.hp = bruce.max_hp
	_check(not game._kneel_conditions_met(bruce), "未受伤不能发动")
	bruce.hp = 3
	bruce.kneel_used = true
	_check(not game._kneel_conditions_met(bruce), "限定技已使用不能发动")
	bruce.kneel_used = false

	# ---- 用例 5：【下跪】技能点击流程（发动 / 解除 / 已使用提示） ----
	# 5.1 条件不满足（有手牌）时 toast 提示，不发动
	bruce.hp = 3
	bruce.hand.clear()
	bruce.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	bruce.kneeling = false
	bruce.kneel_used = false
	game._kneel_override = Callable()
	await game._on_detail_skill_clicked("下跪", bruce)
	_check(not bruce.kneeling and not bruce.kneel_used, "条件不满足不发动")
	_check(game._toast_label != null and game._toast_label.text.contains("手牌"), "toast 提示缺手牌: " + (game._toast_label.text if game._toast_label else "null"))

	# 5.2 条件满足 + 确认 后发动（进入下跪状态）
	bruce.hand.clear()
	game._kneel_override = func(): return true
	await game._on_detail_skill_clicked("下跪", bruce)
	_check(bruce.kneeling and bruce.kneel_used, "发动下跪成功")
	_check(game._is_kneeling(bruce), "is_kneeling 判定")

	# 5.3 下跪中点击，询问解除
	game._kneel_override = func(): return true
	await game._on_detail_skill_clicked("下跪", bruce)
	_check(not bruce.kneeling, "解除下跪成功")
	_check(bruce.kneel_used, "限定技仍标记已使用")

	# 5.4 已使用（未下跪）点击 后 toast 限定技已使用
	game._kneel_override = func(): return true
	await game._on_detail_skill_clicked("下跪", bruce)
	_check(not bruce.kneeling, "已使用后不能再发动")
	_check(game._toast_label.text.contains("限定技已使用"), "toast 提示限定技已使用: " + game._toast_label.text)

	# 5.5 点别人技能无效
	await game._on_detail_skill_clicked("下跪", p1)
	_check(not bruce.kneeling, "点别人技能无效")

	# ---- 用例 6：下跪状态，不会成为任何效果的目标 ----
	bruce.kneeling = true
	bruce.kneel_used = true
	bruce.hp = 3
	# 6.1 目标列表排除
	game.turn_manager.current_player_idx = 0
	var strike_targets = game._get_strike_targets(p1)
	_check(not strike_targets.has(bruce), "杀目标列表不含下跪角色")
	var all_targets = game._get_all_alive_targets(p2)
	_check(not all_targets.has(bruce), "所有目标列表不含下跪角色")
	# 6.2 AOE 跳过（p1 为使用者放南蛮，p0 下跪被跳过）
	game.turn_manager.current_player_idx = 1
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.BARBARIAN_INVASION))
	var bruce_hp_before = bruce.hp
	var p2_hp_before = p2.hp
	await game._play_aoe(CardData.CardSubType.STRIKE, "南蛮入侵", "杀")
	_check(bruce.hp == bruce_hp_before, "下跪角色不受南蛮伤害: %d" % bruce.hp)
	_check(p2.hp == p2_hp_before - 1, "其他角色正常受南蛮伤害: %d -> %d" % [p2_hp_before, p2.hp])
	# 6.3 铁索传导跳过
	bruce.hp = bruce.max_hp
	p1.hp = p1.max_hp
	bruce.chained = true
	p1.chained = true
	game.turn_manager.current_player_idx = 0
	await game._deal_damage(p2, p1, 1, EffectChain.DamageType.FIRE)
	_check(bruce.hp == bruce.max_hp, "下跪角色不受铁索传导: %d" % bruce.hp)
	bruce.chained = false
	p1.chained = false
	# 6.4 判定阶段跳过
	bruce.hp = 3
	bruce.judgment_cards.clear()
	bruce.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._do_judge(0)
	_check(bruce.judgment_cards.size() == 1, "下跪角色判定牌保留不结算: %d" % bruce.judgment_cards.size())
	# 判定被跳过，阶段继续推进（摸牌→出牌，回合正常进行）
	_check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "判定跳过并推进到出牌阶段: %s" % game.turn_manager.current_phase)
	bruce.judgment_cards.clear()

	# ---- 用例 7：下跪状态，无法使用或打出任何牌 ----
	bruce.hp = 3
	bruce.hand.clear()
	bruce.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	# 7.1 play_card 拦截
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.play_card(CardData.CardSubType.STRIKE)
	_check(bruce.hand_size() == 1, "下跪角色不能出牌: %d" % bruce.hand_size())
	# 7.2 不能出闪
	var chain = EffectChain.new(p2, bruce, CardBase.create(CardData.CardSubType.STRIKE), EffectChain.EffectType.DAMAGE, 1)
	var can_dodge = await game._on_chain_response_check(chain, bruce, CardData.CardSubType.DODGE, p2)
	_check(not can_dodge, "下跪角色不能出闪")
	# 7.3 无懈询问跳过（不弹窗直接无人响应）
	game.turn_manager.current_player_idx = 1
	var actor = await game._ask_nullification_round("测试")
	_check(actor == "", "下跪角色被跳过无懈询问")

	# ---- 用例 8：详情弹窗技能显示（下跪按钮 / 灰色状态） ----
	bruce.kneeling = true
	game._open_player_detail(bruce)
	await process_frame
	var kneel_btn = _find_btn_rec(game._detail_popup_root, "下跪")
	_check(kneel_btn != null, "详情弹窗有【下跪】按钮")
	var wumou_label = _find_label_rec(game._detail_popup_root, "无谋")
	_check(wumou_label != null, "详情弹窗有无谋描述")
	# 下跪时，无谋灰色
	if wumou_label:
		var wc = wumou_label.get_theme_color("font_color")
		_check(wc.r < 0.6, "下跪状态无谋灰色: %s" % wc)
	# 解除后，下跪按钮灰色（限定技已使用）
	bruce.kneeling = false
	bruce.kneel_used = true
	game._refresh_detail_popup()
	await process_frame
	var kneel_btn2 = _find_btn_rec(game._detail_popup_root, "下跪")
	if kneel_btn2:
		var kc = kneel_btn2.get_theme_color("font_color")
		_check(kc.r < 0.6, "已使用后下跪按钮灰色: %s" % kc)

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)

func _find_btn_rec(node: Node, text: String) -> Button:
	if node is Button and not node.is_queued_for_deletion() and node.text.contains(text):
		return node
	for c in node.get_children():
		var r = _find_btn_rec(c, text)
		if r:
			return r
	return null

func _find_label_rec(node: Node, text: String) -> Label:
	if node is Label and not node.is_queued_for_deletion() and node.text.contains(text):
		return node
	for c in node.get_children():
		var r = _find_label_rec(c, text)
		if r:
			return r
	return null
