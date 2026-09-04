# test_selector.gd — CardSelector 多层级选择冒烟测试
# 注意：本脚本模式下 add_child 后 _ready 延迟到下一帧，需 await process_frame
extends SceneTree

var failures := 0
var asserts := 0
var selector: Control = null
var confirmed_value := -1
var cancelled_flag := false

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	# 用例 1：大类页
	selector = _make()
	await process_frame
	var b = _buttons()
	_check(b.has("基本牌") and b.has("锦囊牌") and b.has("装备牌") and b.has("取消"), "大类页按钮齐全")
	_check(_title() == "选择卡牌类型", "大类页标题")
	# 大类按钮尺寸
	var big = _find_button("基本牌")
	_check(big.custom_minimum_size.y >= 50, "大类按钮改大(>=50): " + str(big.custom_minimum_size))
	_check(big.get_theme_font_size("font_size") >= 18, "大类按钮字号加大")

	# 用例 2：锦囊牌 → 延时锦囊 → 闪电
	_click("锦囊牌")
	_check(_title() == "锦囊牌", "锦囊子分类标题")
	b = _buttons()
	_check(b.has("普通锦囊") and b.has("延时锦囊"), "锦囊子分类按钮")
	_click("延时锦囊")
	_check(_title() == "延时锦囊", "延时锦囊标题")
	b = _buttons()
	_check(b.has("闪电") and b.has("乐不思蜀") and b.has("兵粮寸断"), "延时锦囊三张")
	_click("闪电")
	await _wait_free()
	_check(confirmed_value == CardData.CardSubType.LIGHTNING, "闪电 confirmed=LIGHTNING")

	# 用例 3：基本牌 → 杀 → 火杀
	selector = _make()
	await process_frame
	_click("基本牌")
	_check(_title() == "基本牌", "基本牌标题")
	b = _buttons()
	_check(b.has("杀") and b.has("闪") and b.has("桃") and b.has("酒"), "基本牌四张")
	_click("杀")
	_check(_title() == "选择杀的属性", "杀属性标题")
	b = _buttons()
	_check(b.has("杀") and b.has("火杀") and b.has("雷杀"), "杀属性三种")
	_click("火杀")
	await _wait_free()
	_check(confirmed_value == CardData.CardSubType.FIRE_STRIKE, "火杀 confirmed=FIRE_STRIKE")

	# 用例 4：装备牌 → 马 → +1马
	selector = _make()
	await process_frame
	_click("装备牌")
	_check(_title() == "装备牌", "装备标题")
	b = _buttons()
	_check(b.has("马") and b.has("武器") and b.has("防具"), "装备子分类")
	_click("马")
	_check(_title() == "马", "马标题")
	b = _buttons()
	_check(b.has("+1马") and b.has("-1马") and b.has("-1劣马") and b.has("+1劣马"), "四匹马")
	_click("+1马")
	await _wait_free()
	_check(confirmed_value == CardData.CardSubType.MOUNT_PLUS, "+1马 confirmed=MOUNT_PLUS")

	# 用例 5：返回链（武器 → 返回 → 装备子分类 → 返回 → 大类）
	selector = _make()
	await process_frame
	_click("装备牌")
	_click("武器")
	_check(_title() == "武器", "武器标题")
	_click("← 返回")
	_check(_title() == "装备牌", "返回后回装备子分类")
	_click("← 返回")
	_check(_title() == "选择卡牌类型", "返回后回大类")

	# 用例 6：取消
	selector = _make()
	await process_frame
	_click("取消")
	await _wait_free()
	_check(cancelled_flag, "取消信号发出")

	# 用例 7：悬停 tooltip
	selector = _make()
	await process_frame
	_click("基本牌")
	var strike_btn = _find_button("杀")
	var tip = selector.get_node("Tooltip")
	_check(not tip.visible, "初始 tooltip 隐藏")
	strike_btn.mouse_entered.emit()
	_check(tip.visible, "悬停显示 tooltip")
	var tip_text = selector.get_node("Tooltip/Label").text
	_check(tip_text.length() > 5, "tooltip 有描述文字: " + tip_text)
	strike_btn.mouse_exited.emit()
	_check(not tip.visible, "移开隐藏 tooltip")
	# 进入杀属性页
	_click("杀")
	_check(_title() == "选择杀的属性", "tooltip 用例进杀属性页")
	var fire_btn = _find_button("火杀")
	fire_btn.mouse_entered.emit()
	_check(tip.visible, "火杀悬停显示 tooltip")
	_click("火杀")
	_check(not tip.visible, "页面切换后 tooltip 隐藏")
	await _wait_free()
	_check(confirmed_value == CardData.CardSubType.FIRE_STRIKE, "tooltip 用例确认火杀")

	# 用例 8：装备描述存在性抽查（武器/防具/马都有描述）
	selector = _make()
	await process_frame
	_click("装备牌")
	_click("武器")
	var liannu = _find_button("连弩")
	liannu.mouse_entered.emit()
	var liannu_tip = selector.get_node("Tooltip/Label").text
	_check(liannu_tip.contains("杀"), "连弩悬停有描述: " + liannu_tip)
	liannu.mouse_exited.emit()
	_click("← 返回")
	_click("马")
	var mount = _find_button("+1马")
	mount.mouse_entered.emit()
	var mount_tip = selector.get_node("Tooltip/Label").text
	_check(mount_tip.contains("距离"), "+1马悬停有描述: " + mount_tip)

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _make() -> Control:
	confirmed_value = -1
	cancelled_flag = false
	var scene = load("res://Scenes/CardSelector.tscn")
	var s = scene.instantiate()
	s.confirmed.connect(_on_confirm)
	s.cancelled.connect(_on_cancel)
	root.add_child(s)
	return s

func _wait_free() -> void:
	# 淡出 tween 约 0.1s，等真实时间再检查信号
	await create_timer(0.25).timeout
	await process_frame

func _title() -> String:
	return selector.get_node("Panel/Title").text

func _click(text: String) -> void:
	var btn = _find_button(text)
	if btn == null:
		_check(false, "找不到按钮: " + text)
		return
	btn.pressed.emit()

func _find_button(text: String) -> Button:
	return _find_btn_recursive(selector.get_node("Panel/Content/List"), text)

func _find_btn_recursive(node: Node, text: String) -> Button:
	if node is Button and not node.is_queued_for_deletion() and node.text == text:
		return node
	for c in node.get_children():
		var r = _find_btn_recursive(c, text)
		if r:
			return r
	return null

func _buttons() -> Array:
	var arr: Array = []
	_collect(selector.get_node("Panel/Content/List"), arr)
	return arr

func _collect(node: Node, arr: Array):
	if node is Button and not node.is_queued_for_deletion():
		arr.append(node.text)
	for c in node.get_children():
		_collect(c, arr)

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)

func _on_confirm(v):
	confirmed_value = v

func _on_cancel():
	cancelled_flag = true
