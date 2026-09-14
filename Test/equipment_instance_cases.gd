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
