"""Serialize actual imported mesh IDs to a Rojo-managed model, never synthetic IDs."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET
root=Path(__file__).resolve().parents[2]
data=json.loads((root/'assets/game/hub/published-meshes.json').read_text())
materials={'Fabric':1312,'Metal':1088,'Wood':512,'SmoothPlastic':272,'Glass':1568}
r=ET.Element('roblox',version='4')
f=ET.SubElement(r,'Item',{'class':'Folder','referent':'OutbreakKit'})
pr=ET.SubElement(f,'Properties');ET.SubElement(pr,'string',name='Name').text='OutbreakKit'
def val(props,typ,name,v):
 ET.SubElement(props,typ,name=name).text=str(v).lower() if isinstance(v,bool) else str(v)
def vector(props,name,v):
 e=ET.SubElement(props,'Vector3',name=name)
 for k,x in zip('XYZ',v): ET.SubElement(e,k).text=str(x)
for name,pieces in sorted(data.items()):
 m=ET.SubElement(f,'Item',{'class':'Model','referent':name});p=ET.SubElement(m,'Properties');val(p,'string','Name',name)
 for i,d in enumerate(pieces):
  item=ET.SubElement(m,'Item',{'class':'MeshPart','referent':name+str(i)});props=ET.SubElement(item,'Properties')
  val(props,'string','Name',d['name'])
  for k,b in [('Anchored',True),('CanCollide',False),('CanTouch',False),('CanQuery',False),('CastShadow',True)]: val(props,'bool',k,b)
  material=d['material']
  if name in ('UtilityHelicopter','Turret','Grenade') and material=='Fabric': material='Metal'
  val(props,'token','Material',materials[material]);d['material']=material
  color=d['color'];val(props,'Color3uint8','Color3uint8',4278190080+color[0]*65536+color[1]*256+color[2])
  vector(props,'size',d['size']);vector(props,'InitialSize',d['size'])
  cf=ET.SubElement(props,'CoordinateFrame',name='CFrame')
  for k,v in zip(['X','Y','Z','R00','R01','R02','R10','R11','R12','R20','R21','R22'],d['cf']): ET.SubElement(cf,k).text=str(v)
  content=ET.SubElement(props,'Content',name='MeshId');ET.SubElement(content,'url').text=d['id']
ET.indent(r)
(root/'assets/models/OutbreakKit.rbxmx').write_text(ET.tostring(r,encoding='unicode'))
# Normalize the data too, so future installers use the verified material overrides.
(root/'assets/game/hub/published-meshes.json').write_text(json.dumps(data,indent=2)+'\n')
print('EXPORTED',len(data),'models',sum(len(p) for p in data.values()),'real uploaded meshes')
