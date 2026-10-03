@tool
extends RefCounted

# One pure calculation used by preview, Apply and tests. No scene mutation.
static func generate(p: Dictionary, original: Dictionary = {}) -> PackedFloat32Array:
	var n: int = p.get("resolution", 65)
	var noise := FastNoiseLite.new()
	noise.seed = int(p.get("seed", 1337))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / maxf(float(p.get("scale", 32)), 1.0)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = clampi(int(p.get("octaves", 5)), 1, 8)
	noise.fractal_gain = clampf(float(p.get("roughness", 0.5)), 0, 1)
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var base: float = p.get("base", 0.0)
	var amplitude: float = p.get("range", 24.0)
	for z in n:
		for x in n:
			var v := clampf(noise.get_noise_2d(x + float(p.get("offset_x", 0)), z + float(p.get("offset_z", 0))) * 0.5 + 0.5, 0, 1)
			v = pow(v, maxf(0.1, float(p.get("curve", 1.0))))
			var h := base + v * amplitude
			var q := Vector2(x, z) / float(n - 1) * 2.0 - Vector2.ONE
			var d := lerpf(q.length(), maxf(absf(q.x), absf(q.y)), float(p.get("island_shape", 0.0)))
			var falloff := pow(clampf(d, 0, 1), maxf(0.1, float(p.get("island_sharpness", 2.0))))
			h = lerpf(h, base + amplitude * float(p.get("island_height", -0.2)), clampf(falloff * float(p.get("island_weight", 0)), 0, 1))
			if p.get("additive", false) and not original.is_empty():
				h += sample(original.heights, int(original.resolution), float(x) / (n - 1) * (int(original.resolution) - 1), float(z) / (n - 1) * (int(original.resolution) - 1))
			heights[z * n + x] = h
	# Lightweight directional diffusion, not hydraulic erosion.
	for pass_index in clampi(int(p.get("erosion", 0)), 0, 12):
		var source := heights.duplicate()
		var direction := Vector2(float(p.get("slope_x", 0)), float(p.get("slope_z", 0))).normalized()
		if p.get("slope_invert", false): direction = -direction
		for z in range(1, n - 1):
			for x in range(1, n - 1):
				var i := z * n + x
				var slope := Vector2(source[i + 1] - source[i - 1], source[i + n] - source[i - n]) * 0.5
				var bias := clampf(1.0 + slope.dot(direction) * float(p.get("slope_factor", 0)), 0, 2)
				var average := (source[i - 1] + source[i + 1] + source[i - n] + source[i + n]) * 0.25
				heights[i] = lerpf(source[i], average, clampf(float(p.get("erosion_weight", 0.35)) * bias, 0, 1))
	var dilation: float = p.get("dilation", 0)
	if dilation > 0:
		var source := heights.duplicate()
		for z in range(1, n - 1):
			for x in range(1, n - 1):
				var i := z * n + x
				var peak := maxf(source[i], maxf(maxf(source[i - 1], source[i + 1]), maxf(source[i - n], source[i + n])))
				heights[i] = lerpf(source[i], peak, dilation)
	return heights

static func sample(h: PackedFloat32Array, n: int, x: float, z: float) -> float:
	x = clampf(x, 0, n - 1)
	z = clampf(z, 0, n - 1)
	var ix := mini(int(x), n - 2)
	var iz := mini(int(z), n - 2)
	var fx := x - ix
	var fz := z - iz
	var a := h[iz * n + ix]
	var b := h[iz * n + ix + 1]
	var c := h[(iz + 1) * n + ix]
	var d := h[(iz + 1) * n + ix + 1]
	if fx + fz <= 1: return a + fx * (b - a) + fz * (c - a)
	return d + (1 - fx) * (c - d) + (1 - fz) * (b - d)
