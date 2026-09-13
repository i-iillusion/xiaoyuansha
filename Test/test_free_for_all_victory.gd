# ST-06/07：2～10 人无身份乱斗判胜与普通濒死窗口回归。
extends SceneTree

var checks := 0
var failures := 0
var game: GameManager
var winners: Array[String] = []

func _init():
	_run()

func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
	print(("PASS: " if ok else "FAIL: ") + message)

func make_roster(count: int) -> Array[Player]:
	var roster: Array[Player] = []
	for i in range(count):
		var p := Player.new()
		p.player_name = "P%d" % i
		p.seat_index = i
		p.identity = ""
		p.hp = 4
		roster.append(p)
	return roster

func mark_dead(roster: Array[Player], indices: Array):
	for i in indices:
		roster[i].hp = 0
		roster[i].mark_dead()

func free_roster(roster: Array[Player]):
	for p in roster:
		p.free()

func check_pure_matrix():
	for count in range(2, 11):
		var roster := make_roster(count)
		check(FreeForAllVictory.evaluate(roster).is_empty(), "F%02d %d 人开局继续" % [count, count])
		mark_dead(roster, range(1, count))
		var outcome := FreeForAllVictory.evaluate(roster)
		check(outcome.get("winner", "") == "P0" and outcome.get("winner_seat", -1) == 0,
			"F%02d %d 人仅剩 P0 最终存活" % [count + 10, count])
		free_roster(roster)

	var roster := make_roster(4)
	mark_dead(roster, [0, 1, 2, 3])
	var outcome := FreeForAllVictory.evaluate(roster)
	check(outcome.get("is_draw", false) and outcome.get("winner", "") == "平局", "F20 全员最终死亡判平局")
	free_roster(roster)

	roster = make_roster(3)
	mark_dead(roster, [1])
	roster[2].hp = 0
	check(FreeForAllVictory.evaluate(roster).is_empty(), "F21 存在濒死者时等待救援，不提前判唯一生还者")
	roster[2].mark_dead()
	check(FreeForAllVictory.evaluate(roster).get("winner", "") == "P0", "F22 濒死者最终死亡后判唯一生还者")
	free_roster(roster)

	for invalid_count in [0, 1, 11]:
		roster = make_roster(invalid_count)
		check(FreeForAllVictory.evaluate(roster).is_empty(), "F23 拒绝 %d 人配置" % invalid_count)
		free_roster(roster)

	roster = make_roster(2)
	roster[1].identity = "反贼"
	check(FreeForAllVictory.evaluate(roster).is_empty(), "F24 有身份角色不能套用乱斗判胜")
	roster[1].identity = ""
	var invalid: Array[Player] = [roster[0], roster[0]]
	check(FreeForAllVictory.evaluate(invalid).is_empty(), "F25 重复角色引用拒绝判胜")
	invalid[1] = null
	check(FreeForAllVictory.evaluate(invalid).is_empty(), "F26 缺失角色拒绝判胜")
	free_roster(roster)

func reset_case():
	for p in game.players:
		p.identity = ""
		p.identity_revealed = false
		p.hp = p.max_hp
		p.hand.clear()
		p.equipment.clear()
		p.judgment_cards.clear()
		p.determined_cards.clear()
	game.reset_game_over_state()
	game._stop_countdown()
	game._sacrifice_override = func(): return false
	game._nullify_override = func(): return false
	game._dying_peach_override = func(): return false
	winners.clear()

func check_integration():
	GameManager.random_identity = false
	GameManager.random_general = false
	GameManager.selected_players = 3
	GameManager.selected_mode = GameManager.MODE_FREE_FOR_ALL
	GameManager.selected_general = "稻草人"
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	root.add_child(game)
	await process_frame
	game.start_game()
	game._stop_countdown()
	game.game_over.connect(func(winner: String): winners.append(winner))

	check(game.game_mode == GameManager.MODE_FREE_FOR_ALL and game.players.size() == 3, "F30 三人乱斗按显式模式启动")
	check(game.players.all(func(p): return p.identity == ""), "F31 乱斗所有玩家无身份")

	reset_case()
	mark_dead(game.players, [2])
	var killer := game.players[0]
	var victim := game.players[1]
	victim.hp = 1
	await game._deal_damage(killer, victim, 1, EffectChain.DamageType.PHYSICAL)
	check(winners == ["玩家 1"], "F32 最后一名最终存活玩家获胜")
	check(killer.hand_size() == 0, "F33 乱斗击杀不摸奖励牌")
	var overlay = game._game_over_overlay
	game._handle_death(victim, killer)
	game._check_win_condition(victim, killer)
	check(winners.size() == 1 and game._game_over_overlay == overlay, "F34 终局信号与弹窗只创建一次")

	reset_case()
	mark_dead(game.players, [1])
	var dying := game.players[0]
	var survivor := game.players[2]
	dying.hp = 0
	dying.hand.append(CardBase.create(CardData.CardSubType.PEACH))
	game._check_win_condition(null, null)
	check(winners.is_empty(), "F35 最后对手仍濒死时暂缓终局")
	game._dying_peach_override = func(): return true
	await game._check_dying(dying)
	check(dying.is_alive() and winners.is_empty(), "F36 救回后两人存活，对局继续")
	survivor.hp = 0
	game._handle_death(survivor, null)
	check(winners == ["玩家 1"], "F37 救回者后来成为唯一生还者")

	reset_case()
	mark_dead(game.players, [0, 1])
	game.players[2].hp = 0
	game._handle_death(game.players[2], null)
	check(winners == ["平局"], "F38 全员最终死亡只宣告平局")

	game.queue_free()
	await process_frame
	GameManager.selected_players = 5
	GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY

func _run():
	check_pure_matrix()
	await check_integration()
	print("RESULT: %d asserts, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
