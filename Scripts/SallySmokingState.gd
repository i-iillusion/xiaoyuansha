class_name SallySmokingState
extends RefCounted

# State transitions only. The GM must authorize a real phase/fee/continuation.
# These methods never pay HP/cards, resolve dying, or double any response.
static func enabled(p: Player) -> bool:
	return is_instance_valid(p) and p.sally_smoking_enabled and p.general_name == "萨利·赛克斯" \
		and not p.is_dead() and not p.unit_disappeared

static func can_smoke(p: Player) -> bool:
	return enabled(p) and p.is_alive() and p.gender == "female"

static func cost(p: Player) -> int:
	return 0 if p.sally_surgery_enabled and p.sally_surgery_active else p.sally_smoke_uses + 1

# Called at an actually confirmed payment, before any ensuing rescue.
static func note_payment(p: Player) -> bool:
	if not can_smoke(p): return false
	p.sally_smoke_uses += 1
	return true

# No counter write here: Q14 must decide how Sage interacts with the pending
# caller. A raw state helper cannot choose whether that old caller may resume.
static func establish_after_rescue(p: Player) -> bool:
	if not enabled(p) or not p.is_alive(): return false
	p.gender = "male"
	p.sally_smoke_active = true
	p.sally_smoke_pending_boost = true
	return true

static func can_operate(p: Player) -> bool:
	return enabled(p) and p.sally_surgery_enabled and p.is_alive() and p.sally_smoke_uses >= 3

static func note_operation_paid(p: Player) -> bool:
	if not can_operate(p): return false
	p.sally_surgery_pending = true
	return true

# The caller must authorize the operation's future effective boundary. Do not
# silently extend smoking's skipped-turn ruling to this separate skill.
static func establish_operation(p: Player) -> bool:
	if not enabled(p) or not p.sally_surgery_enabled or not p.is_alive() or not p.sally_surgery_pending: return false
	p.sally_surgery_pending = false
	p.sally_surgery_active = true
	return true

# A full skipped turn consumes its receipt but advances none of these effects.
# A granted PLAY never calls this method; only an actual turn may supply a key.
static func start_turn(p: Player, turn: int, skipped: bool) -> bool:
	if not enabled(p) or not p.is_alive() or turn < 0 or turn <= p.sally_smoke_last_start: return false
	p.sally_smoke_last_start = turn
	if skipped: return true
	if p.sally_smoke_pending_boost:
		p.sally_smoke_active = false
		p.sally_smoke_pending_boost = false
		p.sally_boost_turn = turn
		p.sally_female_end_turn = turn
	else:
		p.sally_boost_turn = -1
	return true

static func end_turn(p: Player, turn: int, skipped: bool) -> bool:
	if not enabled(p) or not p.is_alive() or turn < 0 or turn != p.sally_smoke_last_start \
		or turn <= p.sally_smoke_last_end: return false
	p.sally_smoke_last_end = turn
	if skipped: return true
	if p.sally_female_end_turn == turn:
		p.gender = "female"
		p.sally_female_end_turn = -1
	if p.sally_boost_turn == turn: p.sally_boost_turn = -1
	return true

static func protects_hp(p: Player, outside_turn: bool) -> bool:
	return enabled(p) and p.sally_smoke_active and outside_turn

static func doubles_response(p: Player, turn: int) -> bool:
	return enabled(p) and p.sally_boost_turn == turn and turn >= 0
