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
	await check_sao_active_hidden_slot_choice()
	await check_hidden_dismantle_resource()
	await check_hidden_snatch_declaration()
	await check_hidden_snatch_default_declaration()
	await check_hidden_death_and_disarm()
	await check_meiyong_one_empty_visible_slot()
	await check_meiyong_empty_mount_slots()
	await check_meiyong_one_hidden_to_empty()
	await check_meiyong_multiple_hidden_receiver()
	await check_hidden_name_exhaustion()
	await check_meiyong_hidden_visible_exchange()
	await check_meiyong_two_hidden_exchange()
	await check_meiyong_one_hidden_mount_to_empty()
	await check_meiyong_hidden_visible_mount_exchange()
	await _check_claimed_original_requip()
	await _check_claimed_original_hidden_declaration()
	await _check_claimed_original_hidden_exhaustion()
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

func check_sao_active_hidden_slot_choice():
	# DEV-B02b-4d：有【苕】者自主指定暗置槽位；旧单张兼容指针不得代替选择。
	for scenario in ["cancel", "select_armor", "stale_slot", "stale_name"]:
		suite.reset_players()
		game.equipment_pool.clear()
		game.deck._discard.clear()
		var owner = game.players[0]
		owner.hidden_equip_slot = ""
		owner.hidden_equip_card = null
		owner.general_name = "安普提·斯丢皮得"
		var weapon = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
		weapon.hidden_category = "weapon"
		var armor = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
		armor.hidden_category = "armor"
		check(owner.equip_hidden_card_to_slot("weapon", weapon)
			and owner.equip_hidden_card_to_slot("armor", armor), scenario + "：两槽各保存一张暗置原牌")
		game._sao_reveal_slot_override = func(slots):
			if scenario == "stale_slot":
				owner.remove_equipment("armor")
				var replacement = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
				replacement.hidden_category = "armor"
				owner.equip_hidden_card_to_slot("armor", replacement)
			return -1 if scenario == "cancel" else slots.find("armor")
		game._sao_reveal_sub_override = func():
			if scenario == "stale_name":
				owner.remove_equipment("armor")
				var replacement = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
				replacement.hidden_category = "armor"
				owner.equip_hidden_card_to_slot("armor", replacement)
			return CardData.CardSubType.RENWANG_DUN
		await game._do_sao_reveal(owner)
		if scenario == "select_armor":
			check(owner.get_equipment_card("armor") == armor
				and owner.get_hidden_equipment_card("weapon") == weapon
				and owner.hidden_equip_card == weapon,
				"主动指定防具只明置该原牌，武器仍暗置")
		else:
			check(owner.get_hidden_equipment_card("weapon") == weapon
				and owner.equipment.get("armor") == CardData.CardSubType.HIDDEN_EQUIPMENT
				and not game.equipment_pool.is_claimed(CardData.CardSubType.RENWANG_DUN),
				scenario + "：取消或过期答复不明置、不占名")
		game._sao_reveal_slot_override = Callable()
		game._sao_reveal_sub_override = Callable()

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

	# C-S4c：最后一个武器名被声明时，暗置牌先于后续顺走立刻入弃。
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
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
	for i in range(game.SAO_WEAPON_SUBS.size() - 1):
		game.equipment_pool.claim(game.SAO_WEAPON_SUBS[i])
	check(target.get_hidden_equipment_card("weapon") == hidden,
		"仍有一个武器名称时暗置原牌留在装备区")
	game._claim_equipment_name(game.SAO_WEAPON_SUBS[-1])
	check(not target.has_hidden_equip() and game.deck._discard.count(hidden) == 1
		and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT,
		"最后一个武器名称声明后原牌立即暗置入弃")
	game._equip_pick_override = func(): return "weapon"
	await game._steal_equip(attacker, target, true, "顺手牵羊")
	check(attacker.determined_cards.is_empty() and game.deck._discard.count(hidden) == 1,
		"名称耗尽后顺走不能取回已经消失的暗置原牌")
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

# DEV-B03a：占名后仅未弃置的同一原牌能再次装备，不能让任意牌再造同名。
func _check_claimed_original_requip():
	var previous_phase = game.turn_manager.current_phase
	for spec in [
		{"sub": CardData.CardSubType.LIANNU, "old": CardData.CardSubType.QINGLONG_BLADE, "slot": "weapon"},
		{"sub": CardData.CardSubType.RENWANG_DUN, "old": CardData.CardSubType.BAGUA_ZHEN, "slot": "armor"},
	]:
		suite.reset_players()
		game.equipment_pool.clear()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game._pending_determined_card = null
		var sub: CardData.CardSubType = spec.sub
		var slot: String = spec.slot
		var thief: Player = game.players[0]
		var first_owner: Player = game.players[1]
		var other: Player = game.players[2]
		first_owner.hand.append(null)
		game.turn_manager.current_player_idx = first_owner.seat_index
		await game.play_card(sub)
		var original: CardBase = first_owner.get_equipment_card(slot)
		check(original != null and game.equipment_pool.is_claimed_original(sub, original),
			"首次装备记录%s原牌" % slot)
		game._equip_pick_override = func(): return slot
		await game._steal_equip(thief, first_owner, true, "顺手牵羊")
		game._equip_pick_override = Callable()
		check(thief.determined_cards.has(original) and game.deck._discard.is_empty(),
			"顺走%s只转移原牌，不弃置" % slot)
		var old_card = CardBase.create(spec.old)
		check(thief.equip_card_to_slot(slot, old_card), "替换确认前已有另一%s" % slot)
		game.turn_manager.current_player_idx = thief.seat_index
		game._weapon_replace_override = func(): return false
		await game.play_card(sub)
		check(thief.get_equipment_card(slot) == old_card and thief.determined_cards.has(original),
			"取消替换%s不消耗被顺走的原牌" % slot)
		game._weapon_replace_override = func(): return true
		await game.play_card(sub)
		check(thief.get_equipment_card(slot) == original and not thief.determined_cards.has(original)
			and game.deck._discard.count(old_card) == 1,
			"被顺走的同一%s原牌可替换再装备" % slot)
		other.hand.append(null)
		game.turn_manager.current_player_idx = other.seat_index
		await game.play_card(sub)
		check(other.hand_size() == 1 and not other.equipment.has(slot),
			"另一玩家任意牌不能新造同名%s" % slot)
		game._equip_pick_override = func(): return slot
		await game._steal_equip(other, thief, false, "过河拆桥")
		game._equip_pick_override = Callable()
		check(not thief.equipment.has(slot) and game.deck._discard.count(original) == 1
			and not other.determined_cards.has(original),
			"过河拆桥拆掉重装的%s原牌，离槽且恰好弃置一次" % slot)
		# 防御性检查：正式流程不会从弃牌堆取回同一对象；模拟误回手后也不能再次使用。
		thief.determined_cards.append(original)
		game.turn_manager.current_player_idx = thief.seat_index
		await game.play_card(sub)
		check(thief.determined_cards.has(original) and not thief.equipment.has(slot),
			"弃置后的%s原牌即使误回手也不能再装备" % slot)
		game._weapon_replace_override = Callable()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game.turn_manager.current_phase = previous_phase

# DEV-B03b-1：已占名的同一原牌被顺走后暗置，仍可主动明置或离区声明原名。
func _check_claimed_original_hidden_declaration():
	var previous_phase = game.turn_manager.current_phase
	for spec in [
		{"sub": CardData.CardSubType.LIANNU, "slot": "weapon"},
		{"sub": CardData.CardSubType.RENWANG_DUN, "slot": "armor"},
	]:
		for path in ["active", "snatch", "exchange"]:
			suite.reset_players()
			game.equipment_pool.clear()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			var sub: CardData.CardSubType = spec.sub
			var slot: String = spec.slot
			var owner: Player = game.players[1]
			var sao: Player = game.players[0]
			var recipient: Player = game.players[2]
			sao.general_name = "安普提·斯丢皮得"
			owner.hand.append(null)
			game.turn_manager.current_player_idx = owner.seat_index
			await game.play_card(sub)
			var original: CardBase = owner.get_equipment_card(slot)
			game._equip_pick_override = func(): return slot
			await game._steal_equip(sao, owner, true, "顺手牵羊")
			game._equip_pick_override = Callable()
			game.turn_manager.current_player_idx = sao.seat_index
			game._sao_type_override = func(): return slot
			await game._do_sao_hide(sao, false)
			game._sao_type_override = Callable()
			check(original != null and sao.get_hidden_equipment_card(slot) == original
				and original.hidden_original_sub_type == sub and game.equipment_pool.is_claimed_original(sub, original),
				"%s%s：被顺走的唯一原牌暗置仍保留原名与对象" % [slot, path])
			var other_hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
			other_hidden.hidden_category = slot
			check(game._hidden_declaration_options(original).has(sub)
				and not game._hidden_declaration_options(other_hidden).has(sub),
				"%s%s：原牌保留已占名资格，另一任意暗置牌没有" % [slot, path])
			if path == "active":
				game._sao_reveal_sub_override = func(): return -1
				await game._do_sao_reveal(sao)
				check(sao.get_hidden_equipment_card(slot) == original and game.deck._discard.is_empty(),
					"%s主动取消不改变原牌" % slot)
				var later = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
				later.hidden_category = slot
				game._sao_reveal_sub_override = func():
					check(sao.remove_equipment(slot) == original
						and sao.equip_hidden_card_to_slot(slot, later), "%s选名等待中同槽暗置原牌已替换" % slot)
					sao.determined_cards.append(original)
					return sub
				await game._do_sao_reveal(sao)
				check(sao.get_hidden_equipment_card(slot) == later and sao.determined_cards.has(original)
					and later.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT,
					"%s过期答复不能替后来暗置牌声明已占名" % slot)
				check(sao.remove_equipment(slot) == later and sao.equip_hidden_card_to_slot(slot, original),
					"%s下一合法明置前同一原牌重新回槽" % slot)
				sao.determined_cards.erase(original)
				game._sao_reveal_sub_override = func(): return sub
				await game._do_sao_reveal(sao)
				game._sao_reveal_sub_override = Callable()
				check(sao.get_equipment_card(slot) == original and original.sub_type == sub
					and game.deck._discard.is_empty(), "%s已占名的原牌可主动明置" % slot)
			elif path == "snatch":
				game._sao_transfer_declare_override = func(): return sub
				await game._steal_equip(recipient, sao, true, "顺手牵羊")
				game._sao_transfer_declare_override = Callable()
				check(recipient.determined_cards.has(original) and original.sub_type == sub
					and game.equipment_pool.is_claimed_original(sub, original),
					"%s原持有者在再次顺走后仍可声明同一原名" % slot)
			else:
				check(game._swap_equip_slot(sao, slot, recipient, slot), "%s暗置原牌先交换到接收者" % slot)
				game._sao_transfer_declare_override = func(): return sub
				await game._declare_exchanged_hidden_equipment(sao, recipient, slot, original)
				game._sao_transfer_declare_override = Callable()
				check(recipient.get_equipment_card(slot) == original and original.sub_type == sub
					and game.equipment_pool.is_claimed_original(sub, original),
					"%s交换后由原持有者声明同一原名" % slot)
			var other: Player = game.players[3]
			other.hand.append(null)
			game.turn_manager.current_player_idx = other.seat_index
			await game.play_card(sub)
			check(other.hand_size() == 1 and not other.equipment.has(slot),
				"%s%s：原牌声明不准另一任意牌造同名" % [slot, path])
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game.turn_manager.current_phase = previous_phase

# DEV-B03b-2：原牌已声明过名字，也不能逃过C-S4c的同类名称耗尽清理。
func _check_claimed_original_hidden_exhaustion():
	var previous_phase = game.turn_manager.current_phase
	for spec in [
		{"sub": CardData.CardSubType.LIANNU, "slot": "weapon", "names": game.SAO_WEAPON_SUBS},
		{"sub": CardData.CardSubType.RENWANG_DUN, "slot": "armor", "names": game.SAO_ARMOR_SUBS},
	]:
		suite.reset_players()
		game.equipment_pool.clear()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		var original_sub: CardData.CardSubType = spec.sub
		var slot: String = spec.slot
		var names: Array = spec.names
		var last_sub: CardData.CardSubType = names[-1]
		var sao: Player = game.players[0]
		var first_owner: Player = game.players[1]
		var final_equipper: Player = game.players[2]
		sao.general_name = "安普提·斯丢皮得"
		first_owner.hand.append(null)
		game.turn_manager.current_player_idx = first_owner.seat_index
		await game.play_card(original_sub)
		var original: CardBase = first_owner.get_equipment_card(slot)
		game._equip_pick_override = func(): return slot
		await game._steal_equip(sao, first_owner, true, "顺手牵羊")
		game._equip_pick_override = Callable()
		game.turn_manager.current_player_idx = sao.seat_index
		game._sao_type_override = func(): return slot
		await game._do_sao_hide(sao, false)
		game._sao_type_override = Callable()
		check(sao.get_hidden_equipment_card(slot) == original
			and game.equipment_pool.is_claimed_original(original_sub, original),
			"%s原牌已占名后仍可暗置待明置" % slot)
		for sub in names:
			if sub != original_sub and sub != last_sub:
				game._claim_equipment_name(sub, CardBase.create(sub))
		check(sao.get_hidden_equipment_card(slot) == original and game.deck._discard.is_empty(),
			"%s尚余一个名称时已占名原牌仍暗置" % slot)
		final_equipper.hand.append(null)
		game.turn_manager.current_player_idx = final_equipper.seat_index
		game._sao_reveal_override = func(): return false
		await game.play_card(last_sub)
		game._sao_reveal_override = Callable()
		check(final_equipper.get_equipment_card(slot) != null
			and final_equipper.get_equipment_card(slot).sub_type == last_sub,
			"%s最后一个名称经真实出牌入口声明" % slot)
		check(sao.get_hidden_equipment_card(slot) == null and game.deck._discard.count(original) == 1
			and original.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT,
			"%s名称耗尽使已占名的暗置原牌立即暗置入弃一次" % slot)
		check(not game._can_declare_hidden_name(original, original_sub),
			"%s弃后的同一原牌不能再凭旧声明占名资格明置" % slot)
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game.turn_manager.current_phase = previous_phase

func check_meiyong_two_hidden_exchange():
	# DEV-B02b-4c-2b-ii-b：原牌先互换，随机选原持有者先声明；对方只能选剩余名称。
	var previous_phase = game.turn_manager.current_phase
	for zone in ["weapon", "armor"]:
		for a_first in [true, false]:
			suite.reset_players()
			game.equipment_pool.clear()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			game._lanzhonghou_used = false
			var actor = game.players[0]
			var a = game.players[1]
			var b = game.players[2]
			actor.general_name = "麦克斯·欧尼斯特"
			actor.hand.append(null)
			var hidden_a = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
			var hidden_b = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
			hidden_a.hidden_category = zone
			hidden_b.hidden_category = zone
			hidden_a.source_seat = 6
			hidden_b.source_seat = 7
			check(a.equip_hidden_card_to_slot(zone, hidden_a) and b.equip_hidden_card_to_slot(zone, hidden_b),
				zone + "双暗置原牌分别在两名角色装备槽")
			var zones: Array = ["cancel"]
			game._lanzhonghou_zone_override = func(): return zones.pop_front()
			await game._run_lanzhonghou(a, b)
			check(a.get_hidden_equipment_card(zone) == hidden_a and b.get_hidden_equipment_card(zone) == hidden_b
				and actor.hand_size() == 1 and not game._lanzhonghou_used,
				zone + "双暗置取消不移动或付费")
			zones.assign([zone, "done"])
			game._lanzhonghou_hidden_first_override = func(): return a_first
			var declaration_count = {"value": 0}
			game._sao_transfer_declare_override = func():
				declaration_count["value"] += 1
				if declaration_count["value"] == 1:
					check(a.get_hidden_equipment_card(zone) == hidden_b and b.get_hidden_equipment_card(zone) == hidden_a,
						zone + "声明前双方暗置原牌已完成物理交换")
				return -1
			await game._run_lanzhonghou(a, b)
			var first = hidden_a if a_first else hidden_b
			var second = hidden_b if a_first else hidden_a
			var default_sub = CardData.CardSubType.CALAMITY_SWORD if zone == "weapon" else CardData.CardSubType.CALAMITY_ROBE
			check(declaration_count["value"] == 2 and first.sub_type == default_sub
				and second.sub_type != default_sub and second.sub_type != CardData.CardSubType.HIDDEN_EQUIPMENT
				and game.equipment_pool.is_claimed(first.sub_type) and game.equipment_pool.is_claimed(second.sub_type),
				zone + ("A" if a_first else "B") + "先声明占用默认名，后者仅在剩余名称中随机")
			check(a.get_equipment_card(zone) == hidden_b and b.get_equipment_card(zone) == hidden_a
				and hidden_a.source_seat == 6 and hidden_b.source_seat == 7
				and actor.hand_size() == 0 and game._lanzhonghou_used and game.deck._discard.is_empty(),
				zone + "双暗置仅付一张手牌，两张具体化原牌均不入弃")
			game._lanzhonghou_zone_override = Callable()
			game._lanzhonghou_hidden_first_override = Callable()
			game._sao_transfer_declare_override = Callable()
	# 首位声明唯一剩余名称后，C-S4c应在第二位声明前立即弃掉另一张暗置原牌。
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._lanzhonghou_used = false
	var actor = game.players[0]
	var a = game.players[1]
	var b = game.players[2]
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	var hidden_a = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	var hidden_b = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden_a.hidden_category = "weapon"
	hidden_b.hidden_category = "weapon"
	check(a.equip_hidden_card_to_slot("weapon", hidden_a) and b.equip_hidden_card_to_slot("weapon", hidden_b),
		"唯一剩余武器名前双暗置原牌已落位")
	for sub in game.SAO_WEAPON_SUBS:
		if sub != CardData.CardSubType.CALAMITY_SWORD:
			game.equipment_pool.claim(sub)
	var zones: Array = ["weapon", "done"]
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	game._lanzhonghou_hidden_first_override = func(): return true
	var declaration_count = {"value": 0}
	game._sao_transfer_declare_override = func():
		declaration_count["value"] += 1
		return -1
	await game._run_lanzhonghou(a, b)
	check(declaration_count["value"] == 1 and hidden_a.sub_type == CardData.CardSubType.CALAMITY_SWORD
		and b.get_equipment_card("weapon") == hidden_a and not a.equipment.has("weapon")
		and hidden_b.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT and game.deck._discard.count(hidden_b) == 1
		and actor.hand_size() == 0 and game._lanzhonghou_used,
		"首位声明最后武器名后，第二张暗置原牌立即暗置入弃且不再询问")
	game._lanzhonghou_zone_override = Callable()
	game._lanzhonghou_hidden_first_override = Callable()
	game._sao_transfer_declare_override = Callable()
	# 选区期间其中一张暗置原牌被同槽替换：旧选区不扣费，新选择可正常交换。
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game._lanzhonghou_used = false
	actor = game.players[0]
	a = game.players[1]
	b = game.players[2]
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	hidden_a = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden_b = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	var next_hidden_b = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	for card in [hidden_a, hidden_b, next_hidden_b]:
		card.hidden_category = "weapon"
	check(a.equip_hidden_card_to_slot("weapon", hidden_a) and b.equip_hidden_card_to_slot("weapon", hidden_b),
		"过期选区例两张暗置原牌已落位")
	zones.assign(["weapon", "done"])
	game._lanzhonghou_zone_override = func():
		var result = zones.pop_front()
		if result == "done":
			check(b.remove_equipment("weapon") == hidden_b
				and b.equip_hidden_card_to_slot("weapon", next_hidden_b), "等待中同槽暗置原牌已替换")
		return result
	await game._run_lanzhonghou(a, b)
	check(a.get_hidden_equipment_card("weapon") == hidden_a
		and b.get_hidden_equipment_card("weapon") == next_hidden_b
		and actor.hand_size() == 1 and not game._lanzhonghou_used,
		"旧双暗置选区过期不付费、不移动后来者")
	zones.assign(["weapon", "done"])
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	game._lanzhonghou_hidden_first_override = func(): return false
	game._sao_transfer_declare_override = func(): return -1
	await game._run_lanzhonghou(a, b)
	check(a.get_equipment_card("weapon") == next_hidden_b
		and b.get_equipment_card("weapon") == hidden_a
		and actor.hand_size() == 0 and game._lanzhonghou_used,
		"重新选择当前双暗置原牌后仅付一次费用并完成交换")
	game._lanzhonghou_zone_override = Callable()
	game._lanzhonghou_hidden_first_override = Callable()
	game._sao_transfer_declare_override = Callable()
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

func check_meiyong_one_empty_visible_slot():
	# DEV-B02b-4a：一侧空槽可接另一侧明置原牌；等待中换牌使旧选择过期。
	var previous_phase = game.turn_manager.current_phase
	for zone in ["weapon", "armor"]:
		for source_is_a in [true, false]:
			suite.reset_players()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			game.turn_manager.current_player_idx = 0
			game._lanzhonghou_used = false
			var actor = game.players[0]
			var a = game.players[1]
			var b = game.players[2]
			actor.general_name = "麦克斯·欧尼斯特"
			actor.hand.append(null)
			var source = a if source_is_a else b
			var dest = b if source_is_a else a
			var sub = CardData.CardSubType.LIANNU if zone == "weapon" else CardData.CardSubType.RENWANG_DUN
			var card = CardBase.create(sub)
			card.source_seat = 8
			check(source.equip_card_to_slot(zone, card), "单边空槽前保存原装备")
			var zones: Array = ["cancel"]
			game._lanzhonghou_zone_override = func(): return zones.pop_front()
			await game._run_lanzhonghou(a, b)
			check(source.get_equipment_card(zone) == card and not dest.equipment.has(zone)
				and actor.hand_size() == 1 and not game._lanzhonghou_used,
				zone + "取消选对不付费、不移牌")
			zones.assign(["weapon" if zone == "weapon" else "armor", "done"])
			await game._run_lanzhonghou(a, b)
			check(not source.equipment.has(zone) and dest.get_equipment_card(zone) == card
				and card.source_seat == 8 and actor.hand_size() == 0 and game._lanzhonghou_used,
				zone + ("A到B" if source_is_a else "B到A") + "空槽交换只移动原对象并付一张")
			game._lanzhonghou_zone_override = Callable()

	# 已确认的E-01：白银狮子移至空槽也算失去装备，原持有者回血。
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = 0
	game._lanzhonghou_used = false
	var actor = game.players[0]
	var a = game.players[1]
	var b = game.players[2]
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	a.hp = 2
	a.max_hp = 4
	var lion = CardBase.create(CardData.CardSubType.SILVER_LION)
	a.equip_card_to_slot("armor", lion)
	var zones: Array = ["armor", "done"]
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	await game._run_lanzhonghou(a, b)
	check(a.hp == 3 and b.get_equipment_card("armor") == lion and not a.equipment.has("armor"),
		"白银狮子交换至空槽时原持有者回血且原对象只在新槽")
	game._lanzhonghou_zone_override = Callable()

	# 选择后、支付前同槽换上另一张合法牌：旧答复不支付、不动后来者，随后可重新选择。
	suite.reset_players()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = 0
	game._lanzhonghou_used = false
	actor = game.players[0]
	a = game.players[1]
	b = game.players[2]
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	var first = CardBase.create(CardData.CardSubType.LIANNU)
	var later = CardBase.create(CardData.CardSubType.QINGLONG_BLADE)
	a.equip_card_to_slot("weapon", first)
	zones.assign(["weapon", "done"])
	game._lanzhonghou_zone_override = func():
		var choice = zones.pop_front()
		if choice == "done":
			a.determined_cards.append(a.remove_equipment("weapon"))
			a.equip_card_to_slot("weapon", later)
		return choice
	await game._run_lanzhonghou(a, b)
	check(a.get_equipment_card("weapon") == later and b.get_weapon() == -1
		and a.determined_cards == [first] and actor.hand_size() == 1
		and not game._lanzhonghou_used and game.deck._discard.is_empty(),
		"空槽交换旧选择遇同槽换原对象，不误移后来者或付费")
	zones.assign(["weapon", "done"])
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	await game._run_lanzhonghou(a, b)
	check(not a.equipment.has("weapon") and b.get_equipment_card("weapon") == later
		and actor.hand_size() == 0 and game._lanzhonghou_used,
		"过期选择后下一次有效空槽交换可正常执行")
	game._lanzhonghou_zone_override = Callable()
	game.turn_manager.current_phase = previous_phase

func check_meiyong_empty_mount_slots():
	# DEV-B02b-4b：空对空不得计为交换；明置坐骑可移入对方空槽。
	var previous_phase = game.turn_manager.current_phase
	for zone in ["weapon", "armor", "mount"]:
		suite.reset_players()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game._lanzhonghou_used = false
		var actor = game.players[0]
		var a = game.players[1]
		var b = game.players[2]
		actor.general_name = "麦克斯·欧尼斯特"
		actor.hand.append(null)
		var zones: Array = [zone, "done"]
		game._lanzhonghou_zone_override = func(): return zones.pop_front()
		await game._run_lanzhonghou(a, b)
		check(actor.hand_size() == 1 and not game._lanzhonghou_used and game.deck._discard.is_empty()
			and game._lanzhonghou_pending.is_empty(), zone + "双方空槽不可选择且不支付")
		game._lanzhonghou_zone_override = Callable()
	for source_is_a in [true, false]:
		suite.reset_players()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game._lanzhonghou_used = false
		var actor = game.players[0]
		var a = game.players[1]
		var b = game.players[2]
		actor.general_name = "麦克斯·欧尼斯特"
		actor.hand.append(null)
		var source = a if source_is_a else b
		var dest = b if source_is_a else a
		# 共享测试夹具仅清装备表，不重置坐骑计数；本例显式隔离前例状态。
		a.mount_plus = 0
		b.mount_plus = 0
		var source_slot = "mount_2" if source_is_a else "mount_3"
		var dest_slot = "mount_4" if source_is_a else "mount_1"
		var card = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
		card.source_seat = 8
		check(source.equip_card_to_slot(source_slot, card), "坐骑交换前保留指定原对象")
		var zones: Array = ["mount", "done"]
		var slots: Array = [source_slot if source_is_a else dest_slot, dest_slot if source_is_a else source_slot]
		game._lanzhonghou_zone_override = func(): return zones.pop_front()
		game._lanzhonghou_mount_override = func(_target, available):
			var choice = slots.pop_front()
			check(available.has(choice), "坐骑选槽包含有牌与空槽")
			return choice
		await game._run_lanzhonghou(a, b)
		var direction = "A到B" if source_is_a else "B到A"
		check(not source.equipment.has(source_slot) and dest.get_equipment_card(dest_slot) == card
			and card.source_seat == 8, "坐骑" + direction + "单侧空槽保原对象")
		check(source.mount_plus == 0 and dest.mount_plus == 1,
			"坐骑" + direction + "单侧空槽更新双方坐骑计数")
		check(actor.hand_size() == 0 and game._lanzhonghou_used,
			"坐骑" + direction + "单侧空槽只付一张牌")
		game._lanzhonghou_zone_override = Callable()
		game._lanzhonghou_mount_override = Callable()
	game.turn_manager.current_phase = previous_phase

func check_meiyong_one_hidden_to_empty():
	# DEV-B02b-4c-1：只验一张暗置武器/防具移至对方空槽，离区后原持有者声明。
	var previous_phase = game.turn_manager.current_phase
	for zone in ["weapon", "armor"]:
		for source_is_a in [true, false]:
			for concrete in [false, true]:
				suite.reset_players()
				game.equipment_pool.clear()
				game.deck._discard.clear()
				game.turn_manager.current_phase = TurnManager.Phase.PLAY
				game._lanzhonghou_used = false
				var actor = game.players[0]
				var a = game.players[1]
				var b = game.players[2]
				for player in [a, b]:
					player.hidden_equip_slot = ""
					player.hidden_equip_card = null
				var source = a if source_is_a else b
				var dest = b if source_is_a else a
				actor.general_name = "麦克斯·欧尼斯特"
				actor.hand.append(null)
				source.general_name = "安普提·斯丢皮得"
				var original_sub = CardData.CardSubType.QINGLONG_BLADE if zone == "weapon" else CardData.CardSubType.RENWANG_DUN
				var original: CardBase = null
				if concrete:
					original = CardBase.create(original_sub)
					original.source_seat = 8
					source.determined_cards.append(original)
				else:
					source.hand.append(null)
				game.turn_manager.current_player_idx = source.seat_index
				game._sao_type_override = func(): return zone
				await game._do_sao_hide(source, false)
				game._sao_type_override = Callable()
				var hidden = source.hidden_equip_card
				var label = zone + ("A到B" if source_is_a else "B到A") + ("具体" if concrete else "任意")
				check(hidden != null and source.equipment.get(zone) == CardData.CardSubType.HIDDEN_EQUIPMENT
					and (hidden == original if concrete else true), label + "交换前仅有一份暗置原牌")
				game.turn_manager.current_player_idx = 0
				var zones: Array = ["cancel"]
				game._lanzhonghou_zone_override = func(): return zones.pop_front()
				await game._run_lanzhonghou(a, b)
				check(source.hidden_equip_card == hidden and dest.equipment.is_empty()
					and actor.hand_size() == 1 and not game._lanzhonghou_used,
					label + "取消不动暗置牌或费用")
				zones.assign([zone, "done"])
				game._sao_transfer_declare_override = func(): return -1
				await game._run_lanzhonghou(a, b)
				var expected = original_sub if concrete else (CardData.CardSubType.CALAMITY_SWORD if zone == "weapon" else CardData.CardSubType.CALAMITY_ROBE)
				check(not source.equipment.has(zone) and not source.has_hidden_equip()
					and dest.get_equipment_card(zone) == hidden and hidden.sub_type == expected
					and (hidden.source_seat == 8 if concrete else true),
					label + "原牌移入空槽并按原持有者默认声明")
				check(actor.hand_size() == 0 and game._lanzhonghou_used and game.deck._discard.is_empty()
					and game.equipment_pool.is_claimed(expected), label + "只付一张并占用具体名称")
				game._lanzhonghou_zone_override = Callable()
				game._sao_transfer_declare_override = Callable()

	# C-S4c：最后一个武器名声明后原牌立即消失，【没用】不再可选这对空槽。
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._lanzhonghou_used = false
	var actor = game.players[0]
	var a = game.players[1]
	var b = game.players[2]
	for player in [a, b]:
		player.hidden_equip_slot = ""
		player.hidden_equip_card = null
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	a.general_name = "安普提·斯丢皮得"
	a.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(a, false)
	game._sao_type_override = Callable()
	var hidden = a.hidden_equip_card
	for i in range(game.SAO_WEAPON_SUBS.size() - 1):
		game.equipment_pool.claim(game.SAO_WEAPON_SUBS[i])
	game._claim_equipment_name(game.SAO_WEAPON_SUBS[-1])
	game.turn_manager.current_player_idx = 0
	var zones: Array = ["weapon", "done"]
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	await game._run_lanzhonghou(a, b)
	check(not a.has_hidden_equip() and b.equipment.is_empty()
		and game.deck._discard.count(hidden) == 1
		and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
		and actor.hand_size() == 1 and not game._lanzhonghou_used,
		"全名称耗尽立即弃暗置原牌，空对空不支付、不交换")
	game._lanzhonghou_zone_override = Callable()
	game.equipment_pool.clear()

	# 默认灾厄剑已被占用：使用剩余合法武器名，不重复占名。
	suite.reset_players()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._lanzhonghou_used = false
	actor = game.players[0]
	a = game.players[1]
	b = game.players[2]
	for player in [a, b]:
		player.hidden_equip_slot = ""
		player.hidden_equip_card = null
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	a.general_name = "安普提·斯丢皮得"
	a.hand.append(null)
	game.turn_manager.current_player_idx = 1
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(a, false)
	game._sao_type_override = Callable()
	hidden = a.hidden_equip_card
	game.equipment_pool.claim(CardData.CardSubType.CALAMITY_SWORD)
	game.turn_manager.current_player_idx = 0
	zones.assign(["weapon", "done"])
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	game._sao_transfer_declare_override = func(): return -1
	await game._run_lanzhonghou(a, b)
	check(b.get_equipment_card("weapon") == hidden and game.SAO_WEAPON_SUBS.has(hidden.sub_type)
		and hidden.sub_type != CardData.CardSubType.CALAMITY_SWORD
		and game.equipment_pool.is_claimed(hidden.sub_type),
		"交换声明取消且默认名已占用时，原对象从剩余武器池具体化")
	game._lanzhonghou_zone_override = Callable()
	game._sao_transfer_declare_override = Callable()

	# 等待原持有者声明期间，原牌再次离开接收者：过期答复不得改名或占用名额。
	for stale in [true, false]:
		suite.reset_players()
		game.equipment_pool.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game._lanzhonghou_used = false
		actor = game.players[0]
		a = game.players[1]
		b = game.players[2]
		for player in [a, b]:
			player.hidden_equip_slot = ""
			player.hidden_equip_card = null
		actor.general_name = "麦克斯·欧尼斯特"
		actor.hand.append(null)
		a.general_name = "安普提·斯丢皮得"
		a.hand.append(null)
		game.turn_manager.current_player_idx = 1
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(a, false)
		game._sao_type_override = Callable()
		hidden = a.hidden_equip_card
		game.turn_manager.current_player_idx = 0
		zones.assign(["weapon", "done"])
		game._lanzhonghou_zone_override = func(): return zones.pop_front()
		game._sao_transfer_declare_override = func():
			if stale:
				check(b.remove_equipment("weapon") == hidden, "声明等待期间只能移出接收者的原对象")
				a.determined_cards.append(hidden)
			return CardData.CardSubType.QINGLONG_BLADE
		await game._run_lanzhonghou(a, b)
		if stale:
			check(b.equipment.is_empty() and a.determined_cards == [hidden]
				and hidden.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
				and not game.equipment_pool.is_claimed(CardData.CardSubType.QINGLONG_BLADE),
				"交换声明旧答复不改已再次离区的牌或占名")
		else:
			check(b.get_equipment_card("weapon") == hidden
				and hidden.sub_type == CardData.CardSubType.QINGLONG_BLADE
				and game.equipment_pool.is_claimed(CardData.CardSubType.QINGLONG_BLADE),
				"过期答复后的下一局合法交换可正常声明")
		game._lanzhonghou_zone_override = Callable()
		game._sao_transfer_declare_override = Callable()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase

func check_meiyong_multiple_hidden_receiver():
	# DEV-B02b-4c-2a：接收者原有另一槽暗置，交换仍须接同一原牌；无【苕】不可主动明置。
	var previous_phase = game.turn_manager.current_phase
	for no_weapon_name in [false, true]:
		suite.reset_players()
		game.equipment_pool.clear()
		game.deck._discard.clear()
		game.turn_manager.current_phase = TurnManager.Phase.PLAY
		game._lanzhonghou_used = false
		var actor = game.players[0]
		var a = game.players[1]
		var b = game.players[2]
		for player in [a, b]:
			player.hidden_equip_slot = ""
			player.hidden_equip_card = null
		actor.general_name = "麦克斯·欧尼斯特"
		actor.hand.append(null)
		a.general_name = "安普提·斯丢皮得"
		a.hand.append(null)
		var original_armor = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
		original_armor.hidden_category = "armor"
		original_armor.source_seat = 8
		check(b.equip_hidden_card_to_slot("armor", original_armor), "接收者先持有暗置防具原对象")
		check(not b.equip_hidden_card_to_slot("weapon", original_armor)
			and b.get_hidden_equipment_card("armor") == original_armor,
			"暗置防具不能复制到武器槽或改类别")
		game.turn_manager.current_player_idx = 1
		game._sao_type_override = func(): return "weapon"
		await game._do_sao_hide(a, false)
		game._sao_type_override = Callable()
		var incoming = a.hidden_equip_card
		if no_weapon_name:
			for i in range(game.SAO_WEAPON_SUBS.size() - 1):
				game.equipment_pool.claim(game.SAO_WEAPON_SUBS[i])
			game._claim_equipment_name(game.SAO_WEAPON_SUBS[-1])
			check(not a.has_hidden_equip() and game.deck._discard.count(incoming) == 1
				and b.get_hidden_equipment_card("armor") == original_armor,
				"武器名耗尽立即弃暗置武器，不波及另一槽暗置防具")
		game.turn_manager.current_player_idx = 0
		var zones: Array = ["weapon", "done"]
		game._lanzhonghou_zone_override = func(): return zones.pop_front()
		if not no_weapon_name:
			game._sao_transfer_declare_override = func():
				check(b.get_hidden_equipment_card("armor") == original_armor
					and b.get_hidden_equipment_card("weapon") == incoming
					and a.hidden_equip_card == null,
					"原持有者声明前，接收者同时拥有两槽不同暗置原牌")
				return -1
		await game._run_lanzhonghou(a, b)
		check(actor.hand_size() == (1 if no_weapon_name else 0)
			and game._lanzhonghou_used == not no_weapon_name and not a.has_hidden_equip()
			and b.get_hidden_equipment_card("armor") == original_armor
			and b.equipment.get("armor") == CardData.CardSubType.HIDDEN_EQUIPMENT,
			"暗置武器尚在时可交换，耗尽消失后不支付；暗置防具不受影响")
		await game._on_sao_skill_clicked(b)
		check(b.get_hidden_equipment_card("armor") == original_armor,
			"没有苕的接收者不能主动明置原有暗置防具")
		if no_weapon_name:
			check(not b.equipment.has("weapon") and game.deck._discard.count(incoming) == 1,
				"已暗置入弃的武器不会通过交换重新出现在接收者牌区")
			game._discard_all_cards(b, true)
			check(b.equipment.is_empty() and not b.has_hidden_equip()
				and game.deck._discard.count(incoming) == 1
				and game.deck._discard.count(original_armor) == 1,
				"全区清理仅弃剩余防具，武器不重复弃置")
		else:
			check(b.get_equipment_card("weapon") == incoming
				and incoming.sub_type == CardData.CardSubType.CALAMITY_SWORD
				and b.get_hidden_equipment_card("armor") == original_armor,
				"交换暗置武器完成声明不改另一槽的暗置防具")
		game._lanzhonghou_zone_override = Callable()
		game._sao_transfer_declare_override = Callable()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase

func check_hidden_name_exhaustion():
	# C-S4c：最后名称的声明是全场即时事件，装备区与手牌区都保留原牌暗置入弃。
	var previous_phase = game.turn_manager.current_phase
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	var owner = game.players[0]
	var receiver = game.players[1]
	var other = game.players[2]
	var weapon_equip = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	weapon_equip.hidden_category = "weapon"
	var weapon_hand = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	weapon_hand.hidden_category = "weapon"
	var armor_equip = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	armor_equip.hidden_category = "armor"
	var mount_hand = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	mount_hand.hidden_category = "mount"
	check(owner.equip_hidden_card_to_slot("weapon", weapon_equip)
		and receiver.equip_hidden_card_to_slot("armor", armor_equip),
		"名称耗尽前不同类型暗置原牌分别在装备区")
	receiver.determined_cards.append(weapon_hand)
	other.hand.append(mount_hand)
	for i in range(game.SAO_WEAPON_SUBS.size() - 1):
		game._claim_equipment_name(game.SAO_WEAPON_SUBS[i])
	check(owner.get_hidden_equipment_card("weapon") == weapon_equip
		and receiver.determined_cards.has(weapon_hand),
		"尚有一个武器名称时跨牌区暗置武器都保留")
	game._claim_equipment_name(game.SAO_WEAPON_SUBS[-1])
	check(not owner.has_hidden_equip() and not receiver.determined_cards.has(weapon_hand)
		and game.deck._discard.count(weapon_equip) == 1
		and game.deck._discard.count(weapon_hand) == 1
		and weapon_equip.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT
		and weapon_hand.sub_type == CardData.CardSubType.HIDDEN_EQUIPMENT,
		"武器名耗尽立即将装备区与手牌区暗置原牌各弃一次")
	check(receiver.get_hidden_equipment_card("armor") == armor_equip
		and other.hand.has(mount_hand), "武器耗尽不波及暗置防具和坐骑")
	game._claim_equipment_name(game.SAO_WEAPON_SUBS[-1])
	check(game.deck._discard.count(weapon_equip) == 1 and game.deck._discard.count(weapon_hand) == 1,
		"重复声明已占用名称不重复弃牌")
	for sub in game.SAO_ARMOR_SUBS:
		game._claim_equipment_name(sub)
	check(not receiver.has_hidden_equip() and game.deck._discard.count(armor_equip) == 1
		and other.hand.has(mount_hand), "防具名耗尽独立弃防具，坐骑仍保留")
	other.general_name = "安普提·斯丢皮得"
	other.hand.append(null)
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.current_player_idx = other.seat_index
	game._sao_type_override = func(): return "weapon"
	await game._do_sao_hide(other, false)
	game._sao_type_override = Callable()
	check(not other.has_hidden_equip() and other.hand.has(mount_hand)
		and other.hand_size() == 1 and game.deck._discard.size() == 4,
		"类别已耗尽时新暗置武器也立刻暗置入弃")
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase

func check_meiyong_one_hidden_mount_to_empty():
	# DEV-B02b-4c-2b-ii-c-1：暗置坐骑可与对方空马槽跨槽交换，原持有者离区声明。
	var previous_phase = game.turn_manager.current_phase
	for source_is_a in [true, false]:
		for concrete in [false, true]:
			suite.reset_players()
			game.equipment_pool.clear()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			game._lanzhonghou_used = false
			var actor = game.players[0]
			var a = game.players[1]
			var b = game.players[2]
			for player in [a, b]:
				player.hidden_equip_slot = ""
				player.hidden_equip_card = null
				player.mount_plus = 0
				player.mount_minus = 0
			var source = a if source_is_a else b
			var dest = b if source_is_a else a
			actor.general_name = "麦克斯·欧尼斯特"
			actor.hand.append(null)
			source.general_name = "安普提·斯丢皮得"
			var original: CardBase = null
			if concrete:
				original = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
				original.source_seat = 8
				source.determined_cards.append(original)
			else:
				source.hand.append(null)
			game.turn_manager.current_player_idx = source.seat_index
			game._sao_type_override = func(): return "mount"
			await game._do_sao_hide(source, false)
			game._sao_type_override = Callable()
			var source_slot = source.hidden_equip_slot
			var hidden = source.get_hidden_equipment_card(source_slot)
			var dest_slot = "mount_3"
			var label = ("A到B" if source_is_a else "B到A") + ("具体" if concrete else "任意")
			check(hidden != null and source_slot == "mount_1" and hidden.hidden_category == "mount"
				and (hidden == original if concrete else true), label + "暗置坐骑保留来源原牌")
			game.turn_manager.current_player_idx = 0
			var zones: Array = ["cancel"]
			game._lanzhonghou_zone_override = func(): return zones.pop_front()
			await game._run_lanzhonghou(a, b)
			check(source.get_hidden_equipment_card(source_slot) == hidden and not dest.equipment.has(dest_slot)
				and actor.hand_size() == 1 and not game._lanzhonghou_used,
				label + "取消时不移牌、不付费")
			zones.assign(["mount", "done"])
			game._lanzhonghou_mount_override = func(target, available):
				var slot = source_slot if target == source else dest_slot
				check(available.has(slot), label + "暗置来源和对方空马槽可选")
				return slot
			game._sao_transfer_declare_override = func(): return -1
			await game._run_lanzhonghou(a, b)
			var correct_name = hidden.sub_type == CardData.CardSubType.MOUNT_MINUS if concrete else \
				(hidden.sub_type == CardData.CardSubType.MULE_MINUS or hidden.sub_type == CardData.CardSubType.MULE_PLUS)
			check(not source.equipment.has(source_slot) and dest.get_equipment_card(dest_slot) == hidden
				and correct_name and (hidden.source_seat == 8 if concrete else true),
				label + "跨马槽移动同一原牌并由原持有者默认声明")
			check(source.mount_plus == 0 and source.mount_minus == 0
				and dest.mount_plus == 0 and dest.mount_minus == (1 if concrete else 0)
				and actor.hand_size() == 0 and game._lanzhonghou_used and game.deck._discard.is_empty(),
				label + "仅付一张，坐骑计数与具体化结果一致且原牌不入弃")
			game._lanzhonghou_zone_override = Callable()
			game._lanzhonghou_mount_override = Callable()
			game._sao_transfer_declare_override = Callable()
	# 选区期间暗置坐骑原牌被同槽换掉：旧答复不支付，新选择取当前原牌。
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game._lanzhonghou_used = false
	var actor = game.players[0]
	var a = game.players[1]
	var b = game.players[2]
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	a.hidden_equip_slot = ""
	a.hidden_equip_card = null
	var old_hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	var next_hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	old_hidden.hidden_category = "mount"
	next_hidden.hidden_category = "mount"
	check(a.equip_hidden_card_to_slot("mount_2", old_hidden), "旧选区例暗置坐骑原牌已落位")
	var zones: Array = ["mount", "done"]
	game._lanzhonghou_zone_override = func():
		var result = zones.pop_front()
		if result == "done":
			a.determined_cards.append(a.remove_equipment("mount_2"))
			check(a.equip_hidden_card_to_slot("mount_2", next_hidden), "选区等待中暗置坐骑已同槽换牌")
		return result
	game._lanzhonghou_mount_override = func(target, available):
		var slot = "mount_2" if target == a else "mount_4"
		check(available.has(slot), "过期选择期间暗置马槽及空马槽仍可选")
		return slot
	await game._run_lanzhonghou(a, b)
	check(a.get_hidden_equipment_card("mount_2") == next_hidden
		and b.equipment.is_empty() and a.determined_cards.has(old_hidden)
		and actor.hand_size() == 1 and not game._lanzhonghou_used,
		"暗置坐骑原牌过期时不付费、不移动后来者")
	zones.assign(["mount", "done"])
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	game._sao_transfer_declare_override = func(): return -1
	await game._run_lanzhonghou(a, b)
	check(not a.equipment.has("mount_2") and b.get_equipment_card("mount_4") == next_hidden
		and actor.hand_size() == 0 and game._lanzhonghou_used,
		"重新选择当前暗置坐骑后付一张并跨槽转移原牌")
	game._lanzhonghou_zone_override = Callable()
	game._lanzhonghou_mount_override = Callable()
	game._sao_transfer_declare_override = Callable()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase

func check_meiyong_hidden_visible_mount_exchange():
	# DEV-B02b-4c-2b-ii-c-2：一暗一明坐骑先交换原对象，再由暗置原持有者声明。
	var previous_phase = game.turn_manager.current_phase
	for hidden_is_a in [true, false]:
		for concrete in [false, true]:
			suite.reset_players()
			game.equipment_pool.clear()
			game.deck._discard.clear()
			game.turn_manager.current_phase = TurnManager.Phase.PLAY
			game._lanzhonghou_used = false
			var actor = game.players[0]
			var a = game.players[1]
			var b = game.players[2]
			for player in [a, b]:
				player.hidden_equip_slot = ""
				player.hidden_equip_card = null
				player.mount_plus = 0
				player.mount_minus = 0
			var hidden_owner = a if hidden_is_a else b
			var visible_owner = b if hidden_is_a else a
			actor.general_name = "麦克斯·欧尼斯特"
			actor.hand.append(null)
			hidden_owner.general_name = "安普提·斯丢皮得"
			var original: CardBase = null
			if concrete:
				original = CardBase.create(CardData.CardSubType.MOUNT_MINUS)
				original.source_seat = 8
				hidden_owner.determined_cards.append(original)
			else:
				hidden_owner.hand.append(null)
			game.turn_manager.current_player_idx = hidden_owner.seat_index
			game._sao_type_override = func(): return "mount"
			await game._do_sao_hide(hidden_owner, false)
			game._sao_type_override = Callable()
			var hidden_slot = hidden_owner.hidden_equip_slot
			var hidden = hidden_owner.get_hidden_equipment_card(hidden_slot)
			var visible_slot = "mount_3"
			var visible = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
			visible.source_seat = 7
			var label = ("A暗" if hidden_is_a else "B暗") + ("具体" if concrete else "任意")
			check(hidden != null and hidden_slot == "mount_1" and visible_owner.equip_card_to_slot(visible_slot, visible),
				label + "交换前暗置与明置坐骑原牌各自落位")
			game.turn_manager.current_player_idx = 0
			var zones: Array = ["cancel"]
			game._lanzhonghou_zone_override = func(): return zones.pop_front()
			await game._run_lanzhonghou(a, b)
			check(hidden_owner.get_hidden_equipment_card(hidden_slot) == hidden
				and visible_owner.get_equipment_card(visible_slot) == visible
				and actor.hand_size() == 1 and not game._lanzhonghou_used,
				label + "取消不交换、不付费")
			zones.assign(["mount", "done"])
			game._lanzhonghou_mount_override = func(target, available):
				var slot = hidden_slot if target == hidden_owner else visible_slot
				check(available.has(slot), label + "一暗一明坐骑槽均可选择")
				return slot
			game._sao_transfer_declare_override = func():
				check(hidden_owner.get_equipment_card(hidden_slot) == visible
					and visible_owner.get_hidden_equipment_card(visible_slot) == hidden,
					label + "声明前两件坐骑原牌已经互换")
				return -1
			await game._run_lanzhonghou(a, b)
			var correct_name = hidden.sub_type == CardData.CardSubType.MOUNT_MINUS if concrete else \
				(hidden.sub_type == CardData.CardSubType.MULE_MINUS or hidden.sub_type == CardData.CardSubType.MULE_PLUS)
			check(hidden_owner.get_equipment_card(hidden_slot) == visible
				and visible_owner.get_equipment_card(visible_slot) == hidden
				and visible.source_seat == 7 and (hidden == original and hidden.source_seat == 8 if concrete else true)
				and correct_name,
				label + "双方保留各自原对象，暗置原持有者按合法名声明")
			check(hidden_owner.mount_plus == 1 and hidden_owner.mount_minus == 0
				and visible_owner.mount_plus == 0 and visible_owner.mount_minus == (1 if concrete else 0)
				and actor.hand_size() == 0 and game._lanzhonghou_used and game.deck._discard.is_empty(),
				label + "只付一张、双方马计数按最终具体名更新且原牌不入弃")
			game._lanzhonghou_zone_override = Callable()
			game._lanzhonghou_mount_override = Callable()
			game._sao_transfer_declare_override = Callable()
	# 选区等待中明置坐骑同槽换了原实例，旧选择不付费；重新选当前牌才生效。
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game._lanzhonghou_used = false
	var actor = game.players[0]
	var a = game.players[1]
	var b = game.players[2]
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	a.hidden_equip_slot = ""
	a.hidden_equip_card = null
	var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden.hidden_category = "mount"
	var old_visible = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	var next_visible = CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	check(a.equip_hidden_card_to_slot("mount_2", hidden)
		and b.equip_card_to_slot("mount_4", old_visible), "过期选择例两侧坐骑原牌已落位")
	var zones: Array = ["mount", "done"]
	game._lanzhonghou_zone_override = func():
		var choice = zones.pop_front()
		if choice == "done":
			b.determined_cards.append(b.remove_equipment("mount_4"))
			check(b.equip_card_to_slot("mount_4", next_visible), "等待中明置坐骑已换成同名另一原牌")
		return choice
	game._lanzhonghou_mount_override = func(target, available):
		var slot = "mount_2" if target == a else "mount_4"
		check(available.has(slot), "过期选择例暗置和明置马槽均可选")
		return slot
	await game._run_lanzhonghou(a, b)
	check(a.get_hidden_equipment_card("mount_2") == hidden
		and b.get_equipment_card("mount_4") == next_visible and b.determined_cards.has(old_visible)
		and actor.hand_size() == 1 and not game._lanzhonghou_used,
		"旧坐骑原牌选区过期不付费、不移动后来者")
	zones.assign(["mount", "done"])
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	game._sao_transfer_declare_override = func(): return -1
	await game._run_lanzhonghou(a, b)
	check(a.get_equipment_card("mount_2") == next_visible
		and b.get_equipment_card("mount_4") == hidden
		and actor.hand_size() == 0 and game._lanzhonghou_used,
		"下一次选择当前一暗一明坐骑后仅付一张并完成互换")
	game._lanzhonghou_zone_override = Callable()
	game._lanzhonghou_mount_override = Callable()
	game._sao_transfer_declare_override = Callable()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase

func check_meiyong_hidden_visible_exchange():
	# DEV-B02b-4c-2b-ii-a：已暗置与明置的同类武器／防具先交换原牌，再由原持有者声明。
	var previous_phase = game.turn_manager.current_phase
	for zone in ["weapon", "armor"]:
		for hidden_is_a in [true, false]:
			for concrete in [false, true]:
				suite.reset_players()
				game.equipment_pool.clear()
				game.deck._discard.clear()
				game.turn_manager.current_phase = TurnManager.Phase.PLAY
				game._lanzhonghou_used = false
				var actor = game.players[0]
				var a = game.players[1]
				var b = game.players[2]
				for player in [a, b]:
					player.hidden_equip_slot = ""
					player.hidden_equip_card = null
				var hidden_owner = a if hidden_is_a else b
				var visible_owner = b if hidden_is_a else a
				actor.general_name = "麦克斯·欧尼斯特"
				actor.hand.append(null)
				hidden_owner.general_name = "安普提·斯丢皮得"
				var original_sub = CardData.CardSubType.QINGLONG_BLADE if zone == "weapon" else CardData.CardSubType.RENWANG_DUN
				var visible_sub = CardData.CardSubType.LIANNU if zone == "weapon" else CardData.CardSubType.BAIHUA_SKIRT
				var original: CardBase = null
				if concrete:
					original = CardBase.create(original_sub)
					original.source_seat = 8
					hidden_owner.determined_cards.append(original)
				else:
					hidden_owner.hand.append(null)
				game.turn_manager.current_player_idx = hidden_owner.seat_index
				game._sao_type_override = func(): return zone
				await game._do_sao_hide(hidden_owner, false)
				game._sao_type_override = Callable()
				var hidden = hidden_owner.get_hidden_equipment_card(zone)
				var visible = CardBase.create(visible_sub)
				visible.source_seat = 7
				check(visible_owner.equip_card_to_slot(zone, visible), "暗置/明置交换前明置原牌在对方槽")
				var label = zone + ("A暗置" if hidden_is_a else "B暗置") + ("具体" if concrete else "任意")
				check(hidden != null and (hidden == original if concrete else true), label + "暗置仍是同一来源原牌")
				game.turn_manager.current_player_idx = 0
				var zones: Array = ["cancel"]
				game._lanzhonghou_zone_override = func(): return zones.pop_front()
				await game._run_lanzhonghou(a, b)
				check(hidden_owner.get_hidden_equipment_card(zone) == hidden
					and visible_owner.get_equipment_card(zone) == visible
					and actor.hand_size() == 1 and not game._lanzhonghou_used,
					label + "取消时两张原牌和费用均不动")
				zones.assign([zone, "done"])
				game._sao_transfer_declare_override = func(): return -1
				await game._run_lanzhonghou(a, b)
				var expected = original_sub if concrete else (CardData.CardSubType.CALAMITY_SWORD if zone == "weapon" else CardData.CardSubType.CALAMITY_ROBE)
				check(hidden_owner.get_equipment_card(zone) == visible
					and visible_owner.get_equipment_card(zone) == hidden
					and hidden.sub_type == expected and visible.source_seat == 7
					and (hidden.source_seat == 8 if concrete else true),
					label + "原牌先互换，原暗置持有者再声明且仅暗置原牌改名")
				check(actor.hand_size() == 0 and game._lanzhonghou_used
					and game.deck._discard.is_empty() and game.equipment_pool.is_claimed(expected),
					label + "仅付一张任意手牌，不弃两件交换原牌")
				game._lanzhonghou_zone_override = Callable()
				game._sao_transfer_declare_override = Callable()

	# 选择期间明置原牌被同槽另一实例替换，旧选择不得付费或移走后来者；下一次可重新选择。
	suite.reset_players()
	game.equipment_pool.clear()
	game.deck._discard.clear()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._lanzhonghou_used = false
	var actor = game.players[0]
	var a = game.players[1]
	var b = game.players[2]
	actor.general_name = "麦克斯·欧尼斯特"
	actor.hand.append(null)
	a.general_name = "安普提·斯丢皮得"
	var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden.hidden_category = "weapon"
	check(a.equip_hidden_card_to_slot("weapon", hidden), "过期选择例暗置原牌已落位")
	var old_visible = CardBase.create(CardData.CardSubType.LIANNU)
	var next_visible = CardBase.create(CardData.CardSubType.ZHUGE_LIANNU)
	check(b.equip_card_to_slot("weapon", old_visible), "过期选择例明置原牌已落位")
	var zones: Array = ["weapon", "done"]
	game._lanzhonghou_zone_override = func():
		var result = zones.pop_front()
		if result == "done":
			check(b.remove_equipment("weapon") == old_visible
				and b.equip_card_to_slot("weapon", next_visible), "选区等待中同槽换为另一原实例")
		return result
	await game._run_lanzhonghou(a, b)
	check(a.get_hidden_equipment_card("weapon") == hidden
		and b.get_equipment_card("weapon") == next_visible
		and actor.hand_size() == 1 and not game._lanzhonghou_used,
		"旧选区答复过期时不付费、不移动后来者")
	zones.assign(["weapon", "done"])
	game._lanzhonghou_zone_override = func(): return zones.pop_front()
	game._sao_transfer_declare_override = func(): return -1
	await game._run_lanzhonghou(a, b)
	check(a.get_equipment_card("weapon") == next_visible
		and b.get_equipment_card("weapon") == hidden
		and actor.hand_size() == 0 and game._lanzhonghou_used,
		"过期后下一次有效选择仍按当前两件原牌完成交换")
	game._lanzhonghou_zone_override = Callable()
	game._sao_transfer_declare_override = Callable()
	game.equipment_pool.clear()
	game.turn_manager.current_phase = previous_phase
