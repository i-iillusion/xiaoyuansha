extends RefCounted

# Explicit regression clock. Production never detects headless mode.
static func install(tree: SceneTree) -> void:
	tree.node_added.connect(func(node):
		if node is GameManager:
			node.ready.connect(func():
				node.ai_pacer.wait_override = func(_seconds): await tree.process_frame
			, CONNECT_ONE_SHOT))
