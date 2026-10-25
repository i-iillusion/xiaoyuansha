# I03b-1: state primitives only. Callers authorize skills/phases, pay physical
# cards, register bodies, dispatch actual turns/USE facts and await effects.
# This component does not open Chris or route a unit action through its owner.
class_name FireDragonState
extends RefCounted

var _registry: UnitRegistry
var _generation := -1
var _dragons: Dictionary = {}
var _initialized: Array[Player] = []

func initialize(registry: UnitRegistry) -> bool:
	if _registry != null or registry == null or registry.players().is_empty(): return false
	_registry = registry
	_generation = registry.generation()
	return true

func reset() -> void:
	_registry = null
	_generation = -1
	_dragons.clear()
	_initialized.clear()

func _owner_valid(owner: Player) -> bool:
	return _registry != null and _registry.generation() == _generation and is_instance_valid(owner) and _registry.players().has(owner) and not owner.is_dead()

# Called once at game start, not when a turn begins or a learned skill changes.
func grant_start_egg(owner: Player) -> bool:
	if not _owner_valid(owner) or owner.general_name != "克里斯·西弗" or _initialized.has(owner): return false
	owner.fire_dragon_eggs = 1
	_initialized.append(owner)
	return true

func has_dragon(owner: Player) -> bool:
	if not _owner_valid(owner): return false
	for body in _registry.turn_units():
		if _registry.entry(_registry.id_for(body)).summoner == owner: return true
	return false

# Eligibility only: no automatic discard, no partial payment and no UI default.
func can_summon(owner: Player) -> bool:
	return _owner_valid(owner) and owner.is_alive() and owner.fire_dragon_eggs > 0 and owner.hand_size() >= 3 and not has_dragon(owner)

func can_heal(owner: Player, acting_body: Player, phase: int) -> bool:
	return _owner_valid(owner) and owner.fire_dragon_eggs > 0 and (owner.is_dying() or (owner == acting_body and phase == TurnManager.Phase.PLAY))

# Resource primitive. Skill callers own the atomic transaction with other costs.
func spend_egg(owner: Player) -> bool:
	if not _owner_valid(owner) or owner.fire_dragon_eggs <= 0: return false
	owner.fire_dragon_eggs -= 1
	return true

static func create_body() -> Player:
	var body = Player.new()
	body.player_name = "火龙"
	body.general_name = "火龙"
	body.identity = ""
	body.seat_index = -1
	body.max_hp = 3
	body.hp = 3
	return body

func attach(id: String) -> bool:
	if _registry == null or _registry.generation() != _generation or _dragons.has(id): return false
	var entry = _registry.entry(id)
	if entry.is_empty() or entry.kind != UnitRegistry.Kind.FIRE_DRAGON or entry.removed: return false
	var body: Player = entry.body
	if not is_instance_valid(body) or not body.is_alive() or body.max_hp != 3 or body.hp != 3 or body.hand_size() != 0: return false
	if not _owner_valid(entry.summoner): return false
	_dragons[id] = {"last_turn": 0, "turn_count": 0, "egg_awarded": false, "last_use": 0, "revealed": []}
	return true

func _live_entry(id: String) -> Dictionary:
	if _registry == null or not _dragons.has(id): return {}
	var entry = _registry.entry(id)
	if entry.is_empty() or entry.removed or not _registry.contains_active(entry.body) or not _owner_valid(entry.summoner): return {}
	return entry

# Authorized USE (not RESPONSE/discard/payment); supply the full designated
# target list once, before effects. Nullification does not undo a USE fact.
func record_use(id: String, action_id: int, targets: Array[Player]) -> bool:
	var entry = _live_entry(id)
	if entry.is_empty() or action_id <= int(_dragons[id].last_use): return false
	for target in targets:
		if not is_instance_valid(target) or target.is_dead(): return false
		if not _registry.players().has(target) and not _registry.turn_units().has(target): return false
	_dragons[id].last_use = action_id
	for target in targets:
		if not _dragons[id].revealed.has(target): _dragons[id].revealed.append(target)
	return true

func is_revealed_to(id: String, source: Player) -> bool:
	return not _live_entry(id).is_empty() and is_instance_valid(source) and _dragons[id].revealed.has(source)

# Only the stealth gate, not card/phase/range authorization. Q6 permits self
# targeting without creating a USE fact or revealing the dragon to anyone else.
func stealth_allows_target(id: String, source: Player) -> bool:
	var entry = _live_entry(id)
	if entry.is_empty() or not is_instance_valid(source) or source.is_dead(): return false
	if source == entry.body: return true
	if not _registry.players().has(source) and not _registry.turn_units().has(source): return false
	return is_revealed_to(id, source)

# Positive receipt IDs from actual unit START, not the controller's START or a
# WAITING->PLAY resume. Never count round boundaries as a unit's own turns.
func begin_turn(id: String, receipt_id: int) -> bool:
	var entry = _live_entry(id)
	if entry.is_empty() or not entry.body.is_alive() or receipt_id <= int(_dragons[id].last_turn): return false
	_dragons[id].last_turn = receipt_id
	_dragons[id].turn_count += 1
	if _dragons[id].turn_count == 2 and not _dragons[id].egg_awarded:
		entry.summoner.fire_dragon_eggs += 1
		_dragons[id].egg_awarded = true
	return true

func draw_count(id: String) -> int:
	var entry = _live_entry(id)
	return 1 if not entry.is_empty() and entry.body.is_alive() else 0

func turn_count(id: String) -> int:
	return int(_dragons[id].turn_count) if not _live_entry(id).is_empty() else 0
