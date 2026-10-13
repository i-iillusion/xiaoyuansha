extends RefCounted

func run(t):
	var manual = {
		5: ["主公", "忠臣", "反贼", "反贼", "内奸"],
		6: ["主公", "忠臣", "反贼", "反贼", "内奸", "奸雄"],
		8: ["主公", "忠臣", "忠臣", "反贼", "反贼", "反贼", "内奸", "奸雄"],
		10: ["主公", "忠臣", "忠臣", "忠臣", "反贼", "反贼", "反贼", "反贼", "内奸", "奸雄"],
	}
	for count in manual:
		var mode = GameModes.CLASSIC if count == 5 else GameModes.AMBITIOUS
		var roles = GameModes.roles(mode, count)
		t.check(roles == manual[count] and roles.size() == count and roles.count("主公") == 1, "H02a known opening matches source, unique lord")
		t.check(GameModes.valid_opening(mode, count, roles), "H02a source distribution validates")
		roles.reverse()
		t.check(GameModes.valid_opening(mode, count, roles), "H02a shuffled deck has same distribution")
		roles[0] = "主公"
		t.check(not GameModes.valid_opening(mode, count, roles), "H02a duplicate lord rejected")
		t.check(GameModes.roles(mode, count) == manual[count], "H02a returned deck mutation cannot damage definition")
	for count in range(2, 11):
		var roles = GameModes.roles(GameModes.FREE_FOR_ALL, count)
		t.check(roles.size() == count and roles.all(func(role): return role == "") and GameModes.valid_opening(GameModes.FREE_FOR_ALL, count, roles), "H02a FFA has exactly N identity-free players")
		roles[0] = "主公"
		t.check(not GameModes.valid_opening(GameModes.FREE_FOR_ALL, count, roles), "H02a FFA cannot invent role or identity bonus")
	for count in [6, 8, 10]:
		t.check(GameModes.defined(GameModes.AMBITIOUS, count) and not GameModes.playable(GameModes.AMBITIOUS, count), "H02a ambitious rules known but H03/release gate remains closed")
	for count in [7, 9]:
		t.check(GameModes.defined(GameModes.CLASSIC, count) and GameModes.roles(GameModes.CLASSIC, count).count("忠臣") == (count - 3) / 2 and GameModes.roles(GameModes.CLASSIC, count).count("反贼") == (count - 1) / 2, "H02-Q1 confirmed classic distribution")
	for count in range(4, 11):
		t.check(GameModes.defined(GameModes.FREE_FOR_ALL, count) and GameModes.playable(GameModes.FREE_FOR_ALL, count), "H02 integrated FFA configuration supported")
	for value in [0, 1, 11, 5.0, "5", null, true]:
		t.check(not GameModes.defined(GameModes.FREE_FOR_ALL, value) and not GameModes.playable(GameModes.CLASSIC, value), "H02a bad count is not coerced")
	for value in ["", "boss", 0, null]:
		t.check(not GameModes.defined(value, 5), "H02a unknown mode cannot default to identity-free game")
	t.check(GameModes.playable(GameModes.CLASSIC, 5) and GameModes.playable(GameModes.FREE_FOR_ALL, 2) and GameModes.playable(GameModes.FREE_FOR_ALL, 3), "H02a existing release gates retained")
	var catalog = GameModes.catalog()
	t.check(catalog.size() == 15 and catalog.filter(func(row): return row.playable).size() == 12, "H02 definition and release state counted independently")
	catalog[0].roles.clear()
	catalog[0].count = 99
	t.check(GameModes.catalog()[0].count == 5 and GameModes.catalog()[0].roles.size() == 5, "H02a catalog snapshots are isolated")
	t.check(not GameModes.valid_opening(GameModes.CLASSIC, 5, ["主公", "忠臣", "反贼", "内奸"]), "H02a missing player rejected")
	t.check(not GameModes.valid_opening(GameModes.CLASSIC, 5, ["主公", "忠臣", "反贼", "反贼", null]), "H02a missing/unknown role rejected")
	t.check(not GameModes.valid_opening(GameModes.AMBITIOUS, 6, ["主公", "忠臣", "反贼", "反贼", "内奸", "内奸"]), "H02a ambitious deck requires its actual role, not second renegade")
