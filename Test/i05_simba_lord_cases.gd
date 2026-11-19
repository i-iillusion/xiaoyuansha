extends RefCounted
const SIMBA = "辛巴·古德曼"

func run(t):
	pure(t)
	await succession(t)
	await discard_bridge(t)

func pure(t):
	var p = Player.new()
	p.general_name = SIMBA
	p.max_hp = 5
	p.hp = 5
	t.check(not p.simba_lord_skill_enabled and p.hand_limit() == 5, "I05d private capability defaults off even for a metadata Simba")
	p.simba_lord_skill_enabled = true
	for role in ["忠臣", "反贼", "内奸", "奸雄", ""]:
		p.identity = role
		t.check(p.hand_limit() == 5, "I05d non-lord and identity-free Simba receive no lord skill: " + role)
	p.identity = "主公"
	p.identity_max_hp_bonus = 1
	p.hp = 6
	t.check(p.hand_limit() == 8 and p.max_hp == 6, "I05d healthy 6/6 lord has limit eight, not another HP bonus")
	p.hp = 4
	t.check(p.hand_limit() == 6, "I05d wounded lord limit follows current HP")
	p.hand_limit_bonus = 3
	var armor = CardBase.create(CardData.CardSubType.SHENGGUANG_BAIYI)
	t.check(p.equip_card_to_slot("armor", armor), "I05d equip actual white armor")
	for i in 3:
		t.check(p.hand_limit() == 11 and p.hand_limit_bonus == 3 and p.hand_size() == 0, "I05d dynamic lord, white armor and Pofeng compose without accumulating or drawing")
	p.remove_equipment("armor")
	t.check(p.hand_limit() == 9, "I05d white armor loss removes only its own two")
	p.identity = "忠臣"
	t.check(p.hand_limit() == 7, "I05d current identity change removes lord skill without stale cache")
	p.identity = "主公"
	p.simba_lord_skill_enabled = false
	t.check(p.hand_limit() == 7, "I05d capability disable preserves independent bonuses")
	p.simba_lord_skill_enabled = true
	p.general_name = "稻草人"
	t.check(p.hand_limit() == 7, "I05d private capability alone grants no skill to another general")
	p.general_name = "布鲁斯·萨维奇"
	t.check(p.hand_limit() == 0, "I05d existing wounded Bruce limit remains zero")
	p.kneeling = true
	t.check(p.hand_limit() == 5, "I05d existing kneeling fixed limit remains five")
	p.general_name = SIMBA
	p.kneeling = false
	p.capture_game_start_state()
	p.general_name = "稻草人"
	p.restore_game_start_state()
	t.check(p.general_name == SIMBA and p.simba_lord_skill_enabled and p.hand_limit() == 11, "I05d Sage general restoration uses current lord identity and HP without caching bonus")
	p.mark_dead()
	t.check(p.hand_limit() == 9, "I05d final death removes lord-skill authority")
	p.free()
	t.check(GeneralData.GENERALS.has(SIMBA) and LanSession.GENERALS.count(SIMBA)==1 and LanSession.PROTOCOL == "campus-lan-18", "I05d public Simba source, LAN pool and protocol agree after opening")

func succession(t):
	var helper = load("res://Test/h03_identity_state_cases.gd").new()
	var players = helper.roster(6)
	var p: Player = players[5]
	p.general_name = SIMBA
	p.simba_lord_skill_enabled = true
	p.max_hp = 5
	p.hp = 2
	p.capture_game_start_state()
	var state = AmbitiousIdentityState.new()
	t.check(state.initialize(players) and p.hand_limit() == 2, "I05d ambitious Simba has no lord skill before declaration")
	helper.die(players[0])
	t.check(state.declare() and p.hp == 3 and p.max_hp == 6 and p.hand_limit() == 5, "I05d actual succession grants current authority alongside existing plus-one HP rule")
	t.check(not state.declare() and p.hand_limit() == 5, "I05d repeated declaration does not stack lord bonus")
	p.restore_game_start_state()
	t.check(p.hp == 6 and p.max_hp == 6 and p.hand_limit() == 8 and p.identity == "主公", "I05d Sage after succession keeps new identity and computes limit eight")
	helper.free_roster(players)

func begin_discard(game, seat, done):
	await game._do_discard(seat)
	done.value = true

func discard_bridge(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var helper = load("res://Test/h02_integration_cases.gd").new()
	for seat in [0, 1]:
		for concrete in [false, true]:
			var game = helper.fixture(t, 5, GameModes.CLASSIC)
			game.lan_enabled = true
			# Stop after this real DISCARD parent; do not start unrelated next turns.
			game.turn_manager.phase_changed.disconnect(game._on_phase_changed)
			game.turn_manager.current_player_idx = seat
			game.turn_manager.current_phase = TurnManager.Phase.DISCARD
			var p: Player = game.players[seat]
			p.general_name = SIMBA
			p.simba_lord_skill_enabled = true
			p.identity = "主公"
			p.hp = 4
			p.hand.clear()
			p.determined_cards.clear()
			for i in 7:
				if concrete: p.determined_cards.append(CardBase.create(CardData.CardSubType.DODGE))
				else: p.hand.append(null)
			var original = p.determined_cards[0] if concrete else null
			var bridge = LanGameBridge.new()
			t.root.add_child(bridge)
			bridge.game = game
			var done = {"value": false}
			begin_discard(game, seat, done)
			await t.process_frame
			var view = bridge.snapshot(seat)
			t.check(view.owner == seat and not done.value and p.hand_size() == 7 and p.hand_limit() == 6, "I05d host/remote discard waits for owner with lord-adjusted excess one")
			var choices = view.controls.filter(func(c): return c.text.begins_with("1 ·"))
			t.check(choices.size() == 1, "I05d real discard exposes first original hand resource")
			if choices.size() == 1:
				var token = choices[0].id
				t.check(not bridge.submit((seat + 1) % 5, token) and bridge.submit(seat, token), "I05d only host/remote owner can choose discarded card")
				view = bridge.snapshot(seat)
				var confirms = view.controls.filter(func(c): return c.text == "确认弃牌" and not c.disabled)
				t.check(confirms.size() == 1, "I05d one selected card suffices, not HP-only excess three")
				if confirms.size() == 1: t.check(bridge.submit(seat, confirms[0].id), "I05d actual discard confirmation accepted")
				for i in 3: await t.process_frame
				t.check(done.value and p.hand_size() == 6 and game.turn_manager.current_phase == TurnManager.Phase.END, "I05d discard parent removes exactly one and advances once")
				t.check(not bridge.submit(seat, token), "I05d old hand-choice token cannot discard twice")
				if concrete: t.check(game.deck._discard.count(original) == 1, "I05d concrete original enters discard once")
			bridge.game = null
			bridge.queue_free()
			await load("res://Test/i05_peter_peach_cases.gd").new().dispose(t, game)
	GameManager.selected_players = saved[0]
	GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]
	GameManager.random_general = saved[3]
	GameManager.random_identity = saved[4]
