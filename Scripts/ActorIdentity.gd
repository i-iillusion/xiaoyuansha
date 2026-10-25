# Identity lookup only: neither turn scheduling nor card/target authorization.
# A unit ID is never an index into the permanent player roster. Identity may
# outlive an actor; resolve_live is required before using a retained handle.
class_name ActorIdentity
extends RefCounted

static func key_for(roster: Array[Player], registry: UnitRegistry, body: Player) -> Variant:
	if not is_instance_valid(body): return null
	if roster.has(body): return body.seat_index
	var id = registry.id_for(body)
	var entry = registry.entry(id)
	return id if not entry.is_empty() and entry.kind == UnitRegistry.Kind.FIRE_DRAGON else null

static func resolve_live(roster: Array[Player], registry: UnitRegistry, key: Variant) -> Player:
	if typeof(key) == TYPE_INT:
		for player in roster:
			if is_instance_valid(player) and player.seat_index == key and not player.is_dead(): return player
		return null
	if typeof(key) != TYPE_STRING: return null
	var entry = registry.entry(key)
	if entry.is_empty() or entry.kind != UnitRegistry.Kind.FIRE_DRAGON: return null
	if not registry.contains_active(entry.body) or registry.controller(key) == null: return null
	return entry.body

# Input ownership is not acting-body identity. Preserve the fixed-player query
# during final-death UI; rules still independently check phase/life/permission.
static func controller(roster: Array[Player], registry: UnitRegistry, body: Player) -> Player:
	if not is_instance_valid(body): return null
	if roster.has(body): return body
	return registry.controller(registry.id_for(body))

# Base seat-distance anchor only. Never inherit the owner's equipment modifiers.
static func position_body(roster: Array[Player], registry: UnitRegistry, body: Player) -> Player:
	var live = resolve_live(roster, registry, key_for(roster, registry, body))
	return controller(roster, registry, live) if live != null else null
