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
        drawFooter(dc, cx, s, d, y);
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
        // The circle is narrow this high up: measure the title against the
        // chord at its own height and tighten the letter-spacing until it
        // fits. Spaced at 3 it lost both ends to the bezel.
        var title = "HORSESHOE STATION";
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var r = dc.getWidth() / 2;
        var dy = r - (sy(30, s) - hX / 2);
        var half = Math.sqrt((r * r - dy * dy).toFloat()).toNumber();
        var room = 2 * half - (10 * s).toNumber();
        var extra = 3;
        while (extra > 0
               && dc.getTextWidthInPixels(title, Graphics.FONT_XTINY)
                  + extra * (title.length() - 1) > room) {
            extra -= 1;
        }
        dc.setColor(Palette.blue(), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, sy(30, s), Graphics.FONT_XTINY,
                        title, extra, Graphics.TEXT_JUSTIFY_CENTER);
        var winter = isWinter();
        Draw.sunArc(dc, s, sunFrac(d), winter ? 58 : 46, 78,
                    Palette.grid(), Palette.gold());
        Draw.ridgeline(dc, s, 82, 1.0, Palette.ink(), winter);
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

        var centre = sy(124, s);
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

        var feelsC = tempC + hM / 2 + hX / 2 + pad;
        var feels = Feed.num(d, "feels");
        if (feels != null) {
            dc.setColor(Palette.red(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, feelsC, Graphics.FONT_XTINY,
                            "feels " + Feed.whole(feels), 1, Graphics.TEXT_JUSTIFY_CENTER);
        }

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

        var bottom = thirdC + hX / 2;
        var feelsBottom = feelsC + hX / 2;
        return (feelsBottom > bottom) ? feelsBottom : bottom;
    }

    // The condition ladder, and the pointer that says which rung we live on.
    // Flows from `top`, returns its bottom edge.
    hidden function drawGlassWord(dc, cx, s, d, top) {
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var seg = Feed.num(d, "dutch");
        if (seg == null) { seg = segFromWord(Feed.num(d, "dutchw")); }

        var ladderY = top + (6 * s).toNumber();
        var w = (216 * s).toNumber();
        Draw.dutchScale(dc, cx - w / 2, ladderY, w, seg,
                        Palette.grid(), Palette.red(), Graphics.FONT_XTINY);

        // the pointer under the scale reaches ladderY + 12
        // One word only. The trend word came off the face: the arrow beside
        // BARO already tells that story, and its sentence lives on Storm
        // Watch. The line it freed is what lets the footer back on the glass.
        var wordC = ladderY + (11 * s).toNumber() + hX / 2;
        dc.setColor(Palette.trendColor(Feed.num(d, "trend")), Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, wordC, Graphics.FONT_XTINY,
                        Draw.ladderWord(seg), 3, Graphics.TEXT_JUSTIFY_CENTER);
        return wordC + hX / 2;
    }

    // A live warning outranks the fire stage, which outranks the season's own
    // line: UV and burn time above treeline in summer, daylight left on the
    // snow in winter. Rain is the fallback when nothing else has a claim.
    hidden function drawFooter(dc, cx, s, d, top) {
        var alert = Feed.num(d, "alert");
        var fire = Feed.num(d, "fire");
        var text = null;
        var color = Palette.dim();

        if (alert != null) {
            text = alert;
            color = Palette.red();
        } else if (fire != null) {
            text = fire;
            color = Palette.gold();
        } else if (isWinter()) {
            var ss = Feed.num(d, "ss");
            var left = (ss != null) ? (ss / 1000 - Time.now().value()) : null;
            if (left != null && left > 0) {
                var hrs = left / 3600;
                var mins = (left % 3600) / 60;
                text = "daylight " + hrs.format("%d") + " h " + mins.format("%02d") + " m left";
                color = Palette.gold();
            }
        } else {
            var uv = Feed.num(d, "uv");
            if (uv != null && uv >= 3) {
                var burn = (uv >= 11) ? 10 : (uv >= 8) ? 15 : (uv >= 6) ? 25 : 45;
                text = "UV " + Feed.whole(uv) + " - burn " + burn.format("%d") + " min";
                color = Palette.gold();
            }
        }
        if (text == null) {
            text = "rain " + Feed.twoDp(Feed.num(d, "rain")) + " in";
            color = Palette.blue();
        }

        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var footerC = top + (6 * s).toNumber() + hX / 2;
        if (footerC + hX / 2 > sy(390, s)) { return; }   // off the glass — yield
        if (text.length() > 30) { text = text.substring(0, 30); }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        Draw.spacedText(dc, cx, footerC, Graphics.FONT_XTINY, text, 1,
                        Graphics.TEXT_JUSTIFY_CENTER);

        // How old the sky is. Not how old the fetch is — the frame renders on
        // its own ten-minute clock, so a fresh download can still be stale air.
        // Suppressed in always-on, where every lit pixel is battery.
        var age = Feed.dataAgeMinutes(d);
        if (!lowPower && age != null && age > 25) {
            dc.setColor(Palette.dim(), Graphics.COLOR_TRANSPARENT);
            Draw.spacedText(dc, cx, footerC + hX + (1 * s).toNumber(), Graphics.FONT_XTINY,
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
