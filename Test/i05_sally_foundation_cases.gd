extends RefCounted
const SALLY = "萨利·赛克斯"

func run(t):
	var p = Player.new()
	p.general_name = SALLY
	p.max_hp = GeneralData.get_max_hp(SALLY)
	p.gender = GeneralData.get_gender(SALLY)
	p.hp = p.max_hp
	t.check(p.hp == 3 and p.gender == "female", "I05e2a adopted Sally starts female at 3/3")
	t.check(not p.sally_jiegui_enabled and not p.has_jiegui() and not p.has_virtual_chixiong_effect(), "I05e2a metadata alone never enables a private skill")
	p.sally_jiegui_enabled = true
	t.check(p.has_jiegui() and p.has_virtual_chixiong_effect() and p.has_chixiong_effect(), "I05e2a private empty-slot Jiegui qualifies as an effect")
	t.check(p.get_weapon() == -1 and p.get_equipment_card("weapon") == null and p.equipment_cards.is_empty(), "I05e2a virtual qualification creates no physical weapon")
	var before = [p.attack_range, p.strike_limit(), p.hand_size(), p.equipment.duplicate()]
	for i in 3:
		t.check(p.has_virtual_chixiong_effect() and before == [p.attack_range, p.strike_limit(), p.hand_size(), p.equipment], "I05e2a repeated reads do not equip, draw or alter quotas/range")
	var other = Player.new()
	other.gender = "male"
	t.check(p.is_opposite_gender_to(other), "I05e2a female Sally sees a male as opposite gender")
	other.gender = "female"
	t.check(not p.is_opposite_gender_to(other), "I05e2a same gender is not opposite")
	other.gender = "none"
	t.check(not p.is_opposite_gender_to(other), "I05e2a genderless units are not opposite")
	p.gender = "male"
	t.check(p.has_virtual_chixiong_effect(), "I05e2a Jiegui itself is not restricted to female Sally")
	p.gender = "female"
	var sword = CardBase.create(CardData.CardSubType.LIANNU)
	t.check(p.equip_card_to_slot("weapon", sword), "I05e2a actual weapon occupies the real slot")
	t.check(not p.has_virtual_chixiong_effect() and not p.has_chixiong_effect() and p.get_equipment_card("weapon") == sword, "I05e2a real crossbow suppresses virtual sword without replacing its instance")
	t.check(p.remove_equipment("weapon") == sword and p.has_virtual_chixiong_effect(), "I05e2a removing the exact real weapon restores the empty-slot effect")
	var actual = CardBase.create(CardData.CardSubType.CHIXIONG_SHUANGGU)
	t.check(p.equip_card_to_slot("weapon", actual) and not p.has_virtual_chixiong_effect() and p.has_chixiong_effect(), "I05e2a real Chixiong is one real effect source, not real plus virtual")
	p.sally_jiegui_enabled = false
	t.check(p.has_chixiong_effect() and not p.has_jiegui(), "I05e2a disabled skill does not disable an actual equipped sword")
	t.check(p.remove_equipment("weapon") == actual and not p.has_chixiong_effect(), "I05e2a disabled private skill cannot restore a virtual effect")
	p.sally_jiegui_enabled = true
	var hidden = CardBase.create(CardData.CardSubType.HIDDEN_EQUIPMENT)
	hidden.hidden_category = "weapon"
	t.check(p.equip_hidden_card_to_slot("weapon", hidden) and not p.has_virtual_chixiong_effect(), "I05e2a hidden weapon is occupied, not an empty slot")
	t.check(p.remove_equipment("weapon") == hidden and p.has_virtual_chixiong_effect(), "I05e2a hidden original remains the actual removed resource")
	var armor = CardBase.create(CardData.CardSubType.SILVER_LION)
	t.check(p.equip_card_to_slot("armor", armor) and p.has_virtual_chixiong_effect(), "I05e2a armor does not occupy the weapon slot")
	p.hp = 2
	t.check(p.remove_equipment("armor") == armor and p.hp == 3, "I05e2a existing actual loss still heals the lion once; this is not the later voluntary-action UI")
	p.capture_game_start_state()
	p.gender = "male"
	p.general_name = "稻草人"
	p.hp = 1
	t.check(not p.has_jiegui() and not p.has_chixiong_effect(), "I05e2a stale capability does not grant Jiegui to a different general")
	p.restore_game_start_state()
	t.check(p.general_name == SALLY and p.gender == "female" and p.hp == 3 and p.has_virtual_chixiong_effect(), "I05e2a Sage restores general and gender while preserving server capability")
	t.check(not Player.GENERAL_STATE_FIELDS.has("sally_jiegui_enabled"), "I05e2a ability configuration is not a cached restored status")
	p.sally_jiegui_enabled = false
	p.restore_game_start_state()
	t.check(not p.has_virtual_chixiong_effect(), "I05e2a Sage cannot re-enable a disabled server capability")
	p.sally_jiegui_enabled = true
	p.unit_disappeared = true
	t.check(not p.has_jiegui() and not p.has_chixiong_effect(), "I05e2a disappeared bodies have no effective sword")
	p.unit_disappeared = false
	p.mark_dead()
	t.check(not p.has_jiegui() and not p.has_chixiong_effect(), "I05e2a final dead bodies have no effective sword")
	p.free(); other.free()
	t.check(GeneralData.get_implementation_status(SALLY) == "metadata_only" and not GeneralData.GENERALS.has(SALLY) and not LanSession.GENERALS.has(SALLY), "I05e2a private foundation never opens Sally")
	t.check(GeneralData.get_available_random_generals().size() == 14 and LanSession.PROTOCOL == "campus-lan-17", "I05e2a public pool and protocol remain unchanged")
	await borrowed_boundary(t)
	await public_observation(t)

func public_observation(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var fixture = load("res://Test/i05_sally_jiegui_cases.gd").new()
	for seat in [0,1]:
		var game = fixture.fixture(t,seat)
		var sally = game.players[seat]
		var viewer = game.players[(seat+1)%5]
		sally.identity = "反贼"
		sally.identity_revealed = false
		sally.sally_smoking_enabled = true
		sally.sally_surgery_enabled = true
		sally.determined_cards.append(CardBase.create(CardData.CardSubType.PEACH))
		var bridge = LanGameBridge.new()
		t.root.add_child(bridge)
		bridge.game = game
		var old_token = bridge.snapshot(seat).targets.get(str(seat),"")
		t.check(old_token != "" and bridge.snapshot(seat).players[seat].gender == "female", "I05e6a owner's opening gender and portrait are available")
		SallySmokingState.establish_after_rescue(sally)
		sally.sally_surgery_pending = true
		var remote = bridge.snapshot(viewer.seat_index)
		var row = remote.players[seat]
		var ai_row = game._ai_observation(viewer).players[seat]
		t.check(row.gender == "male" and row.sally == {"smoking":true,"boosted":false,"surgery_pending":true,"surgery_active":false} and ai_row.sally == row.sally and ai_row.gender == row.gender, "I05e6a remote and AI agree on public Sally state")
		t.check(row.identity == "" and not row.has("own_cards") and remote.own_cards.is_empty() and bridge.snapshot(seat).own_cards.size() == 1, "I05e6a public gender and skill state never expose identities or opponent hand")
		t.check(not bridge.submit(seat,old_token), "I05e6a a change to public gender and skill state refreshes the portrait token")
		var current_token = bridge.snapshot(seat).targets.get(str(seat),"")
		t.check(current_token != old_token and bridge.submit(seat,current_token), "I05e6a refreshed owner can open detail")
		await t.process_frame
		var labels = bridge.snapshot(seat).labels
		t.check(labels.any(func(label): return "男性" in label) and labels.has("抽烟状态") and labels.has("肺部手术待生效"), "I05e6a actual detail reports current gender and public status")
		sally.restore_game_start_state()
		var restored = bridge.snapshot(viewer.seat_index).players[seat]
		t.check(restored.gender == "female" and not restored.sally.smoking and not restored.sally.surgery_pending and not restored.sally.boosted, "I05e6a general restoration clears public smoking and surgery state")
		sally.mark_dead()
		t.check(not bridge.snapshot(viewer.seat_index).players[seat].has("sally"), "I05e6a final death removes active Sally observation")
		bridge.game = null
		bridge.queue_free()
		await fixture.dispose(t,game)
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]

func borrowed_boundary(t):
	var saved = [GameManager.selected_players, GameManager.selected_mode, GameManager.selected_general, GameManager.random_general, GameManager.random_identity]
	var game = load("res://Test/h02_integration_cases.gd").new().fixture(t, 5, GameModes.FREE_FOR_ALL)
	var sally: Player = game.players[1]
	sally.general_name = SALLY
	sally.sally_jiegui_enabled = true
	var user: Player = game.players[0]
	var before = game.deck._discard.size()
	t.check(sally.has_virtual_chixiong_effect() and not game.get_trick_targets(user, CardData.CardSubType.BORROWED_SWORD).has(sally), "I05e2a Q9 actual Borrowed Sword target query rejects a virtual-only weapon")
	var weapon = CardBase.create(CardData.CardSubType.LIANNU)
	t.check(sally.equip_card_to_slot("weapon", weapon), "I05e2a actual original weapon installed for positive control")
	t.check(game.get_trick_targets(user, CardData.CardSubType.BORROWED_SWORD).has(sally), "I05e2a Q9 positive control with real weapon remains a legal first target")
	t.check(sally.remove_equipment("weapon") == weapon and not game.get_trick_targets(user, CardData.CardSubType.BORROWED_SWORD).has(sally), "I05e2a losing the real weapon removes Borrowed qualification while restoring virtual effect")
	t.check(game.deck._discard.size() == before and sally.get_equipment_card("weapon") == null, "I05e2a qualification reads fabricate no transferable/discarded sword")
	game._game_over = true; game.queue_free()
	await t.process_frame
	GameManager.selected_players = saved[0]; GameManager.selected_mode = saved[1]
	GameManager.selected_general = saved[2]; GameManager.random_general = saved[3]; GameManager.random_identity = saved[4]
