# I02b: membership and event classification only. No skill authorization,
# card disposal or turn insertion occurs in this registry.
class_name UnitRegistry
extends RefCounted

enum Kind { FIRE_DRAGON, MOUNTAIN }
enum Removal { NORMAL_DEATH, SUMMONER_LOST }
var _players: Array[Player] = []
var _entries: Dictionary = {}
var _serial := 0
var _epoch := 0

func initialize(roster: Array[Player]) -> bool:
	if not _players.is_empty() or roster.is_empty(): return false
	var ids: Array[int] = []
	for player in roster:
		if not is_instance_valid(player) or player.seat_index < 0 or ids.has(player.seat_index): return false
		ids.append(player.seat_index)
	_players.assign(roster)
	return true

func reset() -> void:
	_players.clear()
	_entries.clear()
	_serial = 0
	_epoch += 1

# Caller creates/configures the body and validates its summoning skill/position.
# Strings are a different ID namespace from permanent player seat integers.
func register(kind: int, body: Player, summoner: Player) -> String:
	if kind not in [Kind.FIRE_DRAGON, Kind.MOUNTAIN]: return ""
	if not is_instance_valid(body) or not is_instance_valid(summoner): return ""
	if not _players.has(summoner) or summoner.is_dead() or _players.has(body) or body.is_dead(): return ""
	if body.identity != "" or body.identity_max_hp_bonus != 0: return ""
	for entry in _entries.values():
		if entry.body == body: return "" # Removed bodies cannot be re-registered.
	_serial += 1
	var id = "unit:%d:%d" % [_epoch, _serial]
	_entries[id] = {"id": id, "kind": kind, "body": body, "summoner": summoner,
		"controller": summoner if kind == Kind.FIRE_DRAGON else null, "removed": false, "reason": -1}
	return id

func players() -> Array[Player]: return _players.duplicate()

func entry(id: String) -> Dictionary:
	return _entries[id].duplicate() if _entries.has(id) else {}

func id_for(body: Player) -> String:
	for id in _entries:
		if _entries[id].body == body: return id
	return ""

func contains_active(body: Player) -> bool:
	var id = id_for(body)
	return not id.is_empty() and not _entries[id].removed and is_instance_valid(body) and not body.is_dead()

func all_bodies() -> Array[Player]:
	var result: Array[Player] = []
	for value in _entries.values():
		if is_instance_valid(value.body): result.append(value.body)
	return result

func active_units() -> Array[Player]:
	var result: Array[Player] = []
	for value in _entries.values():
		if not value.removed and is_instance_valid(value.body) and not value.body.is_dead(): result.append(value.body)
	return result

# Only intelligent units have actors/controllers. Mountains remain attached to
# their summoner for cleanup, but are not autonomous controlled characters.
func turn_units() -> Array[Player]:
	var result: Array[Player] = []
	for value in _entries.values():
		if value.kind == Kind.FIRE_DRAGON and not value.removed and is_instance_valid(value.body) and not value.body.is_dead(): result.append(value.body)
	return result

func controller(id: String) -> Player:
	var value = entry(id)
	if value.is_empty() or value.removed or not is_instance_valid(value.controller) or value.controller.is_dead(): return null
	return value.controller

# Explicitly named query sets; do not reuse a single generic "all actors" list.
func zhuangsha_count_participants() -> Array[Player]: return _living_players()
func science_count_participants() -> Array[Player]: return _living_players()
func yudaxi_candidates() -> Array[Player]: return _living_players()
func victory_roster() -> Array[Player]: return players() # Dead player rows matter.

func _living_players() -> Array[Player]:
	var result: Array[Player] = []
	for player in _players:
		if is_instance_valid(player) and not player.is_dead(): result.append(player)
	return result

# Candidate classification, NOT final target legality. Stealth, kneeling,
# distance and mountain partitions are validated by their future callers.
func strike_unit_candidates() -> Array[Player]: return active_units()
func character_unit_candidates() -> Array[Player]: return turn_units()

func retire_dead(id: String) -> Dictionary:
	var value = entry(id)
	if value.is_empty() or value.removed or not is_instance_valid(value.body) or not value.body.is_dead(): return {}
	return _retire(id, Removal.NORMAL_DEATH)

func detach_final_summoner(summoner: Player) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not is_instance_valid(summoner) or not _players.has(summoner) or not summoner.is_dead(): return events
	for id in _entries:
		var value: Dictionary = _entries[id]
		if value.summoner == summoner and not value.removed:
			events.append(_retire(id, Removal.SUMMONER_LOST))
	return events

func _retire(id: String, reason: int) -> Dictionary:
	_entries[id].removed = true
	_entries[id].reason = reason
	# No body.mark_dead(): disappearance does not fabricate a death/kill.
	return entry(id)
