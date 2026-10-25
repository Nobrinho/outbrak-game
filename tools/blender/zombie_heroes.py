"""Four hero zombies (Tank, Toxic, Armored, Runner), low-poly dark fantasy, side by side on X.

Showcase models for the horde game: rigid faceted blocks, flat shading, emissive eyes and
mutation points. Each zombie is built at the origin (feet on Z=0, facing Blender -Y, the
Roblox front) and joined into one mesh per material, so a zombie imports as ~8-12 MeshParts.
Left to right in the render: Tank (-X), Toxic, Armored, Runner (+X).

Outputs: assets/source/zombie_heroes.blend, assets/export/zombie_heroes.fbx/.json/.preview.png.
Bloom: Eevee's bloom is gone in Blender 4.2+, so the glow comes from emission + a compositor
Glare node on the Cycles preview render.
"""
import json
import math
from pathlib import Path
import random
import sys

import bpy
import bmesh
from mathutils import Euler, Matrix, Vector

root = Path(sys.argv[sys.argv.index("--") + 1])
source = root / "assets/source"
export = root / "assets/export"
source.mkdir(parents=True, exist_ok=True)
export.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
rng = random.Random(13)
scene = bpy.context.scene

# ---- Materials -------------------------------------------------------------------------------


def lin(channel):
    c = channel / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


MATS = {}


def mat(name, hexv, rough=0.85, metal=0.0, glow=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    color = (lin(hexv >> 16 & 255), lin(hexv >> 8 & 255), lin(hexv & 255), 1)
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if glow:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = glow
    m.diffuse_color = color
    MATS[name] = m


mat("skin_ash", 0x5B5A52)          # tank: dead grey-brown skin
mat("skin_rot", 0x4C6038)          # rotten green
mat("skin_toxic", 0x6A8A33)        # toxic mutant skin
mat("skin_pale", 0x7A8274)         # runner / armored skin
mat("flesh", 0x3B1F22)             # dark exposed flesh
mat("bone", 0xB9B196, rough=0.7)
mat("iron_rust", 0x7A3D1C, rough=0.75, metal=0.7)
mat("steel_dark", 0x2A2E33, rough=0.45, metal=0.85)
mat("stone", 0x4B4A47, rough=0.95)
mat("cloth_red", 0xA3171A, rough=0.95)
mat("cloth_dark", 0x1F2229, rough=0.95)
mat("cloth_olive", 0x3A3F2C, rough=0.95)
mat("boot", 0x121315, rough=0.8)
mat("cavity", 0x050506, rough=1.0)
mat("wire_copper", 0xC4701F, rough=0.4, metal=1.0)
mat("wire_red", 0xB01010, rough=0.5)
mat("eye_red", 0xFF1408, glow=18)
mat("eye_amber", 0xFFA21A, glow=12)
mat("eye_orange", 0xFF6A10, glow=14)
mat("toxic_fluid", 0x4DFF2A, glow=7)
mat("crystal", 0xB8FF1F, glow=10)

# ---- Geometry helpers (everything is baked into world space at the origin) -------------------

current = {"name": "", "coll": None, "count": 0, "role": "Body"}


def role(name):
    """Animation role of everything built next: Body, Head, ArmL, ArmR, LegL, LegR.
    Roblox left is Blender +X (the axis flip), so s == 1 below means L."""
    current["role"] = name


def side(prefix, s):
    role(prefix + ("L" if s > 0 else "R"))


def fr(loc=(0, 0, 0), rx=0.0, ry=0.0, rz=0.0, parent=None):
    """Local frame: translation then XYZ Euler (degrees), optionally nested in `parent`."""
    m = Matrix.Translation(Vector(loc)) @ Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix().to_4x4()
    return parent @ m if parent is not None else m


def world(frame, point):
    return frame @ Vector(point) if frame is not None else Vector(point)


def add(label, bm, matrix, material):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.transform(matrix)
    current["count"] += 1
    name = f"{current['name']}_{label}_{current['count']}"
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    mesh.materials.append(MATS[material])
    obj = bpy.data.objects.new(name, mesh)
    obj["role"] = current["role"]
    current["coll"].objects.link(obj)
    return obj


def local_matrix(loc, rot, frame):
    m = Matrix.Translation(Vector(loc)) @ Euler(tuple(math.radians(a) for a in rot), "XYZ").to_matrix().to_4x4()
    return frame @ m if frame is not None else m


def box(label, loc, size, material, rot=(0, 0, 0), frame=None, top=None, bot=None):
    """Box centred at loc. `top`/`bot` = (sx, sy) scale of the upper/lower faces (tapered block)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1)
    for v in bm.verts:
        k = (top if v.co.z > 0 else bot) or (1, 1)
        v.co = Vector((v.co.x * size[0] * k[0], v.co.y * size[1] * k[1], v.co.z * size[2]))
    return add(label, bm, local_matrix(loc, rot, frame), material)


def ico(label, loc, radius, material, rot=(0, 0, 0), frame=None, lumpy=0.0, clip_x=0):
    """Faceted ico-sphere (1 subdivision, 80 tris). clip_x=+1/-1 keeps only that side of x=0."""
    r = radius if isinstance(radius, (tuple, list)) else (radius,) * 3
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
    if clip_x:
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, 0),
                               plane_no=(1, 0, 0), clear_outer=clip_x < 0, clear_inner=clip_x > 0)
        bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
    for v in bm.verts:
        j = 1 + rng.uniform(-lumpy, lumpy) if lumpy else 1
        v.co = Vector((v.co.x * r[0] * j, v.co.y * r[1] * j, v.co.z * r[2] * j))
    return add(label, bm, local_matrix(loc, rot, frame), material)


def limb(label, a, b, r0, r1, material, seg=6, frame=None):
    """Faceted tapered prism from a to b (r1 = 0 gives a pointed spike)."""
    a, b = world(frame, a), world(frame, b)
    direction = b - a
    z = direction.normalized()
    helper = Vector((0, 0, 1)) if abs(z.z) < 0.95 else Vector((1, 0, 0))
    x = z.cross(helper).normalized()
    y = z.cross(x)
    bm = bmesh.new()
    angles = [(i + 0.5) * 2 * math.pi / seg for i in range(seg)]
    ring0 = [bm.verts.new(a + (x * math.cos(t) + y * math.sin(t)) * r0) for t in angles]
    if r1 > 0:
        ring1 = [bm.verts.new(b + (x * math.cos(t) + y * math.sin(t)) * r1) for t in angles]
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
        bm.faces.new(ring1)
    else:
        apex = bm.verts.new(b)
        for i in range(seg):
            bm.faces.new((ring0[i], ring0[(i + 1) % seg], apex))
    bm.faces.new(list(reversed(ring0)))
    return add(label, bm, Matrix.Identity(4), material)


def spike(label, a, b, r, material, seg=4, frame=None):
    return limb(label, a, b, r, 0, material, seg=seg, frame=frame)


def teeth(label, centre, width, count, length, direction, material="bone", frame=None, r=0.03):
    d = Vector(direction).normalized()
    for i in range(count):
        t = (i / (count - 1) - 0.5) * width
        base = Vector(centre) + Vector((t, 0, 0))
        spike(label, base, base + d * length * (0.8 + 0.4 * ((i * 7) % 3) / 2), r, material, frame=frame)


def claw(label, wrist, direction, material, fingers=4, length=0.45, width=0.3, r=0.04, curl=-0.2):
    """Bony hand: fingers fan out from the wrist along `direction` (world space)."""
    w = Vector(wrist)
    d = Vector(direction).normalized()
    side = d.cross(Vector((0, 0, 1)))
    side = side.normalized() if side.length > 0.1 else Vector((1, 0, 0))
    for i in range(fingers):
        t = i / (fingers - 1) - 0.5
        base = w + side * t * width
        mid = base + d * length * 0.55
        tip = mid + d * length * 0.45 + Vector((0, 0, curl * length)) + side * t * 0.12
        limb(label, base, mid, r, r * 0.8, material, seg=4)
        limb(label, mid, tip, r * 0.8, 0, material, seg=4)


def crystals(label, centre, radius, count, length, base_r, material="crystal"):
    c = Vector(centre)
    for i in range(count):
        y = 1 - 2 * (i + 0.5) / count
        rr = math.sqrt(1 - y * y)
        th = i * 2.399963
        d = Vector((math.cos(th) * rr, math.sin(th) * rr, y))
        k = rng.uniform(0.75, 1.3)
        spike(label, c + d * radius * 0.8, c + d * (radius + length * k), base_r * rng.uniform(0.8, 1.2), material, seg=4)


def group(name):
    coll = bpy.data.collections.new(name)
    scene.collection.children.link(coll)
    current.update(name=name, coll=coll, count=0)


# ---- 1. Tank: colossal, hunched, giant claw on the right arm ----------------------------------


def build_tank():
    group("Tank")
    # Legs: short and thick, rusted knee braces
    for s in (-1, 1):
        side("Leg", s)
        limb("thigh", (s * 0.6, 0.1, 1.5), (s * 0.65, -0.25, 0.7), 0.44, 0.38, "skin_ash")
        limb("shin", (s * 0.65, -0.25, 0.7), (s * 0.62, -0.1, 0.25), 0.36, 0.3, "cloth_dark")
        box("boot", (s * 0.62, -0.3, 0.14), (0.8, 1.1, 0.3), "boot")
        box("kneeplate", (s * 0.65, -0.5, 0.75), (0.5, 0.18, 0.4), "iron_rust", rot=(-15, 0, 0))
        spike("kneespike", (s * 0.65, -0.58, 0.75), (s * 0.65, -0.95, 0.9), 0.1, "iron_rust")
    role("Body")
    box("pelvis", (0, 0.05, 1.6), (1.6, 0.95, 0.7), "cloth_dark")
    box("belt", (0, 0.0, 1.9), (1.7, 1.05, 0.2), "iron_rust")
    for x in (-0.5, 0.0, 0.5):
        box("buckle", (x, -0.55, 1.9), (0.22, 0.1, 0.22), "steel_dark")

    t = fr((0, -0.15, 2.4), rx=24)
    box("torso", (0, 0, 0), (1.9, 1.3, 1.9), "skin_ash", frame=t, top=(1.35, 1.0))
    ico("hump", (0, 0.75, 0.6), (0.95, 0.7, 0.8), "skin_ash", frame=t, lumpy=0.12)
    for x, y, z, r in ((-0.55, 1.0, 0.95, 0.42), (0.5, 1.05, 0.65, 0.36), (0.0, 1.2, 1.1, 0.3), (0.75, 0.9, 1.15, 0.28)):
        ico("rock", (x, y, z), r, "stone", frame=t, lumpy=0.25)
    for x, z, rz in ((-0.45, 0.2, 10), (0.4, 0.6, -14)):
        box("backplate", (x, 1.18, z), (0.9, 0.12, 0.75), "iron_rust", rot=(0, 10, rz), frame=t)
    for x in (-0.7, -0.2, 0.3, 0.75):
        spike("backspike", (x, 1.1, 0.4 + 0.2 * x), (x * 1.3, 1.9, 0.9 + 0.3 * x), 0.12, "iron_rust", frame=t)

    # Exposed rib cage with a rusted iron carcass
    box("cavity", (0, -0.64, 0.05), (1.15, 0.14, 1.15), "cavity", frame=t)
    limb("sternum", (0, -0.72, -0.62), (0, -0.74, 0.62), 0.09, 0.09, "bone", seg=4, frame=t)
    for i in range(5):
        z = -0.5 + i * 0.28
        mat_name = "bone" if i % 2 == 0 else "iron_rust"
        for s in (-1, 1):
            pts = [(0, -0.74, z), (s * 0.4, -0.9, z + 0.05), (s * 0.78, -0.78, z - 0.1), (s * 0.98, -0.45, z - 0.22)]
            for p, q, r0, r1 in zip(pts, pts[1:], (0.08, 0.075, 0.07), (0.075, 0.07, 0.05)):
                limb("rib", p, q, r0, r1, mat_name, seg=4, frame=t)
    box("brace", (0, -0.95, 0.1), (1.6, 0.08, 0.12), "iron_rust", rot=(0, 38, 0), frame=t)
    box("brace", (0, -0.95, -0.1), (1.6, 0.08, 0.12), "iron_rust", rot=(0, -38, 0), frame=t)
    for p, r in (((0.55, -0.82, 0.5), 0.2), ((-0.62, -0.8, -0.45), 0.17)):
        ico("rock", p, r, "stone", frame=t, lumpy=0.2)
    for p in ((0.4, -0.97, 0.3), (-0.4, -0.97, -0.3), (0.4, -0.97, -0.3), (-0.4, -0.97, 0.3)):
        ico("rivet", p, 0.06, "steel_dark", frame=t)

    # Head: cube with a visor and red glowing eyes
    role("Head")
    h = fr((0, -0.45, 1.3), rx=-24, parent=t)
    box("head", (0, 0, 0), (0.9, 0.9, 0.85), "skin_ash", frame=h, top=(0.92, 0.92))
    box("visor", (0, -0.47, 0.08), (0.98, 0.14, 0.3), "steel_dark", frame=h)
    box("visorslit", (0, -0.55, 0.08), (0.8, 0.02, 0.12), "cavity", frame=h)
    for s in (-1, 1):
        box("eye", (s * 0.2, -0.56, 0.08), (0.22, 0.05, 0.1), "eye_red", frame=h)
        spike("horn", (s * 0.4, -0.1, 0.35), (s * 0.7, -0.05, 0.7), 0.1, "iron_rust", frame=h)
    box("brow", (0, -0.4, 0.34), (1.0, 0.22, 0.12), "iron_rust", frame=h)
    box("jaw", (0, -0.3, -0.5), (0.7, 0.4, 0.22), "skin_ash", frame=h)
    teeth("tooth", (0, -0.52, -0.38), 0.55, 5, 0.18, (0, 0, 1), frame=h)

    # Shoulders and arms
    role("Body")
    for s in (-1, 1):
        ico("shoulder", (s * 1.2, 0.0, 0.85), (0.7, 0.62, 0.55), "skin_ash", frame=t, lumpy=0.08)
        box("pauldron", (s * 1.28, 0.0, 1.22), (0.95, 0.95, 0.15), "iron_rust", rot=(0, s * 14, 0), frame=t)
        spike("pauldronspike", (s * 1.3, 0.0, 1.28), (s * 1.45, 0.0, 1.85), 0.14, "iron_rust", frame=t)
    role("ArmL")
    shoulder_l = t @ Vector((1.2, 0, 0.7))
    elbow_l = shoulder_l + Vector((0.45, -0.1, -1.25))
    wrist_l = elbow_l + Vector((-0.05, -0.2, -0.95))
    limb("upperarm", shoulder_l, elbow_l, 0.55, 0.5, "skin_ash")
    ico("bicep", shoulder_l.lerp(elbow_l, 0.35) + Vector((0.1, -0.25, 0)), (0.5, 0.45, 0.55), "skin_ash", lumpy=0.1)
    limb("forearm", elbow_l, wrist_l, 0.5, 0.66, "skin_ash")
    box("fist", wrist_l + Vector((0, -0.05, -0.35)), (1.05, 1.0, 0.85), "skin_ash")
    box("wristband", wrist_l + Vector((0, 0, 0.18)), (0.95, 0.9, 0.16), "iron_rust")
    for x in (-0.33, -0.11, 0.11, 0.33):
        spike("knuckle", wrist_l + Vector((x, -0.5, -0.15)), wrist_l + Vector((x, -0.8, -0.1)), 0.09, "iron_rust")

    role("ArmR")
    shoulder_r = t @ Vector((-1.2, 0, 0.7))
    elbow_r = shoulder_r + Vector((-0.5, -0.1, -1.2))
    wrist_r = elbow_r + Vector((0.1, -0.7, -0.9))
    limb("upperarm", shoulder_r, elbow_r, 0.55, 0.48, "skin_ash")
    limb("forearm", elbow_r, wrist_r, 0.48, 0.42, "skin_ash")
    ico("palm", wrist_r + Vector((0, -0.2, -0.1)), (0.6, 0.42, 0.52), "skin_ash", lumpy=0.1)
    wrist_band = wrist_r + Vector((0, -0.05, 0.05))
    box("wristband", wrist_band, (0.8, 0.8, 0.14), "iron_rust", rot=(-40, 0, 0))
    # Giant twisted claw: 4 fingers + thumb, each 3 segments ending in a point
    base_c = wrist_r + Vector((0, -0.45, -0.15))
    for i, x in enumerate((-0.38, -0.13, 0.13, 0.38)):
        p0 = base_c + Vector((x, 0, 0))
        p1 = p0 + Vector((x * 0.25, -0.5, -0.1))
        p2 = p1 + Vector((x * 0.5, -0.45, -0.28 - 0.05 * i))
        p3 = p2 + Vector((-x * 0.9, -0.35, -0.1))
        limb("finger", p0, p1, 0.16, 0.13, "skin_ash", seg=4)
        limb("finger", p1, p2, 0.13, 0.1, "bone", seg=4)
        spike("claw", p2, p3, 0.1, "iron_rust", seg=4)
    th0 = base_c + Vector((0.5, 0.05, 0.05))
    th1 = th0 + Vector((0.4, -0.4, -0.05))
    spike("thumbclaw", th0, th1 + Vector((0.2, -0.45, -0.1)), 0.15, "iron_rust", seg=4)


# ---- 2. Toxic: hunched demolition mutant, glowing green guts ----------------------------------


def build_toxic():
    group("Toxic")
    for s in (-1, 1):
        side("Leg", s)
        limb("thigh", (s * 0.3, 0.0, 1.0), (s * 0.34, -0.38, 0.55), 0.21, 0.18, "cloth_dark", seg=5)
        limb("shin", (s * 0.34, -0.38, 0.55), (s * 0.32, -0.1, 0.14), 0.18, 0.14, "skin_toxic", seg=5)
        box("foot", (s * 0.32, -0.3, 0.07), (0.36, 0.7, 0.14), "boot")
    role("Body")
    box("hips", (0, 0.0, 1.05), (0.85, 0.5, 0.35), "cloth_dark")
    box("belt", (0, 0, 1.25), (0.92, 0.56, 0.12), "cloth_dark")
    for x in (-0.3, 0.0, 0.3):   # demolition canisters with glowing caps
        limb("canister", (x, -0.33, 1.1), (x, -0.33, 1.5), 0.085, 0.085, "steel_dark", seg=6)
        ico("cap", (x, -0.33, 1.53), 0.07, "crystal")
    t = fr((0, -0.2, 1.65), rx=32)
    box("torso", (0, 0, 0), (1.1, 0.7, 1.0), "skin_toxic", frame=t, top=(1.2, 1.0))
    ico("hump", (0, 0.3, 0.3), (0.55, 0.38, 0.5), "skin_toxic", frame=t, lumpy=0.1)
    # Open abdomen and chest with bioluminescent fluid
    box("cavity", (0, -0.34, -0.12), (0.72, 0.12, 0.62), "cavity", frame=t)
    box("cavity", (0, -0.34, 0.38), (0.5, 0.12, 0.26), "cavity", frame=t)
    for p, r in (((0, -0.4, -0.15), (0.28, 0.1, 0.24)), ((0.14, -0.43, 0.1), (0.13, 0.08, 0.13)),
                 ((-0.15, -0.42, -0.34), (0.12, 0.08, 0.12)), ((0, -0.4, 0.4), (0.2, 0.08, 0.1))):
        ico("guts", p, r, "toxic_fluid", frame=t)
    for i in range(8):
        a = i * math.tau / 8
        base = Vector((0.37 * math.cos(a), -0.36, -0.12 + 0.34 * math.sin(a)))
        spike("flap", base, base * Vector((0.35, 1, 0.35)) + Vector((0, -0.12, -0.12 * 0)), 0.07, "flesh", frame=t)
    for i in range(3):
        z = -0.3 + i * 0.28
        for s in (-1, 1):
            pts = [(s * 0.4, -0.38, z), (s * 0.5, -0.46, z - 0.02), (s * 0.58, -0.3, z - 0.1)]
            for p, q in zip(pts, pts[1:]):
                limb("rib", p, q, 0.04, 0.035, "bone", seg=4, frame=t)

    role("Head")
    h = fr((0, -0.28, 0.9), rx=-32, parent=t)
    box("skull", (0, 0, 0), (0.62, 0.6, 0.62), "skin_pale", frame=h, top=(0.9, 0.9))
    for s in (-1, 1):
        box("socket", (s * 0.15, -0.31, 0.06), (0.22, 0.04, 0.18), "cavity", frame=h)
        box("eye", (s * 0.15, -0.34, 0.06), (0.15, 0.04, 0.1), "eye_amber", frame=h)
    box("crack", (0.1, -0.31, 0.24), (0.06, 0.04, 0.34), "cavity", rot=(0, 25, 0), frame=h)
    box("crackglow", (0.1, -0.325, 0.24), (0.025, 0.035, 0.3), "toxic_fluid", rot=(0, 25, 0), frame=h)
    box("crack", (-0.18, -0.31, 0.12), (0.05, 0.04, 0.26), "cavity", rot=(0, -30, 0), frame=h)
    box("crackglow", (-0.18, -0.325, 0.12), (0.02, 0.035, 0.22), "toxic_fluid", rot=(0, -30, 0), frame=h)
    jaw = fr((0, -0.12, -0.28), rx=30, parent=h)
    box("jaw", (0, -0.14, -0.08), (0.5, 0.32, 0.14), "skin_toxic", frame=jaw)
    teeth("tooth", (0, -0.28, -0.0), 0.4, 4, 0.1, (0, 0, 1), frame=jaw)
    mouth = h @ Vector((0, -0.3, -0.36))
    limb("drool", mouth, mouth + Vector((0, -0.05, -0.85)), 0.07, 0.04, "toxic_fluid", seg=4)
    ico("drop", mouth + Vector((0, -0.06, -0.98)), 0.07, "toxic_fluid")

    for s in (-1, 1):
        side("Arm", s)
        sh = t @ Vector((s * 0.66, 0, 0.36))
        el = sh + Vector((s * 0.12, -0.2, -0.5))
        wr = el + Vector((s * 0.0, -0.4, -0.4))
        ico("shoulder", sh, 0.26, "skin_toxic", lumpy=0.1)
        limb("upperarm", sh, el, 0.2, 0.16, "skin_toxic", seg=5)
        limb("forearm", el, wr, 0.16, 0.2, "skin_toxic", seg=5)
        hand = wr + Vector((0, -0.2, -0.12))
        ico("hand", hand, 0.38, "skin_toxic", lumpy=0.05)
        crystals("crystal", hand, 0.38, 11, 0.5, 0.09)


# ---- 3. Armored: broken tactical gear, wires and a half skull ---------------------------------


def build_armored():
    group("Armored")
    for s, fwd in ((-1, 0.0), (1, -0.25)):
        side("Leg", s)
        limb("thigh", (s * 0.3, fwd * 0.3, 1.35), (s * 0.3, fwd, 0.78), 0.27, 0.22, "cloth_olive")
        limb("shin", (s * 0.3, fwd, 0.78), (s * 0.3, fwd + 0.05, 0.25), 0.22, 0.2, "cloth_olive")
        box("kneepad", (s * 0.3, fwd - 0.2, 0.78), (0.34, 0.14, 0.3), "steel_dark")
        box("boot", (s * 0.3, fwd - 0.1, 0.13), (0.42, 0.8, 0.26), "boot")
    role("Body")
    box("hips", (0, 0, 1.45), (0.95, 0.55, 0.4), "cloth_olive")
    box("belt", (0, 0, 1.68), (1.0, 0.6, 0.12), "boot")
    for s in (-1, 1):
        box("pouch", (s * 0.45, -0.34, 1.52), (0.22, 0.16, 0.3), "steel_dark")
    t = fr((0, -0.1, 2.15), rx=12)
    box("torso", (0, 0, 0), (1.0, 0.62, 1.0), "cloth_dark", frame=t, top=(1.15, 1.0))
    # Vest: cracked plates that part to show wiring and torn fabric
    box("plate", (-0.29, -0.37, 0.1), (0.36, 0.14, 0.82), "steel_dark", rot=(0, 0, 6), frame=t)
    box("plate", (0.29, -0.37, 0.0), (0.36, 0.14, 0.86), "steel_dark", rot=(0, 0, -5), frame=t)
    box("platecrack", (-0.3, -0.45, 0.2), (0.04, 0.02, 0.4), "cavity", rot=(0, 35, 0), frame=t)
    box("platecrack", (0.3, -0.45, -0.1), (0.04, 0.02, 0.5), "cavity", rot=(0, -30, 0), frame=t)
    box("gap", (0, -0.34, 0.02), (0.18, 0.1, 0.8), "cavity", frame=t)
    for i, (x, m) in enumerate(((-0.05, "wire_copper"), (0.0, "wire_red"), (0.05, "wire_copper"))):
        z = -0.35
        for k in range(4):
            nz = z + 0.2
            nx = x + (0.05 if k % 2 == 0 else -0.05)
            limb("wire", (x, -0.42 - 0.01 * i, z), (nx, -0.42 - 0.01 * i, nz), 0.018, 0.018, m, seg=3, frame=t)
            x, z = nx, nz
    for x, z, rz in ((-0.1, -0.5, 8), (0.12, -0.55, -10)):
        box("tornfabric", (x, -0.42, z), (0.13, 0.03, 0.42), "cloth_olive", rot=(0, 0, rz), frame=t)
    box("backplate", (0, 0.37, 0.05), (0.9, 0.14, 0.9), "steel_dark", frame=t)
    for s in (-1, 1):
        for z in (0.05, 0.3):
            box("pocket", (s * 0.28, -0.46, z - 0.4), (0.2, 0.08, 0.16), "boot", frame=t)
    # Shoulder pads split by a crack with wire inside
    for s in (-1, 1):
        sp = fr((s * 0.7, 0.0, 0.5), ry=s * 22, parent=t)
        box("pad", (-0.14 * s, 0, 0.0), (0.26, 0.7, 0.18), "steel_dark", frame=sp)
        box("pad", (0.17 * s, 0, 0.0), (0.24, 0.7, 0.18), "steel_dark", frame=sp)
        limb("wire", (0.02 * s, -0.3, 0.0), (0.0, 0.3, 0.02), 0.02, 0.02, "wire_copper", seg=3, frame=sp)
    # Head: helmet covers the left half; the right half is a skull with one red eye
    role("Head")
    h = fr((0, -0.05, 0.85), rx=-10, parent=t)
    box("headleft", (0.12, 0, 0), (0.26, 0.5, 0.52), "skin_pale", frame=h)
    box("skullright", (-0.13, -0.01, 0), (0.26, 0.5, 0.52), "bone", frame=h)
    ico("helmet", (0, 0.02, 0.1), (0.38, 0.36, 0.33), "steel_dark", frame=h, clip_x=1)
    box("brim", (0.17, -0.27, 0.15), (0.34, 0.12, 0.07), "steel_dark", frame=h)
    spike("broken", (0.02, -0.15, 0.4), (-0.06, -0.12, 0.55), 0.06, "steel_dark", frame=h)
    spike("broken", (0.02, 0.1, 0.4), (-0.08, 0.15, 0.52), 0.06, "steel_dark", frame=h)
    box("socket", (-0.13, -0.255, 0.04), (0.17, 0.04, 0.17), "cavity", frame=h)
    ico("eye", (-0.13, -0.275, 0.04), 0.055, "eye_red", frame=h)
    box("socket", (0.13, -0.255, 0.0), (0.15, 0.04, 0.12), "cavity", frame=h)
    box("nose", (-0.0, -0.26, -0.08), (0.06, 0.03, 0.09), "cavity", frame=h)
    teeth("tooth", (-0.1, -0.26, -0.2), 0.2, 3, 0.07, (0, 0, 1), frame=h, r=0.025)
    box("jawstrap", (0.2, -0.14, -0.2), (0.04, 0.3, 0.05), "boot", frame=h)

    for s in (-1, 1):
        side("Arm", s)
        sh = t @ Vector((s * 0.66, 0, 0.38))
        if s == 1:
            el = sh + Vector((0.15, -0.3, -0.5))
            wr = el + Vector((0.0, -0.55, 0.05))
            direction = (0, -1, -0.1)
        else:
            el = sh + Vector((-0.1, -0.05, -0.6))
            wr = el + Vector((-0.05, -0.15, -0.55))
            direction = (0, -0.2, -1)
        limb("upperarm", sh, el, 0.17, 0.14, "cloth_olive")
        limb("forearm", el, wr, 0.14, 0.12, "cloth_olive")
        box("glove", wr + Vector((0, -0.05, -0.05)), (0.22, 0.2, 0.22), "boot")
        claw("finger", wr + Vector((0, -0.08, -0.08)), direction, "bone", fingers=4, length=0.3, width=0.16, r=0.03, curl=-0.1)


# ---- 4. Runner: lean, crouched, torn civilian clothes, bone spikes ----------------------------


def build_runner():
    group("Runner")
    # Stride: front leg planted ahead, back leg trailing
    legs = (
        (0.22, (0.22, -0.05, 1.05), (0.26, -0.7, 0.62), (0.26, -0.62, 0.1), -1),
        (-0.22, (-0.22, 0.0, 1.05), (-0.26, 0.45, 0.5), (-0.26, 0.95, 0.18), 1),
    )
    for s, hip, knee, ankle, dirn in legs:
        side("Leg", s)
        limb("thigh", hip, knee, 0.17, 0.12, "cloth_dark", seg=5)
        limb("shin", knee, ankle, 0.11, 0.07, "bone", seg=5)
        k = Vector(knee)
        spike("kneespike", k, k + Vector((s * 0.12, -0.3 * (1 if dirn < 0 else -1) * 0 - 0.28, 0.2)), 0.08, "bone")
        foot = Vector(ankle)
        box("foot", foot + Vector((0, -0.12 * dirn * -1 if False else -0.12, -0.04)), (0.18, 0.4, 0.08), "bone")
        for x in (-0.06, 0.0, 0.06):
            spike("toespike", foot + Vector((x, -0.3, -0.04)), foot + Vector((x * 1.4, -0.55, -0.1)), 0.035, "bone", seg=4)
    role("Body")
    box("hips", (0, 0.0, 1.1), (0.6, 0.38, 0.3), "cloth_dark")
    t = fr((0, -0.05, 1.25), rx=48)
    box("torso", (0, 0, 0.45), (0.68, 0.4, 0.95), "cloth_red", frame=t, top=(1.2, 1.0))
    for i, x in enumerate((-0.25, -0.08, 0.1, 0.27)):   # torn hem
        spike("hem", (x, -0.1, 0.0), (x + 0.04, -0.12 - 0.04 * i, -0.28 - 0.08 * (i % 2)), 0.07, "cloth_red", seg=3, frame=t)
    box("stain", (0.08, -0.215, 0.5), (0.22, 0.02, 0.26), "flesh", rot=(0, 0, 20), frame=t)
    for i in range(4):   # spine bumps
        z = 0.2 + i * 0.22
        spike("spine", (0, 0.2, z), (0, 0.46, z + 0.03), 0.06, "bone", frame=t)
    role("Head")
    h = fr((0, -0.1, 1.05), rx=-34, parent=t)
    box("skull", (0, 0, 0), (0.46, 0.52, 0.5), "skin_pale", frame=h, top=(0.9, 0.9))
    for s in (-1, 1):
        box("socket", (s * 0.12, -0.27, 0.06), (0.16, 0.04, 0.14), "cavity", frame=h)
        box("eye", (s * 0.12, -0.3, 0.06), (0.11, 0.04, 0.08), "eye_orange", frame=h)
        spike("cheek", (s * 0.22, -0.2, -0.05), (s * 0.4, -0.3, -0.15), 0.05, "bone", frame=h)
    teeth("tooth", (0, -0.26, -0.2), 0.34, 5, 0.08, (0, -0.2, -1), frame=h, r=0.025)
    jaw = fr((0, -0.12, -0.24), rx=42, parent=h)
    box("jaw", (0, -0.12, -0.08), (0.38, 0.3, 0.07), "bone", frame=jaw)
    teeth("tooth", (0, -0.24, -0.04), 0.3, 4, 0.08, (0, 0, 1), frame=jaw, r=0.025)

    for s in (-1, 1):
        side("Arm", s)
        sh = t @ Vector((s * 0.4, 0, 0.8))
        if s == 1:   # reaching forward
            el = sh + Vector((0.12, -0.45, -0.15))
            wr = el + Vector((0.05, -0.5, 0.0))
            direction = (0, -1, -0.3)
        else:        # trailing back
            el = sh + Vector((-0.15, 0.25, -0.3))
            wr = el + Vector((-0.05, 0.3, -0.3))
            direction = (0, 0.5, -1)
        limb("upperarm", sh, el, 0.1, 0.08, "skin_pale", seg=5)
        limb("forearm", el, wr, 0.08, 0.05, "bone", seg=5)
        spike("elbowspike", el, el + Vector((s * 0.1, 0.32 if s == 1 else -0.2, 0.12)), 0.06, "bone")
        claw("finger", wr, direction, "bone", fingers=4, length=0.38, width=0.14, r=0.03, curl=-0.1)


# ---- Assemble ----------------------------------------------------------------------------------

OFFSETS = {"Tank": -6.4, "Toxic": -1.9, "Armored": 2.2, "Runner": 5.9}
# Hero -> game kind (Config.ZOMBIES), and the factor that brings it to the size the game's rig
# has at scale 1 (the renderer multiplies by the kind's own scale on top).
GAME_KIND = {"Tank": "Brute", "Toxic": "Creeper", "Armored": "Bull", "Runner": "Runner"}
GAME_HEIGHT = {"Tank": 4.6, "Toxic": 4.4, "Armored": 5.2, "Runner": 4.8}
# Runner outfits vary per zombie in the game, so its materials follow the variant colours.
TONES = {"Runner": {"cloth_red": "shirt", "cloth_dark": "pants", "skin_pale": "skin"}}
GLOWS = {"toxic_fluid", "crystal"}
NEON = {"eye_red", "eye_amber", "eye_orange", "toxic_fluid", "crystal"}
ZOMBIES = [("Tank", build_tank), ("Toxic", build_toxic), ("Armored", build_armored), ("Runner", build_runner)]
parts = []
rigs = {}
manifest = {"axes": "Roblox (x,y,z) = Blender (-x,z,y); front is Blender -Y", "zombies": {}}
for index, (name, builder) in enumerate(ZOMBIES):
    builder()
    offset = OFFSETS[name]
    kind = GAME_KIND[name]
    groups = {}
    for obj in list(current["coll"].objects):
        groups.setdefault((obj["role"], obj.data.materials[0].name), []).append(obj)
    joined = []
    for (rname, mname), items in groups.items():
        bpy.ops.object.select_all(action="DESELECT")
        for o in items:
            o.select_set(True)
        bpy.context.view_layer.objects.active = items[0]
        bpy.ops.object.join()
        obj = bpy.context.view_layer.objects.active
        obj.name = obj.data.name = f"Hero_{kind}_{rname}_{mname}"
        obj["role"], obj["material"] = rname, mname
        joined.append(obj)
    # Mesh origin at its bounding-box centre, so the game sets Size/CFrame like zombies.py.
    low = Vector((1e9,) * 3)
    high = Vector((-1e9,) * 3)
    for obj in joined:
        for v in obj.data.vertices:
            for i in range(3):
                low[i], high[i] = min(low[i], v.co[i]), max(high[i], v.co[i])
    factor = GAME_HEIGHT[name] / (high.z - low.z)
    tris = 0
    specs = []
    pivots = {}
    for obj in joined:
        mesh = obj.data
        lo = Vector([min(v.co[i] for v in mesh.vertices) for i in range(3)])
        hi = Vector([max(v.co[i] for v in mesh.vertices) for i in range(3)])
        centre = (lo + hi) / 2
        rname, mname = obj["role"], obj["material"]
        if rname != "Body" and rname != "Head":   # pivot: the highest vertex of the limb (hip/shoulder)
            top = max(mesh.vertices, key=lambda v: v.co.z).co.copy()
            old = pivots.get(rname)
            if old is None or top.z > old[1].z:
                pivots[rname] = (top, top)
        mesh.transform(Matrix.Translation(-centre))
        obj.location = Vector((offset, 0, 0)) + centre
        mesh.calc_loop_triangles()
        tris += len(mesh.loop_triangles)
        size = (hi - lo)
        mat_obj = MATS[mname]
        color = mat_obj.diffuse_color
        srgb = [round(255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)) for c in color[:3]]
        specs.append({
            "name": obj.name, "role": rname, "tone": TONES.get(name, {}).get(mname, "fixed"),
            "color": srgb, "material": "Neon" if mname in NEON else ("Metal" if mname in ("steel_dark", "iron_rust") else "SmoothPlastic"),
            "glow": mname in GLOWS,
            "size": [max(size.x, 0.02) * factor, max(size.z, 0.02) * factor, max(size.y, 0.02) * factor],
            "offset": [-centre.x * factor, centre.z * factor, centre.y * factor],
        })
        parts.append(obj)
    rigs[kind] = {
        "pivots": {r: [-p[0].x * factor, p[0].z * factor, p[0].y * factor] for r, p in pivots.items()},
        "parts": specs,
    }
    manifest["zombies"][name] = {
        "gameKind": kind, "meshParts": len(joined), "triangles": tris, "gameScale": round(factor, 3),
        "heightStuds": round((high.z - low.z) * factor, 2), "widthStuds": round((high.x - low.x) * factor, 2),
        "depthStuds": round((high.y - low.y) * factor, 2), "x": offset,
    }

# ---- Luau data for the renderer (src/shared/Art/HeroRigs.luau) ---------------------------------


def num(v):
    return ("%.3f" % v).rstrip("0").rstrip(".") if v else "0"


def vec(v):
    return "Vector3.new(%s)" % ", ".join(num(x) for x in v)


lines = [
    "--!strict",
    "-- Generated by tools/blender/zombie_heroes.py (python3 tools/art.py heroes). Do not edit.",
    "-- Hero rigs: the Blender meshes of the Tank, Toxic, Armored and Runner, split per animation",
    "-- role and material, in studs at kind scale 1. Mesh names match the models imported into",
    "-- ReplicatedStorage.Assets.Heroes; until they exist the renderer keeps the block rigs.",
    "",
    'local Types = require(script.Parent.Parent.Types)',
    'local ZombieRigs = require(script.Parent.ZombieRigs)',
    "",
    "export type HeroRig = { pivots: { [ZombieRigs.Role]: Vector3 }, parts: { ZombieRigs.PartSpec } }",
    "",
    "local HeroRigs = {}",
    "",
    "HeroRigs.RIGS = {",
]
for kind, rig in rigs.items():
    lines.append("\t%s = {" % kind)
    lines.append("\t\tpivots = {")
    for r, p in sorted(rig["pivots"].items()):
        lines.append("\t\t\t%s = %s," % (r, vec(p)))
    lines.append("\t\t},")
    lines.append("\t\tparts = {")
    for sp in rig["parts"]:
        fields = ['name = "%s"' % sp["name"], 'mesh = "%s"' % sp["name"], 'role = "%s"' % sp["role"],
                  'tone = "%s"' % sp["tone"], "size = " + vec(sp["size"]), "offset = " + vec(sp["offset"])]
        if sp["tone"] == "fixed":
            fields.append("color = Color3.fromRGB(%d, %d, %d)" % tuple(sp["color"]))
        fields.append("material = Enum.Material.%s" % sp["material"])
        if sp["glow"]:
            fields.append("glow = true")
        lines.append("\t\t\t{ %s }," % ", ".join(fields))
    lines.append("\t\t},")
    lines.append("\t},")
lines += ["} :: { [Types.ZombieKind]: HeroRig }", "", "return HeroRigs", ""]
(root / "src/shared/Art/HeroRigs.luau").write_text("\n".join(lines))

# ---- Scene: dark grey studio, rim lights, Cycles preview with compositor glow ------------------

bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
floor = bpy.context.active_object
floor.name = "Floor"
floor_mat = bpy.data.materials.new("Floor")
floor_mat.use_nodes = True
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.032, 0.036, 1)
floor_mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
floor.data.materials.append(floor_mat)

world_data = bpy.data.worlds.new("Studio")
world_data.use_nodes = True
bg = world_data.node_tree.nodes["Background"]
bg.inputs["Color"].default_value = (0.03, 0.032, 0.036, 1)
bg.inputs["Strength"].default_value = 1.0
scene.world = world_data


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def light(name, kind, loc, energy, color, size=5.0, target=(0, 0, 1.6)):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.size = size
    obj = bpy.data.objects.new(name, data)
    obj.location = loc
    scene.collection.objects.link(obj)
    aim(obj, target)
    return obj


light("RimLeft", "AREA", (-9, 6.5, 4.5), 1100, (0.55, 0.8, 1.0), size=5)     # cool back light
light("RimRight", "AREA", (9, 6.5, 4.5), 1100, (1.0, 0.55, 0.3), size=5)     # warm back light
light("RimTop", "AREA", (0, 5.0, 7.5), 700, (0.75, 0.85, 1.0), size=10)
light("Key", "AREA", (-3, -10, 6.5), 450, (1.0, 0.92, 0.85), size=6)
light("Fill", "AREA", (8, -9, 2.0), 90, (0.6, 0.7, 1.0), size=6)

cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = 33
cam = bpy.data.objects.new("Camera", cam_data)
cam.location = (0, -19, 2.7)
scene.collection.objects.link(cam)
aim(cam, (0, 0, 1.7))
scene.camera = cam

scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.render.resolution_x = 2400
scene.render.resolution_y = 1000
scene.view_settings.view_transform = "Filmic" if "Filmic" in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items else "AgX"
scene.view_settings.look = "None"
scene.use_nodes = True
tree = scene.node_tree
tree.nodes.clear()
layers = tree.nodes.new("CompositorNodeRLayers")
glare = tree.nodes.new("CompositorNodeGlare")
glare.glare_type = "FOG_GLOW"
glare.quality = "MEDIUM"
glare.threshold = 1.0
glare.size = 7
out = tree.nodes.new("CompositorNodeComposite")
tree.links.new(layers.outputs["Image"], glare.inputs["Image"])
tree.links.new(glare.outputs["Image"], out.inputs["Image"])
scene.render.filepath = str(export / "zombie_heroes.preview.png")
bpy.ops.wm.save_as_mainfile(filepath=str(source / "zombie_heroes.blend"))
bpy.ops.render.render(write_still=True)

# ---- Export (zombies only: floor, lights and camera stay out of the FBX) -----------------------

bpy.ops.object.select_all(action="DESELECT")
for obj in parts:
    obj.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=str(export / "zombie_heroes.fbx"), use_selection=True,
    object_types={"MESH"}, axis_forward="-Z", axis_up="Y",
    global_scale=1.0, apply_unit_scale=False, bake_anim=False,
    use_mesh_modifiers=True, add_leaf_bones=False,
)
(export / "zombie_heroes.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("ZOMBIE_HEROES_OK " + json.dumps(manifest["zombies"]))
