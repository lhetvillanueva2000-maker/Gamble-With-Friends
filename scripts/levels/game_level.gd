class_name GameLevel
extends Node3D
## Base class for every streamable level (the lobby and all casino floors).
## A level owns its geometry, triggers, and spawn markers; Main asks it for
## spawn points after FloorStreamer swaps it in and moves players there.

const SPAWN_GROUP := &"player_spawn"


## Spawn markers belonging to THIS level only (the group is global, so a
## level filters to its own descendants).
func get_spawn_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for node: Node in get_tree().get_nodes_in_group(SPAWN_GROUP):
		var marker := node as Marker3D
		if marker != null and is_ancestor_of(marker):
			points.append(marker)
	return points
