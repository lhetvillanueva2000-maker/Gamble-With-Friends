class_name Interactable
extends Area3D
## Reusable physical interaction target. Drop one under any prop, size its
## CollisionShape3D, and it becomes hover-highlightable and triggerable by
## an Interactor's raycast — the shop buy button, item pickup zones, the
## limo driver seat, and later every table game all share this class.
##
## Highlighting uses ONE shared ShaderMaterial (created lazily, applied as
## material_overlay to every MeshInstance3D under highlight_root), so a
## hundred interactables cost a single material and zero per-frame work.

signal focus_entered(interactor: Interactor)
signal focus_exited(interactor: Interactor)
signal interacted(interactor: Interactor)

const OUTLINE_SHADER := preload("res://shaders/interact_outline.gdshader")

static var _outline_material: ShaderMaterial = null

## Verb shown on the HUD prompt ("BUY BIN CONTENTS", "PICK UP CRATE"...).
@export var prompt_text := "INTERACT"
## InputMap action that triggers this target: &"interact" (LMB/tap) for
## panels and buttons, &"action_pickup" (E) for physical grabs.
@export var action: StringName = &"interact"
@export var enabled := true
## Meshes under this node receive the outline while focused.
## Defaults to the parent, i.e. the prop this zone is attached to.
@export var highlight_root: Node3D


func _ready() -> void:
	if highlight_root == null:
		highlight_root = get_parent() as Node3D


## Key label for the HUD prompt, honoring Phase 2 rebinds.
func action_key_label() -> String:
	if action == &"interact":
		return "LMB"
	var label := SettingsManager.get_action_key_label(action)
	return label if not label.is_empty() else String(action).to_upper()


## Called by the focusing Interactor when the bound action fires.
func interact(interactor: Interactor) -> void:
	if enabled:
		interacted.emit(interactor)


func set_focused(interactor: Interactor, focused: bool) -> void:
	_set_outline(focused and enabled)
	if focused:
		focus_entered.emit(interactor)
	else:
		focus_exited.emit(interactor)


func _set_outline(on: bool) -> void:
	if highlight_root == null:
		return
	var overlay: ShaderMaterial = _shared_outline_material() if on else null
	if highlight_root is MeshInstance3D:
		(highlight_root as MeshInstance3D).material_overlay = overlay
	for node: Node in highlight_root.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_overlay = overlay


static func _shared_outline_material() -> ShaderMaterial:
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
	return _outline_material
