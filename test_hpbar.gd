# test_hpbar.gd �?伤害后体力条/数字实时变化
extends SceneTree

var failures := 0
var asserts := 0
var game = null

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 5
	GameManager.selected_general = "凯文·罗本"
	game = load("res://Scenes/Game.tscn").instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	game._sacrifice_override = func(): return false

	# ---- 用例 1：统一伤害入口（无技能延迟路径）后血条立即变�?----
	var p2 = game.players[2]
	var panel2 = game._other_player_panels[1]
	var bar2: ColorRect = panel2.get_meta("hp_bar")
	var label2: Label = panel2.get_meta("hp_label")
	var size_before = bar2.size.x
	_check(size_before > 100, "满血血条宽: %.1f" % size_before)
	await game._deal_damage(game.players[1], p2, 1, EffectChain.DamageType.PHYSICAL)
	_check(bar2.size.x < size_before - 5, "受伤后血条立即缩�? %.1f -> %.1f" % [size_before, bar2.size.x])
	_check(label2.text.contains("4/5"), "体力数字更新: " + label2.text)

	# ---- 用例 2：凯文受伤害（询问弹窗有 0.8s 延迟）期间血条已更新 ----
	var kaiwen = game.players[0]
	var kaiwen_panel = game._self_info_panel
	var kaiwen_bar: ColorRect = kaiwen_panel.get_meta("hp_bar")
	var kaiwen_label: Label = kaiwen_panel.get_meta("hp_label")
	kaiwen.hp = kaiwen.max_hp
	game._kaiwen_override = func(): return false  # 不发动（�?0.8s 延迟仍存在）
	await game._deal_damage(game.players[1], kaiwen, 1, EffectChain.DamageType.PHYSICAL)
	_check(kaiwen_label.text.contains("3/4"), "凯文受伤害体力数字更�? " + kaiwen_label.text)

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
