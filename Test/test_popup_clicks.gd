# test_popup_clicks.gd — 弹窗按钮点击返回值回归测试
# 背景：Godot 4 lambda 捕获局部变量是值拷贝——`var result = false; btn.pressed.connect(func(): result = true)`
# 点击后 result 永远是 false（导致南蛮/无懈/舍己/贤者等全部失效）。已改为数组引用捕获 result[0]。
extends SceneTree

var failures := 0
var asserts := 0
var game = null
var prompt_result = false
var prompt_done := false

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	game = load("res://Scenes/Game.tscn").instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	game._sacrifice_override = Callable()  # 清掉，走真实弹窗

	# ---- 用例 1：出闪弹窗点「出闪」→ true ----
	await _check_click("dodge", "出【闪】", true)
	# ---- 用例 2：出闪弹窗点「不响应」→ false ----
	await _check_click("dodge", "不响应", false)
	# ---- 用例 3：南蛮弹窗点「出【杀】」→ true ----
	await _check_click("aoe", "出【杀】", true)
	# ---- 用例 4：决斗弹窗点「出【杀】」→ true ----
	await _check_click("duel", "出【杀】", true)
	# ---- 用例 5：舍己为人弹窗点「打出【舍己为人】」→ "card"（消耗手牌） ----
	await _check_click("sacrifice", "打出【舍己为人】", "card")
	# ---- 用例 6：贤者保命弹窗点「发动【贤者的加护】」→ true ----
	await _check_click("sage", "发动【贤者的加护】", true)

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check_click(kind: String, btn_text: String, expected):
	prompt_done = false
	prompt_result = false
	_start_prompt(kind)
	await process_frame
	await process_frame
	var btn = _find_btn(btn_text)
	_check(btn != null, kind + " 弹窗出现: " + btn_text + "?")
	if btn:
		btn.pressed.emit()
		await create_timer(0.5).timeout
		_check(prompt_done, kind + " 弹窗已结束")
		_check(prompt_result == expected, kind + " 点击返回 %s: %s" % [str(expected), str(prompt_result)])
	else:
		_check(false, kind + " 找不到按钮，跳过")
	# 清理：如果有残留弹窗（倒计时超时兜底），等它消失
	await create_timer(0.3).timeout

func _start_prompt(kind: String):
	match kind:
		"dodge":
			prompt_result = await game._show_dodge_prompt("敌人", "杀")
		"aoe":
			prompt_result = await game._show_aoe_prompt("南蛮入侵", "杀")
		"duel":
			prompt_result = await game._show_duel_prompt()
		"sacrifice":
			prompt_result = await game._show_sacrifice_prompt(game.players[1], 1)
		"sage":
			prompt_result = await game._show_sage_save_prompt()
	prompt_done = true

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
