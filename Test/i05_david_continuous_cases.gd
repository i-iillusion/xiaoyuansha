extends RefCounted
const Peach = preload("res://Test/i05_david_peach_cases.gd")

func frames(t, count := 3):
	for i in count: await t.process_frame

func token(b, seat, text):
	for c in b.snapshot(seat).controls:
		if not c.disabled and str(c.text).begins_with(text): return c.id
	return ""

func click(t, b, seat, text):
	var id = token(b, seat, text)
	var ok = not id.is_empty() and not b.submit(1 - seat, id) and b.submit(seat, id)
	t.check(ok, "I05b5 continuous actual Bridge owns and submits: " + text)
	if not ok: b.game._game_over = true
	await frames(t)
	return ok

func card(t, b, seat, name, basic):
	for label in ["出牌", "基本牌" if basic else "锦囊牌"]:
		if not await click(t, b, seat, label): return false
	if not basic and not await click(t, b, seat, "普通锦囊"): return false
	if not await click(t, b, seat, name): return false
	await t.create_timer(0.15).timeout # Existing selector close animation, not an altered game clock.
	await frames(t)
	return true

func target(t, b, seat, victim):
	var declaring = b.snapshot(seat).targeting
	var id = b.snapshot(seat).targets.get(str(victim), "")
	var ok = not id.is_empty() and not b.submit(1 - seat, id) and b.submit(seat, id)
	t.check(ok, "I05b5 continuous actual target/detail command belongs to acting seat")
	if not ok: b.game._game_over = true
	await frames(t)
	if ok and declaring: return await click(t, b, seat, "是")
	return ok

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var b = Peach.new().bridge_fixture(t)
	await sequence(t, b)
	await Peach.new().dispose_bridge(t, b)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func sequence(t, b):
	var game = b.game; var david = game.players[0]
	# Explicit initial resource/HP fixture. All later resources, turns and
	# responses come from production widgets, without payment/choice overrides.
	david.hp = 1; david.hand.assign([null, null, null, null])
	david.farm_empty_fields = 0; david.farm_good_fields = 0
	game._wrestling_rules_enabled = true
	var armor = CardBase.create(CardData.CardSubType.SHENGGUANG_BAIYI)
	david.equip_card_to_slot("armor", armor)
	var facts: Array = []; game.card_action_committed.connect(func(a): facts.append(a))
	game._sync_all_ui()
	if not await card(t, b, 0, "酒", true): return
	if not await card(t, b, 0, "桃", true): return
	t.check(david.hp == 2 and david.hand_size() == 2 and david.farm_empty_fields == 1 and david.farm_hand_actions == 2, "I05b5 continuous two actual hand uses create first field before next action")
	if not await target(t, b, 0, 0): return
	if not await click(t, b, 0, "· 【种田】"): return
	for index in ["1 · 任意牌", "2 · 任意牌"]:
		if not await click(t, b, 0, index): return
	var old = token(b, 0, "确认弃牌")
	if not await click(t, b, 0, "确认弃牌"): return
	t.check(not b.submit(0, old) and david.hand_size() == 0 and david.farm_empty_fields == 0 and david.farm_good_fields == 1, "I05b5 continuous real two-card upgrade pays once without hand-use farming")
	if not await card(t, b, 0, "桃", true): return
	t.check(david.hp == 3 and david.farm_good_fields == 0 and david.farm_empty_fields == 1 and david.hand_size() == 0, "I05b5 continuous earned good field returns empty field through real empty-hand Peach")
	if not await click(t, b, 0, "结束出牌"): return
	await frames(t, 5)
	game._halt_countdown()
	t.check(game.turn_manager.current_player_idx == 1 and game.turn_manager.current_phase == TurnManager.Phase.PLAY and game.players[1].hand_size() == 2, "I05b5 actual whole turn ends, next player normally draws two and enters PLAY")
	if not await card(t, b, 1, "决斗", false): return
	if not await target(t, b, 1, 0): return
	if not await click(t, b, 0, "空田当无懈"): return
	if not await click(t, b, 1, "放弃"): return
	t.check(david.farm_empty_fields == 0 and david.hp == 3 and game.players[1].hand_size() == 1 and b.input_owner() == 1, "I05b5 earned field nullifies real enemy Duel and returns to enemy PLAY without damage")
	var enemy_hp = game.players[1].hp
	if not await card(t, b, 1, "顺手牵羊", false): return
	if not await target(t, b, 1, 0): return
	if not await click(t, b, 1, "装备牌"): return
	if not await click(t, b, 1, Player.EQUIP_SLOT_NAMES["armor"]): return
	if not await click(t, b, 0, "发动摔角"): return
	t.check(david.get_equipment_card("armor") == armor and game.players[1].hand_size() == 0 and game.players[1].hp == enemy_hp - 1, "I05b5 continuous native counter keeps original equipment and fully resolves extra Duel")
	t.check(david.wrestle_round == game.turn_manager.rounds.round_id and b.input_owner() == 1 and game._pending_card_actions.is_empty() and game._choice_prompt_stack.is_empty() and game._wrestling_resolving.is_empty(), "I05b5 continuous UI returns to original enemy actor with no nested actions or windows")
	t.check(facts.size() == 7 and facts.all(func(a): return a.settlement_completed) and facts.filter(func(a): return a.actor_body == david and a.is_virtual).size() == 3 and david.farm_hand_actions == 2, "I05b5 seven actual USE facts complete once; three virtual costs never re-farm hand income")
