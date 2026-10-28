"""Build code-native Outbreak UI assets as editable SVG + antialiased alpha PNG.
No generated marketing images are modified. Requires Pillow.
"""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/game/ui'
S=4
icons={}
class Icon:
    def __init__(self):
        self.im=Image.new('RGBA',(256,256)); self.d=ImageDraw.Draw(self.im)
        self.svg=['<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 64 64" fill="none" stroke="white" stroke-width="4" stroke-linecap="round" stroke-linejoin="round">']
    def line(self,points,w=4):
        p=[(int(x*S),int(y*S)) for x,y in points]; self.d.line(p,fill='white',width=w*S,joint='curve')
        for x,y in (p[0],p[-1]): self.d.ellipse((x-w*S/2,y-w*S/2,x+w*S/2,y+w*S/2),fill='white')
        self.svg.append('<polyline points="'+' '.join(f'{x},{y}' for x,y in points)+f'" stroke-width="{w}"/>')
    def rect(self,x,y,w,h,fill=False):
        self.d.rectangle((x*S,y*S,(x+w)*S,(y+h)*S),fill='white' if fill else None,outline=None if fill else 'white',width=4*S)
        self.svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}"'+(' fill="white" stroke="none"' if fill else '')+'/>')
    def circle(self,x,y,r,fill=False):
        self.d.ellipse(((x-r)*S,(y-r)*S,(x+r)*S,(y+r)*S),fill='white' if fill else None,outline=None if fill else 'white',width=4*S)
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{r}"'+(' fill="white" stroke="none"' if fill else '')+'/>')
    def poly(self,p):
        self.d.polygon([(x*S,y*S) for x,y in p],fill='white')
        self.svg.append('<polygon points="'+' '.join(f'{x},{y}' for x,y in p)+'" fill="white" stroke="none"/>')
    def save(self,name):
        folder=OUT/'icons'; folder.mkdir(parents=True,exist_ok=True)
        self.im.save(folder/f'{name}.png'); (folder/f'{name}.svg').write_text('\n'.join(self.svg+['</svg>']))
        icons[name]=self.im

def make(name,fn):
    i=Icon(); fn(i); i.save(name)
make('health',lambda i:(i.rect(25,10,14,44,True),i.rect(10,25,44,14,True)))
make('shield',lambda i:i.line([(12,13),(32,7),(52,13),(49,36),(42,46),(32,55),(22,46),(15,36),(12,13)]))
make('ammo',lambda i:[(i.poly([(x,10),(x-5,18),(x-5,46),(x+5,46),(x+5,18)]),i.line([(x-5,51),(x+5,51)])) for x in (17,32,47)])
make('aim',lambda i:(i.circle(32,32,17),i.circle(32,32,3,True),*[i.line(p) for p in [[(32,5),(32,20)],[(32,44),(32,59)],[(5,32),(20,32)],[(44,32),(59,32)]]]))
make('reload',lambda i:(i.line([(49,24),(43,14),(30,10),(17,15),(10,27),(13,42),(25,51),(39,51),(49,43)]),i.poly([(40,25),(55,29),(54,12)])))
make('fire',lambda i:(i.line([(32,7),(34,23),(43,18),(51,33),(50,44),(43,53),(28,56),(16,48),(12,36),(19,23),(23,32),(32,7)]),i.line([(32,35),(25,45),(32,51),(39,45),(32,35)])))
make('grenade',lambda i:(i.circle(31,38,18),i.rect(25,12,13,8),i.line([(34,13),(44,11),(52,38)]),i.circle(19,12,5)))
make('melee',lambda i:(i.poly([(45,7),(51,10),(37,37),(28,33)]),i.line([(23,31),(40,39)]),i.line([(28,38),(18,55)],7)))
make('repair',lambda i:(i.line([(13,8),(11,22),(20,29),(30,26),(44,45),(51,52),(56,47),(50,40),(33,22),(33,12),(25,7),(25,20),(18,21),(13,8)])))
make('turret',lambda i:(i.rect(17,19,27,15),i.rect(6,23,13,5,True),i.rect(43,22,13,8),i.line([(32,34),(32,44),(15,55)]),i.line([(32,44),(49,55)]),i.line([(32,44),(32,56)])))
make('shop',lambda i:(i.rect(12,25,40,30),i.line([(9,25),(14,10),(50,10),(55,25),(9,25)]),i.rect(26,38,12,17)))
make('credits',lambda i:(i.circle(32,32,23),i.line([(41,21),(25,21),(21,26),(25,32),(39,32),(43,38),(39,43),(22,43)]),i.line([(32,15),(32,49)])))
make('xp',lambda i:(i.poly([(32,6),(39,24),(58,25),(43,38),(48,57),(32,46),(16,57),(21,38),(6,25),(25,24)])))
make('trophy',lambda i:(i.line([(20,10),(44,10),(42,31),(36,38),(28,38),(22,31),(20,10)]),i.line([(20,14),(10,14),(10,26),(22,29)]),i.line([(44,14),(54,14),(54,26),(42,29)]),i.line([(32,38),(32,51),(21,51),(43,51)])))
make('players',lambda i:(i.circle(32,19,9),i.line([(17,52),(17,43),(23,34),(41,34),(47,43),(47,52)]),i.line([(12,19),(7,24),(7,29),(13,33)]),i.line([(52,19),(57,24),(57,29),(51,33)])))
make('helicopter',lambda i:(i.line([(8,35),(14,25),(37,25),(43,36),(37,43),(13,43),(8,35)]),i.line([(43,35),(56,26),(56,38),(43,38)]),i.line([(28,25),(28,17)]),i.line([(10,16),(46,16)]),i.line([(17,44),(17,50),(41,50)]),i.line([(35,44),(35,50)])))
make('helipad',lambda i:(i.circle(32,32,24),i.line([(23,19),(23,45)]),i.line([(41,19),(41,45)]),i.line([(23,32),(41,32)])))
make('camp',lambda i:(i.line([(7,52),(31,10),(56,52),(7,52)]),i.line([(21,52),(32,31),(43,52)]),i.line([(27,7),(37,17)])))
make('farm',lambda i:(i.line([(9,26),(32,10),(55,26),(55,55),(9,55),(9,26)]),i.rect(23,34,18,21),i.line([(23,34),(41,55)]),i.line([(41,34),(23,55)])))
make('settings',lambda i:(i.circle(32,32,15),i.circle(32,32,5),*[i.line(p,6) for p in [[(32,8),(32,15)],[(32,49),(32,56)],[(8,32),(15,32)],[(49,32),(56,32)],[(15,15),(20,20)],[(44,44),(49,49)],[(15,49),(20,44)],[(44,20),(49,15)]]]))
make('sound',lambda i:(i.line([(10,25),(21,25),(34,13),(34,51),(21,39),(10,39),(10,25)]),i.line([(43,22),(48,28),(48,36),(43,42)]),i.line([(51,14),(58,25),(58,39),(51,50)])))
make('close',lambda i:(i.line([(15,15),(49,49)]),i.line([(49,15),(15,49)])))
make('check',lambda i:i.line([(12,33),(26,47),(53,16)],6))
make('lock',lambda i:(i.rect(15,27,34,29),i.line([(22,27),(22,16),(26,10),(38,10),(42,16),(42,27)]),i.circle(32,39,3,True),i.line([(32,41),(32,46)])))
make('warning',lambda i:(i.line([(32,7),(58,53),(6,53),(32,7)]),i.line([(32,24),(32,36)]),i.circle(32,44,2,True)))
make('timer',lambda i:(i.circle(32,36,21),i.line([(32,36),(32,23)]),i.line([(32,36),(41,36)]),i.line([(24,7),(40,7)]),i.line([(32,7),(32,14)])))
make('wave',lambda i:(i.line([(8,20),(18,12),(28,20),(38,12),(48,20),(56,12)]),i.line([(8,36),(18,28),(28,36),(38,28),(48,36),(56,28)]),i.line([(8,52),(18,44),(28,52),(38,44),(48,52),(56,44)])))
make('skull',lambda i:(i.line([(17,42),(10,34),(10,21),(18,10),(46,10),(54,21),(54,34),(47,42),(44,54),(20,54),(17,42)]),i.rect(18,24,9,9,True),i.rect(37,24,9,9,True),i.poly([(32,34),(27,42),(37,42)]),i.line([(28,47),(28,54)]),i.line([(36,47),(36,54)])))
make('back',lambda i:i.line([(39,12),(18,32),(39,52)]))
make('interact',lambda i:(i.circle(32,32,23),i.circle(32,32,7,True)))
make('jump',lambda i:(i.line([(15,30),(32,12),(49,30)]),i.line([(32,12),(32,48)]),i.line([(16,54),(48,54)])))
make('menu',lambda i:[i.line([(12,y),(52,y)]) for y in (18,32,46)])
make('gunslinger',lambda i:(i.circle(32,32,20),i.line([(32,5),(32,16)]),i.line([(32,48),(32,59)]),i.line([(5,32),(16,32)]),i.line([(48,32),(59,32)]),i.poly([(32,21),(38,32),(32,43),(26,32)])))
make('exterminator',lambda i:(i.line([(14,15),(50,51)],7),i.line([(50,15),(14,51)],7),i.rect(10,10,10,14,True),i.rect(44,10,10,14,True)))

# 9-slice backgrounds; labels and icons stay separate and localizable.
colors={'primary':'#FFCC00','secondary':'#24242A','touch':'#101014'}
entries=[]
for family,color in colors.items():
    for state in ('normal','hover','pressed','disabled','focused'):
        im=Image.new('RGBA',(256,256)); d=ImageDraw.Draw(im)
        c=color
        if state=='disabled': c='#5A5A60'
        elif state=='pressed': c={'primary':'#D6AB00','secondary':'#19191F','touch':'#24242A'}[family]
        elif state=='hover': c={'primary':'#FFDD55','secondary':'#34343C','touch':'#24242A'}[family]
        d.rounded_rectangle((2,2,253,253),radius=16,fill=c,outline='#ECE8DE' if state=='focused' else None,width=8)
        if family=='touch': d.polygon([(4,4),(40,4),(4,40)],fill='#FFCC00')
        folder=OUT/'buttons'; folder.mkdir(parents=True,exist_ok=True)
        name=f'{family}-{state}'; im.resize((64,64),Image.Resampling.LANCZOS).save(folder/f'{name}.png')
        entries.append({'family':family,'state':state,'path':f'assets/game/ui/buttons/{name}.png','sliceCenter':[12,12,52,52]})
for name,color in [('hud','#101014'),('modal','#101014'),('warning','#101014')]:
    im=Image.new('RGBA',(256,256)); d=ImageDraw.Draw(im)
    d.rounded_rectangle((0,0,255,255),radius=16,fill=color,outline='#37373E',width=4)
    d.polygon([(0,0),(44,0),(0,44)],fill='#DC2828' if name=='warning' else '#FFCC00')
    folder=OUT/'panels';folder.mkdir(parents=True,exist_ok=True)
    im.resize((64,64),Image.Resampling.LANCZOS).save(folder/f'{name}.png')
(OUT/'slices.json').write_text(json.dumps(entries,indent=2))
# Overview of the native icons, no marketing images are modified.
board=Image.new('RGB',(1200,800),'#101014'); d=ImageDraw.Draw(board)
f=ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Narrow.ttf',20)
for idx,(name,im) in enumerate(icons.items()):
    x=24+(idx%8)*148; y=20+(idx//8)*150
    thumb=im.resize((88,88),Image.Resampling.LANCZOS)
    board.paste(thumb,(x+28,y),thumb);d.text((x+6,y+96),name,font=f,fill='#ECE8DE')
d.text((30,765),'OUTBREAK / UI ICON KIT / WHITE MASKS + IMAGECOLOR3',font=f,fill='#FFCC00')
board.save(OUT/'icon-contact-sheet.png')
print(f'UI_KIT_OK {len(icons)} icons, {len(entries)} buttons, 3 panels')
# Original procedural particle masks for ParticleEmitter/GUI tinting.
import math
vfx=ROOT/'assets/game/vfx';vfx.mkdir(parents=True,exist_ok=True)
for kind in ('soft-particle','smoke','muzzle-flash','spark'):
    im=Image.new('RGBA',(256,256)); pix=im.load()
    for y in range(256):
        for x in range(256):
            nx=(x-127.5)/127.5; ny=(y-127.5)/127.5
            r=math.hypot(nx,ny); angle=math.atan2(ny,nx)
            if kind=='soft-particle': a=max(0,1-r)**2
            elif kind=='smoke':
                wobble=.08*math.sin(angle*5)+.04*math.cos(angle*9)
                a=max(0,1-r/(.88+wobble))**1.5*(.8+.2*math.cos(nx*10)*math.sin(ny*9))
            elif kind=='muzzle-flash':
                edge=.2+.72*abs(math.cos(angle*4))**12
                a=max(0,1-r/edge)**.7
            else:
                a=max(0,1-abs(nx)*12)*max(0,1-abs(ny))
            pix[x,y]=(255,255,255,round(255*a))
    im.save(vfx/f'{kind}.png')
print('VFX_OK 4 original alpha masks')
