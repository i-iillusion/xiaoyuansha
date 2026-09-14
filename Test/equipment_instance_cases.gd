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
