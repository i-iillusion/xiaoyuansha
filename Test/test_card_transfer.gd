# ST-08/10 局部回归：顺手/拆桥的实例保留与弃牌记账，不代表完整牌生命周期覆盖。
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

func reset_case():
	for p in game.players:
		p.hp = p.max_hp
		p.hand.clear()
		p.judgment_cards.clear()
		p.determined_cards.clear()
		p.equipment.clear()
		p.hidden_equip_slot = ""
	game.reset_game_over_state()
	game.deck._discard.clear()
	game._stop_countdown()
	game._liehuo_override = func(): return false
	game._nullify_override = func(): return false
	game._zone_pick_override = func(): return "hand"

func _run():
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 5
	GameManager.selected_general = "稻草人"
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	game.start_game()
	var attacker := game.players[1] # 装备选择不弹窗，只有一件待处理装备。
	var target := game.players[2]
	var concrete := CardBase.create(CardData.CardSubType.PEACH)
	concrete.source_seat = 4
	var original_id := concrete.card_id

	reset_case()
	target.hand.append(concrete)
	await game._steal_hand(attacker, target, true, "顺手牵羊")
	check(target.hand.is_empty() and attacker.hand == [concrete], "顺手转移原手牌资源，不生成空白牌")
	check(concrete.card_id == original_id and concrete.source_seat == 4, "具体牌 ID 与元数据不改变")
	check(game.deck.discard_count() == 0, "转移不是弃牌")
	await game._steal_hand(target, attacker, true, "顺手牵羊")
	check(target.hand == [concrete] and attacker.hand.is_empty(), "再次转移仍保持同一具体牌")
	await game._steal_hand(attacker, target, false, "过河拆桥")
	check(target.hand.is_empty() and game.deck._discard == [concrete], "拆桥将原具体手牌放入弃牌堆一次")
	await game._steal_hand(attacker, target, false, "过河拆桥")
	check(game.deck._discard == [concrete], "空牌区重复调用不制造弃牌")

	reset_case()
	target.hand.append(null)
	await game._steal_hand(attacker, target, true, "顺手牵羊")
	check(attacker.hand.size() == 1 and attacker.hand[0] == null, "未具体化手牌转移后仍为任意牌")
	await game._steal_hand(target, attacker, false, "过河拆桥")
	check(attacker.hand.is_empty() and game.deck.discard_count() == 0, "弃空白牌不凭空决定类型或生成实体")

	reset_case()
	var delayed := CardBase.create(CardData.CardSubType.LIGHTNING)
	delayed.source_seat = 3
	target.judgment_cards.append(delayed)
	await game._steal_judgment(attacker, target, true, "顺手牵羊")
	check(attacker.determined_cards == [delayed] and target.judgment_cards.is_empty(), "顺手保留判定牌原实例")
	check(delayed.source_seat == 3 and game.deck.discard_count() == 0, "转移判定牌不丢来源、不入弃牌堆")
	attacker.determined_cards.clear()
	target.judgment_cards.append(delayed)
	await game._steal_judgment(attacker, target, false, "过河拆桥")
	check(game.deck._discard == [delayed], "拆桥将原判定牌记入弃牌堆")

	reset_case()
	target.equipment["weapon"] = CardData.CardSubType.LIANNU
	game.equipment_pool.claim(CardData.CardSubType.LIANNU)
	await game._steal_equip(attacker, target, false, "过河拆桥")
	check(target.equipment.is_empty() and game.deck.discard_count() == 1, "拆装备记录一张弃牌")
	check(game.deck._discard[0].sub_type == CardData.CardSubType.LIANNU, "弃置装备的类型正确")
	check(game.equipment_pool.is_claimed(CardData.CardSubType.LIANNU), "弃装备不释放唯一性占用")

	reset_case()
	target.equipment["weapon"] = CardData.CardSubType.HIDDEN_EQUIPMENT
	target.hidden_equip_slot = "weapon"
	await game._steal_equip(attacker, target, false, "过河拆桥")
	check(target.equipment.is_empty() and target.hidden_equip_slot == "", "拆除暗置占位清理槽位")
	check(game.deck.discard_count() == 0, "暗置占位不制造假装备进弃牌堆")

	reset_case()
	target.hand.append(concrete)
	target.equipment["armor"] = CardData.CardSubType.LIEHUO_SHIELD
	game._liehuo_override = func(): return true
	var previous_hp := target.hp
	await game._steal_hand(attacker, target, true, "顺手牵羊")
	check(target.hp == previous_hp - 1 and target.hand == [concrete], "烈火盾代替效果失牌时保留原牌")
	check(attacker.hand.is_empty() and game.deck.discard_count() == 0, "替代成功不转移也不弃牌")
	target.hp = 1
	await game._steal_hand(attacker, target, true, "顺手牵羊")
	check(target.is_dead() and attacker.hand.is_empty(), "烈火盾失血致死后不从空牌区偷出假牌")
	check(game.deck._discard.count(concrete) == 1, "死亡弃牌与原拆偷效果不重复记账")

	reset_case()
	attacker = game.players[0]
	attacker.hand.append(null)
	target.hand.append(concrete)
	game._zone_pick_override = func(): return "cancel"
	await game._play_steal_card(attacker, target, true)
	check(attacker.hand == [null] and target.hand == [concrete], "区域选择取消不收费用、不转移")
	check(game.deck.discard_count() == 0, "取消不产生弃牌记录")
	game._zone_pick_override = func(): return "hand"
	await game._play_steal_card(attacker, target, true)
	check(attacker.hand == [concrete] and target.hand.is_empty(), "完整顺手入口收一次费用并取得原牌")
	check(game.deck.discard_count() == 1 and game.deck._discard[0].sub_type == CardData.CardSubType.SNATCH, "完整入口只将使用的顺手牌入弃牌堆")

	game.queue_free()
	await process_frame
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
