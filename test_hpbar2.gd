# test_hpbar2.gd — 杀路径（EffectChain）伤害后血条立即变化（不等拼点延迟）
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

	var kaiwen = game.players[0]
	var ai = game.players[1]
	game._kaiwen_override = func(): return false  # 不发动（0.8s 延迟仍存在）
	game._sacrifice_override = func(): return false
	ai.hp = ai.max_hp

	var ai_panel = game._other_player_panels[0]
	var ai_bar: ColorRect = ai_panel.get_meta("hp_bar")
	var ai_label: Label = ai_panel.get_meta("hp_label")
	_check(ai_bar.size.x > 115, "满血血量: %.1f" % ai_bar.size.x)

	# 构造杀伤害链（凯文出杀打 AI，AI 不出闪）
	var chain = EffectChain.new(kaiwen, ai, CardBase.create(CardData.CardSubType.STRIKE), EffectChain.EffectType.DAMAGE, 1)
	chain.trigger_callback = game._on_chain_trigger
	chain.response_callback = func(c, responder, expected, attacker): return false
	_start_chain(chain)
	# 0.3s：伤害已施加（damage_applied 事件同步 UI），凯文拼点询问在 0.8s 延迟后
	await create_timer(0.3).timeout
	_check(ai_bar.size.x < 115, "杀伤害后血条立即缩短（0.3s 时）: %.1f" % ai_bar.size.x)
	_check(ai_label.text.contains("4/5"), "杀伤害后体力数字更新: " + ai_label.text)
	# 等链完成
	await create_timer(2.0).timeout

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _start_chain(chain):
	await chain.start()

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
