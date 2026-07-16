class_name CasinoFloor
extends GameLevel
## Base script shared by all four casino floors. Each floor scene inherits
## casino_floor_base.tscn and overrides the exports below — the geometry
## kit and section layout stay identical, only stakes and dressing change.

## A player reached the exit elevator at the end of the floor.
signal exit_requested

const ENV_FLAT_SHADER := preload("res://shaders/env_flat.gdshader")
const NEON_TUBE_SHADER := preload("res://shaders/neon_tube.gdshader")
const NEON_HALO_SHADER := preload("res://shaders/neon_halo.gdshader")

@export_range(1, 4) var floor_number := 1
## Shared-bank target the crew must hit before the timer expires.
@export var quota_target := 5_000
## Cheapest seat at any table on this floor — the stakes ladder.
@export var min_bet := 5

@onready var _exit_trigger: Area3D = $Sections/Section04Exit/ExitTrigger


func _ready() -> void:
	_exit_trigger.body_entered.connect(_on_exit_body_entered)
	_apply_floor_palette()


## Everything visual on a floor derives from its GamePalette entry, applied
## at load: the Environment atmosphere, ONE shared architecture material,
## and neon dressing above each divider doorway. Sharing one ShaderMaterial
## across all architectural meshes means one shader/material state for the
## whole floor shell — each MeshInstance3D stays a single cheap draw call.
func _apply_floor_palette() -> void:
	var palette := GamePalette.floor_palette(floor_number)

	var env: Environment = ($WorldEnvironment as WorldEnvironment).environment
	env.background_color = palette.background
	env.ambient_light_color = palette.ambient

	var surface := ShaderMaterial.new()
	surface.shader = ENV_FLAT_SHADER
	surface.set_shader_parameter("base_color", palette.surface)
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = surface

	_decorate_neon(palette)


## One neon tube + one additive halo above each divider doorway: 6 draw
## calls per floor, zero Light3D nodes, zero WorldEnvironment glow. Meshes
## and materials are shared across all three dividers.
func _decorate_neon(palette: Dictionary) -> void:
	var tube_material := ShaderMaterial.new()
	tube_material.shader = NEON_TUBE_SHADER
	tube_material.set_shader_parameter("neon_color", palette.neon_primary)

	var halo_material := ShaderMaterial.new()
	halo_material.shader = NEON_HALO_SHADER
	halo_material.set_shader_parameter("halo_color", palette.neon_primary)

	var tube_mesh := BoxMesh.new()
	tube_mesh.size = Vector3(6.0, 0.15, 0.15)
	var halo_mesh := QuadMesh.new()
	halo_mesh.size = Vector2(7.5, 2.4)

	for divider: Node3D in $Occluders.get_children():
		var tube := MeshInstance3D.new()
		tube.mesh = tube_mesh
		tube.material_override = tube_material
		tube.position = Vector3(0.0, 2.8, 0.35)
		divider.add_child(tube)

		var halo := MeshInstance3D.new()
		halo.mesh = halo_mesh
		halo.material_override = halo_material
		halo.position = Vector3(0.0, 2.8, 0.5)
		divider.add_child(halo)


func _on_exit_body_entered(body: Node3D) -> void:
	if body.is_in_group(&"players"):
		exit_requested.emit()
