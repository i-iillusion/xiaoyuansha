# test_pingdian_color.gd — 拼点结果日志颜色（赢绿/平灰/输红）
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

	var p0 = game.players[0]
	var p1 = game.players[1]

	# ---- 用例 1：赢 → 绿色 ----
	game._rps_override = func(p):
		return 0 if p == p0 else 2  # 石头 vs 剪刀 → p0 赢
	await game._do_ping_dian_once(p0, p1)
	_check(_is_green(game._log_label.get_theme_color("font_color")), "赢显示绿色: " + str(game._log_label.get_theme_color("font_color")))

	# ---- 用例 2：输 → 红色 ----
	game._rps_override = func(p):
		return 2 if p == p0 else 0  # 剪刀 vs 石头 → p0 输
	await game._do_ping_dian_once(p0, p1)
	_check(_is_red(game._log_label.get_theme_color("font_color")), "输显示红色: " + str(game._log_label.get_theme_color("font_color")))

	# ---- 用例 3：平局 → 灰色 ----
	game._rps_override = func(p):
		return 0  # 都出石头 → 平
	await game._do_ping_dian_once(p0, p1)
	_check(_is_gray(game._log_label.get_theme_color("font_color")), "平局显示灰色: " + str(game._log_label.get_theme_color("font_color")))

	# ---- 用例 4：普通日志恢复默认色 ----
	game._update_debug("普通消息")
	var default_c = game._log_label.get_theme_color("font_color")
	_check(not _is_green(default_c) and not _is_red(default_c), "普通日志默认色: " + str(default_c))

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _is_green(c: Color) -> bool:
	return c.g > 0.9 and c.r < 0.6
func _is_red(c: Color) -> bool:
	return c.r > 0.9 and c.g < 0.6
func _is_gray(c: Color) -> bool:
	return absf(c.r - c.g) < 0.05 and absf(c.g - c.b) < 0.05 and c.r > 0.7

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
