# 2026-09-07 规则确认回归：代受/丈八/完整复原/真实体力/可恢复结算。
extends SceneTree

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
	game._nullify_override = func(): return false
	game._yes_ah_override = Callable()
	for p in game.players:
		p.reset_death_state()
		p.general_name = "稻草人"
		p.max_hp = 10
		p.hp = 10
		p.hand.clear()
		p.equipment.clear()
		p.chained = false
		p.kneeling = false
		p.awoken = false
		p.awake_choice = 0
		p.capture_game_start_state()

func strike(source: Player, target: Player, ignore_restrictions: bool = false):
	return await game._execute_single_strike(source, target,
		CardBase.create(CardData.CardSubType.STRIKE), CardData.CardSubType.STRIKE,
		EffectChain.DamageType.PHYSICAL, 1, ignore_restrictions)

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
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
