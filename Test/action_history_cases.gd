extends RefCounted

var answer: Variant

func capture(callback: Callable) -> void:
	answer = await callback.call()

func frames(tree: SceneTree, count: int = 3) -> void:
	for i in count: await tree.process_frame

func run(t: SceneTree) -> void:
	var roster: Array[Dictionary] = []
	for i in 5: roster.append({"name": "P%d" % i, "general": "稻草人"})
	var bridge = LanGameBridge.new()
	t.root.add_child(bridge)
	bridge.start(roster, GameManager.MODE_CLASSIC_IDENTITY)
	await t.create_timer(0.9).timeout
	var game = bridge.game
	game._halt_countdown()
	game._nullify_override = func(): return false
	game._sacrifice_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	for p in game.players:
		p.max_hp = 10
		p.hp = 10
	var history: ActionHistory = game.action_history
	t.check(not "座位：" in history.visible_text(), "LOG initial identity debug never enters history")
	history.reset("log-case")
	var actor: Player = game.players[0]
	var target: Player = game.players[1]
	game._dodge_override = func(): return true
	await game.execute_card_on_target(target, CardData.CardSubType.STRIKE)
	var kinds = history.entries.map(func(e): return e.kind)
	t.check(kinds.find("use") < kinds.find("response") and kinds.find("response") < kinds.find("dodged"), "LOG real kill/flash order")
	t.check(not kinds.has("damage") and target.hp == 10, "LOG dodged kill records no damage")
	t.check(history.entries.filter(func(e): return e.kind == "completed").size() == 2, "LOG each paid kill/flash completes once")
	t.check(history.entries.filter(func(e): return e.kind == "target")[0].targets == [1], "LOG actual kill target seat")
	var saved = history.visible_text()
	game._update_debug("PRIVATE-IDENTITIES-AND-HAND")
	t.check(saved == history.visible_text(), "LOG arbitrary debug never broadcast")
	var before = history.sequence
	await game.execute_card_on_target(target, CardData.CardSubType.BURNING_CAMP)
	t.check(target.judgment_cards.size() == 1, "LOG real fire card waits in judgment zone")
	t.check(not history.entries.any(func(e): return e.seq > before and "判定生效" in e.text), "LOG placement does not claim judgment damage")
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.JUDGE
	await game._run_judgment(target, false)
	t.check(history.entries.any(func(e): return "火烧连营】判定生效" in e.text), "LOG actual later judgment result")
	t.check(history.entries.any(func(e): return e.kind == "damage" and e.actor == -1 and e.details.element == EffectChain.DamageType.FIRE), "LOG fire damage has no source")
	game.turn_manager.current_player_idx = 1
	game.turn_manager.current_phase = TurnManager.Phase.PLAY
	game.turn_manager.play_actor_idx = 1
	actor.general_name = "里奥·普利威尔"
	actor.prep_tokens = 1
	game._prep_replace_override = func(_leo, _user, _target, _sub, _candidates): return CardData.CardSubType.IRON_CHAIN
	await game.execute_card_on_target(game.players[2], CardData.CardSubType.DUEL)
	var replacement = history.entries.filter(func(e): return e.kind == "replacement")
	t.check(replacement.size() == 1 and replacement[0].actor == 1 and replacement[0].targets == [2], "LOG prep preserves user and fixed target")
	t.check(replacement[0].details.original == CardData.CardSubType.DUEL and replacement[0].details.effective == CardData.CardSubType.IRON_CHAIN, "LOG original and effective card separate")
	t.check(game.deck._discard.back().sub_type == CardData.CardSubType.DUEL, "LOG observation preserves original physical card")
	actor.general_name = "稻草人"
	game.turn_manager.current_player_idx = 0
	game.turn_manager.play_actor_idx = 0
	var calls = {"n": 0}
	game._nullify_override = func():
		calls.n += 1
		return calls.n == 1
	var nullified = await game._ask_nullification_chain_result("log nullification")
	t.check(nullified == GameManager.NullificationOutcome.NULLIFIED, "LOG real nullification chain completes")
	t.check(history.entries.any(func(e): return e.kind == "use" and e.details.card == "无懈可击"), "LOG nullification paid fact recorded")
	game._nullify_override = func(): return false
	# First hidden gesture must not become a public event before second commits.
	before = history.sequence
	answer = null
	capture(game._do_ping_dian_once.bind(actor, target))
	await frames(t)
	t.check(bridge.submit(0, bridge.snapshot(0).controls[0].id), "LOG first remote gesture submitted")
	await frames(t)
	t.check(not history.entries.any(func(e): return e.seq > before and e.kind == "rps"), "LOG first gesture remains private")
	t.check(bridge.submit(1, bridge.snapshot(1).controls[0].id), "LOG second remote gesture submitted")
	await frames(t)
	t.check(answer == GameManager.RPS_DRAW and history.entries.back().kind == "rps", "LOG RPS draw publishes only after both choices")
	# A hidden resource with a concrete origin logs only its declared category.
	actor.general_name = "安普提·斯丢皮得"
	actor.hand.clear()
	actor.determined_cards.clear()
	actor.determined_cards.append(CardBase.create(CardData.CardSubType.ZHUGE_LIANNU))
	game._sao_type_override = func(): return "weapon"
	before = history.sequence
	await game._do_sao_hide(actor, false)
	var hidden_text = "\n".join(history.entries.filter(func(e): return e.seq > before).map(func(e): return e.text))
	t.check("暗置" in hidden_text and not "诸葛连弩" in hidden_text, "LOG hidden concrete weapon name not revealed")
	var wire = bridge.snapshot(0).history
	for seat in 5:
		t.check(bridge.snapshot(seat).history == wire, "LOG public packet same for seat%d" % seat)
	t.check(not "PRIVATE-IDENTITIES" in var_to_str(wire), "LOG packet excludes private debug")
	# Actual skill draw is one public result, not a loop or a private choice.
	actor.general_name = "凯文·罗本"
	game._kaiwen_override = func(): return true
	game._rps_override = func(_p): return GameManager.RPS_ROCK
	before = history.sequence
	var hand_before = actor.hand_size()
	await game._deal_damage(actor, target, 1, EffectChain.DamageType.PHYSICAL)
	var skill_events = history.entries.filter(func(e): return e.seq > before)
	t.check(skill_events.filter(func(e): return e.kind == "rps").size() == 1 and actor.hand_size() == hand_before, "LOG Kevin draw is one round without draw reward")
	t.check(skill_events.any(func(e): return e.kind == "damage" and e.details.amount == 1), "LOG actual applied damage recorded")
	before = history.sequence
	target.heal(1)
	t.check(history.entries.any(func(e): return e.seq > before and e.kind == "hp" and e.details.after > e.details.before), "LOG actual healing recorded")
	actor.general_name = "稻草人"
	for i in 5: game.players[i].identity = ["主公", "忠臣", "反贼", "反贼", "内奸"][i]
	var victim: Player = game.players[3]
	victim.identity_revealed = false
	before = history.sequence
	await game._deal_damage(actor, victim, 20, EffectChain.DamageType.PHYSICAL)
	var death_texts = history.entries.filter(func(e): return e.seq > before).map(func(e): return e.text)
	var death_at = death_texts.find("P3 阵亡！")
	var reveal_at = death_texts.find("身份翻开：P3 是【反贼】！")
	t.check(victim.is_dead() and death_at >= 0 and reveal_at > death_at, "LOG final death precedes public identity reveal")
	t.check(history.entries.any(func(e): return e.seq > before and e.kind == "discard" and e.actor == 3), "LOG final death clears public card counts")
	# LAN history is independent of the rebuilt rule controls.
	var room = load("res://Scripts/LanRoom.gd").new()
	t.root.add_child(room)
	var state = bridge.snapshot(0)
	room._state_changed(state)
	var first_control = room.body.get_child(0)
	var first_panel = room._history_panel
	history.append("result", "联机日志刷新", 2, 3)
	room._state_changed(bridge.snapshot(0))
	t.check(room.body.get_child(0) == first_control and room._history_panel == first_panel, "LOG LAN updates preserve controls and panel")
	room.queue_free()
	await frames(t)
	game._game_over = true
	game._halt_countdown()
	bridge.queue_free()
	await frames(t)
	await _journal_and_panel(t)

func _journal_and_panel(t: SceneTree) -> void:
	var source = ActionHistory.new()
	var receiver = ActionHistory.new()
	source.reset("old")
	receiver.reset("old")
	for i in 280: source.append("draw", "event%d" % i, 1, 2)
	while receiver.sequence < source.sequence:
		var packet = source.packet(receiver.sequence)
		t.check(packet.entries.size() <= ActionHistory.BATCH, "LOG bounded wire batch")
		t.check(receiver.receive(packet), "LOG accepts contiguous batch")
		t.check(receiver.receive(packet), "LOG replay packet accepted without duplicates")
	t.check(receiver.entries == source.entries, "LOG same-frame burst fully retained")
	var stale = source.packet()
	receiver.reset("new")
	t.check(not receiver.receive(stale) and receiver.entries.is_empty(), "LOG old match rejected")
	source.reset("new")
	for i in ActionHistory.LIMIT + 9: source.append("result", "event%d" % i, 1, 3)
	t.check(source.entries.size() == ActionHistory.LIMIT and source.entries[0].seq == 10, "LOG explicit rolling retention")
	t.check(receiver.receive(source.packet()) and receiver.entries[0].seq == 10, "LOG retained gap explicitly supported")
	t.check("超出保留范围" in receiver.visible_text(), "LOG truncated history disclosure")
	var lagged = ActionHistory.new()
	lagged.reset("new")
	lagged.receive(source.packet())
	for i in ActionHistory.LIMIT: source.append("result", "burst%d" % i, 2, 3)
	t.check(lagged.receive(source.packet(lagged.sequence)) and lagged.entries[0].seq == 2010, "LOG lagging client discards discontinuous old prefix")
	while lagged.sequence < source.sequence: lagged.receive(source.packet(lagged.sequence))
	t.check(lagged.entries == source.entries and source.entries.size() == ActionHistory.LIMIT, "LOG repeated ring wraps preserve complete retained order")
	t.check("超出保留范围" in lagged.visible_text(), "LOG lagging client discloses lost history")
	var panel = ActionHistoryPanel.new()
	panel.custom_minimum_size.x = 440
	t.root.add_child(panel)
	panel.bind(receiver)
	panel.toggle.pressed.emit()
	await frames(t)
	t.check(panel.text_view.text == receiver.visible_text(), "LOG local panel opens current history")
	panel.follow = false
	var old_position = panel.text_view.get_v_scroll_bar().value
	receiver.append("result", "新的长中文行动结果测试", 2, 3)
	await frames(t)
	t.check(panel.unseen == 1 and not panel.follow, "LOG scrolled reader gets new-message badge")
	t.check(panel.text_view.get_v_scroll_bar().value == old_position, "LOG does not steal reader scroll")
	receiver.reset("third")
	await frames(t)
	t.check(panel.text_view.text.is_empty() and panel.unseen == 0, "LOG new game clears panel")
	var old_size = t.root.size
	for dimensions in [Vector2i(960, 540), Vector2i(3840, 2160)]:
		t.root.size = dimensions
		panel.size = Vector2(424, 310)
		receiver.append("result", "长中文".repeat(100), 3, 3)
		await frames(t)
		t.check(panel.text_view.get_v_scroll_bar().max_value > panel.text_view.get_v_scroll_bar().page and panel.text_view.size.x <= panel.size.x, "LOG long Chinese remains scrollable at viewport %s" % dimensions)
	t.root.size = old_size
	panel.queue_free()
	await frames(t)
