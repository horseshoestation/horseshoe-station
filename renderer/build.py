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
    cycle = ["glass", "wind", "week", "glasshouse"]
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
        page = browser.new_page(viewport={"width": 800, "height": 480})
        def shoot(page_id, out_name, nowarn=False):
            d = dict(data); d["page"] = "__nowarn__" if nowarn and page_id is None else page_id
            html = tpl.replace("__DATA__", json.dumps(d))
            tmp = ROOT / "renderer" / "_tmp.html"
            tmp.write_text(html)
            page.goto("file://" + str(tmp))
            page.wait_for_timeout(700)
            raw = SITE / ("_" + out_name)
            page.screenshot(path=str(raw))
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
    dash = ROOT / "renderer" / "dashboard.html"
    if dash.exists():
        (SITE / "dashboard.html").write_text(dash.read_text())
    (SITE / "index.html").write_text(
        "<html><body style='background:#2c1f15;text-align:center;padding:30px;font-family:serif'>"
        + "".join(f"<img src='page-{p}.png?t={data['now']}' style='width:640px;max-width:96vw;margin:12px;box-shadow:0 10px 30px #0008'><br>" for p in cycle)
        + "</body></html>")

def main():
    if MOCK:
        cur, hist, nws, alerts, aqi, fire = mock_data()
    else:
        cur, hist = fetch_awn()
        nws, alerts = fetch_nws()
        aqi = fetch_aqi()
        fire = fetch_fire_ban()
    book = update_logbook(cur, hist)
    import zoneinfo
    nl = datetime.datetime.now(zoneinfo.ZoneInfo(TZ))
    cycle, current = decide_pages(nl, aqi, alerts, nl.month)
    data = dict(cur=cur, hist=hist, nws=nws, alerts=alerts, aqi=aqi, fire=fire,
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
