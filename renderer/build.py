#!/usr/bin/env python3
"""
Horseshoe Station — cloud renderer.
Fetches station + forecast + air + fire-ban data, keeps the daily logbook,
renders every active page as an 800x480 Spectra-6 PNG, and stages the site/.

Run modes:
  python build.py            normal (needs AWN_API_KEY / AWN_APP_KEY env)
  MOCK=1 python build.py     synthetic data, no network (for testing)
"""
import os, re, json, time, math, random, datetime, subprocess, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
DATA = ROOT / "data"
LOGBOOK = DATA / "logbook.json"
TZ = "America/Denver"
LAT, LON = 39.9693, -105.4951
MAC = "34:5F:45:66:8E:40"
UA = {"User-Agent": "HorseshoeStation/1.0 (personal weather frame; mountainautorepair@gmail.com)"}

MOCK = os.environ.get("MOCK") == "1"
if not MOCK:
    import requests

def now_ms():
    return int(time.time() * 1000)

def local_today():
    import zoneinfo
    return datetime.datetime.now(zoneinfo.ZoneInfo(TZ)).date()

# ---------------- fetchers ----------------
def awn_get(url, tries=4):
    for i in range(tries):
        r = requests.get(url, timeout=20, headers=UA)
        if r.status_code == 429:
            time.sleep(2.5 * (i + 1)); continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError("AWN rate limited")

def fetch_awn():
    api = os.environ["AWN_API_KEY"]; app = os.environ["AWN_APP_KEY"]
    base = "https://rt.ambientweather.net/v1/devices"
    q = f"applicationKey={app}&apiKey={api}"
    devs = awn_get(f"{base}?{q}")
    cur = devs[0]["lastData"]
    recs, end = [], None
    for _ in range(5):
        u = f"{base}/{MAC}?{q}&limit=288" + (f"&endDate={end}" if end else "")
        time.sleep(1.3)
        batch = awn_get(u)
        if not batch: break
        recs += batch
        end = batch[-1]["dateutc"] - 60000
    recs.reverse()
    return cur, recs

# The Chart's company: name, lat, lon, elevation m (Open-Meteo wants meters),
# elevation ft (what the page prints)
NEIGHBORS = [
    ("The Divide", 40.0128, -105.6440, 3630, 11906),   # Arapaho Pass
    ("Ward", 40.0722, -105.5089, 2880, 9450),
    ("Eldora", 39.9472, -105.5828, 2710, 8890),
    ("Gold Hill", 40.0630, -105.4101, 2530, 8300),
    ("Rollinsville", 39.9169, -105.5022, 2461, 8074),
    ("Boulder", 40.0150, -105.2705, 1624, 5328),
]

def fetch_neighbors():
    try:
        r = requests.get(
            "https://api.open-meteo.com/v1/forecast"
            "?latitude=" + ",".join(str(p[1]) for p in NEIGHBORS)
            + "&longitude=" + ",".join(str(p[2]) for p in NEIGHBORS)
            + "&elevation=" + ",".join(str(p[3]) for p in NEIGHBORS)
            + "&current=temperature_2m,weather_code,wind_speed_10m,"
              "wind_gusts_10m,wind_direction_10m"
            + "&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=auto",
            timeout=20, headers=UA).json()
        arr = r if isinstance(r, list) else [r]
        out = []
        for p, d in zip(NEIGHBORS, arr):
            c = d.get("current") or {}
            out.append(dict(name=p[0], lat=p[1], lon=p[2], elev=p[4],
                            tempf=c.get("temperature_2m"), code=c.get("weather_code"),
                            windmph=c.get("wind_speed_10m"), gustmph=c.get("wind_gusts_10m"),
                            winddir=c.get("wind_direction_10m")))
        return out
    except Exception:
        return None                      # the chart still draws, temps show em-dashes

def mock_neighbors(cur):
    codes = [2, 1, 2, 0, 1, 3]
    winds = [(22, 38, 275), (9, 15, 250), (7, 12, 240), (5, 9, 230), (6, 11, 245), (4, 8, 160)]
    out = []
    for p, code, w in zip(NEIGHBORS, codes, winds):
        out.append(dict(name=p[0], lat=p[1], lon=p[2], elev=p[4],
                        tempf=round(cur["tempf"] - (p[4] - 8373) * 3.3 / 1000, 1),
                        code=code, windmph=w[0], gustmph=w[1], winddir=w[2]))
    return out

def fetch_nws():
    try:
        p = requests.get(f"https://api.weather.gov/points/{LAT},{LON}", timeout=20, headers=UA).json()
        f = requests.get(p["properties"]["forecast"], timeout=20, headers=UA).json()
        periods = f["properties"]["periods"]
    except Exception:
        periods = None
    try:
        a = requests.get(f"https://api.weather.gov/alerts/active?point={LAT},{LON}", timeout=20, headers=UA).json()
        alerts = [x["properties"] for x in a.get("features", [])]
    except Exception:
        alerts = []
    return periods, alerts

def fetch_aqi():
    try:
        a = requests.get(
            "https://air-quality-api.open-meteo.com/v1/air-quality"
            f"?latitude={LAT}&longitude={LON}&current=us_aqi,pm2_5,pm10&timezone=auto",
            timeout=20, headers=UA).json()
        return a.get("current")
    except Exception:
        return None

FIRE_SOURCES = [
    "https://bouldercounty.gov/disasters/wildfires/fire-restriction-and-ban-info/",
    "https://bouldercounty.gov/safety/fire/fire-restrictions/",
    "https://www.nfpd.org/",
]
def fetch_fire_ban():
    for url in FIRE_SOURCES:
        try:
            html = requests.get(url, timeout=25, headers=UA).text
            text = re.sub(r"<[^>]+>", " ", html)
            m = re.search(r"Stage\s*([123])\s*(?:Fire\s*)?(?:Restrictions?|Ban)", text, re.I)
            if m:
                return {"stage": f"Stage {m.group(1)} fire restrictions", "src": url}
            if re.search(r"no\s+(?:current\s+)?fire\s+(?:restrictions|bans?)", text, re.I):
                return {"stage": None, "src": url}
        except Exception:
            continue
    return {"stage": None, "src": None}

# ---------------- mock data (testing) ----------------
def mock_data():
    random.seed(3)
    now = now_ms(); recs = []
    for i in range(1440, -1, -1):
        t = now - i * 2 * 60 * 1000
        h = (now - t) / 3.6e6
        rel = round(29.52 + 0.045 * math.sin(h / 24 * 4 * math.pi + 1.1)
                    - 0.12 * math.exp(-((h - 30) / 6) ** 2) + 0.0025 * (48 - h), 3)
        gust = max(1, 6 + 7 * max(0, math.sin(h / 24 * 2 * math.pi + .4))
                   + 30 * math.exp(-((h - 31) / 3.2) ** 2))
        lh = (datetime.datetime.utcfromtimestamp(t / 1000).hour - 6 +
              datetime.datetime.utcfromtimestamp(t / 1000).minute / 60) % 24
        solar = max(0, math.cos((lh - 12.6) / 6.8 * math.pi / 2)) * 934
        recs.append(dict(dateutc=t, tempf=61 + 14 * math.sin((h % 24) / 24 * 2 * math.pi + 3.6),
                         humidity=42, baromrelin=rel, windspeedmph=gust * 0.5, windgustmph=gust,
                         winddir=(255 + 18 * math.sin(h * 0.9)) % 360, solarradiation=solar,
                         uv=round(solar / 100), hourlyrainin=0, dailyrainin=0.12,
                         tempinf=71 + 9 * math.sin((h % 24) / 24 * 2 * math.pi + 3.4), humidityin=45))
    cur = dict(recs[-1])
    cur.update(feelsLike=cur["tempf"], dewPoint=44, baromabsin=round(cur["baromrelin"] - 7.27, 3),
               maxdailygust=17.2, dailyrainin=0.12, weeklyrainin=0.15, monthlyrainin=0.76,
               yearlyrainin=4.57, lastRain="2026-07-24T02:48:00.000Z", tz=TZ)
    periods = []
    names = [("Today", True), ("Tonight", False)] + [(d + s, s == " ") for d in
             ["Saturday", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday"] for s in [" ", " Night"]]
    base = datetime.datetime.now(datetime.timezone.utc)
    for i, (nm, isday) in enumerate(names[:14]):
        periods.append(dict(name=nm.strip(), isDaytime=(i % 2 == 0),
                            startTime=(base + datetime.timedelta(hours=12 * i)).isoformat(),
                            temperature=75 - (i % 5) if i % 2 == 0 else 48,
                            shortForecast=["Sunny", "Partly Cloudy", "Chance T-storms", "Mostly Sunny",
                                           "Slight Chance Rain Showers", "Sunny", "Partly Sunny"][i % 7],
                            detailedForecast="Sunny, with a high near 75. Southwest wind 5 to 10 mph.",
                            probabilityOfPrecipitation={"value": [10, 20, 40, 10, 30, 0, 20][i % 7]},
                            windSpeed="5 to 10 mph", windDirection="WSW"))
    return cur, recs, periods, [], {"us_aqi": 62, "pm2_5": 19, "pm10": 31}, \
           {"stage": "Stage 1 fire restrictions", "src": "mock"}

# ---------------- logbook ----------------
def update_logbook(cur, hist):
    DATA.mkdir(exist_ok=True)
    book = {}
    if LOGBOOK.exists():
        book = json.loads(LOGBOOK.read_text())
    import zoneinfo
    tz = zoneinfo.ZoneInfo(TZ)
    today = datetime.datetime.now(tz).date().isoformat()
    days = {}
    for r in hist:
        d = datetime.datetime.fromtimestamp(r["dateutc"] / 1000, tz).date().isoformat()
        days.setdefault(d, []).append(r)
    for d, rs in days.items():
        temps = [r["tempf"] for r in rs if r.get("tempf") is not None]
        gusts = [r["windgustmph"] for r in rs if r.get("windgustmph") is not None]
        rains = [r.get("dailyrainin") or 0 for r in rs]
        hums = [r["humidity"] for r in rs if r.get("humidity") is not None]
        if not temps: continue
        e = book.get(d, {})
        e["hi"] = round(max(temps + [e.get("hi", -99)]), 1)
        e["lo"] = round(min(temps + [e.get("lo", 199)]), 1)
        e["gust"] = round(max(gusts + [e.get("gust", 0)]), 1) if gusts else e.get("gust", 0)
        e["rain"] = round(max(rains + [e.get("rain", 0)]), 2)
        e["rh_min"] = round(min(hums + [e.get("rh_min", 100)])) if hums else e.get("rh_min")
        book[d] = e
    LOGBOOK.write_text(json.dumps(book, indent=0, sort_keys=True))
    return book

# ---------------- rotation ----------------
def decide_pages(now_local, aqi, alerts, month):
    cycle = ["glass", "wind", "week", "chart", "glasshouse"]
    if 4 <= month - 1 <= 9:                     # May..Oct (month is 1-based)
        cycle.append("fire")
    if month in (11, 12, 1, 2, 3):
        cycle.append("winter")
    cycle += ["almanack", "season", "records"]
    if aqi and (aqi.get("us_aqi") or 0) > 100:
        cycle.append("smoke")
    if any(re.search("red flag", a.get("event", ""), re.I) for a in alerts) and "fire" not in cycle:
        cycle.append("fire")
    slot = (now_local.hour * 60 + now_local.minute) // 10
    current = cycle[slot % len(cycle)]
    return cycle, current

# ---------------- render ----------------
def render_pages(data, cycle):
    from PIL import Image
    from playwright.sync_api import sync_playwright

    tpl = (ROOT / "renderer" / "render.html").read_text()
    SITE.mkdir(exist_ok=True)
    # Spectra 6 palette for quantization
    pal = [0x1a, 0x1a, 0x1a, 0xf2, 0xef, 0xe6, 0xc0, 0x39, 0x2b,
           0x2e, 0x5f, 0x94, 0xd4, 0xa0, 0x17, 0x2e, 0x7d, 0x4f]
    pimg = Image.new("P", (1, 1)); pimg.putpalette(pal + [0, 0, 0] * (256 - 6))

    warn_active = any(a.get("severity") in ("Severe", "Extreme")
                      and re.search("warning", a.get("event", ""), re.I) for a in data["alerts"])
    targets = list(cycle)
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        # Render at 3x and take two shots of the same load: a full-resolution
        # one for screens, and a CSS-pixel one for the panel. The e-ink version
        # is unchanged in size but now supersampled before it is dithered,
        # which is if anything slightly kinder to the six inks.
        page = browser.new_page(viewport={"width": 800, "height": 480},
                                device_scale_factor=3)
        def shoot(page_id, out_name, nowarn=False):
            d = dict(data); d["page"] = "__nowarn__" if nowarn and page_id is None else page_id
            html = tpl.replace("__DATA__", json.dumps(d))
            tmp = ROOT / "renderer" / "_tmp.html"
            tmp.write_text(html)
            page.goto("file://" + str(tmp))
            page.wait_for_timeout(700)

            # screens: 2400x1440, full colour, no dither. An iPad showing the
            # panel's six-ink dithered PNG was upscaling it about three times
            # and magnifying the dither grain along with it.
            hi = SITE / (out_name[:-4] + "@3x.png")
            page.screenshot(path=str(hi), scale="device")

            # the panel: 800x480, quantised to Spectra 6
            raw = SITE / ("_" + out_name)
            page.screenshot(path=str(raw), scale="css")
            im = Image.open(raw).convert("RGB")
            im = im.quantize(palette=pimg, dither=Image.FLOYDSTEINBERG).convert("RGB")
            im.save(SITE / out_name, optimize=True)
            raw.unlink()
            tmp.unlink(missing_ok=True)
        for pid in targets:
            # pages render their normal selves; the warning takes over automatically if active
            shoot(pid if not warn_active else None, f"page-{pid}.png")
        # current.png: what the frame shows on a timed wake
        shoot(data["current"], "current.png")
        browser.close()

def stage_site(data, cycle):
    # summary the phone dashboard may read (same-origin on Pages)
    (SITE / "summary.json").write_text(json.dumps({
        "generated": data["now"], "fire": data["fire"],
        "aqi": data["aqi"], "cycle": cycle, "current": data["current"],
        "alert": (data["alerts"][0]["event"] if data["alerts"] else None),
    }))
    # the wrist gets its own small, flat feed — no keys, no arithmetic on-watch
    try:
        sys.path.insert(0, str(ROOT / "renderer"))
        from watch_build import write_watch
        _, nbytes = write_watch(SITE, data)
        print("watch.json:", nbytes, "bytes")
    except Exception as e:
        print("watch feed skipped:", e)
    dash = ROOT / "renderer" / "dashboard.html"
    if dash.exists():
        (SITE / "dashboard.html").write_text(dash.read_text())
    # The contact sheet points at the screen-grade renders too; it is only ever
    # read on a screen, and at 640 CSS px a Retina display wants 1280+ real ones.
    (SITE / "index.html").write_text(
        "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'></head>"
        "<body style='background:#2c1f15;text-align:center;padding:30px;font-family:serif'>"
        + "".join(f"<img src='page-{p}@3x.png?t={data['now']}' style='width:640px;max-width:96vw;margin:12px;box-shadow:0 10px 30px #0008'><br>" for p in cycle)
        + "</body></html>")

def main():
    if MOCK:
        cur, hist, nws, alerts, aqi, fire = mock_data()
        neighbors = mock_neighbors(cur)
    else:
        cur, hist = fetch_awn()
        nws, alerts = fetch_nws()
        aqi = fetch_aqi()
        fire = fetch_fire_ban()
        neighbors = fetch_neighbors()
    book = update_logbook(cur, hist)
    import zoneinfo
    nl = datetime.datetime.now(zoneinfo.ZoneInfo(TZ))
    cycle, current = decide_pages(nl, aqi, alerts, nl.month)
    data = dict(cur=cur, hist=hist, nws=nws, alerts=alerts, aqi=aqi, fire=fire,
                neighbors=neighbors,
                logbook=book, now=now_ms(), cycle=cycle, current=current)
    render_pages(data, cycle)
    stage_site(data, cycle)
    try:
        sys.path.insert(0, str(ROOT / "renderer"))
        from kindle_build import build_kindle
        edition = build_kindle(data, force_edition=os.environ.get("FORCE_EDITION"))
        print("kindle edition:", edition)
    except Exception as e:
        print("kindle render skipped:", e)
    print("rendered:", cycle, "| current:", current, "| fire:", fire.get("stage"))

if __name__ == "__main__":
    main()
