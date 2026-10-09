class_name LanSession
extends Node

signal lobby_changed(state: Dictionary)
signal state_received(state: Dictionary)
signal notice(message: String)

const PROTOCOL := "campus-lan-2"
const DEFAULT_PORT := 24567
const GENERALS: Array[String] = ["凯文·罗本", "布鲁斯·萨维奇", "安普提·斯丢皮得", "史蒂芬·彼特先斯",
	"杰基·斯特朗", "麦克斯·欧尼斯特", "里奥·普利威尔", "比尔·盖伊"]
var members: Dictionary = {}
var count := 2
var bridge: LanGameBridge
var lobby: Dictionary = {}
var latest: Dictionary = {}
var match_id := ""
var connected := false
var nickname := "玩家"
var port_number := DEFAULT_PORT
var _tick := 0.0
var _connecting := 0.0
var _last_sent: Dictionary = {}

func _ready() -> void:
	# Clients only communicate with authority; do not relay peer-to-peer traffic.
	multiplayer.server_relay = false
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _lost("连接失败：检查IP、端口和私有网络防火墙。"))
	multiplayer.server_disconnected.connect(func(): _lost("房主已断开，本局中断；请重新加入房间。"))
	multiplayer.peer_disconnected.connect(_peer_left)

func host(player_name: String, size: int = 2, port: int = DEFAULT_PORT) -> Error:
	if size not in [2, 3, 5] or port < 1024 or port > 65535: return ERR_INVALID_PARAMETER
	close()
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, size - 1)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	connected = true
	count = size
	port_number = port
	nickname = _clean_name(player_name)
	members[1] = {"peer": 1, "name": nickname, "general": "随机", "ready": false}
	_publish_lobby()
	return OK

func join_room(address: String, player_name: String, port: int = DEFAULT_PORT) -> Error:
	if not address.is_valid_ip_address() or port < 1024 or port > 65535: return ERR_INVALID_PARAMETER
	close()
	nickname = _clean_name(player_name)
	var peer = ENetMultiplayerPeer.new()
	port_number = port
	var error = peer.create_client(address, port)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	_connecting = 10.0
	return OK

func _clean_name(value: String) -> String:
	return value.strip_edges().replace("\n", " ").replace("\r", " ").left(24) if not value.strip_edges().is_empty() else "玩家"

func _connected() -> void:
	connected = true
	_connecting = 0.0
	_register.rpc_id(1, PROTOCOL, nickname)

@rpc("any_peer", "call_remote", "reliable")
func _register(protocol: String, player_name: String) -> void:
	if not multiplayer.is_server(): return
	var peer = multiplayer.get_remote_sender_id()
	if peer <= 1 or not _peer_ready(peer): return
	if members.has(peer): return
	if protocol != PROTOCOL or bridge != null or members.size() >= count:
		_remote_notice.rpc_id(peer, "版本不一致、房间已满或对局已开始；请退出并使用同一个试玩包重新加入。")
		return
	members[peer] = {"peer": peer, "name": _clean_name(player_name), "general": "随机", "ready": false}
	_publish_lobby()

func choose(general: String, ready: bool) -> void:
	if not connected: return
	if multiplayer.is_server(): _apply_choice(1, general, ready)
	else: _choose.rpc_id(1, general, ready)

@rpc("any_peer", "call_remote", "reliable")
func _choose(general: String, ready: bool) -> void:
	if multiplayer.is_server(): _apply_choice(multiplayer.get_remote_sender_id(), general, ready)

func _apply_choice(peer: int, general: String, ready: bool) -> void:
	if bridge != null or not members.has(peer): return
	if general not in GENERALS and general not in ["随机", "稻草人"]: return
	members[peer].general = general
	members[peer].ready = ready
	_publish_lobby()

func begin_match() -> bool:
	if not connected or not multiplayer.is_server() or bridge != null or members.size() != count: return false
	var used: Array[String] = []
	for entry in members.values():
		if not entry.ready: return false
		if entry.general in ["随机", "稻草人"]: continue
		if used.has(entry.general):
			notice.emit("武将不能重复，请修改选将后重新准备。")
			return false
		used.append(entry.general)
	var pool: Array[String] = []
	for general in GENERALS:
		if not used.has(general): pool.append(general)
	pool.shuffle()
	var roster: Array[Dictionary] = []
	for peer in members:
		var entry: Dictionary = members[peer]
		entry["seat"] = roster.size()
		roster.append({"name": entry.name, "general": pool.pop_back() if entry.general == "随机" else entry.general})
	match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	bridge = LanGameBridge.new()
	add_child(bridge)
	bridge.start(roster, GameManager.MODE_CLASSIC_IDENTITY if count == 5 else GameManager.MODE_FREE_FOR_ALL)
	_last_sent.clear()
	_publish_lobby()
	_publish_states()
	return true

func act(token: String) -> void:
	if not connected or token.length() > 80: return
	if multiplayer.is_server(): _apply_action(1, match_id, token)
	else: _action.rpc_id(1, str(latest.get("match", "")), token)

@rpc("any_peer", "call_remote", "reliable")
func _action(match_key: String, token: String) -> void:
	if multiplayer.is_server(): _apply_action(multiplayer.get_remote_sender_id(), match_key, token)

func _apply_action(peer: int, match_key: String, token: String) -> bool:
	if bridge == null or match_key != match_id or not members.has(peer) or token.length() > 80: return false
	var accepted = bridge.submit(int(members[peer].seat), token)
	_last_sent.erase(peer)
	_tick = 0.12 # Publish on next frame, after queued windows have been removed.
	return accepted

func return_to_lobby() -> void:
	if not connected or not multiplayer.is_server() or bridge == null or not bridge.game._game_over: return
	bridge.abort()
	bridge = null
	match_id = ""
	for entry in members.values(): entry.ready = false
	latest.clear()
	_publish_lobby()

func _publish_lobby() -> void:
	var state = {"count": count, "members": members.values().duplicate(true), "playing": bridge != null, "protocol": PROTOCOL}
	_receive_lobby(state)
	for peer in members:
		if peer != 1 and _peer_ready(peer): _receive_lobby.rpc_id(peer, state)

func _peer_ready(peer: int) -> bool:
	if not connected or not multiplayer.get_peers().has(peer): return false
	var transport = multiplayer.multiplayer_peer
	if not transport is ENetMultiplayerPeer: return false
	var packet_peer = transport.get_peer(peer)
	return packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED

@rpc("authority", "call_remote", "reliable")
func _receive_lobby(state: Dictionary) -> void:
	lobby = state
	if not state.playing: latest.clear()
	lobby_changed.emit(state)

func _publish_states() -> void:
	if bridge == null: return
	for peer in members:
		if peer != 1 and not _peer_ready(peer): continue
		var state = bridge.snapshot(int(members[peer].seat))
		state["match"] = match_id
		var fingerprint = var_to_str(state)
		if _last_sent.get(peer, "") == fingerprint: continue
		_last_sent[peer] = fingerprint
		if peer == 1: _receive_state(state)
		else: _receive_state.rpc_id(peer, state)

@rpc("authority", "call_remote", "reliable")
func _receive_state(state: Dictionary) -> void:
	latest = state
	state_received.emit(state)

@rpc("authority", "call_remote", "reliable")
func _remote_notice(message: String) -> void:
	notice.emit(message)

func _peer_left(peer: int) -> void:
	if not multiplayer.is_server() or not members.has(peer): return
	members.erase(peer)
	if bridge != null:
		bridge.abort()
		bridge = null
		match_id = ""
		for entry in members.values(): entry.ready = false
		var message = "有玩家断开，本局中断（不判胜负）。请补齐人数后重新准备。"
		notice.emit(message)
		for id in members:
			if id != 1 and _peer_ready(id): _remote_notice.rpc_id(id, message)
	_publish_lobby()

func _lost(message: String) -> void:
	close()
	notice.emit(message)
	lobby_changed.emit({})

func close() -> void:
	connected = false
	_connecting = 0.0
	if bridge != null:
		bridge.abort()
		bridge = null
	if multiplayer.multiplayer_peer != null: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	members.clear()
	lobby.clear()
	latest.clear()
	_last_sent.clear()
	match_id = ""

func _exit_tree() -> void:
	close()

func _process(delta: float) -> void:
	if _connecting > 0:
		_connecting -= delta
		if _connecting <= 0: _lost("连接超时。请确认同一局域网、房主IP及UDP端口。")
	if not connected or not multiplayer.is_server(): return
	_tick += delta
	if _tick >= 0.12:
		_tick = 0.0
		_publish_states()
