extends SceneTree

var checks := 0
var failures := 0
var selected := -1

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var selector = load("res://Scenes/CardSelector.tscn").instantiate()
	root.add_child(selector)
	selector._render_normal_stratagem()
	await process_frame
	var ordinary = selector.find_children("*", "Button", true, false)
	check(not ordinary.any(func(button): return button.text == "火烧连营"), "burning camp absent from ordinary trick menu")
	selector._render_delayed_stratagem()
	await process_frame
	var delayed = selector.find_children("*", "Button", true, false)
	var burning = delayed.filter(func(button): return button.text == "火烧连营")
	check(burning.size() == 1, "burning camp appears once in delayed menu")
	selector.confirmed.connect(func(sub): selected = sub)
	if not burning.is_empty(): burning[0].pressed.emit()
	await create_timer(0.2).timeout
	check(selected == CardData.CardSubType.BURNING_CAMP, "delayed menu click selects actual burning camp")
	if is_instance_valid(selector): selector.queue_free()
	var game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	game.start_game()
	game._halt_countdown()
	var owner: Player = game.players[0]
	var other: Player = game.players[1]
	for p in game.players:
		p.general_name = "稻草人"
		p.equipment.clear()
	owner.general_name = "凯文·罗本"
	game._kaiwen_override = func(): return true
	for receive in [false, true]:
		for scenario in ["win", "lose", "draw", "draw_then_win"]:
			owner.hp = 10
			owner.max_hp = 10
			other.hp = 10
			other.max_hp = 10
			owner.hand.clear()
			var choices: Array = [GameManager.RPS_ROCK, GameManager.RPS_SCISSORS]
			if scenario == "lose": choices[1] = GameManager.RPS_PAPER
			if scenario == "draw": choices[1] = GameManager.RPS_ROCK
			if scenario == "draw_then_win": choices = [0, 0, 0, 2]
			var calls := {"count": 0}
			game._rps_override = func(p):
				calls.count += 1
				return choices.pop_front() if not choices.is_empty() else (GameManager.RPS_ROCK if p == owner else GameManager.RPS_SCISSORS)
			var amount := 2 if scenario == "draw_then_win" else 1
			await game._deal_damage(other if receive else owner, owner if receive else other, amount, EffectChain.DamageType.PHYSICAL)
			check(calls.count == amount * 2, "each damage point has exactly one RPS round: %s/%s" % [receive, scenario])
			check(owner.hand_size() == (2 if scenario in ["win", "draw_then_win"] else 0), "draw reward follows wins only: %s/%s" % [receive, scenario])
			check((owner if receive else other).hp == 10 - amount, "RPS result does not undo damage")
	game._game_over = true
	game._halt_countdown()
	game.queue_free()
	await process_frame
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures else 0)
