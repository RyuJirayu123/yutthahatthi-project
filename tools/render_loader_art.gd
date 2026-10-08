extends SceneTree
## Renders the elephants on the web loading page (web/*_idle.webp, web/*_happy.webp) from the
## game's own rig, on a transparent background. Run from the project folder, with a window:
##   <godot> --path . --script tools/render_loader_art.gd
## then `python web/build_shell.py`. Idle and happy poses of one elephant share a crop, so
## swapping them when loading finishes keeps the feet in place.

## [ElephantDef file, facing, image name]: left elephant faces right, right one faces left
const ELEPHANTS := [["phlai_saeng", 1, "saeng"], ["phlai_mek", -1, "mek"]]
const HEIGHT := 560


func _initialize() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.transparent_bg = true
	_run.call_deferred()


func _grab(def_name: String, face: int, happy: bool) -> Image:
	var p = load("res://scripts/elephant_preview.gd").new()
	p.size = Vector2(960, 540)
	root.add_child(p)
	p.def = load("res://data/elephants/%s.tres" % def_name)
	p.face = face
	p.happy = happy
	# the victory action is rearing up about 0.45 s in
	await create_timer(0.45 if happy else 0.5).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	p.queue_free()
	await process_frame
	return img


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://web")
	for spec in ELEPHANTS:
		var idle: Image = await _grab(spec[0], spec[1], false)
		var happy: Image = await _grab(spec[0], spec[1], true)
		var r := idle.get_used_rect().merge(happy.get_used_rect()).grow(6).intersection(Rect2i(Vector2i.ZERO, idle.get_size()))
		for pair in [[idle, "_idle"], [happy, "_happy"]]:
			var img: Image = (pair[0] as Image).get_region(r)
			img.resize(int(img.get_width() * HEIGHT / float(img.get_height())), HEIGHT, Image.INTERPOLATE_LANCZOS)
			img.save_webp(out + "/" + spec[2] + pair[1] + ".webp", true, 0.86)
			print("wrote web/", spec[2], pair[1], ".webp ", img.get_size())
	quit()
