using Toybox.Application;
using Toybox.Graphics;
using Toybox.Lang;
using Toybox.Math;
using Toybox.System;
using Toybox.Time;
using Toybox.WatchUi;

// The station, at wrist scale — mountain edition.
//
//        HORSESHOE STATION
//         .·˙˙☀˙˙·.
//        ▁▂/\▄/\▂▁▂▁          ← the Divide, sun on its true arc
//              10:42
//        THU 30 JUL · 5:58 - 20:17
//        ──────────────────
//    WIND        61°        BARO
//   WSW 11      feels 61    29.94 ↗
//    g 23
//        ─ STORM|…|SETTLED ─
//              FAIR · RISING
//        UV 9 - BURN 15 MIN        ← winter: daylight left
//
// The ridge is the Chart page's Divide; snowcaps November through April.
// Everything above the rule is the watch's own; everything below it came
// from the station on Horseshoe Place.
class HorseshoeFaceView extends WatchUi.WatchFace {

    hidden var lowPower = false;

    function initialize() {
        WatchUi.WatchFace.initialize();
    }

    function onLayout(dc) {
    }

    function onEnterSleep() {
        lowPower = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() {
        lowPower = false;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;

        dc.setColor(Palette.paper(), Palette.paper());
        dc.clear();

        var d = Feed.stored();

        // scale the fixed 416 px design to whatever the device actually is
        var s = h / 416.0;

        // The vertical layout flows: every block measures the real device
        // fonts and hands its bottom edge to the next. Fixed offsets stacked
        // lines on top of each other the first time this met actual hardware.
        drawHeading(dc, cx, s, d);
        var y = drawTime(dc, cx, s);
        y = drawAlmanacLine(dc, cx, s, d, y);

        y = y + (10 * s).toNumber();
        Draw.rule(dc, cx - (150 * s).toNumber(), cx + (150 * s).toNumber(), y, Palette.grid());

        if (d == null) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, y + (44 * s).toNumber(), Graphics.FONT_XTINY,
                            "Awaiting the glass", 2, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        y = drawDeckLog(dc, cx, s, d, y + (10 * s).toNumber());
        y = drawGlassWord(dc, cx, s, d, y);
        drawBottom(dc, cx, s, d, y);
    }

    // vertical position from the 416 px reference design
    hidden function sy(v, s) {
        return (v * s).toNumber();
    }

    // November through April the summits wear snow and the sun rides low —
    // the same months the skis come out.
    hidden function isWinter() {
        var m = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT).month;
        return m >= 11 || m <= 4;
    }

    // Where the sun stands between today's rise and set, 0..1, or null when
    // the feed has no sun times. Night falls outside the range and sunArc
    // simply leaves the traveller off the road.
    hidden function sunFrac(d) {
        var sr = Feed.num(d, "sr");
        var ss = Feed.num(d, "ss");
        if (sr == null || ss == null || ss <= sr) { return null; }
        var now = Time.now().value();
        return (now - sr / 1000).toFloat() / ((ss - sr) / 1000).toFloat();
    }

    hidden function drawHeading(dc, cx, s, d) {
        // No masthead. The ridge is the signature; the name lives on the
        // glance and the app. With the title gone the Divide climbs into the
        // clear air at the top of the glass.
        var winter = isWinter();
        Draw.sunArc(dc, s, sunFrac(d), winter ? 46 : 32, 66,
                    Palette.grid(), Palette.gold());
        Draw.ridgeline(dc, s, 70, 1.0, Palette.ink(), winter);
    }

    hidden function drawTime(dc, cx, s) {
        var clock = System.getClockTime();
        var hour = clock.hour;
        var suffix = "";
        if (!System.getDeviceSettings().is24Hour) {
            suffix = (hour >= 12) ? "PM" : "AM";
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var text = hour.format("%02d") + ":" + clock.min.format("%02d");

        var centre = sy(112, s);
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, cx, centre, Graphics.FONT_NUMBER_HOT, text,
                   Graphics.TEXT_JUSTIFY_CENTER);

        if (!suffix.equals("")) {
            // beside the numerals, wherever they actually end — a fixed
            // offset parked AM on top of the last digit
            var halfW = dc.getTextWidthInPixels(text, Graphics.FONT_NUMBER_HOT) / 2;
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            Draw.textC(dc, cx + halfW + (4 * s).toNumber(), centre + (14 * s).toNumber(),
                       Graphics.FONT_XTINY, suffix, Graphics.TEXT_JUSTIFY_LEFT);
        }
        return centre + dc.getFontHeight(Graphics.FONT_NUMBER_HOT) / 2;
    }

    hidden function drawAlmanacLine(dc, cx, s, d, top) {
        var now = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var line = now.day_of_week.toUpper() + " " + now.day.format("%d") + " " + now.month.toUpper();

        var sr = hhmm(Feed.num(d, "sr"));
        var ss = hhmm(Feed.num(d, "ss"));
        if (sr != null && ss != null) {
            line = line + "  " + sr + " - " + ss;
        }

        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var centre = top + hX / 2 + (2 * s).toNumber();
        dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, centre, Graphics.FONT_XTINY, line, 1,
                        Graphics.TEXT_JUSTIFY_CENTER);
        return centre + hX / 2;
    }

    // Three columns: the wind on the left, the temperature holding the middle,
    // the barometer on the right — the same order the frame reads in. All rows
    // are spaced from measured font heights; returns the block's bottom edge.
    hidden function drawDeckLog(dc, cx, s, d, top) {
        var leftX = cx - (118 * s).toNumber();
        var rightX = cx + (118 * s).toNumber();
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var hT = dc.getFontHeight(Graphics.FONT_TINY);
        var hM = dc.getFontHeight(Graphics.FONT_NUMBER_MEDIUM);
        var pad = (2 * s).toNumber();

        var labelC = top + hX / 2;
        var valueC = labelC + hX / 2 + hT / 2 + pad;
        var thirdC = valueC + hT / 2 + hX / 2 + pad;

        // centre: the number you actually looked down for
        var tempC = top + hM / 2;
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, cx, tempC, Graphics.FONT_NUMBER_MEDIUM,
                   Feed.whole(Feed.num(d, "temp")) + "°", Graphics.TEXT_JUSTIFY_CENTER);

        // No feels-like on the face — it read as clutter under the big number.
        // The Trail Log still carries it for the days it differs enough to care.

        // left: wind
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, leftX, labelC, Graphics.FONT_XTINY, "Wind", 2,
                        Graphics.TEXT_JUSTIFY_CENTER);
        var dirn = Feed.num(d, "dirn");
        if (dirn == null) { dirn = "--"; }
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, leftX, valueC, Graphics.FONT_TINY,
                   dirn + " " + Feed.whole(Feed.num(d, "wind")),
                   Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Palette.red(), Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, leftX, thirdC, Graphics.FONT_XTINY,
                   "g " + Feed.whole(Feed.num(d, "gust")),
                   Graphics.TEXT_JUSTIFY_CENTER);

        // right: the barometer and where it is going
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, rightX, labelC, Graphics.FONT_XTINY, "Baro", 2,
                        Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Palette.ink(), Graphics.COLOR_TRANSPARENT);
        Draw.textC(dc, rightX, valueC, Graphics.FONT_TINY,
                   Feed.twoDp(Feed.num(d, "bar")), Graphics.TEXT_JUSTIFY_CENTER);

        var trend = Feed.num(d, "trend");
        Draw.arrow(dc, rightX, thirdC, (26 * s).toNumber(),
                   trend, Palette.trendColor(trend));

        return thirdC + hX / 2;
    }

    // The condition ladder, and the pointer that says which rung we live on.
    // Flows from `top`, returns its bottom edge.
    hidden function drawGlassWord(dc, cx, s, d, top) {
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var seg = Feed.num(d, "dutch");
        if (seg == null) { seg = segFromWord(Feed.num(d, "dutchw")); }

        // Pointer above the line, word tucked close beneath: the ladder block
        // now spends half the height it used to.
        var ladderY = top + (12 * s).toNumber();
        var w = (216 * s).toNumber();
        Draw.dutchScale(dc, cx - w / 2, ladderY, w, seg,
                        Palette.grid(), Palette.red(), Graphics.FONT_XTINY, true);

        // One word only. The trend word came off the face: the arrow beside
        // BARO already tells that story, and its sentence lives on Storm Watch.
        var wordC = ladderY + (6 * s).toNumber() + hX / 2;
        dc.setColor(Palette.trendColor(Feed.num(d, "trend")), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, wordC, Graphics.FONT_XTINY,
                        Draw.ladderWord(seg), 3, Graphics.TEXT_JUSTIFY_CENTER);
        return wordC + hX / 2;
    }

    // The bottom of the glass: a warning or the fire stage when one stands,
    // otherwise the last 24 hours of temperature as a thin trace — the day's
    // shape at a glance, hi and lo already implied by its ends.
    hidden function drawBottom(dc, cx, s, d, top) {
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var alert = Feed.num(d, "alert");
        var fire = Feed.num(d, "fire");

        if (alert != null || fire != null) {
            var text = (alert != null) ? alert : fire;
            var color = (alert != null) ? Palette.red() : Palette.gold();
            var footerC = top + (6 * s).toNumber() + hX / 2;
            if (footerC + hX / 2 > sy(390, s)) { return; }
            if (text.length() > 30) { text = text.substring(0, 30); }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, footerC, Graphics.FONT_XTINY, text, 1,
                            Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var tt = Feed.num(d, "tt");
        var traceTop = top + (8 * s).toNumber();
        var traceH = sy(384, s) - traceTop;
        if (traceH > (34 * s).toNumber()) { traceH = (34 * s).toNumber(); }
        if (tt != null && traceH >= (14 * s).toNumber()) {
            var tw2 = (200 * s).toNumber();
            Draw.trace(dc, tt, cx - tw2 / 2, traceTop, tw2, traceH, Palette.dim(), 2);
        }

        // Staleness still gets the last word, drawn over the trace's ground.
        var age = Feed.dataAgeMinutes(d);
        if (!lowPower && age != null && age > 25) {
            dc.setColor(Palette.red(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, traceTop + traceH / 2, Graphics.FONT_XTINY,
                            age.format("%d") + " min old", 1, Graphics.TEXT_JUSTIFY_CENTER);
        }
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
        var moment = new Time.Moment(ms / 1000);
        var info = Time.Gregorian.info(moment, Time.FORMAT_SHORT);
        return info.hour.format("%d") + ":" + info.min.format("%02d");
    }
}
