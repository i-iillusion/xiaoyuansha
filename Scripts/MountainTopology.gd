# I04a: an immutable-by-copy query snapshot, not placement/lifecycle authority.
# Inputs contain only living fixed-player spatial IDs and already specified
# current gaps. No owner anchoring, death projection or relocation policy here.
class_name MountainTopology
extends RefCounted

const UNREACHABLE: int = LivingTable.UNREACHABLE
var _order: Array[int] = []
var _mountains: Array[Dictionary] = []
var _blocked: Dictionary = {}

func configure(order: Variant, mountains: Variant) -> bool:
	if typeof(order) != TYPE_ARRAY or order.size() < 2 or order.size() > 10: return false
	var seats: Array[int] = []
	for seat in order:
		if typeof(seat) != TYPE_INT or seat < 0 or seats.has(seat): return false
		seats.append(seat)
	if typeof(mountains) != TYPE_ARRAY or mountains.size() > 2: return false
	var entries: Array[Dictionary] = []
	var ids: Array[String] = []
	var blocked: Dictionary = {}
	for mountain in mountains:
		if typeof(mountain) != TYPE_DICTIONARY or mountain.size() != 3 or not mountain.has_all(["id", "left", "right"]): return false
		if typeof(mountain.id) != TYPE_STRING or mountain.id.is_empty() or ids.has(mountain.id): return false
		if typeof(mountain.left) != TYPE_INT or typeof(mountain.right) != TYPE_INT: return false
		var left = seats.find(mountain.left)
		if left < 0 or seats[(left + 1) % seats.size()] != mountain.right: return false
		ids.append(mountain.id)
		entries.append(mountain.duplicate(true))
		blocked[mountain.left] = true
	_order = seats
	_mountains = entries
	_blocked = blocked
	return true

func order() -> Array[int]: return _order.duplicate()
func placements() -> Array[Dictionary]: return _mountains.duplicate(true)

# Mountains block arcs, never add a player-distance step. Unreachable is not a
# finite route that horses or a range-independent weapon can make cross-region.
func player_distance(source: int, target: int) -> int:
	if not _order.has(source) or not _order.has(target): return UNREACHABLE
	var distance = _distances_from(source)
	return distance.get(target, UNREACHABLE)

func same_region(source: int, target: int) -> bool:
	return player_distance(source, target) != UNREACHABLE

func mountain_distance(source: int, id: String) -> int:
	if not _order.has(source): return UNREACHABLE
	for mountain in _mountains:
		if mountain.id != id: continue
		var near = mini(player_distance(source, mountain.left), player_distance(source, mountain.right))
		return UNREACHABLE if near == UNREACHABLE else near + 1
	return UNREACHABLE

# Membership sets only; the eventual skill pipeline chooses settlement order.
# Both IDs in the same gap enclose an empty side, not an extra spatial seat.
func sides() -> Array:
	if _mountains.size() != 2: return []
	var first = _mountains[0]
	var second = _mountains[1]
	if first.left == second.left: return [[], _order.duplicate()]
	var arc: Array[int] = []
	var start = _order.find(first.right)
	for offset in _order.size():
		var seat = _order[(start + offset) % _order.size()]
		arc.append(seat)
		if seat == second.left: break
	var other: Array[int] = []
	for seat in _order:
		if not arc.has(seat): other.append(seat)
	return [arc, other]

# I04-Q5: Gather counts fixed players only, never a controller's fire dragon.
# The snapshot deliberately contains no summon vertices. Return membership,
# not effect legality/order: I04-Q6 permits Gather itself across the partition.
func gather_for_players() -> Dictionary:
	var counts: Array[int] = []
	for side in sides(): counts.append(side.size())
	return gather_options(counts)

# Low-level explicit-count query retained for validation; production Gather
# must use gather_for_players() under I04-Q5, not add summons to these counts.
func gather_options(counts: Variant) -> Dictionary:
	var result = {"heal": [], "lose": []}
	var regions = sides()
	if regions.is_empty() or typeof(counts) != TYPE_ARRAY or counts.size() != 2: return result
	for index in 2:
		if typeof(counts[index]) != TYPE_INT or counts[index] < regions[index].size(): return result
	if counts[0] == counts[1]: return result
	var small = regions[0] if counts[0] < counts[1] else regions[1]
	var large = regions[1] if counts[0] < counts[1] else regions[0]
	if not small.is_empty(): result.heal = small.duplicate()
	result.lose = large.duplicate()
	return result

func _distances_from(source: int) -> Dictionary:
	var result = {source: 0}
	var pending: Array[int] = [source]
	var cursor := 0
	while cursor < pending.size():
		var seat = pending[cursor]
		cursor += 1
		var index = _order.find(seat)
		var next = _order[(index + 1) % _order.size()]
		var previous = _order[(index + _order.size() - 1) % _order.size()]
		var neighbors: Array[int] = []
		if not _blocked.has(seat): neighbors.append(next)
		if not _blocked.has(previous): neighbors.append(previous)
		for neighbor in neighbors:
			if not result.has(neighbor):
				result[neighbor] = result[seat] + 1
				pending.append(neighbor)
	return result
