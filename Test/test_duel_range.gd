# test_duel_range.gd：决斗距离限制 2 冒烟测试（2026-08-24 朋友规则修订：原为无距离限制）
extends SceneTree

var failures := 0
var asserts := 0
var game = null

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "稻草人"
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
	game.turn_manager.current_player_idx = 0

	# ---- 用例 1：基础座位距离（5 人局，无马）----
	_check(p0.attack_distance_to(p1) == 1, "座0→座1 距离 1: %d" % p0.attack_distance_to(p1))
	_check(p0.attack_distance_to(p2) == 2, "座0→座2 距离 2: %d" % p0.attack_distance_to(p2))
	_check(p0.attack_distance_to(p3) == 2, "座0→座3 距离 2: %d" % p0.attack_distance_to(p3))
	_check(p0.attack_distance_to(p4) == 1, "座0→座4 距离 1: %d" % p0.attack_distance_to(p4))

	# ---- 用例 2：_get_duel_targets 包含距离 2 内全部（5 人局无马 = 全部 4 人）----
	var duel_targets = game._get_duel_targets(p0)
	_check(duel_targets.size() == 4, "无马时决斗目标 = 全部 4 人: %d" % duel_targets.size())

	# ---- 用例 3：目标 +1 马（距离 3）不在决斗目标列表 ----
	p3.equip_mount(CardData.CardSubType.MOUNT_PLUS)
	_check(p0.attack_distance_to(p3) == 3, "座0 装 +1 马后距离 3: %d" % p0.attack_distance_to(p3))
	duel_targets = game._get_duel_targets(p0)
	_check(not duel_targets.has(p3), "距离 3 的目标不在决斗目标列表")
	_check(duel_targets.size() == 3, "决斗目标数 3 人: %d" % duel_targets.size())

	# ---- 用例 4：_play_duel 兜底拒绝（距离 3）----
	var p3_hp = p3.hp
	var p0_hp = p0.hp
	for p in game.players:
		p.hand.clear()
	await game._play_duel(p0, p3)
	_check(p3.hp == p3_hp and p0.hp == p0_hp, "距离 3 决斗被兜底拒绝（无人受伤）: p3=%d p0=%d" % [p3.hp, p0.hp])

	# ---- 用例 5：自己 -1 马抵消目标 +1 马（距离回到 2）可决斗并生效 ----
	p0.equip_mount(CardData.CardSubType.MOUNT_MINUS)
	_check(p0.attack_distance_to(p3) == 2, "-1马抵消 +1 马后距离 2: %d" % p0.attack_distance_to(p3))
	duel_targets = game._get_duel_targets(p0)
	_check(duel_targets.has(p3), "-1马抵消后 p3 回到决斗目标列表")
	p3.hp = p3.max_hp
	p3.hand.clear()
	p0.hand.clear()
	game.turn_manager.strike_count_this_turn = 0
	await game._play_duel(p0, p3)
	_check(p3.hp == p3.max_hp - 1, "距离 2 决斗生效：p3 掉 1 点伤害: %d" % p3.hp)

	# ---- 用例 6：距离 1 决斗正常（p1）----
	p1.hand.clear()
	p1.hp = p1.max_hp
	await game._play_duel(p0, p1)
	_check(p1.hp == p1.max_hp - 1, "距离 1 决斗生效：p1 掉 1 点伤害: %d" % p1.hp)

	# ---- 用例 7：出牌阶段目标点击的距离检查 ----
	# 先卸掉 p0 的 -1 马（用例 5 装的），使 p3 距离回到 3
	for s in Player.MOUNT_SLOTS:
		if p0.equipment.has(s):
			p0.remove_equipment(s)
	_check(p0.attack_distance_to(p3) == 3, "卸马后 p3 距离回到 3: %d" % p0.attack_distance_to(p3))
	# 直测 _on_target_click 的距离分支：p3 距离 3，点击应被拒绝且不进入确认
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.DUEL))
	game._targeting_card_sub = CardData.CardSubType.DUEL
	game._is_targeting = true
	var p3_hp_before = p3.hp
	await game._on_target_click(p3)
	_check(p3.hp == p3_hp_before, "目标选择：距离 3 时 p3 点击被拒（未受伤）: %d" % p3.hp)
	_check(game._is_targeting, "目标选择：距离 3 点击后仍处选择模式")
	game._is_targeting = false
	game._targeting_card_sub = -1

	# ---- 用例 8：目标选择中距离 2 可点（p2 无马距离 2）→ 确认后执行决斗 ----
	p2.hand.clear()
	p2.hp = p2.max_hp
	game._target_confirm_override = func(): return true
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.DUEL))
	game._targeting_card_sub = CardData.CardSubType.DUEL
	game._is_targeting = true
	await game._on_target_click(p2)
	_check(p2.hp == p2.max_hp - 1, "目标选择：距离 2 时 p2 点击确认后决斗生效（掉 1 点伤害）: %d" % p2.hp)
	_check(not game._is_targeting, "确认后退出目标选择模式")
	game._target_confirm_override = Callable()

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
