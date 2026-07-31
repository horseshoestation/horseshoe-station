using Toybox.Communications;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.PersistedContent;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// The frame turns its own pages on a ten-minute clock. On the wrist you turn
// them yourself: swipe or press up and down through the Glass, the Wind, the
// Deck Log and the Almanack.
class PagesView extends WatchUi.View {

    static const PAGE_GLASS   = 0;
    static const PAGE_WIND    = 1;
    static const PAGE_LOG     = 2;
    static const PAGE_ALMANAC = 3;
    static const PAGE_COUNT   = 4;

    hidden var page = 0;
    hidden var data = null;
    hidden var fetching = false;
    hidden var failed = false;

    function initialize() {
        WatchUi.View.initialize();
    }

    function onShow() {
        data = Feed.storedFull();
        refresh(false);
    }

    function turn(delta) {
        page = (page + delta + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
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

        drawChrome(dc, cx, s);

        if (data == null) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            var msg = fetching ? "Reading the glass" : (failed ? "No word from the station" : "Awaiting the glass");
            Draw.spacedText(dc, cx, py(200, s), Graphics.FONT_XTINY, msg, 2,
                            Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (page == PAGE_GLASS)        { drawGlass(dc, cx, s); }
        else if (page == PAGE_WIND)    { drawWind(dc, cx, s); }
        else if (page == PAGE_LOG)     { drawLog(dc, cx, s); }
        else                           { drawAlmanac(dc, cx, s); }

        drawFooter(dc, cx, s);
        drawDots(dc, cx, s);
    }

    hidden function py(v, s) { return (v * s).toNumber(); }

    hidden function title() {
        if (page == PAGE_GLASS) { return "Storm Watch"; }
        if (page == PAGE_WIND)  { return "The Wind"; }
        if (page == PAGE_LOG)   { return "Trail Log"; }
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

    hidden function drawFooter(dc, cx, s) {
        var age = Feed.dataAgeMinutes(data);
        var text = "485 Horseshoe Pl";
        if (fetching) {
            text = "reading...";
        } else if (age != null) {
            text = (age < 1) ? "just now" : age.format("%d") + " min old";
        }
        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, py(362, s), Graphics.FONT_XTINY, text, 1,
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
        dc.drawText(right, y - 2, Graphics.FONT_TINY, value, Graphics.TEXT_JUSTIFY_RIGHT);
    }

    // ---- the pages --------------------------------------------------------

    hidden function drawGlass(dc, cx, s) {
        var bar = Feed.num(data, "bar");
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, py(92, s), Graphics.FONT_NUMBER_MEDIUM, Feed.twoDp(bar),
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, py(150, s), Graphics.FONT_XTINY,
                        "inches - abs " + Feed.twoDp(Feed.num(data, "barabs")), 1,
                        Graphics.TEXT_JUSTIFY_CENTER);

        var trend = Feed.num(data, "trend");
        Draw.arrow(dc, cx - (56 * s).toNumber(), py(182, s), (28 * s).toNumber(),
                   trend, Palette.trendColor(trend));
        var tw = Feed.num(data, "trendw");
        if (tw == null) { tw = "Steady"; }
        dc.setColor(Palette.trendColor(trend), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx + (18 * s).toNumber(), py(172, s), Graphics.FONT_XTINY, tw, 2,
                        Graphics.TEXT_JUSTIFY_CENTER);

        wrapped(dc, cx, py(202, s), Feed.num(data, "verdict"), s, 2);

        // The scale and its word sit high enough to clear the trace's header
        // row, which lands at 290.
        var seg = Feed.num(data, "dutch");
        if (seg == null) { seg = segFromWord(Feed.num(data, "dutchw")); }
        var w = (224 * s).toNumber();
        Draw.dutchScale(dc, cx - w / 2, py(250, s), w, seg,
                        Palette.grid(), Palette.red(), Graphics.FONT_XTINY);
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, py(264, s), Graphics.FONT_XTINY,
                        Draw.ladderWord(seg), 3, Graphics.TEXT_JUSTIFY_CENTER);

        traceBox(dc, cx, s, Feed.num(data, "bt"), "Pressure - 24 h", Palette.ink(), 306);
    }

    hidden function drawWind(dc, cx, s) {
        Draw.rose(dc, cx, py(168, s), (66 * s).toNumber(),
                  Feed.num(data, "rose"), Feed.num(data, "dir"),
                  Palette.grid(), Palette.blue(), Palette.red());

        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, py(244, s), Graphics.FONT_TINY,
                    Draw.dirName(Feed.num(data, "dir")) + "  "
                    + Feed.whole(Feed.num(data, "wind")) + "  g "
                    + Feed.whole(Feed.num(data, "gust")),
                    Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, py(276, s), Graphics.FONT_XTINY,
                        "Force " + Feed.whole(Feed.num(data, "bf")) + " - "
                        + strOr(Feed.num(data, "bfw"), ""), 1, Graphics.TEXT_JUSTIFY_CENTER);

        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, py(294, s), Graphics.FONT_XTINY,
                        "max " + Feed.whole(Feed.num(data, "maxgust")) + " today - "
                        + strOr(Feed.num(data, "prev"), "--") + " prevails", 1,
                        Graphics.TEXT_JUSTIFY_CENTER);

        // No header on this one — the page is already called The Wind, and the
        // line above it is using the space a label would want.
        traceBox(dc, cx, s, Feed.num(data, "gt"), null, Palette.red(), 314);
    }

    hidden function drawLog(dc, cx, s) {
        var y = py(104, s);
        var step = py(32, s);
        row(dc, s, y, "Temperature", Feed.oneDp(Feed.num(data, "temp")) + "°", Palette.ink());
        row(dc, s, y + step, "Feels like", Feed.whole(Feed.num(data, "feels")) + "°", Palette.red());
        row(dc, s, y + step * 2, "Humidity",
            Feed.whole(Feed.num(data, "hum")) + "%  dew " + Feed.whole(Feed.num(data, "dew")) + "°",
            Palette.ink());
        row(dc, s, y + step * 3, "High / low",
            Feed.whole(Feed.num(data, "hi")) + "° / " + Feed.whole(Feed.num(data, "lo")) + "°",
            Palette.blue());
        row(dc, s, y + step * 4, "Back home",
            Feed.whole(Feed.num(data, "tin")) + "°  " + Feed.whole(Feed.num(data, "hin")) + "%",
            Palette.dim());

        traceBox(dc, cx, s, Feed.num(data, "tt"), "Temperature - 24 h", Palette.ink(), 306);
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
        if (banner != null) {
            dc.setColor((alert != null) ? Palette.red() : Palette.gold(), Graphics.COLOR_TRANSPARENT);
            wrapped(dc, cx, py(288, s), banner, s, 2);
        }
    }

    // ---- shared bits ------------------------------------------------------

    // label == null draws the trace bare, for pages with no room for a header.
    hidden function traceBox(dc, cx, s, series, label as Lang.String?, color, top) {
        if (series == null) { return; }
        var x = cx - (112 * s).toNumber();
        var w = (224 * s).toNumber();
        var y = py(top, s);
        var h = (40 * s).toNumber();

        var bounds = Draw.trace(dc, series, x, y, w, h, color, 2) as Lang.Array<Lang.Number>?;
        Draw.rule(dc, x, x + w, y + h + 2, Palette.grid());

        if (label != null) {
            dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, x, y - py(16, s), Graphics.FONT_XTINY, label, 1,
                            Graphics.TEXT_JUSTIFY_LEFT);
            if (bounds != null) {
                dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
                dc.drawText(x + w, y - py(16, s), Graphics.FONT_XTINY,
                            bounds[0].format("%d") + "-" + bounds[1].format("%d"),
                            Graphics.TEXT_JUSTIFY_RIGHT);
            }
        }
    }

    // Two lines of centred prose, broken on whitespace.
    hidden function wrapped(dc, cx, y, text as Lang.String?, s, maxLines) {
        if (text == null) { return; }
        var font = Graphics.FONT_XTINY;
        var maxW = (250 * s).toNumber();
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
