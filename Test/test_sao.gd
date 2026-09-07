# test_sao.gd — 安普提·斯丢皮得冒烟测试（是~啊~ / 苕 / 装傻）
extends SceneTree

var failures := 0
var asserts := 0
var game = null

# 拼点出拳序列（_rps_test 用）：p0 的拳序列 / 对手的拳序列（按调用顺序循环取）
var rps_seq_p0: Array = []
var rps_seq_opp: Array = []
var rps_idx_a: int = 0
var rps_idx_b: int = 0

func _init():
	_run()

func _run() -> void:
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "安普提·斯丢皮得"
	var game_scene = load("res://Scenes/Game.tscn")
	game = game_scene.instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame

	var p0 = game.players[0]
	var p1 = game.players[1]
	var p2 = game.players[2]
	var p3 = game.players[3]
	var p4 = game.players[4]

	# 通用钩子：不弹窗
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._aoe_override = func(): return false
	game._yes_ah_override = Callable()
	game._sao_type_override = Callable()
	game._sao_reveal_override = Callable()
	game._sao_reveal_sub_override = Callable()
	game._sao_menu_override = Callable()
	game._rps_override = Callable()

	# 回合/出牌环境
	game.turn_manager.current_player_idx = 0
	game.turn_manager.current_phase = TurnManager.Phase.PLAY

	# ---- 用例 1：武将数据 ----
	_check(GeneralData.is_valid("安普提·斯丢皮得"), "安普提·斯丢皮得武将存在")
	_check(GeneralData.get_max_hp("安普提·斯丢皮得") == 3, "安普提·斯丢皮得 3 血")
	_check(GeneralData.get_skills("安普提·斯丢皮得").size() == 3, "三个技能: %d" % GeneralData.get_skills("安普提·斯丢皮得").size())
	_check(p0.general_name == "安普提·斯丢皮得", "玩家0 = 安普提·斯丢皮得")
	_check(p0.max_hp == 3, "玩家0 体力上限 3: %d" % p0.max_hp)

	# ---- 用例 2：【是~啊~】南蛮入侵：发动 → 流失体力不消耗手牌 ----
	p0.hp = 3
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.BARBARIAN_INVASION))
	game._yes_ah_override = func(): return "skill"
	var p1_hp_before = p1.hp
	await game.play_card(CardData.CardSubType.BARBARIAN_INVASION)
	_check(p0.hp == 2, "发动是~啊~：流失 1 点体力（3->2）: %d" % p0.hp)
	_check(p0.hand_size() == 1, "发动是~啊~：南蛮手牌未消耗: %d" % p0.hand_size())
	_check(p1.hp == p1_hp_before - 1, "南蛮照常生效：P1 受 1 点伤害: %d -> %d" % [p1_hp_before, p1.hp])

	# ---- 用例 3：【是~啊~】不发动 → 照常消耗手牌 ----
	p0.hp = 3
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.BARBARIAN_INVASION))
	game._yes_ah_override = func(): return "card"
	p1.hp = p1.max_hp
	await game.play_card(CardData.CardSubType.BARBARIAN_INVASION)
	_check(p0.hp == 3, "不发动是~啊~：体力不变: %d" % p0.hp)
	_check(p0.hand_size() == 0, "不发动是~啊~：照常消耗手牌: %d" % p0.hand_size())

	# ---- 用例 4：【是~啊~】决斗（目标执行路径）：发动 → 流失体力不消耗手牌 ----
	p0.hp = 3
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.DUEL))
	p1.hp = p1.max_hp
	p1.hand.clear()
	game._yes_ah_override = func(): return "skill"
	game._yes_ah_active = (await game._ask_yes_ah(p0, "决斗", true)) == "skill"
	_check(game._yes_ah_active, "决斗询问返回发动")
	await game.execute_card_on_target(p1, CardData.CardSubType.DUEL)
	_check(p0.hp == 2, "决斗是~啊~：流失 1 点体力（3->2）: %d" % p0.hp)
	_check(p0.hand_size() == 1, "决斗是~啊~：手牌未消耗: %d" % p0.hand_size())
	_check(p1.hp == p1.max_hp - 1, "决斗照常生效：P1 受 1 点伤害: %d -> %d" % [p1.max_hp, p1.hp])
	game._yes_ah_active = false

	# ---- 用例 5：【是~啊~】无懈可击（有手牌，发动）：流失体力不消耗手牌 ----
	p0.hp = 3
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.NULLIFICATION))
	game._nullify_override = func(): return true
	game._yes_ah_override = func(): return "skill"
	var actor = await game._ask_nullification_round("测试：是否打出一张【无懈可击】？")
	_check(actor == p0.player_name, "有手牌无懈打出成功: " + actor)
	_check(p0.hp == 2, "无懈是~啊~：流失 1 点体力（3->2）: %d" % p0.hp)
	_check(p0.hand_size() == 1, "无懈是~啊~：手牌未消耗: %d" % p0.hand_size())

	# ---- 用例 6：【是~啊~】无懈可击（无手牌）：可直接发动（流失体力）或取消 ----
	# 6.1 无手牌发动
	p0.hp = 3
	p0.hand.clear()
	game._yes_ah_override = Callable()
	actor = await game._ask_nullification_round("测试：是否打出一张【无懈可击】？")
	_check(actor == p0.player_name, "无手牌通过是~啊~打出无懈: " + actor)
	_check(p0.hp == 2, "无手牌无懈是~啊~：流失 1 点体力（3->2）: %d" % p0.hp)
	_check(p0.hand_size() == 0, "无手牌无懈：手牌仍为 0: %d" % p0.hand_size())
	# 6.2 无手牌取消（视为没有打出）
	p0.hp = 3
	game._nullify_override = func(): return false
	actor = await game._ask_nullification_round("测试：是否打出一张【无懈可击】？")
	_check(actor == "", "取消后无人打出无懈: " + actor)
	_check(p0.hp == 3, "取消无懈：体力不变: %d" % p0.hp)
	game._nullify_override = func(): return false

	# ---- 用例 7：【是~啊~】舍己为人（有手牌发动）：流失体力不消耗手牌，代替承受 ----
	p0.hp = 3
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.SACRIFICE))
	p1.hp = p1.max_hp
	game._sacrifice_override = func(): return true
	game._yes_ah_override = func(): return "skill"
	await game._deal_damage(p2, p1, 1, EffectChain.DamageType.PHYSICAL)
	_check(p0.hp == 1, "舍己为人是~啊~：流失+承受1点（3->2->1）: %d" % p0.hp)
	_check(p0.hand_size() == 1, "舍己为人是~啊~：手牌未消耗: %d" % p0.hand_size())
	_check(p1.hp == p1.max_hp, "舍己为人：P1 未受伤: %d" % p1.hp)
	game._sacrifice_override = func(): return false
	game._yes_ah_override = Callable()

	# ---- 用例 8：【苕】暗置武器 ----
	_clear_equips(p0)
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(p0, false)
	_check(p0.has_hidden_equip(), "暗置成功")
	_check(p0.hidden_equip_slot == "weapon", "暗置槽位 weapon: " + p0.hidden_equip_slot)
	_check(p0.equipment["weapon"] == CardData.CardSubType.HIDDEN_EQUIPMENT, "武器槽为暗置占位")
	_check(p0.get_hidden_equip_type() == "weapon", "暗置类型 weapon")

	# ---- 用例 9：【苕】武器槽被真实装备占用时不能暗置 ----
	_clear_equips(p0)
	p0.equipment["weapon"] = CardData.CardSubType.LIANNU
	await game._do_sao_hide(p0, false)
	_check(not p0.has_hidden_equip(), "武器槽被占不能暗置")
	p0.remove_equipment("weapon")

	# ---- 用例 10：【苕】明置武器（未被装备过的）----
	await game._do_sao_hide(p0, false)
	game._sao_reveal_sub_override = func(): return CardData.CardSubType.ICE_SWORD
	await game._do_sao_reveal(p0)
	_check(not p0.has_hidden_equip(), "明置后暗置状态清除")
	_check(p0.equipment["weapon"] == CardData.CardSubType.ICE_SWORD, "明置为寒冰剑")
	_check(game.equipment_pool.is_claimed(CardData.CardSubType.ICE_SWORD), "寒冰剑进唯一性占用")

	# ---- 用例 11：【苕】不能明置已被打出过的装备 ----
	_clear_equips(p0)
	await game._do_sao_hide(p0, false)
	game._sao_reveal_sub_override = func(): return CardData.CardSubType.ICE_SWORD  # 已被占用
	await game._do_sao_reveal(p0)
	_check(p0.has_hidden_equip(), "已被打出的装备不能明置（保持暗置）: %s" % p0.hidden_equip_slot)
	game._sao_reveal_sub_override = func(): return CardData.CardSubType.QINGLONG_BLADE
	await game._do_sao_reveal(p0)
	_check(not p0.has_hidden_equip(), "换一件未打出的武器可明置")
	_check(p0.equipment["weapon"] == CardData.CardSubType.QINGLONG_BLADE, "明置为青龙偃月刀")
	_check(game.equipment_pool.is_claimed(CardData.CardSubType.QINGLONG_BLADE), "青龙偃月刀进唯一性占用")

	# ---- 用例 12：【苕】暗置坐骑 + 明置 +1马（计数生效）----
	_clear_equips(p0)
	game._sao_type_override = func(): return "mount"
	await game._do_sao_hide(p0, false)
	_check(p0.get_hidden_equip_type() == "mount", "暗置类型 mount")
	_check(Player.MOUNT_SLOTS.has(p0.hidden_equip_slot), "暗置在坐骑槽: " + p0.hidden_equip_slot)
	game._sao_reveal_sub_override = func(): return CardData.CardSubType.MOUNT_PLUS
	await game._do_sao_reveal(p0)
	_check(not p0.has_hidden_equip(), "坐骑明置后暗置清除")
	_check(p0.mount_plus == 1, "明置 +1马：mount_plus=1: %d" % p0.mount_plus)
	_check(p0.equipment[p0.get_mount_slots()[0]] == CardData.CardSubType.MOUNT_PLUS, "坐骑槽为 +1马")
	_clear_equips(p0)
	game._sao_type_override = Callable()
	game._sao_reveal_sub_override = Callable()

	# ---- 用例 13：【苕】抢先明置：其他玩家装备同类型武器被阻止，手牌退回 ----
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(p0, false)
	game.turn_manager.current_player_idx = 1
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.ZHANGBA_SPEAR))
	game._sao_reveal_override = func(): return true
	await game.play_card(CardData.CardSubType.ZHANGBA_SPEAR)
	_check(p0.equipment["weapon"] == CardData.CardSubType.ZHANGBA_SPEAR, "抢先明置：暗置武器变为丈八蛇矛")
	_check(not p0.has_hidden_equip(), "抢先明置后暗置清除")
	_check(game.equipment_pool.is_claimed(CardData.CardSubType.ZHANGBA_SPEAR), "丈八蛇矛进唯一性占用")
	_check(p1.hand_size() == 1, "对方装备被阻止，手牌未消耗: %d" % p1.hand_size())
	_check(not p1.equipment.has("weapon"), "对方未能装备武器")
	game.turn_manager.current_player_idx = 0

	# ---- 用例 14：【苕】抢先明置拒绝 → 对方正常装备，暗置保留 ----
	_clear_equips(p0)
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(p0, false)
	game.turn_manager.current_player_idx = 1
	p1.hand.clear()
	p1.hand.append(CardBase.create(CardData.CardSubType.LIANNU))
	game._sao_reveal_override = func(): return false
	await game.play_card(CardData.CardSubType.LIANNU)
	_check(p1.equipment["weapon"] == CardData.CardSubType.LIANNU, "拒绝抢先：对方正常装备连弩")
	_check(p1.hand_size() == 0, "拒绝抢先：对方消耗手牌: %d" % p1.hand_size())
	_check(p0.has_hidden_equip(), "拒绝抢先：暗置保留")
	game.turn_manager.current_player_idx = 0
	game._sao_reveal_override = Callable()

	# ---- 用例 13.5：【苕】自己装备同类型武器时也可抢先明置（手牌退回） ----
	_clear_equips(p0)
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(p0, false)
	game.turn_manager.current_player_idx = 0
	p0.hand.clear()
	p0.hand.append(CardBase.create(CardData.CardSubType.GUDING_BLADE))
	game._sao_reveal_override = func(): return true
	await game.play_card(CardData.CardSubType.GUDING_BLADE)
	_check(p0.equipment["weapon"] == CardData.CardSubType.GUDING_BLADE, "自己装备抢先明置：暗置武器变为古锭刀")
	_check(p0.hand_size() == 1, "自己装备被阻止：手牌退回: %d" % p0.hand_size())
	_check(not p0.has_hidden_equip(), "自己装备抢先明置后暗置清除")
	game._sao_reveal_override = Callable()
	game._sao_type_override = Callable()
	_clear_equips(p0)

	# ---- 用例 15：【苕】技能点击流程（暗置 → 菜单明置 / 替换）----
	# 15.1 点击技能暗置
	_clear_equips(p0)
	p0.hidden_equip_slot = ""
	game._sao_type_override = func(): return "armor"
	await game._on_sao_skill_clicked(p0)
	_check(p0.get_hidden_equip_type() == "armor", "点击技能暗置防具")
	# 15.2 已有暗置 → 菜单选明置
	game._sao_menu_override = func(): return 0
	game._sao_reveal_sub_override = func(): return CardData.CardSubType.RENWANG_DUN
	await game._on_sao_skill_clicked(p0)
	_check(p0.equipment["armor"] == CardData.CardSubType.RENWANG_DUN, "菜单明置为仁王盾")
	_check(not p0.has_hidden_equip(), "明置后暗置清除")
	# 15.3 再暗置 → 菜单选替换
	game._sao_type_override = func(): return "weapon"
	await game._on_sao_skill_clicked(p0)
	_check(p0.get_hidden_equip_type() == "weapon", "再次暗置武器")
	game._sao_menu_override = func(): return 1
	game._sao_type_override = func(): return "mount"
	await game._on_sao_skill_clicked(p0)
	_check(p0.get_hidden_equip_type() == "mount", "菜单替换为暗置坐骑")
	# 15.4 菜单取消
	game._sao_menu_override = func(): return -1
	await game._on_sao_skill_clicked(p0)
	_check(p0.get_hidden_equip_type() == "mount", "菜单取消：暗置保留")
	_clear_equips(p0)
	p0.hidden_equip_slot = ""

	# ---- 用例 16：明置时机询问（任意行动后 _maybe_ask_reveal）----
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(p0, false)
	game._reveal_ask_pending = true
	game._sao_reveal_override = func(): return true
	game._sao_reveal_sub_override = func(): return CardData.CardSubType.FATE_BLADE
	await game._maybe_ask_reveal()
	_check(p0.equipment["weapon"] == CardData.CardSubType.FATE_BLADE, "行动后询问明置为命运之刃")
	_check(not p0.has_hidden_equip(), "行动后明置：暗置清除")
	_check(not game._reveal_ask_pending, "行动窗口内不再重复询问")
	game._sao_reveal_override = Callable()
	game._sao_reveal_sub_override = Callable()
	game._sao_type_override = Callable()

	# ---- 用例 17：【装傻】濒死拼点赢超过一半 → 回复至 1 点体力 ----
	_clear_equips(p0)
	p0.hand.clear()
	p0.hp = 0
	game._rps_override = Callable(self, "_rps_test")
	rps_seq_p0 = [0, 0, 0, 0]      # 石头
	rps_seq_opp = [2, 2, 2, 2]    # 剪刀 → 全赢
	rps_idx_a = 0
	rps_idx_b = 0
	await game._check_dying(p0)
	_check(p0.hp == 1, "装傻全赢（4/4）：回复至 1 点体力: %d" % p0.hp)
	_check(p0.is_alive(), "装傻后存活")

	# ---- 用例 18：【装傻】平局不算赢，2 赢 2 平 → 未超过一半，死亡 ----
	p0.hp = 0
	rps_seq_p0 = [0, 0, 0, 0]
	rps_seq_opp = [2, 2, 0, 0]    # 赢、赢、平、平
	rps_idx_a = 0
	rps_idx_b = 0
	await game._check_dying(p0)
	_check(p0.hp == 0, "装傻 2 赢 2 平未超过一半：死亡: %d" % p0.hp)
	_check(not p0.is_alive(), "装傻失败后阵亡")

	# ---- 用例 19：【装傻】全输 → 死亡 ----
	p0.hp = 0
	rps_seq_p0 = [2, 2, 2, 2]     # 剪刀
	rps_seq_opp = [0, 0, 0, 0]    # 石头 → 全输
	rps_idx_a = 0
	rps_idx_b = 0
	await game._check_dying(p0)
	_check(p0.hp == 0, "装傻全输：死亡: %d" % p0.hp)
	game._rps_override = Callable()
	p0.hp = 3

	# ---- 用例 20：详情弹窗显示【苕】按钮 + 暗置装备 ----
	_clear_equips(p0)
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(p0, false)
	game._sao_type_override = Callable()
	game._open_player_detail(p0)
	await process_frame
	var sao_btn = _find_btn_rec(game._detail_popup_root, "苕")
	_check(sao_btn != null, "详情弹窗有【苕】按钮")
	var hidden_btn = _find_btn_rec(game._detail_popup_root, "暗置")
	_check(hidden_btn != null, "详情弹窗显示暗置装备（一件装备（暗置））")
	# 清理详情弹窗
	for child in game._detail_popup_root.get_children():
		child.queue_free()
	game._detail_popup_root.visible = false

	print("RESULT: %d asserts, %d failures" % [asserts, failures])
	quit(1 if failures > 0 else 0)

# 拼点测试钩子：p0 出 rps_seq_p0 序列，其他玩家出 rps_seq_opp 序列（循环取）
func _rps_test(p: Player) -> int:
	if p == game.players[0]:
		var c = rps_seq_p0[rps_idx_a % rps_seq_p0.size()]
		rps_idx_a += 1
		return c
	var c2 = rps_seq_opp[rps_idx_b % rps_seq_opp.size()]
	rps_idx_b += 1
	return c2

# 清空玩家全部装备（含暗置）
func _clear_equips(p: Player):
	var slots = p.get_equip_slots()
	for s in slots:
		p.remove_equipment(s)
	p.hidden_equip_slot = ""

func _check(cond: bool, msg: String):
	asserts += 1
	if cond:
		print("PASS: " + msg)
	else:
		failures += 1
		print("FAIL: " + msg)

func _find_btn_rec(node: Node, text: String) -> Button:
	if node is Button and not node.is_queued_for_deletion() and node.text.contains(text):
		return node
	for c in node.get_children():
		var r = _find_btn_rec(c, text)
		if r:
			return r
	return null

func _find_label_rec(node: Node, text: String) -> Label:
	if node is Label and not node.is_queued_for_deletion() and node.text.contains(text):
		return node
	for c in node.get_children():
		var r = _find_label_rec(c, text)
		if r:
			return r
	return null
