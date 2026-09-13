# A2a：由核心 CI 调用，跨区计数、原子弃牌、拆偷和费用边界。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, label: String):
	suite.check(ok, "A2a：" + label)

func reset_case():
	suite.reset_players()
	game.deck._discard.clear()
	game._gay_used = false
	game._liehuo_override = func(): return false
	for p in game.players:
		p.judgment_cards.clear()
		p.sage_activated = false
		p.kneel_used = false

func run(host):
	suite = host
	game = host.game
	var p = game.players[0]
	var target = game.players[1]
	var first = CardBase.create(CardData.CardSubType.STRIKE)
	var second = CardBase.create(CardData.CardSubType.PEACH)
	first.source_seat = 3
	reset_case()
	p.hand.assign([null, first])
	p.determined_cards.append(second)
	check(p.hand_size() == 3 and p.has_any_card(), "两个手牌存储区共同计数")
	check(p.take_hand_cards(4).is_empty() and p.hand_size() == 3, "超额取牌失败且完全不扣")
	check(p.take_hand_cards(-1).is_empty() and p.hand_size() == 3, "负数量请求不扣牌")
	check(p.take_hand_cards(3) == [first, null, second], "一次取牌跨越两个原数组，保留任意牌占位")
	check(p.hand_size() == 0 and not p.has_any_card(), "取空后计数及有牌判断一致")
	p.determined_cards.append(first)
	check(p.remove_from_hand(first) and p.hand_size() == 0, "按原对象移除支持已确定牌区")
	check(not p.remove_from_hand(first), "同一对象不能重复移除")

	reset_case()
	p.hand.append(null)
	p.determined_cards.assign([first, second])
	check(not game._discard_hand_cards(p, 4), "不足费用不部分支付")
	check(p.hand_size() == 3 and game.deck._discard.is_empty(), "失败不改变牌区或弃牌堆")
	check(game._discard_hand_cards(p, 3), "完整费用可以跨区支付")
	check(game.deck._discard == [second, first] and p.hand_size() == 0, "具体牌入堆，任意牌不虚构类型")
	check(game._discard_hand_cards(p, 0) and game.deck._discard.size() == 2, "零费用不制造牌")

	reset_case()
	target.determined_cards.append(first)
	await game._steal_hand(p, target, true, "顺手牵羊")
	check(target.hand_size() == 0 and p.hand == [first], "只有已确定牌也可被偷，获得原实例")
	check(first.source_seat == 3 and game.deck._discard.is_empty(), "转移保留来源且不入弃牌堆")
	await game._steal_hand(target, p, false, "过河拆桥")
	check(p.hand_size() == 0 and game.deck._discard == [first], "再次拆除只弃置一次原牌")
	target.determined_cards.append(second)
	await game._steal_hand(p, target, false, "过河拆桥")
	check(target.hand_size() == 0 and game.deck._discard.count(second) == 1, "第二牌区可直接拆除")

	reset_case()
	var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
	p.hand.append(first)
	p.determined_cards.append(second)
	p.judgment_cards.append(judgment)
	game._discard_all_cards(p, false)
	check(p.hand_size() == 0 and game.deck._discard == [first, second], "主公惩罚清理全部手牌存储区")
	check(p.judgment_cards == [judgment], "只弃手牌装备不误清判定区")
	game._discard_all_cards(p, true)
	check(game.deck._discard == [first, second, judgment], "后续最终死亡不重复弃手牌")

	reset_case()
	p.general_name = "史蒂芬·彼特先斯"
	p.determined_cards.append(first)
	game._check_awaken_trigger()
	check(not p.awoken, "有已确定牌不能错误触发空手觉醒")
	p.general_name = "布鲁斯·萨维奇"
	p.hp = 9
	game.turn_manager.current_player_idx = 1
	check(not game._kneel_conditions_met(p), "有已确定牌不能满足下跪的无手牌条件")

	reset_case()
	p.general_name = "比尔·盖伊"
	p.hp = 5
	target.hp = 5
	p.determined_cards.assign([first, second])
	p.equipment["armor"] = CardData.CardSubType.LIEHUO_SHIELD
	game._liehuo_override = func():
		check(false, "技能费用不应询问烈火盾替代")
		return true
	game._gay_x_override = func(): return 2
	await game._execute_gay(p, target)
	check(p.hp == 7 and target.hp == 7 and game._gay_used, "技能按跨区手牌支付后产生效果并记次数")
	check(p.hand_size() == 0 and game.deck._discard == [second, first], "技能费用具体牌一次入堆，不用失血代付")

	reset_case()
	p.general_name = "比尔·盖伊"
	p.hp = 5
	target.hp = 5
	p.determined_cards.assign([first, second])
	game._gay_x_override = func():
		p.determined_cards.erase(first)
		return 2
	await game._execute_gay(p, target)
	check(p.determined_cards == [second] and game.deck._discard.is_empty(), "选择费用期间失牌，不部分扣费")
	check(p.hp == 5 and target.hp == 5 and not game._gay_used, "失效费用不回血也不登记发动")

	reset_case()
	p.hp = 1
	p.hand.append(null)
	p.determined_cards.assign([first, second])
	# 隔离回合后续调度，只执行实际弃牌阶段函数并检查其推进到 END。
	game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
	game.turn_manager.current_phase = TurnManager.Phase.DISCARD
	await game._do_discard(0)
	game.turn_manager.phase_changed.connect(game._on_phase_changed)
	check(p.hand_size() == 1 and p.determined_cards == [first], "弃牌阶段按总手牌数计算超限并跨区弃牌")
	check(game.deck._discard == [second], "弃牌阶段不漏具体牌、不制造任意牌实体")
	check(game.turn_manager.current_phase == TurnManager.Phase.END, "弃牌后只正常推进一次")
	reset_case()
	game._gay_x_override = Callable()
	game._liehuo_override = Callable()
	game = null
	suite = null
