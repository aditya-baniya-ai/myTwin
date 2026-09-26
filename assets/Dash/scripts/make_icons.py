"""Build the app icons: Dash's head and shoulders on a glow in each mood's battery colour.

Reads assets/Dash/icon/Dash_bust_<state>.png (from render_icon_busts.py) and writes
myTwin/Assets.xcassets/AppIcon*.appiconset. The colours match AvatarEnergyState.glow in
the app, so the icon, the widget and the app always agree.

The normal (blue) icon is the app's main icon; the others are alternates the app
switches to as your energy changes.

Run from the repository root:  python3 assets/Dash/scripts/make_icons.py
"""
import json
import os

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BUSTS = os.path.join(REPO, "assets", "Dash", "icon")
CATALOG = os.path.join(REPO, "myTwin", "Assets.xcassets")
SIZE = 1024

# Same two colours per mood as AvatarEnergyState.glow.
GLOW = {
    "energetic": ((0.16, 0.84, 0.58), (0.42, 0.95, 0.82)),
    "normal": ((0.30, 0.62, 1.00), (0.45, 0.85, 0.95)),
    "tired": ((1.00, 0.75, 0.25), (1.00, 0.58, 0.35)),
    "exhausted": ((0.95, 0.42, 0.45), (0.78, 0.40, 0.62)),
}
ICON_SET = {"normal": "AppIcon", "energetic": "AppIcon-Energetic",
            "tired": "AppIcon-Tired", "exhausted": "AppIcon-Exhausted"}
NIGHT = np.array([0.035, 0.04, 0.07])          # the deep base the light falls off into


def soft_light(center, radius):
    """1 at `center`, fading smoothly to 0 at `radius` (pixels)."""
    y, x = np.mgrid[0:SIZE, 0:SIZE]
    d = np.hypot(x - center[0], y - center[1]) / radius
    t = np.clip(1 - d, 0, 1)
    return (t * t * (3 - 2 * t))[..., None]


def background(state):
    main, light = (np.array(c) for c in GLOW[state])
    image = np.broadcast_to(NIGHT, (SIZE, SIZE, 3)).copy()
    image = image * (1 - 0.55 * soft_light((512, 560), 900)) + main * 0.55 * soft_light((512, 560), 900)
    image += main * 0.55 * soft_light((512, 400), 470)                  # the glow behind the head
    image += light * 0.35 * soft_light((330, 330), 330)                 # aurora lights either side
    image += main * 0.30 * soft_light((720, 520), 360)
    image += 0.25 * soft_light((512, 380), 200)                         # bright heart
    image *= 1 - 0.35 * (1 - soft_light((512, 512), 820))               # darker corners
    return np.clip(image, 0, 1)


def build(state):
    base = Image.fromarray((background(state) * 255).astype(np.uint8), "RGB")
    bust = Image.open(os.path.join(BUSTS, f"Dash_bust_{state}.png")).convert("RGBA")
    base.paste(bust, (0, 0), bust)
    return base


for state, name in ICON_SET.items():
    folder = os.path.join(CATALOG, f"{name}.appiconset")
    os.makedirs(folder, exist_ok=True)
    build(state).save(os.path.join(folder, "icon.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "icon.png", "idiom": "universal",
                               "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
    print("wrote", folder)
