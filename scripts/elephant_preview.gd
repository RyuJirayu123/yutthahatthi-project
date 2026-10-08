class_name ElephantPreview
extends Control
## An animated elephant inside a UI box (select screen cards and detail panels).
## Uses the same ElephantRig as the arena; `happy` makes it rear up.

var def: ElephantDef:
	set(v):
		def = v
		_fighter = Fighter.new(def, 0.0, face, "none") if def else null
		_rig = ElephantRig.new()
		material = ElephantRig.material_for(def) if def else null
var face := 1:
	set(v):
		face = v
		if _fighter:
			_fighter.face = v
var happy := false

var _fighter: Fighter
var _rig: ElephantRig


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(delta: float) -> void:
	if _fighter == null or not is_visible_in_tree():
		return
	_fighter.win = happy
	_rig.update(_fighter, "done" if happy else "fight", minf(delta, 0.05))
	queue_redraw()


func _draw() -> void:
	if _fighter == null:
		return
	# the elephant spans about x -100..140 and y -215..0 in rig space; extra margin for rearing up
	var s := minf(size.x / 300.0, size.y / 235.0)
	var base := Transform2D(0.0, Vector2(size.x / 2.0 - 20.0 * s * face, size.y - 4.0))
	base = base.scaled_local(Vector2(s, s)).translated_local(Vector2(0.0, -GameData.GROUND))
	_rig.draw(self, _fighter, base)
	draw_set_transform_matrix(Transform2D.IDENTITY)
