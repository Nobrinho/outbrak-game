"""Low-poly zombie body parts (16 shared meshes) + a preview render of the 4 kinds.

Each mesh replaces one part of src/shared/Art/ZombieRigs.luau and is authored at that part's
exact size, centred, so the game can set MeshPart.Size directly — the importer's unit scale
doesn't matter. Left/right parts share one symmetric mesh (Arm, Sleeve, Leg, Plate, Fist,
Trap); Pustule serves all three pustules.

Axes: the weapon import showed that Blender -Y arrives as Roblox -Z (front) and Blender -X as
Roblox +X, so a point at Roblox (x, y, z) is modelled at Blender (-x, z, y) and parts face
Blender -Y. Sizes: Roblox (sx, sy, sz) are Blender dimensions (sx, sz, sy).
"""
import json
import math
from pathlib import Path
import random
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
rng = random.Random(7)


def ring(a, b, jag=0.0):
    """Octagon (rounded rectangle) with half extents a, b; `jag` drops every other vertex."""
    pts = [(a, 0.55 * b), (0.55 * a, b), (-0.55 * a, b), (-a, 0.55 * b),
           (-a, -0.55 * b), (-0.55 * a, -b), (0.55 * a, -b), (a, -0.55 * b)]
    return [(x, y, -jag if i % 2 == 0 else 0.0) for i, (x, y) in enumerate(pts)]


def loft(bm, rings, axis="Z", offset=(0, 0, 0)):
    """Connects octagon rings stacked along `axis`. rings = [(position, a, b, jag), ...]."""
    ox, oy, oz = offset
    layers = []
    for position, a, b, jag in rings:
        layer = []
        for u, v, drop in ring(a, b, jag):
            if axis == "Z":  # ring in XY (a = x, b = y/depth), stacked up
                co = (ox + u, oy + v, oz + position + drop)
            else:  # axis Y: ring in XZ (a = x, b = z/height), stacked front-to-back
                co = (ox + u, oy + position + drop, oz + v)
            layer.append(bm.verts.new(co))
        layers.append(layer)
    for lower, upper in zip(layers, layers[1:]):
        for i in range(8):
            j = (i + 1) % 8
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bm.faces.new(list(reversed(layers[0])))
    bm.faces.new(layers[-1])


def ico(bm, radius, offset=(0, 0, 0), lumpy=0.0):
    geom = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius)
    for v in geom["verts"]:
        v.co *= 1 + rng.uniform(-lumpy, lumpy)
        v.co += Vector(offset)


def box(bm, size, offset=(0, 0, 0)):
    geom = bmesh.ops.create_cube(bm, size=1)
    for v in geom["verts"]:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(offset)


# Each builder draws roughly at size; normalisation then fits the exact Roblox size.
def torso(bm):
    loft(bm, [(-0.85, 0.66, 0.42, 0.14), (-0.3, 0.74, 0.47, 0), (0.45, 0.9, 0.5, 0), (0.85, 0.8, 0.42, 0)])

def hips(bm):
    loft(bm, [(-0.3, 0.8, 0.45, 0), (0.3, 0.85, 0.47, 0)])

def head(bm):
    loft(bm, [(-0.57, 0.4, 0.42, 0), (-0.3, 0.54, 0.55, 0), (0.25, 0.58, 0.56, 0), (0.57, 0.45, 0.46, 0)])
    box(bm, (0.95, 0.18, 0.12), (0, -0.55, 0.16))  # brow ridge, front (-Y)

def jaw(bm):
    loft(bm, [(-0.14, 0.32, 0.22, 0.05), (0.14, 0.4, 0.25, 0)])

def eyes(bm):
    for x in (-0.25, 0.25):
        loft(bm, [(-0.05, 0.16, 0.09, 0), (0.05, 0.14, 0.08, 0)], axis="Y", offset=(x, 0, 0))

def arm(bm):
    # Shoulder at +Y (back), hand at -Y (front).
    loft(bm, [(1.0, 0.22, 0.22, 0), (0.0, 0.19, 0.19, 0), (-0.72, 0.16, 0.16, 0),
              (-0.8, 0.22, 0.2, 0), (-1.0, 0.2, 0.12, 0.06)], axis="Y")

def sleeve(bm):
    loft(bm, [(0.3, 0.28, 0.28, 0), (-0.3, 0.3, 0.3, 0.08)], axis="Y")

def leg(bm):
    loft(bm, [(1.0, 0.33, 0.33, 0), (0.0, 0.29, 0.29, 0), (-0.75, 0.26, 0.26, 0)])
    box(bm, (0.55, 0.85, 0.28), (0, -0.18, -0.88))  # foot pointing forward

def plate(bm):
    loft(bm, [(-0.25, 0.5, 0.6, 0), (0.08, 0.48, 0.58, 0), (0.25, 0.3, 0.42, 0)])

def chest(bm):
    loft(bm, [(0.15, 0.95, 0.62, 0), (-0.12, 0.9, 0.58, 0), (-0.15, 0.55, 0.35, 0)], axis="Y")

def helmet(bm):
    loft(bm, [(-0.3, 0.66, 0.66, 0), (0.0, 0.63, 0.63, 0), (0.18, 0.5, 0.5, 0), (0.3, 0.24, 0.24, 0)])
    box(bm, (1.1, 0.25, 0.14), (0, -0.62, -0.18))  # visor rim

def belly(bm):
    ico(bm, 0.95, lumpy=0.07)

def pustule(bm):
    ico(bm, 0.5, lumpy=0.05)

def fist(bm):
    loft(bm, [(-0.48, 0.42, 0.44, 0), (0.3, 0.48, 0.48, 0), (0.48, 0.38, 0.4, 0)])
    box(bm, (0.85, 0.2, 0.22), (0, -0.48, 0.18))  # knuckle ridge

def hunch(bm):
    loft(bm, [(-0.5, 0.6, 0.4, 0), (0.0, 0.8, 0.5, 0), (0.5, 0.5, 0.33, 0)])

def trap(bm):
    loft(bm, [(-0.3, 0.35, 0.45, 0), (0.3, 0.18, 0.28, 0)])


# Mesh name → (builder, Roblox size of the part it replaces).
MESHES = {
    "Torso": (torso, (1.8, 1.7, 1)),
    "Hips": (hips, (1.7, 0.6, 0.95)),
    "Head": (head, (1.15, 1.15, 1.15)),
    "Jaw": (jaw, (0.8, 0.28, 0.5)),
    "Eyes": (eyes, (0.85, 0.2, 0.1)),
    "Arm": (arm, (0.45, 0.45, 2)),
    "Sleeve": (sleeve, (0.58, 0.58, 0.6)),
    "Leg": (leg, (0.7, 2, 0.7)),
    "Plate": (plate, (1, 0.5, 1.2)),
    "Chest": (chest, (1.9, 1.3, 0.3)),
    "Helmet": (helmet, (1.3, 0.6, 1.3)),
    "Belly": (belly, (1.9, 1.9, 1.9)),
    "Pustule": (pustule, (0.5, 0.5, 0.5)),
    "Fist": (fist, (0.95, 0.95, 0.95)),
    "Hunch": (hunch, (1.6, 1, 1)),
    "Trap": (trap, (0.7, 0.6, 0.9)),
}

material = bpy.data.materials.new("ZombieFlat")
material.diffuse_color = (0.5, 0.5, 0.5, 1)


def build(name, builder, size):
    mesh = bpy.data.meshes.new("Zombie_" + name)
    bm = bmesh.new()
    builder(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Fit the exact part size (Roblox x, y, z → Blender x, z, y) and centre it.
    lo = Vector([min(v.co[i] for v in bm.verts) for i in range(3)])
    hi = Vector([max(v.co[i] for v in bm.verts) for i in range(3)])
    target = Vector((size[0], size[2], size[1]))
    for v in bm.verts:
        for i in range(3):
            v.co[i] = (v.co[i] - (lo[i] + hi[i]) / 2) * target[i] / max(hi[i] - lo[i], 1e-6)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    mesh.materials.append(material)
    obj = bpy.data.objects.new("Zombie_" + name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


objects = [build(name, *spec) for name, spec in MESHES.items()]
manifest = {"blender": bpy.app.version_string, "meshes": {}}
for obj in objects:
    obj.data.calc_loop_triangles()
    manifest["meshes"][obj.name] = {
        "triangles": len(obj.data.loop_triangles),
        "size_studs": [round(obj.dimensions.x, 3), round(obj.dimensions.z, 3), round(obj.dimensions.y, 3)],
    }

bpy.context.scene.unit_settings.system = "NONE"
bpy.ops.object.select_all(action="DESELECT")
for obj in objects:
    obj.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(source / "zombies.blend"))
bpy.ops.export_scene.fbx(
    filepath=str(export / "zombies.fbx"), use_selection=True,
    object_types={"MESH"}, axis_forward="-Z", axis_up="Y",
    global_scale=1.0, apply_unit_scale=False, bake_anim=False,
    use_mesh_modifiers=True, add_leaf_bones=False,
)
(export / "zombies.json").write_text(json.dumps(manifest, indent=2) + "\n")

# ---- Preview: assemble the four kinds from the same specs the game uses (ZombieRigs.luau).
BASE = [
    ("Leg", "pants", (-0.45, 1, 0)), ("Leg", "pants", (0.45, 1, 0)),
    ("Hips", "pants", (0, 2.15, 0)), ("Torso", "shirt", (0, 3.25, -0.1)),
    ("Head", "skin", (0, 4.6, -0.3)), ("Jaw", "dark", (0, 4.08, -0.65)),
    ("Eyes", "eyes", (0, 4.75, -0.88)),
    ("Arm", "skin", (-1.12, 3.75, -0.85)), ("Arm", "skin", (1.12, 3.75, -0.85)),
    ("Sleeve", "shirt", (-1.12, 3.75, -0.1)), ("Sleeve", "shirt", (1.12, 3.75, -0.1)),
]
KINDS = {
    "Runner": (1.0, {"skin": (122, 132, 110), "shirt": (110, 52, 46), "pants": (55, 60, 72)}, []),
    "Bull": (1.5, {"skin": (110, 104, 96), "shirt": (58, 62, 72), "pants": (45, 48, 55)}, [
        ("Plate", "accent", (-1.1, 4.15, 0)), ("Plate", "accent", (1.1, 4.15, 0)),
        ("Chest", "accent", (0, 3.3, -0.65)), ("Helmet", "accent", (0, 5.05, -0.3))]),
    "Creeper": (1.2, {"skin": (160, 176, 70), "shirt": (104, 118, 40), "pants": (60, 64, 40)}, [
        ("Belly", "skin", (0, 2.95, -0.4)), ("Pustule", "glow", (0.6, 3.4, -1.25)),
        ("Pustule", "glow", (-0.5, 2.6, -1.3)), ("Pustule", "glow", (0.4, 5, -0.6))]),
    "Brute": (2.4, {"skin": (104, 92, 84), "shirt": (58, 44, 38), "pants": (45, 38, 34)}, [
        ("Fist", "skin", (-1.12, 3.75, -2)), ("Fist", "skin", (1.12, 3.75, -2)),
        ("Hunch", "shirt", (0, 4.15, 0.5)), ("Trap", "skin", (-0.7, 4.15, 0)), ("Trap", "skin", (0.7, 4.15, 0))]),
}
FIXED = {"eyes": (255, 120, 20), "dark": (40, 25, 25), "glow": (170, 255, 60), "accent": (70, 74, 80)}
PUSTULE_SIZES = [0.5, 0.4, 0.35]


def srgb(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def tone_material(rgb, glow):
    mat = bpy.data.materials.new("Preview")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    color = (*[srgb(v) for v in rgb], 1)
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.9
    if glow:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = 6
    return mat


x_cursor = 0.0
for kind, (scale, palette, extras) in KINDS.items():
    pustule = 0
    for mesh_name, tone, offset in BASE + extras:
        src = bpy.data.objects["Zombie_" + mesh_name]
        obj = bpy.data.objects.new(f"Preview_{kind}_{mesh_name}", src.data.copy())
        rgb = FIXED.get(tone) or palette[tone]
        obj.data.materials.clear()
        obj.data.materials.append(tone_material(rgb, tone in ("eyes", "glow")))
        s = scale
        if mesh_name == "Pustule":
            s = scale * PUSTULE_SIZES[pustule] / 0.5
            pustule += 1
        obj.scale = (s, s, s)
        x, y, z = offset
        obj.location = (x_cursor + (-x) * scale, z * scale, y * scale)
        bpy.context.collection.objects.link(obj)
    x_cursor -= 2.6 * scale + 2.5  # next zombie to the (Roblox) right

for obj in objects:
    obj.hide_render = True

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 32
scene.render.resolution_x = 1600
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
cam.data.ortho_scale = 27
center_x = x_cursor / 2 + 2
cam.location = (center_x + 9, -16, 9.5)
cam.rotation_euler = (math.radians(80), 0, math.radians(30))  # front three-quarter view
bpy.context.collection.objects.link(cam)
scene.camera = cam
scene.render.filepath = str(export / "zombies.preview.png")
bpy.ops.render.render(write_still=True)
print("ZOMBIES_OK " + json.dumps({k: v["triangles"] for k, v in manifest["meshes"].items()}))
