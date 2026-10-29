# I04b: persistent spatial markers. Fixed player IDs remain distinct from unit
# IDs. Dead players are omitted only when projecting a living query; the marker
# stays for retained-body/revival semantics. Fire dragons never enter this ring.
class_name MountainSpace
extends RefCounted

var _fixed: Array[int] = []
var _ring: Array = []
var _mountains: Array[String] = []

func initialize(order: Array[int]) -> bool:
	if not _fixed.is_empty() or order.size() < 2 or order.size() > 10: return false
	var seen: Array[int] = []
	for seat in order:
		if seat < 0 or seen.has(seat): return false
		seen.append(seat)
	_fixed.assign(order)
	_ring.assign(order)
	return true

func reset() -> void:
	_fixed.clear()
	_ring.clear()
	_mountains.clear()

func markers() -> Array: return _ring.duplicate()
func ids() -> Array[String]: return _mountains.duplicate()

func player_order() -> Array[int]:
	var result: Array[int] = []
	for marker in _ring:
		if typeof(marker) == TYPE_INT: result.append(marker)
	return result

func _valid_live(live: Array[int]) -> bool:
	var seen: Array[int] = []
	for seat in live:
		if not _fixed.has(seat) or seen.has(seat): return false
		seen.append(seat)
	return not _fixed.is_empty()

func _living_ring(live: Array[int]) -> Array:
	return _ring.filter(func(marker): return typeof(marker) == TYPE_STRING or live.has(marker))

func legal_gap(left: int, right: int, live: Array[int]) -> bool:
	if not _valid_live(live) or live.size() < 2 or left == right: return false
	var order = player_order().filter(func(seat): return live.has(seat))
	var index = order.find(left)
	return index >= 0 and order[(index + 1) % order.size()] == right

# Gap placement ignores intervening mountain markers: two mountains may share
# one gap. No center, owner-following anchors or unit-as-player positions.
func place(id: String, left: int, right: int, live: Array[int]) -> bool:
	if id.is_empty() or _mountains.has(id) or _mountains.size() >= 2 or not legal_gap(left, right, live): return false
	_ring.insert(_ring.find(right), id)
	_mountains.append(id)
	return true

func move(id: String, left: int, right: int, live: Array[int]) -> bool:
	if not _mountains.has(id) or not legal_gap(left, right, live): return false
	_ring.erase(id)
	_ring.insert(_ring.find(right), id)
	return true

func remove(id: String) -> bool:
	if not _mountains.has(id): return false
	_ring.erase(id)
	_mountains.erase(id)
	return true

# Mirrors the already-authorized RoundLedger operation. Removing just the
# player leaves the mountains at their original spatial positions (I04-Q3).
func relocate_before(seat: int, before: int) -> bool:
	if seat == before or not _fixed.has(seat) or not _fixed.has(before): return false
	_ring.erase(seat)
	_ring.insert(_ring.find(before), seat)
	return true

func snapshot(live: Array[int]) -> MountainTopology:
	if not _valid_live(live) or live.size() < 2: return null
	var ring = _living_ring(live)
	var order: Array[int] = []
	var placements: Array[Dictionary] = []
	for marker in ring:
		if typeof(marker) == TYPE_INT: order.append(marker)
	for id in _mountains:
		var index = ring.find(id)
		var left := -1
		var right := -1
		for step in range(1, ring.size()):
			var marker = ring[posmod(index - step, ring.size())]
			if typeof(marker) == TYPE_INT:
				left = marker
				break
		for step in range(1, ring.size()):
			var marker = ring[(index + step) % ring.size()]
			if typeof(marker) == TYPE_INT:
				right = marker
				break
		placements.append({"id": id, "left": left, "right": right})
	var result = MountainTopology.new()
	return result if result.configure(order, placements) else null
