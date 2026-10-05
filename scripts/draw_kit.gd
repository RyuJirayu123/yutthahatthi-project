class_name DrawKit
extends RefCounted
## Fast drawing for shapes that are redrawn every frame.
## Godot's draw_colored_polygon / draw_polygon / draw_circle build a new GPU polygon on every
## call (~10 µs each), which adds up fast with hundreds of ornaments per frame. A cached mesh
## costs ~0.3 µs and a primitive of up to four points ~1 µs, so the elephants and the HUD use
## these instead. (Antialiasing comes from the thin polyline rims drawn over the shapes.)

static var _unit_circle: ArrayMesh
static var _meshes := {}     ## key -> ArrayMesh


static var _oct := PackedVector2Array()


## Big circles are a cached mesh (one draw call each); small ones an octagon of three quads,
## which the renderer batches together with the other primitives.
static func circle(c: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	if r > 6.0:
		c.draw_mesh(_circle_mesh(), null, Transform2D(0.0, Vector2(r, r), 0.0, p), col)
		return
	if _oct.is_empty():
		for i in 8:
			_oct.append(Vector2.from_angle(TAU * (i + 0.5) / 8.0))
	var o := _oct
	var cols := PackedColorArray([col])
	var none := PackedVector2Array()
	c.draw_primitive(PackedVector2Array([p + o[0] * r, p + o[1] * r, p + o[2] * r, p + o[3] * r]), cols, none)
	c.draw_primitive(PackedVector2Array([p + o[0] * r, p + o[3] * r, p + o[4] * r, p + o[7] * r]), cols, none)
	c.draw_primitive(PackedVector2Array([p + o[4] * r, p + o[5] * r, p + o[6] * r, p + o[7] * r]), cols, none)


static func ellipse(c: CanvasItem, p: Vector2, rx: float, ry: float, col: Color) -> void:
	c.draw_mesh(_circle_mesh(), null, Transform2D(0.0, Vector2(rx, ry), 0.0, p), col)


## Small polygon whose points change every frame: one colour, or one per point.
static func fill(c: CanvasItem, pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if pts.size() <= 4:
		c.draw_primitive(pts, cols, PackedVector2Array())
	elif cols.size() == 1:
		c.draw_colored_polygon(pts, cols[0])
	else:
		c.draw_polygon(pts, cols)


## Mesh for a polygon that never changes shape, built the first time `key` is asked for.
## Without `cols` the vertices are white and the colour comes from draw_mesh's modulate.
static func mesh(key: Variant, pts: PackedVector2Array, cols := PackedColorArray()) -> ArrayMesh:
	var m: ArrayMesh = _meshes.get(key)
	if m == null:
		m = build(pts, cols)
		_meshes[key] = m
	return m


## Uncached: triangulates `pts` into a new mesh.
static func build(pts: PackedVector2Array, cols := PackedColorArray()) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	if cols.size() == pts.size():
		arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(pts)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Static polygon in one colour.
static func shape(c: CanvasItem, key: Variant, pts: PackedVector2Array, col: Color) -> void:
	c.draw_mesh(mesh(key, pts), null, Transform2D.IDENTITY, col)


static func _circle_mesh() -> ArrayMesh:
	if _unit_circle == null:
		var pts := PackedVector2Array()
		for i in 28:
			pts.append(Vector2.from_angle(TAU * i / 28.0))
		_unit_circle = mesh(&"__circle", pts)
	return _unit_circle
