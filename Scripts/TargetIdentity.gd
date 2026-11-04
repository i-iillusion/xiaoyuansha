# Target identity only. Rules still authorize card/mode, range and lifetime.
# Mountains can be targets, but never become ActorIdentity or input owners.
class_name TargetIdentity
extends RefCounted

static func key_for(roster: Array[Player], registry: UnitRegistry, body: Player) -> Variant:
	if not is_instance_valid(body): return null
	if roster.has(body): return body.seat_index
	var id = registry.id_for(body)
	return id if not registry.entry(id).is_empty() else null

static func resolve_live(roster: Array[Player], registry: UnitRegistry, key: Variant) -> Player:
	if typeof(key) == TYPE_INT: return ActorIdentity.resolve_live(roster, registry, key)
	if typeof(key) != TYPE_STRING: return null
	var entry = registry.entry(key)
	if entry.is_empty() or not registry.contains_active(entry.body): return null
	if not is_instance_valid(entry.summoner) or entry.summoner.is_dead(): return null
	if entry.kind == UnitRegistry.Kind.FIRE_DRAGON: return ActorIdentity.resolve_live(roster, registry, key)
	return entry.body if entry.kind == UnitRegistry.Kind.MOUNTAIN else null
