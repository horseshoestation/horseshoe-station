"""
The voice of Horseshoe Station's Kindle editions.
Three broadsheet editions by day; a miner-pioneer's journal at midnight.
All text composed here from real data; seeded by date so each edition is
stable within its window but different from yesterday's.
"""
import math, random, datetime

# ---------------- helpers ----------------
NUMS = ["zero","one","two","three","four","five","six","seven","eight","nine","ten",
        "eleven","twelve","thirteen","fourteen","fifteen","sixteen","seventeen",
        "eighteen","nineteen","twenty"]
TENS = {20:"twenty",30:"thirty",40:"forty",50:"fifty",60:"sixty",70:"seventy",
        80:"eighty",90:"ninety"}

def words(n):
    n = int(round(n))
    if n < 0: return "minus " + words(-n)
    if n <= 20: return NUMS[n]
    if n < 100:
        t, r = (n // 10) * 10, n % 10
        return TENS[t] + ("-" + NUMS[r] if r else "")
    return str(n)

def ordinal_day(d):
    n = d.day
    suf = "th" if 11 <= n % 100 <= 13 else {1:"st",2:"nd",3:"rd"}.get(n % 10, "th")
    return f"{n}{suf}"

def fmt12(dt):
    return dt.strftime("%-I:%M") if hasattr(dt, "strftime") else dt

def moon_info(now_ms):
    age = ((now_ms / 86400000 + 2440587.5) - 2451550.1) % 29.53059
    illum = round((1 - math.cos(2 * math.pi * age / 29.53059)) / 2 * 100)
    names = [(1.8,"new moon"),(5.5,"waxing crescent"),(9.2,"first quarter"),
             (12.9,"waxing gibbous"),(16.6,"full moon"),(20.3,"waning gibbous"),
             (24.1,"last quarter"),(27.7,"waning crescent"),(29.6,"new moon")]
    name = "new moon"
    for lim, nm in names:
        if age <= lim: name = nm; break
    to_full = round((14.765 - age + 29.53059) % 29.53059)
    return dict(age=age, illum=illum, name=name, to_full=to_full, waxing=age < 14.765)

# ---------------- condition classification ----------------
def classify(stats, nws_today):
    """One coarse label the phrase pools key on."""
    if stats["gust"] >= 40: return "gale"
    if stats["rain"] >= 0.25: return "wet"
    if (nws_today and "thunder" in nws_today.lower()) or stats.get("storm_hit"): return "storm"
    if stats["hi"] >= 82: return "hot"
    if stats["lo"] <= 10: return "bitter"
    if stats["lo"] <= 32: return "freeze"
    if stats["rain"] > 0.01: return "showery"
    return "fair"

# ---------------- flavor pools ----------------
# Mining seasoning — used sparingly, one draw per entry at most.
MINE = {
    "fair":   ["The road up to the Caribou would carry a wagon without complaint.",
               "Good weather for the diggings, if anyone still dug.",
               "The old tungsten camps would have called this hauling weather."],
    "wet":    ["The mine road will be gumbo by morning; the creek at least will be glad.",
               "Weather to send a man underground, where it never rains."],
    "storm":  ["No hour to be standing at a portal with steel in your hand.",
               "The thunder walked the ridgeline like a shift boss with a grievance."],
    "gale":   ["A wind to strip the smoke straight off the old mill stacks.",
               "The kind of blow that used to shake the tram cables above Caribou."],
    "freeze": ["Colder on the surface tonight than in the drifts of the old mine, where it is forty degrees forever.",
               "The tunnels never notice a night like this; the road to them is another matter."],
    "bitter": ["Colder by far than the deepest drift of the Caribou, which holds its forty degrees through anything.",
               "Weather that once froze the flumes and stopped the stamps mid-song."],
    "hot":    ["Even the mine mouths breathe cool on a day like this; the marmots have claimed the tailings.",
               "Heat to make a man envy the forty-degree dark below."],
    "showery":["Enough rain to lay the dust on the mine road and no more."],
}
GLASSHOUSE = {
    "warm":  ["the little glasshouse holds {gh}, and the plants want for nothing",
              "the glasshouse keeps its {gh} and the basil sleeps on"],
    "cool":  ["the glasshouse is down to {gh}; the heater earns its keep tonight",
              "{gh} under the glass — close enough to frost to mind it"],
}
CLOSERS = ["All quiet on the mountain. Thus the day is ended.",
           "The lamp is low. Thus ends this day.",
           "Nothing more worth the ink. So closes the day.",
           "The mountain keeps its own counsel tonight. Thus the day is ended.",
           "So ends the {dayn} day of the year."]
CLOSERS_ROUGH = ["A hard day, fairly ended. The mountain owes us nothing.",
                 "The weather had its say today; tomorrow we shall have ours."]

# ---------------- the journal (Night Watch) ----------------
def compose_journal(d, rng):
    """d: dict with stats, cur, sun, moon, nws bits, gh (sunroom temp)."""
    s = d["stats"]; c = d["cur"]; cond = d["cond"]
    p1 = []
    # opening
    if cond == "gale":
        p1.append(f"Night, and the wind still worrying the eaves. The day's gusts made <b>{words(s['gust'])}</b> and meant it.")
    elif cond in ("storm", "wet", "showery"):
        p1.append("Night, and the wind gone quiet at last.")
    elif cond in ("bitter", "freeze"):
        p1.append(f"Night, and the cold settled in to stay — <b>{words(c['tempf'])} degrees</b> and no argument about it.")
    else:
        p1.append("Night, clear over the peaks.")
    # the day's story
    if s.get("storm_hit"):
        p1.append(f"The day carried us to <b>{words(s['hi'])} degrees</b> before the thunder came over the divide"
                  + (f" at {s['storm_time']}" if s.get("storm_time") else "")
                  + ", as the sinking glass had promised it would"
                  + (f"; it left <b>{s['rain']:.2f} inches</b> in the gauge and the smell of wet granite on the air."
                     if s["rain"] >= 0.01 else "."))
    elif s["rain"] >= 0.25:
        p1.append(f"Rain for much of it — <b>{s['rain']:.2f} inches</b> in the gauge by dark, and the high a modest <b>{words(s['hi'])}</b>.")
    elif cond == "gale":
        p1.append(f"The high made <b>{words(s['hi'])}</b> between blows.")
    else:
        p1.append(f"The day carried us to <b>{words(s['hi'])} degrees</b> and asked little in return.")
    if s["gust"] >= 25 and cond != "gale":
        p1.append(f"The gusts touched <b>{words(s['gust'])}</b> on the high ground and then thought better of it.")

    p2 = []
    # the glass
    tr = d["trend"]  # 'rising','falling','steady'
    gv = f"<b>{c['baromrelin']:.2f}</b>"
    if tr == "steady":
        p2.append(f"The glass has steadied at {gv} and I am inclined to trust it.")
    elif tr == "rising":
        p2.append(f"The glass climbs — {gv} and rising — and the sky agrees with it.")
    else:
        p2.append(f"The glass sinks to {gv}, and I mislike what it implies for tomorrow.")
    # now + overnight
    p2.append(f"It is <b>{words(c['tempf'])} degrees</b> now"
              + (f" and falling toward <b>{words(d['overnight_lo'])}</b> before dawn" if d.get("overnight_lo") is not None else "")
              + ";")
    gh_t = "cool" if d["gh"] < 45 else "warm"
    p2.append(rng.choice(GLASSHOUSE[gh_t]).format(gh=f"<b>{words(d['gh'])}</b>") + ".")
    # tomorrow
    if d.get("tomorrow"):
        p2.append(f"Tomorrow promises {d['tomorrow']} — first light comes at <b>{d['sunrise']}</b>.")
    # one draw of mine flavor
    p2.append(rng.choice(MINE[cond]))

    closer_pool = CLOSERS_ROUGH if cond in ("gale", "storm", "bitter") and rng.random() < 0.5 else CLOSERS
    closer = rng.choice(closer_pool).format(dayn=ordinal_day_n(d["doy"]))
    return {
        "dateline": f"{d['weekday']} Night, the {d['dom']} of {d['month']}",
        "subline": f"The {d['doy']}th day &middot; written by lamplight at {d['setat']}",
        "paras": [" ".join(p1), " ".join(p2)],
        "closer": closer,
        "moonline": f"{d['moon']['name']} &middot; " +
                    (f"full in {words(d['moon']['to_full'])} nights" if d['moon']['to_full'] > 1 and d['moon']['name'] != 'full moon'
                     else ("full tomorrow night" if d['moon']['to_full'] == 1 else "the moon at her full")),
        "recordline": f"day&rsquo;s record &middot; high {round(s['hi'])} low {round(s['lo'])} &middot; gust {round(s['gust'])} &middot; "
                      f"rain {s['rain']:.2f} in &middot; glass {c['baromrelin']:.2f} {ARROW[tr]}",
        "nextline": "the night watch &middot; morning page at six",
    }

def ordinal_day_n(n):
    suf = "th" if 11 <= n % 100 <= 13 else {1:"st",2:"nd",3:"rd"}.get(n % 10, "th")
    return f"{n}{suf}"

ARROW = {"rising": "&#8599;", "falling": "&#8600;", "steady": "steady"}

# ---------------- the broadsheet editions ----------------
GLASS_HEADS = {
    ("falling", "morning"): "The glass fell overnight",
    ("falling", "midday"):  "The glass is falling",
    ("falling", "evening"): "The glass falls into evening",
    ("rising", "morning"):  "The glass rose overnight",
    ("rising", "midday"):   "The glass is on the climb",
    ("rising", "evening"):  "The glass rises with the dusk",
    ("steady", "morning"):  "The glass held all night",
    ("steady", "midday"):   "The glass holds steady",
    ("steady", "evening"):  "The glass ends the day unmoved",
}
VERDICTS = {
    "storm":  ["Moisture rides in from the southwest &mdash; thunder over the Divide by afternoon.",
               "The Divide will speak this afternoon; odds favor it."],
    "wet":    ["A wet spell settles in; the gauge will have work today.",
               "Rain holds the high ground today."],
    "gale":   ["A blow is coming down off the Divide &mdash; mind what is loose.",
               "The westerlies mean business today."],
    "fair":   ["A kind day on the mountain; take it while it offers.",
               "Nothing organized anywhere near &mdash; a day to be believed."],
    "hot":    ["Heat builds under a high sun &mdash; the burn index will run extreme by noon.",
               "A hot one for this height; the glasshouse will want venting."],
    "showery":["Passing showers and no conviction behind them."],
    "freeze": ["Freeze tonight; the glasshouse margin is the number to watch.",
               "Winter tests the door tonight."],
    "bitter": ["Bitter air holds the mountain; dress for the wind, not the number.",
               "A day the tunnels would envy nobody."],
}
ED_META = {
    "morning": ("MORNING EDITION", "midday edition at noon"),
    "midday":  ("MIDDAY EDITION",  "evening edition at six"),
    "evening": ("EVENING EDITION", "the night watch at midnight"),
}

def compose_broadsheet(edition, d, rng):
    s = d["stats"]; c = d["cur"]; cond = d["cond"]; tr = d["trend"]
    name, nextline = ED_META[edition]
    head = GLASS_HEADS[(tr, edition)]
    verdict = rng.choice(VERDICTS[cond])
    if edition == "morning":
        today_label = "Today &middot; NWS Boulder"
        big = f"{d['fc_hi']}&deg; <span class='lo'>/ {d['fc_lo']}&deg;</span>" if d.get("fc_hi") is not None else "&mdash;"
        line1 = d.get("fc_line", "")
        rows = [
            ("Now, at first light", f"{c['tempf']:.1f}&deg; &middot; {windw(c)} &middot; humidity {round(c['humidity'])}%"),
            ("The sunroom kept", f"{d['gh_lo']:.1f}&deg; overnight" if d.get("gh_lo") is not None else f"{d['gh']}&deg; now"),
            ("Sun", f"rise {d['sunrise']} &middot; set {d['sunset']} &middot; {d['daylen']} of light"),
            ("Moon", f"{d['moon']['name']} &middot; full in {words(d['moon']['to_full'])} nights"),
        ]
    elif edition == "midday":
        today_label = "The day so far"
        big = f"{round(c['tempf'])}&deg; <span class='lo'>now</span>"
        line1 = f"high so far <b>{round(s['hi'])}&deg;</b> &middot; UV peak <b>{s['uv_max']}</b>" \
                + (f" &middot; rain <b>{s['rain']:.2f} in</b>" if s['rain'] >= 0.01 else "")
        rows = [
            ("Wind now", f"{windw(c)} &middot; top gust {round(s['gust'])}"),
            ("The sunroom", f"{d['gh']:.1f}&deg; &middot; {round(c['humidityin'])}%"),
            ("The afternoon", d.get("fc_line", "&mdash;")),
            ("Sun", f"sets {d['sunset']} &middot; {d['daylen']} of light today"),
        ]
    else:  # evening
        today_label = "The day&rsquo;s tallies"
        big = f"{round(s['hi'])}&deg; <span class='lo'>/ {round(s['lo'])}&deg;</span>"
        line1 = f"top gust <b>{round(s['gust'])}</b> &middot; rain <b>{s['rain']:.2f} in</b> &middot; UV peak <b>{s['uv_max']}</b>"
        rows = [
            ("Now, at dusk", f"{c['tempf']:.1f}&deg; &middot; {windw(c)}"),
            ("Tomorrow", d.get("fc_tomorrow", "&mdash;")),
            ("The sunroom", f"{d['gh']:.1f}&deg; &middot; holding for the night"),
            ("Moon", f"{d['moon']['name']} &middot; {d['moon']['illum']}% lit"),
        ]
    return {
        "edition": name, "setat": d["setat"], "nextline": nextline,
        "glass": {"val": f"{c['baromrelin']:.2f}", "head": ("&#8599; " if tr == "rising" else "&#8600; " if tr == "falling" else "&#8594; ") + head,
                  "verdict": verdict,
                  "unit": f"inches of mercury &middot; {'low' if tr != 'rising' else 'high'} {s['glass_lo' if tr != 'rising' else 'glass_hi']:.2f} "
                          + ("overnight" if edition == "morning" else "today")},
        "seg": seg_for(c["baromrelin"]),
        "today": {"label": today_label, "big": big, "line1": line1},
        "rows": rows,
        "date": f"{d['weekday'][:3]} {d['dom']} {d['month'][:3]}".upper(),
    }

def windw(c):
    DIRS = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
    spd = c.get("windspeedmph") or 0
    if spd < 1: return "calm"
    return f"{DIRS[round((c.get('winddir') or 0)/22.5)%16]} {round(spd)}"

def seg_for(rel):
    i = 0 if rel < 29.25 else 1 if rel < 29.45 else 2 if rel < 29.70 else 3 if rel < 29.95 else 4
    x = max(8, min(1052, round((rel - 29.0) / 1.2 * 1060)))
    return {"i": i, "x": x}

# ---------------- entry point ----------------
def compose(edition, d):
    rng = random.Random(f"{d['date_iso']}-{edition}")
    if edition == "night":
        return {"kind": "journal", "j": compose_journal(d, rng)}
    return {"kind": "broadsheet", "b": compose_broadsheet(edition, d, rng)}
