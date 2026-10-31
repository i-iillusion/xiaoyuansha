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

# Q31: a committed card keeps its original spatial origin after source death.
# Add only that retained fixed marker to this connectivity query; it is never
# restored to the turn roster, normal distance count or input ownership.
func same_region_from_anchor(source: int, target: int, live: Array[int]) -> bool:
	if not _fixed.has(source) or not live.has(target): return false
	var query: Array[int] = live.duplicate()
	if not query.has(source): query.append(source)
	var view = snapshot(query)
	return view != null and view.same_region(source,target)

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

func gaps(live: Array[int], moving_id: String = "") -> Array:
	var result: Array = []
	if not _valid_live(live) or live.size() < 2: return result
	if not moving_id.is_empty() and not _mountains.has(moving_id): return result
	var ring = _living_ring(live)
	for index in ring.size():
		var left = ring[index]
		var right = ring[(index+1)%ring.size()]
		# Q25: moving a mountain cannot select either of its own boundaries.
		if not moving_id.is_empty() and (is_same(left,moving_id) or is_same(right,moving_id)): continue
		result.append([left,right])
	return result

func legal_gap(left: Variant, right: Variant, live: Array[int]) -> bool:
	if not _valid_live(live) or live.size() < 2 or is_same(left,right): return false
	return gaps(live).has([left,right])

# Q24: a mountain splits a gap; its two boundaries are distinct destinations.
func place(id: String, left: Variant, right: Variant, live: Array[int]) -> bool:
	if id.is_empty() or _mountains.has(id) or _mountains.size() >= 2 or not legal_gap(left, right, live): return false
	_ring.insert(_ring.find(right), id)
	_mountains.append(id)
	return true

func move(id: String, left: Variant, right: Variant, live: Array[int]) -> bool:
	if not _mountains.has(id) or not gaps(live,id).has([left,right]): return false
	_ring.erase(id)
	_ring.insert(_ring.find(right), id)
	return true

# Planned pair uses a local placeholder, resolved only after actual registration.
# It is never a registry handle, input owner or player ID.
const PLANNED_FIRST = "@planned-first-mountain"

func placement_sequences(count: int, live: Array[int]) -> Array:
	var result: Array = []
	if count not in [1,2] or _mountains.size()+count > 2: return result
	for first in gaps(live):
		if count == 1: result.append([first]); continue
		var preview = MountainSpace.new()
		preview._fixed.assign(_fixed)
		preview._ring.assign(_ring)
		preview._mountains.assign(_mountains)
		if not preview.place(PLANNED_FIRST,first[0],first[1],live): continue
		for second in preview.gaps(live): result.append([first,second])
	return result

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
