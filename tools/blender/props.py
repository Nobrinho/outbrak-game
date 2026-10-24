"""Low-poly farm props (rusted tractor, abandoned pickup, crate): FBX + a preview render.

Each prop replaces the look of the parts FarmMap.luau builds for it, never their collisions:
the game keeps the original parts (invisible) and lays the meshes over them. Each prop is drawn
around the centre of its body part (TractorBody, TruckBody, Crate) and split into one mesh per
colour tone (<Prop>_Paint, _Tire…), recoloured by the game (src/shared/Art/FarmProps.luau).
<Prop>_Origin, a 0.1-stud cube at that centre, gives the importer's unit scale and the point
every tone mesh is placed from.

Shapes are written in Roblox axes (x right, y up, -z front), relative to the prop's ground
anchor in FarmMap.luau, and converted like the zombies: Roblox (x, y, z) → Blender (-x, z, y),
so fronts face Blender -Y. Props sit side by side along Blender X in the file.
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

SPACING = 14.0
# Preview colours only (sRGB); the game applies the same ones from FarmProps.luau.
TONES = {
    "Tractor": {"Paint": (124, 72, 44), "Dark": (43, 38, 34), "Tire": (28, 28, 30), "Rim": (176, 146, 74)},
    "Truck": {
        "Paint": (113, 44, 31), "Glass": (30, 36, 42), "Tire": (28, 28, 30), "Chrome": (82, 86, 86),
        "Dark": (43, 38, 34), "Lamp": (174, 161, 119), "Tail": (120, 32, 26),
    },
    "Crate": {"Wood": (108, 94, 77), "Frame": (72, 60, 48)},
}


def to_blender(p):
    return Vector((-p.x, p.z, p.y))


def euler(deg):
    """Roblox CFrame.Angles(rx, ry, rz) as a matrix acting on Roblox-space vectors."""
    rx, ry, rz = (math.radians(a) for a in deg)
    return (Matrix.Rotation(rx, 3, "X") @ Matrix.Rotation(ry, 3, "Y") @ Matrix.Rotation(rz, 3, "Z"))


def frame(z_axis, up=(0, 1, 0)):
    """Rotation whose local +Z points along `z_axis` (Roblox space)."""
    z = Vector(z_axis).normalized()
    up = Vector(up)
    if abs(z.dot(up)) > 0.99:
        up = Vector((1, 0, 0))
    x = up.cross(z).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


class Prop:
    """Collects primitives per tone in Roblox space, then writes one mesh per tone."""

    def __init__(self, name, origin, slot):
        self.name = name
        self.origin = Vector(origin)  # body part centre, from the ground anchor
        self.shift = Vector((-slot * SPACING, 0, 0))  # Blender offset in the file
        self.tones = {}

    def _emit(self, tone, bm, rotation, center):
        verts, faces = self.tones.setdefault(tone, ([], []))
        base = len(verts)
        index = {}
        offset = Vector(center) - self.origin
        for i, v in enumerate(bm.verts):
            index[v] = base + i
            verts.append(to_blender(rotation @ v.co + offset) + self.shift)
        for f in bm.faces:
            faces.append([index[v] for v in f.verts])
        bm.free()

    def box(self, tone, size, center, rot=(0, 0, 0), bevel=0.0, taper=None, slant=0.0, matrix=None):
        """Box of Roblox size (x, y, z). `taper` (tx, ty) scales the front (-z) end; `slant`
        moves the top front edge back by that many studs (windshields, hoods)."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1)
        sx, sy, sz = size
        for v in bm.verts:
            v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
            if taper and v.co.z < 0:
                v.co.x *= taper[0]
                v.co.y *= taper[1]
            if slant and v.co.y > 0 and v.co.z < 0:
                v.co.z += slant
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES", profile=0.5)
        self._emit(tone, bm, matrix or euler(rot), center)

    def cylinder(self, tone, radius, length, center, axis="X", rot=(0, 0, 0), sides=12):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=sides, radius1=radius, radius2=radius, depth=length)
        turn = {"X": euler((0, 90, 0)), "Y": euler((90, 0, 0)), "Z": Matrix.Identity(3)}[axis]
        self._emit(tone, bm, euler(rot) @ turn, center)

    def bar(self, tone, a, b, thickness):
        a, b = Vector(a), Vector(b)
        self.box(tone, (thickness, thickness, (b - a).length), (a + b) / 2, matrix=frame(b - a))

    def ring(self, tone, center, normal, radius, thickness, segments=8):
        basis = frame(normal)
        u, w = basis.col[0], basis.col[1]
        chord = 2 * radius * math.sin(math.pi / segments) * 1.08
        for i in range(segments):
            a = 2 * math.pi * (i + 0.5) / segments
            spot = Vector(center) + (u * math.cos(a) + w * math.sin(a)) * radius
            tangent = -u * math.sin(a) + w * math.cos(a)
            self.box(tone, (thickness, thickness, chord), spot, matrix=frame(tangent, normal))

    def tire(self, tone, radius, width, center, lugs, lug_size, rim=None, hub=None):
        """Wheel turning about X: tread lugs around a plain tyre, plus rim and hub discs."""
        x, y, z = center
        self.cylinder(tone, radius, width, center, axis="X", sides=max(12, lugs))
        lx, ly, lz = lug_size
        for i in range(lugs):
            a = 2 * math.pi * i / lugs
            shift = (0.22 if i % 2 else -0.22) * width
            spot = (x + shift, y + radius * math.cos(a), z + radius * math.sin(a))
            self.box(tone, (lx, ly, lz), spot, rot=(math.degrees(a), 0, 0))
        if rim:
            self.cylinder(rim[0], rim[1], width + 0.06, center, axis="X", sides=12)
        if hub:
            self.cylinder(hub[0], hub[1], width + 0.2, center, axis="X", sides=8)

    def finish(self):
        objects = []
        for tone, (verts, faces) in self.tones.items():
            mesh = bpy.data.meshes.new(f"{self.name}_{tone}")
            mesh.from_pydata([tuple(v) for v in verts], [], faces)
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            bm.to_mesh(mesh)
            bm.free()
            for poly in mesh.polygons:
                poly.use_smooth = False
            mesh.materials.append(material(self.name, tone))
            obj = bpy.data.objects.new(mesh.name, mesh)
            bpy.context.collection.objects.link(obj)
            objects.append(obj)
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.1)
        marker_mesh = bpy.data.meshes.new(f"{self.name}_Origin")
        bm.to_mesh(marker_mesh)
        bm.free()
        marker = bpy.data.objects.new(f"{self.name}_Origin", marker_mesh)
        marker.location = self.shift
        bpy.context.collection.objects.link(marker)
        return objects, marker


def srgb(c):
    c /= 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def material(prop, tone):
    mat = bpy.data.materials.new(f"{prop}_{tone}")
    linear = (*[srgb(v) for v in TONES[prop][tone]], 1)
    mat.diffuse_color = linear
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = linear
    shiny = tone in ("Chrome", "Glass", "Lamp", "Tail")
    bsdf.inputs["Roughness"].default_value = 0.3 if shiny else 0.85
    bsdf.inputs["Metallic"].default_value = 0.7 if tone == "Chrome" else 0
    return mat


# FarmMap: tractor = CFrame.new(18, 0, -38) · 20° yaw, TractorBody (3.4, 2.6, 7) at y 2.6,
# big wheels Ø5 at (±2.4, 2.5, 2), small wheels Ø2.6 at (±2, 1.3, -2.6), stack at (0.8, 6.4, -2.4).
def tractor(p):
    p.box("Dark", (1.9, 1.5, 3.4), (0, 2.75, -1.9), bevel=0.06)  # engine block
    p.box("Paint", (2.5, 1.3, 3.8), (0, 4.1, -1.95), bevel=0.15, taper=(0.9, 0.92))  # hood
    p.box("Dark", (2.1, 1.0, 0.16), (0, 3.95, -3.86))  # grille
    for i in range(4):
        p.box("Rim", (0.08, 0.85, 0.1), (-0.66 + i * 0.44, 3.95, -3.95))
    for x in (-0.75, 0.75):
        p.cylinder("Rim", 0.2, 0.16, (x, 4.55, -3.92), axis="Z", sides=8)  # headlights
    p.box("Dark", (2.6, 0.6, 0.6), (0, 2.15, -4.05), bevel=0.05)  # front weight
    p.box("Dark", (4.0, 0.35, 0.35), (0, 1.3, -2.6))  # front axle
    p.box("Dark", (0.5, 1.0, 0.5), (0, 1.8, -2.6))
    p.box("Paint", (2.3, 2.2, 2.4), (0, 2.7, 1.7), bevel=0.12)  # transmission housing
    p.cylinder("Dark", 0.32, 4.4, (0, 2.5, 2), axis="X", sides=8)  # rear axle
    p.box("Dark", (3.3, 0.14, 2.0), (0, 3.85, 1.5))  # footplate
    for side in (-1, 1):  # fenders arching over the rear wheels
        for a in range(-55, 66, 24):
            angle = math.radians(a)
            p.box("Paint", (1.6, 0.14, 1.25), (side * 2.4, 2.5 + 2.8 * math.cos(angle), 2 + 2.8 * math.sin(angle)),
                  rot=(a, 0, 0))
    p.box("Dark", (0.25, 0.7, 0.25), (0, 4.25, 2.1))  # seat post
    p.box("Dark", (1.3, 0.22, 1.1), (0, 4.65, 2.1), bevel=0.06)  # seat
    p.box("Dark", (1.3, 0.9, 0.18), (0, 5.15, 2.7), rot=(12, 0, 0), bevel=0.05)  # backrest
    p.bar("Dark", (0, 4.6, -0.1), (0, 5.55, 0.75), 0.14)  # steering column
    p.ring("Dark", (0, 5.6, 0.8), (0, 1, 0.9), 0.5, 0.09)  # steering wheel
    p.cylinder("Dark", 0.17, 2.6, (0.8, 6.0, -2.4), axis="Y", sides=8)  # exhaust stack
    p.cylinder("Dark", 0.26, 0.2, (0.8, 7.35, -2.35), axis="Y", rot=(0, 0, -18), sides=8)  # rain cap
    p.cylinder("Rim", 0.22, 1.1, (-0.75, 5.2, -2.9), axis="Y", sides=8)  # air intake
    for side in (-1, 1):
        p.tire("Tire", 2.32, 1.4, (side * 2.4, 2.5, 2), 14, (0.85, 0.3, 0.5),
               rim=("Rim", 1.4), hub=("Dark", 0.45))
        p.tire("Tire", 1.2, 0.95, (side * 2.05, 1.3, -2.6), 10, (0.55, 0.2, 0.3),
               rim=("Rim", 0.7), hub=("Dark", 0.25))


# FarmMap: truck = CFrame.new(-28, 0, 70) · -35° yaw · 4° roll, TruckBody (5, 2.4, 12) at
# y 2.2, cab (4.8, 2.4, 4) at (0, 4.6, -1), wheels Ø2.4 at (±2.5, 1.1, ±3.6).
def truck(p):
    p.box("Dark", (3.4, 0.5, 10.6), (0, 1.25, 0))  # chassis
    p.box("Paint", (4.9, 1.1, 11.6), (0, 2.85, 0), bevel=0.1)  # body above the wheels
    for z, depth in ((0, 4.6), (-5.35, 0.9), (5.35, 0.9)):  # sills between the wheel wells
        p.box("Paint", (4.9, 0.8, depth), (0, 1.95, z), bevel=0.05)
    for wz in (-3.6, 3.6):  # flared arches
        for side in (-1, 1):
            for a in (-62, -35, 35, 62):
                angle = math.radians(a)
                p.box("Paint", (0.18, 0.16, 0.82),
                      (side * 2.5, 1.15 + 1.45 * math.cos(angle), wz + 1.45 * math.sin(angle)), rot=(a, 0, 0))
    p.box("Paint", (4.7, 0.45, 2.95), (0, 3.6, -4.45), rot=(-3, 0, 0), bevel=0.08)  # hood
    p.box("Dark", (3.4, 0.9, 0.16), (0, 2.85, -5.85))  # grille
    for i in range(5):
        p.box("Chrome", (0.08, 0.8, 0.1), (-1.2 + i * 0.6, 2.85, -5.93))
    for x in (-1.95, 1.95):
        p.cylinder("Lamp", 0.3, 0.14, (x, 2.95, -5.86), axis="Z", sides=8)
    p.box("Chrome", (5.2, 0.45, 0.5), (0, 1.75, -6.0), bevel=0.06)  # front bumper
    p.box("Chrome", (5.0, 0.4, 0.4), (0, 1.75, 5.95), bevel=0.05)  # rear bumper
    for x in (-2.1, 2.1):
        p.box("Tail", (0.45, 0.55, 0.1), (x, 2.95, 5.84))
    # Cab: door tops, a glass greenhouse with a raked windshield, roof and pillars.
    p.box("Paint", (4.7, 0.6, 3.9), (0, 3.7, -1.05), bevel=0.06)
    p.box("Glass", (4.4, 1.55, 3.6), (0, 4.75, -1.0), slant=0.7)
    p.box("Paint", (4.6, 0.2, 3.0), (0, 5.6, -0.65), bevel=0.05)
    for side in (-1, 1):
        p.bar("Paint", (side * 2.22, 3.95, -2.8), (side * 2.22, 5.55, -2.1), 0.18)
        p.box("Paint", (0.18, 1.55, 0.24), (side * 2.22, 4.75, 0.72))
        p.box("Chrome", (0.08, 0.12, 0.5), (side * 2.47, 3.2, -0.5))  # door handle
        p.box("Dark", (0.12, 0.36, 0.26), (side * 2.6, 4.3, -2.55))  # mirror
        p.box("Dark", (0.3, 0.06, 0.06), (side * 2.45, 4.15, -2.6))
    # Bed: walls, darker floor, a spare tyre thrown in the back.
    for side in (-1, 1):
        p.box("Paint", (0.2, 0.9, 4.7), (side * 2.35, 3.85, 3.4), bevel=0.04)
    p.box("Paint", (4.9, 0.9, 0.2), (0, 3.85, 1.15), bevel=0.04)
    p.box("Paint", (4.9, 0.85, 0.18), (0, 3.83, 5.7), bevel=0.04)  # tailgate
    p.box("Dark", (4.5, 0.06, 4.4), (0, 3.42, 3.4))
    p.cylinder("Tire", 0.85, 0.45, (0.7, 3.7, 3.8), axis="Y", rot=(8, 0, 0), sides=12)
    p.cylinder("Chrome", 0.45, 0.5, (0.7, 3.7, 3.8), axis="Y", rot=(8, 0, 0), sides=8)
    for x in (-2.25, 2.25):
        for z in (-3.6, 3.6):
            p.tire("Tire", 1.12, 0.8, (x, 1.15, z), 12, (0.5, 0.12, 0.3),
                   rim=("Chrome", 0.6), hub=("Dark", 0.2))


# FarmMap: Crate (3, 3, 3), drawn around its centre.
def crate(p):
    p.box("Frame", (2.76, 2.76, 2.76), (0, 0, 0))  # dark core between the planks
    for i in (-1, 0, 1):
        for s in (-1, 1):
            p.box("Wood", (0.12, 0.8, 2.5), (s * 1.44, i * 0.88, 0))
            p.box("Wood", (2.5, 0.8, 0.12), (0, i * 0.88, s * 1.44))
            p.box("Wood", (0.8, 0.12, 2.5), (i * 0.88, s * 1.44, 0))
    for a in (-1, 1):  # battens along the 12 edges
        for b in (-1, 1):
            p.box("Frame", (3.0, 0.3, 0.3), (0, a * 1.38, b * 1.38))
            p.box("Frame", (0.3, 3.0, 0.3), (a * 1.38, 0, b * 1.38))
            p.box("Frame", (0.3, 0.3, 3.0), (a * 1.38, b * 1.38, 0))
    for s in (-1, 1):  # diagonal braces on the front and back
        p.box("Frame", (0.3, 3.4, 0.14), (0, 0, s * 1.52), rot=(0, 0, 45 * s))


PROPS = [("Tractor", tractor, (0, 2.6, 0)), ("Truck", truck, (0, 2.2, 0)), ("Crate", crate, (0, 0, 0))]

manifest = {"blender": bpy.app.version_string, "props": {}}
all_objects = []
for slot, (name, build, origin) in enumerate(PROPS):
    prop = Prop(name, origin, slot)
    build(prop)
    meshes, marker = prop.finish()
    all_objects += meshes + [marker]
    tris = 0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        tris += len(obj.data.loop_triangles)
    manifest["props"][name] = {"meshes": [obj.name for obj in meshes], "triangles": tris}
    assert tris < 3000, (name, tris)

bpy.context.scene.unit_settings.system = "NONE"
bpy.ops.object.select_all(action="DESELECT")
for obj in all_objects:
    obj.select_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(source / "props.blend"))
bpy.ops.export_scene.fbx(
    filepath=str(export / "props.fbx"), use_selection=True,
    object_types={"MESH"}, axis_forward="-Z", axis_up="Y",
    global_scale=1.0, apply_unit_scale=False, bake_anim=False,
    use_mesh_modifiers=True, add_leaf_bones=False,
)
(export / "props.json").write_text(json.dumps(manifest, indent=2) + "\n")

# ---- Preview: front three-quarter view of the three props in a row.
for obj in all_objects:
    obj.hide_render = obj.name.endswith("_Origin")
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
cam.data.ortho_scale = 34
cam.location = (-SPACING + 15, -30, 12.5)
cam.rotation_euler = (math.radians(72), 0, math.radians(25))
bpy.context.collection.objects.link(cam)
scene.camera = cam
scene.render.filepath = str(export / "props.preview.png")
bpy.ops.render.render(write_still=True)
print("PROPS_OK " + json.dumps({k: v["triangles"] for k, v in manifest["props"].items()}))
