# test_menu.gd — 主菜单（开始界面/测试模式/随机模式切换）冒烟测试
extends SceneTree

var failures := 0
var asserts := 0
var menu: Control = null

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	MainMenu.random_mode = false  # 确定性：先测自选武将模式
	var scene = load("res://Scenes/MainMenu.tscn")
	menu = scene.instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	# ---- 用例 1：主页面 ----
	var b = _buttons()
	_check(b.has("开始游戏") and b.has("退出游戏"), "主页面按钮: " + str(b))
	var title = menu.get_node("Center/Box/Title")
	_check(title.text == "校园杀", "大标题校园杀: " + title.text)
	_check(not menu.get_node("Center/Box").has_node("Subtitle"), "小标题已移除")

	# ---- 用例 2：开始游戏页 ----
	_click("开始游戏")
	b = _buttons()
	_check(b.has("单人游戏") and b.has("多人游戏") and b.has("设置") and b.has("测试模式"), "开始游戏页按钮: " + str(b))

	# ---- 用例 3：测试模式页面（7 种模式 + 玩法切换按钮） ----
	_click("测试模式")
	b = _buttons()
	var expected = ["1V1", "3人混战", "2V2", "5人标准", "6人奸雄", "7人标准", "8人奸雄"]
	var all_ok = true
	for e in expected:
		if not b.has(e):
			all_ok = false
			print("  缺少: ", e)
	_check(all_ok, "测试模式 7 种模式齐全: " + str(b))
	_check(_find_partial("模式：自选武将") != null, "玩法切换按钮显示自选武将")
	_check(MainMenu.random_mode == false, "random_mode = false")

	# ---- 用例 4：未实现模式点击 → 提示 ----
	var tip = menu.get_node("Tip")
	_check(not tip.visible, "初始提示隐藏")
	_click("3人混战")
	_check(tip.visible, "点击未实现模式显示提示")
	_check(tip.text.contains("尚未实现"), "提示文案: " + tip.text)

	# ---- 用例 5：返回链 ----
	_click("← 返回")
	_check(_buttons().has("单人游戏"), "测试模式返回开始游戏页")
	_click("← 返回")
	_check(_buttons().has("开始游戏"), "开始游戏页返回主页面")

	# ---- 用例 6：自选武将模式：5人标准 / 1V1 → 武将选择页 ----
	_click("开始游戏")
	_click("测试模式")
	var game_scene = load("res://Scenes/Game.tscn")
	_check(game_scene != null, "Game.tscn 可加载（5人标准入口）")
	_click("5人标准")
	b = _buttons()
	_check(_page_has("稻草人") and _page_has("凯文·罗本"), "5人标准进入武将选择页: " + str(b))
	_check(_page_has("杰基·斯特朗") and _page_has("麦克斯·欧尼斯特"), "武将选择页含全部已实现武将")
	# 武将卡片含技能信息
	_check(_find_partial("凯文·罗本") != null and _find_partial("你个壊货") != null, "凯文卡片显示技能")
	_check(_find_partial("稻草人") != null and _find_partial("无技能") != null, "稻草人卡片显示无技能")
	# 返回链：武将页 → 测试模式
	_click("← 返回")
	_check(_buttons().has("1V1"), "武将页返回测试模式")
	# 1V1 同样进武将选择页
	_click("1V1")
	_check(_page_has("稻草人") and _page_has("凯文·罗本"), "1V1 进入武将选择页")
	_check(GameManager.random_identity == false and GameManager.random_general == false, "自选武将模式 statics 为 false")

	# ---- 用例 7：切到随机玩法 → 5人标准直接进入游戏 ----
	_click("← 返回")  # 武将页 → 测试模式
	_click_partial("模式")  # 切换玩法
	_check(_find_partial("模式：随机玩法") != null, "切换到随机玩法")
	_check(MainMenu.random_mode, "random_mode = true")
	_click("5人标准")
	await create_timer(0.3).timeout
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.name == "Game", "随机模式 5人标准直接进入游戏: " + (current_scene.name if current_scene else "null"))
	_check(current_scene.players.size() == 5, "游戏 5 名玩家: " + str(current_scene.players.size() if current_scene else 0))
	_check(GameManager.random_identity and GameManager.random_general, "随机玩法 statics 置 true")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _buttons() -> Array:
	var arr: Array = []
	for c in menu.get_node("Center/Box/Page").get_children():
		if c is Button and not c.is_queued_for_deletion():
			arr.append(c.text)
	return arr

func _page_has(partial: String) -> bool:
	return _find_partial(partial) != null

func _find_partial(partial: String) -> Button:
	for c in menu.get_node("Center/Box/Page").get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text.contains(partial):
			return c
	return null

func _click_partial(partial: String) -> void:
	var btn = _find_partial(partial)
	if btn:
		btn.pressed.emit()
	else:
		_check(false, "找不到按钮(部分匹配): " + partial)

func _click(text: String) -> void:
	for c in menu.get_node("Center/Box/Page").get_children():
		if c is Button and not c.is_queued_for_deletion() and c.text == text:
			c.pressed.emit()
			return
	_check(false, "找不到按钮: " + text)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)
