# test_kaiwen.gd — 凯文·罗本技能冒烟测试（裸奔 / 你个壊货）
extends SceneTree

var failures := 0
var asserts := 0
var game = null

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	var kaiwen = game.players[0]
	var p1 = game.players[1]
	var p2 = game.players[2]

	# 猜拳钩子：凯文恒出石头(0)，对手恒出剪刀(2) → 凯文必赢
	game._rps_override = func(p):
		if p == kaiwen:
			return 0
		return 2

	# ---- 用例 1：武将数据 ----
	_check(GeneralData.is_valid("凯文·罗本"), "凯文·罗本武将存在")
	_check(GeneralData.get_max_hp("凯文·罗本") == 4, "凯文·罗本 4 血")
	_check(GeneralData.get_skills("凯文·罗本").size() == 2, "两个技能: %d" % GeneralData.get_skills("凯文·罗本").size())

	# ---- 用例 2：【裸奔】无装备时不能成为杀目标 ----
	_check(game._is_bare_running(kaiwen), "凯文开局无装备，裸奔生效")
	_check(game._get_strike_targets(p1).has(kaiwen) == false, "杀目标列表不含裸奔凯文")
	# 有装备后裸奔失效
	kaiwen.equipment["weapon"] = CardData.CardSubType.LIANNU
	_check(not game._is_bare_running(kaiwen), "装备武器后裸奔失效")
	_check(game._get_strike_targets(p1).has(kaiwen), "有装备后可被选为杀目标")
	# 拆光装备裸奔恢复
	kaiwen.remove_equipment("weapon")
	_check(game._is_bare_running(kaiwen), "装备卸下后裸奔恢复")
	# 非凯文武将无裸奔
	_check(not game._is_bare_running(p1), "稻草人没有裸奔")

	# ---- 用例 3：【你个壊货】受到伤害拼点赢摸两张 ----
	kaiwen.hand.clear()
	game._kaiwen_override = func(): return true
	game._sacrifice_override = func(): return false
	await game._deal_damage(p1, kaiwen, 1, EffectChain.DamageType.PHYSICAL)
	_check(kaiwen.hand_size() == 2, "受到伤害拼点赢摸两张: %d" % kaiwen.hand_size())

	# ---- 用例 4：拼点输不摸牌 ----
	# 凯文出剪刀(2) 输给石头(0)：临时改钩子
	game._rps_override = func(p):
		if p == kaiwen:
			return 2
		return 0
	kaiwen.hand.clear()
	await game._deal_damage(p1, kaiwen, 1, EffectChain.DamageType.PHYSICAL)
	_check(kaiwen.hand_size() == 0, "拼点输不摸牌: %d" % kaiwen.hand_size())
	# 恢复凯文必赢
	game._rps_override = func(p):
		if p == kaiwen:
			return 0
		return 2

	# ---- 用例 5：不发动不拼点 ----
	game._kaiwen_override = func(): return false
	kaiwen.hand.clear()
	await game._deal_damage(p1, kaiwen, 1, EffectChain.DamageType.PHYSICAL)
	_check(kaiwen.hand_size() == 0, "不发动不摸牌: %d" % kaiwen.hand_size())

	# ---- 用例 6：造成伤害拼点赢摸两张 ----
	game._kaiwen_override = func(): return true
	kaiwen.hand.clear()
	var p1_hp_before = p1.hp
	await game._deal_damage(kaiwen, p1, 1, EffectChain.DamageType.PHYSICAL)
	_check(kaiwen.hand_size() == 2, "造成伤害拼点赢摸两张: %d" % kaiwen.hand_size())
	_check(p1.hp == p1_hp_before - 1, "目标受伤: %d -> %d" % [p1_hp_before, p1.hp])

	# ---- 用例 7：按点数逐点触发（2 点 = 拼 2 次赢摸 4 张）----
	kaiwen.hp = kaiwen.max_hp  # 回血（前面用例已消耗体力）
	kaiwen.hand.clear()
	await game._deal_damage(p1, kaiwen, 2, EffectChain.DamageType.PHYSICAL)
	_check(kaiwen.hand_size() == 4, "2 点伤害拼点 2 次摸 4 张: %d" % kaiwen.hand_size())

	# ---- 用例 8：无来源伤害（闪电）不触发 ----
	kaiwen.hand.clear()
	await game._deal_damage(null, kaiwen, 1, EffectChain.DamageType.THUNDER)
	_check(kaiwen.hand_size() == 0, "无来源伤害不触发: %d" % kaiwen.hand_size())

	# ---- 用例 9：非凯文武将不触发 ----
	game._kaiwen_override = func(): return true
	p1.hand.clear()
	await game._deal_damage(kaiwen, p1, 1, EffectChain.DamageType.PHYSICAL)
	_check(p1.hand_size() == 0, "稻草人受伤不触发你个壊货: %d" % p1.hand_size())

	# ---- 用例 10：铁索传导触发「受到伤害」拼点 ----
	# 凯文连环，p1 连环，p2 用火伤打 p1 → 传导给凯文；凯文受到传导伤害触发拼点（对手 = 来源 p2）
	kaiwen.hp = kaiwen.max_hp  # 复活/回血
	p1.hp = p1.max_hp
	p1.chained = true
	kaiwen.chained = true
	kaiwen.hand.clear()
	await game._deal_damage(p2, p1, 1, EffectChain.DamageType.FIRE)
	_check(kaiwen.hand_size() >= 2, "传导伤害触发拼点摸牌: %d" % kaiwen.hand_size())
	# 清理连环
	p1.chained = false
	kaiwen.chained = false

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
