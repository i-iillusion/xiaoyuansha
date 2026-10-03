# DEV-C00：恢复本地草稿后的兼容回归。真实用牌/伤害链另由C01/C03用例覆盖。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "装备技能边界：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game.equipment_pool.clear()
	game._clear_pending_determined_card()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game._rps_override = Callable()
	game._kaiwen_override = Callable()
	game._bloodthirsty_override = Callable()
	game._sao_reveal_override = Callable()
	game._liehuo_override = Callable()
	for p in game.players:
		p.hidden_equip_slot = ""
		p.hidden_equip_card = null
		p.mount_plus = 0
		p.mount_minus = 0

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	var owner = game.players[0]
	var equipper = game.players[1]

	# C-S3/E-04：普通马及两种劣马都不能通过同名抢占阻止。
	for sub in [CardData.CardSubType.MOUNT_PLUS, CardData.CardSubType.MOUNT_MINUS,
		CardData.CardSubType.MULE_PLUS, CardData.CardSubType.MULE_MINUS]:
		reset_case()
		owner.general_name = "安普提·斯丢皮得"
		var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
		hidden.hidden_category = "mount"
		owner.equip_hidden_card_to_slot("mount_1", hidden)
		var asks: Array = []
		game._sao_reveal_override = func():
			asks.append(true)
			return true
		var preempted = await game._try_sao_preempt(equipper, sub, "mount")
		check(not preempted and asks.is_empty(), "坐骑直接绕过抢先声明询问：" + CardData.get_type_name(sub))
		check(owner.get_hidden_equipment_card("mount_1") == hidden, "坐骑不抢占且原暗置对象保持不变")

	# ST-14：【你个壊货】每一点均可放弃；放弃不拼点、不摸牌。
	reset_case()
	owner.general_name = "凯文·罗本"
	var opponent = game.players[1]
	var kaiwen_asks: Array = []
	var rps_calls: Array = []
	game._kaiwen_override = func():
		kaiwen_asks.append(true)
		return false
	game._rps_override = func(_p):
		rps_calls.append(true)
		return 0
	await game._try_kaiwen_ping(owner, opponent, 2, true)
	check(kaiwen_asks.size() == 2, "你个壊货对两点伤害逐点提供可选发动机会")
	check(rps_calls.is_empty() and owner.hand_size() == 0, "两次放弃均不拼点、不摸牌")

	# ST-14：【噬血之刃】可放弃；放弃不拼点、不回复。
	reset_case()
	owner.hp = 8
	owner.equip_card_to_slot("weapon", CardBase.create(CardData.CardSubType.BLOODTHIRSTY_BLADE))
	var blood_asks: Array = []
	rps_calls.clear()
	game._bloodthirsty_override = func():
		blood_asks.append(true)
		return false
	game._rps_override = func(_p):
		rps_calls.append(true)
		return 0
	await game._try_bloodthirsty(owner, opponent, 2)
	check(blood_asks.size() == 2, "噬血之刃对两点伤害逐点提供可选发动机会")
	check(rps_calls.is_empty() and owner.hp == 8, "两次放弃均不拼点、不回复体力")

	reset_case()
	game.turn_manager.current_phase = phase
	game = null
	suite = null
