# B1：装备区真实卡牌实例与旧类型查询兼容层。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "B1：" + label)

func run(host):
	suite = host
	game = host.game
	suite.reset_players()
	var p = game.players[0]
	var weapon = CardBase.create(CardData.CardSubType.LIANNU)
	weapon.source_seat = 4
	check(p.equip_card_to_slot("weapon", weapon), "真实武器可装入空槽")
	check(p.get_weapon() == CardData.CardSubType.LIANNU, "旧类型查询接口保持不变")
	check(p.get_equipment_card("weapon") == weapon, "装备区保存原始卡牌对象")
	check(p.get_equipment_card("weapon").source_seat == 4, "装备时保留卡牌来源元数据")
	var removed = p.remove_equipment("weapon")
	check(removed == weapon and p.get_weapon() == -1, "卸下返回同一对象并清空类型槽")
	check(p.remove_equipment("weapon") == null, "同一装备不能重复卸下")

	# 旧测试/旧入口直接写类型时只补建一次兼容对象；正式流程不得依赖此分支。
	p.equipment["armor"] = CardData.CardSubType.SILVER_LION
	var legacy = p.get_equipment_card("armor")
	check(legacy != null and legacy.sub_type == CardData.CardSubType.SILVER_LION, "旧类型入口可补建兼容实例")
	check(p.get_equipment_card("armor") == legacy and p.remove_equipment("armor") == legacy, "兼容实例在后续操作中保持唯一")

	p.equipment["armor"] = CardData.CardSubType.HIDDEN_EQUIPMENT
	p.hidden_equip_slot = "armor"
	check(p.get_equipment_card("armor") == null, "暗置占位不虚构实体装备牌")
	check(p.remove_equipment("armor") == null and p.hidden_equip_slot == "", "移除暗置占位只清状态")

	# DEV-B01b：落位入口按实际牌型与槽位分类拒绝错误资源，失败不改状态。
	suite.reset_players()
	var peach = CardBase.create(CardData.CardSubType.PEACH)
	var armor_card = CardBase.create(CardData.CardSubType.RENWANG_DUN)
	var mount_card = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	check(not p.equip_card_to_slot("weapon", peach), "基本牌不能装入武器槽")
	check(not p.equip_card_to_slot("weapon", armor_card), "防具不能装入武器槽")
	check(not p.equip_card_to_slot("mount_1", weapon), "武器不能装入坐骑槽")
	check(not p.equip_card_to_slot("armor", mount_card), "坐骑不能装入防具槽")
	check(not p.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)), "暗置占位不能伪装为实体装备牌")
	check(p.equipment.is_empty() and p.equipment_cards.is_empty() and p.mount_plus == 0,
		"非法落位不改变类型槽、原实例表或坐骑计数")
	check(p.equip_card_to_slot("weapon", weapon) and p.get_equipment_card("weapon") == weapon,
		"合法武器仍保留原实例")
	check(p.equip_card_to_slot("armor", armor_card) and p.get_equipment_card("armor") == armor_card,
		"合法防具仍保留原实例")
	check(p.equip_card_to_slot("mount_1", mount_card) and p.get_equipment_card("mount_1") == mount_card and p.mount_plus == 1,
		"合法坐骑仍保留原实例并只增加一次计数")
	check(not p.equip_card_to_slot("mount_1", CardBase.create(CardData.CardSubType.MOUNT_MINUS))
		and p.get_equipment_card("mount_1") == mount_card and p.mount_plus == 1 and p.mount_minus == 0,
		"已占槽位拒绝第二张牌且不改变原牌或计数")

	# B2：正式出牌、主动替换和全牌区清理均沿用真实对象。
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game.turn_manager.current_player_idx = 0
	p = game.players[0]
	weapon = CardBase.create(CardData.CardSubType.LIANNU)
	weapon.source_seat = 6
	p.hand.append(weapon)
	await game.play_card(CardData.CardSubType.LIANNU)
	check(p.get_equipment_card("weapon") == weapon and p.hand.is_empty(), "从手牌装备武器保留原实例")

	var old_armor = CardBase.create(CardData.CardSubType.SILVER_LION)
	var new_armor = CardBase.create(CardData.CardSubType.RENWANG_DUN)
	p.hp = 8
	p.equip_card_to_slot("armor", old_armor)
	p.hand.append(new_armor)
	game._weapon_replace_override = func(): return true
	await game.play_card(CardData.CardSubType.RENWANG_DUN)
	game._weapon_replace_override = Callable()
	check(p.get_equipment_card("armor") == new_armor, "主动替换后新防具仍是打出的对象")
	check(game.deck._discard.count(old_armor) == 1, "被替换防具的原实例恰好弃置一次")
	check(p.hp == 9, "主动替换算失去装备并触发白银狮子一次")

	var mount = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	p.equip_mount_card(mount)
	var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
	p.judgment_cards.append(judgment)
	game._discard_all_cards(p, true)
	check(p.equipment.is_empty() and p.equipment_cards.is_empty(), "全牌区清理同步清空装备类型与实例表")
	check(game.deck._discard.count(weapon) == 1 and game.deck._discard.count(new_armor) == 1 and game.deck._discard.count(mount) == 1, "死亡清理按原实例弃置全部装备")
	check(game.deck._discard.count(judgment) == 1, "装备实例迁移不影响判定牌原实例清理")

	# B3：偷取、交换和装备技能转移不再按类型重建卡牌。
	suite.reset_players()
	game.deck._discard.clear()
	var attacker = game.players[0]
	var victim = game.players[1]
	var stolen = CardBase.create(CardData.CardSubType.QIXING_PAO)
	stolen.source_seat = 7
	victim.equip_card_to_slot("armor", stolen)
	game._equip_pick_override = func(): return "armor"
	await game._steal_equip(attacker, victim, true, "顺手牵羊")
	game._equip_pick_override = Callable()
	check(attacker.determined_cards == [stolen] and victim.get_armor() == -1, "顺手牵羊获得装备原实例")
	check(stolen.source_seat == 7 and game.deck._discard.is_empty(), "偷取装备保留来源且不误入弃牌堆")

	var first_weapon = CardBase.create(CardData.CardSubType.LIANNU)
	var second_weapon = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
	attacker.equip_card_to_slot("weapon", first_weapon)
	victim.equip_card_to_slot("weapon", second_weapon)
	check(game._swap_equip_slot(attacker, "weapon", victim, "weapon"), "两件明置装备可以交换")
	check(attacker.get_equipment_card("weapon") == second_weapon and victim.get_equipment_card("weapon") == first_weapon, "交换后两张装备对象互换而非重建")
	check(game.deck._discard.is_empty(), "交换不把任一装备送入弃牌堆")
	await check_equip_pick_ownership()

	suite.reset_players()
	game.deck._discard.clear()
	var source = game.players[1]
	var target = game.players[2]
	var calamity = CardBase.create(CardData.CardSubType.CALAMITY_SWORD)
	var replaced_weapon = CardBase.create(CardData.CardSubType.GUDING_BLADE)
	source.equip_card_to_slot("weapon", calamity)
	target.equip_card_to_slot("weapon", replaced_weapon)
	game._calamity_target_override = func(): return target
	await game._try_calamity_transfer(source)
	game._calamity_target_override = Callable()
	check(target.get_equipment_card("weapon") == calamity and source.get_weapon() == -1, "灾厄剑向目标转移同一对象")
	check(game.deck._discard.count(replaced_weapon) == 1, "灾厄剑顶掉的旧武器原实例弃置一次")
	await check_calamity_transfer_ownership()

	suite.reset_players()
	game.deck._discard.clear()
	source = game.players[1]
	target = game.players[2]
	var mule = CardBase.create(CardData.CardSubType.MULE_MINUS)
	mule.source_seat = 8
	source.equip_mount_card(mule)
	var replaced_mount = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	target.equip_mount_card(replaced_mount)
	for i in range(3):
		target.equip_mount_card(CardBase.create(CardData.CardSubType.MOUNT_MINUS))
	game._minus_mule_target_override = func(): return target
	await game._try_mule_transfer(source, CardData.CardSubType.MULE_MINUS, true)
	game._minus_mule_target_override = Callable()
	check(target.get_equipment_card("mount_1") == mule and mule.source_seat == 8, "劣马转移与满槽顶替保留原实例")
	check(game.deck._discard.count(replaced_mount) == 1 and source.get_mount_slots().is_empty(), "满槽目标被顶坐骑原实例弃置一次")
	await check_mule_transfer_ownership()

	# DEV-B01a：只验证现有暗置占位兼容路径的所有权，不裁定暗置牌离区明置规则。
	for mule_sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
		suite.reset_players()
		game.deck._discard.clear()
		for player in game.players:
			player.hidden_equip_slot = ""
			player.mount_plus = 0
			player.mount_minus = 0
		source = game.players[1]
		target = game.players[2]
		mule = CardBase.create(mule_sub)
		mule.source_seat = 9
		source.equip_mount_card(mule)
		target.equipment["mount_1"] = CardData.CardSubType.HIDDEN_EQUIPMENT
		target.hidden_equip_slot = "mount_1"
		for i in range(3):
			target.equip_mount_card(CardBase.create(CardData.CardSubType.MOUNT_MINUS))
		game._minus_mule_target_override = func(): return target
		game._plus_mule_target_override = func(): return target
		await game._try_mule_transfer(source, mule_sub, mule_sub == CardData.CardSubType.MULE_MINUS)
		game._minus_mule_target_override = Callable()
		game._plus_mule_target_override = Callable()
		check(target.get_equipment_card("mount_1") == mule and mule.source_seat == 9, "暗置首槽满马转移保留劣马原对象")
		check(source.get_mount_slots().is_empty(), "替掉暗置成功后来源不恢复同一张劣马")
		var owners := 0
		for player in game.players:
			for stored in player.equipment_cards.values():
				if stored == mule:
					owners += 1
		check(owners == 1 and game.deck._discard.is_empty(), "转移坐骑恰好一个装备所有者且不伪造旧牌弃置")
		check(target.hidden_equip_slot == "" and target.mount_count() == 4 and target.mount_minus == 3, "成功替换清暗置状态并保留其他三匹坐骑")

	# 无旧牌的成功与非法输入失败不能继续共享 null 这一种结果。
	suite.reset_players()
	target = game.players[2]
	target.hidden_equip_slot = "mount_1"
	target.equipment["mount_1"] = CardData.CardSubType.HIDDEN_EQUIPMENT
	var invalid = target.replace_mount_card_result("mount_1", CardBase.create(CardData.CardSubType.PEACH))
	check(not invalid.success and invalid.replaced_card == null, "非坐骑输入明确报告失败")
	check(target.get_hidden_equip_type() == "mount", "非法替换不移除原暗置")
	invalid = target.replace_mount_card_result("mount_2", CardBase.create(CardData.CardSubType.MOUNT_PLUS))
	check(not invalid.success and not target.equipment.has("mount_2"), "替换空槽失败且不安装新牌")
	invalid = target.replace_mount_card_result("mount_1", null)
	check(not invalid.success and target.has_hidden_equip(), "空输入失败且保留原占位")
	var incoming = CardBase.create(CardData.CardSubType.MULE_PLUS)
	var changed = target.replace_mount_card_result("mount_1", incoming)
	check(changed.success and changed.replaced_card == null, "替掉暗置明确成功但没有具体旧牌")
	check(target.get_equipment_card("mount_1") == incoming, "成功结果对应已落位的原资源")
	var next_mount = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
	changed = target.replace_mount_card_result("mount_1", next_mount)
	check(changed.success and changed.replaced_card == incoming, "替掉明置装备返回旧牌原对象")
	check(target.get_equipment_card("mount_1") == next_mount, "替换后新原对象仅在目标槽")
	await check_active_mount_replace()
	await check_active_weapon_armor_replace()
	await check_first_sao_hide_resource()
	await check_hidden_dismantle_resource()
	await check_hidden_snatch_declaration()
	await check_hidden_snatch_default_declaration()
	await check_hidden_death_and_disarm()
	suite.reset_players()
	for player in game.players:
		player.hidden_equip_slot = ""
		player.hidden_equip_card = null
		player.mount_plus = 0
		player.mount_minus = 0

func check_calamity_transfer_ownership():
	# DEV-B01c-1：等待目标选择期间，原牌可能已离开或来源改装；不可因此丢弃目标装备。
	for is_weapon in [true, false]:
		var slot = "weapon" if is_weapon else "armor"
		var original_sub = CardData.CardSubType.CALAMITY_SWORD if is_weapon else CardData.CardSubType.CALAMITY_ROBE
		var replacement_sub = CardData.CardSubType.QINGLONG_BLADE if is_weapon else CardData.CardSubType.RENWANG_DUN
		var target_sub = CardData.CardSubType.GUDING_BLADE if is_weapon else CardData.CardSubType.QIXING_PAO
		var label = "灾厄剑" if is_weapon else "灾厄袍"
		var source = game.players[1]
		var target = game.players[2]

		suite.reset_players()
		game.deck._discard.clear()
		var original = CardBase.create(original_sub)
		var target_card = CardBase.create(target_sub)
		source.equip_card_to_slot(slot, original)
		target.equip_card_to_slot(slot, target_card)
		if is_weapon:
			game._calamity_target_override = func(): return "cancel"
			await game._try_calamity_transfer(source)
			game._calamity_target_override = Callable()
		else:
			game._calamity_robe_target_override = func(): return "cancel"
			await game._try_calamity_robe_transfer(source)
			game._calamity_robe_target_override = Callable()
		check(source.get_equipment_card(slot) == original and target.get_equipment_card(slot) == target_card
			and game.deck._discard.is_empty(), label + "取消时双方装备原对象不动")

		# 旧目标答复到达前，来源原牌进入已确定手牌、同槽换上另一件装备。
		var replacement = CardBase.create(replacement_sub)
		var move_source = func():
			var moved = source.remove_equipment(slot)
			source.determined_cards.append(moved)
			source.equip_card_to_slot(slot, replacement)
			return target
		if is_weapon:
			game._calamity_target_override = move_source
			await game._try_calamity_transfer(source)
			game._calamity_target_override = Callable()
		else:
			game._calamity_robe_target_override = move_source
			await game._try_calamity_robe_transfer(source)
			game._calamity_robe_target_override = Callable()
		check(source.get_equipment_card(slot) == replacement and source.determined_cards == [original],
			label + "原牌离区后不转走后来换上的装备")
		check(target.get_equipment_card(slot) == target_card and game.deck._discard.is_empty(),
			label + "过期目标答复不弃目标原装备或制造弃牌")

		# 下一次合法转移仍沿同一原实例正常执行，目标旧牌只弃一次。
		suite.reset_players()
		game.deck._discard.clear()
		original = CardBase.create(original_sub)
		target_card = CardBase.create(target_sub)
		source.equip_card_to_slot(slot, original)
		target.equip_card_to_slot(slot, target_card)
		if is_weapon:
			game._calamity_target_override = func(): return target
			await game._try_calamity_transfer(source)
			game._calamity_target_override = Callable()
		else:
			game._calamity_robe_target_override = func(): return target
			await game._try_calamity_robe_transfer(source)
			game._calamity_robe_target_override = Callable()
		check(target.get_equipment_card(slot) == original and source.get_equipment_card(slot) == null,
			label + "下一次合法转移保持原对象且来源不再持有")
		check(game.deck._discard == [target_card], label + "目标旧装备只入弃牌堆一次")

func check_mule_transfer_ownership():
	# DEV-B01c-2：目标选择期间换上同名劣马，旧答复不能转移后来者。
	for mule_sub in [CardData.CardSubType.MULE_MINUS, CardData.CardSubType.MULE_PLUS]:
		var label = "-1劣马" if mule_sub == CardData.CardSubType.MULE_MINUS else "+1劣马"
		var source = game.players[1]
		var target = game.players[2]
		suite.reset_players()
		game.deck._discard.clear()
		for player in game.players:
			player.hidden_equip_slot = ""
			player.mount_plus = 0
			player.mount_minus = 0
		var original = CardBase.create(mule_sub)
		var target_card = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		source.equip_mount_card(original)
		target.equip_mount_card(target_card)
		if mule_sub == CardData.CardSubType.MULE_MINUS:
			game._minus_mule_target_override = func(): return "cancel"
		else:
			game._plus_mule_target_override = func(): return "cancel"
		await game._try_mule_transfer(source, mule_sub, mule_sub == CardData.CardSubType.MULE_MINUS)
		game._minus_mule_target_override = Callable()
		game._plus_mule_target_override = Callable()
		check(source.get_equipment_card("mount_1") == original and target.get_equipment_card("mount_1") == target_card
			and game.deck._discard.is_empty(), label + "取消时双方原牌不动")

		var replacement = CardBase.create(mule_sub)
		var move_source = func():
			source.determined_cards.append(source.remove_equipment("mount_1"))
			source.equip_card_to_slot("mount_1", replacement)
			return target
		if mule_sub == CardData.CardSubType.MULE_MINUS:
			game._minus_mule_target_override = move_source
		else:
			game._plus_mule_target_override = move_source
		await game._try_mule_transfer(source, mule_sub, mule_sub == CardData.CardSubType.MULE_MINUS)
		game._minus_mule_target_override = Callable()
		game._plus_mule_target_override = Callable()
		check(source.get_equipment_card("mount_1") == replacement and source.determined_cards == [original],
			label + "旧原牌离区后不转走同名替换牌")
		check(target.get_equipment_card("mount_1") == target_card and game.deck._discard.is_empty(),
			label + "过期答复不动目标坐骑或弃牌")

		# 紧接着合法转移：满四槽已有实体旧牌，转移后恰好一个装备所有者。
		for i in range(3):
			target.equip_mount_card(CardBase.create(CardData.CardSubType.MOUNT_MINUS))
		if mule_sub == CardData.CardSubType.MULE_MINUS:
			game._minus_mule_target_override = func(): return target
		else:
			game._plus_mule_target_override = func(): return target
		await game._try_mule_transfer(source, mule_sub, mule_sub == CardData.CardSubType.MULE_MINUS)
		game._minus_mule_target_override = Callable()
		game._plus_mule_target_override = Callable()
		var owners := 0
		for player in game.players:
			for stored in player.equipment_cards.values():
				if stored == replacement:
					owners += 1
		check(owners == 1 and source.get_mount_slots().is_empty() and target.get_equipment_card("mount_1") == replacement,
			label + "下一次合法满槽转移只保留一个原牌所有者")
		check(game.deck._discard == [target_card] and target.mount_count() == 4 and target.mount_plus == 0,
			label + "满槽转移只弃目标旧牌并同步计数")

func check_equip_pick_ownership():
	# DEV-B01c-3：拆/顺选中装备槽后，不把等待中换上的同名实体当成原目标。
	for is_snatch in [true, false]:
		suite.reset_players()
		game.deck._discard.clear()
		var attacker = game.players[0]
		var target = game.players[1]
		target.mount_plus = 0
		var label = "顺手牵羊" if is_snatch else "过河拆桥"
		var original = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		original.source_seat = 3
		var replacement = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		replacement.source_seat = 4
		target.equip_card_to_slot("mount_1", original)

		game._equip_pick_override = func(): return "cancel"
		await game._steal_equip(attacker, target, is_snatch, label)
		game._equip_pick_override = Callable()
		check(target.get_equipment_card("mount_1") == original and attacker.determined_cards.is_empty()
			and game.deck._discard.is_empty(), label + "取消选装备不移动原对象")

		var replace_during_pick = func():
			target.determined_cards.append(target.remove_equipment("mount_1"))
			target.equip_card_to_slot("mount_1", replacement)
			return "mount_1"
		game._equip_pick_override = replace_during_pick
		await game._steal_equip(attacker, target, is_snatch, label)
		game._equip_pick_override = Callable()
		check(target.get_equipment_card("mount_1") == replacement and target.determined_cards == [original]
			and target.mount_plus == 1,
			label + "旧装备离槽后不处理同名后来者")
		check(attacker.determined_cards.is_empty() and game.deck._discard.is_empty(),
			label + "过期槽位答复不错误转移或弃牌")

		game._equip_pick_override = func(): return "mount_1"
		await game._steal_equip(attacker, target, is_snatch, label)
		game._equip_pick_override = Callable()
		check(target.get_equipment_card("mount_1") == null and target.determined_cards == [original]
			and target.mount_plus == 0,
			label + "下一次合法选择移出当前装备且保留旧原牌")
		if is_snatch:
			check(attacker.determined_cards == [replacement] and game.deck._discard.is_empty(),
				"顺手牵羊只获得当次选中的原对象")
		else:
			check(attacker.determined_cards.is_empty() and game.deck._discard == [replacement],
				"过河拆桥只弃当次选中的原对象一次")

func check_active_mount_replace():
	# DEV-B01c-4：真实出牌入口分别用任意手牌与已具体化坐骑。
	var previous_phase = game.turn_manager.current_phase
	for concrete in [false, true]:
		suite.reset_players()
		game.deck._discard.clear()
		game._clear_pending_determined_card()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		var p = game.players[0]
		p.mount_plus = 0
		p.mount_minus = 0
		var old_mount = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		var replacement = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		p.equip_mount_card(old_mount)
		for i in range(3):
			p.equip_mount_card(CardBase.create(CardData.CardSubType.MOUNT_MINUS))
		var incoming: CardBase = null
		if concrete:
			incoming = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
			incoming.source_seat = 6
			p.determined_cards.append(incoming)
			game._pending_determined_card = incoming
		else:
			p.hand.append(null)
		var label = "具体牌" if concrete else "任意牌"

		game._mount_replace_override = func(): return "cancel"
		await game.play_card(CardData.CardSubType.MOUNT_MINUS)
		check(p.get_equipment_card("mount_1") == old_mount and game.deck._discard.is_empty()
			and (p.determined_cards.has(incoming) if concrete else p.hand == [null]),
			label + "取消满槽替换不支付或移动原牌")

		var change_during_pick = func():
			p.determined_cards.append(p.remove_equipment("mount_1"))
			p.equip_card_to_slot("mount_1", replacement)
			return "mount_1"
		game._mount_replace_override = change_during_pick
		await game.play_card(CardData.CardSubType.MOUNT_MINUS)
		check(p.get_equipment_card("mount_1") == replacement and p.determined_cards.has(old_mount)
			and p.mount_plus == 1 and p.mount_minus == 3 and game.deck._discard.is_empty(),
			label + "旧槽位换上同名马后不误顶后来者")
		check((p.determined_cards.has(incoming) and game._pending_determined_card == incoming) if concrete else p.hand == [null],
			label + "过期选择不消耗具体牌或任意牌")

		game._mount_replace_override = func(): return "mount_9"
		await game.play_card(CardData.CardSubType.MOUNT_MINUS)
		check(p.get_equipment_card("mount_1") == replacement and game.deck._discard.is_empty()
			and (p.determined_cards.has(incoming) if concrete else p.hand == [null]),
			label + "非法槽位答复不扣牌且不访问错误槽位")

		game._mount_replace_override = func(): return "mount_1"
		await game.play_card(CardData.CardSubType.MOUNT_MINUS)
		var equipped = p.get_equipment_card("mount_1")
		check(equipped != null and equipped.sub_type == CardData.CardSubType.MOUNT_MINUS
			and (equipped == incoming if concrete else p.hand.is_empty()),
			label + "下一次合法替换按原牌或任意牌具体化落位")
		check(game.deck._discard == [replacement] and p.determined_cards.has(old_mount)
			and p.mount_count() == 4 and p.mount_plus == 0 and p.mount_minus == 4,
			label + "成功只弃所选旧坐骑一次并同步四槽计数")
		game._mount_replace_override = Callable()
		game._clear_pending_determined_card()
	game.turn_manager.current_phase = previous_phase

func check_active_weapon_armor_replace():
	# DEV-B01c-5：武器/防具确认后的旧答复不能弃掉原槽后来换上的装备。
	var previous_phase = game.turn_manager.current_phase
	for slot in ["weapon", "armor"]:
		var old_sub = CardData.CardSubType.LIANNU if slot == "weapon" else CardData.CardSubType.SILVER_LION
		var later_sub = CardData.CardSubType.ZHUGE_LIANNU if slot == "weapon" else CardData.CardSubType.QIXING_PAO
		var incoming_sub = CardData.CardSubType.QINGLONG_BLADE if slot == "weapon" else CardData.CardSubType.RENWANG_DUN
		for concrete in [false, true]:
			suite.reset_players()
			game.deck._discard.clear()
			game.equipment_pool.clear()
			game._clear_pending_determined_card()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var p = game.players[0]
			var old_card = CardBase.create(old_sub)
			var later_card = CardBase.create(later_sub)
			p.equip_card_to_slot(slot, old_card)
			var incoming: CardBase = null
			if concrete:
				incoming = CardBase.create(incoming_sub)
				incoming.source_seat = 6
				p.determined_cards.append(incoming)
				game._pending_determined_card = incoming
			else:
				p.hand.append(null)
			var label = ("武器" if slot == "weapon" else "防具") + ("具体牌" if concrete else "任意牌")

			game._weapon_replace_override = func(): return false
			await game.play_card(incoming_sub)
			check(p.get_equipment_card(slot) == old_card and game.deck._discard.is_empty()
				and (p.determined_cards.has(incoming) if concrete else p.hand == [null]),
				label + "拒绝替换保留原装备和待出牌")

			var expire_context = func():
				game.turn_manager.current_phase = TurnManager.Phase.DISCARD
				game.turn_manager.current_phase = TurnManager.Phase.PLAY
				return true
			game._weapon_replace_override = expire_context
			await game.play_card(incoming_sub)
			check(p.get_equipment_card(slot) == old_card and game.deck._discard.is_empty()
				and (p.determined_cards.has(incoming) if concrete else p.hand == [null]),
				label + "阶段离开再返回不接受旧确认")

			var change_during_confirm = func():
				p.determined_cards.append(p.remove_equipment(slot))
				p.equip_card_to_slot(slot, later_card)
				return true
			game._weapon_replace_override = change_during_confirm
			await game.play_card(incoming_sub)
			check(p.get_equipment_card(slot) == later_card and p.determined_cards.has(old_card)
				and game.deck._discard.is_empty(), label + "原装备离槽后不弃后来换上的装备")
			check((p.determined_cards.has(incoming) and game._pending_determined_card == incoming) if concrete else p.hand == [null],
				label + "原槽过期不消耗任意或具体牌")

			game._weapon_replace_override = func(): return true
			await game.play_card(incoming_sub)
			var equipped = p.get_equipment_card(slot)
			check(equipped != null and equipped.sub_type == incoming_sub
				and (equipped == incoming if concrete else p.hand.is_empty()),
				label + "下一次有效确认才装备声明的原对象")
			check(game.deck._discard == [later_card] and p.determined_cards.has(old_card)
				and game.equipment_pool.is_claimed(incoming_sub),
				label + "成功后只弃当前旧装备一次并登记新装备")
			game._weapon_replace_override = Callable()
			game._clear_pending_determined_card()
	game.turn_manager.current_phase = previous_phase

func check_first_sao_hide_resource():
	# DEV-B02a：首次暗置从真实手牌支付；明置沿用同一资源，不多造装备。
	var previous_phase = game.turn_manager.current_phase
	for concrete in [false, true]:
		suite.reset_players()
		game.deck._discard.clear()
		game.equipment_pool.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		var p = game.players[0]
		p.general_name = "安普提·斯丢皮得"
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null
		var source: CardBase = null
		if concrete:
			source = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
			source.source_seat = 7
			p.determined_cards.append(source)
		else:
			p.hand.append(null)
		var label = "具体牌" if concrete else "任意牌"
		game._sao_type_override = func(): return "cancel"
		await game._do_sao_hide(p, false)
		check(not p.has_hidden_equip() and p.hand_size() == 1, label + "取消不支付、不占槽")
		var expire_choice = func():
			game.turn_manager.current_phase = TurnManager.Phase.DISCARD
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			return "weapon"
		game._sao_type_override = expire_choice
		await game._do_sao_hide(p, false)
		check(not p.has_hidden_equip() and p.hand_size() == 1, label + "阶段离开再返回不接受旧暗置选择")
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(p, false)
		var hidden = p.hidden_equip_card
		check(p.has_hidden_equip() and p.hand_size() == 0 and p.equipment.get("weapon") == CardData.CardSubType.HIDDEN_EQUIPMENT,
			label + "成功暗置恰好支付一张并占一槽")
		check(hidden != null and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
			and hidden.hidden_category == "weapon" and (hidden == source if concrete else true),
			label + "暗置保留原资源且不公开具体名称")
		check(not game._reveal_hidden_as(p, CardData.CardSubType.RENWANG_DUN)
			and p.hidden_equip_card == hidden and p.get_hidden_equip_type() == "weapon",
			label + "武器暗置不能跨类别声明防具")
		await game._do_sao_hide(p, true)
		check(p.hidden_equip_card == hidden and p.hand_size() == 0,
			label + "旧替换入口不能把武器暗置改成其他类别")
		game._sao_reveal_sub_override = func(): return CardData.CardSubType.QINGLONG_BLADE if concrete else CardData.CardSubType.LIANNU
		await game._do_sao_reveal(p)
		check(not p.has_hidden_equip() and p.get_equipment_card("weapon") == hidden
			and p.hand_size() == 0 and game.deck._discard.is_empty(), label + "明置沿用原资源不复制或多扣手牌")
		if concrete:
			check(hidden != null and hidden.source_seat == 7 and hidden.sub_type == CardData.CardSubType.QINGLONG_BLADE,
				"具体牌明置后名称和来源不变")
		p.remove_equipment("weapon")
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(p, false)
		check(not p.has_hidden_equip() and p.hand_size() == 0, label + "零手牌不能免费再次暗置")
	game._sao_type_override = Callable()
	game._sao_reveal_sub_override = Callable()
	game.turn_manager.current_phase = previous_phase

func check_hidden_dismantle_resource():
	# DEV-B02b-1：拆暗置仍弃暗置原对象，旧选槽答复不能拆后来换上的同槽资源。
	var previous_phase = game.turn_manager.current_phase
	for concrete in [false, true]:
		suite.reset_players()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		var attacker = game.players[0]
		var target = game.players[1]
		target.general_name = "安普提·斯丢皮得"
		target.hidden_equip_slot = ""
		target.hidden_equip_card = null
		var source: CardBase = null
		if concrete:
			source = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
			source.source_seat = 5
			target.determined_cards.append(source)
		else:
			target.hand.append(null)
		game.turn_manager.current_player_idx = 1
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(target, false)
		game._sao_type_override = Callable()
		game.turn_manager.current_player_idx = 0
		var first = target.hidden_equip_card
		var label = "具体牌" if concrete else "任意牌"
		check(first != null and (first == source if concrete else true) and target.hand_size() == 0,
			label + "暗置来源已支付并保留原对象")
		game._equip_pick_override = func(): return "cancel"
		await game._steal_equip(attacker, target, false, "过河拆桥")
		check(target.hidden_equip_card == first and game.deck._discard.is_empty(), label + "取消拆牌不移动暗置资源")
		var second = CardBase.create(CardData.CardSubType.QINGLONG_BLADE if concrete else CardData.CardSubType.HIDDEN_EQUIPMENT)
		if concrete:
			second.hidden_original_sub_type = second.sub_type
			second.sub_type = CardData.CardSubType.HIDDEN_EQUIPMENT
			second.card_name = CardData.get_type_name(second.sub_type)
			second.source_seat = 6
		second.hidden_category = "weapon"
		var change_during_pick = func():
			target.determined_cards.append(target.remove_equipment("weapon"))
			target.equipment["weapon"] = CardData.CardSubType.HIDDEN_EQUIPMENT
			target.hidden_equip_slot = "weapon"
			target.hidden_equip_card = second
			return "weapon"
		game._equip_pick_override = change_during_pick
		await game._steal_equip(attacker, target, false, "过河拆桥")
		check(target.hidden_equip_card == second and target.determined_cards == [first]
			and game.deck._discard.is_empty(), label + "旧选择不弃同槽后来暗置的另一原对象")
		game._equip_pick_override = func(): return "weapon"
		await game._steal_equip(attacker, target, false, "过河拆桥")
		check(not target.has_hidden_equip() and game.deck._discard == [second]
			and second.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT and second.hidden_category == "weapon"
			and (second.source_seat == 6 and second.hidden_original_sub_type == CardData.CardSubType.QINGLONG_BLADE if concrete else true),
			label + "下一次有效拆牌只弃当前暗置原对象一次且仍为暗置")
		game._equip_pick_override = Callable()
	game.turn_manager.current_phase = previous_phase

func check_hidden_snatch_declaration():
	# DEV-B02b-2：顺走后由原持有者声明，不能凭后来者答复改写已转走的原牌。
	var previous_phase = game.turn_manager.current_phase
	for concrete in [false, true]:
		suite.reset_players()
		game.equipment_pool.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		var attacker = game.players[0]
		var target = game.players[1]
		target.general_name = "安普提·斯丢皮得"
		target.hidden_equip_slot = ""
		target.hidden_equip_card = null
		var original: CardBase = null
		if concrete:
			original = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
			original.source_seat = 7
			target.determined_cards.append(original)
		else:
			target.hand.append(null)
		game.turn_manager.current_player_idx = 1
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(target, false)
		game._sao_type_override = Callable()
		game.turn_manager.current_player_idx = 0
		var hidden = target.hidden_equip_card
		var label = "具体来源" if concrete else "任意来源"
		game._equip_pick_override = func(): return "cancel"
		await game._steal_equip(attacker, target, true, "顺手牵羊")
		check(target.hidden_equip_card == hidden and attacker.determined_cards.is_empty(), label + "取消选槽不转移")
		game._equip_pick_override = func(): return "weapon"
		game._sao_transfer_declare_override = func(): return CardData.CardSubType.QINGLONG_BLADE
		await game._steal_equip(attacker, target, true, "顺手牵羊")
		check(not target.has_hidden_equip() and attacker.determined_cards == [hidden]
			and hidden.sub_type == CardData.CardSubType.QINGLONG_BLADE
			and hidden.hidden_category == "" and game.equipment_pool.is_claimed(CardData.CardSubType.QINGLONG_BLADE)
			and (hidden == original and hidden.source_seat == 7 if concrete else true),
			label + "顺走后原持有者声明，保留原对象与来源")
		game._sao_transfer_declare_override = Callable()
		game._equip_pick_override = Callable()

	# 全部武器已出场：顺走成功，但不能重命名，也不能吞掉这张暗置牌。
	suite.reset_players()
	game.equipment_pool.clear()
	var attacker = game.players[0]
	var target = game.players[1]
	target.general_name = "安普提·斯丢皮得"
	target.hidden_equip_slot = ""
	target.hidden_equip_card = null
	target.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(target, false)
	game._sao_type_override = Callable()
	game.turn_manager.current_player_idx = 0
	var hidden = target.hidden_equip_card
	for sub in game.SAO_WEAPON_SUBS:
		game.equipment_pool.claim(sub)
	game._equip_pick_override = func(): return "weapon"
	await game._steal_equip(attacker, target, true, "顺手牵羊")
	check(not target.has_hidden_equip() and attacker.determined_cards == [hidden]
		and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT and hidden.hidden_category == "weapon",
		"武器名称耗尽仍转移原牌且继续暗置")
	game._equip_pick_override = Callable()

	# 声明窗口中原牌离开接收者；旧答复不得明置它或占用唯一名称。
	suite.reset_players()
	game.equipment_pool.clear()
	attacker = game.players[0]
	target = game.players[1]
	target.general_name = "安普提·斯丢皮得"
	target.hidden_equip_slot = ""
	target.hidden_equip_card = null
	target.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(target, false)
	game._sao_type_override = Callable()
	game.turn_manager.current_player_idx = 0
	hidden = target.hidden_equip_card
	game._equip_pick_override = func(): return "weapon"
	game._sao_transfer_declare_override = func():
		attacker.determined_cards.erase(hidden)
		target.determined_cards.append(hidden)
		return CardData.CardSubType.QINGLONG_BLADE
	await game._steal_equip(attacker, target, true, "顺手牵羊")
	check(target.determined_cards == [hidden] and attacker.determined_cards.is_empty()
		and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
		and not game.equipment_pool.is_claimed(CardData.CardSubType.QINGLONG_BLADE),
		"声明期间原牌再次转移，过期答复不改牌或占名")
	game._sao_transfer_declare_override = Callable()
	game._equip_pick_override = Callable()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase

func check_hidden_snatch_default_declaration():
	# DEV-B02b-2b：只有原持有者取消/超时才使用默认名称，具体原牌仍保原名。
	var previous_phase = game.turn_manager.current_phase
	for category in ["weapon", "armor", "mount"]:
		for concrete in [false, true]:
			suite.reset_players()
			game.equipment_pool.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var attacker = game.players[0]
			var target = game.players[1]
			target.general_name = "安普提·斯丢皮得"
			target.hidden_equip_slot = ""
			target.hidden_equip_card = null
			var original_sub = CardData.CardSubType.QINGLONG_BLADE
			match category:
				"armor": original_sub = CardData.CardSubType.RENWANG_DUN
				"mount": original_sub = CardData.CardSubType.MOUNT_PLUS
			var original: CardBase = null
			if concrete:
				original = CardBase.create(original_sub)
				original.source_seat = 8
				target.determined_cards.append(original)
			else:
				target.hand.append(null)
			game.turn_manager.current_player_idx = 1
			game._sao_type_override = func(): return category
			await game._do_sao_hide(target, false)
			game._sao_type_override = Callable()
			var hidden = target.hidden_equip_card
			var slot = target.hidden_equip_slot
			game.turn_manager.current_player_idx = 0
			game._equip_pick_override = func(): return slot
			game._sao_transfer_declare_override = func(): return -1
			await game._steal_equip(attacker, target, true, "顺手牵羊")
			var expected = original_sub if concrete else (CardData.CardSubType.CALAMITY_SWORD if category == "weapon" else CardData.CardSubType.CALAMITY_ROBE)
			var correct_name = hidden.sub_type == expected if concrete or category != "mount" else \
				(hidden.sub_type == CardData.CardSubType.MULE_MINUS or hidden.sub_type == CardData.CardSubType.MULE_PLUS)
			check(not target.has_hidden_equip() and attacker.determined_cards == [hidden]
				and correct_name and hidden.hidden_category == ""
				and (hidden == original and hidden.source_seat == 8 if concrete else true),
				category + ("具体原牌" if concrete else "任意来源") + "取消声明后正确默认且保原对象")
			game._equip_pick_override = Callable()
			game._sao_transfer_declare_override = Callable()

	# 默认灾厄剑已占用：只能从尚可声明的其他武器名中选，不重复占名。
	suite.reset_players()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	var attacker = game.players[0]
	var target = game.players[1]
	target.general_name = "安普提·斯丢皮得"
	target.hidden_equip_slot = ""
	target.hidden_equip_card = null
	target.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(target, false)
	game._sao_type_override = Callable()
	var hidden = target.hidden_equip_card
	game.equipment_pool.claim(CardData.CardSubType.CALAMITY_SWORD)
	game.turn_manager.current_player_idx = 0
	game._equip_pick_override = func(): return "weapon"
	game._sao_transfer_declare_override = func(): return -1
	await game._steal_equip(attacker, target, true, "顺手牵羊")
	check(attacker.determined_cards == [hidden] and game.SAO_WEAPON_SUBS.has(hidden.sub_type)
		and hidden.sub_type != CardData.CardSubType.CALAMITY_SWORD
		and game.equipment_pool.is_claimed(hidden.sub_type),
		"灾厄剑已占用时从剩余武器名中默认声明")
	game._equip_pick_override = Callable()
	game._sao_transfer_declare_override = Callable()

	# 取消答复到达前原牌又离开取得者，不能用默认名改写失效对象。
	suite.reset_players()
	game.equipment_pool.clear()
	attacker = game.players[0]
	target = game.players[1]
	target.general_name = "安普提·斯丢皮得"
	target.hidden_equip_slot = ""
	target.hidden_equip_card = null
	target.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(target, false)
	game._sao_type_override = Callable()
	hidden = target.hidden_equip_card
	game.turn_manager.current_player_idx = 0
	game._equip_pick_override = func(): return "weapon"
	game._sao_transfer_declare_override = func():
		attacker.determined_cards.erase(hidden)
		target.determined_cards.append(hidden)
		return -1
	await game._steal_equip(attacker, target, true, "顺手牵羊")
	check(attacker.determined_cards.is_empty() and target.determined_cards == [hidden]
		and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
		and not game.equipment_pool.is_claimed(CardData.CardSubType.CALAMITY_SWORD),
		"过期取消答复不触发默认声明或占名")
	game._equip_pick_override = Callable()
	game._sao_transfer_declare_override = Callable()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase

func check_hidden_death_and_disarm():
	# DEV-B02b-3：真实卸甲入口按实际弃置件数摸牌；最终死亡清理仍弃暗置原对象。
	var previous_phase = game.turn_manager.current_phase
	for concrete in [false, true]:
		suite.reset_players()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game.turn_manager.disarm_count_this_turn = 0
		var actor = game.players[0]
		var target = game.players[1]
		target.general_name = "安普提·斯丢皮得"
		target.hidden_equip_slot = ""
		target.hidden_equip_card = null
		var original: CardBase = null
		if concrete:
			original = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
			original.source_seat = 8
			target.determined_cards.append(original)
		else:
			target.hand.append(null)
		game.turn_manager.current_player_idx = 1
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(target, false)
		game._sao_type_override = Callable()
		var hidden = target.hidden_equip_card
		var armor = CardBase.create(CardData.CardSubType.RENWANG_DUN)
		check(target.equip_card_to_slot("armor", armor), "卸甲前可装备普通防具")
		actor.hand.append(null)
		game.turn_manager.current_player_idx = 0
		await game._play_disarm()
		var label = "具体来源" if concrete else "任意来源"
		check(target.equipment.is_empty() and target.hidden_equip_card == null
			and game.deck._discard.count(hidden) == 1 and game.deck._discard.count(armor) == 1
			and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
			and (hidden == original and hidden.source_seat == 8 if concrete else true),
			label + "卸甲只弃暗置原对象一次且不明置")
		check(target.hand_size() == 2, label + "卸甲确实弃两件才摸两张")
		var after_first = target.hand_size()
		await game._play_disarm()
		check(target.hand_size() == after_first and game.deck._discard.count(hidden) == 1,
			label + "同回合再次卸甲不重复弃或摸")

		suite.reset_players()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		target = game.players[1]
		target.general_name = "安普提·斯丢皮得"
		target.hidden_equip_slot = ""
		target.hidden_equip_card = null
		if concrete:
			original = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
			original.source_seat = 9
			target.determined_cards.append(original)
		else:
			target.hand.append(null)
		game.turn_manager.current_player_idx = 1
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(target, false)
		game._sao_type_override = Callable()
		hidden = target.hidden_equip_card
		target.hp = 0
		target.reset_death_state()
		game._handle_death(target, null)
		check(target.is_dead() and not target.has_hidden_equip() and target.hidden_equip_card == null
			and game.deck._discard.count(hidden) == 1 and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
			and (hidden == original and hidden.source_seat == 9 if concrete else true),
			label + "最终死亡后清暗置原牌一次，不提前明置")
	game.turn_manager.current_phase = previous_phase
