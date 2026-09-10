# ST-09 局部：物理手牌支付与即时/延时锦囊去向。只覆盖已接入的入口。
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
		p.judgment_cards.clear()
		p.equipment.clear()
		p.wine_stacks = 0
		p.mount_minus = 0
		p.mount_plus = 0
	game.reset_game_over_state()
	game.turn_manager.strike_count_this_turn = 0
	game.turn_manager._strike_actors_this_turn.clear()
	game._stop_countdown()
	game.deck._discard.clear()
	game._yes_ah_active = false
	game._dying_peach_override = func(): return false
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game._dodge_override = func(): return false

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

	game.queue_free()
	await process_frame
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
