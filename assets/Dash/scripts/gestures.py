"""One-shot actions the app plays now and then, on top of the idle loops.

  wave, jump   full of energy: waves hello, or jumps on the platform with knees tucked
  stretch      normal: a slow, lazy stretch overhead, then a sigh
  yawn         tired: hand to mouth, a big yawn
  doze         nearly empty: nods off standing, jolts awake, sags again

Each action is a body action on the armature plus face actions on the Body and Eyes
shape keys, named like the clips finish_dash.py makes, so export_usdz.py treats them
the same way. They replace finish_dash.py's simpler yawn and stretch, and are created in
memory at export time: nothing here is saved into the .blend.
"""
from math import cos, pi, sin

import bpy
from mathutils import Quaternion, Vector

FACE_MESHES = ["Body", "Eyes"]


def smooth(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def window(t, rise_from, rise_to, fall_from, fall_to):
    """0 -> 1 -> 0: up between the first two times, down between the last two."""
    return smooth(rise_from, rise_to, t) - smooth(fall_from, fall_to, t)


class Pose:
    """Poses Dash's bones in world-space terms: 'turn this bone about that axis'."""

    def __init__(self, rig):
        self.rig = rig
        self.bones = rig.pose.bones

    def reset(self):
        for bone in self.bones:
            bone.rotation_mode = "XYZ"
            bone.rotation_euler = (0, 0, 0)
            bone.location = (0, 0, 0)
            bone.scale = (1, 1, 1)

    def turn(self, name, axis, angle):
        """Rotates a bone about a direction in the armature's own space (Z up, -Y front)."""
        bone = self.bones[name]
        local = (bone.bone.matrix_local.to_3x3().inverted() @ Vector(axis)).normalized()
        turned = Quaternion(local, angle) @ bone.rotation_euler.to_quaternion()
        bone.rotation_euler = turned.to_euler("XYZ")

    def twist(self, name, angle):
        """Rotates a bone about its own length, like turning a forearm palm up."""
        bone = self.bones[name]
        turned = bone.rotation_euler.to_quaternion() @ Quaternion((0, 1, 0), angle)
        bone.rotation_euler = turned.to_euler("XYZ")

    def neutral(self, slump=0.0):
        """The resting stance of the idle clips: arms relaxed, fingers softly curled."""
        self.reset()
        for side, sign in (("L", 1), ("R", -1)):
            self.turn(f"UpperArm.{side}", (0, 1, 0), sign * 0.32)
            for finger in ("Index", "Middle", "Ring", "Little"):
                for joint in (1, 2, 3):
                    self.bones[f"{finger}{joint}.{side}"].rotation_euler[0] = 0.045
        if slump:
            self.bones["Spine"].rotation_euler[0] = slump * 0.55
            self.bones["Chest"].rotation_euler[0] = slump * 0.45
            self.bones["Head"].rotation_euler[0] = slump

    def bend_legs(self, amount, tuck=0.0):
        """Knees forward and hips down, feet staying flat. `tuck` lifts the knees in the air."""
        for side in ("L", "R"):
            thigh = 0.5 * amount + 1.1 * tuck
            self.turn(f"UpperLeg.{side}", (1, 0, 0), -thigh)
            self.turn(f"LowerLeg.{side}", (1, 0, 0), 1.0 * amount + 1.7 * tuck)
            self.turn(f"Foot.{side}", (1, 0, 0), -0.5 * amount - 0.3 * tuck)

    def key(self, frame):
        for bone in self.bones:
            bone.keyframe_insert("location", frame=frame, group=bone.name)
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("scale", frame=frame, group=bone.name)


def record(rig, name, frames, pose_at, face_at, step=2):
    """Builds one action from `pose_at(pose, t)` and `face_at(t) -> {shape key: value}`,
    with t running 0 -> 1 across the clip. Replaces any action of the same name."""
    for old in [name] + [f"{name}__{mesh}_face" for mesh in FACE_MESHES]:
        if old in bpy.data.actions:
            bpy.data.actions.remove(bpy.data.actions[old])
    pose = Pose(rig)
    rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    samples = sorted(set(range(1, frames + 1, step)) | {frames + 1})   # always end at t = 1
    for frame in samples:
        pose_at(pose, (frame - 1) / frames)
        pose.key(frame)
    rig.animation_data.action = None

    for mesh in FACE_MESHES:
        keys = bpy.data.objects[mesh].data.shape_keys
        keys.animation_data_create()
        face = bpy.data.actions.new(f"{name}__{mesh}_face")
        face.use_fake_user = True
        keys.animation_data.action = face
        for frame in samples:
            values = face_at((frame - 1) / frames)
            for block in keys.key_blocks:
                if block.name != "Basis":
                    block.value = values.get(block.name, 0.0)
                    block.keyframe_insert("value", frame=frame)
        keys.animation_data.action = None
        for block in keys.key_blocks:
            block.value = 0.0
    Pose(rig).reset()


# --- The actions --------------------------------------------------------------------

def wave_pose(pose, t):
    """Right hand up beside the face, three friendly waves, back down."""
    pose.neutral()
    up = window(t, 0.0, 0.2, 0.8, 1.0)
    waving = window(t, 0.18, 0.26, 0.74, 0.82)
    swing = sin((t - 0.2) * 2 * pi * 4.5) * waving
    pose.turn("UpperArm.R", (0, 1, 0), 1.55 * up)          # arm out and up
    pose.turn("UpperArm.R", (1, 0, 0), -0.35 * up)         # a little forward
    pose.turn("LowerArm.R", (0, 1, 0), 1.25 * up + 0.35 * swing)
    pose.twist("LowerArm.R", -1.2 * up)                    # palm towards you
    pose.turn("Hand.R", (0, 1, 0), 0.25 * swing)
    pose.turn("Chest", (0, 1, 0), 0.05 * up)               # lean into it
    pose.turn("Head", (0, 1, 0), -0.08 * up)
    pose.bones["Head"].rotation_euler[0] -= 0.05 * up      # chin up, cheerful
    pose.bones["Hips"].location.y = 0.006 * sin(t * 2 * pi * 2) * up


def wave_face(t):
    up = window(t, 0.0, 0.2, 0.8, 1.0)
    return {"Smile": 0.25 + 0.65 * up, "BrowsUp": 0.16 + 0.35 * up, "EyesWide": 0.15 * up}


def jump_pose(pose, t):
    """Crouch, spring up with knees tucked and arms thrown up, land, settle."""
    pose.neutral()
    crouch = window(t, 0.0, 0.2, 0.22, 0.3) + window(t, 0.62, 0.7, 0.78, 0.95) * 0.8
    air = window(t, 0.26, 0.3, 0.58, 0.64)
    rise = sin(min(max((t - 0.27) / 0.34, 0.0), 1.0) * pi)   # up, then down again
    arms_up = window(t, 0.22, 0.32, 0.6, 0.72)
    arms_back = window(t, 0.05, 0.2, 0.22, 0.28)

    pose.bend_legs(crouch, tuck=0.75 * air)
    pose.bones["Hips"].location.y = -0.09 * crouch + 0.15 * rise    # fits the view's headroom
    pose.bones["Spine"].rotation_euler[0] = 0.18 * crouch - 0.06 * air
    pose.bones["Head"].rotation_euler[0] = -0.12 * crouch - 0.1 * air
    for side, sign in (("L", 1), ("R", -1)):
        pose.turn(f"UpperArm.{side}", (0, 1, 0), -sign * 1.9 * arms_up)   # up and out
        pose.turn(f"UpperArm.{side}", (1, 0, 0), 0.5 * arms_back)          # swung back first
        pose.turn(f"LowerArm.{side}", (0, 1, 0), -sign * 0.4 * arms_up)


def jump_face(t):
    air = window(t, 0.24, 0.3, 0.6, 0.7)
    set_ = window(t, 0.0, 0.15, 0.22, 0.28)
    return {"Smile": 0.25 + 0.7 * air, "BrowsUp": 0.16 + 0.4 * air, "EyesWide": 0.35 * air,
            "BrowsDown": 0.3 * set_, "MouthOpen": 0.35 * air}


def doze_pose(pose, t):
    """Eyes close, head drops, gentle breathing; a jolt awake, then the slump again."""
    pose.neutral(slump=0.2)
    asleep = window(t, 0.05, 0.3, 0.72, 0.76)
    jolt = window(t, 0.72, 0.75, 0.8, 0.95)
    breathe = sin(t * 2 * pi * 4)
    pose.bones["Head"].rotation_euler[0] += 0.2 * asleep - 0.3 * jolt
    pose.bones["Neck"].rotation_euler[0] = 0.06 * asleep
    pose.bones["Chest"].rotation_euler[0] += 0.03 * breathe * asleep
    pose.bones["Chest"].scale = (1, 1, 1 + 0.015 * breathe * asleep)
    pose.bones["Hips"].location.x = 0.012 * sin(t * 2 * pi * 1.5) * asleep     # sway
    pose.bones["Hips"].location.y = -0.02 * asleep
    pose.bend_legs(0.12 * asleep)                                              # knees sag
    pose.turn("Head", (0, 1, 0), 0.08 * asleep * sin(t * 2 * pi))


def doze_face(t):
    asleep = window(t, 0.05, 0.3, 0.72, 0.75)
    jolt = window(t, 0.72, 0.74, 0.8, 0.95)
    closed = max(asleep, 0.0)
    return {"BlinkLeft": closed, "BlinkRight": closed, "EyesTired": 0.72 * (1 - jolt),
            "EyesWide": 0.7 * jolt, "BrowsUp": 0.6 * jolt, "Frown": 0.36 * (1 - jolt),
            "MouthOpen": 0.25 * asleep}


def stretch_pose(pose, t):
    """Arms up overhead, leaning back on tiptoe; then down, shoulders drop, a sigh."""
    pose.neutral()
    up = window(t, 0.05, 0.4, 0.62, 0.85)
    sigh = window(t, 0.78, 0.86, 0.9, 1.0)
    for side, sign in (("L", 1), ("R", -1)):
        pose.turn(f"UpperArm.{side}", (0, 1, 0), -sign * 2.35 * up)
        pose.turn(f"UpperArm.{side}", (1, 0, 0), -0.25 * up)            # slightly forward
        pose.turn(f"LowerArm.{side}", (0, 1, 0), -sign * 0.5 * up)      # hands meet overhead
        pose.turn(f"Clavicle.{side}", (0, 1, 0), -sign * 0.12 * up - sign * -0.08 * sigh)
    pose.bones["Spine"].rotation_euler[0] = -0.1 * up + 0.05 * sigh
    pose.bones["Chest"].rotation_euler[0] = -0.12 * up + 0.06 * sigh
    pose.bones["Head"].rotation_euler[0] = -0.2 * up + 0.08 * sigh
    pose.bones["Hips"].location.y = 0.025 * up - 0.01 * sigh           # up onto tiptoe
    for side in ("L", "R"):
        pose.turn(f"Foot.{side}", (1, 0, 0), -0.18 * up)


def stretch_face(t):
    up = window(t, 0.05, 0.4, 0.62, 0.85)
    after = window(t, 0.8, 0.9, 0.95, 1.0)
    return {"BlinkLeft": 0.85 * up, "BlinkRight": 0.85 * up, "MouthOpen": 0.3 * up,
            "BrowsUp": 0.3 * up, "Smile": 0.08 + 0.3 * after}


# Where the right arm goes to cover the mouth, solved numerically against the mouth
# position (see the note in yawn_pose). Local bone rotations, as quaternions.
YAWN_HAND = {"UpperArm.R": Quaternion((0.02324, 0.92147, -0.07768, -0.37989)),
             "LowerArm.R": Quaternion((-0.92688, -0.33194, -0.03766, -0.17117))}


def reach(pose, targets, amount):
    """Blends bones from wherever they are now towards fixed local rotations."""
    for name, target in targets.items():
        bone = pose.bones[name]
        now = bone.rotation_euler.to_quaternion()
        if now.dot(target) < 0:
            target = -target                    # same rotation; take the short way round
        bone.rotation_euler = now.slerp(target, amount).to_euler("XYZ")


def yawn_pose(pose, t):
    """Shoulders rise, head tips back, hand comes up to cover a big yawn."""
    pose.neutral(slump=0.1)
    yawn = window(t, 0.1, 0.4, 0.62, 0.9)
    hand = window(t, 0.15, 0.38, 0.62, 0.85)
    pose.bones["Head"].rotation_euler[0] -= 0.28 * yawn
    pose.bones["Neck"].rotation_euler[0] = -0.08 * yawn
    pose.bones["Chest"].rotation_euler[0] -= 0.06 * yawn
    pose.turn("Clavicle.L", (0, 1, 0), -0.08 * yawn)
    pose.turn("Clavicle.R", (0, 1, 0), 0.08 * yawn)
    # Hand over the mouth. The arm angles were found by a search that put the fingertips
    # 6 cm in front of the lips at the peak of the yawn, elbow below the chin.
    reach(pose, YAWN_HAND, hand)
    pose.turn("Hand.R", (1, 0, 0), 0.3 * hand)
    pose.turn("UpperArm.L", (0, 1, 0), 0.25 * yawn)                    # other arm hangs loose


def yawn_face(t):
    yawn = window(t, 0.1, 0.4, 0.62, 0.9)
    return {"Yawn": yawn, "EyesTired": 0.4 + 0.45 * yawn, "BlinkLeft": 0.55 * yawn,
            "BlinkRight": 0.55 * yawn, "BrowsUp": 0.3 * yawn, "Frown": 0.18 * (1 - yawn)}


ACTIONS = {
    "wave": (72, wave_pose, wave_face),
    "jump": (51, jump_pose, jump_face),
    "stretch": (120, stretch_pose, stretch_face),
    "yawn": (135, yawn_pose, yawn_face),
    "doze": (180, doze_pose, doze_face),
}


def add_all(rig):
    """Creates every action above; returns their names."""
    for name, (frames, pose_at, face_at) in ACTIONS.items():
        record(rig, name, frames, pose_at, face_at)
    return list(ACTIONS)
