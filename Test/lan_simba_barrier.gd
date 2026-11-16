# Test transport only; never attached by production LanSession or gameplay.
extends Node

signal reported(peer: int, digest: String)
var released := false

@rpc("any_peer", "call_remote", "reliable")
func report(digest: String):
	if multiplayer.is_server(): reported.emit(multiplayer.get_remote_sender_id(), digest)

@rpc("authority", "call_remote", "reliable")
func release_clients():
	released = true
