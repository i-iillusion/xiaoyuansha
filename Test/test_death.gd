# test_death.gd — 阵亡管线冒烟测试
# 按朋友要求分阶段验证：阵亡判定 → 阵亡效果（弃牌）→ 翻开身份 → 击杀奖惩 → 胜负判定
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

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 5
	GameManager.selected_general = "稻草人"
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	game.auto_start = false
	root.add_child(game)
	for i in range(6):
		await process_frame
	# 通用钩子：不弹窗
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game.start_game()
	for i in range(6):
		await process_frame

	var p0 = game.players[0]  # 主公
	var p1 = game.players[1]  # 忠臣
	var p2 = game.players[2]  # 反贼
	var p3 = game.players[3]  # 反贼
	var p4 = game.players[4]  # 内奸

	# ---- 用例1：初始身份公开状态（主公公开，其余隐藏）----
	_check(p0.identity == "主公" and p0.identity_revealed, "主公身份开局公开")
	_check(p1.identity == "忠臣" and not p1.identity_revealed, "忠臣身份开局隐藏")
	_check(p2.identity == "反贼" and not p2.identity_revealed, "反贼身份开局隐藏")
	_check(p4.identity == "内奸" and not p4.identity_revealed, "内奸身份开局隐藏")
	var p1_panel = game._other_player_panels[0]
	var p1_id_label: Label = p1_panel.get_meta("identity_label")
	game._update_player_panel(p1_panel, p1)
	_check(p1_id_label.text == "【?】", "面板未公开身份显示【?】: " + p1_id_label.text)

	# ---- 用例2：阵亡管线（判定→弃牌→翻身份），反贼P2 杀 忠臣P1（无奖惩）----
	p1.hp = 1
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p1.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	p1.equipment["weapon"] = CardData.CardSubType.LIANNU
	p1.mount_plus = 1
	p1.equipment["mount_1"] = CardData.CardSubType.MOUNT_PLUS
	p1.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
	p1.determined_cards.append(CardBase.create(CardData.CardSubType.MOUNT_MINUS))
	p2.hand.clear()
	await game._deal_damage(p2, p1, 1, EffectChain.DamageType.PHYSICAL)
	_check(not p1.is_alive(), "P1 阵亡（体力 0）")
	_check(game._dead_processed.has(p1), "P1 已走完阵亡管线（防重复）")
	_check(p1.hand.is_empty(), "阵亡弃置全部手牌")
	_check(p1.equipment.is_empty(), "阵亡弃置全部装备")
	_check(p1.mount_plus == 0, "阵亡弃马计数清零: %d" % p1.mount_plus)
	_check(p1.judgment_cards.is_empty(), "阵亡弃置判定牌")
	_check(p1.determined_cards.is_empty(), "阵亡弃置已确定牌")
	_check(p1.identity_revealed, "P1 身份翻开（忠臣）")
	game._update_player_panel(p1_panel, p1)
	_check(p1_id_label.text == "【忠臣】", "P1 面板显示翻开身份【忠臣】: " + p1_id_label.text)
	_check(p2.hand_size() == 0, "杀忠臣无奖励（P2 反贼不摸牌）: %d" % p2.hand_size())
	_check(not game._game_over, "忠臣阵亡不结束游戏")

	# ---- 用例3：击杀奖惩·杀死反贼摸 3 张（P2 杀 P3）----
	game.reset_game_over_state()
	p3.hp = 1
	p2.hand.clear()
	await game._deal_damage(p2, p3, 1, EffectChain.DamageType.PHYSICAL)
	_check(not p3.is_alive(), "P3 阵亡（反贼）")
	_check(p3.identity_revealed, "P3 身份翻开（反贼）")
	_check(p2.hand_size() == 3, "击杀反贼摸 3 张: %d" % p2.hand_size())
	_check(not game._game_over, "还剩一名反贼，游戏继续")

	# ---- 用例4：击杀奖惩·主公杀忠臣 → 弃置所有手牌和装备 ----
	game.reset_game_over_state()
	p1.hp = p1.max_hp  # 复活 P1（新场景）
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	p0.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	p0.equipment["weapon"] = CardData.CardSubType.LIANNU
	p0.mount_plus = 1
	p0.equipment["mount_1"] = CardData.CardSubType.MOUNT_PLUS
	p1.hp = 1
	p1.hand.clear()
	await game._deal_damage(p0, p1, 1, EffectChain.DamageType.PHYSICAL)
	_check(not p1.is_alive(), "P1 再次阵亡（忠臣）")
	_check(p0.is_alive(), "主公存活")
	_check(p0.hand.is_empty(), "主公杀忠臣弃置所有手牌: %d" % p0.hand_size())
	_check(p0.equipment.is_empty(), "主公杀忠臣弃置所有装备")
	_check(p0.mount_plus == 0, "主公弃装备后马计数清零: %d" % p0.mount_plus)
	_check(not game._game_over, "主公存活且反贼存活，游戏继续")

	# ---- 用例5：胜负判定·反贼全灭 → 主公&忠臣胜 ----
	game.reset_game_over_state()
	p3.hp = p3.max_hp  # 复活 P3（用例3 已阵亡）
	p0.hand.clear()
	p2.hp = 1
	await game._deal_damage(p0, p2, 1, EffectChain.DamageType.PHYSICAL)
	_check(p0.hand_size() == 3, "主公杀反贼摸 3 张: %d" % p0.hand_size())
	_check(not game._game_over, "剩 P3 一名反贼，未结束")
	p3.hp = 1
	await game._deal_damage(p0, p3, 1, EffectChain.DamageType.PHYSICAL)
	_check(p0.hand_size() == 6, "主公再杀反贼再摸 3 张: %d" % p0.hand_size())
	_check(game._game_over, "反贼全灭 → 游戏结束")
	_check(game._game_over_overlay != null, "游戏结束弹窗已显示")

	# ---- 用例6：胜负判定·主公阵亡（凶手反贼）→ 反贼胜 ----
	game.reset_game_over_state()
	p2.hp = p2.max_hp  # 复活 P2（新场景）
	p0.hp = 1
	p0.hand.clear()
	await game._deal_damage(p2, p0, 1, EffectChain.DamageType.PHYSICAL)
	_check(not p0.is_alive(), "主公阵亡")
	_check(game._game_over, "主公阵亡 → 游戏结束")
	_check(game._game_over_overlay != null, "结束弹窗显示")

	# ---- 用例7：胜负判定·主公阵亡（凶手内奸）→ 内奸胜 ----
	game.reset_game_over_state()
	p0.hp = p0.max_hp
	p0.hp = 1
	await game._deal_damage(p4, p0, 1, EffectChain.DamageType.PHYSICAL)
	_check(game._game_over, "内奸杀主公 → 游戏结束")

	# ---- 用例8：胜负判定·主公阵亡（无伤害来源）→ 内奸胜 ----
	game.reset_game_over_state()
	p0.hp = p0.max_hp
	p0.hp = 1
	await game._deal_damage(null, p0, 1, EffectChain.DamageType.THUNDER)
	_check(game._game_over, "闪电式无来源杀主公 → 内奸胜（游戏结束）")

	# ---- 用例9：流失致死无击杀者（无奖惩）----
	game.reset_game_over_state()
	p0.hp = p0.max_hp
	p3.hp = 1
	p3.hand.clear()
	p0.hand.clear()
	var paid = await game._pay_yes_ah_cost(p3)
	_check(not paid, "流失致死返回 false")
	_check(not p3.is_alive(), "P3 流失阵亡")
	_check(p3.identity_revealed, "P3 身份翻开（反贼）")
	_check(p0.hand_size() == 0, "流失致死无击杀者，无奖惩: %d" % p0.hand_size())
	_check(not game._game_over, "反贼还剩 P2，游戏继续")

	# ---- 用例10：阵亡角色跳过自己的回合 ----
	game.reset_game_over_state()
	for p in game.players:
		p.hp = p.max_hp
	p1.hp = 0
	game._handle_death(p1, null)  # 直接走阵亡管线（无击杀者）
	_check(not p1.is_alive(), "P1 阵亡（跳回合前置）")
	_check(not game._game_over, "忠臣阵亡不结束游戏")
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._on_turn_ended(0)
	_check(game.turn_manager.current_player_idx == 2, "跳过阵亡的 P1，轮到 P2: %d" % game.turn_manager.current_player_idx)
	_check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "P2 停在出牌阶段")
	_check(not game._game_over, "跳回合不触发游戏结束")

	game.queue_free()
	await process_frame

	# ---- 用例11：1V1 无身份 → 阵亡不判定胜负/不翻开身份 ----
	GameManager.selected_players = 2
	GameManager.selected_general = "稻草人"
	var game2_scene = load("res://Scenes/Game.tscn")
	var game2 = game2_scene.instantiate()
	game2.auto_start = false
	root.add_child(game2)
	for i in range(6):
		await process_frame
	game2._sacrifice_override = func(): return false
	game2.start_game()
	for i in range(6):
		await process_frame
	var q0 = game2.players[0]
	q0.hp = 1
	await game2._deal_damage(game2.players[1], q0, 1, EffectChain.DamageType.PHYSICAL)
	_check(not q0.is_alive(), "1V1 玩家0 阵亡")
	_check(not game2._game_over, "1V1 无身份不判定胜负")
	_check(not q0.identity_revealed, "1V1 无身份不翻开")
	game2.queue_free()
	await process_frame
	GameManager.selected_players = 5

	# ---- 用例12：阵亡效果·【装傻】濒死拼点全胜 → 回 1 血，不触发阵亡管线 ----
	GameManager.selected_general = "安普提·斯丢皮得"
	var game3_scene = load("res://Scenes/Game.tscn")
	var game3 = game3_scene.instantiate()
	game3.auto_start = false
	root.add_child(game3)
	for i in range(6):
		await process_frame
	game3._sacrifice_override = func(): return false
	game3._nullify_override = func(): return false
	# 安普提（P0）出石头，其余出剪刀 → P0 全胜
	game3._rps_override = func(p): return game3.RPS_ROCK if p == game3.players[0] else game3.RPS_SCISSORS
	game3.start_game()
	for i in range(6):
		await process_frame
	var a0 = game3.players[0]
	a0.hp = 1
	a0.hand.clear()
	await game3._deal_damage(game3.players[1], a0, 1, EffectChain.DamageType.PHYSICAL)
	_check(a0.is_alive() and a0.hp == 1, "【装傻】拼点全胜回复至 1 血: %d/%d" % [a0.hp, a0.max_hp])
	_check(not game3._dead_processed.has(a0), "装傻救回：不触发阵亡管线")
	_check(not game3._game_over, "装傻救回：游戏继续")
	game3.queue_free()
	await process_frame
	GameManager.selected_general = "稻草人"

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)
