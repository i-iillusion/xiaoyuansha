# ST-09：物理手牌支付、即时/延时锦囊去向，以及「已确定的牌」主动再使用入口。
extends SceneTree

var checks := 0
var failures := 0
var game: GameManager

func _init():
	_run()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)

func check_selection():
	var peach := CardBase.create(CardData.CardSubType.PEACH)
	var strike := CardBase.create(CardData.CardSubType.STRIKE)
	var hand: Array[CardBase] = [null, peach, strike]
	check(HandPayment.find_index(hand, CardData.CardSubType.PEACH) == 1, "预查找到同类型具体牌")
	check(hand == [null, peach, strike], "预查不移除或具体化手牌")
	check(HandPayment.take(hand, CardData.CardSubType.PEACH) == peach, "优先取原具体牌，不消耗末尾杀")
	check(hand == [null, strike], "支付只移除所选对象")
	var wine := HandPayment.take(hand, CardData.CardSubType.WINE)
	check(wine != null and wine.sub_type == CardData.CardSubType.WINE, "空白手牌在支付时具体化")
	check(hand == [strike], "声明任意牌不改变其他具体牌")
	check(HandPayment.take(hand, CardData.CardSubType.DISARM) == null, "杀不能冒充卸甲归田")
	check(hand == [strike], "支付失败无副作用")
	hand.append(null)
	check(HandPayment.take(hand, CardData.CardSubType.PEACH, strike) == null, "显式选择错误类型不偷换为任意牌")
	check(HandPayment.take(hand, CardData.CardSubType.PEACH, peach) == null, "显式选择已离手对象不扣其他牌")
	check(hand == [strike, null], "两次无效显式选择都不收费用")
	check(HandPayment.take(hand, CardData.CardSubType.STRIKE, strike) == strike, "有效显式选择保持原实例")

func reset_case():
	for p in game.players:
		p.hp = p.max_hp
		p.hand.clear()
		p.determined_cards.clear()
		p.judgment_cards.clear()
		p.equipment.clear()
		p.chained = false
		p.wine_stacks = 0
		p.mount_minus = 0
		p.mount_plus = 0
	game.reset_game_over_state()
	game.turn_manager.strike_count_this_turn = 0
	game.turn_manager._strike_actors_this_turn.clear()
	game._stop_countdown()
	game.deck._discard.clear()
	game._yes_ah_active = false
	game._clear_pending_determined_card()
	game._is_targeting = false
	game._is_multi_targeting = false
	game._is_iron_chain_targeting = false
	game._dying_peach_override = func(): return false
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game._dodge_override = func(): return false
	game._target_confirm_override = func(): return true

func _run():
	check_selection()
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 5
	GameManager.selected_general = "稻草人"
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	game.start_game()
	var owner := game.players[0]
	var other := game.players[1]
	var spare := CardBase.create(CardData.CardSubType.STRIKE)

	reset_case()
	var disarm := CardBase.create(CardData.CardSubType.DISARM)
	owner.hand.assign([disarm, spare])
	check(await game._consume_trick(owner, CardData.CardSubType.DISARM), "即时锦囊支付成功")
	check(owner.hand == [spare] and game.deck._discard == [disarm], "即时锦囊将原实例入弃牌堆，不误扣末尾牌")
	check(not await game._consume_trick(owner, CardData.CardSubType.SNATCH), "缺少声明类型时拒绝锦囊支付")
	check(owner.hand == [spare] and game.deck._discard == [disarm], "失败不会生成弃牌或消耗杀")

	for sub in [CardData.CardSubType.LIGHTNING, CardData.CardSubType.INDULGENCE,
			CardData.CardSubType.SUPPLY_SHORTAGE, CardData.CardSubType.BURNING_CAMP]:
		reset_case()
		var delayed := CardBase.create(sub)
		delayed.source_seat = 4
		owner.hand.assign([delayed, spare])
		var target := owner if sub == CardData.CardSubType.LIGHTNING else other
		if target == owner:
			await game.play_card(sub)
		else:
			await game.execute_card_on_target(target, sub)
		check(target.judgment_cards == [delayed], "延时锦囊使用原资源进入判定区：" + delayed.card_name)
		check(owner.hand == [spare] and game.deck.discard_count() == 0, "放置时不同时入弃牌堆、不误扣其他牌")
		check(delayed.source_seat == owner.seat_index, "再次使用时更新放置者来源")

	reset_case()
	owner.hp = 2
	owner.hand.append(spare)
	await game.play_card(CardData.CardSubType.PEACH)
	await game.play_card(CardData.CardSubType.WINE)
	check(owner.hp == 2 and owner.wine_stacks == 0, "没有桃/酒不能先回复或增加酒层数")
	check(owner.hand == [spare] and game.deck.discard_count() == 0, "错误类型的基本牌支付不改变牌区")
	var peach := CardBase.create(CardData.CardSubType.PEACH)
	owner.hand.push_front(peach)
	await game.play_card(CardData.CardSubType.PEACH)
	check(owner.hp == 3 and owner.hand == [spare], "使用实际桃并保留末尾杀")
	check(game.deck._discard == [peach], "桃的原实例进入弃牌堆")

	reset_case()
	owner.hand.append(spare)
	var hp_before := owner.hp
	game._yes_ah_active = true
	check(await game._consume_trick(owner, CardData.CardSubType.DUEL), "是啊采用独立失血费用")
	check(owner.hp == hp_before - 1 and owner.hand == [spare], "技能视为使用不强制匹配或消耗物理手牌")
	check(game.deck.discard_count() == 0, "技能即时锦囊沿用不生成实体弃牌的约定")
	game._yes_ah_active = true
	await game.execute_card_on_target(other, CardData.CardSubType.BURNING_CAMP)
	check(other.judgment_cards.size() == 1 and owner.hand == [spare], "技能延时锦囊支付后生成判定区资源")
	check(game.deck.discard_count() == 0, "技能延时锦囊不会同时生成弃牌")

	reset_case()
	owner.equipment["weapon"] = CardData.CardSubType.QINGLONG_BLADE
	owner.wine_stacks = 2
	owner.hand.append(peach)
	var target_hp := other.hp
	await game.execute_card_on_target(other, CardData.CardSubType.STRIKE)
	check(owner.hand == [peach] and game.deck.discard_count() == 0, "缺杀时不扣桃、不借青龙摸牌完成支付")
	check(owner.wine_stacks == 2 and game.turn_manager.strike_count_this_turn == 0, "缺杀时保留酒和使用次数")
	check(other.hp == target_hp, "费用不足时杀不造成伤害")
	var paid_strike := CardBase.create(CardData.CardSubType.STRIKE)
	owner.hand.push_front(paid_strike)
	await game.execute_card_on_target(other, CardData.CardSubType.STRIKE)
	check(game.deck._discard.count(paid_strike) == 1 and not owner.hand.has(paid_strike), "杀保留并弃置原实例")
	check(owner.hand == [peach, null], "先支付实际杀，再通过青龙摸牌，不误扣末尾牌")
	check(owner.wine_stacks == 0 and game.turn_manager.strike_count_this_turn == 1, "成功支付后消耗酒、记录一次杀")
	check(other.hp == target_hp - 3, "本次杀保留原酒加成")

	reset_case()
	owner.hand.append(paid_strike)
	await game.execute_card_on_target(other, CardData.CardSubType.FIRE_STRIKE)
	check(owner.hand == [paid_strike] and game.turn_manager.strike_count_this_turn == 0, "主动火杀不能重新声明已具体化的普通杀")
	await game.execute_multi_strike([], CardData.CardSubType.STRIKE)
	check(owner.hand == [paid_strike] and game.deck.discard_count() == 0, "空多目标列表不收费用")
	owner.equipment["weapon"] = CardData.CardSubType.FANGTIAN_HALBERD
	owner.equipment["mount_1"] = CardData.CardSubType.MOUNT_MINUS
	owner.mount_minus = 1
	var second := game.players[2]
	var before_first := other.hp
	var before_second := second.hp
	await game.execute_multi_strike([other, second], CardData.CardSubType.STRIKE)
	check(game.deck._discard.count(paid_strike) == 1 and owner.hand.is_empty(), "多目标杀只支付并弃置一张原牌")
	check(game.turn_manager.strike_count_this_turn == 1, "多目标杀只记录一次使用")
	check(other.hp == before_first - 1 and second.hp == before_second - 1, "两个目标分别结算同一次使用")

	# ST-09：从「已确定的牌」进入同一主动出牌流程，确认前保留、支付时精确移除原对象。
	reset_case()
	owner.hp = 2
	var determined_peach := CardBase.create(CardData.CardSubType.PEACH)
	determined_peach.source_seat = 3
	owner.determined_cards.append(determined_peach)
	owner.hand.append(spare)
	await game._on_determined_card_clicked(determined_peach)
	check(owner.hp == 3, "点击已确定桃沿用主动桃合法性与回复流程")
	check(owner.determined_cards.is_empty() and owner.hand == [spare], "已确定桃只移除所选对象，不误扣普通手牌")
	check(game.deck._discard.count(determined_peach) == 1, "已确定桃原实例只进入弃牌堆一次")

	reset_case()
	var response_only := CardBase.create(CardData.CardSubType.DODGE)
	owner.determined_cards.append(response_only)
	await game._on_determined_card_clicked(response_only)
	check(owner.determined_cards == [response_only] and game.deck.discard_count() == 0, "响应牌不能主动使用且仍保留原实例")
	check(game._pending_determined_card == null, "非法主动使用后清理待支付状态")

	reset_case()
	var cancelled_strike := CardBase.create(CardData.CardSubType.STRIKE)
	owner.determined_cards.append(cancelled_strike)
	await game._on_determined_card_clicked(cancelled_strike)
	check(game._is_targeting and game._pending_determined_card == cancelled_strike, "已确定杀选目标期间保留原对象")
	game._on_cancel_target_pressed()
	check(owner.determined_cards == [cancelled_strike] and game.deck.discard_count() == 0, "取消目标不丢弃已确定杀")
	check(game._pending_determined_card == null and game.turn_manager.strike_count_this_turn == 0, "取消目标不留下支付状态或次数")

	reset_case()
	var determined_strike := CardBase.create(CardData.CardSubType.STRIKE)
	determined_strike.source_seat = 4
	owner.determined_cards.append(determined_strike)
	owner.hand.append(peach)
	var determined_target_hp := other.hp
	await game._on_determined_card_clicked(determined_strike)
	await game._on_target_click(other)
	check(not owner.determined_cards.has(determined_strike) and owner.hand == [peach], "确认目标后只支付所选已确定杀")
	check(game.deck._discard.count(determined_strike) == 1 and other.hp == determined_target_hp - 1, "已确定杀以原实例结算并只弃置一次")
	check(game.turn_manager.strike_count_this_turn == 1 and game._pending_determined_card == null, "已确定杀成功后记录次数并清理待支付状态")

	reset_case()
	var moved_strike := CardBase.create(CardData.CardSubType.STRIKE)
	owner.determined_cards.append(moved_strike)
	owner.hand.append(peach)
	var moved_target_hp := other.hp
	await game._on_determined_card_clicked(moved_strike)
	owner.determined_cards.erase(moved_strike)
	await game._on_target_click(other)
	check(owner.hand == [peach] and game.deck.discard_count() == 0, "确认前所选牌离手时不改扣其他手牌")
	check(other.hp == moved_target_hp and game.turn_manager.strike_count_this_turn == 0, "确认前所选牌离手时不产生效果或次数")
	check(game._pending_determined_card == null, "确认前所选牌离手后清理待支付状态")

	reset_case()
	var determined_delay := CardBase.create(CardData.CardSubType.INDULGENCE)
	determined_delay.source_seat = 4
	owner.determined_cards.append(determined_delay)
	await game._on_determined_card_clicked(determined_delay)
	await game._on_target_click(other)
	check(other.judgment_cards == [determined_delay] and owner.determined_cards.is_empty(), "已确定延时锦囊原实例进入目标判定区")
	check(determined_delay.source_seat == owner.seat_index and game.deck.discard_count() == 0, "再次放置延时锦囊更新来源且不重复弃置")

	reset_case()
	var determined_mount := CardBase.create(CardData.CardSubType.MOUNT_PLUS)
	owner.determined_cards.append(determined_mount)
	owner.hand.append(peach)
	await game._on_determined_card_clicked(determined_mount)
	check(owner.determined_cards.is_empty() and owner.hand == [peach], "已确定装备只移除所选对象")
	check(owner.mount_plus == 1 and game.deck.discard_count() == 0, "已确定坐骑进入现有装备流程且不作为使用牌弃置")

	reset_case()
	var determined_chain := CardBase.create(CardData.CardSubType.IRON_CHAIN)
	owner.determined_cards.append(determined_chain)
	await game._on_determined_card_clicked(determined_chain)
	check(game._is_iron_chain_targeting and owner.determined_cards == [determined_chain], "已确定铁索在专用目标选择期间保留")
	game._iron_chain_targets.append(owner)
	await game._on_iron_chain_target_click(other)
	check(owner.chained and other.chained, "已确定铁索复用一至两名目标结算")
	check(game.deck._discard.count(determined_chain) == 1 and game._pending_determined_card == null, "已确定铁索原实例只弃置一次并清理待支付状态")

	reset_case()
	owner.equipment["weapon"] = CardData.CardSubType.FANGTIAN_HALBERD
	owner.equipment["mount_1"] = CardData.CardSubType.MOUNT_MINUS
	owner.mount_minus = 1
	var determined_multi := CardBase.create(CardData.CardSubType.STRIKE)
	owner.determined_cards.append(determined_multi)
	var multi_first_hp := other.hp
	var multi_second_hp := second.hp
	await game._on_determined_card_clicked(determined_multi)
	check(game._is_multi_targeting and owner.determined_cards == [determined_multi], "已确定杀在方天画戟多目标选择期间保留")
	game._on_multi_target_click(other)
	game._on_multi_target_click(second)
	await game._on_confirm_multi_target()
	check(other.hp == multi_first_hp - 1 and second.hp == multi_second_hp - 1, "已确定杀复用方天画戟多目标结算")
	check(game.deck._discard.count(determined_multi) == 1 and game.turn_manager.strike_count_this_turn == 1 and game._pending_determined_card == null, "多目标已确定杀只支付一次")

	reset_case()
	owner.general_name = "安普提·斯丢皮得"
	owner.hp = owner.max_hp
	var determined_disarm := CardBase.create(CardData.CardSubType.DISARM)
	owner.determined_cards.append(determined_disarm)
	game._yes_ah_override = func(): return "skill"
	await game._on_determined_card_clicked(determined_disarm)
	check(owner.hp == owner.max_hp and game.deck._discard.count(determined_disarm) == 1, "明确点击已确定锦囊时不改用是啊虚拟支付")
	owner.general_name = "稻草人"
	game._yes_ah_override = Callable()

	reset_case()
	var only_determined := CardBase.create(CardData.CardSubType.PEACH)
	owner.determined_cards.append(only_determined)
	game._sync_all_ui()
	check(not game._play_btn.disabled, "只有已确定牌时出牌按钮仍可打开选择器")

	await check_cross_zone_payments()
	game.queue_free()
	await process_frame
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

# A1：生产预查与支付入口，而非仅在合并视图上删除副本。
func check_cross_zone_payments():
	var p = game.players[0]
	var target = game.players[1]
	reset_case()
	var peach = CardBase.create(CardData.CardSubType.PEACH)
	var fire = CardBase.create(CardData.CardSubType.FIRE_STRIKE)
	p.hand.append(null)
	p.determined_cards.assign([peach, fire])
	check(HandPayment.has_card(p, CardData.CardSubType.PEACH), "A1 跨牌区预查可用桃")
	check(p.hand == [null] and p.determined_cards == [peach, fire], "A1 预查不移动或具体化任何牌")
	check(HandPayment.take_card(p, CardData.CardSubType.PEACH) == peach and p.hand == [null], "A1 第二牌区具体桃优先于第一牌区任意牌")
	check(HandPayment.take_player_response(p, CardData.CardSubType.STRIKE) == fire, "A1 响应杀保留第二牌区火杀原实例")
	check(p.determined_cards.is_empty() and p.hand == [null], "A1 支付从原数组精确移除")
	var wine = HandPayment.take_card(p, CardData.CardSubType.WINE)
	check(wine != null and wine.sub_type == CardData.CardSubType.WINE and p.hand.is_empty(), "A1 用尽具体牌后任意牌正常具体化")
	p.determined_cards.append(fire)
	check(not HandPayment.has_card(p, CardData.CardSubType.STRIKE) and HandPayment.take_card(p, CardData.CardSubType.STRIKE) == null, "A1 主动普通杀不能冒充具体火杀")
	check(p.determined_cards == [fire] and not HandPayment.has_card(null, CardData.CardSubType.PEACH), "A1 错误类型和空角色无副作用")

	reset_case()
	p.hp = 2
	p.determined_cards.append(peach)
	await game.play_card(CardData.CardSubType.PEACH)
	check(p.hp == 3 and game.deck._discard == [peach] and p.determined_cards.is_empty(), "A1 无普通手牌时通用主动桃入口可支付已确定桃")

	reset_case()
	target.hp = 0
	p.determined_cards.append(peach)
	check(game._rescue_options(p, target).has(CardData.CardSubType.PEACH), "A1 求救名单识别第二牌区桃")
	check(game._use_rescue_card(p, target, CardData.CardSubType.PEACH), "A1 实际支付已确定桃救他人")
	check(target.hp == 1 and p.determined_cards.is_empty() and game.deck._discard == [peach], "A1 求救恢复正确目标且原牌只弃一次")
	check(not game._use_rescue_card(p, target, CardData.CardSubType.PEACH), "A1 已救回目标不重复支付")
	p.hp = 0
	p.determined_cards.append(wine)
	check(game._use_rescue_card(p, p, CardData.CardSubType.WINE) and p.hp == 1, "A1 第二牌区酒可自救")
	check(p.wine_stacks == 0 and game.deck._discard.count(wine) == 1, "A1 自救酒不增加进攻层数")

	reset_case()
	p.determined_cards.append(fire)
	check(await game._ask_basic_card_response(p, CardData.CardSubType.STRIKE, func(): return true), "A1 决斗/AOE 响应杀识别已确定火杀")
	check(game.deck._discard == [fire] and p.determined_cards.is_empty(), "A1 响应原属性牌只弃一次")
	check(game.turn_manager.strike_count_this_turn == 0, "A1 响应不消耗主动杀次数")
	p.determined_cards.append(fire)
	check(not await game._ask_basic_card_response(p, CardData.CardSubType.STRIKE, func(): return false), "A1 拒绝响应不支付")
	check(p.determined_cards == [fire], "A1 拒绝后原牌仍在")
	check(not await game._ask_basic_card_response(p, CardData.CardSubType.STRIKE, func():
		p.determined_cards.erase(fire)
		return true), "A1 等待期间牌离手，返回后不凭空支付")
	check(game.deck._discard.count(fire) == 1, "A1 失效操作不重复制造弃牌")

	reset_case()
	var dodge = CardBase.create(CardData.CardSubType.DODGE)
	p.determined_cards.append(dodge)
	game._dodge_override = func(): return true
	var chain = game._new_damage_chain(target, p, null, 1, EffectChain.DamageType.PHYSICAL)
	check(await game._on_chain_response_check(chain, p, CardData.CardSubType.DODGE, target), "A1 杀的出闪入口可使用第二牌区闪")
	check(game.deck._discard == [dodge] and p.determined_cards.is_empty(), "A1 出闪精确扣除原牌")

	reset_case()
	var nullify = CardBase.create(CardData.CardSubType.NULLIFICATION)
	p.determined_cards.append(nullify)
	game._nullify_override = func(): return true
	check(await game._ask_nullification_round("A1") == p.player_name, "A1 无懈弹窗预查与最终支付一致")
	check(game.deck._discard == [nullify] and p.determined_cards.is_empty(), "A1 无懈原实例只弃一次")

	reset_case()
	var sacrifice = CardBase.create(CardData.CardSubType.SACRIFICE)
	p.determined_cards.append(sacrifice)
	game._sacrifice_override = func(): return true
	check(await game._maybe_sacrifice(game.players[2], target, 1, EffectChain.DamageType.PHYSICAL) == p, "A1 舍己代受预查与最终支付一致")
	check(game.deck._discard == [sacrifice] and p.determined_cards.is_empty(), "A1 舍己原实例只弃一次")
	reset_case()
