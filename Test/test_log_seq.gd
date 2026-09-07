# test_log_seq.gd �?凯文技能时序诊断：伤害先展示→延迟→询问→拼点→提示句结果
extends SceneTree

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
	# 凯文必赢：石�?vs 剪刀
	game._rps_override = func(p):
		if p == kaiwen:
			return 0
		return 2
	game._kaiwen_override = Callable()  # 走真实弹�?	kaiwen.hp = kaiwen.max_hp
	kaiwen.hand.clear()

	print("LOGSEQ: 伤害前体�?", kaiwen.hp)
	_start_damage(p1, kaiwen)
	# 伤害�?0.3s（延�?0.8s 还没到）：应显示「受到伤害」日�?+ 体力已扣，且询问弹窗未出�?	await create_timer(0.4).timeout
	print("LOGSEQ: 0.4s 日志: ", game._log_label.text)
	print("LOGSEQ: 0.4s 体力=", kaiwen.hp, " 询问弹窗=", _find_btn("发动拼点") != null)
	# 1.2s（延迟过了）：询问弹窗出现，提示句仍为阶段提�?	await create_timer(0.8).timeout
	print("LOGSEQ: 1.2s 询问弹窗=", _find_btn("发动拼点") != null, " 提示�?", game._debug_label.text)
	# 点发�?�?猜拳 �?出拳
	var ask_btn = _find_btn("发动拼点")
	if ask_btn:
		ask_btn.pressed.emit()
	await process_frame
	await process_frame
	var rps = _find_btn("石头")
	print("LOGSEQ: 猜拳弹窗=", rps != null)
	if rps:
		rps.pressed.emit()
	await create_timer(0.5).timeout
	print("LOGSEQ: 拼点后提示句=", game._debug_label.text, "（应为拼点结果）")
	print("LOGSEQ: 拼点后日�?", game._log_label.text)
	# 1.5s 后提示句恢复
	await create_timer(1.5).timeout
	print("LOGSEQ: 恢复后提示句=", game._debug_label.text)
	quit()

func _start_damage(attacker, target):
	await game._deal_damage(attacker, target, 1, EffectChain.DamageType.PHYSICAL)

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
