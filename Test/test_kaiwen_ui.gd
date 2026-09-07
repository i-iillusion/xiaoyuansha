# test_kaiwen_ui.gd — 你个壊货真实 UI 流程（弹窗 → 猜拳 → 结果）
extends SceneTree

var failures := 0
var asserts := 0
var game = null

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	game = load("res://Scenes/Game.tscn").instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	var kaiwen = game.players[0]
	var p1 = game.players[1]
	game._sacrifice_override = func(): return false
	# 不设 _kaiwen_override / _rps_override → 走真实弹窗与猜拳 UI

	kaiwen.hand.clear()
	_start_damage(p1, kaiwen)
	# 伤害展示 0.8s 延迟后才弹询问窗
	await create_timer(1.2).timeout
	await process_frame

	# 技能询问弹窗
	var ask_btn = _find_btn("发动拼点")
	_check(ask_btn != null, "技能询问弹窗出现（发动拼点按钮）")
	if ask_btn:
		ask_btn.pressed.emit()

	await process_frame
	await process_frame
	await process_frame

	# 猜拳弹窗
	var rps_btn = _find_btn("石头")
	_check(rps_btn != null, "猜拳弹窗出现（石头按钮）")
	if rps_btn:
		rps_btn.pressed.emit()

	# 等待伤害流程结束（AI 随机出拳，凯文赢概率 1/3 → 摸 2 张）
	await create_timer(1.0).timeout
	_check(kaiwen.hand_size() <= 2, "拼点流程走完，手牌 %d（0=输 2=赢）" % kaiwen.hand_size())
	# 拼点结果走实时日志（5 秒小字），不再有大字提示
	_check(game._log_label.text.contains("拼点"), "拼点结果在实时日志: " + game._log_label.text)

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _start_damage(attacker, target):
	await game._deal_damage(attacker, target, 1, EffectChain.DamageType.PHYSICAL)

func _all_btn_texts() -> Array:
	var arr: Array = []
	for c in game.get_node("UI").get_children():
		_collect_btns(c, arr)
	return arr

func _collect_btns(node: Node, arr: Array):
	if node is Button and not node.is_queued_for_deletion():
		arr.append(node.text)
	for c in node.get_children():
		_collect_btns(c, arr)

func _find_btn(text: String) -> Button:
	for c in game.get_node("UI").get_children():
		var b = _find_btn_rec(c, text)
		if b:
			return b
	return null

func _find_btn_rec(node: Node, text: String) -> Button:
	if node is Button and not node.is_queued_for_deletion() and node.text == text:
		return node
	for c in node.get_children():
		var r = _find_btn_rec(c, text)
		if r:
			return r
	return null

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
