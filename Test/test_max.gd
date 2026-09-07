# test_max.gd：麦克斯·欧尼斯特冒烟测试（烂忠厚/ 没用）
extends SceneTree

var failures := 0
var asserts := 0
var game = null
var zone_queue: Array = []
var mount_a_queue: Array = []
var mount_b_queue: Array = []

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "麦克斯·欧尼斯特"
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	# 手动开局：先设置钩子再 start_game（【没用】在回合开始阶段询问，避免开局卡弹窗）
	game.auto_start = false
	root.add_child(game)
	for i in range(6):
		await process_frame

	# 通用钩子：不弹窗
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._meiyong_override = func(): return false
	game._meiyong_option_override = Callable()
	game._meiyong_target_override = Callable()
	game._lanzhonghou_zone_override = Callable()
	game._lanzhonghou_mount_override = Callable()

	game.start_game()
	for i in range(6):
		await process_frame

	var p0 = game.players[0]
	var p1 = game.players[1]
	var p2 = game.players[2]
	var p3 = game.players[3]
	var p4 = game.players[4]

	# ---- 用例 1：武将数量 ----
	_check(GeneralData.is_valid("麦克斯·欧尼斯特"), "麦克斯·欧尼斯特武将存在")
	_check(GeneralData.get_max_hp("麦克斯·欧尼斯特") == 4, "麦克斯·欧尼斯特 4 血: %d" % GeneralData.get_max_hp("麦克斯·欧尼斯特"))
	_check(GeneralData.get_skills("麦克斯·欧尼斯特").size() == 2, "两个技能: %d" % GeneralData.get_skills("麦克斯·欧尼斯特").size())
	_check(p0.general_name == "麦克斯·欧尼斯特", "玩家0 = 麦克斯·欧尼斯特")
	_check(p0.max_hp == 4, "玩家0 体力上限 4: %d" % p0.max_hp)

	# ============ 【烂忠厚】============

	# ---- 用例 2：武器交换（弃 1 张）----
	_set_play_env()
	_set_weapon(p0, CardData.CardSubType.ZHUGE_LIANNU)
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	zone_queue = ["weapon", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["weapon"] == CardData.CardSubType.LIANNU, "武器交换：p0 获得连弩")
	_check(p1.equipment["weapon"] == CardData.CardSubType.ZHUGE_LIANNU, "武器交换：p1 获得诸葛连弩")
	_check(p0.hand_size() == 2, "武器交换：弃 1 张手牌（3->2）: %d" % p0.hand_size())
	_check(game._lanzhonghou_used, "烂忠厚已标记使用")

	# ---- 用例 3：防具交换 ----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_armor(p0, CardData.CardSubType.RENWANG_DUN)
	_set_armor(p1, CardData.CardSubType.SILVER_LION)
	zone_queue = ["armor", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["armor"] == CardData.CardSubType.SILVER_LION, "防具交换：p0 获得白银狮子")
	_check(p1.equipment["armor"] == CardData.CardSubType.RENWANG_DUN, "防具交换：p1 获得仁王盾")

	# ---- 用例 4：坐骑跨槽位交换（A坐骑1 → B坐骑3） 计数正确 ----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_mount(p0, "mount_1", CardData.CardSubType.MOUNT_PLUS)   # p0: +1 马
	_set_mount(p1, "mount_3", CardData.CardSubType.MOUNT_MINUS)  # p1: -1 马
	game._lanzhonghou_mount_override = func(target, _slots):
		return "mount_1" if target == p0 else "mount_3"
	zone_queue = ["mount", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["mount_1"] == CardData.CardSubType.MOUNT_MINUS, "坐骑跨槽交换：p0 坐骑1 变为 -1 马")
	_check(p1.equipment["mount_3"] == CardData.CardSubType.MOUNT_PLUS, "坐骑跨槽交换：p1 坐骑3 变为 +1 马")
	_check(p0.mount_plus == 0 and p0.mount_minus == 1, "p0 计数 +0/-1: %d/%d" % [p0.mount_plus, p0.mount_minus])
	_check(p1.mount_plus == 1 and p1.mount_minus == 0, "p1 计数 +1/-0: %d/%d" % [p1.mount_plus, p1.mount_minus])
	_check(p0.attack_distance_to(p1) == 1 and p1.attack_distance_to(p0) == 1, "交换后距离互相为 1（攻防抵消）: %d/%d" % [p0.attack_distance_to(p1), p1.attack_distance_to(p0)])

	# ---- 用例 5：一方无武器 → 装备直接归还（不交换，但仍弃 1 张）----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	zone_queue = ["weapon", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p1.equipment["weapon"] == CardData.CardSubType.LIANNU, "空区域：p1 武器保留（直接归还）")
	_check(not p0.equipment.has("weapon"), "空区域：p0 无武器")
	_check(p0.hand_size() == 2, "空区域：仍弃 1 张（3->2）: %d" % p0.hand_size())

	# ---- 用例 6：暗置装备不交换 ----
	_set_play_env()
	game._lanzhonghou_used = false
	p0.equipment["weapon"] = CardData.CardSubType.HIDDEN_EQUIPMENT
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	zone_queue = ["weapon", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["weapon"] == CardData.CardSubType.HIDDEN_EQUIPMENT, "暗置装备：p0 暗置保留")
	_check(p1.equipment["weapon"] == CardData.CardSubType.LIANNU, "暗置装备：p1 武器保留")

	# ---- 用例 7：白银狮子交换不触发回血 ----
	_set_play_env()
	game._lanzhonghou_used = false
	p0.hp = 2
	_set_armor(p0, CardData.CardSubType.SILVER_LION)
	_set_armor(p1, CardData.CardSubType.RENWANG_DUN)
	zone_queue = ["armor", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["armor"] == CardData.CardSubType.RENWANG_DUN, "白银狮子：p0 获得仁王盾")
	_check(p1.equipment["armor"] == CardData.CardSubType.SILVER_LION, "白银狮子：p1 获得白银狮子")
	_check(p0.hp == 2, "白银狮子交换不算失去，不触发回血: %d" % p0.hp)

	# ---- 用例 8：破风枪交换 → 加成清零 ----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_weapon(p0, CardData.CardSubType.POFENG_SPEAR)
	p0.hand_limit_bonus = 3
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	zone_queue = ["weapon", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["weapon"] == CardData.CardSubType.LIANNU and p0.hand_limit_bonus == 0, "破风枪：p0 失去加成清零: %d" % p0.hand_limit_bonus)
	_check(p1.equipment["weapon"] == CardData.CardSubType.POFENG_SPEAR and p1.hand_limit_bonus == 0, "破风枪：p1 获得后从 0 开始: %d" % p1.hand_limit_bonus)

	# ---- 用例 9：贤者的加护 → 标记跟随装备转移 ----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_armor(p0, CardData.CardSubType.SAGE_PROTECTION)
	p0.sage_tokens = 2
	_set_armor(p1, CardData.CardSubType.RENWANG_DUN)
	zone_queue = ["armor", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p1.equipment["armor"] == CardData.CardSubType.SAGE_PROTECTION and p1.sage_tokens == 2, "贤者标记随装备转移至 p1: %d" % p1.sage_tokens)
	_check(p0.equipment["armor"] == CardData.CardSubType.RENWANG_DUN and p0.sage_tokens == 0, "贤者标记从 p0 清空: %d" % p0.sage_tokens)

	# ---- 用例 10：多区域交换（武器+坐骑，弃 2 张）----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_weapon(p0, CardData.CardSubType.ZHUGE_LIANNU)
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	_set_mount(p0, "mount_1", CardData.CardSubType.MOUNT_PLUS)
	_set_mount(p1, "mount_2", CardData.CardSubType.MOUNT_MINUS)
	game._lanzhonghou_mount_override = func(target, _slots):
		return "mount_1" if target == p0 else "mount_2"
	zone_queue = ["weapon", "mount", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["weapon"] == CardData.CardSubType.LIANNU, "多区域：武器已交换")
	_check(p0.equipment["mount_1"] == CardData.CardSubType.MOUNT_MINUS, "多区域：坐骑已交换")
	_check(p0.hand_size() == 1, "多区域：弃 2 张（3->1）: %d" % p0.hand_size())

	# ---- 用例 11：取消不消耗手牌 ----
	_set_play_env()
	game._lanzhonghou_used = false
	zone_queue = ["cancel"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.hand_size() == 3, "取消：手牌不消耗: %d" % p0.hand_size())
	_check(not game._lanzhonghou_used, "取消：不标记已使用")

	# ---- 用例 12：一方无坐骑 → 坐骑直接归还（防御路径），坐骑按钮禁用 ----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_mount(p0, "mount_1", CardData.CardSubType.MOUNT_PLUS)
	_check(game._lanzhonghou_has_swappable_mount(p0), "p0 有可交换坐骑")
	_check(not game._lanzhonghou_has_swappable_mount(p1), "p1 无可交换坐骑（按钮应禁用）")
	zone_queue = ["mount", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["mount_1"] == CardData.CardSubType.MOUNT_PLUS, "无马一方：p0 坐骑保留（直接归还）")
	_check(p0.hand_size() == 2, "无马一方：仍弃 1 张（3->2）: %d" % p0.hand_size())

	# ---- 用例 13：两个 AI 角色之间交换（无需含自己）----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_weapon(p1, CardData.CardSubType.ZHUGE_LIANNU)
	_set_weapon(p2, CardData.CardSubType.LIANNU)
	zone_queue = ["weapon", "done"]
	await game._run_lanzhonghou(p1, p2)
	_check(p1.equipment["weapon"] == CardData.CardSubType.LIANNU, "AI 间交换：p1 获得连弩")
	_check(p2.equipment["weapon"] == CardData.CardSubType.ZHUGE_LIANNU, "AI 间交换：p2 获得诸葛连弩")

	# ---- 用例 13b：两对坐骑交换（坐骑槽每个算一对，可多对）----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_mount(p0, "mount_1", CardData.CardSubType.MOUNT_PLUS)
	_set_mount(p0, "mount_3", CardData.CardSubType.MOUNT_MINUS)
	_set_mount(p1, "mount_2", CardData.CardSubType.MOUNT_MINUS)
	_set_mount(p1, "mount_4", CardData.CardSubType.MOUNT_PLUS)
	mount_a_queue = ["mount_1", "mount_3"]
	mount_b_queue = ["mount_2", "mount_4"]
	game._lanzhonghou_mount_override = func(target, _slots):
		return mount_a_queue.pop_front() if target == p0 else mount_b_queue.pop_front()
	zone_queue = ["mount", "mount", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["mount_1"] == CardData.CardSubType.MOUNT_MINUS and p0.equipment["mount_3"] == CardData.CardSubType.MOUNT_PLUS, "两对坐骑：p0 槽位内容互换")
	_check(p1.equipment["mount_2"] == CardData.CardSubType.MOUNT_PLUS and p1.equipment["mount_4"] == CardData.CardSubType.MOUNT_MINUS, "两对坐骑：p1 槽位内容互换")
	_check(p0.mount_plus == 1 and p0.mount_minus == 1, "两对坐骑：p0 计数 +1/-1: %d/%d" % [p0.mount_plus, p0.mount_minus])
	_check(p0.hand_size() == 1, "两对坐骑：弃 2 张（3->1）: %d" % p0.hand_size())

	# ---- 用例 13c：武器+防具+坐骑×2 = 4 对，弃 4 张 ----

	_set_play_env()
	game._lanzhonghou_used = false
	p0.hand.clear()
	for i in 5:
		p0.hand.append(null)
	_set_weapon(p0, CardData.CardSubType.ZHUGE_LIANNU)
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	_set_armor(p0, CardData.CardSubType.RENWANG_DUN)
	_set_armor(p1, CardData.CardSubType.SILVER_LION)
	_set_mount(p0, "mount_1", CardData.CardSubType.MOUNT_PLUS)
	_set_mount(p1, "mount_2", CardData.CardSubType.MOUNT_MINUS)
	_set_mount(p0, "mount_3", CardData.CardSubType.MOUNT_PLUS)
	_set_mount(p1, "mount_4", CardData.CardSubType.MOUNT_MINUS)
	mount_a_queue = ["mount_1", "mount_3"]
	mount_b_queue = ["mount_2", "mount_4"]
	game._lanzhonghou_mount_override = func(target, _slots):
		return mount_a_queue.pop_front() if target == p0 else mount_b_queue.pop_front()
	zone_queue = ["weapon", "armor", "mount", "mount", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.equipment["weapon"] == CardData.CardSubType.LIANNU and p1.equipment["weapon"] == CardData.CardSubType.ZHUGE_LIANNU, "4对：武器已交换")
	_check(p0.equipment["armor"] == CardData.CardSubType.SILVER_LION and p1.equipment["armor"] == CardData.CardSubType.RENWANG_DUN, "4对：防具已交换")
	_check(p0.mount_plus == 0 and p0.mount_minus == 2, "4对：p0 坐骑计数 +0/-2: %d/%d" % [p0.mount_plus, p0.mount_minus])
	_check(p0.hand_size() == 1, "4对：弃 4 张（5->1）: %d" % p0.hand_size())

	# ---- 用例 13d：满 6 对（武器+防具+坐骑×4）→ 弃 6 张 ----

	_set_play_env()
	game._lanzhonghou_used = false
	p0.hand.clear()
	for i in 8:
		p0.hand.append(null)
	_set_weapon(p0, CardData.CardSubType.ZHUGE_LIANNU)
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	_set_armor(p0, CardData.CardSubType.RENWANG_DUN)
	_set_armor(p1, CardData.CardSubType.SILVER_LION)
	for s in Player.MOUNT_SLOTS:
		_set_mount(p0, s, CardData.CardSubType.MOUNT_PLUS)
		_set_mount(p1, s, CardData.CardSubType.MOUNT_MINUS)
	mount_a_queue = Player.MOUNT_SLOTS.duplicate()
	mount_b_queue = Player.MOUNT_SLOTS.duplicate()
	game._lanzhonghou_mount_override = func(target, _slots):
		return mount_a_queue.pop_front() if target == p0 else mount_b_queue.pop_front()
	zone_queue = ["weapon", "armor", "mount", "mount", "mount", "mount", "done"]
	await game._run_lanzhonghou(p0, p1)
	_check(p0.mount_plus == 0 and p0.mount_minus == 4, "6对：p0 全部 +1 马换成 -1 马: %d/%d" % [p0.mount_plus, p0.mount_minus])
	_check(p1.mount_plus == 4 and p1.mount_minus == 0, "6对：p1 全部 -1 马换成 +1 马: %d/%d" % [p1.mount_plus, p1.mount_minus])
	_check(p0.equipment["weapon"] == CardData.CardSubType.LIANNU, "6对：武器已交换")
	_check(p0.hand_size() == 2, "6对：弃 6 张（8->2）: %d" % p0.hand_size())

	# ---- 用例 13e：坐骑最多 4 对（防御：第 5 对直调被拒）----
	_set_play_env()
	game._lanzhonghou_used = false
	p0.hand.clear()
	for i in 6:
		p0.hand.append(null)
	for s in Player.MOUNT_SLOTS:
		_set_mount(p0, s, CardData.CardSubType.MOUNT_PLUS)
		_set_mount(p1, s, CardData.CardSubType.MOUNT_MINUS)
	mount_a_queue = Player.MOUNT_SLOTS.duplicate()
	mount_b_queue = Player.MOUNT_SLOTS.duplicate()
	game._lanzhonghou_mount_override = func(target, _slots):
		return mount_a_queue.pop_front() if target == p0 else mount_b_queue.pop_front()
	zone_queue = ["mount", "mount", "mount", "mount", "mount", "done"]  # 第 5 个坐骑对被拒
	await game._run_lanzhonghou(p0, p1)
	_check(p0.mount_plus == 0 and p0.mount_minus == 4, "坐骑最多对：只交换 4 对: %d/%d" % [p0.mount_plus, p0.mount_minus])
	_check(p0.hand_size() == 2, "坐骑最多对：弃 4 张（6->2）: %d" % p0.hand_size())
	_check(mount_a_queue.is_empty(), "坐骑最多对：5 对中第 5 对被拒（槽位队列剩空）")

	# ---- 用例 13f：已选坐骑槽不再出现在候选中（_lanzhonghou_has_swappable_mount）----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_mount(p0, "mount_1", CardData.CardSubType.MOUNT_PLUS)
	_set_mount(p0, "mount_2", CardData.CardSubType.MOUNT_MINUS)
	var picked_m1 = [{"zone": "mount", "a": p0, "slot_a": "mount_1", "b": p1, "slot_b": "mount_2", "ok": true}]
	_check(game._lanzhonghou_has_swappable_mount(p0, picked_m1, true), "p0 还有未用坐骑槽（mount_2）")
	var picked_m2 = picked_m1 + [{"zone": "mount", "a": p0, "slot_a": "mount_2", "b": p1, "slot_b": "mount_3", "ok": true}]
	_check(not game._lanzhonghou_has_swappable_mount(p0, picked_m2, true), "p0 坐骑槽全部被选后无可交换")
	_check(game._lanzhonghou_count(picked_m2, "mount") == 2, "区域计数：坐骑 2 个")
	_check(game._lanzhonghou_count(picked_m1, "weapon") == 0, "区域计数：武器 0 个")

	# ---- 用例 14：详情弹窗，点击【烂忠厚】→ 选两名角色，执行 ----
	_set_play_env()
	game._lanzhonghou_used = false
	_set_weapon(p0, CardData.CardSubType.ZHUGE_LIANNU)
	_set_weapon(p1, CardData.CardSubType.LIANNU)
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._open_player_detail(p0)
	await process_frame
	var btn = _find_btn_rec(game._detail_popup_root, "烂忠厚")
	_check(btn != null, "详情弹窗显示【烂忠厚】技能按钮")
	btn.pressed.emit()
	await process_frame
	await process_frame
	_check(game._is_lanzhonghou_targeting, "点击【烂忠厚】→ 进入角色选择模式")
	_check(not game._detail_popup_root.visible, "发动后详情弹窗自动关闭")
	zone_queue = ["weapon", "done"]
	await game._on_lanzhonghou_target_click(p0)
	_check(game._is_lanzhonghou_targeting, "选 1 名角色后仍在选择 1/2")
	await game._on_lanzhonghou_target_click(p1)
	_check(not game._is_lanzhonghou_targeting, "选 2 名角色后退出选择模式")
	_check(p0.equipment["weapon"] == CardData.CardSubType.LIANNU, "全流程：p0 武器已交换")
	_check(p1.equipment["weapon"] == CardData.CardSubType.ZHUGE_LIANNU, "全流程：p1 武器已交换")
	_check(p0.hand_size() == 2, "全流程：弃 1 张（3->2）: %d" % p0.hand_size())

	# ---- 用例 15：限一次 ----
	game._lanzhonghou_used = true
	game._is_lanzhonghou_targeting = false
	game._on_lanzhonghou_skill_clicked(p0)
	_check(not game._is_lanzhonghou_targeting, "限一次：已使用后不能再次发动")
	game._lanzhonghou_used = false

	# ---- 用例 16：阵亡角色不能选择 ----
	game._is_lanzhonghou_targeting = true
	game._lanzhonghou_selected.clear()
	p1.hp = 0
	await game._on_lanzhonghou_target_click(p1)
	_check(game._lanzhonghou_selected.is_empty(), "阵亡角色不能选择")
	p1.hp = p1.max_hp
	game._is_lanzhonghou_targeting = false
	game._lanzhonghou_selected.clear()

	# ============ 【没用】============

	# ---- 用例 17：选项1 → 目标乐不思蜀失效（判定区清空、无副作用），自己正常摸 2 ----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	p1.judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
	await _run_p0_turn(0, 1)
	_check(p1.judgment_cards.is_empty(), "选项1：目标乐不思蜀已判定消耗（失效）")
	_check(not game.turn_manager.skip_play_phase, "选项1：乐不思蜀失效，无人跳过出牌阶段")
	_check(p0.hand_size() == 7, "选项1：自己摸 1（没用）+ 摸牌阶段 2 张，+1+2=7 张: %d" % p0.hand_size())
	_check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "选项1：自己正常进入出牌阶段")

	# ---- 用例 18：选项1 → 目标闪电正常生效（3 点雷伤）----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	p1.hp = p1.max_hp
	p1.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
	await _run_p0_turn(0, 1)
	_check(p1.hp == p1.max_hp - 3, "选项1：目标闪电 3 点雷伤（4->1）: %d" % p1.hp)
	_check(p1.judgment_cards.is_empty(), "选项1：闪电已判定消耗")
	_check(p0.hand_size() == 7, "选项1：自己摸牌正常: %d" % p0.hand_size())

	# ---- 用例 19：选项1 → 目标兵粮寸断失效（自己摸牌不少摸）----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	p1.hp = p1.max_hp
	p1.judgment_cards.append(CardBase.create(CardData.CardSubType.SUPPLY_SHORTAGE))
	await _run_p0_turn(0, 1)
	_check(p1.judgment_cards.is_empty(), "选项1：兵粮寸断已判定消耗（失效）")
	_check(p0.hand_size() == 7, "选项1：兵粮失效，自己摸牌阶段 2 张: %d" % p0.hand_size())
	_check(not game.turn_manager.supply_shortage_active, "选项1：兵粮失效，无少摸标记")

	# ---- 用例 20：选项1 → 目标火烧连营正常生效（三连伤 + 蔓延）----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	p0.hp = 4
	p1.hp = 4
	p2.hp = 4
	p1.judgment_cards.append(CardBase.create(CardData.CardSubType.BURNING_CAMP))
	await _run_p0_turn(0, 1)
	# p1 seat1：左邻 = seat2（p2），右邻 = seat0（p0）
	_check(p1.hp == 3, "选项1：火烧连营中，p1 受 1 火伤: %d" % p1.hp)
	_check(p2.hp == 3, "选项1：左邻 p2 受 1 火伤: %d" % p2.hp)
	_check(p0.hp == 3, "选项1：右邻 p0 受 1 火伤: %d" % p0.hp)
	_check(p2.judgment_cards.size() == 1 and p2.judgment_cards[0].sub_type == CardData.CardSubType.BURNING_CAMP, "选项1：左邻判定区生成火烧连营")
	_check(p0.judgment_cards.size() == 1 and p0.judgment_cards[0].sub_type == CardData.CardSubType.BURNING_CAMP, "选项1：右邻（自己）判定区生成火烧连营")

	# ---- 用例 21：选项2 → 跳过摸牌，目标摸 2 ----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	p1.hand.clear()
	for i in 4:
		p1.hand.append(null)
	await _run_p0_turn(1, 1)
	_check(p0.hand_size() == 5, "选项2：自己只摸 1（没用），跳过摸牌阶段: %d" % p0.hand_size())
	_check(p1.hand_size() == 6, "选项2：目标获得摸牌阶段摸 2 张（+2=6）: %d" % p1.hand_size())
	_check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "选项2：自己正常进入出牌阶段")

	# ---- 用例 22：选项3 → 跳过出牌 → 弃牌 → 回合结束 → 下一玩家 ----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	await _run_p0_turn(2, 1)
	# p0: 没用+1=5 → 摸牌+2=7 → 跳过出牌 → 弃牌（上限4）弃3 → 4 → 回合结束 → P1 开始
	_check(p0.hand_size() == 4, "选项3：弃牌阶段后手牌 4 张（-3）: %d" % p0.hand_size())
	_check(game.turn_manager.current_player_idx == 1, "选项3：自己的回合已结束，切到下一玩家: %d" % game.turn_manager.current_player_idx)
	_check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "选项3：P1 出牌阶段（AI 停驻）")

	# ---- 用例 23：不发动 → 正常摸 2 ----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	game._meiyong_override = func(): return false
	await _run_p0_turn_raw()
	_check(p0.hand_size() == 6, "不发动：正常摸 2 张，+2=6 张: %d" % p0.hand_size())

	# ---- 用例 24：取消三选一 → 收回已摸的牌 ----
	_clear_all_zones()
	p0.hand.clear()
	for i in 4:
		p0.hand.append(null)
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return -1
	await _run_p0_turn_raw()
	_check(p0.hand_size() == 6, "取消三选一：收回已摸的牌（4+1-1+2=6）: %d" % p0.hand_size())

	# ---- 用例 25：判定目标选择校验（UI 点击路径）----
	_clear_all_zones()
	game._is_meiyong_targeting = true
	game._meiyong_option = 0
	p1.judgment_cards.clear()
	game._on_meiyong_target_click(p1)
	_check(game._is_meiyong_targeting, "判定目标无判定牌 → 拒绝（保持选择中）")
	p1.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
	game._on_meiyong_target_click(p1)
	_check(not game._is_meiyong_targeting, "判定目标有判定牌 → 接受")
	# 不能选自己
	game._is_meiyong_targeting = true
	game._meiyong_option = 1
	game._on_meiyong_target_click(p0)
	_check(game._is_meiyong_targeting, "不能选择自己作为目标")
	game._is_meiyong_targeting = false

	# ---- 用例 26：_pick_meiyong_target 信号驱动选择（call_deferred 先发出目标信号，再 await）----
	game._meiyong_target_override = Callable()
	p1.judgment_cards.clear()
	p1.judgment_cards.append(CardBase.create(CardData.CardSubType.INDULGENCE))
	p2.judgment_cards.clear()
	game._meiyong_pick_result.emit.call_deferred(p1)
	var r1 = await game._pick_meiyong_target(0, p0)
	_check(r1 == p1, "选项1目标选择：返回判定区有牌的角色")
	game._is_meiyong_targeting = false
	game._meiyong_pick_result.emit.call_deferred(p2)
	var r2 = await game._pick_meiyong_target(1, p0)
	_check(r2 == p2, "选项2目标选择：返回任意存活角色")
	game._is_meiyong_targeting = false

	# ---- 用例 27：取消按钮退出【没用】选择 ----
	game._on_cancel_target_pressed.call_deferred()
	var r3 = await game._pick_meiyong_target(0, p0)
	_check(r3 == null, "取消按钮：目标选择返回 null")

	# ---- 用例 28：取消按钮退出【烂忠厚】角色选择 ----
	game._is_lanzhonghou_targeting = true
	game._lanzhonghou_selected.clear()
	game._on_cancel_target_pressed()
	_check(not game._is_lanzhonghou_targeting, "取消按钮：退出烂忠厚角色选择")
	_check(game._lanzhonghou_selected.is_empty(), "取消按钮：清空已选角色")

	# ---- 用例 29：取消按钮退出【烂忠厚】时恢复出牌按钮 ----
	game._is_lanzhonghou_targeting = true
	game._lanzhonghou_selected.clear()
	game._on_cancel_target_pressed()
	_check(game._play_btn.visible, "取消烂忠厚后出牌按钮恢复")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

# ---- 辅助 ----

# 烂忠厚用例环境：玩家0 出牌阶段 + 3 张手牌 + 干净装备 + 未使用
func _set_play_env():
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._halt_countdown()
	game._lanzhonghou_used = false
	game._lanzhonghou_selected.clear()
	game._lanzhonghou_pending.clear()
	game._lanzhonghou_mount_override = Callable()
	zone_queue.clear()
	# 区域选择钩子：从 zone_queue 依次取（"weapon"/"armor"/"mount"/"done"/"cancel"）
	game._lanzhonghou_zone_override = func(): return zone_queue.pop_front()
	_clear_equips_all()
	_clear_all_zones()
	var p0 = game.players[0]
	p0.hand.clear()
	for i in 3:
		p0.hand.append(null)
	p0.hp = p0.max_hp

# 没用用例：跑玩家0 完整回合（从 START 开始），option = 0/1/2，target_idx = 目标座位
func _run_p0_turn(option: int, target_idx: int) -> void:
	game._meiyong_override = func(): return true
	game._meiyong_option_override = func(): return option
	game._meiyong_target_override = func(): return game.players[target_idx]
	await _run_p0_turn_raw()

# 不设三选一/目标钩子（用例 23/24 自己设）
func _run_p0_turn_raw() -> void:
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.START
	game._halt_countdown()
	await game._do_start(0)
	for i in range(8):
		await process_frame

func _clear_equips_all():
	for p in game.players:
		var slots = p.get_equip_slots()
		for s in slots:
			p.remove_equipment(s)

func _clear_all_zones():
	for p in game.players:
		p.judgment_cards.clear()
		p.hp = p.max_hp
		p.chained = false

func _set_weapon(p: Player, sub: CardData.CardSubType):
	p.equipment["weapon"] = sub

func _set_armor(p: Player, sub: CardData.CardSubType):
	p.equipment["armor"] = sub

func _set_mount(p: Player, slot: String, sub: CardData.CardSubType):
	p.equipment[slot] = sub
	if sub == CardData.CardSubType.MOUNT_PLUS:
		p.mount_plus += 1
	elif sub == CardData.CardSubType.MOUNT_MINUS:
		p.mount_minus += 1

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
