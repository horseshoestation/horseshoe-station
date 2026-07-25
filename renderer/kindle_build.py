"""Kindle edition builder — computes the day's story and renders kindle.png."""
import os, json, math, datetime, pathlib, zoneinfo
import voice

ROOT = pathlib.Path(__file__).resolve().parent.parent
TZ = zoneinfo.ZoneInfo("America/Denver")
LAT, LON = 39.9693, -105.4951
DIRS = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]


def sun_times(d):
    """NOAA-style approximation; returns (rise, set) as aware local datetimes."""
    def calc(rise):
        n = d.timetuple().tm_yday
        lng_hour = LON / 15.0
        t = n + ((6 if rise else 18) - lng_hour) / 24.0
        m = (0.9856 * t) - 3.289
        l = m + 1.916 * math.sin(math.radians(m)) + 0.020 * math.sin(math.radians(2 * m)) + 282.634
        l %= 360
        ra = math.degrees(math.atan(0.91764 * math.tan(math.radians(l)))) % 360
        ra = (ra + (math.floor(l / 90) * 90 - math.floor(ra / 90) * 90)) / 15.0
        sin_dec = 0.39782 * math.sin(math.radians(l))
        cos_dec = math.cos(math.asin(sin_dec))
        cos_h = (math.cos(math.radians(90.833)) - sin_dec * math.sin(math.radians(LAT))) / (cos_dec * math.cos(math.radians(LAT)))
        if not -1 <= cos_h <= 1: return None
        h = (360 - math.degrees(math.acos(cos_h))) / 15.0 if rise else math.degrees(math.acos(cos_h)) / 15.0
        ut = (h + ra - 0.06571 * t - 6.622 - lng_hour) % 24
        base = datetime.datetime(d.year, d.month, d.day, tzinfo=datetime.timezone.utc)
        return (base + datetime.timedelta(hours=ut)).astimezone(TZ)
    r, s = calc(True), calc(False)
    if r and s and s < r: s += datetime.timedelta(days=1)
    return r, s


def h12(dt):
    return dt.strftime("%I:%M %p").lstrip("0") if dt else ""


def hm(dt):
    return dt.strftime("%I:%M").lstrip("0") if dt else ""


def day_stats(hist, now_local):
    midnight = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    mid_ms = midnight.timestamp() * 1000
    today = [r for r in hist if r["dateutc"] >= mid_ms]
    if not today: today = hist[-30:] if hist else []
    temps = [r["tempf"] for r in today if r.get("tempf") is not None]
    gusts = [r["windgustmph"] for r in today if r.get("windgustmph") is not None]
    glass = [r["baromrelin"] for r in today if r.get("baromrelin") is not None]
    uvs = [r["uv"] for r in today if r.get("uv") is not None]
    rains = [r.get("dailyrainin") or 0 for r in today]
    # storm detection: heaviest hour of rain-rate
    storm_hit, storm_time = False, None
    best = 0
    for r in today:
        rr = r.get("hourlyrainin") or 0
        if rr > best:
            best = rr
            if rr >= 0.08:
                storm_hit = True
                storm_time = datetime.datetime.fromtimestamp(r["dateutc"] / 1000, TZ).strftime("%-I o'clock" if os.name != "nt" else "%I o'clock")
    return dict(
        hi=max(temps) if temps else 0, lo=min(temps) if temps else 0,
        gust=max(gusts) if gusts else 0, rain=max(rains) if rains else 0,
        uv_max=max(uvs) if uvs else 0,
        glass_lo=min(glass) if glass else 0, glass_hi=max(glass) if glass else 0,
        storm_hit=storm_hit, storm_time=storm_time,
    )


def trend_of(hist):
    recs = [r for r in hist if r.get("baromrelin") is not None]
    if len(recs) < 10: return "steady"
    last = recs[-1]
    t3 = last["dateutc"] - 3 * 3600 * 1000
    past = [r for r in recs if r["dateutc"] <= t3]
    if not past: return "steady"
    d3 = last["baromrelin"] - past[-1]["baromrelin"]
    if d3 >= 0.02: return "rising"
    if d3 <= -0.02: return "falling"
    return "steady"


def petals_of(hist):
    counts = [0] * 16
    for r in hist:
        spd, wd = r.get("windspeedmph"), r.get("winddir")
        if spd is None or wd is None or spd < 1: continue
        counts[round(wd / 22.5) % 16] += 1
    return counts


def edition_for(now_local):
    h = now_local.hour
    if 6 <= h < 12: return "morning"
    if 12 <= h < 18: return "midday"
    if 18 <= h < 24: return "evening"
    return "night"


def forecast_bits(nws, edition):
    out = {}
    if not nws: return out
    daytimes = [p for p in nws if p.get("isDaytime")]
    nights = [p for p in nws if not p.get("isDaytime")]
    if daytimes:
        p = daytimes[0]
        pop = (p.get("probabilityOfPrecipitation") or {}).get("value") or 0
        wind = f"{p.get('windDirection','')} {str(p.get('windSpeed','')).replace(' mph','').split(' to ')[-1]}"
        out["fc_hi"] = p.get("temperature")
        out["fc_line"] = f"{p.get('shortForecast','')} &middot; rain odds {pop}%<br>wind {wind}"
        out["fc_cond_text"] = p.get("shortForecast", "")
    if nights:
        out["fc_lo"] = nights[0].get("temperature")
        out["overnight_lo"] = nights[0].get("temperature")
    if len(daytimes) > 1:
        t = daytimes[1]
        out["fc_tomorrow"] = f"{t.get('shortForecast','')} &middot; {t.get('temperature','')}&deg;"
        sf = (t.get("shortForecast") or "").lower()
        out["tomorrow"] = ("fair" if "sunn" in sf or "clear" in sf else
                           "storms again" if "thunder" in sf else
                           "rain" if "rain" in sf or "shower" in sf else
                           "snow" if "snow" in sf else "clouds")
    return out


def build_kindle(data, force_edition=None):
    """data: the same dict build.py assembles. Renders site/kindle.png."""
    cur, hist, nws = data["cur"], data["hist"], data["nws"]
    now_local = datetime.datetime.now(TZ)
    edition = force_edition or edition_for(now_local)
    stats = day_stats(hist, now_local)
    fc = forecast_bits(nws, edition)
    cond = voice.classify(dict(stats, **{"storm_hit": stats["storm_hit"]}),
                          fc.get("fc_cond_text"))
    rise, sset = sun_times(now_local.date())
    daylen = ""
    if rise and sset:
        mins = int((sset - rise).total_seconds() // 60)
        daylen = f"{mins//60} h {mins%60} m"
    moon = voice.moon_info(now_local.timestamp() * 1000)
    gh = cur.get("tempinf") or 60
    # overnight sunroom low (00:00-06:00 records)
    gh_lo = None
    mid = now_local.replace(hour=0, minute=0).timestamp() * 1000
    six = now_local.replace(hour=6, minute=0).timestamp() * 1000
    ghs = [r["tempinf"] for r in hist if r.get("tempinf") is not None and mid <= r["dateutc"] < six]
    if ghs: gh_lo = min(ghs)

    d = dict(
        stats=stats, cur=cur, cond=cond, trend=trend_of(hist),
        weekday=now_local.strftime("%A"), dom=voice.ordinal_day(now_local),
        month=now_local.strftime("%B"), doy=now_local.timetuple().tm_yday,
        date_iso=now_local.date().isoformat(),
        setat=h12(now_local), sunrise=hm(rise), sunset=hm(sset), daylen=daylen,
        moon=moon, gh=gh, gh_lo=gh_lo, **fc,
    )
    composed = voice.compose(edition, d)
    composed["petals"] = petals_of(hist)
    composed["curdir"] = cur.get("winddir") or 0
    composed["moonillum"] = moon["illum"]
    composed["moonwax"] = moon["waxing"]

    tpl = (ROOT / "renderer" / "kindle.html").read_text()
    html = tpl.replace("__DATA__", json.dumps(composed))
    tmp = ROOT / "renderer" / "_ktmp.html"
    tmp.write_text(html)
    from playwright.sync_api import sync_playwright
    from PIL import Image
    site = ROOT / "site"; site.mkdir(exist_ok=True)
    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport={"width": 1236, "height": 1648})
        page.goto("file://" + str(tmp))
        page.wait_for_timeout(600)
        raw = site / "_kindle_raw.png"
        page.screenshot(path=str(raw))
        browser.close()
    Image.open(raw).convert("L").save(site / "kindle.png", optimize=True)
    raw.unlink(); tmp.unlink(missing_ok=True)
    return edition
