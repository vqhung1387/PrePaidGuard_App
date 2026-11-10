# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render local, deterministic flow diagrams to SVG/PNG and editable Mermaid.
Run: uv run docs/diagrams/generate_diagrams.py
No network calls. Images and Mermaid share the same flow specifications.
"""
import html
import json
import textwrap
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SPECS = json.loads((ROOT / "flows.json").read_text(encoding="utf-8"))
WIDTH = 1280
MAIN_X, MAIN_W, SIDE_X, SIDE_W = 70, 710, 910, 300
NODE_H, STEP, TOP = 96, 145, 145
FONT_ROOT = Path("C:/Windows/Fonts")

def font(size, bold=False):
    candidates = [FONT_ROOT / ("segoeuib.ttf" if bold else "segoeui.ttf"),
                  FONT_ROOT / ("arialbd.ttf" if bold else "arial.ttf"),
                  Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")]
    for candidate in candidates:
        if candidate.is_file():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default(size=size)

def render(spec):
    height = TOP + len(spec["nodes"]) * STEP + 35
    image = Image.new("RGB", (WIDTH, height), "#f8fafc")
    draw = ImageDraw.Draw(image)
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{height}" viewBox="0 0 {WIDTH} {height}" role="img">',
           f'<title>{html.escape(spec["title"])}</title>',
           f'<desc>{html.escape(spec["subtitle"])}</desc>',
           f'<rect width="{WIDTH}" height="{height}" fill="#f8fafc"/>']

    def line(points, color="#64748b", width=3, arrow=False):
        draw.line(points, fill=color, width=width, joint="curve")
        coords = " ".join(f"{x},{y}" for x, y in points)
        svg.append(f'<polyline points="{coords}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round"/>')
        if arrow:
            x1, y1 = points[-2]
            x2, y2 = points[-1]
            if y1 == y2:
                direction = 1 if x2 > x1 else -1
                tri = [(x2, y2), (x2 - direction * 10, y2 - 5), (x2 - direction * 10, y2 + 5)]
            else:
                direction = 1 if y2 > y1 else -1
                tri = [(x2, y2), (x2 - 5, y2 - direction * 10), (x2 + 5, y2 - direction * 10)]
            draw.polygon(tri, fill=color)
            svg.append(f'<polygon points="{" ".join(f"{x},{y}" for x,y in tri)}" fill="{color}"/>')

    def box(x, y, w, h, fill, stroke, diamond=False):
        if diamond:
            pts = [(x+w/2,y),(x+w,y+h/2),(x+w/2,y+h),(x,y+h/2)]
            draw.polygon(pts, fill=fill)
            draw.line(pts+[pts[0]], fill=stroke, width=2)
            svg.append(f'<polygon points="{" ".join(f"{a},{b}" for a,b in pts)}" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
        else:
            draw.rounded_rectangle((x,y,x+w,y+h),radius=16,fill=fill,outline=stroke,width=2)
            svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')

    def text(x, y, content, size=22, color="#0f172a", bold=False, centered=True):
        draw.text((x,y),content,font=font(size,bold),fill=color,anchor="mt" if centered else "lt")
        svg.append(f'<text x="{x}" y="{y+size}" font-family="Segoe UI, Arial, sans-serif" font-size="{size}" font-weight="{"700" if bold else "400"}" text-anchor="{"middle" if centered else "start"}" fill="{color}">{html.escape(content)}</text>')

    def label_box(x,y,w,h,content,side=False,diamond=False):
        lines = textwrap.wrap(content, width=28 if side else (43 if diamond else 58), break_long_words=False)
        size = 18 if side else 22
        leading = size + 7
        start = y + (h-leading*len(lines))/2
        for j, part in enumerate(lines):
            text(x+w/2,start+j*leading,part,size=size)

    text(45,25,spec["title"],size=32,bold=True,centered=False)
    for j, part in enumerate(textwrap.wrap(spec["subtitle"],width=115)):
        text(45,73+j*24,part,size=18,color="#475569",centered=False)
    for i,node in enumerate(spec["nodes"]):
        y = TOP+i*STEP
        decision = bool(node.get("branch"))
        terminal = i == len(spec["nodes"])-1
        fill, stroke = ("#fef3c7","#d97706") if decision else (("#dcfce7","#16a34a") if terminal else ("#dbeafe","#2563eb"))
        box(MAIN_X,y,MAIN_W,NODE_H,fill,stroke,diamond=decision)
        label_box(MAIN_X,y,MAIN_W,NODE_H,node["text"],diamond=decision)
        if i < len(spec["nodes"])-1:
            center=MAIN_X+MAIN_W/2
            line([(center,y+NODE_H),(center,y+STEP-8)],arrow=True)
            if decision:
                text(center+30,y+NODE_H+7,node.get("label") or "Yes",size=16,color="#475569")
        if decision:
            box(SIDE_X,y,SIDE_W,NODE_H,"#fff1f2","#e11d48")
            label_box(SIDE_X,y,SIDE_W,NODE_H,node["branch"],side=True)
            line([(MAIN_X+MAIN_W,y+NODE_H/2),(SIDE_X-8,y+NODE_H/2)],color="#e11d48",arrow=True)
            text((MAIN_X+MAIN_W+SIDE_X)/2,y+NODE_H/2-25,"No",size=16,color="#be123c")
    text(45,height-39,"PrePaidGuard | Design draft | Read policy B1-B6 in project.md",size=16,color="#64748b",centered=False)
    svg.append("</svg>")
    (ROOT / (spec["file"]+".svg")).write_text("\n".join(svg),encoding="utf-8")
    image.save(ROOT / (spec["file"]+".png"))

    mermaid = ["flowchart TD"]
    for i,node in enumerate(spec["nodes"]):
        content = node["text"].replace('"',"'")
        suffix = '{' if node.get("branch") else '['
        ending = '}' if node.get("branch") else ']'
        mermaid.append(f'  N{i}{suffix}"{content}"{ending}')
        if node.get("branch"):
            branch = node["branch"].replace('"',"'")
            mermaid.append(f'  B{i}["{branch}"]')
            mermaid.append(f'  N{i} -->|No| B{i}')
        if i < len(spec["nodes"])-1:
            arrow = '-->|Yes|' if node.get("branch") else '-->'
            mermaid.append(f'  N{i} {arrow} N{i+1}')
    (ROOT / (spec["file"]+".mmd")).write_text("\n".join(mermaid)+"\n",encoding="utf-8")

for spec in SPECS:
    render(spec)

# Small preview sheet for visual QA; not a source diagram.
thumbs = []
for spec in SPECS:
    with Image.open(ROOT / (spec["file"]+".png")) as image:
        image.thumbnail((390, 510))
        thumbs.append(image.copy())
sheet = Image.new("RGB",(390*4,560*4),"#e2e8f0")
sheet_draw = ImageDraw.Draw(sheet)
for i,thumb in enumerate(thumbs):
    x,y=(i%4)*390,(i//4)*560
    sheet.paste(thumb,(x,y+28))
    sheet_draw.text((x+8,y+4),SPECS[i]["file"],font=font(14),fill="#0f172a")
sheet.save(ROOT / "preview.png")
print(f"Rendered {len(SPECS)} SVG, PNG and Mermaid diagrams.")
