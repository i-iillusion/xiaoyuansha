# test_random_game.gd — 随机身份 + 随机武将 冒烟测试
# 身份洗牌随机分配（主公按身份查找，不固定座位 0）；所有玩家随机武将
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

func _find_by_identity(id: String) -> Player:
	for p in game.players:
		if p.identity == id:
			return p
	return null

func _find_all_by_identity(id: String) -> Array:
	var arr: Array = []
	for p in game.players:
		if p.identity == id:
			arr.append(p)
	return arr

func _run() -> void:
	GameManager.random_identity = true
	GameManager.random_general = true
	GameManager.selected_players = 5
	GameManager.selected_general = "稻草人"
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	game.auto_start = false
	root.add_child(game)
	for i in range(6):
		await process_frame
	# 通用钩子：全部不弹窗（随机武将下 P0 可能是任意技能持有者）
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._meiyong_override = func(): return false
	game._kaiwen_override = func(): return false
	game._paixiong_override = func(): return false
	game._yes_ah_override = func(): return "card"
	game._sao_reveal_override = func(): return false
	game._sao_type_override = func(): return "weapon"
	game._awaken_pick_override = func(): return 1
	game._dying_peach_override = func(): return false
	game._rps_override = func(p): return game.RPS_ROCK  # 全员石头 → 拼点全平
	game.start_game()
	for i in range(6):
		await process_frame

	# ---- 用例1：身份随机分配正确（1主/1忠/2反/1内，主公公开其余隐藏）----
	var lord = _find_by_identity("主公")
	var loyal = _find_by_identity("忠臣")
	var rebels = _find_all_by_identity("反贼")
	var traitor = _find_by_identity("内奸")
	_check(lord != null and loyal != null and rebels.size() == 2 and traitor != null, "身份分布 1主/1忠/2反/1内")
	_check(lord.identity_revealed, "主公身份公开")
	_check(not loyal.identity_revealed and not traitor.identity_revealed and not rebels[0].identity_revealed, "其余身份隐藏")

	# ---- 用例2：随机武将（全员来自已实现武将池，且不含稻草人占位）----
	var valid_pool = ["凯文·罗本", "布鲁斯·萨维奇", "安普提·斯丢皮得", "史蒂芬·彼特先斯", "杰基·斯特朗", "麦克斯·欧尼斯特", "比尔·盖伊"]
	var all_ok = true
	for p in game.players:
		if not valid_pool.has(p.general_name):
			all_ok = false
			print("  非法武将: ", p.player_name, " = ", p.general_name)
	_check(all_ok, "所有玩家武将来自已实现池")
	_check(GeneralData.get_max_hp(lord.general_name) > 0, "主公武将体力上限有效")

	# ---- 用例3：反贼全灭 → 主公&忠臣胜（主公按身份击杀两名反贼，每次摸 3）----
	lord.hand.clear()
	for r in rebels:
		r.hp = 1
		r.hand.clear()
	await game._deal_damage(lord, rebels[0], 1, EffectChain.DamageType.PHYSICAL)
	_check(not rebels[0].is_alive(), "反贼1 阵亡")
	_check(rebels[0].identity_revealed, "反贼1 身份翻开")
	_check(lord.hand_size() == 3, "主公击杀反贼摸 3 张: %d" % lord.hand_size())
	_check(not game._game_over, "还剩一名反贼，游戏继续")
	await game._deal_damage(lord, rebels[1], 1, EffectChain.DamageType.PHYSICAL)
	_check(lord.hand_size() == 6, "主公再杀反贼再摸 3 张: %d" % lord.hand_size())
	_check(game._game_over, "反贼全灭 → 游戏结束")
	_check(game._game_over_overlay != null, "结束弹窗显示")

	# ---- 用例4：主公阵亡（凶手反贼）→ 反贼胜 ----
	game.reset_game_over_state()
	var killer = rebels[0]
	killer.hp = killer.max_hp  # 复活凶手
	lord.hp = 1
	lord.hand.clear()
	await game._deal_damage(killer, lord, 1, EffectChain.DamageType.PHYSICAL)
	_check(not lord.is_alive(), "主公阵亡（按身份找到的主公）")
	_check(game._game_over, "主公阵亡 → 游戏结束（反贼胜）")

	# ---- 用例5：主公阵亡（无伤害来源）→ 内奸胜 ----
	game.reset_game_over_state()
	lord.hp = lord.max_hp
	lord.hp = 1
	await game._deal_damage(null, lord, 1, EffectChain.DamageType.THUNDER)
	_check(game._game_over, "无来源杀主公 → 内奸胜（游戏结束）")

	# ---- 用例6：主公杀忠臣 → 弃置所有手牌和装备（随机主公可能是 AI）----
	game.reset_game_over_state()
	lord.hp = lord.max_hp
	loyal.hp = 1
	loyal.hand.clear()
	lord.hand.clear()
	lord.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	lord.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	lord.equipment["weapon"] = CardData.CardSubType.LIANNU
	lord.mount_plus = 1
	lord.equipment["mount_1"] = CardData.CardSubType.MOUNT_PLUS
	await game._deal_damage(lord, loyal, 1, EffectChain.DamageType.PHYSICAL)
	_check(not loyal.is_alive(), "忠臣阵亡")
	_check(lord.is_alive(), "主公存活")
	_check(lord.hand.is_empty(), "主公杀忠臣弃置所有手牌: %d" % lord.hand_size())
	_check(lord.equipment.is_empty(), "主公杀忠臣弃置所有装备")
	_check(not game._game_over, "主公存活且反贼存活，游戏继续")

	# ---- 用例7：AI 回合流转（随机武将不弹窗、不崩溃）----
	game.reset_game_over_state()
	for p in game.players:
		p.hp = p.max_hp
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for i in range(5):
		game._on_turn_ended(0)
		var expected = (i + 1) % 5
		_check(game.turn_manager.current_player_idx == expected, "回合流转轮到 P%d（实际 P%d）" % [expected, game.turn_manager.current_player_idx])
	_check(game.turn_manager.current_phase == TurnManager.Phase.PLAY, "回合停在出牌阶段")
	_check(not game._game_over, "回合流转不触发游戏结束")

	# ---- 用例8：P0 击杀反贼摸 3（P0 可能是任意身份/武将）----
	game.reset_game_over_state()
	for p in game.players:
		p.hp = p.max_hp
	var victim: Player = null
	for r in _find_all_by_identity("反贼"):
		if r != game.players[0]:
			victim = r
			break
	if victim != null:
		victim.hp = 1
		victim.hand.clear()
		game.players[0].hand.clear()
		await game._deal_damage(game.players[0], victim, 1, EffectChain.DamageType.PHYSICAL)
		_check(not victim.is_alive(), "P0 击杀反贼")
		_check(game.players[0].hand_size() == 3, "P0 击杀反贼摸 3 张: %d" % game.players[0].hand_size())
		_check(victim.identity_revealed, "反贼身份翻开")
	else:
		_check(false, "找不到可被 P0 击杀的反贼")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)
