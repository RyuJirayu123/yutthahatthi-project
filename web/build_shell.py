"""Builds web/shell.html (the custom HTML shell used by the Web export preset).

Edit shell_src.html, then run:  python web/build_shell.py
The elephant images and the backdrop are inlined as data URIs so the shell stays a single file
(Godot's exporter copies only the HTML, not files next to it).
"""
import base64
import pathlib

here = pathlib.Path(__file__).parent
html = (here / "shell_src.html").read_text(encoding="utf-8")
for key, name, mime in [
    ("{{ELEPHANT_STAND}}", "elephant_stand.png", "image/png"),
    ("{{ELEPHANT_REAR}}", "elephant_rear.png", "image/png"),
    ("{{SCENE}}", "scene_day.jpg", "image/jpeg"),
]:
    data = base64.b64encode((here / name).read_bytes()).decode("ascii")
    html = html.replace(key, "data:%s;base64,%s" % (mime, data))
(here / "shell.html").write_text(html, encoding="utf-8", newline="\n")
print("wrote", here / "shell.html")
