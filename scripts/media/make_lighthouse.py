"""Draws scripts/media/lighthouse.png (768x512), the demo picture of the docs media tour:
a lighthouse at dusk in watercolour-like soft shapes. Needs Pillow; the PNG is committed."""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter

W, H = 768, 512
random.seed(7)
def lerp(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
stops = [(0, (58, 52, 120)), (0.55, (186, 110, 150)), (0.82, (244, 170, 130)), (1.0, (250, 214, 160))]
HOR = int(H * 0.68)
for y in range(HOR):
    t = y / HOR
    for i in range(len(stops) - 1):
        if stops[i][0] <= t <= stops[i + 1][0]:
            u = (t - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
            d.line([(0, y), (W, y)], fill=lerp(stops[i][1], stops[i + 1][1], u))
for y in range(HOR, H):
    t = (y - HOR) / (H - HOR)
    d.line([(0, y), (W, y)], fill=lerp((120, 110, 160), (32, 40, 84), t))

# soft clouds
cl = Image.new("RGBA", (W, H), (0, 0, 0, 0)); cd = ImageDraw.Draw(cl)
for _ in range(14):
    x, y = random.randint(0, W), random.randint(30, 230)
    w, h = random.randint(120, 260), random.randint(16, 36)
    cd.ellipse([x - w, y - h, x + w, y + h], fill=(255, 200, 190, 70))
img = Image.alpha_composite(img.convert("RGBA"), cl.filter(ImageFilter.GaussianBlur(14)))

# sea ripples
ov = Image.new("RGBA", (W, H), (0, 0, 0, 0)); od = ImageDraw.Draw(ov)
for _ in range(120):
    x, y = random.randint(0, W), random.randint(HOR + 6, H)
    w = random.randint(20, 90)
    od.line([(x, y), (x + w, y)], fill=(255, 225, 190, 60), width=2)
# light reflection
od.polygon([(470, HOR), (520, HOR), (560, H), (430, H)], fill=(255, 230, 160, 50))

# rocks and lighthouse
od.polygon([(350, HOR + 6), (420, HOR - 40), (520, HOR - 40), (620, HOR + 10), (640, HOR + 40), (330, HOR + 40)], fill=(40, 36, 64, 255))
tx = 470
od.polygon([(tx - 30, HOR - 36), (tx + 30, HOR - 36), (tx + 18, HOR - 230), (tx - 18, HOR - 230)], fill=(244, 232, 226, 255))
for y0 in (HOR - 190, HOR - 120):
    od.polygon([(tx - 26 + (y0 - HOR) * -0.0, y0), (tx + 26, y0), (tx + 22, y0 + 34), (tx - 22, y0 + 34)], fill=(196, 70, 80, 255))
od.rectangle([tx - 26, HOR - 244, tx + 26, HOR - 230], fill=(50, 44, 70, 255))
od.rectangle([tx - 14, HOR - 276, tx + 14, HOR - 244], fill=(255, 236, 150, 255))
od.polygon([(tx - 18, HOR - 276), (tx + 18, HOR - 276), (tx, HOR - 300)], fill=(50, 44, 70, 255))
# light beams
beam = Image.new("RGBA", (W, H), (0, 0, 0, 0)); bd = ImageDraw.Draw(beam)
by = HOR - 260
bd.polygon([(tx, by), (W, by - 70), (W, by + 40)], fill=(255, 240, 170, 110))
bd.polygon([(tx, by), (0, by - 40), (0, by + 60)], fill=(255, 240, 170, 80))
img = Image.alpha_composite(img, ov.filter(ImageFilter.GaussianBlur(1.2)))
img = Image.alpha_composite(img, beam.filter(ImageFilter.GaussianBlur(10)))

# birds, paper grain
bd = ImageDraw.Draw(img)
for x, y in [(140, 120), (180, 100), (110, 160)]:
    bd.arc([x, y, x + 18, y + 12], 200, 340, fill=(60, 50, 90), width=2)
    bd.arc([x + 16, y, x + 34, y + 12], 200, 340, fill=(60, 50, 90), width=2)
noise = Image.effect_noise((W, H), 14).convert("RGB")
img = Image.blend(img.convert("RGB"), Image.blend(img.convert("RGB"), noise, 0.5), 0.04).filter(ImageFilter.GaussianBlur(0.6))
img.save(os.path.join(os.path.dirname(os.path.abspath(__file__)), "lighthouse.png"), optimize=True)
