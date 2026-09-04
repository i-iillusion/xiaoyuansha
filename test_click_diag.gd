# test_click_diag.gd — 验证点击修复（容器 mouse_filter=IGNORE 不拦截点击，面板居中）
extends SceneTree

var failures := 0
var asserts := 0
var game = null
var target_confirmed := false

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 2
	GameManager.selected_general = "凯文·罗本"
	game = load("res://Scenes/Game.tscn").instantiate()
	root.add_child(game)
	for i in range(5):
		await process_frame

	# ---- 用例 1：位置容器 mouse_filter = IGNORE（空容器不拦点击）----
	_check(game._pos_left.mouse_filter == Control.MOUSE_FILTER_IGNORE, "PlayerPosLeft IGNORE")
	_check(game._pos_top_left.mouse_filter == Control.MOUSE_FILTER_IGNORE, "PlayerPosTopLeft IGNORE")
	_check(game._pos_top_right.mouse_filter == Control.MOUSE_FILTER_IGNORE, "PlayerPosTopRight IGNORE")
	_check(game._pos_right.mouse_filter == Control.MOUSE_FILTER_IGNORE, "PlayerPosRight IGNORE")
	_check(game._pos_top.mouse_filter == Control.MOUSE_FILTER_IGNORE, "PlayerPosTop IGNORE")

	# ---- 用例 2：1V1 对方面板在容器内居中（锚点 0.5 + 偏移）----
	var panel = game._other_player_panels[0]
	_check(panel.anchor_left == 0.5 and panel.anchor_right == 0.5, "面板水平锚点居中")
	_check(panel.offset_left == -100 and panel.offset_right == 100, "面板水平偏移居中")
	_check(panel.offset_top == -50 and panel.offset_bottom == 50, "面板垂直偏移居中")

	# ---- 用例 3：模拟点击面板（emit）仍正常 ----
	game._enter_targeting_mode(CardData.CardSubType.STRIKE)
	target_confirmed = false
	game._target_confirm_override = func():
		target_confirmed = true
		return true
	var ev = InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	panel.gui_input.emit(ev)
	await process_frame
	_check(target_confirmed, "点击 AI 面板触发目标确认")

	# ---- 用例 4：5人局面板也居中 ----
	GameManager.selected_players = 5
	game.queue_free()
	await process_frame
	game = load("res://Scenes/Game.tscn").instantiate()
	root.add_child(game)
	for i in range(5):
		await process_frame
	_check(game._other_player_panels.size() == 4, "5人局 4 个面板")
	for p in game._other_player_panels:
		_check(p.anchor_left == 0.5, "5人局面板水平居中: " + p.get_parent().name)
	game.queue_free()
	await process_frame
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
