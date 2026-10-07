# Test-only decisions installed before the real scene's auto-start. No altered
# HP/cards/victory, and no production navigation interception.
extends "res://Test/replay_game.gd"

var opening: Dictionary = {}
var completed_turns: int = 0
var winners: Array[String] = []
var equipped_first: bool = false

func _ready():
	ai_driver.rng.seed = 7401
	_dodge_override = func(): return true
	_aoe_override = func(): return true
	_duel_respond_override = func(): return true
	_duel_second_override = func(): return true
	_nullify_override = func(): return false
	_sacrifice_override = func(): return false
	_hand_discard_override = func(snapshot, amount, _mandatory): return snapshot.defaults(amount)
	_zone_pick_override = func(): return "hand"
	_prep_replace_override = func(_l, _u, _t, _s, _o): return -1
	_rescue_choice_override = func(r, d, o): return _choose_ai_rescue(r, d, o)
	game_over.connect(func(winner): winners.append(winner))
	super._ready()

func _on_phase_changed(old_phase, new_phase, pid):
	if opening.is_empty() and new_phase == TurnManager.Phase.START:
		opening = {"hands": players.map(func(p): return p.hand_size()),
			"hp": players.map(func(p): return p.hp), "pool": equipment_pool.claimed_count(),
			"discard": deck._discard.size(), "turn": turn_manager.turn_id,
			"counts": turn_manager._turn_card_counts.duplicate(true),
			"windows": _choice_prompt_stack.size(), "pending": _pending_card_actions.size(),
			"dying": _dying_contexts.size(), "paused": rule_scheduler.is_paused(),
			"yudaxi": yudaxi.is_active(), "standalone": turn_manager._standalone_play_frame.duplicate(true)}
	super._on_phase_changed(old_phase, new_phase, pid)

func _do_play(pid: int):
	# One legal real equipment use proves that a later new game can reclaim this
	# same name. Existing replay observer drives all further choices normally.
	if pid == 0 and not equipped_first and not _game_over:
		equipped_first = true
		await play_card(CardData.CardSubType.LIANNU)
	await super._do_play(pid)

func _on_turn_ended(pid: int):
	if not _game_over and players[pid].is_alive(): completed_turns += 1
	super._on_turn_ended(pid)
