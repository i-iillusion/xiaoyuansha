# test_countdown.gd — 30+30 倒计时 / 提示句 / 实时日志冒烟测试
# 机制：每步 30 秒（出牌/响应时重置）+ 整局储备 30 秒（只扣不加，每步耗尽后开始扣除
extends SceneTree

var failures := 0
var asserts := 0
var dodge_done := false
var dodge_result := true
var timeout_flag := false

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	var game_scene = load("res://Scenes/Game.tscn")
	var game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	# ---- 用例 1：出牌阶段启动倒计时（每步 30 + 储备 30） ----
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = game.turn_manager.Phase.PLAY
	game._bank_remaining = 30.0
	game._do_play(0)
	_check(game._countdown_active, "出牌阶段启动倒计时")
	_check(game._step_remaining > 29.0, "每步 30 秒: %.1f" % game._step_remaining)
	_check(game._bank_remaining > 29.0, "整局储备 30 秒: %.1f" % game._bank_remaining)
	_check(game._debug_label.text.contains("出牌阶段"), "提示句显示出牌阶段: " + game._debug_label.text)
	_check(game._countdown_label.text.contains("秒"), "倒计时文字显示: " + game._countdown_label.text)

	# ---- 用例 2：直接生效的牌（酒）成功打出后重置每步（储备不变） ----
	game._step_remaining = 5.0
	var bank_before = game._bank_remaining
	await game._on_selector_confirmed(CardData.CardSubType.WINE)
	_check(game._step_remaining > 29.0, "出牌后重置每步倒计时: %.1f" % game._step_remaining)
	_check(absf(game._bank_remaining - bank_before) < 0.5, "储备不因出牌重置")

	# ---- 用例 2b：选择牌时倒计时继续（未成功出牌不重置） ----
	game._step_remaining = 5.0
	await game._on_selector_confirmed(CardData.CardSubType.DODGE)  # 闪不能主动打出(则)return
	_check(game._step_remaining < 6.0, "选择牌（未打出）不重置倒计时: %.1f" % game._step_remaining)

	# ---- 用例 3：超时触发回调（每步耗尽后扣储备，储备也耗尽才超时） ----
	timeout_flag = false
	game._countdown_active = true
	game._step_remaining = 0.05
	game._bank_remaining = 0.05
	game._countdown_on_timeout = func(): timeout_flag = true
	await create_timer(0.3).timeout
	await process_frame
	_check(timeout_flag, "倒计时超时触发回调")
	_check(not game._countdown_active, "超时后倒计时停止")
	_check(game._bank_remaining <= 0.0, "储备耗尽: %.2f" % game._bank_remaining)

	# ---- 用例 3b：每步耗尽但储备充足(则)不超时（扣储备继续） ----
	timeout_flag = false
	game._countdown_active = true
	game._step_remaining = 0.05
	game._bank_remaining = 10.0
	game._countdown_on_timeout = func(): timeout_flag = true
	await create_timer(0.3).timeout
	await process_frame
	_check(not timeout_flag, "储备充足时每步耗尽不超时")
	_check(game._bank_remaining < 10.0 and game._bank_remaining >= 0.0, "储备被扣: %.2f" % game._bank_remaining)
	game._halt_countdown()

	# ---- 用例 4：响应弹窗倒计时 + 超时自动放弃（当前 AI 回合，结束后无倒计时） ----
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = game.turn_manager.Phase.PLAY
	game._countdown_active = false
	game._bank_remaining = 5.0
	dodge_done = false
	dodge_result = true
	_start_dodge(game)
	await process_frame
	await process_frame
	_check(game._countdown_active, "响应弹窗启动倒计时")
	_check(game._debug_label.text.contains("等待") and game._debug_label.text.contains("响应"), "提示句显示等待响应: " + game._debug_label.text)
	game._step_remaining = 0.05
	game._bank_remaining = 0.05
	await create_timer(0.35).timeout
	await process_frame
	_check(dodge_done, "响应弹窗已结束")
	_check(dodge_result == false, "响应超时自动放弃: %s" % str(dodge_result))
	_check(not game._countdown_active, "响应结束后（AI 回合）无倒计时")

	# ---- 用例 5：提示句恢复阶段（响应结束后回到出牌阶段提示句 ----
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = game.turn_manager.Phase.PLAY
	game._stop_countdown()
	_check(game._countdown_active, "回到出牌阶段重新启动倒计时")
	_check(game._debug_label.text.contains("出牌阶段"), "提示句恢复出牌阶段: " + game._debug_label.text)

	# ---- 用例 6：实时日志 5 秒后消失 ----
	game._log_remaining = 0.0
	game._log_label.text = ""
	game._update_debug("测试日志内容")
	_check(game._log_label.text == "测试日志内容", "实时日志显示")
	_check(game._debug_label.text.contains("出牌阶段"), "日志不影响提示句")
	game._log_remaining = 0.05
	await create_timer(0.25).timeout
	_check(game._log_label.text == "", "日志 5 秒后消失")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

# 并发启动出闪弹窗（协程函数不能存返回值稍候 await，用成员变量收集结果）
func _start_dodge(game):
	dodge_result = await game._show_dodge_prompt("敌人", "杀")
	dodge_done = true

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
