"""Render the Outbreak component specification to editable SVG and PNG.
Uses local substitute fonts; Roblox remains the typography reference.
Run with the bundled Python runtime (Pillow).
"""
from pathlib import Path
from html import escape
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/design'
OUT.mkdir(parents=True, exist_ok=True)
W, H = 1440, 1520
C = dict(bg='#0B0D11', panel='#101014', surface='#24242A', text='#ECE8DE', muted='#A09C94', accent='#FFCC00', player='#00C8E6', danger='#DC2828', fire='#FF8C14', disabled='#5A5A60', line='#37373E')
img = Image.new('RGB', (W,H), C['bg'])
draw = ImageDraw.Draw(img)
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', f'<rect width="{W}" height="{H}" fill="{C["bg"]}"/>']
FONT = '/System/Library/Fonts/Supplemental/Arial Narrow.ttf'
BOLD = '/System/Library/Fonts/Supplemental/DIN Condensed Bold.ttf'

def rect(x,y,w,h,fill,r=0,stroke=None):
    draw.rounded_rectangle((x,y,x+w,y+h),radius=r,fill=fill,outline=stroke,width=1)
    svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"'+(f' stroke="{stroke}"' if stroke else '')+'/>')

def text(x,y,s,size=20,color=None,bold=False):
    color = color or C['text']
    font = ImageFont.truetype(BOLD if bold else FONT,size)
    draw.text((x,y),s,font=font,fill=color,anchor='lt')
    svg.append(f'<text x="{x}" y="{y}" dominant-baseline="text-before-edge" font-family="{("DIN Condensed, Arial Narrow" if bold else "Arial Narrow, sans-serif")}" font-size="{size}" fill="{color}">{escape(s)}</text>')

def line(x,y,x2,y2,color=None):
    color=color or C['line']
    draw.line((x,y,x2,y2),fill=color,width=1)
    svg.append(f'<path d="M{x} {y}L{x2} {y2}" stroke="{color}"/>')

def panel(x,y,w,h):
    rect(x,y,w,h,C['panel'],4,C['line'])
    pts=[(x,y),(x+12,y),(x,y+12)]
    draw.polygon(pts, fill=C['accent'])
    svg.append(f'<polygon points="{x},{y} {x+12},{y} {x},{y+12}" fill="{C["accent"]}"/>')

def button(x,y,w,label,fill=None,fg=None):
    rect(x,y,w,48,fill or C['accent'],4)
    text(x+16,y+14,label,22,fg or C['panel'],True)

def section(y,no,title,sub):
    text(48,y,no,18,C['accent'],True)
    text(82,y-2,title,26,bold=True)
    text(550,y+1,sub,18,C['muted'])
    line(48,y+38,1392,y+38)

rect(48,40,42,6,C['accent'])
text(48,62,'OUTBREAK',82,bold=True)
text(51,149,'SISTEMA DE INTERFACE / SOBREVIVÊNCIA COOPERATIVA',22,C['muted'])
text(1100,68,'UI FIELD GUIDE',28,bold=True)
text(1100,106,'v0.1  /  25 OUT 2026',19,C['muted'])
text(1100,137,'PC + MOBILE · ROBLOX',19,C['muted'])
line(48,194,1392,194)
section(220,'01','COR COM FUNÇÃO','Amarelo interage. Ciano identifica. Vermelho alerta.')
swatches=[('panel','GRAFITE'),('surface','SUPERFÍCIE'),('text','TEXTO'),('accent','INTERAÇÃO'),('player','JOGADOR'),('danger','PERIGO'),('fire','FOGO')]
for i,(key,label) in enumerate(swatches):
    x=48+i*194
    rect(x,278,180,62,C[key],4,C['line'] if key in ('panel','surface') else None)
    text(x,354,label,20,bold=True)
    text(x,381,C[key].upper(),18,C['muted'])
section(432,'02','TIPOGRAFIA E RITMO','Oswald para leitura · Bangers para anúncios breves')
text(48,492,'32 / 180',64,bold=True)
text(50,562,'NÚMERO DOMINANTE',18,C['muted'])
text(410,494,'SUPRIMENTOS',36,bold=True)
text(410,541,'Segure para reparar a barricada.',23)
text(410,578,'RÓTULO 18  /  CORPO 20  /  TÍTULO 28',18,C['muted'])
for i,s in enumerate([4,8,12,16,24,32]):
    x=940+i*72
    rect(x,526-s,40,s,C['accent'])
    text(x+8,543,str(s),20,C['muted'])
text(940,578,'ESPAÇAMENTO · UNIDADES DE UI',18,C['muted'])
section(631,'03','COMPONENTES E ESTADOS','Informação essencial primeiro. Estado sempre com rótulo.')
panel(48,691,424,230)
text(68,714,'AÇÕES',20,C['muted'],True)
button(68,750,181,'COMPRAR · 900')
button(263,750,189,'FECHAR',C['surface'],C['text'])
button(68,814,384,'NÍVEL 5 NECESSÁRIO',C['disabled'],C['text'])
text(68,880,'ALVO TOUCH ≥48  /  RAIO 4',18,C['muted'])
panel(488,691,424,230)
text(508,714,'VIDA',20,C['muted'],True)
text(810,705,'82',42,bold=True)
rect(508,757,384,8,C['surface'])
rect(508,757,315,8,C['player'])
text(508,787,'! VIDA BAIXA',22,C['text'],True)
rect(508,820,384,8,C['surface'])
rect(508,820,77,8,C['danger'])
text(508,851,'20 / 100',30,bold=True)
text(686,880,'COR + TEXTO + VALOR',18,C['muted'])
panel(928,691,464,230)
text(948,714,'HABILIDADE',20,C['muted'],True)
rect(948,751,48,48,C['surface'],4)
text(962,763,'Q',27,bold=True)
text(1012,750,'MUNIÇÃO INCENDIÁRIA',25,bold=True)
text(1012,782,'PRONTA',20,C['player'])
line(948,819,1372,819)
text(948,839,'RECARREGANDO',22,bold=True)
text(1310,831,'18 s',32,C['muted'],True)
rect(948,886,424,5,C['surface'])
rect(948,886,254,5,C['player'])
section(953,'04','COMPOSIÇÃO DO COMBATE','Esquema de posição · valores ilustrativos · sem cenário real')
rect(48,1013,1344,364,'#151D25',4,C['line'])
# Abstract empty playfield, deliberately not a Roblox screenshot.
line(48,1285,1392,1285,'#25303B')
panel(72,1037,240,92)
text(90,1051,'VIDA',18,C['muted'],True)
text(246,1047,'82',32,bold=True)
rect(90,1083,204,6,C['surface']); rect(90,1083,167,6,C['player'])
text(90,1100,'CR  1.250',23,C['accent'],True)
text(621,1040,'ONDA 04 / 10',27,bold=True)
text(610,1076,'SOBREVIVA À HORDA',20,C['muted'])
panel(1110,1037,258,92)
text(1130,1050,'32',46,bold=True)
text(1190,1068,'/ 180',26,C['muted'])
text(1130,1100,'AK-47',19,C['muted'],True)
text(1175,1145,'Q  PRONTA   ·   G  2',20,C['player'],True)
# Reticle marks, not an icon asset.
line(708,1195,716,1195,C['text']); line(724,1195,732,1195,C['text'])
line(720,1183,720,1191,C['text']); line(720,1199,720,1207,C['text'])
text(551,1304,'CENTRO E ÁREA DE MIRA LIVRES',23,C['muted'],True)
text(72,1343,'MOBILE: RESERVAR ANALÓGICO + AÇÕES + PULO NATIVO',17,C['muted'])
text(48,1405,'PAINÉIS GRAFITE  /  CANTO AMARELO  /  NÚMEROS CONDENSADOS',22,bold=True)
text(48,1444,'Prancha de especificação. Fontes locais equivalentes na prévia; conferir Oswald/Bangers no Studio.',19,C['muted'])
text(1262,1444,'OUTBREAK / 01',19,C['accent'],True)
svg.append('</svg>')
(OUT/'design-system.svg').write_text('\n'.join(svg),encoding='utf-8')
img.save(OUT/'design-system.png')
print(OUT/'design-system.png')
