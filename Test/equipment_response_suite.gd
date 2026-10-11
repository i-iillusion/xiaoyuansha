# Isolated host for whole existing equipment-response modules moved out of the
# saturated confirmed/core suites. Same reset fixture; modules/assertions unchanged.
extends RefCounted

var host
var game: GameManager
var process_frame: Signal:
	get: return host.process_frame
var root: Window:
	get: return host.root

func create_timer(seconds: float) -> SceneTreeTimer:
	return host.create_timer(seconds)

func check(ok: bool, message: String):
	host.check(ok, message)

func strike(source: Player, target: Player, ignore_restrictions: bool = false):
	return await game._execute_single_strike(source, target,
		CardBase.create(CardData.CardSubType.STRIKE), CardData.CardSubType.STRIKE,
		EffectChain.DamageType.PHYSICAL, 1, ignore_restrictions)

func reset_players():
	game._hand_discard_override = func(snapshot, count, _mandatory): return snapshot.defaults(count)
	game.reset_game_over_state()
	game._sacrifice_override = func(): return false
	game._sacrifice_actor_override = Callable()
	game._ai_response_override = func(_view, _kind, _options): return -1
	game._prep_replace_override = func(_leo, _user, _target, _sub, _options): return -1
	game._dodge_override = func(): return false
	game._dying_peach_override = func(): return false
	game._rescue_choice_override = func(_rescuer, _dying, _options): return -1
	game._nullify_override = func(): return false
	game._yes_ah_override = Callable()
	game._aoe_override = func(): return false
	game._duel_respond_override = func(): return false
	game._duel_second_override = func(): return false
	game.turn_manager.current_player_idx = 0
	game.turn_manager.play_actor_idx = -1
	game.turn_manager._reset_turn_counts()
	game.turn_manager._phase_skill_uses.clear()
	for p in game.players:
		p.reset_death_state()
		p.general_name = "稻草人"
		p.max_hp = 10
		p.hp = 10
		p.hand.clear()
		p.determined_cards.clear()
		p.equipment.clear()
		p.equipment_cards.clear()
		p.chained = false
		p.kneeling = false
		p.consume_wine_bonus()
		p.heal_staff_peach_used = false
		p.awoken = false
		p.awake_choice = 0
		p.prep_tokens = 0
		p.capture_game_start_state()

func run(suite):
	host = suite
	var previous = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general,
		GameManager.random_general, GameManager.random_identity]
	GameManager.selected_players = 5
	GameManager.selected_mode = GameManager.MODE_CLASSIC_IDENTITY
	GameManager.selected_general = "稻草人"
	GameManager.random_general = false
	GameManager.random_identity = false
	game = load("res://Scenes/Game.tscn").instantiate()
	game.auto_start = false
	host.root.add_child(game)
	await host.process_frame
	game.start_game()
	game._stop_countdown()
	for module in ["soul_blade_prompt_cases", "soul_blade_discard_cases", "soul_blade_rps_cases", "soul_blade_activation_cases",
		"play_skill_selection_generation_cases",
		"play_skill_entry_guard_cases",
		"exchange_prompt_lifecycle_cases",
		"kneel_prompt_lifecycle_cases",
		"shensu_prompt_lifecycle_cases",
		"grant_prompt_lifecycle_cases",
		"standalone_grant_cases",
		"sage_save_lifecycle_cases",
		"rescue_lifecycle_cases",
		"dying_caller_lifecycle_cases",
		"judgment_damage_lifecycle_cases",
		"thorn_lifecycle_cases",
		"yes_ah_discard_lifecycle_cases",
		"zhuangbi_revised_rule_cases",
		"reset_scheduler_ai_cases",
		"reveal_inner_lifecycle_cases",
		"response_target_reset_cases",
		"awaken_reset_cases",
		"ui_tail_reset_cases",
		"mandatory_skill_cases",
		"equipment_boundary_cases"]:
		await load("res://Test/" + module + ".gd").new().run(self)
	game._game_over = true
	game.queue_free()
	await host.process_frame
	game = null
	GameManager.selected_players = previous[0]
	GameManager.selected_mode = previous[1]
	GameManager.selected_general = previous[2]
	GameManager.random_general = previous[3]
	GameManager.random_identity = previous[4]
	host = null
