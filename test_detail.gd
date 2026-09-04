# test_detail.gd — PlayerDetailPopup 装备区/悬停冒烟测试
extends SceneTree

var failures := 0
var asserts := 0
var popup: Control = null
var player: Player = null
var equip_clicked_value := -1

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	# 准备玩家：武器连弩 + 防具仁王盾 + 坐骑(+1马、-1马、-1劣马)
	player = Player.new()
	player.player_name = "测试者"
	player.max_hp = 4
	player.hp = 4
	player.identity = "反贼"
	player.equipment["weapon"] = CardData.CardSubType.LIANNU
	player.equipment["armor"] = CardData.CardSubType.RENWANG_DUN
	player.equipment["mount_1"] = CardData.CardSubType.MOUNT_PLUS
	player.equipment["mount_2"] = CardData.CardSubType.MOUNT_MINUS
	player.equipment["mount_3"] = CardData.CardSubType.MULE_MINUS

	popup = PlayerDetailPopup.create(root, player)
	popup.equip_clicked.connect(_on_equip_clicked)
	await process_frame
	await process_frame

	# 1. 技能区不再显示座位/坐骑
	var skills = popup.get_node("Panel/Content/SkillsSection/SkillsList")
	var skills_text = _collect_text(skills)
	_check(not skills_text.contains("座位"), "技能区无座位信息")
	_check(not skills_text.contains("坐骑"), "技能区无坐骑汇总")

	# 2. 装备区顺序：武器 → 防具 → 坐骑
	var equips = popup.get_node("Panel/Content/EquipmentSection/EquipmentList")
	var rows: Array = []
	for c in equips.get_children():
		if c is Button and not c.is_queued_for_deletion():
			rows.append(c.text)
	print("EQUIP ROWS: ", rows)
	_check(rows.size() == 3, "装备区三行（武器/防具/坐骑）: %d" % rows.size())
	_check(rows[0].contains("武器") and rows[0].contains("连弩"), "第一行是武器: " + rows[0])
	_check(rows[1].contains("护甲") and rows[1].contains("仁王盾"), "第二行是防具: " + rows[1])
	_check(rows[2].contains("坐骑"), "第三行是坐骑: " + rows[2])
	_check(rows[2].contains("+1马") and rows[2].contains("-1马") and rows[2].contains("-1劣马"), "坐骑统计: " + rows[2])
	# 3. 不再显示描述
	var no_desc = true
	for r in rows:
		if r.contains("【") or r.contains("】"):
			no_desc = false
	_check(no_desc, "装备行不内嵌描述")

	# 4. 悬停显示 tooltip
	var weapon_btn = equips.get_child(0)
	var tip = popup.get_node("Tooltip")
	_check(not tip.visible, "初始 tooltip 隐藏")
	weapon_btn.mouse_entered.emit()
	_check(tip.visible, "悬停武器显示 tooltip")
	var tip_text = popup.get_node("Tooltip/Label").text
	_check(tip_text.contains("杀"), "武器描述: " + tip_text)
	weapon_btn.mouse_exited.emit()
	_check(not tip.visible, "移开隐藏 tooltip")

	# 5. 坐骑行悬停（多行描述）
	var mount_btn = equips.get_child(2)
	mount_btn.mouse_entered.emit()
	var mount_tip = popup.get_node("Tooltip/Label").text
	_check(mount_tip.contains("+1马") and mount_tip.contains("-1马"), "坐骑悬停描述含各类: " + mount_tip)
	mount_btn.mouse_exited.emit()

	# 6. 装备行点击发出 equip_clicked 信号（贤者的加护发动入口）
	equip_clicked_value = -1
	var weapon_btn2 = equips.get_child(0)
	weapon_btn2.pressed.emit()
	_check(equip_clicked_value == CardData.CardSubType.LIANNU, "点击武器行发出 equip_clicked(LIANNU)")
	var mount_btn2 = equips.get_child(2)
	mount_btn2.pressed.emit()
	_check(equip_clicked_value == CardData.CardSubType.LIANNU, "坐骑汇总行不可点击（值不变仍为 LIANNU）")

	# 7. 贤者的加护行点击发出 SAGE_PROTECTION（先改装备再创建弹窗）
	player.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	equip_clicked_value = -1
	var popup2 = PlayerDetailPopup.create(root, player)
	popup2.equip_clicked.connect(_on_equip_clicked)
	await process_frame
	await process_frame
	var armor_btn = popup2.get_node("Panel/Content/EquipmentSection/EquipmentList").get_child(1)
	armor_btn.pressed.emit()
	_check(equip_clicked_value == CardData.CardSubType.SAGE_PROTECTION, "点击贤者的加护行发出 equip_clicked(SAGE_PROTECTION)")
	popup2.queue_free()
	await process_frame

	# 7b. 贤者标记在标记栏（不在状态栏）
	player.sage_tokens = 2
	player.sage_activated = false
	var popup3 = PlayerDetailPopup.create(root, player)
	await process_frame
	await process_frame
	var marks_text = _collect_text(popup3.get_node("Panel/Content/MarksSection/MarksList"))
	var status_text = _collect_text(popup3.get_node("Panel/Content/StatusSection/StatusList"))
	_check(marks_text.contains("贤者标记") and marks_text.contains("2/3"), "标记栏显示贤者标记: " + marks_text)
	_check(not status_text.contains("贤者"), "状态栏不再显示贤者标记")
	_check(not marks_text.contains("暂无标记"), "有贤者标记时不显示「暂无标记」")
	# 激活状态也在标记栏
	player.sage_tokens = 0
	player.sage_activated = true
	var popup4 = PlayerDetailPopup.create(root, player)
	await process_frame
	await process_frame
	var marks_text2 = _collect_text(popup4.get_node("Panel/Content/MarksSection/MarksList"))
	_check(marks_text2.contains("已激活"), "标记栏显示激活状态: " + marks_text2)
	popup3.queue_free()
	popup4.queue_free()
	await process_frame

	# 8. 关闭按钮
	popup.get_node("Panel/CloseBtn").pressed.emit()
	await create_timer(0.25).timeout
	await process_frame
	_check(is_instance_valid(popup) == false or popup.is_queued_for_deletion(), "关闭后弹窗销毁")

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _on_equip_clicked(v):
	equip_clicked_value = v

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
