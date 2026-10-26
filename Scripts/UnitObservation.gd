# Value-only unit views. Fixed player rows and player space are not unit IDs.
class_name UnitObservation
extends RefCounted

const FIELDS = ["id", "kind", "name", "summoner", "controller", "hp", "max_hp", "dying", "hand_count", "equipment", "judgments", "own_cards", "facedown", "chained", "gender"]
const NAMES = ["火龙", "山"]

static func capture(registry: UnitRegistry, viewer: Player = null) -> Array:
	var rows: Array = []
	for body in registry.active_units():
		var entry = registry.entry(registry.id_for(body))
		if not is_instance_valid(entry.summoner) or entry.summoner.is_dead(): continue
		var controller = registry.controller(entry.id)
		var own_cards: Array = []
		if controller != null and controller == viewer:
			own_cards = PlayerObservation.capture([], body, 0, 0).own_cards
		var judgments: Array = []
		for card in body.judgment_cards: judgments.append(card.sub_type)
		rows.append({"id": entry.id, "kind": entry.kind, "name": NAMES[entry.kind],
			"summoner": entry.summoner.seat_index, "controller": controller.seat_index if controller != null else -1,
			"hp": body.hp, "max_hp": body.max_hp, "dying": body.is_dying(), "hand_count": body.hand_size(),
			"equipment": body.equipment.duplicate(), "judgments": judgments, "own_cards": own_cards,
			"facedown": body.facedown, "chained": body.chained,
			"gender": body.gender if entry.kind == UnitRegistry.Kind.FIRE_DRAGON else ""})
	return rows

static func valid(rows: Variant, count: int, viewer: int) -> bool:
	if typeof(rows) != TYPE_ARRAY or rows.size() > count + 2: return false
	var ids: Array = []
	var dragon_owners: Array = []
	var mountains := 0
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY or row.size() != FIELDS.size() or not row.keys().all(func(key): return key in FIELDS): return false
		if typeof(row.id) != TYPE_STRING or not row.id.begins_with("unit:") or ids.has(row.id): return false
		ids.append(row.id)
		if typeof(row.kind) != TYPE_INT or row.kind not in [UnitRegistry.Kind.FIRE_DRAGON, UnitRegistry.Kind.MOUNTAIN]: return false
		if row.name != NAMES[row.kind] or typeof(row.summoner) != TYPE_INT or row.summoner < 0 or row.summoner >= count: return false
		if typeof(row.controller) != TYPE_INT or row.controller != (row.summoner if row.kind == UnitRegistry.Kind.FIRE_DRAGON else -1): return false
		if row.kind == UnitRegistry.Kind.FIRE_DRAGON:
			if dragon_owners.has(row.summoner): return false
			dragon_owners.append(row.summoner)
		else:
			mountains += 1
			if mountains > 2: return false
		for field in ["hp", "max_hp", "hand_count"]:
			if typeof(row[field]) != TYPE_INT: return false
		if row.max_hp <= 0 or row.hand_count < 0 or typeof(row.dying) != TYPE_BOOL: return false
		if typeof(row.facedown) != TYPE_BOOL or typeof(row.chained) != TYPE_BOOL: return false
		if typeof(row.gender) != TYPE_STRING: return false
		if row.gender not in (["male", "female", "none"] if row.kind == UnitRegistry.Kind.FIRE_DRAGON else [""]): return false
		if typeof(row.equipment) != TYPE_DICTIONARY or typeof(row.judgments) != TYPE_ARRAY or typeof(row.own_cards) != TYPE_ARRAY: return false
		for slot in row.equipment:
			if slot not in Player.EQUIP_SLOTS or typeof(row.equipment[slot]) != TYPE_INT or row.equipment[slot] not in CardData.CardSubType.values(): return false
		for sub in row.judgments:
			if typeof(sub) != TYPE_INT or sub not in CardData.CardSubType.values(): return false
		if row.own_cards.size() != (row.hand_count if row.controller == viewer else 0): return false
		var choices: Array = []
		for card in row.own_cards:
			if typeof(card) != TYPE_DICTIONARY or card.size() != 3 or not card.has_all(["zone", "index", "sub"]): return false
			if card.zone not in ["hand", "determined_cards"] or typeof(card.index) != TYPE_INT or card.index < 0: return false
			if typeof(card.sub) != TYPE_INT or (card.sub != -1 and card.sub not in CardData.CardSubType.values()): return false
			var key = str(card.zone) + ":" + str(card.index)
			if choices.has(key): return false
			choices.append(key)
	return true

static func valid_acting_unit(key: Variant, rows: Array) -> bool:
	if typeof(key) != TYPE_STRING: return false
	return key.is_empty() or rows.any(func(row): return row.id == key and row.kind == UnitRegistry.Kind.FIRE_DRAGON)
