"""Export Dash for the iOS app.

Writes three things:
  myTwin/Avatar/Dash.usdz          the rigged model RealityKit loads
  myTwin/Avatar/Dash.clips.json    where each clip sits on the model's timeline
  Shared/AvatarImages.xcassets     one rendered still per energy state, for the Home
                                   Screen widget and while the 3D model loads

RealityKit cannot read .glb, and it plays a USD file's animation as one timeline. So
the four idle loops and the one-shot actions from gestures.py are laid end to end on
that timeline (body and face together), and the app cuts them apart again using the
ranges in Dash.clips.json.

Run from the repository root, on the .blend that holds the approved Dash:
  Blender --background assets/Dash/Dash_Final_backup.blend --python assets/Dash/scripts/export_usdz.py
"""
import json
import math
import os

import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import gestures  # noqa: E402  (needs the path above)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
AVATAR_DIR = os.path.join(REPO, "myTwin", "Avatar")
STILLS_DIR = os.path.join(REPO, "Shared", "AvatarImages.xcassets")

# Idle loop -> the energy state it acts out. Stills are rendered from these.
IDLES = {"idle_normal": "normal", "idle_energetic": "energetic",
         "idle_tired": "tired", "idle_exhausted": "exhausted"}
FACE_MESHES = ["Body", "Eyes"]          # their shape keys carry the expressions
STILL_SIZE = (520, 780)
# Framing, shared with Avatar3DView: vertical field of view, and the space left above the
# head (room to jump) and below the feet, as shares of the character's height.
FIELD_OF_VIEW = 30.0
HEADROOM, FOOTROOM = 0.12, 0.02

scene = bpy.context.scene
rig = bpy.data.objects["Dash_Armature"]
meshes = [o for o in rig.children if o.type == "MESH"]
fps = scene.render.fps

missing = [clip for clip in IDLES if clip not in bpy.data.actions]
if missing:
    sys.exit(f"{bpy.data.filepath} is not the approved Dash: it has no {', '.join(missing)}")


def lay_out_clips():
    """Mute every stored track and put the clips end to end on one new track each for
    the skeleton and the two face meshes. Returns {clip: (first_frame, last_frame)}."""
    owners = {None: rig.animation_data}
    for name in FACE_MESHES:
        owners[name] = bpy.data.objects[name].data.shape_keys.animation_data
    tracks = {}
    for key, data in owners.items():
        data.action = None
        for track in data.nla_tracks:
            track.mute = True
        tracks[key] = data.nla_tracks.new()
        tracks[key].name = "app_timeline"

    ranges, frame = {}, 0
    for clip in list(IDLES) + ACTIONS:
        first, last = bpy.data.actions[clip].frame_range
        length = int(round(last - first))
        for key, track in tracks.items():
            action = bpy.data.actions[clip if key is None else f"{clip}__{key}_face"]
            strip = track.strips.new(clip, frame, action)
            strip.extrapolation = "NOTHING"
        ranges[clip] = (frame, frame + length)
        frame += length + 1
    scene.frame_start, scene.frame_end = 0, frame - 1
    return ranges


def export_usdz():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes + [rig]:
        obj.select_set(True)
    bpy.ops.wm.usd_export(
        filepath=os.path.join(AVATAR_DIR, "Dash.usdz"),
        selected_objects_only=True,
        export_animation=True, export_armatures=True, only_deform_bones=True,
        export_shapekeys=True, export_materials=True, generate_preview_surface=True,
        # Dash carries a baked normal map, so normals and UVs have to travel with him.
        export_normals=True, export_uvmaps=True, export_textures_mode="NEW",
        export_subdivision="IGNORE", triangulate_meshes=True,
        convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        export_lights=False, export_cameras=False, export_curves=False,
        export_points=False, export_volumes=False, export_hair=False,
        export_custom_properties=False, root_prim_path="/Dash",
        # On a phone Dash is a few hundred points tall, so the GPU never samples the
        # 2K levels: 1K looks the same and needs a quarter of the memory.
        usdz_downscale_size="1024")


def write_clip_table(ranges):
    table = {"fps": fps,
             "clips": {clip: {"start": first / fps, "end": last / fps,
                              "loops": clip in IDLES}
                       for clip, (first, last) in ranges.items()}}
    with open(os.path.join(AVATAR_DIR, "Dash.clips.json"), "w") as f:
        json.dump(table, f, indent=2)


def render_stills(ranges):
    """Front view, transparent background, a quarter of the way into each clip so no
    still lands on a blink."""
    scene.frame_set(0)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    corners = [o.evaluated_get(depsgraph).matrix_world @ Vector(c)
               for o in meshes for c in o.evaluated_get(depsgraph).bound_box]
    bottom, top = min(c.z for c in corners), max(c.z for c in corners)
    tall = top - bottom
    frame_bottom, frame_top = bottom - FOOTROOM * tall, top + HEADROOM * tall
    height = frame_top - frame_bottom

    cam_data = bpy.data.cameras.new("AppStill")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle = math.radians(FIELD_OF_VIEW)
    camera = bpy.data.objects.new("AppStill", cam_data)
    scene.collection.objects.link(camera)
    distance = (height / 2) / math.tan(cam_data.angle / 2)
    camera.location = (0, -distance, (frame_top + frame_bottom) / 2)
    camera.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = camera

    bpy.data.objects["Studio_Ground"].hide_render = True
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = STILL_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    cycles = bpy.context.preferences.addons["cycles"].preferences
    cycles.compute_device_type = "METAL"
    cycles.get_devices()
    for device in cycles.devices:
        device.use = True
    scene.cycles.device = "GPU"

    for clip, state in IDLES.items():
        first, last = ranges[clip]
        scene.frame_set(first + (last - first) // 4)
        name = f"Dash_{state}"
        folder = os.path.join(STILLS_DIR, f"{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        scene.render.filepath = os.path.join(folder, f"{name}.png")
        bpy.ops.render.render(write_still=True)
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                       "info": {"author": "xcode", "version": 1}}, f, indent=2)
    with open(os.path.join(STILLS_DIR, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)


os.makedirs(AVATAR_DIR, exist_ok=True)
ACTIONS = gestures.add_all(rig)
clip_ranges = lay_out_clips()
export_usdz()
write_clip_table(clip_ranges)
render_stills(clip_ranges)
print("clips:", clip_ranges)
# The .blend on disk is never saved, so the source file keeps its muted tracks.
