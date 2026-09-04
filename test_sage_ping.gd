# test_sage_ping.gd — 贤者的加护：详情弹窗发动全流程冒烟测试
extends SceneTree

var failures := 0
var asserts := 0

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	var game_scene = load("res://Scenes/Game.tscn")
	var game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	var p0 = game.players[0]
	var p1 = game.players[1]

	# 准备：P0 装备贤者的加护、未激活、有手牌；当前是 P0 出牌阶段
	p0.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	p0.sage_tokens = 0
	p0.sage_activated = false
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = game.turn_manager.Phase.PLAY

	# 猜拳钩子：P0 恒出石头(0)，对手恒出剪刀(2) → P0 必赢（石头>剪刀）
	game._rps_override = func(p):
		if p == p0:
			return 0
		return 2

	# ---- 用例 1：点开自己详情 → 点击贤者的加护 → 进入拼点目标选择 ----
	game._is_sage_targeting = false
	game._on_detail_equip_clicked(CardData.CardSubType.SAGE_PROTECTION, p0)
	_check(game._is_sage_targeting, "点击自己的贤者的加护进入目标选择模式")
	_check(game._cancel_target_btn.visible, "取消按钮出现")

	# ---- 用例 2：点击目标 → 弃牌拼点 → 赢 → 获得 1 标记 ----
	var hand_before = p0.hand_size()
	await game._on_sage_target_click(p1)
	_check(p0.sage_tokens == 1, "拼点赢获得 1 贤者标记: %d" % p0.sage_tokens)
	_check(p0.hand_size() == hand_before - 1, "弃置一张手牌: %d -> %d" % [hand_before, p0.hand_size()])
	_check(not game._is_sage_targeting, "拼点结束退出目标选择")

	# ---- 用例 3：点别人的贤者的加护不能发动 ----
	game._is_sage_targeting = false
	var p2 = game.players[2]
	p2.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	game._on_detail_equip_clicked(CardData.CardSubType.SAGE_PROTECTION, p2)
	_check(not game._is_sage_targeting, "点别人的贤者的加护不进入选择模式")

	# ---- 用例 4：非出牌阶段不能发动 ----
	game.turn_manager.current_phase = game.turn_manager.Phase.DRAW
	game._on_detail_equip_clicked(CardData.CardSubType.SAGE_PROTECTION, p0)
	_check(not game._is_sage_targeting, "非出牌阶段不进入选择模式")
	game.turn_manager.current_phase = game.turn_manager.Phase.PLAY

	# ---- 用例 5：3 标记激活 ----
	p0.sage_tokens = 2
	await game._on_sage_target_click(p1)
	_check(p0.sage_tokens == 0 and p0.sage_activated, "3 标记激活装备")
	# 激活后不能再拼点
	game._on_detail_equip_clicked(CardData.CardSubType.SAGE_PROTECTION, p0)
	_check(not game._is_sage_targeting, "已激活不能再发动拼点")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
