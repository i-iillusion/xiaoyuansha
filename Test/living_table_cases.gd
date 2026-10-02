extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "D00：" + label)

func reset_case():
	suite.reset_players()
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	for p in game.players:
		p.mount_minus = 0
		p.mount_plus = 0
		p.judgment_cards.clear()
		p.identity = "主公" if p.seat_index == 0 else "反贼"

func run(host):
	suite = host
	game = host.game
	var phase = game.turn_manager.current_phase
	for sub in [CardData.CardSubType.STRIKE, CardData.CardSubType.SUPPLY_SHORTAGE]:
		for concrete in [false, true]:
			reset_case()
			var a: Player = game.players[0]
			var b: Player = game.players[1]
			var c: Player = game.players[2]
			var used: CardBase = CardBase.create(sub) if concrete else null
			a.hand.append(used)
			var confirmations: Array = []
			game._target_confirm_override = func():
				confirmations.append(true)
				return true
			game._enter_targeting_mode(sub)
			await game._on_target_click(c)
			check(confirmations.is_empty() and a.hand_size() == 1 and a.seat_distance_to(c) == 2,
				"五人完整圆桌距离2，真实选目标拒绝且不支付")
			b.hp = 0
			check(b.is_dying() and a.seat_distance_to(c) == 2, "濒死窗口尚占原座位")
			b.hp = 1
			check(a.seat_distance_to(c) == 2, "救回不改变编号与距离")
			await game._deal_damage(null, b, 1, EffectChain.DamageType.PHYSICAL)
			check(b.is_dead() and a.seat_distance_to(c) == 1 and c.seat_distance_to(a) == 1,
				"真实死亡结算后双向距离立即压缩为1")
			check(c.seat_index == 2 and game.players[1] == b, "玩家编号及回合数组不重排")
			await game._on_target_click(c)
			check(confirmations.size() == 1 and a.hand_size() == 0, "下一次选同目标合法，任意/具体牌真实支付")
			check(c.hp == 9 if sub == CardData.CardSubType.STRIKE else c.judgment_cards.size() == 1,
				"杀与延时锦囊入口共用存活圆桌距离")
			c.mount_plus = 1
			check(a.attack_distance_to(c) == 2 and not a.can_attack(c), "死亡后仍叠加目标坐骑修正")
			a.mount_minus = 1
			check(a.attack_distance_to(c) == 1 and a.can_attack(c), "自己的减距离坐骑仍有效")
	game._target_confirm_override = Callable()
	# 多人数纯查询不依赖GameManager布局；输入数组顺序不可更改。
	for count in [2, 3, 7, 10]:
		var all: Array[Player] = []
		for i in range(count):
			var p = Player.new()
			p.seat_index = i
			p.hp = 4
			all.append(p)
		var shuffled = all.duplicate()
		shuffled.reverse()
		check(LivingTable.distance(shuffled, all[0], all[count - 1]) == 1,
			"首尾相邻，查询按固定座号排序：%d人" % count)
		check(shuffled[0] == all[count - 1], "只读查询不修改输入数组")
		if count > 2:
			all[1].mark_dead()
			check(LivingTable.distance(all, all[0], all[2]) == 1, "非五人局同样排除最终死者")
			check(LivingTable.distance(all, all[0], all[1]) == LivingTable.UNREACHABLE, "死者不在距离圆环内")
		for p in all:
			p.free()
	reset_case()
	game.turn_manager.current_phase = phase
