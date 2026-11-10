# Pre-move bookkeeping only. This object neither authorizes a skill nor moves
# cards. The effect caller retains its paid cost and its local prevention scope.
class_name CardLossTransaction
extends RefCounted

enum Outcome { ALLOW, PREVENTED, INVALIDATED }
var source: Player
var reason: String
var losses: Array[Dictionary] = []
var _owners: Array[Dictionary] = []
var _closed := false

func _init(actor: Player, effect: String, atoms: Array[Dictionary]):
	source = actor
	reason = effect
	losses.assign(atoms.duplicate())
	var seen: Array[Player] = []
	for atom in losses:
		var p: Player = atom.owner
		if seen.has(p): continue
		seen.append(p)
		var equipment: Dictionary = {}
		for slot in p.get_equip_slots():
			equipment[slot] = [p.equipment[slot], p.get_hidden_equipment_card(slot)
				if p.equipment[slot] == CardData.CardSubType.HIDDEN_EQUIPMENT else p.get_equipment_card(slot)]
		_owners.append({"owner": p, "hand": p.hand.duplicate(), "determined": p.determined_cards.duplicate(),
			"judgment": p.judgment_cards.duplicate(), "equipment": equipment,
			"general": p.general_name, "revision": p.awakening_revision, "life": p.life_state})

func valid() -> bool:
	if _closed or losses.is_empty(): return false
	for state in _owners:
		var p: Player = state.owner
		if not is_instance_valid(p) or p.life_state != state.life or p.general_name != state.general \
				or p.awakening_revision != state.revision or p.hand != state.hand \
				or p.determined_cards != state.determined or p.judgment_cards != state.judgment \
				or p.get_equip_slots().size() != state.equipment.size(): return false
		for slot in state.equipment:
			if p.equipment.get(slot, -1) != state.equipment[slot][0]: return false
			var card = p.get_hidden_equipment_card(slot) if p.equipment[slot] == CardData.CardSubType.HIDDEN_EQUIPMENT else p.get_equipment_card(slot)
			if card != state.equipment[slot][1]: return false
	for atom in losses:
		var p: Player = atom.owner
		match atom.zone:
			"hand", "determined", "judgment":
				var cards: Array = p.hand if atom.zone == "hand" else (p.determined_cards if atom.zone == "determined" else p.judgment_cards)
				if atom.index < 0 or atom.index >= cards.size() or cards[atom.index] != atom.card: return false
				if atom.has("draw_id") and (atom.zone!="hand" or not atom.has("draw_epoch") \
						or p.draw_hand_index(int(atom.draw_id),int(atom.draw_epoch))!=atom.index): return false
			"equip":
				var card = p.get_hidden_equipment_card(atom.slot) if p.equipment.get(atom.slot, -1) == CardData.CardSubType.HIDDEN_EQUIPMENT else p.get_equipment_card(atom.slot)
				if atom.card == null or card != atom.card: return false
			_: return false
	return true

func close() -> void:
	_closed = true
