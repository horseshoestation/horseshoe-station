#!/usr/bin/env python3
"""
Horseshoe Station — the watch feed.

Publishes site/watch.json: one small, flat, already-chewed payload for the
Garmin epix. The watch does no arithmetic it doesn't have to and carries no
API keys — everything here is computed on the same schedule as the frame, so
the wrist and the wall agree.

Keys are short on purpose. A Connect IQ watch face runs in a few tens of KB;
every byte of JSON becomes a Dictionary entry in that budget.
"""
import json, math, datetime, zoneinfo

TZ = "America/Denver"
LAT, LON = 39.9693, -105.4951

DIRS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
        "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

# the old glass words, same cuts the Dutch scale uses on the frame
DUTCH = ["STORM", "REGEN", "VERANDERLYK", "MOOI WEER", "BESTENDIG"]


def dir_name(d):
    if d is None:
        return "—"
    return DIRS[int(round(d / 22.5)) % 16]


def beaufort(mph):
    if mph is None:
        return 0, "calm"
    for lim, num, word in ((1, 0, "calm"), (4, 1, "light air"), (8, 2, "light breeze"),
                           (13, 3, "gentle breeze"), (19, 4, "moderate"), (25, 5, "fresh breeze"),
                           (32, 6, "strong breeze"), (39, 7, "near gale"), (47, 8, "gale"),
                           (55, 9, "strong gale"), (64, 10, "storm")):
        if mph < lim:
            return num, word
    return 11, "violent storm"


def dutch_seg(rel):
    if rel is None:
        return 2
    return 0 if rel < 29.25 else 1 if rel < 29.45 else 2 if rel < 29.7 else 3 if rel < 29.95 else 4


def trend_of(hist):
    """3-hour barometer delta, same thresholds as the frame's trendOf()."""
    recs = [r for r in hist if r.get("baromrelin") is not None]
    if len(recs) < 10:
        return 0, "Steady", "The glass is still filling its memory."
    last = recs[-1]["baromrelin"]
    cutoff = recs[-1]["dateutc"] - 3 * 3600_000
    i = len(recs) - 1
    while i > 0 and recs[i]["dateutc"] > cutoff:
        i -= 1
    d3 = last - recs[i]["baromrelin"]
    if d3 >= 0.02:
        fast = d3 >= 0.06
        return (2 if fast else 1), ("Rising fast" if fast else "Rising"), \
               "Drier air moving in — a good sign for tomorrow."
    if d3 <= -0.02:
        fast = d3 <= -0.06
        return (-2 if fast else -1), ("Falling fast" if fast else "Falling slowly"), \
               ("A disturbance approaches — wind and weather within a day." if fast
                else "Clouds or afternoon storms becoming more likely.")
    return 0, "Steady", "No organized system nearby — watch the afternoon build-ups."


def prevailing(hist):
    counts = {}
    for r in hist:
        if r.get("winddir") is not None and (r.get("windspeedmph") or 0) >= 1:
            n = dir_name(r["winddir"])
            counts[n] = counts.get(n, 0) + 1
    if not counts:
        return "—"
    return max(counts, key=counts.get)


def rose(hist):
    """16-petal share of the last 48 h, as whole percents."""
    buckets = [0] * 16
    total = 0
    for r in hist:
        if r.get("winddir") is not None and (r.get("windspeedmph") or 0) >= 1:
            buckets[int(round(r["winddir"] / 22.5)) % 16] += 1
            total += 1
    if not total:
        return buckets
    return [int(round(b * 100.0 / total)) for b in buckets]


def spark(hist, key, hours, n, xform=None):
    """Downsample the last `hours` of `key` to `n` points, keeping extremes.

    Straight stride-sampling flattens the peak the whole graph exists to show,
    so each bucket contributes whichever of its samples is furthest from the
    running mean — the shape survives at 24 points.
    """
    if not hist:
        return []
    end = hist[-1]["dateutc"]
    start = end - hours * 3600_000
    vals = [(r["dateutc"], r[key]) for r in hist
            if r.get(key) is not None and r["dateutc"] >= start]
    if not vals:
        return []
    mean = sum(v for _, v in vals) / len(vals)
    out = []
    for i in range(n):
        lo = start + (end - start) * i / n
        hi = start + (end - start) * (i + 1) / n
        bucket = [v for t, v in vals if lo <= t < hi]
        if not bucket:
            out.append(None)
            continue
        pick = max(bucket, key=lambda v: abs(v - mean))
        out.append(xform(pick) if xform else int(round(pick)))
    # carry the last known value across gaps; the watch draws a solid trace
    last = None
    for i, v in enumerate(out):
        if v is None:
            out[i] = last
        else:
            last = v
    first = next((v for v in out if v is not None), 0)
    return [first if v is None else v for v in out]


def sun_times(day, lat=LAT, lon=LON):
    """NOAA-style rise/set, returned as local epoch ms. Same math the frame uses."""
    def calc(rise):
        n = day.timetuple().tm_yday
        lng_hour = lon / 15.0
        t = n + ((6 if rise else 18) - lng_hour) / 24.0
        m = (0.9856 * t) - 3.289
        l = m + 1.916 * math.sin(math.radians(m)) + 0.020 * math.sin(math.radians(2 * m)) + 282.634
        l %= 360
        ra = math.degrees(math.atan(0.91764 * math.tan(math.radians(l)))) % 360
        ra += (math.floor(l / 90) * 90) - (math.floor(ra / 90) * 90)
        ra /= 15.0
        sin_dec = 0.39782 * math.sin(math.radians(l))
        cos_dec = math.cos(math.asin(sin_dec))
        cos_h = (math.cos(math.radians(90.833)) - sin_dec * math.sin(math.radians(lat))) / \
                (cos_dec * math.cos(math.radians(lat)))
        if cos_h > 1 or cos_h < -1:
            return None
        h = (360 - math.degrees(math.acos(cos_h))) if rise else math.degrees(math.acos(cos_h))
        h /= 15.0
        mean_t = h + ra - (0.06571 * t) - 6.622
        ut = (mean_t - lng_hour) % 24
        return ut
    out = []
    for rise in (True, False):
        ut = calc(rise)
        if ut is None:
            out.append(None)
            continue
        base = datetime.datetime(day.year, day.month, day.day, tzinfo=datetime.timezone.utc)
        moment = base + datetime.timedelta(hours=ut)
        # west of Greenwich, the evening event lands on the following UTC day;
        # nudge it back onto the local date we were actually asked about
        local_date = moment.astimezone(zoneinfo.ZoneInfo(TZ)).date()
        if local_date < day:
            moment += datetime.timedelta(days=1)
        elif local_date > day:
            moment -= datetime.timedelta(days=1)
        out.append(int(moment.timestamp() * 1000))
    return out


def build_watch(data):
    cur = data["cur"] or {}
    hist = data.get("hist") or []
    aqi = data.get("aqi") or {}
    fire = data.get("fire") or {}
    alerts = data.get("alerts") or []
    book = data.get("logbook") or {}

    tz = zoneinfo.ZoneInfo(TZ)
    now_local = datetime.datetime.now(tz)
    today_key = now_local.date().isoformat()
    today = book.get(today_key, {})

    tnum, tword, tverdict = trend_of(hist)
    bf_num, bf_word = beaufort(cur.get("windspeedmph"))
    sr, ss = sun_times(now_local.date())

    def r1(v):
        return None if v is None else round(v, 1)

    def r2(v):
        return None if v is None else round(v, 2)

    def ri(v):
        return None if v is None else int(round(v))

    # a warning outranks everything; the watch face turns red for these
    warn = None
    for a in alerts:
        if a.get("severity") in ("Severe", "Extreme"):
            warn = a.get("event")
            break
    if warn is None and alerts:
        warn = alerts[0].get("event")

    payload = {
        "t": data["now"],
        "tz": TZ,

        # the deck log
        "temp": r1(cur.get("tempf")),
        "feels": ri(cur.get("feelsLike")),
        "hum": ri(cur.get("humidity")),
        "dew": ri(cur.get("dewPoint")),
        "hi": r1(today.get("hi")),
        "lo": r1(today.get("lo")),

        # the wind
        "wind": r1(cur.get("windspeedmph")),
        "gust": r1(cur.get("windgustmph")),
        "dir": ri(cur.get("winddir")),
        "dirn": dir_name(cur.get("winddir")),
        "maxgust": r1(cur.get("maxdailygust") or today.get("gust")),
        "bf": bf_num,
        "bfw": bf_word,
        "prev": prevailing(hist),
        "rose": rose(hist),

        # the glass
        "bar": r2(cur.get("baromrelin")),
        "barabs": r2(cur.get("baromabsin")),
        "trend": tnum,
        "trendw": tword,
        "verdict": tverdict,
        "dutch": dutch_seg(cur.get("baromrelin")),
        "dutchw": DUTCH[dutch_seg(cur.get("baromrelin"))],

        # water and light
        "rain": r2(cur.get("dailyrainin")),
        "rainrate": r2(cur.get("hourlyrainin")),
        "rainw": r2(cur.get("weeklyrainin")),
        "rainm": r2(cur.get("monthlyrainin")),
        "uv": ri(cur.get("uv")),
        "sol": ri(cur.get("solarradiation")),

        # the glasshouse
        "tin": r1(cur.get("tempinf")),
        "hin": ri(cur.get("humidityin")),

        # the world outside the station
        "aqi": ri(aqi.get("us_aqi")),
        "fire": fire.get("stage"),
        "alert": warn,
        "sr": sr,
        "ss": ss,

        # 24 h traces, 24 points each
        "tt": spark(hist, "tempf", 24, 24),
        "gt": spark(hist, "windgustmph", 24, 24),
        # pressure as hundredths above 29.00 inHg — keeps it a small integer
        "bt": spark(hist, "baromrelin", 24, 24, xform=lambda v: int(round((v - 29.0) * 100))),
    }
    return payload


def write_watch(site_dir, data):
    payload = build_watch(data)
    p = site_dir / "watch.json"
    p.write_text(json.dumps(payload, separators=(",", ":")))
    return payload, p.stat().st_size
