#!/usr/bin/env python3
# Generates diagram-workflow.svg (next to this script, i.e. docs/) - a
# vertical flowchart of the Mini-SOC attack -> detection -> response
# workflow, with network-zone swimlanes and "where is it put" annotations
# (ports, file paths, script names). Run after changing the workflow it
# describes; re-export a PNG for the ODT essay with e.g.:
#   libreoffice --headless --convert-to \
#     'png:draw_png_Export:{"PixelWidth":{"type":"long","value":2000},"PixelHeight":{"type":"long","value":2014}}' \
#     docs/diagram-workflow.svg
# (run from a path under $HOME - the snap build can't see /tmp)
import html
import os

W = 1000

# ---- palette --------------------------------------------------------
ZONE_RED    = "#fdeceb"
ZONE_SOC    = "#eaf1fb"
ZONE_SERV   = "#fef6e7"
ZONE_BORDER = "#c9d2dc"
NODE_FILL   = "#ffffff"
NODE_STROKE = "#2c3440"
TEXT        = "#1b2229"
SUBTEXT     = "#5b6572"
ARROW       = "#394351"
ARROW_LABEL = "#3a4552"
STEP_FILL   = "#2c3440"
STEP_TEXT   = "#ffffff"
SANS        = "'Helvetica Neue',Helvetica,Arial,sans-serif"

parts = []

def esc(t):
    return html.escape(t, quote=True)

def text(x, y, s, size=15, fill=TEXT, weight="normal", anchor="start", style="normal"):
    parts.append(f'<text x="{x}" y="{y}" font-size="{size}" fill="{fill}" '
                 f'font-weight="{weight}" text-anchor="{anchor}" font-family="{SANS}" '
                 f'font-style="{style}">{esc(s)}</text>')

def wrapped(x, y, lines, size=13, fill=SUBTEXT, anchor="start", lh=16):
    for i, ln in enumerate(lines):
        text(x, y + i*lh, ln, size=size, fill=fill, anchor=anchor)

def node(x, y, w, h, title, sub_lines=None, title_size=15):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" '
                 f'fill="{NODE_FILL}" stroke="{NODE_STROKE}" stroke-width="1.6"/>')
    ty = y + 23 if sub_lines else y + h/2 + 5
    text(x + w/2, ty, title, size=title_size, weight="bold", anchor="middle")
    if sub_lines:
        wrapped(x + w/2, ty + 19, sub_lines, size=12, fill=SUBTEXT, anchor="middle", lh=15)
    return (x, y, w, h)

def top(n):    x,y,w,h = n; return (x+w/2, y)
def bottom(n): x,y,w,h = n; return (x+w/2, y+h)
def left(n):   x,y,w,h = n; return (x, y+h/2)
def right(n):  x,y,w,h = n; return (x+w, y+h/2)

def straight(x1, y1, x2, y2, step=None, dashed=False, label_lines=None, label_at=0.5, label_dx=12, anchor="start"):
    dash = ' stroke-dasharray="6,5"' if dashed else ''
    parts.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{ARROW}" '
                 f'stroke-width="2"{dash} marker-end="url(#arrowhead)"/>')
    if step is not None:
        sx, sy = x1 + (x2-x1)*0.08, y1 + (y2-y1)*0.08
        parts.append(f'<circle cx="{sx}" cy="{sy}" r="13" fill="{STEP_FILL}"/>')
        text(sx, sy+5, str(step), size=13, fill=STEP_TEXT, weight="bold", anchor="middle")
    if label_lines:
        mx, my = x1 + (x2-x1)*label_at, y1 + (y2-y1)*label_at
        wrapped(mx+label_dx, my-6, label_lines, anchor=anchor)

def curved(x1, y1, x2, y2, cx1, cy1, cx2, cy2, step=None, dashed=False,
           label_lines=None, label_pos=None, anchor="start"):
    dash = ' stroke-dasharray="6,5"' if dashed else ''
    parts.append(f'<path d="M {x1} {y1} C {cx1} {cy1}, {cx2} {cy2}, {x2} {y2}" fill="none" '
                 f'stroke="{ARROW}" stroke-width="2"{dash} marker-end="url(#arrowhead)"/>')
    if step is not None:
        parts.append(f'<circle cx="{x1}" cy="{y1}" r="13" fill="{STEP_FILL}"/>')
        text(x1, y1+5, str(step), size=13, fill=STEP_TEXT, weight="bold", anchor="middle")
    if label_lines and label_pos:
        wrapped(label_pos[0], label_pos[1], label_lines, anchor=anchor)

parts.append('<defs><marker id="arrowhead" markerWidth="10" markerHeight="8" '
             'refX="9" refY="4" orient="auto"><polygon points="0 0, 10 4, 0 8" '
             f'fill="{ARROW}"/></marker></defs>')

text(W/2, 42, "Mini-SOC — attack, detection & response workflow", size=23, weight="bold", anchor="middle")
text(W/2, 66, "What happens, in order, and exactly where each piece of data is written",
     size=14, fill=SUBTEXT, anchor="middle")

# ============================================================ RED zone
zy = 95
parts.append(f'<rect x="40" y="{zy}" width="{W-80}" height="104" rx="10" fill="{ZONE_RED}" stroke="{ZONE_BORDER}"/>')
text(60, zy+22, "RED  10.10.66.0/24", size=13, weight="bold", fill="#8a3b33")
kali = node(W/2-95, zy+28, 190, 64, "kali", ["attacker — nmap, nikto, sqlmap,", "FTP client, curl"])

# fw sits between zones, on the main kali->target line
fw_y = zy + 104 + 44
fw = node(W/2-100, fw_y, 200, 54, "fw  (OPNsense)", ["routes RED → SERVERS, logs the match"])
straight(*bottom(kali), *top(fw), step=1, label_lines=["attack traffic", "(e.g. FTP upload, SQLi)"], label_at=0.45)

# ======================================================== SERVERS zone
zy2 = fw_y + 50 + 40
parts.append(f'<rect x="40" y="{zy2}" width="{W-80}" height="104" rx="10" fill="{ZONE_SERV}" stroke="{ZONE_BORDER}"/>')
text(60, zy2+22, "SERVERS  10.10.20.0/24", size=13, weight="bold", fill="#8a6a1f")
target = node(W/2-130, zy2+32, 260, 58, "target", ["Apache + DVWA at /legacy/", "Wazuh agent (FIM + log watch)"])
straight(*bottom(fw), *top(target), label_at=2)  # short connector, no label/step (continuation of step 1)

# ============================================================ SOC zone
zy3 = zy2 + 104 + 40
soc_h = 470
parts.append(f'<rect x="40" y="{zy3}" width="{W-80}" height="{soc_h}" rx="10" fill="{ZONE_SOC}" stroke="{ZONE_BORDER}"/>')
text(60, zy3+22, "SOC  10.10.10.0/24", size=13, weight="bold", fill="#2c5a94")

sensor = node(60, zy3+40, 230, 62, "sensor  (Suricata)", ["passive tap on SERVERS —", "sees the wire, has no IP"])
# tap point: a small dot on the fw->target line, branching to sensor (not "from target")
tap_x, tap_y = W/2, zy2 - 20
parts.append(f'<circle cx="{tap_x}" cy="{tap_y}" r="4" fill="{ARROW}"/>')
sx, sy = right(sensor)
curved(tap_x-3, tap_y, sx+8, sy, tap_x-120, tap_y+10, sx+120, sy-30,
       dashed=True, label_pos=(sx+30, sy-55),
       label_lines=["taps the same wire", "→ eve-alerts.json"])
parts.append(f'<circle cx="{tap_x-70}" cy="{tap_y+20}" r="13" fill="{STEP_FILL}"/>')
text(tap_x-70, tap_y+25, "2", size=13, fill=STEP_TEXT, weight="bold", anchor="middle")

wazuh = node(W/2-100, zy3+180, 200, 64, "wazuh  (manager)", ["correlates + rates (custom rules)", "→ alerts.json"])

# target agent -> wazuh (step 3): comes straight down the right side, clear of the sensor->wazuh path
x1, y1 = target[0]+target[2]*0.82, target[1]+target[3]
x2, y2 = wazuh[0]+wazuh[2], wazuh[1]+wazuh[3]*0.3
curved(x1, y1, x2, y2, x1+60, y1+80, x2+90, y2-60,
       label_pos=(x2+20, y2-70),
       label_lines=["agent: Apache/vsftpd logs +", "FIM on /var/www/html", "→ :1514/1515"])
parts.append(f'<circle cx="{x1+30}" cy="{y1+25}" r="13" fill="{STEP_FILL}"/>')
text(x1+30, y1+30, "3", size=13, fill=STEP_TEXT, weight="bold", anchor="middle")

# sensor -> wazuh
x1, y1 = bottom(sensor)
x2, y2 = wazuh[0], wazuh[1]+wazuh[3]*0.5
straight(x1, y1, x2, y2, label_at=2)

iris = node(60, zy3+300, 240, 66, "soc — DFIR-IRIS", ["case management"])
greenbone = node(W-60-240, zy3+300, 240, 66, "soc — Greenbone", ["vulnerability scanning"])

x1, y1 = wazuh[0]+wazuh[2]*0.25, wazuh[1]+wazuh[3]
x2, y2 = iris[0]+iris[2]*0.75, iris[1]
curved(x1, y1, x2, y2, x1-40, y1+40, x2+20, y2-40,
       label_pos=(iris[0]+iris[2]+16, iris[1]-26), anchor="start",
       label_lines=["level ≥ 10 alerts auto-forwarded", "(custom-iris.py) → new Alert"])
parts.append(f'<circle cx="{x1-15}" cy="{y1+55}" r="13" fill="{STEP_FILL}"/>')
text(x1-15, y1+60, "4", size=13, fill=STEP_TEXT, weight="bold", anchor="middle")

analyst = node(60, zy3+395, 240, 58, "analyst", ["escalates Alert → Case,", "documents the incident"])
straight(*bottom(iris), *top(analyst), step=5)

# greenbone -> target: scan confirms the root cause (long curve up the right edge)
x1, y1 = top(greenbone)
x2, y2 = right(target)
curved(x1, y1, x2+10, y2, x1, y1-110, x2+150, y2+60, step=6,
       label_pos=(target[0]+target[2]+18, target[1]+target[3]+28), anchor="start",
       label_lines=['on-demand scan confirms the root', 'cause ("Anonymous FTP Login",', '"FTP Writeable Directories")'])

fix = node(W-60-240, zy3+395, 240, 58, "fix applied", ["e.g. fix.sh on target,", "then: rescan confirms clean"])
straight(*bottom(greenbone), *top(fix), step=7)

x1, y1 = right(analyst)
x2, y2 = left(fix)
straight(x1, y1+2, x2, y2+2, step=8, dashed=True, label_lines=["analyst directs the fix"], label_at=0.5, label_dx=-70, anchor="middle")

y_end = zy3 + soc_h + 36
text(W/2, y_end, "See exercises/01-ftp-webshell/ for this exact sequence, run end to end against the real lab.",
     size=13, fill=SUBTEXT, anchor="middle", style="italic")

H = int(y_end + 24)
svg_open = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
            f'viewBox="0 0 {W} {H}" font-family="{SANS}">'
            f'<rect x="0" y="0" width="{W}" height="{H}" fill="#ffffff"/>')

out = svg_open + '\n'.join(parts) + '</svg>'
out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'diagram-workflow.svg')
with open(out_path, 'w', encoding='utf-8') as f:
    f.write(out)
print("wrote", out_path, "height", H)
