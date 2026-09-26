"""Render Dash head-and-shoulders, one per mood, for the app icons.

Writes assets/Dash/icon/Dash_bust_<state>.png (1024 x 1024, transparent). make_icons.py
then puts each on its battery-colour glow and writes the app's icon sets.

Run from the repository root, on the approved Dash:
  Blender --background assets/Dash/Dash_Final_backup.blend --python assets/Dash/scripts/render_icon_busts.py
"""
import math
import os

import bpy
from mathutils import Vector

HERE = os.path.dirname(__file__)
OUT = os.path.abspath(os.path.join(HERE, "..", "icon"))
IDLES = {"idle_energetic": "energetic", "idle_normal": "normal",
         "idle_tired": "tired", "idle_exhausted": "exhausted"}
FACE_MESHES = ["Body", "Eyes"]

scene = bpy.context.scene
rig = bpy.data.objects["Dash_Armature"]
meshes = [o for o in rig.children if o.type == "MESH"]


def play(clip):
    """Show one clip on the body and face, everything else muted."""
    rig.animation_data.action = bpy.data.actions[clip]
    for track in rig.animation_data.nla_tracks:
        track.mute = True
    for name in FACE_MESHES:
        data = bpy.data.objects[name].data.shape_keys.animation_data
        for track in data.nla_tracks:
            track.mute = True
        data.action = bpy.data.actions[f"{clip}__{name}_face"]


# Frame: the head fills a bit under half the picture, cut off at the chest.
scene.frame_set(1)
depsgraph = bpy.context.evaluated_depsgraph_get()
top = max((o.evaluated_get(depsgraph).matrix_world @ Vector(c)).z
          for o in meshes for c in o.evaluated_get(depsgraph).bound_box)
frame_top, frame_bottom = top + 0.13, top - 0.68
camera_data = bpy.data.cameras.new("IconCamera")
camera_data.sensor_fit = "VERTICAL"
camera_data.angle = math.radians(22)
camera = bpy.data.objects.new("IconCamera", camera_data)
scene.collection.objects.link(camera)
distance = ((frame_top - frame_bottom) / 2) / math.tan(camera_data.angle / 2)
camera.location = (0, -distance, (frame_top + frame_bottom) / 2)
camera.rotation_euler = (math.radians(90), 0, 0)
scene.camera = camera

bpy.data.objects["Studio_Ground"].hide_render = True
scene.render.film_transparent = True
scene.render.resolution_x = scene.render.resolution_y = 1024
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.cycles.samples = 160
scene.cycles.use_denoising = True
cycles = bpy.context.preferences.addons["cycles"].preferences
cycles.compute_device_type = "METAL"
cycles.get_devices()
for device in cycles.devices:
    device.use = True
scene.cycles.device = "GPU"

os.makedirs(OUT, exist_ok=True)
for clip, state in IDLES.items():
    play(clip)
    first, last = bpy.data.actions[clip].frame_range
    scene.frame_set(int(first + (last - first) / 4))        # a quarter in: never mid-blink
    scene.render.filepath = os.path.join(OUT, f"Dash_bust_{state}.png")
    bpy.ops.render.render(write_still=True)
print("busts written to", OUT)
