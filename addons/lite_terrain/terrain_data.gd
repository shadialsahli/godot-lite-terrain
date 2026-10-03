@tool
extends Resource

@export_storage var resolution: int = 65
@export var heights := PackedFloat32Array()
@export var weights := PackedColorArray()
@export_storage var foliage: Array[Dictionary] = []

func initialize() -> void:
	resource_local_to_scene = true
	if heights.size() != resolution * resolution:
		heights.resize(resolution * resolution)
		heights.fill(0.0)
	if weights.size() != heights.size():
		weights.resize(heights.size())
		weights.fill(Color(1, 0, 0, 0))

func snapshot() -> Dictionary:
	return {"resolution": resolution, "heights": heights.duplicate(), "weights": weights.duplicate(), "foliage": foliage.duplicate(true)}

func restore(state: Dictionary) -> void:
	resolution = int(state.get("resolution", roundi(sqrt(state.heights.size()))))
	heights = state.heights.duplicate()
	weights = state.weights.duplicate()
	foliage.assign(state.get("foliage", []).duplicate(true))
	emit_changed()
