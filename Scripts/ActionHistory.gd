class_name ActionHistory
extends RefCounted

# Player-facing value records only. Never ingest debug output or live rule objects.
const LIMIT := 2000
const BATCH := 128
signal changed()
var match_key := ""
var sequence := 0
var _ring: Array[Dictionary] = []
var _head := 0
var _view: Array[Dictionary] = []
var _dirty := true
var entries: Array[Dictionary]:
	get:
		if _dirty:
			_view = []
			for i in _ring.size(): _view.append(_ring[(_head + i) % _ring.size()])
			_dirty = false
		return _view

func _retain(entry: Dictionary) -> void:
	if _ring.size() < LIMIT:
		_ring.append(entry)
	else:
		_ring[_head] = entry
		_head = (_head + 1) % LIMIT
	_dirty = true

func reset(key: String) -> void:
	match_key = key
	sequence = 0
	_ring.clear()
	_view.clear()
	_head = 0
	_dirty = true
	changed.emit()

func append(kind: String, text: String, turn: int, phase: int, actor: int = -1,
		targets: Array = [], details: Dictionary = {}) -> void:
	sequence += 1
	_retain({"seq": sequence, "kind": kind, "text": text, "turn": turn,
		"phase": phase, "actor": actor, "targets": targets.duplicate(), "details": details.duplicate(true)})
	changed.emit()

func packet(after: int = 0) -> Dictionary:
	var batch: Array[Dictionary] = []
	for entry in entries:
		if int(entry.seq) <= after: continue
		batch.append(entry.duplicate(true))
		if batch.size() == BATCH: break
	return {"match": match_key, "first": entries[0].seq if not entries.is_empty() else sequence + 1,
		"last": sequence, "entries": batch}

# Reliable server batches may repeat; old matches and out-of-order records cannot
# overwrite current history. Missing retained records are explicitly shown by UI.
func receive(packet: Dictionary) -> bool:
	if str(packet.get("match", "")) != match_key: return false
	var dirty := false
	for entry in packet.get("entries", []):
		if int(entry.seq) <= sequence: continue
		if int(entry.seq) != sequence + 1 and int(entry.seq) != int(packet.first): return false
		if int(entry.seq) != sequence + 1:
			# Server retention has overtaken this client. Do not display the old
			# prefix as if it were contiguous with the new retained window.
			_ring.clear()
			_view.clear()
			_head = 0
			_dirty = true
		_retain(entry.duplicate(true))
		sequence = int(entry.seq)
		dirty = true
	if dirty: changed.emit()
	return true

func visible_text() -> String:
	var lines: PackedStringArray = []
	if not entries.is_empty() and int(entries[0].seq) > 1:
		lines.append("较早记录已超出保留范围。")
	for entry in entries:
		lines.append("#%d · 回合%d · %s" % [entry.seq, entry.turn, entry.text])
	return "\n".join(lines)
