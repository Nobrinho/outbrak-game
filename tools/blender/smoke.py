"""Deterministic art-pipeline check: low-poly rusty barrel, FBX and GLB."""
import json
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from preview import write_preview

root = Path(sys.argv[sys.argv.index("--") + 1])
source = root / "assets/source"
export = root / "assets/export"
source.mkdir(parents=True, exist_ok=True)
export.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)


def material(name, color):
    result = bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1)
    result.use_nodes = True
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = 0.9
    return result


rust = material("Rust_Ochre", (0.32, 0.14, 0.065))
metal = material("Dark_Metal", (0.10, 0.085, 0.075))


def cylinder(name, radius, depth, z, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for polygon in obj.data.polygons:
        polygon.use_smooth = False
    return obj


# Units are a pipeline convention: 1 Blender unit = 1 stud after import scale check.
cylinder("Barrel_Body", 1.1, 3.2, 1.6, rust)
for index, z in enumerate((0.12, 0.85, 2.35, 3.08)):
    cylinder("Barrel_Band_%02d" % index, 1.13, 0.12, z, metal)

scene = bpy.context.scene
scene.unit_settings.system = "NONE"
meshes = [obj for obj in scene.objects if obj.type == "MESH"]
triangles = sum(sum(len(face.vertices) - 2 for face in obj.data.polygons) for obj in meshes)
assert triangles < 1000, triangles
bpy.ops.object.select_all(action="SELECT")
bpy.ops.wm.save_as_mainfile(filepath=str(source / "pipeline_barrel.blend"))
bpy.ops.export_scene.fbx(
    filepath=str(export / "pipeline_barrel.fbx"), use_selection=True,
    object_types={"MESH"}, axis_forward="-Z", axis_up="Y",
    global_scale=1.0, apply_unit_scale=False, bake_anim=False,
    use_mesh_modifiers=True, add_leaf_bones=False,
)
bpy.ops.export_scene.gltf(
    filepath=str(export / "pipeline_barrel.glb"), export_format="GLB",
    use_selection=True, export_yup=True,
)
write_preview(meshes, export)
manifest = {
    "asset": "pipeline_barrel", "blender": bpy.app.version_string,
    "mesh_count": len(meshes), "triangles": triangles,
    "blender_dimensions": [2.26, 2.26, 3.2],
    "roblox_target_dimensions_studs": [2.26, 3.2, 2.26],
    "import": "FBX via Studio 3D Importer; verify scale, materials and pivot before reuse",
    "purpose": "Toolchain smoke test; not a final reference-matched map asset",
}
(export / "pipeline_barrel.json").write_text(json.dumps(manifest, indent=2) + "\n")
for extension in ("fbx", "glb", "json"):
    output = export / ("pipeline_barrel." + extension)
    assert output.is_file() and output.stat().st_size > 0, output
print("ART_PIPELINE_OK " + json.dumps(manifest))
