extends MultiMeshInstance3D

# The fields of the village's farm estates (sim.estates, filled by village_growth.gd): crop rows over
# every field tile, coloured for the estate's crop and its growing stage. Stages turn over on active
# play time, each estate a little out of step with the others. One multimesh, rebuilt only when the
# estates or a stage change.

const ROWS: int = 4
const STAGE_SECONDS: float = 30.0
# Stages: 0 freshly worked, 1 sprouting, 2 ripe, 3 harvested.
const HEIGHTS: Array[float] = [0.06, 0.18, 0.32, 0.08]
const PALETTES: Dictionary = {
	"farm": [Color("7a5a3c"), Color("7fb04e"), Color("e0b84e"), Color("8f7a48")],
	"pasture": [Color("5f8f42"), Color("6ea84a"), Color("7fbb52"), Color("93a85a")],
	"grove": [Color("587f3a"), Color("6a9a44"), Color("c7a2ad"), Color("4f8a3c")],
	"pond": [Color("5d7f48"), Color("6f9350"), Color("82a05a"), Color("98a06a")],
}
const GROUND: Dictionary = {"farm": Color("5b4430"), "pasture": Color("4f7d38"), "grove": Color("4a6f33"), "pond": Color("3e5a3a")}
const WATER := Color("2c5560")
const BARK := Color("5a4430")

var _signature: int = -1
var _blobs: MultiMeshInstance3D = null       # rounded shapes: orchard canopies, grass tufts, reeds
var _clock: float = 0.0


func _ready() -> void:
	name = "EstateFields"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.95
	box.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = box
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 7
	sphere.rings = 4
	sphere.material = material
	_blobs = MultiMeshInstance3D.new()
	_blobs.name = "EstateBlobs"
	_blobs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_blobs.multimesh = MultiMesh.new()
	_blobs.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_blobs.multimesh.use_colors = true
	_blobs.multimesh.mesh = sphere
	add_child(_blobs)


func stage_of(sim, house_id: int) -> int:
	return posmod(floori((float(sim.elapsed) + house_id * 13.0) / STAGE_SECONDS), HEIGHTS.size())


# Call every frame; does real work about once a second, and rebuilds only on a change.
func sync(sim, host, delta: float) -> void:
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = 1.0
	var parts: Array = []
	for id: int in sim.estates:
		var b: Dictionary = sim.get_building(id)
		if b.is_empty():
			continue
		parts.append([id, str(b["type"]), stage_of(sim, id), (sim.estates[id]["fields"] as Array).size(), sim.estates[id]["fields"].hash()])
	var signature: int = hash(parts)
	if signature == _signature:
		return
	_signature = signature
	_rebuild(sim, host)


func instance_total() -> int:
	return (multimesh.instance_count if multimesh != null else 0) + (_blobs.multimesh.instance_count if _blobs != null else 0)


func _rebuild(sim, host) -> void:
	var placed: Array = []
	var round: Array = []
	var tile_size: float = float(host.TILE)
	for id: int in sim.estates:
		var b: Dictionary = sim.get_building(id)
		if b.is_empty():
			continue
		var crop: String = str(b["type"])
		var palette: Array = PALETTES.get(crop, PALETTES["farm"])
		var stage: int = stage_of(sim, id)
		var colour: Color = palette[stage]
		for tile: Vector2i in sim.estates[id]["fields"]:
			var centre: Vector3 = host.world_position(Vector2(tile) + Vector2(0.5, 0.5))
			var ground: float = host._town_ground_y(centre.x, centre.z)
			var bed: Color = GROUND.get(crop, GROUND["farm"])
			placed.append(_box(Vector3(tile_size * 0.98, 0.04, tile_size * 0.98), Vector3(centre.x, ground + 0.02, centre.z), bed))
			var jitter: float = float((tile.x * 7 + tile.y * 13) % 5) * 0.04
			match crop:
				"farm":
					# Furrows of wheat across the tile.
					# Each furrow is a few clumps of uneven height, so a field reads as a crop, not planks.
					for row in ROWS:
						var z: float = centre.z + (float(row) - (ROWS - 1) * 0.5) * tile_size / ROWS
						for seg in 3:
							var wobble: int = (tile.x * 31 + tile.y * 17 + row * 7 + seg * 13) % 7
							var height: float = HEIGHTS[stage] * (0.75 + 0.08 * wobble + jitter)
							var shade: Color = colour.darkened(0.035 * float(wobble % 4)).lightened(0.03 * float(seg))
							var x: float = centre.x + (float(seg) - 1.0) * tile_size * 0.3
							placed.append(_box(Vector3(tile_size * 0.27, height, tile_size / ROWS * 0.5), Vector3(x, ground + 0.04 + height * 0.5, z + (float(wobble) - 3.0) * 0.012), shade))
				"pasture":
					# Grass tufts on open grazing.
					for k in 4:
						var off := Vector2(float((tile.x * 5 + k * 11) % 7) - 3.0, float((tile.y * 3 + k * 7) % 7) - 3.0) * tile_size * 0.11
						var height: float = HEIGHTS[stage] * 0.8 + 0.12
						round.append(_box(Vector3(0.42, height, 0.42), Vector3(centre.x + off.x, ground + 0.04 + height * 0.35, centre.z + off.y), colour.darkened(0.05 * k)))
				"grove":
					# Two fruit trees a tile; they blossom when ripe.
					for k in 2:
						var off := Vector2(-0.45 + 0.9 * k, 0.25 - 0.5 * k) * tile_size * 0.5
						var crown: float = 0.4 + HEIGHTS[stage] * 0.9
						var trunk: float = 0.25 + crown * 0.4
						placed.append(_box(Vector3(0.12, trunk, 0.12), Vector3(centre.x + off.x, ground + 0.04 + trunk * 0.5, centre.z + off.y), BARK))
						round.append(_box(Vector3(crown, crown * 0.85, crown), Vector3(centre.x + off.x, ground + 0.04 + trunk + crown * 0.3, centre.z + off.y), colour.darkened(0.06 * k)))
				"pond":
					# Shallow water with reeds along its edge.
					placed.append(_box(Vector3(tile_size * 0.8, 0.02, tile_size * 0.8), Vector3(centre.x, ground + 0.05, centre.z), WATER))
					for k in 3:
						var height: float = HEIGHTS[stage] * 1.4 + 0.25
						var x: float = centre.x + (float(k) - 1.0) * tile_size * 0.3
						round.append(_box(Vector3(0.14, height, 0.14), Vector3(x, ground + 0.05 + height * 0.5, centre.z - tile_size * 0.42), colour.darkened(0.05 * k)))
	multimesh.instance_count = placed.size()
	for i in placed.size():
		multimesh.set_instance_transform(i, placed[i][0])
		multimesh.set_instance_color(i, placed[i][1])
	_blobs.multimesh.instance_count = round.size()
	for i in round.size():
		_blobs.multimesh.set_instance_transform(i, round[i][0])
		_blobs.multimesh.set_instance_color(i, round[i][1])


func _box(size: Vector3, at: Vector3, colour: Color) -> Array:
	return [Transform3D(Basis.from_scale(size), at), colour]
