# 由 test_rule_settlement.gd 调用，复用核心 CI 的 RESULT 与失败计数。
extends RefCounted

var suite
var game: GameManager
const PEACH = CardData.CardSubType.PEACH
const WINE = CardData.CardSubType.WINE
const STRIKE = CardData.CardSubType.STRIKE

func check(ok: bool, message: String):
	suite.check(ok, "求救：" + message)

func reset_case():
	suite.reset_players()
	game._dying_peach_override = Callable()
	game._rescue_choice_override = Callable()
	var identities = ["主公", "忠臣", "反贼", "反贼", "内奸"]
	for i in game.players.size():
		var p = game.players[i]
		p.identity = identities[i]
		p.identity_revealed = i == 0
		p.judgment_cards.clear()
		p.determined_cards.clear()
		p.sage_activated = false

func run(host):
	suite = host
	game = host.game
	check_payments()
	await check_rounds()
	await check_ai()
	await check_prompts()
	reset_case()
	suite.reset_players()
	game = null
	suite = null

func check_payments():
	reset_case()
	var helper = game.players[0]
	var victim = game.players[2]
	helper.hp = 3
	victim.hp = 0
	var peach = CardBase.create(PEACH)
	var wine = CardBase.create(WINE)
	var wrong = CardBase.create(STRIKE)
	helper.hand.assign([peach, wine, wrong])
	check(game._rescue_options(helper, victim) == [PEACH], "救别人只允许桃，不把酒或杀冒充桃")
	check(not game._use_rescue_card(helper, victim, WINE) and helper.hand.size() == 3, "非法酒救别人不支付")
	check(game._use_rescue_card(helper, victim, PEACH), "有合法桃可救其他人")
	check(victim.hp == 1 and helper.hp == 3 and helper.hand == [wine, wrong], "治疗濒死者而非出牌者")
	check(game.deck._discard.count(peach) == 1, "原桃实例只入弃牌堆一次")
	helper.hand.append(null)
	check(not game._use_rescue_card(helper, victim, PEACH) and helper.hand == [wine, wrong, null], "已救回的过期选择不扣牌")
	victim.hp = 0
	check(game._use_rescue_card(helper, victim, PEACH) and game.deck._discard.back().sub_type == PEACH, "任意牌救援后具体化为桃")
	victim.hp = 0
	check(not game._use_rescue_card(helper, victim, PEACH), "错误具体牌不能凭空治疗")
	helper.hand.append(null)
	helper.hp = 0
	check(game._rescue_options(helper, victim).is_empty(), "另一濒死者不能作为普通救援者")
	helper.mark_dead()
	check(game._rescue_options(helper, victim).is_empty(), "已死亡者不能救援")
	helper.hp = 3
	helper.reset_death_state()
	helper.general_name = "布鲁斯·萨维奇"
	helper.kneeling = true
	check(game._rescue_options(helper, victim).is_empty(), "下跪者不能出牌救人")
	helper.kneeling = false
	victim.general_name = "布鲁斯·萨维奇"
	victim.kneeling = true
	check(game._rescue_options(helper, victim).is_empty(), "下跪的濒死者不能成为桃的目标")
	victim.kneeling = false
	victim.mark_dead()
	check(not game._use_rescue_card(helper, victim, PEACH), "桃不能复活最终死亡者")
	check(game._rescue_options(null, victim).is_empty() and game._rescue_options(helper, null).is_empty(), "无效角色不提供救援选项")

	reset_case()
	helper.hp = 3
	helper.equipment["weapon"] = CardData.CardSubType.HEAL_STAFF
	helper.hand.assign([null, null])
	victim.hp = -2
	check(game._use_rescue_card(helper, victim, PEACH) and victim.hp == 0, "治疗权杖第一张桃对负体力目标回复二点")
	check(helper.hp == 3 and helper.heal_staff_peach_used and not victim.heal_staff_peach_used, "权杖次数归出桃者，目标不占用次数也不回错人")
	check(game._use_rescue_card(helper, victim, PEACH) and victim.hp == 1, "第二张桃正常回复一点")
	victim.hp = 0
	victim.hand.append(null)
	victim.equipment["weapon"] = CardData.CardSubType.HEAL_STAFF
	check(game._use_dying_card(victim, PEACH) and victim.hp == 2, "别人出桃不消耗本人的权杖首次桃")

	reset_case()
	helper.hand.assign([null, null])
	helper.equipment["weapon"] = CardData.CardSubType.HEAL_STAFF
	victim.equipment["armor"] = CardData.CardSubType.QINGGANG_SHIELD
	victim.hp = -1
	check(game._use_rescue_card(helper, victim, PEACH) and victim.hp == 0 and helper.heal_staff_peach_used, "青釭盾目标无视出牌者武器，仍登记已使用第一张桃")
	victim.equipment.clear()
	check(game._use_rescue_card(helper, victim, PEACH) and victim.hp == 1, "解除青釭盾不会补触发第一张桃")

	reset_case()
	helper.hand.assign([null, null])
	victim.hp = -1
	game._use_rescue_card(helper, victim, PEACH)
	helper.equipment["weapon"] = CardData.CardSubType.HEAL_STAFF
	check(game._use_rescue_card(helper, victim, PEACH) and victim.hp == 1, "中途装备治疗权杖不能把第二张桃当第一张")

func check_rounds():
	reset_case()
	var victim = game.players[3]
	var visits: Array = []
	game.turn_manager.current_player_idx = 2
	for p in game.players:
		p.hand.append(null)
	victim.hp = -1
	game._rescue_choice_override = func(rescuer, target, options):
		visits.append(rescuer.seat_index)
		check(target == victim and options.has(PEACH), "每次询问指向实际濒死者并提供合法桃")
		return PEACH if rescuer.seat_index in [4, 0] else -1
	await game._resolve_dying(victim, null, "damage")
	check(visits == [2, 3, 4, 0], "从当前回合者开始轮询，救回后不再询问下一人")
	check(victim.hp == 1 and victim.hand == [null] and not victim.identity_revealed, "多人接力救回，放弃自救不丢牌、不翻身份")
	check(game.players[0].hand.is_empty() and game.players[4].hand.is_empty(), "仅实际救援者支付")

	reset_case()
	victim.hp = -2
	game.players[1].hand.assign([null, null, null, null])
	visits.clear()
	game._rescue_choice_override = func(rescuer, _target, _options):
		visits.append(rescuer.seat_index)
		return PEACH
	await game._resolve_dying(victim, null, "damage")
	check(visits == [1, 1, 1] and victim.hp == 1, "同一人可连续救援负体力目标")
	check(game.players[1].hand == [null], "达到一点后停止，不多收第四张牌")

	reset_case()
	victim.hp = -1
	victim.hand.append(null)
	game.players[4].hand.append(null)
	visits.clear()
	game._rescue_choice_override = func(rescuer, _target, _options):
		visits.append(rescuer.seat_index)
		return PEACH if rescuer.seat_index == 4 else -1
	await game._resolve_dying(victim, null, "damage")
	check(visits == [3, 4] and victim.is_dead(), "自己放弃后不回头重问，部分救援不足则最终死亡")
	check(game.players[4].hand.is_empty(), "救援不足不会返还已使用的桃")

	reset_case()
	victim.hp = 0
	game.players[0].hand.append(null)
	game._rescue_choice_override = func(rescuer, _target, _options):
		rescuer.hand.clear()
		return PEACH
	await game._run_rescue_round(victim)
	check(victim.hp == 0, "异步选择后已失去牌则不凭空救回")
	game.players[0].hand.append(null)
	game._rescue_choice_override = func(_rescuer, target, _options):
		target.hp = 1
		return PEACH
	await game._run_rescue_round(victim)
	check(victim.hp == 1 and game.players[0].hand == [null], "等待选择时已被其他效果救回，不再支付")

	reset_case()
	victim.hp = 0
	game.players[1].hand.append(null)
	game._rescue_choice_override = func(_rescuer, _target, _options): return WINE
	await game._run_rescue_round(victim)
	check(victim.hp == 0 and game.players[1].hand == [null], "决策钩子也不能绕过酒仅自救限制")
	var context = DyingContext.new(victim, null, "damage")
	context.stage = DyingContext.Stage.BEFORE_DEATH
	game._dying_contexts[victim] = context
	check(not game._use_rescue_card(game.players[1], victim, PEACH), "求救窗口已结束后不能补用桃")
	game._dying_contexts.clear()

	reset_case()
	victim.hp = 0
	victim.equipment["armor"] = CardData.CardSubType.SAGE_PROTECTION
	victim.sage_activated = true
	var retained = CardBase.create(STRIKE)
	victim.hand.append(retained)
	game.players[0].hand.append(null)
	var sage_calls: Array = []
	game._sage_save_override = func():
		sage_calls.append(true)
		return true
	game._rescue_choice_override = func(_rescuer, _target, _options): return PEACH
	await game._resolve_dying(victim, null, "damage")
	check(victim.is_alive() and sage_calls.is_empty() and victim.hand == [retained] and victim.sage_activated, "别人救回后不再询问贤者，也不执行贤者清牌")
	game._sage_save_override = Callable()

func check_ai():
	reset_case()
	var victim = game.players[2]
	victim.hp = -1
	victim.wine_stacks = 2
	victim.hand.assign([CardBase.create(WINE), CardBase.create(WINE)])
	await game._resolve_dying(victim, null, "damage")
	check(victim.hp == 1 and victim.hand.is_empty() and victim.wine_stacks == 2, "AI 可连续酒自救，不占用或增加进攻酒层数")

	reset_case()
	game.players[0].hp = 0
	game.players[1].hand.append(null)
	await game._resolve_dying(game.players[0], null, "damage")
	check(game.players[0].hp == 1 and game.players[1].hand.is_empty(), "忠臣 AI 使用真实牌救公开主公")

	reset_case()
	var helper = game.players[3]
	helper.hand.append(null)
	victim.hp = 0
	check(await game._ask_rescue_card(helper, victim) == -1, "隐藏身份即使实际同为反贼也不被 AI 偷看")
	victim.identity = "忠臣"
	check(await game._ask_rescue_card(helper, victim) == -1, "改变未公开身份不改变 AI 决策")
	victim.identity = "反贼"
	victim.identity_revealed = true
	check(await game._ask_rescue_card(helper, victim) == PEACH, "AI 可选择救公开反贼同伴")
	victim.identity = "内奸"
	check(await game._ask_rescue_card(helper, victim) == -1, "AI 不把公开敌人当同伴")
	victim.identity = ""
	check(await game._ask_rescue_card(helper, victim) == -1, "无身份不自动视为队友")

# 延后一帧操作真实弹窗；不依赖玩家输入或真实等待超时。
func respond_to_prompt(mode: String):
	var overlay = game.get_node_or_null("UI/RescuePrompt")
	check(overlay != null, "实际救援弹窗已打开")
	if overlay == null:
		return
	var buttons = overlay.find_children("*", "Button", true, false)
	var peach_button: Button
	var cancel_button: Button
	var has_wine := false
	for button in buttons:
		if button.text == "使用【桃】":
			peach_button = button
		elif button.text == "放弃":
			cancel_button = button
		elif button.text == "使用【酒】":
			has_wine = true
	check(peach_button != null and cancel_button != null and not has_wine, "救别人弹窗只提供桃与放弃")
	game._response_ready.emit() # 不得结束当前独立救援弹窗。
	check(not overlay.is_queued_for_deletion(), "其他响应信号不串入救援弹窗")
	if mode == "timeout":
		var timeout = game._countdown_on_timeout
		timeout.call()
	elif mode == "cancel":
		cancel_button.pressed.emit()
	else:
		peach_button.pressed.emit()
		peach_button.pressed.emit() # 重复点击只能提交一次。

func check_prompts():
	for mode in ["pay", "cancel", "timeout"]:
		reset_case()
		var victim = game.players[2]
		victim.hp = 0
		game.players[0].hand.assign([null, null])
		respond_to_prompt.call_deferred(mode)
		await game._run_rescue_round(victim)
		check(victim.hp == (1 if mode == "pay" else 0), "弹窗 %s 正确返回并结束本人的询问" % mode)
		check(game.players[0].hand.size() == (1 if mode == "pay" else 2), "弹窗 %s 不重复付费，拒绝/超时不扣牌" % mode)
		check(not game._countdown_active, "弹窗结束停止响应计时")
		await suite.process_frame
		check(game.get_node_or_null("UI/RescuePrompt") == null, "弹窗结束无残留遮罩")
