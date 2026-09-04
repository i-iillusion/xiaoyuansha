# test_general.gd — 武将系统（稻草人默认武将）冒烟测试
extends SceneTree

var failures := 0
var asserts := 0

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	# ---- 用例 1：GeneralData 稻草人数据 ----
	_check(GeneralData.is_valid("稻草人"), "稻草人武将存在")
	_check(GeneralData.get_max_hp("稻草人") == 5, "稻草人 5 血: %d" % GeneralData.get_max_hp("稻草人"))
	_check(GeneralData.get_avatar("稻草人") == "🦊", "稻草人头像🦊")
	_check(GeneralData.get_skills("稻草人").is_empty(), "稻草人无技能")

	# ---- 用例 2：进入对局默认武将 = 稻草人（全员 5 血）----
	var game_scene = load("res://Scenes/Game.tscn")

	# ===== 场景 1：默认 selected_general（凯文·罗本）=====
	GameManager.selected_general = "凯文·罗本"
	var game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	_check(game.players[0].general_name == "凯文·罗本", "默认 selected_general 下玩家是凯文·罗本: " + game.players[0].general_name)
	_check(game.players[0].max_hp == 4, "凯文·罗本 4 血: %d" % game.players[0].max_hp)
	var all_scarecrow = true
	var all_5hp = true
	for i in range(1, game.players.size()):
		if game.players[i].general_name != "稻草人":
			all_scarecrow = false
		if game.players[i].max_hp != 5:
			all_5hp = false
	_check(all_scarecrow, "AI 默认稻草人")
	_check(all_5hp, "AI 体力上限 5")

	# 面板名字：同时显示玩家名和武将名（玩家 1 = 凯文·罗本）
	var self_panel = game._self_info_panel
	var panel_name: Label = self_panel.get_meta("name_label")
	_check(panel_name.text.contains("玩家 1") and panel_name.text.contains("凯文·罗本"), "面板同时显示玩家名/武将名: " + panel_name.text)

	# 详情弹窗：稻草人（players[1]）武将名 + 技能区
	var popup = PlayerDetailPopup.create(root, game.players[1])
	await process_frame
	await process_frame
	var general_label = popup.get_node("Panel/Content/AvatarSection/AvatarInfo/GeneralLabel")
	_check(general_label.text.contains("稻草人"), "详情弹窗武将名=稻草人: " + general_label.text)
	var name_label = popup.get_node("Panel/Content/AvatarSection/AvatarInfo/NameLabel")
	_check(name_label.text.contains("玩家 2"), "详情弹窗玩家名: " + name_label.text)
	_check(general_label.get_theme_font_size("font_size") == name_label.get_theme_font_size("font_size"), "武将名与玩家名字号一致: %d vs %d" % [general_label.get_theme_font_size("font_size"), name_label.get_theme_font_size("font_size")])
	var skills_text = _collect_text(popup.get_node("Panel/Content/SkillsSection/SkillsList"))
	_check(skills_text.contains("稻草人 没有技能"), "技能区显示稻草人没有技能: " + skills_text)
	popup.queue_free()
	await process_frame

	# 详情弹窗：凯文·罗本（players[0]）技能区显示技能
	var popup2 = PlayerDetailPopup.create(root, game.players[0])
	await process_frame
	await process_frame
	var skills_text2 = _collect_text(popup2.get_node("Panel/Content/SkillsSection/SkillsList"))
	_check(skills_text2.contains("裸奔") and skills_text2.contains("你个壊货"), "凯文技能区显示技能: " + skills_text2)
	popup2.queue_free()
	await process_frame

	game.queue_free()
	await process_frame

	# ===== 场景 2：selected_general = 稻草人（主菜单选择影响对局）====
	GameManager.selected_general = "稻草人"
	var game2 = game_scene.instantiate()
	root.add_child(game2)
	for i in range(8):
		await process_frame
	_check(game2.players[0].general_name == "稻草人", "selected_general=稻草人时玩家是稻草人: " + game2.players[0].general_name)
	_check(game2.players[0].max_hp == 5, "稻草人玩家 5 血: %d" % game2.players[0].max_hp)
	game2.queue_free()
	await process_frame
	# 恢复默认（后续测试依赖）
	GameManager.selected_general = "凯文·罗本"

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _collect_text(node: Node) -> String:
	var parts: Array[String] = []
	_collect(node, parts)
	return "\n".join(parts)

func _collect(node: Node, parts: Array[String]):
	if node is Label and not node.is_queued_for_deletion():
		parts.append(node.text)
	for c in node.get_children():
		_collect(c, parts)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
