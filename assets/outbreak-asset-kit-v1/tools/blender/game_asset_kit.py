"""Non-destructive UI weapon renders and standalone hub/consumable meshes.
Run: blender --background --factory-startup --python-exit-code 1 --python tools/blender/game_asset_kit.py -- PROJECT_ROOT
Outputs only assets/game/. Existing models and runtime maps are unchanged.
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(sys.argv[sys.argv.index('--') + 1])
OUT = ROOT / 'assets/game'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.world = bpy.data.worlds.new('Studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .8
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.35,.4,.5,1)
scene.view_settings.view_transform = 'AgX'
cam = bpy.data.objects.new('AssetCamera', bpy.data.cameras.new('AssetCamera'))
bpy.context.collection.objects.link(cam)
cam.data.type = 'ORTHO'
scene.camera = cam
for name,loc,power,size in [('Key',(5,-5,9),1400,7),('Rim',(-4,5,6),1800,6)]:
    obj = bpy.data.objects.new(name,bpy.data.lights.new(name,'AREA'))
    obj.location=loc; obj.data.energy=power; obj.data.shape='DISK'; obj.data.size=size
    obj.rotation_euler=(-obj.location).to_track_quat('-Z','Y').to_euler()
    bpy.context.collection.objects.link(obj)

mats={}
def mat(name,rgb,metal=0):
    if name in mats: return mats[name]
    m=bpy.data.materials.new(name); m.use_nodes=True
    v=[c/255 for c in rgb]
    linear=[c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in v]
    bs=m.node_tree.nodes['Principled BSDF']; bs.inputs['Base Color'].default_value=(*linear,1)
    bs.inputs['Roughness'].default_value=.7; bs.inputs['Metallic'].default_value=metal
    m.diffuse_color=(*linear,1); mats[name]=m
    return m
olive=mat('Canvas',(86,96,66)); dark=mat('Metal',(52,56,60),.5)
wood=mat('Wood',(104,92,80)); yellow=mat('Marking',(255,204,0))
sand=mat('Sand',(150,132,96)); steel=mat('Steel',(150,154,160),.5)
cream=mat('Cream',(236,232,222)); red=mat('Medical',(180,40,40))
objects=[]
def box(name,size,loc,material,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc,rotation=rot)
    o=bpy.context.object; o.name=name; o.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(material); objects.append(o); return o

def cyl(name,radius,depth,loc,material,vertices=12,rot=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc,rotation=rot)
    o=bpy.context.object; o.name=name; o.data.materials.append(material); objects.append(o); return o

def bounds(obs):
    vs=[o.matrix_world @ Vector(c) for o in obs for c in o.bound_box]
    lo=Vector(tuple(min(v[i] for v in vs) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in vs) for i in range(3)))
    return lo,hi

def render(obs,path,weapon=False):
    for o in bpy.data.objects:
        if o.type=='MESH': o.hide_render=o not in obs
    bpy.context.view_layer.update()
    lo,hi=bounds(obs); center=(lo+hi)/2; dims=hi-lo
    light_scale=max(max(dims)/6,.5)
    for light_name,offset,power in [('Key',(5,-5,9),2400),('Rim',(-4,5,6),1800)]:
        light=bpy.data.objects[light_name]
        light.location=center+Vector(offset)*light_scale
        light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
        light.data.energy=power*light_scale**2
        light.data.size=6*light_scale
    direction=Vector((1,-.55,.45) if weapon else (1,-1,.8)).normalized()
    cam.location=center+direction*max(dims.length,8)*2
    cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler()
    bpy.context.view_layer.update()
    inv=cam.matrix_world.inverted()
    projected=[inv @ (o.matrix_world @ Vector(v)) for o in obs for v in o.bound_box]
    cam.data.ortho_scale=max(max(v[i] for v in projected)-min(v[i] for v in projected) for i in (0,1))*1.3
    scene.render.filepath=str(path); bpy.ops.render.render(write_still=True)

# Render actual existing weapon meshes rather than unrelated painted silhouettes.
with bpy.data.libraries.load(str(ROOT/'assets/source/weapons.blend'),link=False) as (src,dst):
    dst.objects=[n for n in src.objects if any(n.startswith(p+'_') for p in ('Pistol','SMG','Shotgun','Rifle','AK47','Knife','Bat')) and not n.endswith(('_Grip','_Muzzle'))]
for o in dst.objects: bpy.context.collection.objects.link(o)
weapon_objects=list(dst.objects)
for key in ('Pistol','SMG','Shotgun','Rifle','AK47','Knife','Bat'):
    path=OUT/'weapons'/f'{key}.png'; path.parent.mkdir(parents=True,exist_ok=True)
    render([o for o in weapon_objects if o.name.startswith(key+'_')],path,True)
for o in weapon_objects: bpy.data.objects.remove(o,do_unlink=True)

models={}
def start(): objects.clear()
def finish(name,category='hub'):
    obs=list(objects); models[name]=obs
    folder=OUT/category; folder.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in obs: o.select_set(True)
    bpy.context.view_layer.objects.active=obs[0]
    # FBX uses the same axis convention as the existing weapon pipeline.
    bpy.ops.export_scene.fbx(filepath=str(folder/f'{name}.fbx'),use_selection=True,object_types={'MESH'},axis_forward='-Z',axis_up='Y',global_scale=1,apply_unit_scale=True,add_leaf_bones=False,bake_anim=False)
    render(obs,folder/f'{name}.png')

start()
box('Crate_Body',(3,2.4,2.5),(0,0,1.25),wood)
for x in (-1.35,1.35): box('Crate_Strap',(.18,2.52,2.62),(x,0,1.25),dark)
box('Crate_Patch',(.65,.05,.55),(0,-1.23,1.4),yellow)
finish('SupplyCrate')
start()
for row in range(3):
    for col in range(4):
        o=box('Sandbag',(2,.95,.7),((col-1.5)*1.9+(row%2)*.45,0,.35+row*.66),sand)
        bevel=o.modifiers.new('Soft sewn corners','BEVEL'); bevel.width=.2; bevel.segments=1
        bpy.context.view_layer.objects.active=o; bpy.ops.object.modifier_apply(modifier=bevel.name)
finish('SandbagWall')
start()
box('Tent_Floor',(8,7,.15),(0,0,.075),dark)
# A-frame canvas, open entrance at y=-3.5.
for sign in (-1,1):
    box('Tent_Canvas',(.12,7,5.66),(sign*2,0,2),olive,(0,-sign*math.pi/4,0))
for x in (-4,0,4): cyl('Tent_Pole',.07,4.1 if x==0 else .6,(x,0,2.05 if x==0 else .3),steel)
box('Tent_Ridge',(.12,7.4,.12),(0,0,4),steel)
finish('FieldTent')
start()
cyl('Lamp_Base',1,.2,(0,0,.1),dark)
cyl('Lamp_Pole',.12,7,(0,0,3.5),steel)
box('Lamp_Housing',(2,.5,1),(0,0,7),dark)
box('Lamp_Lens',(1.7,.08,.65),(0,-.3,7),cream)
finish('Floodlight')
start()
for x in (-2.1,2.1): box('Sign_Post',(.25,.25,5),(x,0,2.5),wood)
box('Sign_Plate',(5,.25,2.2),(0,0,4.4),dark)
box('Sign_Stripe',(.22,.28,2.2),(-2.3,0,4.4),yellow)
finish('DestinationSign')
start()
cyl('Pad_Base',9,.25,(0,0,.125),dark,32)
# Segmented yellow perimeter, no transparency or large texture.
for i in range(32):
    a=2*math.pi*i/32
    box('Pad_Ring',(.2,1.5,.02),(8*math.cos(a),8*math.sin(a),.26),yellow,(0,0,a))
for x in (-1.4,1.4): box('Pad_H',(.55,4,.02),(x,0,.26),cream)
box('Pad_H',(3.3,.55,.02),(0,0,.26),cream)
finish('Helipad')
start()
body=box('Heli_Fuselage',(3.6,6.2,3.1),(0,0,3.4),olive)
bevel=body.modifiers.new('Faceted body','BEVEL'); bevel.width=.6; bevel.segments=1
bpy.context.view_layer.objects.active=body; bpy.ops.object.modifier_apply(modifier=bevel.name)
glass=mat('CockpitGlass',(42,68,80),.25)
for sign in (-1,1):
    box('Heli_Windshield',(1.4,.12,1.15),(sign*.8,-3.12,3.9),glass,(.15,0,0))
    box('Heli_SideWindow',(.06,1.8,1.1),(sign*1.81,-1.25,4),glass)
    box('Heli_Door',(.06,1.7,2),(sign*1.81,1,3.45),dark)
    box('Heli_DoorWindow',(.08,1.3,.75),(sign*1.85,1,4),glass)
    box('Heli_DoorHandle',(.1,.4,.08),(sign*1.86,1.5,3.4),steel)
    box('Heli_Engine',(.7,2,.5),(sign*.9,.4,5),dark)
box('Heli_Nose',(2.7,.9,.6),(0,-3,2.9),olive)
box('Heli_Tail',(.7,7,.7),(0,5.8,3.7),olive,(.06,0,0))
box('Heli_Fin',(.2,1.2,2.7),(0,9.2,4.7),olive)
cyl('Heli_RotorMast',.18,1.5,(0,0,5.4),steel)
for a in (0,math.pi/2): box('Heli_Rotor',(16,.28,.1),(0,0,6.2),dark,(0,0,a))
for x in (-2.2,2.2):
    cyl('Heli_Skid',.13,7,(x,0,1.2),dark,8,(math.pi/2,0,0))
    for y in (-1.6,1.6): box('Heli_SkidStrut',(.14,.14,1.5),(x,y,1.9),steel)
box('Heli_TailRotor',(.16,.22,2),(0,9.2,4.7),dark,(math.pi/4,0,0))
finish('UtilityHelicopter')
start()
cyl('Grenade_Body',.4,.85,(0,0,.45),olive,10)
cyl('Grenade_Neck',.2,.22,(0,0,.98),dark,8)
box('Grenade_Lever',(.14,.22,.9),(.35,0,.85),steel,(0,-.3,0))
finish('Grenade','weapons')
start()
box('Medkit_Case',(2,1.3,.8),(0,0,.4),olive)
box('Medkit_Patch',(.9,.9,.02),(0,0,.81),cream)
box('Medkit_Cross',(.55,.17,.03),(0,0,.83),red)
box('Medkit_Cross',(.17,.55,.03),(0,0,.83),red)
finish('Medkit','weapons')
start()
for a in (0,2.094,4.188):
    box('Turret_Leg',(.16,2.8,.2),(math.sin(a)*.8,math.cos(a)*.8,.35),dark,(.2,0,-a))
cyl('Turret_Mast',.25,2,(0,0,1.2),steel)
box('Turret_Receiver',(1.2,1.8,.8),(0,0,2.5),olive)
cyl('Turret_Barrel',.14,3,(0,-1.8,2.5),dark,10,(math.pi/2,0,0))
box('Turret_Ammo',(.7,1,.7),(1,0,2.35),yellow)
finish('Turret','weapons')
for o in bpy.data.objects:
    if o.type=='MESH': o.hide_render=False
# Separate collections at the origin for reusable import, explicitly named.
for name,obs in models.items():
    col=bpy.data.collections.new(name); scene.collection.children.link(col)
    for o in obs:
        for old in list(o.users_collection): old.objects.unlink(o)
        col.objects.link(o)
    col.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'hub/hub-and-equipment.blend'))
report={name:{'meshes':len(obs),'triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in obs),'bounds_blender': [list(v) for v in bounds(obs)]} for name,obs in models.items()}
(OUT/'hub/model-report.json').write_text(json.dumps(report,indent=2))
print('ASSET_KIT_OK',json.dumps({k:v['triangles'] for k,v in report.items()}))
