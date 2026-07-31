#!/usr/bin/env python3
"""
A paper mock-up of the watch screens, at true 416x416, from real feed values.

This is not a simulator screenshot — it is the same layout arithmetic as
FaceView.mc and PagesView.mc, drawn with PIL so the composition can be judged
before anyone plugs a watch in. If you move a number in the Monkey C, move it
here too, or this stops telling the truth.

    python garmin/preview.py [path-to-watch.json]
"""
import json, math, pathlib, sys
from PIL import Image, ImageDraw, ImageFont

W = H = 416
SS = 3                      # supersample, then downscale for clean edges

DARK = dict(paper=(0, 0, 0), ink=(242, 239, 230), red=(232, 86, 74),
            blue=(111, 168, 220), gold=(232, 185, 58), green=(79, 184, 120),
            dim=(138, 133, 120), grid=(58, 55, 48))
PAPER = dict(paper=(242, 239, 230), ink=(26, 26, 26), red=(192, 57, 43),
             blue=(46, 95, 148), gold=(212, 160, 23), green=(46, 125, 79),
             dim=(107, 100, 85), grid=(201, 194, 174))

FONTDIRS = ["/usr/share/fonts/truetype/dejavu", "/usr/share/fonts/truetype"]
# (path, regular, bold) fallbacks so the tool works on Windows too
FALLBACKS = [(r"C:\Windows\Fonts", "georgia.ttf", "georgiab.ttf")]


def font(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    for d in FONTDIRS:
        p = pathlib.Path(d) / name
        if p.exists():
            return ImageFont.truetype(str(p), size * SS)
    for d, reg, bld in FALLBACKS:
        p = pathlib.Path(d) / (bld if bold else reg)
        if p.exists():
            return ImageFont.truetype(str(p), size * SS)
    return ImageFont.load_default()


def spaced(d, x, y, text, f, fill, extra, anchor="mm"):
    """Letter-spaced small caps, the way Draw.spacedText sets them."""
    text = text.upper()
    widths = [d.textlength(c, font=f) for c in text]
    total = sum(widths) + extra * SS * (len(text) - 1)
    cx = x * SS - total / 2 if anchor == "mm" else x * SS
    for c, w in zip(text, widths):
        d.text((cx, y * SS), c, font=f, fill=fill, anchor="lm")
        cx += w + extra * SS


def ornament(d, cx, y, half, P):
    d.line([(cx - half) * SS, y * SS, (cx - 7) * SS, y * SS], fill=P["grid"], width=SS)
    d.line([(cx + 7) * SS, y * SS, (cx + half) * SS, y * SS], fill=P["grid"], width=SS)
    d.polygon([(cx * SS, (y - 3) * SS), ((cx + 3) * SS, y * SS),
               (cx * SS, (y + 3) * SS), ((cx - 3) * SS, y * SS)], fill=P["red"])


def arrow(d, cx, cy, size, trend, color):
    h = size / 2
    if not trend:
        d.line([(cx - h) * SS, cy * SS, (cx + h) * SS, cy * SS], fill=color, width=2 * SS)
        return
    rise = h if abs(trend) == 2 else h * 3 / 5
    dy = -rise if trend > 0 else rise
    d.line([(cx - h) * SS, (cy - dy) * SS, (cx + h) * SS, (cy + dy) * SS],
           fill=color, width=2 * SS)
    tx, ty = cx + h, cy + dy
    if trend > 0:
        pts = [(tx, ty), (tx - 7, ty + 2), (tx - 2, ty + 7)]
    else:
        pts = [(tx, ty), (tx - 7, ty - 2), (tx - 2, ty - 7)]
    d.polygon([(a * SS, b * SS) for a, b in pts], fill=color)


LADDER = ["STORM", "UNSETTLED", "SHIFTING", "FAIR", "SETTLED"]

# The Divide's profile — mirror of Draw.RIDGE; 82 is the valley floor.
RIDGE = [(58, 82), (84, 74), (104, 60), (116, 67), (132, 54), (144, 62),
         (166, 70), (190, 64), (212, 72), (242, 66), (268, 75), (300, 71),
         (330, 78), (358, 82)]


def ridgeline(d, base_y, amp, color, snow=False):
    pts = [(x * SS, (base_y - (82 - y) * amp) * SS) for x, y in RIDGE]
    d.line(pts, fill=color, width=2 * SS, joint="curve")
    if snow:
        for ai, li, ri in ((2, 1, 3), (4, 3, 5)):
            a, l, r = RIDGE[ai], RIDGE[li], RIDGE[ri]
            cap = [(l[0] + (a[0] - l[0]) * .45, l[1] + (a[1] - l[1]) * .45),
                   a,
                   (r[0] + (a[0] - r[0]) * .45, r[1] + (a[1] - r[1]) * .45)]
            d.polygon([(x * SS, (base_y - (82 - y) * amp) * SS) for x, y in cap],
                      fill=color)


def sun_arc(d, frac, peak_y, base_y, dot_color, sun_color):
    x0, x1, steps = 84, 332, 39
    for i in range(0, steps + 1, 3):
        t = i / steps
        x = x0 + (x1 - x0) * t
        y = base_y - (base_y - peak_y) * math.sin(t * math.pi)
        d.ellipse([(x - .8) * SS, (y - .8) * SS, (x + .8) * SS, (y + .8) * SS],
                  fill=dot_color)
    if frac is not None and 0.0 <= frac <= 1.0:
        x = x0 + (x1 - x0) * frac
        y = base_y - (base_y - peak_y) * math.sin(frac * math.pi)
        d.ellipse([(x - 5) * SS, (y - 5) * SS, (x + 5) * SS, (y + 5) * SS],
                  fill=sun_color)


def dutch_scale(d, x, y, w, seg, P):
    n, step = 5, w / 5
    d.line([x * SS, y * SS, (x + w) * SS, y * SS], fill=P["grid"], width=SS)
    for i in range(n + 1):
        tx = x + i * step
        d.line([tx * SS, (y - 4) * SS, tx * SS, (y + 4) * SS], fill=P["grid"], width=SS)
    cx = x + seg * step + step / 2
    d.polygon([(cx * SS, (y + 5) * SS), ((cx + 5) * SS, (y + 12) * SS),
               ((cx - 5) * SS, (y + 12) * SS)], fill=P["red"])


def trace(d, series, x, y, w, h, color, pen=2):
    if not series or len(series) < 2:
        return None
    lo, hi = min(series), max(series)
    span = (hi - lo) or 1
    pts = []
    for i, v in enumerate(series):
        pts.append(((x + w * i / (len(series) - 1)) * SS,
                    (y + h - (v - lo) * h / span) * SS))
    d.line(pts, fill=color, width=pen * SS, joint="curve")
    return lo, hi


def rose(d, cx, cy, r, shares, live, P):
    d.ellipse([(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS],
              outline=P["grid"], width=SS)
    d.ellipse([(cx - r / 2) * SS, (cy - r / 2) * SS, (cx + r / 2) * SS, (cy + r / 2) * SS],
              outline=P["grid"], width=SS)

    def polar(rr, a):
        a = math.radians(a)
        return (cx + rr * math.sin(a)) * SS, (cy - rr * math.cos(a)) * SS

    if shares:
        top = max(max(shares), 1)
        for i, sh in enumerate(shares):
            if sh <= 0:
                continue
            ln = (r - 4) * sh / top
            if ln < 3:
                continue
            a = i * 22.5
            d.polygon([(cx * SS, cy * SS), polar(ln / 4, a - 9),
                       polar(ln, a), polar(ln / 4, a + 9)], fill=P["blue"])
    if live is not None:
        d.polygon([polar(r - 2, live), polar(6, live + 90), polar(6, live - 90)],
                  fill=P["red"])


DIRS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


def dirname(deg):
    return "--" if deg is None else DIRS[int(round(deg / 22.5)) % 16]


def new(P):
    im = Image.new("RGB", (W * SS, H * SS), P["paper"])
    return im, ImageDraw.Draw(im)


def finish(im, name):
    im = im.resize((W, H), Image.LANCZOS)
    # a hairline bezel, so the round crop is obvious in a flat PNG
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, W - 1, H - 1], fill=255)
    out = Image.new("RGB", (W, H), (18, 18, 18))
    out.paste(im, (0, 0), mask)
    out.save(name)
    return name


def face(d, w, P, winter=None):
    import datetime
    if winter is None:
        m = datetime.date.today().month
        winter = m >= 11 or m <= 4
    spaced(d, 208, 30, "Horseshoe Station", font(12), P["blue"], 3)

    frac = None
    if w.get("sr") and w.get("ss") and w["ss"] > w["sr"]:
        import time as _t
        frac = (_t.time() - w["sr"] / 1000) / ((w["ss"] - w["sr"]) / 1000)
    sun_arc(d, frac, 58 if winter else 46, 78, P["grid"], P["gold"])
    ridgeline(d, 82, 1.0, P["ink"], snow=winter)

    d.text((208 * SS, 122 * SS), "10:42", font=font(62, True), fill=P["ink"], anchor="mm")

    spaced(d, 208, 162, "THU 30 JUL  5:58 - 20:17", font(12), P["dim"], 1)
    d.line([58 * SS, 186 * SS, 358 * SS, 186 * SS], fill=P["grid"], width=SS)

    d.text((208 * SS, 216 * SS), f"{round(w['temp'])}°", font=font(46, True),
           fill=P["ink"], anchor="mm")
    spaced(d, 208, 252, f"feels {w['feels']}", font(12), P["red"], 1)

    spaced(d, 90, 200, "Wind", font(12), P["blue"], 2)
    d.text((90 * SS, 220 * SS), f"{w['dirn']} {round(w['wind'])}", font=font(18),
           fill=P["ink"], anchor="mm")
    d.text((90 * SS, 244 * SS), f"g {round(w['gust'])}", font=font(13),
           fill=P["red"], anchor="mm")

    spaced(d, 326, 200, "Baro", font(12), P["blue"], 2)
    d.text((326 * SS, 220 * SS), f"{w['bar']:.2f}", font=font(18),
           fill=P["ink"], anchor="mm")
    arrow(d, 326, 250, 26, w["trend"], P["red"] if w["trend"] < 0 else
          (P["blue"] if w["trend"] > 0 else P["gold"]))

    dutch_scale(d, 100, 288, 216, w["dutch"], P)
    spaced(d, 208, 310, LADDER[w["dutch"]], font(12), P["ink"], 3)
    spaced(d, 208, 330, w["trendw"], font(12),
           P["blue"] if w["trend"] > 0 else P["red"], 2)

    # alert > fire > the season's line (summer UV, winter daylight) > rain
    if w.get("alert"):
        banner, col = w["alert"], P["red"]
    elif w.get("fire"):
        banner, col = w["fire"], P["gold"]
    elif winter:
        banner, col = "daylight 4 h 12 m left", P["gold"]
    elif (w.get("uv") or 0) >= 3:
        uv = w["uv"]
        burn = 10 if uv >= 11 else 15 if uv >= 8 else 25 if uv >= 6 else 45
        banner, col = f"UV {uv} - burn {burn} min", P["gold"]
    else:
        banner, col = f"rain {w['rain']:.2f} in", P["blue"]
    spaced(d, 208, 356, banner[:30], font(11), col, 1)


def page_glass(d, w, P):
    spaced(d, 208, 48, "Storm Watch", font(13), P["blue"], 4)
    ridgeline(d, 84, 0.55, P["grid"])
    d.text((208 * SS, 118 * SS), f"{w['bar']:.2f}", font=font(44, True),
           fill=P["ink"], anchor="mm")
    spaced(d, 208, 152, f"inches - abs {w['barabs']:.2f}", font(11), P["dim"], 1)
    tcol = P["blue"] if w["trend"] > 0 else P["red"]
    arrow(d, 152, 182, 28, w["trend"], tcol)
    spaced(d, 226, 180, w["trendw"], font(12), tcol, 2)
    words = w["verdict"].split()
    mid = len(words) // 2 + 1
    d.text((208 * SS, 208 * SS), " ".join(words[:mid]), font=font(11),
           fill=P["dim"], anchor="mm")
    d.text((208 * SS, 224 * SS), " ".join(words[mid:]), font=font(11),
           fill=P["dim"], anchor="mm")
    dutch_scale(d, 96, 250, 224, w["dutch"], P)
    spaced(d, 208, 272, LADDER[w["dutch"]], font(12), P["ink"], 3)
    spaced(d, 96, 296, "Pressure - 24 h", font(10), P["blue"], 1, anchor="lm")
    trace(d, w["bt"], 96, 306, 224, 40, P["ink"])
    d.line([96 * SS, 348 * SS, 320 * SS, 348 * SS], fill=P["grid"], width=SS)
    spaced(d, 208, 366, "8 min old", font(10), P["dim"], 1)
    dots(d, 0, P)


def page_wind(d, w, P):
    spaced(d, 208, 48, "The Wind", font(13), P["blue"], 4)
    ridgeline(d, 84, 0.55, P["grid"])
    rose(d, 208, 168, 66, w["rose"], w["dir"], P)
    d.text((208 * SS, 246 * SS), f"{w['dirn']}   {round(w['wind'])}   g {round(w['gust'])}",
           font=font(19), fill=P["ink"], anchor="mm")
    spaced(d, 208, 276, f"Force {w['bf']} - {w['bfw']}", font(11), P["blue"], 1)
    spaced(d, 208, 294, f"max {round(w['maxgust'])} today - {w['prev']} prevails",
           font(10), P["dim"], 1)
    trace(d, w["gt"], 96, 314, 224, 34, P["red"])
    d.line([96 * SS, 350 * SS, 320 * SS, 350 * SS], fill=P["grid"], width=SS)
    dots(d, 1, P)


def dots(d, active, P):
    gap, y = 14, 388
    x0 = 208 - gap * 1.5
    for i in range(4):
        x = x0 + i * gap
        if i == active:
            d.ellipse([(x - 4) * SS, (y - 4) * SS, (x + 4) * SS, (y + 4) * SS], fill=P["red"])
        else:
            d.ellipse([(x - 3) * SS, (y - 3) * SS, (x + 3) * SS, (y + 3) * SS],
                      outline=P["grid"], width=SS)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else None
    if src:
        w = json.loads(pathlib.Path(src).read_text())
    else:
        sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "renderer"))
        import build, watch_build
        cur, hist, nws, alerts, aqi, fire = build.mock_data()
        w = watch_build.build_watch(dict(cur=cur, hist=hist, nws=nws, alerts=alerts,
                                         aqi=aqi, fire=fire, logbook={},
                                         now=build.now_ms()))
    out = []
    for name, fn, P in (("face-dark", face, DARK), ("face-paper", face, PAPER),
                        ("face-winter", lambda d, w, P: face(d, w, P, winter=True), DARK),
                        ("face-summer", lambda d, w, P: face(d, w, P, winter=False), DARK),
                        ("page-glass", page_glass, DARK), ("page-wind", page_wind, DARK)):
        im, d = new(P)
        fn(d, w, P)
        out.append(finish(im, f"preview-{name}.png"))
    print("\n".join(out))


if __name__ == "__main__":
    main()
