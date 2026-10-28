"""Persist verified upload results separately from generated asset catalogs."""
import json
from pathlib import Path
from urllib.parse import urlparse
root=Path(__file__).resolve().parents[2];game=root/'assets/game'
ids=json.loads((game/'upload-a.json').read_text())
b=json.loads((game/'upload-b.json').read_text())
for block in b['content']:
 if block.get('type')=='text':
  for url,uri in json.loads(block['text']).items():
   key=str(Path(urlparse(url).path.lstrip('/')).with_suffix('')).replace('/','.')
   ids[key]=int(uri.removeprefix('rbxassetid://'))
(game/'published-images.json').write_text(json.dumps(ids,indent=2,sort_keys=True)+'\n')
source=['--!strict','-- Actual Roblox image IDs. Rebuild with tools/design/record-upload.py.','return table.freeze({']
source += [f'\t["{k}"] = {v},' for k,v in sorted(ids.items())]
source += ['} :: { [string]: number })','']
(root/'src/shared/Art/AssetIds.luau').write_text('\n'.join(source))
p=game/'manifest.json';manifest=json.loads(p.read_text());manifest['image_ids']=ids;manifest['published']=True
manifest['notes']=['Image uploads recorded in published-images.json. Non-runtime previews remain local.','107 actual imported mesh IDs in hub/published-meshes.json; portable source assets/models/OutbreakKit.rbxmx.']
for asset in manifest['assets']:
 key=asset['key']
 if key in ids and asset['path'].endswith('.png'): asset.update(status='uploaded',robloxId=ids[key])
p.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
print('IMAGE_IDS_RECORDED',len(ids))
