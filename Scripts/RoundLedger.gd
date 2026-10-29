# I01b bookkeeping only. Placement and interruption primitives do not authorize
# a skill, choose its window, or establish a timeout rule.
class_name RoundLedger
extends RefCounted

signal space_relocated(seat: int, before: int)

enum Kind { ORDINARY, EXTRA }
var round_id := 0
var round_head := -1
var _fixed: Array[int] = []
var _space: Array[int] = []
var _pending: Array[int] = []
var _frames: Array[Dictionary] = []
var _last_ordinary := -1

func initialize(seats: Array[int]) -> bool:
	if not _fixed.is_empty() or seats.is_empty(): return false
	var seen: Array[int] = []
	for seat in seats:
		if seat < 0 or seen.has(seat): return false
		seen.append(seat)
	_fixed.assign(seats)
	_space.assign(seats)
	return true

func _valid_live(live: Array[int]) -> bool:
	var seen: Array[int] = []
	for seat in live:
		if not _fixed.has(seat) or seen.has(seat): return false
		seen.append(seat)
	return not _fixed.is_empty()

func fixed_seats() -> Array[int]: return _fixed.duplicate()
func space_order() -> Array[int]: return _space.duplicate()
func pending_seats() -> Array[int]: return _pending.duplicate()
func current() -> Dictionary:
	return _frames.back().duplicate() if not _frames.is_empty() else {}

# Before START effects, choose one still-unspent ordinary quota.
func select_pending(seat: int) -> bool:
	if _frames.size() != 1 or _frames[0].kind != Kind.ORDINARY or not _pending.has(seat): return false
	_frames[0].seat = seat
	return true

func next_pending_except(seat: int) -> int:
	var origin = _space.find(seat)
	if origin < 0: return -1
	for offset in range(1, _space.size()):
		var candidate = _space[(origin + offset) % _space.size()]
		if _pending.has(candidate): return candidate
	return -1

func begin_next(live: Array[int]) -> int:
	if not _frames.is_empty() or not _valid_live(live) or live.is_empty(): return -1
	# Final deaths count as processed without inventing a turn for the dead.
	_pending = _pending.filter(func(seat): return live.has(seat))
	if _pending.is_empty():
		round_id += 1
		round_head = live.min()
		_pending.assign(live)
		_last_ordinary = -1
	var next := round_head
	if _last_ordinary >= 0:
		var origin = _space.find(_last_ordinary)
		for offset in range(1, _space.size() + 1):
			var seat = _space[(origin + offset) % _space.size()]
			if _pending.has(seat):
				next = seat
				break
	if not _pending.has(next): return -1
	_frames.append({"seat": next, "kind": Kind.ORDINARY, "round": round_id})
	return next

func finish() -> Dictionary:
	if _frames.is_empty(): return {}
	var finished = _frames.pop_back()
	if finished.kind == Kind.ORDINARY:
		_pending.erase(finished.seat)
		_last_ordinary = finished.seat
	return finished

# An already-authorized immediate extra turn suspends the active frame. It never
# pays another ordinary-turn quota; its exact triggering skill belongs to caller.
func begin_extra(seat: int) -> bool:
	if not _fixed.has(seat) or round_id == 0: return false
	_frames.append({"seat": seat, "kind": Kind.EXTRA, "round": round_id})
	return true

# Spatial primitive only; the skill caller must validate its window and quota.
func relocate_before(seat: int, before: int) -> bool:
	if seat == before or not _fixed.has(seat) or not _fixed.has(before): return false
	_space.erase(seat)
	_space.insert(_space.find(before), seat)
	space_relocated.emit(seat, before)
	return true
