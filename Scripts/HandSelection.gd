class_name HandSelection
extends RefCounted

var owner: Player
var hand: Array[CardBase]
var determined: Array[CardBase]
var cards: Array[CardBase]

func _init(p: Player):
	owner = p
	hand = p.hand.duplicate()
	determined = p.determined_cards.duplicate()
	cards = hand.duplicate()
	cards.append_array(determined)

func defaults(count: int) -> Array[int]:
	var indices: Array[int] = []
	for i in range(hand.size() - 1, -1, -1):
		indices.append(i)
	for i in range(cards.size() - 1, hand.size() - 1, -1):
		indices.append(i)
	indices.resize(mini(maxi(count, 0), indices.size()))
	return indices

func take(indices: Array[int], count: int) -> Array[CardBase]:
	var result: Array[CardBase] = []
	if count <= 0 or indices.size() != count or owner.hand != hand or owner.determined_cards != determined:
		return result
	var seen: Array[int] = []
	for i in indices:
		if i < 0 or i >= cards.size() or seen.has(i):
			return []
		seen.append(i)
		result.append(cards[i])
	# 全部校验后才按倒序删除索引，任意牌占位也有自己的索引。
	seen.sort()
	seen.reverse()
	for i in seen:
		if i < hand.size():
			owner.hand.remove_at(i)
		else:
			owner.determined_cards.remove_at(i - hand.size())
	return result
