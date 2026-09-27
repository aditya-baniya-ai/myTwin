"""
Renders key frames from Dash's animation timeline for the README.
Run with:
  blender --background assets/Dash/Dash_Final.blend --python assets/Dash/scripts/render_readme_frames.py
"""

import bpy
import os

# Output directory — next to the script, in a new readme_frames folder
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "readme_frames")
os.makedirs(OUT_DIR, exist_ok=True)

# Frames to render: (output_name, frame_number)
# At 30 fps, frame = round(time_seconds * 30)
FRAMES = [
    # Idle states — a distinctive mid-cycle moment for each
    ("idle_energetic",  180),   # ~6.0s into idle_energetic (midpoint of 4.03–8.03s)
    ("idle_normal",      60),   # ~2.0s into idle_normal (midpoint of 0–4.0s)
    ("idle_tired",      333),   # ~11.1s into idle_tired (midpoint of 8.07–14.07s)
    ("idle_exhausted",  543),   # ~18.1s into idle_exhausted (midpoint of 14.1–22.1s)
    # One-shot gestures — peak moment of each action
    ("wave",            699),   # ~23.3s — arm fully raised
    ("jump",            762),   # ~25.4s — peak of jump
    ("stretch",         849),   # ~28.3s — mid-stretch
    ("yawn",            978),   # ~32.6s — mouth fully open
    ("doze",           1137),   # ~37.9s — fully nodded off
]

scene = bpy.context.scene
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 1080
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100

for name, frame in FRAMES:
    scene.frame_set(frame)
    out_path = os.path.join(OUT_DIR, f"Dash_{name}.png")
    scene.render.filepath = out_path
    print(f"Rendering frame {frame} → {out_path}")
    bpy.ops.render.render(write_still=True)
    print(f"  Done.")

print("All frames rendered.")
