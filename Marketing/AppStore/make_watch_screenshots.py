"""Apple Watch screenshots from watch_light/ captures (46mm, 416x496).

out/watch-46mm: App Store files, clock repainted to 9:41.
out/watch-marketing: white/orange promo slides (1320x2868) matching the iPhone set.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).parent
FILES = [
    ("log", "01-log-set", ["Log sets from", "your wrist"], "Turn the crown to set weight, reps and RIR"),
    ("rest", "02-rest-timer", ["Rest, then", "go again"], "A rest ring that counts down to your next set"),
    ("complete", "03-complete", ["Finish on", "your phone"], "Your watch follows the session on iPhone"),
]
W, H = 1320, 2868
ACCENT, INK, SUBTLE = (250, 107, 46), (28, 28, 30), (110, 110, 116)


def font(size, weight="Bold", name="SFNS"):
    f = ImageFont.truetype(f"/System/Library/Fonts/{name}.ttf", size)
    f.set_variation_by_name(weight)
    return f


def background():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = min(1, y / (H * 0.7))
        d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip((255, 255, 255), (255, 244, 236))))
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


def promo(shot, lines, sub):
    canvas = background().convert("RGBA")
    d = ImageDraw.Draw(canvas)
    y = 150
    for i, line in enumerate(lines):
        d.text((W / 2, y), line, font=font(150), fill=ACCENT if i == 1 else INK, anchor="mt")
        y += 168
    d.text((W / 2, y + 20), sub, font=font(52, "Medium"), fill=SUBTLE, anchor="mt")
    sw = 1080
    shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
    x, top = (W - sw) // 2, 1000
    body = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((x - 40, top - 40, x + sw + 40, top + shot.height + 40), 270, fill=(28, 28, 30, 255))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x - 40, top - 10, x + sw + 40, top + shot.height + 70), 270, fill=(120, 70, 40, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(40)))
    canvas.alpha_composite(body)
    canvas.alpha_composite(rounded(shot, 220), (x, top))
    return canvas.convert("RGB")


clock = font(33, "Semibold")
(ROOT / "out/watch-46mm").mkdir(parents=True, exist_ok=True)
(ROOT / "out/watch-marketing").mkdir(parents=True, exist_ok=True)
for src, dst, lines, sub in FILES:
    img = Image.open(ROOT / "watch_light" / f"{src}.png").convert("RGB")
    d = ImageDraw.Draw(img)
    d.rectangle((290, 28, 416, 78), fill=(0, 0, 0))
    d.text((385, 53), "9:41", font=clock, fill=(255, 255, 255), anchor="rm")
    img.save(ROOT / "out/watch-46mm" / f"{dst}.png")
    promo(img, lines, sub).save(ROOT / "out/watch-marketing" / f"{dst}.png")
    print("wrote", dst)
