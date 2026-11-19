extends RefCounted

func offer(game, actor, skill):
	return game._ai_play_candidates(game._ai_observation(actor)).filter(func(action): return action.get("skill") == skill)

func run(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var fixture = load("res://Test/i05_sally_jiegui_cases.gd").new()
	var game = fixture.fixture(t,1)
	game.lan_enabled = false
	var actor = game.players[1]
	actor.sally_smoking_enabled = true
	actor.sally_surgery_enabled = true
	actor.sally_woman_enabled = true
	var smoke = offer(game,actor,"sally_smoke")
	t.check(smoke.size() == 1, "I05e6b native AI receives a safe smoking option")
	actor.hp = 1
	if not smoke.is_empty(): await game._execute_ai_action(smoke[0])
	t.check(actor.hp == 1 and actor.gender == "female" and not actor.sally_smoke_active, "I05e6b stale smoking option is revalidated before paying HP")
	actor.hp = 3
	smoke = offer(game,actor,"sally_smoke")
	if not smoke.is_empty(): await game._execute_ai_action(smoke[0])
	t.check(actor.hp == 2 and actor.gender == "male" and actor.sally_smoke_uses == 1 and actor.sally_smoke_active, "I05e6b AI uses the real smoking payment and state transition")
	actor.sally_smoke_uses = 3
	var fee = CardBase.create(CardData.CardSubType.PEACH)
	actor.determined_cards.append(fee)
	var surgery = offer(game,actor,"sally_surgery")
	t.check(surgery.size() == 1, "I05e6b eligible AI sees surgery")
	if not surgery.is_empty(): await game._execute_ai_action(surgery[0])
	t.check(actor.sally_surgery_pending and not actor.sally_surgery_active and game.deck._discard.count(fee) == 1 and offer(game,actor,"sally_surgery").is_empty(), "I05e6b AI pays the original card once and waits for next round")
	var lion = CardBase.create(CardData.CardSubType.SILVER_LION)
	actor.equip_card_to_slot("armor",lion)
	var discard = offer(game,actor,"sally_lion")
	if not discard.is_empty(): await game._execute_ai_action(discard[0])
	t.check(discard.size() == 1 and actor.hp == 3 and game.deck._discard.count(lion) == 1, "I05e6b AI discards Silver Lion through the normal loss and recovery path")
	actor.gender = "female"
	actor.hand.append_array([null,null])
	var women = offer(game,actor,"sally_woman")
	t.check(not women.is_empty(), "I05e6b useful Woman candidates are actual legal players")
	if not women.is_empty():
		var target = game.players[women[0].recipient]
		target.gender = "female"
		await game._execute_ai_action(women[0])
		t.check(actor.hand_size() == 2, "I05e6b a changed target invalidates AI payment")
		target.gender = "male"
		women = offer(game,actor,"sally_woman")
		var selected = women.filter(func(action): return action.recipient == target.seat_index)
		if not selected.is_empty(): await game._execute_ai_action(selected[0])
		t.check(selected.size() == 1 and actor.hand_size() == 1 and target.gender == "female" and actor.sally_source_bonus(target) == 1, "I05e6b real one-card Woman payment updates the same-sex damage query")
	t.check(game._choice_prompt_stack.is_empty(), "I05e6b native AI never waits on a human control")
	await fixture.dispose(t,game)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]; GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]
