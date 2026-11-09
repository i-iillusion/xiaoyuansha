extends RefCounted
const H03 = preload("res://Test/h03_identity_state_cases.gd")

func run(t):
	role_values(t)
	await observations_and_restore(t)
	succession(t)

func role_values(t):
	for left in ["忠臣","反贼","内奸","奸雄"]:
		for right in ["忠臣","反贼","内奸","奸雄"]:
			var a = Player.new()
			var b = Player.new()
			a.identity=left; b.identity=right
			a.hp=2; b.hp=3
			a.hand.append(null)
			var original=CardBase.create(CardData.CardSubType.LIANNU)
			b.determined_cards.append(original)
			t.check(a.exchange_non_lord_identity(b) and a.identity==right and b.identity==left,"I05c role primitive permits distinct holders including same-role pair")
			t.check(a.hp==2 and b.hp==3 and a.max_hp==4 and b.max_hp==4 and a.hand_size()==1 and b.determined_cards==[original],"I05c non-lord identity swap never swaps bodies, hp or resources")
			t.check(not a.spy_used and not b.spy_used,"I05c pure role primitive does not invent skill-use commitment")
			a.free(); b.free()
	for fault in ["lord_left","lord_right","self","null","dead","dying","empty","unknown"]:
		var a=Player.new()
		var b=Player.new()
		a.identity="忠臣"; b.identity="反贼"
		a.hp=4; b.hp=4
		if fault=="lord_left": a.identity="主公"; a.identity_max_hp_bonus=1; a.hp=5
		if fault=="lord_right": b.identity="主公"; b.identity_max_hp_bonus=1; b.hp=5
		if fault=="dead": b.mark_dead()
		if fault=="dying": b.hp=0
		if fault=="empty": b.identity=""
		if fault=="unknown": b.identity="unknown"
		var before=[a.identity,b.identity,a.hp,b.hp,a.max_hp,b.max_hp]
		var target=b if fault not in ["self","null"] else (a if fault=="self" else null)
		t.check(not a.exchange_non_lord_identity(target) and before==[a.identity,b.identity,a.hp,b.hp,a.max_hp,b.max_hp],"I05c invalid/dead/lord pair is rejected atomically: "+fault)
		a.free(); b.free()

func observations_and_restore(t):
	var players: Array[Player]=[]
	for i in 3:
		var p=Player.new()
		p.identity=["主公","忠臣","内奸"][i]
		p.identity_revealed=i==0
		p.seat_index=i
		p.hp=4
		players.append(p)
	var a=players[1]
	var b=players[2]
	a.general_name="桑尼·斯派"
	a.capture_game_start_state()
	a.spy_used=true # explicit limited-use state, not a claim that skill UI exists
	t.check(a.exchange_non_lord_identity(b),"I05c hidden non-lords can exchange their own actual identity values")
	for viewer in players:
		var view=PlayerObservation.capture(players,viewer,TurnManager.Phase.PLAY,0)
		for row in view.players:
			var subject=players[row.seat]
			t.check(row.identity==(subject.identity if subject==viewer or subject.identity_revealed else ""),"I05c new role is visible to its owner, not third-party observers")
	a.restore_game_start_state()
	t.check(not a.spy_used and a.identity=="内奸" and b.identity=="忠臣" and not a.identity_revealed,"I05c Sage restores spy use without reverting the exchanged hidden identity")
	t.check(players[0].identity=="主公" and players[0].identity_revealed and players[0].has_lord_skill_authority(),"I05c exchange leaves public lord and lord-skill authority untouched")
	for p in players: p.free()

func succession(t):
	for count in [6,8,10]:
		var players=H03.new().roster(count)
		var state=AmbitiousIdentityState.new()
		t.check(state.initialize(players),"I05c initialize trusted ambitious roster before role exchanges")
		var former: Player=players.back()
		var recipient: Player=players[1]
		var lord: Player=players[0]
		t.check(state.exchange_non_lord_identities(former,recipient) and state.valid() and recipient.identity=="奸雄" and former.identity=="忠臣","I05c moving ambitious identity synchronizes cached role holder without reopening the match")
		t.check(state.declaration==AmbitiousIdentityState.Declaration.UNRESOLVED and state.candidate()==null and state.evaluate().is_empty(),"I05c swap itself is not a declaration or a premature victory")
		t.check(not state.exchange_non_lord_identities(lord,recipient) and state.valid() and lord.identity=="主公","I05c ambitious state's transaction independently rejects the current lord")
		var foreign=Player.new()
		foreign.identity="反贼"; foreign.hp=4
		t.check(not state.exchange_non_lord_identities(former,foreign) and state.valid(),"I05c foreign player cannot enter a trusted identity state")
		foreign.free()
		H03.new().die(lord)
		t.check(state.candidate()==recipient and state.evaluate().is_empty(),"I05c new holder, not original general, receives existing ambitious declaration opportunity")
		t.check(state.declare() and state.valid() and recipient.identity=="主公" and recipient.hp==5 and former.identity=="内奸","I05c normal succession after swap applies existing loyalist conversion and H03 recovery")
		var other: Player=players[2]
		var other_role=other.identity
		var former_role=former.identity
		t.check(state.exchange_non_lord_identities(former,other) and former.identity==other_role and other.identity==former_role and state.valid(),"I05c non-lord exchange after succession preserves transformed cached roster")
		t.check(state.declaration==AmbitiousIdentityState.Declaration.ACCEPTED and state.candidate()==null and recipient.identity=="主公" and recipient.identity_max_hp_bonus==1,"I05c later exchanges do not reset accepted declaration or current lord bonus")
		for p in players:
			if p.identity in ["反贼","内奸"] and not p.is_dead(): H03.new().die(p)
		t.check(state.evaluate().get("winner")=="主公","I05c transformed lord victory still resolves after authorized role exchanges")
		H03.new().free_roster(players)
	var players=H03.new().roster(6)
	var state=AmbitiousIdentityState.new()
	state.initialize(players)
	players[2].identity="忠臣"
	t.check(not state.valid() and not state.exchange_non_lord_identities(players[1],players[3]) and players[1].identity=="忠臣" and players[3].identity=="反贼","I05c authorized swap cannot launder an already-corrupted role cache")
	H03.new().free_roster(players)
