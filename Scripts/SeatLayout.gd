# Presentation geometry only. Never derives distance or turn order from pixels.
class_name SeatLayout
extends RefCounted

const PANEL_SIZE = Vector2(200, 100)
const MIN_PLAYERS = 2
const MAX_PLAYERS = 10

static func valid_count(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= MIN_PLAYERS and value <= MAX_PLAYERS

# Fixed IDs in an observer-relative visual order; dead seats are retained.
static func view_order(count: int, viewer: int = 0) -> Array[int]:
	var result: Array[int] = []
	if not valid_count(count) or viewer < 0 or viewer >= count: return result
	for offset in range(1, count): result.append((viewer + offset) % count)
	return result

static func rectangles(count: int, extent: Vector2, viewer: int = 0) -> Dictionary:
	var order = view_order(count, viewer)
	var result = {}
	if order.is_empty() or extent.x < 1200 or extent.y < 500: return result
	var centers: Array[Vector2] = []
	if count == 2:
		centers.append(Vector2(extent.x / 2, 62))
	else:
		var sides = 1 if count <= 6 else 2
		for index in sides:
			centers.append(Vector2(116, extent.y * (0.56 if sides == 1 else [0.78, 0.4][index])))
		var top_count = count - 1 - sides * 2
		for index in top_count:
			centers.append(Vector2(extent.x * (index + 1) / (top_count + 1), 62))
		for index in sides:
			centers.append(Vector2(extent.x - 116, extent.y * (0.56 if sides == 1 else [0.4, 0.78][index])))
	for index in order.size():
		result[order[index]] = Rect2(centers[index] - PANEL_SIZE / 2, PANEL_SIZE)
	return result

static func columns(count: int, width: float, minimum_width: float = 210, gap: float = 4) -> int:
	return mini(maxi(count, 1), maxi(1, int((width + gap) / (minimum_width + gap))))
