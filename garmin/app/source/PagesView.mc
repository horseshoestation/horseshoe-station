using Toybox.Communications;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.PersistedContent;
using Toybox.System;
using Toybox.Time;
using Toybox.Timer;
using Toybox.WatchUi;

// The frame turns its own pages on a ten-minute clock. On the wrist you turn
// them yourself: swipe or press up and down through the Glass, the Wind, the
// Deck Log and the Almanack.
class PagesView extends WatchUi.View {

    static const PAGE_GLASS   = 0;
    static const PAGE_WIND    = 1;
    static const PAGE_LOG     = 2;
    static const PAGE_ALMANAC = 3;
    static const PAGE_RADAR   = 4;
    static const PAGE_COUNT   = 5;

    // RainViewer's public radar, one mercator tile centred on the station:
    // z7 x26 y48 spans roughly Kremmling to Byers, Wyoming line to Pikes
    // Peak — the weather that matters, an hour either side of the Divide.
    static const RADAR_INDEX = "https://api.rainviewer.com/public/weather-maps.json";
    static const RADAR_TILE  = "/256/7/26/48/2/1_1.png";

    hidden var page = 0;
    hidden var data = null;
    hidden var fetching = false;
    hidden var failed = false;

    // The radar loop: up to six frames spanning the last ~100 minutes,
    // fetched newest-first so the screen fills at once, played oldest to
    // newest with a hold on the present.
    hidden var radarFrames = [];      // [{ :t => epoch sec, :bmp => bitmap }]
    hidden var radarPending = [];     // frame dictionaries still to fetch
    hidden var radarCurrent = null;   // the frame in flight
    hidden var radarHost = null;
    hidden var radarIdx = 0;
    hidden var radarHold = 0;
    hidden var radarTimer = null;
    hidden var radarBusy = false;
    hidden var radarFail = false;

    function initialize() {
        WatchUi.View.initialize();
    }

    function onShow() {
        data = Feed.storedFull();
        refresh(false);
    }

    function turn(delta) {
        page = (page + delta + PAGE_COUNT) % PAGE_COUNT;
        if (page == PAGE_RADAR) {
            radarRefresh(false);
            radarPlay();
        } else {
            radarStop();
        }
        WatchUi.requestUpdate();
    }

    function onHide() {
        radarStop();
    }

    // ---- the radar loop ----------------------------------------------------

    hidden function radarPlay() {
        if (radarTimer == null && radarFrames.size() > 1) {
            radarTimer = new Timer.Timer();
            radarTimer.start(method(:radarTick), 700, true);
        }
    }

    hidden function radarStop() {
        if (radarTimer != null) {
            radarTimer.stop();
            radarTimer = null;
        }
    }

    // Advance the loop; linger three beats on the present before replaying.
    function radarTick() as Void {
        if (radarFrames.size() < 2) { return; }
        if (radarIdx >= radarFrames.size() - 1) {
            radarHold += 1;
            if (radarHold < 3) { return; }
            radarHold = 0;
            radarIdx = 0;
        } else {
            radarIdx += 1;
        }
        WatchUi.requestUpdate();
    }

    // ---- the radar ---------------------------------------------------------

    // RainViewer's index names the past two hours of frames; we take every
    // other one, newest first, and chain the tile fetches one at a time.
    // force = the user asked; otherwise only when our newest frame is older
    // than five minutes.
    function radarRefresh(force) {
        if (radarBusy) { return; }
        if (!force && radarFrames.size() > 0) {
            var newest = radarFrames[radarFrames.size() - 1] as Lang.Dictionary;
            var t = newest.get(:t);
            if (t != null && Time.now().value() - t < 300) { return; }
        }
        radarBusy = true;
        radarFail = false;
        Communications.makeWebRequest(RADAR_INDEX, null, Feed.requestOptions(),
                                      method(:onRadarIndex));
    }

    function onRadarIndex(
        code as Lang.Number,
        payload as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator
    ) as Void {
        if (code != 200 || payload == null || !(payload instanceof Lang.Dictionary)) {
            radarBusy = false;
            radarFail = true;
            WatchUi.requestUpdate();
            return;
        }
        var dict = payload as Lang.Dictionary;
        var host = dict.get("host");
        var radar = dict.get("radar");
        var frames = null;
        if (radar instanceof Lang.Dictionary) {
            frames = (radar as Lang.Dictionary).get("past");
        }
        if (host == null || !(frames instanceof Lang.Array) || (frames as Lang.Array).size() == 0) {
            radarBusy = false;
            radarFail = true;
            WatchUi.requestUpdate();
            return;
        }
        var arr = frames as Lang.Array;
        radarHost = host as Lang.String;
        radarPending = [] as Lang.Array;
        var i = arr.size() - 1;
        while (i >= 0 && radarPending.size() < 6) {
            radarPending.add(arr[i]);
            i -= 2;                       // every other frame: ~20-minute steps
        }
        radarFrames = [] as Lang.Array;
        radarIdx = 0;
        radarHold = 0;
        fetchNextRadar();
    }

    hidden function fetchNextRadar() {
        if (radarPending.size() == 0) {
            radarBusy = false;
            radarIdx = radarFrames.size() - 1;   // rest on the present
            radarPlay();
            WatchUi.requestUpdate();
            return;
        }
        radarCurrent = radarPending[0] as Lang.Dictionary;
        radarPending = radarPending.slice(1, null);
        Communications.makeImageRequest(
            radarHost + (radarCurrent.get("path") as Lang.String) + RADAR_TILE, null,
            { :maxWidth => 256, :maxHeight => 256 },
            method(:onRadarTile));
    }

    // The signature must match Communications' image callback exactly, or
    // the checker rejects the method reference at the call site.
    function onRadarTile(
        code as Lang.Number,
        bmp as Null or Graphics.BitmapReference or WatchUi.BitmapResource
    ) as Void {
        if (code == 200 && bmp != null && radarCurrent != null) {
            // fetched newest-first; keep the list oldest-first for the loop
            var frame = { :t => radarCurrent.get("time"), :bmp => bmp };
            var rebuilt = [frame] as Lang.Array;
            for (var i = 0; i < radarFrames.size(); i += 1) {
                rebuilt.add(radarFrames[i]);
            }
            radarFrames = rebuilt;
            radarIdx = radarFrames.size() - 1;   // show the present while loading
        } else if (radarFrames.size() == 0) {
            radarFail = true;
        }
        WatchUi.requestUpdate();
        fetchNextRadar();
    }

    // force = the user asked; otherwise only go out if what we hold is stale.
    function refresh(force) {
        if (fetching) { return; }
        var age = Feed.dataAgeMinutes(data);
        if (!force && data != null && age != null && age < 8) { return; }
        fetching = true;
        failed = false;
        WatchUi.requestUpdate();
        Communications.makeWebRequest(Feed.URL, null, Feed.requestOptions(), method(:onFeed));
    }

    function onFeed(
        code as Lang.Number,
        payload as Null or Lang.Dictionary or Lang.String or PersistedContent.Iterator
    ) as Void {
        fetching = false;
        if (code == 200 && payload != null) {
            data = payload;
            Feed.storeFull(payload);
        } else {
            failed = true;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var s = h / 416.0;

        dc.setColor(Palette.paper(), Palette.paper());
        dc.clear();

        // The radar draws its own sky and needs nothing from the station, so
        // it goes ahead of the no-data gate and skips the shared chrome.
        if (page == PAGE_RADAR) {
            drawRadar(dc, cx, s);
            drawDots(dc, cx, s);
            return;
        }

        drawChrome(dc, cx, s);

        if (data == null) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            var msg = fetching ? "Reading the glass" : (failed ? "No word from the station" : "Awaiting the glass");
            Draw.spacedText(dc, cx, py(200, s), Graphics.FONT_XTINY, msg, 2,
                            Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var bottom;
        if (page == PAGE_GLASS)        { bottom = drawGlass(dc, cx, s); }
        else if (page == PAGE_WIND)    { bottom = drawWind(dc, cx, s); }
        else if (page == PAGE_LOG)     { bottom = drawLog(dc, cx, s); }
        else                           { bottom = drawAlmanac(dc, cx, s); }

        drawFooter(dc, cx, s, bottom);
        drawDots(dc, cx, s);
    }

    hidden function py(v, s) { return (v * s).toNumber(); }

    hidden function title() {
        if (page == PAGE_GLASS) { return "Storm Watch"; }
        if (page == PAGE_WIND)  { return "The Wind"; }
        if (page == PAGE_LOG)   { return "Trail Log"; }
        if (page == PAGE_RADAR) { return "The Radar"; }
        return "Sun & Sky";
    }

    hidden function drawChrome(dc, cx, s) {
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, py(48, s), Graphics.FONT_XTINY, title(), 4,
                        Graphics.TEXT_JUSTIFY_CENTER);
        // the Divide again, compressed to a hairline horizon under the title
        Draw.ridgeline(dc, s, 84, 0.55, Palette.grid(), false);
    }

    hidden function drawDots(dc, cx, s) {
        var y = py(388, s);
        var gap = (14 * s).toNumber();
        var x0 = cx - (gap * (PAGE_COUNT - 1)) / 2;
        for (var i = 0; i < PAGE_COUNT; i += 1) {
            if (i == page) {
                dc.setColor(Palette.red(), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x0 + i * gap, y, (3 * s).toNumber() + 1);
            } else {
                dc.setColor(Palette.grid(), Graphics.COLOR_TRANSPARENT);
                dc.drawCircle(x0 + i * gap, y, (3 * s).toNumber());
            }
        }
    }

    // The freshness line earns its pixels only when something is happening:
    // a fetch in flight, or a reading gone stale. A quiet current page keeps
    // the room. It flows under the content and yields if there is none left.
    hidden function drawFooter(dc, cx, s, bottom) {
        var age = Feed.dataAgeMinutes(data);
        var text = null;
        if (fetching) {
            text = "reading...";
        } else if (age != null && age > 25) {
            text = age.format("%d") + " min old";
        }
        if (text == null) { return; }

        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var centre = bottom + (6 * s).toNumber() + hX / 2;
        var floor = py(352, s) + hX / 2;
        if (centre < floor) { centre = floor; }
        if (centre + hX / 2 > py(382, s)) { return; }
        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, centre, Graphics.FONT_XTINY, text, 1,
                        Graphics.TEXT_JUSTIFY_CENTER);
    }

    // A ledger line: label left, value right, dotted leader between, exactly as
    // the frame sets its tables.
    hidden function row(dc, s, y, label, value, valueColor) {
        var left = py(78, s);
        var right = dc.getWidth() - py(78, s);
        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, left, y, Graphics.FONT_XTINY, label, 1, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(valueColor, Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, right, y, Graphics.FONT_TINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // ---- the pages --------------------------------------------------------

    hidden function drawGlass(dc, cx, s) {
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var hM = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var pad = (3 * s).toNumber();

        // MILD, not MEDIUM: the epix's medium numerals alone spent a third of
        // the page and pushed the trace off the glass entirely.
        var barFont = (Graphics has :FONT_NUMBER_MILD)
                      ? Graphics.FONT_NUMBER_MILD : Graphics.FONT_NUMBER_MEDIUM;
        hM = dc.getFontHeight(barFont);
        var barC = py(94, s) + hM / 2;
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, cx, barC, barFont,
                   Feed.twoDp(Feed.num(data, "bar")), Graphics.TEXT_JUSTIFY_CENTER);

        var absC = barC + hM / 2 + hX / 2 + pad;
        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, absC, Graphics.FONT_XTINY,
                        "inches - abs " + Feed.twoDp(Feed.num(data, "barabs")), 1,
                        Graphics.TEXT_JUSTIFY_CENTER);

        var trend = Feed.num(data, "trend");
        var rowC = absC + hX + (8 * s).toNumber();
        Draw.arrow(dc, cx - (60 * s).toNumber(), rowC, (28 * s).toNumber(),
                   trend, Palette.trendColor(trend));
        var tw = Feed.num(data, "trendw");
        if (tw == null) { tw = "Steady"; }
        dc.setColor(Palette.trendColor(trend), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx + (22 * s).toNumber(), rowC, Graphics.FONT_XTINY, tw, 2,
                        Graphics.TEXT_JUSTIFY_CENTER);

        var verdictTop = rowC + hX / 2 + (6 * s).toNumber();
        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        var vlines = wrapped(dc, cx, verdictTop, Feed.num(data, "verdict"), s, 3);

        var seg = Feed.num(data, "dutch");
        if (seg == null) { seg = segFromWord(Feed.num(data, "dutchw")); }
        var ladderY = verdictTop + (hX - 2) * vlines + (10 * s).toNumber();
        var w = (224 * s).toNumber();
        Draw.dutchScale(dc, cx - w / 2, ladderY, w, seg,
                        Palette.grid(), Palette.red(), Graphics.FONT_XTINY, false);
        var wordC = ladderY + (14 * s).toNumber() + hX / 2;
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, wordC, Graphics.FONT_XTINY,
                        Draw.ladderWord(seg), 3, Graphics.TEXT_JUSTIFY_CENTER);

        // bare trace: the page title already says what this is
        return traceBox(dc, cx, s, Feed.num(data, "bt"), null, Palette.ink(),
                        wordC + hX / 2 + (8 * s).toNumber());
    }

    hidden function drawWind(dc, cx, s) {
        Draw.rose(dc, cx, py(168, s), (66 * s).toNumber(),
                  Feed.num(data, "rose"), Feed.num(data, "dir"),
                  Palette.grid(), Palette.blue(), Palette.red());

        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var hT = dc.getFontHeight(Graphics.FONT_TINY);
        var pad = (3 * s).toNumber();

        var dirC = py(240, s) + hT / 2;
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, cx, dirC, Graphics.FONT_TINY,
                   Draw.dirName(Feed.num(data, "dir")) + "  "
                   + Feed.whole(Feed.num(data, "wind")) + "  g "
                   + Feed.whole(Feed.num(data, "gust")),
                   Graphics.TEXT_JUSTIFY_CENTER);

        var forceC = dirC + hT / 2 + hX / 2 + pad;
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, forceC, Graphics.FONT_XTINY,
                        "Force " + Feed.whole(Feed.num(data, "bf")) + " - "
                        + strOr(Feed.num(data, "bfw"), ""), 1, Graphics.TEXT_JUSTIFY_CENTER);

        // Short words down here: the circle narrows fast and "max 13 today -
        // SW prevails" lost both its ends to the bezel.
        var maxC = forceC + hX + pad;
        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, maxC, Graphics.FONT_XTINY,
                        "max " + Feed.whole(Feed.num(data, "maxgust")) + " - "
                        + strOr(Feed.num(data, "prev"), "--") + " prevails", 0,
                        Graphics.TEXT_JUSTIFY_CENTER);

        // No header on this one — the page is already called The Wind, and the
        // line above it is using the space a label would want.
        return traceBox(dc, cx, s, Feed.num(data, "gt"), null, Palette.red(),
                        maxC + hX / 2 + (10 * s).toNumber());
    }

    hidden function drawLog(dc, cx, s) {
        var y = py(104, s);
        var step = py(32, s);
        row(dc, s, y, "Temperature", Feed.oneDp(Feed.num(data, "temp")) + "°", Palette.ink());
        row(dc, s, y + step, "Feels like", Feed.whole(Feed.num(data, "feels")) + "°", Palette.red());
        row(dc, s, y + step * 2, "Hum / dew",
            Feed.whole(Feed.num(data, "hum")) + "% / " + Feed.whole(Feed.num(data, "dew")) + "°",
            Palette.ink());
        row(dc, s, y + step * 3, "High / low",
            Feed.whole(Feed.num(data, "hi")) + "° / " + Feed.whole(Feed.num(data, "lo")) + "°",
            Palette.blue());
        row(dc, s, y + step * 4, "Back home",
            Feed.whole(Feed.num(data, "tin")) + "°  " + Feed.whole(Feed.num(data, "hin")) + "%",
            Palette.dim());

        return traceBox(dc, cx, s, Feed.num(data, "tt"), "Temp - 24 h", Palette.ink(), py(296, s));
    }

    hidden function drawAlmanac(dc, cx, s) {
        var y = py(104, s);
        var step = py(32, s);
        row(dc, s, y, "Rain today", Feed.twoDp(Feed.num(data, "rain")) + " in", Palette.blue());
        row(dc, s, y + step, "This month", Feed.twoDp(Feed.num(data, "rainm")) + " in", Palette.blue());
        row(dc, s, y + step * 2, "UV / solar",
            Feed.whole(Feed.num(data, "uv")) + "  " + Feed.whole(Feed.num(data, "sol")) + " w",
            Palette.gold());

        var aqi = Feed.num(data, "aqi");
        var aqiColor = Palette.green();
        if (aqi != null && aqi > 100) { aqiColor = Palette.red(); }
        else if (aqi != null && aqi > 50) { aqiColor = Palette.gold(); }
        row(dc, s, y + step * 3, "Air", Feed.whole(aqi), aqiColor);

        row(dc, s, y + step * 4, "Sun",
            strOr(hhmm(Feed.num(data, "sr")), "--") + " - " + strOr(hhmm(Feed.num(data, "ss")), "--"),
            Palette.gold());

        var fire = Feed.num(data, "fire");
        var alert = Feed.num(data, "alert");
        var banner = (alert != null) ? alert : fire;
        var bottom = py(240, s);
        if (banner != null) {
            dc.setColor((alert != null) ? Palette.red() : Palette.gold(), Graphics.COLOR_TRANSPARENT);
            var hX = dc.getFontHeight(Graphics.FONT_XTINY);
            var n = wrapped(dc, cx, py(288, s), banner, s, 2);
            bottom = py(288, s) + (hX - 2) * n;
        }
        return bottom;
    }

    // The rain over the country round. The tile carries transparency where
    // the sky is dry, so the underlay — the Divide, the station, the towns —
    // reads through it exactly like weather over the Chart page.
    hidden function drawRadar(dc, cx, s) {
        var w = dc.getWidth();
        var h = dc.getHeight();

        // underlay first: a ghost of the chart for the rain to land on
        dc.setColor(Palette.grid(), Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(py(184, s), 0, py(176, s), h);              // the Divide
        drawTown(dc, s, 237, 179, "BOULDER", false);
        drawTown(dc, s, 202, 161, "WARD", true);       // label left: clears Boulder's
        drawTown(dc, s, 203, 207, "ROLLINSVILLE", false);

        var showing = null;
        if (radarFrames.size() > 0) {
            if (radarIdx >= radarFrames.size()) { radarIdx = radarFrames.size() - 1; }
            showing = radarFrames[radarIdx] as Lang.Dictionary;
            var bmp = showing.get(:bmp);
            if (bmp != null) {
                if (dc has :drawScaledBitmap) {
                    dc.drawScaledBitmap(0, 0, w, h, bmp);
                } else {
                    // the tile is requested at 256; centre it without asking
                    // the bitmap anything a BitmapReference might not answer
                    dc.drawBitmap(cx - 128, h / 2 - 128, bmp);
                }
            }
        }

        // the station over everything: this is where you are standing
        dc.setColor(Palette.red(), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(py(204, s), py(192, s), (4 * s).toNumber());

        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, py(40, s), Graphics.FONT_XTINY, "The Radar", 4,
                        Graphics.TEXT_JUSTIFY_CENTER);

        // The sweep line follows the loop: each frame names its own clock
        // time, so you can watch the last hour and a half walk past.
        var line = null;
        if (radarFrames.size() == 0) {
            line = radarFail ? "no radar reachable" : "raising the radar...";
        } else if (showing != null) {
            var t = showing.get(:t);
            if (t != null) {
                line = hhmm((t as Lang.Number) * 1000) + " - rainviewer";
                if (radarBusy) {
                    line = hhmm((t as Lang.Number) * 1000) + " - raising "
                           + radarFrames.size().format("%d") + "/6";
                }
            }
        }
        if (line != null) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, py(348, s), Graphics.FONT_XTINY, line, 0,
                            Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    hidden function drawTown(dc, s, x, y, name, labelLeft) {
        dc.drawCircle(py(x, s), py(y, s), (3 * s).toNumber());
        if (labelLeft) {
            Draw.spacedText(dc, py(x, s) - (8 * s).toNumber(), py(y, s),
                            Graphics.FONT_XTINY, name, 0, Graphics.TEXT_JUSTIFY_RIGHT);
        } else {
            Draw.spacedText(dc, py(x, s) + (8 * s).toNumber(), py(y, s),
                            Graphics.FONT_XTINY, name, 0, Graphics.TEXT_JUSTIFY_LEFT);
        }
    }

    // ---- shared bits ------------------------------------------------------

    // label == null draws the trace bare, for pages with no room for a header.
    // yTop is absolute pixels: pages flow their layout from measured fonts and
    // hand the trace whatever honest space is left. If the flow left no honest
    // space, the trace yields entirely — a clipped graph lies about its data.
    // Returns the bottom edge of whatever was drawn.
    hidden function traceBox(dc, cx, s, series, label as Lang.String?, color, yTop) {
        if (series == null) { return yTop; }
        if (yTop > py(330, s)) { return yTop; }
        var x = cx - (112 * s).toNumber();
        var w = (224 * s).toNumber();
        var h = (32 * s).toNumber();
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var y = yTop;

        if (label != null) { y = y + hX + (4 * s).toNumber(); }

        var bounds = Draw.trace(dc, series, x, y, w, h, color, 2) as Lang.Array<Lang.Number>?;
        Draw.rule(dc, x, x + w, y + h + 2, Palette.grid());

        if (label != null) {
            var labelC = yTop + hX / 2;
            dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, x, labelC, Graphics.FONT_XTINY, label, 1,
                            Graphics.TEXT_JUSTIFY_LEFT);
            if (bounds != null) {
                dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
                Draw.textC(dc, x + w, labelC, Graphics.FONT_XTINY,
                           bounds[0].format("%d") + "-" + bounds[1].format("%d"),
                           Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }
        return y + h + 2;
    }

    // Centred prose broken on whitespace; returns how many lines it set.
    hidden function wrapped(dc, cx, y, text as Lang.String?, s, maxLines) {
        if (text == null) { return 0; }
        var font = Graphics.FONT_XTINY;
        var maxW = (300 * s).toNumber();
        var words = split(text, " ");
        var line = "";
        var lines = [] as Lang.Array<Lang.String>;
        for (var i = 0; i < words.size(); i += 1) {
            var probe = line.equals("") ? words[i] : line + " " + words[i];
            if (dc.getTextWidthInPixels(probe, font) > maxW && !line.equals("")) {
                lines.add(line);
                line = words[i];
                if (lines.size() == maxLines) { break; }
            } else {
                line = probe;
            }
        }
        if (lines.size() < maxLines && !line.equals("")) { lines.add(line); }

        var lh = dc.getFontHeight(font) - 2;
        for (var i = 0; i < lines.size(); i += 1) {
            dc.drawText(cx, y + i * lh, font, lines[i], Graphics.TEXT_JUSTIFY_CENTER);
        }
        return lines.size();
    }

    hidden function split(text as Lang.String, sep as Lang.String) as Lang.Array<Lang.String> {
        var out = [] as Lang.Array<Lang.String>;
        var start = 0;
        var n = text.length();
        for (var i = 0; i < n; i += 1) {
            if (text.substring(i, i + 1).equals(sep)) {
                if (i > start) { out.add(text.substring(start, i)); }
                start = i + 1;
            }
        }
        if (start < n) { out.add(text.substring(start, n)); }
        return out;
    }

    hidden function strOr(v, fallback) {
        if (v == null) { return fallback; }
        return v;
    }

    hidden function segFromWord(word) {
        if (word == null) { return 2; }
        if (word.equals("STORM")) { return 0; }
        if (word.equals("REGEN")) { return 1; }
        if (word.equals("VERANDERLYK")) { return 2; }
        if (word.equals("MOOI WEER")) { return 3; }
        return 4;
    }

    hidden function hhmm(ms) {
        if (ms == null) { return null; }
        var info = Time.Gregorian.info(new Time.Moment(ms / 1000), Time.FORMAT_SHORT);
        return info.hour.format("%d") + ":" + info.min.format("%02d");
    }
}

class PagesDelegate extends WatchUi.BehaviorDelegate {

    hidden var view;

    function initialize(v) {
        WatchUi.BehaviorDelegate.initialize();
        view = v;
    }

    function onNextPage() {
        view.turn(1);
        return true;
    }

    function onPreviousPage() {
        view.turn(-1);
        return true;
    }

    // The middle button asks the station for a fresh reading.
    function onSelect() {
        view.refresh(true);
        return true;
    }
}
