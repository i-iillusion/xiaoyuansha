# test_1v1.gd — 1V1 模式冒烟测试（2 人 / 无身份 / 对方稻草人）
extends SceneTree

var failures := 0
var asserts := 0

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	# ---- 用例 1：selected_players=2 时加载对局 ----
	GameManager.selected_players = 2
	GameManager.selected_general = "凯文·罗本"
	var game_scene = load("res://Scenes/Game.tscn")
	var game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	_check(game.players.size() == 2, "1V1 只有 2 名玩家: %d" % game.players.size())
	_check(game.turn_manager.player_count == 2, "TurnManager 2 人")
	_check(game.players[0].general_name == "凯文·罗本", "玩家0 = 凯文·罗本（所选武将）")
	_check(game.players[1].general_name == "稻草人", "对方 = 稻草人: " + game.players[1].general_name)
	_check(game.players[1].max_hp == 5, "对方稻草人 5 血")
	# 无身份
	_check(game.players[0].identity == "" and game.players[1].identity == "", "双方无身份")
	_check(game._other_player_panels.size() == 1, "其他玩家面板只有 1 个: %d" % game._other_player_panels.size())
	# 面板身份标签为空
	var p1_panel = game._other_player_panels[0]
	var p1_identity: Label = p1_panel.get_meta("identity_label")
	_check(p1_identity.text == "", "对方面板不显示身份: '" + p1_identity.text + "'")
	# 对方在正上方（玩家对面）
	_check(p1_panel.get_parent().name == "PlayerPosTop", "1V1 对方面板在正上方: " + p1_panel.get_parent().name)

	# 详情弹窗显示「身份：无」
	var popup = PlayerDetailPopup.create(root, game.players[0])
	await process_frame
	await process_frame
	var identity_label = popup.get_node("Panel/Content/AvatarSection/AvatarInfo/IdentityLabel")
	_check(identity_label.text.contains("无"), "详情弹窗身份显示无: " + identity_label.text)
	popup.queue_free()
	await process_frame

	# 距离：2 人互距 1
	_check(game.players[0].attack_distance_to(game.players[1]) == 1, "2 人互距 1: %d" % game.players[0].attack_distance_to(game.players[1]))

	game.queue_free()
	await process_frame
	# 恢复默认（后续测试依赖）
	GameManager.selected_players = 5

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
