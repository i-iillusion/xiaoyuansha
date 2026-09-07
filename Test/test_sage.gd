# test_sage.gd — 贤者的加护：顺手牵羊标记转移冒烟测试
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

	game._equip_pick_override = func(): return "armor"

	# ---- 用例 1：顺手牵羊转移贤者标记 ----
	var p0 = game.players[0]
	var p1 = game.players[1]
	p1.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	p1.sage_tokens = 2
	p1.sage_activated = false
	p0.determined_cards.clear()
	p0.sage_tokens = 0
	p0.sage_activated = false
	await game._steal_equip(p0, p1, true, "顺手牵羊")
	_check(p1.sage_tokens == 0 and not p1.sage_activated, "原持有者标记清空")
	_check(p0.sage_tokens == 2, "新持有者获得标记: %d" % p0.sage_tokens)
	var has_sage = false
	for c in p0.determined_cards:
		if c.sub_type == CardData.CardSubType.SAGE_PROTECTION:
			has_sage = true
	_check(has_sage, "贤者的加护进入已确定牌区")

	# ---- 用例 2：激活状态也一并转移 ----
	var p2 = game.players[2]
	p2.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	p2.sage_tokens = 0
	p2.sage_activated = true
	p0.sage_tokens = 0
	p0.sage_activated = false
	await game._steal_equip(p0, p2, true, "顺手牵羊")
	_check(p2.sage_tokens == 0 and not p2.sage_activated, "原持有者已激活清空")
	_check(p0.sage_activated, "激活状态一并转移")

	# ---- 用例 3：过河拆桥不转移（标记直接消失） ----
	var p3 = game.players[3]
	p3.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	p3.sage_tokens = 1
	p3.sage_activated = false
	var p0_before = p0.sage_tokens
	await game._steal_equip(p0, p3, false, "过河拆桥")
	_check(p3.sage_tokens == 0 and not p3.sage_activated, "被拆标记清空")
	_check(p0.sage_tokens == p0_before, "拆不转移给拆者")

	# ---- 用例 4：防具替换（灾厄袍等）时标记清空不转移 ----
	# 直接调 remove_equipment（替换分支等价）
	var p4 = game.players[4]
	p4.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	p4.sage_tokens = 2
	p4.sage_activated = true
	p4.remove_equipment("armor")
	_check(p4.sage_tokens == 0 and not p4.sage_activated, "卸甲清空标记")
	_check(not p4.equipment.has("armor"), "卸甲移除装备")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
