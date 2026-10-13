# Rule definitions are separate from release gates. A catalog entry does not
# authorize a menu/room to launch an unimplemented mode.
class_name GameModes
extends RefCounted

const CLASSIC = "classic_identity"
const AMBITIOUS = "ambitious_identity"
const FREE_FOR_ALL = "free_for_all"
const ROLE_ORDER = ["主公", "忠臣", "反贼", "内奸", "奸雄"]
# Classic 7/9 remain unregistered pending H02-Q1; never infer them by
# subtracting the ambitious role from the manual's table.
const IDENTITY_COUNTS = {
	CLASSIC: {5: [1, 1, 2, 1, 0]},
	AMBITIOUS: {6: [1, 1, 2, 1, 1], 8: [1, 2, 3, 1, 1], 10: [1, 3, 4, 1, 1]},
}
const OPEN = {CLASSIC: [5], FREE_FOR_ALL: [2, 3]}

static func defined(mode: Variant, count: Variant) -> bool:
	if typeof(mode) != TYPE_STRING or not SeatLayout.valid_count(count): return false
	return mode == FREE_FOR_ALL or (IDENTITY_COUNTS.has(mode) and IDENTITY_COUNTS[mode].has(count))

static func playable(mode: Variant, count: Variant) -> bool:
	return defined(mode, count) and OPEN.has(mode) and count in OPEN[mode]

static func roles(mode: Variant, count: Variant) -> Array[String]:
	var result: Array[String] = []
	if not defined(mode, count): return result
	if mode == FREE_FOR_ALL:
		result.resize(count)
		result.fill("")
	else:
		var amounts: Array = IDENTITY_COUNTS[mode][count]
		for i in ROLE_ORDER.size():
			for unused in amounts[i]: result.append(ROLE_ORDER[i])
	return result

# Pure validation of the opening deck only; future identity swaps are not
# checked against an opening distribution and belong to H03.
static func valid_opening(mode: Variant, count: Variant, identities: Array) -> bool:
	if not defined(mode, count) or identities.size() != count: return false
	var expected = roles(mode, count)
	for role in identities:
		if typeof(role) != TYPE_STRING or role not in expected: return false
	for role in expected:
		if identities.count(role) != expected.count(role): return false
	return true

static func catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mode in [CLASSIC, AMBITIOUS, FREE_FOR_ALL]:
		for count in range(2, 11):
			if defined(mode, count):
				result.append({"mode": mode, "count": count, "roles": roles(mode, count),
					"playable": playable(mode, count),
					"identity_related": mode != FREE_FOR_ALL})
	return result
