from PIL import Image, ImageDraw
import math

BG = (31, 61, 46, 255)        # deep forest green
BG2 = (22, 43, 33, 255)       # darker shade for ground shadow
LEAF = (241, 232, 213, 255)   # warm cream
LEAF_SHADE = (223, 210, 184, 255)
ACCENT = (196, 92, 48, 255)   # terracotta

def leaf_points(base, length, width, angle_deg, curve=0.55, n=24):
    """Leaf silhouette: base point, growing along local +y (before rotation),
    pointed tip, asymmetric-ish width profile for a natural look."""
    pts_right = []
    pts_left = []
    for i in range(n+1):
        t = i / n
        w = math.sin(math.pi * t) ** 0.65 * width * (1 - 0.15*t)
        y = -t * length
        # slight forward curve
        x_bend = curve * width * math.sin(math.pi * t) * 0.5
        pts_right.append((x_bend + w/2, y))
        pts_left.append((x_bend - w/2, y))
    outline = pts_right + list(reversed(pts_left))
    rad = math.radians(angle_deg)
    cos_a, sin_a = math.cos(rad), math.sin(rad)
    out = []
    for (x, y) in outline:
        rx = x*cos_a - y*sin_a
        ry = x*sin_a + y*cos_a
        out.append((base[0]+rx, base[1]+ry))
    return out

def make_icon(size, path, maskable=False):
    S = size
    img = Image.new("RGBA", (S, S), (0,0,0,0))
    d = ImageDraw.Draw(img)

    radius = int(S * (0.22 if not maskable else 0.0))
    d.rounded_rectangle((0, 0, S-1, S-1), radius=radius, fill=BG)

    # ground mound
    gy = S*0.66
    d.pieslice((int(-S*0.15), int(gy), int(S*1.15), int(gy+S*0.95)), 180, 360, fill=BG2)

    base = (S*0.5, gy)

    # stem
    stem_w = max(2, int(S*0.032))
    d.line([(base[0], base[1]), (base[0], base[1]-S*0.14)], fill=LEAF, width=stem_w)
    stem_top = (base[0], base[1]-S*0.14)

    # two symmetric leaves + one center leaf for fullness
    left = leaf_points(stem_top, S*0.30, S*0.20, -34)
    right = leaf_points(stem_top, S*0.30, S*0.20, 34)
    center = leaf_points(stem_top, S*0.36, S*0.16, 0)

    d.polygon(left, fill=LEAF_SHADE)
    d.polygon(right, fill=LEAF_SHADE)
    d.polygon(center, fill=LEAF)

    # midrib lines
    def midrib(base, length, angle_deg):
        rad = math.radians(angle_deg)
        tip = (base[0] + length*math.sin(rad)*0 - length*math.sin(rad), base[1])
        end = (base[0] + length*math.sin(rad), base[1] - length*math.cos(rad))
        d.line([base, end], fill=(210,196,166,255), width=max(1,int(S*0.008)))

    midrib(stem_top, S*0.34, 0)
    midrib(stem_top, S*0.28, -34)
    midrib(stem_top, S*0.28, 34)

    # terracotta sun/seed accent
    dot_r = S*0.045
    dot_c = (S*0.76, S*0.20)
    d.ellipse((dot_c[0]-dot_r, dot_c[1]-dot_r, dot_c[0]+dot_r, dot_c[1]+dot_r), fill=ACCENT)

    img.save(path)

make_icon(192, "/root/farmlog-app/icons/icon-192.png")
make_icon(512, "/root/farmlog-app/icons/icon-512.png")
make_icon(512, "/root/farmlog-app/icons/icon-maskable-512.png", maskable=True)
print("done")
