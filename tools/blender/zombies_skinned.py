"""Skinned low-poly Runner: one continuous body on an R15-style armature + a preview render.

Replaces the rigid-part rig (tools/blender/zombies.py) for the near LOD tier once the
renderer plays Blender animations. The body is split by tone into skinned meshes that share
one armature (Runner_Skin, Runner_Shirt, Runner_Pants, Runner_Dark, Runner_Eyes), so the game
keeps colouring each zombie's variant at runtime.

Axes as in zombies.py: a point at Roblox (x, y, z) is modelled at Blender (-x, z, y); the
zombie faces Blender -Y, so its left side is Blender +X. Units are studs; the FBX is written at
0.01 because the importer showed a 100× scale with global_scale 1.

Skin weights are computed here, not by Blender's heat weighting: each vertex blends its two
nearest bones among the ones its body piece may follow (a sleeve never follows the hip),
so the result is deterministic and has at most two influences per vertex.
"""
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Vector

root = Path(sys.argv[sys.argv.index("--") + 1])
source = root / "assets/source"
export = root / "assets/export"
source.mkdir(parents=True, exist_ok=True)
export.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)


def rb(x, y, z):
    """Roblox point (studs) → Blender vector."""
    return Vector((-x, z, y))


# ---- Joints (Roblox space, feet at y = 0, facing -Z). Runner: lean, hunched forward, head
# pushed ahead of the chest, arms hanging a little forward.
J = {
    "Root": (0, 0, 0),
    "Pelvis": (0, 2.05, 0.05),
    "Waist": (0, 2.6, 0),
    "Chest": (0, 3.65, -0.18),
    "Neck": (0, 4.05, -0.3),
    "HeadTop": (0, 5.15, -0.45),
}
for side, sx in (("Left", -1), ("Right", 1)):
    J[side + "Hip"] = (0.45 * sx, 2.0, 0.05)
    J[side + "Knee"] = (0.47 * sx, 1.05, -0.08)
    J[side + "Ankle"] = (0.48 * sx, 0.22, 0.05)
    J[side + "Toe"] = (0.5 * sx, 0.06, -0.5)
    J[side + "Shoulder"] = (1.0 * sx, 3.72, -0.15)
    J[side + "Elbow"] = (1.18 * sx, 2.95, -0.4)
    J[side + "Wrist"] = (1.24 * sx, 2.3, -0.62)
    J[side + "Fingers"] = (1.26 * sx, 1.9, -0.72)

# Bone name → (head joint, tail joint, parent). Names follow Roblox R15 so animations and
# code can refer to familiar parts.
BONES = {
    "HumanoidRootNode": ("Root", "Pelvis", None),
    "LowerTorso": ("Pelvis", "Waist", "HumanoidRootNode"),
    "UpperTorso": ("Waist", "Chest", "LowerTorso"),
    "Neck": ("Chest", "Neck", "UpperTorso"),
    "Head": ("Neck", "HeadTop", "Neck"),
}
for side in ("Left", "Right"):
    BONES[side + "UpperLeg"] = (side + "Hip", side + "Knee", "LowerTorso")
    BONES[side + "LowerLeg"] = (side + "Knee", side + "Ankle", side + "UpperLeg")
    BONES[side + "Foot"] = (side + "Ankle", side + "Toe", side + "LowerLeg")
    BONES[side + "UpperArm"] = (side + "Shoulder", side + "Elbow", "UpperTorso")
    BONES[side + "LowerArm"] = (side + "Elbow", side + "Wrist", side + "UpperArm")
    BONES[side + "Hand"] = (side + "Wrist", side + "Fingers", side + "LowerArm")

arm_data = bpy.data.armatures.new("RunnerRig")
rig = bpy.data.objects.new("RunnerRig", arm_data)
bpy.context.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, (h, t, parent) in BONES.items():
    bone = arm_data.edit_bones.new(name)
    bone.head = rb(*J[h])
    bone.tail = rb(*J[t])
    bone.roll = 0
    if parent:
        bone.parent = arm_data.edit_bones[parent]
        bone.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")
segments = {name: (rb(*J[h]), rb(*J[t])) for name, (h, t, _) in BONES.items()}


# ---- Geometry: octagonal tubes along joint paths. Each piece records which bones it may
# follow; weights are filled in after the mesh is built.
def octagon(a, b, jag):
    pts = [(a, 0.55 * b), (0.55 * a, b), (-0.55 * a, b), (-a, 0.55 * b),
           (-a, -0.55 * b), (-0.55 * a, -b), (0.55 * a, -b), (a, -0.55 * b)]
    return [(u, v, -jag if i % 2 == 0 else 0.0) for i, (u, v) in enumerate(pts)]


def tube(bm, rings, bones, tags, side_hint=Vector((1, 0, 0))):
    """rings = [(roblox point, half width a, half depth b, jag)]; a runs along side_hint."""
    layers = []
    pts = [rb(*p) for p, *_ in rings]
    for i, (_, a, b, jag) in enumerate(rings):
        lo, hi = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        axis = (hi - lo).normalized()
        u = (side_hint - axis * side_hint.dot(axis)).normalized()
        v = axis.cross(u)
        layer = []
        for du, dv, drop in octagon(a, b, jag):
            vert = bm.verts.new(pts[i] + u * du + v * dv + axis * drop)
            tags[vert] = bones
            layer.append(vert)
        layers.append(layer)
    for lower, upper in zip(layers, layers[1:]):
        for i in range(8):
            j = (i + 1) % 8
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bm.faces.new(list(reversed(layers[0])))
    bm.faces.new(layers[-1])


def block(bm, center, size, bones, tags):
    geom = bmesh.ops.create_cube(bm, size=1)
    c = rb(*center)
    for vert in geom["verts"]:
        vert.co = Vector((vert.co.x * size[0], vert.co.z * size[2], vert.co.y * size[1])) + c
        tags[vert] = bones


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def build_skin(bm, tags):
    # Head: skull loft from neck to crown, brow ridge in front.
    tube(bm, [((0, 4.0, -0.28), 0.22, 0.22, 0), ((0, 4.25, -0.36), 0.42, 0.45, 0),
              ((0, 4.6, -0.42), 0.56, 0.56, 0), ((0, 4.95, -0.45), 0.5, 0.5, 0),
              ((0, 5.15, -0.45), 0.3, 0.3, 0)], ["Head", "Neck"], tags)
    block(bm, (0, 4.75, -0.95), (0.95, 0.14, 0.14), ["Head"], tags)
    for side in ("Left", "Right"):
        s = J
        # Bare forearm out of the torn sleeve, then the hand.
        tube(bm, [(lerp(s[side + "Shoulder"], s[side + "Elbow"], 0.75), 0.17, 0.17, 0),
                  (s[side + "Elbow"], 0.16, 0.16, 0),
                  (lerp(s[side + "Elbow"], s[side + "Wrist"], 0.5), 0.15, 0.15, 0),
                  (s[side + "Wrist"], 0.13, 0.12, 0)],
             [side + "UpperArm", side + "LowerArm"], tags)
        tube(bm, [(s[side + "Wrist"], 0.16, 0.1, 0), (lerp(s[side + "Wrist"], s[side + "Fingers"], 0.5), 0.2, 0.1, 0),
                  (s[side + "Fingers"], 0.16, 0.07, 0.06)],
             [side + "LowerArm", side + "Hand"], tags)


def build_shirt(bm, tags):
    # Torso from waist to shoulders; ragged hem at the bottom.
    tube(bm, [((0, 2.3, 0.02), 0.78, 0.45, 0.14), ((0, 2.75, 0.0), 0.76, 0.46, 0),
              ((0, 3.25, -0.08), 0.86, 0.5, 0), ((0, 3.7, -0.18), 0.92, 0.48, 0),
              ((0, 4.0, -0.25), 0.55, 0.36, 0)], ["LowerTorso", "UpperTorso", "Neck"], tags)
    for side in ("Left", "Right"):
        sh, el = J[side + "Shoulder"], J[side + "Elbow"]
        tube(bm, [(lerp(sh, el, -0.08), 0.27, 0.27, 0), (lerp(sh, el, 0.45), 0.24, 0.24, 0),
                  (lerp(sh, el, 0.8), 0.25, 0.25, 0.09)],
             ["UpperTorso", side + "UpperArm"], tags)


def build_pants(bm, tags):
    tube(bm, [((0, 1.85, 0.05), 0.82, 0.46, 0), ((0, 2.15, 0.05), 0.84, 0.47, 0),
              ((0, 2.45, 0.02), 0.8, 0.46, 0)], ["LowerTorso", "LeftUpperLeg", "RightUpperLeg"], tags)
    for side in ("Left", "Right"):
        hip, knee, ankle = J[side + "Hip"], J[side + "Knee"], J[side + "Ankle"]
        tube(bm, [(lerp(hip, knee, -0.1), 0.34, 0.34, 0), (lerp(hip, knee, 0.5), 0.31, 0.31, 0),
                  (knee, 0.28, 0.28, 0), (lerp(knee, ankle, 0.5), 0.26, 0.26, 0),
                  (lerp(knee, ankle, 0.92), 0.27, 0.27, 0.07)],
             ["LowerTorso", side + "UpperLeg", side + "LowerLeg"], tags)


def build_dark(bm, tags):
    # Shoes and the hanging jaw.
    for side in ("Left", "Right"):
        ankle, toe = J[side + "Ankle"], J[side + "Toe"]
        tube(bm, [((ankle[0], 0.3, 0.18), 0.22, 0.17, 0), ((ankle[0], 0.14, 0.0), 0.27, 0.14, 0),
                  ((toe[0], 0.1, -0.5), 0.24, 0.1, 0)],
             [side + "LowerLeg", side + "Foot"], tags, side_hint=Vector((1, 0, 0)))
    tube(bm, [((0, 4.12, -0.55), 0.3, 0.12, 0), ((0, 4.05, -0.92), 0.36, 0.13, 0.04)],
         ["Head"], tags)


def build_eyes(bm, tags):
    for x in (-0.24, 0.24):
        block(bm, (x, 4.62, -0.98), (0.22, 0.12, 0.08), ["Head"], tags)


def seg_distance(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def make_piece(name, builder):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    tags = {}
    builder(bm, tags)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    order = list(bm.verts)
    bm.verts.index_update()
    weights = []
    for vert in order:
        scored = sorted((seg_distance(vert.co, *segments[b]), b) for b in tags[vert])[:2]
        raw = [(1 / (d * d * d * d + 1e-4), b) for d, b in scored]
        total = sum(w for w, _ in raw)
        weights.append([(b, w / total) for w, b in raw if w / total > 0.02])
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for index, influences in enumerate(weights):
        total = sum(w for _, w in influences)
        for bone, w in influences:
            group = obj.vertex_groups.get(bone) or obj.vertex_groups.new(name=bone)
            group.add([index], w / total, "REPLACE")
    obj.parent = rig
    obj.modifiers.new("Armature", "ARMATURE").object = rig
    return obj


PIECES = {
    "Runner_Skin": (build_skin, (122, 132, 110)),
    "Runner_Shirt": (build_shirt, (110, 52, 46)),
    "Runner_Pants": (build_pants, (55, 60, 72)),
    "Runner_Dark": (build_dark, (40, 25, 25)),
    "Runner_Eyes": (build_eyes, (255, 120, 20)),
}
material = bpy.data.materials.new("ZombieFlat")
material.diffuse_color = (0.5, 0.5, 0.5, 1)
pieces = []
for name, (builder, _) in PIECES.items():
    obj = make_piece(name, builder)
    obj.data.materials.append(material)
    pieces.append(obj)

manifest = {"blender": bpy.app.version_string, "bones": list(BONES), "meshes": {}}
for obj in pieces:
    obj.data.calc_loop_triangles()
    manifest["meshes"][obj.name] = {"triangles": len(obj.data.loop_triangles), "vertices": len(obj.data.vertices)}
manifest["triangles"] = sum(m["triangles"] for m in manifest["meshes"].values())

bpy.context.scene.unit_settings.system = "NONE"
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
for obj in pieces:
    obj.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(source / "zombies_skinned.blend"))
bpy.ops.export_scene.fbx(
    filepath=str(export / "zombies_skinned.fbx"), use_selection=True,
    object_types={"ARMATURE", "MESH"}, axis_forward="-Z", axis_up="Y",
    global_scale=0.01, apply_unit_scale=False, bake_anim=False,
    use_mesh_modifiers=False, add_leaf_bones=False, use_armature_deform_only=True,
    primary_bone_axis="Y", secondary_bone_axis="X",
)
(export / "zombies_skinned.json").write_text(json.dumps(manifest, indent=2) + "\n")

# ---- Preview: rest pose next to a test pose (stagger step, arms reaching) to show the
# skinning bends cleanly at knees, elbows, waist and neck.
def srgb(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


for obj in pieces:
    rgb = PIECES[obj.name][1]
    mat = bpy.data.materials.new("Preview_" + obj.name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    color = (*[srgb(v) for v in rgb], 1)
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.9
    if obj.name == "Runner_Eyes":
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = 6
    obj.data.materials[0] = mat

posed = rig.copy()
bpy.context.collection.objects.link(posed)
posed.location.x = -4.5
for obj in pieces:
    twin = obj.copy()
    twin.parent = posed
    twin.modifiers["Armature"].object = posed
    bpy.context.collection.objects.link(twin)
TEST_POSE = {  # bone → rotation (degrees) about the bone's local X: bends forward/back
    "LeftUpperLeg": 30, "LeftLowerLeg": -45, "RightUpperLeg": -20, "RightLowerLeg": -15,
    "LeftUpperArm": 70, "LeftLowerArm": 25, "RightUpperArm": 40, "RightLowerArm": 35,
    "UpperTorso": 12, "Neck": 15, "Head": -10,
}
for bone, deg in TEST_POSE.items():
    pb = posed.pose.bones[bone]
    pb.rotation_mode = "XYZ"
    pb.rotation_euler = (math.radians(deg), 0, 0)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 32
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
world = bpy.data.worlds.new("Preview")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.1, 0.1, 0.12, 1)
scene.world = world
sun = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
sun.data.energy = 3.5
sun.rotation_euler = (math.radians(55), 0, math.radians(-25))
bpy.context.collection.objects.link(sun)
cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 9.5
cam.location = (-2.25 + 7, -12, 4.2)
cam.rotation_euler = (math.radians(86), 0, math.radians(30))
bpy.context.collection.objects.link(cam)
scene.camera = cam
scene.render.filepath = str(export / "zombies_skinned.preview.png")
bpy.ops.render.render(write_still=True)
print("ZOMBIES_SKINNED_OK " + json.dumps(manifest["meshes"]))
