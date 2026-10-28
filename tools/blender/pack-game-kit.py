"""Pack the existing kit into one named FBX and generate normalization metadata.
Every mesh is frozen into Roblox-oriented coordinates; importer size/position are
corrected by the Studio installer from the recorded bounds, without touching topology.
"""
import bpy
import json
import sys
from pathlib import Path
from mathutils import Matrix, Vector
root=Path(sys.argv[sys.argv.index('--')+1])
out=root/'assets/game/hub'
bpy.ops.wm.open_mainfile(filepath=str(out/'hub-and-equipment.blend'))
for o in list(bpy.data.objects):
 if o.type!='MESH': bpy.data.objects.remove(o,do_unlink=True)
report={}
# B = (x, yDepth, zUp) -> Roblox = (x, zUp, yDepth); front Blender -Y -> Roblox -Z.
# Mirror X to preserve handedness while retaining front -Z.
conv=Matrix(((-1,0,0),(0,0,1),(0,1,0)))
for col in bpy.data.collections:
 if not col.objects: continue
 name=col.name; col.hide_render=False; col.hide_viewport=False
 report[name]=[]
 for index,o in enumerate(list(col.objects)):
  if o.type!='MESH': continue
  o.hide_set(False); o.hide_render=False
  old_name=o.name
  o.name=f'Kit_{name}_{index:02}'
  points=[conv @ (o.matrix_world @ v.co) for v in o.data.vertices]
  lo=Vector([min(v[i] for v in points) for i in range(3)])
  hi=Vector([max(v[i] for v in points) for i in range(3)])
  # FBX imported axes may rotate the mesh; original identity export convention
  # is reconstructed by the actual imported mesh's orientation during normalization.
  rgb=o.data.materials[0].diffuse_color[:3]
  srgb=[round((12.92*c if c<=.0031308 else 1.055*c**(1/2.4)-.055)*255) for c in rgb]
  report[name].append({'name':o.name,'source':old_name,'center':list((lo+hi)/2),'size':list(hi-lo),'color':srgb,'material':o.data.materials[0].name})
# Put every mesh at its original location. The installer uses per-mesh descriptors,
# not imported position, so overlapping imported models aren't a problem.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.fbx(filepath=str(out/'outbreak-kit-import.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',global_scale=1,apply_unit_scale=True,add_leaf_bones=False,bake_anim=False)
(out/'import-metadata.json').write_text(json.dumps(report,indent=2))
print('PACKED',sum(len(x) for x in report.values()))
