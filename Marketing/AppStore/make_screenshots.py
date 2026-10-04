"""Compose App Store marketing screenshots from raw simulator captures.

Raw captures (raw/*.png) must come from an iPhone 17 Pro Max simulator (1320x2868).
Outputs: out/6.9-inch (1320x2868) and out/6.5-inch (1284x2778).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).parent
W, H = 1320, 2868
BG_TOP, BG_BOTTOM = (255, 255, 255), (255, 244, 236)
ACCENT = (250, 107, 46)
INK = (28, 28, 30)
SUBTLE = (110, 110, 116)

SLIDES = [
    ("01-home", ["Know what to", "train today"], 1, "Check-in, freshness and your next workout"),
    ("05-live", ["Log every set", "in seconds"], 1, "Weight, reps and RIR with PR badges"),
    ("02-muscle", ["See what's", "recovered"], 1, "Per-muscle freshness from your training load"),
    ("03-stress", ["Train smart,", "not just hard"], 1, "A daily stress score for lifting and cardio"),
    ("04-records", ["Track every", "PR"], 1, "Estimated 1RMs and projected next records"),
    ("08-cardio", ["Cardio and", "steps too"], 1, "Runs, rides and hikes from Apple Health"),
    ("06-programs", ["Rotations that", "run themselves"], 1, "Your next day, always one tap away"),
    ("07-catalog", ["Every lift,", "searchable"], 1, "Filter by category, equipment or muscle"),
    ("10-widgets", ["Your training,", "at a glance"], 1, "Home Screen, StandBy and Lock Screen widgets"),
    ("09-customize", ["Make it", "yours"], 1, "Accent colors, themes and the units you use"),
]

def font(size, weight="Bold"):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    f.set_variation_by_name(weight)
    return f

def gradient():
    img = Image.new("RGB", (W, H))
    px = ImageDraw.Draw(img)
    for y in range(H):
        t = min(1, y / (H * 0.7))
        px.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    glow = Image.new("RGB", (W, H), ACCENT)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse((W * 0.1, -H * 0.12, W * 0.9, H * 0.16), fill=38)
    return Image.composite(glow, img, mask.filter(ImageFilter.GaussianBlur(220)))

def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out

def compose(name, lines, accent_line, sub):
    canvas = gradient().convert("RGBA")
    d = ImageDraw.Draw(canvas)
    y = 150
    for i, line in enumerate(lines):
        d.text((W / 2, y), line, font=font(150), fill=ACCENT if i == accent_line else INK, anchor="mt")
        y += 168
    d.text((W / 2, y + 20), sub, font=font(52, "Medium"), fill=SUBTLE, anchor="mt")

    shot = Image.open(ROOT / "raw_light" / f"{name}.png").convert("RGB")
    sw = 960
    shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
    phone = rounded(shot, 120)
    x, top = (W - sw) // 2, 700
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, top + 30, x + sw, top + 30 + shot.height), 120, fill=(120, 70, 40, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(40)))
    border = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((x - 8, top - 8, x + sw + 8, top + shot.height + 8), 128, fill=(226, 226, 230, 255))
    canvas.alpha_composite(border)
    canvas.alpha_composite(phone, (x, top))
    return canvas.convert("RGB")

for sub_dir, size in (("6.9-inch", (1320, 2868)), ("6.5-inch", (1284, 2778))):
    (ROOT / "out" / sub_dir).mkdir(parents=True, exist_ok=True)
for name, lines, accent_line, sub in SLIDES:
    img = compose(name, lines, accent_line, sub)
    img.save(ROOT / "out/6.9-inch" / f"{name}.png")
    img.resize((1284, 2778), Image.LANCZOS).save(ROOT / "out/6.5-inch" / f"{name}.png")
    print("wrote", name)
