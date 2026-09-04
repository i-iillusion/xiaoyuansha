# test_kaiwen_order.gd — 你个壊货时序 + 拼点显示验证
# ① 你个壊货在武器技能（寒冰剑/丈八蛇矛）之后发动（寒冰剑防止伤害后，你个壊货不触发）
# ② 所有拼点结果只写实时日志（上一行），不覆盖中间提示句（当前进行）；拳名显示正确
extends SceneTree

var failures := 0
var asserts := 0
var game = null
var _klogs: Array[String] = []
var _zlog := ""

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
	var target = game.players[1]

	# 通用钩子：你个壊货必发动 / 不打舍己为人 / 凯文必赢（石头 vs 剪刀）
	game._kaiwen_override = func(): return true
	game._sacrifice_override = func(): return false
	game._rps_override = func(p):
		if p == kaiwen:
			return 0
		return 2
	kaiwen.hp = kaiwen.max_hp
	target.hp = target.max_hp

	# ========== ① 寒冰剑：防止伤害 → 你个壊货不触发 ==========
	kaiwen.equipment["weapon"] = CardData.CardSubType.ICE_SWORD
	game._ice_sword_override = func(): return true  # 发动寒冰剑防止伤害
	kaiwen.hand.clear()
	target.hand.clear()
	for i in range(2):
		target.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	var hp_before = target.hp
	await game._execute_single_strike(kaiwen, target, CardBase.create(CardData.CardSubType.STRIKE), CardData.CardSubType.STRIKE, EffectChain.DamageType.PHYSICAL, 1)
	_check(kaiwen.hand_size() == 0, "寒冰剑防止伤害后你个壊货不触发: %d" % kaiwen.hand_size())
	_check(target.hp == hp_before, "寒冰剑防止后目标体力恢复: %d" % target.hp)
	_check(target.hand_size() == 0, "寒冰剑弃两张: %d" % target.hand_size())
	kaiwen.remove_equipment("weapon")

	# ========== ② 丈八蛇矛：你个壊货在丈八结算（流失+额外伤害）之后才询问 ==========
	kaiwen.equipment["weapon"] = CardData.CardSubType.ZHANGBA_SPEAR
	_klogs.clear()
	_zlog = ""
	game._zhangba_override = func():
		_zlog = game._log_label.text  # 丈八询问时：应只有伤害日志，你个壊货拼点尚未发生
		return 1                      # 流失 1 点体力追加伤害
	game._kaiwen_override = func():
		_klogs.append(game._log_label.text)  # 你个壊货每次询问时记录当时的日志（数组引用捕获）
		return true
	kaiwen.hp = kaiwen.max_hp
	target.hp = target.max_hp
	kaiwen.hand.clear()
	target.hand.clear()  # 无手牌 → 不出闪
	await game._execute_single_strike(kaiwen, target, CardBase.create(CardData.CardSubType.STRIKE), CardData.CardSubType.STRIKE, EffectChain.DamageType.PHYSICAL, 1)
	# 结算：基础 1 点 + 丈八额外 1 点；你个壊货按点触发（基础 1 点 + 额外 1 点 = 共 4 张）
	_check(kaiwen.hand_size() == 4, "丈八+你个壊货：基础+额外各拼点一次摸 4 张: %d" % kaiwen.hand_size())
	_check(target.hp == target.max_hp - 2, "目标共受 2 点伤害: %d" % target.hp)
	_check(kaiwen.hp == kaiwen.max_hp - 1, "凯文流失 1 点体力: %d" % kaiwen.hp)
	_check(_zlog.contains("造成"), "丈八询问时已有伤害日志: " + _zlog)
	_check(not _zlog.contains("拼点"), "丈八询问时你个壊货拼点尚未发生: " + _zlog)
	_check(_klogs.size() == 2, "你个壊货共询问 2 次（额外+基础）: %d" % _klogs.size())
	if _klogs.size() == 2:
		_check(_klogs[0].contains("额外受到"), "你个壊货（额外）在丈八额外伤害之后询问: " + _klogs[0])
		_check(_klogs[1].contains("拼点"), "你个壊货（基础）在额外拼点结果之后询问（丈八已全部结算）: " + _klogs[1])
	kaiwen.remove_equipment("weapon")

	# ========== ③ 所有拼点结果：只写实时日志（上一行），不覆盖中间提示句 ==========
	game._kaiwen_override = func(): return true
	# 默认拼点（所有拼点统一行为：只写实时日志）
	game._refresh_status_line()
	var r = await game._do_ping_dian_once(kaiwen, target)
	_check(r == game.RPS_WIN, "普通拼点结果: %d" % r)
	_check(game._log_label.text.contains("拼点"), "实时日志含拼点结果: " + game._log_label.text)
	_check(not game._debug_label.text.contains("拼点"), "提示句不含拼点结果: " + game._debug_label.text)
	_check(game._log_label.text.contains("剪刀"), "拼点结果正确显示拳名（剪刀/布不颠倒）: " + game._log_label.text)
	# 你个壊货路径：同样只写实时日志
	kaiwen.hp = kaiwen.max_hp
	target.hp = target.max_hp
	kaiwen.hand.clear()
	game._refresh_status_line()
	await game._deal_damage(target, kaiwen, 1, EffectChain.DamageType.PHYSICAL)
	_check(kaiwen.hand_size() == 2, "你个壊货仍正常拼点摸牌: %d" % kaiwen.hand_size())
	_check(not game._debug_label.text.contains("拼点"), "你个壊货拼点后提示句不含拼点结果: " + game._debug_label.text)
	_check(game._log_label.text.contains("拼点"), "你个壊货拼点结果在实时日志: " + game._log_label.text)

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
