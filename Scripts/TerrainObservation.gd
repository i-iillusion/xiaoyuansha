# Value-only spatial transport. Fixed players and terrain retain separate IDs;
# intelligent units never acquire a distance seat through this packet.
class_name TerrainObservation
extends RefCounted

static func valid(markers: Variant, space: Array, units: Array) -> bool:
	if typeof(markers) != TYPE_ARRAY or space.size()<2 or space.size()>10: return false
	var fixed: Array=[]
	for seat in space:
		if typeof(seat)!=TYPE_INT or seat<0 or seat>=space.size() or fixed.has(seat): return false
		fixed.append(seat)
	var mountains: Array=[]
	for unit in units:
		if typeof(unit)!=TYPE_DICTIONARY or not unit.has_all(["id","kind"]): return false
		if typeof(unit.id)!=TYPE_STRING or typeof(unit.kind)!=TYPE_INT: return false
		if unit.kind==UnitRegistry.Kind.MOUNTAIN:
			if mountains.has(unit.id): return false
			mountains.append(unit.id)
		elif unit.kind!=UnitRegistry.Kind.FIRE_DRAGON: return false
	if mountains.size()>2 or markers.size()!=space.size()+mountains.size(): return false
	var seen: Array=[]
	var ordered: Array=[]
	for marker in markers:
		if typeof(marker)==TYPE_INT:
			if not space.has(marker): return false
			ordered.append(marker)
		elif typeof(marker)==TYPE_STRING:
			if not mountains.has(marker): return false
		else: return false
		# Avoid cross-type int/string equality in the engine.
		var token=str(typeof(marker))+":"+str(marker)
		if seen.has(token): return false
		seen.append(token)
	return ordered==space

static func endpoint(key: Variant, units: Array) -> String:
	if typeof(key)==TYPE_INT: return "%d号" % (key+1)
	if typeof(key)!=TYPE_STRING: return ""
	var mountains=units.filter(func(unit): return unit.kind==UnitRegistry.Kind.MOUNTAIN)
	for i in mountains.size():
		if mountains[i].id==key: return "山甲" if i==0 else "山乙"
	return ""

static func describe(markers: Array, units: Array) -> String:
	var names: Array[String]=[]
	for marker in markers: names.append(endpoint(marker,units))
	return " → ".join(names)

static func location(id: String, markers: Array, units: Array) -> String:
	var index=markers.find(id)
	if index<0 or markers.size()<3: return ""
	return "%s / %s" % [endpoint(markers[posmod(index-1,markers.size())],units),endpoint(markers[(index+1)%markers.size()],units)]
