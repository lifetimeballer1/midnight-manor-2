extends MultiMeshInstance3D

# The fields of the village's farm estates (sim.estates, filled by village_growth.gd): crop rows over
# every field tile, coloured for the estate's crop and its growing stage. Stages turn over on active
# play time, each estate a little out of step with the others. One multimesh, rebuilt only when the
# estates or a stage change.

const ROWS: int = 5
const STAGE_SECONDS: float = 30.0
# Stages: 0 freshly worked, 1 sprouting, 2 ripe, 3 harvested.
const HEIGHTS: Array[float] = [0.06, 0.18, 0.32, 0.08]
const PALETTES: Dictionary = {
	"farm": [Color("7a5a3c"), Color("6f9e45"), Color("c4973a"), Color("7f6a3a")],
	"pasture": [Color("557f3c"), Color("5f9142"), Color("6a9c48"), Color("7d9150")],
	"grove": [Color("587f3a"), Color("6a9a44"), Color("c7a2ad"), Color("4f8a3c")],
	"pond": [Color("5d7f48"), Color("6f9350"), Color("82a05a"), Color("98a06a")],
}
const GROUND: Dictionary = {"farm": Color("5b4430"), "pasture": Color("44692f"), "grove": Color("4a6f33"), "pond": Color("3e5a3a")}
const WATER := Color("2b4b4f")
const BARK := Color("5a4430")
const FURROW := Color("4a3626")
const HAY := Color("c9a24a")
const WOOL := Color("e8e2d2")
const HEDGE := Color("355a2c")
const FENCE := Color("8a6a46")
const MUD := Color("4a3a28")
const RUBBLE := Color("6f6c66")
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

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
	parts.append(sim.aftermath.trampled.size())
	parts.append(sim.aftermath.rubble.hash())
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
		var field: Dictionary = {}
		for tile: Vector2i in sim.estates[id]["fields"]:
			field[tile] = true
		var house := Rect2i(int(b["x"]), int(b["y"]), int(b["size"]), int(b["size"]))
		for tile: Vector2i in field:
			var centre: Vector3 = host.world_position(Vector2(tile) + Vector2(0.5, 0.5))
			var ground: float = host._town_ground_y(centre.x, centre.z)
			var wave: float = _wave(centre.x, centre.z)
			var bed: Color = (GROUND.get(crop, GROUND["farm"]) as Color).darkened(0.06 * wave)
			placed.append(_box(Vector3(tile_size, 0.04, tile_size), Vector3(centre.x, ground + 0.02, centre.z), bed))
			var mark: int = posmod(tile.x * 7 + tile.y * 13, 11)
			if sim.aftermath.trampled.has(tile):
				# Trodden flat by raiders: churned earth and broken stalks until a farmhand replants it.
				placed.append(_box(Vector3(tile_size * 0.94, 0.045, tile_size * 0.94), Vector3(centre.x, ground + 0.025, centre.z), MUD.darkened(0.05 * wave)))
				for k in 3:
					var turn: float = float(mark + k * 3) * 0.7
					var stalk := Transform3D(Basis(Vector3.UP, turn).scaled(Vector3(tile_size * 0.5, 0.03, 0.12)), Vector3(centre.x + (float(k) - 1.0) * 0.5, ground + 0.06, centre.z + float((mark + k) % 3 - 1) * 0.45))
					placed.append([stalk, palette[3]])
				continue
			match crop:
				"farm":
					# Long furrows: rows run on from tile to tile, swelling and dipping like a real field.
					for row in ROWS:
						var z: float = centre.z + (float(row) - (ROWS - 1) * 0.5) * tile_size / ROWS
						if stage == 0:
							placed.append(_box(Vector3(tile_size, 0.05, tile_size / ROWS * 0.45), Vector3(centre.x, ground + 0.045, z), FURROW.darkened(0.05 * float(row % 2))))
							continue
						var height: float = HEIGHTS[stage] * (0.65 + 0.6 * _wave(centre.x * 1.7, z * 1.3))
						var shade: Color = colour.darkened(0.08).lerp(colour.lightened(0.08), _wave(centre.x * 0.6 + 3.0, z * 0.9))
						placed.append(_box(Vector3(tile_size, height, tile_size / ROWS * 0.5), Vector3(centre.x, ground + 0.04 + height * 0.5, z), shade))
					if stage == 3 and mark == 0:
						round.append(_box(Vector3(0.95, 0.75, 0.95), Vector3(centre.x, ground + 0.36, centre.z), HAY))
						round.append(_box(Vector3(0.7, 0.4, 0.7), Vector3(centre.x, ground + 0.7, centre.z), HAY.lightened(0.08)))
				"pasture":
					# Tufts on open grazing, and the flock.
					for k in 3:
						var off := Vector2(float(posmod(tile.x * 5 + k * 11, 7)) - 3.0, float(posmod(tile.y * 3 + k * 7, 7)) - 3.0) * tile_size * 0.11
						var height: float = HEIGHTS[stage] * 0.6 + 0.1
						round.append(_box(Vector3(0.36, height, 0.36), Vector3(centre.x + off.x, ground + 0.04 + height * 0.35, centre.z + off.y), colour.darkened(0.05 * k)))
					if mark % 4 == 1:
						var turn: float = float(mark) * 0.9
						var facing := Vector3(cos(turn), 0.0, sin(turn))
						var at := Vector3(centre.x, ground + 0.42, centre.z) + Vector3(facing.z, 0, -facing.x) * 0.3
						round.append(_box(Vector3(0.62, 0.48, 0.62) + facing.abs() * 0.3, at, WOOL.darkened(0.04 * float(mark % 3))))
						round.append(_box(Vector3(0.26, 0.26, 0.26), at + facing * 0.5 + Vector3(0, 0.06, 0), Color("2f2a28")))
						for leg: Vector3 in [facing * 0.22, -facing * 0.22]:
							placed.append(_box(Vector3(0.08, 0.26, 0.08), at + leg + Vector3(0, -0.28, 0), Color("2f2a28")))
				"grove":
					# Fruit trees in rows; they blossom when ripe, and windfalls lie under them after picking.
					for k in 2:
						var off := Vector2(-0.45 + 0.9 * k, 0.25 - 0.5 * k) * tile_size * 0.5
						var crown: float = 0.55 + HEIGHTS[stage] * 0.9
						var trunk: float = 0.3 + crown * 0.4
						placed.append(_box(Vector3(0.14, trunk, 0.14), Vector3(centre.x + off.x, ground + 0.04 + trunk * 0.5, centre.z + off.y), BARK))
						var leaf: Color = (palette[1] as Color).darkened(0.08 * k + 0.06 * wave)
						round.append(_box(Vector3(crown, crown * 0.85, crown), Vector3(centre.x + off.x, ground + 0.04 + trunk + crown * 0.3, centre.z + off.y), leaf))
						if stage == 2:
							for petal in 3:
								var p := Vector3(cos(petal * 2.1 + k), 0.0, sin(petal * 2.1 + k)) * crown * 0.38
								round.append(_box(Vector3.ONE * crown * 0.32, Vector3(centre.x + off.x, ground + 0.04 + trunk + crown * 0.55, centre.z + off.y) + p, colour.lightened(0.05 * petal)))
				"pond":
					# One sheet of water across the estate; reeds and lily pads only near the banks.
					placed.append(_box(Vector3(tile_size, 0.02, tile_size), Vector3(centre.x, ground + 0.05, centre.z), WATER.lightened(0.05 * wave)))
					if mark % 5 == 2:
						round.append(_box(Vector3(0.45, 0.03, 0.45), Vector3(centre.x + 0.3, ground + 0.07, centre.z - 0.2), Color("4f7a3a")))
					for step: Vector2i in SIDES:
						if field.has(tile + step) or house.has_point(tile + step):
							continue
						var edge := Vector3(float(step.x), 0.0, float(step.y)) * tile_size * 0.4
						var along := Vector3(float(step.y), 0.0, float(step.x)) * tile_size * 0.3
						for k in 3:
							var height: float = HEIGHTS[stage] * 1.4 + 0.3 + 0.1 * float((mark + k) % 3)
							round.append(_box(Vector3(0.14, height, 0.14), Vector3(centre.x, ground + 0.05 + height * 0.5, centre.z) + edge + along * (float(k) - 1.0), palette[stage].darkened(0.05 * k)))
			# Hedges round wheat and orchards, rail fences round pasture, along the estate's outer edge.
			if crop == "pond":
				continue
			for step: Vector2i in SIDES:
				if field.has(tile + step) or house.has_point(tile + step):
					continue
				var edge := Vector3(float(step.x), 0.0, float(step.y)) * tile_size * 0.47
				var flat: bool = step.x == 0      # the edge runs along x
				if crop == "pasture":
					var rail := Vector3(tile_size, 0.07, 0.07) if flat else Vector3(0.07, 0.07, tile_size)
					placed.append(_box(rail, Vector3(centre.x, ground + 0.44, centre.z) + edge, FENCE))
					placed.append(_box(rail, Vector3(centre.x, ground + 0.24, centre.z) + edge, FENCE.darkened(0.12)))
					var corner := Vector3(tile_size * 0.5, 0.0, 0.0) if flat else Vector3(0.0, 0.0, tile_size * 0.5)
					placed.append(_box(Vector3(0.12, 0.6, 0.12), Vector3(centre.x, ground + 0.3, centre.z) + edge - corner, FENCE.darkened(0.25)))
				else:
					var hedge := Vector3(tile_size * 1.08, 0.44 + 0.1 * wave, 0.4) if flat else Vector3(0.4, 0.44 + 0.1 * wave, tile_size * 1.08)
					round.append(_box(hedge, Vector3(centre.x, ground + 0.22, centre.z) + edge, HEDGE.darkened(0.1 * wave)))
	# Rubble where stone buildings fell, waiting for builders to carry it off.
	for pile: Dictionary in sim.aftermath.rubble:
		var at: Vector3 = host.world_position(Vector2(float(pile["x"]), float(pile["y"])))
		var ground: float = host._town_ground_y(at.x, at.z)
		var stones: int = clampi(int(pile["stone"]) / 3 + 2, 3, 9)
		for k in stones:
			var turn: float = float(k) * 2.39996
			var reach: float = (0.2 + 0.12 * float(k)) * tile_size * 0.5
			var size: float = (0.5 - 0.03 * float(k)) * tile_size * 0.5
			round.append(_box(Vector3(size * 1.3, size * 0.8, size), Vector3(at.x + cos(turn) * reach, ground + size * 0.35, at.z + sin(turn) * reach), RUBBLE.darkened(0.06 * float(k % 3))))
	multimesh.instance_count = placed.size()
	for i in placed.size():
		multimesh.set_instance_transform(i, placed[i][0])
		multimesh.set_instance_color(i, placed[i][1])
	_blobs.multimesh.instance_count = round.size()
	for i in round.size():
		_blobs.multimesh.set_instance_transform(i, round[i][0])
		_blobs.multimesh.set_instance_color(i, round[i][1])


# A smooth 0..1 swell over the ground, so neighbouring rows and tiles shade into one another.
func _wave(x: float, z: float) -> float:
	return 0.5 + 0.25 * sin(x * 0.37 + z * 0.11) + 0.25 * cos(z * 0.29 - x * 0.07)


func _box(size: Vector3, at: Vector3, colour: Color) -> Array:
	return [Transform3D(Basis.from_scale(size), at), colour]
