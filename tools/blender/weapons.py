"""Low-poly weapon set for Roblox Swarm: Outbreak (7 weapons), FBX + preview renders.

Conventions (docs/art/PIPELINE.md): 1 Blender unit = 1 stud, Z up, flat faces. Each weapon is
split into one mesh per colour tone (<Weapon>_Metal, _Steel, _Wood, _WoodDark); Roblox recolours
them by name (and the Survivor Pack turns _Metal/_Steel gold). Magazines are their own mesh,
<Weapon>_Mag (metal colour), so the game can pull them out of the gun while reloading. Two tiny marker cubes per weapon,
<Weapon>_Grip at the hand and <Weapon>_Muzzle at the barrel tip, let the game find the grip,
measure the import scale and start tracers.

Shapes are written in Roblox axes (x right, y up, -z forward) and converted with
Blender = (x, -z, y), so the barrel points along Blender +Y, which the FBX export
(forward -Z, up Y) turns back into Roblox -Z. Weapons sit side by side along X in the file;
the game locates each one by its Grip marker, so the spacing doesn't matter in Roblox.
"""
import json
import math
from pathlib import Path
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

root = Path(sys.argv[sys.argv.index("--") + 1])
source = root / "assets/source"
export = root / "assets/export"
source.mkdir(parents=True, exist_ok=True)
export.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

# Tones match src/shared/Art/WeaponModels.luau (sRGB 0-255).
TONES = {
    "Metal": (42, 44, 48),
    "Steel": (150, 154, 160),
    "Wood": (110, 72, 44),
    "WoodDark": (80, 52, 34),
    "Mag": (42, 44, 48),
    "Marker": (255, 0, 255),
}
SPACING = 5.0


def srgb_to_linear(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


materials = {}
for tone, rgb in TONES.items():
    mat = bpy.data.materials.new(tone)
    linear = (*[srgb_to_linear(v) for v in rgb], 1)
    mat.diffuse_color = linear
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = linear
    bsdf.inputs["Roughness"].default_value = 0.55 if tone in ("Metal", "Steel", "Mag") else 0.85
    bsdf.inputs["Metallic"].default_value = 0.6 if tone in ("Metal", "Steel", "Mag") else 0
    materials[tone] = mat


def to_blender(v):
    x, y, z = v
    return Vector((x, -z, y))


def rotation_matrix(deg):
    rx, ry, rz = (math.radians(a) for a in deg)
    # Roblox rotation (X then Y then Z, as CFrame.Angles); the same signs hold in Blender
    # because the axis swap keeps handedness (see module docstring).
    # Roblox Y is Blender Z and Roblox Z is Blender -Y, so Rx·Ry·Rz becomes X(rx)·Z(ry)·Y(-rz).
    return (
        Matrix.Rotation(rx, 4, "X")
        @ Matrix.Rotation(ry, 4, "Z")
        @ Matrix.Rotation(-rz, 4, "Y")
    )


class Builder:
    """Collects primitives per tone for one weapon, then joins them into one mesh per tone."""

    def __init__(self, name, origin_x):
        self.name = name
        self.offset = Vector((origin_x, 0, 0))
        self.parts = {}

    def _add(self, tone, obj, center, rot):
        obj.matrix_world = Matrix.Translation(self.offset + to_blender(center)) @ rotation_matrix(rot)
        bpy.context.view_layer.update()
        self.parts.setdefault(tone, []).append(obj)

    def box(self, tone, size, center, rot=(0, 0, 0), bevel=0.04, taper=None):
        """Box of Roblox size (x, y, z). `taper` scales the -z (front) end's x/y."""
        sx, sy, sz = size
        mesh = bpy.data.meshes.new("tmp")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        bmesh.ops.scale(bm, vec=Vector((sx, sz, sy)), verts=bm.verts)
        if taper:
            tx, ty = taper
            for v in bm.verts:
                if v.co.y > 0:  # Blender +Y is the front (-z in Roblox)
                    v.co.x *= tx
                    v.co.z *= ty
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", profile=0.5)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("tmp", mesh)
        bpy.context.collection.objects.link(obj)
        self._add(tone, obj, center, rot)
        return obj

    def cylinder(self, tone, radius, length, center, rot=(0, 0, 0), sides=8, radius_front=None):
        """Cylinder along Roblox Z (the barrel axis)."""
        mesh = bpy.data.meshes.new("tmp")
        bm = bmesh.new()
        bmesh.ops.create_cone(
            bm, cap_ends=True, segments=sides, radius1=radius,
            radius2=radius if radius_front is None else radius_front, depth=length,
        )
        # Cone axis is Blender Z; turn it to Blender +Y (Roblox -Z), front end = radius2.
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new("tmp", mesh)
        bpy.context.collection.objects.link(obj)
        self._add(tone, obj, center, rot)
        return obj

    def marker(self, label, center):
        mesh = bpy.data.meshes.new("tmp")
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.1)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(f"{self.name}_{label}", mesh)
        obj.data.materials.append(materials["Marker"])
        bpy.context.collection.objects.link(obj)
        obj.location = self.offset + to_blender(center)
        return obj

    def finish(self, muzzle):
        objects = []
        for tone, pieces in self.parts.items():
            bpy.ops.object.select_all(action="DESELECT")
            for piece in pieces:
                piece.select_set(True)
            bpy.context.view_layer.objects.active = pieces[0]
            if len(pieces) > 1:
                bpy.ops.object.join()
            obj = bpy.context.view_layer.objects.active
            obj.name = f"{self.name}_{tone}"
            obj.data.name = obj.name
            bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
            obj.data.materials.clear()
            obj.data.materials.append(materials[tone])
            for poly in obj.data.polygons:
                poly.use_smooth = False
            objects.append(obj)
        grip = self.marker("Grip", (0, 0, 0))
        tip = self.marker("Muzzle", muzzle)
        return objects, grip, tip


def pistol(b):
    b.box("Metal", (0.27, 0.32, 1.05), (0, 0.22, -0.32), bevel=0.05)  # slide
    b.box("Metal", (0.24, 0.16, 0.8), (0, 0.02, -0.22))  # frame
    b.box("Metal", (0.24, 0.62, 0.34), (0, -0.25, 0.05), rot=(-14, 0, 0), bevel=0.05)  # grip
    b.box("Mag", (0.2, 0.5, 0.26), (0, -0.33, 0.07), rot=(-14, 0, 0))  # magazine (base pokes out)
    b.box("Metal", (0.08, 0.06, 0.32), (0, -0.12, -0.25), bevel=0)  # trigger guard
    b.cylinder("Steel", 0.07, 0.14, (0, 0.24, -0.88), sides=6)  # barrel crown
    b.box("Steel", (0.06, 0.06, 0.06), (0, 0.4, -0.75), bevel=0)  # front sight
    return (0, 0.24, -0.95)


def smg(b):
    b.box("Metal", (0.3, 0.42, 1.25), (0, 0.2, -0.35), bevel=0.05)  # receiver
    b.box("Mag", (0.22, 0.75, 0.28), (0, -0.32, -0.5), rot=(6, 0, 0))  # magazine
    b.box("Metal", (0.22, 0.5, 0.3), (0, -0.18, 0.05), rot=(-12, 0, 0))  # grip
    b.box("Metal", (0.07, 0.07, 0.75), (0.1, 0.25, 0.55), bevel=0)  # stock rods
    b.box("Metal", (0.07, 0.07, 0.75), (-0.1, 0.25, 0.55), bevel=0)
    b.box("Metal", (0.24, 0.32, 0.1), (0, 0.22, 0.95), bevel=0)  # butt plate
    b.cylinder("Steel", 0.08, 0.5, (0, 0.28, -1.2), sides=8)  # barrel
    b.box("Steel", (0.05, 0.12, 0.05), (0, 0.46, -1.0), bevel=0)  # front sight
    return (0, 0.28, -1.48)


def shotgun(b):
    b.cylinder("Steel", 0.11, 2.4, (0, 0.33, -1.05), sides=8)  # barrel
    b.cylinder("Steel", 0.08, 1.7, (0, 0.13, -0.75), sides=6)  # magazine tube
    b.box("Wood", (0.3, 0.26, 0.75), (0, 0.13, -1.05), bevel=0.06)  # pump
    b.box("Metal", (0.3, 0.42, 0.65), (0, 0.22, 0.05), bevel=0.04)  # receiver
    b.box("Wood", (0.26, 0.42, 0.5), (0, -0.12, 0.45), rot=(-20, 0, 0))  # grip
    b.box("Wood", (0.28, 0.5, 0.9), (0, 0.02, 0.95), rot=(-8, 0, 0), taper=(0.9, 0.7))  # stock
    return (0, 0.33, -2.25)


def rifle(b):
    b.box("Metal", (0.3, 0.45, 1.7), (0, 0.2, -0.45), bevel=0.05)  # receiver + handguard
    b.cylinder("Steel", 0.08, 1.05, (0, 0.26, -1.82), sides=8)  # barrel
    b.cylinder("Metal", 0.12, 0.85, (0, 0.65, -0.45), sides=8)  # scope tube
    b.cylinder("Steel", 0.15, 0.12, (0, 0.65, -0.9), sides=8)  # scope front lens ring
    b.box("Metal", (0.08, 0.2, 0.1), (0, 0.48, -0.25), bevel=0)  # scope mounts
    b.box("Metal", (0.08, 0.2, 0.1), (0, 0.48, -0.65), bevel=0)
    b.box("Mag", (0.22, 0.7, 0.32), (0, -0.32, -0.6), rot=(8, 0, 0))  # magazine
    b.box("Metal", (0.22, 0.48, 0.28), (0, -0.2, 0.05), rot=(-15, 0, 0))  # grip
    b.box("Metal", (0.26, 0.48, 0.95), (0, 0.1, 0.8), taper=(1, 0.75))  # stock
    return (0, 0.26, -2.35)


def ak47(b):
    b.box("Metal", (0.3, 0.4, 1.3), (0, 0.2, -0.3), bevel=0.04)  # receiver
    b.box("Wood", (0.32, 0.32, 0.75), (0, 0.17, -1.2), bevel=0.06)  # lower handguard
    b.cylinder("Metal", 0.06, 0.7, (0, 0.4, -1.15), sides=6)  # gas tube
    b.cylinder("Steel", 0.07, 0.75, (0, 0.24, -1.85), sides=8)  # barrel
    b.box("Metal", (0.06, 0.18, 0.08), (0, 0.38, -2.05), bevel=0)  # front sight
    # The curved magazine is the AK's silhouette: two segments bending forward.
    b.box("Mag", (0.22, 0.45, 0.3), (0, -0.18, -0.48), rot=(8, 0, 0))
    b.box("Mag", (0.22, 0.45, 0.3), (0, -0.55, -0.62), rot=(28, 0, 0))
    b.box("Wood", (0.24, 0.45, 0.28), (0, -0.18, 0.12), rot=(-18, 0, 0))  # pistol grip
    b.box("Wood", (0.26, 0.42, 1), (0, 0.02, 0.85), rot=(-10, 0, 0), taper=(1, 0.8))  # stock
    return (0, 0.24, -2.25)


def knife(b):
    b.box("WoodDark", (0.18, 0.24, 0.52), (0, 0, 0.1), bevel=0.05)  # handle
    b.box("Metal", (0.28, 0.08, 0.1), (0, 0.02, -0.2), bevel=0)  # guard
    b.box("Steel", (0.05, 0.22, 0.8), (0, 0.03, -0.62), bevel=0, taper=(1, 0.15))  # blade
    return (0, 0.03, -1.0)


def bat(b):
    b.cylinder("WoodDark", 0.11, 1.2, (0, 0, -0.2), sides=8, radius_front=0.13)  # taped handle
    b.cylinder("Wood", 0.13, 1.7, (0, 0, -1.6), sides=8, radius_front=0.21)  # barrel
    for i, (angle, z) in enumerate([(0, -1.3), (60, -1.5), (120, -1.7), (180, -1.9), (240, -2.1), (300, -2.25)]):
        a = math.radians(angle)
        b.box("Steel", (0.04, 0.32, 0.04), (math.cos(a) * 0.2, math.sin(a) * 0.2, z), rot=(0, 0, angle - 90), bevel=0)
    return (0, 0, -2.45)


WEAPONS = [
    ("Pistol", pistol),
    ("SMG", smg),
    ("Shotgun", shotgun),
    ("Rifle", rifle),
    ("AK47", ak47),
    ("Knife", knife),
    ("Bat", bat),
]

manifest = {"blender": bpy.app.version_string, "weapons": {}}
all_objects = []
for index, (name, build) in enumerate(WEAPONS):
    builder = Builder(name, index * SPACING)
    muzzle = build(builder)
    meshes, grip, tip = builder.finish(muzzle)
    all_objects += meshes + [grip, tip]
    tris = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
    manifest["weapons"][name] = {
        "meshes": [obj.name for obj in meshes],
        "triangles": tris,
        # Roblox-space grip→muzzle vector in studs, for checking the import.
        "muzzle_from_grip": list(muzzle),
    }
    assert tris < 600, (name, tris)

bpy.context.scene.unit_settings.system = "NONE"
bpy.ops.object.select_all(action="DESELECT")
for obj in all_objects:
    obj.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(source / "weapons.blend"))
bpy.ops.export_scene.fbx(
    filepath=str(export / "weapons.fbx"), use_selection=True,
    object_types={"MESH"}, axis_forward="-Z", axis_up="Y",
    global_scale=1.0, apply_unit_scale=False, bake_anim=False,
    use_mesh_modifiers=True, add_leaf_bones=False,
)
(export / "weapons.json").write_text(json.dumps(manifest, indent=2) + "\n")


# Preview render: Cycles on the CPU (works headless). Runs after saving/exporting, so it may
# move things around: each weapon is turned to show its side profile and stacked in two columns.
def render_previews():
    scene = bpy.context.scene
    turn = Matrix.Rotation(math.radians(90), 4, "Z")  # barrel from Blender +Y to -X
    for index, (name, _) in enumerate(WEAPONS):
        grip = bpy.data.objects[f"{name}_Grip"].location.copy()
        column, row = index // 4, index % 4
        place = Vector((column * 7.5, 0, -row * 1.9))
        for obj in all_objects:
            if obj.name.startswith(name + "_"):
                obj.matrix_world = Matrix.Translation(place) @ turn @ Matrix.Translation(-grip) @ obj.matrix_world
                obj.hide_render = obj.name.endswith(("_Grip", "_Muzzle"))

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    world = bpy.data.worlds.new("Preview")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.12, 0.12, 0.14, 1)
    background.inputs["Strength"].default_value = 1.2
    scene.world = world
    key = bpy.data.objects.new("Key", bpy.data.lights.new("Key", "SUN"))
    key.data.energy = 4
    key.rotation_euler = (math.radians(60), 0, math.radians(-30))
    bpy.context.collection.objects.link(key)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 16
    cam.location = (5.2, -12, -2.6)
    cam.rotation_euler = (math.radians(90), 0, 0)  # look along +Y at the side profiles
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    scene.render.filepath = str(export / "weapons.preview.png")
    bpy.ops.render.render(write_still=True)


render_previews()
print("WEAPONS_OK " + json.dumps({k: v["triangles"] for k, v in manifest["weapons"].items()}))
