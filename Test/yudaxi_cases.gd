# 由核心 CI 调用，使用生产濒死/求救入口，不把结果回调伪装成技能。
extends RefCounted

var suite
var game: GameManager

func check(ok: bool, message: String):
	suite.check(ok, "预大习：" + message)

func reset_case():
	suite.reset_players()
	game.yudaxi = YudaxiResolver.new()
	game.rule_scheduler = RuleScheduler.new()
	game._sage_save_override = func(): return false
	var identities = ["主公", "忠臣", "反贼", "反贼", "内奸"]
	for i in game.players.size():
		var p = game.players[i]
		p.identity = identities[i]
		p.identity_revealed = i == 0
		p.judgment_cards.clear()
		p.determined_cards.clear()
		p.sage_activated = false

func leo(index: int, hp: int = 0) -> Player:
	var p = game.players[index]
	p.general_name = "里奥·普利威尔"
	p.capture_game_start_state()
	p.hp = hp
	return p

func run(host):
	suite = host
	game = host.game
	await check_success()
	await check_nested()
	await check_saves()
	await check_order_and_limit()
	reset_case()
	game._sage_save_override = Callable()
	game = null
	suite = null

func check_success():
	reset_case()
	var owner = leo(2, 1)
	var hand = CardBase.create(CardData.CardSubType.STRIKE)
	var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
	owner.hand.append(hand)
	owner.judgment_cards.append(judgment)
	owner.equipment["armor"] = CardData.CardSubType.SILVER_LION
	game.players[3].hp = 2
	# 真正伤害入口：狮子把伤害减为1，濒死后扣其他人2不经防具。
	await game._deal_damage(game.players[1], owner, 1, EffectChain.DamageType.PHYSICAL)
	check(owner.is_alive() and owner.hp == 1, "真实伤害入口成功恢复至 X")
	check(owner.hand.size() == 2 and owner.hand[0] == hand, "保留原手牌并摸 X")
	check(owner.judgment_cards == [judgment] and owner.get_armor() == CardData.CardSubType.SILVER_LION, "成功保留判定区和装备")
	check(not owner.identity_revealed and not game._dead_processed.has(owner), "成功不公开身份、不提交死亡")
	check(game.players[3].is_dead() and game.players[1].hand.is_empty(), "扣血死亡没有击杀来源或反贼奖励")
	check(game._dying_contexts.is_empty() and not game.yudaxi.is_active(), "结算结束清理所有活跃帧")

	reset_case()
	owner = leo(2, -4)
	owner.max_hp = 1
	game.players[3].hp = 2
	game.players[3].equipment["armor"] = CardData.CardSubType.SILVER_LION
	game.players[4].hp = 2
	game.players[4].equipment["armor"] = CardData.CardSubType.QIXING_PAO
	await game._resolve_dying(owner, null, "test")
	check(owner.hp == 2 and owner.hand.size() == 2, "恢复至 X 不叠加负体力、不按普通回血封顶")
	check(game.players[3].is_dead() and game.players[4].is_dead(), "扣除不受伤害减免影响，死亡狮子不回血")

	reset_case()
	owner = leo(2)
	owner.hand.append(hand)
	owner.judgment_cards.append(judgment)
	owner.equipment["armor"] = CardData.CardSubType.SILVER_LION
	await game._resolve_dying(owner, null, "test")
	check(owner.is_dead() and owner.identity_revealed and owner.hp == 0, "X=0 才最终死亡并公开，死亡弃狮子不回复")
	check(owner.hand.is_empty() and owner.equipment.is_empty() and owner.judgment_cards.is_empty(), "失败最终死亡清理三个牌区")

func check_nested():
	reset_case()
	var parent = leo(0)
	var child = leo(1, 2)
	game.players[2].hp = 2
	var ordinary: Array = []
	game.rule_scheduler.enqueue("ordinary", func(context, _stage):
		ordinary.append([context.victim, game.yudaxi.is_active(), game.players[2].is_dead()]))
	await game._resolve_dying(parent, null, "test")
	check(child.hp == 1 and child.is_alive() and parent.is_dead(), "子帧救回后父帧不把子帧死亡人数计入自己的 X")
	check(game.yudaxi.results.size() == 2, "嵌套产生两个独立结果")
	check(game.yudaxi.results[0].owner == child and game.yudaxi.results[0].deaths == 1, "子帧先完成且仅记录其直接死亡")
	check(game.yudaxi.results[1].owner == parent and game.yudaxi.results[1].deaths == 0, "父帧跳过已死目标，X仍为0")
	check(game.players[3].hp == 6 and game.players[4].hp == 6, "父帧恢复原游标，其余目标各受父子两次扣除")
	check(ordinary == [[parent, false, true]], "普通死亡前回调不插入预大习子帧")
	check(game._game_over and game._dying_contexts.is_empty(), "主公死亡在整段结算退出后判胜")

	reset_case()
	parent = leo(0)
	child = leo(1, 2)
	for i in range(2, 5):
		game.players[i].hp = 5
	await game._resolve_dying(parent, null, "test")
	check(child.is_dead() and parent.is_alive() and parent.hp == 1, "子帧 X=0 最终死亡，计入父帧直接目标死亡")
	check(game.yudaxi.results[0].deaths == 0 and game.yudaxi.results[1].deaths == 1, "死亡归属不是所有帧累加")
	check(not game._game_over, "嵌套期间不因主公暂时濒死而提前判负")

func check_saves():
	reset_case()
	var owner = leo(2)
	var target = game.players[3]
	target.hp = 2
	target.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	game._rescue_choice_override = func(rescuer, dying, options):
		return CardData.CardSubType.PEACH if rescuer == target and dying == target and options.has(CardData.CardSubType.PEACH) else -1
	await game._resolve_dying(owner, null, "test")
	check(target.hp == 1 and target.hand.is_empty(), "被扣至濒死仍可实际支付桃救援")
	check(owner.is_dead() and game.yudaxi.results[0].deaths == 0, "普通救回目标不计 X")

	reset_case()
	owner = leo(2)
	owner.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	owner.sage_activated = true
	game._sage_save_override = func(): return true
	await game._resolve_dying(owner, null, "test")
	check(owner.is_alive() and owner.hand.size() == 4, "可先发动贤者复原并摸四")
	check(game.yudaxi.results.is_empty() and game.players[3].hp == 10, "贤者成功不再发动预大习")

	reset_case()
	owner = leo(2)
	owner.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	owner.sage_activated = true
	var asks: Array = []
	game._sage_save_override = func():
		asks.append(true)
		return false
	game.players[3].hp = 2
	await game._resolve_dying(owner, null, "test")
	check(asks.size() == 1 and owner.hp == 1, "放弃贤者进入预大习后不重新询问贤者")
	check(owner.get_armor() == CardData.CardSubType.SAGE_PROTECTION, "成功保留未发动的贤者装备")

func check_order_and_limit():
	reset_case()
	var owner = leo(3)
	check(game._yudaxi_targets(owner) == [game.players[4], game.players[0], game.players[1], game.players[2]], "目标快照从发动者下家起算并绕桌")
	var order: Array = []
	var callbacks: Array[Callable] = []
	for p in game.players:
		var callback = func(_hp): order.append(p.seat_index)
		callbacks.append(callback)
		p.hp_changed.connect(callback)
	await game._resolve_dying(owner, null, "test")
	for i in game.players.size():
		game.players[i].hp_changed.disconnect(callbacks[i])
	check(order == [4, 0, 1, 2], "实际扣除顺序与下家快照一致")

	reset_case()
	owner = leo(2)
	owner.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game.yudaxi.step_limit = 1
	var outcomes: Array = []
	var on_over = func(winner): outcomes.append(winner)
	game.game_over.connect(on_over)
	await game._resolve_dying(owner, null, "test")
	game._refresh_status_line()
	game.game_over.disconnect(on_over)
	check(outcomes == ["平局"] and game._game_over, "安全阈值只提交一次平局")
	check(game.yudaxi.aborted and not game.yudaxi.is_active() and game._dying_contexts.is_empty(), "超限退出所有结算栈和濒死窗口")
	check(owner.is_dying() and owner.hand.size() == 1 and not owner.identity_revealed, "终止不伪造死亡、亮身份或清牌")
	check(game.players[3].hp == 10, "到达阈值后不继续扣除")
	check(not game._countdown_active and not game._countdown_on_timeout.is_valid(), "终局刷新不重新启动计时")

	reset_case()
	owner = leo(2, 1)
	game.yudaxi.step_limit = 1
	var chain = game._new_damage_chain(game.players[1], owner, null, 1, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	await chain.start()
	check(chain.is_cancelled and chain.current_phase == EffectChain.Phase.DONE, "超限平局取消外层真实伤害链")
	check(not chain.damage.events.has("after_deal_damage") and not chain.damage.events.has("after_take_damage"), "平局后不继续伤害后事件")
