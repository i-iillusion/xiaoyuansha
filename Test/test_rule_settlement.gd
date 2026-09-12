# 2026-09-07 规则确认回归：代受/丈八/完整复原/真实体力/可恢复结算。
extends SceneTree

# 只在测试中观察实际入弃牌堆的瞬间，不给生产代码增加测试专用事件。
class DeathOrderDeck extends Deck:
	var on_discard: Callable

	func discard(card: CardBase):
		if on_discard.is_valid():
			on_discard.call(card)
		super.discard(card)

var failures := 0
var checks := 0
var game: GameManager
var observations: Array = []

func _init():
	_run()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)

func reset_players():
	game.reset_game_over_state()
	game._sacrifice_override = func(): return false
	game._dodge_override = func(): return false
	game._dying_peach_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	game._nullify_override = func(): return false
	game._yes_ah_override = Callable()
	game._aoe_override = func(): return false
	game._duel_respond_override = func(): return false
	game._duel_second_override = func(): return false
	game.turn_manager.current_player_idx = 0
	game.turn_manager.strike_count_this_turn = 0
	game.turn_manager._strike_actors_this_turn.clear()
	for p in game.players:
		p.reset_death_state()
		p.general_name = "稻草人"
		p.max_hp = 10
		p.hp = 10
		p.hand.clear()
		p.equipment.clear()
		p.chained = false
		p.kneeling = false
		p.wine_stacks = 0
		p.heal_staff_peach_used = false
		p.awoken = false
		p.awake_choice = 0
		p.capture_game_start_state()

func strike(source: Player, target: Player, ignore_restrictions: bool = false):
	return await game._execute_single_strike(source, target,
		CardBase.create(CardData.CardSubType.STRIKE), CardData.CardSubType.STRIKE,
		EffectChain.DamageType.PHYSICAL, 1, ignore_restrictions)

func check_death_order():
	reset_players()
	var original_deck = game.deck
	var observed_deck = DeathOrderDeck.new()
	game.deck = observed_deck
	var victim = game.players[2]
	var killer = game.players[0]
	var original_identity = victim.identity
	var original_revealed = victim.identity_revealed
	for p in game.players:
		p.judgment_cards.clear()
		p.determined_cards.clear()
	victim.identity = "反贼"
	victim.identity_revealed = false
	var hand_card = CardBase.create(CardData.CardSubType.STRIKE)
	var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
	var determined = CardBase.create(CardData.CardSubType.PEACH)
	victim.hand.append(hand_card)
	victim.equipment["armor"] = CardData.CardSubType.SILVER_LION
	victim.judgment_cards.append(judgment)
	victim.determined_cards.append(determined)
	victim.hp = 0

	# 普通求救结束不等于实际死亡；完整预大习尚未接入，不在此伪造技能验收。
	await game._check_dying(victim)
	check(victim.is_dying() and not game._dead_processed.has(victim), "未救回者在死亡前窗口仍是濒死，不提前确认死亡")
	check(not victim.identity_revealed and observed_deck.discard_count() == 0, "等待死亡前规则时不翻身份、不清牌")
	check(victim.hand == [hand_card] and victim.get_armor() == CardData.CardSubType.SILVER_LION, "等待死亡前规则时保留手牌和装备")
	check(victim.judgment_cards == [judgment] and victim.determined_cards == [determined], "等待死亡前规则时保留判定区和已确定牌")
	victim.hp = 1 # 模拟死亡前窗口已救回，只验证最终死亡入口的保护条件。
	game._handle_death(victim, killer)
	check(victim.is_alive() and not game._dead_processed.has(victim), "已救回者不进入最终死亡处理")
	check(not victim.identity_revealed and observed_deck.discard_count() == 0 and killer.hand.is_empty(), "已救回者不公开、不清牌、不发击杀奖励")
	check(victim.hand == [hand_card] and victim.get_armor() == CardData.CardSubType.SILVER_LION and victim.judgment_cards == [judgment] and victim.determined_cards == [determined], "已救回者保留全部原牌区")

	var discard_states: Array = []
	observed_deck.on_discard = func(_card):
		discard_states.append([victim.is_dead(), victim.identity_revealed, game._dead_processed.has(victim), killer.hand_size()])
		if discard_states.size() == 1:
			game._handle_death(victim, killer) # 清牌回调重入不能再次处理或提前发奖励。
	victim.hp = 0
	game._handle_death(victim, killer)
	check(discard_states == [[true, true, true, 0], [true, true, true, 0], [true, true, true, 0], [true, true, true, 0]], "每张牌清理时均已死亡并公开身份，奖惩尚未执行，重入不重复清牌")
	check(victim.is_dead() and victim.hp == 0, "死亡弃白银狮子不回复体力")
	check(victim.hand.is_empty() and victim.equipment.is_empty() and victim.judgment_cards.is_empty() and victim.determined_cards.is_empty(), "最终死亡清空全部牌区")
	check(observed_deck._discard.count(hand_card) == 1 and observed_deck._discard.count(judgment) == 1 and observed_deck._discard.count(determined) == 1, "手牌、判定牌和已确定牌原实例各弃置一次")
	check(game._dead_processed.count(victim) == 1 and killer.hand_size() == 3, "一次最终死亡只登记一次、发放一次反贼击杀奖励")
	game._handle_death(victim, killer)
	check(discard_states.size() == 4 and observed_deck.discard_count() == 4 and killer.hand_size() == 3, "完成后再次请求处理同一死亡也不重复清牌或奖惩")

	# 无身份的角色没有身份可翻；本例只覆盖死亡入口，不代表乱斗模式已实现。
	observed_deck.on_discard = Callable()
	reset_players()
	victim.identity = ""
	victim.identity_revealed = false
	victim.hand.append(hand_card)
	victim.hp = 0
	discard_states.clear()
	observed_deck.on_discard = func(_card):
		discard_states.append([victim.is_dead(), victim.identity_revealed])
	game._handle_death(victim, null)
	check(discard_states == [[true, false]] and victim.hand.is_empty(), "无身份角色实际死亡后正常清牌，不制造身份公开")
	check(killer.hand.is_empty(), "无击杀来源、无身份的死亡不产生击杀奖励")
	observed_deck.on_discard = Callable()
	game.deck = original_deck
	victim.identity = original_identity
	victim.identity_revealed = original_revealed
	reset_players()

# 只检查支付结果，不改变原有无懈轮询或代受结算时机。
func pay_response(sub: CardData.CardSubType) -> bool:
	if sub == CardData.CardSubType.NULLIFICATION:
		return await game._ask_nullification_round("支付回归") != ""
	return await game._maybe_sacrifice(game.players[2], game.players[1], 1, EffectChain.DamageType.PHYSICAL) != null

func check_trick_responses():
	var owner = game.players[0]
	for sub in [CardData.CardSubType.NULLIFICATION, CardData.CardSubType.SACRIFICE]:
		var label = CardData.get_type_name(sub)
		reset_players()
		var wrong = CardBase.create(CardData.CardSubType.PEACH)
		owner.hand.append(wrong)
		game._nullify_override = func(): return true
		game._sacrifice_override = func(): return true
		check(not await pay_response(sub), label + "：具体桃不能冒充响应牌")
		check(owner.hand == [wrong] and not game.deck._discard.has(wrong), label + "：类型不符保留原牌")

		var actual = CardBase.create(sub)
		owner.hand.push_front(actual)
		check(await pay_response(sub), label + "：匹配具体牌可支付")
		check(owner.hand == [wrong] and game.deck._discard.count(actual) == 1, label + "：原实例入弃牌堆一次，不扣末尾桃")

		owner.hand.append(null)
		var discard_before = game.deck._discard.size()
		check(await pay_response(sub), label + "：任意牌可响应")
		check(owner.hand == [wrong] and game.deck._discard.size() == discard_before + 1 and game.deck._discard.back().sub_type == sub, label + "：任意牌具体化后入弃牌堆")

		actual = CardBase.create(sub)
		owner.hand.append(actual)
		game._nullify_override = func(): return false
		game._sacrifice_override = func(): return false
		check(not await pay_response(sub) and owner.hand == [wrong, actual], label + "：放弃不扣牌")

		# 提示打开时可支付，返回时原牌已离手：不能改扣剩下的桃。
		var remove_response = func():
			owner.hand.erase(actual)
			return true
		game._nullify_override = remove_response
		game._sacrifice_override = remove_response
		check(not await pay_response(sub) and owner.hand == [wrong], label + "：弹窗返回后再次校验费用")

		game._nullify_override = func(): return true
		game._sacrifice_override = func(): return true
		owner.general_name = "安普提·斯丢皮得"
		discard_before = game.deck._discard.size()
		check(await pay_response(sub), label + "：无匹配牌仍可用是啊代付")
		check(owner.hp == 9 and owner.hand == [wrong] and game.deck._discard.size() == discard_before, label + "：代付只失血，不造实体弃牌")

		owner.hand.append(actual)
		game._yes_ah_override = func(): return "cancel"
		check(not await pay_response(sub) and owner.hp == 9 and owner.hand == [wrong, actual], label + "：取消是啊保留费用")
		game._yes_ah_override = func(): return "card"
		check(await pay_response(sub) and owner.hp == 9 and owner.hand == [wrong], label + "：拒绝技能后仍可支付匹配牌")

		# 下跪状态只对布鲁斯生效；这里模拟弹窗期间状态失效，不测试技能发动条件。
		owner.general_name = "布鲁斯·萨维奇"
		actual = CardBase.create(sub)
		owner.hand.append(actual)
		var kneel_on_prompt = func():
			owner.kneeling = true
			return true
		game._nullify_override = kneel_on_prompt
		game._sacrifice_override = kneel_on_prompt
		check(not await pay_response(sub) and owner.hand == [wrong, actual] and owner.hp == 9, label + "：弹窗期间下跪后不收费用")

func check_duel_aoe_payments():
	var owner = game.players[0]
	var opponent = game.players[1]
	for sub in [CardData.CardSubType.STRIKE, CardData.CardSubType.FIRE_STRIKE, CardData.CardSubType.THUNDER_STRIKE]:
		reset_players()
		var actual = CardBase.create(sub)
		var wrong = CardBase.create(CardData.CardSubType.PEACH)
		owner.hand.assign([actual, wrong, null])
		check(HandPayment.find_response_index(owner.hand, CardData.CardSubType.STRIKE) == 0, "响应杀优先具体牌，不先消耗任意牌")
		check(HandPayment.find_index(owner.hand, CardData.CardSubType.STRIKE, actual) == (0 if sub == CardData.CardSubType.STRIKE else -1), "主动声明仍严格匹配，不受响应族匹配影响")
		owner.hand.pop_back() # 本场只保留实际响应牌与错误类型。
		owner.wine_stacks = 2
		game.turn_manager.strike_count_this_turn = 1
		game._duel_respond_override = func(): return true
		await game._play_duel(opponent, owner)
		check(owner.hp == 10 and opponent.hp == 9, "普通/属性杀均可响应决斗，对手未响应后承担普通伤害")
		check(owner.hand == [wrong] and game.deck._discard.count(actual) == 1 and actual.sub_type == sub, "决斗保留响应原牌与原类型，不扣末尾桃")
		check(owner.wine_stacks == 2 and game.turn_manager.strike_count_this_turn == 1, "响应杀不消耗酒和主动杀次数")

	reset_players()
	var peach = CardBase.create(CardData.CardSubType.PEACH)
	owner.hand.append(peach)
	game._duel_respond_override = func(): return true
	await game._play_duel(opponent, owner)
	check(owner.hp == 9 and owner.hand == [peach], "决斗没有杀时不拿桃冒充")

	# 霸王必须依次支付，第二张缺少/拒绝时第一张不退回。
	for second_mode in ["missing", "decline", "accept", "removed"]:
		reset_players()
		opponent.general_name = "杰基·斯特朗"
		var first = CardBase.create(CardData.CardSubType.THUNDER_STRIKE)
		var second = CardBase.create(CardData.CardSubType.FIRE_STRIKE)
		owner.hand.assign([peach, first])
		if second_mode != "missing":
			owner.hand.push_front(second)
		game._duel_respond_override = func(): return true
		game._duel_second_override = func():
			if second_mode == "removed":
				owner.hand.erase(second)
			return second_mode != "decline"
		await game._play_duel(opponent, owner)
		check(game.deck._discard.count(first) == 1, "霸王：第一张杀实际支付且不退回")
		check(owner.hp == (10 if second_mode == "accept" else 9) and opponent.hp == (9 if second_mode == "accept" else 10), "霸王：两张成功才交换响应方")
		check(game.deck._discard.count(second) == (1 if second_mode == "accept" else 0) and owner.hand.has(peach), "霸王：第二张失败不扣错牌、不虚构弃牌")

	for required in [CardData.CardSubType.STRIKE, CardData.CardSubType.DODGE]:
		for mode in ["actual", "blank", "wrong", "decline", "removed"]:
			reset_players()
			var aoe = CardData.CardSubType.BARBARIAN_INVASION if required == CardData.CardSubType.STRIKE else CardData.CardSubType.VOLLEY_OF_ARROWS
			var response_sub = CardData.CardSubType.FIRE_STRIKE if required == CardData.CardSubType.STRIKE else CardData.CardSubType.DODGE
			var actual = CardBase.create(response_sub)
			owner.hand.append(peach)
			if mode == "blank":
				owner.hand.append(null)
			elif mode != "wrong":
				owner.hand.push_front(actual)
			if required == CardData.CardSubType.DODGE:
				owner.equipment["armor"] = CardData.CardSubType.BAGUA_ZHEN
			opponent.hand.append(CardBase.create(aoe))
			game.turn_manager.current_player_idx = 1
			game._aoe_override = func():
				if mode == "removed":
					owner.hand.erase(actual)
				return mode != "decline"
			var discard_before = game.deck._discard.size()
			await game._play_aoe(required, CardData.get_type_name(aoe), CardData.get_type_name(required))
			var paid = mode in ["actual", "blank"]
			check(owner.hp == (10 if paid else 9) and owner.hand.has(peach), "AOE：只有真实支付成功才避免伤害，保留桃")
			check(game.deck._discard.size() == discard_before + (2 if paid else 1), "AOE：使用牌和成功响应各入弃牌堆一次")
			if mode == "actual":
				check(game.deck._discard.count(actual) == 1 and actual.sub_type == response_sub, "AOE：响应保留原实例与属性")
			if mode == "blank":
				check(game.deck._discard.back().sub_type == required, "AOE：任意牌默认具体化为所需基本牌")
			if required == CardData.CardSubType.DODGE:
				check(owner.hand.count(null) == (1 if paid else 0), "万箭：八卦只在实际支付闪后摸一张")
	reset_players()

func check_qinglong_history():
	# 独立状态机验证边界，不触发对局的回合开始 UI。
	var turns = TurnManager.new()
	turns.debug_log = false
	turns.start_game()
	check(turns.record_strike_played(0) and turns.record_strike_played(1), "青龙：各座位独立记录第一次杀")
	check(not turns.record_strike_played(0) and turns.strikes_used() == 0, "青龙：响应历史不占主动杀次数")
	turns.start_waiting("test", 1)
	turns.end_waiting()
	check(not turns.record_strike_played(1), "青龙：响应返回不清空历史")
	turns.current_phase = TurnManager.Phase.DRAW
	turns.advance_phase()
	check(not turns.record_strike_played(0), "青龙：摸牌后进入出牌阶段不重置历史")
	turns.next_turn()
	check(turns.record_strike_played(0) and turns.record_strike_played(1), "青龙：下一角色回合重置全部座位")
	turns.skip_full_turn = true
	turns.advance_phase()
	turns.next_turn()
	check(turns.record_strike_played(0), "青龙：跳过回合后仍按新回合重置")
	turns.start_game()
	check(turns.record_strike_played(0), "青龙：新对局不继承旧历史")
	turns.free()

	reset_players()
	var owner = game.players[0]
	var opponent = game.players[1]
	owner.equipment["weapon"] = CardData.CardSubType.QINGLONG_BLADE
	var peach = CardBase.create(CardData.CardSubType.PEACH)
	owner.hand.append(peach)
	check(not await game._ask_basic_card_response(owner, CardData.CardSubType.STRIKE, func(): return true), "青龙：缺少杀不能借摸牌支付")
	var first = CardBase.create(CardData.CardSubType.FIRE_STRIKE)
	owner.hand.push_front(first)
	check(not await game._ask_basic_card_response(owner, CardData.CardSubType.STRIKE, func(): return false), "青龙：拒绝响应不登记首次")
	check(await game._ask_basic_card_response(owner, CardData.CardSubType.STRIKE, func(): return true), "青龙：支付属性杀响应成功")
	check(owner.hand == [peach, null] and game.deck._discard.count(first) == 1, "青龙：实际响应牌先弃置，首次响应再摸一张")
	await game.execute_card_on_target(opponent, CardData.CardSubType.STRIKE)
	check(owner.hand == [peach] and game.turn_manager.strikes_used() == 1, "青龙：同回合响应后主动杀不再次摸牌")

	reset_players()
	owner.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	await game.execute_card_on_target(opponent, CardData.CardSubType.STRIKE)
	owner.equipment["weapon"] = CardData.CardSubType.QINGLONG_BLADE
	owner.hand.append(CardBase.create(CardData.CardSubType.THUNDER_STRIKE))
	await game._ask_basic_card_response(owner, CardData.CardSubType.STRIKE, func(): return true)
	check(owner.hand.is_empty(), "青龙：未装备时打过杀，中途装备不能补触发")

	reset_players()
	owner.equipment["weapon"] = CardData.CardSubType.QINGLONG_BLADE
	owner.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	opponent.general_name = "杰基·斯特朗"
	game._duel_respond_override = func(): return true
	game._duel_second_override = func(): return true
	await game._play_duel(opponent, owner)
	check(owner.hp == 10 and opponent.hp == 9 and owner.hand.is_empty(), "青龙：霸王第一张杀摸到的任意牌可支付第二张，仅摸一次")
	check(game.turn_manager.strikes_used() == 0, "青龙：霸王两次响应仍不占主动杀次数")

	reset_players()
	owner.general_name = "比尔·盖伊"
	owner.equipment["weapon"] = CardData.CardSubType.QINGLONG_BLADE
	await game._execute_shensu_strike(owner, opponent)
	check(owner.hand == [null] and game.turn_manager.strikes_used() == 0, "青龙：神速视为使用杀计入首次，但不占主动杀次数")
	await game.execute_card_on_target(opponent, CardData.CardSubType.STRIKE)
	check(owner.hand.is_empty(), "青龙：神速后同回合主动杀不再次摸牌")

	reset_players()
	# 多目标入口只登记一次使用；方天与青龙不能同时装备，不构造双武器规则。
	owner.equipment["weapon"] = CardData.CardSubType.FANGTIAN_HALBERD
	owner.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	var targets: Array[Player] = [opponent, game.players[2]]
	await game.execute_multi_strike(targets, CardData.CardSubType.STRIKE)
	check(not game.turn_manager.record_strike_played(owner.seat_index) and game.turn_manager.strikes_used() == 1, "多目标杀登记使用历史且只占一次主动次数")
	reset_players()

func check_dying_payments():
	var owner = game.players[0]
	for sub in [CardData.CardSubType.PEACH, CardData.CardSubType.WINE]:
		reset_players()
		owner.hp = 0
		owner.heal_staff_peach_used = false
		owner.wine_stacks = 2
		var wrong = CardBase.create(CardData.CardSubType.STRIKE)
		owner.hand.append(wrong)
		check(not game._use_dying_card(owner, sub) and owner.hp == 0 and owner.hand == [wrong], "自救：不能将具体杀冒充桃或酒")
		var actual = CardBase.create(sub)
		owner.hand.push_front(actual)
		check(game._use_dying_card(owner, sub), "自救：濒死本人可支付对应具体牌")
		check(owner.hp == 1 and owner.hand == [wrong] and game.deck._discard.count(actual) == 1, "自救：原实例只弃置一次，保留末尾其他牌")
		check(owner.wine_stacks == 2, "自救：不消耗或增加攻击酒层数")
		owner.hand.append(null)
		check(not game._use_dying_card(owner, sub) and owner.hand == [wrong, null], "自救：已救回的过期操作不收费用")
		owner.hp = 0
		check(game._use_dying_card(owner, sub) and owner.hp == 1 and owner.hand == [wrong], "自救：任意牌可具体化为桃或酒")
		check(game.deck._discard.back().sub_type == sub, "自救：任意牌按实际声明类型入弃牌堆")
		owner.hp = 0
		owner.mark_dead()
		owner.hand.append(null)
		check(not game._use_dying_card(owner, sub) and owner.hand == [wrong, null], "自救：已死亡不能用牌复活")

	reset_players()
	owner.hp = -2
	owner.hand.assign([null, null, null])
	game._dying_peach_override = func(): return true
	await game._check_dying(owner)
	check(owner.hp == 1 and owner.hand.is_empty(), "负体力自救可连续使用三张任意牌")

	reset_players()
	owner.hp = 0
	owner.hand.append(null)
	await game._show_dying_prompt(owner) # 默认钩子拒绝。
	check(owner.hp == 0 and owner.hand == [null], "自救：放弃保留任意牌和体力")
	game._dying_peach_override = func():
		owner.hand.clear() # 模拟提示返回前费用已离手。
		return true
	await game._show_dying_prompt(owner)
	check(owner.hp == 0, "自救：确认时无牌不凭空回复")

	reset_players()
	owner.hp = -1
	owner.equipment["weapon"] = CardData.CardSubType.HEAL_STAFF
	owner.heal_staff_peach_used = false
	check(not game._use_dying_card(owner, CardData.CardSubType.PEACH) and not owner.heal_staff_peach_used, "自救：支付失败不消耗治疗权杖首次桃")
	owner.hand.append(null)
	check(game._use_dying_card(owner, CardData.CardSubType.PEACH) and owner.hp == 1 and owner.heal_staff_peach_used, "自救：先付桃再应用治疗权杖")
	reset_players()

# 四个生产入口必须经过同一个死亡前窗口；回调只模拟规则的保命结果，非完整预大习。
func check_dying_windows():
	var actor = game.players[2]
	var target = game.players[1]
	var lord = game.players[0]
	for route in ["damage", "zhangba", "liehuo", "yes_ah"]:
		for save in [true, false]:
			reset_players()
			actor.identity_revealed = false
			actor.judgment_cards.clear()
			actor.determined_cards.clear()
			actor.hp = 1
			var card = CardBase.create(CardData.CardSubType.STRIKE)
			var judgment = CardBase.create(CardData.CardSubType.INDULGENCE)
			actor.hand.append(card)
			actor.judgment_cards.append(judgment)
			var windows: Array = []
			var label = "%s/%s：" % [route, "救回" if save else "死亡"]
			var rule = func(context, stage):
				windows.append(context)
				check(context is DyingContext and stage == "before_death" and context.stage == DyingContext.Stage.BEFORE_DEATH, label + "使用显式死亡前上下文")
				check(context.victim == actor and context.cause == route and context.killer == (lord if route == "damage" else null), label + "保留真正的濒死者与原因，流失无击杀来源")
				check(actor.is_dying() and not actor.identity_revealed and actor.hand == [card] and actor.judgment_cards == [judgment], label + "规则开始前未死亡、未亮身份、未清牌")
				game._handle_death(actor, lord)
				await game._resolve_dying(actor, lord, "duplicate")
				check(actor.is_dying() and not game._dead_processed.has(actor) and game._dying_contexts[actor] == context, label + "回调不能提前提交死亡或重开同一窗口")
				await process_frame
				if save:
					actor.hp = 1
			var chain: EffectChain = null
			if route == "damage":
				chain = game._new_damage_chain(lord, actor, null, 1, EffectChain.DamageType.PHYSICAL)
				chain.skip_targeting = true
				var callback = game._on_chain_trigger
				chain.trigger_callback = func(current, event, subject, source, data):
					if event == "damage_applied":
						game.rule_scheduler.enqueue("死亡前入口回归", rule)
					return await callback.call(current, event, subject, source, data)
				await chain.start()
			elif route == "zhangba":
				actor.equipment["weapon"] = CardData.CardSubType.ZHANGBA_SPEAR
				game._zhangba_override = func():
					game.rule_scheduler.enqueue("死亡前入口回归", rule)
					return 1
				chain = game._new_damage_chain(actor, target, CardBase.create(CardData.CardSubType.STRIKE), 1, EffectChain.DamageType.PHYSICAL)
				await chain.start()
				check(target.hp == 8 and chain.damage.source == (actor if save else null), label + "恢复原杀且只提交一次伤害，来源只在最终死亡后清除")
			elif route == "liehuo":
				actor.equipment["armor"] = CardData.CardSubType.LIEHUO_SHIELD
				game._liehuo_override = func():
					game.rule_scheduler.enqueue("死亡前入口回归", rule)
					return true
				check(await game._maybe_liehuo_save(actor), label + "完成原有体力支付")
			else:
				game.rule_scheduler.enqueue("死亡前入口回归", rule)
				check(await game._pay_yes_ah_cost(actor) == save, label + "费用入口按最终是否救回返回，死亡则中止后续锦囊")
			check(windows.size() == 1 and windows[0].stage == DyingContext.Stage.FINISHED and game._dying_contexts.is_empty(), label + "窗口仅执行一次，完成后无活动上下文残留")
			check(windows[0].effect_chain == chain, label + "链内保留原链，链外不伪造伤害链")
			if save:
				check(actor.is_alive() and not actor.identity_revealed and actor.hand == [card] and actor.judgment_cards == [judgment], label + "规则救回后保留牌区与隐藏身份")
			else:
				check(actor.is_dead() and actor.identity_revealed and actor.hand.is_empty() and actor.judgment_cards.is_empty() and game._dead_processed.count(actor) == 1, label + "规则未救回才提交一次最终死亡")
			check(lord.hand_size() == (3 if route == "damage" and not save else 0), label + "只有有来源伤害击杀反贼才发奖励")
			# 上下文引用原链；释放测试观察记录/回调，避免形成引用环。
			windows.clear()
			if chain != null:
				chain.trigger_callback = Callable()
	game._zhangba_override = Callable()
	game._liehuo_override = Callable()

	reset_players()
	lord.hp = 0
	lord.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	game._dying_peach_override = func(): return true
	var skipped: Array = []
	game.rule_scheduler.enqueue("不应进入的死亡前窗口", func(_context, _stage): skipped.append(true))
	await game._resolve_dying(lord, actor, "damage")
	check(lord.is_alive() and lord.hand.is_empty() and not game._dead_processed.has(lord), "普通桃自救先完成支付并阻止死亡")
	check(skipped.is_empty() and game._dying_contexts.is_empty(), "普通求救已救回时不再开放死亡前窗口")
	game.rule_scheduler._pending.clear() # 丢弃本例未执行的测试回调，不影响后续例子。

	# 父窗口暂时救回，但规则尚未返回；子窗口杀死最后一个敌人也不能抢先终局。
	reset_players()
	for index in [3, 4]:
		game.players[index].hp = 0
		game.players[index].mark_dead()
	lord.hp = 0
	var timeline: Array = []
	var on_winner = func(winner): timeline.append(winner)
	game.game_over.connect(on_winner)
	game.rule_scheduler.enqueue("嵌套窗口回归", func(parent, _stage):
		timeline.append("parent")
		lord.hp = 1
		actor.hp = 0
		game.rule_scheduler.enqueue("子窗口回归", func(child, _child_stage):
			check(child.victim == actor and parent.victim == lord and game._dying_contexts.size() == 2, "嵌套窗口分别记录濒死者，不覆盖父窗口")
			timeline.append("child")
		)
		await game._resolve_dying(actor, lord, "damage")
		check(actor.is_dead() and lord.hand_size() == 3, "子窗口先完成实际死亡与原有奖惩")
		game._check_win_condition(null, null)
		check(not game._game_over and game._dying_contexts.size() == 1, "即使已无濒死者，父窗口仍未完成时也不提前判胜")
		await process_frame
		timeline.append("parent:end")
	)
	await game._resolve_dying(lord, null, "damage")
	check(timeline == ["parent", "child", "parent:end", "主公"], "最外层窗口返回后再宣告胜利，顺序不受暂时救回影响")
	check(game._dying_contexts.is_empty() and not game.rule_scheduler.is_paused(), "嵌套结束后上下文与调度帧均释放")
	game.game_over.disconnect(on_winner)
	reset_players()
	await process_frame

func _run():
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_general = "稻草人"
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	game.start_game()
	game._stop_countdown()
	var c = game.players[0]
	var b = game.players[1]
	var a = game.players[2]
	await check_trick_responses()
	await check_duel_aoe_payments()
	await check_qinglong_history()
	await check_dying_payments()

	reset_players()
	c.hand.append(CardBase.create(CardData.CardSubType.DODGE))
	c.hand.append(CardBase.create(CardData.CardSubType.SACRIFICE))
	b.hand.append(CardBase.create(CardData.CardSubType.STRIKE))
	game._sacrifice_override = func(): return true
	game._dodge_override = func():
		observations.append(c.hand_size())
		return true
	await strike(a, b)
	check(b.hp == 10 and b.hand_size() == 1, "B 不扣血，也不替代受者出闪")
	check(c.hp == 10 and c.hand_size() == 0, "C 支付舍己为人和闪，成功躲避")
	check(observations == [1], "只询问实际目标 C 一次，且已先支付代受费用")

	reset_players()
	var wrong_dodge = CardBase.create(CardData.CardSubType.PEACH)
	c.hand.append(wrong_dodge)
	game._dodge_override = func(): return true
	await strike(b, c)
	check(c.hp == 9 and c.hand == [wrong_dodge], "桃不能当闪响应，即使测试钩子答应出闪也不扣错牌")
	check(not game.deck._discard.has(wrong_dodge), "无合法闪不会把其他具体牌放入弃牌堆")

	reset_players()
	var actual_dodge = CardBase.create(CardData.CardSubType.DODGE)
	c.hand.append(actual_dodge)
	c.equipment["armor"] = CardData.CardSubType.BAGUA_ZHEN
	game._dodge_override = func(): return true
	await strike(b, c)
	check(c.hp == 10, "实际闪成功防止本次杀伤害")
	check(game.deck._discard.count(actual_dodge) == 1, "响应闪原实例只进入弃牌堆一次")
	check(c.hand.size() == 1 and c.hand[0] == null, "先支付实际闪，再通过八卦摸任意牌")

	reset_players()
	c.hand.append(CardBase.create(CardData.CardSubType.SACRIFICE))
	b.equipment["armor"] = CardData.CardSubType.SILVER_LION
	a.equipment["weapon"] = CardData.CardSubType.ZHANGBA_SPEAR
	game._sacrifice_override = func(): return true
	game._zhangba_override = func():
		check(c.hp == 10 and b.hp == 10, "丈八询问时尚未扣血")
		return 3
	await strike(a, b)
	check(a.hp == 7 and c.hp == 6 and b.hp == 10, "丈八加成给 C，B 的白银狮子不参与减伤")

	reset_players()
	a.equipment["weapon"] = CardData.CardSubType.ZHANGBA_SPEAR
	b.equipment["armor"] = CardData.CardSubType.CALAMITY_ROBE
	game._zhangba_override = func(): return 2
	var chain = game._new_damage_chain(a, b, CardBase.create(CardData.CardSubType.FIRE_STRIKE), 1, EffectChain.DamageType.FIRE)
	await chain.start()
	check(b.hp == 6 and chain.damage.applied_amount == 4, "基础1+丈八2+灾厄袍1，只修正和扣血一次")
	await chain.start()
	check(b.hp == 6, "重复启动同一条链不再次扣血")
	check(chain.damage.hp_before == 10 and chain.damage.hp_after == 6, "记录保留扣血前后体力")
	check(chain.damage.events == ["on_play_card", "on_being_targeted", "before_deal_damage", "before_take_damage", "damage_applied", "after_deal_damage", "after_take_damage"], "普通结算阶段顺序固定")

	reset_players()
	a.equipment["weapon"] = CardData.CardSubType.ZHANGBA_SPEAR
	b.equipment["armor"] = CardData.CardSubType.SILVER_LION
	await strike(a, b)
	check(b.hp == 9, "白银狮子在丈八合并后封顶一次")

	reset_players()
	b.equipment["armor"] = CardData.CardSubType.TENGJIA
	# 忽略目标限制不取消响应；响应必须有真实闪或任意牌，不能拿具体杀冒充。
	b.hand.append(CardBase.create(CardData.CardSubType.DODGE))
	check(not await strike(a, b), "通常不能选择藤甲为杀的目标")
	game._dodge_override = func(): return true
	await strike(a, b, true)
	check(b.hp == 10 and b.hand_size() == 0, "忽略目标限制仍可出闪")
	b.equipment["armor"] = CardData.CardSubType.BAIHUA_SKIRT
	b.hp = 1
	await strike(a, b, true)
	check(b.hp == 1, "忽略目标限制不取消百花裙伤害免疫")

	reset_players()
	a.hp = 1
	a.take_damage(3)
	check(a.hp == -2 and a.is_dying() and not a.is_dead(), "负体力仍为濒死，不是已死亡")
	a.heal(1)
	check(a.hp == -1 and a.is_dying(), "负体力救援保留欠缺值")
	a.mark_dead()
	a.heal(10)
	check(a.hp == -1 and a.is_dead(), "普通回复不能复活已死亡角色")
	var record = DamageRecord.new(a, b, null, 1)
	record.refresh_source()
	check(record.source == null and record.original_source == a, "来源阵亡后改为无来源，保留追溯信息")
	b.hp = 12
	b.heal(1)
	check(b.hp == 12, "特殊超上限体力不会因普通回复而被压低")
	b.take_damage(1)
	check(b.hp == 11, "超上限体力正常承担伤害")

	reset_players()
	a.hp = 1
	a.equipment["weapon"] = CardData.CardSubType.ZHANGBA_SPEAR
	game._zhangba_override = func(): return 1
	chain = game._new_damage_chain(a, b, CardBase.create(CardData.CardSubType.STRIKE), 1, EffectChain.DamageType.PHYSICAL)
	await chain.start()
	check(a.is_dead() and b.hp == 8, "丈八支付流失致死后，已发起伤害继续结算")
	check(chain.damage.source == null, "该次剩余伤害以无来源提交")

	reset_players()
	c.general_name = "史蒂芬·彼特先斯"
	c.max_hp = 3
	c.capture_game_start_state()
	c.awoken = true
	c.awake_choice = 1
	c.kneel_used = true
	c.max_hp = 2
	c.hp = 0
	c.facedown = true
	c.chained = true
	c.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	c.sage_activated = true
	c.determined_cards.append(CardBase.create(CardData.CardSubType.STRIKE))
	c.judgment_cards.append(CardBase.create(CardData.CardSubType.LIGHTNING))
	game._do_sage_save(c)
	check(c.hp == 3 and c.max_hp == 3 and c.is_alive(), "贤者恢复开局体力上限与满体力")
	check(not c.awoken and c.awake_choice == 0 and not c.kneel_used, "贤者恢复觉醒、选项和限定技状态")
	check(not c.facedown and not c.chained and not c.sage_activated, "贤者清除翻面、连环和装备状态")
	check(c.hand_size() == 4 and c.determined_cards.is_empty() and c.equipment.is_empty() and c.judgment_cards.is_empty(), "所有旧牌清理后摸四张，不会因中间空手再次觉醒")

	b.general_name = "比尔·盖伊"
	b.capture_game_start_state()
	b.shensu_penalty = 3
	b.shensu_used_this_turn = true
	b.hp = 0
	game._do_sage_save(b)
	check(b.shensu_penalty == 0 and not b.shensu_used_this_turn, "贤者同样恢复上游新增武将的神速状态")

	reset_players()
	observations.clear()
	chain = game._new_damage_chain(a, b, null, 1, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	chain.skip_response = true
	game.rule_scheduler.enqueue("低优先级测试", func(_context, _stage): observations.append("low"), 0)
	game.rule_scheduler.enqueue("高优先级测试", func(context, stage):
		check(context == chain and stage == "before_deal_damage", "暂停保留当前链与阶段")
		check(game.rule_scheduler.is_paused() and b.hp == 10, "规则完成前不扣血")
		observations.append("high:start")
		await process_frame
		context.damage.amount = 2
		observations.append("high:end")
	, 100)
	await chain.start()
	check(observations == ["high:start", "high:end", "low"], "按优先级完成异步规则后继续")
	check(not game.rule_scheduler.is_paused() and b.hp == 8, "恢复原链，保留单独规则对记录的修改且只扣一次")

	reset_players()
	c.equipment["armor"] = CardData.CardSubType.QIXING_PAO
	chain = game._new_damage_chain(a, b, null, 1, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	game.rule_scheduler.enqueue("修改记录的测试规则", func(context, _stage):
		context.damage.target = c
		context.damage.element = EffectChain.DamageType.FIRE
	)
	await chain.start()
	check(chain.damage.original_target == b and chain.target_player == c, "暂停期间更换目标保留原目标记录")
	check(not chain.damage.committed and c.hp == 10, "暂停期间改变属性后按新目标七星袍判定")

	chain = game._new_damage_chain(a, b, null, 1, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	game.rule_scheduler.enqueue("取消链的测试规则", func(context, _stage): context.is_cancelled = true)
	await chain.start()
	check(not chain.damage.committed and b.hp == 10, "高优先级取消后不执行普通伤害")

	reset_players()
	c.hp = -2
	for i in range(3):
		c.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	game._dying_peach_override = func(): return true
	await game._check_dying(c)
	check(c.hp == 1 and c.hand_size() == 0, "负二体力可连续使用三张桃救回至一体力")

	reset_players()
	b.chained = true
	c.chained = true
	b.hp = 1
	await game._deal_damage(null, b, 2, EffectChain.DamageType.FIRE)
	check(b.is_dead() and c.hp == 8, "首个目标死亡后，无来源属性伤害仍正常传导")
	check(not b.chained and not c.chained, "本次连环不会重复传导")

	reset_players()
	b.hp = 1
	chain = game._new_damage_chain(a, b, null, 2, EffectChain.DamageType.PHYSICAL)
	chain.skip_targeting = true
	observations.clear()
	var callback = game._on_chain_trigger
	chain.trigger_callback = func(current, event, subject, source, data):
		if event == "after_deal_damage":
			observations.append(b.is_dead())
		return await callback.call(current, event, subject, source, data)
	await chain.start()
	check(observations == [true], "濒死/死亡先于普通伤害后技能")
	await check_death_order()
	await check_dying_windows()
	var rescue_cases = load("res://Test/rescue_cases.gd").new()
	await rescue_cases.run(self)
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
