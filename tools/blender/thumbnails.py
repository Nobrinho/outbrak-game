"""Store art for the experience page: a 1920x1080 thumbnail and a 512x512 icon.

Built only from the game's own meshes (assets/source/zombies.blend, props.blend, weapons.blend,
made by the other scripts in this folder), so run those first. The scene: a survivor behind a
barricade at dusk, the horde charging out of the corn, the pickup and the tractor on the
flanks. Zombies are assembled from the same part offsets as ZombieRigs.luau; axes as in
zombies.py (Roblox (x, y, z) → Blender (-x, z, y), fronts facing Blender -Y).

Outputs assets/export/store_thumbnail.png and assets/export/store_icon.png.
"""
import math
from pathlib import Path
import random
import sys

import bpy
from mathutils import Matrix, Vector

root = Path(sys.argv[sys.argv.index("--") + 1])
source = root / "assets/source"
export = root / "assets/export"
bpy.ops.wm.read_factory_settings(use_empty=True)
rng = random.Random(25)


def append(blend, prefixes):
    with bpy.data.libraries.load(str(source / blend), link=False) as (src, dst):
        dst.objects = [n for n in src.objects if n.startswith(prefixes)]
    library = {}
    for obj in dst.objects:
        library[obj.name] = obj  # not linked to the scene: used as mesh sources
    return library


zombie_parts = append("zombies.blend", ("Zombie_",))
props = append("props.blend", ("Tractor_", "Truck_", "Crate_"))
weapons = append("weapons.blend", ("AK47_",))


def srgb(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


materials = {}


def material(rgb, glow=0.0, rough=0.85, metal=0.0):
    key = (rgb, glow, rough, metal)
    if key in materials:
        return materials[key]
    mat = bpy.data.materials.new("M")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    color = (*[srgb(v) for v in rgb], 1)
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if glow:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = glow
    materials[key] = mat
    return mat


def place(src, matrix, mat):
    obj = bpy.data.objects.new(src.name + "_i", src.data.copy())
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    obj.matrix_world = matrix
    bpy.context.collection.objects.link(obj)
    return obj


def box(size, location, mat, rot=(0, 0, 0)):
    """Box in Blender units/axes (x, y depth, z up)."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location, rotation=rot)
    obj = bpy.context.active_object
    obj.scale = size
    obj.data.materials.append(mat)
    return obj


def to_b(v):
    x, y, z = v
    return Vector((-x, z, y))


# ---- Zombies (offsets and palettes mirror ZombieRigs.luau / zombies.py) ----
BASE = [
    ("Leg", "pants", (-0.45, 1, 0), "LegL"), ("Leg", "pants", (0.45, 1, 0), "LegR"),
    ("Hips", "pants", (0, 2.15, 0), None), ("Torso", "shirt", (0, 3.25, -0.1), None),
    ("Head", "skin", (0, 4.6, -0.3), None), ("Jaw", "dark", (0, 4.08, -0.65), None),
    ("Eyes", "eyes", (0, 4.75, -0.88), None),
    ("Arm", "skin", (-1.12, 3.75, -0.85), "ArmL"), ("Arm", "skin", (1.12, 3.75, -0.85), "ArmR"),
    ("Sleeve", "shirt", (-1.12, 3.75, -0.1), "ArmL"), ("Sleeve", "shirt", (1.12, 3.75, -0.1), "ArmR"),
]
PIVOTS = {"ArmL": (-1.12, 3.75, 0), "ArmR": (1.12, 3.75, 0), "LegL": (-0.45, 2, 0), "LegR": (0.45, 2, 0)}
KINDS = {
    "Runner": (1.0, [], [
        {"skin": (122, 132, 110), "shirt": (110, 52, 46), "pants": (55, 60, 72)},
        {"skin": (118, 126, 104), "shirt": (64, 78, 96), "pants": (70, 62, 50)},
        {"skin": (128, 134, 116), "shirt": (150, 140, 110), "pants": (50, 52, 58)},
        {"skin": (112, 122, 100), "shirt": (82, 96, 60), "pants": (60, 56, 64)},
    ]),
    "Bull": (1.5, [
        ("Plate", "accent", (-1.1, 4.15, 0), "ArmL"), ("Plate", "accent", (1.1, 4.15, 0), "ArmR"),
        ("Chest", "accent", (0, 3.3, -0.65), None), ("Helmet", "accent", (0, 5.05, -0.3), None),
    ], [{"skin": (110, 104, 96), "shirt": (58, 62, 72), "pants": (45, 48, 55)}]),
    "Creeper": (1.2, [
        ("Belly", "skin", (0, 2.95, -0.4), None), ("Pustule", "glow", (0.6, 3.4, -1.25), None),
        ("Pustule", "glow", (-0.5, 2.6, -1.3), None), ("Pustule", "glow", (0.4, 5, -0.6), None),
    ], [{"skin": (160, 176, 70), "shirt": (104, 118, 40), "pants": (60, 64, 40)}]),
    "Brute": (2.4, [
        ("Fist", "skin", (-1.12, 3.75, -2), "ArmL"), ("Fist", "skin", (1.12, 3.75, -2), "ArmR"),
        ("Hunch", "shirt", (0, 4.15, 0.5), None), ("Trap", "skin", (-0.7, 4.15, 0), None),
        ("Trap", "skin", (0.7, 4.15, 0), None),
    ], [{"skin": (104, 92, 84), "shirt": (58, 44, 38), "pants": (45, 38, 34)}]),
}
FIXED = {"eyes": (255, 120, 20), "dark": (40, 25, 25), "glow": (170, 255, 60), "accent": (70, 74, 80)}


def zombie(kind, x, y, yaw_deg=0.0, stride=0.0, reach=0.0):
    scale, extras, palettes = KINDS[kind]
    palette = rng.choice(palettes)
    base = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
    for mesh, tone, offset, role in BASE + extras:
        rgb = FIXED.get(tone) or palette[tone]
        glow = 12 if tone == "eyes" else 5 if tone == "glow" else 0
        local = Matrix.Translation(to_b(offset) * scale) @ Matrix.Scale(scale, 4)
        if role:
            angle = 0.0
            if role == "LegL":
                angle = stride
            elif role == "LegR":
                angle = -stride
            else:
                angle = reach + (stride if role == "ArmL" else -stride) * 0.3
            pivot = to_b(PIVOTS[role]) * scale
            local = Matrix.Translation(pivot) @ Matrix.Rotation(angle, 4, "X") @ Matrix.Translation(-pivot) @ local
        place(zombie_parts["Zombie_" + mesh], base @ local, material(rgb, glow))


# ---- Props (each set of tone meshes is placed from its origin marker) ----
PROP_TONES = {
    "Tractor": {"Paint": (124, 72, 44), "Dark": (43, 38, 34), "Tire": (28, 28, 30), "Rim": (176, 146, 74)},
    "Truck": {"Paint": (113, 44, 31), "Glass": (30, 36, 42), "Tire": (28, 28, 30), "Chrome": (82, 86, 86),
              "Dark": (43, 38, 34), "Lamp": (174, 161, 119), "Tail": (120, 32, 26)},
    "Crate": {"Wood": (108, 94, 77), "Frame": (72, 60, 48)},
}
BODY_HEIGHT = {"Tractor": 2.6, "Truck": 2.2, "Crate": 1.5}


def prop(name, x, y, yaw_deg, roll_deg=0.0, lamp_glow=0.0):
    origin = props[name + "_Origin"].matrix_world.to_translation()
    at = Matrix.Translation((x, y, BODY_HEIGHT[name])) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z") \
        @ Matrix.Rotation(math.radians(roll_deg), 4, "Y")
    for tone, rgb in PROP_TONES[name].items():
        src = props.get(f"{name}_{tone}")
        if src:
            glow = lamp_glow if tone == "Lamp" else 0
            rough = 0.25 if tone in ("Glass", "Chrome", "Lamp") else 0.85
            place(src, at @ Matrix.Translation(-origin) @ src.matrix_world, material(rgb, glow, rough))


# ---- Survivor: a blocky Roblox-style avatar holding the AK-47, back to the camera ----
def survivor(x, y):
    skin = material((234, 184, 146))
    shirt = material((52, 60, 44))
    pants = material((40, 40, 46))
    vest = material((30, 34, 30))
    box((2, 1, 2), (x, y, 4), shirt)
    box((2.05, 1.05, 1.2), (x, y, 4.3), vest)
    box((1.2, 1.2, 1.2), (x, y, 5.6), skin)
    box((1.25, 1.25, 0.35), (x, y, 6.25), material((24, 24, 26)))  # cap
    for side in (-1, 1):
        box((1, 1, 2), (x + side * 0.5, y, 1), pants)
    # Arms raised forward into the aim pose, both hands on the rifle.
    box((1, 1, 2), (x + 1.3, y + 0.9, 4.6), shirt, rot=(math.radians(-80), 0, math.radians(15)))
    box((1, 1, 2), (x - 1.1, y + 1.3, 4.6), shirt, rot=(math.radians(-80), 0, math.radians(-25)))
    grip = weapons["AK47_Grip"].matrix_world.to_translation()
    gun = Matrix.Translation((x + 0.3, y + 2.2, 4.75)) @ Matrix.Scale(1.5, 4) @ Matrix.Translation(-grip)
    for tone, rgb, metal in (("Metal", (42, 44, 48), 0.6), ("Steel", (150, 154, 160), 0.6),
                             ("Wood", (110, 72, 44), 0.0), ("WoodDark", (80, 52, 34), 0.0)):
        src = weapons.get(f"AK47_{tone}")
        if src:
            place(src, gun @ src.matrix_world, material(rgb, 0, 0.5, metal))
    # Muzzle flash: a hot light at the barrel that rakes across the front of the horde.
    flash = bpy.data.objects.new("Flash", bpy.data.lights.new("Flash", "POINT"))
    flash.data.energy = 2500
    flash.data.color = (1.0, 0.7, 0.35)
    flash.data.shadow_soft_size = 0.3
    flash.location = (x + 0.3, y + 6.6, 5.0)
    bpy.context.collection.objects.link(flash)


# ---- Set ----
ground = box((400, 400, 1), (0, 60, -0.5), material((52, 42, 34)))
wood = material((104, 92, 80))
dark_wood = material((70, 58, 46))
for i in range(-6, 7):  # barricade: posts and planks in front of the survivor
    box((0.35, 0.35, 3.2), (i * 2.2, 2, 1.6), dark_wood)
for z, tilt in ((0.9, 3), (1.9, -4), (2.8, 2)):
    box((28, 0.25, 0.6), (0, 1.8, z), wood, rot=(0, math.radians(tilt), 0))
corn = material((150, 128, 60))
for i in range(260):  # corn stalks hiding the far horde
    cx, cy = rng.uniform(-80, 80), rng.uniform(48, 110)
    h = rng.uniform(4.5, 7)
    box((0.25, 0.25, h), (cx, cy, h / 2), corn, rot=(rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), 0))
house = material((80, 70, 62))
box((20, 14, 9), (-34, 70, 4.5), house)  # farmhouse silhouette with lit windows
box((22, 16, 1), (-34, 70, 9.5), material((40, 46, 52)), rot=(math.radians(8), 0, 0))
for wx in (-40, -34, -28):
    box((2.2, 0.2, 2.6), (wx, 62.9, 4.5), material((255, 170, 70), glow=8))
silo = bpy.ops.mesh.primitive_cylinder_add(radius=6, depth=26, location=(42, 80, 13))
bpy.context.active_object.data.materials.append(material((110, 104, 96)))

# The horde: Runners up front, a Bull and a glowing Creeper among them, the Brute at the back.
for i in range(62):
    x = rng.uniform(-20, 20)
    y = rng.uniform(8, 50) + abs(x) * 0.25
    zombie("Runner", x, y, rng.uniform(-25, 25), rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.15))
zombie("Runner", -2.5, 5.2, 8, 0.45, -0.35)
zombie("Runner", 3.8, 6.0, -12, -0.4, -0.2)
zombie("Bull", -9, 13, 15, 0.3)
zombie("Creeper", 7, 10, -10, -0.3)
zombie("Creeper", -15, 26, 20, 0.2)
zombie("Brute", 2, 40, -5, 0.25, -0.2)
prop("Truck", 19, 20, 120, 4, lamp_glow=6)
prop("Tractor", -22, 34, -30)
prop("Crate", -6, -3, 12)
prop("Crate", -9.2, -2.5, -6)
prop("Crate", -7.4, -2.8, 20)
survivor(2.5, -6)

# ---- World, lights, render ----
scene = bpy.context.scene
world = bpy.data.worlds.new("Dusk")
world.use_nodes = True
nodes = world.node_tree.nodes
links = world.node_tree.links
background = nodes["Background"]
sky = nodes.new("ShaderNodeTexSky")
sky.sky_type = "NISHITA"
sky.sun_elevation = math.radians(1.5)
sky.sun_rotation = math.radians(15)
sky.air_density = 3.0
sky.dust_density = 6.0
links.new(sky.outputs["Color"], background.inputs["Color"])
background.inputs["Strength"].default_value = 0.6
fog = nodes.new("ShaderNodeVolumePrincipled")
fog.inputs["Color"].default_value = (0.9, 0.45, 0.3, 1)
fog.inputs["Density"].default_value = 0.005
links.new(fog.outputs["Volume"], nodes["World Output"].inputs["Volume"])
scene.world = world

sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
sun.data.energy = 2.2
sun.data.color = (1.0, 0.55, 0.32)
sun.rotation_euler = (math.radians(80), 0, math.radians(200))  # low, from behind the horde
bpy.context.collection.objects.link(sun)
rim = bpy.data.objects.new("Rim", bpy.data.lights.new("Rim", "AREA"))
rim.data.energy = 900
rim.data.size = 6
rim.data.color = (0.3, 0.85, 1.0)  # cyan player highlight (art direction)
rim.location = (8, 2, 9)
rim.rotation_euler = (math.radians(-60), 0, math.radians(-120))
bpy.context.collection.objects.link(rim)
fill = bpy.data.objects.new("Fill", bpy.data.lights.new("Fill", "AREA"))
fill.data.energy = 1500
fill.data.size = 30
fill.data.color = (1.0, 0.6, 0.4)
fill.location = (0, -18, 14)
fill.rotation_euler = (math.radians(55), 0, 0)
bpy.context.collection.objects.link(fill)

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.cycles.volume_step_rate = 4
scene.view_settings.view_transform = "AgX"
scene.view_settings.look = "AgX - Punchy"


def camera(name, location, target, lens):
    cam = bpy.data.objects.new(name, bpy.data.cameras.new(name))
    cam.data.lens = lens
    cam.location = location
    direction = Vector(target) - Vector(location)
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    bpy.context.collection.objects.link(cam)
    return cam


def title(cam, text, size, offset, glow_rgb):
    curve = bpy.data.curves.new("Title", "FONT")
    curve.body = text
    curve.size = size
    curve.extrude = 0.02
    curve.align_x = "CENTER"
    if FONT.exists():
        curve.font = bpy.data.fonts.load(str(FONT))
    obj = bpy.data.objects.new("Title", curve)
    obj.data.materials.append(material(glow_rgb, glow=3))
    obj.parent = cam
    obj.location = offset
    bpy.context.collection.objects.link(obj)
    return obj


# Bold display face when the system has it (macOS); Blender's own font otherwise.
FONT = Path("/System/Library/Fonts/Supplemental/Impact.ttf")
quick = "--quick" in sys.argv
scene.view_settings.exposure = 0.6
thumb = camera("Thumb", (-2.5, -15.5, 7.8), (4, 22, 3.6), 32)
title(thumb, "WWZ", 0.42, (0, 0.62, -3), (255, 204, 0))
title(thumb, "SOBREVIVA AO APOCALIPSE ZUMBI", 0.15, (0, 0.43, -3), (240, 240, 240))
scene.camera = thumb
scene.render.resolution_x, scene.render.resolution_y = (960, 540) if quick else (1920, 1080)
scene.render.filepath = str(export / "store_thumbnail.png")
bpy.ops.render.render(write_still=True)

for obj in list(bpy.data.objects):
    if obj.name.startswith("Title"):
        obj.hide_render = True
icon = camera("Icon", (-1.2, -4.2, 6.6), (-2.3, 5.2, 4.9), 50)
title(icon, "WWZ", 0.3, (0, -0.33, -1.6), (255, 204, 0))
scene.camera = icon
scene.render.resolution_x = scene.render.resolution_y = 256 if quick else 512
scene.render.filepath = str(export / "store_icon.png")
bpy.ops.render.render(write_still=True)
print("THUMBNAILS_OK")
