# test_jacqui.gd — 杰基·斯特朗冒烟测试（霸王 / 校园霸主）
extends SceneTree

var failures := 0
var asserts := 0
var game = null

# 拼点出拳序列（_rps_test 用）：p0 的拳序列 / 对手的拳序列（按调用顺序循环取）
var rps_seq_p0: Array = []
var rps_seq_opp: Array = []
var rps_idx_a: int = 0
var rps_idx_b: int = 0

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "杰基·斯特朗"
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	var p0 = game.players[0]
	var p1 = game.players[1]
	var p2 = game.players[2]
	var p3 = game.players[3]
	var p4 = game.players[4]

	# 通用钩子：不弹窗
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._duel_respond_override = Callable()
	game._duel_second_override = Callable()
	game._rps_override = Callable()

	# ---- 用例 1：武将数据 ----
	_check(GeneralData.is_valid("杰基·斯特朗"), "杰基·斯特朗武将存在")
	_check(GeneralData.get_max_hp("杰基·斯特朗") == 6, "杰基·斯特朗 6 血")
	_check(GeneralData.get_skills("杰基·斯特朗").size() == 2, "两个技能: %d" % GeneralData.get_skills("杰基·斯特朗").size())
	_check(p0.general_name == "杰基·斯特朗", "玩家0 = 杰基·斯特朗")
	_check(p0.max_hp == 6, "玩家0 体力上限 6: %d" % p0.max_hp)

	# ---- 用例 2：【霸王】决斗上限 3 ----
	game.turn_manager.duel_count_this_turn = 2
	_check(game.turn_manager.can_use("duel", 3), "杰基：已用 2 张决斗仍可用（上限 3）")
	game.turn_manager.duel_count_this_turn = 3
	_check(not game.turn_manager.can_use("duel", 3), "杰基：已用 3 张决斗不可用")
	_check(not game.turn_manager.can_use("duel", 2), "对照：普通上限 2 时已用 3 不可用")
	game.turn_manager.duel_count_this_turn = 0

	# ---- 用例 3：【霸王】决斗无距离限制 ----
	p3.equip_mount(CardData.CardSubType.MOUNT_PLUS)
	_check(p0.attack_distance_to(p3) == 3, "p3 装 +1 马后距离 3: %d" % p0.attack_distance_to(p3))
	var duel_targets = game._get_duel_targets(p0)
	_check(duel_targets.has(p3), "杰基：距离 3 的目标仍在决斗目标列表")
	p0.general_name = "稻草人"
	var duel_targets_normal = game._get_duel_targets(p0)
	_check(not duel_targets_normal.has(p3), "对照：普通武将距离 3 的目标不在决斗目标列表")
	p0.general_name = "杰基·斯特朗"
	p3.hp = p3.max_hp
	p3.hand.clear()
	game.turn_manager.current_player_idx = 0
	await game._play_duel(p0, p3)
	_check(p3.hp == p3.max_hp - 1, "杰基：距离 3 决斗生效（p3 受 1 点伤害）: %d" % p3.hp)

	# ---- 用例 4：【霸王】对方先响应 + 每次响应需两张杀（对方 = 玩家0）---
	# 场景：AI 杰基（p1）对 p0 决斗 → p0（非杰基方）先响应且需依次打出两张杀
	p1.general_name = "杰基·斯特朗"
	p1.max_hp = 6
	p1.hp = 6
	p0.general_name = "稻草人"
	p0.max_hp = 5
	p0.hp = 5
	game.turn_manager.current_player_idx = 1
	# 4a：p0 出两张杀 → 轮到 AI 杰基不响应 → 杰基受伤
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	game._duel_respond_override = func(): return true    # p0 出第一张
	game._duel_second_override = func(): return true     # p0 继续出第二张
	await game._play_duel(p1, p0)
	_check(p0.hand_size() == 1, "霸王：对方响应需两张杀（3->1）: %d" % p0.hand_size())
	_check(p1.hp == 5, "p0 出两张杀后轮到 AI 杰基，AI 不响应 → 杰基受伤（6->5）: %d" % p1.hp)
	# 4b：p0 打出第一张后放弃第二张 → p0 受伤（第一张白打）
	p0.hp = 5
	p1.hp = 6
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	game._duel_second_override = func(): return false
	await game._play_duel(p1, p0)
	_check(p0.hand_size() == 1, "霸王：只打出第一张（2->1）: %d" % p0.hand_size())
	_check(p0.hp == 4, "霸王：放弃第二张 → p0 受伤（5->4）: %d" % p0.hp)
	_check(p1.hp == 6, "霸王：杰基未受伤: %d" % p1.hp)
	# 4c：p0 只有一张杀 → 出第一张后无第二张 → 自动失败受伤
	p0.hp = 5
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	game._duel_second_override = Callable()
	await game._play_duel(p1, p0)
	_check(p0.hp == 4, "霸王：只有一张杀，出后无第二张 → 受伤（5->4）: %d" % p0.hp)
	_check(p0.hand_size() == 0, "霸王：仅有的杀已打出: %d" % p0.hand_size())
	# 4d：p0 第一张就不响应 → 直接受伤
	p0.hp = 5
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	game._duel_respond_override = func(): return false
	await game._play_duel(p1, p0)
	_check(p0.hp == 4, "霸王：不响应 → 直接受伤（5->4）: %d" % p0.hp)
	_check(p1.hp == 6, "霸王：杰基未受伤: %d" % p1.hp)

	# ---- 用例 5：【霸王】杰基被决斗时，对方（攻击者）先响应 ----
	# p0（稻草人）对 p1（杰基）决斗 → 霸王：p0 先响应（原版是目标杰基先响应）
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	p0.hp = 5
	p1.hp = 6
	game._duel_respond_override = func(): return false  # p0 不响应 → 攻击者自己受伤
	await game._play_duel(p0, p1)
	_check(p0.hp == 4, "杰基被决斗：攻击者 p0 先响应，不响应 → p0 受伤（5->4）: %d" % p0.hp)
	_check(p1.hp == 6, "杰基被决斗：杰基未受伤: %d" % p1.hp)
	game._duel_respond_override = Callable()
	game._duel_second_override = Callable()

	# ---- 用例 6：【校园霸主】点击头像 → 详情弹窗 → 技能 → 目标选择模式 ----
	p0.general_name = "杰基·斯特朗"
	p0.max_hp = 6
	p0.hp = 6
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game._open_player_detail(p0)
	await process_frame
	var campus_btn = _find_btn_rec(game._detail_popup_root, "校园霸主")
	_check(campus_btn != null, "详情弹窗显示【校园霸主】技能按钮")
	campus_btn.pressed.emit()
	await process_frame
	await process_frame
	_check(game._is_campus_targeting, "点击【校园霸主】→ 进入目标选择模式")
	_check(not game._detail_popup_root.visible, "发动后详情弹窗自动关闭")

	# ---- 用例 7：【校园霸主】拼点赢 → 目标受伤 ----
	p1.hp = p1.max_hp
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game._rps_override = Callable(self, "_rps_test")
	rps_seq_p0 = [0]        # 石头
	rps_seq_opp = [2]       # 剪刀 → 杰基赢
	rps_idx_a = 0
	rps_idx_b = 0
	await game._on_campus_target_click(p1)
	_check(p0.hand_size() == 1, "校园霸主：自己弃 1 张（2->1）: %d" % p0.hand_size())
	_check(p1.hand_size() == 0, "校园霸主：目标弃 1 张: %d" % p1.hand_size())
	_check(p1.hp == p1.max_hp - 1, "杰基拼点赢 → p1 受 1 点伤害: %d" % p1.hp)
	_check(not game._is_campus_targeting, "执行后退出目标选择模式")

	# ---- 用例 8：【校园霸主】拼点输 → 自己受伤（伤害来源 = 目标）---
	p0.hp = 6
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	rps_seq_p0 = [2]        # 剪刀
	rps_seq_opp = [0]       # 石头 → 杰基输
	rps_idx_a = 0
	rps_idx_b = 0
	await game._execute_campus_dominator(p0, p1)
	_check(p0.hp == 5, "杰基拼点输 → 自己受 1 点伤害（6->5）: %d" % p0.hp)

	# ---- 用例 9：【校园霸主】拼点平局后继续直到分出胜负 ----
	p0.hp = 6
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hp = p1.max_hp
	rps_seq_p0 = [0, 0]     # 石头、石头
	rps_seq_opp = [0, 2]    # 石头（平）→ 剪刀（输）
	rps_idx_a = 0
	rps_idx_b = 0
	await game._execute_campus_dominator(p0, p1)
	_check(rps_idx_a == 2, "校园霸主拼点：平局后继续（p0 出拳 2 次）: %d" % rps_idx_a)
	_check(p1.hp == p1.max_hp - 1, "平局后继续 → 杰基赢 → p1 受伤: %d" % p1.hp)
	game._rps_override = Callable()

	# ---- 用例 10：目标无手牌不能发动（点击被拒，无消耗）----
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.clear()
	var p1_hp_before = p1.hp
	await game._on_campus_target_click(p1)
	_check(p1.hp == p1_hp_before, "目标无手牌：p1 未受伤: %d" % p1.hp)
	_check(p0.hand_size() == 1, "目标无手牌：自己不弃牌: %d" % p0.hand_size())

	# ---- 用例 11：取消按钮退出校园霸主模式 ----
	game._is_campus_targeting = true
	game._on_cancel_target_pressed()
	_check(not game._is_campus_targeting, "取消按钮退出校园霸主模式")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

# 拼点测试钩子：p0 出 rps_seq_p0 序列，其他玩家出 rps_seq_opp 序列（循环取）
func _rps_test(p: Player) -> int:
	if p == game.players[0]:
		var c = rps_seq_p0[rps_idx_a % rps_seq_p0.size()]
		rps_idx_a += 1
		return c
	var c2 = rps_seq_opp[rps_idx_b % rps_seq_opp.size()]
	rps_idx_b += 1
	return c2

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
